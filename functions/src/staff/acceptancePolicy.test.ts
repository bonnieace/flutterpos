import assert from "node:assert/strict";
import test from "node:test";
import {invitationAcceptanceViolation} from "./acceptancePolicy";

const ELIGIBLE = {
  callerUid: "user-1",
  invitedUid: "user-1",
  currentEmail: "person@example.com",
  invitedEmail: "person@example.com",
  tenantStatus: "active",
  membershipStatus: "pending",
  membershipInvitationStatus: "pending",
  invitationStatus: "sent",
  invitationConsumed: false,
  emailVerified: true,
  visibleAcceptanceAllowed: true,
};

test("an existing verified user can accept a visible pending invitation", () => {
  assert.equal(invitationAcceptanceViolation("visible", ELIGIBLE), undefined);
});

test("new or initially unverified identities require versioned proof", () => {
  assert.equal(invitationAcceptanceViolation("visible", {
    ...ELIGIBLE,
    visibleAcceptanceAllowed: false,
  }), "versioned_proof_required");
  assert.equal(invitationAcceptanceViolation("visible", {
    ...ELIGIBLE,
    emailVerified: false,
  }), "email_unverified");
  assert.equal(invitationAcceptanceViolation("token", {
    ...ELIGIBLE,
    emailVerified: false,
    visibleAcceptanceAllowed: false,
  }), undefined);
});

test("consuming either route closes both token and tokenless acceptance", () => {
  const consumed = {...ELIGIBLE, invitationConsumed: true};
  assert.equal(invitationAcceptanceViolation("token", consumed), "invitation_consumed");
  assert.equal(invitationAcceptanceViolation("visible", consumed), "invitation_consumed");
});
