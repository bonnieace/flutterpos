import {
  DocumentData,
  FieldPath,
  FieldValue,
  Firestore,
  Timestamp,
} from "firebase-admin/firestore";

/**
 * An in-memory Firestore for testing the reconciliation processors as units.
 *
 * `processors.ts` is the largest module in `functions/src/reconciliation` and the
 * only coverage it has ever had is the end-to-end integration suite, which needs
 * an emulator, a real task queue, and about two minutes per run. The behaviour
 * that suite cannot reach is exactly the behaviour worth pinning: the page-size
 * boundaries, the cursor a partial page resumes from, and a lease revoked between
 * two products of one page. Reaching those against a real Firestore would mean
 * seeding twenty-five products or two hundred movements per assertion.
 *
 * So this is a double, and the whole value of it depends on it being wrong in no
 * way the code under test can observe. Three rules follow from that:
 *
 * - **Where Firestore's semantics decide an outcome, they are implemented, not
 *   approximated.** A document missing a field the query orders by is invisible
 *   to that query; a transaction may not read after its first write; a
 *   `FieldValue.delete()` in an unmerged `set` or a `create` is rejected;
 *   `update` refuses a document that does not exist and `create` refuses one that
 *   does. Each of those is a real refusal this module reproduces, because a
 *   double that is more permissive than Firestore turns a production defect into
 *   a green test.
 * - **Everything else throws.** Any operator but `==`, any `FieldPath` but
 *   `documentId()`, any sentinel but the three used, any value type the sort
 *   order does not cover. A silently-ignored `where` clause is the single worst
 *   thing a Firestore double can do, so nothing here is silently ignored.
 * - **It records what it wrote.** `writes` is the log a test asserts "and nothing
 *   else was written" against, which is most of what a phase that finds nothing
 *   has to prove.
 *
 * It is deliberately not a general-purpose fake: `array-contains`, collection
 * group queries, aggregations, and cursors built from snapshots are all absent
 * because the reconciliation processors use none of them, and each one added
 * without a caller is a piece of untested test infrastructure.
 */

/** Firestore's own name for the document ID when it is used as a sort key. */
const DOCUMENT_ID = "__name__";

interface OrderBy {
  field: string;
  descending: boolean;
}

interface EqualityFilter {
  field: string;
  value: unknown;
}

interface QueryPlan {
  collectionPath: string;
  filters: readonly EqualityFilter[];
  orders: readonly OrderBy[];
  cursor?: readonly unknown[];
  limit?: number;
}

/** One committed write, in the order it was committed. */
export interface FakeWrite {
  kind: "create" | "set" | "merge" | "update" | "delete";
  path: string;
}

/**
 * A write that has been asked for but not yet published.
 *
 * Staging exists so a set of writes is all-or-nothing: a transaction whose third
 * write is refused must leave the first two unwritten, which is the property
 * behind every "a lease that is not current wrote nothing" assertion.
 */
type PendingWrite =
  | {kind: "create" | "set" | "merge" | "update"; path: string; data: DocumentData}
  | {kind: "delete"; path: string};

/** Staged documents by path. `null` is a staged deletion. */
type StagedDocuments = Map<string, Record<string, unknown> | null>;

/**
 * Whether `value` is a bare `{...}` rather than a Firestore value object.
 *
 * `Timestamp` and `DocumentReference` are objects too, and merging into one would
 * corrupt it, so only plain maps are walked. Same test `writeSentinels.ts` makes,
 * for the same reason.
 */
function isPlainMap(value: unknown): value is Record<string, unknown> {
  if (value === null || typeof value !== "object") return false;
  const prototype = Object.getPrototypeOf(value);
  return prototype === Object.prototype || prototype === null;
}

/**
 * The sentinel kind of `value`, or `undefined` if it is an ordinary value.
 *
 * `methodName` is how the Firestore client itself reports a sentinel in its error
 * messages, and `operand` is where `increment` keeps its addend. Both are
 * internal, so this throws rather than guesses if a firebase-admin upgrade
 * renames them - a double that resolved an unrecognised sentinel to `undefined`
 * would quietly drop every `serverTimestamp` and every counter in the suite.
 */
function sentinelKind(value: unknown): string | undefined {
  if (!(value instanceof FieldValue)) return undefined;
  const name = (value as unknown as {methodName?: unknown}).methodName;
  if (typeof name !== "string") {
    throw new Error(
      "This firebase-admin no longer reports a FieldValue's `methodName`, so " +
      "fakeFirestore cannot tell one sentinel from another. Update sentinelKind()."
    );
  }
  return name;
}

/** What a sentinel resolves to, given whatever the field held before the write. */
function resolveSentinel(
  kind: string,
  sentinel: unknown,
  existing: unknown,
  nowMilliseconds: number
): unknown {
  if (kind === "FieldValue.serverTimestamp") return Timestamp.fromMillis(nowMilliseconds);
  if (kind === "FieldValue.increment") {
    const operand = (sentinel as unknown as {operand?: unknown}).operand;
    if (typeof operand !== "number") {
      throw new Error(
        "This firebase-admin no longer reports a FieldValue.increment's `operand`. " +
        "Update resolveSentinel()."
      );
    }
    // Firestore's own rule: a field that is absent or not a number is set to the
    // operand rather than treated as zero.
    return typeof existing === "number" ? existing + operand : operand;
  }
  throw new Error(`fakeFirestore does not support ${kind}().`);
}

/** A deep copy, so a caller can never reach into the store through a snapshot. */
function cloneValue(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(cloneValue);
  if (!isPlainMap(value)) return value;
  const copy: Record<string, unknown> = {};
  for (const [key, nested] of Object.entries(value)) copy[key] = cloneValue(nested);
  return copy;
}

/**
 * Applies `patch` onto `target`, resolving sentinels against what is already
 * there. `allowDelete` is false for an unmerged `set`, which is the write
 * Firestore rejects a delete sentinel in.
 */
function applyPatch(
  target: Record<string, unknown>,
  patch: DocumentData,
  nowMilliseconds: number,
  allowDelete: boolean,
  path: string
): void {
  for (const [key, value] of Object.entries(patch)) {
    if (key.includes(".")) {
      throw new Error(
        `fakeFirestore does not support the dotted field path "${key}" at ${path}.`
      );
    }
    const kind = sentinelKind(value);
    if (kind === "FieldValue.delete") {
      if (!allowDelete) {
        throw new Error(
          "Firestore rejects FieldValue.delete() outside update() and " +
          `set(..., {merge: true}); found at ${path}.${key}.`
        );
      }
      delete target[key];
      continue;
    }
    if (kind !== undefined) {
      target[key] = resolveSentinel(kind, value, target[key], nowMilliseconds);
      continue;
    }
    if (isPlainMap(value)) {
      const existing = target[key];
      const nested = isPlainMap(existing) ? existing : {};
      applyPatch(nested, value, nowMilliseconds, allowDelete, `${path}.${key}`);
      target[key] = nested;
      continue;
    }
    target[key] = cloneValue(value);
  }
}

function fieldName(field: string | FieldPath): string {
  if (typeof field === "string") {
    if (field.includes(".")) {
      throw new Error(`fakeFirestore does not support the nested field path "${field}".`);
    }
    return field;
  }
  if (field.isEqual(FieldPath.documentId())) return DOCUMENT_ID;
  throw new Error("fakeFirestore supports only FieldPath.documentId() as a FieldPath.");
}

/** Firestore's canonical type order, over the types these fixtures use. */
function typeRank(value: unknown): number {
  if (value === null) return 0;
  if (typeof value === "boolean") return 1;
  if (typeof value === "number") return 2;
  if (value instanceof Timestamp) return 3;
  if (typeof value === "string") return 4;
  throw new Error(
    `fakeFirestore cannot order a value of type ${typeof value}. Order by a ` +
    "null, boolean, number, Timestamp, or string."
  );
}

function compareValues(left: unknown, right: unknown): number {
  const leftRank = typeRank(left);
  const rightRank = typeRank(right);
  if (leftRank !== rightRank) return leftRank < rightRank ? -1 : 1;
  if (left instanceof Timestamp && right instanceof Timestamp) {
    if (left.seconds !== right.seconds) return left.seconds < right.seconds ? -1 : 1;
    if (left.nanoseconds === right.nanoseconds) return 0;
    return left.nanoseconds < right.nanoseconds ? -1 : 1;
  }
  if (typeof left === "boolean" && typeof right === "boolean") {
    return left === right ? 0 : left ? 1 : -1;
  }
  const comparable = left as number | string;
  const other = right as number | string;
  if (comparable === other) return 0;
  return comparable < other ? -1 : 1;
}

function valuesEqual(left: unknown, right: unknown): boolean {
  if (left instanceof Timestamp) return right instanceof Timestamp && left.isEqual(right);
  return left === right;
}

function requireDocumentPath(path: string): string {
  const segments = path.split("/");
  if (segments.length % 2 !== 0 || segments.some((segment) => segment.length === 0)) {
    throw new Error(`"${path}" is not a Firestore document path.`);
  }
  return path;
}

export class FakeDocumentSnapshot {
  constructor(
    readonly ref: FakeDocumentReference,
    private readonly stored: Record<string, unknown> | undefined
  ) {}

  get id(): string {
    return this.ref.id;
  }

  get exists(): boolean {
    return this.stored !== undefined;
  }

  data(): DocumentData | undefined {
    return this.stored === undefined ?
      undefined :
      cloneValue(this.stored) as DocumentData;
  }

  get(field: string | FieldPath): unknown {
    if (this.stored === undefined) return undefined;
    return cloneValue(this.stored[fieldName(field)]);
  }
}

export class FakeQuerySnapshot {
  constructor(readonly docs: readonly FakeDocumentSnapshot[]) {}

  get size(): number {
    return this.docs.length;
  }

  get empty(): boolean {
    return this.docs.length === 0;
  }
}

export class FakeQuery {
  constructor(
    protected readonly db: FakeFirestore,
    protected readonly plan: QueryPlan
  ) {}

  where(field: string | FieldPath, operator: string, value: unknown): FakeQuery {
    if (operator !== "==") {
      throw new Error(`fakeFirestore supports only "==" filters, not "${operator}".`);
    }
    return new FakeQuery(this.db, {
      ...this.plan,
      filters: [...this.plan.filters, {field: fieldName(field), value}],
    });
  }

  orderBy(field: string | FieldPath, direction = "asc"): FakeQuery {
    if (direction !== "asc" && direction !== "desc") {
      throw new Error(`"${direction}" is not a Firestore sort direction.`);
    }
    return new FakeQuery(this.db, {
      ...this.plan,
      orders: [...this.plan.orders, {field: fieldName(field), descending: direction === "desc"}],
    });
  }

  startAfter(...values: readonly unknown[]): FakeQuery {
    if (values.length === 0) throw new Error("startAfter() needs at least one value.");
    if (values.some((value) => value instanceof FakeDocumentSnapshot)) {
      throw new Error("fakeFirestore does not support a snapshot cursor; pass the field values.");
    }
    return new FakeQuery(this.db, {...this.plan, cursor: values});
  }

  limit(count: number): FakeQuery {
    if (!Number.isSafeInteger(count) || count < 1) {
      throw new Error(`limit(${count}) is not a positive integer.`);
    }
    return new FakeQuery(this.db, {...this.plan, limit: count});
  }

  get(): Promise<FakeQuerySnapshot> {
    return Promise.resolve(this.db.runQuery(this.plan));
  }
}

export class FakeCollectionReference extends FakeQuery {
  constructor(db: FakeFirestore, readonly path: string) {
    super(db, {collectionPath: path, filters: [], orders: []});
  }

  get id(): string {
    return this.path.split("/").slice(-1)[0];
  }

  doc(id: string): FakeDocumentReference {
    if (id.length === 0 || id.includes("/")) {
      throw new Error(`"${id}" is not a Firestore document ID.`);
    }
    return new FakeDocumentReference(this.db, `${this.path}/${id}`);
  }

  /** The document this collection hangs below, or null at the root. */
  get parent(): FakeDocumentReference | null {
    const segments = this.path.split("/");
    if (segments.length === 1) return null;
    return new FakeDocumentReference(this.db, segments.slice(0, -1).join("/"));
  }
}

export class FakeDocumentReference {
  constructor(private readonly db: FakeFirestore, readonly path: string) {
    requireDocumentPath(path);
  }

  get id(): string {
    return this.path.split("/").slice(-1)[0];
  }

  get parent(): FakeCollectionReference {
    return new FakeCollectionReference(this.db, this.path.split("/").slice(0, -1).join("/"));
  }

  collection(name: string): FakeCollectionReference {
    return new FakeCollectionReference(this.db, `${this.path}/${name}`);
  }

  get(): Promise<FakeDocumentSnapshot> {
    return Promise.resolve(this.db.readSnapshot(this));
  }

  // Nothing here is `async`, so a refused write throws where it was asked for
  // rather than settling later. Firestore splits its refusals - an invalid
  // payload throws synchronously, a missing document on `update` comes back from
  // the server - and a double cannot honour that split without pretending to have
  // a server. Every caller in `functions/src` awaits, and an awaited synchronous
  // throw and an awaited rejection are the same failure.

  create(data: DocumentData): Promise<void> {
    this.db.applyCreate(this.path, data);
    return Promise.resolve();
  }

  set(data: DocumentData, options?: {merge?: boolean}): Promise<void> {
    this.db.applySet(this.path, data, options?.merge === true);
    return Promise.resolve();
  }

  update(data: DocumentData): Promise<void> {
    this.db.applyUpdate(this.path, data);
    return Promise.resolve();
  }

  delete(): Promise<void> {
    this.db.applyDelete(this.path);
    return Promise.resolve();
  }
}

/**
 * Reads run against committed state and writes are buffered until the callback
 * returns, exactly as a real transaction behaves - so a processor that reads a
 * document it has already written in the same transaction sees the old value
 * here too, and a callback that throws commits nothing.
 */
export class FakeTransaction {
  private wrote = false;
  private readonly buffered: PendingWrite[] = [];

  constructor(private readonly db: FakeFirestore) {}

  get(
    target: FakeDocumentReference | FakeQuery
  ): Promise<FakeDocumentSnapshot | FakeQuerySnapshot> {
    this.requireReadPhase();
    if (target instanceof FakeDocumentReference) {
      return Promise.resolve(this.db.readSnapshot(target));
    }
    return target.get();
  }

  getAll(
    ...refs: readonly FakeDocumentReference[]
  ): Promise<FakeDocumentSnapshot[]> {
    this.requireReadPhase();
    return Promise.resolve(refs.map((ref) => this.db.readSnapshot(ref)));
  }

  create(ref: FakeDocumentReference, data: DocumentData): FakeTransaction {
    return this.buffer({kind: "create", path: ref.path, data});
  }

  set(
    ref: FakeDocumentReference,
    data: DocumentData,
    options?: {merge?: boolean}
  ): FakeTransaction {
    return this.buffer({
      kind: options?.merge === true ? "merge" : "set",
      path: ref.path,
      data,
    });
  }

  update(ref: FakeDocumentReference, data: DocumentData): FakeTransaction {
    return this.buffer({kind: "update", path: ref.path, data});
  }

  delete(ref: FakeDocumentReference): FakeTransaction {
    return this.buffer({kind: "delete", path: ref.path});
  }

  /** @internal */
  commit(): void {
    this.db.commitWrites(this.buffered);
  }

  private buffer(write: PendingWrite): FakeTransaction {
    this.wrote = true;
    this.buffered.push(write);
    return this;
  }

  private requireReadPhase(): void {
    if (this.wrote) {
      throw new Error(
        "Firestore refuses a read after the first write in a transaction. " +
        "Move this read above the write."
      );
    }
  }
}

export class FakeFirestore {
  private readonly store = new Map<string, Record<string, unknown>>();

  /** Every committed write, in order. Reset with `clearWrites()`. */
  readonly writes: FakeWrite[] = [];

  /**
   * @param clock what `FieldValue.serverTimestamp()` resolves to. The processors
   *   read the wall clock directly for lease expiry and for the recent-write
   *   deferral window, so this cannot make a test independent of real time - it
   *   exists so a fixture can tell two written instants apart.
   */
  constructor(private readonly clock: () => number = Date.now) {}

  /** This double, typed as the `Firestore` the processors take. */
  asFirestore(): Firestore {
    return this as unknown as Firestore;
  }

  collection(path: string): FakeCollectionReference {
    const segments = path.split("/");
    if (segments.length % 2 !== 1 || segments.some((segment) => segment.length === 0)) {
      throw new Error(`"${path}" is not a Firestore collection path.`);
    }
    return new FakeCollectionReference(this, path);
  }

  doc(path: string): FakeDocumentReference {
    return new FakeDocumentReference(this, requireDocumentPath(path));
  }

  async runTransaction<T>(body: (transaction: FakeTransaction) => Promise<T>): Promise<T> {
    const transaction = new FakeTransaction(this);
    const result = await body(transaction);
    transaction.commit();
    return result;
  }

  /**
   * Writes a fixture document. Routed through the same unmerged `set` production
   * code uses, so a fixture cannot smuggle in a delete sentinel or an unresolved
   * `serverTimestamp`; it is not recorded in `writes`, which is reserved for what
   * the code under test did.
   */
  seed(path: string, data: DocumentData): void {
    const before = this.writes.length;
    this.applySet(requireDocumentPath(path), data, false);
    this.writes.length = before;
  }

  /** What is stored at `path`, or undefined. A copy, never the stored object. */
  read(path: string): DocumentData | undefined {
    const stored = this.store.get(requireDocumentPath(path));
    return stored === undefined ? undefined : cloneValue(stored) as DocumentData;
  }

  /** The document IDs directly below `collectionPath`, ascending. */
  ids(collectionPath: string): string[] {
    return this.childIds(collectionPath).sort();
  }

  clearWrites(): void {
    this.writes.length = 0;
  }

  /** The paths written since the last `clearWrites()`, deduplicated and sorted. */
  writtenPaths(): string[] {
    return [...new Set(this.writes.map((write) => write.path))].sort();
  }

  /** @internal */
  readSnapshot(ref: FakeDocumentReference): FakeDocumentSnapshot {
    const stored = this.store.get(ref.path);
    return new FakeDocumentSnapshot(
      ref,
      stored === undefined ? undefined : cloneValue(stored) as Record<string, unknown>
    );
  }

  /** @internal */
  applyCreate(path: string, data: DocumentData): void {
    this.commitWrites([{kind: "create", path: requireDocumentPath(path), data}]);
  }

  /** @internal */
  applySet(path: string, data: DocumentData, merge: boolean): void {
    this.commitWrites([{kind: merge ? "merge" : "set", path, data}]);
  }

  /** @internal */
  applyUpdate(path: string, data: DocumentData): void {
    this.commitWrites([{kind: "update", path, data}]);
  }

  /** @internal */
  applyDelete(path: string): void {
    this.commitWrites([{kind: "delete", path: requireDocumentPath(path)}]);
  }

  /**
   * Stages every write, then publishes them together.
   *
   * Nothing reaches the store until all of them have been computed, so a set that
   * Firestore would refuse leaves the ones before it unwritten. Writes are staged
   * in order and each sees the ones before it, which is what makes two merges to
   * one document inside a transaction accumulate rather than race.
   *
   * @internal
   */
  commitWrites(writes: readonly PendingWrite[]): void {
    const staged: StagedDocuments = new Map();
    for (const write of writes) this.stageWrite(staged, write);
    for (const [path, document] of staged) {
      if (document === null) this.store.delete(path);
      else this.store.set(path, document);
    }
    for (const write of writes) this.writes.push({kind: write.kind, path: write.path});
  }

  private stageWrite(staged: StagedDocuments, write: PendingWrite): void {
    if (write.kind === "delete") {
      staged.set(write.path, null);
      return;
    }
    const existing = this.stagedValue(staged, write.path);
    if (write.kind === "update" && existing === undefined) {
      // Firestore's own refusal. A processor that updates a document it only
      // assumes exists must fail here rather than create a partial one.
      throw new Error(`NOT_FOUND: no document to update at ${write.path}.`);
    }
    if (write.kind === "create" && existing !== undefined) {
      // The other half of that refusal, and the one every idempotent creator in
      // this codebase leans on: a second create of the same job, invitation, or
      // sale is rejected rather than silently replacing the first.
      throw new Error(`ALREADY_EXISTS: a document already exists at ${write.path}.`);
    }
    // `create` writes a whole document, so it carries a replace's sentinel rules:
    // a delete sentinel in one is rejected, which is the defect the sentinel audit
    // beside this file exists to find.
    const merge = write.kind === "merge" || write.kind === "update";
    const target = merge && existing !== undefined ? existing : {};
    applyPatch(target, write.data, this.clock(), merge, write.path);
    staged.set(write.path, target);
  }

  /** What `path` holds given the writes staged so far. */
  private stagedValue(
    staged: StagedDocuments,
    path: string
  ): Record<string, unknown> | undefined {
    if (staged.has(path)) return staged.get(path) ?? undefined;
    const stored = this.store.get(path);
    return stored === undefined ?
      undefined :
      cloneValue(stored) as Record<string, unknown>;
  }

  /** @internal */
  runQuery(plan: QueryPlan): FakeQuerySnapshot {
    const orders = effectiveOrders(plan.orders);
    let candidates = this.childIds(plan.collectionPath).map((id) => ({
      id,
      path: `${plan.collectionPath}/${id}`,
      stored: this.store.get(`${plan.collectionPath}/${id}`) as Record<string, unknown>,
    }));

    candidates = candidates.filter((candidate) => plan.filters.every(
      (filter) => valuesEqual(orderValue(candidate.id, candidate.stored, filter.field), filter.value)
    ));
    // Firestore returns nothing for a document that has no value at a field the
    // query orders by. A stock movement with no `recordedAt` is therefore
    // invisible to the cursor query that reads the ledger, which is a real
    // property of the pipeline and not a shortcut taken here.
    candidates = candidates.filter((candidate) => orders.every(
      (order) => orderValue(candidate.id, candidate.stored, order.field) !== undefined
    ));

    candidates.sort((left, right) => {
      for (const order of orders) {
        const comparison = compareValues(
          orderValue(left.id, left.stored, order.field),
          orderValue(right.id, right.stored, order.field)
        );
        if (comparison !== 0) return order.descending ? -comparison : comparison;
      }
      return 0;
    });

    const cursor = plan.cursor;
    if (cursor !== undefined) {
      if (cursor.length > orders.length) {
        throw new Error(
          `startAfter() was given ${cursor.length} values for ${orders.length} sort keys.`
        );
      }
      candidates = candidates.filter((candidate) => {
        for (let index = 0; index < cursor.length; index += 1) {
          const order = orders[index];
          const comparison = compareValues(
            orderValue(candidate.id, candidate.stored, order.field),
            cursor[index]
          );
          const directed = order.descending ? -comparison : comparison;
          if (directed !== 0) return directed > 0;
        }
        return false;
      });
    }

    const limited = plan.limit === undefined ? candidates : candidates.slice(0, plan.limit);
    return new FakeQuerySnapshot(limited.map((candidate) => new FakeDocumentSnapshot(
      new FakeDocumentReference(this, candidate.path),
      cloneValue(candidate.stored) as Record<string, unknown>
    )));
  }

  private childIds(collectionPath: string): string[] {
    const prefix = `${collectionPath}/`;
    const ids: string[] = [];
    for (const path of this.store.keys()) {
      if (!path.startsWith(prefix)) continue;
      const remainder = path.slice(prefix.length);
      if (remainder.includes("/")) continue;
      ids.push(remainder);
    }
    return ids;
  }
}

/**
 * Firestore appends `__name__` to every sort so the order is total, in the
 * direction of the last key given. Without that, a page boundary in this double
 * would depend on insertion order and a cursor test could pass by luck.
 */
function effectiveOrders(orders: readonly OrderBy[]): readonly OrderBy[] {
  if (orders.some((order) => order.field === DOCUMENT_ID)) return orders;
  const last = orders[orders.length - 1];
  return [...orders, {field: DOCUMENT_ID, descending: last?.descending ?? false}];
}

function orderValue(
  id: string,
  stored: Record<string, unknown>,
  field: string
): unknown {
  return field === DOCUMENT_ID ? id : stored[field];
}
