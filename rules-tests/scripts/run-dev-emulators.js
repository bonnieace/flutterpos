/**
 * Starts the local Auth, Firestore, and Functions emulators declared in
 * `firebase.json`, seeds them, and holds them up until Ctrl+C.
 *
 * This is the developer-facing counterpart to
 * `run-invitation-emulator-tests.js` and follows the same pattern: the local
 * secret file is written for the run and removed afterwards, so no secret
 * value is ever committed and a real `.secret.local` is never overwritten.
 *
 * It deliberately does not share `firebase.test.json`. Every suite in PLAN.md
 * depends on that config, and coupling a developer's local run to the test
 * harness would make one break the other.
 */
import { spawnSync } from "node:child_process";
import { existsSync, readFileSync, unlinkSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const projectId = process.env.SEED_PROJECT_ID ?? "multitenant-pos-b8326";

const firebaseCli = fileURLToPath(
  new URL("../node_modules/firebase-tools/lib/bin/firebase.js", import.meta.url),
);
const functionsDirectory = fileURLToPath(
  new URL("../../functions/", import.meta.url),
);
const localSecretFile = `${functionsDirectory}.secret.local`;
const localEnvFile = `${functionsDirectory}.env.local`;
const config = JSON.parse(
  readFileSync(fileURLToPath(new URL("../../firebase.json", import.meta.url)), "utf8"),
);
const emulators = config.emulators;
for (const service of ["auth", "firestore", "functions", "storage"]) {
  if (!Number.isInteger(emulators?.[service]?.port)) {
    throw new Error(`firebase.json declares no ${service} emulator port.`);
  }
}

for (const file of [localSecretFile, localEnvFile]) {
  if (existsSync(file)) {
    throw new Error(
      `Refusing to overwrite existing Functions emulator configuration: ${file}`,
    );
  }
}

// Local-only values. Two separate reasons every one of these is needed:
//
// - `listMyTenants` refuses with `failed-precondition` when the cursor secret
//   is shorter than 32 bytes, which presents in the app as a business list
//   that never loads.
// - Every `defineSecret`/`defineString` parameter without a default makes the
//   emulator stop and ask for a value at startup. With no terminal to answer,
//   that is a run that appears to hang forever after "Serving at port ...".
//   The invitation harness never hits this because its codebase exports only
//   seven functions; this one loads them all.
writeFileSync(
  localSecretFile,
  [
    "TENANT_CURSOR_HMAC_SECRET=local-emulator-tenant-cursor-secret-32-bytes",
    "STAFF_INVITATION_HMAC_SECRET_V1=local-emulator-invitation-hmac-secret-at-least-32-bytes",
    "EMAIL_RECIPIENT_HMAC_KEYRING=" +
      JSON.stringify({
        currentVersion: "v1",
        keys: { v1: "local-emulator-recipient-hmac-key-at-least-32-bytes" },
      }),
    "BREVO_API_KEY=local-emulator-unused-brevo-key",
    "BREVO_WEBHOOK_SECRET=local-emulator-unused-brevo-webhook-secret",
    "",
  ].join("\n"),
  { encoding: "utf8", flag: "wx" },
);

// No mail is sent locally - no Brevo key here is real - so these exist to make
// the parameters resolvable, not to be delivered to.
writeFileSync(
  localEnvFile,
  [
    "EMAIL_SENDER_ADDRESS=no-reply@local.emulator.invalid",
    "EMAIL_SENDER_NAME=Local emulator",
    "PASSWORD_RESET_CONTINUE_URL=http://127.0.0.1:4000/password-reset",
    "EMAIL_VERIFICATION_CONTINUE_URL=http://127.0.0.1:4000/verify-email",
    "PLATFORM_ALERTS_URL=http://127.0.0.1:4000/platform-alerts",
    "STAFF_INVITATION_ACTION_BASE_URL=http://127.0.0.1:4000/invitation",
    "STAFF_INVITATION_SENDER_EMAIL=no-reply@local.emulator.invalid",
    "STAFF_INVITATION_SENDER_NAME=Local emulator",
    "",
  ].join("\n"),
  { encoding: "utf8", flag: "wx" },
);

// `--no-hold` seeds and shuts straight back down, which is how this script is
// smoke-tested without a person holding Ctrl+C.
const hold = !process.argv.includes("--no-hold");
const seedCommand = [
  process.execPath,
  "scripts/seed-dev-emulator.js",
  ...(hold ? ["--hold"] : []),
]
  .map((part) => JSON.stringify(part))
  .join(" ");

let result;
try {
  result = spawnSync(
    process.execPath,
    [
      firebaseCli,
      "emulators:exec",
      "--config",
      "../firebase.json",
      "--project",
      projectId,
      "--only",
      "auth,firestore,functions,storage",
      seedCommand,
    ],
    {
      cwd: fileURLToPath(new URL("..", import.meta.url)),
      env: {
        ...process.env,
        // Without this the CLI may stop on an interactive prompt with no
        // terminal to answer it, which presents as a run that never starts.
        CI: "true",
        DEBUG: "",
        FUNCTIONS_DISCOVERY_TIMEOUT:
          process.env.FUNCTIONS_DISCOVERY_TIMEOUT ?? "60000",
        GCLOUD_PROJECT: projectId,
        // The seeder refuses to run without these, which is what keeps a
        // mis-pointed seed impossible; setting them here is what makes the
        // developer command a single line.
        FIREBASE_AUTH_EMULATOR_HOST: `127.0.0.1:${emulators.auth.port}`,
        FIRESTORE_EMULATOR_HOST: `127.0.0.1:${emulators.firestore.port}`,
        FUNCTIONS_EMULATOR_HOST: `127.0.0.1:${emulators.functions.port}`,
      },
      stdio: "inherit",
    },
  );
} finally {
  for (const file of [localSecretFile, localEnvFile]) {
    if (existsSync(file)) unlinkSync(file);
  }
}

if (result.error) throw result.error;
process.exitCode = result.status ?? 1;
