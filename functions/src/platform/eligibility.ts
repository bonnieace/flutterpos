import {Firestore, QueryDocumentSnapshot} from "firebase-admin/firestore";
import {RootUserRecord} from "../core/model";

export const PLATFORM_ELIGIBILITY_SCAN_SOURCES = [
  "staff_memberships",
  "tenant_ownership",
  "staff_invitations",
] as const;

export type PlatformEligibilityScanSource =
  (typeof PLATFORM_ELIGIBILITY_SCAN_SOURCES)[number];

export type PlatformEligibilityBlockerKind =
  | "staff_membership"
  | "tenant_ownership"
  | "unresolved_invitation";

export interface PlatformEligibilityEvidenceItem {
  kind: PlatformEligibilityBlockerKind;
  documentPath: string;
  status?: string;
}

export interface PlatformEligibilityEvidence {
  targetUid: string;
  scannedSources: readonly PlatformEligibilityScanSource[];
  staffMemberships: readonly PlatformEligibilityEvidenceItem[];
  ownedTenants: readonly PlatformEligibilityEvidenceItem[];
  unresolvedInvitations: readonly PlatformEligibilityEvidenceItem[];
}

export type PlatformEligibilityWarningCode =
  | "membership_counter_positive"
  | "owned_tenant_counter_positive"
  | "owned_active_tenant_counter_positive"
  | "membership_counter_underreports"
  | "owned_tenant_counter_underreports";

export interface PlatformEligibilityEvaluation {
  eligible: boolean;
  blockers: readonly PlatformEligibilityEvidenceItem[];
  warnings: readonly PlatformEligibilityWarningCode[];
}

const RESOLVED_INVITATION_STATUSES = new Set([
  "accepted",
  "cancelled",
  "canceled",
  "declined",
  "expired",
  "revoked",
]);

/**
 * Missing and unknown invitation states are deliberately treated as unresolved.
 * A schema migration must not accidentally make an invitation invisible to the
 * platform eligibility decision.
 */
export function isUnresolvedInvitationStatus(status: unknown): boolean {
  if (typeof status !== "string") return true;
  return !RESOLVED_INVITATION_STATUSES.has(status.trim().toLowerCase());
}

function evidenceFromDocument(
  document: QueryDocumentSnapshot,
  kind: PlatformEligibilityBlockerKind,
  statusField: string
): PlatformEligibilityEvidenceItem {
  const data = document.data();
  const rawStatus = data[statusField];
  return {
    kind,
    documentPath: document.ref.path,
    ...(typeof rawStatus === "string" ? {status: rawStatus} : {}),
  };
}

/**
 * Reads every canonical source used to decide whether a UID can become a
 * dedicated platform identity. Counters and membership mirrors are not read.
 *
 * Every `staff` document and every `staff_invitations` document must carry a
 * server-controlled `uid` field. Relying on the document ID would not support a
 * safe collection-group query and would allow unresolved invitations to be
 * missed.
 */
export async function scanPlatformEligibility(
  db: Firestore,
  targetUid: string
): Promise<PlatformEligibilityEvidence> {
  const staffQuery = db.collectionGroup("staff").where("uid", "==", targetUid);
  const ownerQuery = db.collection("tenants").where("ownerUid", "==", targetUid);
  const invitationQuery = db
    .collectionGroup("staff_invitations")
    .where("uid", "==", targetUid);

  const [staffSnapshot, ownerSnapshot, invitationSnapshot] = await Promise.all([
    staffQuery.get(),
    ownerQuery.get(),
    invitationQuery.get(),
  ]);

  const invitations = invitationSnapshot.docs
    .filter((document) => isUnresolvedInvitationStatus(document.data().invitationStatus))
    .map((document) => evidenceFromDocument(
      document,
      "unresolved_invitation",
      "invitationStatus"
    ));

  return {
    targetUid,
    scannedSources: [...PLATFORM_ELIGIBILITY_SCAN_SOURCES],
    staffMemberships: staffSnapshot.docs.map((document) => evidenceFromDocument(
      document,
      "staff_membership",
      "status"
    )),
    ownedTenants: ownerSnapshot.docs.map((document) => evidenceFromDocument(
      document,
      "tenant_ownership",
      "status"
    )),
    unresolvedInvitations: invitations,
  };
}

function isPositiveCounter(value: unknown): boolean {
  return typeof value === "number" && Number.isFinite(value) && value > 0;
}

/**
 * The eligibility result is derived exclusively from canonical evidence.
 * Root counters contribute warnings for operators, never allow or deny a grant.
 */
export function evaluatePlatformEligibility(
  evidence: PlatformEligibilityEvidence,
  advisoryCounters: Pick<
    RootUserRecord,
    "membershipCount" | "ownedTenantCount" | "ownedActiveTenantCount"
  > = {}
): PlatformEligibilityEvaluation {
  const blockers = [
    ...evidence.staffMemberships,
    ...evidence.ownedTenants,
    ...evidence.unresolvedInvitations,
  ];
  const warnings: PlatformEligibilityWarningCode[] = [];

  if (isPositiveCounter(advisoryCounters.membershipCount)) {
    warnings.push("membership_counter_positive");
  }
  if (isPositiveCounter(advisoryCounters.ownedTenantCount)) {
    warnings.push("owned_tenant_counter_positive");
  }
  if (isPositiveCounter(advisoryCounters.ownedActiveTenantCount)) {
    warnings.push("owned_active_tenant_counter_positive");
  }
  if (evidence.staffMemberships.length > 0 && advisoryCounters.membershipCount === 0) {
    warnings.push("membership_counter_underreports");
  }
  if (evidence.ownedTenants.length > 0 && advisoryCounters.ownedTenantCount === 0) {
    warnings.push("owned_tenant_counter_underreports");
  }

  return {
    eligible: blockers.length === 0,
    blockers,
    warnings,
  };
}
