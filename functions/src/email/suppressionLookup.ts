import {Firestore} from "firebase-admin/firestore";
import {
  allRecipientHashes,
  hashRecipient,
  normalizeEmail,
  RecipientHash,
  RecipientHmacKeyring,
} from "./recipientHash";

export interface RecipientPrivacyBinding {
  normalizedEmail: string;
  current: RecipientHash;
  supported: readonly RecipientHash[];
}

/**
 * Shared seam for every delivery type, including staff invitations. The
 * normalized address is returned for transient Auth/provider use only; callers
 * must persist `current.recipientHash` and `current.keyVersion`, never the
 * address.
 */
export function bindRecipientPrivacy(
  email: unknown,
  keyring: RecipientHmacKeyring
): RecipientPrivacyBinding | undefined {
  const normalizedEmail = normalizeEmail(email);
  if (!normalizedEmail) return undefined;
  return {
    normalizedEmail,
    current: hashRecipient(normalizedEmail, keyring),
    supported: allRecipientHashes(normalizedEmail, keyring),
  };
}

/** Reads current and supported previous suppression keys without a plaintext query. */
export async function hasActiveEmailSuppression(
  db: Firestore,
  binding: RecipientPrivacyBinding
): Promise<boolean> {
  const snapshots = await db.getAll(...binding.supported.map((hash) =>
    db.collection("email_suppressions").doc(hash.documentId)));
  return snapshots.some((snapshot) => snapshot.exists &&
    snapshot.data()?.status === "active");
}
