import assert from "node:assert/strict";
import test from "node:test";
import {absorbedFailureEntry} from "./absorbedFailure";

test("an absorbed failure keeps the cause's frames under the event's header", () => {
  const cause = new TypeError("provider answered 502");
  const {reported, fields} = absorbedFailureEntry(
    "staff.invitation_send_failed",
    cause,
    {deliveryId: "d-1", safeCode: "provider_transport_failure", retryable: true}
  );
  const [header, ...frames] = (reported.stack ?? "").split("\n");
  assert.equal(
    header,
    "TypeError: staff.invitation_send_failed: provider answered 502"
  );
  assert.deepEqual(frames, (cause.stack ?? "").split("\n").slice(1));
  assert.deepEqual(fields, {
    event: "staff.invitation_send_failed",
    errorName: "TypeError",
    deliveryId: "d-1",
    safeCode: "provider_transport_failure",
    retryable: true,
  });
});

test("a thrown non-Error is logged without printing the value", () => {
  const {reported, fields} = absorbedFailureEntry(
    "lifecycle.operation_quarantined",
    "someone@example.com",
    {operationId: undefined}
  );
  assert.doesNotMatch(reported.stack ?? "", /someone@example\.com/);
  assert.match(reported.message, /non-Error value was thrown \(string\)/);
  assert.deepEqual(fields, {
    event: "lifecycle.operation_quarantined",
    errorName: "Error",
  });
});
