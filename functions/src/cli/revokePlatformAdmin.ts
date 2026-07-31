import {applicationDefault, getApps, initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {Firestore, getFirestore} from "firebase-admin/firestore";
import {
  assertPlatformGrantRuntimeRouting,
  PLATFORM_GRANT_PROJECTS,
  PlatformGrantAuthClient,
  PlatformGrantCliInputError,
  PlatformGrantEnvironment,
  PlatformGrantOperatorError,
  requirePlatformGrantOperator,
} from "./grantPlatformAdmin";
import {
  PlatformAdminRevocationError,
  RevokePlatformAdminInput,
  RevokePlatformAdminResult,
  revokePlatformAdmin,
} from "../platform/revokePlatformAdmin";

export const REVOKE_PLATFORM_ADMIN_USAGE = `
revoke-platform-admin --environment ENV --project-id PROJECT \\
  --confirm-project-id PROJECT --actor-uid UID --target-uid UID \\
  --confirm-target-uid UID --request-id ID --reason TEXT

ENV must be dev, staging, or prod and PROJECT must exactly match the source-
controlled allowlist. Production additionally requires --confirm-production.
The emulator environment is reserved for the fixed localhost integration test.

Run from functions/ after building, using Application Default Credentials that
are authorized for the explicitly supplied Firebase project. Retain the
request ID: a recoverable failure must be retried with the same arguments.
`.trim();

export interface PlatformAdminRevokeCliArguments {
  environment: PlatformGrantEnvironment;
  projectId: string;
  input: RevokePlatformAdminInput;
}

export interface PlatformAdminRevokeAuthClient extends PlatformGrantAuthClient {
  getUser(uid: string): Promise<{
    uid: string;
    disabled: boolean;
    customClaims?: Record<string, unknown>;
    tokensValidAfterTime?: string;
  }>;
  revokeRefreshTokens(uid: string): Promise<void>;
}

export interface ExecutePlatformAdminRevokeDependencies {
  db: Firestore;
  auth: PlatformAdminRevokeAuthClient;
}

export type PlatformRevokeCliFailure = {
  exitCode: number;
  output: {
    status: "rejected" | "partially_failed" | "failed";
    code: string;
    recoverable: boolean;
    retryGuidance?: string;
  };
};

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

export function parsePlatformAdminRevokeCliArgs(
  argv: readonly string[]
): PlatformAdminRevokeCliArguments {
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
      throw new PlatformGrantCliInputError(REVOKE_PLATFORM_ADMIN_USAGE);
    }
    throw new PlatformGrantCliInputError(`Unknown argument: ${argument}`);
  }

  const environment = parseEnvironment(requiredValue(values, "--environment"));
  const projectId = requiredValue(values, "--project-id");
  if (projectId !== PLATFORM_GRANT_PROJECTS[environment]) {
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

export async function executePlatformAdminRevoke(
  dependencies: ExecutePlatformAdminRevokeDependencies,
  input: RevokePlatformAdminInput
): Promise<RevokePlatformAdminResult> {
  await requirePlatformGrantOperator(dependencies, input.actorUid);
  return revokePlatformAdmin(dependencies, input);
}

export function describePlatformAdminRevokeFailure(
  error: unknown
): PlatformRevokeCliFailure {
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
  if (error instanceof PlatformAdminRevocationError) {
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
  return {
    exitCode: 1,
    output: {status: "failed", code: "unexpected", recoverable: false},
  };
}

export async function runPlatformAdminRevokeCli(argv: readonly string[]): Promise<void> {
  if (argv.includes("--help") || argv.includes("-h")) {
    process.stdout.write(`${REVOKE_PLATFORM_ADMIN_USAGE}\n`);
    return;
  }
  const arguments_ = parsePlatformAdminRevokeCliArgs(argv);
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
  }, "platform-admin-revoke");
  if (app.options.projectId !== arguments_.projectId) {
    throw new PlatformGrantCliInputError(
      "The initialized Firebase app does not match the confirmed project."
    );
  }
  const auth = getAuth(app);
  const result = await executePlatformAdminRevoke({
    db: getFirestore(app),
    auth: {
      async getUser(uid) {
        const user = await auth.getUser(uid);
        return {
          uid: user.uid,
          disabled: user.disabled,
          customClaims: user.customClaims,
          tokensValidAfterTime: user.tokensValidAfterTime,
        };
      },
      async setCustomUserClaims(uid, claims) {
        await auth.setCustomUserClaims(uid, claims);
      },
      async revokeRefreshTokens(uid: string) {
        await auth.revokeRefreshTokens(uid);
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
  void runPlatformAdminRevokeCli(process.argv.slice(2)).catch((error: unknown) => {
    const failure = describePlatformAdminRevokeFailure(error);
    process.stderr.write(`${JSON.stringify(failure.output, null, 2)}\n`);
    process.exitCode = failure.exitCode;
  });
}
