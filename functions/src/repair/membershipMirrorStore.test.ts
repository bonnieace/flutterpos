import assert from "node:assert/strict";
import test from "node:test";
import {DocumentData, Timestamp} from "firebase-admin/firestore";
import {deleteSentinelPaths} from "../testing/writeSentinels";
import {
  membershipRepairRetryDelayMilliseconds,
  mirrorWriteFields,
} from "./membershipMirrorStore";

test("membership repair retries back off and remain bounded", () => {
  assert.equal(membershipRepairRetryDelayMilliseconds(1), 30_000);
  assert.equal(membershipRepairRetryDelayMilliseconds(2), 60_000);
  assert.equal(membershipRepairRetryDelayMilliseconds(11), 6 * 60 * 60 * 1000);
  assert.equal(membershipRepairRetryDelayMilliseconds(100), 6 * 60 * 60 * 1000);
  assert.equal(membershipRepairRetryDelayMilliseconds(Number.NaN), 30_000);
});

const CREATED_AT = Timestamp.fromMillis(1785000000000);
const JOINED_AT = Timestamp.fromMillis(1785600000000);

function decision(overrides: {
  membershipStatus?: "active" | "inactive";
  invitationStatus?: string;
} = {}) {
  return {
    action: "upsert" as const,
    tenantId: "tenant-a",
    issues: [],
    value: {
      tenantId: "tenant-a",
      tenantName: "Chill Tent",
      tenantSlug: "chill-tent",
      role: "cashier" as const,
      membershipStatus: overrides.membershipStatus ?? "active",
      tenantStatus: "active" as const,
      ...(overrides.invitationStatus === undefined ?
        {} : {invitationStatus: overrides.invitationStatus}),
      isOwner: false,
      mirrorVersion: 3,
    },
  };
}

test("a mirror that does not exist is created without any delete sentinel", () => {
  // The regression guard for this payload. It is shared between a `create` and
  // an `update` branch, which is the shape that made `mergeSaleReconciliationJob`
  // throw on every sale: Firestore rejects a sentinel in `create()` and nothing
  // short of a real write says so.
  for (const membershipStatus of ["active", "inactive"] as const) {
    const write = mirrorWriteFields(
      decision({membershipStatus}),
      {createdAt: CREATED_AT, joinedAt: JOINED_AT},
      undefined
    );
    assert.equal(write.kind, "create", membershipStatus);
    assert.deepEqual(deleteSentinelPaths(write.data), [], membershipStatus);
  }
});

test("no absent invitation status can put a sentinel in the create payload", () => {
  // An absent `invitationStatus` is the one input that produces a sentinel at
  // all, so it is the input the create branch has to be asserted against.
  const write = mirrorWriteFields(
    decision({invitationStatus: undefined}),
    {},
    undefined
  );

  assert.deepEqual(deleteSentinelPaths(write.data), []);
  assert.equal("invitationStatus" in write.data, false);
});

test("a created mirror adopts canonical transport metadata", () => {
  const write = mirrorWriteFields(
    decision({invitationStatus: "pending"}),
    {createdAt: CREATED_AT, joinedAt: JOINED_AT},
    undefined
  );

  assert.equal(write.data.createdAt, CREATED_AT);
  assert.equal(write.data.joinedAt, JOINED_AT);
  assert.equal(write.data.invitationStatus, "pending");
  assert.equal(write.data.mirrorVersion, 3);
});

test("a created mirror for an inactive membership has never been joined", () => {
  // `null` rather than a missing field, because the strict client model reads
  // `joinedAt` and an absent one is not the same statement as "not joined".
  const write = mirrorWriteFields(
    decision({membershipStatus: "inactive"}),
    {createdAt: CREATED_AT, joinedAt: JOINED_AT},
    undefined
  );

  assert.equal(write.data.joinedAt, null);
});

test("an existing mirror clears an invitation status the staff record dropped", () => {
  // The update branch is where a sentinel belongs and must keep working: a
  // membership that has finished accepting no longer has an invitation status,
  // and the stale field has to go rather than linger.
  const current: DocumentData = {
    createdAt: CREATED_AT,
    joinedAt: JOINED_AT,
    invitationStatus: "pending",
  };
  const write = mirrorWriteFields(decision(), {}, current);

  assert.equal(write.kind, "update");
  assert.deepEqual(deleteSentinelPaths(write.data), ["invitationStatus"]);
});

test("an existing mirror keeps an invitation status it still has", () => {
  const write = mirrorWriteFields(
    decision({invitationStatus: "pending"}),
    {},
    {createdAt: CREATED_AT, joinedAt: JOINED_AT}
  );

  assert.deepEqual(deleteSentinelPaths(write.data), []);
  assert.equal(write.data.invitationStatus, "pending");
});

test("an existing mirror keeps usable transport metadata untouched", () => {
  const write = mirrorWriteFields(
    decision({invitationStatus: "accepted"}),
    {createdAt: Timestamp.fromMillis(1), joinedAt: Timestamp.fromMillis(2)},
    {createdAt: CREATED_AT, joinedAt: JOINED_AT}
  );

  assert.equal("createdAt" in write.data, false);
  assert.equal("joinedAt" in write.data, false);
});

test("an existing mirror repairs transport metadata that is not a timestamp", () => {
  const write = mirrorWriteFields(
    decision({invitationStatus: "accepted"}),
    {createdAt: CREATED_AT, joinedAt: JOINED_AT},
    {createdAt: "yesterday", joinedAt: 0}
  );

  assert.equal(write.data.createdAt, CREATED_AT);
  assert.equal(write.data.joinedAt, JOINED_AT);
});

test("an inactive existing membership is not given a joined timestamp", () => {
  // Only an active membership has a join date to repair; writing one for an
  // inactive record would invent a fact about when it started.
  const write = mirrorWriteFields(
    decision({membershipStatus: "inactive", invitationStatus: "accepted"}),
    {createdAt: CREATED_AT, joinedAt: JOINED_AT},
    {createdAt: CREATED_AT}
  );

  assert.equal("joinedAt" in write.data, false);
});
