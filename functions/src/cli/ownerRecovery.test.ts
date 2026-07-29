import assert from "node:assert/strict";
import test from "node:test";
import {parseOwnerRecoveryCliArgs} from "./ownerRecovery";

const COMMON_ARGUMENTS = [
  "--project-id", "multitenant-pos-dev",
  "--operator-uid", "platform-operator",
  "--tenant-id", "tenant-a",
  "--replacement-uid", "replacement-user",
  "--operation-id", "recovery-operation-001",
  "--reason", "Support verified the requested owner recovery.",
];

test("CLI parses a dry-run normal recovery without exceptional controls", () => {
  const parsed = parseOwnerRecoveryCliArgs([...COMMON_ARGUMENTS, "--dry-run"]);

  assert.equal(parsed.projectId, "multitenant-pos-dev");
  assert.deepEqual(parsed.input, {
    operatorUid: "platform-operator",
    tenantId: "tenant-a",
    replacementUid: "replacement-user",
    operationId: "recovery-operation-001",
    reason: "Support verified the requested owner recovery.",
    mode: "normal",
    dryRun: true,
  });
});

test("CLI requires every exceptional case and confirmation control", () => {
  const complete = [
    ...COMMON_ARGUMENTS,
    "--exceptional",
    "--case-id", "case-001",
    "--support-reference", "SUP-8675309",
    "--confirm-tenant-slug", "north-shop",
    "--confirm-old-owner-uid", "old-owner",
    "--confirm-replacement-uid", "replacement-user",
    "--confirm-exactly-one-owner",
  ];
  const parsed = parseOwnerRecoveryCliArgs(complete);

  assert.equal(parsed.input.mode, "exceptional");
  assert.deepEqual(parsed.input.confirmations, {
    tenantSlug: "north-shop",
    oldOwnerUid: "old-owner",
    replacementUid: "replacement-user",
    secondConfirmation: true,
  });

  assert.throws(
    () => parseOwnerRecoveryCliArgs(
      complete.filter((argument) => argument !== "--confirm-exactly-one-owner")
    ),
    /--confirm-exactly-one-owner is required/
  );
});

test("CLI rejects duplicate, unknown, and exceptional-only normal arguments", () => {
  assert.throws(
    () => parseOwnerRecoveryCliArgs([...COMMON_ARGUMENTS, "--tenant-id", "tenant-b"]),
    /--tenant-id was supplied more than once/
  );
  assert.throws(
    () => parseOwnerRecoveryCliArgs([...COMMON_ARGUMENTS, "--surprise"]),
    /Unknown argument/
  );
  assert.throws(
    () => parseOwnerRecoveryCliArgs([
      ...COMMON_ARGUMENTS,
      "--support-reference", "SUP-1",
    ]),
    /Exceptional controls require --exceptional/
  );
});
