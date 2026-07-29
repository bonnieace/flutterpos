import {HttpsError} from "firebase-functions/v2/https";
import {RootUserRecord} from "../core/model";

export interface TenantIdentityOptions {
  requireActive: boolean;
  hasPlatformClaim?: boolean;
}

export function assertTenantIdentityTarget(
  user: RootUserRecord | undefined,
  options: TenantIdentityOptions
): RootUserRecord {
  if (!user) {
    throw new HttpsError("failed-precondition", "The target root user does not exist.");
  }
  if (user.identityTransition) {
    throw new HttpsError("aborted", "The target identity has a transition in progress.");
  }
  if (user.accountType !== "tenant_user" || options.hasPlatformClaim === true) {
    throw new HttpsError(
      "permission-denied",
      "Platform identities cannot have tenant memberships."
    );
  }
  if (options.requireActive && user.globalStatus !== "active") {
    throw new HttpsError("failed-precondition", "The target account is not active.");
  }
  return user;
}

export function normalizedCounter(value: unknown): number {
  return Number.isSafeInteger(value) && (value as number) >= 0 ? value as number : 0;
}
