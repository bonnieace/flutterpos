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
const testCommand = [
  process.execPath,
  "--test",
  "--test-concurrency=1",
  "test/invitation-acceptance.integration.test.js",
].map((part) => JSON.stringify(part)).join(" ");

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
        FUNCTIONS_EMULATOR_HOST: "127.0.0.1:5101",
        GCLOUD_PROJECT: projectId,
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
