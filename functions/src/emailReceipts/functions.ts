import {getFirestore} from "firebase-admin/firestore";
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
  EMAIL_BREVO_API_KEY,
  EMAIL_RECIPIENT_HMAC_KEYRING,
  EMAIL_SENDER_ADDRESS,
  EMAIL_SENDER_NAME,
} from "../email/config";
import {parseRecipientHmacKeyring} from "../email/recipientHash";
import type {RecipientHmacKeyring} from "../email/recipientHash";
import {RECEIPT_SEND_ROLES} from "../whatsapp/functions";
import {brevoEmailReceiptSend} from "./brevo";
import {EMAIL_RECEIPT_UNSUBSCRIBE_URL} from "./config";
import {
  EmailReceiptDeliveryTask,
  EmailReceiptSend,
  executeEmailReceiptDelivery,
  requestManualEmailReceipt,
} from "./deliveries";
import {
  UNSUBSCRIBE_PAGE_POLICY,
  UnsubscribePage,
  applyEmailReceiptUnsubscribe,
  readEmailReceiptUnsubscribeToken,
  renderUnsubscribePage,
} from "./unsubscribe";

/**
 * The keyring, or null where it is missing or unreadable.
 *
 * **Null rather than a throw**, so a deployment without one - every emulator
 * run - records each receipt as not configured instead of retrying it a day.
 */
function receiptKeyring(): RecipientHmacKeyring | null {
  try {
    return parseRecipientHmacKeyring(EMAIL_RECIPIENT_HMAC_KEYRING.value());
  } catch {
    return null;
  }
}

/** Brevo with this deployment's key and sender, or null where either is unset. */
function receiptSend(): EmailReceiptSend | null {
  let apiKey = "";
  let senderAddress = "";
  try {
    apiKey = EMAIL_BREVO_API_KEY.value().trim();
    senderAddress = EMAIL_SENDER_ADDRESS.value().trim();
  } catch {
    return null;
  }
  if (apiKey.length === 0 || !senderAddress.includes("@")) return null;
  return brevoEmailReceiptSend({apiKey, senderAddress});
}

/** Sends one queued email receipt. See `executeEmailReceiptDelivery`. */
export const deliverEmailReceipt = onTaskDispatched<EmailReceiptDeliveryTask>(
  {
    invoker: "private",
    secrets: [EMAIL_BREVO_API_KEY, EMAIL_RECIPIENT_HMAC_KEYRING],
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
    await executeEmailReceiptDelivery(getFirestore(), data, {
      send: receiptSend(),
      keyring: receiptKeyring(),
      senderNameFallback: EMAIL_SENDER_NAME.value(),
      unsubscribeBaseUrl: EMAIL_RECEIPT_UNSUBSCRIBE_URL.value().trim(),
    });
  }
);

interface SendEmailReceiptRequest {
  tenantId?: unknown;
  saleId?: unknown;
  email?: unknown;
  requestId?: unknown;
  customerName?: unknown;
}

/**
 * A cashier asks for one sale's receipt to go to one address.
 *
 * **Queued by the till, so it works with no signal**, exactly as
 * `sendWhatsappReceipt` is: the request ID is what a replay is answered by.
 */
export const sendEmailReceipt = onCall<
  SendEmailReceiptRequest,
  Promise<{deliveryId: string; status: string}>
>(async (request: CallableRequest<SendEmailReceiptRequest>) => {
  const data = requireObject(request.data);
  const tenantId = requireDocumentId(data.tenantId, "tenantId");
  const saleId = requireDocumentId(data.saleId, "saleId");
  const requestId = requireRequestId(data.requestId);
  const email = requireString(data.email, "email", {maxLength: 320});
  const customerName = typeof data.customerName === "string" &&
    data.customerName.trim().length > 0 && data.customerName.length <= 120 ?
    data.customerName.trim() : undefined;
  const db = getFirestore();
  const actor = await requireTenantMember(db, request, tenantId, RECEIPT_SEND_ROLES);
  return runIdempotentFirestoreTransaction(db, {
    actorUid: actor.uid,
    operation: "sendEmailReceipt",
    tenantId,
    requestId,
    input: {saleId, email},
  }, async () => requestManualEmailReceipt(db, {
    tenantId,
    saleId,
    email,
    requestId,
    actorUid: actor.uid,
    customerName,
  }));
});

function page(response: Response, status: number, which: UnsubscribePage, token: string) {
  response
    .status(status)
    .set("Content-Type", "text/html; charset=utf-8")
    .set("Content-Security-Policy", UNSUBSCRIBE_PAGE_POLICY)
    .set("Cache-Control", "no-store")
    .set("X-Robots-Tag", "noindex")
    .send(renderUnsubscribePage(which, token));
}

/**
 * The link at the foot of every email receipt, and the mail client's
 * one-click unsubscribe. See `unsubscribe.ts`.
 *
 * GET asks; POST answers. A one-click POST (`List-Unsubscribe=One-Click`) gets
 * a bare 200, because a mail client shows nothing; the button's POST gets the
 * next page.
 */
export const unsubscribeEmailReceipts = onRequest(
  {secrets: [EMAIL_RECIPIENT_HMAC_KEYRING], timeoutSeconds: 30},
  async (request: Request, response: Response) => {
    const token = typeof request.query.t === "string" ? request.query.t : "";
    const keyring = receiptKeyring();
    const recipient = keyring === null ? null :
      readEmailReceiptUnsubscribeToken(token, keyring);
    if (request.method === "GET" || request.method === "HEAD") {
      page(response, recipient ? 200 : 400, recipient ? "confirm" : "invalid", token);
      return;
    }
    if (request.method !== "POST") {
      response.status(405).set("Allow", "GET, POST").send("Method not allowed");
      return;
    }
    const body = request.body && typeof request.body === "object" ?
      request.body as Record<string, unknown> : {};
    const oneClick = body["List-Unsubscribe"] === "One-Click";
    if (recipient === null) {
      if (oneClick) response.status(400).send("Invalid link");
      else page(response, 400, "invalid", token);
      return;
    }
    const action = body.action === "resume" ? "resume" : "stop";
    try {
      await applyEmailReceiptUnsubscribe(
        getFirestore(),
        recipient,
        oneClick ? "stop" : action,
        oneClick ? "one_click" : "page"
      );
    } catch (error) {
      logger.error("email_receipts.unsubscribe_failed", {error: String(error)});
      response.status(500).send("Try again in a moment.");
      return;
    }
    if (oneClick) {
      response.status(200).send("Unsubscribed");
      return;
    }
    page(response, 200, action === "resume" ? "resumed" : "stopped", token);
  }
);
