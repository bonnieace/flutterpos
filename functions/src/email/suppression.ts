import {getAuth} from "firebase-admin/auth";
import {
  FieldValue,
  getFirestore,
  Timestamp,
} from "firebase-admin/firestore";
import {CallableRequest, HttpsError, onCall} from "firebase-functions/v2/https";
import {requirePlatformAdmin} from "../core/authorization";
import {runIdempotentFirestoreTransaction} from "../core/idempotency";
import {
  optionalString,
  requireObject,
  requireRequestId,
  requireString,
} from "../core/validation";
import {EMAIL_RECIPIENT_HMAC_KEYRING} from "./config";
import {
  allRecipientHashes,
  normalizeEmail,
  parseRecipientHmacKeyring,
  stablePrivateId,
} from "./recipientHash";
import {ProviderReasonClass, SuppressionCategory} from "./reasonMapping";
import {
  assertSuppressionClearAllowed,
  SuppressionForReview,
} from "./suppressionPolicy";

interface ReviewEmailSuppressionRequest {
  email?: unknown;
  action?: unknown;
  reason?: unknown;
  confirmation?: unknown;
  evidenceReference?: unknown;
  requestId?: unknown;
}

export interface RedactedSuppressionRecord {
  category: SuppressionCategory;
  eventDate: string | null;
  status: "active" | "cleared";
  providerReasonClass: ProviderReasonClass;
}

export interface ReviewEmailSuppressionResponse {
  items: RedactedSuppressionRecord[];
  clearedCount: number;
}

interface StoredSuppression {
  category?: unknown;
  status?: unknown;
  providerReasonClass?: unknown;
  lastEventAt?: unknown;
}

const CATEGORIES = new Set<SuppressionCategory>([
  "hard_bounce",
  "invalid_recipient",
  "spam_complaint",
  "permanent_provider_block",
]);
const REASON_CLASSES = new Set<ProviderReasonClass>([
  "none",
  "hard_bounce",
  "invalid_recipient",
  "spam_complaint",
  "permanent_provider_block",
  "temporary_mailbox",
  "temporary_rate_limit",
  "temporary_policy",
  "temporary_provider",
  "unknown_temporary",
]);

function storedForReview(data: StoredSuppression): SuppressionForReview | undefined {
  if (
    !CATEGORIES.has(data.category as SuppressionCategory) ||
    !["active", "cleared"].includes(String(data.status))
  ) return undefined;
  return {
    category: data.category as SuppressionCategory,
    status: data.status as "active" | "cleared",
  };
}

function redact(data: StoredSuppression): RedactedSuppressionRecord | undefined {
  const review = storedForReview(data);
  if (!review) return undefined;
  const providerReasonClass = REASON_CLASSES.has(
    data.providerReasonClass as ProviderReasonClass
  ) ? data.providerReasonClass as ProviderReasonClass : "unknown_temporary";
  return {
    ...review,
    providerReasonClass,
    eventDate: data.lastEventAt instanceof Timestamp ?
      data.lastEventAt.toDate().toISOString() : null,
  };
}

async function uidForEmail(email: string): Promise<string | undefined> {
  try {
    return (await getAuth().getUserByEmail(email)).uid;
  } catch (error) {
    const code = error && typeof error === "object" && "code" in error ?
      String((error as {code?: unknown}).code) : undefined;
    if (code === "auth/user-not-found") return undefined;
    throw error;
  }
}

export const reviewEmailSuppression = onCall<
  ReviewEmailSuppressionRequest,
  Promise<ReviewEmailSuppressionResponse>
>(
  {secrets: [EMAIL_RECIPIENT_HMAC_KEYRING]},
  async (request: CallableRequest<ReviewEmailSuppressionRequest>) => {
    const db = getFirestore();
    const authorization = await requirePlatformAdmin(db, request);
    const data = requireObject(request.data);
    const email = normalizeEmail(data.email);
    if (!email) throw new HttpsError("invalid-argument", "email is invalid.");
    const action = requireString(data.action, "action", {maxLength: 16});
    if (action !== "inspect" && action !== "clear") {
      throw new HttpsError("invalid-argument", "action must be inspect or clear.");
    }
    const reason = requireString(data.reason, "reason", {maxLength: 1000});
    const confirmation = optionalString(data.confirmation, "confirmation", {
      maxLength: 64,
    });
    const evidenceReference = optionalString(
      data.evidenceReference,
      "evidenceReference",
      {maxLength: 256}
    );
    const requestId = requireRequestId(data.requestId);
    const keyring = parseRecipientHmacKeyring(EMAIL_RECIPIENT_HMAC_KEYRING.value());
    const hashes = allRecipientHashes(email, keyring);
    const lookupFingerprint = stablePrivateId(
      "suppression-review",
      ...hashes.map((hash) => `${hash.keyVersion}:${hash.recipientHash}`)
    );
    const targetUid = action === "clear" ? await uidForEmail(email) : undefined;

    return runIdempotentFirestoreTransaction(db, {
      actorUid: authorization.uid,
      operation: "reviewEmailSuppression",
      requestId,
      input: {
        lookupFingerprint,
        action,
        reason,
        confirmation,
        evidenceReference,
      },
    }, async (transaction) => {
      await requirePlatformAdmin(db, request, transaction);
      const references = hashes.map((hash) =>
        db.collection("email_suppressions").doc(hash.documentId));
      const snapshots = await Promise.all(references.map((reference) =>
        transaction.get(reference)));
      const stored = snapshots
        .filter((snapshot) => snapshot.exists)
        .map((snapshot) => snapshot.data() as StoredSuppression);
      const reviewable = stored
        .map(storedForReview)
        .filter((item): item is SuppressionForReview => item !== undefined);
      if (action === "clear") {
        const activeRecordCount = stored.filter((item) => item.status === "active").length;
        const reviewableActiveCount = reviewable.filter((item) =>
          item.status === "active").length;
        if (activeRecordCount !== reviewableActiveCount) {
          throw new HttpsError(
            "failed-precondition",
            "An active suppression record has an unsupported policy shape."
          );
        }
        assertSuppressionClearAllowed(reviewable, confirmation, evidenceReference);
      }

      let clearedCount = 0;
      if (action === "clear") {
        snapshots.forEach((snapshot) => {
          if (snapshot.exists && snapshot.data()?.status === "active") {
            clearedCount += 1;
            transaction.update(snapshot.ref, {
              status: "cleared",
              clearedAt: FieldValue.serverTimestamp(),
              clearedBy: authorization.uid,
              clearReason: reason,
              ...(evidenceReference ? {evidenceReference} : {}),
              updatedAt: FieldValue.serverTimestamp(),
            });
          }
        });
        if (targetUid) {
          const currentHash = hashes[0];
          transaction.set(db.collection("email_delivery_status").doc(targetUid), {
            recipientHash: currentHash.recipientHash,
            recipientHashKeyVersion: currentHash.keyVersion,
            availability: "available",
            updatedAt: FieldValue.serverTimestamp(),
          }, {merge: true});
        }
      }

      transaction.create(db.collection("platform_audit_logs").doc(), {
        eventType: action === "clear" ?
          "email_suppression_cleared" : "email_suppression_inspected",
        actorUid: authorization.uid,
        lookupFingerprint,
        matchingRecordCount: snapshots.filter((snapshot) => snapshot.exists).length,
        clearedCount,
        reason,
        ...(confirmation ? {confirmation} : {}),
        ...(evidenceReference ? {evidenceReference} : {}),
        requestId,
        createdAt: FieldValue.serverTimestamp(),
      });

      return {
        items: stored
          .map(redact)
          .filter((item): item is RedactedSuppressionRecord => item !== undefined),
        clearedCount,
      };
    });
  }
);
