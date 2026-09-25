import {createHash} from "node:crypto";
import {FieldValue, getFirestore} from "firebase-admin/firestore";
import {CallableRequest, HttpsError, onCall} from "firebase-functions/v2/https";
import {requireTenantMember} from "../core/authorization";
import {runIdempotentFirestoreTransaction} from "../core/idempotency";
import {
  requireDocumentId,
  requireObject,
  optionalString,
} from "../core/validation";
import {addStockQuantity, requireStoredQuantity} from "./domain";
import {BUSINESS_DATE_PATTERN, MAXIMUM_STOCK_TAKE_LINES} from "./stockTake";

/**
 * Turns a count that has been reviewed into the movements that correct the books.
 *
 * **This is the act `submitStockTake` deliberately is not.** Counting records an
 * observation and moves nothing; this moves stock, so it is back on
 * `adjustStock`'s owner/admin/manager set. A cashier may count a shortfall and
 * may not make it disappear.
 *
 * **It applies the variance as a delta, and does not set the quantity to what
 * was counted.** That distinction is the one thing in this file that must not be
 * "corrected" by a later reader. The variance is a fact about the moment of
 * counting: the books said forty, the shelf held thirty-eight, so two units are
 * unaccounted for. Sales made between the count and the approval are separately
 * recorded real movements. Adding the delta composes both correctly; setting the
 * quantity to thirty-eight would silently undo every sale in between. It follows
 * that `quantityAfter` will not equal `counted` when trading happened in the gap
 * - **that is correct, not a bug.**
 *
 * **Paging is by cursor and idempotent twice over.** A page is keyed on the
 * cursor it started from, so a lost response replays off the idempotency record;
 * and independently of that, a line already carrying `appliedAdjustmentId` is
 * skipped, so even a caller that loses its place entirely cannot move the same
 * units twice.
 */
interface ApplyStockTakeRequest {
  tenantId?: unknown;
  takeId?: unknown;
  cursor?: unknown;
}

export interface ApplyStockTakeResponse {
  takeId: string;

  /** Lines corrected by this page. */
  applied: number;

  /** Pass back to continue, or null when the count is fully applied. */
  nextCursor: string | null;
  status: "submitted" | "applied";
}

/** Why the correcting ledger entry exists, in the words the stock ledger records. */
export const STOCK_TAKE_REASON =
  "Corrected against a counted stock take.";

const STOCK_TAKE_APPLY_ROLES = ["owner", "admin", "manager"] as const;

/**
 * How many lines one page corrects.
 *
 * `submitStockTake`'s bound, for its reason: one document per line inside one
 * transaction. Apply writes three documents per line rather than one, so it
 * takes a third of it.
 */
export const MAXIMUM_STOCK_TAKE_APPLY_LINES = Math.floor(
  MAXIMUM_STOCK_TAKE_LINES / 3
);

/** The `stock_adjustments` and `stock_movements` ID one corrected line writes at. */
export function stockTakeAdjustmentId(
  takeId: string,
  productId: string
): string {
  // Derived from the take and the product together, so it is stable across
  // every replay of this apply and distinct from the same product's correction
  // in any other count. Mirrors `productCreateAdjustmentId`.
  const digest = createHash("sha256")
    .update(`${takeId}\0${productId}`)
    .digest("hex");
  return `sa_st_${digest.slice(0, 40)}`;
}

/** What correcting one line writes, without its timestamps. */
export interface StockTakeLineCorrection {
  productId: string;
  adjustmentId: string;
  previousQuantity: number;
  quantity: number;
  quantityDelta: number;
  ledgerData: Record<string, unknown>;
}

/**
 * Decides what correcting one counted line writes.
 *
 * Pure, as `planProductCreate` and `planProductRetire` are, so the arithmetic
 * that decides where a shop's stock lands is testable without a database.
 */
export function planStockTakeLine(options: {
  tenantId: string;
  takeId: string;
  productId: string;
  actorUid: string;

  /**
   * The trading day the count was taken for, carried from the take.
   *
   * **A count is about a day, not a moment, which is why this carries a
   * business date where `adjustStock` deliberately does not.** A manager
   * writing off six broken bottles at three in the afternoon is describing that
   * instant, and a timestamp says it completely. A count says "this is what the
   * shelf held at the end of Tuesday", and the correction it produces belongs
   * to Tuesday however many days later somebody got round to approving it.
   *
   * Without it, a shortfall found on Tuesday lands on the day of approval:
   * Tuesday reads clean and some later day reads short by units that never
   * moved on it. The take has always recorded this; it was simply not carried
   * the one step further onto the records that correct the books.
   */
  businessDate: string;

  /** The difference the count recorded, at the moment it was counted. */
  variance: number;

  /** What the product holds now, which may have moved since. */
  storedQuantity: number;
}): StockTakeLineCorrection {
  const quantity = addStockQuantity(options.storedQuantity, options.variance);
  const adjustmentId = stockTakeAdjustmentId(options.takeId, options.productId);
  return {
    productId: options.productId,
    adjustmentId,
    previousQuantity: options.storedQuantity,
    quantity,
    quantityDelta: options.variance,
    // The shape `adjustStock` writes, field for field, because a unit counted
    // off and a unit adjusted off are the same unit and reconciliation reads
    // one ledger.
    //
    // `inventory_count` rather than `correction`: the type already exists, it
    // is exactly what this is, and `assertAdjustmentDirection` leaves it free
    // to move either way - a count may find a surplus as readily as a shortfall.
    ledgerData: {
      tenantId: options.tenantId,
      productId: options.productId,
      sourceType: "stock_take",
      adjustmentType: "inventory_count",
      quantityDelta: options.variance,
      previousQuantity: options.storedQuantity,
      quantityAfter: quantity,
      reason: STOCK_TAKE_REASON,
      actorUid: options.actorUid,
      requestId: options.takeId,
      takeId: options.takeId,
      // The day the count claimed, never the day this ran - see the field note
      // above. They differ by however long the count waited to be approved.
      businessDate: options.businessDate,
    },
  };
}

export const applyStockTake = onCall<
  ApplyStockTakeRequest,
  Promise<ApplyStockTakeResponse>
>(async (
  request: CallableRequest<ApplyStockTakeRequest>
): Promise<ApplyStockTakeResponse> => {
  const data = requireObject(request.data);
  const tenantId = requireDocumentId(data.tenantId, "tenantId");
  const takeId = requireDocumentId(data.takeId, "takeId");
  const cursor = optionalString(data.cursor, "cursor", {maxLength: 200});
  const db = getFirestore();

  const actor = await requireTenantMember(
    db,
    request,
    tenantId,
    STOCK_TAKE_APPLY_ROLES
  );

  const tenantRef = db.collection("tenants").doc(tenantId);
  const takeRef = tenantRef.collection("stock_takes").doc(takeId);
  const linesRef = takeRef.collection("lines");

  // Read the page outside the transaction: a query cannot be issued inside one,
  // and every document it names is re-read inside before anything is written.
  let query = linesRef
    .where("needsApply", "==", true)
    .orderBy("__name__")
    .limit(MAXIMUM_STOCK_TAKE_APPLY_LINES);
  if (cursor !== undefined) query = query.startAfter(cursor);
  const pageSnapshot = await query.get();
  const candidateIds = pageSnapshot.docs.map((doc) => doc.id);
  const nextCursor = candidateIds.length === MAXIMUM_STOCK_TAKE_APPLY_LINES ?
    candidateIds[candidateIds.length - 1] :
    null;

  return runIdempotentFirestoreTransaction(db, {
    actorUid: actor.uid,
    operation: "applyStockTake",
    tenantId,
    requestId: `${takeId}:apply:${cursor ?? "start"}`,
    input: {candidateIds},
  }, async (transaction) => {
    const currentActor = await requireTenantMember(
      db,
      request,
      tenantId,
      STOCK_TAKE_APPLY_ROLES,
      transaction
    );
    const takeSnapshot = await transaction.get(takeRef);
    if (!takeSnapshot.exists) {
      throw new HttpsError("not-found", "That count does not exist.");
    }
    const status = takeSnapshot.get("status");
    if (status === "submitting") {
      throw new HttpsError(
        "failed-precondition",
        "This count has not finished arriving yet, so applying it would " +
        "correct only the part of it that has."
      );
    }
    if (status !== "submitted" && status !== "applied") {
      throw new HttpsError("failed-precondition", "This count cannot be applied.");
    }

    // **Read here, not derived here.** The trading day belongs to the count, and
    // the count recorded it when somebody stood at the shelf; deriving it now
    // would date every correction to the approval instead, which is the whole
    // defect this closes. `submitStockTake` writes it into the header on every
    // page, so a take that reached `submitted` has one.
    const businessDate = takeSnapshot.get("businessDate");
    if (
      typeof businessDate !== "string" ||
      !BUSINESS_DATE_PATTERN.test(businessDate)
    ) {
      throw new HttpsError(
        "failed-precondition",
        "This count does not name the trading day it was taken for, so the " +
        "corrections it would write could not be attributed to one."
      );
    }

    const lineRefs = candidateIds.map((id) => linesRef.doc(id));
    const productRefs = candidateIds.map((id) =>
      tenantRef.collection("products").doc(id));
    const snapshots = candidateIds.length === 0 ?
      [] :
      await transaction.getAll(...lineRefs, ...productRefs);
    const lineSnapshots = snapshots.slice(0, candidateIds.length);
    const productSnapshots = snapshots.slice(candidateIds.length);

    let applied = 0;
    for (let index = 0; index < candidateIds.length; index++) {
      const lineSnapshot = lineSnapshots[index];
      const productSnapshot = productSnapshots[index];
      if (!lineSnapshot.exists) continue;
      // **Already corrected, so skipped rather than corrected again.** This is
      // the guard that holds even when a caller loses its place in the paging
      // entirely, which the idempotency record alone would not cover.
      if (lineSnapshot.get("appliedAdjustmentId")) continue;
      const variance = lineSnapshot.get("variance");
      if (!Number.isSafeInteger(variance) || variance === 0) continue;
      if (!productSnapshot.exists) {
        // The product was counted but this business does not hold it - the
        // unmatched case `submitStockTake` records rather than refuses. There
        // is nothing to correct.
        continue;
      }
      const plan = planStockTakeLine({
        tenantId,
        takeId,
        productId: candidateIds[index],
        actorUid: currentActor.uid,
        businessDate,
        variance: variance as number,
        storedQuantity: requireStoredQuantity(productSnapshot.get("quantity")),
      });

      const immutableRecord = {
        ...plan.ledgerData,
        // Applying a count is only ever done online, and the stock changes
        // when it is applied rather than when it was counted. Every adjustment
        // carries this field, so the feed can be ordered by it.
        occurredAt: FieldValue.serverTimestamp(),
        createdAt: FieldValue.serverTimestamp(),
      };
      transaction.update(productRefs[index], {
        quantity: plan.quantity,
        updatedAt: FieldValue.serverTimestamp(),
      });
      transaction.create(
        tenantRef.collection("stock_adjustments").doc(plan.adjustmentId),
        immutableRecord
      );
      transaction.create(
        productRefs[index].collection("stock_movements").doc(plan.adjustmentId),
        {
          ...immutableRecord,
          movementId: plan.adjustmentId,
          recordedAt: FieldValue.serverTimestamp(),
        }
      );
      transaction.update(lineRefs[index], {
        appliedAdjustmentId: plan.adjustmentId,
        appliedQuantityAfter: plan.quantity,
        appliedAt: FieldValue.serverTimestamp(),
      });
      applied++;
    }

    // The last page is the one that found no further page to fetch, so it is
    // also the one that closes the count.
    if (nextCursor === null) {
      transaction.update(takeRef, {
        status: "applied",
        appliedAt: FieldValue.serverTimestamp(),
        appliedBy: currentActor.uid,
        appliedMovementCount: FieldValue.increment(applied),
        updatedAt: FieldValue.serverTimestamp(),
      });
    } else if (applied > 0) {
      transaction.update(takeRef, {
        appliedMovementCount: FieldValue.increment(applied),
        updatedAt: FieldValue.serverTimestamp(),
      });
    }

    return {
      takeId,
      applied,
      nextCursor,
      status: nextCursor === null ?
        ("applied" as const) :
        ("submitted" as const),
    };
  });
});
