import assert from "node:assert/strict";
import test from "node:test";
import {DocumentData, Transaction} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {FakeFirestore} from "../testing/fakeFirestore";
import {
  MAXIMUM_SUPPLIER_SCAN,
  SupplierFields,
  applySupplierCreate,
  applySupplierUpdate,
  readSupplierDocument,
} from "./suppliers";

/**
 * What `createSupplier` and `updateSupplier` decide and write.
 *
 * The rule that makes these callables at all is the duplicate check - one that
 * reads every other supplier, which no Firestore rule can - so most of this suite
 * is about when two names are the same supplier and when they are not. The rest
 * pins the shape a device may send and what is stored from it.
 */

const TENANT = "tenant-a";
const ACTOR = "uid-manager";

function supplierPath(supplierId: string): string {
  return `tenants/${TENANT}/suppliers/${supplierId}`;
}

function seeded(suppliers: Record<string, DocumentData> = {}): FakeFirestore {
  const db = new FakeFirestore();
  for (const [id, data] of Object.entries(suppliers)) {
    db.seed(supplierPath(id), data);
  }
  db.clearWrites();
  return db;
}

function create(db: FakeFirestore, supplierId: string, document: Record<string, unknown>) {
  const fields: SupplierFields = readSupplierDocument(document, "create");
  return db.runTransaction((transaction) => applySupplierCreate(
    db.asFirestore(),
    transaction as unknown as Transaction,
    {tenantId: TENANT, supplierId, actorUid: ACTOR, fields}
  ));
}

function update(db: FakeFirestore, supplierId: string, document: Record<string, unknown>) {
  const fields: SupplierFields = readSupplierDocument(document, "update");
  return db.runTransaction((transaction) => applySupplierUpdate(
    db.asFirestore(),
    transaction as unknown as Transaction,
    {tenantId: TENANT, supplierId, actorUid: ACTOR, fields}
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

test("a supplier is added active, with what was typed and who added it", async () => {
  const db = seeded();

  const response = await create(db, "sp_abc", {
    name: "  ABC   Distributors ",
    phone: " 0712 345 678 ",
    email: "orders@abc.example",
    notes: "",
    // Composed by the device and ignored: the actor is the server's to say.
    createdBy: "somebody-else",
  });

  assert.deepEqual(response, {supplierId: "sp_abc", name: "ABC Distributors", active: true});
  const stored = db.read(supplierPath("sp_abc"));
  assert.equal(stored?.name, "ABC Distributors");
  assert.equal(stored?.phone, "0712 345 678");
  assert.equal(stored?.email, "orders@abc.example");
  assert.equal(stored?.active, true);
  assert.equal(stored?.createdBy, ACTOR);
  // An empty field is not stored as an empty string on a create.
  assert.equal("notes" in (stored ?? {}), false);
});

test("two names that differ only in capitals and spacing are one supplier", async () => {
  const db = seeded({sp_abc: {name: "ABC Distributors", active: true}});

  const error = await refusal(() => create(db, "sp_other", {name: "abc  distributors"}));

  assert.equal(error.code, "already-exists");
  assert.match(error.message, /ABC Distributors/);
  assert.equal(db.read(supplierPath("sp_other")), undefined);
});

test("an inactive supplier still holds its name", async () => {
  // Marking a supplier inactive keeps its history; a second supplier under the
  // same name would split that history just as surely as an active one would.
  const db = seeded({sp_abc: {name: "ABC Distributors", active: false}});

  const error = await refusal(() => create(db, "sp_other", {name: "ABC Distributors"}));

  assert.equal(error.code, "already-exists");
});

test("correcting a supplier's own capitalisation is not a duplicate of itself", async () => {
  const db = seeded({sp_abc: {name: "abc distributors", active: true}});

  const response = await update(db, "sp_abc", {name: "ABC Distributors"});

  assert.equal(response.name, "ABC Distributors");
  assert.equal(db.read(supplierPath("sp_abc"))?.name, "ABC Distributors");
  assert.equal(db.read(supplierPath("sp_abc"))?.updatedBy, ACTOR);
});

test("renaming onto another supplier's name is refused", async () => {
  const db = seeded({
    sp_abc: {name: "ABC Distributors", active: true},
    sp_xyz: {name: "XYZ Wholesale", active: true},
  });

  const error = await refusal(() => update(db, "sp_xyz", {name: "abc distributors"}));

  assert.equal(error.code, "already-exists");
  assert.equal(db.read(supplierPath("sp_xyz"))?.name, "XYZ Wholesale");
});

test("a cleared contact field is removed, not stored empty", async () => {
  const db = seeded({sp_abc: {name: "ABC", phone: "0712 345 678", active: true}});

  await update(db, "sp_abc", {phone: ""});

  assert.equal("phone" in (db.read(supplierPath("sp_abc")) ?? {}), false);
});

test("a supplier is marked inactive and back, and nothing else moves", async () => {
  const db = seeded({sp_abc: {name: "ABC", phone: "0712 345 678", active: true}});

  const off = await update(db, "sp_abc", {active: false});
  assert.equal(off.active, false);
  assert.equal(db.read(supplierPath("sp_abc"))?.active, false);
  assert.equal(db.read(supplierPath("sp_abc"))?.phone, "0712 345 678");

  const on = await update(db, "sp_abc", {active: true});
  assert.equal(on.active, true);
});

test("correcting a supplier that does not exist is not found", async () => {
  const error = await refusal(() => update(seeded(), "sp_missing", {active: false}));

  assert.equal(error.code, "not-found");
});

test("more suppliers than one name can be checked against is said, not guessed", async () => {
  const many: Record<string, DocumentData> = {};
  for (let index = 0; index <= MAXIMUM_SUPPLIER_SCAN; index += 1) {
    many[`sp_${index}`] = {name: `Supplier ${index}`, active: true};
  }

  const error = await refusal(() => create(seeded(many), "sp_new", {name: "New"}));

  assert.equal(error.code, "failed-precondition");
});

test("what a device may send is bounded", async () => {
  const cases: Array<[Record<string, unknown>, "create" | "update"]> = [
    [{}, "create"],
    [{name: "ABC", quantity: 4}, "create"],
    [{name: "ABC", active: false}, "create"],
    [{name: "ABC", email: "not an address"}, "create"],
    [{name: "ABC", phone: "call me"}, "create"],
    [{name: "ABC", address: "a".repeat(301)}, "create"],
    [{name: "ABC\u0007"}, "create"],
    [{}, "update"],
    [{active: "yes"}, "update"],
  ];
  for (const [document, mode] of cases) {
    const error = await refusal(() => readSupplierDocument(document, mode));
    assert.equal(error.code, "invalid-argument", JSON.stringify(document));
  }
});

test("notes keep their line breaks and lose everything else unusual", () => {
  const fields = readSupplierDocument(
    {name: "ABC", notes: "  Deliveries   Tuesdays \r\n ask for Peter  "},
    "create"
  );

  assert.equal(fields.notes, "Deliveries Tuesdays\nask for Peter");
});
