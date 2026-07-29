import {RootUserRecord} from "../core/model";

/**
 * Auth.disabled is not sufficient: global disable deliberately changes the
 * root before Auth, so every delivery rechecks this canonical gate.
 */
export function isEmailEligibleRoot(
  root: RootUserRecord | undefined,
  authenticatedAtSeconds?: number
): boolean {
  if (!root || root.globalStatus !== "active") return false;
  if (root.accountType !== "tenant_user" && root.accountType !== "platform_admin") {
    return false;
  }
  if (authenticatedAtSeconds !== undefined && (
    !Number.isSafeInteger(authenticatedAtSeconds) ||
    (root.authValidAfterSeconds !== undefined && (
      !Number.isSafeInteger(root.authValidAfterSeconds) ||
      authenticatedAtSeconds < root.authValidAfterSeconds
    ))
  )) return false;
  return true;
}
