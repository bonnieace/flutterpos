/**
 * Runs the sale-trigger reconciliation suite against real Auth, Firestore, and
 * Functions emulators.
 *
 * This harness exists because of a defect nothing else could have found.
 * `mergeSaleReconciliationJob` threw on **every** sale for as long as it existed:
 * its create payload carried a `FieldValue.delete()`, which Firestore rejects at
 * serialization time and no pure test can see. The consequence was total - no
 * dirty day, no reconciliation job, no daily metric ever regenerated from sale
 * activity - and it was found by using the app, after eleven sessions of green
 * tests. One integration test that writes a sale and looks for a dirty day would
 * have caught it in seconds.
 *
 * Modelled on `run-invitation-emulator-tests.js`, which was the only
 * Auth/Firestore/Functions harness in the repository until this one. It runs its
 * own project, its own ports, and its own Functions codebase so the two suites
 * cannot interfere with each other or with a developer's `emulators:dev` run.
 */
import { spawnSync } from "node:child_process";
import { cpSync, existsSync, rmSync } from "node:fs";
import { fileURLToPath } from "node:url";

const projectId = "demo-multitenant-reconciliation-integration";
if (!projectId.startsWith("demo-")) {
  throw new Error("Reconciliation integration tests require a demo Firebase project.");
}

const firebaseCli = fileURLToPath(
  new URL("../node_modules/firebase-tools/lib/bin/firebase.js", import.meta.url),
);
const compiledFunctionsSource = fileURLToPath(
  new URL("../../functions/lib/", import.meta.url),
);
const compiledFunctionsTarget = fileURLToPath(
  new URL("../../functions/reconciliation-integration/lib/", import.meta.url),
);
if (!existsSync(compiledFunctionsSource)) {
  throw new Error("Compile Functions before running reconciliation integration tests.");
}
rmSync(compiledFunctionsTarget, { recursive: true, force: true });
cpSync(compiledFunctionsSource, compiledFunctionsTarget, { recursive: true });

// The fixture exports only the sale trigger and the task worker, and neither
// reaches a `defineSecret` parameter, so unlike `run-dev-emulators.js` this needs
// no local secret or env file at all. That is worth stating: those two files are
// the leading cause of a wedged emulator run on this project, and their absence
// here means a killed run leaves nothing behind to clean up.
//
// The fixture also has no `node_modules` of its own, unlike `functions/integration`.
// Node resolution walks up, so `firebase-admin` and `firebase-functions` come from
// `functions/node_modules` - the same install the compiled `lib/` above was built
// against, which is the version this suite should be exercising anyway. If a run
// ever fails to discover the two functions, `npm --prefix functions install` is the
// thing to check first.

const testCommandParts = [
  process.execPath,
  "--test",
  "--test-concurrency=1",
];
const testNamePattern = process.env.INTEGRATION_TEST_NAME_PATTERN;
if (testNamePattern) {
  // Printable ASCII only: this string is spliced into a shell command line,
  // so a control character or a stray quote in it is not a pattern but an
  // injection.
  if (testNamePattern.length > 200 || /[^ -~]/.test(testNamePattern)) {
    throw new Error("The integration test-name pattern is invalid.");
  }
  testCommandParts.push(`--test-name-pattern=${testNamePattern}`);
}
testCommandParts.push("test/sale-reconciliation.integration.test.js");
const testCommand = testCommandParts
  .map((part) => JSON.stringify(part))
  .join(" ");

const result = spawnSync(
  process.execPath,
  [
    firebaseCli,
    "emulators:exec",
    "--config",
    "../firebase.reconciliation-test.json",
    "--project",
    projectId,
    "--only",
    "auth,firestore,functions",
    testCommand,
  ],
  {
    cwd: fileURLToPath(new URL("..", import.meta.url)),
    env: {
      ...process.env,
      CI: "true",
      DEBUG: "",
      FUNCTIONS_DISCOVERY_TIMEOUT:
        process.env.FUNCTIONS_DISCOVERY_TIMEOUT ?? "60000",
      FUNCTIONS_EMULATOR_HOST: "127.0.0.1:5201",
      GCLOUD_PROJECT: projectId,
    },
    stdio: "inherit",
  },
);

if (result.error) throw result.error;
process.exitCode = result.status ?? 1;
