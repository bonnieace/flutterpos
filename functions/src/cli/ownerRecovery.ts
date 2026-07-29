import {applicationDefault, getApps, initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {getFirestore} from "firebase-admin/firestore";
import {
  FirestoreOwnerRecoveryStore,
  OwnerRecoveryConfirmations,
  OwnerRecoveryInput,
  recoverTenantOwner,
} from "../recovery/ownerRecovery";

export const OWNER_RECOVERY_USAGE = `
owner-recovery --project-id PROJECT --operator-uid UID --tenant-id TENANT \\
  --replacement-uid UID --operation-id ID --reason TEXT [--dry-run]

Normal recovery requires the replacement to already be an active canonical admin.

Exceptional recovery additionally requires:
  --exceptional
  --case-id CASE_ID
  --support-reference REFERENCE
  --confirm-tenant-slug SLUG
  --confirm-old-owner-uid UID
  --confirm-replacement-uid UID
  --confirm-exactly-one-owner

Run from functions/ after building, using Application Default Credentials that
are authorized for the explicitly supplied Firebase project. Start with
--dry-run, retain the operation ID, then rerun without --dry-run.
`.trim();

export interface OwnerRecoveryCliArguments {
  projectId: string;
  input: OwnerRecoveryInput;
}

const VALUE_FLAGS = new Set([
  "--project-id",
  "--operator-uid",
  "--tenant-id",
  "--replacement-uid",
  "--operation-id",
  "--reason",
  "--case-id",
  "--support-reference",
  "--confirm-tenant-slug",
  "--confirm-old-owner-uid",
  "--confirm-replacement-uid",
]);

function requiredValue(values: ReadonlyMap<string, string>, flag: string): string {
  const value = values.get(flag)?.trim();
  if (!value) throw new Error(`${flag} is required.`);
  return value;
}

export function parseOwnerRecoveryCliArgs(argv: readonly string[]): OwnerRecoveryCliArguments {
  const values = new Map<string, string>();
  const switches = new Set<string>();

  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (VALUE_FLAGS.has(argument)) {
      if (values.has(argument)) throw new Error(`${argument} was supplied more than once.`);
      const value = argv[index + 1];
      if (value === undefined || value.startsWith("--")) {
        throw new Error(`${argument} requires a value.`);
      }
      values.set(argument, value);
      index += 1;
      continue;
    }
    if (["--exceptional", "--confirm-exactly-one-owner", "--dry-run"].includes(argument)) {
      if (switches.has(argument)) throw new Error(`${argument} was supplied more than once.`);
      switches.add(argument);
      continue;
    }
    if (argument === "--help" || argument === "-h") {
      throw new Error(OWNER_RECOVERY_USAGE);
    }
    throw new Error(`Unknown argument: ${argument}`);
  }

  const exceptional = switches.has("--exceptional");
  let confirmations: OwnerRecoveryConfirmations | undefined;
  if (exceptional) {
    confirmations = {
      tenantSlug: requiredValue(values, "--confirm-tenant-slug"),
      oldOwnerUid: requiredValue(values, "--confirm-old-owner-uid"),
      replacementUid: requiredValue(values, "--confirm-replacement-uid"),
      secondConfirmation: switches.has("--confirm-exactly-one-owner"),
    };
    if (!confirmations.secondConfirmation) {
      throw new Error("--confirm-exactly-one-owner is required in exceptional mode.");
    }
  } else if (
    values.has("--case-id") ||
    values.has("--support-reference") ||
    values.has("--confirm-tenant-slug") ||
    values.has("--confirm-old-owner-uid") ||
    values.has("--confirm-replacement-uid") ||
    switches.has("--confirm-exactly-one-owner")
  ) {
    throw new Error("Exceptional controls require --exceptional.");
  }

  return {
    projectId: requiredValue(values, "--project-id"),
    input: {
      operatorUid: requiredValue(values, "--operator-uid"),
      tenantId: requiredValue(values, "--tenant-id"),
      replacementUid: requiredValue(values, "--replacement-uid"),
      operationId: requiredValue(values, "--operation-id"),
      reason: requiredValue(values, "--reason"),
      mode: exceptional ? "exceptional" : "normal",
      ...(exceptional ? {
        caseId: requiredValue(values, "--case-id"),
        supportReference: requiredValue(values, "--support-reference"),
        confirmations,
      } : {}),
      ...(switches.has("--dry-run") ? {dryRun: true} : {}),
    },
  };
}

export async function runOwnerRecoveryCli(argv: readonly string[]): Promise<void> {
  if (argv.includes("--help") || argv.includes("-h")) {
    process.stdout.write(`${OWNER_RECOVERY_USAGE}\n`);
    return;
  }
  const arguments_ = parseOwnerRecoveryCliArgs(argv);
  const app = getApps().length > 0 ? getApps()[0] : initializeApp({
    credential: applicationDefault(),
    projectId: arguments_.projectId,
  });
  if (app.options.projectId !== arguments_.projectId) {
    throw new Error(
      `The initialized Firebase app targets ${String(app.options.projectId)}, not ` +
      `${arguments_.projectId}. Start a fresh process for the requested project.`
    );
  }

  const auth = getAuth(app);
  const result = await recoverTenantOwner({
    store: new FirestoreOwnerRecoveryStore(getFirestore(app)),
    auth: {
      async getUser(uid) {
        const user = await auth.getUser(uid);
        return {
          uid: user.uid,
          email: user.email,
          displayName: user.displayName,
          disabled: user.disabled,
          emailVerified: user.emailVerified,
          customClaims: user.customClaims,
        };
      },
    },
  }, arguments_.input);

  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
}

if (require.main === module) {
  void runOwnerRecoveryCli(process.argv.slice(2)).catch((error: unknown) => {
    const message = error instanceof Error ? error.message : String(error);
    process.stderr.write(`owner-recovery failed: ${message}\n`);
    process.exitCode = 1;
  });
}
