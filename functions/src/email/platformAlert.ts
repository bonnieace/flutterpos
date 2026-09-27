import {randomUUID} from "node:crypto";
import {Auth, getAuth, UserRecord} from "firebase-admin/auth";
import {getFunctions} from "firebase-admin/functions";
import {
  FieldPath,
  FieldValue,
  Firestore,
  getFirestore,
  QueryDocumentSnapshot,
  Timestamp,
} from "firebase-admin/firestore";
import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {onTaskDispatched} from "firebase-functions/v2/tasks";
import {RootUserRecord} from "../core/model";
import {BrevoEmailProvider} from "./brevoProvider";
import {EmailProvider, EmailProviderError} from "./contracts";
import {
  EMAIL_BREVO_API_KEY,
  EMAIL_RECIPIENT_HMAC_KEYRING,
  EMAIL_SENDER_ADDRESS,
  EMAIL_SENDER_NAME,
  PLATFORM_ALERTS_URL,
  PLATFORM_ALERT_TASK_FUNCTION,
} from "./config";
import {
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
  RecipientHmacKeyring,
  stablePrivateId,
} from "./recipientHash";
import {logAbsorbedFailure} from "../core/absorbedFailure";

const ALERT_LEASE_MILLISECONDS = 10 * 60 * 1000;
const PLATFORM_PAGE_SIZE = 100;
const SUPPORTED_ALERT_TYPES = new Set([
  "tenant_owner_unavailable",
  "no_active_administrator",
  "tenant_reconciliation_quarantined",
]);

export interface PlatformAlertTask {
  alertId: string;
}

export interface RedactedPlatformAlert {
  alertId: string;
  alertType: string;
  severity: "critical";
}

interface ClaimedPlatformAlert extends RedactedPlatformAlert {
  leaseId: string;
  attemptNumber: number;
  cursor?: string;
}

export function redactedPlatformAlert(
  alertId: string,
  value: unknown
): RedactedPlatformAlert | undefined {
  if (!/^[^/]{1,512}$/.test(alertId) ||
    !value || typeof value !== "object" || Array.isArray(value)) return undefined;
  const data = value as Record<string, unknown>;
  if (
    data.severity !== "critical" ||
    typeof data.type !== "string" ||
    !SUPPORTED_ALERT_TYPES.has(data.type)
  ) return undefined;
  return {alertId, alertType: data.type, severity: "critical"};
}

export function isEligiblePlatformNotificationRecipient(
  root: RootUserRecord,
  authUser: Pick<UserRecord, "disabled" | "customClaims" | "email">
): boolean {
  return root.accountType === "platform_admin" &&
    root.globalStatus === "active" &&
    root.identityTransition === undefined &&
    authUser.disabled !== true &&
    authUser.customClaims?.platformRole === "superAdmin" &&
    normalizeEmail(authUser.email) !== undefined;
}

function retryDelayMilliseconds(attempt: number): number {
  return Math.min(6 * 60 * 60 * 1000, 30_000 * (2 ** Math.min(attempt - 1, 10)));
}

async function claimPlatformAlert(
  db: Firestore,
  alertId: string
): Promise<ClaimedPlatformAlert | undefined> {
  const ref = db.collection("platform_alerts").doc(alertId);
  const now = Timestamp.now();
  return db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (!snapshot.exists) return undefined;
    const alert = redactedPlatformAlert(alertId, snapshot.data());
    if (!alert) {
      transaction.update(ref, {
        notificationStatus: "invalid",
        notificationErrorCode: "unsupported_alert_shape",
        updatedAt: FieldValue.serverTimestamp(),
      });
      return undefined;
    }
    const data = snapshot.data() ?? {};
    if (["completed", "failed", "invalid"].includes(data.notificationStatus)) {
      return undefined;
    }
    if (
      data.notificationStatus === "retry_pending" &&
      data.nextNotificationAttemptAt instanceof Timestamp &&
      data.nextNotificationAttemptAt.toMillis() > now.toMillis()
    ) return undefined;
    const leaseActive = data.notificationStatus === "processing" &&
      data.notificationLeaseExpiresAt instanceof Timestamp &&
      data.notificationLeaseExpiresAt.toMillis() > now.toMillis();
    if (leaseActive) return undefined;
    const previousAttempts = Number.isSafeInteger(data.notificationAttemptCount) ?
      data.notificationAttemptCount as number : 0;
    const attemptNumber = previousAttempts + 1;
    if (attemptNumber > MAX_EMAIL_DELIVERY_ATTEMPTS) {
      transaction.update(ref, {
        notificationStatus: "failed",
        notificationErrorCode: "notification_attempts_exhausted",
        notificationLeaseId: FieldValue.delete(),
        notificationLeaseExpiresAt: FieldValue.delete(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      return undefined;
    }
    const resumingExpiredLease = data.notificationStatus === "processing";
    const cursor = resumingExpiredLease && typeof data.notificationCursor === "string" ?
      data.notificationCursor : undefined;
    const leaseId = randomUUID();
    transaction.update(ref, {
      notificationStatus: "processing",
      notificationAttemptCount: attemptNumber,
      notificationLeaseId: leaseId,
      notificationLeaseExpiresAt: Timestamp.fromMillis(
        now.toMillis() + ALERT_LEASE_MILLISECONDS
      ),
      nextNotificationAttemptAt: FieldValue.delete(),
      notificationErrorCode: FieldValue.delete(),
      ...(resumingExpiredLease ? {} : {
        notificationCursor: FieldValue.delete(),
        notificationPassRetryableCount: 0,
      }),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return {...alert, leaseId, attemptNumber, ...(cursor ? {cursor} : {})};
  });
}

function platformDeliveryIdentity(
  alertId: string,
  uid: string,
  recipientHash: string,
  keyVersion: string
): ActionDeliveryIdentity {
  return {
    deliveryId: stablePrivateId("platform-alert-delivery", alertId, uid),
    deliveryType: "platform_alert",
    targetUid: uid,
    recipientHash,
    recipientHashKeyVersion: keyVersion,
  };
}

async function isSuppressed(
  db: Firestore,
  email: string,
  keyring: RecipientHmacKeyring
): Promise<boolean> {
  const hashes = allRecipientHashes(email, keyring);
  const snapshots = await db.getAll(...hashes.map((hash) =>
    db.collection("email_suppressions").doc(hash.documentId)));
  return snapshots.some((snapshot) => snapshot.exists &&
    snapshot.data()?.status === "active");
}

async function sendOperatorPage(
  db: Firestore,
  auth: Auth,
  provider: EmailProvider,
  keyring: RecipientHmacKeyring,
  alert: ClaimedPlatformAlert,
  roots: readonly QueryDocumentSnapshot[]
): Promise<{sent: number; suppressed: number; permanent: number; retryable: number}> {
  const result = {sent: 0, suppressed: 0, permanent: 0, retryable: 0};
  const authResult = await auth.getUsers(roots.map((root) => ({uid: root.id})));
  const authByUid = new Map(authResult.users.map((user) => [user.uid, user]));
  const dashboardUrl = PLATFORM_ALERTS_URL.value();
  if (!/^https:\/\//i.test(dashboardUrl)) {
    throw new Error("PLATFORM_ALERTS_URL must be an HTTPS URL.");
  }

  for (const rootSnapshot of roots) {
    const root = rootSnapshot.data() as RootUserRecord;
    const authUser = authByUid.get(rootSnapshot.id);
    if (!authUser || !isEligiblePlatformNotificationRecipient(root, authUser)) continue;
    const email = normalizeEmail(authUser.email);
    if (!email) continue;
    const recipient = hashRecipient(email, keyring);
    const identity = platformDeliveryIdentity(
      alert.alertId,
      rootSnapshot.id,
      recipient.recipientHash,
      recipient.keyVersion
    );
    const safeFields = {
      platformAlertId: alert.alertId,
      alertType: alert.alertType,
      severity: alert.severity,
    };
    if (await isSuppressed(db, email, keyring)) {
      if (await recordActionDeliverySuppressed(db, identity, safeFields)) {
        result.suppressed += 1;
      }
      continue;
    }
    const attempt = await claimActionDelivery(
      db,
      identity,
      safeFields,
      {allowRecipientRebind: true}
    );
    if (!attempt) continue;
    try {
      const sent = await provider.send({
        deliveryId: identity.deliveryId,
        recipient: email,
        template: "platform_alert",
        actionUrl: dashboardUrl,
        redactedContext: {
          alertType: alert.alertType,
          severity: alert.severity,
        },
      });
      await completeActionDelivery(
        db,
        identity,
        attempt,
        sent.provider,
        sent.providerMessageId
      );
      result.sent += 1;
    } catch (error) {
      const code = error instanceof EmailProviderError ?
        error.safeCode : "operator_notification_failure";
      const retryable = (error instanceof EmailProviderError ? error.retryable : true) &&
        attempt.attemptNumber < MAX_EMAIL_DELIVERY_ATTEMPTS;
      logAbsorbedFailure("email.platform_alert_send_failed", error, {
        deliveryId: identity.deliveryId,
        platformAlertId: alert.alertId,
        safeCode: code,
        retryable,
        attempt: attempt.attemptNumber,
      });
      await failActionDelivery(db, identity, attempt, code, retryable);
      if (retryable) result.retryable += 1;
      else result.permanent += 1;
    }
  }
  return result;
}

async function executePlatformAlertNotification(
  db: Firestore,
  auth: Auth,
  provider: EmailProvider,
  keyring: RecipientHmacKeyring,
  alertId: string
): Promise<void> {
  const alert = await claimPlatformAlert(db, alertId);
  if (!alert) return;
  let cursor = alert.cursor;
  do {
    let query = db.collection("users")
      .where("accountType", "==", "platform_admin")
      .orderBy(FieldPath.documentId())
      .limit(PLATFORM_PAGE_SIZE);
    if (cursor) query = query.startAfter(cursor);
    const page = await query.get();
    if (page.empty) break;
    const pageResult = await sendOperatorPage(
      db,
      auth,
      provider,
      keyring,
      alert,
      page.docs
    );
    cursor = page.docs[page.docs.length - 1].id;
    const ref = db.collection("platform_alerts").doc(alert.alertId);
    await db.runTransaction(async (transaction) => {
      const snapshot = await transaction.get(ref);
      if (snapshot.data()?.notificationLeaseId !== alert.leaseId) {
        throw new Error("Platform alert notification lease changed.");
      }
      transaction.update(ref, {
        notificationCursor: cursor,
        notificationSentCount: FieldValue.increment(pageResult.sent),
        notificationSuppressedCount: FieldValue.increment(pageResult.suppressed),
        notificationPermanentFailureCount: FieldValue.increment(pageResult.permanent),
        notificationPassRetryableCount: FieldValue.increment(pageResult.retryable),
        updatedAt: FieldValue.serverTimestamp(),
      });
    });
    if (page.size < PLATFORM_PAGE_SIZE) break;
  } while (cursor);

  const ref = db.collection("platform_alerts").doc(alert.alertId);
  let requiresRetry = false;
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (snapshot.data()?.notificationLeaseId !== alert.leaseId) return;
    const retryableCount = Number.isSafeInteger(
      snapshot.data()?.notificationPassRetryableCount
    ) ? snapshot.data()?.notificationPassRetryableCount as number : 0;
    if (retryableCount > 0) {
      requiresRetry = true;
      transaction.update(ref, {
        notificationStatus: "retry_pending",
        notificationErrorCode: "recipient_delivery_retry_pending",
        nextNotificationAttemptAt: Timestamp.fromMillis(
          Date.now() + retryDelayMilliseconds(alert.attemptNumber)
        ),
        notificationCursor: FieldValue.delete(),
        notificationPassRetryableCount: FieldValue.delete(),
        notificationLeaseId: FieldValue.delete(),
        notificationLeaseExpiresAt: FieldValue.delete(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      return;
    }
    transaction.update(ref, {
      notificationStatus: "completed",
      notificationCursor: FieldValue.delete(),
      notificationPassRetryableCount: FieldValue.delete(),
      notificationLeaseId: FieldValue.delete(),
      notificationLeaseExpiresAt: FieldValue.delete(),
      nextNotificationAttemptAt: FieldValue.delete(),
      notificationErrorCode: FieldValue.delete(),
      notificationCompletedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
  if (requiresRetry) {
    throw new Error("One or more operator notifications require retry.");
  }
}

function taskAlreadyExists(error: unknown): boolean {
  const code = error && typeof error === "object" && "code" in error ?
    String((error as {code?: unknown}).code) : undefined;
  return code === "functions/task-already-exists" ||
    code === "already-exists" || code === "6";
}

async function enqueuePlatformAlert(
  db: Firestore,
  alertId: string
): Promise<void> {
  const snapshot = await db.collection("platform_alerts").doc(alertId).get();
  const attempt = Number.isSafeInteger(snapshot.data()?.notificationAttemptCount) ?
    snapshot.data()?.notificationAttemptCount as number : 0;
  const taskId = `platform-alert-${stablePrivateId(
    "platform-alert-task",
    alertId,
    String(attempt)
  )}`;
  try {
    await getFunctions().taskQueue<PlatformAlertTask>(
      PLATFORM_ALERT_TASK_FUNCTION
    ).enqueue({alertId}, {id: taskId, dispatchDeadlineSeconds: 60});
  } catch (error) {
    if (!taskAlreadyExists(error)) throw error;
  }
}

export const consumePendingPlatformAlert = onDocumentCreated(
  {document: "platform_alerts/{alertId}", retry: true},
  async (event) => {
    if (!event.data || event.data.data().notificationStatus !== "pending") return;
    await enqueuePlatformAlert(getFirestore(), event.params.alertId);
  }
);

export const deliverPlatformAlertNotification = onTaskDispatched<PlatformAlertTask>(
  {
    invoker: "private",
    secrets: [EMAIL_RECIPIENT_HMAC_KEYRING, EMAIL_BREVO_API_KEY],
    retryConfig: {
      maxAttempts: MAX_EMAIL_DELIVERY_ATTEMPTS,
      minBackoffSeconds: 30,
      maxBackoffSeconds: 3600,
      maxDoublings: 6,
    },
    rateLimits: {maxConcurrentDispatches: 2, maxDispatchesPerSecond: 5},
    timeoutSeconds: 300,
  },
  async (request) => {
    if (!request.data || typeof request.data.alertId !== "string") return;
    const keyring = parseRecipientHmacKeyring(EMAIL_RECIPIENT_HMAC_KEYRING.value());
    const provider = new BrevoEmailProvider({
      apiKey: EMAIL_BREVO_API_KEY.value(),
      senderAddress: EMAIL_SENDER_ADDRESS.value(),
      senderName: EMAIL_SENDER_NAME.value(),
    });
    await executePlatformAlertNotification(
      getFirestore(),
      getAuth(),
      provider,
      keyring,
      request.data.alertId
    );
  }
);

export const retryPlatformAlertNotifications = onSchedule(
  {schedule: "every 5 minutes", timeoutSeconds: 120, maxInstances: 1},
  async () => {
    const db = getFirestore();
    const now = Timestamp.now();
    const [pending, retryPending, processing] = await Promise.all([
      db.collection("platform_alerts")
        .where("notificationStatus", "==", "pending")
        .orderBy(FieldPath.documentId())
        .limit(50)
        .get(),
      db.collection("platform_alerts")
        .where("notificationStatus", "==", "retry_pending")
        .where("nextNotificationAttemptAt", "<=", now)
        .orderBy("nextNotificationAttemptAt", "asc")
        .orderBy(FieldPath.documentId())
        .limit(50)
        .get(),
      db.collection("platform_alerts")
        .where("notificationStatus", "==", "processing")
        .where("notificationLeaseExpiresAt", "<=", now)
        .orderBy("notificationLeaseExpiresAt", "asc")
        .orderBy(FieldPath.documentId())
        .limit(50)
        .get(),
    ]);
    const candidates = [...pending.docs, ...retryPending.docs, ...processing.docs];
    await Promise.all(candidates.map((document) =>
      enqueuePlatformAlert(db, document.id)));
  }
);
