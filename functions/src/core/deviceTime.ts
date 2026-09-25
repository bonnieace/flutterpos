import {Timestamp} from "firebase-admin/firestore";
import {HttpsError} from "firebase-functions/v2/https";

/**
 * **When a queued change happened is the device's to say, 2026-09-25.**
 *
 * A device records a change the moment somebody saves it and sends it whenever
 * it next can - an hour later, or the next morning. Until this date every
 * callable stamped the server's own clock as the moment stock moved, so a
 * delivery received offline on the 24th and sent on the 25th was reported, listed
 * and ledgered on the 25th. The server's time is still written beside it, as
 * `recordedAt` or `createdAt`: that one says when the change *arrived*.
 */

/**
 * The earliest instant a device can mean. Anything before it is a clock that was
 * never set, and a record dated 1970 would vanish from every period anybody asks
 * about.
 */
export const EARLIEST_DEVICE_INSTANT_MS = Date.UTC(2020, 0, 1);

/**
 * [value], a device's milliseconds since the epoch, as the server will record it.
 *
 * **Corrected rather than refused.** A time after [now] is a clock running fast -
 * nothing happened after it reached here - and one before 2020 is a clock never
 * set; both become [now]. Refusing either would strand the change on the device
 * that holds it, where a refused record cannot be cleared.
 *
 * Anything that is not a whole number of milliseconds becomes [now] too. Only
 * [requireDeviceInstant] refuses that, because only a request can be malformed:
 * a stored document written by an older device is not a caller to answer.
 */
export function deviceInstantOrNow(value: unknown, now: Date = new Date()): Timestamp {
  const nowMs = now.getTime();
  if (
    typeof value !== "number" ||
    !Number.isSafeInteger(value) ||
    value < EARLIEST_DEVICE_INSTANT_MS ||
    value > nowMs
  ) {
    return Timestamp.fromMillis(nowMs);
  }
  return Timestamp.fromMillis(value);
}

/**
 * The `occurredAtMs` a queued request carries, read as [deviceInstantOrNow]
 * reads it. A request without one is a caller defect and is refused.
 */
export function requireDeviceInstant(
  value: unknown,
  label: string,
  now: Date = new Date()
): Timestamp {
  if (typeof value !== "number" || !Number.isSafeInteger(value)) {
    throw new HttpsError(
      "invalid-argument",
      `${label} must be the whole milliseconds since the epoch at which the change was made.`
    );
  }
  return deviceInstantOrNow(value, now);
}
