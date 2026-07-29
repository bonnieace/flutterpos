import assert from "node:assert/strict";
import test from "node:test";
import {HttpsError} from "firebase-functions/v2/https";
import {assertTenantIdentityTarget} from "./identity";

function expectCode(code: string, callback: () => unknown): void {
  assert.throws(callback, (error: unknown) =>
    error instanceof HttpsError && error.code === code
  );
}

test("tenant invitation target rejects platform records and claims", () => {
  expectCode("permission-denied", () => assertTenantIdentityTarget({
    accountType: "platform_admin",
    globalStatus: "active",
  }, {requireActive: true}));
  expectCode("permission-denied", () => assertTenantIdentityTarget({
    accountType: "tenant_user",
    globalStatus: "active",
  }, {requireActive: true, hasPlatformClaim: true}));
});

test("tenant invitation target rejects identity-transition races", () => {
  expectCode("aborted", () => assertTenantIdentityTarget({
    accountType: "tenant_user",
    globalStatus: "active",
    identityTransition: "granting_platform",
  }, {requireActive: true}));
});
