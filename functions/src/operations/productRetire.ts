import {FieldValue, getFirestore} from "firebase-admin/firestore";
import {CallableRequest, HttpsError, onCall} from "firebase-functions/v2/https";
import {requireTenantMember} from "../core/authorization";
import {runIdempotentFirestoreTransaction} from "../core/idempotency";
import {requireDeviceInstant} from "../core/deviceTime";
import {
  requireDocumentId,
  requireObject,
  requireRequestId,
} from "../core/validation";
import {PRODUCT_PRICE_ROLES} from "./productUpdate";

/**
 * Takes one product out of the catalog, or puts it back.
 *
 * **"Retire" used to mean "delete", and that is the defect this closes.** The
 * product document carrying the current quantity was removed outright: no
 * movement recorded the stock leaving, every past sale line went on naming an ID
 * nothing answered to, and the `stock_movements` below it were orphaned rather
 * than deleted - Firestore keeps a subcollection when its parent goes - so the
 * ledger survived with no way into it, because the way in is the product.
 *
 * So this sets a flag instead, and **writes the movement that accounts for the
 * stock in the same transaction**. A product retired holding seventeen units
 * ends at zero with a ledger entry saying those seventeen left and when. That is
 * the same rule `createProduct` follows in the other direction: whoever writes
 * the quantity writes the movement, and only the server can write both.
 *
 * **Retired is not hidden from the books.** Reports and stock valuations count a
 * retired product exactly as they always did; it simply holds nothing. What
 * changes is that the till will not offer it and the catalog marks it.
 *
 * **Restoring is the same operation with [SetProductRetiredRequest.retired]
 * false**, and it deliberately does *not* give the stock back. Those units were
 * accounted for as leaving; inventing them again would be a second movement
 * nobody could explain. A restored product starts empty and takes an ordinary
 * opening balance, which is the route that already says where stock came from.
 */
interface SetProductRetiredRequest {
  tenantId?: unknown;
  productId?: unknown;
  requestId?: unknown;
  retired?: unknown;
  occurredAtMs?: unknown;
}

export interface SetProductRetiredResponse {
  productId: string;
  retired: boolean;

  /** The ledger entry the stock left through, or null when it held none. */
  adjustmentId: string | null;
  previousQuantity: number;
  quantity: number;
}

/** Why the closing ledger entry exists, in the words the stock ledger records. */
export const RETIRE_CLOSING_STOCK_REASON =
  "Stock cleared when the product was retired from the catalog.";

/**
 * Retiring is owner and administrator work, which is exactly who `allow delete`
 * on `products` admitted before this callable replaced it. A manager may correct
 * a product and adjust its stock; taking it out of the catalog is narrower, and
 * stays where it was.
 */
const PRODUCT_RETIRE_ROLES = PRODUCT_PRICE_ROLES;

/** The `stock_adjustments` and `stock_movements` ID one retirement writes at. */
export function productRetireAdjustmentId(requestId: string): string {
  // Derived from the request rather than the product, unlike `createProduct`'s.
  // A product may be retired, restored and retired again, and each retirement
  // clears whatever it held at that moment - so they are separate movements and
  // must not collide on one ID.
  return `sa_ret_${requestId}`;
}

/** The `audit_logs` ID one retirement or restoration writes at. */
export function productRetireAuditId(requestId: string): string {
  return `pr_${requestId}`;
}

/** Every document one retirement or restoration writes, without its timestamps. */
export interface ProductRetirePlan {
  retired: boolean;

  /** Whether stock is being taken off the books by this. */
  clears: boolean;
  adjustmentId: string | null;
  auditId: string;
  previousQuantity: number;
  quantity: number;
  auditData: Record<string, unknown>;

  /** The `stock_adjustments` record and `stock_movements` entry, or null. */
  ledgerData: Record<string, unknown> | null;
}

/**
 * Decides what one retirement or restoration writes.
 *
 * Split out for the reason `planProductCreate` is: everything that decides is a
 * pure function, and the callable is the authorization and the transaction
 * around it. Timestamps are the one thing a plan cannot hold.
 */
export function planProductRetire(options: {
  tenantId: string;
  productId: string;
  actorUid: string;
  requestId: string;
  retired: boolean;
  previousQuantity: number;
}): ProductRetirePlan {
  // Only a retirement clears stock, and only when there is stock to clear.
  // Restoring leaves the figure alone: it is already zero, and putting units
  // back would be a movement nobody could account for.
  const clears = options.retired && options.previousQuantity !== 0;
  const adjustmentId = clears ?
    productRetireAdjustmentId(options.requestId) :
    null;
  const quantity = clears ? 0 : options.previousQuantity;

  return {
    retired: options.retired,
    clears,
    adjustmentId,
    auditId: productRetireAuditId(options.requestId),
    previousQuantity: options.previousQuantity,
    quantity,
    auditData: {
      eventType: options.retired ? "product_retired" : "product_restored",
      tenantId: options.tenantId,
      productId: options.productId,
      previousQuantity: options.previousQuantity,
      quantity,
      // Names the record the stock left through, and null when it held none.
      // Whenever `mutatesQuantity` is true this is what says where it went,
      // which is the property that makes clearing the figure acceptable at all.
      adjustmentId,
      mutatesQuantity: clears,
      actorUid: options.actorUid,
      requestId: options.requestId,
    },
    // The shape `adjustStock` writes, field for field, for the reason the create
    // path gives: a unit cleared and a unit adjusted out are the same unit and
    // reconciliation reads one ledger.
    //
    // `adjustmentType` is `correction` because that is the only operator-facing
    // type that moves either way without claiming the units were damaged,
    // wasted or counted. What actually happened is carried by `sourceType`,
    // which is how `createProduct` distinguishes its opening balance from an
    // import's.
    ledgerData: !clears ? null : {
      tenantId: options.tenantId,
      productId: options.productId,
      sourceType: "product_retired",
      adjustmentType: "correction",
      quantityDelta: -options.previousQuantity,
      previousQuantity: options.previousQuantity,
      quantityAfter: 0,
      reason: RETIRE_CLOSING_STOCK_REASON,
      actorUid: options.actorUid,
      requestId: options.requestId,
    },
  };
}

export const setProductRetired = onCall<
  SetProductRetiredRequest,
  Promise<SetProductRetiredResponse>
>(async (
  request: CallableRequest<SetProductRetiredRequest>
): Promise<SetProductRetiredResponse> => {
  const data = requireObject(request.data);
  const tenantId = requireDocumentId(data.tenantId, "tenantId");
  const productId = requireDocumentId(data.productId, "productId");
  const requestId = requireRequestId(data.requestId);
  if (typeof data.retired !== "boolean") {
    throw new HttpsError("invalid-argument", "retired must be true or false.");
  }
  const retired = data.retired;
  // When the product was taken out (or put back) on the device. Outside the
  // fingerprint, as `adjustStock` keeps it.
  const occurredAt = requireDeviceInstant(data.occurredAtMs, "occurredAtMs");
  const db = getFirestore();

  const actor = await requireTenantMember(db, request, tenantId, PRODUCT_RETIRE_ROLES);

  return runIdempotentFirestoreTransaction(db, {
    actorUid: actor.uid,
    operation: "setProductRetired",
    tenantId,
    requestId,
    input: {productId, retired},
  }, async (transaction) => {
    const currentActor = await requireTenantMember(
      db,
      request,
      tenantId,
      PRODUCT_RETIRE_ROLES,
      transaction
    );
    const tenantRef = db.collection("tenants").doc(tenantId);
    const productRef = tenantRef.collection("products").doc(productId);
    const snapshot = await transaction.get(productRef);
    if (!snapshot.exists) {
      throw new HttpsError("not-found", "The product does not exist in this tenant.");
    }

    const storedQuantity = snapshot.get("quantity");
    if (!Number.isSafeInteger(storedQuantity)) {
      throw new HttpsError(
        "failed-precondition",
        "This product's stock quantity is not a whole number, so it cannot be " +
        "cleared. It needs reconciliation before it can be retired."
      );
    }
    const plan = planProductRetire({
      tenantId,
      productId,
      actorUid: currentActor.uid,
      requestId,
      retired,
      previousQuantity: storedQuantity as number,
    });

    transaction.update(productRef, {
      retired,
      // Written on both, so a restored product does not keep claiming the
      // moment it was taken out.
      retiredAt: retired ? occurredAt : null,
      ...(plan.clears ? {quantity: plan.quantity} : {}),
      updatedAt: FieldValue.serverTimestamp(),
    });

    transaction.create(tenantRef.collection("audit_logs").doc(plan.auditId), {
      ...plan.auditData,
      createdAt: FieldValue.serverTimestamp(),
    });

    if (plan.ledgerData !== null && plan.adjustmentId !== null) {
      const immutableRecord = {
        ...plan.ledgerData,
        occurredAt,
        createdAt: FieldValue.serverTimestamp(),
      };
      transaction.create(
        tenantRef.collection("stock_adjustments").doc(plan.adjustmentId),
        immutableRecord
      );
      transaction.create(
        productRef.collection("stock_movements").doc(plan.adjustmentId),
        {
          ...immutableRecord,
          movementId: plan.adjustmentId,
          recordedAt: FieldValue.serverTimestamp(),
        }
      );
    }

    return {
      productId,
      retired,
      adjustmentId: plan.adjustmentId,
      previousQuantity: plan.previousQuantity,
      quantity: plan.quantity,
    };
  });
});
