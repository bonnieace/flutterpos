import {randomUUID} from "node:crypto";
import {Auth, getAuth, UserRecord} from "firebase-admin/auth";
import {getFunctions} from "firebase-admin/functions";
import {
  FieldValue,
  Firestore,
  getFirestore,
  Timestamp,
} from "firebase-admin/firestore";
import {CallableRequest, onCall} from "firebase-functions/v2/https";
import {onTaskDispatched} from "firebase-functions/v2/tasks";
import {requireAppCheckedPublic, requireAuthenticatedUser} from "../core/authorization";
import {requireObject, requireRequestId} from "../core/validation";
import {BrevoEmailProvider} from "./brevoProvider";
import {
  EmailProvider,
  EmailProviderError,
  PasswordResetIdentity,
  PasswordResetIdentityGateway,
} from "./contracts";
import {
  EMAIL_BREVO_API_KEY,
  EMAIL_RECIPIENT_HMAC_KEYRING,
  EMAIL_SENDER_ADDRESS,
  EMAIL_SENDER_NAME,
  EMAIL_UNAVAILABLE_MESSAGE,
  PASSWORD_RESET_CONTINUE_URL,
  PASSWORD_RESET_TASK_FUNCTION,
} from "./config";
import {
  allRecipientHashes,
  hashRecipient,
  normalizeEmail,
  parseRecipientHmacKeyring,
  RecipientHash,
  RecipientHmacKeyring,
  recipientHashMatches,
  stablePrivateId,
} from "./recipientHash";
import {isEmailEligibleRoot} from "./rootEligibility";

const DELIVERY_LEASE_MILLISECONDS = 5 * 60 * 1000;
const MAXIMUM_DELIVERY_ATTEMPTS = 8;

export interface PasswordResetTask {
  deliveryId: string;
  normalizedEmail: string;
  recipientHash: string;
  recipientHashKeyVersion: string;
}

export interface PasswordResetRequestPreparation {
  response: {accepted: true};
  task?: PasswordResetTask;
  taskId?: string;
}

interface DeliveryAttempt {
  leaseId: string;
  attemptNumber: number;
}

export interface PasswordResetProcessingDependencies {
  identities: PasswordResetIdentityGateway;
  provider: EmailProvider;
  keyring: RecipientHmacKeyring;
  isRootEligible(uid: string): Promise<boolean>;
  isSuppressed(hashes: readonly RecipientHash[]): Promise<boolean>;
  recordSuppressed(
    task: PasswordResetTask,
    identity: PasswordResetIdentity
  ): Promise<void>;
  beginDelivery(
    task: PasswordResetTask,
    identity: PasswordResetIdentity
  ): Promise<DeliveryAttempt | undefined>;
  markSent(
    task: PasswordResetTask,
    attempt: DeliveryAttempt,
    provider: string,
    providerMessageId: string
  ): Promise<void>;
  markFailure(
    task: PasswordResetTask,
    attempt: DeliveryAttempt,
    safeCode: string,
    retryable: boolean
  ): Promise<void>;
}

function authErrorCode(error: unknown): string | undefined {
  return error && typeof error === "object" && "code" in error ?
    String((error as {code?: unknown}).code) : undefined;
}

function taskAlreadyExists(error: unknown): boolean {
  const code = authErrorCode(error);
  return code === "functions/task-already-exists" ||
    code === "already-exists" || code === "6";
}

export function preparePasswordResetRequest(
  input: unknown,
  keyring: RecipientHmacKeyring
): PasswordResetRequestPreparation {
  const data = requireObject(input);
  const requestId = requireRequestId(data.requestId);
  const normalizedEmail = normalizeEmail(data.email);
  if (!normalizedEmail) return {response: {accepted: true}};

  const recipient = hashRecipient(normalizedEmail, keyring);
  const deliveryId = stablePrivateId(
    "password-reset-delivery",
    recipient.keyVersion,
    recipient.recipientHash,
    requestId
  );
  return {
    response: {accepted: true},
    task: {
      deliveryId,
      normalizedEmail,
      recipientHash: recipient.recipientHash,
      recipientHashKeyVersion: recipient.keyVersion,
    },
    taskId: `password-reset-${deliveryId}`,
  };
}

export function validatePasswordResetTask(value: unknown): PasswordResetTask {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("Password reset task is invalid.");
  }
  const data = value as Record<string, unknown>;
  const normalizedEmail = normalizeEmail(data.normalizedEmail);
  if (
    !normalizedEmail ||
    normalizedEmail !== data.normalizedEmail ||
    typeof data.deliveryId !== "string" ||
    !/^[a-f0-9]{64}$/.test(data.deliveryId) ||
    typeof data.recipientHash !== "string" ||
    !/^[A-Za-z0-9_-]{43}$/.test(data.recipientHash) ||
    typeof data.recipientHashKeyVersion !== "string"
  ) {
    throw new Error("Password reset task is invalid.");
  }
  return data as unknown as PasswordResetTask;
}

/** Provider-independent orchestration seam; tests never call Auth, Brevo, or Firestore. */
export async function processPasswordResetTask(
  rawTask: unknown,
  dependencies: PasswordResetProcessingDependencies
): Promise<"ignored" | "suppressed" | "already_final" | "sent" | "permanent_failure"> {
  const task = validatePasswordResetTask(rawTask);
  if (!recipientHashMatches(
    task.normalizedEmail,
    task.recipientHash,
    task.recipientHashKeyVersion,
    dependencies.keyring
  )) return "ignored";

  const identity = await dependencies.identities.findByEmail(task.normalizedEmail);
  const currentEmail = normalizeEmail(identity?.email);
  if (
    !identity ||
    identity.disabled ||
    !currentEmail ||
    currentEmail !== task.normalizedEmail ||
    !recipientHashMatches(
      currentEmail,
      task.recipientHash,
      task.recipientHashKeyVersion,
      dependencies.keyring
    )
  ) return "ignored";
  if (!await dependencies.isRootEligible(identity.uid)) return "ignored";

  const recipientHashes = allRecipientHashes(currentEmail, dependencies.keyring);
  if (await dependencies.isSuppressed(recipientHashes)) {
    await dependencies.recordSuppressed(task, identity);
    return "suppressed";
  }

  const attempt = await dependencies.beginDelivery(task, identity);
  if (!attempt) return "already_final";

  try {
    const actionUrl = await dependencies.identities.createActionLink(currentEmail);
    const result = await dependencies.provider.send({
      deliveryId: task.deliveryId,
      recipient: currentEmail,
      template: "password_reset",
      actionUrl,
    });
    await dependencies.markSent(
      task,
      attempt,
      result.provider,
      result.providerMessageId
    );
    return "sent";
  } catch (error) {
    const safeCode = error instanceof EmailProviderError ?
      error.safeCode : "action_or_delivery_failure";
    const retryable = (error instanceof EmailProviderError ? error.retryable : true) &&
      attempt.attemptNumber < MAXIMUM_DELIVERY_ATTEMPTS;
    await dependencies.markFailure(task, attempt, safeCode, retryable);
    if (retryable) throw new Error("Password reset delivery will be retried.");
    return "permanent_failure";
  }
}

function userIdentity(user: UserRecord): PasswordResetIdentity | undefined {
  const email = normalizeEmail(user.email);
  return email ? {uid: user.uid, email, disabled: user.disabled} : undefined;
}

class FirebasePasswordResetIdentityGateway implements PasswordResetIdentityGateway {
  constructor(
    private readonly auth: Auth,
    private readonly continueUrl: string
  ) {
    if (!/^https:\/\//i.test(continueUrl)) {
      throw new Error("PASSWORD_RESET_CONTINUE_URL must be an HTTPS URL.");
    }
  }

  async findByEmail(normalizedEmail: string): Promise<PasswordResetIdentity | undefined> {
    try {
      return userIdentity(await this.auth.getUserByEmail(normalizedEmail));
    } catch (error) {
      if (authErrorCode(error) === "auth/user-not-found") return undefined;
      throw error;
    }
  }

  async createActionLink(normalizedEmail: string): Promise<string> {
    return this.auth.generatePasswordResetLink(normalizedEmail, {
      url: this.continueUrl,
      handleCodeInApp: false,
    });
  }
}

function retryDelayMilliseconds(attempt: number): number {
  return Math.min(6 * 60 * 60 * 1000, 30_000 * (2 ** Math.min(attempt - 1, 10)));
}

/**
 * The real Firestore and Auth adapters behind the seam above. Exported so an
 * emulator integration test can drive the worker over real infrastructure: the
 * unit tests substitute every one of these, so until they are exported nothing
 * has ever run `generatePasswordResetLink` against a real Auth record, or the
 * lease transactions against a real Firestore.
 */
export function firestorePasswordResetDependencies(
  db: Firestore,
  auth: Auth,
  provider: EmailProvider,
  keyring: RecipientHmacKeyring
): PasswordResetProcessingDependencies {
  const statusRef = (uid: string) => db.collection("email_delivery_status").doc(uid);
  return {
    identities: new FirebasePasswordResetIdentityGateway(
      auth,
      PASSWORD_RESET_CONTINUE_URL.value()
    ),
    provider,
    keyring,
    async isRootEligible(uid) {
      const snapshot = await db.collection("users").doc(uid).get();
      return isEmailEligibleRoot(snapshot.exists ? snapshot.data() : undefined);
    },
    async isSuppressed(hashes) {
      const snapshots = await db.getAll(...hashes.map((hash) =>
        db.collection("email_suppressions").doc(hash.documentId)));
      return snapshots.some((snapshot) => snapshot.exists &&
        snapshot.data()?.status === "active");
    },
    async recordSuppressed(task, identity) {
      const deliveryRef = db.collection("email_deliveries").doc(task.deliveryId);
      await db.runTransaction(async (transaction) => {
        const existing = await transaction.get(deliveryRef);
        if (existing.exists && ["sent", "delivered"].includes(existing.data()?.status)) return;
        transaction.set(deliveryRef, {
          deliveryId: task.deliveryId,
          deliveryType: "password_reset",
          status: "suppressed",
          targetUid: identity.uid,
          recipientHash: task.recipientHash,
          recipientHashKeyVersion: task.recipientHashKeyVersion,
          sendable: false,
          retryable: false,
          attemptCount: existing.data()?.attemptCount ?? 0,
          ...(existing.exists ? {} : {createdAt: FieldValue.serverTimestamp()}),
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
        transaction.set(statusRef(identity.uid), {
          recipientHash: task.recipientHash,
          recipientHashKeyVersion: task.recipientHashKeyVersion,
          availability: "unavailable",
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
      });
    },
    async beginDelivery(task, identity) {
      const deliveryRef = db.collection("email_deliveries").doc(task.deliveryId);
      const now = Timestamp.now();
      return db.runTransaction(async (transaction) => {
        const snapshot = await transaction.get(deliveryRef);
        const current = snapshot.data() ?? {};
        if (snapshot.exists && (
          current.deliveryType !== "password_reset" ||
          current.targetUid !== identity.uid ||
          current.recipientHash !== task.recipientHash ||
          current.recipientHashKeyVersion !== task.recipientHashKeyVersion
        )) throw new Error("Password reset delivery identity mismatch.");
        if ([
          "sent",
          "delivered",
          "suppressed",
          "permanent_failure",
        ].includes(current.status)) return undefined;
        const leaseActive = current.status === "processing" &&
          current.leaseExpiresAt instanceof Timestamp &&
          current.leaseExpiresAt.toMillis() > now.toMillis();
        if (leaseActive) return undefined;
        const previousAttempts = Number.isSafeInteger(current.attemptCount) ?
          current.attemptCount as number : 0;
        const attemptNumber = previousAttempts + 1;
        if (attemptNumber > MAXIMUM_DELIVERY_ATTEMPTS) return undefined;
        const leaseId = randomUUID();
        transaction.set(deliveryRef, {
          deliveryId: task.deliveryId,
          deliveryType: "password_reset",
          status: "processing",
          targetUid: identity.uid,
          recipientHash: task.recipientHash,
          recipientHashKeyVersion: task.recipientHashKeyVersion,
          sendable: true,
          retryable: true,
          attemptCount: attemptNumber,
          leaseId,
          leaseExpiresAt: Timestamp.fromMillis(
            now.toMillis() + DELIVERY_LEASE_MILLISECONDS
          ),
          nextAttemptAt: FieldValue.delete(),
          ...(snapshot.exists ? {} : {createdAt: FieldValue.serverTimestamp()}),
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
        return {leaseId, attemptNumber};
      });
    },
    async markSent(task, attempt, providerName, providerMessageId) {
      const deliveryRef = db.collection("email_deliveries").doc(task.deliveryId);
      await db.runTransaction(async (transaction) => {
        const snapshot = await transaction.get(deliveryRef);
        if (snapshot.data()?.leaseId !== attempt.leaseId) return;
        const targetUid = snapshot.data()?.targetUid;
        transaction.update(deliveryRef, {
          status: "sent",
          provider: providerName,
          providerMessageId,
          retryable: false,
          sentAt: FieldValue.serverTimestamp(),
          leaseId: FieldValue.delete(),
          leaseExpiresAt: FieldValue.delete(),
          nextAttemptAt: FieldValue.delete(),
          lastErrorCode: FieldValue.delete(),
          updatedAt: FieldValue.serverTimestamp(),
        });
        if (typeof targetUid === "string") {
          transaction.set(statusRef(targetUid), {
            recipientHash: task.recipientHash,
            recipientHashKeyVersion: task.recipientHashKeyVersion,
            availability: "available",
            updatedAt: FieldValue.serverTimestamp(),
          }, {merge: true});
        }
      });
    },
    async markFailure(task, attempt, safeCode, retryable) {
      const deliveryRef = db.collection("email_deliveries").doc(task.deliveryId);
      await db.runTransaction(async (transaction) => {
        const snapshot = await transaction.get(deliveryRef);
        if (snapshot.data()?.leaseId !== attempt.leaseId) return;
        const targetUid = snapshot.data()?.targetUid;
        transaction.update(deliveryRef, {
          status: retryable ? "retry_pending" : "permanent_failure",
          retryable,
          lastErrorCode: safeCode,
          ...(retryable ? {
            nextAttemptAt: Timestamp.fromMillis(
              Date.now() + retryDelayMilliseconds(attempt.attemptNumber)
            ),
          } : {nextAttemptAt: FieldValue.delete()}),
          leaseId: FieldValue.delete(),
          leaseExpiresAt: FieldValue.delete(),
          updatedAt: FieldValue.serverTimestamp(),
        });
        if (!retryable && typeof targetUid === "string") {
          transaction.set(statusRef(targetUid), {
            recipientHash: task.recipientHash,
            recipientHashKeyVersion: task.recipientHashKeyVersion,
            availability: "unavailable",
            updatedAt: FieldValue.serverTimestamp(),
          }, {merge: true});
        }
      });
    },
  };
}

async function defaultEnqueue(task: PasswordResetTask, taskId: string): Promise<void> {
  await getFunctions().taskQueue<PasswordResetTask>(PASSWORD_RESET_TASK_FUNCTION).enqueue(
    task,
    {id: taskId, dispatchDeadlineSeconds: 60}
  );
}

export const requestPasswordReset = onCall<unknown, Promise<{accepted: true}>>(
  {
    enforceAppCheck: true,
    secrets: [EMAIL_RECIPIENT_HMAC_KEYRING],
  },
  async (request: CallableRequest<unknown>) => {
    requireAppCheckedPublic(request);
    const keyring = parseRecipientHmacKeyring(EMAIL_RECIPIENT_HMAC_KEYRING.value());
    const prepared = preparePasswordResetRequest(request.data, keyring);
    if (!prepared.task || !prepared.taskId) return prepared.response;
    try {
      await defaultEnqueue(prepared.task, prepared.taskId);
    } catch (error) {
      if (!taskAlreadyExists(error)) throw error;
    }
    return prepared.response;
  }
);

export const deliverPasswordReset = onTaskDispatched<PasswordResetTask>(
  {
    invoker: "private",
    secrets: [EMAIL_RECIPIENT_HMAC_KEYRING, EMAIL_BREVO_API_KEY],
    retryConfig: {
      maxAttempts: MAXIMUM_DELIVERY_ATTEMPTS,
      minBackoffSeconds: 30,
      maxBackoffSeconds: 3600,
      maxDoublings: 6,
    },
    rateLimits: {maxConcurrentDispatches: 10, maxDispatchesPerSecond: 20},
    timeoutSeconds: 60,
  },
  async (request) => {
    const keyring = parseRecipientHmacKeyring(EMAIL_RECIPIENT_HMAC_KEYRING.value());
    const provider = new BrevoEmailProvider({
      apiKey: EMAIL_BREVO_API_KEY.value(),
      senderAddress: EMAIL_SENDER_ADDRESS.value(),
      senderName: EMAIL_SENDER_NAME.value(),
    });
    await processPasswordResetTask(
      request.data,
      firestorePasswordResetDependencies(
        getFirestore(),
        getAuth(),
        provider,
        keyring
      )
    );
  }
);

export const getMyEmailDeliveryStatus = onCall<unknown, Promise<string>>(
  {secrets: [EMAIL_RECIPIENT_HMAC_KEYRING]},
  async (request: CallableRequest<unknown>) => {
    const authContext = requireAuthenticatedUser(request, {allowUnverified: true});
    const authUser = await getAuth().getUser(authContext.uid);
    const currentEmail = normalizeEmail(authUser.email);
    if (!currentEmail) return EMAIL_UNAVAILABLE_MESSAGE;
    const keyring = parseRecipientHmacKeyring(EMAIL_RECIPIENT_HMAC_KEYRING.value());
    const hashes = allRecipientHashes(currentEmail, keyring);
    const db = getFirestore();
    const snapshots = await db.getAll(
      ...hashes.map((hash) => db.collection("email_suppressions").doc(hash.documentId)),
      db.collection("email_delivery_status").doc(authContext.uid),
      db.collection("users").doc(authContext.uid)
    );
    const rootSnapshot = snapshots[snapshots.length - 1];
    if (!isEmailEligibleRoot(
      rootSnapshot.exists ? rootSnapshot.data() : undefined,
      authContext.token.auth_time
    )) return EMAIL_UNAVAILABLE_MESSAGE;
    if (snapshots.slice(0, hashes.length).some((snapshot) =>
      snapshot.exists && snapshot.data()?.status === "active")) {
      return EMAIL_UNAVAILABLE_MESSAGE;
    }
    const status = snapshots[snapshots.length - 2]?.data();
    const statusMatchesCurrentEmail = hashes.some((hash) =>
      hash.keyVersion === status?.recipientHashKeyVersion &&
      hash.recipientHash === status?.recipientHash);
    return statusMatchesCurrentEmail && status?.availability === "unavailable" ?
      EMAIL_UNAVAILABLE_MESSAGE : "available";
  }
);
