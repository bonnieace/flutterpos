import {createHash} from "node:crypto";
import {FieldValue, Timestamp} from "firebase-admin/firestore";
import type {DocumentReference, Firestore} from "firebase-admin/firestore";
import {getFunctions} from "firebase-admin/functions";
import {HttpsError} from "firebase-functions/v2/https";
import {CUSTOMER_ID_SHAPE} from "../customers/customerId";
import {
  WhatsappFetch,
  WhatsappSendError,
  maskPhone,
  phoneHash,
  sendWhatsappTemplate,
  uploadWhatsappMedia,
} from "./client";
import {WHATSAPP_RECEIPT_TASK_FUNCTION, WhatsappSendConfig} from "./config";
import {readEReceiptSettings} from "./eReceiptSettings";
import type {ReceiptFormat} from "./eReceiptSettings";
import {readReceiptContent} from "./receiptContent";
import type {ReceiptContent} from "./receiptContent";
import {renderReceiptPdf} from "./receiptPdf";
import {
  RECEIPT_PDF_TEMPLATE,
  RECEIPT_SUMMARY_TEMPLATE,
  receiptFilename,
  receiptPdfParameters,
  receiptSummaryParameters,
} from "./templates";

/**
 * Every receipt the server tries to send on WhatsApp, from the moment it is
 * asked for to what Meta says became of it.
 *
 * **One record per receipt, written before anything is sent.**
 * `tenants/{tenantId}/receipt_deliveries/{deliveryId}` is what management sees
 * on the WhatsApp screen, so a receipt that never left - the channel off, a
 * customer who said STOP, a number Meta refused - is a row with a reason
 * rather than a silence.
 *
 * **No phone number in the clear.** The record holds the number masked and as
 * a digest. An automatic receipt looks the number up on the customer when it
 * is sent, so consent withdrawn in between still wins; a manual one travels
 * only inside the task that sends it.
 *
 * **Sent at most once, as far as this side can make it.** A delivery is
 * claimed under a lease before the call to Meta, and a second worker that
 * finds it claimed leaves it alone. A worker that dies after Meta accepted the
 * message and before the record says so can still send it twice when the
 * lease runs out - that window is the call itself, and it is accepted.
 */

export interface ReceiptDeliveryTask {
  tenantId: string;
  deliveryId: string;
  /** A manual send's number, E.164. Absent for an automatic one. */
  phone?: string;
}

export type DeliveryTrigger = "automatic" | "manual";

export type DeliveryStatus =
  | "queued"
  | "sending"
  | "sent"
  | "delivered"
  | "read"
  | "failed"
  | "skipped";

/** How far a delivery has got, so a late webhook never moves one back. */
export const DELIVERY_RANK: Record<DeliveryStatus, number> = {
  queued: 0,
  sending: 1,
  sent: 2,
  delivered: 3,
  read: 4,
  failed: 5,
  skipped: 5,
};

const TERMINAL: ReadonlySet<DeliveryStatus> = new Set<DeliveryStatus>([
  "sent", "delivered", "read", "failed", "skipped",
]);

/** The most receipts one sale may be sent as, by every trigger together. */
export const MAXIMUM_SENDS_PER_SALE = 3;

/** How many times one delivery is tried before it is recorded as failed. */
export const MAXIMUM_SEND_ATTEMPTS = 5;

const LEASE_MILLISECONDS = 5 * 60 * 1000;

const E164 = /^\+[1-9]\d{7,14}$/;

/** A delivery's ID: the same sale, number and request always name one. */
export function receiptDeliveryId(
  tenantId: string,
  saleId: string,
  phone: string,
  requestId: string
): string {
  const digest = createHash("sha256")
    .update(["whatsapp-receipt", tenantId, saleId, phone, requestId].join(" "))
    .digest("hex");
  return `rd_${digest.slice(0, 40)}`;
}

function deliveryRef(db: Firestore, tenantId: string, deliveryId: string): DocumentReference {
  return db.collection("tenants").doc(tenantId)
    .collection("receipt_deliveries").doc(deliveryId);
}

function taskAlreadyExists(error: unknown): boolean {
  const code = error && typeof error === "object" && "code" in error ?
    String((error as {code?: unknown}).code) : undefined;
  return code === "functions/task-already-exists" ||
    code === "already-exists" || code === "6";
}

/** How a send is queued; a test passes one that records instead. */
export type ReceiptEnqueuer = (task: ReceiptDeliveryTask) => Promise<void>;

/** Queues one send; queueing the same delivery twice sends it once. */
export async function enqueueReceiptDelivery(task: ReceiptDeliveryTask): Promise<void> {
  try {
    await getFunctions().taskQueue<ReceiptDeliveryTask>(
      WHATSAPP_RECEIPT_TASK_FUNCTION
    ).enqueue(task, {id: `whatsapp-${task.deliveryId}`, dispatchDeadlineSeconds: 300});
  } catch (error) {
    if (!taskAlreadyExists(error)) throw error;
  }
}

function newDelivery(options: {
  tenantId: string;
  saleId: string;
  phone: string;
  trigger: DeliveryTrigger;
  format: ReceiptFormat;
  customerId?: string;
  customerName?: string;
  requestedBy?: string;
}): Record<string, unknown> {
  return {
    tenantId: options.tenantId,
    saleId: options.saleId,
    receiptNumber: null,
    trigger: options.trigger,
    format: options.format,
    phoneMasked: maskPhone(options.phone),
    phoneHash: phoneHash(options.phone),
    customerId: options.customerId ?? null,
    customerName: options.customerName ?? null,
    requestedBy: options.requestedBy ?? null,
    status: "queued",
    reason: null,
    attempts: 0,
    providerMessageId: null,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };
}

/**
 * Queues the receipt a counted sale sends on its own, where the business asked
 * for that and the customer agreed.
 *
 * **Nothing happens otherwise, and nothing is recorded.** A business sending
 * manually, or a customer who never agreed, is the ordinary case and is not a
 * delivery that was skipped.
 *
 * Safe to call again for the same sale: the delivery's ID is the sale and the
 * number, so a retried task finds the one it already queued.
 */
export async function queueAutomaticReceipt(
  db: Firestore,
  task: {tenantId: string; saleId: string},
  enqueue: ReceiptEnqueuer = enqueueReceiptDelivery
): Promise<string | null> {
  const tenantRef = db.collection("tenants").doc(task.tenantId);
  const [settingsSnapshot, saleSnapshot] = await Promise.all([
    tenantRef.collection("configuration").doc("e_receipts").get(),
    tenantRef.collection("sales").doc(task.saleId).get(),
  ]);
  const settings = readEReceiptSettings(settingsSnapshot.data());
  if (!settings.whatsappEnabled || settings.mode !== "automatic") return null;
  const customerId = saleSnapshot.get("customerId");
  if (typeof customerId !== "string" || !CUSTOMER_ID_SHAPE.test(customerId)) return null;
  const customer = await tenantRef.collection("customers").doc(customerId).get();
  const phone = customer.get("phone");
  if (
    !customer.exists ||
    customer.get("active") === false ||
    customer.get("whatsappOptIn") !== true ||
    typeof phone !== "string" ||
    !E164.test(phone)
  ) {
    return null;
  }
  const deliveryId = receiptDeliveryId(task.tenantId, task.saleId, phone, "automatic");
  const ref = deliveryRef(db, task.tenantId, deliveryId);
  await db.runTransaction(async (transaction) => {
    const existing = await transaction.get(ref);
    if (existing.exists) return;
    transaction.create(ref, newDelivery({
      tenantId: task.tenantId,
      saleId: task.saleId,
      phone,
      trigger: "automatic",
      format: settings.format,
      customerId,
      customerName: typeof customer.get("name") === "string" ? customer.get("name") : undefined,
    }));
  });
  await enqueue({tenantId: task.tenantId, deliveryId});
  return deliveryId;
}

/**
 * Records a receipt a cashier asked to send, and queues it.
 *
 * **The sale need not have arrived yet.** A till that rang the sale up offline
 * and then sent its receipt queues both; the send waits for the sale.
 *
 * **At most [MAXIMUM_SENDS_PER_SALE] receipts per sale**, so a mistyped number
 * can be corrected and a lost message sent again, and a till cannot be used
 * to message anybody it likes.
 */
export async function requestManualReceipt(
  db: Firestore,
  options: {
    tenantId: string;
    saleId: string;
    phone: string;
    requestId: string;
    actorUid: string;
    customerName?: string;
  },
  enqueue: ReceiptEnqueuer = enqueueReceiptDelivery
): Promise<{deliveryId: string; status: DeliveryStatus}> {
  if (!E164.test(options.phone)) {
    throw new HttpsError(
      "invalid-argument",
      "phone must be an international number such as +254712345678."
    );
  }
  const tenantRef = db.collection("tenants").doc(options.tenantId);
  const settings = readEReceiptSettings(
    (await tenantRef.collection("configuration").doc("e_receipts").get()).data()
  );
  if (!settings.whatsappEnabled) {
    throw new HttpsError(
      "failed-precondition",
      "This business does not send receipts on WhatsApp."
    );
  }
  const deliveryId = receiptDeliveryId(
    options.tenantId,
    options.saleId,
    options.phone,
    options.requestId
  );
  const ref = deliveryRef(db, options.tenantId, deliveryId);
  const status = await db.runTransaction(async (transaction): Promise<DeliveryStatus> => {
    const [existing, others] = await Promise.all([
      transaction.get(ref),
      transaction.get(
        tenantRef.collection("receipt_deliveries")
          .where("saleId", "==", options.saleId)
          .limit(MAXIMUM_SENDS_PER_SALE + 1)
      ),
    ]);
    // A replay of this request answers with what it already did.
    if (existing.exists) return existing.get("status") as DeliveryStatus;
    if (others.size >= MAXIMUM_SENDS_PER_SALE) {
      throw new HttpsError(
        "resource-exhausted",
        `This receipt has already been sent ${MAXIMUM_SENDS_PER_SALE} times.`
      );
    }
    transaction.create(ref, newDelivery({
      tenantId: options.tenantId,
      saleId: options.saleId,
      phone: options.phone,
      trigger: "manual",
      format: settings.format,
      customerName: options.customerName,
      requestedBy: options.actorUid,
    }));
    return "queued";
  });
  if (status === "queued") {
    await enqueue({
      tenantId: options.tenantId,
      deliveryId,
      phone: options.phone,
    });
  }
  return {deliveryId, status};
}

/** Thrown while the sale a receipt is for has not reached the server. */
export class WaitingForSale extends Error {
  constructor(readonly saleId: string) {
    super(`Sale ${saleId} has not reached the server yet.`);
  }
}

export type DeliveryOutcome =
  | "sent"
  | "skipped"
  | "failed"
  | "already_handled";

export interface DeliveryDependencies {
  config: WhatsappSendConfig | null;
  fetchImpl?: WhatsappFetch;
  renderPdf?: (content: ReceiptContent) => Promise<Uint8Array>;
  now?: () => Timestamp;
}

async function finish(
  ref: DocumentReference,
  status: "skipped" | "failed",
  reason: string
): Promise<"skipped" | "failed"> {
  await ref.update({
    status,
    reason,
    leaseUntil: FieldValue.delete(),
    updatedAt: FieldValue.serverTimestamp(),
    ...(status === "failed" ? {failedAt: FieldValue.serverTimestamp()} : {}),
  });
  return status;
}

/**
 * Sends one queued receipt.
 *
 * Answers what became of it, or throws to be tried again: [WaitingForSale]
 * while the sale has not arrived, and a retryable [WhatsappSendError] while
 * Meta cannot take it. Everything else - the channel off, the business no
 * longer sending, a customer who withdrew consent or said STOP, a number Meta
 * refuses - is recorded and ends here.
 */
export async function executeReceiptDelivery(
  db: Firestore,
  task: ReceiptDeliveryTask,
  dependencies: DeliveryDependencies
): Promise<DeliveryOutcome> {
  const now = dependencies.now ?? (() => Timestamp.now());
  const ref = deliveryRef(db, task.tenantId, task.deliveryId);
  const claimed = await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (!snapshot.exists) return null;
    const status = snapshot.get("status") as DeliveryStatus;
    if (TERMINAL.has(status)) return null;
    const lease = snapshot.get("leaseUntil");
    if (
      status === "sending" &&
      lease instanceof Timestamp &&
      lease.toMillis() > now().toMillis()
    ) {
      return null;
    }
    transaction.update(ref, {
      status: "sending",
      leaseUntil: Timestamp.fromMillis(now().toMillis() + LEASE_MILLISECONDS),
      attempts: FieldValue.increment(1),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return snapshot.data() ?? {};
  });
  if (claimed === null) return "already_handled";

  const tenantRef = db.collection("tenants").doc(task.tenantId);
  const attempts = (Number.isSafeInteger(claimed.attempts) ? claimed.attempts as number : 0) + 1;
  const config = dependencies.config;
  if (config === null) return finish(ref, "skipped", "not_configured");

  const settings = readEReceiptSettings(
    (await tenantRef.collection("configuration").doc("e_receipts").get()).data()
  );
  if (!settings.whatsappEnabled) return finish(ref, "skipped", "turned_off");

  // The number: carried by a manual send, looked up for an automatic one so
  // consent withdrawn since the sale still wins.
  let phone = typeof task.phone === "string" && E164.test(task.phone) ? task.phone : null;
  if (claimed.trigger === "automatic") {
    const customerId = claimed.customerId;
    const customer = typeof customerId === "string" ?
      await tenantRef.collection("customers").doc(customerId).get() :
      null;
    const stored = customer?.get("phone");
    phone = customer?.exists &&
      customer.get("active") !== false &&
      customer.get("whatsappOptIn") === true &&
      typeof stored === "string" &&
      E164.test(stored) ? stored : null;
    if (phone === null) return finish(ref, "skipped", "no_consent");
  }
  if (phone === null) return finish(ref, "failed", "no_number");
  const suppressed = await db.collection("whatsapp_suppressions").doc(phoneHash(phone)).get();
  if (suppressed.exists) return finish(ref, "skipped", "opted_out");

  const content = await readReceiptContent(db, task.tenantId, String(claimed.saleId));
  if (content === null) {
    await ref.update({
      status: "queued",
      reason: "waiting_for_sale",
      leaseUntil: FieldValue.delete(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    throw new WaitingForSale(String(claimed.saleId));
  }

  const format: ReceiptFormat = claimed.format === "summary" ? "summary" : "pdf";
  try {
    let providerMessageId: string;
    if (format === "pdf") {
      const bytes = await (dependencies.renderPdf ?? renderReceiptPdf)(content);
      const filename = receiptFilename(content);
      const mediaId = await uploadWhatsappMedia(
        config,
        {bytes, mimeType: "application/pdf", filename},
        dependencies.fetchImpl
      );
      ({providerMessageId} = await sendWhatsappTemplate(config, {
        to: phone,
        templateName: RECEIPT_PDF_TEMPLATE,
        languageCode: config.languageCode,
        bodyParameters: receiptPdfParameters(content),
        headerDocument: {mediaId, filename},
      }, dependencies.fetchImpl));
    } else {
      ({providerMessageId} = await sendWhatsappTemplate(config, {
        to: phone,
        templateName: RECEIPT_SUMMARY_TEMPLATE,
        languageCode: config.languageCode,
        bodyParameters: receiptSummaryParameters(content),
      }, dependencies.fetchImpl));
    }
    const month = now().toDate().toISOString().slice(0, 7);
    // Together or not at all: a sent receipt the webhook could not find, or
    // one the usage count missed, would each be a record that disagrees.
    await db.runTransaction(async (transaction) => {
      transaction.update(ref, {
        status: "sent",
        reason: null,
        receiptNumber: content.receiptNumber,
        providerMessageId,
        leaseUntil: FieldValue.delete(),
        sentAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      transaction.set(db.collection("whatsapp_messages").doc(providerMessageId), {
        tenantId: task.tenantId,
        deliveryId: task.deliveryId,
        createdAt: FieldValue.serverTimestamp(),
      });
      // What the business's receipts cost Meta, counted for when it is billed.
      transaction.set(tenantRef.collection("whatsapp_usage").doc(month), {
        month,
        sent: FieldValue.increment(1),
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    });
    return "sent";
  } catch (error) {
    if (error instanceof WhatsappSendError) {
      if (error.retryable && attempts < MAXIMUM_SEND_ATTEMPTS) {
        await ref.update({
          status: "queued",
          reason: "retrying",
          leaseUntil: FieldValue.delete(),
          updatedAt: FieldValue.serverTimestamp(),
        });
        throw error;
      }
      return finish(ref, "failed", error.code === undefined ?
        "refused" : `refused_${error.code}`);
    }
    // Anything else - a PDF that could not be drawn, the database - is ours,
    // and is tried again by the queue's own backoff.
    await ref.update({
      status: "queued",
      reason: "retrying",
      leaseUntil: FieldValue.delete(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    throw error;
  }
}

/**
 * Applies one status Meta reported, never moving a delivery backwards.
 *
 * A message ID UzaPay did not send - carerota's, until it moves to its own
 * account - has no `whatsapp_messages` entry and is acknowledged and dropped.
 */
export async function applyDeliveryStatus(
  db: Firestore,
  update: {providerMessageId: string; status: "sent" | "delivered" | "read" | "failed"; error?: string}
): Promise<boolean> {
  const index = await db.collection("whatsapp_messages").doc(update.providerMessageId).get();
  const tenantId = index.get("tenantId");
  const deliveryId = index.get("deliveryId");
  if (!index.exists || typeof tenantId !== "string" || typeof deliveryId !== "string") {
    return false;
  }
  const ref = deliveryRef(db, tenantId, deliveryId);
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (!snapshot.exists) return;
    const current = snapshot.get("status") as DeliveryStatus;
    if (current === "failed" || current === "skipped") return;
    if (update.status === "failed") {
      // A message already delivered stays delivered: a later failure report
      // takes nothing back off the customer's phone.
      if (DELIVERY_RANK[current] >= DELIVERY_RANK.delivered) return;
    } else if (DELIVERY_RANK[update.status] <= DELIVERY_RANK[current]) {
      // Statuses arrive out of order; `read` then a late `delivered` is still read.
      return;
    }
    transaction.update(ref, {
      status: update.status,
      ...(update.status === "failed" ? {reason: update.error ?? "undelivered"} : {}),
      [`${update.status}At`]: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
  return true;
}
