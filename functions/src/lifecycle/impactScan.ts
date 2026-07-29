import {
  DocumentReference,
  FieldPath,
  FieldValue,
  Firestore,
  Query,
} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {buildIdempotencyIdentity} from "../core/idempotency";
import {CanonicalStaffRecord, RootUserRecord, TenantRecord} from "../core/model";
import {
  CriticalTenantAlert,
  evaluateTenantAdministrativeImpact,
  GlobalUserStatusImpact,
  GlobalUserStatusOperation,
} from "./globalStatusCore";

const IMPACT_PAGE_SIZE = 50;
const PRINCIPAL_PAGE_SIZE = 50;
const RESPONSE_TENANT_LIMIT = 100;

type ScanSource = "staff" | "owners" | "complete";

interface StoredScanProgress {
  uid?: unknown;
  status?: unknown;
  impactStatus?: unknown;
  impactScanSource?: unknown;
  impactStaffCursorPath?: unknown;
  impactOwnerCursorPath?: unknown;
  scannedTenantCount?: unknown;
  affectedTenantCount?: unknown;
  affectedTenantIds?: unknown;
}

interface TenantImpactResult {
  tenantId: string;
  alert?: CriticalTenantAlert;
}

function safeCount(value: unknown): number {
  return Number.isSafeInteger(value) && (value as number) >= 0 ? value as number : 0;
}

function safeAffectedIds(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value
    .filter((item): item is string => typeof item === "string" && item.length > 0)
    .slice(0, RESPONSE_TENANT_LIMIT);
}

function scanSource(value: unknown): ScanSource {
  return value === "owners" || value === "complete" ? value : "staff";
}

function operationRef(db: Firestore, requestId: string): DocumentReference {
  return db.collection("platform_user_operations").doc(requestId);
}

function tenantIdFromStaffPath(path: string): string | undefined {
  const segments = path.split("/");
  if (
    segments.length === 4 &&
    segments[0] === "tenants" &&
    segments[2] === "staff"
  ) {
    return segments[1];
  }
  return undefined;
}

async function hasRemainingAdministrativePrincipal(
  db: Firestore,
  tenantId: string,
  tenant: TenantRecord,
  targetUid: string
): Promise<boolean> {
  const staff = db.collection("tenants").doc(tenantId).collection("staff");
  let cursor: FirebaseFirestore.QueryDocumentSnapshot | undefined;
  while (true) {
    let query: Query = staff
      .where("status", "==", "active")
      .orderBy(FieldPath.documentId(), "asc")
      .limit(PRINCIPAL_PAGE_SIZE);
    if (cursor) query = query.startAfter(cursor);
    const snapshot = await query.get();
    const candidates = snapshot.docs.filter((document) => {
      const candidate = document.data() as CanonicalStaffRecord;
      return document.id !== targetUid &&
        candidate.uid === document.id &&
        (
          candidate.role === "admin" ||
          (candidate.role === "owner" && document.id === tenant.ownerUid)
        );
    });
    if (candidates.length > 0) {
      const roots = await db.getAll(...candidates.map((candidate) =>
        db.collection("users").doc(candidate.id)
      ));
      if (roots.some((root) => {
        if (!root.exists) return false;
        const user = root.data() as RootUserRecord;
        return user.globalStatus === "active" && user.accountType === "tenant_user";
      })) {
        return true;
      }
    }
    if (snapshot.size < PRINCIPAL_PAGE_SIZE) return false;
    cursor = snapshot.docs[snapshot.docs.length - 1];
  }
}

async function evaluateTenantImpact(
  db: Firestore,
  tenantId: string,
  targetUid: string,
  targetStaff?: CanonicalStaffRecord
): Promise<TenantImpactResult> {
  const snapshot = await db.collection("tenants").doc(tenantId).get();
  const tenant = snapshot.exists ? snapshot.data() as TenantRecord : {};
  if (tenant.status === "archived") return {tenantId};
  if (tenant.ownerUid === targetUid) {
    return {
      tenantId,
      alert: {tenantId, type: "tenant_owner_unavailable"},
    };
  }
  const targetWasPrincipal = targetStaff?.status === "active" &&
    targetStaff.role === "admin";
  if (!targetWasPrincipal) return {tenantId};
  const hasRemaining = await hasRemainingAdministrativePrincipal(
    db,
    tenantId,
    tenant,
    targetUid
  );
  return {
    tenantId,
    alert: evaluateTenantAdministrativeImpact({
      tenantId,
      tenantStatus: tenant.status,
      ownerUid: tenant.ownerUid,
      targetUid,
      targetStaffStatus: targetStaff.status,
      targetStaffRole: targetStaff.role,
      remainingPrincipals: hasRemaining ? [{
        uid: "canonical-active-principal",
        staffUid: "canonical-active-principal",
        role: "admin",
        staffStatus: "active",
        globalStatus: "active",
        accountType: "tenant_user",
      }] : [],
    }),
  };
}

async function evaluateInBoundedBatches(
  db: Firestore,
  tenantStaff: ReadonlyMap<string, CanonicalStaffRecord | undefined>,
  targetUid: string
): Promise<TenantImpactResult[]> {
  const entries = [...tenantStaff.entries()];
  const results: TenantImpactResult[] = [];
  for (let offset = 0; offset < entries.length; offset += 10) {
    const batch = entries.slice(offset, offset + 10);
    results.push(...await Promise.all(batch.map(([tenantId, staff]) =>
      evaluateTenantImpact(db, tenantId, targetUid, staff)
    )));
  }
  return results;
}

export function buildTenantSafeGlobalStatusAudit(
  alert: CriticalTenantAlert,
  correlationId: string
): Record<string, unknown> {
  return {
    eventType: alert.type,
    severity: "critical",
    tenantId: alert.tenantId,
    actorType: "platform",
    reasonCode: alert.type,
    operationReference: correlationId,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };
}

async function persistImpactPage(
  db: Firestore,
  operation: GlobalUserStatusOperation,
  source: Exclude<ScanSource, "complete">,
  nextSource: ScanSource,
  cursorPath: string | undefined,
  impacts: readonly TenantImpactResult[]
): Promise<void> {
  const opRef = operationRef(db, operation.requestId);
  const impactRefs = impacts.map((impact) =>
    opRef.collection("tenant_impacts").doc(impact.tenantId)
  );
  await db.runTransaction(async (transaction) => {
    const snapshots = await transaction.getAll(opRef, ...impactRefs);
    const storedSnapshot = snapshots[0];
    if (!storedSnapshot.exists) {
      throw new HttpsError("not-found", "The status operation no longer exists.");
    }
    const stored = storedSnapshot.data() as StoredScanProgress;
    if (stored.uid !== operation.uid || stored.status === "completed") {
      throw new HttpsError("aborted", "The status operation is no longer retryable.");
    }
    let scannedTenantCount = safeCount(stored.scannedTenantCount);
    let affectedTenantCount = safeCount(stored.affectedTenantCount);
    const affectedIds = new Set(safeAffectedIds(stored.affectedTenantIds));

    impacts.forEach((impact, index) => {
      const previous = snapshots[index + 1];
      const previousAlert = previous.exists ? previous.get("alertType") : undefined;
      if (!previous.exists) scannedTenantCount += 1;
      if (!previousAlert && impact.alert) affectedTenantCount += 1;
      if (impact.alert && affectedIds.size < RESPONSE_TENANT_LIMIT) {
        affectedIds.add(impact.tenantId);
      }
      transaction.set(impactRefs[index], {
        tenantId: impact.tenantId,
        alertType: impact.alert?.type ?? null,
        scannedAt: FieldValue.serverTimestamp(),
      }, {merge: true});

      if (impact.alert) {
        const correlationId = buildIdempotencyIdentity(
          operation.requestedBy,
          "globalUserStatusTenantImpact",
          impact.tenantId,
          operation.requestId
        ).documentId;
        const fullAlert = {
          severity: "critical",
          type: impact.alert.type,
          tenantId: impact.tenantId,
          uid: operation.uid,
          operationId: operation.requestId,
          requestedBy: operation.requestedBy,
          reason: operation.reason,
          notificationStatus: "pending",
          createdAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        };
        transaction.set(
          db.collection("tenants").doc(impact.tenantId)
            .collection("alerts").doc(correlationId),
          {
            severity: "critical",
            type: impact.alert.type,
            tenantId: impact.tenantId,
            operatorActionRequired: true,
            createdAt: FieldValue.serverTimestamp(),
            updatedAt: FieldValue.serverTimestamp(),
          },
          {merge: true}
        );
        transaction.set(
          db.collection("tenants").doc(impact.tenantId)
            .collection("audit_logs").doc(correlationId),
          buildTenantSafeGlobalStatusAudit(impact.alert, correlationId),
          {merge: true}
        );
        transaction.set(
          db.collection("platform_alerts").doc(`${correlationId}_${impact.tenantId}`),
          fullAlert,
          {merge: true}
        );
      }
    });

    transaction.update(opRef, {
      impactScanSource: nextSource,
      ...(nextSource === "complete" ? {impactStatus: "completed"} : {}),
      ...(source === "staff" ? {
        impactStaffCursorPath: cursorPath ?? FieldValue.delete(),
      } : {
        impactOwnerCursorPath: cursorPath ?? FieldValue.delete(),
      }),
      scannedTenantCount,
      affectedTenantCount,
      affectedTenantIds: [...affectedIds].sort(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
}

async function loadProgress(
  db: Firestore,
  operation: GlobalUserStatusOperation
): Promise<StoredScanProgress> {
  const snapshot = await operationRef(db, operation.requestId).get();
  if (!snapshot.exists) {
    throw new HttpsError("not-found", "The status operation no longer exists.");
  }
  const data = snapshot.data() as StoredScanProgress;
  if (data.uid !== operation.uid) {
    throw new HttpsError("aborted", "The status operation target changed.");
  }
  return data;
}

async function queryStaffPage(
  db: Firestore,
  targetUid: string,
  cursorPath: unknown
) {
  let query: Query = db.collectionGroup("staff")
    .where("uid", "==", targetUid)
    .orderBy(FieldPath.documentId(), "asc")
    .limit(IMPACT_PAGE_SIZE);
  if (typeof cursorPath === "string" && cursorPath.length > 0) {
    query = query.startAfter(db.doc(cursorPath));
  }
  return query.get();
}

async function queryOwnerPage(
  db: Firestore,
  targetUid: string,
  cursorPath: unknown
) {
  let query: Query = db.collection("tenants")
    .where("ownerUid", "==", targetUid)
    .orderBy(FieldPath.documentId(), "asc")
    .limit(IMPACT_PAGE_SIZE);
  if (typeof cursorPath === "string" && cursorPath.length > 0) {
    query = query.startAfter(db.doc(cursorPath));
  }
  return query.get();
}

/**
 * Resumable canonical impact scan. Each page and each per-tenant result is
 * persisted before the next query, so a timeout resumes instead of restarting
 * an unbounded membership scan or growing the operation document indefinitely.
 */
export async function scanAndRecordGlobalDisableImpact(
  db: Firestore,
  operation: GlobalUserStatusOperation
): Promise<GlobalUserStatusImpact> {
  while (true) {
    const progress = await loadProgress(db, operation);
    const source = scanSource(progress.impactScanSource);
    if (source === "complete") {
      const affectedTenantIds = safeAffectedIds(progress.affectedTenantIds);
      const impactSnapshots = affectedTenantIds.length > 0 ? await db.getAll(
        ...affectedTenantIds.map((tenantId) => operationRef(db, operation.requestId)
          .collection("tenant_impacts").doc(tenantId))
      ) : [];
      return {
        scannedTenantIds: [],
        alerts: affectedTenantIds.flatMap((tenantId, index) => {
          const type = impactSnapshots[index]?.get("alertType");
          return type === "tenant_owner_unavailable" ||
            type === "no_active_administrator" ? [{tenantId, type}] : [];
        }),
      };
    }

    const snapshot = source === "staff" ?
      await queryStaffPage(db, operation.uid, progress.impactStaffCursorPath) :
      await queryOwnerPage(db, operation.uid, progress.impactOwnerCursorPath);
    const tenantStaff = new Map<string, CanonicalStaffRecord | undefined>();
    for (const document of snapshot.docs) {
      const tenantId = source === "staff" ?
        tenantIdFromStaffPath(document.ref.path) : document.id;
      if (!tenantId) continue;
      tenantStaff.set(
        tenantId,
        source === "staff" ? document.data() as CanonicalStaffRecord : undefined
      );
    }
    const impacts = await evaluateInBoundedBatches(db, tenantStaff, operation.uid);
    const hasMore = snapshot.size === IMPACT_PAGE_SIZE;
    const nextSource: ScanSource = hasMore ? source :
      source === "staff" ? "owners" : "complete";
    const cursorPath = hasMore ? snapshot.docs[snapshot.docs.length - 1].ref.path : undefined;
    await persistImpactPage(
      db,
      operation,
      source,
      nextSource,
      cursorPath,
      impacts
    );
  }
}
