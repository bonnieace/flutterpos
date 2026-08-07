import assert from "node:assert/strict";
import test from "node:test";
import {FieldPath, FieldValue, Timestamp} from "firebase-admin/firestore";
import {FakeFirestore} from "./fakeFirestore";

/**
 * The double's own semantics, each one named for the processor behaviour that
 * depends on it.
 *
 * `processors.test.ts` asserts what the reconciliation processors do against this
 * module rather than against Firestore, so every one of those assertions is only
 * worth what this module's fidelity is worth. Three panel fakes in this
 * repository have already made a test pass for the wrong reason by answering a
 * question they were never asked - one served every collection from a single
 * page, another ignored a filter - and this file is the largest fake in the
 * project. So the semantics it reproduces are asserted here, in the same place
 * they are relied on, and the ones it refuses to guess at are asserted to throw.
 *
 * These are claims about Firestore. Where one is wrong, the processor tests that
 * lean on it are wrong in the same direction, which is exactly why they are
 * written down as assertions rather than left as comments.
 */

const DOC = "tenants/tenant-a/things/thing-1";

test("increment resolves against what the field already held", () => {
  // The `reconciliation_dirty_days` revision. The metrics phase reads it back and
  // refuses anything below one, so a double that dropped the sentinel or resolved
  // it to the sentinel object would quarantine every day of a full window.
  const db = new FakeFirestore();

  db.doc(DOC).set({counter: FieldValue.increment(1)}, {merge: true});
  assert.equal(db.read(DOC)?.counter, 1);

  db.doc(DOC).set({counter: FieldValue.increment(4)}, {merge: true});
  assert.equal(db.read(DOC)?.counter, 5);

  // Firestore's own rule for a field that is not a number: the operand wins
  // rather than being added to something it cannot be added to.
  db.seed(DOC, {counter: "not a number"});
  db.doc(DOC).set({counter: FieldValue.increment(3)}, {merge: true});
  assert.equal(db.read(DOC)?.counter, 3);
});

test("a server timestamp resolves to an instant a fixture can order", () => {
  const clock = {now: 1_785_000_000_000};
  const db = new FakeFirestore(() => clock.now);

  db.doc(DOC).set({writtenAt: FieldValue.serverTimestamp()}, {merge: true});
  const first = db.read(DOC)?.writtenAt;
  assert.ok(first instanceof Timestamp);
  assert.equal(first.toMillis(), clock.now);

  clock.now += 1000;
  db.doc(DOC).set({writtenAt: FieldValue.serverTimestamp()}, {merge: true});
  const second = db.read(DOC)?.writtenAt;
  assert.ok(second instanceof Timestamp);
  assert.equal(second.toMillis(), clock.now);
});

test("a delete sentinel is honoured by a merge and rejected by a replace", () => {
  // `reconcileProduct` clears `lastMovementAt` and `lastMovementId` with delete
  // sentinels in a `set(..., {merge: true})`. A create payload carrying one threw
  // on every sale for as long as it existed, which is what `writeSentinels.ts`
  // and the sentinel audit beside this file exist for - so the double has to
  // refuse it in exactly the write Firestore refuses it in.
  const db = new FakeFirestore();
  db.seed(DOC, {kept: 1, cleared: 2});

  db.doc(DOC).set({cleared: FieldValue.delete()}, {merge: true});
  assert.deepEqual(db.read(DOC), {kept: 1});

  assert.throws(
    () => db.doc(DOC).set({kept: FieldValue.delete()}),
    /Firestore rejects FieldValue.delete\(\)/
  );
  assert.deepEqual(db.read(DOC), {kept: 1});
});

test("a replace drops fields a merge would have kept", () => {
  // Both halves are load-bearing: the regenerated `daily_metrics` document is an
  // unmerged set and must not retain a field from an earlier shape, while the
  // dirty-day window is a merge and must not lose the `processedRevision` the
  // metrics phase compares against.
  const db = new FakeFirestore();
  db.seed(DOC, {fromAnEarlierShape: true, sales: 1});

  db.doc(DOC).set({sales: 2}, {merge: true});
  assert.deepEqual(db.read(DOC), {fromAnEarlierShape: true, sales: 2});

  db.doc(DOC).set({sales: 3});
  assert.deepEqual(db.read(DOC), {sales: 3});
});

test("create refuses a document that already exists", () => {
  // `createManualJobInTransaction` creates the reconciliation job document, and
  // that is the whole of its idempotency: two operators asking for the same run,
  // or one request retried, must be refused rather than have the second silently
  // replace a job already part-way through its phases. A double that accepted the
  // second create would reset a running job's cursors and counters in a test that
  // then reported success.
  const db = new FakeFirestore();

  db.doc(DOC).create({status: "queued", revision: 0});
  assert.deepEqual(db.read(DOC), {status: "queued", revision: 0});

  assert.throws(() => db.doc(DOC).create({status: "queued", revision: 0}), /ALREADY_EXISTS/);
  db.doc(DOC).update({revision: 4});
  assert.throws(() => db.doc(DOC).create({status: "queued", revision: 0}), /ALREADY_EXISTS/);
  assert.equal(db.read(DOC)?.revision, 4);
});

test("create carries a replace's sentinel rules, not a merge's", () => {
  // The exact shape of the defect the sentinel audit beside this file exists to
  // find: one payload shared between a create and an update, carrying a delete
  // sentinel that only the create rejects. It threw on every sale for as long as
  // it lived, and no compiler, linter, or pure test saw it.
  const db = new FakeFirestore();

  assert.throws(
    () => db.doc(DOC).create({status: "queued", leaseToken: FieldValue.delete()}),
    /Firestore rejects FieldValue.delete\(\)/
  );
  assert.equal(db.read(DOC), undefined);

  // Everything else a create payload holds resolves as a replace's would.
  db.doc(DOC).create({attemptCount: FieldValue.increment(1), at: FieldValue.serverTimestamp()});
  assert.equal(db.read(DOC)?.attemptCount, 1);
  assert.ok(db.read(DOC)?.at instanceof Timestamp);
});

test("a create Firestore would refuse leaves the writes staged beside it unwritten", async () => {
  // A refused create is discovered while the transaction's writes are being
  // staged, after earlier writes in the same transaction have already been
  // computed. Publishing those would leave a job's side effects behind without
  // the job, which is the one outcome an all-or-nothing commit exists to prevent.
  const db = new FakeFirestore();
  db.seed(DOC, {status: "running"});

  await assert.rejects(db.runTransaction(async (transaction) => {
    transaction.set(db.doc("tenants/tenant-a/things/thing-2"), {enqueued: true});
    transaction.create(db.doc(DOC), {status: "queued"});
  }), /ALREADY_EXISTS/);

  assert.equal(db.read("tenants/tenant-a/things/thing-2"), undefined);
  assert.equal(db.read(DOC)?.status, "running");
  assert.deepEqual(db.writes, []);
});

test("update refuses a document that does not exist", () => {
  // `regenerateDailyMetric` and `verifyShiftExpectation` both `update` a document
  // they read earlier in the same transaction. A double that created one instead
  // would hide a processor updating something it only assumed was there.
  const db = new FakeFirestore();

  assert.throws(() => db.doc(DOC).update({status: "clean"}), /NOT_FOUND/);
  db.seed(DOC, {status: "dirty"});
  db.doc(DOC).update({status: "clean"});
  assert.equal(db.read(DOC)?.status, "clean");
});

test("a transaction commits nothing when its body throws", async () => {
  // Every processor buffers its writes and then re-checks the job lease, so this
  // is the property behind "a lease that is not current writes no part of the
  // window". If the double committed as it went, that test would pass while
  // proving the opposite.
  const db = new FakeFirestore();
  const failure = new Error("the lease is no longer current");

  await assert.rejects(db.runTransaction(async (transaction) => {
    transaction.set(db.doc(DOC), {written: true});
    throw failure;
  }), failure);

  assert.equal(db.read(DOC), undefined);
  assert.deepEqual(db.writes, []);
});

test("a transaction refuses a read after its first write", async () => {
  const db = new FakeFirestore();

  await assert.rejects(db.runTransaction(async (transaction) => {
    transaction.set(db.doc(DOC), {written: true});
    await transaction.get(db.doc(DOC));
  }), /refuses a read after the first write/);
});

test("a transaction's own writes are invisible to it until it commits", async () => {
  const db = new FakeFirestore();
  db.seed(DOC, {status: "dirty"});

  const seen = await db.runTransaction(async (transaction) => {
    const [before] = await transaction.getAll(db.doc(DOC));
    transaction.set(db.doc(DOC), {status: "clean"}, {merge: true});
    return before.get("status");
  });

  assert.equal(seen, "dirty");
  assert.equal(db.read(DOC)?.status, "clean");
});

test("a document with no value at an ordered field is not returned", async () => {
  // The reason the ledger cursor query cannot see a stock movement that has no
  // `recordedAt`: `reconcileProduct` orders by it. A double that returned such a
  // movement would let a test assert on an invalid-movement count Firestore
  // could never produce that way.
  const db = new FakeFirestore();
  db.seed("tenants/tenant-a/movements/mv_1", {
    recordedAt: Timestamp.fromMillis(1_000),
    quantityDelta: -1,
  });
  db.seed("tenants/tenant-a/movements/mv_2", {quantityDelta: -1});

  const ordered = await db.collection("tenants/tenant-a/movements")
    .orderBy("recordedAt")
    .get();
  assert.deepEqual(ordered.docs.map((document) => document.id), ["mv_1"]);

  // Unordered, both are there - so the exclusion is the sort's doing and not a
  // fixture that failed to be written.
  const all = await db.collection("tenants/tenant-a/movements").get();
  assert.deepEqual(all.docs.map((document) => document.id), ["mv_1", "mv_2"]);
});

test("an equality filter excludes a document that has no such field", async () => {
  const db = new FakeFirestore();
  db.seed("tenants/tenant-a/days/2026-08-01", {status: "dirty"});
  db.seed("tenants/tenant-a/days/2026-08-02", {status: "clean"});
  db.seed("tenants/tenant-a/days/2026-08-03", {});

  const dirty = await db.collection("tenants/tenant-a/days")
    .where("status", "==", "dirty")
    .get();
  assert.deepEqual(dirty.docs.map((document) => document.id), ["2026-08-01"]);
  assert.equal(dirty.empty, false);
  assert.equal(dirty.size, 1);
});

test("startAfter skips exactly the documents at or before the cursor", async () => {
  // The two-key cursor `reconcileProduct` resumes a movement backlog from, and
  // the descending single-key read it establishes a baseline with.
  const db = new FakeFirestore();
  const at = (millis: number): Timestamp => Timestamp.fromMillis(millis);
  for (const [id, millis] of [
    ["mv_a", 1_000],
    ["mv_b", 2_000],
    ["mv_c", 2_000],
    ["mv_d", 3_000],
  ] as const) {
    db.seed(`tenants/tenant-a/movements/${id}`, {recordedAt: at(millis)});
  }
  const movements = db.collection("tenants/tenant-a/movements");

  const ascending = await movements
    .orderBy("recordedAt", "asc")
    .orderBy(FieldPath.documentId(), "asc")
    .startAfter(at(2_000), "mv_b")
    .get();
  // `mv_c` shares the instant and sorts after by ID, so a cursor that compared
  // only the timestamp would drop it.
  assert.deepEqual(ascending.docs.map((document) => document.id), ["mv_c", "mv_d"]);

  const descending = await movements
    .orderBy("recordedAt", "desc")
    .orderBy(FieldPath.documentId(), "desc")
    .limit(1)
    .get();
  assert.deepEqual(descending.docs.map((document) => document.id), ["mv_d"]);
});

test("a page is bounded and ordered by document ID whatever order it was written in", async () => {
  const db = new FakeFirestore();
  for (const id of ["product-03", "product-01", "product-04", "product-02"]) {
    db.seed(`tenants/tenant-a/products/${id}`, {quantity: 1});
  }

  const page = await db.collection("tenants/tenant-a/products")
    .orderBy(FieldPath.documentId())
    .limit(2)
    .get();

  assert.deepEqual(page.docs.map((document) => document.id), ["product-01", "product-02"]);
  assert.deepEqual(
    db.ids("tenants/tenant-a/products"),
    ["product-01", "product-02", "product-03", "product-04"]
  );
});

test("what the double will not do, it refuses rather than ignores", () => {
  // The one thing a Firestore double must never do is answer a question it was
  // not asked. A dropped `where` clause, a misread sentinel, or a silently
  // reversed sort would each turn a processor defect into a green test.
  const db = new FakeFirestore();
  const products = db.collection("tenants/tenant-a/products");

  assert.throws(() => products.where("quantity", ">=", 1), /only "==" filters/);
  assert.throws(() => products.orderBy(new FieldPath("a", "b")), /FieldPath.documentId\(\)/);
  assert.throws(() => products.orderBy("nested.field"), /nested field path/);
  assert.throws(() => products.orderBy("quantity", "ascending"), /not a Firestore sort direction/);
  assert.throws(() => products.limit(0), /not a positive integer/);
  assert.throws(
    () => db.doc(DOC).set({tags: FieldValue.arrayUnion("a")}),
    /does not support FieldValue.arrayUnion/
  );
  assert.throws(() => db.doc("tenants/tenant-a/products"), /not a Firestore document path/);
  assert.throws(() => db.collection("tenants/tenant-a/products/product-01"), /collection path/);
});

test("an unorderable value stops the query instead of sorting by luck", () => {
  const db = new FakeFirestore();
  db.seed("tenants/tenant-a/movements/mv_1", {recordedAt: Timestamp.fromMillis(1)});
  db.seed("tenants/tenant-a/movements/mv_2", {recordedAt: {seconds: 2}});

  assert.throws(
    () => db.collection("tenants/tenant-a/movements").orderBy("recordedAt").get(),
    /cannot order a value/
  );
});

test("a snapshot is a copy, so a test cannot write to the store by reading it", async () => {
  const db = new FakeFirestore();
  db.seed(DOC, {nested: {quantity: 1}});

  const read = db.read(DOC) as {nested: {quantity: number}};
  read.nested.quantity = 99;
  const snapshot = await db.doc(DOC).get();
  const data = snapshot.data() as {nested: {quantity: number}};
  data.nested.quantity = 98;

  assert.deepEqual(db.read(DOC), {nested: {quantity: 1}});
  assert.deepEqual(snapshot.get("nested"), {quantity: 1});
});
