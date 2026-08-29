import assert from "node:assert/strict";
import test from "node:test";

import {AuthBlockingEvent} from "firebase-functions/v2/identity";

import {FakeFirestore} from "../testing/fakeFirestore";
import {ensureRootUser, prepareSelfSignupRoot} from "./identityBootstrap";

function event(data: Record<string, unknown> | undefined): AuthBlockingEvent {
  return {data} as unknown as AuthBlockingEvent;
}

test("a self-signup is prepared as an active tenant identity", () => {
  const prepared = prepareSelfSignupRoot(
    event({uid: "user-a", email: "Owner@Example.COM", displayName: "  Ada  "})
  );

  assert.equal(prepared.email, "owner@example.com");
  assert.equal(prepared.displayName, "Ada");
  assert.equal(prepared.accountType, "tenant_user");
  // The value the model declared and nothing ever wrote until now.
  assert.equal(prepared.identityOrigin, "self_signup");
  assert.equal(prepared.globalStatus, "active");
  // A member of nothing yet. `requestTenant` is the next step.
  assert.equal(prepared.membershipCount, 0);
  assert.equal(prepared.ownedTenantCount, 0);
  assert.equal(prepared.ownedActiveTenantCount, 0);
});

test("a blank display name is left off rather than stored empty", () => {
  const prepared = prepareSelfSignupRoot(
    event({uid: "user-a", email: "owner@example.com", displayName: "   "})
  );

  assert.equal("displayName" in prepared, false);
});

test("an account with no usable email is refused at creation", () => {
  // Throwing here aborts the account creation itself, which is the whole
  // reason this is a blocking function: no identity is left behind.
  for (const data of [
    {uid: "user-a"},
    {uid: "user-a", email: ""},
    {uid: "user-a", email: "   "},
    {uid: "user-a", email: 42},
  ]) {
    assert.throws(() => prepareSelfSignupRoot(event(data)), /email address/);
  }
});

test("the root document is created once, with server timestamps", async () => {
  const db = new FakeFirestore();
  const prepared = prepareSelfSignupRoot(
    event({uid: "user-a", email: "owner@example.com"})
  );

  const created = await ensureRootUser(db.asFirestore(), "user-a", prepared);

  assert.equal(created, true);
  const stored = await db.collection("users").doc("user-a").get();
  assert.equal(stored.exists, true);
  assert.equal(stored.data()?.identityOrigin, "self_signup");
  assert.equal(stored.data()?.accountType, "tenant_user");
  assert.notEqual(stored.data()?.createdAt, undefined);
  assert.notEqual(stored.data()?.updatedAt, undefined);
});

test("a second firing is a no-op rather than a rewrite", async () => {
  // Blocking functions are not expected to fire twice, but a retry of a
  // blocked creation is a case that needs an answer - and the same
  // create-if-absent is what keeps this safe beside the invitation path.
  const db = new FakeFirestore();
  const prepared = prepareSelfSignupRoot(
    event({uid: "user-a", email: "owner@example.com"})
  );

  assert.equal(await ensureRootUser(db.asFirestore(), "user-a", prepared), true);
  db.clearWrites();
  assert.equal(await ensureRootUser(db.asFirestore(), "user-a", prepared), false);

  assert.deepEqual(db.writes, []);
});

test("an invited member's root document is never rewritten as a self-signup", async () => {
  // The case this exists to be safe about: `identityOrigin` records how an
  // identity came to exist, and overwriting `staff_invitation` with
  // `self_signup` would lose that permanently.
  const db = new FakeFirestore();
  await db
    .collection("users")
    .doc("user-a")
    .set({
      email: "invited@example.com",
      accountType: "tenant_user",
      identityOrigin: "staff_invitation",
      globalStatus: "active",
      membershipCount: 1,
    });
  db.clearWrites();

  const created = await ensureRootUser(
    db.asFirestore(),
    "user-a",
    prepareSelfSignupRoot(event({uid: "user-a", email: "invited@example.com"}))
  );

  assert.equal(created, false);
  const stored = await db.collection("users").doc("user-a").get();
  assert.equal(stored.data()?.identityOrigin, "staff_invitation");
  assert.equal(stored.data()?.membershipCount, 1);
  assert.deepEqual(db.writes, []);
});
