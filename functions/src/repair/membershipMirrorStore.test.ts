import assert from "node:assert/strict";
import test from "node:test";
import {membershipRepairRetryDelayMilliseconds} from "./membershipMirrorStore";

test("membership repair retries back off and remain bounded", () => {
  assert.equal(membershipRepairRetryDelayMilliseconds(1), 30_000);
  assert.equal(membershipRepairRetryDelayMilliseconds(2), 60_000);
  assert.equal(membershipRepairRetryDelayMilliseconds(11), 6 * 60 * 60 * 1000);
  assert.equal(membershipRepairRetryDelayMilliseconds(100), 6 * 60 * 60 * 1000);
  assert.equal(membershipRepairRetryDelayMilliseconds(Number.NaN), 30_000);
});
