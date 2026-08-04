import {randomUUID} from "node:crypto";
import {
  DocumentData,
  DocumentReference,
  DocumentSnapshot,
  FieldPath,
  FieldValue,
  Firestore,
  Query,
  QueryDocumentSnapshot,
  Timestamp,
  WriteBatch,
} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {
  CanonicalStaffRecord,
  RootUserRecord,
  TenantMembershipMirror,
  TenantRecord,
} from "../core/model";
import {
  addRootRoutingCounts,
  MirrorRepairDecision,
  planMembershipMirrorRepair,
  RootRoutingCounts,
  rootRoutingContribution,
} from "./membershipMirror";
import {
  emptyRepairSummary,
  FULL_REPAIR_DISCOVERY_PAGE_SIZE,
  membershipRepairRunId,
  MembershipRepairPhase,
  MembershipRepairRunKind,
  MembershipRepairRunStatus,
  MembershipRepairSummary,
  mergeRepairSummaries,
  parseCanonicalStaffPath,
  parseMembershipMirrorPath,
  recordInvalidDocumentPath,
  recordMirrorDecision,
  REPAIR_LEASE_MILLISECONDS,
  RepairTaskContinuation,
  RepairTaskPayload,
  safeRepairErrorCode,
  TENANT_REPAIR_PAGE_SIZE,
  USER_REPAIR_PAGE_SIZE,
} from "./repairRun";

const RUN_COLLECTION = "platform_membership_repair_runs";
const ZERO_COUNTS: RootRoutingCounts = {
  membershipCount: 0,
  ownedTenantCount: 0,
  ownedActiveTenantCount: 0,
};

interface StaffDocument extends CanonicalStaffRecord {
  createdAt?: unknown;
  joinedAt?: unknown;
}

interface StoredRepairRun {
  kind: MembershipRepairRunKind;
  status: MembershipRepairRunStatus;
  phase: MembershipRepairPhase;
  revision: number;
  attemptCount: number;
  childRunsCompleted: number;
  childSummary: MembershipRepairSummary;
  cursor?: string;
  targetUid?: string;
  tenantId?: string;
  sourceKey: string;
  sourceJobPath?: string;
  sourceOperationId?: string;
  parentRunId?: string;
  summary: MembershipRepairSummary;
  rootCounts: RootRoutingCounts;
  leaseToken?: string;
  leaseExpiresAt?: Timestamp;
  nextAttemptAt?: Timestamp;
}

interface ClaimedRepairRun extends StoredRepairRun {
  runId: string;
  leaseToken: string;
}

interface EnsureRunInput {
  kind: MembershipRepairRunKind;
  sourceKey: string;
  targetUid?: string;
  tenantId?: string;
  sourceJobPath?: string;
  sourceOperationId?: string;
  parentRunId?: string;
}

interface ProcessedPage {
  continuation: RepairTaskContinuation;
}

function runRef(db: Firestore, runId: string): DocumentReference<DocumentData> {
  return db.collection(RUN_COLLECTION).doc(runId);
}

function requireDocumentSegment(value: unknown, field: string): string {
  if (!isDocumentSegment(value)) {
    throw new HttpsError("invalid-argument", `${field} is not a valid document ID.`);
  }
  return value;
}

function isDocumentSegment(value: unknown): value is string {
  return !(
    typeof value !== "string" ||
    value.length === 0 ||
    value.length > 1500 ||
    value.includes("/")
  );
}

function requireCollectionGroupCursor(
  value: unknown,
  collectionGroup: string
): string {
  if (typeof value !== "string" || value.length === 0 || value.length > 6144) {
    throw new HttpsError("data-loss", "The collection-group repair cursor is invalid.");
  }
  const segments = value.split("/");
  if (
    segments.length < 2 ||
    segments.length % 2 !== 0 ||
    segments.some((segment) => segment.length === 0) ||
    segments[segments.length - 2] !== collectionGroup
  ) {
    throw new HttpsError("data-loss", "The collection-group repair cursor is invalid.");
  }
  return value;
}

function initialPhase(kind: MembershipRepairRunKind): MembershipRepairPhase {
  return kind === "weekly_full" ? "users" : "canonical";
}

function requireSourceKey(value: string): string {
  if (value.length === 0 || value.length > 2048) {
    throw new HttpsError("invalid-argument", "sourceKey must contain 1 to 2048 characters.");
  }
  return value;
}

function requireParentRunId(value: string): string {
  if (!/^mr_[a-f0-9]{40}$/.test(value)) {
    throw new HttpsError("invalid-argument", "parentRunId is invalid.");
  }
  return value;
}

function nonNegativeInteger(value: unknown): number {
  return Number.isSafeInteger(value) && (value as number) >= 0 ? value as number : 0;
}

function normalizedSummary(value: unknown): MembershipRepairSummary {
  const source = value && typeof value === "object" ?
    value as Partial<MembershipRepairSummary> : {};
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
    result[key] = nonNegativeInteger(source[key]);
  }
  if (source.issueCounts && typeof source.issueCounts === "object") {
    for (const [key, count] of Object.entries(source.issueCounts)) {
      if (Number.isSafeInteger(count) && (count as number) >= 0) {
        result.issueCounts[key as keyof typeof result.issueCounts] = count as number;
      }
    }
  }
  return result;
}

function normalizedRootCounts(value: unknown): RootRoutingCounts {
  const source = value && typeof value === "object" ?
    value as Partial<RootRoutingCounts> : {};
  return {
    membershipCount: nonNegativeInteger(source.membershipCount),
    ownedTenantCount: nonNegativeInteger(source.ownedTenantCount),
    ownedActiveTenantCount: nonNegativeInteger(source.ownedActiveTenantCount),
  };
}

function parseRun(runId: string, data: DocumentData): StoredRepairRun {
  const kind = data.kind;
  if (kind !== "target_user" && kind !== "target_tenant" && kind !== "weekly_full") {
    throw new HttpsError("data-loss", `Repair run ${runId} has an invalid kind.`);
  }
  const status = data.status;
  if (status !== "pending" && status !== "running" && status !== "completed") {
    throw new HttpsError("data-loss", `Repair run ${runId} has an invalid status.`);
  }
  const phase = data.phase;
  if (phase !== "canonical" && phase !== "mirrors" && phase !== "finalize" && phase !== "users") {
    throw new HttpsError("data-loss", `Repair run ${runId} has an invalid phase.`);
  }
  const sourceKey = typeof data.sourceKey === "string" ? data.sourceKey : "";
  if (sourceKey.length === 0) {
    throw new HttpsError("data-loss", `Repair run ${runId} has no source key.`);
  }
  return {
    kind,
    status,
    phase,
    revision: nonNegativeInteger(data.revision),
    attemptCount: nonNegativeInteger(data.attemptCount),
    childRunsCompleted: nonNegativeInteger(data.childRunsCompleted),
    childSummary: normalizedSummary(data.childSummary),
    ...(typeof data.cursor === "string" ? {cursor: data.cursor} : {}),
    ...(typeof data.targetUid === "string" ? {targetUid: data.targetUid} : {}),
    ...(typeof data.tenantId === "string" ? {tenantId: data.tenantId} : {}),
    sourceKey,
    ...(typeof data.sourceJobPath === "string" ? {sourceJobPath: data.sourceJobPath} : {}),
    ...(typeof data.sourceOperationId === "string" ? {
      sourceOperationId: data.sourceOperationId,
    } : {}),
    ...(typeof data.parentRunId === "string" ? {parentRunId: data.parentRunId} : {}),
    summary: normalizedSummary(data.summary),
    rootCounts: normalizedRootCounts(data.rootCounts),
    ...(typeof data.leaseToken === "string" ? {leaseToken: data.leaseToken} : {}),
    ...(data.leaseExpiresAt instanceof Timestamp ? {
      leaseExpiresAt: data.leaseExpiresAt,
    } : {}),
    ...(data.nextAttemptAt instanceof Timestamp ? {
      nextAttemptAt: data.nextAttemptAt,
    } : {}),
  };
}

function initialRunData(input: EnsureRunInput): DocumentData {
  return {
    kind: input.kind,
    status: "pending",
    phase: initialPhase(input.kind),
    revision: 0,
    attemptCount: 0,
    childRunsCompleted: 0,
    childSummary: emptyRepairSummary(),
    sourceKey: input.sourceKey,
    initiatedBy: "system",
    authority: "canonical_tenant_staff_root",
    authorizationPurpose: false,
    ...(input.targetUid ? {targetUid: input.targetUid} : {}),
    ...(input.tenantId ? {tenantId: input.tenantId} : {}),
    ...(input.sourceJobPath ? {sourceJobPath: input.sourceJobPath} : {}),
    ...(input.sourceOperationId ? {sourceOperationId: input.sourceOperationId} : {}),
    ...(input.parentRunId ? {parentRunId: input.parentRunId} : {}),
    summary: emptyRepairSummary(),
    rootCounts: ZERO_COUNTS,
    nextAttemptAt: FieldValue.serverTimestamp(),
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };
}

function sameImmutableRun(existing: StoredRepairRun, input: EnsureRunInput): boolean {
  return existing.kind === input.kind &&
    existing.sourceKey === input.sourceKey &&
    existing.targetUid === input.targetUid &&
    existing.tenantId === input.tenantId &&
    existing.sourceJobPath === input.sourceJobPath &&
    existing.sourceOperationId === input.sourceOperationId &&
    existing.parentRunId === input.parentRunId;
}

async function ensureRun(db: Firestore, input: EnsureRunInput): Promise<RepairTaskPayload> {
  const runId = membershipRepairRunId(input.kind, input.sourceKey);
  const ref = runRef(db, runId);
  const revision = await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (!snapshot.exists) {
      transaction.create(ref, initialRunData(input));
      return 0;
    }
    const existing = parseRun(runId, snapshot.data() ?? {});
    if (!sameImmutableRun(existing, input)) {
      throw new HttpsError(
        "already-exists",
        "The deterministic repair run ID belongs to a different repair request."
      );
    }
    return existing.revision;
  });
  return {runId, revision};
}

function targetUserRepairInput(
  uid: string,
  sourceKey: string,
  parentRunId?: string
): EnsureRunInput {
  return {
    kind: "target_user",
    sourceKey: requireSourceKey(sourceKey),
    targetUid: requireDocumentSegment(uid, "uid"),
    ...(parentRunId ? {parentRunId: requireParentRunId(parentRunId)} : {}),
  };
}

export async function createTargetedUserRepair(
  db: Firestore,
  uid: string,
  sourceKey: string,
  parentRunId?: string
): Promise<RepairTaskPayload> {
  return ensureRun(db, targetUserRepairInput(uid, sourceKey, parentRunId));
}

export async function createTargetedTenantRepair(
  db: Firestore,
  tenantId: string,
  sourceKey: string,
  options: {
    sourceJobPath?: string;
    sourceOperationId?: string;
  } = {}
): Promise<RepairTaskPayload> {
  const normalizedTenantId = requireDocumentSegment(tenantId, "tenantId");
  if (
    options.sourceJobPath &&
    !validFanoutJobPath(options.sourceJobPath, normalizedTenantId)
  ) {
    throw new HttpsError("invalid-argument", "sourceJobPath is invalid.");
  }
  if (
    options.sourceJobPath &&
    options.sourceOperationId &&
    options.sourceJobPath.split("/")[3] !== options.sourceOperationId
  ) {
    throw new HttpsError(
      "invalid-argument",
      "sourceOperationId does not identify sourceJobPath."
    );
  }
  return ensureRun(db, {
    kind: "target_tenant",
    sourceKey: requireSourceKey(sourceKey),
    tenantId: normalizedTenantId,
    ...(options.sourceJobPath ? {sourceJobPath: options.sourceJobPath} : {}),
    ...(options.sourceOperationId ? {
      sourceOperationId: requireDocumentSegment(
        options.sourceOperationId,
        "sourceOperationId"
      ),
    } : {}),
  });
}

export async function createWeeklyFullRepair(
  db: Firestore,
  weeklyKey: string
): Promise<RepairTaskPayload> {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(weeklyKey)) {
    throw new HttpsError("invalid-argument", "weeklyKey must be an ISO local date.");
  }
  return ensureRun(db, {
    kind: "weekly_full",
    sourceKey: requireSourceKey(`weekly:${weeklyKey}`),
  });
}

async function claimRun(
  db: Firestore,
  payload: RepairTaskPayload
): Promise<ClaimedRepairRun | RepairTaskContinuation> {
  const ref = runRef(db, payload.runId);
  return db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (!snapshot.exists) {
      throw new HttpsError("not-found", "The membership repair run does not exist.");
    }
    const run = parseRun(payload.runId, snapshot.data() ?? {});
    if (run.status === "completed") return {tasks: []};
    if (payload.revision !== run.revision) {
      return {tasks: [{runId: payload.runId, revision: run.revision}]};
    }
    const now = Timestamp.now();
    if (
      run.status === "pending" &&
      run.nextAttemptAt &&
      run.nextAttemptAt.toMillis() > now.toMillis()
    ) {
      return {tasks: []};
    }
    if (
      run.status === "running" &&
      run.leaseExpiresAt &&
      run.leaseExpiresAt.toMillis() > now.toMillis()
    ) {
      return {tasks: []};
    }
    const leaseToken = randomUUID();
    const leaseExpiresAt = Timestamp.fromMillis(now.toMillis() + REPAIR_LEASE_MILLISECONDS);
    transaction.update(ref, {
      status: "running",
      leaseToken,
      leaseExpiresAt,
      nextAttemptAt: FieldValue.delete(),
      attemptCount: run.attemptCount + 1,
      lastErrorCode: FieldValue.delete(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return {
      ...run,
      runId: payload.runId,
      status: "running",
      attemptCount: run.attemptCount + 1,
      leaseToken,
      leaseExpiresAt,
    };
  });
}

function isContinuation(value: ClaimedRepairRun | RepairTaskContinuation):
  value is RepairTaskContinuation {
  return "tasks" in value;
}

function documentData<T>(snapshot: DocumentSnapshot<DocumentData>): T | undefined {
  return snapshot.exists ? snapshot.data() as T : undefined;
}

function isTimestamp(value: unknown): value is Timestamp {
  return value instanceof Timestamp;
}

function mirrorMetadataDrift(
  snapshot: DocumentSnapshot<DocumentData>,
  staff: StaffDocument | undefined
): boolean {
  if (!snapshot.exists) return false;
  const data = snapshot.data() ?? {};
  return !isTimestamp(data.createdAt) ||
    !Number.isSafeInteger(data.mirrorVersion) ||
    data.mirrorVersion < 0 ||
    (staff?.status === "active" && !isTimestamp(data.joinedAt));
}

type MirrorUpsertDecision = Exclude<MirrorRepairDecision, {action: "delete"}>;

/** Which write a mirror payload was built for, and the payload itself. */
export interface MirrorWrite {
  kind: "create" | "update";
  data: DocumentData;
}

/**
 * The mirror payload for a document that does not exist yet.
 *
 * It carries no `FieldValue.delete()`, and cannot: a mirror being created has no
 * stale `invitationStatus` to clear, and Firestore rejects a sentinel in
 * `create()` outright. That rejection is invisible until a real write is
 * serialized, so the guarantee has to be structural. One object shared between a
 * create branch and an update branch is exactly what made the sale
 * reconciliation trigger throw on every sale.
 */
function mirrorCreateData(
  decision: MirrorUpsertDecision,
  staff: StaffDocument
): DocumentData {
  return {
    ...decision.value,
    createdAt: isTimestamp(staff.createdAt) ?
      staff.createdAt : FieldValue.serverTimestamp(),
    joinedAt: decision.value.membershipStatus === "active" ?
      isTimestamp(staff.joinedAt) ? staff.joinedAt : FieldValue.serverTimestamp() :
      null,
    updatedAt: FieldValue.serverTimestamp(),
  };
}

/**
 * The mirror payload for a document that already exists.
 *
 * This is the branch a sentinel belongs in, and the only one: a mirror whose
 * canonical staff record has stopped carrying an invitation status has a stale
 * field to remove, and only an existing document can have one. Transport
 * metadata is rewritten only where the stored value is unusable, so an ordinary
 * repair leaves `createdAt` and `joinedAt` as they were.
 */
function mirrorUpdateData(
  decision: MirrorUpsertDecision,
  staff: StaffDocument,
  current: DocumentData
): DocumentData {
  return {
    ...decision.value,
    ...(decision.value.invitationStatus === undefined ?
      {invitationStatus: FieldValue.delete()} : {}),
    ...(isTimestamp(current.createdAt) ? {} : {
      createdAt: isTimestamp(staff.createdAt) ?
        staff.createdAt : FieldValue.serverTimestamp(),
    }),
    ...(decision.value.membershipStatus === "active" && !isTimestamp(current.joinedAt) ? {
      joinedAt: isTimestamp(staff.joinedAt) ?
        staff.joinedAt : FieldValue.serverTimestamp(),
    } : {}),
    updatedAt: FieldValue.serverTimestamp(),
  };
}

/**
 * The mirror payload and the write it is for, chosen by whether the mirror
 * exists. `current` is `undefined` when it does not.
 *
 * The two halves are built by separate expressions rather than one object with
 * conditional spreads so that "the create payload has no sentinel" is a property
 * of the code instead of a coincidence of two `exists` checks agreeing.
 */
export function mirrorWriteFields(
  decision: MirrorUpsertDecision,
  staff: StaffDocument,
  current: DocumentData | undefined
): MirrorWrite {
  return current === undefined ?
    {kind: "create", data: mirrorCreateData(decision, staff)} :
    {kind: "update", data: mirrorUpdateData(decision, staff, current)};
}

function applyMirrorDecision(
  batch: WriteBatch,
  mirrorSnapshot: DocumentSnapshot<DocumentData>,
  decision: MirrorRepairDecision,
  staff?: StaffDocument
): void {
  if (decision.action === "delete") {
    if (mirrorSnapshot.exists) {
      batch.delete(mirrorSnapshot.ref, {lastUpdateTime: mirrorSnapshot.updateTime as Timestamp});
    }
    return;
  }
  if (decision.action === "upsert") {
    if (!staff) throw new HttpsError("internal", "An upsert requires canonical staff data.");
    const write = mirrorWriteFields(
      decision,
      staff,
      mirrorSnapshot.exists ? mirrorSnapshot.data() ?? {} : undefined
    );
    if (write.kind === "update") {
      batch.update(
        mirrorSnapshot.ref,
        write.data,
        {lastUpdateTime: mirrorSnapshot.updateTime as Timestamp}
      );
    } else {
      batch.create(mirrorSnapshot.ref, write.data);
    }
  }
}

function progressData(
  run: ClaimedRepairRun,
  options: {
    phase: MembershipRepairPhase;
    cursor?: string;
    summary: MembershipRepairSummary;
    rootCounts?: RootRoutingCounts;
    completed?: boolean;
  }
): DocumentData {
  return {
    status: options.completed ? "completed" : "pending",
    phase: options.phase,
    revision: run.revision + 1,
    cursor: options.cursor ?? FieldValue.delete(),
    summary: options.summary,
    rootCounts: options.rootCounts ?? run.rootCounts,
    leaseToken: FieldValue.delete(),
    leaseExpiresAt: FieldValue.delete(),
    nextAttemptAt: options.completed ?
      FieldValue.delete() : FieldValue.serverTimestamp(),
    lastErrorCode: FieldValue.delete(),
    ...(options.completed ? {completedAt: FieldValue.serverTimestamp()} : {}),
    ...(options.completed ? {
      aggregateSummary: mergeRepairSummaries(options.summary, run.childSummary),
    } : {}),
    updatedAt: FieldValue.serverTimestamp(),
  };
}

function childCompletionUpdates(summary: MembershipRepairSummary): DocumentData {
  const updates: DocumentData = {
    childRunsCompleted: FieldValue.increment(1),
    updatedAt: FieldValue.serverTimestamp(),
  };
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
    updates[`childSummary.${key}`] = FieldValue.increment(summary[key]);
  }
  for (const [issue, count] of Object.entries(summary.issueCounts)) {
    updates[`childSummary.issueCounts.${issue}`] = FieldValue.increment(count);
  }
  return updates;
}

function nextTask(run: ClaimedRepairRun): RepairTaskPayload {
  return {runId: run.runId, revision: run.revision + 1};
}

function pageDocuments(
  documents: readonly QueryDocumentSnapshot<DocumentData>[],
  pageSize: number
): {documents: readonly QueryDocumentSnapshot<DocumentData>[]; hasMore: boolean} {
  return {documents: documents.slice(0, pageSize), hasMore: documents.length > pageSize};
}

function childRunInput(
  parent: ClaimedRepairRun,
  uid: string
): {runId: string; input: EnsureRunInput} {
  const sourceKey = `parent:${parent.runId}:user:${uid}`;
  return {
    runId: membershipRepairRunId("target_user", sourceKey),
    input: targetUserRepairInput(uid, sourceKey, parent.runId),
  };
}

async function addMissingChildRuns(
  db: Firestore,
  batch: WriteBatch,
  parent: ClaimedRepairRun,
  uids: readonly string[]
): Promise<{tasks: RepairTaskPayload[]; created: number}> {
  const children = [...new Set(uids)].sort().map((uid) => childRunInput(parent, uid));
  if (children.length === 0) return {tasks: [], created: 0};
  const refs = children.map(({runId}) => runRef(db, runId));
  const snapshots = await db.getAll(refs[0], ...refs.slice(1));
  const tasks: RepairTaskPayload[] = [];
  let created = 0;
  children.forEach((child, index) => {
    const snapshot = snapshots[index];
    if (!snapshot.exists) {
      batch.create(refs[index], initialRunData(child.input));
      tasks.push({runId: child.runId, revision: 0});
      created += 1;
      return;
    }
    const existing = parseRun(child.runId, snapshot.data() ?? {});
    if (!sameImmutableRun(existing, child.input)) {
      throw new HttpsError("data-loss", "A deterministic child repair run collided.");
    }
    if (existing.status !== "completed") {
      tasks.push({runId: child.runId, revision: existing.revision});
    }
  });
  return {tasks, created};
}

async function processUserCanonicalPage(
  db: Firestore,
  run: ClaimedRepairRun
): Promise<ProcessedPage> {
  const uid = requireDocumentSegment(run.targetUid, "targetUid");
  let query: Query<DocumentData> = db.collectionGroup("staff")
    .where("uid", "==", uid)
    .orderBy(FieldPath.documentId())
    .limit(USER_REPAIR_PAGE_SIZE + 1);
  if (run.cursor) {
    query = query.startAfter(db.doc(requireCollectionGroupCursor(run.cursor, "staff")));
  }
  const [snapshot, rootSnapshot] = await Promise.all([
    query.get(),
    db.collection("users").doc(uid).get(),
  ]);
  const page = pageDocuments(snapshot.docs, USER_REPAIR_PAGE_SIZE);
  const pageSummary = emptyRepairSummary();
  pageSummary.canonicalDocumentsScanned = page.documents.length;
  const canonicalDocuments = page.documents.flatMap((document) => {
    const location = parseCanonicalStaffPath(document.ref.path);
    if (!location || location.uid !== uid) {
      recordInvalidDocumentPath(pageSummary);
      return [];
    }
    return [{document, location}];
  });
  const references = canonicalDocuments.flatMap(({location}) => [
    db.collection("tenants").doc(location.tenantId),
    db.collection("users").doc(uid).collection("tenant_memberships").doc(location.tenantId),
  ]);
  const related = references.length > 0 ?
    await db.getAll(references[0], ...references.slice(1)) : [];
  const root = rootSnapshot.exists ? rootSnapshot.data() as RootUserRecord : null;
  let rootCounts = {...run.rootCounts};
  const batch = db.batch();

  canonicalDocuments.forEach(({document, location}, index) => {
    const tenantSnapshot = related[index * 2];
    const mirrorSnapshot = related[index * 2 + 1];
    const staff = document.data() as StaffDocument;
    const decision = planMembershipMirrorRepair({
      uid,
      tenantId: location.tenantId,
      root,
      tenant: documentData<TenantRecord>(tenantSnapshot),
      staff,
      mirror: documentData<Partial<TenantMembershipMirror>>(mirrorSnapshot),
      forceDrift: mirrorMetadataDrift(mirrorSnapshot, staff),
    });
    recordMirrorDecision(pageSummary, decision, mirrorSnapshot.exists);
    applyMirrorDecision(batch, mirrorSnapshot, decision, staff);
    rootCounts = addRootRoutingCounts(rootCounts, rootRoutingContribution(decision));
  });

  const summary = mergeRepairSummaries(run.summary, pageSummary);
  const cursor = page.hasMore && page.documents.length > 0 ?
    page.documents[page.documents.length - 1].ref.path : undefined;
  batch.update(runRef(db, run.runId), progressData(run, {
    phase: page.hasMore ? "canonical" : "mirrors",
    ...(cursor ? {cursor} : {}),
    summary,
    rootCounts,
  }));
  await batch.commit();
  return {continuation: {tasks: [nextTask(run)]}};
}

async function processUserMirrorPage(
  db: Firestore,
  run: ClaimedRepairRun
): Promise<ProcessedPage> {
  const uid = requireDocumentSegment(run.targetUid, "targetUid");
  const rootRef = db.collection("users").doc(uid);
  let query: Query<DocumentData> = rootRef.collection("tenant_memberships")
    .orderBy(FieldPath.documentId())
    .limit(USER_REPAIR_PAGE_SIZE + 1);
  if (run.cursor) {
    requireDocumentSegment(run.cursor, "mirror cursor");
    query = query.startAfter(run.cursor);
  }
  const [snapshot, rootSnapshot] = await Promise.all([query.get(), rootRef.get()]);
  const page = pageDocuments(snapshot.docs, USER_REPAIR_PAGE_SIZE);
  const references = page.documents.flatMap((document) => [
    db.collection("tenants").doc(document.id),
    db.collection("tenants").doc(document.id).collection("staff").doc(uid),
  ]);
  const related = references.length > 0 ?
    await db.getAll(references[0], ...references.slice(1)) : [];
  const root = rootSnapshot.exists ? rootSnapshot.data() as RootUserRecord : null;
  const pageSummary = emptyRepairSummary();
  pageSummary.mirrorDocumentsScanned = page.documents.length;
  const batch = db.batch();

  page.documents.forEach((mirrorSnapshot, index) => {
    const tenantSnapshot = related[index * 2];
    const staffSnapshot = related[index * 2 + 1];
    const staff = documentData<StaffDocument>(staffSnapshot);
    const decision = planMembershipMirrorRepair({
      uid,
      tenantId: mirrorSnapshot.id,
      root,
      tenant: documentData<TenantRecord>(tenantSnapshot),
      staff,
      mirror: mirrorSnapshot.data() as Partial<TenantMembershipMirror>,
      forceDrift: mirrorMetadataDrift(mirrorSnapshot, staff),
    });
    recordMirrorDecision(pageSummary, decision, true);
    applyMirrorDecision(batch, mirrorSnapshot, decision, staff);
  });

  const summary = mergeRepairSummaries(run.summary, pageSummary);
  const cursor = page.hasMore && page.documents.length > 0 ?
    page.documents[page.documents.length - 1].id : undefined;
  batch.update(runRef(db, run.runId), progressData(run, {
    phase: page.hasMore ? "mirrors" : "finalize",
    ...(cursor ? {cursor} : {}),
    summary,
  }));
  await batch.commit();
  return {continuation: {tasks: [nextTask(run)]}};
}

function isAccessibleDefault(decision: MirrorRepairDecision): boolean {
  return decision.action !== "delete" &&
    decision.value.membershipStatus === "active" &&
    decision.value.tenantStatus === "active";
}

async function processUserFinalize(
  db: Firestore,
  run: ClaimedRepairRun
): Promise<ProcessedPage> {
  const uid = requireDocumentSegment(run.targetUid, "targetUid");
  const rootRef = db.collection("users").doc(uid);
  const rootSnapshot = await rootRef.get();
  const root = documentData<RootUserRecord>(rootSnapshot);
  const rawRoot = rootSnapshot.exists ? rootSnapshot.data() ?? {} : {};
  let clearDefaultTenant = Object.prototype.hasOwnProperty.call(rawRoot, "defaultTenantId") &&
    typeof rawRoot.defaultTenantId !== "string";
  if (root && typeof root.defaultTenantId === "string" &&
    !isDocumentSegment(root.defaultTenantId)) {
    clearDefaultTenant = true;
  } else if (root && typeof root.defaultTenantId === "string") {
    const tenantRef = db.collection("tenants").doc(root.defaultTenantId);
    const [tenantSnapshot, staffSnapshot] = await db.getAll(
      tenantRef,
      tenantRef.collection("staff").doc(uid)
    );
    clearDefaultTenant = !isAccessibleDefault(planMembershipMirrorRepair({
      uid,
      tenantId: root.defaultTenantId,
      root,
      tenant: documentData<TenantRecord>(tenantSnapshot),
      staff: documentData<CanonicalStaffRecord>(staffSnapshot),
    }));
  }
  const countersChanged = rootSnapshot.exists && (
    rawRoot.membershipCount !== run.rootCounts.membershipCount ||
    rawRoot.ownedTenantCount !== run.rootCounts.ownedTenantCount ||
    rawRoot.ownedActiveTenantCount !== run.rootCounts.ownedActiveTenantCount
  );
  const pageSummary = emptyRepairSummary();
  const batch = db.batch();
  if (rootSnapshot.exists && (countersChanged || clearDefaultTenant)) {
    batch.update(
      rootRef,
      {
        ...run.rootCounts,
        ...(clearDefaultTenant ? {defaultTenantId: FieldValue.delete()} : {}),
        membershipRoutingRepairedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      {lastUpdateTime: rootSnapshot.updateTime as Timestamp}
    );
    pageSummary.rootDocumentsUpdated = 1;
    pageSummary.defaultTenantIdsCleared = clearDefaultTenant ? 1 : 0;
  }
  const summary = mergeRepairSummaries(run.summary, pageSummary);
  batch.update(runRef(db, run.runId), progressData(run, {
    phase: "finalize",
    summary,
    completed: true,
  }));
  if (run.parentRunId) {
    batch.update(runRef(db, run.parentRunId), childCompletionUpdates(summary));
  }
  await batch.commit();
  return {continuation: {tasks: []}};
}

async function processTenantCanonicalPage(
  db: Firestore,
  run: ClaimedRepairRun
): Promise<ProcessedPage> {
  const tenantId = requireDocumentSegment(run.tenantId, "tenantId");
  const tenantRef = db.collection("tenants").doc(tenantId);
  let query: Query<DocumentData> = tenantRef.collection("staff")
    .orderBy(FieldPath.documentId())
    .limit(TENANT_REPAIR_PAGE_SIZE + 1);
  if (run.cursor) {
    requireDocumentSegment(run.cursor, "staff cursor");
    query = query.startAfter(run.cursor);
  }
  const [snapshot, tenantSnapshot] = await Promise.all([query.get(), tenantRef.get()]);
  const page = pageDocuments(snapshot.docs, TENANT_REPAIR_PAGE_SIZE);
  const pageSummary = emptyRepairSummary();
  pageSummary.canonicalDocumentsScanned = page.documents.length;
  const canonicalDocuments = page.documents.flatMap((document) => {
    const location = parseCanonicalStaffPath(document.ref.path);
    if (!location || location.tenantId !== tenantId) {
      recordInvalidDocumentPath(pageSummary);
      return [];
    }
    return [{document, location}];
  });
  const references = canonicalDocuments.flatMap(({location}) => [
    db.collection("users").doc(location.uid),
    db.collection("users").doc(location.uid)
      .collection("tenant_memberships").doc(tenantId),
  ]);
  const related = references.length > 0 ?
    await db.getAll(references[0], ...references.slice(1)) : [];
  const tenant = documentData<TenantRecord>(tenantSnapshot);
  const batch = db.batch();
  const affectedUids: string[] = [];

  canonicalDocuments.forEach(({document, location}, index) => {
    const rootSnapshot = related[index * 2];
    const mirrorSnapshot = related[index * 2 + 1];
    const staff = document.data() as StaffDocument;
    const decision = planMembershipMirrorRepair({
      uid: location.uid,
      tenantId,
      root: rootSnapshot.exists ? rootSnapshot.data() as RootUserRecord : null,
      tenant,
      staff,
      mirror: documentData<Partial<TenantMembershipMirror>>(mirrorSnapshot),
      forceDrift: mirrorMetadataDrift(mirrorSnapshot, staff),
    });
    recordMirrorDecision(pageSummary, decision, mirrorSnapshot.exists);
    applyMirrorDecision(batch, mirrorSnapshot, decision, staff);
    affectedUids.push(location.uid);
  });

  const childRuns = await addMissingChildRuns(db, batch, run, affectedUids);
  pageSummary.childRunsQueued += childRuns.created;
  const summary = mergeRepairSummaries(run.summary, pageSummary);
  const cursor = page.hasMore && page.documents.length > 0 ?
    page.documents[page.documents.length - 1].id : undefined;
  batch.update(runRef(db, run.runId), progressData(run, {
    phase: page.hasMore ? "canonical" : "mirrors",
    ...(cursor ? {cursor} : {}),
    summary,
  }));
  await batch.commit();
  return {
    continuation: {tasks: [nextTask(run), ...childRuns.tasks]},
  };
}

async function processTenantMirrorPage(
  db: Firestore,
  run: ClaimedRepairRun
): Promise<ProcessedPage> {
  const tenantId = requireDocumentSegment(run.tenantId, "tenantId");
  const tenantRef = db.collection("tenants").doc(tenantId);
  let query: Query<DocumentData> = db.collectionGroup("tenant_memberships")
    .where("tenantId", "==", tenantId)
    .orderBy(FieldPath.documentId())
    .limit(TENANT_REPAIR_PAGE_SIZE + 1);
  if (run.cursor) {
    query = query.startAfter(db.doc(
      requireCollectionGroupCursor(run.cursor, "tenant_memberships")
    ));
  }
  const [snapshot, tenantSnapshot] = await Promise.all([query.get(), tenantRef.get()]);
  const page = pageDocuments(snapshot.docs, TENANT_REPAIR_PAGE_SIZE);
  const validDocuments = page.documents.flatMap((document) => {
    const location = parseMembershipMirrorPath(document.ref.path);
    return location ? [{document, location}] : [];
  });
  const references = validDocuments.flatMap(({location}) => [
    db.collection("users").doc(location.uid),
    tenantRef.collection("staff").doc(location.uid),
  ]);
  const related = references.length > 0 ?
    await db.getAll(references[0], ...references.slice(1)) : [];
  const tenant = documentData<TenantRecord>(tenantSnapshot);
  const pageSummary = emptyRepairSummary();
  pageSummary.mirrorDocumentsScanned = page.documents.length;
  const batch = db.batch();
  const affectedUids: string[] = [];
  let relatedIndex = 0;

  for (const mirrorSnapshot of page.documents) {
    const location = parseMembershipMirrorPath(mirrorSnapshot.ref.path);
    if (!location) {
      recordInvalidDocumentPath(pageSummary);
      continue;
    }
    const rootSnapshot = related[relatedIndex * 2];
    const staffSnapshot = related[relatedIndex * 2 + 1];
    relatedIndex += 1;
    affectedUids.push(location.uid);
    if (location.tenantId !== tenantId) {
      const decision: MirrorRepairDecision = {
        action: "delete",
        tenantId: location.tenantId,
        issues: ["mirror_drift"],
      };
      recordMirrorDecision(pageSummary, decision, true);
      batch.delete(
        mirrorSnapshot.ref,
        {lastUpdateTime: mirrorSnapshot.updateTime as Timestamp}
      );
      continue;
    }
    const staff = documentData<StaffDocument>(staffSnapshot);
    const decision = planMembershipMirrorRepair({
      uid: location.uid,
      tenantId,
      root: rootSnapshot.exists ? rootSnapshot.data() as RootUserRecord : null,
      tenant,
      staff,
      mirror: mirrorSnapshot.data() as Partial<TenantMembershipMirror>,
      forceDrift: mirrorMetadataDrift(mirrorSnapshot, staff),
    });
    recordMirrorDecision(pageSummary, decision, true);
    applyMirrorDecision(batch, mirrorSnapshot, decision, staff);
  }

  const childRuns = await addMissingChildRuns(db, batch, run, affectedUids);
  pageSummary.childRunsQueued += childRuns.created;
  const summary = mergeRepairSummaries(run.summary, pageSummary);
  const cursor = page.hasMore && page.documents.length > 0 ?
    page.documents[page.documents.length - 1].ref.path : undefined;
  batch.update(runRef(db, run.runId), progressData(run, {
    phase: page.hasMore ? "mirrors" : "finalize",
    ...(cursor ? {cursor} : {}),
    summary,
  }));
  await batch.commit();
  return {
    continuation: {tasks: [nextTask(run), ...childRuns.tasks]},
  };
}

function validFanoutJobPath(path: string, tenantId: string): boolean {
  const segments = path.split("/");
  return segments.length === 4 &&
    segments[0] === "tenants" &&
    segments[1] === tenantId &&
    segments[2] === "membership_fanout_jobs" &&
    segments[3].length > 0;
}

async function processTenantFinalize(
  db: Firestore,
  run: ClaimedRepairRun
): Promise<ProcessedPage> {
  const tenantId = requireDocumentSegment(run.tenantId, "tenantId");
  const tenantRef = db.collection("tenants").doc(tenantId);
  const tenantSnapshot = await tenantRef.get();
  if (run.childRunsCompleted < run.summary.childRunsQueued) {
    await runRef(db, run.runId).update(progressData(run, {
      phase: "finalize",
      summary: run.summary,
    }));
    return {continuation: {tasks: []}};
  }
  const batch = db.batch();
  if (run.sourceJobPath) {
    if (!validFanoutJobPath(run.sourceJobPath, tenantId)) {
      throw new HttpsError("data-loss", "The lifecycle fan-out job path is invalid.");
    }
    batch.set(db.doc(run.sourceJobPath), {
      status: "completed",
      repairRunId: run.runId,
      repairSummary: mergeRepairSummaries(run.summary, run.childSummary),
      completedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  }
  const tenant = tenantSnapshot.exists ? tenantSnapshot.data() ?? {} : {};
  if (
    run.sourceOperationId &&
    tenant.membershipFanoutOperationId === run.sourceOperationId
  ) {
    batch.update(tenantRef, {
      membershipFanoutStatus: "completed",
      membershipFanoutRepairRunId: run.runId,
      membershipFanoutUpdatedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  }
  batch.update(runRef(db, run.runId), progressData(run, {
    phase: "finalize",
    summary: run.summary,
    completed: true,
  }));
  await batch.commit();
  return {continuation: {tasks: []}};
}

async function processWeeklyUserDiscoveryPage(
  db: Firestore,
  run: ClaimedRepairRun
): Promise<ProcessedPage> {
  let query: Query<DocumentData> = db.collection("users")
    .orderBy(FieldPath.documentId())
    .limit(FULL_REPAIR_DISCOVERY_PAGE_SIZE + 1);
  if (run.cursor) {
    requireDocumentSegment(run.cursor, "user discovery cursor");
    query = query.startAfter(run.cursor);
  }
  const snapshot = await query.get();
  const page = pageDocuments(snapshot.docs, FULL_REPAIR_DISCOVERY_PAGE_SIZE);
  const uids = page.documents.map((document) => document.id);
  const batch = db.batch();
  const childRuns = await addMissingChildRuns(db, batch, run, uids);
  const pageSummary = emptyRepairSummary();
  pageSummary.usersDiscovered = uids.length;
  pageSummary.childRunsQueued = childRuns.created;
  const summary = mergeRepairSummaries(run.summary, pageSummary);
  const cursor = page.hasMore && page.documents.length > 0 ?
    page.documents[page.documents.length - 1].id : undefined;
  batch.update(runRef(db, run.runId), progressData(run, {
    phase: page.hasMore ? "users" : "mirrors",
    ...(cursor ? {cursor} : {}),
    summary,
  }));
  await batch.commit();
  return {
    continuation: {tasks: [nextTask(run), ...childRuns.tasks]},
  };
}

async function processWeeklyMirrorDiscoveryPage(
  db: Firestore,
  run: ClaimedRepairRun
): Promise<ProcessedPage> {
  let query: Query<DocumentData> = db.collectionGroup("tenant_memberships")
    .orderBy(FieldPath.documentId())
    .limit(FULL_REPAIR_DISCOVERY_PAGE_SIZE + 1);
  if (run.cursor) {
    query = query.startAfter(db.doc(
      requireCollectionGroupCursor(run.cursor, "tenant_memberships")
    ));
  }
  const snapshot = await query.get();
  const page = pageDocuments(snapshot.docs, FULL_REPAIR_DISCOVERY_PAGE_SIZE);
  const pageSummary = emptyRepairSummary();
  pageSummary.mirrorDocumentsScanned = page.documents.length;
  const uids: string[] = [];
  for (const document of page.documents) {
    const location = parseMembershipMirrorPath(document.ref.path);
    if (location) uids.push(location.uid);
    else recordInvalidDocumentPath(pageSummary);
  }
  const batch = db.batch();
  const childRuns = await addMissingChildRuns(db, batch, run, uids);
  pageSummary.childRunsQueued = childRuns.created;
  const summary = mergeRepairSummaries(run.summary, pageSummary);
  const cursor = page.hasMore && page.documents.length > 0 ?
    page.documents[page.documents.length - 1].ref.path : undefined;
  batch.update(runRef(db, run.runId), progressData(run, {
    phase: page.hasMore ? "mirrors" : "finalize",
    ...(cursor ? {cursor} : {}),
    summary,
  }));
  await batch.commit();
  return {
    continuation: {tasks: [nextTask(run), ...childRuns.tasks]},
  };
}

async function processWeeklyFinalize(
  db: Firestore,
  run: ClaimedRepairRun
): Promise<ProcessedPage> {
  if (run.childRunsCompleted < run.summary.childRunsQueued) {
    await runRef(db, run.runId).update(progressData(run, {
      phase: "finalize",
      summary: run.summary,
    }));
    return {continuation: {tasks: []}};
  }
  await runRef(db, run.runId).update(progressData(run, {
    phase: "finalize",
    summary: run.summary,
    completed: true,
  }));
  return {continuation: {tasks: []}};
}

async function processClaimedRun(
  db: Firestore,
  run: ClaimedRepairRun
): Promise<ProcessedPage> {
  if (run.kind === "target_user") {
    if (run.phase === "canonical") return processUserCanonicalPage(db, run);
    if (run.phase === "mirrors") return processUserMirrorPage(db, run);
    if (run.phase === "finalize") return processUserFinalize(db, run);
  }
  if (run.kind === "target_tenant") {
    if (run.phase === "canonical") return processTenantCanonicalPage(db, run);
    if (run.phase === "mirrors") return processTenantMirrorPage(db, run);
    if (run.phase === "finalize") return processTenantFinalize(db, run);
  }
  if (run.kind === "weekly_full") {
    if (run.phase === "users") return processWeeklyUserDiscoveryPage(db, run);
    if (run.phase === "mirrors") return processWeeklyMirrorDiscoveryPage(db, run);
    if (run.phase === "finalize") return processWeeklyFinalize(db, run);
  }
  throw new HttpsError(
    "data-loss",
    `Repair run ${run.runId} has an impossible kind/phase combination.`
  );
}

/** Claims and atomically advances one bounded page of a durable repair run. */
export async function processMembershipRepairPage(
  db: Firestore,
  payload: RepairTaskPayload
): Promise<RepairTaskContinuation> {
  const claimed = await claimRun(db, payload);
  if (isContinuation(claimed)) return claimed;
  return (await processClaimedRun(db, claimed)).continuation;
}

/** Releases only the failed revision; a newer successful page is never rewound. */
export async function recordMembershipRepairFailure(
  db: Firestore,
  payload: RepairTaskPayload,
  error: unknown
): Promise<void> {
  const ref = runRef(db, payload.runId);
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (!snapshot.exists) return;
    const run = parseRun(payload.runId, snapshot.data() ?? {});
    if (run.status === "completed" || run.revision !== payload.revision) return;
    transaction.update(ref, {
      status: "pending",
      leaseToken: FieldValue.delete(),
      leaseExpiresAt: FieldValue.delete(),
      lastErrorCode: safeRepairErrorCode(error),
      nextAttemptAt: Timestamp.fromMillis(
        Date.now() + membershipRepairRetryDelayMilliseconds(run.attemptCount)
      ),
      lastFailedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
}

export function membershipRepairRetryDelayMilliseconds(attemptCount: number): number {
  const normalized = Number.isSafeInteger(attemptCount) && attemptCount > 0 ?
    attemptCount : 1;
  return Math.min(6 * 60 * 60 * 1000, 30_000 * (2 ** Math.min(normalized - 1, 10)));
}

/** Returns a bounded set of pending or expired jobs for the retry scheduler. */
export async function listResumableMembershipRepairs(
  db: Firestore,
  limit = 100
): Promise<RepairTaskPayload[]> {
  const boundedLimit = Math.max(1, Math.min(100, Math.trunc(limit)));
  const now = Timestamp.now();
  const [pending, expired] = await Promise.all([
    db.collection(RUN_COLLECTION)
      .where("status", "==", "pending")
      .where("nextAttemptAt", "<=", now)
      .orderBy("nextAttemptAt", "asc")
      .orderBy(FieldPath.documentId(), "asc")
      .limit(boundedLimit)
      .get(),
    db.collection(RUN_COLLECTION)
      .where("status", "==", "running")
      .where("leaseExpiresAt", "<=", now)
      .orderBy("leaseExpiresAt", "asc")
      .orderBy(FieldPath.documentId(), "asc")
      .limit(boundedLimit)
      .get(),
  ]);
  return [...pending.docs, ...expired.docs]
    .slice(0, boundedLimit)
    .map((document) => {
      const run = parseRun(document.id, document.data());
      return {runId: document.id, revision: run.revision};
    });
}
