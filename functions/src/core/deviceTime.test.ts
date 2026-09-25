import assert from "node:assert/strict";
import test from "node:test";
import {HttpsError} from "firebase-functions/v2/https";
import {
  EARLIEST_DEVICE_INSTANT_MS,
  deviceInstantOrNow,
  requireDeviceInstant,
} from "./deviceTime";

const NOW = new Date(Date.UTC(2026, 8, 25, 9, 30));
const YESTERDAY = Date.UTC(2026, 8, 24, 18, 2);

test("a device's time in the past is kept as it was", () => {
  assert.equal(deviceInstantOrNow(YESTERDAY, NOW).toMillis(), YESTERDAY);
  assert.equal(requireDeviceInstant(YESTERDAY, "occurredAtMs", NOW).toMillis(), YESTERDAY);
});

test("a clock running fast is brought back to the server's now", () => {
  const ahead = NOW.getTime() + 60_000;
  assert.equal(deviceInstantOrNow(ahead, NOW).toMillis(), NOW.getTime());
  assert.equal(requireDeviceInstant(ahead, "occurredAtMs", NOW).toMillis(), NOW.getTime());
});

test("a clock that was never set reads as now, not as 1970", () => {
  assert.equal(deviceInstantOrNow(0, NOW).toMillis(), NOW.getTime());
  assert.equal(
    deviceInstantOrNow(EARLIEST_DEVICE_INSTANT_MS - 1, NOW).toMillis(),
    NOW.getTime()
  );
  assert.equal(
    deviceInstantOrNow(EARLIEST_DEVICE_INSTANT_MS, NOW).toMillis(),
    EARLIEST_DEVICE_INSTANT_MS
  );
});

test("a stored value that is not a time reads as now", () => {
  for (const value of [undefined, null, "1758790000000", 1.5, Number.NaN]) {
    assert.equal(deviceInstantOrNow(value, NOW).toMillis(), NOW.getTime());
  }
});

test("a request without a whole-millisecond time is refused", () => {
  for (const value of [undefined, null, "1758790000000", 1.5]) {
    assert.throws(
      () => requireDeviceInstant(value, "occurredAtMs", NOW),
      (error: unknown) =>
        error instanceof HttpsError &&
        error.code === "invalid-argument" &&
        /occurredAtMs/.test(error.message)
    );
  }
});
