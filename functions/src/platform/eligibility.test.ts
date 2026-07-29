import assert from "node:assert/strict";
import test from "node:test";
import {Firestore} from "firebase-admin/firestore";
import {
  evaluatePlatformEligibility,
  isUnresolvedInvitationStatus,
  PLATFORM_ELIGIBILITY_SCAN_SOURCES,
  PlatformEligibilityEvidence,
  scanPlatformEligibility,
} from "./eligibility";

function emptyEvidence(): PlatformEligibilityEvidence {
  return {
    targetUid: "target-user",
    scannedSources: [...PLATFORM_ELIGIBILITY_SCAN_SOURCES],
    staffMemberships: [],
    ownedTenants: [],
    unresolvedInvitations: [],
  };
}

test("canonical membership blocks a grant even when every counter is zero", () => {
  const evidence = emptyEvidence();
  const evaluation = evaluatePlatformEligibility({
    ...evidence,
    staffMemberships: [{
      kind: "staff_membership",
      documentPath: "tenants/t-1/staff/target-user",
      status: "inactive",
    }],
  }, {
    membershipCount: 0,
    ownedTenantCount: 0,
    ownedActiveTenantCount: 0,
  });

  assert.equal(evaluation.eligible, false);
  assert.deepEqual(evaluation.blockers.map((blocker) => blocker.kind), [
    "staff_membership",
  ]);
  assert.ok(evaluation.warnings.includes("membership_counter_underreports"));
});

test("positive advisory counters warn but cannot reject clear canonical scans", () => {
  const evaluation = evaluatePlatformEligibility(emptyEvidence(), {
    membershipCount: 4,
    ownedTenantCount: 2,
    ownedActiveTenantCount: 1,
  });

  assert.equal(evaluation.eligible, true);
  assert.deepEqual(evaluation.blockers, []);
  assert.deepEqual(evaluation.warnings, [
    "membership_counter_positive",
    "owned_tenant_counter_positive",
    "owned_active_tenant_counter_positive",
  ]);
});

test("unknown invitation states fail closed", () => {
  assert.equal(isUnresolvedInvitationStatus(undefined), true);
  assert.equal(isUnresolvedInvitationStatus("sent"), true);
  assert.equal(isUnresolvedInvitationStatus("future_new_state"), true);
  assert.equal(isUnresolvedInvitationStatus("accepted"), false);
  assert.equal(isUnresolvedInvitationStatus(" CANCELLED "), false);
});

interface FakeDocument {
  ref: {path: string};
  data(): Record<string, unknown>;
}

function fakeDocument(path: string, data: Record<string, unknown>): FakeDocument {
  return {ref: {path}, data: () => data};
}

test("Firestore scan queries all canonical sources by server-controlled UID", async () => {
  const calls: string[] = [];
  const documents: Record<string, FakeDocument[]> = {
    staff: [fakeDocument("tenants/t-1/staff/target-user", {
      uid: "target-user",
      status: "pending",
    })],
    tenants: [fakeDocument("tenants/t-2", {
      ownerUid: "target-user",
      status: "archived",
    })],
    staff_invitations: [
      fakeDocument("tenants/t-3/staff_invitations/target-user", {
        uid: "target-user",
        invitationStatus: "sent",
      }),
      fakeDocument("tenants/t-4/staff_invitations/target-user", {
        uid: "target-user",
        invitationStatus: "accepted",
      }),
    ],
  };

  function fakeQuery(source: string): object {
    return {
      where(field: string, operator: string, value: string) {
        calls.push(`${source}:${field}:${operator}:${value}`);
        return this;
      },
      async get() {
        return {docs: documents[source]};
      },
    };
  }

  const fakeDb = {
    collectionGroup(name: string) {
      calls.push(`collectionGroup:${name}`);
      return fakeQuery(name);
    },
    collection(name: string) {
      calls.push(`collection:${name}`);
      return fakeQuery(name);
    },
  } as unknown as Firestore;

  const evidence = await scanPlatformEligibility(fakeDb, "target-user");

  assert.deepEqual(calls, [
    "collectionGroup:staff",
    "staff:uid:==:target-user",
    "collection:tenants",
    "tenants:ownerUid:==:target-user",
    "collectionGroup:staff_invitations",
    "staff_invitations:uid:==:target-user",
  ]);
  assert.deepEqual(evidence.scannedSources, PLATFORM_ELIGIBILITY_SCAN_SOURCES);
  assert.equal(evidence.staffMemberships.length, 1);
  assert.equal(evidence.ownedTenants.length, 1);
  assert.deepEqual(
    evidence.unresolvedInvitations.map((item) => item.documentPath),
    ["tenants/t-3/staff_invitations/target-user"]
  );
});
