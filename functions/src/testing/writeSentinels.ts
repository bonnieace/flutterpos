import {DocumentData, FieldValue} from "firebase-admin/firestore";

/**
 * Support for asserting where a `FieldValue.delete()` sentinel is and is not.
 *
 * A sentinel is an ordinary object until the write is serialized, so a payload
 * carrying one in the wrong place compiles, type-checks, and inspects perfectly.
 * Only a real Firestore rejects it - which is how a sentinel in a `create()`
 * payload disabled the sale reconciliation trigger for every sale ever made
 * without a single one of the pure tests noticing. `isEqual` is the public way
 * to ask the question in a test instead.
 */

const DELETE = FieldValue.delete();

/**
 * Whether `value` is a bare `{...}` map rather than a Firestore value object.
 *
 * `Timestamp`, `DocumentReference`, and `GeoPoint` are all objects, and a
 * `DocumentReference` holds a live `Firestore` instance, so walking into one
 * would be both pointless and unbounded.
 */
function isPlainMap(value: unknown): value is Record<string, unknown> {
  if (value === null || typeof value !== "object") return false;
  const prototype = Object.getPrototypeOf(value);
  return prototype === Object.prototype || prototype === null;
}

/**
 * Every path in `payload` holding a `FieldValue.delete()`, sorted.
 *
 * Paths are dotted, and array elements are indexed, so a report names the field
 * a test needs to look at rather than only saying that one exists. Nested paths
 * are reported because Firestore refuses a sentinel below the top level even in
 * an `update()`, so a caller may hold that stricter rule if it wants to.
 */
export function deleteSentinelPaths(payload: DocumentData): string[] {
  const found: string[] = [];

  const visit = (value: unknown, path: string): void => {
    if (value instanceof FieldValue) {
      if (value.isEqual(DELETE)) found.push(path);
      return;
    }
    if (Array.isArray(value)) {
      value.forEach((item, index) => visit(item, `${path}[${index}]`));
      return;
    }
    if (!isPlainMap(value)) return;
    for (const [key, nested] of Object.entries(value)) {
      visit(nested, path.length > 0 ? `${path}.${key}` : key);
    }
  };

  visit(payload, "");
  return found.sort();
}

/**
 * Whether `payload` may be written with `create()` or `set()` without a merge.
 *
 * Named for the question a test actually asks, so the reason a payload is being
 * inspected survives in the assertion.
 */
export function carriesDeleteSentinel(payload: DocumentData): boolean {
  return deleteSentinelPaths(payload).length > 0;
}
