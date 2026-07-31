import assert from "node:assert/strict";
import test from "node:test";
import {
  describePlatformAdminRevokeFailure,
  parsePlatformAdminRevokeCliArgs,
} from "./revokePlatformAdmin";
import {PlatformGrantCliInputError} from "./grantPlatformAdmin";
import {PlatformAdminRevocationError} from "../platform/revokePlatformAdmin";

const DEV_ARGUMENTS = [
  "--environment", "dev",
  "--project-id", "multitenant-pos-b8326",
  "--confirm-project-id", "multitenant-pos-b8326",
  "--actor-uid", "platform-operator",
  "--target-uid", "platform-target",
  "--confirm-target-uid", "platform-target",
  "--request-id", "platform-revoke-request-001",
  "--reason", "  Access is no longer required.  ",
];

test("CLI parses an explicit allowlisted revocation", () => {
  assert.deepEqual(parsePlatformAdminRevokeCliArgs(DEV_ARGUMENTS), {
    environment: "dev",
    projectId: "multitenant-pos-b8326",
    input: {
      actorUid: "platform-operator",
      targetUid: "platform-target",
      requestId: "platform-revoke-request-001",
      reason: "Access is no longer required.",
    },
  });
});

test("revocation cannot infer staging or production", () => {
  assert.throws(
    () => parsePlatformAdminRevokeCliArgs(DEV_ARGUMENTS.map((value) =>
      value === "multitenant-pos-b8326" ? "chilltent-pos-staging" : value
    )),
    /not allowlisted for dev/
  );
  const production = DEV_ARGUMENTS.flatMap((value) => {
    if (value === "dev") return ["prod"];
    if (value === "multitenant-pos-b8326") return ["chilltent-pos-prod"];
    return [value];
  });
  assert.throws(
    () => parsePlatformAdminRevokeCliArgs(production),
    /--confirm-production is required/
  );
  assert.equal(
    parsePlatformAdminRevokeCliArgs([...production, "--confirm-production"])
      .projectId,
    "chilltent-pos-prod"
  );
});

test("CLI requires a different actor and exact destructive confirmation", () => {
  assert.throws(
    () => parsePlatformAdminRevokeCliArgs(DEV_ARGUMENTS.map((value) =>
      value === "platform-target" ? "platform-operator" : value
    )),
    /must identify different users/
  );
  const wrongConfirmation = [...DEV_ARGUMENTS];
  wrongConfirmation[11] = "different-target";
  assert.throws(
    () => parsePlatformAdminRevokeCliArgs(wrongConfirmation),
    /--confirm-target-uid must exactly match/
  );
});

test("revocation failures map to stable safe exit states", () => {
  assert.deepEqual(
    describePlatformAdminRevokeFailure(new PlatformGrantCliInputError("secret")),
    {
      exitCode: 2,
      output: {status: "rejected", code: "invalid-input", recoverable: false},
    }
  );
  assert.deepEqual(
    describePlatformAdminRevokeFailure(new PlatformAdminRevocationError(
      "last-platform-admin",
      "sensitive scan evidence",
      false
    )),
    {
      exitCode: 4,
      output: {
        status: "rejected",
        code: "last-platform-admin",
        recoverable: false,
      },
    }
  );
  const retryable = describePlatformAdminRevokeFailure(
    new PlatformAdminRevocationError(
      "claim-removal-failed",
      "provider details",
      true
    )
  );
  assert.equal(retryable.exitCode, 5);
  assert.match(retryable.output.retryGuidance ?? "", /same request ID/);
  assert.equal(JSON.stringify(retryable).includes("provider details"), false);
});
