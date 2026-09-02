import {Auth, getAuth, UserRecord} from "firebase-admin/auth";
import {getFunctions} from "firebase-admin/functions";
import {FieldValue, Firestore, getFirestore} from "firebase-admin/firestore";
import {CallableRequest, HttpsError, onCall} from "firebase-functions/v2/https";
import {onTaskDispatched} from "firebase-functions/v2/tasks";
import {requireAuthenticatedUser} from "../core/authorization";
import {requireObject, requireRequestId} from "../core/validation";
import {BrevoEmailProvider} from "./brevoProvider";
import {EmailProvider, EmailProviderError} from "./contracts";
import {
  ACCOUNT_VERIFICATION_TASK_FUNCTION,
  EMAIL_BREVO_API_KEY,
  EMAIL_RECIPIENT_HMAC_KEYRING,
  EMAIL_SENDER_ADDRESS,
  EMAIL_SENDER_NAME,
  EMAIL_VERIFICATION_CONTINUE_URL,
} from "./config";
import {
  ActionDeliveryAttempt,
  ActionDeliveryIdentity,
  claimActionDelivery,
  completeActionDelivery,
  failActionDelivery,
  MAX_EMAIL_DELIVERY_ATTEMPTS,
  recordActionDeliverySuppressed,
} from "./deliveryState";
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

const RECENT_AUTH_SECONDS = 5 * 60;

export interface AccountVerificationTask {
  deliveryId: string;
  targetUid: string;
  normalizedEmail: string;
  recipientHash: string;
  recipientHashKeyVersion: string;
  requestAuthTime: number;
}

interface VerificationIdentity {
  uid: string;
  email: string;
  disabled: boolean;
  emailVerified: boolean;
}

export interface AccountVerificationDependencies {
  keyring: RecipientHmacKeyring;
  provider: EmailProvider;
  findIdentity(uid: string): Promise<VerificationIdentity | undefined>;
  isRootEligible(uid: string, requestAuthTime: number): Promise<boolean>;
  createActionLink(email: string): Promise<string>;
  isSuppressed(hashes: readonly RecipientHash[]): Promise<boolean>;
  recordSuppressed(task: AccountVerificationTask, identity: VerificationIdentity): Promise<void>;
  begin(
    task: AccountVerificationTask,
    identity: VerificationIdentity
  ): Promise<ActionDeliveryAttempt | undefined>;
  sent(
    task: AccountVerificationTask,
    attempt: ActionDeliveryAttempt,
    provider: string,
    providerMessageId: string
  ): Promise<void>;
  failed(
    task: AccountVerificationTask,
    attempt: ActionDeliveryAttempt,
    safeCode: string,
    retryable: boolean
  ): Promise<void>;
}

export function isRecentAuthTime(
  authTime: unknown,
  nowMilliseconds = Date.now()
): boolean {
  if (typeof authTime !== "number" || !Number.isInteger(authTime) || authTime <= 0) {
    return false;
  }
  const age = Math.floor(nowMilliseconds / 1000) - authTime;
  return age >= 0 && age <= RECENT_AUTH_SECONDS;
}

export function validateAccountVerificationTask(value: unknown): AccountVerificationTask {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("Account verification task is invalid.");
  }
  const data = value as Record<string, unknown>;
  const email = normalizeEmail(data.normalizedEmail);
  if (
    !email || email !== data.normalizedEmail ||
    typeof data.deliveryId !== "string" || !/^[a-f0-9]{64}$/.test(data.deliveryId) ||
    typeof data.targetUid !== "string" || !/^[^/]{1,128}$/.test(data.targetUid) ||
    typeof data.recipientHash !== "string" ||
    !/^[A-Za-z0-9_-]{43}$/.test(data.recipientHash) ||
    typeof data.recipientHashKeyVersion !== "string" ||
    !Number.isSafeInteger(data.requestAuthTime) ||
    (data.requestAuthTime as number) <= 0
  ) throw new Error("Account verification task is invalid.");
  return data as unknown as AccountVerificationTask;
}

export async function processAccountVerificationTask(
  rawTask: unknown,
  dependencies: AccountVerificationDependencies
): Promise<"ignored" | "suppressed" | "already_final" | "sent" | "permanent_failure"> {
  const task = validateAccountVerificationTask(rawTask);
  if (!recipientHashMatches(
    task.normalizedEmail,
    task.recipientHash,
    task.recipientHashKeyVersion,
    dependencies.keyring
  )) return "ignored";
  const identity = await dependencies.findIdentity(task.targetUid);
  const currentEmail = normalizeEmail(identity?.email);
  if (
    !identity || identity.disabled || identity.emailVerified ||
    !currentEmail || currentEmail !== task.normalizedEmail ||
    !recipientHashMatches(
      currentEmail,
      task.recipientHash,
      task.recipientHashKeyVersion,
      dependencies.keyring
    )
  ) return "ignored";
  if (!await dependencies.isRootEligible(task.targetUid, task.requestAuthTime)) {
    return "ignored";
  }
  if (await dependencies.isSuppressed(allRecipientHashes(currentEmail, dependencies.keyring))) {
    await dependencies.recordSuppressed(task, identity);
    return "suppressed";
  }
  const attempt = await dependencies.begin(task, identity);
  if (!attempt) return "already_final";
  try {
    const actionUrl = await dependencies.createActionLink(currentEmail);
    const result = await dependencies.provider.send({
      deliveryId: task.deliveryId,
      recipient: currentEmail,
      template: "account_verification",
      actionUrl,
    });
    await dependencies.sent(
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
      attempt.attemptNumber < MAX_EMAIL_DELIVERY_ATTEMPTS;
    await dependencies.failed(task, attempt, safeCode, retryable);
    if (retryable) throw new Error("Account verification delivery will be retried.");
    return "permanent_failure";
  }
}

function authErrorCode(error: unknown): string | undefined {
  return error && typeof error === "object" && "code" in error ?
    String((error as {code?: unknown}).code) : undefined;
}

function verificationIdentity(user: UserRecord): VerificationIdentity | undefined {
  const email = normalizeEmail(user.email);
  return email ? {
    uid: user.uid,
    email,
    disabled: user.disabled,
    emailVerified: user.emailVerified,
  } : undefined;
}

function deliveryIdentity(task: AccountVerificationTask): ActionDeliveryIdentity {
  return {
    deliveryId: task.deliveryId,
    deliveryType: "account_verification",
    targetUid: task.targetUid,
    recipientHash: task.recipientHash,
    recipientHashKeyVersion: task.recipientHashKeyVersion,
  };
}

function deployedDependencies(
  db: Firestore,
  auth: Auth,
  provider: EmailProvider,
  keyring: RecipientHmacKeyring
): AccountVerificationDependencies {
  const statusRef = (uid: string) => db.collection("email_delivery_status").doc(uid);
  return {
    keyring,
    provider,
    async findIdentity(uid) {
      try {
        return verificationIdentity(await auth.getUser(uid));
      } catch (error) {
        if (authErrorCode(error) === "auth/user-not-found") return undefined;
        throw error;
      }
    },
    async isRootEligible(uid, requestAuthTime) {
      const snapshot = await db.collection("users").doc(uid).get();
      return isEmailEligibleRoot(
        snapshot.exists ? snapshot.data() : undefined,
        requestAuthTime
      );
    },
    async createActionLink(email) {
      const continueUrl = EMAIL_VERIFICATION_CONTINUE_URL.value();
      if (!/^https:\/\//i.test(continueUrl)) {
        throw new Error("EMAIL_VERIFICATION_CONTINUE_URL must be an HTTPS URL.");
      }
      return auth.generateEmailVerificationLink(email, {
        url: continueUrl,
        handleCodeInApp: false,
      });
    },
    async isSuppressed(hashes) {
      const snapshots = await db.getAll(...hashes.map((hash) =>
        db.collection("email_suppressions").doc(hash.documentId)));
      return snapshots.some((snapshot) => snapshot.exists &&
        snapshot.data()?.status === "active");
    },
    async recordSuppressed(task, identity) {
      await recordActionDeliverySuppressed(
        db,
        deliveryIdentity(task),
        {},
        (transaction) => transaction.set(statusRef(identity.uid), {
          recipientHash: task.recipientHash,
          recipientHashKeyVersion: task.recipientHashKeyVersion,
          availability: "unavailable",
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true})
      );
    },
    begin: (task) => claimActionDelivery(db, deliveryIdentity(task)),
    async sent(task, attempt, providerName, messageId) {
      await completeActionDelivery(
        db,
        deliveryIdentity(task),
        attempt,
        providerName,
        messageId,
        (transaction) => transaction.set(statusRef(task.targetUid), {
          recipientHash: task.recipientHash,
          recipientHashKeyVersion: task.recipientHashKeyVersion,
          availability: "available",
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true})
      );
    },
    async failed(task, attempt, safeCode, retryable) {
      await failActionDelivery(
        db,
        deliveryIdentity(task),
        attempt,
        safeCode,
        retryable,
        retryable ? undefined :
          (transaction) => transaction.set(statusRef(task.targetUid), {
            recipientHash: task.recipientHash,
            recipientHashKeyVersion: task.recipientHashKeyVersion,
            availability: "unavailable",
            updatedAt: FieldValue.serverTimestamp(),
          }, {merge: true})
      );
    },
  };
}

async function enqueueVerification(task: AccountVerificationTask): Promise<void> {
  try {
    await getFunctions().taskQueue<AccountVerificationTask>(
      ACCOUNT_VERIFICATION_TASK_FUNCTION
    ).enqueue(task, {
      id: `account-verification-${task.deliveryId}`,
      dispatchDeadlineSeconds: 60,
    });
  } catch (error) {
    const code = authErrorCode(error);
    if (code !== "functions/task-already-exists" &&
      code !== "already-exists" && code !== "6") throw error;
  }
}

/**
 * Hashes the recipient, derives the delivery id, and enqueues one send.
 *
 * **Extracted because three callers now need the same recipe** and none of them
 * may reinvent it: the `deliveryId` is a `stablePrivateId` over the uid, the key
 * version, the recipient hash and the `requestId`, and it is the *only* thing
 * stopping a retried call from sending a second message - the task id derived
 * from it is what Cloud Tasks deduplicates on. A caller that hashed the address
 * slightly differently, or that stirred a timestamp into the id, would get a
 * fresh delivery for every attempt and nothing downstream would notice.
 *
 * [email] must already be normalized: it is the address the link is minted for
 * and the address the hash is taken of, so a caller that passed the raw Auth
 * value would suppress against one string and send to another.
 *
 * Every function that calls this must declare `EMAIL_RECIPIENT_HMAC_KEYRING`
 * among its secrets. There is no way to check that here - the value simply is
 * not there at runtime - so it is stated where it can be read.
 */
export async function enqueueAccountVerificationFor(options: {
  uid: string;
  email: string;
  requestId: string;
  requestAuthTime: number;
}): Promise<void> {
  const keyring = parseRecipientHmacKeyring(EMAIL_RECIPIENT_HMAC_KEYRING.value());
  const recipient = hashRecipient(options.email, keyring);
  const deliveryId = stablePrivateId(
    "account-verification-delivery",
    options.uid,
    recipient.keyVersion,
    recipient.recipientHash,
    options.requestId
  );
  await enqueueVerification({
    deliveryId,
    targetUid: options.uid,
    normalizedEmail: options.email,
    recipientHash: recipient.recipientHash,
    recipientHashKeyVersion: recipient.keyVersion,
    requestAuthTime: options.requestAuthTime,
  });
}

/**
 * The **resend** button, and nothing else.
 *
 * The first message of an account's life is enqueued by `completeSelfSignup`
 * without anybody pressing anything; this is what the person presses when that
 * one did not arrive. Hence the guards it keeps and the helper above does not:
 * `isRecentAuthTime` bounds how long a stolen session can ask for mail, and the
 * token-email comparison refuses a session whose address has moved underneath
 * it.
 */
export const sendAccountVerification = onCall<unknown, Promise<{accepted: true}>>(
  {secrets: [EMAIL_RECIPIENT_HMAC_KEYRING]},
  async (request: CallableRequest<unknown>) => {
    const caller = requireAuthenticatedUser(request, {allowUnverified: true});
    if (!isRecentAuthTime(caller.token.auth_time)) {
      throw new HttpsError("failed-precondition", "A recent sign-in is required.");
    }
    const data = requireObject(request.data);
    const requestId = requireRequestId(data.requestId);
    const user = await getAuth().getUser(caller.uid);
    const current = verificationIdentity(user);
    const tokenEmail = normalizeEmail(caller.token.email);
    if (!current || current.disabled || !tokenEmail || tokenEmail !== current.email) {
      throw new HttpsError("failed-precondition", "A new sign-in is required.");
    }
    const rootSnapshot = await getFirestore().collection("users").doc(caller.uid).get();
    if (!isEmailEligibleRoot(
      rootSnapshot.exists ? rootSnapshot.data() : undefined,
      caller.token.auth_time
    )) {
      throw new HttpsError("permission-denied", "This account is not active.");
    }
    if (current.emailVerified) return {accepted: true};
    await enqueueAccountVerificationFor({
      uid: caller.uid,
      email: current.email,
      requestId,
      requestAuthTime: caller.token.auth_time,
    });
    return {accepted: true};
  }
);

export const deliverAccountVerification = onTaskDispatched<AccountVerificationTask>(
  {
    invoker: "private",
    secrets: [EMAIL_RECIPIENT_HMAC_KEYRING, EMAIL_BREVO_API_KEY],
    retryConfig: {
      maxAttempts: MAX_EMAIL_DELIVERY_ATTEMPTS,
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
    await processAccountVerificationTask(
      request.data,
      deployedDependencies(getFirestore(), getAuth(), provider, keyring)
    );
  }
);
