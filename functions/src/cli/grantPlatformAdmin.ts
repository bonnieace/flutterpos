import {applicationDefault, getApps, initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {Firestore, getFirestore} from "firebase-admin/firestore";
import {RootUserRecord} from "../core/model";
import {
  CustomClaimsClient,
  GrantPlatformAdminInput,
  GrantPlatformAdminResult,
  grantPlatformAdmin,
  PlatformAdminGrantError,
} from "../platform/grantPlatformAdmin";
import {IdentityTransitionError} from "../platform/identityTransition";

export const PLATFORM_GRANT_PROJECTS = {
  dev: "multitenant-pos-b8326",
  staging: "chilltent-pos-staging",
  prod: "chilltent-pos-prod",
  emulator: "demo-multitenant-invitation-integration",
} as const;

export type PlatformGrantEnvironment = keyof typeof PLATFORM_GRANT_PROJECTS;

export const GRANT_PLATFORM_ADMIN_USAGE = `
grant-platform-admin --environment ENV --project-id PROJECT \\
  --confirm-project-id PROJECT --actor-uid UID --target-uid UID \\
  --confirm-target-uid UID --request-id ID --reason TEXT

ENV must be dev, staging, or prod and PROJECT must exactly match the source-
controlled allowlist. Production additionally requires --confirm-production.
The emulator environment is reserved for the fixed localhost integration test.

Run from functions/ after building, using Application Default Credentials that
are authorized for the explicitly supplied Firebase project. Retain the
request ID: a recoverable failure must be retried with the same arguments.
`.trim();

export interface PlatformGrantAuthClient extends CustomClaimsClient {
  getUser(uid: string): Promise<{
    uid: string;
    disabled: boolean;
    customClaims?: Record<string, unknown>;
  }>;
}

export interface PlatformAdminGrantCliArguments {
  environment: PlatformGrantEnvironment;
  projectId: string;
  input: GrantPlatformAdminInput;
}

export interface ExecutePlatformAdminGrantDependencies {
  db: Firestore;
  auth: PlatformGrantAuthClient;
}

export type PlatformGrantOperatorErrorCode =
  | "operator-unauthorized"
  | "operator-verification-failed";

export class PlatformGrantOperatorError extends Error {
  constructor(
    readonly code: PlatformGrantOperatorErrorCode,
    readonly recoverable: boolean,
    readonly underlyingError?: unknown
  ) {
    super(code === "operator-unauthorized" ?
      "The authenticated operator is not an active platform administrator." :
      "The operator authorization state could not be verified."
    );
    this.name = "PlatformGrantOperatorError";
  }
}

export class PlatformGrantCliInputError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "PlatformGrantCliInputError";
  }
}

export interface PlatformGrantCliFailure {
  exitCode: number;
  output: {
    status: "rejected" | "partially_failed" | "failed";
    code: string;
    recoverable: boolean;
    retryGuidance?: string;
  };
}

const VALUE_FLAGS = new Set([
  "--environment",
  "--project-id",
  "--confirm-project-id",
  "--actor-uid",
  "--target-uid",
  "--confirm-target-uid",
  "--request-id",
  "--reason",
]);
const DOCUMENT_ID_PATTERN = /^[^/]{1,128}$/;
const REQUEST_ID_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._:-]{7,127}$/;
const LOCAL_EMULATOR_HOST_PATTERN = /^(127\.0\.0\.1|localhost):\d+$/;

function requiredValue(values: ReadonlyMap<string, string>, flag: string): string {
  const value = values.get(flag)?.trim();
  if (!value) throw new PlatformGrantCliInputError(`${flag} is required.`);
  return value;
}

function requireDocumentId(value: string, flag: string): string {
  if (!DOCUMENT_ID_PATTERN.test(value) || value === "." || value === "..") {
    throw new PlatformGrantCliInputError(`${flag} has an invalid format.`);
  }
  return value;
}

function normalizeReason(value: string): string {
  const normalized = value.trim().replace(/\s+/g, " ");
  if (normalized.length < 3 || normalized.length > 1000) {
    throw new PlatformGrantCliInputError(
      "--reason must be between 3 and 1000 normalized characters."
    );
  }
  return normalized;
}

function parseEnvironment(value: string): PlatformGrantEnvironment {
  if (!Object.prototype.hasOwnProperty.call(PLATFORM_GRANT_PROJECTS, value)) {
    throw new PlatformGrantCliInputError(
      "--environment must be dev, staging, prod, or emulator."
    );
  }
  return value as PlatformGrantEnvironment;
}

export function parsePlatformAdminGrantCliArgs(
  argv: readonly string[]
): PlatformAdminGrantCliArguments {
  const values = new Map<string, string>();
  const switches = new Set<string>();

  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (VALUE_FLAGS.has(argument)) {
      if (values.has(argument)) {
        throw new PlatformGrantCliInputError(
          `${argument} was supplied more than once.`
        );
      }
      const value = argv[index + 1];
      if (value === undefined || value.startsWith("--")) {
        throw new PlatformGrantCliInputError(`${argument} requires a value.`);
      }
      values.set(argument, value);
      index += 1;
      continue;
    }
    if (argument === "--confirm-production") {
      if (switches.has(argument)) {
        throw new PlatformGrantCliInputError(
          "--confirm-production was supplied more than once."
        );
      }
      switches.add(argument);
      continue;
    }
    if (argument === "--help" || argument === "-h") {
      throw new PlatformGrantCliInputError(GRANT_PLATFORM_ADMIN_USAGE);
    }
    throw new PlatformGrantCliInputError(`Unknown argument: ${argument}`);
  }

  const environment = parseEnvironment(requiredValue(values, "--environment"));
  const projectId = requiredValue(values, "--project-id");
  const allowedProjectId = PLATFORM_GRANT_PROJECTS[environment];
  if (projectId !== allowedProjectId) {
    throw new PlatformGrantCliInputError(
      `Project ${projectId} is not allowlisted for ${environment}.`
    );
  }
  if (requiredValue(values, "--confirm-project-id") !== projectId) {
    throw new PlatformGrantCliInputError(
      "--confirm-project-id must exactly match --project-id."
    );
  }
  if (environment === "prod" && !switches.has("--confirm-production")) {
    throw new PlatformGrantCliInputError(
      "--confirm-production is required for the production project."
    );
  }
  if (environment !== "prod" && switches.has("--confirm-production")) {
    throw new PlatformGrantCliInputError(
      "--confirm-production is valid only with --environment prod."
    );
  }

  const actorUid = requireDocumentId(
    requiredValue(values, "--actor-uid"),
    "--actor-uid"
  );
  const targetUid = requireDocumentId(
    requiredValue(values, "--target-uid"),
    "--target-uid"
  );
  if (actorUid === targetUid) {
    throw new PlatformGrantCliInputError(
      "--actor-uid and --target-uid must identify different users."
    );
  }
  if (requiredValue(values, "--confirm-target-uid") !== targetUid) {
    throw new PlatformGrantCliInputError(
      "--confirm-target-uid must exactly match --target-uid."
    );
  }
  const requestId = requiredValue(values, "--request-id");
  if (!REQUEST_ID_PATTERN.test(requestId)) {
    throw new PlatformGrantCliInputError("--request-id has an invalid format.");
  }

  return {
    environment,
    projectId,
    input: {
      actorUid,
      targetUid,
      requestId,
      reason: normalizeReason(requiredValue(values, "--reason")),
    },
  };
}

export function assertPlatformGrantRuntimeRouting(
  environment: PlatformGrantEnvironment,
  variables: Readonly<Record<string, string | undefined>>
): void {
  const authHost = variables.FIREBASE_AUTH_EMULATOR_HOST;
  const firestoreHost = variables.FIRESTORE_EMULATOR_HOST;
  if (environment === "emulator") {
    if (!authHost || !LOCAL_EMULATOR_HOST_PATTERN.test(authHost) ||
      !firestoreHost || !LOCAL_EMULATOR_HOST_PATTERN.test(firestoreHost)) {
      throw new PlatformGrantCliInputError(
        "The emulator environment requires localhost Auth and Firestore emulators."
      );
    }
    return;
  }
  if (authHost || firestoreHost) {
    throw new PlatformGrantCliInputError(
      "Clear Auth and Firestore emulator host variables for a real project grant."
    );
  }
}

export async function requirePlatformGrantOperator(
  dependencies: ExecutePlatformAdminGrantDependencies,
  actorUid: string
): Promise<void> {
  try {
    const [authUser, rootSnapshot] = await Promise.all([
      dependencies.auth.getUser(actorUid),
      dependencies.db.collection("users").doc(actorUid).get(),
    ]);
    const root = rootSnapshot.exists ? rootSnapshot.data() as RootUserRecord : undefined;
    if (authUser.uid !== actorUid || authUser.disabled ||
      authUser.customClaims?.platformRole !== "superAdmin" ||
      root?.accountType !== "platform_admin" || root.globalStatus !== "active" ||
      root.identityTransition !== undefined) {
      throw new PlatformGrantOperatorError("operator-unauthorized", false);
    }
  } catch (error) {
    if (error instanceof PlatformGrantOperatorError) throw error;
    throw new PlatformGrantOperatorError(
      "operator-verification-failed",
      true,
      error
    );
  }
}

export async function executePlatformAdminGrant(
  dependencies: ExecutePlatformAdminGrantDependencies,
  input: GrantPlatformAdminInput
): Promise<GrantPlatformAdminResult> {
  await requirePlatformGrantOperator(dependencies, input.actorUid);
  return grantPlatformAdmin(dependencies, input);
}

export function describePlatformAdminGrantFailure(
  error: unknown
): PlatformGrantCliFailure {
  if (error instanceof PlatformGrantCliInputError) {
    return {
      exitCode: 2,
      output: {status: "rejected", code: "invalid-input", recoverable: false},
    };
  }
  if (error instanceof PlatformGrantOperatorError) {
    return {
      exitCode: error.recoverable ? 5 : 3,
      output: {
        status: error.recoverable ? "partially_failed" : "rejected",
        code: error.code,
        recoverable: error.recoverable,
        ...(error.recoverable ? {
          retryGuidance: "Verify connectivity, then retry with the same request ID.",
        } : {}),
      },
    };
  }
  if (error instanceof PlatformAdminGrantError) {
    return {
      exitCode: error.recoverable ? 5 : 4,
      output: {
        status: error.recoverable ? "partially_failed" : "rejected",
        code: error.code,
        recoverable: error.recoverable,
        ...(error.recoverable ? {
          retryGuidance: "Retry the identical command with the same request ID.",
        } : {}),
      },
    };
  }
  if (error instanceof IdentityTransitionError) {
    return {
      exitCode: 4,
      output: {
        status: "rejected",
        code: error.code === "identity-transition-conflict" ?
          "identity-transition-conflict" : "target-state-ineligible",
        recoverable: false,
      },
    };
  }
  return {
    exitCode: 1,
    output: {status: "failed", code: "unexpected", recoverable: false},
  };
}

export async function runPlatformAdminGrantCli(argv: readonly string[]): Promise<void> {
  if (argv.includes("--help") || argv.includes("-h")) {
    process.stdout.write(`${GRANT_PLATFORM_ADMIN_USAGE}\n`);
    return;
  }
  const arguments_ = parsePlatformAdminGrantCliArgs(argv);
  assertPlatformGrantRuntimeRouting(arguments_.environment, process.env);

  if (getApps().length > 0) {
    throw new PlatformGrantCliInputError(
      "A Firebase app is already initialized. Start a fresh CLI process."
    );
  }
  const app = initializeApp({
    ...(arguments_.environment === "emulator" ? {} : {
      credential: applicationDefault(),
    }),
    projectId: arguments_.projectId,
  }, "platform-admin-grant");
  if (app.options.projectId !== arguments_.projectId) {
    throw new PlatformGrantCliInputError(
      "The initialized Firebase app does not match the confirmed project."
    );
  }

  const auth = getAuth(app);
  const result = await executePlatformAdminGrant({
    db: getFirestore(app),
    auth: {
      async getUser(uid) {
        const user = await auth.getUser(uid);
        return {
          uid: user.uid,
          disabled: user.disabled,
          customClaims: user.customClaims,
        };
      },
      async setCustomUserClaims(uid, claims) {
        await auth.setCustomUserClaims(uid, claims);
      },
    },
  }, arguments_.input);

  process.stdout.write(`${JSON.stringify({
    status: "completed",
    recoverable: false,
    ...result,
  }, null, 2)}\n`);
}

if (require.main === module) {
  void runPlatformAdminGrantCli(process.argv.slice(2)).catch((error: unknown) => {
    const failure = describePlatformAdminGrantFailure(error);
    process.stderr.write(`${JSON.stringify(failure.output, null, 2)}\n`);
    process.exitCode = failure.exitCode;
  });
}
