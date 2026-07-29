import {createHmac, randomBytes, timingSafeEqual} from "node:crypto";

export const INVITATION_TOKEN_KEY_VERSION = "v1";
export const INVITATION_TOKEN_BYTES = 32;
export const INVITATION_LIFETIME_MILLISECONDS = 7 * 24 * 60 * 60 * 1000;
export const RECENT_AUTH_MAX_AGE_SECONDS = 5 * 60;

const BASE64URL_PATTERN = /^[A-Za-z0-9_-]+$/;
const MIN_SECRET_BYTES = 32;

export interface InvitationProofBinding {
  tenantId: string;
  uid: string;
  invitedEmail: string;
  invitationVersion: number;
}

export interface InvitationProof {
  token: string;
  tokenHash: string;
  tokenKeyVersion: typeof INVITATION_TOKEN_KEY_VERSION;
}

export class InvitationProofConfigurationError extends Error {
  constructor() {
    super("The invitation HMAC secret must contain at least 32 bytes.");
    this.name = "InvitationProofConfigurationError";
  }
}

function requireSecret(secret: string): void {
  if (Buffer.byteLength(secret, "utf8") < MIN_SECRET_BYTES) {
    throw new InvitationProofConfigurationError();
  }
}

function canonicalProofInput(binding: InvitationProofBinding, token: string): string {
  return [
    INVITATION_TOKEN_KEY_VERSION,
    binding.tenantId,
    binding.uid,
    binding.invitedEmail.trim().toLowerCase(),
    String(binding.invitationVersion),
    token,
  ].join("\u0000");
}

function hashToken(
  binding: InvitationProofBinding,
  token: string,
  secret: string
): Buffer {
  return createHmac("sha256", secret)
    .update(canonicalProofInput(binding, token), "utf8")
    .digest();
}

function isCanonicalToken(token: string): boolean {
  if (!BASE64URL_PATTERN.test(token)) return false;
  const bytes = Buffer.from(token, "base64url");
  return bytes.length === INVITATION_TOKEN_BYTES && bytes.toString("base64url") === token;
}

export function createInvitationProof(
  binding: InvitationProofBinding,
  secret: string,
  tokenBytes: Buffer = randomBytes(INVITATION_TOKEN_BYTES)
): InvitationProof {
  requireSecret(secret);
  if (tokenBytes.length !== INVITATION_TOKEN_BYTES) {
    throw new Error(`Invitation tokens must contain ${INVITATION_TOKEN_BYTES} random bytes.`);
  }
  const token = tokenBytes.toString("base64url");
  return {
    token,
    tokenHash: hashToken(binding, token, secret).toString("base64url"),
    tokenKeyVersion: INVITATION_TOKEN_KEY_VERSION,
  };
}

export function verifyInvitationProof(
  binding: InvitationProofBinding,
  token: string,
  storedHash: string,
  storedKeyVersion: unknown,
  secret: string
): boolean {
  requireSecret(secret);
  if (
    storedKeyVersion !== INVITATION_TOKEN_KEY_VERSION ||
    !isCanonicalToken(token) ||
    !BASE64URL_PATTERN.test(storedHash)
  ) {
    return false;
  }
  const expected = hashToken(binding, token, secret);
  const provided = Buffer.from(storedHash, "base64url");
  return provided.length === expected.length && timingSafeEqual(provided, expected);
}

export function isRecentAuthentication(
  authTime: unknown,
  nowMilliseconds: number,
  maximumAgeSeconds = RECENT_AUTH_MAX_AGE_SECONDS
): boolean {
  if (
    typeof authTime !== "number" ||
    !Number.isInteger(authTime) ||
    authTime <= 0 ||
    !Number.isFinite(nowMilliseconds)
  ) {
    return false;
  }
  const nowSeconds = Math.floor(nowMilliseconds / 1000);
  const ageSeconds = nowSeconds - authTime;
  return ageSeconds >= 0 && ageSeconds <= maximumAgeSeconds;
}
