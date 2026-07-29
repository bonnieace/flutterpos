import assert from "node:assert/strict";
import test from "node:test";
import {isEmailEligibleRoot} from "./rootEligibility";

test("email delivery requires an active canonical root with a valid account type", () => {
  assert.equal(isEmailEligibleRoot(undefined), false);
  assert.equal(isEmailEligibleRoot({
    globalStatus: "disabled",
    accountType: "tenant_user",
  }), false);
  assert.equal(isEmailEligibleRoot({globalStatus: "active"}), false);
  assert.equal(isEmailEligibleRoot({
    globalStatus: "active",
    accountType: "tenant_user",
  }), true);
  assert.equal(isEmailEligibleRoot({
    globalStatus: "active",
    accountType: "platform_admin",
  }), true);
});

test("authenticated delivery honors the root sign-in cutoff", () => {
  const root = {
    globalStatus: "active" as const,
    accountType: "tenant_user" as const,
    authValidAfterSeconds: 1_000,
  };
  assert.equal(isEmailEligibleRoot(root, 999), false);
  assert.equal(isEmailEligibleRoot(root, 1_000), true);
});
