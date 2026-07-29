import assert from "node:assert/strict";
import test from "node:test";
import {
  createInvitationProof,
  INVITATION_TOKEN_BYTES,
  isRecentAuthentication,
  verifyInvitationProof,
} from "./invitationProof";

const SECRET = "staff-invitation-test-secret-with-32-bytes";
const BINDING = {
  tenantId: "tenant-1",
  uid: "user-1",
  invitedEmail: "person@example.com",
  invitationVersion: 3,
};

test("invitation proof uses 32 bytes and verifies only its exact binding", () => {
  const proof = createInvitationProof(
    BINDING,
    SECRET,
    Buffer.alloc(INVITATION_TOKEN_BYTES, 7)
  );

  assert.equal(Buffer.from(proof.token, "base64url").length, 32);
  assert.equal(verifyInvitationProof(
    BINDING,
    proof.token,
    proof.tokenHash,
    proof.tokenKeyVersion,
    SECRET
  ), true);
  assert.equal(verifyInvitationProof(
    {...BINDING, tenantId: "other-tenant"},
    proof.token,
    proof.tokenHash,
    proof.tokenKeyVersion,
    SECRET
  ), false);
  assert.equal(verifyInvitationProof(
    {...BINDING, invitationVersion: 4},
    proof.token,
    proof.tokenHash,
    proof.tokenKeyVersion,
    SECRET
  ), false);
});

test("invitation proof rejects a modified token or unsupported key version", () => {
  const proof = createInvitationProof(BINDING, SECRET, Buffer.alloc(32, 9));
  const replacement = proof.token.endsWith("a") ? "b" : "a";
  const modifiedToken = `${proof.token.slice(0, -1)}${replacement}`;

  assert.equal(verifyInvitationProof(
    BINDING,
    modifiedToken,
    proof.tokenHash,
    proof.tokenKeyVersion,
    SECRET
  ), false);
  assert.equal(verifyInvitationProof(
    BINDING,
    proof.token,
    proof.tokenHash,
    "v0",
    SECRET
  ), false);
});

test("recent authentication accepts at most five minutes and rejects future claims", () => {
  const now = Date.UTC(2026, 6, 29, 12, 0, 0);
  const nowSeconds = Math.floor(now / 1000);

  assert.equal(isRecentAuthentication(nowSeconds - 300, now), true);
  assert.equal(isRecentAuthentication(nowSeconds - 301, now), false);
  assert.equal(isRecentAuthentication(nowSeconds + 1, now), false);
  assert.equal(isRecentAuthentication("recent", now), false);
});
