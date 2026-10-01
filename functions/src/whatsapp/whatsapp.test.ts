import assert from "node:assert/strict";
import {createHmac} from "node:crypto";
import test from "node:test";
import {DocumentData, Timestamp} from "firebase-admin/firestore";
import {FakeFirestore} from "../testing/fakeFirestore";
import {
  WhatsappFetch,
  buildTemplatePayload,
  e164FromWhatsapp,
  maskPhone,
  parseWebhookPayload,
  phoneHash,
  verifyWebhookSignature,
} from "./client";
import type {WhatsappSendConfig} from "./config";
import {
  MAXIMUM_SENDS_PER_SALE,
  WaitingForSale,
  applyDeliveryStatus,
  executeReceiptDelivery,
  queueAutomaticReceipt,
  receiptDeliveryId,
  requestManualReceipt,
} from "./deliveries";
import {readEReceiptSettings} from "./eReceiptSettings";
import {
  formatReceiptMoney,
  printedReceiptNumber,
  readReceiptContent,
} from "./receiptContent";
import {renderReceiptPdf} from "./receiptPdf";
import {
  RECEIPT_PDF_TEMPLATE,
  RECEIPT_SUMMARY_TEMPLATE,
  receiptSummaryParameters,
  templateText,
} from "./templates";

/**
 * WhatsApp receipts, from the decision to send one to what Meta says became of
 * it - with Meta replaced by a recording fetch, so nothing leaves the machine.
 */

const TENANT = "tenant-a";
const ROOT = `tenants/${TENANT}`;
const JANE = `cu_${"0123456789abcdef".repeat(2)}01234567`;
const PHONE = "+254712345678";
const CONFIG: WhatsappSendConfig = {
  accessToken: "token",
  phoneNumberId: "1234567890",
  graphVersion: "v23.0",
  languageCode: "en",
};
const NOW = Timestamp.fromMillis(1790000000000);

/** What was queued to send, instead of Cloud Tasks. */
const queued: Array<{tenantId: string; deliveryId: string; phone?: string}> = [];
const enqueue = async (task: {tenantId: string; deliveryId: string; phone?: string}) => {
  queued.push(task);
};

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
  format?: "pdf" | "summary";
  optedIn?: boolean;
  withSale?: boolean;
} = {}): FakeFirestore {
  const db = new FakeFirestore();
  db.seed(ROOT, {name: "Mama Njeri Shop", status: "active"});
  db.seed(`${ROOT}/configuration/branding`, {companyName: "Mama Njeri Shop"});
  db.seed(`${ROOT}/staff/uid-cashier`, {name: "John Kamau"});
  db.seed(`${ROOT}/configuration/e_receipts`, {
    whatsappEnabled: options.enabled ?? true,
    mode: options.mode ?? "automatic",
    format: options.format ?? "summary",
  });
  db.seed(`${ROOT}/customers/${JANE}`, {
    name: "Jane Wanjiku",
    phone: PHONE,
    active: true,
    ...(options.optedIn ?? true ? {whatsappOptIn: true} : {}),
  });
  if (options.withSale ?? true) db.seed(`${ROOT}/sales/sale-1`, sale());
  db.clearWrites();
  return db;
}

interface Call {url: string; body: unknown}

function meta(responses: Array<{status: number; body: unknown}>): {
  fetch: WhatsappFetch;
  calls: Call[];
} {
  const calls: Call[] = [];
  let index = 0;
  return {
    calls,
    fetch: async (url, options) => {
      calls.push({
        url,
        body: typeof options.body === "string" ? JSON.parse(options.body) : "form",
      });
      const response = responses[Math.min(index++, responses.length - 1)];
      return {
        ok: response.status >= 200 && response.status < 300,
        status: response.status,
        json: async () => response.body,
      };
    },
  };
}

const SENT = {status: 200, body: {messages: [{id: "wamid.1"}]}};

test("a sale to a customer who agreed queues their receipt, once", async () => {
  const db = business();

  const first = await queueAutomaticReceipt(db.asFirestore(), {tenantId: TENANT, saleId: "sale-1"}, enqueue);
  const second = await queueAutomaticReceipt(db.asFirestore(), {tenantId: TENANT, saleId: "sale-1"}, enqueue);

  assert.equal(first, second);
  const delivery = db.read(`${ROOT}/receipt_deliveries/${first}`);
  assert.equal(delivery?.status, "queued");
  assert.equal(delivery?.trigger, "automatic");
  assert.equal(delivery?.phoneMasked, "+254•••678");
  // The number itself is never stored on the record.
  assert.equal(JSON.stringify(delivery).includes("712345678"), false);
});

test("nothing is queued without consent or when the business sends by hand", async () => {
  for (const options of [{optedIn: false}, {mode: "manual" as const}, {enabled: false}]) {
    const db = business(options);
    const queued = await queueAutomaticReceipt(
      db.asFirestore(),
      {tenantId: TENANT, saleId: "sale-1"},
      enqueue
    );
    assert.equal(queued, null, JSON.stringify(options));
    assert.deepEqual(db.writtenPaths(), []);
  }
});

test("a summary receipt is sent, indexed for the webhook, and counted", async () => {
  const db = business();
  const deliveryId = (await queueAutomaticReceipt(
    db.asFirestore(),
    {tenantId: TENANT, saleId: "sale-1"},
    enqueue
  ))!;
  const {fetch, calls} = meta([SENT]);

  const outcome = await executeReceiptDelivery(
    db.asFirestore(),
    {tenantId: TENANT, deliveryId},
    {config: CONFIG, fetchImpl: fetch, now: () => NOW}
  );

  assert.equal(outcome, "sent");
  const payload = only(calls).body as Record<string, any>;
  assert.equal(payload.to, "254712345678");
  assert.equal(payload.template.name, RECEIPT_SUMMARY_TEMPLATE);
  assert.deepEqual(
    payload.template.components[0].parameters.map((p: {text: string}) => p.text),
    ["Mama Njeri Shop", "JOHN-CT-7F2-001", "1 Oct 2026", "3 items", "KES 406.00"]
  );
  const delivery = db.read(`${ROOT}/receipt_deliveries/${deliveryId}`);
  assert.equal(delivery?.status, "sent");
  assert.equal(delivery?.providerMessageId, "wamid.1");
  assert.equal(db.read("whatsapp_messages/wamid.1")?.deliveryId, deliveryId);
  assert.equal(db.read(`${ROOT}/whatsapp_usage/2026-09`)?.sent, 1);
});

test("a PDF receipt is uploaded first and named in the header", async () => {
  const db = business({format: "pdf"});
  const deliveryId = (await queueAutomaticReceipt(
    db.asFirestore(),
    {tenantId: TENANT, saleId: "sale-1"},
    enqueue
  ))!;
  const {fetch, calls} = meta([{status: 200, body: {id: "media-1"}}, SENT]);

  const outcome = await executeReceiptDelivery(
    db.asFirestore(),
    {tenantId: TENANT, deliveryId},
    {
      config: CONFIG,
      fetchImpl: fetch,
      now: () => NOW,
      renderPdf: (content) => renderReceiptPdf(content, {logo: null}),
    }
  );

  assert.equal(outcome, "sent");
  assert.match(calls[0].url, /\/1234567890\/media$/);
  const payload = calls[1].body as Record<string, any>;
  assert.equal(payload.template.name, RECEIPT_PDF_TEMPLATE);
  assert.deepEqual(payload.template.components[0], {
    type: "header",
    parameters: [{
      type: "document",
      document: {id: "media-1", filename: "Receipt-JOHN-CT-7F2-001.pdf"},
    }],
  });
});

test("with the channel unset, a receipt is recorded as skipped and nothing is sent", async () => {
  const db = business();
  const deliveryId = (await queueAutomaticReceipt(
    db.asFirestore(),
    {tenantId: TENANT, saleId: "sale-1"},
    enqueue
  ))!;
  const {fetch, calls} = meta([SENT]);

  const outcome = await executeReceiptDelivery(
    db.asFirestore(),
    {tenantId: TENANT, deliveryId},
    {config: null, fetchImpl: fetch, now: () => NOW}
  );

  assert.equal(outcome, "skipped");
  assert.equal(calls.length, 0);
  assert.equal(db.read(`${ROOT}/receipt_deliveries/${deliveryId}`)?.reason, "not_configured");
});

test("consent withdrawn after the sale wins over the queued receipt", async () => {
  const db = business();
  const deliveryId = (await queueAutomaticReceipt(
    db.asFirestore(),
    {tenantId: TENANT, saleId: "sale-1"},
    enqueue
  ))!;
  db.seed(`${ROOT}/customers/${JANE}`, {name: "Jane", phone: PHONE, whatsappOptIn: false});
  const {fetch, calls} = meta([SENT]);

  const outcome = await executeReceiptDelivery(
    db.asFirestore(),
    {tenantId: TENANT, deliveryId},
    {config: CONFIG, fetchImpl: fetch, now: () => NOW}
  );

  assert.equal(outcome, "skipped");
  assert.equal(calls.length, 0);
  assert.equal(db.read(`${ROOT}/receipt_deliveries/${deliveryId}`)?.reason, "no_consent");
});

test("a number that replied STOP gets nothing", async () => {
  const db = business();
  db.seed(`whatsapp_suppressions/${phoneHash(PHONE)}`, {via: "reply"});
  const deliveryId = (await queueAutomaticReceipt(
    db.asFirestore(),
    {tenantId: TENANT, saleId: "sale-1"},
    enqueue
  ))!;

  const outcome = await executeReceiptDelivery(
    db.asFirestore(),
    {tenantId: TENANT, deliveryId},
    {config: CONFIG, fetchImpl: meta([SENT]).fetch, now: () => NOW}
  );

  assert.equal(outcome, "skipped");
  assert.equal(db.read(`${ROOT}/receipt_deliveries/${deliveryId}`)?.reason, "opted_out");
});

test("a manual receipt waits for a sale still on an offline till", async () => {
  const db = business({withSale: false, mode: "manual"});
  const {deliveryId} = await requestManualReceipt(db.asFirestore(), {
    tenantId: TENANT,
    saleId: "sale-1",
    phone: "+254700000001",
    requestId: "receipt-request-0001",
    actorUid: "uid-cashier",
  }, enqueue);

  await assert.rejects(
    () => executeReceiptDelivery(
      db.asFirestore(),
      {tenantId: TENANT, deliveryId, phone: "+254700000001"},
      {config: CONFIG, fetchImpl: meta([SENT]).fetch, now: () => NOW}
    ),
    WaitingForSale
  );
  const delivery = db.read(`${ROOT}/receipt_deliveries/${deliveryId}`);
  assert.equal(delivery?.status, "queued");
  assert.equal(delivery?.reason, "waiting_for_sale");

  db.seed(`${ROOT}/sales/sale-1`, sale());
  const outcome = await executeReceiptDelivery(
    db.asFirestore(),
    {tenantId: TENANT, deliveryId, phone: "+254700000001"},
    {config: CONFIG, fetchImpl: meta([SENT]).fetch, now: () => NOW}
  );
  assert.equal(outcome, "sent");
});

test("Meta's trouble is retried; a refused number is recorded as failed", async () => {
  const db = business();
  const deliveryId = (await queueAutomaticReceipt(
    db.asFirestore(),
    {tenantId: TENANT, saleId: "sale-1"},
    enqueue
  ))!;

  await assert.rejects(() => executeReceiptDelivery(
    db.asFirestore(),
    {tenantId: TENANT, deliveryId},
    {
      config: CONFIG,
      fetchImpl: meta([{status: 503, body: {error: {message: "Busy"}}}]).fetch,
      now: () => NOW,
    }
  ));
  assert.equal(db.read(`${ROOT}/receipt_deliveries/${deliveryId}`)?.status, "queued");

  const outcome = await executeReceiptDelivery(
    db.asFirestore(),
    {tenantId: TENANT, deliveryId},
    {
      config: CONFIG,
      fetchImpl: meta([{
        status: 400,
        body: {error: {message: "Recipient not on WhatsApp", code: 131026}},
      }]).fetch,
      now: () => NOW,
    }
  );
  assert.equal(outcome, "failed");
  const refused = db.read(`${ROOT}/receipt_deliveries/${deliveryId}`);
  assert.equal(refused?.reason, "refused_131026");
  // A refused row still says which sale it was for.
  assert.equal(refused?.receiptNumber, "JOHN-CT-7F2-001");
});

test("a receipt skipped before its sale is read still names the sale", async () => {
  const db = business();
  const deliveryId = (await queueAutomaticReceipt(
    db.asFirestore(),
    {tenantId: TENANT, saleId: "sale-1"},
    enqueue
  ))!;
  db.seed(`${ROOT}/configuration/e_receipts`, {
    whatsappEnabled: false,
    mode: "automatic",
    format: "pdf",
  });

  const outcome = await executeReceiptDelivery(
    db.asFirestore(),
    {tenantId: TENANT, deliveryId},
    {config: CONFIG, fetchImpl: meta([SENT]).fetch, now: () => NOW}
  );

  assert.equal(outcome, "skipped");
  const skipped = db.read(`${ROOT}/receipt_deliveries/${deliveryId}`);
  assert.equal(skipped?.reason, "turned_off");
  assert.equal(skipped?.receiptNumber, "JOHN-CT-7F2-001");
});

test("a delivery being sent elsewhere is left alone", async () => {
  const db = business();
  const deliveryId = (await queueAutomaticReceipt(
    db.asFirestore(),
    {tenantId: TENANT, saleId: "sale-1"},
    enqueue
  ))!;
  db.seed(`${ROOT}/receipt_deliveries/${deliveryId}`, {
    ...db.read(`${ROOT}/receipt_deliveries/${deliveryId}`),
    status: "sending",
    leaseUntil: Timestamp.fromMillis(NOW.toMillis() + 60000),
  });
  const {fetch, calls} = meta([SENT]);

  const outcome = await executeReceiptDelivery(
    db.asFirestore(),
    {tenantId: TENANT, deliveryId},
    {config: CONFIG, fetchImpl: fetch, now: () => NOW}
  );

  assert.equal(outcome, "already_handled");
  assert.equal(calls.length, 0);
});

test("a sale's receipt is sent at most three times, and a replay is one send", async () => {
  const db = business({mode: "manual"});
  const send = (requestId: string, phone = "+254700000001") => requestManualReceipt(
    db.asFirestore(),
    {tenantId: TENANT, saleId: "sale-1", phone, requestId, actorUid: "uid-cashier"},
    enqueue
  );

  const first = await send("receipt-request-0001");
  const replay = await send("receipt-request-0001");
  assert.equal(replay.deliveryId, first.deliveryId);
  await send("receipt-request-0002");
  await send("receipt-request-0003", "+254700000002");

  await assert.rejects(() => send("receipt-request-0004"), /already been sent 3 times/);
  assert.equal(MAXIMUM_SENDS_PER_SALE, 3);
});

test("a business that does not send receipts refuses a manual one", async () => {
  const db = business({enabled: false});
  await assert.rejects(() => requestManualReceipt(db.asFirestore(), {
    tenantId: TENANT,
    saleId: "sale-1",
    phone: PHONE,
    requestId: "receipt-request-0001",
    actorUid: "uid-cashier",
  }, enqueue), /does not send receipts/);
});

test("statuses only move forward, and another product's messages are dropped", async () => {
  const db = business();
  const deliveryId = receiptDeliveryId(TENANT, "sale-1", PHONE, "automatic");
  db.seed(`${ROOT}/receipt_deliveries/${deliveryId}`, {status: "sent"});
  db.seed("whatsapp_messages/wamid.1", {tenantId: TENANT, deliveryId});
  const status = () => db.read(`${ROOT}/receipt_deliveries/${deliveryId}`)?.status;

  await applyDeliveryStatus(db.asFirestore(), {providerMessageId: "wamid.1", status: "read"});
  assert.equal(status(), "read");
  await applyDeliveryStatus(db.asFirestore(), {providerMessageId: "wamid.1", status: "delivered"});
  assert.equal(status(), "read");
  await applyDeliveryStatus(db.asFirestore(), {providerMessageId: "wamid.1", status: "failed"});
  assert.equal(status(), "read");

  assert.equal(
    await applyDeliveryStatus(
      db.asFirestore(),
      {providerMessageId: "wamid.carerota", status: "delivered"}
    ),
    false
  );
});

test("a webhook is believed only with the App Secret's signature", () => {
  const body = JSON.stringify({entry: []});
  const signature = `sha256=${createHmac("sha256", "secret").update(body).digest("hex")}`;

  assert.equal(verifyWebhookSignature(body, signature, "secret"), true);
  assert.equal(verifyWebhookSignature(body, signature, "other"), false);
  assert.equal(verifyWebhookSignature(body, undefined, "secret"), false);
});

test("a webhook's statuses and replies are read out of Meta's shape", () => {
  const parsed = parseWebhookPayload({
    entry: [{changes: [{field: "messages", value: {
      statuses: [{id: "wamid.1", status: "delivered", timestamp: "1"}],
      messages: [{from: "254712345678", id: "in.1", type: "text", text: {body: "STOP"}}],
    }}]}],
  });

  assert.deepEqual(parsed.statuses, [
    {providerMessageId: "wamid.1", status: "delivered", timestamp: "1", error: undefined},
  ]);
  assert.equal(parsed.inbound[0].text, "STOP");
  assert.equal(e164FromWhatsapp(parsed.inbound[0].from), PHONE);
});

test("the readable receipt number matches the printed one", async () => {
  assert.equal(printedReceiptNumber("CT-7F2-20260929-0001", "John Kamau"), "JOHN-CT-7F2-001");
  assert.equal(printedReceiptNumber("CT-7F2-20260929-0001", "  "), "CT-7F2-001");
  assert.equal(printedReceiptNumber("CT-7F2-20260929-0001", "Mũgumo"), "MŨGUMO-CT-7F2-001");
  assert.equal(printedReceiptNumber("not-a-receipt"), "not-a-receipt");

  const content = await readReceiptContent(business().asFirestore(), TENANT, "sale-1");
  assert.equal(content?.receiptNumber, "JOHN-CT-7F2-001");
  assert.equal(content?.paidBy, "M-Pesa");
  assert.equal(content?.customerName, "Jane Wanjiku");
});

test("template parameters are what Meta accepts", () => {
  assert.equal(templateText("Line one\nline two\tend"), "Line one line two end");
  assert.equal(templateText("a      b"), "a   b");
  assert.equal(templateText("   "), "-");
  assert.equal(formatReceiptMoney("KES", 125050), "KES 1,250.50");
  assert.equal(maskPhone(PHONE), "+254•••678");
  assert.deepEqual(
    buildTemplatePayload({
      to: PHONE,
      templateName: "t",
      languageCode: "en",
      bodyParameters: [],
    }).template,
    {name: "t", language: {code: "en"}}
  );
});

test("a malformed setting sends nothing", () => {
  assert.equal(readEReceiptSettings(undefined).whatsappEnabled, false);
  assert.equal(readEReceiptSettings({whatsappEnabled: "yes"}).whatsappEnabled, false);
  assert.deepEqual(
    readEReceiptSettings({whatsappEnabled: true, mode: "weird", format: "weird"}),
    {whatsappEnabled: true, mode: "manual", format: "pdf"}
  );
});

test("a summary counts units, not lines", async () => {
  const content = await readReceiptContent(business().asFirestore(), TENANT, "sale-1");
  assert.equal(receiptSummaryParameters(content!)[3], "3 items");
});

function only<T>(items: T[]): T {
  assert.equal(items.length, 1, `expected one, found ${items.length}`);
  return items[0];
}
