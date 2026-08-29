import {
  DocumentReference,
  FieldValue,
  Firestore,
  Transaction,
  getFirestore,
} from "firebase-admin/firestore";
import {beforeUserCreated, AuthBlockingEvent} from "firebase-functions/v2/identity";
import {HttpsError} from "firebase-functions/v2/https";

import {RootUserRecord} from "../core/model";

/**
 * Creates the canonical `users/{uid}` root document at account creation.
 *
 * **The gap this closes.** `requestTenant` refuses a caller with no root
 * document (`assertVerifiedTenantApplicant`), and until now the only code that
 * ever wrote one was staff-invitation provisioning - so a person who signed
 * themselves up could never request a business. `identityOrigin: "self_signup"`
 * has been a declared value in `RootUserRecord` since the model was written and
 * nothing has ever produced it. This produces it.
 *
 * **Why a blocking function rather than a callable the client calls after
 * signing up.** A blocking function runs *inside* account creation: throwing
 * from it aborts the creation, so an Auth identity cannot come into existence
 * without its root document. The callable alternative leaves a window - the
 * account exists, the second call fails, and the person is left with
 * credentials that can sign in and do nothing, which is exactly the state
 * `cleanupAbandonedStaffIdentities` exists to sweep up on the invitation side.
 *
 * **It never overwrites a root document that already exists.** Blocking
 * functions are not expected to fire for Admin SDK `createUser`, which is how
 * `identityProvisioning` mints an invited member's identity - but "not
 * expected to" is not a guarantee worth a person's `identityOrigin`, and a
 * retry of a blocked creation is a case that needs the same answer anyway. The
 * write is a transactional create-if-absent, so whether this fires once, twice,
 * or beside the invitation path, the first writer wins and the rest are no-ops.
 */

/** What a self-signup's root document holds, before it is written. */
export interface SelfSignupRoot {
  email: string;
  displayName?: string;
  accountType: "tenant_user";
  identityOrigin: "self_signup";
  globalStatus: "active";
  membershipCount: 0;
  ownedTenantCount: 0;
  ownedActiveTenantCount: 0;
}

/**
 * Decides what a new identity's root document should hold, or refuses it.
 *
 * Pure, so the rules below are testable without an emulator.
 */
export function prepareSelfSignupRoot(event: AuthBlockingEvent): SelfSignupRoot {
  const email = normalizeEmail(event.data?.email);
  if (!email) {
    // This product signs in with an email and a password and has no other
    // path. An identity with no address could never verify, could never be
    // invited, and could never reset a password - so it is refused at creation
    // rather than left to fail later with nothing to explain it.
    throw new HttpsError("invalid-argument", "An account requires an email address.");
  }
  const displayName = normalizeName(event.data?.displayName);
  return {
    email,
    ...(displayName ? {displayName} : {}),
    accountType: "tenant_user",
    identityOrigin: "self_signup",
    // A self-signed-up person is active immediately. They are not yet a member
    // of anything: `requestTenant` is the next step and it makes its own
    // checks, one of which is that the address has been verified.
    globalStatus: "active",
    membershipCount: 0,
    ownedTenantCount: 0,
    ownedActiveTenantCount: 0,
  };
}

/**
 * Writes [prepared] at `users/{uid}` unless a root document is already there.
 *
 * Returns whether this call was the one that created it, which is what the
 * tests assert on and what makes a second firing observably a no-op.
 */
export async function ensureRootUser(
  db: Firestore,
  uid: string,
  prepared: SelfSignupRoot
): Promise<boolean> {
  const reference = db.collection("users").doc(uid) as DocumentReference;
  return db.runTransaction(async (transaction: Transaction) => {
    const snapshot = await transaction.get(reference);
    if (snapshot.exists) {
      // Already provisioned - by the invitation path, or by an earlier firing
      // of this one. Its `identityOrigin` is the truth about how this identity
      // came to exist and must not be rewritten.
      return false;
    }
    const record: RootUserRecord = prepared;
    transaction.create(reference, {
      ...record,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return true;
  });
}

export const bootstrapSelfSignupIdentity = beforeUserCreated(
  async (event: AuthBlockingEvent) => {
    const uid = event.data?.uid;
    if (!uid) {
      throw new HttpsError("invalid-argument", "An account requires an identifier.");
    }
    await ensureRootUser(getFirestore(), uid, prepareSelfSignupRoot(event));
    // No response: nothing about the identity itself is being changed. A
    // returned `BeforeCreateResponse` would be an opportunity to set custom
    // claims, and this deliberately sets none - `platformRole` is granted by
    // the CLI saga and by nothing else.
  }
);

function normalizeEmail(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  const trimmed = value.trim().toLowerCase();
  return trimmed.length > 0 ? trimmed : undefined;
}

function normalizeName(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}
