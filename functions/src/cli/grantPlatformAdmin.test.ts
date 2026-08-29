import assert from "node:assert/strict";
import test from "node:test";
import {Firestore} from "firebase-admin/firestore";
import {
  assertPlatformGrantRuntimeRouting,
  describePlatformAdminGrantFailure,
  parsePlatformAdminGrantCliArgs,
  PlatformGrantCliInputError,
  PlatformGrantOperatorError,
  requireBootstrapEligible,
  requirePlatformGrantOperator,
} from "./grantPlatformAdmin";
import {FakeFirestore} from "../testing/fakeFirestore";
import {PlatformAdminGrantError} from "../platform/grantPlatformAdmin";
import {IdentityTransitionError} from "../platform/identityTransition";

const DEV_ARGUMENTS = [
  "--environment", "dev",
  "--project-id", "multitenant-pos-b8326",
  "--confirm-project-id", "multitenant-pos-b8326",
  "--actor-uid", "platform-operator",
  "--target-uid", "target-user",
  "--confirm-target-uid", "target-user",
  "--request-id", "platform-grant-request-001",
  "--reason", "  Approved   by the security team.  ",
];

test("CLI parses an explicitly confirmed allowlisted development grant", () => {
  assert.deepEqual(parsePlatformAdminGrantCliArgs(DEV_ARGUMENTS), {
    environment: "dev",
    projectId: "multitenant-pos-b8326",
    input: {
      actorUid: "platform-operator",
      targetUid: "target-user",
      requestId: "platform-grant-request-001",
      reason: "Approved by the security team.",
    },
  });
});

test("project selection cannot imply staging or production", () => {
  assert.throws(
    () => parsePlatformAdminGrantCliArgs(DEV_ARGUMENTS.map((value) =>
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
    () => parsePlatformAdminGrantCliArgs(production),
    /--confirm-production is required/
  );
  assert.equal(
    parsePlatformAdminGrantCliArgs([...production, "--confirm-production"])
      .projectId,
    "chilltent-pos-prod"
  );
});

test("CLI rejects confirmation, identity, request, and reason mistakes", () => {
  assert.throws(
    () => parsePlatformAdminGrantCliArgs(DEV_ARGUMENTS.map((value) =>
      value === "target-user" ? "different-user" : value
    ).map((value, index) => index === 11 ? "target-user" : value)),
    /--confirm-target-uid must exactly match/
  );
  assert.throws(
    () => parsePlatformAdminGrantCliArgs([
      ...DEV_ARGUMENTS,
      "--target-uid", "second-target",
    ]),
    /was supplied more than once/
  );
  assert.throws(
    () => parsePlatformAdminGrantCliArgs(DEV_ARGUMENTS.map((value) =>
      value === "platform-grant-request-001" ? "short" : value
    )),
    /request-id has an invalid format/
  );
  assert.throws(
    () => parsePlatformAdminGrantCliArgs(DEV_ARGUMENTS.map((value) =>
      value.includes("Approved") ? " x " : value
    )),
    /reason must be between 3 and 1000/
  );
});

test("emulator routing is localhost-only and cannot leak into real grants", () => {
  assert.doesNotThrow(() => assertPlatformGrantRuntimeRouting("emulator", {
    FIREBASE_AUTH_EMULATOR_HOST: "127.0.0.1:9199",
    FIRESTORE_EMULATOR_HOST: "localhost:8180",
  }));
  assert.throws(
    () => assertPlatformGrantRuntimeRouting("emulator", {}),
    /requires localhost Auth and Firestore emulators/
  );
  assert.throws(
    () => assertPlatformGrantRuntimeRouting("dev", {
      FIRESTORE_EMULATOR_HOST: "127.0.0.1:8180",
    }),
    /Clear Auth and Firestore emulator host variables/
  );
});

function operatorHarness(options: {
  disabled?: boolean;
  platformRole?: string;
  accountType?: string;
  globalStatus?: string;
  readError?: Error;
} = {}) {
  const db = {
    collection() {
      return {
        doc() {
          return {
            async get() {
              if (options.readError) throw options.readError;
              return {
                exists: true,
                data: () => ({
                  accountType: options.accountType ?? "platform_admin",
                  globalStatus: options.globalStatus ?? "active",
                }),
              };
            },
          };
        },
      };
    },
  } as unknown as Firestore;
  return {
    db,
    auth: {
      async getUser(uid: string) {
        if (options.readError) throw options.readError;
        return {
          uid,
          disabled: options.disabled ?? false,
          customClaims: {platformRole: options.platformRole ?? "superAdmin"},
        };
      },
      async setCustomUserClaims() {},
    },
  };
}

test("operator authorization requires both the active Auth claim and root", async () => {
  await assert.doesNotReject(requirePlatformGrantOperator(
    operatorHarness(),
    "platform-operator"
  ));
  for (const harness of [
    operatorHarness({disabled: true}),
    operatorHarness({platformRole: "viewer"}),
    operatorHarness({accountType: "tenant_user"}),
    operatorHarness({globalStatus: "disabled"}),
  ]) {
    await assert.rejects(
      requirePlatformGrantOperator(harness, "platform-operator"),
      (error: unknown) => error instanceof PlatformGrantOperatorError &&
        error.code === "operator-unauthorized" && !error.recoverable
    );
  }
});

test("operator verification outages remain recoverable", async () => {
  await assert.rejects(
    requirePlatformGrantOperator(
      operatorHarness({readError: new Error("unavailable")}),
      "platform-operator"
    ),
    (error: unknown) => error instanceof PlatformGrantOperatorError &&
      error.code === "operator-verification-failed" && error.recoverable
  );
});

test("CLI failure descriptions have stable safe exit states", () => {
  assert.deepEqual(
    describePlatformAdminGrantFailure(new PlatformGrantCliInputError("secret")),
    {
      exitCode: 2,
      output: {status: "rejected", code: "invalid-input", recoverable: false},
    }
  );
  assert.deepEqual(
    describePlatformAdminGrantFailure(new PlatformGrantOperatorError(
      "operator-unauthorized",
      false
    )).exitCode,
    3
  );
  const rejected = describePlatformAdminGrantFailure(new PlatformAdminGrantError(
    "platform-identity-ineligible",
    "sensitive evidence",
    false
  ));
  assert.deepEqual(rejected, {
    exitCode: 4,
    output: {
      status: "rejected",
      code: "platform-identity-ineligible",
      recoverable: false,
    },
  });
  const retryable = describePlatformAdminGrantFailure(new PlatformAdminGrantError(
    "custom-claims-update-failed",
    "provider details",
    true
  ));
  assert.equal(retryable.exitCode, 5);
  assert.equal(retryable.output.status, "partially_failed");
  assert.equal(retryable.output.recoverable, true);
  assert.match(retryable.output.retryGuidance ?? "", /same request ID/);
  assert.equal(JSON.stringify(retryable).includes("provider details"), false);
  assert.deepEqual(
    describePlatformAdminGrantFailure(new IdentityTransitionError(
      "identity-transition-conflict",
      "sensitive transition state"
    )),
    {
      exitCode: 4,
      output: {
        status: "rejected",
        code: "identity-transition-conflict",
        recoverable: false,
      },
    }
  );
});

// ---------------------------------------------------------------------------
// --bootstrap: the very first platform administrator
// ---------------------------------------------------------------------------

const BOOTSTRAP_ARGUMENTS = [
  "--bootstrap",
  "--environment", "dev",
  "--project-id", "multitenant-pos-b8326",
  "--confirm-project-id", "multitenant-pos-b8326",
  "--target-uid", "founder",
  "--confirm-target-uid", "founder",
  "--request-id", "platform-grant-request-001",
  "--reason", "Bootstrapping the first platform administrator.",
];

test("a bootstrap needs no actor and records the target as its own", () => {
  assert.deepEqual(parsePlatformAdminGrantCliArgs(BOOTSTRAP_ARGUMENTS), {
    environment: "dev",
    projectId: "multitenant-pos-b8326",
    input: {
      actorUid: "founder",
      targetUid: "founder",
      requestId: "platform-grant-request-001",
      reason: "Bootstrapping the first platform administrator.",
      bootstrap: true,
    },
  });
});

test("a bootstrap refuses an actor rather than quietly ignoring one", () => {
  assert.throws(
    () => parsePlatformAdminGrantCliArgs([
      ...BOOTSTRAP_ARGUMENTS, "--actor-uid", "someone",
    ]),
    /--actor-uid is not accepted with --bootstrap/
  );
});

test("the ordinary form still refuses a self-grant", () => {
  assert.throws(
    () => parsePlatformAdminGrantCliArgs(DEV_ARGUMENTS.map((value) =>
      value === "platform-operator" ? "target-user" : value
    )),
    /must identify different users/
  );
});

test("--bootstrap is refused when it is supplied twice", () => {
  assert.throws(
    () => parsePlatformAdminGrantCliArgs([...BOOTSTRAP_ARGUMENTS, "--bootstrap"]),
    /supplied more than once/
  );
});

test("a bootstrap is allowed on a project with no platform administrator", async () => {
  const db = new FakeFirestore();
  await db.collection("users").doc("founder").set({
    accountType: "tenant_user",
    globalStatus: "active",
  });

  await requireBootstrapEligible({db: db.asFirestore(), auth: UNUSED_AUTH}, "founder");
});

test("a bootstrap is refused once any platform administrator exists", async () => {
  const db = new FakeFirestore();
  await db.collection("users").doc("sitting-admin").set({
    accountType: "platform_admin",
    globalStatus: "active",
  });

  await assert.rejects(
    () => requireBootstrapEligible({db: db.asFirestore(), auth: UNUSED_AUTH}, "founder"),
    (error: unknown) => error instanceof PlatformGrantOperatorError &&
      error.code === "bootstrap-not-eligible" && !error.recoverable
  );
});

test("a bootstrap is refused while another grant is in flight", async () => {
  const db = new FakeFirestore();
  await db.collection("users").doc("someone-else").set({
    accountType: "tenant_user",
    identityTransition: "granting_platform",
  });

  await assert.rejects(
    () => requireBootstrapEligible({db: db.asFirestore(), auth: UNUSED_AUTH}, "founder"),
    (error: unknown) => error instanceof PlatformGrantOperatorError &&
      error.code === "bootstrap-not-eligible"
  );
});

test("the target's own half-finished grant does not refuse its own retry", async () => {
  // `grantPlatformAdmin` is a resumable saga and the documented recovery from a
  // recoverable failure is to re-run with the same request ID. Counting the
  // target's own in-flight transition as "an administrator already exists"
  // would strand a project with no administrator and no way to make one.
  const db = new FakeFirestore();
  await db.collection("users").doc("founder").set({
    accountType: "tenant_user",
    identityTransition: "granting_platform",
  });

  await requireBootstrapEligible({db: db.asFirestore(), auth: UNUSED_AUTH}, "founder");
});

test("a target already carrying the privilege can be re-run to completion", async () => {
  const db = new FakeFirestore();
  await db.collection("users").doc("founder").set({
    accountType: "platform_admin",
    globalStatus: "active",
  });

  await requireBootstrapEligible({db: db.asFirestore(), auth: UNUSED_AUTH}, "founder");
});

/** The bootstrap check never reaches Auth; this proves it by exploding if it does. */
const UNUSED_AUTH = new Proxy({}, {
  get() {
    throw new Error("The bootstrap eligibility check must not call Auth.");
  },
}) as never;
