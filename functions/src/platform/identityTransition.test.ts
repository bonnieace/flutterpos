import assert from "node:assert/strict";
import test from "node:test";
import {Firestore} from "firebase-admin/firestore";
import {RootUserRecord} from "../core/model";
import {
  acquireIdentityTransition,
  clearIdentityTransition,
  IdentityTransitionError,
} from "./identityTransition";

interface TransactionHarness {
  db: Firestore;
  updates: Array<Record<string, unknown>>;
  auditMerges: Array<{path: string; data: Record<string, unknown>}>;
}

function transactionHarness(user: RootUserRecord | undefined): TransactionHarness {
  const updates: Array<Record<string, unknown>> = [];
  const auditMerges: Array<{path: string; data: Record<string, unknown>}> = [];
  const userRef = {path: "users/target-user"};
  const db = {
    collection(name: string) {
      assert.equal(name, "users");
      return {
        doc(uid: string) {
          assert.equal(uid, "target-user");
          return userRef;
        },
      };
    },
    doc(path: string) {
      return {path};
    },
    async runTransaction<T>(callback: (transaction: object) => Promise<T>): Promise<T> {
      return callback({
        async get() {
          return {
            exists: user !== undefined,
            data: () => user,
          };
        },
        update(_reference: object, data: Record<string, unknown>) {
          updates.push(data);
        },
        set(
          reference: {path: string},
          data: Record<string, unknown>,
          options: {merge: boolean}
        ) {
          assert.deepEqual(options, {merge: true});
          auditMerges.push({path: reference.path, data});
        },
      });
    },
  } as unknown as Firestore;

  return {db, updates, auditMerges};
}

async function expectTransitionError(
  expectedCode: string,
  operation: Promise<unknown>
): Promise<void> {
  await assert.rejects(operation, (error: unknown) => {
    return error instanceof IdentityTransitionError && error.code === expectedCode;
  });
}

test("transition acquisition atomically locks the expected active root", async () => {
  const harness = transactionHarness({
    accountType: "tenant_user",
    globalStatus: "active",
  });

  const acquired = await acquireIdentityTransition(harness.db, {
    targetUid: "target-user",
    transition: "granting_platform",
    expectedAccountType: "tenant_user",
    audit: {
      documentPath: "platform_audit_logs/audit-1",
      data: {status: "transition_acquired"},
    },
  });

  assert.equal(acquired.resumed, false);
  assert.equal(harness.updates.length, 1);
  assert.equal(harness.updates[0].identityTransition, "granting_platform");
  assert.deepEqual(harness.auditMerges, [{
    path: "platform_audit_logs/audit-1",
    data: {status: "transition_acquired"},
  }]);
});

test("same transition can resume only from an explicitly allowed account type", async () => {
  const resumable = transactionHarness({
    accountType: "platform_admin",
    globalStatus: "active",
    identityTransition: "granting_platform",
  });
  const acquired = await acquireIdentityTransition(resumable.db, {
    targetUid: "target-user",
    transition: "granting_platform",
    expectedAccountType: "tenant_user",
    resumableAccountTypes: ["tenant_user", "platform_admin"],
  });

  assert.equal(acquired.resumed, true);
  assert.equal(resumable.updates.length, 0);

  const invalid = transactionHarness({
    accountType: "platform_admin",
    globalStatus: "active",
    identityTransition: "granting_platform",
  });
  await expectTransitionError("unexpected-account-type", acquireIdentityTransition(invalid.db, {
    targetUid: "target-user",
    transition: "granting_platform",
    expectedAccountType: "tenant_user",
  }));
});

test("acquire and clear reject inactive roots or an unexpected transition", async () => {
  const inactive = transactionHarness({
    accountType: "tenant_user",
    globalStatus: "disabled",
  });
  await expectTransitionError("root-user-inactive", acquireIdentityTransition(inactive.db, {
    targetUid: "target-user",
    transition: "granting_platform",
    expectedAccountType: "tenant_user",
  }));

  const conflicting = transactionHarness({
    accountType: "tenant_user",
    globalStatus: "active",
    identityTransition: "cleanup_pending",
  });
  await expectTransitionError("identity-transition-conflict", acquireIdentityTransition(
    conflicting.db,
    {
      targetUid: "target-user",
      transition: "granting_platform",
      expectedAccountType: "tenant_user",
    }
  ));

  await expectTransitionError("identity-transition-not-held", clearIdentityTransition(
    conflicting.db,
    {
      targetUid: "target-user",
      expectedTransition: "granting_platform",
      expectedAccountTypes: ["tenant_user"],
    }
  ));
  assert.equal(conflicting.updates.length, 0);
});

test("clear verifies the held transition and merges its completion audit", async () => {
  const harness = transactionHarness({
    accountType: "platform_admin",
    globalStatus: "active",
    identityTransition: "granting_platform",
  });

  await clearIdentityTransition(harness.db, {
    targetUid: "target-user",
    expectedTransition: "granting_platform",
    expectedAccountTypes: ["platform_admin"],
    audit: {
      documentPath: "platform_audit_logs/audit-2",
      data: {status: "completed"},
    },
  });

  assert.equal(harness.updates.length, 1);
  assert.ok("identityTransition" in harness.updates[0]);
  assert.deepEqual(harness.auditMerges, [{
    path: "platform_audit_logs/audit-2",
    data: {status: "completed"},
  }]);
});
