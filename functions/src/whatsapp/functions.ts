import {FieldValue, Timestamp, getFirestore} from "firebase-admin/firestore";
import type {Firestore} from "firebase-admin/firestore";
import {logger} from "firebase-functions/v2";
import {CallableRequest, onCall, onRequest} from "firebase-functions/v2/https";
import type {Request} from "firebase-functions/v2/https";
import type {Response} from "express";
import {onTaskDispatched} from "firebase-functions/v2/tasks";
import {requireTenantMember} from "../core/authorization";
import {runIdempotentFirestoreTransaction} from "../core/idempotency";
import {
  requireDocumentId,
  requireObject,
  requireRequestId,
  requireString,
} from "../core/validation";
import {
  e164FromWhatsapp,
  parseWebhookPayload,
  phoneHash,
  sendWhatsappText,
  verifyWebhookSignature,
} from "./client";
import {
  WHATSAPP_ACCESS_TOKEN,
  WHATSAPP_APP_SECRET,
  WHATSAPP_WEBHOOK_VERIFY_TOKEN,
  whatsappSendConfig,
} from "./config";
import {
  ReceiptDeliveryTask,
  applyDeliveryStatus,
  executeReceiptDelivery,
  requestManualReceipt,
} from "./deliveries";
import {AUTOMATIC_REPLY, STARTED_REPLY, STOPPED_REPLY} from "./templates";

/** Everyone who sells may send a receipt for a sale they can see. */
export const RECEIPT_SEND_ROLES = ["owner", "admin", "manager", "cashier"] as const;

/** Who may ask whether the channel is set up: those who may turn it on. */
export const RECEIPT_STATUS_ROLES = ["owner", "admin", "manager"] as const;

/** Sends one queued receipt. See `executeReceiptDelivery`. */
export const deliverWhatsappReceipt = onTaskDispatched<ReceiptDeliveryTask>(
  {
    invoker: "private",
    secrets: [WHATSAPP_ACCESS_TOKEN],
    retryConfig: {
      // About a day, for a receipt whose sale is still on an offline till.
      maxAttempts: 30,
      minBackoffSeconds: 60,
      maxBackoffSeconds: 3600,
      maxDoublings: 6,
    },
    rateLimits: {maxConcurrentDispatches: 5, maxDispatchesPerSecond: 10},
    timeoutSeconds: 120,
    memory: "512MiB",
  },
  async (request) => {
    const data = request.data;
    if (
      !data ||
      typeof data.tenantId !== "string" ||
      typeof data.deliveryId !== "string"
    ) {
      return;
    }
    await executeReceiptDelivery(getFirestore(), data, {
      config: whatsappSendConfig(),
    });
  }
);

interface SendReceiptRequest {
  tenantId?: unknown;
  saleId?: unknown;
  phone?: unknown;
  requestId?: unknown;
  customerName?: unknown;
}

/**
 * A cashier asks for one sale's receipt to go to one number.
 *
 * **Queued by the till, so it works with no signal**: the request waits in the
 * device's outbox, and the send waits for the sale. The request ID is what a
 * replay is answered by, so a till that sends twice sends one receipt.
 */
export const sendWhatsappReceipt = onCall<
  SendReceiptRequest,
  Promise<{deliveryId: string; status: string}>
>(async (request: CallableRequest<SendReceiptRequest>) => {
  const data = requireObject(request.data);
  const tenantId = requireDocumentId(data.tenantId, "tenantId");
  const saleId = requireDocumentId(data.saleId, "saleId");
  const requestId = requireRequestId(data.requestId);
  const phone = requireString(data.phone, "phone", {maxLength: 16});
  const customerName = typeof data.customerName === "string" &&
    data.customerName.trim().length > 0 && data.customerName.length <= 120 ?
    data.customerName.trim() : undefined;
  const db = getFirestore();
  const actor = await requireTenantMember(db, request, tenantId, RECEIPT_SEND_ROLES);
  return runIdempotentFirestoreTransaction(db, {
    actorUid: actor.uid,
    operation: "sendWhatsappReceipt",
    tenantId,
    requestId,
    input: {saleId, phone},
  }, async () => requestManualReceipt(db, {
    tenantId,
    saleId,
    phone,
    requestId,
    actorUid: actor.uid,
    customerName,
  }));
});

/** Whether this deployment can send at all, for the WhatsApp screen. */
export const getWhatsappReceiptStatus = onCall<
  {tenantId?: unknown},
  Promise<{configured: boolean}>
>({secrets: [WHATSAPP_ACCESS_TOKEN]}, async (request) => {
  const data = requireObject(request.data);
  const tenantId = requireDocumentId(data.tenantId, "tenantId");
  await requireTenantMember(getFirestore(), request, tenantId, RECEIPT_STATUS_ROLES);
  return {configured: whatsappSendConfig() !== null};
});

const STOP_WORDS = new Set(["STOP", "STOP ALL", "UNSUBSCRIBE", "CANCEL", "END", "QUIT"]);
const START_WORDS = new Set(["START", "UNSTOP", "SUBSCRIBE"]);
const AUTOMATIC_REPLY_INTERVAL = 24 * 60 * 60 * 1000;

/**
 * Answers one message somebody sent to the number.
 *
 * STOP suppresses the number for every business's receipts and says so; START
 * lifts it. Anything else gets the automatic reply, at most once a day per
 * number, so a conversation is never answered line by line by a machine.
 */
async function answerInbound(
  db: Firestore,
  message: {from: string; text?: string}
): Promise<void> {
  const phone = e164FromWhatsapp(message.from);
  if (phone === null) return;
  const config = whatsappSendConfig();
  const word = (message.text ?? "").trim().toUpperCase();
  const suppression = db.collection("whatsapp_suppressions").doc(phoneHash(phone));
  if (STOP_WORDS.has(word)) {
    await suppression.set({at: FieldValue.serverTimestamp(), via: "reply"});
    if (config) await sendWhatsappText(config, phone, STOPPED_REPLY);
    return;
  }
  if (START_WORDS.has(word)) {
    await suppression.delete();
    if (config) await sendWhatsappText(config, phone, STARTED_REPLY);
    return;
  }
  const replied = db.collection("whatsapp_auto_replies").doc(phoneHash(phone));
  const due = await db.runTransaction(async (transaction) => {
    const last = (await transaction.get(replied)).get("at");
    if (
      last instanceof Timestamp &&
      Date.now() - last.toMillis() < AUTOMATIC_REPLY_INTERVAL
    ) {
      return false;
    }
    transaction.set(replied, {at: FieldValue.serverTimestamp()});
    return true;
  });
  if (due && config) await sendWhatsappText(config, phone, AUTOMATIC_REPLY);
}

/**
 * Meta's webhook for the shared number.
 *
 * **UzaPay receives this number's events through a per-number override** the
 * developer sets by hand; carerota's own callback is untouched. Until carerota
 * moves to its own account, statuses for its messages arrive here too, find no
 * `whatsapp_messages` entry, and are acknowledged and dropped.
 *
 * **Every POST is answered 200 once its signature checks out**, whatever
 * happens inside: Meta retries a webhook it thinks failed, and a retry storm
 * over one bad status would hold up every other.
 */
export const receiveWhatsappWebhook = onRequest(
  {
    secrets: [WHATSAPP_APP_SECRET, WHATSAPP_WEBHOOK_VERIFY_TOKEN, WHATSAPP_ACCESS_TOKEN],
    timeoutSeconds: 60,
  },
  async (request: Request, response: Response) => {
    if (request.method === "GET") {
      const mode = request.query["hub.mode"];
      const token = request.query["hub.verify_token"];
      const challenge = request.query["hub.challenge"];
      if (
        mode === "subscribe" &&
        typeof token === "string" &&
        token === WHATSAPP_WEBHOOK_VERIFY_TOKEN.value() &&
        typeof challenge === "string"
      ) {
        response.status(200).send(challenge);
        return;
      }
      response.status(403).send("Forbidden");
      return;
    }
    if (request.method !== "POST") {
      response.status(405).send("Method not allowed");
      return;
    }
    const signature = request.get("x-hub-signature-256");
    if (!verifyWebhookSignature(request.rawBody, signature, WHATSAPP_APP_SECRET.value())) {
      response.status(401).send("Invalid signature");
      return;
    }
    const db = getFirestore();
    const {statuses, inbound} = parseWebhookPayload(request.body);
    for (const status of statuses) {
      try {
        await applyDeliveryStatus(db, status);
      } catch (error) {
        logger.error("whatsapp.status_failed", {error: String(error)});
      }
    }
    for (const message of inbound) {
      try {
        await answerInbound(db, message);
      } catch (error) {
        logger.error("whatsapp.inbound_failed", {error: String(error)});
      }
    }
    response.status(200).send("OK");
  }
);

