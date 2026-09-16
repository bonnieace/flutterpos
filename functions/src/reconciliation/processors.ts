import {
  DocumentData,
  DocumentReference,
  DocumentSnapshot,
  FieldPath,
  FieldValue,
  Firestore,
  QueryDocumentSnapshot,
  Timestamp,
  Transaction,
} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";
import {
  aggregateDailySales,
  digest,
  shiftAnomalyId,
  shiftExpectationId,
  shiftTenderAnomalyId,
  stockCheckpointHash,
  stockComparisonOutcome,
  trailingIsoDates,
  TENDER_DECLARATION_REQUIRED_FROM,
} from "./model";
import {ClaimedReconciliationJob} from "./jobs";
import {SaleLike, moneyToMinorUnits, minorUnitsToMoney} from "../operations/domain";

const DAILY_METRICS_PAGE_SIZE = 5;
const DAILY_SALES_LIMIT = 5_000;
/**
 * How many shift expectations one business date may already hold.
 *
 * Not an arbitrary figure: `regenerateDailyMetric` republishes a day in one
 * transaction, and the widest that transaction can get is this many stale
 * expectations deleted plus `aggregateDailySales`'s own 200-shift bound written,
 * plus the daily metric and the dirty-day row - 402 writes against Firestore's
 * limit of 500. Raising either 200 moves that past the limit, and the day it does
 * every regeneration of a busy date starts failing rather than getting slower.
 */
const SHIFT_EXPECTATION_LIMIT = 200;
const PRODUCT_PAGE_SIZE = 25;
const MOVEMENT_PAGE_SIZE = 200;
const SHIFT_PAGE_SIZE = 50;

export interface MetricsPageResult {
  processed: number;
  hasMore: boolean;
}

export interface StockPageResult {
  processed: number;
  varianceCount: number;
  hasMore: boolean;
  productCursor?: string;
  pendingProductId?: string;
}

export interface ShiftPageResult {
  processed: number;
  varianceCount: number;
  /** Shifts whose declared takings disagree with what their sales derive. */
  tenderVarianceCount: number;
  hasMore: boolean;
}

/** What one verification found, so a page can count the two kinds apart. */
interface ShiftVerificationResult {
  salesVariance: boolean;
  tenderVariance: boolean;
}

interface ProductResult {
  completed: boolean;
  variance: boolean;
}

function nonNegativeInteger(value: unknown): number {
  return Number.isSafeInteger(value) && (value as number) >= 0 ? value as number : 0;
}

function safeInteger(value: unknown): number | undefined {
  return Number.isSafeInteger(value) ? value as number : undefined;
}

function safeNonNegativeNumber(value: unknown): number | undefined {
  return typeof value === "number" && Number.isFinite(value) && value >= 0 ? value : undefined;
}

function dirtyRevision(value: unknown): number | undefined {
  return Number.isSafeInteger(value) && (value as number) >= 1 ? value as number : undefined;
}

function movementCursor(timestamp: Timestamp | undefined, documentId?: string): string {
  return timestamp && documentId ? `${timestamp.toMillis()}:${documentId}` : "baseline:none";
}

function validPreviousCheckpointPath(
  path: unknown,
  tenantId: string,
  productId: string
): path is string {
  if (typeof path !== "string") return false;
  const segments = path.split("/");
  return segments.length === 6 &&
    segments[0] === "tenants" && segments[1] === tenantId &&
    segments[2] === "stock_checkpoints" && segments[3].length > 0 &&
    segments[4] === "products" && segments[5] === productId;
}

async function assertCurrentLease(
  transaction: Transaction,
  db: Firestore,
  job: ClaimedReconciliationJob
): Promise<void> {
  const snapshot = await transaction.get(
    db.collection("tenants").doc(job.tenantId)
      .collection("reconciliation_jobs").doc(job.jobId)
  );
  if (
    !snapshot.exists || snapshot.get("status") !== "running" ||
    snapshot.get("generation") !== job.generation ||
    snapshot.get("revision") !== job.revision ||
    snapshot.get("leaseToken") !== job.leaseToken ||
    !(snapshot.get("leaseExpiresAt") instanceof Timestamp) ||
    (snapshot.get("leaseExpiresAt") as Timestamp).toMillis() <= Date.now()
  ) {
    throw new HttpsError("aborted", "The reconciliation processor lease is no longer current.");
  }
}

export async function initializeFullReconciliationWindow(
  db: Firestore,
  job: ClaimedReconciliationJob
): Promise<void> {
  const tenantRef = db.collection("tenants").doc(job.tenantId);
  const dates = trailingIsoDates(job.localDate, 35);
  await db.runTransaction(async (transaction) => {
    await assertCurrentLease(transaction, db, job);
    for (const businessDate of dates) {
      transaction.set(tenantRef.collection("reconciliation_dirty_days").doc(businessDate), {
        tenantId: job.tenantId,
        businessDate,
        status: "dirty",
        revision: FieldValue.increment(1),
        dirtyReason: job.source === "monthly" ? "monthly_full" : "manual_full",
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    }
  });
}

async function regenerateDailyMetric(
  db: Firestore,
  job: ClaimedReconciliationJob,
  dirtyDocument: QueryDocumentSnapshot<DocumentData>
): Promise<boolean> {
  const tenantId = job.tenantId;
  const businessDate = dirtyDocument.id;
  const revision = dirtyRevision(dirtyDocument.get("revision"));
  if (revision === undefined) {
    await dirtyDocument.ref.set({
      status: "quarantined",
      lastErrorCode: "invalid_dirty_revision",
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    return true;
  }
  const tenantRef = db.collection("tenants").doc(tenantId);
  const salesSnapshot = await tenantRef.collection("sales")
    .where("businessDate", "==", businessDate)
    .limit(DAILY_SALES_LIMIT + 1)
    .get();
  if (salesSnapshot.size > DAILY_SALES_LIMIT) {
    throw new HttpsError(
      "resource-exhausted",
      `Business date ${businessDate} exceeds the bounded daily aggregation limit.`
    );
  }
  const result = aggregateDailySales(
    businessDate,
    salesSnapshot.docs.map((document) => document.data() as SaleLike)
  );
  const previousExpectationSnapshot = await tenantRef.collection("shift_expectations")
    .where("businessDate", "==", businessDate)
    .limit(SHIFT_EXPECTATION_LIMIT + 1)
    .get();
  if (previousExpectationSnapshot.size > SHIFT_EXPECTATION_LIMIT) {
    throw new HttpsError(
      "resource-exhausted",
      `Business date ${businessDate} exceeds the bounded shift expectation limit.`
    );
  }
  const expectedIds = new Set(result.shifts.map((shift) =>
    shiftExpectationId(businessDate, shift.shiftId)
  ));
  const metricGeneration = digest([
    businessDate,
    `${revision}`,
    `${result.metrics.sales}`,
    `${result.metrics.transactions}`,
  ]);

  return db.runTransaction(async (transaction) => {
    const [currentDirty] = await Promise.all([
      transaction.get(dirtyDocument.ref),
      assertCurrentLease(transaction, db, job),
    ]);
    if (
      !currentDirty.exists || currentDirty.get("status") !== "dirty" ||
      currentDirty.get("revision") !== revision
    ) return false;
    transaction.set(tenantRef.collection("daily_metrics").doc(businessDate), {
      ...result.metrics,
      tenantId,
      metricGeneration,
      sourceDirtyRevision: revision,
      regeneratedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: false});
    for (const shift of result.shifts) {
      const id = shiftExpectationId(businessDate, shift.shiftId);
      // **The version tag is load-bearing, not decoration.** `shiftAnomalyId`
      // is keyed by this digest, so without a term that every pre-deploy
      // generation lacks, a regeneration that happened to reproduce an earlier
      // one would merge today's figures into an anomaly document written
      // against the old shape. The tender terms are the honest half: a split
      // that changed is a different expectation, and an in-flight verifier
      // holding the old generation is then correctly refused.
      const generation = digest([
        "shift-expectation-v2",
        metricGeneration,
        shift.shiftId,
        `${shift.sales}`,
        `${shift.transactions}`,
        `${shift.tenders.cashMinor}`,
        `${shift.tenders.mpesaMinor}`,
        `${shift.tenders.cardMinor}`,
        `${shift.tenders.unattributedMinor}`,
      ]);
      const {tenders, ...aggregate} = shift;
      transaction.set(tenantRef.collection("shift_expectations").doc(id), {
        ...aggregate,
        tenantId,
        expectationId: id,
        generation,
        metricGeneration,
        // Flattened rather than nested so the verifier can read one field at a
        // time and tell "this expectation predates the split" from "this shift
        // took nothing by that method".
        expectedCashMinor: tenders.cashMinor,
        expectedMpesaMinor: tenders.mpesaMinor,
        expectedCardMinor: tenders.cardMinor,
        expectedUnattributedMinor: tenders.unattributedMinor,
        tenderExpectationVersion: 1,
        needsVerification: true,
        updatedAt: FieldValue.serverTimestamp(),
        createdAt: FieldValue.serverTimestamp(),
      }, {merge: false});
    }
    for (const stale of previousExpectationSnapshot.docs) {
      if (!expectedIds.has(stale.id)) transaction.delete(stale.ref);
    }
    transaction.update(dirtyDocument.ref, {
      status: "clean",
      processedRevision: revision,
      metricGeneration,
      processedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return true;
  });
}

export async function processMetricsPage(
  db: Firestore,
  job: ClaimedReconciliationJob
): Promise<MetricsPageResult> {
  const dirtyCollection = db.collection("tenants").doc(job.tenantId)
    .collection("reconciliation_dirty_days");
  const snapshot = await dirtyCollection
    .where("status", "==", "dirty")
    .orderBy(FieldPath.documentId())
    .limit(DAILY_METRICS_PAGE_SIZE)
    .get();
  let processed = 0;
  for (const document of snapshot.docs) {
    if (await regenerateDailyMetric(db, job, document)) processed += 1;
  }
  const remainder = await dirtyCollection.where("status", "==", "dirty").limit(1).get();
  return {processed, hasMore: !remainder.empty};
}

function productStateRef(
  db: Firestore,
  tenantId: string,
  productId: string
): DocumentReference<DocumentData> {
  return db.collection("tenants").doc(tenantId)
    .collection("stock_reconciliation_state").doc(productId);
}

async function reconcileProduct(
  db: Firestore,
  job: ClaimedReconciliationJob,
  productId: string
): Promise<ProductResult> {
  const tenantRef = db.collection("tenants").doc(job.tenantId);
  const productRef = tenantRef.collection("products").doc(productId);
  const stateRef = productStateRef(db, job.tenantId, productId);
  const verificationParent = tenantRef.collection("stock_verifications").doc(job.jobId);
  const verificationRef = verificationParent.collection("products").doc(productId);

  return db.runTransaction(async (transaction) => {
    const [productSnapshot, stateSnapshot] = await transaction.getAll(productRef, stateRef);
    await assertCurrentLease(transaction, db, job);
    if (!productSnapshot.exists) return {completed: true, variance: false};
    const observedQuantity = safeInteger(productSnapshot.get("quantity"));
    if (observedQuantity === undefined) {
      transaction.set(verificationRef, {
        tenantId: job.tenantId,
        jobId: job.jobId,
        productId,
        status: "invalid_observed_quantity",
        mutatesStock: false,
        observedAt: FieldValue.serverTimestamp(),
      }, {merge: false});
      transaction.set(tenantRef.collection("reconciliation_anomalies")
        .doc(`product_quantity_${digest([productId])}`), {
        tenantId: job.tenantId,
        productId,
        anomalyType: "invalid_product_quantity",
        jobId: job.jobId,
        updatedAt: FieldValue.serverTimestamp(),
        createdAt: FieldValue.serverTimestamp(),
      }, {merge: true});
      return {completed: true, variance: true};
    }

    if (
      stateSnapshot.exists &&
      stateSnapshot.get("lastVerificationJobId") === job.jobId &&
      stateSnapshot.get("lastVerificationGeneration") === job.generation &&
      stateSnapshot.get("lastVerificationCompleted") === true
    ) {
      return {
        completed: true,
        variance: stateSnapshot.get("lastVerificationHadVariance") === true,
      };
    }

    // A sale creates the product decrement before its trigger-owned movement.
    // Deferring recently changed products avoids a false variance during that
    // short eventual-consistency window without ever mutating stock.
    const productUpdatedAt = productSnapshot.get("updatedAt");
    if (productUpdatedAt instanceof Timestamp) {
      const safeAfter = productUpdatedAt.toMillis() + 5 * 60 * 1000;
      if (safeAfter > Date.now()) {
        transaction.set(verificationParent, {
          tenantId: job.tenantId,
          jobId: job.jobId,
          checkpointKind: job.checkpointKind,
          checkpointKey: job.checkpointKey,
          mutatesStock: false,
          updatedAt: FieldValue.serverTimestamp(),
          createdAt: FieldValue.serverTimestamp(),
        }, {merge: true});
        transaction.set(verificationRef, {
          tenantId: job.tenantId,
          jobId: job.jobId,
          productId,
          status: "recent_write_deferred",
          safeAfter: Timestamp.fromMillis(safeAfter),
          mutatesStock: false,
          observedAt: FieldValue.serverTimestamp(),
        }, {merge: false});
        return {
          completed: true,
          variance: false,
        };
      }
    }

    const movements = productRef.collection("stock_movements");
    let expectedQuantity: number;
    let cursorTimestamp: Timestamp | undefined;
    let cursorId: string | undefined;
    let previousCheckpointHash: string | undefined;
    let previousCheckpointPath: string | undefined;
    let chainValid = true;
    let baselineStatus = "verified";
    const sameVerificationExecution = stateSnapshot.exists &&
      stateSnapshot.get("activeVerificationJobId") === job.jobId &&
      stateSnapshot.get("activeVerificationGeneration") === job.generation;
    const priorInvalidMovementCount = sameVerificationExecution ?
      nonNegativeInteger(stateSnapshot.get("activeInvalidMovementCount")) : 0;

    if (!stateSnapshot.exists) {
      const latest = await transaction.get(
        movements.orderBy("recordedAt", "desc")
          .orderBy(FieldPath.documentId(), "desc")
          .limit(1)
      );
      expectedQuantity = observedQuantity;
      cursorTimestamp = latest.docs[0]?.get("recordedAt") instanceof Timestamp ?
        latest.docs[0].get("recordedAt") as Timestamp : undefined;
      cursorId = latest.docs[0]?.id;
      baselineStatus = "baseline_established";
    } else {
      const storedExpected = safeInteger(stateSnapshot.get("expectedQuantity"));
      const storedTimestamp = stateSnapshot.get("lastMovementAt");
      const storedId = stateSnapshot.get("lastMovementId");
      const hasStoredTimestamp = storedTimestamp !== undefined;
      const hasStoredId = storedId !== undefined;
      if (
        storedExpected === undefined ||
        hasStoredTimestamp !== hasStoredId ||
        (storedTimestamp !== undefined && !(storedTimestamp instanceof Timestamp)) ||
        (storedId !== undefined && typeof storedId !== "string")
      ) {
        expectedQuantity = observedQuantity;
        baselineStatus = "baseline_reestablished_invalid_state";
        chainValid = false;
      } else {
        expectedQuantity = storedExpected;
        cursorTimestamp = storedTimestamp as Timestamp | undefined;
        cursorId = storedId as string | undefined;
      }
      previousCheckpointHash = typeof stateSnapshot.get("lastCheckpointHash") === "string" ?
        stateSnapshot.get("lastCheckpointHash") as string : undefined;
      previousCheckpointPath = validPreviousCheckpointPath(
        stateSnapshot.get("lastCheckpointPath"),
        job.tenantId,
        productId
      ) ? stateSnapshot.get("lastCheckpointPath") as string : undefined;
    }

    let movementQuery = movements.orderBy("recordedAt", "asc")
      .orderBy(FieldPath.documentId(), "asc");
    if (cursorTimestamp && cursorId) {
      movementQuery = movementQuery.startAfter(cursorTimestamp, cursorId);
    } else if (stateSnapshot.exists && baselineStatus === "verified") {
      // A valid baseline with no movement cursor starts at the beginning.
    } else if (baselineStatus.startsWith("baseline_reestablished")) {
      const latest = await transaction.get(
        movements.orderBy("recordedAt", "desc")
          .orderBy(FieldPath.documentId(), "desc")
          .limit(1)
      );
      cursorTimestamp = latest.docs[0]?.get("recordedAt") instanceof Timestamp ?
        latest.docs[0].get("recordedAt") as Timestamp : undefined;
      cursorId = latest.docs[0]?.id;
      movementQuery = movements.orderBy("recordedAt", "asc")
        .orderBy(FieldPath.documentId(), "asc")
        .startAfter(cursorTimestamp ?? Timestamp.fromMillis(0), cursorId ?? "");
    }

    let movementSnapshot;
    if (!stateSnapshot.exists) {
      movementSnapshot = undefined;
    } else {
      movementSnapshot = await transaction.get(movementQuery.limit(MOVEMENT_PAGE_SIZE + 1));
    }
    const movementDocuments = movementSnapshot?.docs.slice(0, MOVEMENT_PAGE_SIZE) ?? [];
    let invalidMovementCount = 0;
    for (const movement of movementDocuments) {
      const delta = safeInteger(movement.get("quantityDelta"));
      if (delta === undefined || !Number.isSafeInteger(expectedQuantity + delta)) {
        invalidMovementCount += 1;
      } else {
        expectedQuantity += delta;
      }
      const recordedAt = movement.get("recordedAt");
      if (recordedAt instanceof Timestamp) {
        cursorTimestamp = recordedAt;
        cursorId = movement.id;
      } else {
        invalidMovementCount += 1;
      }
    }
    const backlog = (movementSnapshot?.size ?? 0) > MOVEMENT_PAGE_SIZE;
    const cumulativeInvalidMovementCount = priorInvalidMovementCount + invalidMovementCount;
    const cursor = movementCursor(cursorTimestamp, cursorId);
    const variance = observedQuantity - expectedQuantity;

    if (backlog) {
      transaction.set(stateRef, {
        tenantId: job.tenantId,
        productId,
        expectedQuantity,
        observedQuantity,
        ...(cursorTimestamp && cursorId ? {
          lastMovementAt: cursorTimestamp,
          lastMovementId: cursorId,
        } : {}),
        status: "movement_backlog",
        lastVerificationJobId: job.jobId,
        lastVerificationGeneration: job.generation,
        lastVerificationCompleted: false,
        activeVerificationJobId: job.jobId,
        activeVerificationGeneration: job.generation,
        activeInvalidMovementCount: cumulativeInvalidMovementCount,
        invalidMovementCount: FieldValue.increment(invalidMovementCount),
        updatedAt: FieldValue.serverTimestamp(),
        createdAt: FieldValue.serverTimestamp(),
      }, {merge: true});
      transaction.set(verificationRef, {
        tenantId: job.tenantId,
        jobId: job.jobId,
        productId,
        status: "movement_backlog",
        expectedQuantity,
        observedQuantity,
        movementCursor: cursor,
        mutatesStock: false,
        updatedAt: FieldValue.serverTimestamp(),
      }, {merge: false});
      return {completed: false, variance: false};
    }

    if (previousCheckpointPath && previousCheckpointHash) {
      const previous = await transaction.get(db.doc(previousCheckpointPath));
      const previousExpected = previous.exists ?
        safeInteger(previous.get("expectedQuantity")) : undefined;
      const previousObserved = previous.exists ?
        safeInteger(previous.get("observedQuantity")) : undefined;
      const previousCursor = previous.exists ? previous.get("movementCursor") : undefined;
      const previousKey = previous.exists ? previous.get("checkpointKey") : undefined;
      const previousPriorHash = previous.exists ?
        previous.get("previousCheckpointHash") : undefined;
      const recomputedHash = previous.exists && previousExpected !== undefined &&
        previousObserved !== undefined && typeof previousCursor === "string" &&
        typeof previousKey === "string" ? stockCheckpointHash({
          tenantId: job.tenantId,
          productId,
          checkpointKey: previousKey,
          expectedQuantity: previousExpected,
          observedQuantity: previousObserved,
          movementCursor: previousCursor,
          ...(typeof previousPriorHash === "string" ? {
            previousCheckpointHash: previousPriorHash,
          } : {}),
        }) : undefined;
      chainValid = chainValid && previous.exists &&
        previous.get("checkpointHash") === previousCheckpointHash &&
        recomputedHash === previousCheckpointHash;
    } else if (previousCheckpointHash || previousCheckpointPath) {
      chainValid = false;
    }
    // An unreadable movement invalidates the chain's guarantee: no checkpoint can
    // claim to describe a ledger part of which could not be read. What is then
    // *reported* still has to name the movement rather than the chain, which is
    // `stockComparisonOutcome`'s job.
    if (cumulativeInvalidMovementCount > 0) chainValid = false;
    const shouldCheckpoint = job.checkpointKind !== "none";
    const checkpointHash = shouldCheckpoint ? stockCheckpointHash({
      tenantId: job.tenantId,
      productId,
      checkpointKey: job.checkpointKey,
      expectedQuantity,
      observedQuantity,
      movementCursor: cursor,
      previousCheckpointHash,
    }) : undefined;
    const checkpointRef = shouldCheckpoint ? tenantRef.collection("stock_checkpoints")
      .doc(job.checkpointKey).collection("products").doc(productId) : undefined;
    // One decision, in one place, over the four facts that settle it: what this
    // comparison concluded and whether it is a difference worth recording.
    const outcome = stockComparisonOutcome({
      baselineStatus,
      chainValid,
      invalidMovementCount: cumulativeInvalidMovementCount,
      variance,
    });
    const status = outcome.status;

    transaction.set(verificationParent, {
      tenantId: job.tenantId,
      jobId: job.jobId,
      checkpointKind: job.checkpointKind,
      checkpointKey: job.checkpointKey,
      mutatesStock: false,
      updatedAt: FieldValue.serverTimestamp(),
      createdAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    transaction.set(verificationRef, {
      tenantId: job.tenantId,
      jobId: job.jobId,
      productId,
      status,
      expectedQuantity,
      observedQuantity,
      variance,
      movementCursor: cursor,
      invalidMovementCount: cumulativeInvalidMovementCount,
      checkpointChainValid: chainValid,
      mutatesStock: false,
      observedAt: FieldValue.serverTimestamp(),
    }, {merge: false});
    if (checkpointRef && checkpointHash) {
      transaction.set(checkpointRef.parent.parent as DocumentReference<DocumentData>, {
        tenantId: job.tenantId,
        checkpointKey: job.checkpointKey,
        checkpointKind: job.checkpointKind,
        jobId: job.jobId,
        mutatesStock: false,
        updatedAt: FieldValue.serverTimestamp(),
        createdAt: FieldValue.serverTimestamp(),
      }, {merge: true});
      transaction.set(checkpointRef, {
        tenantId: job.tenantId,
        productId,
        checkpointKey: job.checkpointKey,
        checkpointKind: job.checkpointKind,
        expectedQuantity,
        observedQuantity,
        variance,
        movementCursor: cursor,
        previousCheckpointHash: previousCheckpointHash ?? null,
        previousCheckpointPath: previousCheckpointPath ?? null,
        checkpointHash,
        checkpointChainValid: chainValid,
        mutatesStock: false,
        createdAt: FieldValue.serverTimestamp(),
      }, {merge: false});
    }
    transaction.set(stateRef, {
      tenantId: job.tenantId,
      productId,
      expectedQuantity,
      observedQuantity,
      lastVariance: variance,
      ...(cursorTimestamp && cursorId ? {
        lastMovementAt: cursorTimestamp,
        lastMovementId: cursorId,
      } : {
        lastMovementAt: FieldValue.delete(),
        lastMovementId: FieldValue.delete(),
      }),
      ...(checkpointRef && checkpointHash ? {
        lastCheckpointHash: checkpointHash,
        lastCheckpointPath: checkpointRef.path,
      } : {}),
      status,
      checkpointChainValid: chainValid,
      lastVerificationJobId: job.jobId,
      lastVerificationGeneration: job.generation,
      lastVerificationCompleted: true,
      // Exactly "a difference was recorded", from the one decision above rather
      // than from a second copy of its condition.
      lastVerificationHadVariance: outcome.anomalyType !== undefined,
      activeVerificationJobId: job.jobId,
      activeVerificationGeneration: job.generation,
      activeInvalidMovementCount: cumulativeInvalidMovementCount,
      invalidMovementCount: FieldValue.increment(invalidMovementCount),
      updatedAt: FieldValue.serverTimestamp(),
      createdAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    if (outcome.anomalyType) {
      transaction.set(tenantRef.collection("reconciliation_anomalies")
        .doc(`stock_${digest([productId, job.jobId])}`), {
        tenantId: job.tenantId,
        productId,
        jobId: job.jobId,
        anomalyType: outcome.anomalyType,
        expectedQuantity,
        observedQuantity,
        variance,
        mutatesStock: false,
        updatedAt: FieldValue.serverTimestamp(),
        createdAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    }
    return {
      completed: true,
      variance: outcome.anomalyType !== undefined,
    };
  });
}

// A page that stops short is continued immediately, never after a delay. The
// only product this phase leaves unfinished has a movement backlog, which means
// the work for the next dispatch is already written and waiting; the only product
// it would ever be worth waiting for is one written in the last five minutes, and
// that one is deferred and stepped past rather than held, because holding it
// would block every product after it in the catalog while a product that sells
// more often than once every five minutes never leaves its own window.
export async function processStockPage(
  db: Firestore,
  job: ClaimedReconciliationJob
): Promise<StockPageResult> {
  if (job.pendingProductId) {
    const result = await reconcileProduct(db, job, job.pendingProductId);
    return {
      processed: result.completed ? 1 : 0,
      varianceCount: result.variance ? 1 : 0,
      hasMore: true,
      ...(result.completed ? {
        productCursor: job.pendingProductId,
      } : {
        productCursor: job.productCursor,
        pendingProductId: job.pendingProductId,
      }),
    };
  }
  let query = db.collection("tenants").doc(job.tenantId)
    .collection("products")
    .orderBy(FieldPath.documentId())
    .limit(PRODUCT_PAGE_SIZE);
  if (job.productCursor) query = query.startAfter(job.productCursor);
  const snapshot = await query.get();
  let processed = 0;
  let varianceCount = 0;
  let lastCompleted = job.productCursor;
  for (const product of snapshot.docs) {
    const result = await reconcileProduct(db, job, product.id);
    if (!result.completed) {
      return {
        processed,
        varianceCount,
        hasMore: true,
        productCursor: lastCompleted,
        pendingProductId: product.id,
      };
    }
    processed += 1;
    if (result.variance) varianceCount += 1;
    lastCompleted = product.id;
  }
  return {
    processed,
    varianceCount,
    hasMore: snapshot.size === PRODUCT_PAGE_SIZE,
    productCursor: lastCompleted,
  };
}

async function verifyShiftExpectation(
  db: Firestore,
  job: ClaimedReconciliationJob,
  expectation: QueryDocumentSnapshot<DocumentData>
): Promise<ShiftVerificationResult> {
  const tenantRef = db.collection("tenants").doc(job.tenantId);
  const shiftId = expectation.get("shiftId");
  const generation = expectation.get("generation");
  if (
    typeof shiftId !== "string" || shiftId.length === 0 || shiftId.includes("/") ||
    typeof generation !== "string" || generation.length === 0
  ) {
    return db.runTransaction(async (transaction) => {
      const currentExpectation = await transaction.get(expectation.ref);
      await assertCurrentLease(transaction, db, job);
      if (!currentExpectation.exists || currentExpectation.get("needsVerification") !== true) {
        return {salesVariance: false, tenderVariance: false};
      }
      const currentShiftId = currentExpectation.get("shiftId");
      const currentGeneration = currentExpectation.get("generation");
      if (
        typeof currentShiftId === "string" && currentShiftId.length > 0 &&
        !currentShiftId.includes("/") && typeof currentGeneration === "string" &&
        currentGeneration.length > 0
      ) return {salesVariance: false, tenderVariance: false};
      transaction.update(expectation.ref, {
        needsVerification: false,
        verificationStatus: "quarantined",
        lastErrorCode: "invalid_shift_expectation",
        updatedAt: FieldValue.serverTimestamp(),
      });
      // Counted as a difference, as it was before this returned two flags: a
      // quarantined expectation is one the run could not verify, and a job that
      // reported none would say the day reconciled cleanly.
      return {salesVariance: true, tenderVariance: false};
    });
  }
  const shiftRef = tenantRef.collection("shifts").doc(shiftId);
  const verificationRef = tenantRef.collection("shift_verifications")
    .doc(`${job.jobId}_${digest([expectation.id])}`);
  const tenderAnomalyRef = tenantRef.collection("reconciliation_anomalies")
    .doc(shiftTenderAnomalyId(shiftId));
  return db.runTransaction(async (transaction) => {
    // The tender anomaly is read here, with the others, because a transaction
    // may not read after it writes - and this one is both updated when the
    // declaration still disagrees and deleted when it no longer does.
    const [currentExpectation, shiftSnapshot, currentTenderAnomaly] =
      await transaction.getAll(expectation.ref, shiftRef, tenderAnomalyRef);
    await assertCurrentLease(transaction, db, job);
    if (
      !currentExpectation.exists ||
      currentExpectation.get("needsVerification") !== true ||
      currentExpectation.get("generation") !== generation
    ) return {salesVariance: false, tenderVariance: false};
    const expectedSales = safeNonNegativeNumber(currentExpectation.get("sales"));
    const expectedTransactions = safeInteger(currentExpectation.get("transactions"));
    // **A close made with no sale evidence states no figures, it does not state
    // zero.** `closedWithoutEvidence` is written by a device that holds none of
    // the shift's sales - a reinstall, or the other till of a duplicated shift -
    // so its summary is zero because it is unknown. Reading that zero as an
    // observation reported the shift's entire takings as a shortfall, every
    // night, against a shift nobody could have closed any better.
    //
    // `compareShiftTenders` has always skipped these, and says in its own
    // comment that it does so because *`invalid_or_missing_shift` already says
    // so* - which is the status this now produces. That expectation was the
    // design; only this half of it was missing.
    const evidenceFree = shiftSnapshot.get("closedWithoutEvidence") === true;
    const observedSales = shiftSnapshot.exists && !evidenceFree ?
      safeNonNegativeNumber(shiftSnapshot.get("totalSales")) : undefined;
    const observedTransactions = shiftSnapshot.exists && !evidenceFree ?
      safeInteger(shiftSnapshot.get("transactionCount")) : undefined;
    const valid = expectedSales !== undefined && expectedTransactions !== undefined &&
      observedSales !== undefined && observedTransactions !== undefined;
    const expectedSalesMinor = valid ? moneyToMinorUnits(expectedSales) : undefined;
    const observedSalesMinor = valid ? moneyToMinorUnits(observedSales) : undefined;
    const salesVarianceMinor = valid && expectedSalesMinor !== undefined &&
      observedSalesMinor !== undefined ? observedSalesMinor - expectedSalesMinor : null;
    const salesVariance = salesVarianceMinor === null ? null :
      minorUnitsToMoney(salesVarianceMinor);
    const transactionVariance = valid ? observedTransactions - expectedTransactions : null;
    const matched = valid && salesVarianceMinor === 0 && transactionVariance === 0;
    const tender = compareShiftTenders(currentExpectation, shiftSnapshot);
    transaction.set(verificationRef, {
      tenderStatus: tender.status,
      ...tender.figures,
      tenantId: job.tenantId,
      jobId: job.jobId,
      shiftId,
      businessDate: currentExpectation.get("businessDate"),
      generation,
      status: !valid ? "invalid_or_missing_shift" : matched ? "matched" : "variance",
      expectedSales: expectedSales ?? null,
      expectedSalesMinor: expectedSalesMinor ?? null,
      observedSales: observedSales ?? null,
      observedSalesMinor: observedSalesMinor ?? null,
      salesVariance,
      salesVarianceMinor,
      expectedTransactions: expectedTransactions ?? null,
      observedTransactions: observedTransactions ?? null,
      transactionVariance,
      mutatesShift: false,
      observedAt: FieldValue.serverTimestamp(),
    }, {merge: false});
    transaction.update(expectation.ref, {
      needsVerification: false,
      verificationStatus: !valid ? "invalid_or_missing_shift" : matched ? "matched" : "variance",
      verifiedGeneration: generation,
      verifiedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    if (!matched) {
      transaction.set(tenantRef.collection("reconciliation_anomalies")
        .doc(shiftAnomalyId(shiftId, generation)), {
        tenantId: job.tenantId,
        jobId: job.jobId,
        shiftId,
        anomalyType: !valid ? "invalid_or_missing_shift" : "shift_variance",
        salesVariance,
        transactionVariance,
        mutatesShift: false,
        updatedAt: FieldValue.serverTimestamp(),
        createdAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    }
    if (tender.anomalyType === undefined) {
      // **Deleted rather than left standing.** A shift whose late sales arrive
      // and bring the two sides into agreement stops being a difference, and
      // nobody should have to dismiss a record that is no longer true. The same
      // holds where the comparison could not be made at all.
      if (currentTenderAnomaly.exists) transaction.delete(tenderAnomalyRef);
    } else {
      // `resolution` is written only when the record is new or a figure has
      // moved. An unchanged re-verify leaves it alone, so an owner's
      // acknowledgement survives the next nightly run - while a difference that
      // has actually changed is a new fact and correctly reopens.
      const reopens = !currentTenderAnomaly.exists ||
        tenderFiguresMoved(currentTenderAnomaly, tender.figures);
      transaction.set(tenderAnomalyRef, {
        tenantId: job.tenantId,
        jobId: job.jobId,
        shiftId,
        businessDate: currentExpectation.get("businessDate") ?? null,
        staffId: shiftSnapshot.exists ? shiftSnapshot.get("staffId") ?? null : null,
        anomalyType: tender.anomalyType,
        generation,
        ...tender.figures,
        ...(reopens ? {resolution: "open"} : {}),
        mutatesShift: false,
        updatedAt: FieldValue.serverTimestamp(),
        createdAt: FieldValue.serverTimestamp(),
      }, {merge: true});
    }
    return {salesVariance: !matched, tenderVariance: tender.anomalyType !== undefined};
  });
}

/** The declared-versus-derived figures one verification records. */
type TenderFigures = Record<string, number | null>;

interface ShiftTenderComparison {
  status: string;
  /** The anomaly kind to record, or undefined to record none. */
  anomalyType?: "shift_tender_variance" | "missing_tender_declaration";
  figures: TenderFigures;
}

/**
 * What has to agree before a declaration is accepted: the money, not the split.
 *
 * **The declaration is the authority on how the money came in, and the sales
 * are the authority on how much.** A sale records whichever tender was tapped
 * at the moment of payment and nothing ever edits it afterwards, so the split
 * derived from sales is the weaker of the two: the cashier is standing at the
 * drawer and can see what is actually in it. Marking their answer against the
 * sales therefore reported the more reliable source as the error.
 *
 * **It cost shops real time.** One sale rung as cash that was actually M-Pesa
 * put cash over by its value and M-Pesa short by the same, with the total exact
 * and not a shilling missing - and left an owner a difference to investigate
 * until somebody dismissed it by hand.
 *
 * So only [totalVarianceMinor] decides. The per-method figures are still
 * computed and still recorded on the verification and on any anomaly, because
 * they are the payment split reporting reads; they simply no longer raise one
 * by themselves. Money genuinely missing still moves the total and still does.
 */
const TENDER_AGREEMENT_FIELDS = ["totalVarianceMinor"] as const;

/**
 * Compares what a cashier declared the till held against what its sales say.
 *
 * **Silence is the default, and there are three ways to earn it.** An
 * expectation written before the split existed cannot be compared. A shift with
 * no declaration on it has nothing to mark. And a shift closed before the
 * rollout was finished was closed by a build with nowhere to type a
 * declaration, so its absence says nothing about the shop.
 *
 * Everything after those is a real answer: a declaration that disagrees, or one
 * that a current build should have recorded and did not.
 *
 * **`closedWithoutEvidence` is not one of the three, and used to be.** It says
 * the closing device could not summarize the shift's *sales* - its own record
 * of them died with the app data it was wiped with - and that is why
 * `verifyShiftExpectation` declines the sales comparison. It says nothing about
 * the cash. The cashier counted the drawer and typed three figures; the
 * expectation those are marked against is built here, from the sale documents
 * the server already holds, and is not affected by what the device forgot. So
 * both halves of the comparison are present and it was being refused anyway.
 *
 * **The cost of refusing it was a shortfall nobody could see.** A till that was
 * genuinely short after a reinstall raised no tender difference at all: the
 * count went in, was thrown away here, and the only record left was
 * `invalid_or_missing_shift`, which reads as a bookkeeping gap rather than as
 * missing money. A reinstall must not be a way to make a short drawer quiet.
 */
function compareShiftTenders(
  expectation: DocumentSnapshot<DocumentData>,
  shift: DocumentSnapshot<DocumentData>
): ShiftTenderComparison {
  const expectedCashMinor = safeInteger(expectation.get("expectedCashMinor"));
  const expectedMpesaMinor = safeInteger(expectation.get("expectedMpesaMinor"));
  const expectedCardMinor = safeInteger(expectation.get("expectedCardMinor"));
  const expectedUnattributedMinor =
    safeInteger(expectation.get("expectedUnattributedMinor"));
  if (
    expectedCashMinor === undefined || expectedMpesaMinor === undefined ||
    expectedCardMinor === undefined || expectedUnattributedMinor === undefined
  ) {
    return {status: "no_expectation", figures: {}};
  }
  if (!shift.exists) {
    return {status: "unverifiable", figures: {}};
  }
  const evidenceFree = shift.get("closedWithoutEvidence") === true;
  const declaredCashMinor = safeInteger(shift.get("declaredCashMinor"));
  const declaredMpesaMinor = safeInteger(shift.get("declaredMpesaMinor"));
  const declaredCardMinor = safeInteger(shift.get("declaredCardMinor"));
  if (
    declaredCashMinor === undefined || declaredMpesaMinor === undefined ||
    declaredCardMinor === undefined
  ) {
    // **An evidence-free close with no declaration counted nothing, and that
    // is a legitimate answer rather than an omission.** It is the shape a
    // second shift is closed in when one drawer has already been counted once
    // - see `TenantShiftController.closeShiftWithoutEvidence` - so demanding a
    // declaration of it would raise a difference against a till that was never
    // supposed to be counted twice.
    if (evidenceFree) {
      return {status: "unverifiable", figures: {}};
    }
    const endTime = shift.get("endTime");
    const closedAt = endTime instanceof Timestamp ? endTime.toMillis() : undefined;
    if (closedAt === undefined || closedAt < TENDER_DECLARATION_REQUIRED_FROM) {
      return {status: "not_declared_legacy", figures: {}};
    }
    return {
      status: "missing",
      anomalyType: "missing_tender_declaration",
      figures: {
        expectedCashMinor,
        expectedMpesaMinor,
        expectedCardMinor,
        expectedUnattributedMinor,
      },
    };
  }
  const declaredTotalMinor =
    declaredCashMinor + declaredMpesaMinor + declaredCardMinor;
  // **The float is money the drawer was given, not money the shift took.**
  // The cashier counts the whole drawer at close - they are asked what the
  // till holds, and the change they started with is sitting in it - so the
  // cash expected of them is their sales plus that float. Without this term a
  // shop that floats its till declares the float as a surplus every day, on
  // every shift, for a drawer that balances to the shilling.
  //
  // Absent reads as zero, which is what every shift opened before the field
  // existed meant, so no closed shift changes its answer under this.
  //
  // **A negative float is not believed.** Rules refuse one on write, and this
  // is the second lock: read as-is it would *lower* the cash expected of the
  // drawer, which is the one direction a dishonest figure would be worth
  // writing in. Anything that is not a non-negative integer reads as no float.
  const declaredFloat = safeInteger(shift.get("openingFloatMinor"));
  const openingFloatMinor =
    declaredFloat !== undefined && declaredFloat >= 0 ? declaredFloat : 0;
  const expectedDrawerCashMinor = expectedCashMinor + openingFloatMinor;
  // The derived total includes what could not be attributed, so a shift whose
  // sales name no method is short by exactly that rather than silently balanced.
  const expectedTotalMinor = expectedDrawerCashMinor + expectedMpesaMinor +
    expectedCardMinor + expectedUnattributedMinor;
  const figures: TenderFigures = {
    declaredCashMinor,
    declaredMpesaMinor,
    declaredCardMinor,
    // **Recorded as the sales expected, not the drawer expected.** This is the
    // figure every report of the tender split reads, and the float is not a
    // taking; an owner reading `expectedCashMinor` wants what was sold for
    // cash. The float is carried beside it so the variance can be explained.
    expectedCashMinor,
    // **Written only where there is a float, and that is a migration
    // guarantee rather than tidiness.** `tenderFiguresMoved` reopens an
    // acknowledged difference whose figures changed, and it compares field by
    // field - so recording these unconditionally would reopen every difference
    // an owner has ever dismissed, on the first nightly run after this
    // deploys, for shops that do not float a till at all. A shop that starts
    // floating one does see its open differences move, which is correct: the
    // figure they are marked against genuinely changed.
    ...(openingFloatMinor > 0 ?
      {openingFloatMinor, expectedDrawerCashMinor} :
      {}),
    expectedMpesaMinor,
    expectedCardMinor,
    expectedUnattributedMinor,
    cashVarianceMinor: declaredCashMinor - expectedDrawerCashMinor,
    mpesaVarianceMinor: declaredMpesaMinor - expectedMpesaMinor,
    cardVarianceMinor: declaredCardMinor - expectedCardMinor,
    declaredTotalMinor,
    expectedTotalMinor,
    totalVarianceMinor: declaredTotalMinor - expectedTotalMinor,
  };
  const agrees = TENDER_AGREEMENT_FIELDS.every((field) => figures[field] === 0);
  return agrees ?
    {status: "matched", figures} :
    {status: "variance", anomalyType: "shift_tender_variance", figures};
}

/** Whether any recorded figure differs from the one already on the record. */
function tenderFiguresMoved(
  recorded: DocumentSnapshot<DocumentData>,
  figures: TenderFigures
): boolean {
  return Object.entries(figures).some(([field, value]) => recorded.get(field) !== value);
}

export async function processShiftPage(
  db: Firestore,
  job: ClaimedReconciliationJob
): Promise<ShiftPageResult> {
  const collection = db.collection("tenants").doc(job.tenantId)
    .collection("shift_expectations");
  const snapshot = await collection.where("needsVerification", "==", true)
    .orderBy(FieldPath.documentId())
    .limit(SHIFT_PAGE_SIZE)
    .get();
  let processed = 0;
  let varianceCount = 0;
  let tenderVarianceCount = 0;
  for (const expectation of snapshot.docs) {
    const result = await verifyShiftExpectation(db, job, expectation);
    if (result.salesVariance) varianceCount += 1;
    if (result.tenderVariance) tenderVarianceCount += 1;
    processed += 1;
  }
  const remainder = await collection.where("needsVerification", "==", true).limit(1).get();
  return {processed, varianceCount, tenderVarianceCount, hasMore: !remainder.empty};
}
