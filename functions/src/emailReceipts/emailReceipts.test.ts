import assert from "node:assert/strict";
import test from "node:test";
import {DocumentData, Timestamp} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {passwordResetEmail} from "../email/templates";
import {
  hashRecipient,
  parseRecipientHmacKeyring,
} from "../email/recipientHash";
import {FakeFirestore} from "../testing/fakeFirestore";
import {readReceiptContent} from "../whatsapp/receiptContent";
import type {ReceiptContent} from "../whatsapp/receiptContent";
import {brevoEmailReceiptSend} from "./brevo";
import {
  EmailReceiptDependencies,
  MAXIMUM_EMAIL_SENDS_PER_SALE,
  WaitingForEmailSale,
  applyEmailReceiptEvent,
  emailReceiptMessageKey,
  executeEmailReceiptDelivery,
  maskEmail,
  queueAutomaticEmailReceipt,
  requestManualEmailReceipt,
} from "./deliveries";
import {readEmailReceiptSettings} from "./emailReceiptSettings";
import {
  emailReceiptEmail,
  emailReceiptSenderName,
  emailReceiptSubject,
} from "./template";
import {
  EMAIL_RECEIPT_SUPPRESSIONS,
  applyEmailReceiptUnsubscribe,
  emailReceiptUnsubscribeToken,
  readEmailReceiptUnsubscribeToken,
  renderUnsubscribePage,
} from "./unsubscribe";

/**
 * Email receipts, from the decision to send one to what Brevo says became of
 * it - with Brevo replaced by a recording fetch, so nothing leaves the machine.
 */

const TENANT = "tenant-a";
const ROOT = `tenants/${TENANT}`;
const JANE = `cu_${"0123456789abcdef".repeat(2)}01234567`;
const EMAIL = "jane@example.com";
const NOW = Timestamp.fromMillis(1790000000000);
const KEYRING = parseRecipientHmacKeyring(JSON.stringify({
  currentVersion: "v2",
  keys: {
    v2: "test-only-recipient-key-v2-0123456789abcdef",
    v1: "test-only-recipient-key-v1-0123456789abcdef",
  },
}));
const UNSUBSCRIBE = "https://auth.uzapay.co.ke/receipts/unsubscribe";

function sale(overrides: DocumentData = {}): DocumentData {
  return {
    tenantId: TENANT,
    soldById: "uid-cashier",
    receiptNumber: "CT-7F2-20261001-0001",
    businessDate: "2026-10-01",
    currency: "KES",
    customerId: JANE,
    customerName: "Jane Wanjiku",
    tender: "mpesa",
    items: [
      {productId: "flour", name: "Maize flour 2kg", quantity: 2, unitPriceMinor: 13550,
        lineTotalMinor: 27100},
      {productId: "sugar", name: "Sugar 1kg", quantity: 1, unitPriceMinor: 13500,
        lineTotalMinor: 13500},
    ],
    subtotalMinor: 40600,
    discountMinor: 0,
    totalMinor: 40600,
    createdAt: NOW,
    ...overrides,
  };
}

function business(options: {
  enabled?: boolean;
  mode?: "automatic" | "manual";
  optedIn?: boolean;
  withSale?: boolean;
  companyName?: string;
} = {}): FakeFirestore {
  const db = new FakeFirestore();
  db.seed(ROOT, {name: "Mama Njeri Shop", status: "active"});
  db.seed(`${ROOT}/configuration/branding`, {
    companyName: options.companyName ?? "Mama Njeri Shop",
  });
  db.seed(`${ROOT}/staff/uid-cashier`, {name: "John Kamau"});
  db.seed(`${ROOT}/configuration/email_receipts`, {
    emailEnabled: options.enabled ?? true,
    mode: options.mode ?? "automatic",
  });
  db.seed(`${ROOT}/customers/${JANE}`, {
    name: "Jane Wanjiku",
    email: "Jane@Example.com",
    active: true,
    ...(options.optedIn ?? true ? {emailOptIn: true} : {}),
  });
  if (options.withSale ?? true) db.seed(`${ROOT}/sales/sale-1`, sale());
  db.clearWrites();
  return db;
}

interface BrevoCall {url: string; headers: Record<string, string>; body: Record<string, any>}

function brevo(responses: Array<{status: number; body: unknown}>): {
  fetch: typeof fetch;
  calls: BrevoCall[];
} {
  const calls: BrevoCall[] = [];
  let index = 0;
  const fake = async (url: unknown, init?: RequestInit) => {
    calls.push({
      url: String(url),
      headers: init?.headers as Record<string, string>,
      body: JSON.parse(String(init?.body)),
    });
    const response = responses[Math.min(index++, responses.length - 1)];
    return {
      ok: response.status >= 200 && response.status < 300,
      status: response.status,
      json: async () => response.body,
    } as Response;
  };
  return {calls, fetch: fake as typeof fetch};
}

const ACCEPTED = {status: 201, body: {messageId: "<202610011200.1@smtp-relay.mailin.fr>"}};

function dependencies(
  fetchImpl: typeof fetch,
  overrides: Partial<EmailReceiptDependencies> = {}
): EmailReceiptDependencies {
  return {
    send: brevoEmailReceiptSend(
      {apiKey: "test-brevo-key-0123456789", senderAddress: "noreply@uzapay.co.ke"},
      fetchImpl
    ),
    keyring: KEYRING,
    senderNameFallback: "UzaPay",
    unsubscribeBaseUrl: UNSUBSCRIBE,
    renderPdf: async () => new Uint8Array([0x25, 0x50, 0x44, 0x46]),
    now: () => NOW,
    ...overrides,
  };
}

const queued: Array<{tenantId: string; deliveryId: string; email?: string}> = [];
const enqueue = async (task: {tenantId: string; deliveryId: string; email?: string}) => {
  queued.push(task);
};

function only<T>(values: readonly T[]): T {
  assert.equal(values.length, 1);
  return values[0];
}

async function refusal(attempt: () => Promise<unknown>): Promise<HttpsError> {
  try {
    await attempt();
  } catch (error) {
    assert.ok(error instanceof HttpsError, `${error}`);
    return error;
  }
  return assert.fail("The request was not refused.");
}

async function content(db: FakeFirestore): Promise<ReceiptContent> {
  return (await readReceiptContent(db.asFirestore(), TENANT, "sale-1"))!;
}

test("the settings read off unless the document says on", () => {
  assert.deepEqual(readEmailReceiptSettings(undefined), {emailEnabled: false, mode: "manual"});
  assert.deepEqual(readEmailReceiptSettings({emailEnabled: "yes"}),
    {emailEnabled: false, mode: "manual"});
  assert.deepEqual(readEmailReceiptSettings({emailEnabled: true, mode: "automatic"}),
    {emailEnabled: true, mode: "automatic"});
});

test("the email is the UzaPay layout with the receipt itemised in it", async () => {
  const db = business();
  const receipt = await content(db);
  const rendered = emailReceiptEmail(receipt, {
    trigger: "automatic",
    unsubscribeUrl: `${UNSUBSCRIBE}?t=abc`,
  });

  assert.equal(rendered.subject, "Receipt JOHN-CT-7F2-001 from Mama Njeri Shop");
  // The account emails' masthead and footer.
  assert.ok(rendered.html.includes("uzapay-logo.webp"));
  assert.ok(rendered.html.includes("no tracking pixel"));
  for (const expected of [
    "Thank you for shopping at Mama Njeri Shop",
    "2 x Maize flour 2kg",
    "@ KES 135.50",
    "KES 271.00",
    "TOTAL",
    "KES 406.00",
    "John Kamau",
    "1 Oct 2026",
    "M-Pesa",
    "Keep this receipt for returns",
    "agreed to get receipts from Mama Njeri Shop by email",
    "Stop email receipts",
  ]) {
    assert.ok(rendered.html.includes(expected), expected);
    assert.ok(rendered.text.includes(expected), `text: ${expected}`);
  }
  assert.ok(rendered.text.includes(`${UNSUBSCRIBE}?t=abc`));
});

test("what a business typed is escaped, and kept out of headers", async () => {
  const db = business({companyName: "<b>Shop</b> \"Best\"\r\nBcc: x@y.z"});
  const receipt = await content(db);
  const rendered = emailReceiptEmail(receipt, {trigger: "manual"});

  assert.equal(rendered.html.includes("<b>Shop</b>"), false);
  assert.ok(rendered.html.includes("&lt;b&gt;Shop&lt;/b&gt;"));
  assert.equal(/[\r\n]/.test(emailReceiptSubject(receipt)), false);
  const sender = emailReceiptSenderName(receipt, "UzaPay");
  assert.equal(/[\r\n"<>]/.test(sender), false);
  assert.ok(sender.endsWith(" via UzaPay"));
  assert.ok(rendered.text.includes("you asked"));
  // No unsubscribe page set up, no link.
  assert.equal(rendered.html.includes("Stop email receipts"), false);
});

test("an unnamed business's receipt comes from UzaPay", async () => {
  const db = business({companyName: ""});
  db.seed(ROOT, {status: "active"});
  const receipt = await content(db);
  assert.equal(emailReceiptSenderName(receipt, "UzaPay"), "UzaPay");
  assert.equal(emailReceiptSubject(receipt), "Receipt JOHN-CT-7F2-001");
});

test("the account emails render as they did, with no receipt block", () => {
  const rendered = passwordResetEmail("https://example.com/reset");
  assert.equal(rendered.html.includes("border-top:1px dashed"), false);
  assert.equal(rendered.html.includes("Stop email receipts"), false);
});

test("a sale to a customer who agreed queues their receipt, once", async () => {
  const db = business();

  const first = await queueAutomaticEmailReceipt(db.asFirestore(),
    {tenantId: TENANT, saleId: "sale-1"}, enqueue);
  const second = await queueAutomaticEmailReceipt(db.asFirestore(),
    {tenantId: TENANT, saleId: "sale-1"}, enqueue);

  assert.equal(first, second);
  const delivery = db.read(`${ROOT}/email_receipt_deliveries/${first}`);
  assert.equal(delivery?.status, "queued");
  assert.equal(delivery?.trigger, "automatic");
  assert.equal(delivery?.emailMasked, "j•••@example.com");
  // The address itself is never stored on the record.
  assert.equal(JSON.stringify(delivery).toLowerCase().includes("jane@"), false);
});

test("nothing is queued without consent or when the business sends by hand", async () => {
  for (const options of [{optedIn: false}, {mode: "manual" as const}, {enabled: false}]) {
    const db = business(options);
    const result = await queueAutomaticEmailReceipt(db.asFirestore(),
      {tenantId: TENANT, saleId: "sale-1"}, enqueue);
    assert.equal(result, null, JSON.stringify(options));
    assert.deepEqual(db.writtenPaths(), []);
  }
});

test("a receipt goes to Brevo with its PDF, its way out, and the shop's name", async () => {
  const db = business();
  const deliveryId = (await queueAutomaticEmailReceipt(db.asFirestore(),
    {tenantId: TENANT, saleId: "sale-1"}, enqueue))!;
  const {fetch, calls} = brevo([ACCEPTED]);

  const outcome = await executeEmailReceiptDelivery(
    db.asFirestore(),
    {tenantId: TENANT, deliveryId},
    dependencies(fetch)
  );

  assert.equal(outcome, "sent");
  const call = only(calls);
  assert.equal(call.url, "https://api.brevo.com/v3/smtp/email");
  assert.deepEqual(call.body.to, [{email: EMAIL}]);
  assert.deepEqual(call.body.sender, {
    email: "noreply@uzapay.co.ke",
    name: "Mama Njeri Shop via UzaPay",
  });
  assert.equal(call.body.attachment[0].name, "Receipt-JOHN-CT-7F2-001.pdf");
  assert.equal(call.body.attachment[0].content, Buffer.from("%PDF").toString("base64"));
  assert.equal(call.body.headers["X-Mailin-Track-Opens"], "0");
  assert.equal(call.body.headers["List-Unsubscribe-Post"], "List-Unsubscribe=One-Click");
  const link = /^<(.+)>$/.exec(call.body.headers["List-Unsubscribe"])![1];
  assert.ok(link.startsWith(`${UNSUBSCRIBE}?t=`));
  assert.ok(call.body.htmlContent.includes(link.replace(/&/g, "&amp;")));
  // The link names the address without containing it.
  assert.equal(link.includes("jane"), false);

  const delivery = db.read(`${ROOT}/email_receipt_deliveries/${deliveryId}`);
  assert.equal(delivery?.status, "sent");
  assert.equal(delivery?.receiptNumber, "JOHN-CT-7F2-001");
  const index = db.read(`email_receipt_messages/${emailReceiptMessageKey(
    "202610011200.1@smtp-relay.mailin.fr"
  )}`);
  assert.deepEqual([index?.tenantId, index?.deliveryId], [TENANT, deliveryId]);
});

test("a manual send carries its address and needs no consent", async () => {
  const db = business({optedIn: false, mode: "manual"});
  queued.length = 0;
  const {deliveryId} = await requestManualEmailReceipt(db.asFirestore(), {
    tenantId: TENANT,
    saleId: "sale-1",
    email: " Walk.In@Example.com ",
    requestId: "receipt-request-0001",
    actorUid: "uid-cashier",
  }, enqueue);
  assert.equal(only(queued).email, "walk.in@example.com");
  const {fetch, calls} = brevo([ACCEPTED]);

  const outcome = await executeEmailReceiptDelivery(
    db.asFirestore(),
    only(queued),
    dependencies(fetch)
  );

  assert.equal(outcome, "sent");
  assert.deepEqual(only(calls).body.to, [{email: "walk.in@example.com"}]);
  assert.ok(only(calls).body.htmlContent.includes("you asked Mama Njeri Shop"));
  assert.equal(
    db.read(`${ROOT}/email_receipt_deliveries/${deliveryId}`)?.emailMasked,
    "w•••@example.com"
  );
});

test("a manual send is refused when off, malformed, or past three", async () => {
  const off = business({enabled: false});
  assert.equal((await refusal(() => requestManualEmailReceipt(off.asFirestore(), {
    tenantId: TENANT, saleId: "sale-1", email: EMAIL,
    requestId: "receipt-request-0001", actorUid: "uid-cashier",
  }, enqueue))).code, "failed-precondition");

  const db = business();
  assert.equal((await refusal(() => requestManualEmailReceipt(db.asFirestore(), {
    tenantId: TENANT, saleId: "sale-1", email: "not an address",
    requestId: "receipt-request-0001", actorUid: "uid-cashier",
  }, enqueue))).code, "invalid-argument");

  for (let sent = 0; sent < MAXIMUM_EMAIL_SENDS_PER_SALE; sent++) {
    await requestManualEmailReceipt(db.asFirestore(), {
      tenantId: TENANT, saleId: "sale-1", email: EMAIL,
      requestId: `receipt-request-000${sent}`, actorUid: "uid-cashier",
    }, enqueue);
  }
  // A replay is answered, not counted.
  const replay = await requestManualEmailReceipt(db.asFirestore(), {
    tenantId: TENANT, saleId: "sale-1", email: EMAIL,
    requestId: "receipt-request-0000", actorUid: "uid-cashier",
  }, enqueue);
  assert.equal(replay.status, "queued");
  assert.equal((await refusal(() => requestManualEmailReceipt(db.asFirestore(), {
    tenantId: TENANT, saleId: "sale-1", email: EMAIL,
    requestId: "receipt-request-0009", actorUid: "uid-cashier",
  }, enqueue))).code, "resource-exhausted");
});

async function automaticDelivery(db: FakeFirestore): Promise<string> {
  return (await queueAutomaticEmailReceipt(db.asFirestore(),
    {tenantId: TENANT, saleId: "sale-1"}, enqueue))!;
}

test("an address that unsubscribed, under any key held, gets nothing", async () => {
  const db = business();
  const deliveryId = await automaticDelivery(db);
  // Stopped while v1 was the current key.
  const old = hashRecipient(EMAIL, KEYRING, "v1");
  db.seed(`${EMAIL_RECEIPT_SUPPRESSIONS}/${old.documentId}`, {at: NOW});
  const {fetch, calls} = brevo([ACCEPTED]);

  const outcome = await executeEmailReceiptDelivery(db.asFirestore(),
    {tenantId: TENANT, deliveryId}, dependencies(fetch));

  assert.equal(outcome, "skipped");
  assert.equal(calls.length, 0);
  const delivery = db.read(`${ROOT}/email_receipt_deliveries/${deliveryId}`);
  assert.equal(delivery?.reason, "opted_out");
  assert.equal(delivery?.receiptNumber, "JOHN-CT-7F2-001");
});

test("an address that bounced any UzaPay email is not tried again", async () => {
  const db = business();
  const deliveryId = await automaticDelivery(db);
  db.seed(`email_suppressions/${hashRecipient(EMAIL, KEYRING).documentId}`, {
    status: "active",
    category: "hard_bounce",
  });
  const {fetch, calls} = brevo([ACCEPTED]);

  const outcome = await executeEmailReceiptDelivery(db.asFirestore(),
    {tenantId: TENANT, deliveryId}, dependencies(fetch));

  assert.equal(outcome, "skipped");
  assert.equal(calls.length, 0);
  assert.equal(
    db.read(`${ROOT}/email_receipt_deliveries/${deliveryId}`)?.reason,
    "undeliverable"
  );
});

test("consent withdrawn after the sale wins over the queued receipt", async () => {
  const db = business();
  const deliveryId = await automaticDelivery(db);
  db.seed(`${ROOT}/customers/${JANE}`, {name: "Jane Wanjiku", email: EMAIL,
    active: true, emailOptIn: false});
  const {fetch, calls} = brevo([ACCEPTED]);

  const outcome = await executeEmailReceiptDelivery(db.asFirestore(),
    {tenantId: TENANT, deliveryId}, dependencies(fetch));

  assert.equal(outcome, "skipped");
  assert.equal(calls.length, 0);
  assert.equal(
    db.read(`${ROOT}/email_receipt_deliveries/${deliveryId}`)?.reason,
    "no_consent"
  );
});

test("a deployment with no keyring or sender records the receipt as not sent", async () => {
  for (const overrides of [{keyring: null}, {send: null}]) {
    const db = business();
    const deliveryId = await automaticDelivery(db);
    const {fetch, calls} = brevo([ACCEPTED]);
    const outcome = await executeEmailReceiptDelivery(db.asFirestore(),
      {tenantId: TENANT, deliveryId}, dependencies(fetch, overrides));
    assert.equal(outcome, "skipped");
    assert.equal(calls.length, 0);
    assert.equal(
      db.read(`${ROOT}/email_receipt_deliveries/${deliveryId}`)?.reason,
      "not_configured"
    );
  }
});

test("a receipt waits for a sale still on its way", async () => {
  const db = business({withSale: false, mode: "manual"});
  queued.length = 0;
  const {deliveryId} = await requestManualEmailReceipt(db.asFirestore(), {
    tenantId: TENANT, saleId: "sale-1", email: EMAIL,
    requestId: "receipt-request-0001", actorUid: "uid-cashier",
  }, enqueue);
  const {fetch} = brevo([ACCEPTED]);

  await assert.rejects(
    executeEmailReceiptDelivery(db.asFirestore(), only(queued), dependencies(fetch)),
    WaitingForEmailSale
  );
  const delivery = db.read(`${ROOT}/email_receipt_deliveries/${deliveryId}`);
  assert.equal(delivery?.status, "queued");
  assert.equal(delivery?.reason, "waiting_for_sale");
});

test("Brevo busy is tried again; Brevo refusing is recorded", async () => {
  const busy = business();
  const busyId = await automaticDelivery(busy);
  const {fetch: busyFetch} = brevo([{status: 503, body: {}}]);
  await assert.rejects(executeEmailReceiptDelivery(busy.asFirestore(),
    {tenantId: TENANT, deliveryId: busyId}, dependencies(busyFetch)));
  assert.equal(
    busy.read(`${ROOT}/email_receipt_deliveries/${busyId}`)?.reason,
    "retrying"
  );

  const refused = business();
  const refusedId = await automaticDelivery(refused);
  const {fetch: refusedFetch} = brevo([{status: 400, body: {}}]);
  const outcome = await executeEmailReceiptDelivery(refused.asFirestore(),
    {tenantId: TENANT, deliveryId: refusedId}, dependencies(refusedFetch));
  assert.equal(outcome, "failed");
  const delivery = refused.read(`${ROOT}/email_receipt_deliveries/${refusedId}`);
  assert.equal(delivery?.reason, "refused");
  assert.equal(delivery?.providerError, "provider_http_400");
});

test("a sent receipt is never sent twice", async () => {
  const db = business();
  const deliveryId = await automaticDelivery(db);
  const {fetch, calls} = brevo([ACCEPTED]);
  await executeEmailReceiptDelivery(db.asFirestore(),
    {tenantId: TENANT, deliveryId}, dependencies(fetch));
  const again = await executeEmailReceiptDelivery(db.asFirestore(),
    {tenantId: TENANT, deliveryId}, dependencies(fetch));
  assert.equal(again, "already_handled");
  assert.equal(calls.length, 1);
});

test("Brevo's events move a receipt forward and never back", async () => {
  const db = business();
  const deliveryId = await automaticDelivery(db);
  const {fetch} = brevo([ACCEPTED]);
  await executeEmailReceiptDelivery(db.asFirestore(),
    {tenantId: TENANT, deliveryId}, dependencies(fetch));
  const path = `${ROOT}/email_receipt_deliveries/${deliveryId}`;
  const messageId = "202610011200.1@smtp-relay.mailin.fr";

  assert.equal(await applyEmailReceiptEvent(db.asFirestore(),
    {providerMessageId: messageId, disposition: "success"}), true);
  assert.equal(db.read(path)?.status, "delivered");
  // A complaint after delivery leaves it delivered.
  await applyEmailReceiptEvent(db.asFirestore(), {
    providerMessageId: messageId,
    disposition: "permanent_failure",
    failure: "spam_complaint",
  });
  assert.equal(db.read(path)?.status, "delivered");

  assert.equal(await applyEmailReceiptEvent(db.asFirestore(),
    {providerMessageId: "an-account-email@relay", disposition: "success"}), false);
});

test("a bounce before delivery fails the receipt with the reason", async () => {
  const db = business();
  const deliveryId = await automaticDelivery(db);
  const {fetch} = brevo([ACCEPTED]);
  await executeEmailReceiptDelivery(db.asFirestore(),
    {tenantId: TENANT, deliveryId}, dependencies(fetch));

  await applyEmailReceiptEvent(db.asFirestore(), {
    providerMessageId: "<202610011200.1@smtp-relay.mailin.fr>",
    disposition: "permanent_failure",
    failure: "hard_bounce",
  });

  const delivery = db.read(`${ROOT}/email_receipt_deliveries/${deliveryId}`);
  assert.equal(delivery?.status, "failed");
  assert.equal(delivery?.reason, "hard_bounce");
});

test("an unsubscribe token names the address's suppression and nothing else", () => {
  const recipient = hashRecipient(EMAIL, KEYRING);
  const token = emailReceiptUnsubscribeToken(recipient, KEYRING);

  assert.deepEqual(readEmailReceiptUnsubscribeToken(token, KEYRING), recipient);
  assert.equal(token.includes("jane"), false);
  const tampered = token.slice(0, -2) + (token.endsWith("A") ? "BB" : "AA");
  assert.equal(readEmailReceiptUnsubscribeToken(tampered, KEYRING), null);
  assert.equal(readEmailReceiptUnsubscribeToken("r1.v2.x.y", KEYRING), null);
  assert.equal(readEmailReceiptUnsubscribeToken(undefined, KEYRING), null);
  // A key rotated out of the keyring no longer signs anything.
  const rotated = parseRecipientHmacKeyring(JSON.stringify({
    currentVersion: "v3",
    keys: {v3: "test-only-recipient-key-v3-0123456789abcdef"},
  }));
  assert.equal(readEmailReceiptUnsubscribeToken(token, rotated), null);
});

test("stopping and resuming write and lift the suppression", async () => {
  const db = new FakeFirestore();
  const recipient = hashRecipient(EMAIL, KEYRING);
  const path = `${EMAIL_RECEIPT_SUPPRESSIONS}/${recipient.documentId}`;

  await applyEmailReceiptUnsubscribe(db.asFirestore(), recipient, "stop", "one_click");
  assert.equal(db.read(path)?.via, "one_click");
  assert.equal(JSON.stringify(db.read(path)).includes("jane"), false);
  await applyEmailReceiptUnsubscribe(db.asFirestore(), recipient, "resume", "page");
  assert.equal(db.read(path), undefined);
});

test("the page asks before it stops anything, and posts back to itself", () => {
  const confirm = renderUnsubscribePage("confirm", "r1.v2.a&b");
  assert.ok(confirm.includes('method="post"'));
  assert.ok(confirm.includes('name="action" value="stop"'));
  assert.ok(confirm.includes("?t=r1.v2.a%26b"));
  assert.equal(renderUnsubscribePage("invalid", "").includes("<form"), false);
  assert.ok(renderUnsubscribePage("stopped", "t").includes('value="resume"'));
});

test("a masked address keeps the first letter and the domain", () => {
  assert.equal(maskEmail("jane@example.com"), "j•••@example.com");
  assert.equal(maskEmail("broken"), "•••");
});
