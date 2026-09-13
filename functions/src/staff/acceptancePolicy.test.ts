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
  invitationExpired: false,
  emailVerified: true,
};

// The tokenless assertion here is the whole of the fix. This state - a verified
// invitee on a pending invitation - was refused forever when the account had
// been created by the invite, because `visibleAcceptanceAllowed` remembered how
// the account came to exist. Nothing in the state distinguishes the two invitees
// any more, because acceptance is about who can read the mail now.
test("a verified invitee can accept by either route", () => {
  assert.equal(invitationAcceptanceViolation("visible", ELIGIBLE), undefined);
  assert.equal(invitationAcceptanceViolation("token", ELIGIBLE), undefined);
});

test("the tokenless route still requires a verified address", () => {
  assert.equal(invitationAcceptanceViolation("visible", {
    ...ELIGIBLE,
    emailVerified: false,
  }), "email_unverified");
  assert.equal(invitationAcceptanceViolation("token", {
    ...ELIGIBLE,
    emailVerified: false,
  }), undefined);
});

test("the seven days the email promises now bind both routes", () => {
  const expired = {...ELIGIBLE, invitationExpired: true};
  assert.equal(invitationAcceptanceViolation("token", expired), "invitation_expired");
  assert.equal(invitationAcceptanceViolation("visible", expired), "invitation_expired");
});

test("consuming either route closes both token and tokenless acceptance", () => {
  const consumed = {...ELIGIBLE, invitationConsumed: true};
  assert.equal(invitationAcceptanceViolation("token", consumed), "invitation_consumed");
  assert.equal(invitationAcceptanceViolation("visible", consumed), "invitation_consumed");
});
