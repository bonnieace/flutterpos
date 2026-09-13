import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createRequire } from "node:module";
import { after, before, test } from "node:test";
import { fileURLToPath } from "node:url";

import { deleteApp, initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore, Timestamp } from "firebase-admin/firestore";

import { createInvitationProof } from
  "../../functions/lib/staff/invitationProof.js";
import {
  PlatformAdminRevocationError,
  revokePlatformAdmin,
} from "../../functions/lib/platform/revokePlatformAdmin.js";

const PROJECT_ID = "demo-multitenant-invitation-integration";
const INVITATION_SECRET =
  "local-emulator-invitation-hmac-secret-at-least-32-bytes";
const PASSWORD = "Local-emulator-password-123!";
const requireFunctionsAdmin = createRequire(new URL(
  "../../functions/package.json",
  import.meta.url,
));
const functionsAdminApp = requireFunctionsAdmin("firebase-admin/app");
const functionsAdminAuth = requireFunctionsAdmin("firebase-admin/auth");
const functionsAdminFirestore = requireFunctionsAdmin("firebase-admin/firestore");
const GRANT_PLATFORM_ADMIN_CLI = fileURLToPath(new URL(
  "../../functions/lib/cli/grantPlatformAdmin.js",
  import.meta.url,
));
const REVOKE_PLATFORM_ADMIN_CLI = fileURLToPath(new URL(
  "../../functions/lib/cli/revokePlatformAdmin.js",
  import.meta.url,
));
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
let revocationApp;
let revocationAuth;
let revocationFirestore;

before(async () => {
  requireEmulator("FIREBASE_AUTH_EMULATOR_HOST");
  requireEmulator("FIRESTORE_EMULATOR_HOST");
  requireEmulator("FUNCTIONS_EMULATOR_HOST");
  assert.equal(process.env.GCLOUD_PROJECT, PROJECT_ID);
  app = initializeApp({ projectId: PROJECT_ID }, "invitation-integration");
  auth = getAuth(app);
  firestore = getFirestore(app);
  revocationApp = functionsAdminApp.initializeApp(
    { projectId: PROJECT_ID },
    "platform-revocation-integration",
  );
  revocationAuth = functionsAdminAuth.getAuth(revocationApp);
  revocationFirestore = functionsAdminFirestore.getFirestore(revocationApp);
});

after(async () => {
  if (revocationApp) await functionsAdminApp.deleteApp(revocationApp);
  if (app) await deleteApp(app);
});

test("platform-admin revocation refuses the last fully active administrator", async () => {
  const uid = "revoke-last-admin";
  const now = Timestamp.now();
  await auth.createUser({
    uid,
    email: `${uid}@integration.example.test`,
    emailVerified: true,
    disabled: false,
  });
  await auth.setCustomUserClaims(uid, { platformRole: "superAdmin" });
  await firestore.doc(`users/${uid}`).set({
    email: `${uid}@integration.example.test`,
    accountType: "platform_admin",
    identityOrigin: "platform_bootstrap",
    globalStatus: "active",
    createdAt: now,
    updatedAt: now,
  });

  await assert.rejects(
    revokePlatformAdmin({ db: revocationFirestore, auth: revocationAuth }, {
      actorUid: "separate-break-glass-actor",
      targetUid: uid,
      requestId: "platform-revoke-last-admin-001",
      reason: "Exercise the authoritative last-admin safety boundary.",
    }),
    (error) => error instanceof PlatformAdminRevocationError &&
      error.code === "last-platform-admin" && !error.recoverable,
  );
  const [root, operations, audits] = await Promise.all([
    firestore.doc(`users/${uid}`).get(),
    firestore.collection("platform_identity_operations")
      .where("targetUid", "==", uid).get(),
    firestore.collection("platform_audit_logs")
      .where("targetUid", "==", uid).get(),
  ]);
  assert.equal(root.get("accountType"), "platform_admin");
  assert.equal(root.get("identityTransition"), undefined);
  assert.equal(operations.size, 1);
  assert.equal(operations.docs[0].get("status"), "rejected");
  assert.equal(audits.size, 1);
  assert.equal(audits.docs[0].get("rejectionCode"), "last-platform-admin");
});

test("acceptTenantInvitation consumes a real versioned proof", async () => {
  const fixture = await seedPendingInvitation({
    suffix: "token",
    emailVerified: false,
    credentialBootstrapRequired: true,
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
    credentialBootstrapRequired: false,
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

test("acceptVisibleTenantInvitation admits an identity the invitation created", async () => {
  // The lockout, end to end. This is the document shape of a new hire: an Auth
  // account the invitation itself created, sent a credential-bootstrap link,
  // who has since followed it - so the password is set and Firebase has marked
  // the address verified. Until 2026-09-08 the stored `visibleAcceptanceAllowed`
  // was false for exactly this person and no amount of verifying changed it, so
  // this call answered `versioned_proof_required` and the emailed link it named
  // opened a page telling them to come back here.
  const fixture = await seedPendingInvitation({
    suffix: "bootstrapped",
    emailVerified: true,
    credentialBootstrapRequired: true,
    tokenByte: 0x33,
  });
  const idToken = await signIn(fixture.email);

  const response = await callFunction(
    "acceptVisibleTenantInvitation",
    idToken,
    {
      tenantId: fixture.tenantId,
      requestId: "bootstrapped-emulator-request-1",
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

test("requestTenant creates an active canonical tenant and routing mirror", async () => {
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
  assert.equal(response.status, "active");
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
  assert.equal(tenant.get("status"), "active");
  assert.equal(tenant.get("ownerUid"), fixture.uid);
  assert.equal(staff.get("uid"), fixture.uid);
  assert.equal(staff.get("role"), "owner");
  assert.equal(staff.get("status"), "active");
  assert.equal(mirror.get("tenantStatus"), "active");
  assert.equal(mirror.get("membershipStatus"), "active");
  assert.equal(slug.get("tenantId"), response.tenantId);
  assert.equal(root.get("membershipCount"), 1);
  assert.equal(root.get("ownedTenantCount"), 1);
  assert.equal(root.get("ownedActiveTenantCount"), 1);
});

test("setTenantLifecycle suspends and reactivates an active tenant", async () => {
  const fixture = await seedTenantForReview("manage", "active");
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

test("setTenantLifecycle archives a suspended tenant with exact persisted state", async () => {
  const fixture = await seedTenantForReview("archive", "suspended");
  const idToken = await signIn(fixture.platformEmail);

  const response = await callFunction("setTenantLifecycle", idToken, {
    tenantId: fixture.tenantId,
    status: "archived",
    reason: "The suspended business is closed permanently.",
    requestId: "lifecycle-archive-emulator-request-1",
  });
  assertLifecycleResponse(
    response,
    fixture.tenantId,
    "archived",
    "suspended",
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
  assert.equal(fanout.get("fromStatus"), "suspended");
  assert.equal(fanout.get("toStatus"), "archived");
  assert.equal(audit.get("reason"), "The suspended business is closed permanently.");
  assert.equal(audit.get("fromStatus"), "suspended");
  assert.equal(audit.get("toStatus"), "archived");
});

test("setGlobalUserStatus completes disable and reactivation sagas", async () => {
  const fixture = await seedGlobalStatusFixture("global-status");
  const targetToken = await signIn(fixture.targetEmail);
  const idToken = await signIn(fixture.platformEmail);

  await assertCallableError(
    "getGlobalUserStatusReview",
    targetToken,
    { uid: fixture.targetUid },
    "PERMISSION_DENIED",
  );
  const review = await callFunction("getGlobalUserStatusReview", idToken, {
    uid: fixture.targetUid,
  });
  assert.deepEqual(Object.keys(review).sort(), [
    "administrativeRoots",
    "administrativeStaff",
    "found",
    "ownedTenants",
    "targetStaff",
    "tenants",
    "user",
  ]);
  assert.equal(review.found, true);
  assert.equal(review.user.id, fixture.targetUid);
  assert.equal(review.user.data.globalStatus, "active");
  assert.equal(Number.isSafeInteger(review.user.data.updatedAtMillis), true);
  assert.deepEqual(review.targetStaff.map((staff) => staff.tenantId), [
    fixture.tenantId,
  ]);
  assert.deepEqual(review.ownedTenants.map((tenant) => tenant.id), [
    fixture.tenantId,
  ]);
  assert.deepEqual(review.tenants.map((tenant) => tenant.id), [
    fixture.tenantId,
  ]);
  assert.equal(review.administrativeStaff.length, 1);
  assert.deepEqual(review.administrativeRoots, []);

  const disabled = await callFunction("setGlobalUserStatus", idToken, {
    uid: fixture.targetUid,
    status: "disabled",
    reason: "Confirmed account security incident.",
    requestId: "global-disable-emulator-request-1",
  });
  assertGlobalStatusResponse(
    disabled,
    "global-disable-emulator-request-1",
    fixture.targetUid,
    "disabled",
    [fixture.tenantId],
  );
  let [root, operation, authUser, mirror, alerts] = await Promise.all([
    firestore.doc(`users/${fixture.targetUid}`).get(),
    firestore.doc(`platform_user_operations/${disabled.operationId}`).get(),
    auth.getUser(fixture.targetUid),
    firestore
      .doc(`users/${fixture.targetUid}/tenant_memberships/${fixture.tenantId}`)
      .get(),
    firestore.collection(`tenants/${fixture.tenantId}/alerts`).get(),
  ]);
  assert.equal(root.get("globalStatus"), "disabled");
  assert.equal(root.get("globalStatusOperationId"), undefined);
  assert.equal(operation.get("status"), "completed");
  assert.equal(operation.get("authStatus"), "completed");
  assert.equal(operation.get("tokenStatus"), "completed");
  assert.deepEqual(operation.get("affectedTenantIds"), [fixture.tenantId]);
  assert.equal(authUser.disabled, true);
  assert.equal(typeof authUser.tokensValidAfterTime, "string");
  assert.ok(Number.isFinite(Date.parse(authUser.tokensValidAfterTime)));
  assert.equal(mirror.get("tenantStatus"), "active");
  assert.equal(alerts.size, 1);
  assert.equal(alerts.docs[0].get("type"), "tenant_owner_unavailable");

  const reactivated = await callFunction("setGlobalUserStatus", idToken, {
    uid: fixture.targetUid,
    status: "active",
    reason: "Support verified the account recovery.",
    requestId: "global-reactivate-emulator-request-1",
  });
  assertGlobalStatusResponse(
    reactivated,
    "global-reactivate-emulator-request-1",
    fixture.targetUid,
    "active",
    [],
  );
  [root, operation, authUser] = await Promise.all([
    firestore.doc(`users/${fixture.targetUid}`).get(),
    firestore.doc(`platform_user_operations/${reactivated.operationId}`).get(),
    auth.getUser(fixture.targetUid),
  ]);
  assert.equal(root.get("globalStatus"), "active");
  assert.equal(Number.isSafeInteger(root.get("authValidAfterSeconds")), true);
  assert.ok(root.get("authValidAfterSeconds") > 0);
  assert.equal(root.get("globalStatusOperationId"), undefined);
  assert.equal(operation.get("status"), "completed");
  assert.equal(operation.get("claimStatus"), "not_restored");
  assert.equal(authUser.disabled, false);

  const audits = await firestore
    .collection("platform_audit_logs")
    .where("uid", "==", fixture.targetUid)
    .get();
  const globalAudits = audits.docs.filter(
    (document) => document.get("eventType") === "global_user_status_changed",
  );
  assert.equal(globalAudits.length, 2);
  assert.deepEqual(
    globalAudits.map((document) => document.get("status")).sort(),
    ["completed", "completed"],
  );
});

test("grant-platform-admin CLI completes, rejects, and resumes real grants", async () => {
  const fixture = await seedPlatformGrantFixture("grant-cli");

  const completed = runPlatformGrantCli(
    fixture.operatorUid,
    fixture.eligibleUid,
    "platform-grant-emulator-eligible-001",
    "Security approved the dedicated platform identity.",
    0,
  );
  assert.equal(completed.status, "completed");
  assert.equal(completed.targetUid, fixture.eligibleUid);
  assert.equal(completed.resumed, false);
  assert.deepEqual(completed.warnings.sort(), [
    "membership_counter_positive",
    "owned_active_tenant_counter_positive",
    "owned_tenant_counter_positive",
  ]);

  let [root, authUser, audit] = await Promise.all([
    firestore.doc(`users/${fixture.eligibleUid}`).get(),
    auth.getUser(fixture.eligibleUid),
    firestore.doc(`platform_audit_logs/${completed.auditId}`).get(),
  ]);
  assert.equal(root.get("accountType"), "platform_admin");
  assert.equal(root.get("identityTransition"), undefined);
  assert.deepEqual(authUser.customClaims, {
    supportTier: "senior",
    platformRole: "superAdmin",
  });
  assert.equal(audit.get("status"), "completed");
  assert.equal(audit.get("actorUid"), fixture.operatorUid);
  assert.equal(audit.get("targetUid"), fixture.eligibleUid);
  assert.equal(
    audit.get("reason"),
    "Security approved the dedicated platform identity.",
  );
  assert.deepEqual(audit.get("canonicalEvidenceCounts"), {
    staffMemberships: 0,
    ownedTenants: 0,
    unresolvedInvitations: 0,
  });

  const rejected = runPlatformGrantCli(
    fixture.operatorUid,
    fixture.ineligibleUid,
    "platform-grant-emulator-ineligible-001",
    "Canonical membership makes this identity ineligible.",
    4,
  );
  assert.deepEqual(rejected, {
    status: "rejected",
    code: "platform-identity-ineligible",
    recoverable: false,
  });
  [root, authUser] = await Promise.all([
    firestore.doc(`users/${fixture.ineligibleUid}`).get(),
    auth.getUser(fixture.ineligibleUid),
  ]);
  assert.equal(root.get("accountType"), "tenant_user");
  assert.equal(root.get("identityTransition"), undefined);
  assert.equal(authUser.customClaims?.platformRole, undefined);
  const rejectedAudits = await firestore
    .collection("platform_audit_logs")
    .where("targetUid", "==", fixture.ineligibleUid)
    .get();
  assert.equal(rejectedAudits.size, 1);
  assert.equal(rejectedAudits.docs[0].get("status"), "rejected_ineligible");
  assert.deepEqual(rejectedAudits.docs[0].get("canonicalEvidenceCounts"), {
    staffMemberships: 1,
    ownedTenants: 1,
    unresolvedInvitations: 0,
  });

  const resumed = runPlatformGrantCli(
    fixture.operatorUid,
    fixture.resumableUid,
    "platform-grant-emulator-resume-001",
    "Resume the previously acquired guarded transition.",
    0,
  );
  assert.equal(resumed.status, "completed");
  assert.equal(resumed.targetUid, fixture.resumableUid);
  assert.equal(resumed.resumed, true);
  [root, authUser, audit] = await Promise.all([
    firestore.doc(`users/${fixture.resumableUid}`).get(),
    auth.getUser(fixture.resumableUid),
    firestore.doc(`platform_audit_logs/${resumed.auditId}`).get(),
  ]);
  assert.equal(root.get("accountType"), "platform_admin");
  assert.equal(root.get("identityTransition"), undefined);
  assert.equal(authUser.customClaims?.platformRole, "superAdmin");
  assert.equal(audit.get("status"), "completed");
});

test("revoke-platform-admin CLI completes, rejects stale state, and resumes", async () => {
  const fixture = await seedPlatformRevokeFixture("revoke-cli");

  const completed = runPlatformRevokeCli(
    fixture.operatorUid,
    fixture.targetUid,
    "platform-revoke-emulator-success-001",
    "The dedicated platform access is no longer required.",
    0,
  );
  assert.equal(completed.status, "completed");
  assert.equal(completed.targetUid, fixture.targetUid);
  assert.equal(completed.resumed, false);
  assert.equal(Number.isSafeInteger(completed.authValidAfterSeconds), true);

  let [root, authUser, operation, audit] = await Promise.all([
    firestore.doc(`users/${fixture.targetUid}`).get(),
    auth.getUser(fixture.targetUid),
    firestore.doc(`platform_identity_operations/${completed.operationId}`).get(),
    firestore.doc(`platform_audit_logs/${completed.auditId}`).get(),
  ]);
  assert.equal(root.get("accountType"), "tenant_user");
  assert.equal(root.get("identityTransition"), undefined);
  assert.equal(root.get("platformIdentityOperationId"), undefined);
  assert.equal(root.get("authValidAfterSeconds"), completed.authValidAfterSeconds);
  assert.deepEqual(authUser.customClaims, { supportTier: "senior" });
  assert.equal(typeof authUser.tokensValidAfterTime, "string");
  assert.equal(operation.get("status"), "completed");
  assert.equal(operation.get("claimStatus"), "removed");
  assert.equal(operation.get("tokenStatus"), "completed");
  assert.equal(audit.get("status"), "completed");
  assert.equal(audit.get("actorUid"), fixture.operatorUid);
  assert.equal(audit.get("fullyActiveOtherAdminCount") >= 1, true);
  assert.deepEqual(audit.get("canonicalEvidenceCounts"), {
    staffMemberships: 0,
    ownedTenants: 0,
    unresolvedInvitations: 0,
  });

  const repeated = runPlatformRevokeCli(
    fixture.operatorUid,
    fixture.targetUid,
    "platform-revoke-emulator-success-001",
    "The dedicated platform access is no longer required.",
    0,
  );
  assert.equal(repeated.operationId, completed.operationId);
  assert.equal(repeated.resumed, true);

  const stale = runPlatformRevokeCli(
    fixture.operatorUid,
    fixture.staleUid,
    "platform-revoke-emulator-stale-001",
    "Reject root-only administrator state without restoring its claim.",
    4,
  );
  assert.deepEqual(stale, {
    status: "rejected",
    code: "target-state-disagreement",
    recoverable: false,
  });
  [root, authUser] = await Promise.all([
    firestore.doc(`users/${fixture.staleUid}`).get(),
    auth.getUser(fixture.staleUid),
  ]);
  assert.equal(root.get("accountType"), "platform_admin");
  assert.equal(root.get("identityTransition"), undefined);
  assert.equal(authUser.customClaims?.platformRole, undefined);

  const ineligible = runPlatformRevokeCli(
    fixture.operatorUid,
    fixture.ineligibleUid,
    "platform-revoke-emulator-ineligible-001",
    "Canonical tenant evidence must block identity conversion.",
    4,
  );
  assert.equal(ineligible.code, "platform-identity-ineligible");
  root = await firestore.doc(`users/${fixture.ineligibleUid}`).get();
  assert.equal(root.get("accountType"), "platform_admin");
  assert.equal(root.get("identityTransition"), undefined);

  const partialInput = {
    actorUid: fixture.operatorUid,
    targetUid: fixture.partialUid,
    requestId: "platform-revoke-emulator-partial-001",
    reason: "Resume after an ambiguous successful Auth claim removal.",
  };
  let failAfterClaimRemoval = true;
  await assert.rejects(
    revokePlatformAdmin({
      db: revocationFirestore,
      auth: {
        getUser: (uid) => revocationAuth.getUser(uid),
        async setCustomUserClaims(uid, claims) {
          await revocationAuth.setCustomUserClaims(uid, claims);
          if (failAfterClaimRemoval) {
            failAfterClaimRemoval = false;
            throw new Error("simulated_response_loss_after_claim_removal");
          }
        },
        revokeRefreshTokens: (uid) => revocationAuth.revokeRefreshTokens(uid),
      },
    }, partialInput),
    (error) => error instanceof PlatformAdminRevocationError &&
      error.code === "claim-removal-failed" && error.recoverable,
  );
  [root, authUser] = await Promise.all([
    firestore.doc(`users/${fixture.partialUid}`).get(),
    auth.getUser(fixture.partialUid),
  ]);
  assert.equal(root.get("identityTransition"), "revoking_platform");
  assert.equal(authUser.customClaims?.platformRole, undefined);

  const resumed = await revokePlatformAdmin({
    db: revocationFirestore,
    auth: revocationAuth,
  }, partialInput);
  assert.equal(resumed.resumed, true);
  [root, authUser, operation, audit] = await Promise.all([
    firestore.doc(`users/${fixture.partialUid}`).get(),
    auth.getUser(fixture.partialUid),
    firestore.doc(`platform_identity_operations/${resumed.operationId}`).get(),
    firestore.doc(`platform_audit_logs/${resumed.auditId}`).get(),
  ]);
  assert.equal(root.get("accountType"), "tenant_user");
  assert.equal(root.get("identityTransition"), undefined);
  assert.equal(authUser.customClaims?.platformRole, undefined);
  assert.equal(operation.get("attemptCount"), 2);
  assert.equal(operation.get("status"), "completed");
  assert.equal(audit.get("status"), "completed");
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
  credentialBootstrapRequired,
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
      credentialBootstrapRequired,
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

async function seedTenantForReview(suffix, status = "active") {
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

async function seedGlobalStatusFixture(suffix) {
  const platformUid = `platform-${suffix}`;
  const platformEmail = `${platformUid}@integration.example.test`;
  const targetUid = `target-${suffix}`;
  const targetEmail = `${targetUid}@integration.example.test`;
  const tenantId = `tenant-${suffix}`;
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
      uid: targetUid,
      email: targetEmail,
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
    ownedActiveTenantCount: 0,
    createdAt: now,
    updatedAt: now,
  });
  batch.set(firestore.doc(`users/${targetUid}`), {
    email: targetEmail,
    displayName: "Global Status Target",
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
    name: "Global Status Business",
    slug: tenantId,
    ownerUid: targetUid,
    status: "active",
    createdAt: now,
    updatedAt: now,
  });
  batch.set(firestore.doc(`tenants/${tenantId}/staff/${targetUid}`), {
    uid: targetUid,
    email: targetEmail,
    role: "owner",
    status: "active",
    invitationStatus: "accepted",
    createdAt: now,
    joinedAt: now,
    updatedAt: now,
  });
  batch.set(firestore.doc(`staff/${targetUid}`), {
    uid: targetUid,
    email: targetEmail,
    role: "owner",
    status: "active",
    legacyOnly: true,
  });
  batch.set(
    firestore.doc(`users/${targetUid}/tenant_memberships/${tenantId}`),
    {
      tenantId,
      tenantName: "Global Status Business",
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
    },
  );
  await batch.commit();
  return { platformEmail, targetUid, targetEmail, tenantId };
}

async function seedPlatformGrantFixture(suffix) {
  const operatorUid = `grant-operator-${suffix}`;
  const eligibleUid = `grant-eligible-${suffix}`;
  const ineligibleUid = `grant-ineligible-${suffix}`;
  const resumableUid = `grant-resumable-${suffix}`;
  const tenantId = `grant-tenant-${suffix}`;
  const now = Timestamp.now();
  await Promise.all([
    auth.createUser({
      uid: operatorUid,
      email: `${operatorUid}@integration.example.test`,
      emailVerified: true,
      disabled: false,
    }),
    auth.createUser({
      uid: eligibleUid,
      email: `${eligibleUid}@integration.example.test`,
      emailVerified: true,
      disabled: false,
    }),
    auth.createUser({
      uid: ineligibleUid,
      email: `${ineligibleUid}@integration.example.test`,
      emailVerified: true,
      disabled: false,
    }),
    auth.createUser({
      uid: resumableUid,
      email: `${resumableUid}@integration.example.test`,
      emailVerified: true,
      disabled: false,
    }),
  ]);
  await Promise.all([
    auth.setCustomUserClaims(operatorUid, { platformRole: "superAdmin" }),
    auth.setCustomUserClaims(eligibleUid, { supportTier: "senior" }),
  ]);

  const root = (uid, extra = {}) => ({
    email: `${uid}@integration.example.test`,
    accountType: "tenant_user",
    identityOrigin: "self_signup",
    globalStatus: "active",
    membershipCount: 0,
    ownedTenantCount: 0,
    ownedActiveTenantCount: 0,
    createdAt: now,
    updatedAt: now,
    ...extra,
  });
  const batch = firestore.batch();
  batch.set(firestore.doc(`users/${operatorUid}`), root(operatorUid, {
    accountType: "platform_admin",
    identityOrigin: "platform_bootstrap",
  }));
  batch.set(firestore.doc(`users/${eligibleUid}`), root(eligibleUid, {
    membershipCount: 9,
    ownedTenantCount: 4,
    ownedActiveTenantCount: 2,
  }));
  batch.set(firestore.doc(`users/${ineligibleUid}`), root(ineligibleUid));
  batch.set(firestore.doc(`users/${resumableUid}`), root(resumableUid, {
    identityTransition: "granting_platform",
  }));
  batch.set(firestore.doc(`tenants/${tenantId}`), {
    name: "Canonical membership blocker",
    slug: tenantId,
    ownerUid: ineligibleUid,
    status: "active",
    createdAt: now,
    updatedAt: now,
  });
  batch.set(firestore.doc(`tenants/${tenantId}/staff/${ineligibleUid}`), {
    uid: ineligibleUid,
    email: `${ineligibleUid}@integration.example.test`,
    role: "owner",
    status: "active",
    invitationStatus: "accepted",
    createdAt: now,
    joinedAt: now,
    updatedAt: now,
  });
  await batch.commit();
  return {operatorUid, eligibleUid, ineligibleUid, resumableUid};
}

function runPlatformGrantCli(
  operatorUid,
  targetUid,
  requestId,
  reason,
  expectedExitCode,
) {
  const result = spawnSync(process.execPath, [
    GRANT_PLATFORM_ADMIN_CLI,
    "--environment", "emulator",
    "--project-id", PROJECT_ID,
    "--confirm-project-id", PROJECT_ID,
    "--actor-uid", operatorUid,
    "--target-uid", targetUid,
    "--confirm-target-uid", targetUid,
    "--request-id", requestId,
    "--reason", reason,
  ], {
    encoding: "utf8",
    env: process.env,
    timeout: 60_000,
  });
  if (result.error) throw result.error;
  assert.equal(
    result.status,
    expectedExitCode,
    `stdout=${result.stdout}\nstderr=${result.stderr}`,
  );
  const output = expectedExitCode === 0 ? result.stdout : result.stderr;
  return JSON.parse(output);
}

async function seedPlatformRevokeFixture(suffix) {
  const operatorUid = `revoke-operator-${suffix}`;
  const targetUid = `revoke-target-${suffix}`;
  const staleUid = `revoke-stale-${suffix}`;
  const ineligibleUid = `revoke-ineligible-${suffix}`;
  const partialUid = `revoke-partial-${suffix}`;
  const tenantId = `revoke-tenant-${suffix}`;
  const uids = [operatorUid, targetUid, staleUid, ineligibleUid, partialUid];
  const now = Timestamp.now();
  await Promise.all(uids.map((uid) => auth.createUser({
    uid,
    email: `${uid}@integration.example.test`,
    emailVerified: true,
    disabled: false,
  })));
  await Promise.all([
    auth.setCustomUserClaims(operatorUid, { platformRole: "superAdmin" }),
    auth.setCustomUserClaims(targetUid, {
      supportTier: "senior",
      platformRole: "superAdmin",
    }),
    auth.setCustomUserClaims(ineligibleUid, { platformRole: "superAdmin" }),
    auth.setCustomUserClaims(partialUid, {
      supportTier: "response-team",
      platformRole: "superAdmin",
    }),
  ]);
  const root = (uid) => ({
    email: `${uid}@integration.example.test`,
    accountType: "platform_admin",
    identityOrigin: "platform_bootstrap",
    globalStatus: "active",
    membershipCount: 0,
    ownedTenantCount: 0,
    ownedActiveTenantCount: 0,
    createdAt: now,
    updatedAt: now,
  });
  const batch = firestore.batch();
  for (const uid of uids) batch.set(firestore.doc(`users/${uid}`), root(uid));
  batch.set(firestore.doc(`tenants/${tenantId}`), {
    name: "Revocation canonical blocker",
    slug: tenantId,
    ownerUid: ineligibleUid,
    status: "active",
    createdAt: now,
    updatedAt: now,
  });
  batch.set(firestore.doc(`tenants/${tenantId}/staff/${ineligibleUid}`), {
    uid: ineligibleUid,
    email: `${ineligibleUid}@integration.example.test`,
    role: "owner",
    status: "active",
    invitationStatus: "accepted",
    createdAt: now,
    joinedAt: now,
    updatedAt: now,
  });
  await batch.commit();
  return {operatorUid, targetUid, staleUid, ineligibleUid, partialUid};
}

function runPlatformRevokeCli(
  operatorUid,
  targetUid,
  requestId,
  reason,
  expectedExitCode,
) {
  const result = spawnSync(process.execPath, [
    REVOKE_PLATFORM_ADMIN_CLI,
    "--environment", "emulator",
    "--project-id", PROJECT_ID,
    "--confirm-project-id", PROJECT_ID,
    "--actor-uid", operatorUid,
    "--target-uid", targetUid,
    "--confirm-target-uid", targetUid,
    "--request-id", requestId,
    "--reason", reason,
  ], {
    encoding: "utf8",
    env: process.env,
    timeout: 60_000,
  });
  if (result.error) throw result.error;
  assert.equal(
    result.status,
    expectedExitCode,
    `stdout=${result.stdout}\nstderr=${result.stderr}`,
  );
  const output = expectedExitCode === 0 ? result.stdout : result.stderr;
  return JSON.parse(output);
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

async function assertCallableError(
  functionName,
  idToken,
  data,
  expectedStatus,
) {
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
  assert.equal(response.ok, false, JSON.stringify(body));
  assert.equal(body.error?.status, expectedStatus, JSON.stringify(body));
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
  previousStatus = "active",
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

function assertGlobalStatusResponse(
  response,
  operationId,
  uid,
  targetStatus,
  affectedTenantIds,
) {
  assert.deepEqual(Object.keys(response).sort(), [
    "affectedTenantIds",
    "attemptCount",
    "operationId",
    "status",
    "targetStatus",
    "uid",
  ]);
  assert.deepEqual(response, {
    operationId,
    uid,
    status: "completed",
    targetStatus,
    affectedTenantIds,
    attemptCount: 1,
  });
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
