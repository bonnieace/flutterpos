import {FieldValue, getFirestore, Transaction} from "firebase-admin/firestore";
import type {DocumentReference, Firestore} from "firebase-admin/firestore";
import {CallableRequest, HttpsError, onCall} from "firebase-functions/v2/https";
import {requireTenantMember} from "../core/authorization";
import {runIdempotentFirestoreTransaction} from "../core/idempotency";
import {
  requireDocumentId,
  requireObject,
  requireRequestId,
} from "../core/validation";
import {foldCategoryName} from "./productImport";
import {MAXIMUM_PRODUCT_NAME_LENGTH} from "./productUpdate";

/**
 * The businesses stock is bought from, and the one rule a device cannot enforce.
 *
 * **A supplier holds no stock.** It is who a delivery came from and how to reach
 * them; its history is the deliveries recorded against it, never a figure stored
 * on it. So this module writes contact details and a standing and nothing that
 * moves a quantity or a cost.
 *
 * **Two suppliers called "ABC Distributors" split one supplier's history in two.**
 * Uniqueness is a statement about every *other* document in the collection, which
 * a Firestore rule cannot read, so these are callables for exactly the reason
 * `categories.ts` gives - and the name folds exactly as a category name does, so
 * "abc  distributors" is the same supplier as "ABC Distributors".
 *
 * **A supplier is never deleted, only marked inactive.** Deliveries name it, and a
 * history whose rows point at nothing is a history nobody can read. Inactive
 * leaves it off the picker and keeps everything it was part of.
 *
 * **Neither call gives up offline.** Both are queued by the outbox and drained
 * when the device reaches the server, as categories are; a queued name a colleague
 * takes first is rejected at drain and reported, which is the honest outcome.
 */

interface SupplierDocumentRequest {
  tenantId?: unknown;
  supplierId?: unknown;
  document?: unknown;
}

export interface SupplierWriteResponse {
  supplierId: string;
  name: string;
  active: boolean;
}

/** Who may add, correct and retire a supplier: the roles that receive stock. */
export const SUPPLIER_WRITE_ROLES = ["owner", "admin", "manager"] as const;

/**
 * The most suppliers one name is checked against.
 *
 * The client reads the whole directory up to this figure too, so a business at
 * the bound can still see every supplier it holds - and one above it is told so,
 * rather than being handed a duplicate check that silently looked at part of it.
 */
export const MAXIMUM_SUPPLIER_SCAN = 500;

export const MAXIMUM_SUPPLIER_PHONE_LENGTH = 32;
export const MAXIMUM_SUPPLIER_EMAIL_LENGTH = 254;
export const MAXIMUM_SUPPLIER_ADDRESS_LENGTH = 300;
export const MAXIMUM_SUPPLIER_TAX_REFERENCE_LENGTH = 64;
export const MAXIMUM_SUPPLIER_NOTES_LENGTH = 1000;

/** The optional contact fields, each cleared by null or an empty string. */
export const OPTIONAL_SUPPLIER_FIELDS = [
  "phone",
  "email",
  "address",
  "taxReference",
  "notes",
] as const;

export type OptionalSupplierField = (typeof OPTIONAL_SUPPLIER_FIELDS)[number];

/**
 * Every key the document a client sends may carry.
 *
 * `createdBy` and `updatedBy` are accepted and ignored, as a category's are: the
 * actor comes from the authenticated request, but the queued document a device
 * composed carries one.
 */
const ACCEPTED_SUPPLIER_DOCUMENT_KEYS = new Set<string>([
  "name",
  ...OPTIONAL_SUPPLIER_FIELDS,
  "active",
  "createdBy",
  "updatedBy",
]);

/** One supplier write, read and normalized. */
export interface SupplierFields {
  name?: string;

  /** A value to store, or null to clear what is stored. Absent leaves it alone. */
  phone?: string | null;
  email?: string | null;
  address?: string | null;
  taxReference?: string | null;
  notes?: string | null;

  active?: boolean;
}

const EMAIL_SHAPE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const PHONE_SHAPE = /^[0-9+()\-. ]{3,}$/;

/** A single line, trimmed and collapsed, with nothing a list row cannot draw. */
function singleLine(
  value: unknown,
  field: string,
  maximum: number
): string | null {
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", `${field} must be a string or null.`);
  }
  const normalized = value.trim().replace(/\s+/g, " ");
  if (normalized.length === 0) return null;
  if (normalized.length > maximum) {
    throw new HttpsError(
      "invalid-argument",
      `${field} must be at most ${maximum} characters.`
    );
  }
  if (/\p{Cc}/u.test(normalized)) {
    throw new HttpsError("invalid-argument", `${field} contains unsupported characters.`);
  }
  return normalized;
}

/**
 * Notes keep their line breaks and nothing else unusual.
 *
 * A note is where somebody writes "deliveries Tuesdays / ask for Peter" on two
 * lines, so collapsing every break would lose what they meant; every other
 * control character is refused, and runs of spaces inside a line collapse.
 */
function notesText(value: unknown): string | null {
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", "notes must be a string or null.");
  }
  const normalized = value
    .replace(/\r\n?/g, "\n")
    .split("\n")
    .map((line) => line.trim().replace(/[^\S\n]+/g, " "))
    .join("\n")
    .trim();
  if (normalized.length === 0) return null;
  if (normalized.length > MAXIMUM_SUPPLIER_NOTES_LENGTH) {
    throw new HttpsError(
      "invalid-argument",
      `notes must be at most ${MAXIMUM_SUPPLIER_NOTES_LENGTH} characters.`
    );
  }
  if (/\p{Cc}/u.test(normalized.replace(/\n/g, ""))) {
    throw new HttpsError("invalid-argument", "notes contains unsupported characters.");
  }
  return normalized;
}

function optionalField(field: OptionalSupplierField, value: unknown): string | null {
  if (value === null) return null;
  switch (field) {
  case "phone": {
    const phone = singleLine(value, "phone", MAXIMUM_SUPPLIER_PHONE_LENGTH);
    if (phone !== null && !PHONE_SHAPE.test(phone)) {
      throw new HttpsError(
        "invalid-argument",
        "phone may hold digits, spaces and + ( ) - . only."
      );
    }
    return phone;
  }
  case "email": {
    const email = singleLine(value, "email", MAXIMUM_SUPPLIER_EMAIL_LENGTH);
    if (email !== null && !EMAIL_SHAPE.test(email)) {
      throw new HttpsError("invalid-argument", "email is not an email address.");
    }
    return email;
  }
  case "address":
    return singleLine(value, "address", MAXIMUM_SUPPLIER_ADDRESS_LENGTH);
  case "taxReference":
    return singleLine(value, "taxReference", MAXIMUM_SUPPLIER_TAX_REFERENCE_LENGTH);
  case "notes":
    return notesText(value);
  }
}

/** The name, in the shape a category name takes, or a refusal. */
export function readSupplierName(value: unknown): string {
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", "name must be a string.");
  }
  const name = value.trim().replace(/\s+/g, " ");
  if (name.length === 0 || name.length > MAXIMUM_PRODUCT_NAME_LENGTH) {
    throw new HttpsError(
      "invalid-argument",
      `name must be between 1 and ${MAXIMUM_PRODUCT_NAME_LENGTH} characters.`
    );
  }
  if (/\p{Cc}/u.test(name)) {
    throw new HttpsError("invalid-argument", "name contains unsupported characters.");
  }
  return name;
}

/**
 * Reads the document a device composed.
 *
 * A create must name the supplier and is always active - a supplier nobody may
 * pick is not a thing worth adding. An update names only what changes, and must
 * change something.
 */
export function readSupplierDocument(
  value: unknown,
  mode: "create" | "update"
): SupplierFields {
  const document = requireObject(value, "document");
  for (const key of Object.keys(document)) {
    if (!ACCEPTED_SUPPLIER_DOCUMENT_KEYS.has(key)) {
      throw new HttpsError("invalid-argument", `${key} is not part of a supplier.`);
    }
  }
  const fields: SupplierFields = {};
  if (document.name !== undefined && document.name !== null) {
    fields.name = readSupplierName(document.name);
  } else if (mode === "create") {
    throw new HttpsError("invalid-argument", "name is required to add a supplier.");
  }
  for (const field of OPTIONAL_SUPPLIER_FIELDS) {
    if (document[field] === undefined) continue;
    const read = optionalField(field, document[field]);
    // On a create, "nothing" is simply not stored; on an update it clears.
    if (mode === "create" && read === null) continue;
    fields[field] = read;
  }
  if (document.active !== undefined && document.active !== null) {
    if (typeof document.active !== "boolean") {
      throw new HttpsError("invalid-argument", "active must be true or false.");
    }
    if (mode === "create" && !document.active) {
      throw new HttpsError("invalid-argument", "A supplier is added active.");
    }
    if (mode === "update") fields.active = document.active;
  }
  if (mode === "update" && Object.keys(fields).length === 0) {
    throw new HttpsError(
      "invalid-argument",
      "Name at least one supplier field to change."
    );
  }
  return fields;
}

/**
 * Refuses [name] when another supplier in this business already folds to it.
 *
 * Read inside the caller's transaction, so two people adding the same supplier in
 * the same second cannot both succeed. [exceptId] is the supplier being corrected:
 * "abc distributors" to "ABC Distributors" is a capitalisation fix, not a
 * duplicate.
 */
export async function assertSupplierNameFree(
  transaction: Transaction,
  tenantRef: DocumentReference,
  name: string,
  exceptId: string | null
): Promise<void> {
  const snapshot = await transaction.get(
    tenantRef.collection("suppliers").limit(MAXIMUM_SUPPLIER_SCAN + 1)
  );
  if (snapshot.size > MAXIMUM_SUPPLIER_SCAN) {
    throw new HttpsError(
      "failed-precondition",
      `This business holds more than ${MAXIMUM_SUPPLIER_SCAN} suppliers, which ` +
      "is more than one name can be checked against."
    );
  }
  const folded = foldCategoryName(name);
  for (const document of snapshot.docs) {
    if (document.id === exceptId) continue;
    const existing = document.get("name");
    if (typeof existing !== "string") continue;
    if (foldCategoryName(existing) === folded) {
      throw new HttpsError(
        "already-exists",
        `This business already has a supplier called "${existing}". Two ` +
        "suppliers with one name would split one supplier's deliveries in two."
      );
    }
  }
}

/** The document one create writes, without the timestamps only a write has. */
export function supplierCreateData(
  fields: SupplierFields,
  actorUid: string
): Record<string, unknown> {
  const data: Record<string, unknown> = {name: fields.name};
  for (const field of OPTIONAL_SUPPLIER_FIELDS) {
    const value = fields[field];
    if (typeof value === "string") data[field] = value;
  }
  data.active = true;
  // From the actor, never from the payload.
  data.createdBy = actorUid;
  return data;
}

/** Writes one new supplier after proving its name is free. */
export async function applySupplierCreate(
  db: Firestore,
  transaction: Transaction,
  options: {
    tenantId: string;
    supplierId: string;
    actorUid: string;
    fields: SupplierFields;
  }
): Promise<SupplierWriteResponse> {
  const tenantRef = db.collection("tenants").doc(options.tenantId);
  await assertSupplierNameFree(
    transaction,
    tenantRef,
    options.fields.name as string,
    null
  );
  transaction.create(tenantRef.collection("suppliers").doc(options.supplierId), {
    ...supplierCreateData(options.fields, options.actorUid),
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  return {
    supplierId: options.supplierId,
    name: options.fields.name as string,
    active: true,
  };
}

/**
 * Corrects one supplier: its name, its contact details, or its standing.
 *
 * Idempotent by construction, like `renameCategory`: setting a field to the value
 * it holds leaves the same document, so a queued correction that drains twice is
 * not a failure the second time and needs no stored answer.
 */
export async function applySupplierUpdate(
  db: Firestore,
  transaction: Transaction,
  options: {
    tenantId: string;
    supplierId: string;
    actorUid: string;
    fields: SupplierFields;
  }
): Promise<SupplierWriteResponse> {
  const tenantRef = db.collection("tenants").doc(options.tenantId);
  const supplierRef = tenantRef.collection("suppliers").doc(options.supplierId);
  const snapshot = await transaction.get(supplierRef);
  if (!snapshot.exists) {
    throw new HttpsError("not-found", "The supplier does not exist in this business.");
  }
  const fields = options.fields;
  if (fields.name !== undefined) {
    await assertSupplierNameFree(transaction, tenantRef, fields.name, options.supplierId);
  }
  const update: Record<string, unknown> = {};
  const cleared: OptionalSupplierField[] = [];
  if (fields.name !== undefined) update.name = fields.name;
  for (const field of OPTIONAL_SUPPLIER_FIELDS) {
    const value = fields[field];
    if (value === undefined) continue;
    if (value === null) cleared.push(field);
    else update[field] = value;
  }
  if (fields.active !== undefined) update.active = fields.active;
  transaction.update(supplierRef, {
    ...update,
    // Cleared fields are deleted inside the write that performs it, so the
    // sentinel can never drift into a create - see `sentinelAudit.test.ts`.
    ...Object.fromEntries(cleared.map((field) => [field, FieldValue.delete()])),
    updatedBy: options.actorUid,
    updatedAt: FieldValue.serverTimestamp(),
  });
  const storedName = snapshot.get("name");
  const storedActive = snapshot.get("active");
  return {
    supplierId: options.supplierId,
    name: fields.name ?? (typeof storedName === "string" ? storedName : ""),
    active: fields.active ?? storedActive !== false,
  };
}

/**
 * Adds one supplier, under a name nothing else in the business answers to.
 *
 * **The client's document ID is the idempotency key**, as it is for
 * `createCategory`: a replay answers off the stored record and never reaches the
 * uniqueness check, so a device retrying its own create is not told its supplier
 * is a duplicate of itself.
 */
export const createSupplier = onCall<
  SupplierDocumentRequest,
  Promise<SupplierWriteResponse>
>(async (
  request: CallableRequest<SupplierDocumentRequest>
): Promise<SupplierWriteResponse> => {
  const data = requireObject(request.data);
  const tenantId = requireDocumentId(data.tenantId, "tenantId");
  const supplierId = requireDocumentId(data.supplierId, "supplierId");
  requireRequestId(supplierId);
  const fields = readSupplierDocument(data.document, "create");
  const db = getFirestore();

  const actor = await requireTenantMember(db, request, tenantId, SUPPLIER_WRITE_ROLES);

  return runIdempotentFirestoreTransaction(db, {
    actorUid: actor.uid,
    operation: "createSupplier",
    tenantId,
    requestId: supplierId,
    input: {supplierId, ...fields},
  }, async (transaction) => {
    const currentActor = await requireTenantMember(
      db,
      request,
      tenantId,
      SUPPLIER_WRITE_ROLES,
      transaction
    );
    return applySupplierCreate(db, transaction, {
      tenantId,
      supplierId,
      actorUid: currentActor.uid,
      fields,
    });
  });
});

/** Corrects one supplier. See [applySupplierUpdate]. */
export const updateSupplier = onCall<
  SupplierDocumentRequest,
  Promise<SupplierWriteResponse>
>(async (
  request: CallableRequest<SupplierDocumentRequest>
): Promise<SupplierWriteResponse> => {
  const data = requireObject(request.data);
  const tenantId = requireDocumentId(data.tenantId, "tenantId");
  const supplierId = requireDocumentId(data.supplierId, "supplierId");
  const fields = readSupplierDocument(data.document, "update");
  const db = getFirestore();

  await requireTenantMember(db, request, tenantId, SUPPLIER_WRITE_ROLES);

  return db.runTransaction(async (transaction) => {
    const actor = await requireTenantMember(
      db,
      request,
      tenantId,
      SUPPLIER_WRITE_ROLES,
      transaction
    );
    return applySupplierUpdate(db, transaction, {
      tenantId,
      supplierId,
      actorUid: actor.uid,
      fields,
    });
  });
});
