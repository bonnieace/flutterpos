import assert from "node:assert/strict";
import test from "node:test";
import {HttpsError} from "firebase-functions/v2/https";
import {
  STRANDED_SALE_WINDOW_MS,
  validateStrandedSale,
} from "./strandedSales";

/**
 * What a deactivated cashier may hand over, and what they may not.
 *
 * **Why this exists.** A sale is durable in the device's own outbox before it
 * reaches the server. If the cashier's membership ends while sales are still
 * there, every path that would send them stops - the workers require a session
 * that can access the business, and `allow create` on `sales` requires
 * `activeStaff` in any case. The money was taken and the only record is on a
 * phone nobody can act through. This grants one narrow way out, and these are
 * the bounds that keep it narrow.
 */

const TENANT = "tenant-a";
const ACTOR = "user-cashier";
const DEACTIVATED_AT = Date.UTC(2026, 6, 31, 12);

function sale(overrides: Record<string, unknown> = {}) {
  return {
    checkoutId: "co-1754000000000-abcdabcdabcdabcd",
    tenantId: TENANT,
    soldById: ACTOR,
    payloadHash: "a".repeat(64),
    payloadSchemaVersion: 2,
    tender: "cash",
    currency: "KES",
    businessDate: "2026-07-31",
    clientCreatedAtMs: DEACTIVATED_AT - 60_000,
    shiftId: "shift-a",
    deviceId: "dev-0123456789abcdef0123456789abcdef",
    receiptNumber: "CT-68E-20260731-0001",
    receiptSequence: 1,
    items: [{productId: "product-a", name: "Tusker", quantity: 2, unitPriceMinor: 500}],
    subtotalMinor: 1000,
    discountMinor: 0,
    totalMinor: 1000,
    ...overrides,
  };
}

function validate(overrides: {
  sale?: Record<string, unknown>;
  actorUid?: string;
  nowMs?: number;
} = {}) {
  return validateStrandedSale({
    sale: overrides.sale ?? sale(),
    tenantId: TENANT,
    actorUid: overrides.actorUid ?? ACTOR,
    deactivatedAtMs: DEACTIVATED_AT,
    nowMs: overrides.nowMs ?? DEACTIVATED_AT + 1000,
  });
}

function refusalCode(run: () => unknown): string {
  try {
    run();
  } catch (error) {
    assert.ok(error instanceof HttpsError);
    return error.code;
  }
  return "no-error";
}

test("a sale rung up before the door closed is handed over", () => {
  const accepted = validate();

  assert.equal(accepted.checkoutId, "co-1754000000000-abcdabcdabcdabcd");
  // The stock the sale moves comes from its own lines rather than from a
  // figure the caller supplies, so a handed-over sale cannot claim to have
  // taken less off the shelf than it sold.
  assert.deepEqual(accepted.lines, [{productId: "product-a", quantity: 2}]);
});

test("a sale dated after the deactivation is refused", () => {
  // The bound that makes the grant narrow. The device's own clock is the only
  // thing that could claim a later sale was earlier, so it is checked.
  assert.equal(
    refusalCode(() => validate({
      sale: sale({clientCreatedAtMs: DEACTIVATED_AT + 1}),
    })),
    "failed-precondition"
  );
});

test("somebody else's sale is refused", () => {
  assert.equal(
    refusalCode(() => validate({sale: sale({soldById: "user-b"})})),
    "permission-denied"
  );
});

test("a sale belonging to another business is refused", () => {
  assert.equal(
    refusalCode(() => validate({sale: sale({tenantId: "tenant-b"})})),
    "permission-denied"
  );
});

test("the window closes eventually", () => {
  assert.equal(
    refusalCode(() => validate({
      nowMs: DEACTIVATED_AT + STRANDED_SALE_WINDOW_MS + 1,
    })),
    "failed-precondition"
  );
  // And is open right up to the edge.
  assert.doesNotThrow(() => validate({
    nowMs: DEACTIVATED_AT + STRANDED_SALE_WINDOW_MS,
  }));
});

test("the tender contract is the one Rules apply on an ordinary create", () => {
  // Absent is an answer at v2 - the register does not preselect a method.
  assert.doesNotThrow(() => validate({sale: sale({tender: undefined})}));
  // A present value must name a modelled method.
  assert.equal(
    refusalCode(() => validate({sale: sale({tender: "cheque"})})),
    "invalid-argument"
  );
  // And a v1 sale predates the field entirely.
  assert.equal(
    refusalCode(() => validate({
      sale: sale({payloadSchemaVersion: 1, tender: "cash"}),
    })),
    "invalid-argument"
  );
  assert.doesNotThrow(() => validate({
    sale: sale({payloadSchemaVersion: 1, tender: undefined}),
  }));
});

test("a malformed sale is refused rather than written", () => {
  const cases: Array<[string, Record<string, unknown>]> = [
    ["no lines", sale({items: []})],
    ["too many lines", sale({items: Array.from({length: 17}, () => ({
      productId: "product-a",
      quantity: 1,
    }))})],
    ["zero quantity", sale({items: [{productId: "product-a", quantity: 0}]})],
    ["negative quantity", sale({items: [{productId: "product-a", quantity: -1}]})],
    ["fractional total", sale({totalMinor: 10.5})],
    ["no receipt", sale({receiptNumber: ""})],
    ["no device", sale({deviceId: ""})],
    ["no client timestamp", sale({clientCreatedAtMs: "yesterday"})],
  ];

  for (const [name, malformed] of cases) {
    const code = refusalCode(() => validate({sale: malformed}));
    assert.ok(
      code === "invalid-argument" || code === "failed-precondition",
      `${name} was accepted (${code})`
    );
  }
});
