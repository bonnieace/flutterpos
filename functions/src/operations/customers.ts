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
import {MAXIMUM_PRODUCT_NAME_LENGTH} from "./productUpdate";

/**
 * Who a business sells to, and the one rule a device cannot enforce.
 *
 * **A customer is a contact, not a ledger.** It is who a sale was for and how to
 * reach them. The figures on it - `points`, `saleCount`, `lastSaleAt` - are
 * written by `processCustomerSale` and never by these callables, so nothing a
 * device sends can award points or rewrite a purchase history.
 *
 * **Two customers may share a name and may not share a phone number.** Two
 * people called John buy from the same shop every day, so a name is not an
 * identity the way a supplier's is. A phone number is: it is where the receipt
 * goes, and two records holding one number would send one person two people's
 * receipts. Uniqueness is a statement about every *other* customer, which no
 * Firestore rule can read, so these are callables for the reason `suppliers.ts`
 * gives.
 *
 * **Consent to WhatsApp receipts belongs to the number it was given for.**
 * Changing or clearing the phone clears the consent in the same write, unless the
 * same correction records it again - the rule carerota's notification consent
 * follows, for the same reason: a tick recorded against one number is not
 * permission to message another.
 *
 * **A customer is never deleted, only marked inactive.** Sales name them, and a
 * history whose rows point at nothing is a history nobody can read.
 *
 * **Neither call gives up offline.** Both are queued by the outbox and drained
 * when the device reaches the server; a queued number a colleague took first is
 * refused at drain and reported, which is the honest outcome.
 */

interface CustomerDocumentRequest {
  tenantId?: unknown;
  customerId?: unknown;
  document?: unknown;
}

export interface CustomerWriteResponse {
  customerId: string;
  name: string;
  active: boolean;
}

/**
 * Who may add a customer: everyone who sells.
 *
 * **A cashier included, because the till is where a customer is met.** A shop
 * whose cashier had to fetch a manager to take a phone number would take no phone
 * numbers.
 */
export const CUSTOMER_CREATE_ROLES = ["owner", "admin", "manager", "cashier"] as const;

/** Who may correct one, mark one inactive, or record consent afterwards. */
export const CUSTOMER_UPDATE_ROLES = ["owner", "admin", "manager"] as const;

export const MAXIMUM_CUSTOMER_EMAIL_LENGTH = 254;
export const MAXIMUM_CUSTOMER_NOTES_LENGTH = 1000;

/** The longest a single search token may be prefixed to, as staff search bounds it. */
const MAXIMUM_SEARCH_TOKEN_LENGTH = 120;

/**
 * The trailing digits a phone search also answers to.
 *
 * **Nine, because that is the national number across the region this product
 * sells in.** `+254 712 345 678` is written `0712 345 678` at a counter and
 * searched as either, and Kenya, Tanzania, Uganda and Rwanda all use nine-digit
 * mobile numbers after the country code. A number shorter than this is indexed by
 * its full digits only.
 */
const NATIONAL_NUMBER_DIGITS = 9;

/** The optional contact fields, each cleared by null or an empty string. */
export const OPTIONAL_CUSTOMER_FIELDS = [
  "phone",
  "email",
  "kraPin",
  "notes",
] as const;

export type OptionalCustomerField = (typeof OPTIONAL_CUSTOMER_FIELDS)[number];

/**
 * Every key the document a client sends may carry.
 *
 * `createdBy` and `updatedBy` are accepted and ignored, as a supplier's are. So
 * are `searchName` and `searchPrefixes`: the device composes them so its own
 * offline list can find a customer it has not sent yet, and the server computes
 * its own from what it stores rather than trusting a device's index.
 */
const ACCEPTED_CUSTOMER_DOCUMENT_KEYS = new Set<string>([
  "name",
  ...OPTIONAL_CUSTOMER_FIELDS,
  "whatsappOptIn",
  "active",
  "createdBy",
  "updatedBy",
  "searchName",
  "searchPrefixes",
]);

/** One customer write, read and normalized. */
export interface CustomerFields {
  name?: string;

  /** A value to store, or null to clear what is stored. Absent leaves it alone. */
  phone?: string | null;
  email?: string | null;
  kraPin?: string | null;
  notes?: string | null;

  /** True records consent now; false withdraws it. Absent leaves it alone. */
  whatsappOptIn?: boolean;

  active?: boolean;
}

const EMAIL_SHAPE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

/** E.164: a plus, a non-zero country digit, then seven to fourteen more. */
const E164_SHAPE = /^\+[1-9]\d{7,14}$/;

/**
 * A KRA PIN: one letter, nine digits, one letter - `A012345678Z`.
 *
 * Stored in capitals. The PIN printed on a certificate is in capitals, and one
 * typed in lower case at a counter is the same PIN rather than a different one.
 */
const KRA_PIN_SHAPE = /^[A-Z][0-9]{9}[A-Z]$/;

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

/** Notes keep their line breaks and nothing else unusual, as a supplier's do. */
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
  if (normalized.length > MAXIMUM_CUSTOMER_NOTES_LENGTH) {
    throw new HttpsError(
      "invalid-argument",
      `notes must be at most ${MAXIMUM_CUSTOMER_NOTES_LENGTH} characters.`
    );
  }
  if (/\p{Cc}/u.test(normalized.replace(/\n/g, ""))) {
    throw new HttpsError("invalid-argument", "notes contains unsupported characters.");
  }
  return normalized;
}

/**
 * The phone number exactly as E.164 writes it, or a refusal.
 *
 * **The device does the conversion, not this.** A person picks a dialling code
 * and types the number they know, and `lib/tenancy/phone_number.dart` joins the
 * two; by the time a number reaches here it is either E.164 or a mistake, and
 * guessing which country a bare `0712...` belongs to is exactly the guess that
 * control exists to avoid.
 */
export function readCustomerPhone(value: unknown): string | null {
  const phone = singleLine(value, "phone", 16);
  if (phone === null) return null;
  if (!E164_SHAPE.test(phone)) {
    throw new HttpsError(
      "invalid-argument",
      "phone must be an international number such as +254712345678."
    );
  }
  return phone;
}

/** A KRA PIN in capitals, or a refusal naming the shape. */
export function readCustomerKraPin(value: unknown): string | null {
  const pin = singleLine(value, "kraPin", 11);
  if (pin === null) return null;
  const upper = pin.toUpperCase();
  if (!KRA_PIN_SHAPE.test(upper)) {
    throw new HttpsError(
      "invalid-argument",
      "kraPin must be a letter, nine digits and a letter, such as A012345678Z."
    );
  }
  return upper;
}

function optionalField(field: OptionalCustomerField, value: unknown): string | null {
  if (value === null) return null;
  switch (field) {
  case "phone":
    return readCustomerPhone(value);
  case "email": {
    const email = singleLine(value, "email", MAXIMUM_CUSTOMER_EMAIL_LENGTH);
    if (email !== null && !EMAIL_SHAPE.test(email)) {
      throw new HttpsError("invalid-argument", "email is not an email address.");
    }
    return email;
  }
  case "kraPin":
    return readCustomerKraPin(value);
  case "notes":
    return notesText(value);
  }
}

/** The name, in the shape a product name takes, or a refusal. */
export function readCustomerName(value: unknown): string {
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
 * A create must name the customer and is always active. An update names only what
 * changes, and must change something.
 */
export function readCustomerDocument(
  value: unknown,
  mode: "create" | "update"
): CustomerFields {
  const document = requireObject(value, "document");
  for (const key of Object.keys(document)) {
    if (!ACCEPTED_CUSTOMER_DOCUMENT_KEYS.has(key)) {
      throw new HttpsError("invalid-argument", `${key} is not part of a customer.`);
    }
  }
  const fields: CustomerFields = {};
  if (document.name !== undefined && document.name !== null) {
    fields.name = readCustomerName(document.name);
  } else if (mode === "create") {
    throw new HttpsError("invalid-argument", "name is required to add a customer.");
  }
  for (const field of OPTIONAL_CUSTOMER_FIELDS) {
    if (document[field] === undefined) continue;
    const read = optionalField(field, document[field]);
    // On a create, "nothing" is simply not stored; on an update it clears.
    if (mode === "create" && read === null) continue;
    fields[field] = read;
  }
  if (document.whatsappOptIn !== undefined && document.whatsappOptIn !== null) {
    if (typeof document.whatsappOptIn !== "boolean") {
      throw new HttpsError("invalid-argument", "whatsappOptIn must be true or false.");
    }
    // A create that says "no" says nothing: there is no consent to withdraw.
    if (mode === "update" || document.whatsappOptIn) {
      fields.whatsappOptIn = document.whatsappOptIn;
    }
  }
  if (mode === "create" && fields.whatsappOptIn === true && !fields.phone) {
    throw new HttpsError(
      "invalid-argument",
      "A customer can agree to WhatsApp receipts only with a phone number."
    );
  }
  if (document.active !== undefined && document.active !== null) {
    if (typeof document.active !== "boolean") {
      throw new HttpsError("invalid-argument", "active must be true or false.");
    }
    if (mode === "create" && !document.active) {
      throw new HttpsError("invalid-argument", "A customer is added active.");
    }
    if (mode === "update") fields.active = document.active;
  }
  if (mode === "update" && Object.keys(fields).length === 0) {
    throw new HttpsError(
      "invalid-argument",
      "Name at least one customer field to change."
    );
  }
  return fields;
}

/** Shared normalization for customer search fields. */
export function normalizeCustomerSearchText(value: string): string {
  return value.trim().toLowerCase().replace(/\s+/g, " ");
}

/**
 * The name and number prefixes the customer search answers to.
 *
 * **The name the way staff search reads one**, whole and by word, so "Jane
 * Wanjiku" is found by "jane", "wanj" or "jane wa". **The number three ways**: its
 * full digits, its national number, and its national number with the trunk zero a
 * counter writes - so `+254712345678` is found by "2547", "7123" and "0712".
 *
 * `lib/customers/customer.dart` computes the same list, so a customer added on
 * a device with no signal is found by its own search before the server has it.
 */
export function customerSearchFields(
  name: string,
  phone: string | null | undefined
): {searchName: string; searchPrefixes: string[]} {
  const normalizedName = normalizeCustomerSearchText(name);
  const tokens = new Set<string>([normalizedName, ...normalizedName.split(" ")]);
  if (phone) {
    const digits = phone.replace(/\D/g, "");
    tokens.add(digits);
    if (digits.length > NATIONAL_NUMBER_DIGITS) {
      const national = digits.slice(-NATIONAL_NUMBER_DIGITS);
      tokens.add(national);
      tokens.add(`0${national}`);
    }
  }
  const prefixes = new Set<string>();
  for (const token of tokens) {
    const maximum = Math.min(token.length, MAXIMUM_SEARCH_TOKEN_LENGTH);
    for (let length = 2; length <= maximum; length += 1) {
      prefixes.add(token.slice(0, length));
    }
  }
  return {
    searchName: normalizedName,
    searchPrefixes: [...prefixes].sort(),
  };
}

/**
 * Refuses [phone] when another customer in this business already holds it.
 *
 * Read inside the caller's transaction, so two cashiers adding the same person in
 * the same second cannot both succeed. [exceptId] is the customer being
 * corrected, so saving a customer's own number again is not a duplicate of itself.
 */
export async function assertCustomerPhoneFree(
  transaction: Transaction,
  tenantRef: DocumentReference,
  phone: string,
  exceptId: string | null
): Promise<void> {
  const snapshot = await transaction.get(
    tenantRef.collection("customers").where("phone", "==", phone).limit(2)
  );
  for (const document of snapshot.docs) {
    if (document.id === exceptId) continue;
    const existing = document.get("name");
    throw new HttpsError(
      "already-exists",
      `This number already belongs to ${
        typeof existing === "string" ? existing : "another customer"
      }. One number reaches one person, so it can be on one customer.`
    );
  }
}

/** The document one create writes, without the timestamps only a write has. */
export function customerCreateData(
  fields: CustomerFields,
  actorUid: string
): Record<string, unknown> {
  const data: Record<string, unknown> = {name: fields.name};
  for (const field of OPTIONAL_CUSTOMER_FIELDS) {
    const value = fields[field];
    if (typeof value === "string") data[field] = value;
  }
  if (fields.whatsappOptIn === true) {
    data.whatsappOptIn = true;
    // From the actor, never from the payload.
    data.whatsappOptInBy = actorUid;
  }
  const search = customerSearchFields(fields.name as string, fields.phone);
  data.searchName = search.searchName;
  data.searchPrefixes = search.searchPrefixes;
  data.active = true;
  data.createdBy = actorUid;
  return data;
}

/** Writes one new customer after proving their number is free. */
export async function applyCustomerCreate(
  db: Firestore,
  transaction: Transaction,
  options: {
    tenantId: string;
    customerId: string;
    actorUid: string;
    fields: CustomerFields;
  }
): Promise<CustomerWriteResponse> {
  const tenantRef = db.collection("tenants").doc(options.tenantId);
  if (options.fields.phone) {
    await assertCustomerPhoneFree(
      transaction,
      tenantRef,
      options.fields.phone,
      null
    );
  }
  const data = customerCreateData(options.fields, options.actorUid);
  transaction.create(tenantRef.collection("customers").doc(options.customerId), {
    ...data,
    ...(data.whatsappOptIn === true ?
      {whatsappOptInAt: FieldValue.serverTimestamp()} :
      {}),
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  return {
    customerId: options.customerId,
    name: options.fields.name as string,
    active: true,
  };
}

const OPT_IN_FIELDS = ["whatsappOptIn", "whatsappOptInAt", "whatsappOptInBy"] as const;

/**
 * Corrects one customer: their name, contact details, consent or standing.
 *
 * Idempotent by construction, as a supplier correction is: setting a field to the
 * value it holds leaves the same document. The one exception is consent recorded
 * again, which restamps who recorded it and when - and that is the truth about the
 * second recording, not a defect in the replay.
 */
export async function applyCustomerUpdate(
  db: Firestore,
  transaction: Transaction,
  options: {
    tenantId: string;
    customerId: string;
    actorUid: string;
    fields: CustomerFields;
  }
): Promise<CustomerWriteResponse> {
  const tenantRef = db.collection("tenants").doc(options.tenantId);
  const customerRef = tenantRef.collection("customers").doc(options.customerId);
  const snapshot = await transaction.get(customerRef);
  if (!snapshot.exists) {
    throw new HttpsError("not-found", "The customer does not exist in this business.");
  }
  const fields = options.fields;
  const storedPhone = snapshot.get("phone");
  const currentPhone = typeof storedPhone === "string" ? storedPhone : null;
  const phoneChanges = fields.phone !== undefined && fields.phone !== currentPhone;
  const resultingPhone = fields.phone !== undefined ? fields.phone : currentPhone;
  if (phoneChanges && fields.phone) {
    await assertCustomerPhoneFree(
      transaction,
      tenantRef,
      fields.phone,
      options.customerId
    );
  }
  if (fields.whatsappOptIn === true && !resultingPhone) {
    throw new HttpsError(
      "failed-precondition",
      "A customer can agree to WhatsApp receipts only with a phone number."
    );
  }

  const update: Record<string, unknown> = {};
  const cleared: string[] = [];
  if (fields.name !== undefined) update.name = fields.name;
  for (const field of OPTIONAL_CUSTOMER_FIELDS) {
    const value = fields[field];
    if (value === undefined) continue;
    if (value === null) cleared.push(field);
    else update[field] = value;
  }
  if (fields.whatsappOptIn === true) {
    update.whatsappOptIn = true;
    update.whatsappOptInAt = FieldValue.serverTimestamp();
    update.whatsappOptInBy = options.actorUid;
  } else if (
    fields.whatsappOptIn === false ||
    (phoneChanges && snapshot.get("whatsappOptIn") === true)
  ) {
    // Withdrawn, or given for a number this customer no longer has.
    cleared.push(...OPT_IN_FIELDS);
  }
  if (fields.name !== undefined || fields.phone !== undefined) {
    const storedName = snapshot.get("name");
    const search = customerSearchFields(
      fields.name ?? (typeof storedName === "string" ? storedName : ""),
      resultingPhone
    );
    update.searchName = search.searchName;
    update.searchPrefixes = search.searchPrefixes;
  }
  if (fields.active !== undefined) update.active = fields.active;
  transaction.update(customerRef, {
    ...update,
    // Cleared fields are deleted inside the write that performs it, so the
    // sentinel can never drift into a create - see `sentinelAudit.test.ts`.
    ...Object.fromEntries(
      [...new Set(cleared)].map((field) => [field, FieldValue.delete()])
    ),
    updatedBy: options.actorUid,
    updatedAt: FieldValue.serverTimestamp(),
  });
  const storedName = snapshot.get("name");
  const storedActive = snapshot.get("active");
  return {
    customerId: options.customerId,
    name: fields.name ?? (typeof storedName === "string" ? storedName : ""),
    active: fields.active ?? storedActive !== false,
  };
}

/**
 * Adds one customer.
 *
 * **The client's document ID is the idempotency key**, as it is for
 * `createSupplier`: a replay answers off the stored record and never reaches the
 * phone check, so a till retrying its own create is not told the customer is a
 * duplicate of themselves.
 */
export const createCustomer = onCall<
  CustomerDocumentRequest,
  Promise<CustomerWriteResponse>
>(async (
  request: CallableRequest<CustomerDocumentRequest>
): Promise<CustomerWriteResponse> => {
  const data = requireObject(request.data);
  const tenantId = requireDocumentId(data.tenantId, "tenantId");
  const customerId = requireDocumentId(data.customerId, "customerId");
  requireRequestId(customerId);
  const fields = readCustomerDocument(data.document, "create");
  const db = getFirestore();

  const actor = await requireTenantMember(db, request, tenantId, CUSTOMER_CREATE_ROLES);

  return runIdempotentFirestoreTransaction(db, {
    actorUid: actor.uid,
    operation: "createCustomer",
    tenantId,
    requestId: customerId,
    input: {customerId, ...fields},
  }, async (transaction) => {
    const currentActor = await requireTenantMember(
      db,
      request,
      tenantId,
      CUSTOMER_CREATE_ROLES,
      transaction
    );
    return applyCustomerCreate(db, transaction, {
      tenantId,
      customerId,
      actorUid: currentActor.uid,
      fields,
    });
  });
});

/** Corrects one customer. See [applyCustomerUpdate]. */
export const updateCustomer = onCall<
  CustomerDocumentRequest,
  Promise<CustomerWriteResponse>
>(async (
  request: CallableRequest<CustomerDocumentRequest>
): Promise<CustomerWriteResponse> => {
  const data = requireObject(request.data);
  const tenantId = requireDocumentId(data.tenantId, "tenantId");
  const customerId = requireDocumentId(data.customerId, "customerId");
  const fields = readCustomerDocument(data.document, "update");
  const db = getFirestore();

  await requireTenantMember(db, request, tenantId, CUSTOMER_UPDATE_ROLES);

  return db.runTransaction(async (transaction) => {
    const actor = await requireTenantMember(
      db,
      request,
      tenantId,
      CUSTOMER_UPDATE_ROLES,
      transaction
    );
    return applyCustomerUpdate(db, transaction, {
      tenantId,
      customerId,
      actorUid: actor.uid,
      fields,
    });
  });
});
