import { spawnSync } from "node:child_process";
import {
  cpSync,
  existsSync,
  rmSync,
  unlinkSync,
  writeFileSync,
} from "node:fs";
import { fileURLToPath } from "node:url";

const projectId = "demo-multitenant-invitation-integration";
if (!projectId.startsWith("demo-")) {
  throw new Error("Invitation integration tests require a demo Firebase project.");
}

const firebaseCli = fileURLToPath(
  new URL("../node_modules/firebase-tools/lib/bin/firebase.js", import.meta.url),
);
const functionsDirectory = fileURLToPath(
  new URL("../../functions/integration/", import.meta.url),
);
const compiledFunctionsSource = fileURLToPath(
  new URL("../../functions/lib/", import.meta.url),
);
const compiledFunctionsTarget = fileURLToPath(
  new URL("../../functions/integration/lib/", import.meta.url),
);
if (!existsSync(compiledFunctionsSource)) {
  throw new Error("Compile Functions before running invitation integration tests.");
}
rmSync(compiledFunctionsTarget, { recursive: true, force: true });
cpSync(compiledFunctionsSource, compiledFunctionsTarget, { recursive: true });
const localSecretFile = `${functionsDirectory}.secret.local`;
if (existsSync(localSecretFile)) {
  throw new Error(
    `Refusing to overwrite existing Functions emulator configuration: ${localSecretFile}`,
  );
}

const invitationSecret =
  "local-emulator-invitation-hmac-secret-at-least-32-bytes";
writeFileSync(
  localSecretFile,
  [
    `STAFF_INVITATION_HMAC_SECRET_V1=${invitationSecret}`,
    "",
  ].join("\n"),
  { encoding: "utf8", flag: "wx" },
);
const testCommandParts = [
  process.execPath,
  "--test",
  "--test-concurrency=1",
];
const testNamePattern = process.env.INTEGRATION_TEST_NAME_PATTERN;
if (testNamePattern) {
  if (testNamePattern.length > 200 || /[\u0000-\u001f]/.test(testNamePattern)) {
    throw new Error("The integration test-name pattern is invalid.");
  }
  testCommandParts.push(`--test-name-pattern=${testNamePattern}`);
}
// Two files, one emulator start. `node --test` gives each file its own process,
// so the password-reset suite brings up its own Admin app and cannot disturb the
// acceptance suite's fixtures; `--test-concurrency=1` keeps them sequential.
// Password reset shares the delivery, suppression, and recipient-hash code this
// suite's project already runs, so it needs no new ports, no fourth demo
// project, and no fourth copy of the compiled Functions build.
testCommandParts.push(
  "test/invitation-acceptance.integration.test.js",
  "test/password-reset-delivery.integration.test.js",
);
const testCommand = testCommandParts
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
      "../firebase.invitation-test.json",
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
        FUNCTIONS_DISCOVERY_TIMEOUT:
          process.env.FUNCTIONS_DISCOVERY_TIMEOUT ?? "60000",
        FUNCTIONS_EMULATOR_HOST: "127.0.0.1:5101",
        GCLOUD_PROJECT: projectId,
        // The password-reset gateway reads this through
        // `defineString(...).value()`, which outside a deployed function is just
        // `process.env`. It is declared here rather than in the test so the
        // suite's configuration stays in one place, the way the invitation
        // secret above is; the gateway refuses anything that is not HTTPS.
        PASSWORD_RESET_CONTINUE_URL:
          "https://reset.integration.example.test/finish",
        STAFF_INVITATION_HMAC_SECRET_V1: invitationSecret,
      },
      stdio: "inherit",
    },
  );
} finally {
  unlinkSync(localSecretFile);
}

if (result.error) throw result.error;
process.exitCode = result.status ?? 1;
