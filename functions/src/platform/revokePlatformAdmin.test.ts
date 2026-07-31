import assert from "node:assert/strict";
import test from "node:test";
import {
  assertAnotherFullyActivePlatformAdmin,
  isFullyActivePlatformAdmin,
  PlatformAdminRevocationError,
} from "./revokePlatformAdmin";

const activeRoot = {
  accountType: "platform_admin" as const,
  globalStatus: "active" as const,
};
const activeAuth = {
  uid: "operator",
  disabled: false,
  customClaims: {platformRole: "superAdmin"},
};

test("fully active platform admins require root, claim, and no transition", () => {
  assert.equal(isFullyActivePlatformAdmin(activeRoot, activeAuth), true);
  assert.equal(isFullyActivePlatformAdmin(
    {...activeRoot, identityTransition: "revoking_platform"},
    activeAuth
  ), false);
  assert.equal(isFullyActivePlatformAdmin(activeRoot, {
    ...activeAuth,
    disabled: true,
  }), false);
  assert.equal(isFullyActivePlatformAdmin(activeRoot, {
    ...activeAuth,
    customClaims: {},
  }), false);
});

test("last-admin evaluation denies a complete scan with no other admin", () => {
  assert.throws(
    () => assertAnotherFullyActivePlatformAdmin({
      candidateRootsScanned: 1,
      fullyActiveOtherUids: [],
      truncated: false,
      scanLimit: 100,
    }),
    (error: unknown) => error instanceof PlatformAdminRevocationError &&
      error.code === "last-platform-admin" && !error.recoverable
  );
});

test("a truncated inconclusive admin scan fails recoverably", () => {
  assert.throws(
    () => assertAnotherFullyActivePlatformAdmin({
      candidateRootsScanned: 100,
      fullyActiveOtherUids: [],
      truncated: true,
      scanLimit: 100,
    }),
    (error: unknown) => error instanceof PlatformAdminRevocationError &&
      error.code === "admin-scan-failed" && error.recoverable
  );
  assert.doesNotThrow(() => assertAnotherFullyActivePlatformAdmin({
    candidateRootsScanned: 100,
    fullyActiveOtherUids: ["known-good-admin"],
    truncated: true,
    scanLimit: 100,
  }));
});
