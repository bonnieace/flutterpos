export interface TenantLimits {
  maxPendingTenantsPerUser: number;
  maxTenantRequestsPer24Hours: number;
  maxOwnedActiveTenantsPerUser: number;
}

export interface TenantLimitCounts {
  pendingTenants: number;
  requestsInLast24Hours: number;
  ownedActiveTenants: number;
}

export type TenantLimitViolation =
  | "max_pending_tenants"
  | "max_requests_per_24_hours"
  | "max_owned_active_tenants";

export const DEFAULT_TENANT_LIMITS: Readonly<TenantLimits> = Object.freeze({
  maxPendingTenantsPerUser: 3,
  maxTenantRequestsPer24Hours: 5,
  maxOwnedActiveTenantsPerUser: 25,
});

const MAX_CONFIGURED_LIMIT = 10000;

function configuredLimit(value: unknown, fallback: number): number {
  return Number.isSafeInteger(value) &&
    (value as number) >= 0 &&
    (value as number) <= MAX_CONFIGURED_LIMIT ?
    value as number :
    fallback;
}

export function resolveTenantLimits(raw: unknown): TenantLimits {
  const config = raw && typeof raw === "object" && !Array.isArray(raw) ?
    raw as Record<string, unknown> :
    {};
  return {
    maxPendingTenantsPerUser: configuredLimit(
      config.maxPendingTenantsPerUser,
      DEFAULT_TENANT_LIMITS.maxPendingTenantsPerUser
    ),
    maxTenantRequestsPer24Hours: configuredLimit(
      config.maxTenantRequestsPer24Hours,
      DEFAULT_TENANT_LIMITS.maxTenantRequestsPer24Hours
    ),
    maxOwnedActiveTenantsPerUser: configuredLimit(
      config.maxOwnedActiveTenantsPerUser,
      DEFAULT_TENANT_LIMITS.maxOwnedActiveTenantsPerUser
    ),
  };
}

export function findTenantLimitViolation(
  counts: TenantLimitCounts,
  limits: TenantLimits
): TenantLimitViolation | undefined {
  if (counts.pendingTenants >= limits.maxPendingTenantsPerUser) {
    return "max_pending_tenants";
  }
  if (counts.requestsInLast24Hours >= limits.maxTenantRequestsPer24Hours) {
    return "max_requests_per_24_hours";
  }
  if (counts.ownedActiveTenants >= limits.maxOwnedActiveTenantsPerUser) {
    return "max_owned_active_tenants";
  }
  return undefined;
}
