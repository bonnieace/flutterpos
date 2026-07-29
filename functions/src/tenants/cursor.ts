import {createHmac, timingSafeEqual} from "node:crypto";

const CURSOR_VERSION = 1;
const MAX_CURSOR_LENGTH = 2048;
const BASE64URL_PATTERN = /^[A-Za-z0-9_-]+$/;
const MIN_SECRET_BYTES = 32;
const MAX_TIMESTAMP_SECONDS = 253402300799;

interface TenantCursorPayload {
  v: typeof CURSOR_VERSION;
  uid: string;
  createdAtSeconds: number;
  createdAtNanoseconds: number;
  tenantId: string;
}

export interface TenantCursorPosition {
  createdAtSeconds: number;
  createdAtNanoseconds: number;
  tenantId: string;
}

export class InvalidTenantCursorError extends Error {
  constructor() {
    super("The tenant cursor is invalid or expired.");
    this.name = "InvalidTenantCursorError";
  }
}

export class InvalidTenantCursorSecretError extends Error {
  constructor() {
    super("The tenant cursor signing secret must contain at least 32 bytes.");
    this.name = "InvalidTenantCursorSecretError";
  }
}

function requireSigningSecret(secret: string): void {
  if (Buffer.byteLength(secret, "utf8") < MIN_SECRET_BYTES) {
    throw new InvalidTenantCursorSecretError();
  }
}

function isValidTenantId(value: unknown): value is string {
  return typeof value === "string" &&
    value.length > 0 &&
    value.length <= 128 &&
    value !== "." &&
    value !== ".." &&
    !value.includes("/");
}

function isValidPosition(value: TenantCursorPosition): boolean {
  return Number.isSafeInteger(value.createdAtSeconds) &&
    value.createdAtSeconds >= 0 &&
    value.createdAtSeconds <= MAX_TIMESTAMP_SECONDS &&
    Number.isInteger(value.createdAtNanoseconds) &&
    value.createdAtNanoseconds >= 0 &&
    value.createdAtNanoseconds <= 999999999 &&
    isValidTenantId(value.tenantId);
}

function sign(encodedPayload: string, secret: string): Buffer {
  return createHmac("sha256", secret).update(encodedPayload, "utf8").digest();
}

export function encodeTenantCursor(
  uid: string,
  position: TenantCursorPosition,
  secret: string
): string {
  requireSigningSecret(secret);
  if (!uid || !isValidPosition(position)) {
    throw new InvalidTenantCursorError();
  }

  const payload: TenantCursorPayload = {
    v: CURSOR_VERSION,
    uid,
    createdAtSeconds: position.createdAtSeconds,
    createdAtNanoseconds: position.createdAtNanoseconds,
    tenantId: position.tenantId,
  };
  const encodedPayload = Buffer.from(JSON.stringify(payload), "utf8").toString("base64url");
  const signature = sign(encodedPayload, secret).toString("base64url");
  return `${encodedPayload}.${signature}`;
}

export function decodeTenantCursor(
  cursor: string,
  expectedUid: string,
  secret: string
): TenantCursorPosition {
  requireSigningSecret(secret);
  if (!cursor || cursor.length > MAX_CURSOR_LENGTH || !expectedUid) {
    throw new InvalidTenantCursorError();
  }

  const parts = cursor.split(".");
  if (
    parts.length !== 2 ||
    !BASE64URL_PATTERN.test(parts[0]) ||
    !BASE64URL_PATTERN.test(parts[1])
  ) {
    throw new InvalidTenantCursorError();
  }

  let providedSignature: Buffer;
  try {
    providedSignature = Buffer.from(parts[1], "base64url");
  } catch {
    throw new InvalidTenantCursorError();
  }
  const expectedSignature = sign(parts[0], secret);
  if (
    providedSignature.length !== expectedSignature.length ||
    !timingSafeEqual(providedSignature, expectedSignature)
  ) {
    throw new InvalidTenantCursorError();
  }

  let payload: unknown;
  try {
    payload = JSON.parse(Buffer.from(parts[0], "base64url").toString("utf8"));
  } catch {
    throw new InvalidTenantCursorError();
  }
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
    throw new InvalidTenantCursorError();
  }

  const candidate = payload as Partial<TenantCursorPayload>;
  const position: TenantCursorPosition = {
    createdAtSeconds: candidate.createdAtSeconds as number,
    createdAtNanoseconds: candidate.createdAtNanoseconds as number,
    tenantId: candidate.tenantId as string,
  };
  if (
    candidate.v !== CURSOR_VERSION ||
    candidate.uid !== expectedUid ||
    !isValidPosition(position)
  ) {
    throw new InvalidTenantCursorError();
  }
  return position;
}
