import assert from "node:assert/strict";
import test from "node:test";
import {rehostActionLink} from "./actionLink";

const generated = "https://multitenant-pos-b8326.firebaseapp.com/__/auth/action" +
  "?mode=resetPassword&oobCode=ABC-123_x&apiKey=key&" +
  "continueUrl=https%3A%2F%2Fauth.uzapay.co.ke%2Fauth%2Fpassword-reset-complete&lang=en";

test("an action link moves onto the origin with its path and query intact", () => {
  const moved = new URL(rehostActionLink(generated, "https://auth.uzapay.co.ke"));
  const original = new URL(generated);
  assert.equal(moved.origin, "https://auth.uzapay.co.ke");
  assert.equal(moved.pathname, "/__/auth/action");
  assert.deepEqual([...moved.searchParams], [...original.searchParams]);
});

test("an empty origin leaves the link exactly as Auth made it", () => {
  assert.equal(rehostActionLink(generated, ""), generated);
});

test("a link that is not the action handler is not touched", () => {
  const other = "https://auth.uzapay.co.ke/staff/invitation?invitationToken=t";
  assert.equal(rehostActionLink(other, "https://example.org"), other);
});

test("an origin that is not a bare HTTPS origin is refused", () => {
  for (const origin of [
    "http://auth.uzapay.co.ke",
    "https://auth.uzapay.co.ke/__/auth/action",
    "https://auth.uzapay.co.ke/?x=1",
    "auth.uzapay.co.ke",
  ]) {
    assert.throws(() => rehostActionLink(generated, origin), Error, origin);
  }
});
