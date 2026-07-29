import {HttpsError} from "firebase-functions/v2/https";

const REQUEST_ID_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._:-]{7,127}$/;
const FIRESTORE_ID_PATTERN = /^[^/]{1,128}$/;

export function requireObject(value: unknown, label = "data"): Record<string, unknown> {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new HttpsError("invalid-argument", `${label} must be an object.`);
  }
  return value as Record<string, unknown>;
}
export function requireString(
  value: unknown,
  label: string,
  options: {minLength?: number; maxLength?: number} = {}
): string {
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", `${label} must be a string.`);
  }

  const normalized = value.trim();
  const minLength = options.minLength ?? 1;
  const maxLength = options.maxLength ?? 256;
  if (normalized.length < minLength || normalized.length > maxLength) {
    throw new HttpsError(
      "invalid-argument",
      `${label} must be between ${minLength} and ${maxLength} characters.`
    );
  }
  return normalized;
}

export function requireRequestId(value: unknown): string {
  const requestId = requireString(value, "requestId", {minLength: 8, maxLength: 128});
  if (!REQUEST_ID_PATTERN.test(requestId)) {
    throw new HttpsError("invalid-argument", "requestId has an invalid format.");
  }
  return requestId;
}

export function requireDocumentId(value: unknown, label: string): string {
  const documentId = requireString(value, label, {maxLength: 128});
  if (!FIRESTORE_ID_PATTERN.test(documentId) || documentId === "." || documentId === "..") {
    throw new HttpsError("invalid-argument", `${label} has an invalid format.`);
  }
  return documentId;
}

export function optionalString(
  value: unknown,
  label: string,
  options: {maxLength?: number} = {}
): string | undefined {
  if (value === undefined || value === null) return undefined;
  return requireString(value, label, {maxLength: options.maxLength});
}

export function optionalPageSize(value: unknown, defaultValue = 20, maximum = 50): number {
  if (value === undefined || value === null) return defaultValue;
  if (!Number.isInteger(value) || (value as number) < 1 || (value as number) > maximum) {
    throw new HttpsError(
      "invalid-argument",
      `pageSize must be an integer between 1 and ${maximum}.`
    );
  }
  return value as number;
}
