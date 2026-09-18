import assert from "node:assert/strict";
import test from "node:test";
import {FakeFirestore} from "../testing/fakeFirestore";
import {buildSalesComparison} from "./reports";

/**
 * The sales comparison, with its returns joined in.
 *
 * **`previous` stays gross and `net` is new beside it**, which is a
 * compatibility requirement rather than a preference:
 * `TenantSalesTotals.fromCallable` refuses an unfiltered answer whose
 * `previous.transactions` disagrees with `scannedTransactions`, so netting in
 * place would render the report blank on every installed client rather than
 * merely stale. Both halves are asserted on every case here for that reason.
 */

const TENANT = "tenant-a";
const START = "2026-08-24";
const END = "2026-08-26";

function db(): FakeFirestore {
  return new FakeFirestore();
}

function seedSale(
  fake: FakeFirestore,
  saleId: string,
  options: {
    soldById?: string;
    businessDate?: string;
    tender?: string;
    quantity?: number;
    unitPriceMinor?: number;
    unitCostMinor?: number | null;
    categoryId?: string;
  } = {}
): void {
  const quantity = options.quantity ?? 2;
  const unitPriceMinor = options.unitPriceMinor ?? 500;
  const unitCostMinor = options.unitCostMinor === undefined ? 300 : options.unitCostMinor;
  const subtotalMinor = unitPriceMinor * quantity;
  fake.seed(`tenants/${TENANT}/sales/${saleId}`, {
    tenantId: TENANT,
    soldById: options.soldById ?? "user-a",
    businessDate: options.businessDate ?? "2026-08-25",
    tender: options.tender ?? "cash",
    subtotalMinor,
    subtotal: subtotalMinor / 100,
    discountMinor: 0,
    discount: 0,
    totalMinor: subtotalMinor,
    total: subtotalMinor / 100,
    items: [
      {
        productId: "prod-a",
        name: "Tusker",
        categoryId: options.categoryId ?? "drinks",
        quantity,
        unitPriceMinor,
        lineTotalMinor: unitPriceMinor * quantity,
        unitPrice: unitPriceMinor / 100,
        lineTotal: (unitPriceMinor * quantity) / 100,
        ...(unitCostMinor === null ? {} : {
          unitCostMinor,
          costMinor: unitCostMinor * quantity,
          unitCost: unitCostMinor / 100,
          cost: (unitCostMinor * quantity) / 100,
        }),
      },
    ],
  });
}

function seedReturn(
  fake: FakeFirestore,
  returnId: string,
  saleId: string,
  quantity: number,
  businessDate = "2026-08-25"
): void {
  fake.seed(`tenants/${TENANT}/returns/${returnId}`, {
    tenantId: TENANT,
    saleId,
    businessDate,
    status: "pending",
    itemsReturned: [{productId: "prod-a", quantity}],
  });
}

const query = {
  tenantId: TENANT,
  previousStartDate: START,
  previousEndDate: END,
};

test("a period with no returns nets to exactly its gross", async () => {
  const fake = db();
  seedSale(fake, "co-1");

  const answer = await buildSalesComparison(fake.asFirestore(), query);

  assert.equal(answer.returnsScanned, 0);
  assert.deepEqual(answer.net, answer.previous);
  assert.deepEqual(answer.netByTender, answer.byTender);
});

test("a partial return comes off the net figures and not the gross", async () => {
  const fake = db();
  seedSale(fake, "co-1");
  seedReturn(fake, "rt-1", "co-1", 1);

  const answer = await buildSalesComparison(fake.asFirestore(), query);

  // Gross is what it always was: one sale of 2 x 500, costing 2 x 300.
  assert.equal(answer.previous.sales, 10);
  assert.equal(answer.previous.profit, 4);
  assert.equal(answer.previous.transactions, 1);
  assert.equal(answer.scannedTransactions, 1);

  // Net loses one unit's revenue and one unit's cost, so profit falls by the
  // margin on what came back rather than by its whole price.
  assert.equal(answer.net.sales, 5);
  assert.equal(answer.net.profit, 2);
  assert.equal(
    answer.net.transactions,
    1,
    "a partly returned sale is still a transaction that happened"
  );
  assert.equal(answer.returnsScanned, 1);
});

test("a fully returned sale stops being a transaction, in net only", async () => {
  const fake = db();
  seedSale(fake, "co-1");
  seedSale(fake, "co-2");
  seedReturn(fake, "rt-1", "co-1", 2);

  const answer = await buildSalesComparison(fake.asFirestore(), query);

  assert.equal(answer.previous.transactions, 2);
  assert.equal(
    answer.scannedTransactions,
    2,
    "the identity every installed client checks must survive this"
  );
  assert.equal(answer.net.transactions, 1);
  assert.equal(answer.net.sales, 10);
});

test("the tender split nets by the sale's own tender and still sums", async () => {
  const fake = db();
  seedSale(fake, "co-1", {tender: "cash"});
  seedSale(fake, "co-2", {tender: "mpesa"});
  seedReturn(fake, "rt-1", "co-1", 1);

  const answer = await buildSalesComparison(fake.asFirestore(), query);

  assert.equal(answer.byTender.cash.sales, 10);
  assert.equal(answer.netByTender.cash.sales, 5);
  assert.equal(
    answer.netByTender.mpesa.sales,
    10,
    "the money comes off the row it went onto, never another"
  );
  const bucketed = Object.values(answer.netByTender)
    .reduce((total, bucket) => total + bucket.sales, 0);
  assert.equal(
    bucketed,
    answer.net.sales,
    "the split sums to the total by construction, not coincidence"
  );
});

test("a sale with no recorded tender nets off the unrecorded row", async () => {
  const fake = db();
  // A schema v1 sale, written before the field existed. It says nothing about
  // how it was paid for, so the money comes back off `unrecorded` rather than
  // off a payment method it never named.
  fake.seed(`tenants/${TENANT}/sales/co-1`, {
    tenantId: TENANT,
    soldById: "user-a",
    businessDate: "2026-08-25",
    subtotalMinor: 1000,
    subtotal: 10,
    discountMinor: 0,
    discount: 0,
    totalMinor: 1000,
    total: 10,
    items: [{
      productId: "prod-a",
      name: "Tusker",
      quantity: 2,
      unitPriceMinor: 500,
      lineTotalMinor: 1000,
      unitPrice: 5,
      lineTotal: 10,
    }],
  });
  seedReturn(fake, "rt-1", "co-1", 1);

  const answer = await buildSalesComparison(fake.asFirestore(), query);

  assert.equal(answer.byTender.unrecorded.sales, 10);
  assert.equal(answer.netByTender.unrecorded.sales, 5);
});

test("a staff filter skips another colleague's returns without a second read", async () => {
  const fake = db();
  seedSale(fake, "co-mine", {soldById: "user-a"});
  seedSale(fake, "co-theirs", {soldById: "user-b"});
  // A return carries no `soldById` of its own. It is scoped by its sale simply
  // not being among the ones the filter read.
  seedReturn(fake, "rt-1", "co-theirs", 2);

  const answer = await buildSalesComparison(fake.asFirestore(), {
    ...query,
    soldById: "user-a",
  });

  assert.equal(answer.previous.transactions, 1);
  assert.equal(
    answer.net.transactions,
    1,
    "the other cashier's return must not empty this one's day"
  );
  assert.deepEqual(answer.net, answer.previous);
});

test("a category filter values the return on the category's own basis", async () => {
  const fake = db();
  seedSale(fake, "co-1", {categoryId: "food"});
  seedSale(fake, "co-2", {categoryId: "drinks"});
  seedReturn(fake, "rt-1", "co-1", 1);

  const answer = await buildSalesComparison(fake.asFirestore(), {
    ...query,
    categoryId: "food",
  });

  assert.equal(answer.previous.sales, 10, "only the food sale is counted");
  assert.equal(answer.net.sales, 5);
  assert.equal(
    answer.net.transactions,
    1,
    "half of it came back, so it is still a food transaction"
  );
});

test("a return outside the period is not netted off it", async () => {
  const fake = db();
  seedSale(fake, "co-1");
  // A return's `businessDate` is pinned by rules to its sale's, so this one
  // belongs to a day the query did not ask about.
  seedReturn(fake, "rt-1", "co-1", 2, "2026-09-02");

  const answer = await buildSalesComparison(fake.asFirestore(), query);

  assert.equal(answer.returnsScanned, 0);
  assert.deepEqual(answer.net, answer.previous);
});

test("a return naming a product its sale never sold is refused", async () => {
  const fake = db();
  seedSale(fake, "co-1");
  fake.seed(`tenants/${TENANT}/returns/rt-1`, {
    tenantId: TENANT,
    saleId: "co-1",
    businessDate: "2026-08-25",
    status: "pending",
    itemsReturned: [{productId: "prod-ghost", quantity: 1}],
  });

  await assert.rejects(
    () => buildSalesComparison(fake.asFirestore(), query),
    /did not sell/
  );
});

test("a return taking back more than the sale sold is refused", async () => {
  const fake = db();
  seedSale(fake, "co-1", {quantity: 1});
  seedReturn(fake, "rt-1", "co-1", 2);

  await assert.rejects(
    () => buildSalesComparison(fake.asFirestore(), query),
    /more of prod-a than its sale sold/
  );
});

test("a partly returned costless line still makes the basis incomplete", async () => {
  const fake = db();
  seedSale(fake, "co-1", {unitCostMinor: null});
  seedReturn(fake, "rt-1", "co-1", 1);

  const answer = await buildSalesComparison(fake.asFirestore(), query);

  // One of the two units is still sold, and what it cost is still unknown.
  assert.equal(answer.previous.incompleteCostLineCount, 1);
  assert.equal(answer.net.incompleteCostLineCount, 1);
  assert.equal(answer.net.sales, 5);
});

test("a fully returned costless line stops poisoning the net basis", async () => {
  // **The rule this test exists for.** A costless line that has come back in
  // full contributes no revenue and no cost to the net figures, so its
  // missing cost cannot move net profit by a shilling. Counting it would let
  // a customer undo a sale and leave the report permanently unable to state a
  // profit about goods nobody has.
  //
  // The sale as a whole is *not* fully returned - a second line is still
  // sold - so this is not the `counted: false` path.
  const fake = db();
  fake.seed(`tenants/${TENANT}/sales/co-1`, {
    tenantId: TENANT,
    soldById: "user-a",
    businessDate: "2026-08-25",
    tender: "cash",
    subtotalMinor: 1500,
    subtotal: 15,
    discountMinor: 0,
    discount: 0,
    totalMinor: 1500,
    total: 15,
    items: [
      // Costless, and every unit of it comes back.
      {
        productId: "prod-unpriced",
        quantity: 1,
        unitPriceMinor: 500,
        lineTotalMinor: 500,
        unitPrice: 5,
        lineTotal: 5,
      },
      // Priced, and still sold.
      {
        productId: "prod-a",
        quantity: 2,
        unitPriceMinor: 500,
        lineTotalMinor: 1000,
        unitPrice: 5,
        lineTotal: 10,
        unitCostMinor: 300,
        costMinor: 600,
        unitCost: 3,
        cost: 6,
      },
    ],
  });
  fake.seed(`tenants/${TENANT}/returns/rt-1`, {
    tenantId: TENANT,
    saleId: "co-1",
    businessDate: "2026-08-25",
    status: "pending",
    itemsReturned: [{productId: "prod-unpriced", quantity: 1}],
  });

  const answer = await buildSalesComparison(fake.asFirestore(), query);

  // Gross still cannot state a profit: the goods *were* sold and what they
  // cost is unknown.
  assert.equal(answer.previous.incompleteCostLineCount, 1);
  assert.equal(
    answer.net.incompleteCostLineCount,
    0,
    "the costless line is entirely out of the net figures, so it cannot make them unknowable"
  );
  // 15.00 less the 5.00 that came back; cost is the 6.00 still sold.
  assert.equal(answer.net.sales, 10);
  assert.equal(answer.net.profit, 4);
});

test("a fully returned sale takes its missing costs with it", async () => {
  // The whole-sale case: `counted: false` already drops the transaction, and
  // its incomplete lines go with it rather than leaving the period unable to
  // state a profit about a sale that did not happen.
  const fake = db();
  seedSale(fake, "co-1", {unitCostMinor: null});
  seedSale(fake, "co-2");
  seedReturn(fake, "rt-1", "co-1", 2);

  const answer = await buildSalesComparison(fake.asFirestore(), query);

  assert.equal(answer.previous.incompleteCostLineCount, 1);
  assert.equal(answer.net.incompleteCostLineCount, 0);
  assert.equal(answer.net.transactions, 1);
});

test("several returns against one sale accumulate", async () => {
  const fake = db();
  seedSale(fake, "co-1", {quantity: 3});
  seedReturn(fake, "rt-1", "co-1", 1);
  seedReturn(fake, "rt-2", "co-1", 2);

  const answer = await buildSalesComparison(fake.asFirestore(), query);

  assert.equal(answer.returnsScanned, 2);
  assert.equal(
    answer.net.transactions,
    0,
    "three of three units back is a sale that did not happen"
  );
  assert.equal(answer.net.sales, 0);
});
