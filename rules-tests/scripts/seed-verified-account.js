/**
 * Seeds one verified account and nothing else, so a person can drive the whole
 * self-serve flow by hand without a mail provider.
 *
 * **Why this exists beside `seed-dev-emulator.js`.** That script hands you a
 * finished shop — a tenant, a catalog, staff, a currency — which is the right
 * tool for working on the till. This one deliberately stops at the first step
 * somebody cannot do locally: verifying an email address. `requestTenant`
 * refuses an unverified applicant, `sendAccountVerification` delivers through
 * Brevo, and a local run has no working Brevo key. Everything after that point
 * — requesting the business, setting a currency, adding products, selling — is
 * left for you to click through, because all of it works unaided now that a
 * pending business trades for a week.
 *
 * **It writes the root document itself, and that is not a workaround.** Auth
 * blocking functions do not fire for Admin SDK user creation, so
 * `bootstrapSelfSignupIdentity` will not run for an account made here. The root
 * document it would have written is written directly instead, in the same shape
 * and with the same `identityOrigin: "self_signup"` — and because that function
 * is a transactional create-if-absent, nothing conflicts if it ever does run.
 *
 * This script is destructive by nature and a mis-pointed run is unrecoverable,
 * so it refuses to start unless the Admin SDK is already pinned at emulators.
 * `FIRESTORE_EMULATOR_HOST` and `FIREBASE_AUTH_EMULATOR_HOST` are not a hint to
 * this script — they are what makes `firebase-admin` itself incapable of
 * reaching a real project — so requiring them is the guarantee, not a check.
 */
import { deleteApp, initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { FieldValue, getFirestore } from "firebase-admin/firestore";

const DEFAULT_PROJECT_ID = "multitenant-pos-b8326";

const EMAIL = process.env.SEED_EMAIL ?? "owner@chilltent.test";
const PASSWORD = process.env.SEED_PASSWORD ?? "hunter22";
const DISPLAY_NAME = process.env.SEED_NAME ?? "Chilltent Owner";

function requireEmulator(variable) {
  const value = process.env[variable];
  if (!value) {
    throw new Error(
      `${variable} is not set. Seeding refuses to run outside the emulators.`,
    );
  }
  return value;
}

function assertNoRealCredentials() {
  if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    throw new Error(
      "GOOGLE_APPLICATION_CREDENTIALS is set. Unset it before seeding.",
    );
  }
}

/** Creates the account, or brings an existing one up to verified. */
async function ensureVerifiedAccount(auth) {
  try {
    const existing = await auth.getUserByEmail(EMAIL);
    await auth.updateUser(existing.uid, {
      password: PASSWORD,
      emailVerified: true,
      disabled: false,
    });
    return { uid: existing.uid, created: false };
  } catch (error) {
    if (error?.code !== "auth/user-not-found") throw error;
    const created = await auth.createUser({
      email: EMAIL,
      password: PASSWORD,
      displayName: DISPLAY_NAME,
      emailVerified: true,
    });
    return { uid: created.uid, created: true };
  }
}

/**
 * Writes the root document `bootstrapSelfSignupIdentity` would have written.
 *
 * Create-if-absent, exactly as that function is: re-running this must not reset
 * the counters of an account that has since requested a business.
 */
async function ensureRootUser(db, uid) {
  const reference = db.collection("users").doc(uid);
  return db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(reference);
    if (snapshot.exists) return false;
    transaction.create(reference, {
      email: EMAIL.toLowerCase(),
      displayName: DISPLAY_NAME,
      accountType: "tenant_user",
      identityOrigin: "self_signup",
      globalStatus: "active",
      membershipCount: 0,
      ownedTenantCount: 0,
      ownedActiveTenantCount: 0,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return true;
  });
}

async function main() {
  requireEmulator("FIRESTORE_EMULATOR_HOST");
  requireEmulator("FIREBASE_AUTH_EMULATOR_HOST");
  assertNoRealCredentials();

  const projectId = process.env.SEED_PROJECT_ID ?? DEFAULT_PROJECT_ID;
  const app = initializeApp({ projectId }, `seed-verified-${Date.now()}`);
  try {
    const auth = getAuth(app);
    const db = getFirestore(app);

    const account = await ensureVerifiedAccount(auth);
    const wroteRoot = await ensureRootUser(db, account.uid);

    console.log("");
    console.log("  Seeded one verified account and nothing else.");
    console.log("");
    console.log(`    email     ${EMAIL}`);
    console.log(`    password  ${PASSWORD}`);
    console.log(`    uid       ${account.uid}`);
    console.log(`    account   ${account.created ? "created" : "already existed, re-verified"}`);
    console.log(`    root doc  ${wroteRoot ? "written" : "already present, left alone"}`);
    console.log("");
    console.log("  Next, in the app: sign in, request a business, then set a");
    console.log("  currency and add a product. The business trades for seven");
    console.log("  days without anybody approving it.");
    console.log("");
  } finally {
    await deleteApp(app);
  }
}

main().catch((error) => {
  console.error(error?.message ?? error);
  process.exitCode = 1;
});
