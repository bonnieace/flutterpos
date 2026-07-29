import {
  createHash,
  createHmac,
  timingSafeEqual,
} from "node:crypto";

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const VERSION_PATTERN = /^[A-Za-z0-9_-]{1,32}$/;
const MINIMUM_KEY_BYTES = 32;
const MAXIMUM_SUPPORTED_KEYS = 4;

export interface RecipientHmacKeyring {
  currentVersion: string;
  keys: Readonly<Record<string, string>>;
}

export interface RecipientHash {
  keyVersion: string;
  recipientHash: string;
  documentId: string;
}

export class RecipientHashConfigurationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "RecipientHashConfigurationError";
  }
}

export function normalizeEmail(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  const normalized = value.trim().toLowerCase();
  if (
    normalized.length < 3 ||
    normalized.length > 320 ||
    !EMAIL_PATTERN.test(normalized)
  ) return undefined;
  return normalized;
}

export function parseRecipientHmacKeyring(serialized: string): RecipientHmacKeyring {
  let decoded: unknown;
  try {
    decoded = JSON.parse(serialized);
  } catch {
    throw new RecipientHashConfigurationError(
      "EMAIL_RECIPIENT_HMAC_KEYRING must be valid JSON."
    );
  }
  if (!decoded || typeof decoded !== "object" || Array.isArray(decoded)) {
    throw new RecipientHashConfigurationError("The recipient HMAC keyring is invalid.");
  }
  const value = decoded as Record<string, unknown>;
  if (
    typeof value.currentVersion !== "string" ||
    !VERSION_PATTERN.test(value.currentVersion) ||
    !value.keys ||
    typeof value.keys !== "object" ||
    Array.isArray(value.keys)
  ) {
    throw new RecipientHashConfigurationError("The recipient HMAC keyring is invalid.");
  }
  const entries = Object.entries(value.keys as Record<string, unknown>);
  if (entries.length < 1 || entries.length > MAXIMUM_SUPPORTED_KEYS) {
    throw new RecipientHashConfigurationError(
      `The recipient HMAC keyring must contain 1-${MAXIMUM_SUPPORTED_KEYS} keys.`
    );
  }
  const keys: Record<string, string> = {};
  for (const [version, secret] of entries) {
    if (
      !VERSION_PATTERN.test(version) ||
      typeof secret !== "string" ||
      Buffer.byteLength(secret, "utf8") < MINIMUM_KEY_BYTES
    ) {
      throw new RecipientHashConfigurationError(
        "Every recipient HMAC key must have a valid version and at least 32 bytes."
      );
    }
    keys[version] = secret;
  }
  if (!(value.currentVersion in keys)) {
    throw new RecipientHashConfigurationError(
      "The current recipient HMAC version is not present in the keyring."
    );
  }
  return {currentVersion: value.currentVersion, keys};
}

function recipientDigest(email: string, version: string, secret: string): string {
  return createHmac("sha256", secret)
    .update(["email-recipient", version, email].join("\u0000"), "utf8")
    .digest("base64url");
}

function suppressionDocumentId(keyVersion: string, recipientHash: string): string {
  return createHash("sha256")
    .update(["email-suppression", keyVersion, recipientHash].join("\u0000"), "utf8")
    .digest("hex");
}

export function hashRecipient(
  normalizedEmail: string,
  keyring: RecipientHmacKeyring,
  keyVersion = keyring.currentVersion
): RecipientHash {
  const secret = keyring.keys[keyVersion];
  if (!secret) {
    throw new RecipientHashConfigurationError(
      "The requested recipient HMAC version is not supported."
    );
  }
  const recipientHash = recipientDigest(normalizedEmail, keyVersion, secret);
  return {
    keyVersion,
    recipientHash,
    documentId: suppressionDocumentId(keyVersion, recipientHash),
  };
}

export function allRecipientHashes(
  normalizedEmail: string,
  keyring: RecipientHmacKeyring
): RecipientHash[] {
  const versions = [
    keyring.currentVersion,
    ...Object.keys(keyring.keys)
      .filter((version) => version !== keyring.currentVersion)
      .sort(),
  ];
  return versions.map((version) => hashRecipient(normalizedEmail, keyring, version));
}

export function recipientHashMatches(
  normalizedEmail: string,
  expectedHash: unknown,
  keyVersion: unknown,
  keyring: RecipientHmacKeyring
): boolean {
  if (
    typeof expectedHash !== "string" ||
    typeof keyVersion !== "string" ||
    !keyring.keys[keyVersion]
  ) return false;
  const actual = Buffer.from(hashRecipient(
    normalizedEmail,
    keyring,
    keyVersion
  ).recipientHash, "utf8");
  const expected = Buffer.from(expectedHash, "utf8");
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}

export function stablePrivateId(namespace: string, ...parts: string[]): string {
  return createHash("sha256")
    .update([namespace, ...parts].join("\u0000"), "utf8")
    .digest("hex");
}
