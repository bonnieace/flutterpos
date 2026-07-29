import {createHash} from "node:crypto";
import {MirrorRepairDecision, MirrorRepairIssue} from "./membershipMirror";

export const USER_REPAIR_PAGE_SIZE = 75;
export const TENANT_REPAIR_PAGE_SIZE = 75;
export const FULL_REPAIR_DISCOVERY_PAGE_SIZE = 75;
// Longer than the deployed five-minute task deadline, preventing overlap.
export const REPAIR_LEASE_MILLISECONDS = 6 * 60 * 1000;

export type MembershipRepairRunKind =
  | "target_user"
  | "target_tenant"
  | "weekly_full";

export type MembershipRepairRunStatus =
  | "pending"
  | "running"
  | "completed";

export type MembershipRepairPhase =
  | "canonical"
  | "mirrors"
  | "finalize"
  | "users";

export interface MembershipRepairSummary {
  canonicalDocumentsScanned: number;
  mirrorDocumentsScanned: number;
  mirrorsCreated: number;
  mirrorsUpdated: number;
  mirrorsDeleted: number;
  mirrorsUnchanged: number;
  invalidCanonicalDocuments: number;
  rootDocumentsUpdated: number;
  defaultTenantIdsCleared: number;
  usersDiscovered: number;
  childRunsQueued: number;
  issueCounts: Partial<Record<MirrorRepairIssue | "invalid_document_path", number>>;
}

export interface RepairTaskPayload {
  runId: string;
  revision: number;
}

export interface RepairTaskContinuation {
  tasks: readonly RepairTaskPayload[];
}

export interface RepairTaskRuntime {
  process(payload: RepairTaskPayload): Promise<RepairTaskContinuation>;
  enqueue(payload: RepairTaskPayload): Promise<void>;
  recordFailure(payload: RepairTaskPayload, error: unknown): Promise<void>;
}

export interface CanonicalStaffLocation {
  tenantId: string;
  uid: string;
}

export interface MembershipMirrorLocation {
  uid: string;
  tenantId: string;
}

export function emptyRepairSummary(): MembershipRepairSummary {
  return {
    canonicalDocumentsScanned: 0,
    mirrorDocumentsScanned: 0,
    mirrorsCreated: 0,
    mirrorsUpdated: 0,
    mirrorsDeleted: 0,
    mirrorsUnchanged: 0,
    invalidCanonicalDocuments: 0,
    rootDocumentsUpdated: 0,
    defaultTenantIdsCleared: 0,
    usersDiscovered: 0,
    childRunsQueued: 0,
    issueCounts: {},
  };
}

function incrementIssue(
  summary: MembershipRepairSummary,
  issue: MirrorRepairIssue | "invalid_document_path"
): void {
  summary.issueCounts[issue] = (summary.issueCounts[issue] ?? 0) + 1;
}

/** Mutates a page-local summary only; persisted summaries are merged explicitly. */
export function recordMirrorDecision(
  summary: MembershipRepairSummary,
  decision: MirrorRepairDecision,
  mirrorExisted: boolean
): void {
  if (decision.action === "noop") {
    summary.mirrorsUnchanged += 1;
  } else if (decision.action === "upsert") {
    if (mirrorExisted) summary.mirrorsUpdated += 1;
    else summary.mirrorsCreated += 1;
  } else if (mirrorExisted) {
    summary.mirrorsDeleted += 1;
  }
  for (const issue of decision.issues) {
    incrementIssue(summary, issue);
    if (
      issue !== "mirror_missing" &&
      issue !== "mirror_drift" &&
      issue !== "missing_canonical_membership"
    ) {
      summary.invalidCanonicalDocuments += 1;
    }
  }
}

export function recordInvalidDocumentPath(summary: MembershipRepairSummary): void {
  incrementIssue(summary, "invalid_document_path");
  summary.invalidCanonicalDocuments += 1;
}

export function mergeRepairSummaries(
  left: MembershipRepairSummary,
  right: MembershipRepairSummary
): MembershipRepairSummary {
  const result = emptyRepairSummary();
  for (const key of [
    "canonicalDocumentsScanned",
    "mirrorDocumentsScanned",
    "mirrorsCreated",
    "mirrorsUpdated",
    "mirrorsDeleted",
    "mirrorsUnchanged",
    "invalidCanonicalDocuments",
    "rootDocumentsUpdated",
    "defaultTenantIdsCleared",
    "usersDiscovered",
    "childRunsQueued",
  ] as const) {
    result[key] = left[key] + right[key];
  }
  const issueKeys = new Set([
    ...Object.keys(left.issueCounts),
    ...Object.keys(right.issueCounts),
  ] as Array<MirrorRepairIssue | "invalid_document_path">);
  for (const key of issueKeys) {
    result.issueCounts[key] = (left.issueCounts[key] ?? 0) +
      (right.issueCounts[key] ?? 0);
  }
  return result;
}

function digest(value: string): string {
  return createHash("sha256").update(value).digest("hex").slice(0, 40);
}

/** IDs are deterministic, bounded, and evenly distributed for Firestore/Cloud Tasks. */
export function membershipRepairRunId(
  kind: MembershipRepairRunKind,
  sourceKey: string
): string {
  return `mr_${digest(`${kind}\u0000${sourceKey}`)}`;
}

export function membershipRepairTaskId(payload: RepairTaskPayload): string {
  return `mrt_${digest(`${payload.runId}\u0000${payload.revision}`)}`;
}

export function parseCanonicalStaffPath(path: string): CanonicalStaffLocation | undefined {
  const segments = path.split("/");
  if (
    segments.length !== 4 ||
    segments[0] !== "tenants" ||
    segments[2] !== "staff" ||
    segments[1].length === 0 ||
    segments[3].length === 0
  ) {
    return undefined;
  }
  return {tenantId: segments[1], uid: segments[3]};
}

export function parseMembershipMirrorPath(
  path: string
): MembershipMirrorLocation | undefined {
  const segments = path.split("/");
  if (
    segments.length !== 4 ||
    segments[0] !== "users" ||
    segments[2] !== "tenant_memberships" ||
    segments[1].length === 0 ||
    segments[3].length === 0
  ) {
    return undefined;
  }
  return {uid: segments[1], tenantId: segments[3]};
}

export function safeRepairErrorCode(error: unknown): string {
  if (error && typeof error === "object" && "code" in error) {
    const code = (error as {code?: unknown}).code;
    if (typeof code === "string" && code.length > 0) return code.slice(0, 128);
    if (typeof code === "number" && Number.isFinite(code)) return `${code}`;
  }
  return "unknown";
}

function requireTaskPayload(payload: RepairTaskPayload): void {
  if (!/^mr_[a-f0-9]{40}$/.test(payload.runId)) {
    throw Object.assign(new Error("Invalid membership repair run ID."), {
      code: "invalid-argument",
    });
  }
  if (!Number.isSafeInteger(payload.revision) || payload.revision < 0) {
    throw Object.assign(new Error("Invalid membership repair revision."), {
      code: "invalid-argument",
    });
  }
}

/** Dependency-injected task orchestration used by the deployed queue handler. */
export async function executeMembershipRepairTask(
  runtime: RepairTaskRuntime,
  payload: RepairTaskPayload
): Promise<void> {
  requireTaskPayload(payload);
  try {
    const continuation = await runtime.process(payload);
    await Promise.all(continuation.tasks.map((task) => runtime.enqueue(task)));
  } catch (error) {
    await runtime.recordFailure(payload, error);
    throw error;
  }
}
