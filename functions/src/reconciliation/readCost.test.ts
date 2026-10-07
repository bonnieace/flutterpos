import assert from "node:assert/strict";
import test from "node:test";
import {Timestamp} from "firebase-admin/firestore";
import {FakeFirestore} from "../testing/fakeFirestore";
import {registerSaleReceipt, registerReturnReceipt, registerCustomerPaymentReceipt, registerShiftClose} from "./jobs";

test("receipt triggers retain dirty days and sale ledger without scheduling reconciliation", async () => {
  const fake = new FakeFirestore();
  const input = {tenantId: "shop", businessDate: "2026-10-05", receivedAt: Timestamp.now(), deferReconciliation: true};
  const sale = await registerSaleReceipt(fake.asFirestore(), {...input, saleId: "one",
    saleData: {items: [{productId: "p", quantity: 1}]}});
  const returned = await registerReturnReceipt(fake.asFirestore(), {...input, returnId: "r"});
  const payment = await registerCustomerPaymentReceipt(fake.asFirestore(), {...input, paymentId: "p"});
  assert.equal(sale.task, undefined); assert.equal(returned.task, undefined); assert.equal(payment.task, undefined);
  assert.equal(fake.writes.some((w) => w.path.includes("/reconciliation_jobs/")), false);
  assert.equal(fake.writes.some((w) => w.path.includes("/stock_movements/")), true);
  const dirty = await fake.asFirestore().doc("tenants/shop/reconciliation_dirty_days/2026-10-05").get();
  assert.equal(dirty.get("revision"), 3);
  await registerSaleReceipt(fake.asFirestore(), {...input, saleId: "one", saleData: {items: []}});
  assert.equal((await dirty.ref.get()).get("revision"), 3);
});

test("a shift close creates one durable job and retry does not dirty the day twice", async () => {
  const fake = new FakeFirestore();
  const first = await registerShiftClose(fake.asFirestore(), "shop", "shift", "2026-10-05");
  assert.ok(first);
  const job = await fake.asFirestore().doc(`tenants/shop/reconciliation_jobs/${first.jobId}`).get();
  assert.equal(job.get("source"), "shift_close");
  assert.equal(await registerShiftClose(fake.asFirestore(), "shop", "shift", "2026-10-05"), undefined);
});
