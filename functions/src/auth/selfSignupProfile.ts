import {getAuth, UserRecord} from "firebase-admin/auth";
import {
  FieldValue,
  Firestore,
  getFirestore,
  Timestamp,
} from "firebase-admin/firestore";
import {CallableRequest, HttpsError, onCall} from "firebase-functions/v2/https";

import {requireAuthenticatedUser} from "../core/authorization";
import {runIdempotentFirestoreTransaction} from "../core/idempotency";
import {RootUserRecord} from "../core/model";
import {requireObject, requireRequestId, requireString} from "../core/validation";
import {enqueueAccountVerificationFor} from "../email/accountVerification";
import {EMAIL_RECIPIENT_HMAC_KEYRING} from "../email/config";
import {normalizeEmail} from "../email/recipientHash";

/**
 * The two calls that make signing up one continuous act.
 *
 * **Why this exists at all.** `createUserWithEmailAndPassword` carries no name,
 * so `bootstrapSelfSignupIdentity` - which runs *inside* account creation and
 * therefore before the client can say anything - has never had a `displayName`
 * to write. Every self-signed-up person in the system is anonymous to their own
 * root document, and `requestTenant` consequently stamps their canonical staff
 * record with whatever the token happens to hold. `completeSelfSignup` is the
 * first moment a name can exist, so it is also where the first verification
 * email is enqueued: one round trip, and nobody has to press anything.
 *
 * **Why the email may be changed here and nowhere else.** Both callables refuse
 * anyone who is not an unverified `self_signup` identity. That is not a
 * convenience boundary, it is the entire safety argument: an address that has
 * never been verified protects nothing, grants nothing, and can be moved without
 * proving ownership of the old one, because there is no old one to prove. The
 * moment either fact stops holding - the address verifies, or the identity came
 * from a staff invitation - changing an address becomes an account-recovery
 * operation with audit and mirror-reconciliation obligations that belong in
 * their own slice, and these refuse it.
 *
 * **Why not `verifyBeforeUpdateEmail`.** It is the Firebase-standard flow and it
 * sends Firebase's own template from Firebase's sender - invisible to
 * `email_suppressions`, absent from the delivery ledger, and the only message in
 * the product that would not come from the configured sender. Setting the
 * address server-side and enqueueing through `enqueueAccountVerificationFor`
 * keeps every message on one set of rails.
 */

const DISPLAY_NAME_MIN_LENGTH = 2;
const DISPLAY_NAME_MAX_LENGTH = 80;

/** E.164: a plus, a non-zero country digit, then 7 to 14 more. */
const E164_PATTERN = /^\+[1-9]\d{7,14}$/;

const EMAIL_PATTERN = /^[^@\s]+@[^@\s.]+(\.[^@\s.]+)+$/;

const EMAIL_CHANGE_WINDOW_MILLISECONDS = 24 * 60 * 60 * 1000;
const MAX_EMAIL_CHANGES_PER_WINDOW = 5;

interface OnboardingCaller {
  uid: string;
  authTime: number;
  root: RootUserRecord;
  identity: UserRecord;
}

/**
 * Establishes that the caller is mid-signup, and refuses every other identity.
 *
 * Verification is read from the **Auth record** rather than the token for the
 * reason `assertVerifiedAuthIdentity` documents: a token minted at sign-in
 * reports the address unverified for up to an hour after the person followed the
 * link. Here the consequence runs the other way - a stale token would let a
 * verified person keep moving their address - so the record is what counts.
 */
async function requireSelfSignupOnboarding<T>(
  db: Firestore,
  request: CallableRequest<T>
): Promise<OnboardingCaller> {
  const caller = requireAuthenticatedUser(request, {allowUnverified: true});
  const authTime = caller.token.auth_time;
  if (typeof authTime !== "number" || !Number.isSafeInteger(authTime)) {
    throw new HttpsError("failed-precondition", "A new sign-in is required.");
  }

  let identity: UserRecord;
  try {
    identity = await getAuth().getUser(caller.uid);
  } catch {
    throw new HttpsError("failed-precondition", "The current identity is unavailable.");
  }
  if (identity.disabled) {
    throw new HttpsError("permission-denied", "This account is not active.");
  }

  const snapshot = await db.collection("users").doc(caller.uid).get();
  const root = (snapshot.exists ? snapshot.data() : undefined) as RootUserRecord | undefined;
  if (!root || root.globalStatus !== "active") {
    throw new HttpsError("permission-denied", "This account is not active.");
  }
  if (root.identityTransition) {
    throw new HttpsError("aborted", "An identity transition is currently in progress.");
  }
  if (root.identityOrigin !== "self_signup" || root.accountType !== "tenant_user") {
    throw new HttpsError(
      "permission-denied",
      "This account was not created by signing up."
    );
  }
  if (root.authValidAfterSeconds !== undefined && (
    !Number.isSafeInteger(root.authValidAfterSeconds) ||
    authTime < root.authValidAfterSeconds
  )) {
    throw new HttpsError("permission-denied", "A new sign-in is required for this account.");
  }
  return {uid: caller.uid, authTime, root, identity};
}

export function normalizeDisplayName(value: unknown): string {
  const name = requireString(value, "displayName", {
    minLength: DISPLAY_NAME_MIN_LENGTH,
    maxLength: DISPLAY_NAME_MAX_LENGTH,
  }).replace(/\s+/g, " ");
  if (/\p{Cc}/u.test(name)) {
    throw new HttpsError("invalid-argument", "displayName contains unsupported characters.");
  }
  return name;
}

/**
 * Accepts the spacing a person types and stores the one form E.164 allows.
 *
 * Spaces, hyphens and brackets are punctuation somebody added to read their own
 * number back; they are not part of it. A leading `00` is the same instruction
 * as a `+` and is accepted as one, because a keypad without a `+` is common.
 */
export function normalizePhoneNumber(value: unknown): string {
  const raw = requireString(value, "phone", {minLength: 8, maxLength: 32});
  const compact = raw.replace(/[\s()./-]/g, "");
  const e164 = compact.startsWith("00") ? `+${compact.slice(2)}` : compact;
  if (!E164_PATTERN.test(e164)) {
    throw new HttpsError(
      "invalid-argument",
      "phone must be an international number, such as +255712345678."
    );
  }
  return e164;
}

export function normalizeSignupEmail(value: unknown): string {
  const email = normalizeEmail(requireString(value, "email", {maxLength: 254}));
  if (!email || !EMAIL_PATTERN.test(email)) {
    throw new HttpsError("invalid-argument", "email is not a valid address.");
  }
  return email;
}

interface CompleteSelfSignupRequest {
  displayName?: unknown;
  phone?: unknown;
  requestId?: unknown;
}

/**
 * Names the account, records the phone, and sends the first verification email.
 *
 * **The enqueue sits outside the transaction and after it**, both deliberately.
 * `runIdempotentFirestoreTransaction` forbids external side effects in its
 * callback - a task enqueued from a transaction that then retries is enqueued
 * twice - and running it unconditionally afterwards is safe because the delivery
 * id is derived from the `requestId`, so Cloud Tasks deduplicates a replay onto
 * the message already in flight. A retried call therefore repairs a
 * half-finished signup without sending a second email.
 */
export const completeSelfSignup = onCall<
  CompleteSelfSignupRequest,
  Promise<{displayName: string; phone: string}>
>(
  {secrets: [EMAIL_RECIPIENT_HMAC_KEYRING]},
  async (request: CallableRequest<CompleteSelfSignupRequest>) => {
    const db = getFirestore();
    const caller = await requireSelfSignupOnboarding(db, request);
    const data = requireObject(request.data);
    const displayName = normalizeDisplayName(data.displayName);
    const phone = normalizePhoneNumber(data.phone);
    const requestId = requireRequestId(data.requestId);

    // Onto the Auth record first, so `token.name` carries it at the next
    // refresh: `requestTenant` reads the root document's copy but falls back to
    // the token, and the two disagreeing is a difference nobody would look for.
    await getAuth().updateUser(caller.uid, {displayName});

    const result = await runIdempotentFirestoreTransaction(db, {
      actorUid: caller.uid,
      operation: "completeSelfSignup",
      requestId,
      input: {displayName, phone},
    }, async (transaction) => {
      transaction.set(db.collection("users").doc(caller.uid), {
        displayName,
        phone,
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
      return {displayName, phone};
    });

    // Already verified means somebody who signed up, verified, and then came
    // back to a profile that was never finished. There is nothing to send.
    if (!caller.identity.emailVerified) {
      const email = normalizeEmail(caller.identity.email);
      if (email) {
        await enqueueAccountVerificationFor({
          uid: caller.uid,
          email,
          requestId,
          requestAuthTime: caller.authTime,
        });
      }
    }
    return result;
  }
);

interface ChangeSignupEmailRequest {
  email?: unknown;
  requestId?: unknown;
}

/**
 * Moves an unverified signup's address and sends the link to the new one.
 *
 * **The order is Auth, then Firestore, then the queue**, and the reason is which
 * divergence is survivable. The Auth record is authoritative for the address;
 * the root document's copy is routing data that `requestTenant` already
 * documents as possibly stale. So a failure after Auth leaves the truth correct
 * and a mirror behind, which the next attempt repairs - where the opposite order
 * would leave the mirror claiming an address the person cannot actually sign in
 * with.
 *
 * **A message already on its way to the mistyped address cancels itself.**
 * `processAccountVerificationTask` re-reads the Auth record before sending and
 * aborts when the target address has moved, so nothing needs to chase it.
 */
export const changeSignupEmail = onCall<
  ChangeSignupEmailRequest,
  Promise<{email: string}>
>(
  {secrets: [EMAIL_RECIPIENT_HMAC_KEYRING]},
  async (request: CallableRequest<ChangeSignupEmailRequest>) => {
    const db = getFirestore();
    const caller = await requireSelfSignupOnboarding(db, request);
    if (caller.identity.emailVerified) {
      throw new HttpsError(
        "failed-precondition",
        "This address is already verified and cannot be changed here."
      );
    }
    const data = requireObject(request.data);
    const requestId = requireRequestId(data.requestId);
    const email = normalizeSignupEmail(data.email);
    if (email === normalizeEmail(caller.identity.email)) {
      throw new HttpsError("failed-precondition", "That is already this account's address.");
    }

    // Asked before anything is written, so the refusal is the ordinary one a
    // person can act on rather than an `auth/email-already-exists` surfacing
    // from underneath a half-applied change.
    try {
      const existing = await getAuth().getUserByEmail(email);
      if (existing.uid !== caller.uid) {
        throw new HttpsError("already-exists", "An account already uses that address.");
      }
    } catch (error) {
      if (error instanceof HttpsError) throw error;
      // `auth/user-not-found` is the answer this wants: nobody holds it.
    }

    const requestedAt = Timestamp.now();
    const windowStart = Timestamp.fromMillis(
      requestedAt.toMillis() - EMAIL_CHANGE_WINDOW_MILLISECONDS
    );
    const userRef = db.collection("users").doc(caller.uid);
    const eventsRef = userRef.collection("email_change_events");

    // The window is spent before Auth is touched, so a burst cannot outrun the
    // limit by failing halfway through. A replayed `requestId` returns this same
    // record rather than spending a second slot.
    await runIdempotentFirestoreTransaction(db, {
      actorUid: caller.uid,
      operation: "changeSignupEmail",
      requestId,
      input: {email},
    }, async (transaction) => {
      const recent = await transaction.get(
        eventsRef.where("createdAt", ">=", windowStart)
          .limit(MAX_EMAIL_CHANGES_PER_WINDOW)
      );
      if (recent.size >= MAX_EMAIL_CHANGES_PER_WINDOW) {
        throw new HttpsError(
          "resource-exhausted",
          "This address has been changed too many times today."
        );
      }
      transaction.create(eventsRef.doc(requestId), {
        actorUid: caller.uid,
        requestId,
        createdAt: requestedAt,
      });
      return {email};
    });

    await getAuth().updateUser(caller.uid, {email, emailVerified: false});
    await userRef.set({email, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
    await enqueueAccountVerificationFor({
      uid: caller.uid,
      email,
      requestId,
      requestAuthTime: caller.authTime,
    });
    return {email};
  }
);
