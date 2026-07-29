import assert from "node:assert/strict";
import test from "node:test";
import {
  decodeTenantCursor,
  encodeTenantCursor,
  InvalidTenantCursorError,
  InvalidTenantCursorSecretError,
} from "./cursor";

const SECRET = "tenant-cursor-test-secret-with-32-bytes";

test("tenant cursor round-trips its stable pagination position", () => {
  const cursor = encodeTenantCursor("user-1", {
    createdAtSeconds: 1753783200,
    createdAtNanoseconds: 123456789,
    tenantId: "tenant-z",
  }, SECRET);

  assert.deepEqual(decodeTenantCursor(cursor, "user-1", SECRET), {
    createdAtSeconds: 1753783200,
    createdAtNanoseconds: 123456789,
    tenantId: "tenant-z",
  });
});

test("tenant cursor rejects tampering and a different user", () => {
  const cursor = encodeTenantCursor("user-1", {
    createdAtSeconds: 1753783200,
    createdAtNanoseconds: 0,
    tenantId: "tenant-a",
  }, SECRET);
  const [payload, signature] = cursor.split(".");
  const replacement = payload.endsWith("a") ? "b" : "a";
  const tampered = `${payload.slice(0, -1)}${replacement}.${signature}`;

  assert.throws(
    () => decodeTenantCursor(tampered, "user-1", SECRET),
    InvalidTenantCursorError
  );
  assert.throws(
    () => decodeTenantCursor(cursor, "user-2", SECRET),
    InvalidTenantCursorError
  );
});

test("tenant cursor rejects an unsafe signing secret", () => {
  assert.throws(() => encodeTenantCursor("user-1", {
    createdAtSeconds: 1753783200,
    createdAtNanoseconds: 0,
    tenantId: "tenant-a",
  }, "too-short"), InvalidTenantCursorSecretError);
});
