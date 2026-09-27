import {Auth, getAuth, UserRecord} from "firebase-admin/auth";
import {getFunctions} from "firebase-admin/functions";
import {
  FieldValue,
  Firestore,
  getFirestore,
  Timestamp,
} from "firebase-admin/firestore";
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
import {logAbsorbedFailure} from "../core/absorbedFailure";
import {AUTH_ACTION_LINK_ORIGIN, rehostActionLink} from "../core/actionLink";

/**
 * How long *Send again* waits between presses, and how many it allows a day.
 *
 * **These replace a five-minute recency rule that was in the wrong place.**
 * `isRecentAuthTime` refused this call once the sign-in was over five minutes
 * old, which cost a person mid-signup a full round trip through the sign-in
 * screen - and it was doing that as the *only* brake on the button, because
 * this host mints a fresh `requestId` per press and the Cloud Tasks
 * deduplication that stops a retried *intent* resending does nothing to stop a
 * genuine repeat.
 *
 * What the recency rule was defending is narrow: this call reads the address
 * off the Auth record and refuses a token whose address disagrees, so a stolen
 * session can only ever mail the account's own current inbox. It cannot
 * redirect anything - and `changeSignupEmail`, which *can*, never had a
 * recency rule at all. So the rule punished the legitimate user for a threat it
 * barely reduced.
 *
 * A cooldown plus a daily ceiling bounds the same abuse by what it actually is
 * - volume - and leaves somebody who has been reading the screen for six
 * minutes able to press the button.
 */
const RESEND_COOLDOWN_MILLISECONDS = 60 * 1000;
const RESEND_WINDOW_MILLISECONDS = 24 * 60 * 60 * 1000;
const MAX_RESENDS_PER_WINDOW = 10;

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
    logAbsorbedFailure("email.account_verification_send_failed", error, {
      deliveryId: task.deliveryId,
      targetUid: task.targetUid,
      safeCode,
      retryable,
      attempt: attempt.attemptNumber,
    });
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
      return rehostActionLink(
        await auth.generateEmailVerificationLink(email, {
          url: continueUrl,
          handleCodeInApp: false,
        }),
        AUTH_ACTION_LINK_ORIGIN.value()
      );
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
 * Whether this press may send, given the presses already recorded.
 *
 * **A replay of the same `requestId` is not a second send.** A retried call -
 * the same user intent reaching the server twice, which is exactly what the
 * client does after refreshing a token left behind by an address change - must
 * answer the way the first one did rather than be refused, and must not spend a
 * second slot. That is the same contract `deliveryId` keeps downstream.
 *
 * [events] are the presses inside the day's window, newest first.
 *
 * Pure and exported so the rule can be asserted on its own, away from a
 * transaction.
 */
export function resendThrottleVerdict(options: {
  requestId: string;
  events: ReadonlyArray<{
    requestId: unknown;
    requestedAtMilliseconds: number | undefined;
  }>;
  nowMilliseconds: number;
}): "replay" | "allowed" | "too_soon" | "exhausted" {
  if (options.events.some((event) => event.requestId === options.requestId)) {
    return "replay";
  }
  if (options.events.length >= MAX_RESENDS_PER_WINDOW) return "exhausted";
  const newest = options.events[0]?.requestedAtMilliseconds;
  if (newest === undefined || !Number.isFinite(newest)) return "allowed";
  const age = options.nowMilliseconds - newest;
  // A record stamped in the future is a clock disagreeing with itself, and
  // refusing on one would wedge the button until it caught up.
  if (age < 0) return "allowed";
  return age < RESEND_COOLDOWN_MILLISECONDS ? "too_soon" : "allowed";
}

/**
 * Refuses a press the allowance does not cover, and records the one it does.
 *
 * The two refusals are told apart in `details.reason`, because "wait a minute"
 * and "that is all for today" are different sentences and a client that could
 * not distinguish them would have to guess - which is how this code came to
 * tell people to sign out when no sign-out was needed.
 */
async function spendResendAllowance(uid: string, requestId: string): Promise<void> {
  const db = getFirestore();
  const eventsRef = db
    .collection("users").doc(uid)
    .collection("verification_request_events");
  const now = Timestamp.now();
  const windowStart = Timestamp.fromMillis(
    now.toMillis() - RESEND_WINDOW_MILLISECONDS
  );
  await db.runTransaction(async (transaction) => {
    // One ordered read serves all three questions: the newest press answers the
    // cooldown, the count answers the ceiling, and the ids answer the replay.
    const snapshot = await transaction.get(
      eventsRef
        .where("requestedAt", ">=", windowStart)
        .orderBy("requestedAt", "desc")
        .limit(MAX_RESENDS_PER_WINDOW)
    );
    const events = snapshot.docs.map((doc) => {
      const requestedAt = doc.get("requestedAt");
      return {
        requestId: doc.get("requestId"),
        requestedAtMilliseconds: requestedAt instanceof Timestamp
          ? requestedAt.toMillis()
          : undefined,
      };
    });
    const verdict = resendThrottleVerdict({
      requestId,
      events,
      nowMilliseconds: now.toMillis(),
    });
    if (verdict === "replay") return;
    if (verdict === "too_soon") {
      throw new HttpsError(
        "resource-exhausted",
        "Another verification email was requested moments ago.",
        {reason: "cooldown"}
      );
    }
    if (verdict === "exhausted") {
      throw new HttpsError(
        "resource-exhausted",
        "This account has requested too many verification emails today.",
        {reason: "daily_cap"}
      );
    }
    transaction.create(eventsRef.doc(requestId), {requestId, requestedAt: now});
  });
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
 * the token-email comparison refuses a session whose address has moved
 * underneath it, and [spendResendAllowance] bounds how often the button works.
 *
 * **There is deliberately no recency rule here.** One used to refuse the call
 * once the sign-in was over five minutes old; see the allowance constants for
 * why it was the wrong defence in the wrong place. Nothing replaced its
 * security value because the token-email comparison below already holds it:
 * this call can only ever mail the address the Auth record currently carries.
 */
export const sendAccountVerification = onCall<unknown, Promise<{accepted: true}>>(
  {secrets: [EMAIL_RECIPIENT_HMAC_KEYRING]},
  async (request: CallableRequest<unknown>) => {
    const caller = requireAuthenticatedUser(request, {allowUnverified: true});
    const data = requireObject(request.data);
    const requestId = requireRequestId(data.requestId);
    const user = await getAuth().getUser(caller.uid);
    const current = verificationIdentity(user);
    const tokenEmail = normalizeEmail(caller.token.email);
    if (!current || current.disabled || !tokenEmail) {
      throw new HttpsError("failed-precondition", "A new sign-in is required.");
    }
    // **Not `failed-precondition`, which the client reads as a stale sign-in.**
    // The address moved underneath a token that is otherwise perfectly fresh -
    // `changeSignupEmail` writes Auth and the claim lags by up to an hour - so
    // the remedy is a token refresh, not a re-authentication. Told apart here
    // because the client cannot tell them apart afterwards, and answering
    // "sign out and sign in again" to somebody who signed in a minute ago
    // teaches a ritual that was never needed.
    if (tokenEmail !== current.email) {
      throw new HttpsError(
        "aborted",
        "This session predates an address change."
      );
    }
    const rootSnapshot = await getFirestore().collection("users").doc(caller.uid).get();
    if (!isEmailEligibleRoot(
      rootSnapshot.exists ? rootSnapshot.data() : undefined,
      caller.token.auth_time
    )) {
      throw new HttpsError("permission-denied", "This account is not active.");
    }
    if (current.emailVerified) return {accepted: true};
    await spendResendAllowance(caller.uid, requestId);
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
