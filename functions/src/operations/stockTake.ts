import {FieldValue, getFirestore} from "firebase-admin/firestore";
import {CallableRequest, HttpsError, onCall} from "firebase-functions/v2/https";
import {requireTenantMember} from "../core/authorization";
import {runIdempotentFirestoreTransaction} from "../core/idempotency";
import {
  requireDocumentId,
  requireObject,
  requireString,
} from "../core/validation";
import {
  MAXIMUM_IMPORT_OPENING_STOCK,
  MAXIMUM_PRODUCT_IMPORT_ROWS,
} from "./productImport";

/**
 * Records what somebody counted on the shelf, and what the books said at the time.
 *
 * **Counting and correcting are two acts, and this is only the first.** Nothing
 * here touches `products.quantity` and nothing here writes a movement: a stock
 * take is an *observation*, and turning an observation into a correction is a
 * separate decision made by somebody else. That separation is the control. If the
 * person counting could also move the stock, a shortfall could be counted away by
 * whoever caused it - so this callable is open to every active member, including
 * a cashier, while applying a count stays on `adjustStock`'s owner/admin/manager
 * set.
 *
 * **The counter never sees the expected figure.** That is the whole point of a
 * blind count: showing somebody the target tells them what to write. `expected`
 * is read here, on the server, at submit - never sent to the device and never
 * rendered. What the device *does* send is `seenQuantity`, the figure its own
 * catalog cache held at the moment of counting. It is recorded and never shown,
 * so a count entered at ten and submitted at two can be read against the window
 * it was taken in, without the counter ever having been given a number to match.
 *
 * **Paging is safe here without a durable plan, and that is deliberate.** The
 * import path mints a request ID per page when it plans, holds the plan in the
 * caller's memory, and so cannot resume a partly-sent batch without re-planning
 * and re-sending work that already landed. Nothing is minted here: `takeId` is
 * generated once and lives in the device's durable draft, the page index is
 * positional, and **a line's document ID is the product ID**. Any page may be
 * re-sent at any time, in any order, and lands on the same documents with the
 * same values.
 *
 * The split below is `productCreate.ts`'s: everything that decides is a pure
 * function this file exports, and the callable is the authorization, the reads
 * and the transaction around it.
 */
interface SubmitStockTakeRequest {
  tenantId?: unknown;
  takeId?: unknown;
  businessDate?: unknown;
  scope?: unknown;
  productsInScope?: unknown;
  page?: unknown;
  isFinalPage?: unknown;
  lines?: unknown;
}

export type StockTakeStatus = "submitting" | "submitted" | "applied";

export interface SubmitStockTakeResponse {
  takeId: string;
  page: number;
  linesWritten: number;
  status: StockTakeStatus;
}

/** What a count covered: the whole catalog, or one category of it. */
export type StockTakeScope =
  | {kind: "all"}
  | {kind: "category"; categoryId: string};

/**
 * The trading day a count is taken for, as the whole system writes one.
 *
 * Exported because `applyStockTake` validates the same field when it carries it
 * onto the ledger: the day a correction is attributed to and the day the count
 * claimed must be the same shape, or one of them is not a business date.
 */
export const BUSINESS_DATE_PATTERN = /^[0-9]{4}-[0-9]{2}-[0-9]{2}$/;

/**
 * The page bound, which is `importProducts`' own.
 *
 * Reused rather than redeclared for the reason `productImport.ts` gives about
 * the opening-stock bound: a limit one path enforces and another does not is a
 * way in rather than a rule. Both paths write one document per row inside one
 * transaction, so they are bounded by the same thing.
 */
export const MAXIMUM_STOCK_TAKE_LINES = MAXIMUM_PRODUCT_IMPORT_ROWS;

/** One counted product, as the device recorded it. */
export interface StockTakeLineInput {
  productId: string;

  /** Units on the shelf. Never negative - a shelf cannot hold less than none. */
  counted: number;

  /**
   * What this device's catalog cache held when the number was typed.
   *
   * Null when the device had no figure for it. This is *not* shown to anybody
   * counting; it exists so the gap between counting and submitting is legible.
   */
  seenQuantity: number | null;

  /** When the number was typed, by the counting device's clock. */
  countedAt: string;
}

/** One line document this page writes, and whether it moves the take's counters. */
export interface StockTakeLineWrite {
  productId: string;
  data: Record<string, unknown>;

  /**
   * False for a line already on the server.
   *
   * A page re-sent under a fresh request ID rewrites its lines with the same
   * values, and the totals on the take must not move for them - so a line that
   * already exists is written again and counted once.
   */
  counts: boolean;
}

/** Everything one page of a submission writes, without its timestamps. */
export interface StockTakePagePlan {
  lines: StockTakeLineWrite[];

  /** Merged onto the take by every page, because every page carries it. */
  header: Record<string, unknown>;
  countedLineDelta: number;
  varianceLineDelta: number;
  absoluteVarianceDelta: number;

  /** Lines whose product this business does not hold. See `planStockTakePage`. */
  unmatchedLineDelta: number;

  /** Whether this page finishes the take. */
  completes: boolean;
}

/**
 * Decides what one page of a submission writes.
 *
 * **A line naming a product the server does not hold is recorded, not refused**,
 * and it is worth saying why. A member can add a product with no connection and
 * then count it in the same session; the create and this page sit in the outbox
 * under different target paths, and the drain runs those concurrently - so the
 * count can arrive first. `not-found` is a permanently-rejected code, so refusing
 * would throw the count away for good. Instead the line keeps what was counted,
 * records `expected` and `variance` as null, and says the product was not
 * matched. It contributes nothing to the variance totals, and management can see
 * it plainly. This is the same race `createProduct` documents for a category that
 * has not landed yet.
 */
export function planStockTakePage(options: {
  tenantId: string;
  takeId: string;
  counterUid: string;
  businessDate: string;
  scope: StockTakeScope;
  productsInScope: number;
  page: number;
  isFinalPage: boolean;
  lines: readonly StockTakeLineInput[];

  /** Quantity per product, or null where this business holds no such product. */
  storedQuantities: ReadonlyMap<string, number | null>;

  /** Product IDs this take already has a line for. */
  existingLineIds: ReadonlySet<string>;
}): StockTakePagePlan {
  const lines: StockTakeLineWrite[] = [];
  let countedLineDelta = 0;
  let varianceLineDelta = 0;
  let absoluteVarianceDelta = 0;
  let unmatchedLineDelta = 0;

  for (const line of options.lines) {
    const stored = options.storedQuantities.get(line.productId) ?? null;
    const matched = stored !== null;
    const variance = matched ? line.counted - stored : null;
    const counts = !options.existingLineIds.has(line.productId);

    if (counts) {
      countedLineDelta += 1;
      if (!matched) unmatchedLineDelta += 1;
      if (variance !== null && variance !== 0) {
        varianceLineDelta += 1;
        absoluteVarianceDelta += Math.abs(variance);
      }
    }

    lines.push({
      productId: line.productId,
      counts,
      data: {
        tenantId: options.tenantId,
        takeId: options.takeId,
        productId: line.productId,
        counted: line.counted,
        // Recorded, never rendered. See this file's header.
        seenQuantity: line.seenQuantity,
        countedAt: line.countedAt,
        // The server's figure at the moment of submission, and the difference
        // from it. Null together, and only when the product was not matched.
        expected: stored,
        variance,
        matched,
        // **What `applyStockTake` queries by.** A line that agrees with the
        // books moves nothing, and one whose product was not matched has
        // nothing to move it against, so neither is ever applied. Storing the
        // answer rather than deriving it keeps the apply query to one equality
        // filter, which Firestore serves from its automatic index.
        //
        // `appliedAdjustmentId` is deliberately **not** written here. Every page
        // is a merge, so writing it as null would let a page re-sent from a
        // stale outbox clear the marker apply had just set and let the same
        // units move twice. Absence is what "not applied yet" looks like.
        needsApply: variance !== null && variance !== 0,
        counterUid: options.counterUid,
        page: options.page,
      },
    });
  }

  return {
    lines,
    countedLineDelta,
    varianceLineDelta,
    absoluteVarianceDelta,
    unmatchedLineDelta,
    completes: options.isFinalPage,
    // Every page carries the same header and merges it, so a take is complete
    // whichever page reaches the server first. Ordering is a property of the
    // outbox, not something this callable is entitled to assume.
    header: {
      tenantId: options.tenantId,
      counterUid: options.counterUid,
      businessDate: options.businessDate,
      scope: options.scope,
      productsInScope: options.productsInScope,
    },
  };
}

/** Reads the scope a count covered. */
export function readStockTakeScope(value: unknown): StockTakeScope {
  const scope = requireObject(value, "scope");
  const kind = requireString(scope.kind, "scope.kind", {maxLength: 16});
  if (kind === "all") return {kind: "all"};
  if (kind === "category") {
    return {
      kind: "category",
      categoryId: requireDocumentId(scope.categoryId, "scope.categoryId"),
    };
  }
  throw new HttpsError("invalid-argument", "scope.kind must be all or category.");
}

/** Reads one counted line, refusing anything a shelf cannot have held. */
export function readStockTakeLine(value: unknown, index: number): StockTakeLineInput {
  const line = requireObject(value, `lines[${index}]`);
  const productId = requireDocumentId(line.productId, `lines[${index}].productId`);
  const counted = line.counted;
  if (
    !Number.isSafeInteger(counted) ||
    (counted as number) < 0 ||
    (counted as number) > MAXIMUM_IMPORT_OPENING_STOCK
  ) {
    throw new HttpsError(
      "invalid-argument",
      `lines[${index}].counted must be a whole number between 0 and ` +
      `${MAXIMUM_IMPORT_OPENING_STOCK}.`
    );
  }
  // A stored quantity may be negative - a sale is never blocked by a stock count
  // - so what the device saw may be too. What was counted may not be.
  const seen = line.seenQuantity;
  if (seen !== null && seen !== undefined && !Number.isSafeInteger(seen)) {
    throw new HttpsError(
      "invalid-argument",
      `lines[${index}].seenQuantity must be a whole number or null.`
    );
  }
  return {
    productId,
    counted: counted as number,
    seenQuantity: seen === undefined || seen === null ? null : (seen as number),
    countedAt: requireString(line.countedAt, `lines[${index}].countedAt`, {maxLength: 40}),
  };
}

/** Reads the lines of one page, refusing a page longer than one transaction. */
export function readStockTakeLines(value: unknown): StockTakeLineInput[] {
  if (!Array.isArray(value) || value.length === 0) {
    throw new HttpsError("invalid-argument", "lines must be a non-empty array.");
  }
  if (value.length > MAXIMUM_STOCK_TAKE_LINES) {
    throw new HttpsError(
      "invalid-argument",
      `A page carries at most ${MAXIMUM_STOCK_TAKE_LINES} lines. Send the rest ` +
      "as a further page."
    );
  }
  const lines = value.map(readStockTakeLine);
  const seen = new Set<string>();
  for (const line of lines) {
    if (seen.has(line.productId)) {
      throw new HttpsError("invalid-argument", "A page names the same product twice.");
    }
    seen.add(line.productId);
  }
  return lines;
}

export const submitStockTake = onCall<
  SubmitStockTakeRequest,
  Promise<SubmitStockTakeResponse>
>(async (
  request: CallableRequest<SubmitStockTakeRequest>
): Promise<SubmitStockTakeResponse> => {
  const data = requireObject(request.data);
  const tenantId = requireDocumentId(data.tenantId, "tenantId");
  const takeId = requireDocumentId(data.takeId, "takeId");
  const businessDate = requireString(data.businessDate, "businessDate", {maxLength: 10});
  if (!BUSINESS_DATE_PATTERN.test(businessDate)) {
    throw new HttpsError("invalid-argument", "businessDate must be YYYY-MM-DD.");
  }
  const scope = readStockTakeScope(data.scope);
  const page = data.page;
  if (!Number.isInteger(page) || (page as number) < 0 || (page as number) > 10000) {
    throw new HttpsError("invalid-argument", "page must be a whole number.");
  }
  if (typeof data.isFinalPage !== "boolean") {
    throw new HttpsError("invalid-argument", "isFinalPage must be true or false.");
  }
  // Captured, because the narrowing above does not survive into the transaction
  // callback below.
  const isFinalPage: boolean = data.isFinalPage;
  const productsInScope = data.productsInScope;
  if (!Number.isSafeInteger(productsInScope) || (productsInScope as number) < 0) {
    throw new HttpsError("invalid-argument", "productsInScope must be a whole number.");
  }
  const lines = readStockTakeLines(data.lines);
  const db = getFirestore();

  // **Every active member, which is the widest set in the inventory surface.**
  // Counting is the one inventory act a cashier performs, and it moves no stock.
  const actor = await requireTenantMember(db, request, tenantId);

  return runIdempotentFirestoreTransaction(db, {
    actorUid: actor.uid,
    operation: "submitStockTake",
    tenantId,
    // Positional, so a page is replayable without anything having been minted
    // for it. See this file's header.
    requestId: `${takeId}:${page}`,
    input: {
      lines: lines.map((line) => ({
        productId: line.productId,
        counted: line.counted,
      })),
      isFinalPage,
    },
  }, async (transaction) => {
    const currentActor = await requireTenantMember(db, request, tenantId);
    const tenantRef = db.collection("tenants").doc(tenantId);
    const takeRef = tenantRef.collection("stock_takes").doc(takeId);
    const lineRefs = lines.map((line) => takeRef.collection("lines").doc(line.productId));
    const productRefs = lines.map(
      (line) => tenantRef.collection("products").doc(line.productId)
    );

    const [takeSnapshot, ...rest] = await transaction.getAll(
      takeRef,
      ...lineRefs,
      ...productRefs
    );
    const lineSnapshots = rest.slice(0, lineRefs.length);
    const productSnapshots = rest.slice(lineRefs.length);

    // **A take belongs to the person who opened it.** Without this, any member
    // could add lines to a colleague's count, which would make the counter named
    // on it a fiction.
    if (takeSnapshot.exists && takeSnapshot.get("counterUid") !== currentActor.uid) {
      throw new HttpsError(
        "permission-denied",
        "This count was opened by somebody else."
      );
    }
    if (takeSnapshot.exists && takeSnapshot.get("status") === "applied") {
      throw new HttpsError(
        "failed-precondition",
        "This count has already been applied to the stock, so it can no longer " +
        "be added to."
      );
    }

    const storedQuantities = new Map<string, number | null>();
    lines.forEach((line, index) => {
      const snapshot = productSnapshots[index];
      const quantity = snapshot.exists ? snapshot.get("quantity") : undefined;
      storedQuantities.set(
        line.productId,
        Number.isSafeInteger(quantity) ? (quantity as number) : null
      );
    });
    const existingLineIds = new Set<string>(
      lines
        .filter((_, index) => lineSnapshots[index].exists)
        .map((line) => line.productId)
    );

    const plan = planStockTakePage({
      tenantId,
      takeId,
      counterUid: currentActor.uid,
      businessDate,
      scope,
      productsInScope: productsInScope as number,
      page: page as number,
      isFinalPage,
      lines,
      storedQuantities,
      existingLineIds,
    });

    const status: StockTakeStatus = plan.completes ? "submitted" : "submitting";
    transaction.set(takeRef, {
      ...plan.header,
      countedLineCount: FieldValue.increment(plan.countedLineDelta),
      varianceLineCount: FieldValue.increment(plan.varianceLineDelta),
      absoluteVarianceUnits: FieldValue.increment(plan.absoluteVarianceDelta),
      unmatchedLineCount: FieldValue.increment(plan.unmatchedLineDelta),
      // A take that exists stays at whatever it reached: only the final page
      // promotes it, and nothing walks it back to `submitting`.
      ...(plan.completes || !takeSnapshot.exists ? {status} : {}),
      ...(plan.completes ? {submittedAt: FieldValue.serverTimestamp()} : {}),
      ...(takeSnapshot.exists ? {} : {createdAt: FieldValue.serverTimestamp()}),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});

    plan.lines.forEach((line, index) => {
      transaction.set(lineRefs[index], {
        ...line.data,
        recordedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    });

    return {
      takeId,
      page: page as number,
      linesWritten: plan.lines.length,
      status: takeSnapshot.exists && !plan.completes ?
        ((takeSnapshot.get("status") as StockTakeStatus) ?? status) :
        status,
    };
  });
});
