import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";

import { initializeTestEnvironment } from "@firebase/rules-unit-testing";
import { doc, setDoc } from "firebase/firestore";

const RULES_PATH = new URL("../../firestore.rules", import.meta.url);
const DEMO_PROJECT_ID = "demo-multitenant-rules";

function firestoreEmulatorAddress() {
  const value = process.env.FIRESTORE_EMULATOR_HOST;
  if (!value) {
    throw new Error(
      "FIRESTORE_EMULATOR_HOST is required. Run `npm run test:emulator` so the tests cannot contact Firestore production.",
    );
  }

  const match = /^(?:\[([^\]]+)\]|([^:]+)):(\d+)$/.exec(value);
  if (!match) {
    throw new Error(
      `Invalid FIRESTORE_EMULATOR_HOST ${JSON.stringify(value)}; expected host:port.`,
    );
  }

  const port = Number(match[3]);
  if (!Number.isInteger(port) || port < 1 || port > 65_535) {
    throw new Error(`Invalid Firestore emulator port in ${JSON.stringify(value)}.`);
  }

  return { host: match[1] ?? match[2], port };
}

export async function createRulesTestEnvironment() {
  const projectId = DEMO_PROJECT_ID;
  if (!projectId.startsWith("demo-")) {
    throw new Error(`Rules tests require a demo-* project, received ${projectId}.`);
  }

  const rules = await readFile(RULES_PATH, "utf8");
  const { host, port } = firestoreEmulatorAddress();

  const testEnvironment = await initializeTestEnvironment({
    projectId,
    firestore: { host, port, rules },
  });
  await testEnvironment.clearFirestore();
  return testEnvironment;
}

export async function seedDocuments(testEnvironment, documents) {
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    const firestore = context.firestore();
    await Promise.all(
      Object.entries(documents).map(([path, data]) =>
        setDoc(doc(firestore, path), data),
      ),
    );
  });
}

export function authenticatedFirestore(testEnvironment, uid, token = {}) {
  return testEnvironment.authenticatedContext(uid, token).firestore();
}

/**
 * Mirrors the client's frozen device code: the first three uppercase hex
 * characters of the SHA-256 digest of the durable installation identifier.
 */
export function receiptDeviceCode(deviceId) {
  return createHash("sha256")
    .update(deviceId, "utf8")
    .digest("hex")
    .slice(0, 3)
    .toUpperCase();
}

/** Builds the frozen `CT-A7F-20260729-0042` receipt shape. */
export function receiptNumber(deviceId, businessDate, sequence) {
  const compactDate = businessDate.split("-").join("");
  const padded = String(sequence).padStart(4, "0");
  return `CT-${receiptDeviceCode(deviceId)}-${compactDate}-${padded}`;
}

export function activeTenantDocuments({
  uid = "user-a",
  tenantId = "tenant-a",
  role = "cashier",
  rootStatus = "active",
  tenantStatus = "active",
  staffStatus = "active",
  accountType = "tenant_user",
} = {}) {
  return {
    [`users/${uid}`]: {
      accountType,
      globalStatus: rootStatus,
      membershipCount: 1,
    },
    [`tenants/${tenantId}`]: {
      name: tenantId,
      ownerUid: role === "owner" ? uid : "owner-a",
      status: tenantStatus,
    },
    [`tenants/${tenantId}/staff/${uid}`]: {
      uid,
      role,
      status: staffStatus,
    },
  };
}
