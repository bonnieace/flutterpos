import assert from "node:assert/strict";
import test from "node:test";
import {Auth} from "firebase-admin/auth";
import {HttpsError} from "firebase-functions/v2/https";
import {provisionalStaffUid} from "./identityProvisioning";
import {
  resolveOrCreateAuthIdentity,
  writePreparedRoot,
} from "./shared";

function authUser(uid: string, email = "person@example.com") {
  return {
    uid,
    email,
    displayName: "Person",
    emailVerified: false,
    disabled: false,
    customClaims: {},
  };
}

test("provisional staff UIDs are deterministic, bounded, and operation-specific", () => {
  const first = provisionalStaffUid("operation-a");
  assert.equal(first, provisionalStaffUid("operation-a"));
  assert.notEqual(first, provisionalStaffUid("operation-b"));
  assert.match(first, /^staff_[A-Za-z0-9_-]{28}$/);
  assert.ok(first.length <= 128);
});

test("Auth creation uses the pre-reserved UID", async () => {
  let createdUid = "";
  const auth = {
    async getUserByEmail() {
      throw {code: "auth/user-not-found"};
    },
    async createUser(input: {uid?: string}) {
      createdUid = input.uid ?? "";
      return authUser(createdUid);
    },
  } as unknown as Auth;
  const identity = await resolveOrCreateAuthIdentity(
    "person@example.com",
    "Person",
    "staff_reserved_uid",
    auth
  );
  assert.equal(createdUid, "staff_reserved_uid");
  assert.equal(identity.uid, "staff_reserved_uid");
  assert.equal(identity.newlyCreated, true);
});

test("a crash-resumed reserved UID remains operation-owned", async () => {
  const auth = {
    async getUserByEmail() {
      return authUser("staff_reserved_uid");
    },
  } as unknown as Auth;
  const identity = await resolveOrCreateAuthIdentity(
    "person@example.com",
    "Person",
    "staff_reserved_uid",
    auth
  );
  assert.equal(identity.newlyCreated, true);
});

test("negative membership deltas cannot create a root", () => {
  const transaction = {create() {
    assert.fail("create must not be called");
  }};
  assert.throws(() => writePreparedRoot(
    transaction as never,
    {} as never,
    {
      create: true,
      user: {accountType: "tenant_user", globalStatus: "active"},
    },
    -1
  ), (error: unknown) => error instanceof HttpsError &&
    error.code === "failed-precondition");
});
