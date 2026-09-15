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
import {
  MAXIMUM_IMPORT_CATEGORY_SCAN,
  foldCategoryName,
} from "./productImport";
import {MAXIMUM_PRODUCT_NAME_LENGTH} from "./productUpdate";

/**
 * Naming a grouping, and the one rule a device could never enforce for itself.
 *
 * **Two categories called "Drinks" is a catalog nobody can import into.** A
 * spreadsheet row names a category the way a shopkeeper does - `Drinks`, never
 * `ct_7f3a` - and `importProducts` resolves that name against this business's own
 * categories. When two of them fold to the same name the server cannot know which
 * was meant, so it refuses the row rather than guessing; the only alternative it
 * can offer is the document ID, which is precisely the implementation detail the
 * rest of this product refuses to show anybody. So the ambiguity has to be
 * prevented where it is created, and that is here.
 *
 * **Why it could not stay a document write.** Uniqueness is a statement about
 * every *other* document in the collection, and a Firestore rule can read the
 * document being written and named documents - never a query. A device can check
 * the categories it has read, and until now that check was the only one there
 * was: two devices adding "Drinks" in the same minute both passed it, and so did
 * one device that had only read the first page. The check has to be made by the
 * principal that can see all of them inside the same transaction that writes.
 *
 * **Bounded by the same figure the import is bounded by, deliberately.** The
 * scan stops at [MAXIMUM_IMPORT_CATEGORY_SCAN], which is where
 * `getProductImportCategories` stops resolving names at all. Above that bound an
 * import refuses every row that names a category by name, so a duplicate up
 * there cannot make an import ambiguous - there is no name resolution left to
 * confuse. Enforcing uniqueness exactly as far as the ambiguity reaches is what
 * keeps one bound instead of two, and a business that large is told to name
 * categories by ID by both paths in the same words.
 *
 * **Neither call gives up offline.** Both are queued by the outbox and drained
 * when the device can reach the server, exactly as `createProduct` is, and
 * `TenantPendingMutationOverlayReader` draws the category over the catalog the
 * moment it is queued. What changed is where the decision is made, not when the
 * person may carry on. A queued name that a colleague takes first is rejected at
 * drain and reported on the notifications screen - which is the honest outcome,
 * and the one a device inventing its own answer was hiding.
 */

interface CategoryDocumentRequest {
  tenantId?: unknown;
  categoryId?: unknown;
  document?: unknown;
}

export interface CategoryWriteResponse {
  categoryId: string;
  name: string;
}

/** The trio the `categories` rule admitted while this was a document write. */
export const CATEGORY_WRITE_ROLES = ["owner", "admin", "manager"] as const;

/**
 * Every key the document a client sends may carry.
 *
 * `createdBy` and `updatedBy` are **accepted and ignored**: this server takes
 * the actor from the authenticated request, and a client has no say in either -
 * but the queued document a device composed carries one, and a record queued
 * before these callables existed carries one too. Refusing a field that is
 * merely redundant would reject work already durable on somebody's phone.
 */
const ACCEPTED_CATEGORY_DOCUMENT_KEYS = new Set<string>([
  "name",
  "createdBy",
  "updatedBy",
]);

/**
 * Reads the one field a category has, in the shape the client normalizes it to.
 *
 * The same trim, the same whitespace collapse, the same bound and the same
 * refusal of control characters that `normalizeProductName` applies and that
 * `tenantCatalogNormalizedName` applies on the device. A name this accepted and
 * that one did not would be a category the catalog surface could not have
 * created, and the two drifting apart is what one spelling in two places means.
 */
export function readCategoryName(value: unknown): string {
  const document = requireObject(value, "document");
  for (const key of Object.keys(document)) {
    if (!ACCEPTED_CATEGORY_DOCUMENT_KEYS.has(key)) {
      throw new HttpsError(
        "invalid-argument",
        `${key} is not part of a category.`
      );
    }
  }
  const raw = (document as Record<string, unknown>).name;
  if (typeof raw !== "string") {
    throw new HttpsError("invalid-argument", "name must be a string.");
  }
  const name = raw.trim().replace(/\s+/g, " ");
  if (name.length === 0 || name.length > MAXIMUM_PRODUCT_NAME_LENGTH) {
    throw new HttpsError(
      "invalid-argument",
      `name must be between 1 and ${MAXIMUM_PRODUCT_NAME_LENGTH} characters.`
    );
  }
  if (/\p{Cc}/u.test(name)) {
    throw new HttpsError(
      "invalid-argument",
      "name contains unsupported characters."
    );
  }
  return name;
}

/**
 * Refuses [name] when another category in this business already folds to it.
 *
 * Read inside the caller's transaction, so a colleague naming the same thing in
 * the same second loses the race rather than joining it: Firestore retries a
 * transaction whose reads were written under it.
 *
 * [exceptId] is the category being renamed, which must not collide with itself -
 * renaming "drinks" to "Drinks" is a capitalisation fix, not a duplicate.
 */
export async function assertCategoryNameFree(
  transaction: Transaction,
  tenantRef: DocumentReference,
  name: string,
  exceptId: string | null
): Promise<void> {
  // One more than the bound, so "there are too many to check" is answered by the
  // read itself rather than by a count query nobody else in this codebase runs -
  // the shape `getProductImportCategories` uses against the same collection.
  const query = tenantRef
    .collection("categories")
    .limit(MAXIMUM_IMPORT_CATEGORY_SCAN + 1);
  const snapshot = await transaction.get(query);
  if (snapshot.size > MAXIMUM_IMPORT_CATEGORY_SCAN) {
    throw new HttpsError(
      "failed-precondition",
      `This business holds more than ${MAXIMUM_IMPORT_CATEGORY_SCAN} ` +
      "categories, which is more than one name can be checked against. " +
      "Name each row's category by categoryId when importing."
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
        `This business already has a category called "${existing}". Two ` +
        "categories with one name cannot be told apart when a spreadsheet " +
        "names that category."
      );
    }
  }
}

/**
 * Brings one category into the catalog, under a name nothing else answers to.
 *
 * **The client's document ID is the idempotency key**, exactly as it is for
 * `createProduct`: a category ID is already `ct_` plus a digest of the operation,
 * business, actor and request ID, so it is unguessable, stable across the retries
 * of one confirmation, and unique to it. Taking a second key would let the two
 * disagree.
 *
 * A replay therefore answers off the stored record and never reaches the
 * uniqueness check - which is what stops a device that retried a create it had
 * already made being told its own category is a duplicate of itself.
 */
export const createCategory = onCall<
  CategoryDocumentRequest,
  Promise<CategoryWriteResponse>
>(async (
  request: CallableRequest<CategoryDocumentRequest>
): Promise<CategoryWriteResponse> => {
  const data = requireObject(request.data);
  const tenantId = requireDocumentId(data.tenantId, "tenantId");
  const categoryId = requireDocumentId(data.categoryId, "categoryId");
  // Proved usable as an idempotency key before it is used as one, so a caller
  // that derived the ID some other way is refused here rather than silently
  // given a key the record cannot be found under again.
  requireRequestId(categoryId);
  const name = readCategoryName(data.document);
  const db = getFirestore();

  const actor = await requireTenantMember(
    db,
    request,
    tenantId,
    CATEGORY_WRITE_ROLES
  );

  return runIdempotentFirestoreTransaction(db, {
    actorUid: actor.uid,
    operation: "createCategory",
    tenantId,
    requestId: categoryId,
    input: {categoryId, name},
  }, async (transaction) => {
    await requireTenantMember(
      db,
      request,
      tenantId,
      CATEGORY_WRITE_ROLES,
      transaction
    );
    const tenantRef = db.collection("tenants").doc(tenantId);
    await assertCategoryNameFree(transaction, tenantRef, name, null);
    transaction.create(tenantRef.collection("categories").doc(categoryId), {
      name,
      // From the actor, never from the payload. A device composes this document
      // and could name anybody; who added the grouping every product is filed
      // under is the server's to say.
      createdBy: actor.uid,
      createdAt: FieldValue.serverTimestamp(),
    });
    return {categoryId, name};
  });
});

/**
 * Renames one category, keeping its identity and every product filed under it.
 *
 * **No idempotency record, and that is deliberate.** Renaming is idempotent by
 * construction - setting a name to the same value twice leaves the same document
 * - so a replay needs no stored answer to be safe, and storing one would key on
 * a request ID this payload has never carried. What the transaction does need is
 * for the uniqueness read and the write to be one act, which it is.
 *
 * A rename to a name the category already holds is accepted rather than refused:
 * the client refuses an unchanged name before sending, and a *queued* rename
 * that drains twice must not become a failure the second time.
 */
export const renameCategory = onCall<
  CategoryDocumentRequest,
  Promise<CategoryWriteResponse>
>(async (
  request: CallableRequest<CategoryDocumentRequest>
): Promise<CategoryWriteResponse> => {
  const data = requireObject(request.data);
  const tenantId = requireDocumentId(data.tenantId, "tenantId");
  const categoryId = requireDocumentId(data.categoryId, "categoryId");
  const name = readCategoryName(data.document);
  const db = getFirestore();

  await requireTenantMember(db, request, tenantId, CATEGORY_WRITE_ROLES);

  return renameCategoryInTransaction(db, {
    request,
    tenantId,
    categoryId,
    name,
  });
});

async function renameCategoryInTransaction(
  db: Firestore,
  options: {
    request: CallableRequest<CategoryDocumentRequest>;
    tenantId: string;
    categoryId: string;
    name: string;
  }
): Promise<CategoryWriteResponse> {
  const {request, tenantId, categoryId, name} = options;
  return db.runTransaction(async (transaction) => {
    const actor = await requireTenantMember(
      db,
      request,
      tenantId,
      CATEGORY_WRITE_ROLES,
      transaction
    );
    const tenantRef = db.collection("tenants").doc(tenantId);
    const categoryRef = tenantRef.collection("categories").doc(categoryId);
    const snapshot = await transaction.get(categoryRef);
    if (!snapshot.exists) {
      throw new HttpsError(
        "not-found",
        "The category does not exist in this business."
      );
    }
    await assertCategoryNameFree(transaction, tenantRef, name, categoryId);
    transaction.update(categoryRef, {
      name,
      updatedBy: actor.uid,
      updatedAt: FieldValue.serverTimestamp(),
    });
    return {categoryId, name};
  });
}
