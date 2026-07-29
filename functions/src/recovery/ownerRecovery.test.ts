import assert from "node:assert/strict";
import test from "node:test";
import {
  assertRecoveryAuthIdentities,
  buildOwnerRecoveryPlan,
  OwnerRecoveryError,
  OwnerRecoveryInput,
  OwnerRecoveryMutation,
  OwnerRecoveryState,
  OwnerRecoveryTransaction,
  RecoveryDocument,
  recoverTenantOwner,
} from "./ownerRecovery";

const TIMESTAMP = "server-time";

function document(
  path: string,
  data?: Readonly<Record<string, unknown>>
): RecoveryDocument {
  return {
    path,
    id: path.split("/").slice(-1)[0] ?? "",
    exists: data !== undefined,
    ...(data ? {data} : {}),
  };
}

function input(mode: "normal" | "exceptional"): OwnerRecoveryInput {
  return {
    tenantId: "tenant-a",
    replacementUid: "replacement-user",
    operatorUid: "platform-operator",
    operationId: "recovery-operation-001",
    mode,
    reason: "Verified owner recovery requested by support.",
    ...(mode === "exceptional" ? {
      caseId: "case-001",
      supportReference: "SUP-8675309",
      confirmations: {
        tenantSlug: "north-shop",
        oldOwnerUid: "old-owner",
        replacementUid: "replacement-user",
        secondConfirmation: true,
      },
    } : {}),
  };
}

function state(mode: "normal" | "exceptional"): OwnerRecoveryState {
  const tenant = document("tenants/tenant-a", {
    name: "North Shop",
    slug: "north-shop",
    status: "active",
    ownerUid: "old-owner",
  });
  const oldOwnerStaff = document("tenants/tenant-a/staff/old-owner", {
    uid: "old-owner",
    role: "owner",
    status: "active",
    invitationStatus: "accepted",
  });
  const replacementStaff = mode === "normal" ?
    document("tenants/tenant-a/staff/replacement-user", {
      uid: "replacement-user",
      role: "admin",
      status: "active",
      invitationStatus: "accepted",
    }) :
    document("tenants/tenant-a/staff/replacement-user");
  const replacementOtherMembership = document("tenants/tenant-c/staff/replacement-user", {
    uid: "replacement-user",
    role: "cashier",
    status: "active",
  });

  return {
    tenant,
    operatorUser: document("users/platform-operator", {
      accountType: "platform_admin",
      globalStatus: "active",
    }),
    oldOwnerUser: document("users/old-owner", {
      accountType: "tenant_user",
      globalStatus: "disabled",
      membershipCount: 2,
      ownedTenantCount: 99,
      ownedActiveTenantCount: 99,
    }),
    replacementUser: document("users/replacement-user", {
      accountType: "tenant_user",
      globalStatus: "active",
      email: "stale@example.invalid",
      displayName: "Canonical Name",
      membershipCount: mode === "normal" ? 2 : 1,
      ownedTenantCount: 0,
      ownedActiveTenantCount: 0,
    }),
    oldOwnerStaff,
    replacementStaff,
    oldOwnerMirror: document("users/old-owner/tenant_memberships/tenant-a", {
      mirrorVersion: 7,
      joinedAt: "old-join-time",
    }),
    replacementMirror: mode === "normal" ?
      document("users/replacement-user/tenant_memberships/tenant-a", {
        mirrorVersion: 3,
        joinedAt: "replacement-join-time",
      }) :
      document("users/replacement-user/tenant_memberships/tenant-a"),
    tenantOwnerStaff: [oldOwnerStaff],
    oldOwnerOwnedTenants: [
      tenant,
      document("tenants/tenant-b", {
        name: "Old Secondary",
        slug: "old-secondary",
        status: "suspended",
        ownerUid: "old-owner",
      }),
      document("tenants/tenant-old-archived", {
        name: "Old Archived",
        slug: "old-archived",
        status: "archived",
        ownerUid: "old-owner",
      }),
    ],
    replacementOwnedTenants: [
      document("tenants/tenant-c", {
        name: "Replacement Secondary",
        slug: "replacement-secondary",
        status: "active",
        ownerUid: "replacement-user",
      }),
      document("tenants/tenant-replacement-archived", {
        name: "Replacement Archived",
        slug: "replacement-archived",
        status: "archived",
        ownerUid: "replacement-user",
      }),
    ],
    oldOwnerMemberships: [
      oldOwnerStaff,
      document("tenants/tenant-b/staff/old-owner", {
        uid: "old-owner",
        role: "owner",
        status: "active",
      }),
    ],
    replacementMemberships: mode === "normal" ?
      [replacementStaff, replacementOtherMembership] :
      [replacementOtherMembership],
    replacementAuth: {
      uid: "replacement-user",
      email: "New.Owner@Example.com",
      displayName: "Auth Name",
      emailVerified: true,
      disabled: false,
    },
    ...(mode === "exceptional" ? {
      recoveryCase: document("owner_recovery_cases/case-001", {
        tenantId: "tenant-a",
        oldOwnerUid: "old-owner",
        replacementUid: "replacement-user",
        supportReference: "SUP-8675309",
        status: "approved",
      }),
    } : {}),
  };
}

function mutationAt(
  mutations: readonly OwnerRecoveryMutation[],
  path: string
): OwnerRecoveryMutation {
  const mutation = mutations.find((candidate) => candidate.path === path);
  assert.ok(mutation, `Missing mutation for ${path}`);
  return mutation;
}

function assertRecoveryError(
  action: () => unknown,
  code: OwnerRecoveryError["code"]
): void {
  assert.throws(action, (error: unknown) =>
    error instanceof OwnerRecoveryError && error.code === code
  );
}

function serviceHarness(mode: "normal" | "exceptional") {
  const canonical = state(mode);
  const directDocuments = new Map<string, RecoveryDocument>();
  for (const candidate of [
    canonical.tenant,
    canonical.operatorUser,
    canonical.oldOwnerUser,
    canonical.replacementUser,
    canonical.oldOwnerStaff,
    canonical.replacementStaff,
    canonical.oldOwnerMirror,
    canonical.replacementMirror,
    ...(canonical.recoveryCase ? [canonical.recoveryCase] : []),
  ]) {
    directDocuments.set(candidate.path, candidate);
  }
  const mutations: OwnerRecoveryMutation[] = [];
  const transaction: OwnerRecoveryTransaction = {
    async get(path) {
      return directDocuments.get(path) ?? document(path);
    },
    async queryTenantOwnerStaff() {
      return canonical.tenantOwnerStaff;
    },
    async queryOwnedTenants(uid) {
      return uid === "old-owner" ?
        canonical.oldOwnerOwnedTenants :
        canonical.replacementOwnedTenants;
    },
    async queryStaffMemberships(uid) {
      return uid === "old-owner" ?
        canonical.oldOwnerMemberships :
        canonical.replacementMemberships;
    },
    create(path, data) {
      mutations.push({kind: "create", path, data});
    },
    update(path, data) {
      mutations.push({kind: "update", path, data});
    },
    set(path, data, merge) {
      mutations.push({kind: "set", path, data, merge});
    },
  };
  let transactionCalls = 0;
  return {
    canonical,
    mutations,
    transactionCalls: () => transactionCalls,
    dependencies: {
      store: {
        async runTransaction<T>(
          handler: (value: OwnerRecoveryTransaction) => Promise<T>
        ): Promise<T> {
          transactionCalls += 1;
          return handler(transaction);
        },
      },
      auth: {
        async getUser(uid: string) {
          if (uid === "platform-operator") {
            return {
              uid,
              disabled: false,
              customClaims: {platformRole: "superAdmin"},
            };
          }
          return canonical.replacementAuth;
        },
      },
      serverTimestamp: () => TIMESTAMP,
    },
  };
}

test("normal recovery replaces an active admin and preserves exactly one owner", () => {
  const plan = buildOwnerRecoveryPlan(input("normal"), state("normal"), TIMESTAMP);

  assert.deepEqual(plan.ownerUidsAfter, ["replacement-user"]);
  assert.equal(plan.mutations.length, 10);
  assert.deepEqual(mutationAt(plan.mutations, "tenants/tenant-a").data, {
    ownerUid: "replacement-user",
    updatedAt: TIMESTAMP,
  });
  assert.deepEqual(
    mutationAt(plan.mutations, "tenants/tenant-a/staff/old-owner").data,
    {
      role: "admin",
      status: "inactive",
      invitationStatus: "accepted",
      updatedAt: TIMESTAMP,
    }
  );
  assert.deepEqual(
    mutationAt(plan.mutations, "tenants/tenant-a/staff/replacement-user").data,
    {
      uid: "replacement-user",
      role: "owner",
      status: "active",
      invitationStatus: "accepted",
      updatedAt: TIMESTAMP,
    }
  );
  assert.deepEqual(mutationAt(plan.mutations, "users/old-owner").data, {
    membershipCount: 2,
    ownedTenantCount: 1,
    ownedActiveTenantCount: 0,
    updatedAt: TIMESTAMP,
  });
  assert.deepEqual(mutationAt(plan.mutations, "users/replacement-user").data, {
    membershipCount: 2,
    ownedTenantCount: 2,
    ownedActiveTenantCount: 2,
    updatedAt: TIMESTAMP,
  });
  assert.equal(
    mutationAt(plan.mutations, "users/old-owner/tenant_memberships/tenant-a").data
      .mirrorVersion,
    8
  );
  assert.equal(
    mutationAt(plan.mutations, "users/replacement-user/tenant_memberships/tenant-a").data
      .isOwner,
    true
  );
  assert.equal(
    mutationAt(plan.mutations, "platform_audit_logs/recovery-operation-001").data
      .eventType,
    "owner_recovered"
  );
});

test("exceptional recovery creates the replacement membership and consumes its case", () => {
  const plan = buildOwnerRecoveryPlan(
    input("exceptional"),
    state("exceptional"),
    TIMESTAMP
  );

  assert.deepEqual(plan.ownerUidsAfter, ["replacement-user"]);
  assert.equal(plan.mutations.length, 11);
  const replacement = mutationAt(
    plan.mutations,
    "tenants/tenant-a/staff/replacement-user"
  );
  assert.equal(replacement.kind, "create");
  assert.equal(replacement.data.uid, "replacement-user");
  assert.equal(replacement.data.email, "new.owner@example.com");
  assert.equal(replacement.data.name, "Auth Name");
  assert.equal(replacement.data.role, "owner");
  assert.equal(replacement.data.status, "active");
  assert.deepEqual(mutationAt(plan.mutations, "users/replacement-user").data, {
    membershipCount: 2,
    ownedTenantCount: 2,
    ownedActiveTenantCount: 2,
    updatedAt: TIMESTAMP,
  });
  assert.deepEqual(
    mutationAt(plan.mutations, "owner_recovery_cases/case-001").data,
    {
      status: "completed",
      completedBy: "platform-operator",
      completedOperationId: "recovery-operation-001",
      completedAt: TIMESTAMP,
      updatedAt: TIMESTAMP,
    }
  );
  assert.equal(
    mutationAt(plan.mutations, "platform_audit_logs/recovery-operation-001").data
      .supportReference,
    "SUP-8675309"
  );
});

test("normal recovery rejects a replacement who is not an active admin", () => {
  const invalidState = state("normal");
  invalidState.replacementStaff = document(
    "tenants/tenant-a/staff/replacement-user",
    {uid: "replacement-user", role: "manager", status: "active"}
  );

  assertRecoveryError(
    () => buildOwnerRecoveryPlan(input("normal"), invalidState, TIMESTAMP),
    "normal-replacement-ineligible"
  );
});

test("exceptional recovery rejects existing membership and mismatched confirmations", () => {
  const existingMember = state("exceptional");
  existingMember.replacementStaff = document(
    "tenants/tenant-a/staff/replacement-user",
    {uid: "replacement-user", role: "cashier", status: "active"}
  );
  existingMember.replacementMemberships = [existingMember.replacementStaff];
  assertRecoveryError(
    () => buildOwnerRecoveryPlan(input("exceptional"), existingMember, TIMESTAMP),
    "exceptional-replacement-ineligible"
  );

  const wrongConfirmation = input("exceptional");
  assert.ok(wrongConfirmation.confirmations);
  wrongConfirmation.confirmations = {
    ...wrongConfirmation.confirmations,
    oldOwnerUid: "wrong-owner",
  };
  assertRecoveryError(
    () => buildOwnerRecoveryPlan(wrongConfirmation, state("exceptional"), TIMESTAMP),
    "confirmation-mismatch"
  );
});

test("recovery fails closed when canonical owner evidence is duplicated or inconsistent", () => {
  const duplicateOwner = state("normal");
  duplicateOwner.tenantOwnerStaff = [
    duplicateOwner.oldOwnerStaff,
    document("tenants/tenant-a/staff/rogue-owner", {
      uid: "rogue-owner",
      role: "owner",
      status: "active",
    }),
  ];
  assertRecoveryError(
    () => buildOwnerRecoveryPlan(input("normal"), duplicateOwner, TIMESTAMP),
    "owner-invariant-invalid"
  );

  const mismatchedTenant = state("normal");
  mismatchedTenant.tenant = document("tenants/tenant-a", {
    name: "North Shop",
    slug: "north-shop",
    status: "active",
    ownerUid: "different-owner",
  });
  assertRecoveryError(
    () => buildOwnerRecoveryPlan(input("normal"), mismatchedTenant, TIMESTAMP),
    "owner-invariant-invalid"
  );

  const mismatchedMembershipId = state("normal");
  mismatchedMembershipId.replacementMemberships = [
    document("tenants/tenant-a/staff/alias-id", {
      uid: "replacement-user",
      role: "admin",
      status: "active",
    }),
  ];
  assertRecoveryError(
    () => buildOwnerRecoveryPlan(input("normal"), mismatchedMembershipId, TIMESTAMP),
    "owner-invariant-invalid"
  );
});

test("archived tenants and active identity transitions cannot be recovered", () => {
  const archived = state("normal");
  archived.tenant = document("tenants/tenant-a", {
    name: "North Shop",
    slug: "north-shop",
    status: "archived",
    ownerUid: "old-owner",
  });
  assertRecoveryError(
    () => buildOwnerRecoveryPlan(input("normal"), archived, TIMESTAMP),
    "tenant-ineligible"
  );

  const transitioning = state("normal");
  transitioning.replacementUser = document("users/replacement-user", {
    accountType: "tenant_user",
    globalStatus: "active",
    identityTransition: "granting_platform",
  });
  assertRecoveryError(
    () => buildOwnerRecoveryPlan(input("normal"), transitioning, TIMESTAMP),
    "replacement-ineligible"
  );
});

test("Auth checks require a real platform operator and verified non-platform exceptional target", () => {
  const exceptionalInput = input("exceptional");
  assert.doesNotThrow(() => assertRecoveryAuthIdentities(
    exceptionalInput,
    {
      uid: "platform-operator",
      disabled: false,
      customClaims: {platformRole: "superAdmin"},
    },
    {
      uid: "replacement-user",
      email: "replacement@example.com",
      disabled: false,
      emailVerified: true,
      customClaims: {supportTier: "standard"},
    }
  ));

  assertRecoveryError(() => assertRecoveryAuthIdentities(
    exceptionalInput,
    {uid: "platform-operator", disabled: false, customClaims: {}},
    {
      uid: "replacement-user",
      email: "replacement@example.com",
      emailVerified: true,
    }
  ), "operator-ineligible");

  assertRecoveryError(() => assertRecoveryAuthIdentities(
    exceptionalInput,
    {
      uid: "platform-operator",
      customClaims: {platformRole: "superAdmin"},
    },
    {
      uid: "replacement-user",
      email: "replacement@example.com",
      emailVerified: false,
    }
  ), "replacement-ineligible");

  assertRecoveryError(() => assertRecoveryAuthIdentities(
    exceptionalInput,
    {
      uid: "platform-operator",
      customClaims: {platformRole: "superAdmin"},
    },
    {
      uid: "replacement-user",
      email: "replacement@example.com",
      emailVerified: true,
      customClaims: {platformRole: "superAdmin"},
    }
  ), "replacement-ineligible");
});

test("service executes all writes in one store transaction and dry-run writes nothing", async () => {
  const dryRunHarness = serviceHarness("normal");
  const dryRunResult = await recoverTenantOwner(
    dryRunHarness.dependencies,
    {...input("normal"), dryRun: true}
  );
  assert.equal(dryRunHarness.transactionCalls(), 1);
  assert.equal(dryRunHarness.mutations.length, 0);
  assert.equal(dryRunResult.dryRun, true);
  assert.equal(dryRunResult.plannedWriteCount, 10);

  const executeHarness = serviceHarness("normal");
  const executeResult = await recoverTenantOwner(
    executeHarness.dependencies,
    input("normal")
  );
  assert.equal(executeHarness.transactionCalls(), 1);
  assert.equal(executeHarness.mutations.length, 10);
  assert.equal(executeResult.dryRun, false);
  assert.equal(executeResult.oldOwnerUid, "old-owner");
  assert.equal(executeResult.replacementUid, "replacement-user");
});
