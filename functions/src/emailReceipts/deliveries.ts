import {createHash} from "node:crypto";
import {FieldValue, Timestamp} from "firebase-admin/firestore";
import type {DocumentReference, DocumentSnapshot, Firestore} from "firebase-admin/firestore";
import {getFunctions} from "firebase-admin/functions";
import {HttpsError} from "firebase-functions/v2/https";
import {logAbsorbedFailure} from "../core/absorbedFailure";
import {CUSTOMER_ID_SHAPE} from "../customers/customerId";
import {EmailProviderError} from "../email/contracts";
import {allRecipientHashes, hashRecipient, normalizeEmail} from "../email/recipientHash";
import type {RecipientHmacKeyring} from "../email/recipientHash";
import {readReceiptContent} from "../whatsapp/receiptContent";
import type {ReceiptContent} from "../whatsapp/receiptContent";
import {renderReceiptPdf} from "../whatsapp/receiptPdf";
import {receiptFilename} from "../whatsapp/templates";
import {EMAIL_RECEIPT_TASK_FUNCTION} from "./config";
import {readEmailReceiptSettings} from "./emailReceiptSettings";
import {emailReceiptEmail, emailReceiptSenderName} from "./template";
import {EMAIL_RECEIPT_SUPPRESSIONS, emailReceiptUnsubscribeUrl} from "./unsubscribe";

/**
 * Every receipt the server tries to send by email, from the moment it is asked
 * for to what Brevo says became of it.
 *
 * **WhatsApp's pipeline, with an inbox at the end** (`whatsapp/deliveries.ts`):
 * one record per receipt written before anything is sent, a lease around the
 * send, at most three per sale, an automatic receipt only to a customer who
 * agreed and still agrees when it goes. What differs is what email allows:
 * the whole receipt in the message and the PDF attached, every time - there
 * is no template to choose between.
 *
 * **Its own records, `email_receipt_deliveries`**, beside `receipt_deliveries`
 * rather than in it. The WhatsApp screen lists that collection whole, and its
 * three-per-sale cap counts it whole; an email in either would be a WhatsApp
 * row with no number, and would use up a WhatsApp send.
 *
 * **No address in the clear.** The record holds it masked; an automatic
 * receipt reads it off the customer when it is sent, and a manual one carries
 * it only inside the task that sends it.
 */

export interface EmailReceiptDeliveryTask {
  tenantId: string;
  deliveryId: string;
  /** A manual send's address, normalized. Absent for an automatic one. */
  email?: string;
}

export type EmailDeliveryTrigger = "automatic" | "manual";

export type EmailDeliveryStatus =
  | "queued"
  | "sending"
  | "sent"
  | "delivered"
  | "failed"
  | "skipped";

/** How far a delivery has got, so a late webhook never moves one back. */
export const EMAIL_DELIVERY_RANK: Record<EmailDeliveryStatus, number> = {
  queued: 0,
  sending: 1,
  sent: 2,
  delivered: 3,
  failed: 4,
  skipped: 4,
};

const TERMINAL: ReadonlySet<EmailDeliveryStatus> = new Set<EmailDeliveryStatus>([
  "sent", "delivered", "failed", "skipped",
]);

/** The most email receipts one sale may be sent as, by every trigger together. */
export const MAXIMUM_EMAIL_SENDS_PER_SALE = 3;

/** How many times one delivery is tried before it is recorded as failed. */
export const MAXIMUM_EMAIL_SEND_ATTEMPTS = 5;

const LEASE_MILLISECONDS = 5 * 60 * 1000;

export const EMAIL_RECEIPT_DELIVERIES = "email_receipt_deliveries";

/** Which business and delivery a Brevo message belongs to, for the webhook. */
export const EMAIL_RECEIPT_MESSAGES = "email_receipt_messages";

/** A delivery's ID: the same sale, address and request always name one. */
export function emailReceiptDeliveryId(
  tenantId: string,
  saleId: string,
  email: string,
  requestId: string
): string {
  const digest = createHash("sha256")
    .update(["email-receipt", tenantId, saleId, email, requestId].join(" "))
    .digest("hex");
  return `ed_${digest.slice(0, 40)}`;
}

/**
 * `j•••@gmail.com`: the first letter and the domain.
 *
 * Enough for a manager to tell which of a customer's addresses it went to,
 * and not enough to write to them.
 */
export function maskEmail(email: string): string {
  const at = email.lastIndexOf("@");
  if (at < 1) return "•••";
  return `${email.slice(0, 1)}•••${email.slice(at)}`;
}

/**
 * The index entry the webhook finds a message's delivery by.
 *
 * Brevo answers a send with `<id@relay>` and reports on it as `id@relay`, so
 * the brackets go before the digest; the digest is what makes it a document ID
 * whatever characters the relay put in it.
 */
export function emailReceiptMessageKey(providerMessageId: string): string {
  const normalized = providerMessageId.trim().replace(/^<|>$/g, "");
  return createHash("sha256").update(`brevo-message ${normalized}`).digest("hex");
}

function deliveryRef(db: Firestore, tenantId: string, deliveryId: string): DocumentReference {
  return db.collection("tenants").doc(tenantId)
    .collection(EMAIL_RECEIPT_DELIVERIES).doc(deliveryId);
}

function taskAlreadyExists(error: unknown): boolean {
  const code = error && typeof error === "object" && "code" in error ?
    String((error as {code?: unknown}).code) : undefined;
  return code === "functions/task-already-exists" ||
    code === "already-exists" || code === "6";
}

/** How a send is queued; a test passes one that records instead. */
export type EmailReceiptEnqueuer = (task: EmailReceiptDeliveryTask) => Promise<void>;

/** Queues one send; queueing the same delivery twice sends it once. */
export async function enqueueEmailReceiptDelivery(
  task: EmailReceiptDeliveryTask
): Promise<void> {
  try {
    await getFunctions().taskQueue<EmailReceiptDeliveryTask>(
      EMAIL_RECEIPT_TASK_FUNCTION
    ).enqueue(task, {id: `email-${task.deliveryId}`, dispatchDeadlineSeconds: 300});
  } catch (error) {
    if (!taskAlreadyExists(error)) throw error;
  }
}

function newDelivery(options: {
  tenantId: string;
  saleId: string;
  email: string;
  trigger: EmailDeliveryTrigger;
  customerId?: string;
  customerName?: string;
  requestedBy?: string;
}): Record<string, unknown> {
  return {
    tenantId: options.tenantId,
    saleId: options.saleId,
    receiptNumber: null,
    trigger: options.trigger,
    emailMasked: maskEmail(options.email),
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

/** The address an automatic receipt may go to, or null where it may not. */
function consentedAddress(customer: DocumentSnapshot | null): string | null {
  if (!customer?.exists || customer.get("active") === false) return null;
  if (customer.get("emailOptIn") !== true) return null;
  return normalizeEmail(customer.get("email")) ?? null;
}

/**
 * Queues the email receipt a counted sale sends on its own, where the
 * business asked for that and the customer agreed.
 *
 * **Nothing happens otherwise, and nothing is recorded**, as on WhatsApp: a
 * business sending by hand, or a customer who never agreed, is the ordinary
 * case and not a delivery that was skipped. Safe to call again for the same
 * sale.
 */
export async function queueAutomaticEmailReceipt(
  db: Firestore,
  task: {tenantId: string; saleId: string},
  enqueue: EmailReceiptEnqueuer = enqueueEmailReceiptDelivery
): Promise<string | null> {
  const tenantRef = db.collection("tenants").doc(task.tenantId);
  const [settingsSnapshot, saleSnapshot] = await Promise.all([
    tenantRef.collection("configuration").doc("email_receipts").get(),
    tenantRef.collection("sales").doc(task.saleId).get(),
  ]);
  const settings = readEmailReceiptSettings(settingsSnapshot.data());
  if (!settings.emailEnabled || settings.mode !== "automatic") return null;
  const customerId = saleSnapshot.get("customerId");
  if (typeof customerId !== "string" || !CUSTOMER_ID_SHAPE.test(customerId)) return null;
  const customer = await tenantRef.collection("customers").doc(customerId).get();
  const email = consentedAddress(customer);
  if (email === null) return null;
  const deliveryId = emailReceiptDeliveryId(task.tenantId, task.saleId, email, "automatic");
  const ref = deliveryRef(db, task.tenantId, deliveryId);
  await db.runTransaction(async (transaction) => {
    const existing = await transaction.get(ref);
    if (existing.exists) return;
    transaction.create(ref, newDelivery({
      tenantId: task.tenantId,
      saleId: task.saleId,
      email,
      trigger: "automatic",
      customerId,
      customerName: typeof customer.get("name") === "string" ? customer.get("name") : undefined,
    }));
  });
  await enqueue({tenantId: task.tenantId, deliveryId});
  return deliveryId;
}

/**
 * Records an email receipt a cashier asked to send, and queues it.
 *
 * **The sale need not have arrived yet**, and **at most
 * [MAXIMUM_EMAIL_SENDS_PER_SALE] per sale** - both for WhatsApp's reasons.
 */
export async function requestManualEmailReceipt(
  db: Firestore,
  options: {
    tenantId: string;
    saleId: string;
    email: string;
    requestId: string;
    actorUid: string;
    customerName?: string;
  },
  enqueue: EmailReceiptEnqueuer = enqueueEmailReceiptDelivery
): Promise<{deliveryId: string; status: EmailDeliveryStatus}> {
  const email = normalizeEmail(options.email);
  if (email === undefined) {
    throw new HttpsError("invalid-argument", "email is not an email address.");
  }
  const tenantRef = db.collection("tenants").doc(options.tenantId);
  const settings = readEmailReceiptSettings(
    (await tenantRef.collection("configuration").doc("email_receipts").get()).data()
  );
  if (!settings.emailEnabled) {
    throw new HttpsError(
      "failed-precondition",
      "This business does not send receipts by email."
    );
  }
  const deliveryId = emailReceiptDeliveryId(
    options.tenantId,
    options.saleId,
    email,
    options.requestId
  );
  const ref = deliveryRef(db, options.tenantId, deliveryId);
  const status = await db.runTransaction(async (transaction): Promise<EmailDeliveryStatus> => {
    const [existing, others] = await Promise.all([
      transaction.get(ref),
      transaction.get(
        tenantRef.collection(EMAIL_RECEIPT_DELIVERIES)
          .where("saleId", "==", options.saleId)
          .limit(MAXIMUM_EMAIL_SENDS_PER_SALE + 1)
      ),
    ]);
    // A replay of this request answers with what it already did.
    if (existing.exists) return existing.get("status") as EmailDeliveryStatus;
    if (others.size >= MAXIMUM_EMAIL_SENDS_PER_SALE) {
      throw new HttpsError(
        "resource-exhausted",
        `This receipt has already been emailed ${MAXIMUM_EMAIL_SENDS_PER_SALE} times.`
      );
    }
    transaction.create(ref, newDelivery({
      tenantId: options.tenantId,
      saleId: options.saleId,
      email,
      trigger: "manual",
      customerName: options.customerName,
      requestedBy: options.actorUid,
    }));
    return "queued";
  });
  if (status === "queued") {
    await enqueue({tenantId: options.tenantId, deliveryId, email});
  }
  return {deliveryId, status};
}

/** Thrown while the sale a receipt is for has not reached the server. */
export class WaitingForEmailSale extends Error {
  constructor(readonly saleId: string) {
    super(`Sale ${saleId} has not reached the server yet.`);
  }
}

export type EmailDeliveryOutcome = "sent" | "skipped" | "failed" | "already_handled";

/** One receipt, ready for the provider. */
export interface EmailReceiptMessage {
  deliveryId: string;
  to: string;
  senderName: string;
  subject: string;
  html: string;
  text: string;
  attachment: {name: string; content: Uint8Array};
  unsubscribeUrl?: string;
}

/** Hands a message to the provider and answers the ID it was given. */
export type EmailReceiptSend = (message: EmailReceiptMessage) => Promise<string>;

export interface EmailReceiptDependencies {
  /** Null where the deployment has no usable key or sender. */
  send: EmailReceiptSend | null;
  /** Null where the recipient keyring is missing or unreadable. */
  keyring: RecipientHmacKeyring | null;
  /** The name an unnamed business's receipts come from. */
  senderNameFallback: string;
  /** The unsubscribe page, or "" for none. */
  unsubscribeBaseUrl: string;
  renderPdf?: (content: ReceiptContent) => Promise<Uint8Array>;
  now?: () => Timestamp;
}

async function finish(
  ref: DocumentReference,
  status: "skipped" | "failed",
  reason: string,
  receiptNumber: string | null,
  extra: Record<string, unknown> = {}
): Promise<"skipped" | "failed"> {
  await ref.update({
    status,
    reason,
    ...(receiptNumber === null ? {} : {receiptNumber}),
    ...extra,
    leaseUntil: FieldValue.delete(),
    updatedAt: FieldValue.serverTimestamp(),
    ...(status === "failed" ? {failedAt: FieldValue.serverTimestamp()} : {}),
  });
  return status;
}

/**
 * Sends one queued email receipt.
 *
 * Answers what became of it, or throws to be tried again: [WaitingForEmailSale]
 * while the sale has not arrived, and a retryable [EmailProviderError] while
 * Brevo cannot take it. Everything else - email not set up, the business no
 * longer sending, a customer who withdrew consent or unsubscribed, an address
 * that bounced before - is recorded and ends here.
 */
export async function executeEmailReceiptDelivery(
  db: Firestore,
  task: EmailReceiptDeliveryTask,
  dependencies: EmailReceiptDependencies
): Promise<EmailDeliveryOutcome> {
  const now = dependencies.now ?? (() => Timestamp.now());
  const ref = deliveryRef(db, task.tenantId, task.deliveryId);
  const claimed = await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (!snapshot.exists) return null;
    const status = snapshot.get("status") as EmailDeliveryStatus;
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
  const saleId = String(claimed.saleId);
  const attempts = (Number.isSafeInteger(claimed.attempts) ? claimed.attempts as number : 0) + 1;
  // Which sale, on every row - looked up here for the outcomes reached before
  // the sale is read, as on WhatsApp.
  const end = async (
    status: "skipped" | "failed",
    reason: string
  ): Promise<"skipped" | "failed"> => {
    let receiptNumber: string | null = null;
    try {
      receiptNumber = (await readReceiptContent(db, task.tenantId, saleId))
        ?.receiptNumber ?? null;
    } catch {
      receiptNumber = null;
    }
    return finish(ref, status, reason, receiptNumber);
  };
  const send = dependencies.send;
  const keyring = dependencies.keyring;
  if (send === null || keyring === null) return end("skipped", "not_configured");

  const settings = readEmailReceiptSettings(
    (await tenantRef.collection("configuration").doc("email_receipts").get()).data()
  );
  if (!settings.emailEnabled) return end("skipped", "turned_off");

  // The address: carried by a manual send, looked up for an automatic one so
  // consent withdrawn since the sale still wins.
  let email = normalizeEmail(task.email) ?? null;
  if (claimed.trigger === "automatic") {
    const customerId = claimed.customerId;
    email = consentedAddress(typeof customerId === "string" ?
      await tenantRef.collection("customers").doc(customerId).get() :
      null);
    if (email === null) return end("skipped", "no_consent");
  }
  if (email === null) return end("failed", "no_address");

  const hashes = allRecipientHashes(email, keyring);
  const [unsubscribed, bounced] = await Promise.all([
    db.getAll(...hashes.map((hash) =>
      db.collection(EMAIL_RECEIPT_SUPPRESSIONS).doc(hash.documentId))),
    db.getAll(...hashes.map((hash) =>
      db.collection("email_suppressions").doc(hash.documentId))),
  ]);
  if (unsubscribed.some((snapshot) => snapshot.exists)) {
    return end("skipped", "opted_out");
  }
  // An address that bounced or complained before, on any UzaPay email. Sending
  // again would only bounce again, and costs the sender's reputation each time.
  if (bounced.some((snapshot) =>
    snapshot.exists && snapshot.get("status") === "active")) {
    return end("skipped", "undeliverable");
  }

  const content = await readReceiptContent(db, task.tenantId, saleId);
  if (content === null) {
    await ref.update({
      status: "queued",
      reason: "waiting_for_sale",
      // Waiting for the sale is not a try at Brevo: the claim's attempt is
      // given back, so a sale from a till offline for hours does not spend
      // the retries a provider outage needs.
      attempts: FieldValue.increment(-1),
      leaseUntil: FieldValue.delete(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    throw new WaitingForEmailSale(saleId);
  }

  let providerMessageId: string;
  try {
    const unsubscribeUrl = emailReceiptUnsubscribeUrl(
      dependencies.unsubscribeBaseUrl,
      email,
      keyring
    );
    const rendered = emailReceiptEmail(content, {
      trigger: claimed.trigger === "automatic" ? "automatic" : "manual",
      unsubscribeUrl,
    });
    const pdf = await (dependencies.renderPdf ?? renderReceiptPdf)(content);
    providerMessageId = await send({
      deliveryId: task.deliveryId,
      to: email,
      senderName: emailReceiptSenderName(content, dependencies.senderNameFallback),
      subject: rendered.subject,
      html: rendered.html,
      text: rendered.text,
      attachment: {name: receiptFilename(content), content: pdf},
      unsubscribeUrl,
    });
  } catch (error) {
    if (error instanceof EmailProviderError) {
      if (error.safeCode === "provider_not_configured") {
        return finish(ref, "skipped", "not_configured", content.receiptNumber);
      }
      if (error.retryable && attempts < MAXIMUM_EMAIL_SEND_ATTEMPTS) {
        await ref.update({
          status: "queued",
          reason: "retrying",
          receiptNumber: content.receiptNumber,
          leaseUntil: FieldValue.delete(),
          updatedAt: FieldValue.serverTimestamp(),
        });
        throw error;
      }
      return finish(
        ref,
        "failed",
        error.retryable ? "provider_unavailable" : "refused",
        content.receiptNumber,
        {providerError: error.safeCode}
      );
    }
    // Anything else - a PDF that could not be drawn, the database - is ours,
    // and is tried again by the queue's own backoff.
    await ref.update({
      status: "queued",
      reason: "retrying",
      receiptNumber: content.receiptNumber,
      leaseUntil: FieldValue.delete(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    throw error;
  }

  // **Brevo has the message, so nothing from here re-queues it**: a retry
  // would email the customer the same receipt again. Written together where
  // it can be - a sent receipt the webhook could not find would stay "sent"
  // for ever, whatever became of it - and as plainly "sent" where it cannot,
  // with the failure logged rather than retried.
  const recipient = hashRecipient(email, keyring);
  const sent = {
    status: "sent",
    reason: null,
    receiptNumber: content.receiptNumber,
    providerMessageId,
    recipientHash: recipient.recipientHash,
    recipientHashKeyVersion: recipient.keyVersion,
    leaseUntil: FieldValue.delete(),
    sentAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };
  try {
    await db.runTransaction(async (transaction) => {
      transaction.update(ref, sent);
      transaction.set(
        db.collection(EMAIL_RECEIPT_MESSAGES).doc(emailReceiptMessageKey(providerMessageId)),
        {
          tenantId: task.tenantId,
          deliveryId: task.deliveryId,
          createdAt: FieldValue.serverTimestamp(),
        }
      );
    });
  } catch (error) {
    logAbsorbedFailure("email_receipt_sent_unrecorded", error, {
      tenantId: task.tenantId,
      deliveryId: task.deliveryId,
    });
    await ref.update(sent).catch((fallback: unknown) => {
      logAbsorbedFailure("email_receipt_sent_unmarked", fallback, {
        tenantId: task.tenantId,
        deliveryId: task.deliveryId,
      });
    });
  }
  return "sent";
}

/** One Brevo event about a message, as the webhook classified it. */
export interface EmailReceiptEvent {
  providerMessageId: string;
  disposition: "success" | "informational" | "temporary_failure" | "permanent_failure";
  /** Why a permanent failure failed: `hard_bounce`, `spam_complaint`... */
  failure?: string;
}

/**
 * Applies one Brevo event to the receipt it is about, never moving a delivery
 * backwards.
 *
 * Answers false for a message that is not a receipt - every account email's
 * events arrive at the same webhook. Only two events move a receipt:
 * `delivered`, and a permanent failure before it was delivered. A complaint
 * after delivery leaves it delivered (the webhook suppresses the address all
 * the same), and a temporary failure is Brevo's to retry, not ours to report.
 */
export async function applyEmailReceiptEvent(
  db: Firestore,
  event: EmailReceiptEvent
): Promise<boolean> {
  const index = await db.collection(EMAIL_RECEIPT_MESSAGES)
    .doc(emailReceiptMessageKey(event.providerMessageId)).get();
  const tenantId = index.get("tenantId");
  const deliveryId = index.get("deliveryId");
  if (!index.exists || typeof tenantId !== "string" || typeof deliveryId !== "string") {
    return false;
  }
  if (event.disposition !== "success" && event.disposition !== "permanent_failure") {
    return true;
  }
  const ref = deliveryRef(db, tenantId, deliveryId);
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (!snapshot.exists) return;
    const current = snapshot.get("status") as EmailDeliveryStatus;
    if (current === "failed" || current === "skipped") return;
    if (event.disposition === "success") {
      if (EMAIL_DELIVERY_RANK[current] >= EMAIL_DELIVERY_RANK.delivered) return;
      transaction.update(ref, {
        status: "delivered",
        deliveredAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      return;
    }
    if (current === "delivered") return;
    transaction.update(ref, {
      status: "failed",
      reason: event.failure ?? "undelivered",
      failedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
  return true;
}
