import {createHash, timingSafeEqual} from "node:crypto";
import {
  FieldValue,
  getFirestore,
  Timestamp,
} from "firebase-admin/firestore";
import {onRequest, Request} from "firebase-functions/v2/https";
import {EMAIL_BREVO_WEBHOOK_SECRET, EMAIL_RECIPIENT_HMAC_KEYRING} from "./config";
import {
  classifyBrevoEvent,
  DeliveryClassification,
} from "./reasonMapping";
import {
  allRecipientHashes,
  hashRecipient,
  normalizeEmail,
  parseRecipientHmacKeyring,
  RecipientHmacKeyring,
  recipientHashMatches,
  stablePrivateId,
} from "./recipientHash";

export const EMAIL_WEBHOOK_PAYLOAD_SCHEMA_VERSION = 1;

export interface NormalizedEmailWebhookEvent {
  documentId: string;
  providerMessageId: string;
  eventType: string;
  providerTimestampMilliseconds: number;
  recipientHash: string;
  recipientHashKeyVersion: string;
  normalizedReasonCode: string;
  reasonMappingVersion: string;
  payloadSchemaVersion: typeof EMAIL_WEBHOOK_PAYLOAD_SCHEMA_VERSION;
  classification: DeliveryClassification;
}

export interface ProviderEventDecision {
  applyDisposition: boolean;
  updateLatestEvent: boolean;
}

function deliveryStatePrecedence(value: unknown): number {
  if (value === "suppressed") return 4;
  if (value === "permanent_failure") return 3;
  if (value === "delivered") return 2;
  if (value === "temporary_failure") return 1;
  return 0;
}

function dispositionPrecedence(
  value: DeliveryClassification["disposition"]
): number {
  if (value === "permanent_failure") return 3;
  if (value === "success") return 2;
  if (value === "temporary_failure") return 1;
  return 0;
}

/** Makes provider state monotonic while allowing stronger terminal evidence to win. */
export function providerEventDecision(
  currentStatus: unknown,
  currentTimestampMilliseconds: number | undefined,
  incomingDisposition: DeliveryClassification["disposition"],
  incomingTimestampMilliseconds: number
): ProviderEventDecision {
  const currentPrecedence = deliveryStatePrecedence(currentStatus);
  const incomingPrecedence = dispositionPrecedence(incomingDisposition);
  const updateLatestEvent = currentTimestampMilliseconds === undefined ||
    incomingTimestampMilliseconds >= currentTimestampMilliseconds;
  return {
    applyDisposition: incomingPrecedence > currentPrecedence ||
      (incomingPrecedence === currentPrecedence && updateLatestEvent),
    updateLatestEvent,
  };
}

function suppressionPrecedence(value: unknown): number {
  if (value === "spam_complaint") return 4;
  if (value === "hard_bounce") return 3;
  if (value === "invalid_recipient") return 2;
  if (value === "permanent_provider_block") return 1;
  return 0;
}

export function shouldApplySuppressionEvent(
  currentStatus: unknown,
  currentCategory: unknown,
  currentLastEventMilliseconds: number | undefined,
  currentClearedAtMilliseconds: number | undefined,
  incomingCategory: unknown,
  incomingTimestampMilliseconds: number
): boolean {
  if (currentStatus === undefined) return true;
  if (currentStatus === "cleared") {
    return currentClearedAtMilliseconds !== undefined &&
      incomingTimestampMilliseconds > currentClearedAtMilliseconds;
  }
  if (currentStatus !== "active") return false;
  const currentPrecedence = suppressionPrecedence(currentCategory);
  const incomingPrecedence = suppressionPrecedence(incomingCategory);
  return incomingPrecedence > currentPrecedence ||
    (incomingPrecedence === currentPrecedence &&
      (currentLastEventMilliseconds === undefined ||
        incomingTimestampMilliseconds >= currentLastEventMilliseconds));
}

function objectValue(value: unknown): Record<string, unknown> | undefined {
  return value && typeof value === "object" && !Array.isArray(value) ?
    value as Record<string, unknown> : undefined;
}

function providerMessageId(data: Record<string, unknown>): string | undefined {
  const raw = data["message-id"] ?? data.messageId ?? data.id;
  if (typeof raw !== "string") return undefined;
  const normalized = raw.trim().replace(/^<|>$/g, "");
  return /^[A-Za-z0-9@._:+/-]{1,256}$/.test(normalized) ? normalized : undefined;
}

function providerTimestamp(value: unknown, nowMilliseconds: number): number | undefined {
  let milliseconds: number;
  if (typeof value === "number" && Number.isFinite(value)) {
    milliseconds = value < 10_000_000_000 ? value * 1000 : value;
  } else if (typeof value === "string" && value.trim()) {
    const numeric = Number(value);
    if (Number.isFinite(numeric)) {
      milliseconds = numeric < 10_000_000_000 ? numeric * 1000 : numeric;
    } else {
      milliseconds = Date.parse(value);
    }
  } else {
    return undefined;
  }
  // Reject corrupt timestamps and events implausibly far from receipt time.
  const tenYears = 10 * 366 * 24 * 60 * 60 * 1000;
  return Number.isFinite(milliseconds) &&
    milliseconds > 0 &&
    Math.abs(milliseconds - nowMilliseconds) <= tenYears ?
    Math.floor(milliseconds) : undefined;
}

export function normalizeBrevoWebhook(
  value: unknown,
  keyring: RecipientHmacKeyring,
  nowMilliseconds = Date.now()
): NormalizedEmailWebhookEvent | undefined {
  const data = objectValue(value);
  if (!data) return undefined;
  const email = normalizeEmail(data.email);
  const messageId = providerMessageId(data);
  const timestamp = providerTimestamp(
    data.ts ?? data.timestamp ?? data.date,
    nowMilliseconds
  );
  const classification = classifyBrevoEvent(data.event, data.reason);
  if (!email || !messageId || timestamp === undefined || !classification) {
    return undefined;
  }
  const recipient = hashRecipient(email, keyring);
  const documentId = stablePrivateId(
    "brevo-webhook-event",
    messageId,
    classification.eventType,
    String(timestamp),
    recipient.recipientHash
  );
  return {
    documentId,
    providerMessageId: messageId,
    eventType: classification.eventType,
    providerTimestampMilliseconds: timestamp,
    recipientHash: recipient.recipientHash,
    recipientHashKeyVersion: recipient.keyVersion,
    normalizedReasonCode: classification.normalizedReasonCode,
    reasonMappingVersion: classification.mappingVersion,
    payloadSchemaVersion: EMAIL_WEBHOOK_PAYLOAD_SCHEMA_VERSION,
    classification,
  };
}

function privateToken(value: string): Buffer {
  return createHash("sha256").update(value, "utf8").digest();
}

export function authenticateEmailWebhook(
  authorizationHeader: unknown,
  alternateHeader: unknown,
  configuredSecret: string
): boolean {
  if (Buffer.byteLength(configuredSecret, "utf8") < 32) return false;
  const bearer = typeof authorizationHeader === "string" &&
    authorizationHeader.startsWith("Bearer ") ?
    authorizationHeader.slice("Bearer ".length).trim() : undefined;
  const alternate = typeof alternateHeader === "string" ? alternateHeader.trim() : undefined;
  const supplied = bearer || alternate;
  return !!supplied && timingSafeEqual(
    privateToken(supplied),
    privateToken(configuredSecret)
  );
}

function requestHeader(request: Request, name: string): string | undefined {
  const value = request.headers[name];
  return Array.isArray(value) ? value[0] : value;
}

export const receiveBrevoEmailWebhook = onRequest(
  {
    cors: false,
    secrets: [EMAIL_BREVO_WEBHOOK_SECRET, EMAIL_RECIPIENT_HMAC_KEYRING],
    timeoutSeconds: 30,
  },
  async (request, response) => {
    if (request.method !== "POST") {
      response.status(405).send("Method not allowed.");
      return;
    }
    if (!authenticateEmailWebhook(
      requestHeader(request, "authorization"),
      requestHeader(request, "x-brevo-webhook-secret"),
      EMAIL_BREVO_WEBHOOK_SECRET.value()
    )) {
      response.status(401).send("Unauthorized.");
      return;
    }
    const keyring = parseRecipientHmacKeyring(EMAIL_RECIPIENT_HMAC_KEYRING.value());
    const event = normalizeBrevoWebhook(request.body, keyring);
    if (!event) {
      // The raw body is deliberately neither logged nor retained.
      response.status(400).send("Invalid event.");
      return;
    }

    const db = getFirestore();
    const normalizedRecipient = normalizeEmail(request.body?.email);
    if (!normalizedRecipient) {
      response.status(400).send("Invalid event.");
      return;
    }
    const deliveryQuery = await db.collection("email_deliveries")
      .where("providerMessageId", "==", event.providerMessageId)
      .limit(3)
      .get();
    const matchingDelivery = deliveryQuery.docs.find((document) => {
      const data = document.data();
      return recipientHashMatches(
        normalizedRecipient,
        data.recipientHash,
        data.recipientHashKeyVersion,
        keyring
      );
    });
    const eventRef = db.collection("email_webhook_events").doc(event.documentId);
    const suppressionHashes = allRecipientHashes(normalizedRecipient, keyring);
    const suppressionRefs = suppressionHashes.map((hash) =>
      db.collection("email_suppressions").doc(hash.documentId));
    const suppressionRef = db.collection("email_suppressions").doc(
      hashRecipient(normalizedRecipient, keyring).documentId
    );

    await db.runTransaction(async (transaction) => {
      const eventSnapshot = await transaction.get(eventRef);
      if (eventSnapshot.exists) return;
      const deliverySnapshot = matchingDelivery ?
        await transaction.get(matchingDelivery.ref) : undefined;
      const suppressionSnapshots = await Promise.all(suppressionRefs.map((reference) =>
        transaction.get(reference)));
      const providerEventAt = Timestamp.fromMillis(
        event.providerTimestampMilliseconds
      );

      transaction.create(eventRef, {
        providerMessageId: event.providerMessageId,
        eventType: event.eventType,
        providerTimestamp: providerEventAt,
        recipientHash: event.recipientHash,
        recipientHashKeyVersion: event.recipientHashKeyVersion,
        normalizedReasonCode: event.normalizedReasonCode,
        reasonMappingVersion: event.reasonMappingVersion,
        processedAt: FieldValue.serverTimestamp(),
        payloadSchemaVersion: event.payloadSchemaVersion,
      });

      const activeSuppressions = suppressionSnapshots.filter((snapshot) =>
        snapshot.exists && snapshot.data()?.status === "active");
      const clearedSuppressions = suppressionSnapshots.filter((snapshot) =>
        snapshot.exists && snapshot.data()?.status === "cleared");
      const strongestActive = activeSuppressions.sort((left, right) =>
        suppressionPrecedence(right.data()?.category) -
        suppressionPrecedence(left.data()?.category))[0];
      const latestTimestamp = (
        snapshots: typeof suppressionSnapshots,
        field: string
      ): number | undefined => snapshots.reduce<number | undefined>((latest, snapshot) => {
        const timestamp = snapshot.get(field);
        if (!(timestamp instanceof Timestamp)) return latest;
        return latest === undefined ? timestamp.toMillis() :
          Math.max(latest, timestamp.toMillis());
      }, undefined);
      const aggregateSuppressionStatus = strongestActive ? "active" :
        clearedSuppressions.length > 0 ? "cleared" : undefined;
      const aggregateSuppressionCategory = strongestActive?.data()?.category;
      const aggregateSuppressionLastEvent = latestTimestamp(activeSuppressions, "lastEventAt");
      const aggregateSuppressionClearedAt = latestTimestamp(
        clearedSuppressions,
        "clearedAt"
      );
      const suppressionApplies = !!event.classification.suppressionCategory &&
        shouldApplySuppressionEvent(
          aggregateSuppressionStatus,
          aggregateSuppressionCategory,
          aggregateSuppressionLastEvent,
          aggregateSuppressionClearedAt,
          event.classification.suppressionCategory,
          event.providerTimestampMilliseconds
        );

      const targetUid = deliverySnapshot?.data()?.targetUid;
      let appliedDisposition = false;
      if (deliverySnapshot?.exists) {
        const disposition = event.classification.disposition;
        const existingProviderTimestamp = deliverySnapshot.get("lastProviderEventAt");
        const decision = providerEventDecision(
          strongestActive && disposition !== "permanent_failure" ?
            "suppressed" : deliverySnapshot.get("status"),
          existingProviderTimestamp instanceof Timestamp ?
            existingProviderTimestamp.toMillis() : undefined,
          disposition,
          event.providerTimestampMilliseconds
        );
        const deliveryUpdate: Record<string, unknown> = {
          updatedAt: FieldValue.serverTimestamp(),
        };
        if (decision.updateLatestEvent) {
          deliveryUpdate.lastProviderEventType = event.eventType;
          deliveryUpdate.lastProviderEventAt = providerEventAt;
        }
        if (decision.applyDisposition && disposition === "success") {
          deliveryUpdate.status = "delivered";
          deliveryUpdate.retryable = false;
          deliveryUpdate.deliveredAt = providerEventAt;
          appliedDisposition = true;
        } else if (decision.applyDisposition && disposition === "permanent_failure") {
          deliveryUpdate.status = "permanent_failure";
          deliveryUpdate.retryable = false;
          deliveryUpdate.lastErrorCode = event.normalizedReasonCode;
          appliedDisposition = true;
        } else if (decision.applyDisposition && disposition === "temporary_failure") {
          deliveryUpdate.status = "temporary_failure";
          deliveryUpdate.retryable = true;
          deliveryUpdate.retryMode = "new_request_required";
          deliveryUpdate.lastErrorCode = event.normalizedReasonCode;
          appliedDisposition = true;
        }
        if (decision.updateLatestEvent || appliedDisposition) {
          transaction.update(deliverySnapshot.ref, deliveryUpdate);
        }
      }

      if (suppressionApplies && event.classification.suppressionCategory) {
        const currentSuppressionSnapshot = suppressionSnapshots.find((snapshot) =>
          snapshot.ref.path === suppressionRef.path);
        transaction.set(suppressionRef, {
          recipientHash: event.recipientHash,
          recipientHashKeyVersion: event.recipientHashKeyVersion,
          status: "active",
          category: event.classification.suppressionCategory,
          providerReasonClass: event.classification.reasonClass,
          normalizedReasonCode: event.normalizedReasonCode,
          reasonMappingVersion: event.reasonMappingVersion,
          providerMessageId: event.providerMessageId,
          ...(typeof targetUid === "string" ? {targetUid} : {}),
          ...(currentSuppressionSnapshot?.exists ? {} : {
            firstEventAt: providerEventAt,
            createdAt: FieldValue.serverTimestamp(),
          }),
          lastEventAt: providerEventAt,
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
      }

      if (typeof targetUid === "string" && (
        suppressionApplies || strongestActive || appliedDisposition
      )) {
        const available = !suppressionApplies && !strongestActive &&
          event.classification.disposition === "success";
        transaction.set(db.collection("email_delivery_status").doc(targetUid), {
          recipientHash: event.recipientHash,
          recipientHashKeyVersion: event.recipientHashKeyVersion,
          availability: available ? "available" : "unavailable",
          updatedAt: FieldValue.serverTimestamp(),
        }, {merge: true});
      }
    });

    response.status(204).send();
  }
);
