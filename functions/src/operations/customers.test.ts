import assert from "node:assert/strict";
import test from "node:test";
import {DocumentData, Transaction} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {FakeFirestore} from "../testing/fakeFirestore";
import {
  CustomerFields,
  applyCustomerCreate,
  applyCustomerUpdate,
  customerSearchFields,
  readCustomerDocument,
} from "./customers";

/**
 * What `createCustomer` and `updateCustomer` decide and write.
 *
 * The rule that makes these callables at all is the phone check - one number,
 * one customer - and the rule that makes consent trustworthy is that it belongs
 * to the number it was given for. Most of this suite is those two.
 */

const TENANT = "tenant-a";
const ACTOR = "uid-cashier";

function customerPath(customerId: string): string {
  return `tenants/${TENANT}/customers/${customerId}`;
}

function seeded(customers: Record<string, DocumentData> = {}): FakeFirestore {
  const db = new FakeFirestore();
  for (const [id, data] of Object.entries(customers)) {
    db.seed(customerPath(id), data);
  }
  db.clearWrites();
  return db;
}

function create(db: FakeFirestore, customerId: string, document: Record<string, unknown>) {
  const fields: CustomerFields = readCustomerDocument(document, "create");
  return db.runTransaction((transaction) => applyCustomerCreate(
    db.asFirestore(),
    transaction as unknown as Transaction,
    {tenantId: TENANT, customerId, actorUid: ACTOR, fields}
  ));
}

function update(db: FakeFirestore, customerId: string, document: Record<string, unknown>) {
  const fields: CustomerFields = readCustomerDocument(document, "update");
  return db.runTransaction((transaction) => applyCustomerUpdate(
    db.asFirestore(),
    transaction as unknown as Transaction,
    {tenantId: TENANT, customerId, actorUid: ACTOR, fields}
  ));
}

async function refusal(attempt: () => Promise<unknown> | unknown): Promise<HttpsError> {
  try {
    await attempt();
  } catch (error) {
    assert.ok(error instanceof HttpsError, `${error}`);
    return error;
  }
  return assert.fail("The write was not refused.");
}

test("a customer is added active, with what was typed and who added them", async () => {
  const db = seeded();

  const response = await create(db, "cu_jane", {
    name: "  Jane   Wanjiku ",
    phone: "+254712345678",
    kraPin: "a012345678z",
    email: "",
    whatsappOptIn: true,
    // Composed by the device and ignored: the server indexes what it stores.
    searchPrefixes: ["zz"],
    createdBy: "somebody-else",
  });

  assert.deepEqual(response, {customerId: "cu_jane", name: "Jane Wanjiku", active: true});
  const stored = db.read(customerPath("cu_jane"));
  assert.equal(stored?.name, "Jane Wanjiku");
  assert.equal(stored?.phone, "+254712345678");
  assert.equal(stored?.kraPin, "A012345678Z");
  assert.equal(stored?.whatsappOptIn, true);
  assert.equal(stored?.whatsappOptInBy, ACTOR);
  assert.ok(stored?.whatsappOptInAt);
  assert.equal(stored?.active, true);
  assert.equal(stored?.createdBy, ACTOR);
  assert.equal("email" in (stored ?? {}), false);
  assert.equal((stored?.searchPrefixes as string[]).includes("zz"), false);
  assert.ok((stored?.searchPrefixes as string[]).includes("wanj"));
  // Nothing a device sends can start a customer with points.
  assert.equal("points" in (stored ?? {}), false);
});

test("a create that arrives after its credit sale adopts the stand-in", async () => {
  const id = `cu_${"a".repeat(40)}`;
  const db = seeded({
    [id]: {
      name: "Jane",
      active: true,
      createdFromSaleId: "sale-1",
      balanceMinor: 5000,
      owing: true,
      saleCount: 1,
    },
  });

  await create(db, id, {name: "Jane Wanjiku", phone: "+254712345678"});

  const stored = db.read(customerPath(id));
  assert.equal(stored?.name, "Jane Wanjiku");
  assert.equal(stored?.phone, "+254712345678");
  assert.equal(stored?.balanceMinor, 5000);
  assert.equal(stored?.saleCount, 1);
  assert.equal("createdFromSaleId" in (stored ?? {}), false);
});

test("a create over a customer that was entered is refused", async () => {
  const id = `cu_${"a".repeat(40)}`;
  const db = seeded({[id]: {name: "Jane", active: true}});

  const error = await refusal(() => create(db, id, {name: "Someone else"}));

  assert.equal(error.code, "already-exists");
  assert.equal(db.read(customerPath(id))?.name, "Jane");
});

test("two customers may share a name", async () => {
  const db = seeded({cu_one: {name: "John Otieno", active: true}});

  await create(db, "cu_two", {name: "John Otieno"});

  assert.equal(db.read(customerPath("cu_two"))?.name, "John Otieno");
});

test("two customers may not share a phone number", async () => {
  const db = seeded({
    cu_one: {name: "John Otieno", phone: "+254712345678", active: true},
  });

  const error = await refusal(() => create(db, "cu_two", {
    name: "Someone Else",
    phone: "+254712345678",
  }));

  assert.equal(error.code, "already-exists");
  assert.match(error.message, /John Otieno/);
  // Who holds it, so a sale already made to cu_two can be counted there.
  assert.deepEqual(error.details, {customerId: "cu_one"});
  assert.equal(db.read(customerPath("cu_two")), undefined);
});

test("saving a customer's own number again is not a duplicate of itself", async () => {
  const db = seeded({
    cu_one: {name: "John", phone: "+254712345678", active: true},
  });

  await update(db, "cu_one", {name: "John Otieno", phone: "+254712345678"});

  assert.equal(db.read(customerPath("cu_one"))?.name, "John Otieno");
});

test("moving a number onto another customer's is refused", async () => {
  const db = seeded({
    cu_one: {name: "John", phone: "+254712345678", active: true},
    cu_two: {name: "Mary", phone: "+254700000000", active: true},
  });

  const error = await refusal(() => update(db, "cu_two", {phone: "+254712345678"}));

  assert.equal(error.code, "already-exists");
  assert.equal(db.read(customerPath("cu_two"))?.phone, "+254700000000");
});

test("consent cannot be given without a number to give it for", async () => {
  const createError = await refusal(() => readCustomerDocument(
    {name: "Jane", whatsappOptIn: true},
    "create"
  ));
  assert.equal(createError.code, "invalid-argument");

  const db = seeded({cu_one: {name: "Jane", active: true}});
  const updateError = await refusal(() => update(db, "cu_one", {whatsappOptIn: true}));
  assert.equal(updateError.code, "failed-precondition");
});

test("changing the number clears consent given for the old one", async () => {
  const db = seeded({
    cu_one: {
      name: "Jane",
      phone: "+254712345678",
      whatsappOptIn: true,
      whatsappOptInBy: "uid-manager",
      active: true,
    },
  });

  await update(db, "cu_one", {phone: "+254733333333"});

  const stored = db.read(customerPath("cu_one")) ?? {};
  assert.equal(stored.phone, "+254733333333");
  assert.equal(stored.whatsappOptIn, false);
  assert.equal("whatsappOptInBy" in stored, false);
});

test("a new number with consent recorded in the same correction keeps it", async () => {
  const db = seeded({
    cu_one: {name: "Jane", phone: "+254712345678", whatsappOptIn: true, active: true},
  });

  await update(db, "cu_one", {phone: "+254733333333", whatsappOptIn: true});

  const stored = db.read(customerPath("cu_one")) ?? {};
  assert.equal(stored.whatsappOptIn, true);
  assert.equal(stored.whatsappOptInBy, ACTOR);
});

test("clearing the number clears consent", async () => {
  const db = seeded({
    cu_one: {name: "Jane", phone: "+254712345678", whatsappOptIn: true, active: true},
  });

  await update(db, "cu_one", {phone: ""});

  const stored = db.read(customerPath("cu_one")) ?? {};
  assert.equal("phone" in stored, false);
  assert.equal(stored.whatsappOptIn, false);
});

test("consent is withdrawn on its own and the number stays", async () => {
  const db = seeded({
    cu_one: {name: "Jane", phone: "+254712345678", whatsappOptIn: true, active: true},
  });

  await update(db, "cu_one", {whatsappOptIn: false});

  const stored = db.read(customerPath("cu_one")) ?? {};
  assert.equal(stored.phone, "+254712345678");
  // An explicit false, so a queued withdrawal reads back what it sent.
  assert.equal(stored.whatsappOptIn, false);
});

test("email consent is recorded with who gave it, and needs an address", async () => {
  const createError = await refusal(() => readCustomerDocument(
    {name: "Jane", emailOptIn: true},
    "create"
  ));
  assert.equal(createError.code, "invalid-argument");

  const db = seeded();
  await create(db, "cu_one", {name: "Jane", email: "jane@example.com", emailOptIn: true});
  const stored = db.read(customerPath("cu_one")) ?? {};
  assert.equal(stored.emailOptIn, true);
  assert.equal(stored.emailOptInBy, ACTOR);
  assert.ok(stored.emailOptInAt);
  // The two consents are separate: agreeing to email says nothing of WhatsApp.
  assert.equal("whatsappOptIn" in stored, false);

  const bare = seeded({cu_two: {name: "Ann", active: true}});
  const updateError = await refusal(() => update(bare, "cu_two", {emailOptIn: true}));
  assert.equal(updateError.code, "failed-precondition");
});

test("changing the email clears email consent and leaves WhatsApp's alone", async () => {
  const db = seeded({
    cu_one: {
      name: "Jane",
      phone: "+254712345678",
      email: "jane@example.com",
      whatsappOptIn: true,
      emailOptIn: true,
      emailOptInBy: "uid-manager",
      active: true,
    },
  });

  await update(db, "cu_one", {email: "jane@work.example"});

  const stored = db.read(customerPath("cu_one")) ?? {};
  assert.equal(stored.email, "jane@work.example");
  assert.equal(stored.emailOptIn, false);
  assert.equal("emailOptInBy" in stored, false);
  assert.equal(stored.whatsappOptIn, true);
});

test("email consent is withdrawn on its own and the address stays", async () => {
  const db = seeded({
    cu_one: {name: "Jane", email: "jane@example.com", emailOptIn: true, active: true},
  });

  await update(db, "cu_one", {emailOptIn: false});

  const stored = db.read(customerPath("cu_one")) ?? {};
  assert.equal(stored.email, "jane@example.com");
  assert.equal(stored.emailOptIn, false);
});

test("a customer is marked inactive and back, and keeps their points", async () => {
  const db = seeded({cu_one: {name: "Jane", points: 40, active: true}});

  const off = await update(db, "cu_one", {active: false});
  assert.equal(off.active, false);
  assert.equal(db.read(customerPath("cu_one"))?.points, 40);

  const on = await update(db, "cu_one", {active: true});
  assert.equal(on.active, true);
});

test("correcting a customer that does not exist is not found", async () => {
  const error = await refusal(() => update(seeded(), "cu_missing", {active: false}));

  assert.equal(error.code, "not-found");
});

test("what a device may send is bounded", async () => {
  const cases: Array<[Record<string, unknown>, "create" | "update"]> = [
    [{}, "create"],
    [{name: "Jane", points: 4}, "create"],
    [{name: "Jane", active: false}, "create"],
    [{name: "Jane", email: "not an address"}, "create"],
    // The device converts to E.164; a bare local number is a mistake, not a guess.
    [{name: "Jane", phone: "0712345678"}, "create"],
    [{name: "Jane", kraPin: "12345"}, "create"],
    [{name: "Jane\u0007"}, "create"],
    [{name: "Jane", whatsappOptIn: "yes"}, "create"],
    [{}, "update"],
    [{active: "yes"}, "update"],
  ];
  for (const [document, mode] of cases) {
    const error = await refusal(() => readCustomerDocument(document, mode));
    assert.equal(error.code, "invalid-argument", JSON.stringify(document));
  }
});

test("a phone number is found the ways a counter writes it", () => {
  const {searchName, searchPrefixes} = customerSearchFields(
    "Jane Wanjiku",
    "+254712345678"
  );

  assert.equal(searchName, "jane wanjiku");
  for (const typed of ["ja", "jane w", "wanj", "2547", "7123", "0712345678"]) {
    assert.ok(searchPrefixes.includes(typed), typed);
  }
  // One-character searches are never indexed.
  assert.equal(searchPrefixes.some((prefix) => prefix.length < 2), false);
});
