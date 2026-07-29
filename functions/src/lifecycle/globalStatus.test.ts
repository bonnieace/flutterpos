import assert from "node:assert/strict";
import test from "node:test";
import {HttpsError} from "firebase-functions/v2/https";
import {requireGlobalStatus} from "./globalStatus";

test("global status parsing is canonical and fail-closed", () => {
  assert.equal(requireGlobalStatus("active"), "active");
  assert.equal(requireGlobalStatus("disabled"), "disabled");
  assert.throws(
    () => requireGlobalStatus("DISABLED"),
    (error: unknown) => error instanceof HttpsError && error.code === "invalid-argument"
  );
  assert.throws(
    () => requireGlobalStatus("suspended"),
    (error: unknown) => error instanceof HttpsError && error.code === "invalid-argument"
  );
});
