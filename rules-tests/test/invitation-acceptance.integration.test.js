import assert from "node:assert/strict";
import { after, before, test } from "node:test";

import { deleteApp, initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore, Timestamp } from "firebase-admin/firestore";

import { createInvitationProof } from
  "../../functions/lib/staff/invitationProof.js";

const PROJECT_ID = "demo-multitenant-invitation-integration";
const INVITATION_SECRET =
  "local-emulator-invitation-hmac-secret-at-least-32-bytes";
const PASSWORD = "Local-emulator-password-123!";
const ACCEPTANCE_FIELDS = [
  "invitationStatus",
  "membershipStatus",
  "role",
  "tenantId",
  "uid",
];

let app;
let auth;
let firestore;

before(async () => {
  requireEmulator("FIREBASE_AUTH_EMULATOR_HOST");
  requireEmulator("FIRESTORE_EMULATOR_HOST");
  requireEmulator("FUNCTIONS_EMULATOR_HOST");
  assert.equal(process.env.GCLOUD_PROJECT, PROJECT_ID);
  app = initializeApp({ projectId: PROJECT_ID }, "invitation-integration");
  auth = getAuth(app);
  firestore = getFirestore(app);
});

after(async () => {
  if (app) await deleteApp(app);
});

test("acceptTenantInvitation consumes a real versioned proof", async () => {
  const fixture = await seedPendingInvitation({
    suffix: "token",
    emailVerified: false,
    visibleAcceptanceAllowed: false,
    tokenByte: 0x11,
  });
  const idToken = await signIn(fixture.email);

  const response = await callFunction("acceptTenantInvitation", idToken, {
    tenantId: fixture.tenantId,
    invitationVersion: fixture.invitationVersion,
    invitationToken: fixture.invitationToken,
    requestId: "token-emulator-request-1",
  });

  assertAcceptedResponse(response, fixture);
  await assertAcceptedDocuments(fixture, "token");
});

test("acceptVisibleTenantInvitation returns the same five-field contract", async () => {
  const fixture = await seedPendingInvitation({
    suffix: "visible",
    emailVerified: true,
    visibleAcceptanceAllowed: true,
    tokenByte: 0x22,
  });
  const idToken = await signIn(fixture.email);

  const response = await callFunction(
    "acceptVisibleTenantInvitation",
    idToken,
    {
      tenantId: fixture.tenantId,
      requestId: "visible-emulator-request-1",
    },
  );

  assertAcceptedResponse(response, fixture);
  await assertAcceptedDocuments(fixture, "visible");
});

test("setDefaultTenant updates the authenticated user's routing profile", async () => {
  const fixture = await seedActiveMembership("default");
  const idToken = await signIn(fixture.email);

  const response = await callFunction("setDefaultTenant", idToken, {
    tenantId: fixture.tenantId,
    requestId: "default-emulator-request-1",
  });

  assert.deepEqual(Object.keys(response).sort(), [
    "defaultTenantId",
    "tenantId",
  ]);
  assert.deepEqual(response, {
    tenantId: fixture.tenantId,
    defaultTenantId: fixture.tenantId,
  });
  const root = await firestore.doc(`users/${fixture.uid}`).get();
  assert.equal(root.get("defaultTenantId"), fixture.tenantId);
  assert.ok(root.get("updatedAt") instanceof Timestamp);
});

test("requestTenant creates a pending canonical tenant and routing mirror", async () => {
  const fixture = await seedTenantApplicant("request");
  const idToken = await signIn(fixture.email);

  const response = await callFunction("requestTenant", idToken, {
    name: "  Chilltent   Emulator  ",
    slug: "CHILLTENT-EMULATOR",
    requestId: "tenant-emulator-request-1",
  });

  assert.deepEqual(Object.keys(response).sort(), [
    "name",
    "slug",
    "status",
    "tenantId",
  ]);
  assert.equal(response.name, "Chilltent Emulator");
  assert.equal(response.slug, "chilltent-emulator");
  assert.equal(response.status, "pending");
  assert.equal(typeof response.tenantId, "string");

  const [tenant, staff, mirror, slug, root] = await Promise.all([
    firestore.doc(`tenants/${response.tenantId}`).get(),
    firestore.doc(`tenants/${response.tenantId}/staff/${fixture.uid}`).get(),
    firestore
      .doc(`users/${fixture.uid}/tenant_memberships/${response.tenantId}`)
      .get(),
    firestore.doc("tenant_slugs/chilltent-emulator").get(),
    firestore.doc(`users/${fixture.uid}`).get(),
  ]);
  assert.equal(tenant.get("status"), "pending");
  assert.equal(tenant.get("ownerUid"), fixture.uid);
  assert.equal(staff.get("uid"), fixture.uid);
  assert.equal(staff.get("role"), "owner");
  assert.equal(staff.get("status"), "active");
  assert.equal(mirror.get("tenantStatus"), "pending");
  assert.equal(mirror.get("membershipStatus"), "active");
  assert.equal(slug.get("tenantId"), response.tenantId);
  assert.equal(root.get("membershipCount"), 1);
  assert.equal(root.get("ownedTenantCount"), 1);
  assert.equal(root.get("ownedActiveTenantCount"), 0);
});

test("setTenantLifecycle approves a pending tenant with an exact contract", async () => {
  const fixture = await seedPendingTenantReview("approve");
  const idToken = await signIn(fixture.platformEmail);

  const response = await callFunction("setTenantLifecycle", idToken, {
    tenantId: fixture.tenantId,
    status: "active",
    requestId: "lifecycle-approve-emulator-request-1",
  });

  assertLifecycleResponse(response, fixture.tenantId, "active");
  const [tenant, mirror, owner, fanout] = await Promise.all([
    firestore.doc(`tenants/${fixture.tenantId}`).get(),
    firestore
      .doc(`users/${fixture.ownerUid}/tenant_memberships/${fixture.tenantId}`)
      .get(),
    firestore.doc(`users/${fixture.ownerUid}`).get(),
    firestore
      .doc(
        `tenants/${fixture.tenantId}/membership_fanout_jobs/` +
          response.fanoutOperationId,
      )
      .get(),
  ]);
  assert.equal(tenant.get("status"), "active");
  assert.equal(mirror.get("tenantStatus"), "active");
  assert.equal(owner.get("ownedActiveTenantCount"), 1);
  assert.equal(fanout.get("status"), "pending");
  assert.equal(fanout.get("toStatus"), "active");
});

test("setTenantLifecycle rejects a pending tenant and records the reason", async () => {
  const fixture = await seedPendingTenantReview("reject");
  const idToken = await signIn(fixture.platformEmail);

  const response = await callFunction("setTenantLifecycle", idToken, {
    tenantId: fixture.tenantId,
    status: "rejected",
    reason: "Owner documentation could not be verified.",
    requestId: "lifecycle-reject-emulator-request-1",
  });

  assertLifecycleResponse(response, fixture.tenantId, "rejected");
  const [tenant, mirror, audit] = await Promise.all([
    firestore.doc(`tenants/${fixture.tenantId}`).get(),
    firestore
      .doc(`users/${fixture.ownerUid}/tenant_memberships/${fixture.tenantId}`)
      .get(),
    firestore.doc(`platform_audit_logs/${response.fanoutOperationId}`).get(),
  ]);
  assert.equal(tenant.get("status"), "rejected");
  assert.equal(mirror.get("tenantStatus"), "rejected");
  assert.equal(audit.get("reason"), "Owner documentation could not be verified.");
  assert.equal(audit.get("fromStatus"), "pending");
  assert.equal(audit.get("toStatus"), "rejected");
});

test("setTenantLifecycle suspends and reactivates an active tenant", async () => {
  const fixture = await seedPendingTenantReview("manage", "active");
  const idToken = await signIn(fixture.platformEmail);

  const suspended = await callFunction("setTenantLifecycle", idToken, {
    tenantId: fixture.tenantId,
    status: "suspended",
    reason: "Repeated compliance failures.",
    requestId: "lifecycle-suspend-emulator-request-1",
  });
  assertLifecycleResponse(
    suspended,
    fixture.tenantId,
    "suspended",
    "active",
  );
  let [tenant, mirror, owner, audit] = await Promise.all([
    firestore.doc(`tenants/${fixture.tenantId}`).get(),
    firestore
      .doc(`users/${fixture.ownerUid}/tenant_memberships/${fixture.tenantId}`)
      .get(),
    firestore.doc(`users/${fixture.ownerUid}`).get(),
    firestore.doc(`platform_audit_logs/${suspended.fanoutOperationId}`).get(),
  ]);
  assert.equal(tenant.get("status"), "suspended");
  assert.equal(mirror.get("tenantStatus"), "suspended");
  assert.equal(owner.get("ownedActiveTenantCount"), 0);
  assert.equal(audit.get("reason"), "Repeated compliance failures.");

  const reactivated = await callFunction("setTenantLifecycle", idToken, {
    tenantId: fixture.tenantId,
    status: "active",
    requestId: "lifecycle-reactivate-emulator-request-1",
  });
  assertLifecycleResponse(
    reactivated,
    fixture.tenantId,
    "active",
    "suspended",
  );
  [tenant, mirror, owner, audit] = await Promise.all([
    firestore.doc(`tenants/${fixture.tenantId}`).get(),
    firestore
      .doc(`users/${fixture.ownerUid}/tenant_memberships/${fixture.tenantId}`)
      .get(),
    firestore.doc(`users/${fixture.ownerUid}`).get(),
    firestore.doc(`platform_audit_logs/${reactivated.fanoutOperationId}`).get(),
  ]);
  assert.equal(tenant.get("status"), "active");
  assert.equal(mirror.get("tenantStatus"), "active");
  assert.equal(owner.get("ownedActiveTenantCount"), 1);
  assert.equal(audit.get("reason"), null);
});

test("setTenantLifecycle archives a rejected tenant with exact persisted state", async () => {
  const fixture = await seedPendingTenantReview("archive", "rejected");
  const idToken = await signIn(fixture.platformEmail);

  const response = await callFunction("setTenantLifecycle", idToken, {
    tenantId: fixture.tenantId,
    status: "archived",
    reason: "The rejected application is closed permanently.",
    requestId: "lifecycle-archive-emulator-request-1",
  });
  assertLifecycleResponse(
    response,
    fixture.tenantId,
    "archived",
    "rejected",
  );
  const [tenant, mirror, owner, fanout, audit] = await Promise.all([
    firestore.doc(`tenants/${fixture.tenantId}`).get(),
    firestore
      .doc(`users/${fixture.ownerUid}/tenant_memberships/${fixture.tenantId}`)
      .get(),
    firestore.doc(`users/${fixture.ownerUid}`).get(),
    firestore
      .doc(
        `tenants/${fixture.tenantId}/membership_fanout_jobs/` +
          response.fanoutOperationId,
      )
      .get(),
    firestore.doc(`platform_audit_logs/${response.fanoutOperationId}`).get(),
  ]);
  assert.equal(tenant.get("status"), "archived");
  assert.equal(mirror.get("tenantStatus"), "archived");
  assert.equal(owner.get("ownedTenantCount"), 0);
  assert.equal(owner.get("ownedActiveTenantCount"), 0);
  assert.equal(fanout.get("status"), "pending");
  assert.equal(fanout.get("fromStatus"), "rejected");
  assert.equal(fanout.get("toStatus"), "archived");
  assert.equal(audit.get("reason"), "The rejected application is closed permanently.");
  assert.equal(audit.get("fromStatus"), "rejected");
  assert.equal(audit.get("toStatus"), "archived");
});

function requireEmulator(name) {
  const value = process.env[name];
  if (!value || !/^127\.0\.0\.1:\d+$/.test(value)) {
    throw new Error(`${name} must target a local emulator, received ${value}`);
  }
}

async function seedPendingInvitation({
  suffix,
  emailVerified,
  visibleAcceptanceAllowed,
  tokenByte,
}) {
  const uid = `user-${suffix}`;
  const ownerUid = `owner-${suffix}`;
  const tenantId = `tenant-${suffix}`;
  const email = `${suffix}@integration.example.test`;
  const invitationVersion = 4;
  await auth.createUser({
    uid,
    email,
    password: PASSWORD,
    emailVerified,
    disabled: false,
  });
  const proof = createInvitationProof(
    { tenantId, uid, invitedEmail: email, invitationVersion },
    INVITATION_SECRET,
    Buffer.alloc(32, tokenByte),
  );
  const now = Timestamp.now();
  const expiresAt = Timestamp.fromMillis(now.toMillis() + 60 * 60 * 1000);
  const batch = firestore.batch();
  batch.set(firestore.doc(`users/${uid}`), {
    email,
    accountType: "tenant_user",
    identityOrigin: "staff_invitation",
    globalStatus: "active",
    membershipCount: 1,
    ownedTenantCount: 0,
    ownedActiveTenantCount: 0,
    createdAt: now,
    updatedAt: now,
  });
  batch.set(firestore.doc(`users/${ownerUid}`), {
    email: `${ownerUid}@integration.example.test`,
    accountType: "tenant_user",
    identityOrigin: "self_signup",
    globalStatus: "active",
    membershipCount: 1,
    ownedTenantCount: 1,
    ownedActiveTenantCount: 1,
    createdAt: now,
    updatedAt: now,
  });
  batch.set(firestore.doc(`tenants/${tenantId}`), {
    name: `Business ${suffix}`,
    slug: tenantId,
    ownerUid,
    status: "active",
    createdAt: now,
    updatedAt: now,
  });
  batch.set(firestore.doc(`tenants/${tenantId}/staff/${ownerUid}`), {
    uid: ownerUid,
    role: "owner",
    status: "active",
    invitationStatus: "accepted",
    createdAt: now,
    joinedAt: now,
    updatedAt: now,
  });
  batch.set(firestore.doc(`tenants/${tenantId}/staff/${uid}`), {
    uid,
    email,
    name: `Invited ${suffix}`,
    phone: "",
    role: "cashier",
    status: "pending",
    invitationStatus: "sent",
    createdAt: now,
    joinedAt: null,
    updatedAt: now,
  });
  batch.set(
    firestore.doc(`users/${uid}/tenant_memberships/${tenantId}`),
    {
      tenantId,
      tenantName: `Business ${suffix}`,
      tenantSlug: tenantId,
      role: "cashier",
      membershipStatus: "pending",
      tenantStatus: "active",
      invitationStatus: "sent",
      isOwner: false,
      mirrorVersion: 1,
      createdAt: now,
      joinedAt: null,
      updatedAt: now,
    },
  );
  batch.set(
    firestore.doc(`tenants/${tenantId}/staff_invitations/${uid}`),
    {
      uid,
      tenantId,
      invitationVersion,
      invitationTokenHash: proof.tokenHash,
      invitationTokenKeyVersion: proof.tokenKeyVersion,
      invitationIssuedAt: now,
      invitationExpiresAt: expiresAt,
      invitationTokenUsedAt: null,
      invitationStatus: "sent",
      invitedEmail: email,
      invitedBy: ownerUid,
      latestDeliveryId: `delivery-${suffix}`,
      visibleAcceptanceAllowed,
      createdAt: now,
      updatedAt: now,
    },
  );
  await batch.commit();
  return {
    uid,
    tenantId,
    email,
    invitationVersion,
    invitationToken: proof.token,
  };
}

async function seedActiveMembership(suffix) {
  const uid = `user-${suffix}`;
  const tenantId = `tenant-${suffix}`;
  const email = `${suffix}@integration.example.test`;
  const now = Timestamp.now();
  await auth.createUser({
    uid,
    email,
    password: PASSWORD,
    emailVerified: true,
    disabled: false,
  });
  const batch = firestore.batch();
  batch.set(firestore.doc(`users/${uid}`), {
    email,
    accountType: "tenant_user",
    identityOrigin: "self_signup",
    globalStatus: "active",
    membershipCount: 1,
    ownedTenantCount: 1,
    ownedActiveTenantCount: 1,
    createdAt: now,
    updatedAt: now,
  });
  batch.set(firestore.doc(`tenants/${tenantId}`), {
    name: `Business ${suffix}`,
    slug: tenantId,
    ownerUid: uid,
    status: "active",
    createdAt: now,
    updatedAt: now,
  });
  batch.set(firestore.doc(`tenants/${tenantId}/staff/${uid}`), {
    uid,
    role: "owner",
    status: "active",
    invitationStatus: "accepted",
    createdAt: now,
    joinedAt: now,
    updatedAt: now,
  });
  batch.set(firestore.doc(`users/${uid}/tenant_memberships/${tenantId}`), {
    tenantId,
    tenantName: `Business ${suffix}`,
    tenantSlug: tenantId,
    role: "owner",
    membershipStatus: "active",
    tenantStatus: "active",
    invitationStatus: "accepted",
    isOwner: true,
    mirrorVersion: 1,
    createdAt: now,
    joinedAt: now,
    updatedAt: now,
  });
  await batch.commit();
  return { uid, tenantId, email };
}

async function seedTenantApplicant(suffix) {
  const uid = `applicant-${suffix}`;
  const email = `${suffix}@integration.example.test`;
  const now = Timestamp.now();
  await auth.createUser({
    uid,
    email,
    displayName: `Applicant ${suffix}`,
    password: PASSWORD,
    emailVerified: true,
    disabled: false,
  });
  await firestore.doc(`users/${uid}`).set({
    email,
    displayName: `Applicant ${suffix}`,
    accountType: "tenant_user",
    identityOrigin: "self_signup",
    globalStatus: "active",
    membershipCount: 0,
    ownedTenantCount: 0,
    ownedActiveTenantCount: 0,
    createdAt: now,
    updatedAt: now,
  });
  return { uid, email };
}

async function seedPendingTenantReview(suffix, status = "pending") {
  const platformUid = `platform-${suffix}`;
  const platformEmail = `${platformUid}@integration.example.test`;
  const ownerUid = `review-owner-${suffix}`;
  const tenantId = `review-tenant-${suffix}`;
  const ownerEmail = `${ownerUid}@integration.example.test`;
  const now = Timestamp.now();
  await Promise.all([
    auth.createUser({
      uid: platformUid,
      email: platformEmail,
      password: PASSWORD,
      emailVerified: true,
      disabled: false,
    }),
    auth.createUser({
      uid: ownerUid,
      email: ownerEmail,
      password: PASSWORD,
      emailVerified: true,
      disabled: false,
    }),
  ]);
  await auth.setCustomUserClaims(platformUid, { platformRole: "superAdmin" });
  const batch = firestore.batch();
  batch.set(firestore.doc(`users/${platformUid}`), {
    email: platformEmail,
    accountType: "platform_admin",
    identityOrigin: "platform_bootstrap",
    globalStatus: "active",
    membershipCount: 0,
    ownedTenantCount: 0,
    ownedActiveTenantCount: status === "active" ? 1 : 0,
    createdAt: now,
    updatedAt: now,
  });
  batch.set(firestore.doc(`users/${ownerUid}`), {
    email: ownerEmail,
    displayName: `Review Owner ${suffix}`,
    accountType: "tenant_user",
    identityOrigin: "self_signup",
    globalStatus: "active",
    membershipCount: 1,
    ownedTenantCount: 1,
    ownedActiveTenantCount: 0,
    createdAt: now,
    updatedAt: now,
  });
  batch.set(firestore.doc(`tenants/${tenantId}`), {
    name: `Review Business ${suffix}`,
    slug: tenantId,
    ownerUid,
    requestedBy: ownerUid,
    status,
    createdAt: now,
    updatedAt: now,
  });
  batch.set(firestore.doc(`tenants/${tenantId}/staff/${ownerUid}`), {
    uid: ownerUid,
    email: ownerEmail,
    name: `Review Owner ${suffix}`,
    phone: "",
    role: "owner",
    status: "active",
    invitationStatus: "accepted",
    createdAt: now,
    joinedAt: now,
    updatedAt: now,
  });
  batch.set(
    firestore.doc(`users/${ownerUid}/tenant_memberships/${tenantId}`),
    {
      tenantId,
      tenantName: `Review Business ${suffix}`,
      tenantSlug: tenantId,
      role: "owner",
      membershipStatus: "active",
      tenantStatus: status,
      invitationStatus: "accepted",
      isOwner: true,
      mirrorVersion: 1,
      createdAt: now,
      joinedAt: now,
      updatedAt: now,
    },
  );
  await batch.commit();
  return { platformEmail, ownerUid, tenantId };
}

async function signIn(email) {
  const host = process.env.FIREBASE_AUTH_EMULATOR_HOST;
  const response = await fetch(
    `http://${host}/identitytoolkit.googleapis.com/v1/` +
      "accounts:signInWithPassword?key=fake-api-key",
    {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ email, password: PASSWORD, returnSecureToken: true }),
    },
  );
  const body = await response.json();
  assert.equal(response.ok, true, JSON.stringify(body));
  assert.equal(typeof body.idToken, "string");
  return body.idToken;
}

async function callFunction(functionName, idToken, data) {
  const host = process.env.FUNCTIONS_EMULATOR_HOST;
  const response = await fetch(
    `http://${host}/${PROJECT_ID}/us-central1/${functionName}`,
    {
      method: "POST",
      headers: {
        authorization: `Bearer ${idToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({ data }),
    },
  );
  const body = await response.json();
  assert.equal(response.ok, true, JSON.stringify(body));
  assert.equal(body.error, undefined, JSON.stringify(body));
  assert.equal(typeof body.result, "object", JSON.stringify(body));
  return body.result;
}

function assertAcceptedResponse(response, fixture) {
  assert.deepEqual(Object.keys(response).sort(), ACCEPTANCE_FIELDS);
  assert.deepEqual(response, {
    tenantId: fixture.tenantId,
    uid: fixture.uid,
    role: "cashier",
    membershipStatus: "active",
    invitationStatus: "accepted",
  });
}

function assertLifecycleResponse(
  response,
  tenantId,
  status,
  previousStatus = "pending",
) {
  assert.deepEqual(Object.keys(response).sort(), [
    "fanoutOperationId",
    "previousStatus",
    "status",
    "tenantId",
  ]);
  assert.equal(response.tenantId, tenantId);
  assert.equal(response.previousStatus, previousStatus);
  assert.equal(response.status, status);
  assert.equal(typeof response.fanoutOperationId, "string");
  assert.ok(response.fanoutOperationId.length > 0);
}

async function assertAcceptedDocuments(fixture, acceptanceMode) {
  const [staff, mirror, invitation] = await Promise.all([
    firestore.doc(`tenants/${fixture.tenantId}/staff/${fixture.uid}`).get(),
    firestore
      .doc(`users/${fixture.uid}/tenant_memberships/${fixture.tenantId}`)
      .get(),
    firestore
      .doc(`tenants/${fixture.tenantId}/staff_invitations/${fixture.uid}`)
      .get(),
  ]);
  assert.equal(staff.get("status"), "active");
  assert.equal(staff.get("invitationStatus"), "accepted");
  assert.equal(mirror.get("membershipStatus"), "active");
  assert.equal(mirror.get("invitationStatus"), "accepted");
  assert.equal(invitation.get("invitationStatus"), "accepted");
  assert.equal(invitation.get("acceptanceMode"), acceptanceMode);
  assert.ok(invitation.get("invitationTokenUsedAt") instanceof Timestamp);
}
