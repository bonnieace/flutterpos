import {GlobalStatus} from "../core/model";
import {logAbsorbedFailure} from "../core/absorbedFailure";

export type GlobalOperationStatus = "pending" | "completed" | "partially_failed";
export type GlobalOperationStepStatus = "pending" | "completed" | "not_applicable";
export type GlobalOperationClaimStatus = GlobalOperationStepStatus | "not_restored";

export interface GlobalUserStatusInput {
  uid: string;
  targetStatus: GlobalStatus;
  requestedBy: string;
  reason: string;
  requestId: string;
}

export interface GlobalUserStatusOperation extends GlobalUserStatusInput {
  firestoreStatus: GlobalOperationStepStatus;
  impactStatus: GlobalOperationStepStatus;
  authStatus: GlobalOperationStepStatus;
  claimStatus: GlobalOperationClaimStatus;
  tokenStatus: GlobalOperationStepStatus;
  status: GlobalOperationStatus;
  attemptCount: number;
  affectedTenantIds: readonly string[];
  scannedTenantIds: readonly string[];
  authValidAfterSeconds?: number;
  lastErrorCode?: string;
}

export type CriticalTenantAlertType =
  | "tenant_owner_unavailable"
  | "no_active_administrator";

export interface CriticalTenantAlert {
  tenantId: string;
  type: CriticalTenantAlertType;
}

export interface GlobalUserStatusImpact {
  scannedTenantIds: readonly string[];
  alerts: readonly CriticalTenantAlert[];
}

export interface TenantAdministrativeSnapshot {
  tenantId: string;
  tenantStatus: unknown;
  ownerUid: unknown;
  targetUid: string;
  targetStaffStatus?: unknown;
  targetStaffRole?: unknown;
  remainingPrincipals: readonly {
    uid: string;
    staffUid?: unknown;
    role?: unknown;
    staffStatus?: unknown;
    globalStatus?: unknown;
    accountType?: unknown;
  }[];
}

export interface GlobalUserStatusSagaAdapter {
  prepare(input: GlobalUserStatusInput): Promise<GlobalUserStatusOperation>;
  processDisableImpact(
    operation: GlobalUserStatusOperation
  ): Promise<GlobalUserStatusImpact>;
  setAuthDisabled(uid: string, disabled: boolean): Promise<void>;
  removePlatformClaim(uid: string): Promise<void>;
  revokeRefreshTokens(uid: string): Promise<number>;
  activateRoot(
    uid: string,
    requestId: string,
    authValidAfterSeconds: number
  ): Promise<void>;
  recordSteps(
    requestId: string,
    steps: Partial<Pick<
      GlobalUserStatusOperation,
      "firestoreStatus" | "impactStatus" | "authStatus" | "claimStatus" | "tokenStatus" |
      "authValidAfterSeconds"
    >>
  ): Promise<void>;
  complete(operation: GlobalUserStatusOperation): Promise<GlobalUserStatusOperation>;
  recordFailure(
    operation: GlobalUserStatusOperation,
    errorCode: string
  ): Promise<GlobalUserStatusOperation>;
}

export function isSameGlobalStatusRequest(
  existing: Pick<
    GlobalUserStatusInput,
    "uid" | "targetStatus" | "requestedBy" | "reason" | "requestId"
  >,
  input: GlobalUserStatusInput
): boolean {
  return existing.uid === input.uid &&
    existing.targetStatus === input.targetStatus &&
    existing.requestedBy === input.requestedBy &&
    existing.reason === input.reason &&
    existing.requestId === input.requestId;
}

function isActiveAdministrativePrincipal(
  principal: TenantAdministrativeSnapshot["remainingPrincipals"][number]
): boolean {
  return principal.uid.length > 0 &&
    principal.staffUid === principal.uid &&
    principal.staffStatus === "active" &&
    (principal.role === "owner" || principal.role === "admin") &&
    principal.globalStatus === "active" &&
    principal.accountType === "tenant_user";
}

export function evaluateTenantAdministrativeImpact(
  snapshot: TenantAdministrativeSnapshot
): CriticalTenantAlert | undefined {
  if (snapshot.tenantStatus === "archived") return undefined;
  if (snapshot.ownerUid === snapshot.targetUid) {
    return {tenantId: snapshot.tenantId, type: "tenant_owner_unavailable"};
  }
  const targetWasAdministrativePrincipal =
    snapshot.targetStaffStatus === "active" &&
    (snapshot.targetStaffRole === "owner" || snapshot.targetStaffRole === "admin");
  if (
    targetWasAdministrativePrincipal &&
    !snapshot.remainingPrincipals.some(isActiveAdministrativePrincipal)
  ) {
    return {tenantId: snapshot.tenantId, type: "no_active_administrator"};
  }
  return undefined;
}

export function withoutPlatformRole(
  claims: Readonly<Record<string, unknown>> | undefined
): Record<string, unknown> {
  const result = {...(claims ?? {})};
  delete result.platformRole;
  return result;
}

export function safeLifecycleErrorCode(error: unknown): string {
  if (error && typeof error === "object" && "code" in error) {
    const code = (error as {code?: unknown}).code;
    if (typeof code === "string" && code.length > 0) return code.slice(0, 128);
  }
  return "unknown";
}

export function globalStatusRetryDelayMilliseconds(attemptCount: number): number {
  const normalizedAttempt = Number.isSafeInteger(attemptCount) && attemptCount > 0 ?
    attemptCount : 1;
  const exponent = Math.min(normalizedAttempt - 1, 7);
  return Math.min(6 * 60 * 60 * 1000, 5 * 60 * 1000 * (2 ** exponent));
}

function applySteps(
  operation: GlobalUserStatusOperation,
  steps: Partial<Pick<
    GlobalUserStatusOperation,
    "firestoreStatus" | "impactStatus" | "authStatus" | "claimStatus" | "tokenStatus" |
    "authValidAfterSeconds"
  >>
): void {
  Object.assign(operation, steps);
}

async function recordSteps(
  adapter: GlobalUserStatusSagaAdapter,
  operation: GlobalUserStatusOperation,
  steps: Parameters<GlobalUserStatusSagaAdapter["recordSteps"]>[1]
): Promise<void> {
  await adapter.recordSteps(operation.requestId, steps);
  applySteps(operation, steps);
}

async function runDisableSaga(
  adapter: GlobalUserStatusSagaAdapter,
  operation: GlobalUserStatusOperation
): Promise<void> {
  // prepare() has already committed the root-first Firestore disable.
  if (operation.impactStatus !== "completed") {
    const impact = await adapter.processDisableImpact(operation);
    operation.affectedTenantIds = impact.alerts.map((alert) => alert.tenantId);
    operation.scannedTenantIds = [...impact.scannedTenantIds];
    operation.impactStatus = "completed";
  }
  if (operation.authStatus !== "completed") {
    await adapter.setAuthDisabled(operation.uid, true);
    await recordSteps(adapter, operation, {authStatus: "completed"});
  }
  if (operation.claimStatus !== "completed") {
    await adapter.removePlatformClaim(operation.uid);
    await recordSteps(adapter, operation, {claimStatus: "completed"});
  }
  if (operation.tokenStatus !== "completed") {
    await adapter.revokeRefreshTokens(operation.uid);
    await recordSteps(adapter, operation, {tokenStatus: "completed"});
  }
}

async function runReactivateSaga(
  adapter: GlobalUserStatusSagaAdapter,
  operation: GlobalUserStatusOperation
): Promise<void> {
  if (operation.authStatus !== "completed") {
    await adapter.setAuthDisabled(operation.uid, false);
    await recordSteps(adapter, operation, {authStatus: "completed"});
  }
  if (operation.tokenStatus !== "completed") {
    const authValidAfterSeconds = await adapter.revokeRefreshTokens(operation.uid);
    await recordSteps(adapter, operation, {
      tokenStatus: "completed",
      authValidAfterSeconds,
    });
  }
  if (
    !Number.isSafeInteger(operation.authValidAfterSeconds) ||
    (operation.authValidAfterSeconds as number) <= 0
  ) {
    throw Object.assign(new Error("The Auth session cutoff is missing."), {
      code: "lifecycle/missing-auth-cutoff",
    });
  }
  if (operation.firestoreStatus !== "completed") {
    await adapter.activateRoot(
      operation.uid,
      operation.requestId,
      operation.authValidAfterSeconds as number
    );
    await recordSteps(adapter, operation, {firestoreStatus: "completed"});
  }
}

/**
 * Runs one resumable attempt. External effects are idempotent, and each phase
 * is durably marked only after it succeeds. Repeating an effect after a marker
 * write failure is safe and preferable to skipping a security operation.
 */
export async function runGlobalUserStatusSaga(
  adapter: GlobalUserStatusSagaAdapter,
  input: GlobalUserStatusInput
): Promise<GlobalUserStatusOperation> {
  const operation = await adapter.prepare(input);
  if (operation.status === "completed") return operation;

  try {
    if (operation.targetStatus === "disabled") {
      await runDisableSaga(adapter, operation);
    } else {
      await runReactivateSaga(adapter, operation);
    }
    return await adapter.complete(operation);
  } catch (error) {
    const code = safeLifecycleErrorCode(error);
    logAbsorbedFailure("lifecycle.global_status_failed", error, {
      requestId: operation.requestId,
      uid: operation.uid,
      targetStatus: operation.targetStatus,
      safeCode: code,
      attempt: operation.attemptCount,
    });
    return adapter.recordFailure(operation, code);
  }
}
