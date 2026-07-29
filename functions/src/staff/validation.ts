import {HttpsError} from "firebase-functions/v2/https";
import {isTenantRole, MembershipStatus, TenantRole} from "../core/model";
import {requireString} from "../core/validation";

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const TOKEN_PATTERN = /^[A-Za-z0-9_-]{43}$/;

export function normalizeEmail(value: unknown): string {
  const email = requireString(value, "email", {maxLength: 320}).toLowerCase();
  if (!EMAIL_PATTERN.test(email)) {
    throw new HttpsError("invalid-argument", "email must be a valid email address.");
  }
  return email;
}

export function normalizeStaffName(value: unknown): string {
  return requireString(value, "name", {maxLength: 100}).replace(/\s+/g, " ");
}

export function normalizePhone(value: unknown): string {
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", "phone must be a string.");
  }
  const phone = value.trim();
  if (phone.length > 32 || /[\p{Cc}]/u.test(phone)) {
    throw new HttpsError("invalid-argument", "phone has an invalid format.");
  }
  return phone;
}

export function requireInvitableRole(value: unknown): Exclude<TenantRole, "owner"> {
  if (!isTenantRole(value) || value === "owner") {
    throw new HttpsError(
      "invalid-argument",
      "role must be admin, manager, or cashier."
    );
  }
  return value;
}

export function requireStaffRole(value: unknown): TenantRole {
  if (!isTenantRole(value)) {
    throw new HttpsError(
      "invalid-argument",
      "role must be owner, admin, manager, or cashier."
    );
  }
  return value;
}

export function requireSettableMembershipStatus(value: unknown): Extract<
  MembershipStatus,
  "active" | "inactive"
> {
  if (value !== "active" && value !== "inactive") {
    throw new HttpsError("invalid-argument", "status must be active or inactive.");
  }
  return value;
}

export function requireInvitationVersion(value: unknown): number {
  if (!Number.isSafeInteger(value) || (value as number) < 1) {
    throw new HttpsError(
      "invalid-argument",
      "invitationVersion must be a positive integer."
    );
  }
  return value as number;
}

export function requireInvitationToken(value: unknown): string {
  const token = requireString(value, "invitationToken", {maxLength: 128});
  if (!TOKEN_PATTERN.test(token)) {
    throw new HttpsError("invalid-argument", "invitationToken has an invalid format.");
  }
  return token;
}

export function requireCancellationReason(value: unknown): string {
  return requireString(value, "reason", {minLength: 3, maxLength: 500});
}
