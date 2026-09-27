import {logger} from "firebase-functions";

/**
 * Logs a failure that a `catch` block absorbs instead of letting it escape.
 *
 * The runtime logs whatever escapes a function, and Error Reporting groups it.
 * A failure written to a Firestore document instead - a delivery's
 * `lastErrorCode`, an operation's quarantine - leaves no log line at all, so
 * nothing alerts on it. This puts one back at ERROR, carrying the original
 * stack so Error Reporting can group it.
 *
 * **Fields carry ids and safe codes only.** Never a recipient address, a
 * payload or an action link: the delivery records hold an HMAC of the
 * recipient precisely so that no store outside Auth names them.
 */
export function logAbsorbedFailure(
  event: string,
  error: unknown,
  fields: Record<string, string | number | boolean | undefined> = {}
): void {
  const entry = absorbedFailureEntry(event, error, fields);
  logger.error(entry.reported, entry.fields);
}

/** The log entry, separated from the transport so it can be tested. */
export function absorbedFailureEntry(
  event: string,
  error: unknown,
  fields: Record<string, string | number | boolean | undefined>
): {reported: Error; fields: Record<string, unknown>} {
  const cause = error instanceof Error ?
    error :
    new Error(`A non-Error value was thrown (${typeof error}).`);
  const reported = new Error(`${event}: ${cause.message}`);
  // The header names the event; the frames are where the cause was thrown,
  // which is what Error Reporting groups on.
  const frames = cause.stack?.split("\n").slice(1).join("\n");
  if (frames) reported.stack = `${cause.name}: ${reported.message}\n${frames}`;
  const safe: Record<string, unknown> = {event, errorName: cause.name};
  for (const [key, value] of Object.entries(fields)) {
    if (value !== undefined) safe[key] = value;
  }
  return {reported, fields: safe};
}
