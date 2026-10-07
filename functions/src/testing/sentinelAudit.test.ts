import assert from "node:assert/strict";
import test from "node:test";
import {
  auditDeleteSentinels,
  classifyDeleteSentinels,
  illegalSentinelSites,
} from "./sentinelAudit";

/**
 * Payload builders that hold a `FieldValue.delete()` somewhere other than inside
 * the write that performs it, each with the write kind its call sites actually
 * use. A sentinel like this is legal or fatal depending on code elsewhere in the
 * file, which is precisely the arrangement that made `mergeSaleReconciliationJob`
 * throw on every sale ever rung up, so each one is listed deliberately rather
 * than tolerated.
 *
 * Adding a new one is a decision, not an accident: the second test below fails
 * until it appears here, which is the moment somebody has to go and look at
 * where the payload is actually written.
 *
 * This list, not the flat "reaches a rejecting write" assertion, is what closes
 * off the defect class. Confirmed by putting a sentinel back into
 * `mirrorCreateData`: the flat assertion still passed, because a payload built
 * away from its write is exactly what the original defect was, and only this
 * list noticed a new builder had appeared.
 */
const REVIEWED_PAYLOAD_BUILDERS: readonly {key: string; because: string}[] = [
  {
    key: "emailReceipts/deliveries.ts#sent",
    because: "Clears the existing delivery's lease after sending. Both the " +
      "primary transaction.update(ref, sent) and fallback ref.update(sent) " +
      "support delete sentinels; neither creates or replaces a document.",
  },
  {
    key: "whatsapp/deliveries.ts#sent",
    because: "Clears the existing delivery's lease after sending. Both the " +
      "primary transaction.update(ref, sent) and fallback ref.update(sent) " +
      "support delete sentinels; neither creates or replaces a document.",
  },
  {
    key: "customers/credit.ts#balanceFields",
    because: "Moves an existing customer's balance, so every caller spreads it " +
      "into `transaction.update` on a customer the transaction just read. A " +
      "credit sale, a return and a repayment all need the customer to exist.",
  },
  {
    key: "reconciliation/jobs.ts#saleTriggerJobFields",
    because: "Returns the create and update payloads separately, and only the " +
      "update half carries the cursor-clearing sentinels. Pinned by jobs.test.ts.",
  },
  {
    key: "reconciliation/jobs.ts#advanceReconciliationJob",
    because: "Builds one `update` object and hands it to `transaction.update`. " +
      "It has no create branch.",
  },
  {
    key: "repair/membershipMirrorStore.ts#mirrorUpdateData",
    because: "The update half of `mirrorWriteFields`. The create half is a " +
      "separate function that cannot express a sentinel. Pinned by " +
      "membershipMirrorStore.test.ts.",
  },
  {
    key: "repair/membershipMirrorStore.ts#progressData",
    because: "All eleven of its call sites are `update(...)`; a repair run " +
      "document is created by `initialRunData`, which carries no sentinel.",
  },
];

test("no FieldValue.delete() reaches a write that rejects it", () => {
  // The whole defect class in one assertion. Firestore refuses a sentinel in
  // `create()` and in `set()` without `{merge: true}`, and refuses it at
  // serialization time - so the payload compiles, type-checks, passes every pure
  // test, and then throws forever against the real thing. Short of a deploy,
  // reading the source is the only way to close this off.
  const illegal = illegalSentinelSites(auditDeleteSentinels()).map(
    (site) => `${site.file}:${site.line} (${site.verdict})`
  );

  assert.deepEqual(illegal, []);
});

test("every payload built away from its write has been classified", () => {
  const found = [...new Set(
    auditDeleteSentinels()
      .filter((site) => site.verdict === "unattached")
      .map((site) => `${site.file}#${site.owner}`)
  )].sort();

  assert.deepEqual(
    found,
    REVIEWED_PAYLOAD_BUILDERS.map((entry) => entry.key).sort()
  );
  for (const entry of REVIEWED_PAYLOAD_BUILDERS) {
    assert.ok(entry.because.length > 40, entry.key);
  }
});

test("the audit reaches the whole source tree", () => {
  // A scanner that quietly read nothing would make both assertions above pass
  // for the worst possible reason.
  const sites = auditDeleteSentinels();
  const files = new Set(sites.map((site) => site.file));

  assert.ok(sites.length > 100, `only ${sites.length} sentinel sites found`);
  assert.ok(files.size > 10, `only ${files.size} files carried one`);
  // Test files and the audit's own support code are skipped on purpose, so every
  // site it reports is one a deployed function can really write.
  for (const file of files) {
    assert.equal(file.endsWith(".test.ts"), false, file);
    assert.equal(file.startsWith("testing/"), false, file);
  }
});

test("the classifier tells the four write kinds apart", () => {
  // The guard above is only worth its runtime if this holds, and the only honest
  // way to show it is source the classifier has never seen.
  const verdicts = classifyDeleteSentinels(`
    function writes(transaction: Transaction, ref: DocumentReference) {
      transaction.update(ref, {a: FieldValue.delete()});
      transaction.set(ref, {b: FieldValue.delete()}, {merge: true});
      transaction.set(ref, {c: FieldValue.delete()});
      transaction.create(ref, {d: FieldValue.delete()});
    }
  `).map((site) => site.verdict);

  assert.deepEqual(verdicts, ["update", "set_merge", "set_without_merge", "create"]);
});

test("the classifier ignores a sentinel that is only talked about", () => {
  // `FieldValue.delete()` is named in the comments and doc strings of the very
  // functions this audit covers, including the one whose defect started it.
  const sites = classifyDeleteSentinels(`
    // A create payload must never carry FieldValue.delete().
    /** Nor may FieldValue.delete() appear in a doc comment's create example. */
    const message = "transaction.create(ref, {a: FieldValue.delete()})";
    function real(ref: DocumentReference) {
      ref.create({a: FieldValue.delete()});
    }
  `);

  assert.deepEqual(sites.map((site) => site.verdict), ["create"]);
  assert.deepEqual(sites.map((site) => site.owner), ["real"]);
});

test("a payload built away from its write is reported unattached, with its owner", () => {
  // The shape of the original defect, and the reason `owner` exists: the reviewed
  // list needs keys that survive an edit anywhere above them.
  const sites = classifyDeleteSentinels(`
    function requeueFields(status: string): DocumentData {
      return {
        ...(status === "queued" ? {cursor: FieldValue.delete()} : {}),
      };
    }
  `);

  assert.deepEqual(sites, [
    {file: "<memory>", line: 4, verdict: "unattached", owner: "requeueFields"},
  ]);
});

test("a name is not stolen by a parameter's inline type or a preceding statement", () => {
  // Both mistakes the owner scan actually made. `progressData`'s own parameter
  // type is an object literal, and `advanceReconciliationJob` declares a `const
  // update = {...}` several statements before the sentinel it reports.
  const sites = classifyDeleteSentinels(`
    function progressData(options: {phase: string; done: boolean}): DocumentData {
      return {cursor: FieldValue.delete()};
    }
    function advance(db: Firestore) {
      return db.runTransaction(async (transaction) => {
        const update: DocumentData = {status: "queued"};
        if (update.status === "queued") {
          update.cursor = FieldValue.delete();
        }
        transaction.update(ref, update);
      });
    }
  `);

  assert.deepEqual(sites.map((site) => site.owner), ["progressData", "advance"]);
});
