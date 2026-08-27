import {FieldValue, Firestore, Transaction} from "firebase-admin/firestore";
import {
  CanonicalStaffRecord,
  RootUserRecord,
  TenantStatus,
} from "../core/model";
import {staffSearchFields} from "../staff/search";

const DOCUMENT_ID_PATTERN = /^[^/]{1,128}$/;
const RECOVERABLE_CASE_STATUSES = new Set(["open", "approved"]);
const KNOWN_TENANT_STATUSES = new Set<TenantStatus>([
  "pending",
  "active",
  "suspended",
  "rejected",
  "archived",
]);

export type OwnerRecoveryMode = "normal" | "exceptional";

export type OwnerRecoveryErrorCode =
  | "invalid-input"
  | "operator-ineligible"
  | "replacement-ineligible"
  | "tenant-ineligible"
  | "owner-invariant-invalid"
  | "normal-replacement-ineligible"
  | "exceptional-replacement-ineligible"
  | "recovery-case-invalid"
  | "confirmation-mismatch"
  | "operation-conflict";

export class OwnerRecoveryError extends Error {
  constructor(readonly code: OwnerRecoveryErrorCode, message: string) {
    super(message);
    this.name = "OwnerRecoveryError";
  }
}

export interface OwnerRecoveryConfirmations {
  tenantSlug: string;
  oldOwnerUid: string;
  replacementUid: string;
  secondConfirmation: boolean;
}

export interface OwnerRecoveryInput {
  tenantId: string;
  replacementUid: string;
  operatorUid: string;
  operationId: string;
  mode: OwnerRecoveryMode;
  reason: string;
  caseId?: string;
  supportReference?: string;
  confirmations?: OwnerRecoveryConfirmations;
  dryRun?: boolean;
}

export interface RecoveryAuthUser {
  uid: string;
  email?: string;
  displayName?: string;
  disabled?: boolean;
  emailVerified?: boolean;
  customClaims?: Readonly<Record<string, unknown>>;
}

export interface OwnerRecoveryAuthClient {
  getUser(uid: string): Promise<RecoveryAuthUser>;
}

export interface RecoveryDocument {
  path: string;
  id: string;
  exists: boolean;
  data?: Readonly<Record<string, unknown>>;
}

export interface OwnerRecoveryTransaction {
  get(path: string): Promise<RecoveryDocument>;
  queryTenantOwnerStaff(tenantId: string): Promise<readonly RecoveryDocument[]>;
  queryOwnedTenants(uid: string): Promise<readonly RecoveryDocument[]>;
  queryStaffMemberships(uid: string): Promise<readonly RecoveryDocument[]>;
  create(path: string, data: Readonly<Record<string, unknown>>): void;
  update(path: string, data: Readonly<Record<string, unknown>>): void;
  set(path: string, data: Readonly<Record<string, unknown>>, merge: boolean): void;
}

export interface OwnerRecoveryStore {
  runTransaction<T>(
    handler: (transaction: OwnerRecoveryTransaction) => Promise<T>
  ): Promise<T>;
}

export interface OwnerRecoveryDependencies {
  store: OwnerRecoveryStore;
  auth: OwnerRecoveryAuthClient;
  serverTimestamp?: () => unknown;
}

export type OwnerRecoveryMutation =
  | {
    kind: "create";
    path: string;
    data: Readonly<Record<string, unknown>>;
  }
  | {
    kind: "update";
    path: string;
    data: Readonly<Record<string, unknown>>;
  }
  | {
    kind: "set";
    path: string;
    data: Readonly<Record<string, unknown>>;
    merge: boolean;
  };

export interface OwnerRecoveryPlan {
  tenantId: string;
  tenantSlug: string;
  oldOwnerUid: string;
  replacementUid: string;
  mode: OwnerRecoveryMode;
  mutations: readonly OwnerRecoveryMutation[];
  ownerUidsAfter: readonly string[];
}

export interface OwnerRecoveryResult {
  tenantId: string;
  tenantSlug: string;
  oldOwnerUid: string;
  replacementUid: string;
  mode: OwnerRecoveryMode;
  operationId: string;
  dryRun: boolean;
  alreadyCompleted: boolean;
  plannedWriteCount: number;
}

export interface OwnerRecoveryState {
  tenant: RecoveryDocument;
  operatorUser: RecoveryDocument;
  oldOwnerUser: RecoveryDocument;
  replacementUser: RecoveryDocument;
  oldOwnerStaff: RecoveryDocument;
  replacementStaff: RecoveryDocument;
  oldOwnerMirror: RecoveryDocument;
  replacementMirror: RecoveryDocument;
  tenantOwnerStaff: readonly RecoveryDocument[];
  oldOwnerOwnedTenants: readonly RecoveryDocument[];
  replacementOwnedTenants: readonly RecoveryDocument[];
  oldOwnerMemberships: readonly RecoveryDocument[];
  replacementMemberships: readonly RecoveryDocument[];
  replacementAuth: RecoveryAuthUser;
  recoveryCase?: RecoveryDocument;
}

function invalid(code: OwnerRecoveryErrorCode, message: string): never {
  throw new OwnerRecoveryError(code, message);
}

function requireDocumentId(value: string, label: string): string {
  const normalized = value.trim();
  if (!DOCUMENT_ID_PATTERN.test(normalized) || normalized === "." || normalized === "..") {
    return invalid("invalid-input", `${label} has an invalid format.`);
  }
  return normalized;
}

function requireText(value: string | undefined, label: string, maximum: number): string {
  if (typeof value !== "string") {
    return invalid("invalid-input", `${label} is required.`);
  }
  const normalized = value.trim();
  if (normalized.length === 0 || normalized.length > maximum) {
    return invalid(
      "invalid-input",
      `${label} must be between 1 and ${maximum} characters.`
    );
  }
  return normalized;
}

function existingData(
  document: RecoveryDocument,
  label: string,
  code: OwnerRecoveryErrorCode
): Readonly<Record<string, unknown>> {
  if (!document.exists || !document.data) {
    return invalid(code, `${label} does not exist.`);
  }
  return document.data;
}

function stringField(
  data: Readonly<Record<string, unknown>>,
  field: string,
  label: string,
  code: OwnerRecoveryErrorCode
): string {
  const value = data[field];
  if (typeof value !== "string" || value.trim().length === 0) {
    return invalid(code, `${label}.${field} is missing or invalid.`);
  }
  return value.trim();
}

function tenantStatus(
  data: Readonly<Record<string, unknown>>,
  label: string,
  code: OwnerRecoveryErrorCode
): TenantStatus {
  const status = data.status;
  if (typeof status !== "string" || !KNOWN_TENANT_STATUSES.has(status as TenantStatus)) {
    return invalid(code, `${label}.status is unknown.`);
  }
  return status as TenantStatus;
}

function nextMirrorVersion(document: RecoveryDocument): number {
  const value = document.data?.mirrorVersion;
  return Number.isSafeInteger(value) && (value as number) >= 0 ? (value as number) + 1 : 1;
}

function assertCanonicalMembershipQuery(
  documents: readonly RecoveryDocument[],
  uid: string,
  label: string
): void {
  const seen = new Set<string>();
  for (const document of documents) {
    const data = existingData(document, label, "owner-invariant-invalid");
    if (document.id !== uid || data.uid !== uid || seen.has(document.path)) {
      invalid(
        "owner-invariant-invalid",
        `${label} returned malformed or duplicate canonical membership evidence.`
      );
    }
    seen.add(document.path);
  }
}

function countOwnedTenants(
  documents: readonly RecoveryDocument[],
  uid: string,
  label: string
): {total: number; active: number; paths: ReadonlySet<string>} {
  const paths = new Set<string>();
  let total = 0;
  let active = 0;
  for (const document of documents) {
    const data = existingData(document, label, "owner-invariant-invalid");
    if (data.ownerUid !== uid || paths.has(document.path)) {
      invalid(
        "owner-invariant-invalid",
        `${label} returned malformed or duplicate canonical ownership evidence.`
      );
    }
    const status = tenantStatus(data, label, "owner-invariant-invalid");
    if (status !== "archived") total += 1;
    if (status === "active") active += 1;
    paths.add(document.path);
  }
  return {total, active, paths};
}

function rootUser(
  document: RecoveryDocument,
  label: string,
  code: OwnerRecoveryErrorCode
): RootUserRecord {
  return existingData(document, label, code) as RootUserRecord;
}

function staffRecord(
  document: RecoveryDocument,
  label: string,
  code: OwnerRecoveryErrorCode
): CanonicalStaffRecord {
  return existingData(document, label, code) as CanonicalStaffRecord;
}

function assertOperatorRoot(document: RecoveryDocument): void {
  const user = rootUser(document, "operator root user", "operator-ineligible");
  if (
    user.accountType !== "platform_admin" ||
    user.globalStatus !== "active" ||
    user.identityTransition !== undefined
  ) {
    invalid(
      "operator-ineligible",
      "The operator must have an active, transition-free canonical platform account."
    );
  }
}

function assertTenantUserRoot(
  document: RecoveryDocument,
  label: string,
  requireActive: boolean
): RootUserRecord {
  const user = rootUser(document, label, "replacement-ineligible");
  if (
    user.accountType !== "tenant_user" ||
    user.identityTransition !== undefined ||
    (requireActive && user.globalStatus !== "active")
  ) {
    invalid(
      "replacement-ineligible",
      `${label} must be a transition-free${requireActive ? ", globally active" : ""} tenant user.`
    );
  }
  return user;
}

export function assertRecoveryAuthIdentities(
  input: OwnerRecoveryInput,
  operator: RecoveryAuthUser,
  replacement: RecoveryAuthUser
): void {
  if (
    operator.uid !== input.operatorUid ||
    operator.disabled === true ||
    operator.customClaims?.platformRole !== "superAdmin"
  ) {
    invalid(
      "operator-ineligible",
      "The operator Auth identity must be enabled and carry platformRole=superAdmin."
    );
  }
  if (
    replacement.uid !== input.replacementUid ||
    replacement.disabled === true ||
    replacement.customClaims?.platformRole === "superAdmin"
  ) {
    invalid(
      "replacement-ineligible",
      "The replacement Auth identity must be enabled and must not be a platform identity."
    );
  }
  if (input.mode === "exceptional" && replacement.emailVerified !== true) {
    invalid(
      "replacement-ineligible",
      "Exceptional recovery requires a verified replacement Auth identity."
    );
  }
  if (
    input.mode === "exceptional" &&
    (typeof replacement.email !== "string" || replacement.email.trim().length === 0)
  ) {
    invalid(
      "replacement-ineligible",
      "Exceptional recovery requires an Auth identity with a verified email address."
    );
  }
}

function assertExceptionalControls(
  input: OwnerRecoveryInput,
  tenantSlug: string,
  oldOwnerUid: string,
  recoveryCase: RecoveryDocument | undefined
): {caseId: string; supportReference: string} {
  const caseId = requireDocumentId(input.caseId ?? "", "caseId");
  const supportReference = requireText(input.supportReference, "supportReference", 512);
  const confirmations = input.confirmations;
  if (
    !confirmations ||
    confirmations.tenantSlug.trim() !== tenantSlug ||
    confirmations.oldOwnerUid.trim() !== oldOwnerUid ||
    confirmations.replacementUid.trim() !== input.replacementUid ||
    confirmations.secondConfirmation !== true
  ) {
    invalid(
      "confirmation-mismatch",
      "Exceptional recovery confirmations do not exactly match the canonical tenant and UIDs."
    );
  }

  if (!recoveryCase || recoveryCase.id !== caseId) {
    invalid("recovery-case-invalid", "The exceptional recovery case was not loaded.");
  }
  const data = existingData(recoveryCase, "owner recovery case", "recovery-case-invalid");
  if (
    data.tenantId !== input.tenantId ||
    data.oldOwnerUid !== oldOwnerUid ||
    data.replacementUid !== input.replacementUid ||
    data.supportReference !== supportReference ||
    typeof data.status !== "string" ||
    !RECOVERABLE_CASE_STATUSES.has(data.status)
  ) {
    invalid(
      "recovery-case-invalid",
      "The recovery case is consumed, incomplete, or does not match this exact recovery."
    );
  }
  return {caseId, supportReference};
}

function mirrorData(
  tenantId: string,
  tenantName: string,
  tenantSlug: string,
  tenantStatusValue: TenantStatus,
  role: "owner" | "admin",
  membershipStatus: "active" | "inactive",
  mirror: RecoveryDocument,
  timestamp: unknown
): Readonly<Record<string, unknown>> {
  return {
    tenantId,
    tenantName,
    tenantSlug,
    role,
    membershipStatus,
    tenantStatus: tenantStatusValue,
    invitationStatus: "accepted",
    isOwner: role === "owner",
    mirrorVersion: nextMirrorVersion(mirror),
    ...(!mirror.exists ? {createdAt: timestamp} : {}),
    ...(membershipStatus === "active" && !mirror.data?.joinedAt ? {joinedAt: timestamp} : {}),
    updatedAt: timestamp,
  };
}

/**
 * Builds the complete transaction mutation set from canonical evidence.
 * Mirrors and counters are outputs of this plan and never authorize it.
 */
export function buildOwnerRecoveryPlan(
  input: OwnerRecoveryInput,
  state: OwnerRecoveryState,
  timestamp: unknown
): OwnerRecoveryPlan {
  const tenantId = requireDocumentId(input.tenantId, "tenantId");
  const replacementUid = requireDocumentId(input.replacementUid, "replacementUid");
  const operatorUid = requireDocumentId(input.operatorUid, "operatorUid");
  const operationId = requireDocumentId(input.operationId, "operationId");
  const reason = requireText(input.reason, "reason", 1000);
  if (replacementUid === operatorUid) {
    invalid("replacement-ineligible", "A platform operator cannot be the replacement owner.");
  }

  assertOperatorRoot(state.operatorUser);
  const tenant = existingData(state.tenant, "tenant", "tenant-ineligible");
  const tenantName = stringField(tenant, "name", "tenant", "tenant-ineligible");
  const tenantSlug = stringField(tenant, "slug", "tenant", "tenant-ineligible");
  const tenantStatusValue = tenantStatus(tenant, "tenant", "tenant-ineligible");
  if (tenantStatusValue === "archived") {
    invalid("tenant-ineligible", "Archived tenants cannot undergo owner recovery.");
  }
  const oldOwnerUid = requireDocumentId(
    stringField(tenant, "ownerUid", "tenant", "owner-invariant-invalid"),
    "tenant.ownerUid"
  );
  if (oldOwnerUid === replacementUid) {
    invalid("replacement-ineligible", "The replacement is already the canonical tenant owner.");
  }

  const oldOwner = staffRecord(
    state.oldOwnerStaff,
    "old owner staff",
    "owner-invariant-invalid"
  );
  const oldOwnerRoot = rootUser(
    state.oldOwnerUser,
    "old owner root user",
    "owner-invariant-invalid"
  );
  if (
    oldOwner.uid !== oldOwnerUid ||
    state.oldOwnerStaff.id !== oldOwnerUid ||
    oldOwner.role !== "owner" ||
    oldOwnerRoot.accountType !== "tenant_user" ||
    oldOwnerRoot.identityTransition !== undefined
  ) {
    invalid(
      "owner-invariant-invalid",
      "The current owner staff and root records do not satisfy the canonical owner invariant."
    );
  }

  if (state.tenantOwnerStaff.length !== 1) {
    invalid(
      "owner-invariant-invalid",
      "Recovery requires exactly one canonical owner before mutation."
    );
  }
  const queriedOwner = staffRecord(
    state.tenantOwnerStaff[0],
    "queried owner staff",
    "owner-invariant-invalid"
  );
  if (
    state.tenantOwnerStaff[0].path !== state.oldOwnerStaff.path ||
    state.tenantOwnerStaff[0].id !== oldOwnerUid ||
    queriedOwner.uid !== oldOwnerUid ||
    queriedOwner.role !== "owner"
  ) {
    invalid(
      "owner-invariant-invalid",
      "Tenant.ownerUid and the unique canonical owner staff record disagree."
    );
  }

  const replacementRoot = assertTenantUserRoot(
    state.replacementUser,
    "replacement root user",
    true
  );
  if (input.mode === "normal") {
    const replacementStaff = staffRecord(
      state.replacementStaff,
      "replacement staff",
      "normal-replacement-ineligible"
    );
    if (
      replacementStaff.uid !== replacementUid ||
      state.replacementStaff.id !== replacementUid ||
      replacementStaff.role !== "admin" ||
      replacementStaff.status !== "active"
    ) {
      invalid(
        "normal-replacement-ineligible",
        "Normal recovery requires the replacement to be a canonical active admin."
      );
    }
  } else if (state.replacementStaff.exists) {
    invalid(
      "exceptional-replacement-ineligible",
      "Exceptional recovery creates a new canonical membership; an existing membership must use a separately reviewed migration path."
    );
  }

  const exceptional = input.mode === "exceptional" ?
    assertExceptionalControls(input, tenantSlug, oldOwnerUid, state.recoveryCase) :
    undefined;

  assertCanonicalMembershipQuery(
    state.oldOwnerMemberships,
    oldOwnerUid,
    "old owner membership scan"
  );
  assertCanonicalMembershipQuery(
    state.replacementMemberships,
    replacementUid,
    "replacement membership scan"
  );
  if (!state.oldOwnerMemberships.some((document) => document.path === state.oldOwnerStaff.path)) {
    invalid("owner-invariant-invalid", "The old owner canonical membership scan is incomplete.");
  }
  const replacementMembershipPresent = state.replacementMemberships.some(
    (document) => document.path === state.replacementStaff.path
  );
  if (
    (input.mode === "normal" && !replacementMembershipPresent) ||
    (input.mode === "exceptional" && replacementMembershipPresent)
  ) {
    invalid(
      "owner-invariant-invalid",
      "The replacement canonical membership scan disagrees with the direct membership read."
    );
  }

  const oldOwned = countOwnedTenants(
    state.oldOwnerOwnedTenants,
    oldOwnerUid,
    "old owner tenant scan"
  );
  const replacementOwned = countOwnedTenants(
    state.replacementOwnedTenants,
    replacementUid,
    "replacement owner tenant scan"
  );
  if (!oldOwned.paths.has(state.tenant.path) || replacementOwned.paths.has(state.tenant.path)) {
    invalid(
      "owner-invariant-invalid",
      "Canonical ownership scans disagree with the tenant being recovered."
    );
  }

  const activeTenantDelta = tenantStatusValue === "active" ? 1 : 0;
  const oldOwnedAfter = {
    total: oldOwned.total - 1,
    active: oldOwned.active - activeTenantDelta,
  };
  const replacementOwnedAfter = {
    total: replacementOwned.total + 1,
    active: replacementOwned.active + activeTenantDelta,
  };
  if (oldOwnedAfter.total < 0 || oldOwnedAfter.active < 0) {
    invalid("owner-invariant-invalid", "Canonical owner counts would become negative.");
  }

  const auditBase = {
    tenantId,
    tenantSlug,
    eventType: "owner_recovered",
    recoveryMode: input.mode,
    oldOwnerUid,
    replacementUid,
    actorUid: operatorUid,
    operationId,
    reason,
    ...(exceptional ? {
      recoveryCaseId: exceptional.caseId,
      supportReference: exceptional.supportReference,
    } : {}),
  };
  const tenantRoot = `tenants/${tenantId}`;
  const oldStaffPath = `${tenantRoot}/staff/${oldOwnerUid}`;
  const replacementStaffPath = `${tenantRoot}/staff/${replacementUid}`;
  const oldMirrorPath = `users/${oldOwnerUid}/tenant_memberships/${tenantId}`;
  const replacementMirrorPath = `users/${replacementUid}/tenant_memberships/${tenantId}`;
  const mutations: OwnerRecoveryMutation[] = [
    {
      kind: "update",
      path: tenantRoot,
      data: {ownerUid: replacementUid, updatedAt: timestamp},
    },
    {
      kind: "update",
      path: oldStaffPath,
      data: {
        role: "admin",
        status: "inactive",
        invitationStatus: "accepted",
        updatedAt: timestamp,
      },
    },
    input.mode === "exceptional" ? {
      kind: "create",
      path: replacementStaffPath,
      data: {
        uid: replacementUid,
        email: state.replacementAuth.email?.trim().toLowerCase() ?? "",
        name: state.replacementAuth.displayName?.trim() ?? replacementRoot.displayName ?? "",
        phone: "",
        role: "owner",
        status: "active",
        invitationStatus: "accepted",
        ...staffSearchFields(
          state.replacementAuth.displayName?.trim() ?? replacementRoot.displayName ?? "",
          state.replacementAuth.email?.trim().toLowerCase() ?? ""
        ),
        createdAt: timestamp,
        joinedAt: timestamp,
        updatedAt: timestamp,
      },
    } : {
      kind: "update",
      path: replacementStaffPath,
      data: {
        uid: replacementUid,
        role: "owner",
        status: "active",
        invitationStatus: "accepted",
        updatedAt: timestamp,
      },
    },
    {
      kind: "set",
      path: oldMirrorPath,
      merge: true,
      data: mirrorData(
        tenantId,
        tenantName,
        tenantSlug,
        tenantStatusValue,
        "admin",
        "inactive",
        state.oldOwnerMirror,
        timestamp
      ),
    },
    {
      kind: "set",
      path: replacementMirrorPath,
      merge: true,
      data: mirrorData(
        tenantId,
        tenantName,
        tenantSlug,
        tenantStatusValue,
        "owner",
        "active",
        state.replacementMirror,
        timestamp
      ),
    },
    {
      kind: "update",
      path: `users/${oldOwnerUid}`,
      data: {
        membershipCount: state.oldOwnerMemberships.length,
        ownedTenantCount: oldOwnedAfter.total,
        ownedActiveTenantCount: oldOwnedAfter.active,
        updatedAt: timestamp,
      },
    },
    {
      kind: "update",
      path: `users/${replacementUid}`,
      data: {
        membershipCount: state.replacementMemberships.length +
          (input.mode === "exceptional" ? 1 : 0),
        ownedTenantCount: replacementOwnedAfter.total,
        ownedActiveTenantCount: replacementOwnedAfter.active,
        updatedAt: timestamp,
      },
    },
    {
      kind: "create",
      path: `${tenantRoot}/lifecycle_history/${operationId}`,
      data: {...auditBase, createdAt: timestamp},
    },
    {
      kind: "create",
      path: `${tenantRoot}/audit_logs/${operationId}`,
      data: {...auditBase, createdAt: timestamp},
    },
    {
      kind: "create",
      path: `platform_audit_logs/${operationId}`,
      data: {...auditBase, status: "completed", createdAt: timestamp, completedAt: timestamp},
    },
  ];

  if (exceptional) {
    mutations.push({
      kind: "update",
      path: `owner_recovery_cases/${exceptional.caseId}`,
      data: {
        status: "completed",
        completedBy: operatorUid,
        completedOperationId: operationId,
        completedAt: timestamp,
        updatedAt: timestamp,
      },
    });
  }

  return {
    tenantId,
    tenantSlug,
    oldOwnerUid,
    replacementUid,
    mode: input.mode,
    mutations,
    ownerUidsAfter: [replacementUid],
  };
}

function applyMutation(
  transaction: OwnerRecoveryTransaction,
  mutation: OwnerRecoveryMutation
): void {
  if (mutation.kind === "create") {
    transaction.create(mutation.path, mutation.data);
  } else if (mutation.kind === "update") {
    transaction.update(mutation.path, mutation.data);
  } else {
    transaction.set(mutation.path, mutation.data, mutation.merge);
  }
}

function completedOperationResult(
  input: OwnerRecoveryInput,
  tenant: RecoveryDocument,
  replacementStaff: RecoveryDocument,
  operation: RecoveryDocument
): OwnerRecoveryResult | undefined {
  if (!operation.exists || !operation.data) return undefined;
  const data = operation.data;
  if (
    data.status !== "completed" ||
    data.eventType !== "owner_recovered" ||
    data.tenantId !== input.tenantId ||
    data.replacementUid !== input.replacementUid ||
    data.recoveryMode !== input.mode
  ) {
    invalid("operation-conflict", "operationId is already used by another operation.");
  }
  const tenantData = existingData(tenant, "tenant", "operation-conflict");
  const staff = staffRecord(
    replacementStaff,
    "replacement staff",
    "operation-conflict"
  );
  if (
    tenantData.ownerUid !== input.replacementUid ||
    staff.uid !== input.replacementUid ||
    staff.role !== "owner" ||
    staff.status !== "active"
  ) {
    invalid(
      "operation-conflict",
      "The completed operation audit does not match current canonical ownership."
    );
  }
  return {
    tenantId: input.tenantId,
    tenantSlug: stringField(tenantData, "slug", "tenant", "operation-conflict"),
    oldOwnerUid: stringField(data, "oldOwnerUid", "operation audit", "operation-conflict"),
    replacementUid: input.replacementUid,
    mode: input.mode,
    operationId: input.operationId,
    dryRun: false,
    alreadyCompleted: true,
    plannedWriteCount: 0,
  };
}

/** Runs all canonical reads and ownership mutations in one Firestore transaction. */
export async function recoverTenantOwner(
  dependencies: OwnerRecoveryDependencies,
  rawInput: OwnerRecoveryInput
): Promise<OwnerRecoveryResult> {
  const input: OwnerRecoveryInput = {
    ...rawInput,
    tenantId: requireDocumentId(rawInput.tenantId, "tenantId"),
    replacementUid: requireDocumentId(rawInput.replacementUid, "replacementUid"),
    operatorUid: requireDocumentId(rawInput.operatorUid, "operatorUid"),
    operationId: requireDocumentId(rawInput.operationId, "operationId"),
    reason: requireText(rawInput.reason, "reason", 1000),
    ...(rawInput.caseId ? {caseId: requireDocumentId(rawInput.caseId, "caseId")} : {}),
  };
  if (input.mode !== "normal" && input.mode !== "exceptional") {
    invalid("invalid-input", "mode must be normal or exceptional.");
  }

  const [operatorAuth, replacementAuth] = await Promise.all([
    dependencies.auth.getUser(input.operatorUid),
    dependencies.auth.getUser(input.replacementUid),
  ]);
  assertRecoveryAuthIdentities(input, operatorAuth, replacementAuth);

  return dependencies.store.runTransaction(async (transaction) => {
    const tenantPath = `tenants/${input.tenantId}`;
    const operationPath = `platform_audit_logs/${input.operationId}`;
    const [tenant, operatorUser, replacementUser, operation] = await Promise.all([
      transaction.get(tenantPath),
      transaction.get(`users/${input.operatorUid}`),
      transaction.get(`users/${input.replacementUid}`),
      transaction.get(operationPath),
    ]);

    assertOperatorRoot(operatorUser);
    assertTenantUserRoot(replacementUser, "replacement root user", true);
    const tenantData = existingData(tenant, "tenant", "tenant-ineligible");
    const currentOwnerUid = requireDocumentId(
      stringField(tenantData, "ownerUid", "tenant", "owner-invariant-invalid"),
      "tenant.ownerUid"
    );
    const replacementStaffPath = `${tenantPath}/staff/${input.replacementUid}`;
    const replacementStaff = await transaction.get(replacementStaffPath);
    const completed = completedOperationResult(input, tenant, replacementStaff, operation);
    if (completed) return completed;

    const oldOwnerStaffPath = `${tenantPath}/staff/${currentOwnerUid}`;
    const recoveryCasePath = input.mode === "exceptional" && input.caseId ?
      `owner_recovery_cases/${input.caseId}` :
      undefined;
    const [
      oldOwnerUser,
      oldOwnerStaff,
      oldOwnerMirror,
      replacementMirror,
      tenantOwnerStaff,
      oldOwnerOwnedTenants,
      replacementOwnedTenants,
      oldOwnerMemberships,
      replacementMemberships,
      recoveryCase,
    ] = await Promise.all([
      transaction.get(`users/${currentOwnerUid}`),
      transaction.get(oldOwnerStaffPath),
      transaction.get(`users/${currentOwnerUid}/tenant_memberships/${input.tenantId}`),
      transaction.get(`users/${input.replacementUid}/tenant_memberships/${input.tenantId}`),
      transaction.queryTenantOwnerStaff(input.tenantId),
      transaction.queryOwnedTenants(currentOwnerUid),
      transaction.queryOwnedTenants(input.replacementUid),
      transaction.queryStaffMemberships(currentOwnerUid),
      transaction.queryStaffMemberships(input.replacementUid),
      recoveryCasePath ? transaction.get(recoveryCasePath) : Promise.resolve(undefined),
    ]);

    const timestamp = (dependencies.serverTimestamp ?? FieldValue.serverTimestamp)();
    const plan = buildOwnerRecoveryPlan(input, {
      tenant,
      operatorUser,
      oldOwnerUser,
      replacementUser,
      oldOwnerStaff,
      replacementStaff,
      oldOwnerMirror,
      replacementMirror,
      tenantOwnerStaff,
      oldOwnerOwnedTenants,
      replacementOwnedTenants,
      oldOwnerMemberships,
      replacementMemberships,
      replacementAuth,
      recoveryCase,
    }, timestamp);

    if (!input.dryRun) {
      for (const mutation of plan.mutations) applyMutation(transaction, mutation);
    }

    return {
      tenantId: plan.tenantId,
      tenantSlug: plan.tenantSlug,
      oldOwnerUid: plan.oldOwnerUid,
      replacementUid: plan.replacementUid,
      mode: plan.mode,
      operationId: input.operationId,
      dryRun: input.dryRun === true,
      alreadyCompleted: false,
      plannedWriteCount: plan.mutations.length,
    };
  });
}

function firestoreDocument(snapshot: {
  ref: {path: string};
  id: string;
  exists: boolean;
  data(): Record<string, unknown> | undefined;
}): RecoveryDocument {
  const data = snapshot.data();
  return {
    path: snapshot.ref.path,
    id: snapshot.id,
    exists: snapshot.exists,
    ...(data ? {data} : {}),
  };
}

class FirestoreRecoveryTransaction implements OwnerRecoveryTransaction {
  constructor(private readonly db: Firestore, private readonly transaction: Transaction) {}

  async get(path: string): Promise<RecoveryDocument> {
    return firestoreDocument(await this.transaction.get(this.db.doc(path)));
  }

  async queryTenantOwnerStaff(tenantId: string): Promise<readonly RecoveryDocument[]> {
    const snapshot = await this.transaction.get(
      this.db.collection("tenants").doc(tenantId).collection("staff")
        .where("role", "==", "owner")
        .select("uid", "role", "status")
    );
    return snapshot.docs.map(firestoreDocument);
  }

  async queryOwnedTenants(uid: string): Promise<readonly RecoveryDocument[]> {
    const snapshot = await this.transaction.get(
      this.db.collection("tenants").where("ownerUid", "==", uid)
        .select("ownerUid", "status")
    );
    return snapshot.docs.map(firestoreDocument);
  }

  async queryStaffMemberships(uid: string): Promise<readonly RecoveryDocument[]> {
    const snapshot = await this.transaction.get(
      this.db.collectionGroup("staff").where("uid", "==", uid).select("uid")
    );
    return snapshot.docs.map(firestoreDocument);
  }

  create(path: string, data: Readonly<Record<string, unknown>>): void {
    this.transaction.create(this.db.doc(path), data);
  }

  update(path: string, data: Readonly<Record<string, unknown>>): void {
    this.transaction.update(this.db.doc(path), data);
  }

  set(path: string, data: Readonly<Record<string, unknown>>, merge: boolean): void {
    this.transaction.set(this.db.doc(path), data, {merge});
  }
}

export class FirestoreOwnerRecoveryStore implements OwnerRecoveryStore {
  constructor(private readonly db: Firestore) {}

  runTransaction<T>(
    handler: (transaction: OwnerRecoveryTransaction) => Promise<T>
  ): Promise<T> {
    return this.db.runTransaction((transaction) =>
      handler(new FirestoreRecoveryTransaction(this.db, transaction))
    );
  }
}
