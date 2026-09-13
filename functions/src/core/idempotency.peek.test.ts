import assert from "node:assert/strict";
import test from "node:test";

import {FakeFirestore} from "../testing/fakeFirestore";
import {
  buildIdempotencyIdentity,
  fingerprintPayload,
  lookupIdempotentResult,
} from "./idempotency";

/**
 * The record `runIdempotentFirestoreTransaction` writes, at the path it writes it.
 *
 * Built from the same exported helpers the transaction uses rather than from a
 * literal, so a change to either derivation fails this test instead of leaving it
 * quietly asserting against a path nothing writes any more.
 */
function seedCompletedRecord(
  db: FakeFirestore,
  options: {
    actorUid: string;
    operation: string;
    tenantId?: string;
    requestId: string;
    input: unknown;
    result: unknown;
    status?: string;
  }
): void {
  const identity = buildIdempotencyIdentity(
    options.actorUid,
    options.operation,
    options.tenantId,
    options.requestId
  );
  db.seed(`operation_idempotency/${identity.documentId}`, {
    actorUid: options.actorUid,
    operation: options.operation,
    scope: identity.scope,
    requestId: options.requestId,
    inputHash: fingerprintPayload(options.input),
    status: options.status ?? "completed",
    result: options.result,
  });
}

const baseline = {
  actorUid: "user-1",
  operation: "changeSignupEmail",
  requestId: "profile-request-1",
  input: {email: "owner@example.com"},
};

test("a completed record under the same request and input is returned", async () => {
  const db = new FakeFirestore();
  seedCompletedRecord(db, {...baseline, result: {email: "owner@example.com"}});

  const replayed = await lookupIdempotentResult(db.asFirestore(), baseline);

  assert.deepEqual(replayed, {email: "owner@example.com"});
});

test("no record at all is undefined rather than a throw", async () => {
  const db = new FakeFirestore();

  assert.equal(await lookupIdempotentResult(db.asFirestore(), baseline), undefined);
});

test("a record whose input has moved is undefined, not an error", async () => {
  // The transaction raises `already-exists` for this. Raising it here too is how
  // the two would come to disagree, so the peek declines to answer and lets the
  // transaction be the one that refuses.
  const db = new FakeFirestore();
  seedCompletedRecord(db, {
    ...baseline,
    input: {email: "somebody-else@example.com"},
    result: {email: "somebody-else@example.com"},
  });

  assert.equal(await lookupIdempotentResult(db.asFirestore(), baseline), undefined);
});

test("an incomplete record is undefined, so the work is not skipped", async () => {
  const db = new FakeFirestore();
  seedCompletedRecord(db, {
    ...baseline,
    result: {email: "owner@example.com"},
    status: "in_progress",
  });

  assert.equal(await lookupIdempotentResult(db.asFirestore(), baseline), undefined);
});

test("another actor's record is never read as this actor's replay", async () => {
  const db = new FakeFirestore();
  seedCompletedRecord(db, {
    ...baseline,
    actorUid: "user-2",
    result: {email: "owner@example.com"},
  });

  assert.equal(await lookupIdempotentResult(db.asFirestore(), baseline), undefined);
});

test("a different request id under the same actor is a different attempt", async () => {
  const db = new FakeFirestore();
  seedCompletedRecord(db, {
    ...baseline,
    requestId: "profile-request-2",
    result: {email: "owner@example.com"},
  });

  assert.equal(await lookupIdempotentResult(db.asFirestore(), baseline), undefined);
});

test("the peek reads nothing and writes nothing", async () => {
  const db = new FakeFirestore();
  seedCompletedRecord(db, {...baseline, result: {email: "owner@example.com"}});
  db.clearWrites();

  await lookupIdempotentResult(db.asFirestore(), baseline);

  assert.deepEqual(db.writes, []);
});
