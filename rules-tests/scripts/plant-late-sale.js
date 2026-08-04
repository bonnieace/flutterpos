/**
 * Plants one sale against an already-closed shift, so a real `shift_variance`
 * can be produced locally and corrected from the app.
 *
 * This is the scenario the `sales` create rule was deliberately written to
 * permit: an offline sale may reach the server after its shift closed, and
 * refusing it would strand evidence the device can no longer correct. The shift
 * keeps the summary its closing device computed, the sales now total more than
 * that summary, and nightly reconciliation reports the difference. Nothing else
 * in the repository can produce that state - the till refuses to sell without an
 * open shift, and a shift refuses to close while any sale is unsettled - so
 * without this the correction path can only ever be proved by tests.
 *
 * The sale is **cloned from a sale the app itself wrote** rather than invented.
 * Every field then has exactly the shape `_saleFields` produces, so a mistake
 * here cannot be mistaken for a defect in the surfaces being exercised. Only
 * the identity fields move: a fresh checkout ID, the next receipt sequence, and
 * the receipt number those two derive.
 *
 * Like `seed-dev-emulator.js`, this refuses to start unless the Admin SDK is
 * already pinned at the emulators. `FIRESTORE_EMULATOR_HOST` and
 * `FIREBASE_AUTH_EMULATOR_HOST` are not a hint - they are what makes
 * `firebase-admin` itself incapable of reaching a real project.
 */
import { createHash, randomUUID } from "node:crypto";
import { pathToFileURL } from "node:url";

import { deleteApp, initializeApp } from "firebase-admin/app";
import { FieldValue, getFirestore } from "firebase-admin/firestore";

/** The project the Flutter app is built against; see `lib/firebase_options.dart`. */
const DEFAULT_PROJECT_ID = "multitenant-pos-b8326";
const DEFAULT_TENANT_ID = "dev-shop";

/** `CT-A7F-20260729-0042`, from `lib/checkout/checkout_receipt.dart`. */
const RECEIPT_PREFIX = "CT";
const RECEIPT_DEVICE_CODE_LENGTH = 3;
const RECEIPT_SEQUENCE_DIGITS = 4;

function requireEmulator(variable) {
  const value = process.env[variable];
  if (!value) {
    throw new Error(
      `${variable} is not set. Planting refuses to run outside the emulators; ` +
        "start them with `npm --prefix rules-tests run emulators:dev` and set " +
        "FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 plus " +
        "FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 in this shell.",
    );
  }
  return value;
}

function assertNoRealCredentials() {
  if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    throw new Error(
      "GOOGLE_APPLICATION_CREDENTIALS is set. Unset it before planting: real " +
        "service-account credentials have no business in a local run.",
    );
  }
}

function argumentValue(name) {
  const prefix = `--${name}=`;
  const match = process.argv.find((part) => part.startsWith(prefix));
  return match?.slice(prefix.length);
}

/**
 * The three-character device code printed on a receipt.
 *
 * Mirrors `checkoutReceiptDeviceCode`: the first three hex characters of the
 * SHA-256 digest of the durable installation identifier, uppercased. It is
 * recomputed rather than copied because the sequence is changing, and a receipt
 * that disagrees with its own envelope is refused by the client read model.
 */
function receiptDeviceCode(deviceId) {
  return createHash("sha256")
    .update(deviceId, "utf8")
    .digest("hex")
    .slice(0, RECEIPT_DEVICE_CODE_LENGTH)
    .toUpperCase();
}

function formatReceiptNumber({ deviceId, businessDate, sequence }) {
  const compactDate = businessDate.split("-").join("");
  const padded = String(sequence).padStart(RECEIPT_SEQUENCE_DIGITS, "0");
  return `${RECEIPT_PREFIX}-${receiptDeviceCode(deviceId)}-${compactDate}-${padded}`;
}

/** The most recently closed shift, or the one named by `--shift=`. */
async function resolveShift(firestore, tenantId) {
  const shifts = firestore.collection("tenants").doc(tenantId).collection("shifts");
  const named = argumentValue("shift");
  if (named) {
    const snapshot = await shifts.doc(named).get();
    if (!snapshot.exists) throw new Error(`Shift ${named} does not exist.`);
    if (snapshot.get("status") !== "closed") {
      throw new Error(`Shift ${named} is not closed, so it has no summary yet.`);
    }
    return snapshot;
  }
  const closed = await shifts
    .where("status", "==", "closed")
    .orderBy("endTime", "desc")
    .limit(1)
    .get();
  if (closed.empty) {
    throw new Error(
      "No closed shift exists in this business. Open a shift in the app, ring " +
        "up at least one sale, and close it with a cash count first.",
    );
  }
  return closed.docs[0];
}

/** One sale of that shift, used as the template for the late arrival. */
async function resolveTemplateSale(firestore, tenantId, shiftId) {
  const sales = await firestore
    .collection("tenants")
    .doc(tenantId)
    .collection("sales")
    .where("shiftId", "==", shiftId)
    .limit(1)
    .get();
  if (sales.empty) {
    throw new Error(
      `Shift ${shiftId} has no sales to clone. Ring up at least one sale in ` +
        "that shift before planting a late one.",
    );
  }
  return sales.docs[0];
}

/** The next unused receipt sequence for this device and business date. */
async function nextReceiptSequence(firestore, tenantId, deviceId, businessDate) {
  const issued = await firestore
    .collection("tenants")
    .doc(tenantId)
    .collection("sales")
    .where("deviceId", "==", deviceId)
    .where("businessDate", "==", businessDate)
    .get();
  let highest = 0;
  for (const sale of issued.docs) {
    const sequence = sale.get("receiptSequence");
    if (Number.isSafeInteger(sequence) && sequence > highest) highest = sequence;
  }
  return highest + 1;
}

export async function plantLateSale() {
  requireEmulator("FIRESTORE_EMULATOR_HOST");
  requireEmulator("FIREBASE_AUTH_EMULATOR_HOST");
  assertNoRealCredentials();
  const projectId = process.env.SEED_PROJECT_ID ?? DEFAULT_PROJECT_ID;
  const tenantId = argumentValue("tenant") ?? DEFAULT_TENANT_ID;

  const app = initializeApp({ projectId }, `plant-${Date.now()}`);
  try {
    const firestore = getFirestore(app);
    const shift = await resolveShift(firestore, tenantId);
    const shiftId = shift.id;
    const businessDate = shift.get("businessDate");
    const deviceId = shift.get("deviceId");
    const template = await resolveTemplateSale(firestore, tenantId, shiftId);

    const checkoutId = `late-${randomUUID()}`;
    const receiptSequence = await nextReceiptSequence(
      firestore,
      tenantId,
      deviceId,
      businessDate,
    );
    const fields = {
      ...template.data(),
      checkoutId,
      receiptSequence,
      receiptNumber: formatReceiptNumber({ deviceId, businessDate, sequence: receiptSequence }),
      // The payload hash describes a local outbox record that does not exist on
      // any device, so it is replaced rather than copied: leaving the template's
      // hash would claim this sale is the confirmation of that one.
      payloadHash: createHash("sha256").update(checkoutId, "utf8").digest("hex"),
      createdAt: FieldValue.serverTimestamp(),
    };

    const tenant = firestore.collection("tenants").doc(tenantId);
    const batch = firestore.batch();
    batch.create(tenant.collection("sales").doc(checkoutId), fields);
    // Decremented in the same write the app would have used. Without it the
    // trigger-owned stock movement would have nothing to account for, and the
    // run would report a *stock* difference beside the shift one - noise that
    // looks like a defect in the surface being exercised.
    for (const line of Array.isArray(fields.items) ? fields.items : []) {
      if (typeof line?.productId !== "string") continue;
      if (!Number.isSafeInteger(line.quantity) || line.quantity <= 0) continue;
      batch.update(tenant.collection("products").doc(line.productId), {
        quantity: FieldValue.increment(-line.quantity),
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();

    const recordedMinor = shift.get("totalSalesMinor");
    const plantedMinor = fields.totalMinor;
    console.log(
      [
        "Planted a late sale against a closed shift.",
        `  business          ${tenantId}`,
        `  shift             ${shiftId} (${businessDate})`,
        `  cloned from       ${template.id}`,
        `  new sale          ${checkoutId}`,
        `  receipt           ${fields.receiptNumber}`,
        `  planted amount    ${plantedMinor} minor units`,
        `  shift still says  ${recordedMinor} minor units over ` +
          `${shift.get("transactionCount")} transactions`,
        "",
        "The sale trigger has marked the day dirty. Ask for a check from the",
        "app - Daily summary, the day above, Reconciliation status, Catch up -",
        "then open View unresolved differences and correct the shift.",
        "",
      ].join("\n"),
    );
    return { tenantId, shiftId, businessDate, checkoutId };
  } finally {
    await deleteApp(app);
  }
}

const invokedDirectly =
  process.argv[1] !== undefined &&
  import.meta.url === pathToFileURL(process.argv[1]).href;

if (invokedDirectly) {
  try {
    await plantLateSale();
  } catch (error) {
    console.error(error instanceof Error ? error.message : error);
    process.exitCode = 1;
  }
}
