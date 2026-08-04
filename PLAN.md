# Chilltent POS — Frozen Implementation Baseline

## Summary

Adopt and freeze this architecture:

```text
One Firebase Auth identity
→ multiple canonical tenant memberships
→ one selected TenantSession per app instance
→ completely isolated business operations
```

Each business has independent approval, staff, stock, sales, shifts, returns, configuration, subscription, branding, reporting, and suspension.

Final decisions:

- Membership mirrors and counters support routing only.
- Canonical tenant and staff documents authorize every operation.
- Tenant APIs accept a tenant ID, but a shared wrapper verifies the exact membership.
- Existing verified users may accept visible pending invitations inside the app.
- New and unverified identities require versioned invitation proof.
- Platform privilege requires an Auth claim, an active platform record, and an authoritative membership scan.
- Global disabling is implemented as a recoverable saga.
- An operator-only owner-recovery CLI covers normal and exceptional emergencies.
- Hive provides cross-platform offline checkout and controls Firestore submission.
- Architecture changes after this baseline become separate implementation tickets.

## Standing decisions and unreachable capabilities

Added 2026-08-01 after an audit of the frozen spec against what is actually
reachable in the app. The per-chunk handovers below track what each **frontend**
chunk deliberately skipped; nothing tracked server capabilities that shipped
without a client, which is how the first item here went unnoticed for roughly
thirty sessions. Keep this section current: a capability that is built, tested,
and unreachable is not done.

### Decided: a sale records how it was paid for, chosen manually

Resolved 2026-08-01 by the product owner. The checkout flow lets the cashier
select the tender at the point of sale - **cash, M-Pesa, or card** - and records
it on the sale. No payment *integration* is in scope: nothing authorizes a card,
queries an M-Pesa STK push, or reconciles a provider statement. The recorded
tender is the cashier's assertion about how the customer paid, and the surfaces
that display it must say so rather than implying the payment was verified.
Integration remains deferred and becomes its own ticket when it is wanted.

That decision unblocks the checkout screen, and it is a **change to a frozen
contract**, so it is a deliberate versioned ticket rather than a field somebody
adds in passing. It was implemented as the payload v2 chunk on **2026-08-02**;
see the handoff at the end of this file. All five hazards are now settled, and
these are the answers, not open questions:

1. **A v1 payload still parses, and is never rewritten.** The payload contract
   is `supportedCheckoutSalePayloadSchemaVersions = {1, 2}` in
   `lib/checkout/checkout_sale.dart`. New drafts are always v2; a v1 draft saved
   before the upgrade still parses, still submits, and writes a sale carrying
   `payloadSchemaVersion: 1` and no tender. Version is read from the payload
   itself, never from the current constant.
2. **That is exactly why the hash still matches.** `checkoutPayloadHash` covers
   the whole payload, so migrating a stored draft to v2 would change its hash -
   and `_parseRecord` re-derives the hash on every read, so an in-place
   migration would also make every stored record `malformed_record`. Nothing
   migrates. An `awaiting_confirmation` v1 record therefore still matches the
   server sale it is waiting on.
3. **The `sales` create rule now constrains the tender**, through
   `validSaleTender` in `firestore.rules`: v1 must carry no tender, v2 must name
   one of `cash`, `mpesa`, `card`. The key set is still not frozen with
   `hasOnly`. The rule also now **requires** `payloadSchemaVersion` on create,
   which it previously ignored entirely.
4. **The tender does not appear in the receipt number, and the frozen pattern
   was not touched.** `CT-A7F-20260729-0042` is an identity, not a description:
   it must stay derivable from device, business date, and sequence alone, and it
   is proved by a Rules regex plus three Dart call sites. When receipt
   *printing* arrives, the tender belongs in the printed body, which does not
   exist yet and is a separate chunk.
5. **Reconciliation was not touched and needs no change.** `aggregateSales`
   reads only the fields it names. A per-tender breakdown remains new work in
   `functions/src/operations/domain.ts` and is **not** part of recording the
   tender.

What remains open is the **write** half: nothing constructs a
`CheckoutDraftRequest` outside tests, so no cashier can choose a tender until
the checkout screen exists. The read half is reachable today - sale history and
receipt lookup both display it.

### Built, tested, and unreachable

Every row is server-side complete with passing tests and **no client entry
point**. The first three were never listed as deferred anywhere; they were
dropped, not postponed.

| Capability | State | Deferred on purpose? |
| --- | --- | --- |
| `sendAccountVerification` | **Reached 2026-08-01.** The business selector offers it to an unverified identity. | Resolved |
| `requestPasswordReset` | **Blocked on App Check** - see below. Still no caller. | Now declared |
| `getMyEmailDeliveryStatus` | **Reached 2026-08-01.** Checked once a verification request is accepted. | Resolved |
| `getSalesComparison` | **Reached 2026-08-02.** The daily summary opens period totals; it answers for unreconciled days, which `daily_metrics` cannot. | Resolved |
| `requestTenantReconciliation` | **Reached 2026-08-02.** The reconciliation status route lets an owner or administrator ask for a run. | Resolved |
| Subscription | Rules exist and `TenantPaths.currentSubscription` exists; **no repository reads it at all**. Spec line 14 names subscription as a per-business concern. | Yes, never revisited |
| Product cost / profit | `profit` is parsed at `lib/reporting/daily_metrics.dart:64` and deliberately never displayed. | Yes |

The verification half of that lockout was closed on 2026-08-01; see the handoff
at the end of this file. `emailVerified` still gates requesting a business
(`lib/tenancy/tenant_request.dart:68`) and accepting a visible invitation
(`lib/tenancy/tenant_visible_invitation_acceptance.dart:65`), but the business
selector now offers the identity the one action that releases it.

### Open decision: public password reset needs App Check, which this app has none of

Found 2026-08-01 while implementing the verification half, and it is a genuine
blocker rather than an omission. `requestPasswordReset` is declared with
`enforceAppCheck: true` **and** calls `requireAppCheckedPublic`, which throws
`failed-precondition` outright when `request.app` is absent. The Flutter app has
no `firebase_app_check` dependency and no initialization, so the callable would
reject every request the client could make today.

That cannot be worked around by signing in first: password reset is a *public*
endpoint, used precisely by someone who cannot authenticate. So unlike every
other callable, it has no authenticated fallback.

The harder half is Windows. This app targets `android`, `ios`, `linux`, `macos`,
`web`, and `windows`, and the frozen spec already records that built-in App Check
providers cover only Apple, Android, and web, with Windows relying on
authentication until a tested custom provider exists. A public endpoint has no
authentication to rely on, so **in-app password reset is structurally
unreachable on Windows** under the current architecture - and Windows is the
platform the whole Hive offline design exists for.

Someone has to choose one of these; none is obviously right, and all three are
outside what a bounded chunk should decide on its own:

1. Add `firebase_app_check` and offer in-app reset only on Apple, Android, and
   web, telling a Windows user to reset from another device. Cheapest, and it
   leaves the primary POS platform without recovery.
2. Implement the custom App Check provider the spec already anticipates for
   Windows, then offer reset everywhere. Most faithful to the architecture and
   by far the most work.
3. Relax `requestPasswordReset` to accept an unattested request under a
   different rate-limiting and abuse control. This weakens a deliberate
   enumeration and abuse boundary and should not be done casually - the endpoint
   is public and unauthenticated by design.

Until this is decided, a user who forgets their password has no recovery path
inside the app on any platform.

Recommended order for the next sessions: the checkout screen and the tender
decision above, which is now the largest reachable piece of product; then this
password-reset decision; then the smaller unreachable rows. The email loop
itself is closed - an identity can ask for its verification email and is told
when the address cannot receive one.

### Checked and found sound

Recorded so the audit is not repeated. These looked like gaps and are not:

- The "Required tests" list below is genuinely honoured, including two cashiers
  on one device, counters independent per device/tenant/date, encrypted restart,
  Hive box reopen, mirror repair, and suppression/complaint/webhook coverage.
- The cashier cross-tenant shift restriction is implemented as
  `_otherTenantShiftOpen` in `lib/shift/shift_controller.dart:461`, despite
  appearing in several early exclusion lists.
- App Check sets `enforceAppCheck: true` on the public password-reset endpoint
  only, which matches "validated platforms only" plus the Windows caveat.
- `lib/main copy.dart` is a 48-line stray file in `lib/` and should be deleted;
  it is noted here only so nobody mistakes it for a live entry point.

## Identity, Tenancy, and Public Interfaces

### Environments

```text
dev      multitenant-pos-b8326
staging  chilltent-pos-staging
prod     chilltent-pos-prod
```

CI must always receive an explicit environment/project mapping.

### Root model

```text
/users/{uid}
  email
  displayName
  accountType                 // tenant_user | platform_admin
  identityOrigin              // self_signup | staff_invitation | platform_bootstrap
  identityTransition?         // granting_platform | cleanup_pending
  globalStatus                // active | disabled
  defaultTenantId?
  membershipCount
  ownedTenantCount
  ownedActiveTenantCount
  createdAt
  updatedAt

/users/{uid}/tenant_memberships/{tenantId}
  tenantId
  tenantName
  tenantSlug
  role                        // owner | admin | manager | cashier
  membershipStatus            // pending | active | inactive
  tenantStatus                // pending | active | suspended | rejected | archived
  invitationStatus
  isOwner
  createdAt
  joinedAt
  updatedAt
  mirrorVersion
```

Mirrors, counters, and `defaultTenantId` are advisory. They never authorize access.

Canonical authorization remains:

```text
/tenants/{tenantId}
/tenants/{tenantId}/staff/{uid}
```

Every canonical staff document contains a server-controlled `uid` field to support authoritative collection-group scans.

Additional platform collections:

```text
/platform_config
/platform_audit_logs
/platform_user_operations
/platform_membership_repair_runs
/owner_recovery_cases
/email_deliveries
/email_suppressions
/tenant_slugs
```

### Tenant routing

```text
listMyTenants({
  pageSize?,
  cursor?
})
```

Behavior:

- Default page size: 20.
- Maximum: 50.
- Stable ordering by membership creation time descending, then tenant ID.
- Server-issued opaque cursor.
- Each result overlays current canonical tenant and staff states.

Return:

```text
items
nextCursor
hasMore
```

Login order:

1. Prefer `{uid}:lastSelectedTenantId` if canonically valid.
2. Otherwise use `defaultTenantId` if canonically valid.
3. Otherwise auto-open the sole accessible tenant.
4. Otherwise show the business selector.
5. Show pending, rejected, suspended, and inactive memberships without granting operational access.

Opening a tenant updates only the device-local last selection. `defaultTenantId` changes only through an explicit “Make default” action.

### Business limits

Server configuration:

```text
maxPendingTenantsPerUser: 3
maxTenantRequestsPer24Hours: 5
maxOwnedActiveTenantsPerUser: 25
```

Enforce active-owned limits when requesting, approving, or reactivating a tenant.

These limits can later depend on an account-level entitlement, while each tenant retains its independent subscription:

```text
/tenants/{tenantId}/subscription/current
```

### Shared authorization

```text
requireAppCheckedPublic()
requireAuthenticatedUser({allowUnverified})
requireVerifiedTenantApplicant()
requirePendingTenantInvite(tenantId)
requireTenantMember(tenantId, allowedRoles)
requirePlatformAdmin()
```

`requireTenantMember` verifies:

```text
Auth exists
root globalStatus == active
tenant exists and is active
canonical tenant staff membership exists
staff status is active
tenant-local role is allowed
```

No handler implements these checks independently.

Idempotency keys are scoped by:

```text
actorUid + operation + tenantId/global-scope + requestId
```

### Public callable interfaces

```text
sendAccountVerification({requestId})

requestPasswordReset({email, requestId})

getMyEmailDeliveryStatus()

listMyTenants({pageSize?, cursor?})

setDefaultTenant({tenantId, requestId})

requestTenant({name, slug, requestId})

setTenantLifecycle({
  tenantId,
  status,
  reason?,
  requestId
})

setGlobalUserStatus({
  uid,
  status,
  reason,
  requestId
})

inviteStaff({
  tenantId,
  email,
  name,
  phone,
  role,
  requestId
})

updateStaffUser({
  tenantId,
  uid,
  name,
  phone,
  role,
  requestId
})

setStaffStatus({
  tenantId,
  uid,
  status,
  requestId
})

replacePendingStaffEmail({
  tenantId,
  uid,
  email,
  requestId
})

resendStaffInvitation({
  tenantId,
  uid,
  requestId
})

cancelTenantInvitation({
  tenantId,
  uid,
  reason,
  requestId
})

acceptTenantInvitation({
  tenantId,
  invitationVersion,
  invitationToken,
  requestId
})

acceptVisibleTenantInvitation({
  tenantId,
  requestId
})

reviewEmailSuppression({
  email,
  action,                   // inspect | clear
  reason,
  confirmation?,
  evidenceReference?,
  requestId
})

adjustStock({
  tenantId,
  productId,
  quantityDelta,
  type,
  reason,
  requestId
})

verifyReturnAndRestoreStock({
  tenantId,
  returnId,
  requestId
})

getSalesComparison({
  tenantId,
  previousStartDate,
  previousEndDate,
  soldById?,
  categoryId?
})

requestTenantReconciliation({
  tenantId,
  mode,                     // incremental | full
  requestId
})
```

## Platform, Ownership, and Membership Integrity

### Authoritative platform-admin eligibility

Platform access requires:

```text
request.auth.token.platformRole == "superAdmin"
users/{uid}.accountType == "platform_admin"
users/{uid}.globalStatus == "active"
```

`grant-platform-admin` must not trust counters.

Grant procedure:

1. Use counters only as a preliminary warning.
2. Transactionally place `identityTransition=granting_platform` on the root user.
3. All tenant-creation and invitation Functions reject identities with an active identity transition.
4. Run `collectionGroup("staff").where("uid", "==", targetUid)`.
5. Search tenants where `ownerUid == targetUid`.
6. Confirm there is no active, pending, inactive, or owner membership.
7. Confirm no unresolved tenant invitation exists.
8. Set `accountType=platform_admin`.
9. Merge `platformRole=superAdmin` into existing claims.
10. Clear the transition and audit completion.

If any canonical membership exists, clear the transition and reject the grant.

The same canonical scans are mandatory before deleting an abandoned invitation-created identity. A zero membership counter is never sufficient.

`requestTenant` rejects platform identities. `inviteStaff` rejects platform targets. Platform identities cannot have tenant memberships in v1.

### Owner and administrative-principal invariant

Every non-archived tenant has exactly one owner:

```text
tenant.ownerUid == owner staff UID
owner staff.role == owner
```

Owner behavior:

- Has all administrator permissions.
- Cannot be demoted or deactivated through ordinary APIs.
- Is counted as an administrative principal.

Administrative principal:

```text
globally active user
AND active tenant membership
AND role is owner or admin
```

Normal membership and role operations must retain at least one administrative principal.

Global security disabling is the deliberate exception: it proceeds even if it removes the last available principal. It then:

- Creates a critical `tenant_owner_unavailable` or `no_active_administrator` alert.
- Identifies all affected tenants.
- Notifies platform operators.
- Does not suspend those tenants automatically.
- Directs operators to owner recovery.

### Global-status saga

```text
/platform_user_operations/{requestId}
  uid
  targetStatus
  firestoreStatus
  authStatus
  claimStatus
  status                    // pending | completed | partially_failed
  attemptCount
  requestedBy
  reason
  affectedTenantIds
  createdAt
  updatedAt
  completedAt
  lastErrorCode
```

Disable order:

1. Create the operation and set root `globalStatus=disabled`.
2. Determine tenants that will lose an administrative principal.
3. Create critical alerts where necessary.
4. Disable Firebase Auth.
5. Remove platform privilege if present.
6. Revoke refresh tokens.
7. Finish audits and operation status.

Reactivate order:

1. Enable Firebase Auth.
2. Set root status active.
3. Complete audits.
4. Require a new sign-in.
5. Never restore platform claims automatically.

A private retry worker resumes partially failed operations. Root status is checked by Rules and Functions, so a failed Auth update does not restore access.

### Operator-only owner-recovery CLI

Rename the recovery tool:

```text
owner-recovery
```

It is unavailable through Flutter and the dashboard but requires network access to Firebase.

Normal recovery:

```text
replacement is already an active admin
```

Exceptional recovery:

```text
replacement is a verified, globally active tenant user
but is not yet an administrator in the stranded tenant
```

Exceptional recovery additionally requires:

- A recorded `/owner_recovery_cases/{caseId}`.
- Documentary/support-case reference.
- Explicit `--exceptional` mode.
- Typed confirmation of tenant slug, old UID, and replacement UID.
- A second confirmation flag.
- A written reason.
- Verification that the replacement is not a platform identity.

Default outcome:

```text
old owner:
  role = admin
  status = inactive

replacement:
  role = owner
  status = active
```

The transaction updates the tenant owner, canonical staff records, user mirrors, owner counters, lifecycle history, tenant audit, and platform audit.

The exceptional path creates the replacement’s tenant membership as part of the transaction. Both paths preserve the exactly-one-owner invariant.

### Membership-mirror repair

Normal membership changes update canonical membership and mirror transactionally. Tenant-wide name/status changes fan out asynchronously.

Run:

- Targeted repair after failed fan-out or membership operations.
- Weekly paginated full repair.

Canonical data always wins.

Repair:

- Missing or orphaned mirrors.
- Wrong tenant, role, membership, invitation, or lifecycle status.
- Incorrect membership/owner counts.
- Wrong owner flag.
- Invalid `defaultTenantId`.
- Mirror entries without canonical staff membership.

Repair summaries are audited but never used as authorization.

## Invitations and Email

### Invitation proof

Server-only invitation state:

```text
/tenants/{tenantId}/staff_invitations/{uid}
  invitationVersion
  invitationTokenHash
  invitationTokenKeyVersion
  invitationIssuedAt
  invitationExpiresAt
  invitationTokenUsedAt
  invitationStatus
  invitedEmail
  invitedBy
  latestDeliveryId
```

Each invitation attempt:

- Generates 32 random bytes.
- Stores only a versioned HMAC.
- Increments `invitationVersion`.
- Expires after seven days.
- Invalidates older versions.
- Gets its own email-delivery record.

Token acceptance requires matching tenant, UID, invited email, version, hash, expiry, unused state, and authentication no older than five minutes.

### Existing-user in-app acceptance

`acceptVisibleTenantInvitation` is permitted only when:

```text
caller UID is the exact invited UID
root globalStatus == active
Firebase email is verified
current email matches invitedEmail
canonical membership is pending
invitationStatus is pending or sent
auth_time is no older than five minutes
tenant is active
```

Before calling, Flutter must visibly show:

```text
business name
invited role
accept/cancel confirmation
```

The transaction:

- Activates canonical staff membership.
- Updates the user membership mirror.
- Marks invitation accepted.
- Consumes/invalidates any outstanding token.
- Writes tenant audit.

This route is for existing verified users only. Versioned token proof remains mandatory for new identities, unverified identities, password setup, and direct email-link acceptance.

### Email correction

A tenant administrator never changes a shared identity’s global Auth email.

Correcting a pending address cancels that membership invitation and creates or reuses the identity for the corrected address.

Before disabling or cleaning an abandoned provisional UID, perform:

```text
canonical staff collection-group scan
tenant owner query
pending invitation scan
identity-transition check
```

### Password-reset task

The public endpoint enqueues a private Cloud Task containing the normalized email. The worker performs Auth lookup and creates an email delivery only for an eligible identity.

The plaintext email never enters Firestore or normal logs. The public response is always:

```json
{"accepted": true}
```

Before sending, the delivery worker confirms the Auth user’s current email HMAC still matches the requested recipient hash.

### Suppression mapping

Permanent global suppression:

```text
hard bounce
invalid recipient
spam complaint
provider block whose exact reason confirms permanent invalidity,
prior complaint, or prior hard bounce
```

Temporary failure:

```text
soft bounce
mailbox full
greylisting
rate limit
provider timeout
temporary policy/reputation block
unknown blocked reason
```

Unknown `blocked` events default to temporary failure. Only a versioned, tested reason-code mapping may classify them as permanent.

### Suppression inspection and recovery

`reviewEmailSuppression` is platform-admin-only.

It:

1. Normalizes the supplied email in memory.
2. Calculates current and supported previous HMAC versions.
3. Finds matching suppression records without storing the plaintext.
4. Returns only redacted category, event date, status, and provider reason class.
5. Audits inspection and clearing.

Clearing behavior:

- Hard-bounce or invalid-recipient suppression requires confirmation that the address was corrected or independently verified.
- Complaint suppression requires `confirmation=clear_spam_complaint` and an evidence/support reference.
- Clearing marks the suppression inactive with `clearedAt`, `clearedBy`, and reason; it does not delete its history.

Tenant administrators cannot inspect or clear global suppression.

An authenticated user may call `getMyEmailDeliveryStatus()` for their own Auth email. It returns only:

```text
available
or
Email delivery unavailable. Check the address or contact support.
```

The public password-reset flow never reveals this state.

### Brevo webhook privacy

Persist normalized webhook events only:

```text
providerMessageId
eventType
providerTimestamp
recipientHash
normalizedReasonCode
processedAt
payloadSchemaVersion
```

Unparseable payloads may be encrypted in quarantine for seven days. No raw Brevo payload is retained indefinitely.

Continue using provider-independent delivery, Firebase Admin action links, Brevo HTTP API, authenticated webhooks, source-controlled templates, SPF, DKIM, DMARC, custom return path, and disabled tracking.

## Offline Operations, Stock, and Receipts

### Tenant switching

Block switching for:

- Unsynchronized checkout.
- Checkout submission in flight.
- Other tracked pending writes.
- Unfinished cash count or shift closing.
- Unsaved tenant-scoped workflows.
- Lack of connectivity for target validation.

A server-confirmed open shift alone does not block switching.

Owners and managers may inspect another tenant while the original shift remains open. A cashier cannot open checkout in a second tenant on the same device while another tenant’s shift remains open.

Returning to a tenant restores only its own validated shift.

### Hive checkout state machine

```text
saved_offline
→ submitting
→ awaiting_confirmation
→ confirmed | needs_attention
```

Outbox key:

```text
{uid}:{tenantId}:{checkoutId}
```

Each record contains submission attempt, persistent lease, retry time, payload, and payload hash.

Only one sync worker may call `batch.commit()` for a checkout. Lease expiry permits confirmation checks, never blind resubmission.

On restart:

1. Inspect the local deterministic sale.
2. Wait if Firestore reports pending writes.
3. Query the server when online.
4. Confirm a matching hash.
5. Flag a mismatching hash.
6. Retry only when no pending write and no server sale exist.

Hive stores encrypted tenant-specific product, price, configuration, shift, draft, printer, and sync state.

Firestore offline persistence is supported for Android, Apple, and web, but not Windows, so Hive remains the cross-platform offline source. [Firebase offline documentation](https://firebase.google.com/docs/firestore/manage-data/enable-offline)

### Stock rules

```text
Sale-line quantity:
  positive integer

Product quantity:
  signed integer
  may be positive, zero, or negative
```

Checkout uses:

```dart
FieldValue.increment(-quantity)
FieldValue.serverTimestamp()
```

Direct checkout updates may change only product `quantity` and `updatedAt`. Positive stock changes require trusted adjustment, return, or opening/import logic.

### Receipt sequence

Device receipt counter key:

```text
{tenantId}:{deviceId}:{businessDate}:receiptCounter
```

It is deliberately not scoped by cashier UID.

Use an atomic Hive operation guarded by the checkout coordinator’s local lock. Two checkouts on the same device cannot receive the same counter value.

Receipt:

```text
CT-A7F-20260729-0042
```

The sale records cashier UID separately. `saleId` remains the database identity.

## Reconciliation, Rules, Testing, and Rollout

### Reconciliation

Immediate sale triggers perform lightweight checks and merge one job per tenant/five-minute server-receipt bucket.

Nightly processing:

- Runs at 05:30 `Africa/Nairobi`.
- Paginates tenants through chained Cloud Tasks.
- Enqueues one deterministic task per active tenant.
- Regenerates dirty daily metrics and verifies stock/shifts.

Weekly checkpoints retain expected and observed quantities separately. Staggered monthly full reconciliation validates the checkpoint chain. Reconciliation never silently changes stock.

### Rules

Firestore Rules must:

- Authorize from root global status, canonical tenant, and canonical staff membership.
- Never authorize from mirrors or counters.
- Require both platform claim and active platform record.
- Reject tenant membership operations involving platform identities.
- Keep invitation proof, suppression, delivery, repair, lifecycle, saga, subscription, and audit records server-write-only.
- Deny positive direct stock updates, return approval, and legacy root operational collections.

App Check built-in providers cover Apple, Android, and web. Firebase supports custom providers for other platforms, including desktop environments. Windows will rely on authentication, canonical authorization, rate limiting, and idempotency until a tested custom provider is implemented. [Firebase custom App Check providers](https://firebase.google.com/docs/app-check/custom-provider)

### Required tests

Add tests proving:

- Platform granting performs canonical scans despite zero counters.
- Platform grant and tenant invitation cannot race through `identityTransition`.
- Abandoned identities are never deleted while a canonical membership exists.
- Every non-archived tenant has exactly one owner.
- Normal staff operations retain an active administrative principal.
- Global disable proceeds but alerts when the last principal becomes unavailable.
- Normal and exceptional owner recovery restore a valid owner.
- Existing verified users accept pending invitations in-app without an email token.
- New or unverified users cannot use the tokenless route.
- Token and tokenless acceptance cannot both complete.
- Suppression inspection is platform-only and audited.
- Complaint clearing requires stronger confirmation.
- Public password reset never reveals suppression.
- Two cashiers on one device receive different receipt numbers.
- Receipt counters remain independent across devices, tenants, and business dates.
- Confirmed open shifts do not block owner/manager switching.
- Pending checkout and cash-close workflows do block switching.
- Mirror repair fixes routing state without affecting authorization.
- Windows checkout survives restart using Hive.
- App Check enforcement is enabled only for validated platforms.

### Rollout

1. Freeze schemas, callable contracts, invariants, and indexes.
2. Implement central authorization and idempotency wrappers.
3. Implement canonical platform eligibility scans and identity-transition locks.
4. Implement tenant routing, pagination, local/default selection, and onboarding limits.
5. Implement owner/admin invariants, global-status saga, and owner-recovery CLI.
6. Implement membership mirrors, fan-out, and repair.
7. Implement invitations, tokenless verified-user acceptance, Cloud Tasks password reset, and suppression review.
8. Implement Brevo delivery, webhook normalization, and custom action pages.
9. Implement `TenantSession`, tenant switching, shift restoration, and session epochs.
10. Implement encrypted Hive cache, single-flight checkout, and device receipt counters.
11. Implement stock, sales, returns, subscriptions, reconciliation, checkpoints, and reporting.
12. Complete emulator, multi-device, Windows-offline, email, recovery, and adversarial isolation tests.
13. Deploy development, then staging.
14. Enable App Check only on validated platforms.
15. Promote the identical versioned release to production.

## Assumptions

- The mono-tenant Firebase project remains untouched.
- The shared Firebase projects begin empty.
- Standard users may own or join several tenants.
- Tenant switching requires connectivity; the current tenant remains offline-first.
- Platform identities are dedicated and membership-free.
- Public ownership transfer remains deferred; operator recovery is included.
- Offline revocation takes effect when connectivity returns.
- Consolidated portfolios, shared billing, and group-wide permissions remain future work.

---

## Implementation handoff - 2026-07-29

### Session stop point

The backend described by this baseline is implemented locally and its automated unit/rules suites pass. No Firebase deployment, live Brevo delivery, Cloud Tasks execution, or production data migration was performed in this session. Treat the backend as code-complete for the current scope, but not deployment-complete.

This session intentionally stops before completing the Flutter UI/offline rollout. The next session should start from the deployment and frontend checklist below; it should not rebuild the backend foundations.

### Backend milestone ledger

The following progressive commits are already on branch `multitenant-main`:

- `7b015e8` - multitenant security foundation and shared authorization/idempotency contracts.
- `4c977f4` - canonical platform eligibility and identity-transition protection.
- `7045d2a` - canonical tenant onboarding, routing, pagination, and default selection.
- `9153c97` - exact owner authorization invariant.
- `0c7d9c0` - typed Flutter tenant-session contracts (foundation only, not the completed UI rollout).
- `5505eaf` - canonical tenant-isolation Firestore Rules and rules tests.
- `8568424` - operator owner-recovery workflow and CLI.
- `bf3090a` - tenant lifecycle and recoverable global-user-status control plane.
- `c9f0ca9` - resumable membership mirror/fan-out repair.
- `2306541` - privacy-safe password reset, verification, suppression, Brevo webhook, and platform-alert delivery.
- `3a5b0ae` - secure staff invitation, acceptance, status, replacement, resend/cancel, delivery, and abandoned-identity cleanup.
- `eecac3f` - tenant stock/return/reporting operations and durable reconciliation/checkpoint workers.
- `9f9a41a` - consolidated 44-handler deployment entry point and required Firestore indexes.

The final backend deployment-surface changes are included in the last two commits above:

- `functions/src/operations/**` - stock adjustments, verified return restoration, and management-only sales comparison.
- `functions/src/reconciliation/**` - durable reconciliation jobs, processors, triggers, schedulers, checkpoints, retries, and quarantine.
- `functions/src/index.ts` - the consolidated 44-function export surface; it removes unsafe legacy root `getSalesComparison`, `createStaffUser`, and `toggleStaffStatus` implementations.
- `firestore.indexes.json` - the indexes required by repair, lifecycle, staff cleanup, email retry, platform-alert retry, and reconciliation workers.

This handoff is the final documentation-only commit immediately following `9f9a41a`. Use `git log --oneline -15` and `git status --short` first in the next session; the log is authoritative. No known backend source or backend index changes remain uncommitted. Do not mix the unrelated Firebase client-configuration or Flutter changes listed below into a backend commit.

### Implemented backend behavior

Identity and authorization:

- Every tenant operation authorizes from the canonical root user, tenant, and `tenants/{tenantId}/staff/{uid}` records. Routing mirrors and counters are never authorization sources.
- Platform access requires the Auth claim, active `platform_users/{uid}`, an active root user, no identity transition, and a canonical zero-membership scan.
- Owner and administrative-principal invariants are transactionally enforced. Global disable remains a resumable saga and produces critical alerts when availability is lost.
- Membership fan-out and mirror repair are leased, resumable, retryable, and do not weaken canonical authorization.
- Owner recovery is operator-only. Run `npm run owner-recovery -- ...` from `functions`; read `functions/src/recovery/README.md` and use dry-run before an apply operation.

Staff and email:

- Staff creation is a reservation/provisioning saga with deterministic provisional identities, cleanup leases, canonical eligibility scans before deletion, and PII scrubbing.
- Pending invitations support verified tokenless acceptance and versioned proof acceptance for new/unverified identities. Acceptance re-reads the current Admin Auth user rather than trusting stale token claims.
- Cancellation, replacement, resend, status, and update paths preserve the exact owner/admin-principal invariants and terminalize stale delivery work safely.
- Public password reset is enumeration-resistant. Account verification requires recent authentication. Recipient addresses are bound using a versioned HMAC keyring; plaintext recipients and raw provider webhook payloads are not persisted or logged.
- Brevo delivery disables tracking headers, maps provider failures into finite retry categories, uses authenticated normalized webhooks, and maintains monotonic suppression/delivery state.
- Platform alert fan-out rechecks canonical operator eligibility and persists pagination counters/cursors so retries resume safely.

Operations and reconciliation:

- `adjustStock` is canonical owner/admin/manager-only, idempotent, and writes immutable adjustment, stock-movement, and audit records.
- `verifyReturnAndRestoreStock` is once-only and bounds restoration by immutable sale quantities minus previously verified returns; it does not trust arbitrary return lines.
- `getSalesComparison` is tenant-scoped, management-only, range-bounded, based on immutable snapshots, and rounds deterministically in minor currency units.
- Sale triggers merge into five-minute dirty buckets. Metrics, stock, and shift processors are leased, bounded, resumable, and never mutate stock.
- Stock verification uses commit-ordered movement cursors and expected-versus-observed checkpoint chains. Hot products defer without blocking the entire job, while invalid movement counts remain cumulative.
- Reconciliation quarantines a job after eight consecutive failures and emits a notifier-compatible critical platform alert. Schedulers run nightly at 05:30 Africa/Nairobi, weekly checkpoints at 04:30 Sunday, and staggered monthly discovery at 04:45 daily, with a ten-minute recovery scheduler.

### Current Functions export surface

The consolidated `functions/src/index.ts` loads 44 exports:

```text
acceptTenantInvitation
acceptVisibleTenantInvitation
adjustStock
cancelTenantInvitation
cleanupAbandonedStaffIdentities
consumePendingPlatformAlert
consumeTenantMembershipFanout
deliverAccountVerification
deliverPasswordReset
deliverPlatformAlertNotification
deliverStaffInvitation
getMyEmailDeliveryStatus
getSalesComparison
inviteStaff
listMyTenants
mergeSaleReconciliationJob
receiveBrevoEmailWebhook
repairCanonicalStaffMirror
repairTenantRoutingProjection
replacePendingStaffEmail
requestPasswordReset
requestTenant
requestTenantReconciliation
resendStaffInvitation
retryGlobalUserStatusOperations
retryMembershipRepairTasks
retryPlatformAlertNotifications
retryStaffInvitationDeliveries
retryTenantReconciliationTasks
reviewEmailSuppression
runMembershipRepairTask
runReconciliationTenantDiscoveryTask
runTenantReconciliationTask
sendAccountVerification
setDefaultTenant
setGlobalUserStatus
setStaffStatus
setTenantLifecycle
startNightlyTenantReconciliation
startStaggeredMonthlyReconciliation
startWeeklyMembershipRepair
startWeeklyStockCheckpoints
updateStaffUser
verifyReturnAndRestoreStock
```

Do not re-export the old root-collection staff or reporting handlers.

### Validation evidence

The last full local validation on 2026-07-29 was green:

- From `functions`: `npm test` completed TypeScript compilation and passed **152/152** Node tests.
- From `rules-tests`: the Firestore emulator suite passed **19/19** tests with Java 21 and `--test-concurrency=1`.
- The compiled `functions/lib/index.js` loaded successfully and exposed exactly **44** handlers.
- `firestore.indexes.json` parsed as valid JSON.
- `git diff --check` found no whitespace errors (only Windows line-ending warnings).
- Focused operations/reconciliation coverage passed **15/15** tests and is included in the 152-test total.

Rules emulator command used on this Windows workspace:

```powershell
$env:JAVA_HOME='C:\tmp\chilltent-jdk21\jdk-21.0.12+8'
$env:Path="$env:JAVA_HOME\bin;$env:Path"
$env:DEBUG=''
node node_modules/firebase-tools/lib/bin/firebase.js emulators:exec --config ../firebase.test.json --project demo-multitenant-rules --only firestore "node --test --test-concurrency=1"
```

Do not treat this as a substitute for Functions + Auth + Firestore + Cloud Tasks integration testing. The email/provider paths have deterministic unit coverage but no live Brevo integration result yet.

### Required deployment secrets and parameters

Provision the following Secret Manager values before deploying Functions:

- `TENANT_CURSOR_HMAC_SECRET` - at least 32 random bytes; signs tenant-routing cursors.
- `EMAIL_RECIPIENT_HMAC_KEYRING` - JSON such as `{"currentVersion":"v2","keys":{"v2":"32+ byte random secret","v1":"previous secret"}}`.
- `BREVO_API_KEY` - transactional Brevo API key.
- `BREVO_WEBHOOK_SECRET` - at least 32 random bytes; configure Brevo to send it as `Authorization: Bearer ...` or `x-brevo-webhook-secret`.
- `STAFF_INVITATION_HMAC_SECRET_V1` - at least 32 random bytes; signs invitation proofs.

Set these Firebase Functions string parameters per environment:

- `EMAIL_SENDER_ADDRESS`
- `EMAIL_SENDER_NAME` (defaults to `ChillTent`)
- `PASSWORD_RESET_CONTINUE_URL` (HTTPS)
- `EMAIL_VERIFICATION_CONTINUE_URL` (HTTPS)
- `PLATFORM_ALERTS_URL` (HTTPS)
- `STAFF_INVITATION_ACTION_BASE_URL` (HTTPS)
- `STAFF_INVITATION_SENDER_EMAIL`
- `STAFF_INVITATION_SENDER_NAME` (defaults to `ChillTent`)

Operational key-rotation constraints:

- Retain old recipient-HMAC keys in `EMAIL_RECIPIENT_HMAC_KEYRING` until every live delivery and suppression lookup that references the old version has expired or been migrated.
- `STAFF_INVITATION_HMAC_SECRET_V1` is not a keyring. Retain it through the seven-day invitation lifetime plus a safe rollout overlap; changing it invalidates outstanding proof links.
- Brevo idempotency protection is provider-window-limited (approximately 15 minutes); a retry outside that window can still duplicate a message. The application ledger reduces this risk but cannot eliminate an ambiguous provider response.

### Firebase project, service, and IAM checklist

The working tree currently points the development clients at `multitenant-pos-b8326`. The original plan also names `chilltent-pos-staging` and `chilltent-pos-prod`, but staging/production mapping and credentials were not validated in this session. Always pass an explicit project/alias; never deploy based on an implicit CLI default.

Before the first development deployment:

1. Confirm the intended `.firebaserc` aliases and every generated Firebase client config with the user.
2. Confirm `firebase.json` references `firestore.rules` and `firestore.indexes.json`. Its current working-tree edit contains that stanza alongside user-owned project-ID changes, so review it instead of blindly staging the whole file.
3. Deploy the composite indexes and Rules before exercising workers that depend on them.
4. Enable/verify Firebase Authentication Email/Password and authorize every action/continue-link domain.
5. Enable the APIs used by Functions v2, Secret Manager, Eventarc, Cloud Tasks, Cloud Scheduler, Pub/Sub, build, and artifact storage. Confirm billing supports these services.
6. Ensure the Functions runtime identity can enqueue Cloud Tasks and the Cloud Tasks identity can invoke each private task handler. Keep task targets and Functions region configuration consistent.
7. Configure a verified Brevo sender/domain, SPF, DKIM, DMARC, and a custom return path. Disable transactional click/open tracking at the provider level as well as in request headers.
8. Configure an unbatched Brevo transactional webhook for the deployed `receiveBrevoEmailWebhook` URL with the shared secret. Test delivered, transient, hard-bounce, blocked, spam/complaint, unsubscribe, and malformed events.
9. Deploy only to development, run smoke tests, then repeat deliberately in staging. No production deployment is authorized by this handoff.
10. Enable App Check enforcement only after each supported platform is validated. Windows still needs the documented auth/canonical-authorization/rate-limit fallback until a tested custom provider exists.

The new indexes cover tenant-membership collection-group scans; membership/global-status/staff-cleanup retries; email and platform-alert retry/lease queries; reconciliation retry/lease collection-group queries; and collection-group `uid` lookups for staff/invitations.

For any legacy stock-movement import, backfill an immutable commit-ordering field such as `recordedAt` before enabling checkpoint/reconciliation workers. A source timestamp alone is not a safe pagination cursor.

### Deliberately uncommitted environment and Flutter work

Preserve and review these user-owned Firebase environment changes independently:

```text
.firebaserc
android/app/google-services.json
files/web/src/firebase-config.js
firebase.json
lib/firebase_options.dart
```

Do not revert them, but do not include them in a backend code commit without confirming the environment mapping.

The working tree also contains an incomplete pure-Dart/Flutter tenant bootstrap layer:

```text
lib/tenancy/tenancy.dart
lib/tenancy/firebase_tenant_gateway.dart
lib/tenancy/hive_tenant_selection_store.dart
lib/tenancy/tenant_bootstrap.dart
lib/tenancy/tenant_directory.dart
lib/tenancy/tenant_selection.dart
lib/tenancy/tenant_session_controller.dart
test/tenancy/tenant_bootstrap_test.dart
test/tenancy/tenant_selection_test.dart
test/tenancy/tenant_session_controller_test.dart
```

It had 34 passing tenancy tests and a clean analysis earlier in development, but it was not revalidated after the final backend work and is not the completed app integration. Review, rerun, and commit it as the first frontend milestone rather than assuming it is production-ready.

### Next-session execution order

1. Run `git status --short`, `git diff --check`, and `git log --oneline -15`; confirm that only the documented environment and Flutter work remains and do not mix those scopes.
2. Rerun `npm test` in `functions` and the 19-test Rules emulator suite. Confirm the compiled entry point still exposes 44 handlers.
3. Decide and implement a secure operator entry point for `grantPlatformAdmin`. The canonical service exists in `functions/src/platform/grantPlatformAdmin.ts`, but it is intentionally not a public callable or CLI export yet.
4. Confirm development Firebase project mapping, secrets, params, IAM, APIs, Auth settings, action domains, and Brevo configuration.
5. Deploy indexes, then Rules, then Functions to development only. Run owner-recovery dry-run and staff/email smoke tests with non-production identities.
6. Add emulator/integration coverage for duplicate triggers, expired leases, retry recovery, token/tokenless acceptance races, abandoned identity cleanup, more than 200 stock movements, checkpoint chains, actual composite queries, and provider/webhook ambiguity.
7. Finish and commit the Flutter tenant directory/bootstrap. Add the business selector, session epochs, route guards, and tenant-scoped repositories; replace every legacy staff callable and root collection path.
8. Implement encrypted Hive state transitions, single-flight checkout, per-device receipt counters, switching guards, shift restoration, multi-device isolation tests, and Windows restart/offline tests.
9. Complete subscription/configuration/branding surfaces and perform adversarial cross-tenant tests.
10. Promote the identical versioned release through staging only after development evidence is recorded; production remains a separate explicit decision.

Backend completion in this handoff means implementation plus local automated validation. The remaining work is deployment configuration, integration evidence, Flutter/offline behavior, and staged rollout.

---

## Frontend implementation handoff - 2026-07-29

### Completed in this session

The first bounded Flutter tenancy milestone is committed on `multitenant-main`:

- `30087ad` - typed tenant directory/bootstrap, Firebase callable gateway, UID-scoped Hive routing selection, canonical revalidation before local selection, login precedence, and session epoch controller/scope.

This supersedes the earlier handoff's statement that the tenancy bootstrap files are uncommitted. The user-owned Firebase environment changes remain deliberately uncommitted and were not staged:

```text
.firebaserc
android/app/google-services.json
files/web/src/firebase-config.js
firebase.json
lib/firebase_options.dart
```

The milestone fails closed when pagination repeats a cursor or tenant ID, a root default tenant ID is malformed, canonical access is inactive, an owner projection is inconsistent, or a requested role is not allowed. Opening a tenant now re-fetches the complete canonically overlaid directory before saving the UID-scoped last selection. Failed switching leaves the current authorized session intact.

Validation after the commit's implementation changes:

- `flutter test --no-pub test/tenancy` passed **39/39** tests.
- `flutter analyze --no-pub lib/tenancy test/tenancy` reported no issues.
- `git diff --cached --check` was clean before commit.

No app root, screen, legacy repository, deployment configuration, or offline checkout behavior was changed in this milestone.

### Next bounded frontend chunk

Implement only the authentication-to-tenant routing shell:

1. Initialize Hive once and open `HiveTenantSelectionStore.boxName` before `runApp`.
2. Own one `TenantSessionController` above authenticated routes and clear it on every Auth UID transition/sign-out.
3. Replace the current direct `AuthGate -> MainHubScreen` jump with an async bootstrap state machine that ignores stale completions after an Auth UID change.
4. Add the business selector for all visible memberships, clearly distinguishing accessible, pending, inactive, rejected, suspended, and archived entries.
5. On selection, call `TenantBootstrapService.openTenant`, then open the returned membership in the session controller. Add retry and sign-out paths for bootstrap failures and disabled/missing roots.
6. Add widget tests for local/default/sole selection, multi-business selection, inaccessible membership display, stale async completion after sign-out, and session clearing.

Keep that chunk out of legacy business repositories. Do not allow `MainHubScreen` to execute its current root `staff`, `store`, or other mono-tenant reads merely because a session exists; either land on a temporary tenant-safe shell or gate the legacy hub until its repositories are migrated. Platform-admin dashboard routing is also not implemented yet and must not be sent into tenant screens.

After that shell is green, use a separate session for route guards and tenant-scoped repository migration. Inventory and replace legacy root collection reads/writes and the old `createStaffUser` / `toggleStaffStatus` call sites before enabling operational screens.

---

## Authentication-to-tenant routing handoff - 2026-07-29

### Completed in this session

The bounded authentication-to-tenant routing shell is implemented as a standalone frontend milestone, and the pre-existing Firebase environment edits remain untouched.

Implemented behavior:

- `main.dart` initializes Hive once and opens `HiveTenantSelectionStore.boxName` before `runApp`.
- One `TenantSessionController` is owned above authenticated tenant routes. Every Auth UID transition, explicit sign-out, retry, and widget disposal invalidates pending work and clears the session.
- Auth bootstrap ignores stale root/directory/open completions after a UID transition.
- Automatic local/default/sole selection and explicit selector choices all pass through `TenantBootstrapService.openTenant`, so a selection is canonically revalidated before the session opens or the device-local choice is saved.
- The business selector displays every visible membership and labels accessible, pending, inactive, rejected, suspended, and archived states. Inaccessible entries cannot be opened.
- Disabled, missing, malformed, and transient bootstrap failures land on a retry/sign-out screen without exposing internal error details.
- Platform identities land on a non-tenant holding screen. No platform identity is routed into tenant UI.
- `LoginScreen` now performs Firebase Auth sign-in only. Its legacy root `staff/{uid}` lookup and direct `MainHubScreen` navigation were removed.
- The authenticated destination is a temporary tenant-safe landing screen. `MainHubScreen` and its mono-tenant/root collection reads remain unreachable.

Files in this chunk:

```text
lib/main.dart
lib/login_screen.dart
lib/tenancy/tenancy.dart
lib/tenancy/tenant_routing_shell.dart
test/tenancy/tenant_routing_shell_test.dart
PLAN.md
```

Validation evidence:

- `dart analyze lib/tenancy test/tenancy lib/main.dart lib/login_screen.dart` reported no issues.
- `flutter test --no-pub test/tenancy` passed **47/47** tests, including **8** new routing-shell widget tests.
- The new tests cover UID-local/default/sole routing, multi-business selection, canonical revalidation, inaccessible membership labels, stale completion after sign-out, session clearing, and bootstrap retry/sign-out affordances.
- `git diff --check` was clean apart from expected Windows line-ending warnings on existing files.

The following user-owned environment changes are still deliberately separate and must not be staged with this frontend chunk without confirmation:

```text
.firebaserc
android/app/google-services.json
files/web/src/firebase-config.js
firebase.json
lib/firebase_options.dart
```

### Next bounded frontend chunk

Implement only the route-guard and repository-migration foundation:

1. Inventory every Flutter root Firestore collection path and legacy callable use, with the owning screen/service and intended tenant-scoped replacement. Do not migrate the entire app in one session.
2. Add a reusable tenant route guard that requires a live `TenantSession`, enforces allowed roles, and rejects stale session epochs before an async result can update UI.
3. Add the minimal tenant-scoped repository base that derives all operational paths from `TenantPaths` and never accepts an arbitrary root collection path.
4. Migrate one small read-only vertical slice behind the guard (prefer tenant configuration/branding if its schema is present). Keep `MainHubScreen`, checkout, stock mutation, reports, staff mutation, and returns disabled.
5. Add unit/widget tests proving missing session, wrong role, tenant switch during an async load, and a cross-tenant document/path mismatch all fail closed.

Keep encrypted Hive checkout, switching guards, shift restoration, and operational repository migration for later bounded sessions. Do not enable the legacy hub merely because the route-guard primitives exist.

---

## Route-guard and tenant repository foundation handoff - 2026-07-29

### Completed in this session

The authentication-to-tenant routing shell was revalidated and committed first:

- `b1ac73b` - authenticated UID routing, business selector, stale-bootstrap rejection, session ownership, and the tenant-safe landing route.

The next bounded frontend foundation is implemented as a separate milestone:

- `TenantRouteGuard<T>` requires a live canonical `TenantSession`, applies optional role checks, captures UID/tenant/epoch, and discards stale async completions before they can update UI.
- `TenantReadRepository` derives document paths only from the session's `TenantPaths`, exposes no arbitrary root-path input, and rejects a returned path that differs from the exact requested tenant document.
- `FirebaseTenantDocumentReader` is the narrow Firestore adapter behind that repository boundary.
- The first read-only vertical slice loads `tenants/{tenantId}/configuration/branding` and renders it inside the existing tenant-safe landing route. A missing branding document falls back to the canonically overlaid tenant name. Malformed branding fails closed through the guarded error state.
- `docs/frontend_tenant_migration_inventory.md` records every currently detected Flutter root Firestore collection and callable owner, its intended tenant-scoped replacement, and whether it is legacy or current.
- `MainHubScreen`, checkout, stock mutation, reports, staff mutation, returns, and all other legacy operational routes remain unreachable.

Files in this chunk:

```text
docs/frontend_tenant_migration_inventory.md
lib/tenancy/tenancy.dart
lib/tenancy/tenant_branding.dart
lib/tenancy/tenant_repository.dart
lib/tenancy/tenant_route_guard.dart
lib/tenancy/tenant_routing_shell.dart
test/tenancy/tenant_repository_test.dart
test/tenancy/tenant_route_guard_test.dart
PLAN.md
```

Validation evidence:

- `dart analyze lib/tenancy test/tenancy` reported no issues.
- `flutter test --no-pub test/tenancy` passed **53/53** tests.
- New coverage proves missing sessions and wrong roles do not start loads, a tenant switch rejects the prior epoch's async completion, an exact tenant branding path is derived from the session, and a cross-tenant response path fails closed.
- `git diff --check` was clean apart from expected Windows line-ending warnings on existing files.

The five user-owned Firebase environment edits remain separate and must not be staged with frontend code without confirming the environment mapping:

```text
.firebaserc
android/app/google-services.json
files/web/src/firebase-config.js
firebase.json
lib/firebase_options.dart
```

### Next bounded frontend chunk

Implement only a read-only tenant product/category catalog foundation:

1. Freeze strict product and category read models from the legacy fields that are still required by the UI; reject malformed tenant IDs, document IDs, quantities, prices, and category references.
2. Extend the repository boundary with tenant-derived collection queries and exact returned-path validation. Do not accept raw collection paths.
3. Add bounded pagination and deterministic ordering for the catalog instead of attaching the legacy unbounded root streams.
4. Render a temporary read-only catalog route behind `TenantRouteGuard`; do not expose add, update, delete, stock adjustment, checkout, returns, or report actions.
5. Test missing/wrong-role access, malformed documents, cross-tenant query results, pagination boundaries, and a tenant switch during an outstanding query.

Keep the legacy hub disabled. Staff lifecycle migration, checkout/Hive state, shifts, reports, returns, and mutation workflows remain separate later chunks.

---

## Read-only tenant catalog handoff - 2026-07-29

### Completed in this session

The next bounded frontend milestone implements only the tenant product/category
catalog foundation. The legacy hub and every operational mutation remain
disabled.

Implemented behavior:

- Strict category and product read models validate exact tenant document paths,
  non-empty names and SKUs, finite non-negative prices, signed safe-integer
  quantities, HTTPS image URLs, and category document IDs. Product reads accept
  the legacy `category` alias during migration, but reject it when it conflicts
  with `categoryId`.
- The repository boundary now supports collection queries that can only be
  constructed from `TenantPaths`. Firebase orders by document ID, pages are
  limited to 1-50 items, one look-ahead document determines `hasMore`, and the
  cursor is the last returned document ID.
- Collection reads reject cross-tenant paths, nested/non-exact document paths,
  duplicate documents, unordered results, and readers that exceed the requested
  bound.
- The tenant-safe landing screen links to a temporary guarded read-only catalog.
  The pushed route receives the same live `TenantSessionController`, so missing,
  wrong-role, switched-tenant, and stale-epoch states continue to fail closed.
- The catalog renders only bounded category/product results and explicitly
  exposes no add, edit, delete, stock, checkout, return, or report action.
- The migration inventory now distinguishes this safe catalog from the still
  disabled `goods.dart` and `pos.dart` legacy screens.

Files in this chunk:

```text
docs/frontend_tenant_migration_inventory.md
lib/tenancy/tenancy.dart
lib/tenancy/tenant_catalog.dart
lib/tenancy/tenant_repository.dart
lib/tenancy/tenant_routing_shell.dart
test/tenancy/tenant_catalog_test.dart
PLAN.md
```

Validation evidence:

- `dart analyze lib/tenancy test/tenancy lib/main.dart lib/login_screen.dart`
  reported no issues.
- `flutter test --no-pub test/tenancy` passed **60/60** tests.
- Seven catalog tests cover strict current/legacy decoding, malformed paths and
  fields, bounded cursor progression, invalid page sizes, cross-tenant results,
  real safe-landing navigation, missing/wrong-role denial, and tenant-switch
  stale-query rejection.
- `git diff --check` was clean apart from expected Windows line-ending warnings
  on existing files.

The five user-owned Firebase environment edits remain separate and must not be
staged with frontend code without confirming the environment mapping:

```text
.firebaserc
android/app/google-services.json
files/web/src/firebase-config.js
firebase.json
lib/firebase_options.dart
```

### Next bounded frontend chunk

Implement only a read-only tenant staff-directory foundation:

1. Freeze a strict canonical staff summary model from
   `tenants/{tenantId}/staff/{uid}`, including exact agreement between the
   document ID and server-controlled `uid`, known roles/statuses, and the
   invitation fields that are safe to display.
2. Reuse the tenant-derived bounded collection boundary and deterministic
   document-ID pagination. Reject cross-tenant responses and duplicate or
   malformed staff identities.
3. Add a management-only route guarded for owner/admin/manager. Render active,
   pending, and inactive staff read-only; do not expose invitations, role
   changes, status changes, email replacement, or cancellation actions yet.
4. Test owner-as-admin access, cashier denial without reads, malformed owner or
   UID projections, page boundaries, and a tenant switch during an outstanding
   staff query.
5. Update the inventory, but leave `lib/screens/users.dart`,
   `lib/screens/create_user.dart`, `createStaffUser`, and `toggleStaffStatus`
   unreachable and unchanged.

Use a later separate session for the typed `inviteStaff`, `updateStaffUser`,
`setStaffStatus`, pending-email replacement, resend, cancel, and invitation
acceptance workflows. Checkout/Hive state, shifts, reports, returns, subscription
surfaces, and all catalog mutations also remain outside this chunk.

---

## Read-only tenant staff-directory handoff - 2026-07-29

### Completed in this session

The next bounded frontend milestone implements only a canonical, read-only
tenant staff directory. The legacy staff screens and every staff mutation remain
disabled.

Implemented behavior:

- `TenantStaffSummary` strictly decodes canonical
  `tenants/{tenantId}/staff/{uid}` records. The server-controlled `uid` must
  exactly equal the document ID; email must already be normalized; role,
  membership status, and invitation status must be known values; optional name
  and phone values must be trimmed and control-character-free.
- Membership/invitation combinations fail closed: pending staff may be pending
  or sent, while active/inactive staff must be accepted. Cancelled or expired
  invitations cannot remain as canonical staff projections.
- Every page reads the canonical tenant root and the exact owner staff document.
  `ownerUid` must be a valid document ID, the owner document must exist, and the
  owner must be active with role `owner` and invitation state `accepted`. Any
  other staff document projecting role `owner` is rejected.
- `TenantReadRepository.readTenantRoot()` derives and validates the exact tenant
  root path. Staff pages reuse the existing 1-50 item, document-ID-ordered query
  contract and reject malformed, duplicate, unordered, nested, or cross-tenant
  results.
- A temporary staff-directory route is available only to owner/admin/manager.
  Owner access uses the frozen owner-as-admin inheritance rule. Cashiers do not
  see the landing action and the route guard starts no reads for them.
- The route renders active, pending, and inactive summaries read-only. It exposes
  no invite, resend, cancel, role, status, or email-replacement action.
- Tenant switches invalidate outstanding directory loads through the existing
  session epoch guard.

Files in this chunk:

```text
docs/frontend_tenant_migration_inventory.md
lib/tenancy/tenancy.dart
lib/tenancy/tenant_repository.dart
lib/tenancy/tenant_routing_shell.dart
lib/tenancy/tenant_staff_directory.dart
test/tenancy/tenant_staff_directory_test.dart
PLAN.md
```

Validation evidence:

- `dart analyze lib/tenancy test/tenancy lib/main.dart lib/login_screen.dart`
  reported no issues.
- `flutter test --no-pub test/tenancy` passed **68/68** tests.
- Eight staff-directory tests cover strict state decoding, exact UID checks,
  malformed owner projections, normalized fields, bounded cursor progression,
  cross-tenant/root rejection, real owner navigation, cashier denial without
  reads, and tenant-switch stale-query rejection.
- `git diff --check` was clean apart from expected Windows line-ending warnings
  on existing files.

The five user-owned Firebase environment edits remain separate and must not be
staged with frontend code without confirming the environment mapping:

```text
.firebaserc
android/app/google-services.json
files/web/src/firebase-config.js
firebase.json
lib/firebase_options.dart
```

### Next bounded frontend chunk

Implement only typed `inviteStaff` issuance from the new staff-directory
foundation:

1. Add a session-bound staff callable gateway for `inviteStaff` only. It must
   derive `tenantId` from the captured `TenantSession`, accept no arbitrary
   tenant/path input, generate one request ID per user intent, and strictly
   decode the callable response.
2. Freeze client validation for normalized email, trimmed name/phone, and the
   allowed invite roles (`admin`, `manager`, `cashier`; never `owner`). Do not
   infer that a client-side check replaces backend authorization.
3. Add an owner/admin-only invitation form from the guarded staff directory.
   Managers retain read-only directory access. Use single-flight submission,
   keep the form recoverable after transient failures, and refresh the bounded
   first page only after a successful current-session response.
4. Reject stale success/failure completions after tenant or UID changes, and
   never show raw callable/internal error details.
5. Test owner-as-admin submission, manager/cashier denial without calls,
   tenant-derived request payloads, invalid roles/fields, duplicate taps,
   retry behavior, strict response decoding, and a tenant switch during an
   outstanding invitation.

Keep `createStaffUser`, `lib/screens/create_user.dart`, and the legacy
`lib/screens/users.dart` unreachable. `updateStaffUser`, `setStaffStatus`, resend,
cancel, pending-email replacement, and both invitation-acceptance routes remain
separate later chunks. Checkout/Hive state, shifts, reports, returns,
subscriptions, and catalog mutations also remain outside this scope.

---

## Typed staff invitation handoff - 2026-07-29

### Completed in this session

The next bounded frontend milestone enables only typed `inviteStaff` issuance
from the canonical staff directory. The legacy staff screens and all other
staff lifecycle mutations remain disabled.

Implemented behavior:

- `TenantStaffInvitationGateway` is bound to one captured, canonically valid
  `TenantSession`. It accepts no tenant ID or path, derives `tenantId` for the
  callable payload, and permits only owner/admin sessions through the frozen
  owner-as-admin rule.
- A normalized invitation draft validates email, trimmed name and phone, and
  only `admin`, `manager`, or `cashier` roles. The client checks improve the
  form experience but do not replace backend authorization or validation.
- Each user intent owns one cryptographically generated request ID. Duplicate
  taps are single-flight, and a retry without changing fields reuses the same
  idempotency key.
- Callable responses are decoded fail-closed with exact fields, tenant
  agreement, canonical document IDs, pending invitation state, a positive safe
  invitation version, and pending delivery metadata.
- The owner/admin-only form is embedded in the guarded directory. Managers
  remain read-only and cashiers remain route-denied without reads or calls.
  A successful current-session response refreshes only the bounded first staff
  page.
- Success and failure completions are discarded after UID, tenant, epoch, or
  authorization changes. UI errors are fixed safe messages and never expose raw
  callable details.
- A guard lifecycle regression was closed: when a `TenantSessionScope` and
  guarded loader change in the same frame, `TenantRouteGuard` now re-reads the
  current inherited controller before starting work, preventing a load under
  the prior authorized controller.

Files in this chunk:

```text
docs/frontend_tenant_migration_inventory.md
lib/tenancy/tenancy.dart
lib/tenancy/tenant_route_guard.dart
lib/tenancy/tenant_staff_directory.dart
lib/tenancy/tenant_staff_invitation.dart
test/tenancy/tenant_staff_directory_test.dart
test/tenancy/tenant_staff_invitation_test.dart
PLAN.md
```

Validation evidence:

- `dart analyze lib/tenancy test/tenancy lib/main.dart lib/login_screen.dart`
  reported no issues.
- `flutter test --no-pub test/tenancy` passed **77/77** tests; the focused staff
  directory/invitation subset passed **17/17**.
- Coverage proves normalization, invalid-field and owner-role rejection,
  tenant-derived payloads, stable per-intent request IDs, strict response
  decoding, owner-as-admin submission, manager/cashier denial, duplicate-tap
  single flight, retry behavior, current-session refresh, safe errors, and stale
  tenant/UID completion rejection.

The five user-owned Firebase environment edits remain separate and must not be
staged with frontend code without confirming the environment mapping:

```text
.firebaserc
android/app/google-services.json
files/web/src/firebase-config.js
firebase.json
lib/firebase_options.dart
```

### Next bounded frontend chunk

Implement only typed `updateStaffUser` editing from the canonical staff
directory:

1. Add a session-bound callable gateway for `updateStaffUser` only. Derive the
   tenant from the captured session, bind the target UID from a decoded
   `TenantStaffSummary`, create one request ID per edit intent, and strictly
   validate the returned tenant, UID, role, and membership status.
2. Reuse the frozen name/phone normalization. Allow only owner/admin callers.
   Preserve an owner's `owner` role while allowing their display fields to be
   edited, and never offer `owner` as a role for another staff member. Treat all
   client checks as UX safeguards; canonical backend owner and administrative-
   principal invariants remain authoritative.
3. Add a recoverable single-flight edit form for one selected directory row.
   Managers remain read-only. Refresh only the bounded first page after a
   successful current-session response, and discard stale success/failure
   completions without showing raw callable errors.
4. Test owner profile edits without demotion, non-owner role changes, manager
   and cashier denial without calls, exact tenant/UID payload derivation,
   malformed responses, duplicate taps, retry idempotency, and tenant/UID
   switching during an outstanding update.
5. Update the inventory while leaving `lib/screens/users.dart` and its legacy
   mutation paths unreachable and unchanged.

Keep `setStaffStatus`, resend, cancel, pending-email replacement, and both
invitation-acceptance routes for later bounded sessions. Checkout/Hive state,
shifts, reports, returns, subscriptions, and catalog mutations also remain
outside this scope.

---

## Typed staff update handoff - 2026-07-29

### Completed in this session

The next bounded frontend milestone enables only typed `updateStaffUser`
editing from the canonical staff directory. The legacy staff screen and every
other staff lifecycle mutation remain disabled.

Implemented behavior:

- `TenantStaffUpdateGateway` is bound to one captured, canonically valid
  `TenantSession` and one strictly decoded `TenantStaffSummary`. It accepts no
  tenant ID, target UID, or path, and permits only owner/admin sessions through
  the frozen owner-as-admin rule.
- Edit drafts reuse the frozen name and phone normalization. Non-owner rows may
  select only admin, manager, or cashier; an owner row remains `owner` while
  allowing its display fields to change. Backend owner and administrative-
  principal checks remain authoritative.
- Each edit intent owns one cryptographically generated request ID. Duplicate
  taps are single-flight, and a retry without changing fields reuses the same
  idempotency key.
- Callable responses are decoded fail-closed with exact fields and exact
  agreement with the expected tenant, target UID, requested role, and existing
  membership status.
- Owner/admin directory rows expose one recoverable inline editor. Managers
  retain read-only directory access, and cashiers remain route-denied without
  reads or calls. A successful current-session response refreshes only the
  bounded first staff page.
- Success and failure completions are discarded after tenant, actor UID,
  session epoch, authorization, or selected target UID changes. UI errors are
  fixed safe messages and never expose raw callable details.

Files in this chunk:

```text
docs/frontend_tenant_migration_inventory.md
lib/tenancy/tenancy.dart
lib/tenancy/tenant_staff_directory.dart
lib/tenancy/tenant_staff_update.dart
test/tenancy/tenant_staff_update_test.dart
PLAN.md
```

Validation evidence:

- `dart analyze lib/tenancy test/tenancy lib/main.dart lib/login_screen.dart`
  reported no issues.
- `flutter test --no-pub test/tenancy` passed **87/87** tests; the focused staff
  update file passed **10/10**.
- Coverage proves owner edits without demotion, non-owner role changes,
  normalized tenant/UID-bound payloads, invalid role and response rejection,
  manager/cashier denial, duplicate-tap single flight, retry idempotency,
  current-session refresh, safe errors, and stale tenant/target completion
  rejection.

The five user-owned Firebase environment edits remain separate and must not be
staged with frontend code without confirming the environment mapping:

```text
.firebaserc
android/app/google-services.json
files/web/src/firebase-config.js
firebase.json
lib/firebase_options.dart
```

### Next bounded frontend chunk

Implement only typed `setStaffStatus` activation/deactivation from the
canonical staff directory:

1. Add a session-bound callable gateway for `setStaffStatus` only. Derive the
   tenant and target UID from the captured session and decoded staff summary,
   create one request ID per status intent, and strictly validate the returned
   tenant, UID, role, and membership status.
2. Allow only owner/admin callers and only active/inactive transitions for
   already accepted non-owner memberships. Never expose status changes for the
   canonical owner or pending invitations. Client checks are UX safeguards;
   backend owner and last-administrative-principal invariants remain
   authoritative.
3. Add an explicit confirmation step, recoverable single-flight submission,
   stable retry idempotency, safe errors, current-session completion checks, and
   a bounded first-page refresh only after success. Managers remain read-only.
4. Test owner protection, pending-member rejection, owner-as-admin operation,
   manager/cashier denial without calls, exact tenant/UID/status payloads,
   malformed responses, confirmation cancellation, duplicate taps, retry, and
   tenant/target switches during an outstanding status change.
5. Update the inventory while leaving `toggleStaffStatus` and the legacy
   `lib/screens/users.dart` route unreachable and unchanged.

Keep resend, cancel, pending-email replacement, and both invitation-acceptance
routes for later bounded sessions. Checkout/Hive state, shifts, reports,
returns, subscriptions, and catalog mutations also remain outside this scope.

---

## Typed staff status handoff - 2026-07-29

### Completed in this session

The next bounded frontend milestone enables only typed `setStaffStatus`
activation and deactivation from the canonical staff directory. The legacy
staff screen and all remaining invitation lifecycle mutations stay disabled.

Implemented behavior:

- `TenantStaffStatusGateway` is bound to one captured, canonically valid
  `TenantSession` and one strictly decoded `TenantStaffSummary`. It accepts no
  tenant ID, target UID, or path, and permits only owner/admin sessions through
  the frozen owner-as-admin rule.
- Status intents apply only to already accepted non-owner memberships and only
  transition between active and inactive. Canonical owners, pending
  invitations, and no-op transitions fail before a callable request. Backend
  owner and last-administrative-principal checks remain authoritative.
- Each status intent owns one cryptographically generated request ID. Duplicate
  taps are single-flight, and retrying the same confirmation reuses the same
  idempotency key.
- Callable responses are decoded fail-closed with exact fields and exact
  agreement with the expected tenant, target UID, preserved role, and requested
  membership status.
- Owner/admin directory rows expose an explicit activate/deactivate confirmation
  only when eligible. Managers remain read-only, cashiers remain route-denied,
  and cancelling confirmation performs no mutation. A successful
  current-session response refreshes only the bounded first staff page.
- Success and failure completions are discarded after tenant, actor UID,
  session epoch, target UID, target status, or authorization changes. UI errors
  are fixed safe messages and never expose raw callable details.

Files in this chunk:

```text
docs/frontend_tenant_migration_inventory.md
lib/tenancy/tenancy.dart
lib/tenancy/tenant_staff_directory.dart
lib/tenancy/tenant_staff_status.dart
test/tenancy/tenant_staff_status_test.dart
PLAN.md
```

Validation evidence:

- `dart analyze lib/tenancy test/tenancy lib/main.dart lib/login_screen.dart`
  reported no issues.
- `flutter test --no-pub test/tenancy` passed **98/98** tests; the focused staff
  status file passed **11/11**.
- Coverage proves owner and pending-member protection, active/inactive-only
  transitions, owner-as-admin operation, manager/cashier denial, exact
  tenant/UID/status payload derivation, strict response decoding, explicit
  cancellation, duplicate-tap single flight, retry idempotency, safe errors,
  current-session refresh, and stale tenant/target completion rejection.

The five user-owned Firebase environment edits remain separate and must not be
staged with frontend code without confirming the environment mapping:

```text
.firebaserc
android/app/google-services.json
files/web/src/firebase-config.js
firebase.json
lib/firebase_options.dart
```

### Next bounded frontend chunk

Implement only typed `resendStaffInvitation` from the canonical staff
directory:

1. Add a session-bound callable gateway for `resendStaffInvitation` only.
   Derive the tenant and target UID from the captured session and decoded staff
   summary, create one request ID per resend intent, and strictly decode the
   exact backend result: tenant ID, UID, pending invitation state, positive safe
   invitation version, and pending-enqueue delivery metadata.
2. Allow only owner/admin callers and only canonical pending memberships whose
   invitation state is pending or sent. Keep active/inactive members and the
   canonical owner ineligible. Client checks are UX safeguards; the backend's
   canonical invitation, identity-email, and authorization checks remain
   authoritative.
3. Add an explicit confirmation action for eligible pending rows, recoverable
   single-flight submission, stable retry idempotency, safe errors,
   current-session completion checks, and a bounded first-page refresh only
   after success. Managers remain read-only.
4. Test eligibility rejection without calls, owner-as-admin operation,
   manager/cashier denial, exact tenant/UID payloads, malformed responses,
   confirmation cancellation, duplicate taps, retry behavior, and tenant/target
   switches during an outstanding resend.
5. Update the inventory while leaving the legacy `lib/screens/users.dart`
   mutation paths unreachable and unchanged.

Keep invitation cancellation, pending-email replacement, and both
invitation-acceptance routes for later bounded sessions. Checkout/Hive state,
shifts, reports, returns, subscriptions, and catalog mutations also remain
outside this scope.

---

## Typed staff invitation resend handoff - 2026-07-29

### Completed in this session

The next bounded frontend milestone enables only typed
`resendStaffInvitation` from the canonical staff directory. Invitation
cancellation, pending-email replacement, and both acceptance routes remain
disabled.

Implemented behavior:

- `TenantStaffInvitationResendGateway` is bound to one captured, canonically
  valid `TenantSession` and one strictly decoded `TenantStaffSummary`. It
  accepts no tenant ID, target UID, or path and permits only owner/admin
  sessions through the frozen owner-as-admin rule.
- Resend intents apply only to canonical non-owner pending memberships whose
  invitation state is pending or sent. Accepted active/inactive memberships
  and the canonical owner fail before a callable request. Backend canonical
  invitation, identity-email, and authorization checks remain authoritative.
- Each resend intent owns one cryptographically generated request ID.
  Duplicate taps are single-flight, and retrying the same confirmation reuses
  the same idempotency key.
- Callable responses are decoded fail-closed with exact fields and exact
  agreement with the expected tenant and target UID. The pending invitation
  state, positive JavaScript-safe invitation version, and pending-enqueue
  delivery metadata are all required.
- Eligible owner/admin directory rows expose an explicit resend confirmation.
  Managers remain read-only, cashiers remain route-denied, and cancelling
  confirmation performs no mutation. A successful current-session response
  refreshes only the bounded first staff page.
- Success and failure completions are discarded after tenant, actor UID,
  session epoch, target UID, membership state, invitation state, or
  authorization changes. UI errors are fixed safe messages and never expose
  raw callable details.

Files in this chunk:

```text
docs/frontend_tenant_migration_inventory.md
lib/tenancy/tenancy.dart
lib/tenancy/tenant_staff_directory.dart
lib/tenancy/tenant_staff_invitation_resend.dart
test/tenancy/tenant_staff_invitation_resend_test.dart
PLAN.md
```

Validation evidence:

- `dart analyze lib/tenancy test/tenancy lib/main.dart lib/login_screen.dart`
  reported no issues.
- `flutter test --no-pub test/tenancy` passed **109/109** tests; the focused
  invitation-resend file passed **11/11**.
- Coverage proves pending/sent eligibility, owner protection, owner-as-admin
  operation, manager/cashier denial, exact tenant/UID payload derivation,
  strict invitation and delivery response decoding, explicit cancellation,
  duplicate-tap single flight, retry idempotency, safe errors,
  current-session refresh, and stale tenant/target completion rejection.

The five user-owned Firebase environment edits remain separate and must not be
staged with frontend code without confirming the environment mapping:

```text
.firebaserc
android/app/google-services.json
files/web/src/firebase-config.js
firebase.json
lib/firebase_options.dart
```

### Next bounded frontend chunk

Implement only typed `cancelTenantInvitation` from the canonical staff
directory:

1. Add a session-bound callable gateway for `cancelTenantInvitation` only.
   Derive the tenant and target UID from the captured session and decoded staff
   summary, normalize and validate the required 3-500 character cancellation
   reason, create one request ID per cancel intent, and strictly decode the
   exact backend result: tenant ID, UID, cancelled invitation state, positive
   safe invitation version, and null delivery metadata.
2. Allow only owner/admin callers and only canonical pending non-owner
   memberships whose invitation state is pending or sent. Keep accepted
   active/inactive members and the canonical owner ineligible. Client checks
   are UX safeguards; the backend's canonical invitation, owner, cleanup, and
   authorization invariants remain authoritative.
3. Add an explicit destructive confirmation with the required reason,
   recoverable single-flight submission, stable retry idempotency, safe errors,
   current-session completion checks, and a bounded first-page refresh only
   after success. Managers remain read-only.
4. Test reason normalization and bounds, eligibility rejection without calls,
   owner-as-admin operation, manager/cashier denial, exact tenant/UID/reason
   payloads, malformed responses, confirmation cancellation, duplicate taps,
   retry behavior, and tenant/target switches during an outstanding cancel.
5. Update the inventory while leaving the legacy `lib/screens/users.dart`
   mutation paths unreachable and unchanged.

Keep pending-email replacement and both invitation-acceptance routes for later
bounded sessions. Checkout/Hive state, shifts, reports, returns,
subscriptions, and catalog mutations also remain outside this scope.

---

## Typed staff invitation cancellation handoff - 2026-07-29

### Completed in this session

The next bounded frontend milestone enables only typed
`cancelTenantInvitation` from the canonical staff directory. Pending-email
replacement and both invitation-acceptance routes remain disabled.

Implemented behavior:

- `TenantStaffInvitationCancellationGateway` is bound to one captured,
  canonically valid `TenantSession` and one strictly decoded
  `TenantStaffSummary`. It accepts no tenant ID, target UID, or path and permits
  only owner/admin sessions through the frozen owner-as-admin rule.
- Cancellation intents apply only to canonical non-owner pending memberships
  whose invitation state is pending or sent. Accepted active/inactive
  memberships and the canonical owner fail before a callable request. Backend
  canonical invitation, owner, cleanup, and authorization checks remain
  authoritative.
- The required cancellation reason is trimmed and constrained to 3-500
  characters. Each reason-bearing cancellation intent owns one
  cryptographically generated request ID. Duplicate taps are single-flight,
  and retrying without changing the reason reuses the same idempotency key.
- Callable responses are decoded fail-closed with exact fields and exact
  agreement with the expected tenant and target UID. The cancelled invitation
  state, positive JavaScript-safe invitation version, and null delivery
  metadata are all required.
- Eligible owner/admin directory rows expose an explicit destructive
  confirmation with an audit reason. Managers remain read-only, cashiers remain
  route-denied, and dismissing confirmation performs no mutation. A successful
  current-session response refreshes only the bounded first staff page.
- Success and failure completions are discarded after tenant, actor UID,
  session epoch, target UID, membership state, invitation state, or
  authorization changes. UI errors are fixed safe messages and never expose
  raw callable details.

Files in this chunk:

```text
docs/frontend_tenant_migration_inventory.md
lib/tenancy/tenancy.dart
lib/tenancy/tenant_staff_directory.dart
lib/tenancy/tenant_staff_invitation_cancellation.dart
test/tenancy/tenant_staff_invitation_cancellation_test.dart
PLAN.md
```

Validation evidence:

- `dart analyze lib/tenancy test/tenancy lib/main.dart lib/login_screen.dart`
  reported no issues.
- `flutter test --no-pub test/tenancy` passed **120/120** tests; the focused
  invitation-cancellation file passed **11/11**.
- Coverage proves reason normalization and bounds, pending/sent eligibility,
  owner protection, owner-as-admin operation, manager/cashier denial, exact
  tenant/UID/reason payload derivation, strict cancelled response decoding,
  explicit dismissal, duplicate-tap single flight, retry idempotency, safe
  errors, current-session refresh, and stale tenant/target completion
  rejection.

The five user-owned Firebase environment edits remain separate and must not be
staged with frontend code without confirming the environment mapping:

```text
.firebaserc
android/app/google-services.json
files/web/src/firebase-config.js
firebase.json
lib/firebase_options.dart
```

### Next bounded frontend chunk

Implement only typed `replacePendingStaffEmail` from the canonical staff
directory:

1. Add a session-bound callable gateway for `replacePendingStaffEmail` only.
   Derive the tenant and old target UID from the captured session and decoded
   staff summary, normalize and validate the corrected email, create one
   request ID per replacement intent, and strictly decode the exact backend
   result: tenant ID, a valid replacement UID distinct from the old UID,
   pending invitation state, positive safe invitation version, and
   pending-enqueue delivery metadata.
2. Allow only owner/admin callers and only canonical pending non-owner
   memberships whose invitation state is pending or sent. Reject an unchanged
   normalized email as a client UX safeguard. Backend canonical invitation,
   identity ownership, duplicate-membership, cleanup, and authorization checks
   remain authoritative.
3. Add an explicit confirmation explaining that the old pending membership is
   replaced, a recoverable single-flight submission, stable retry idempotency,
   safe errors, current-session completion checks, and a bounded first-page
   refresh only after success. Managers remain read-only.
4. Test email normalization and unchanged-email rejection, eligibility denial
   without calls, owner-as-admin operation, manager/cashier denial, exact
   tenant/old-UID/email payloads, replacement-UID response validation,
   malformed delivery responses, confirmation dismissal, duplicate taps,
   retry behavior, and tenant/target switches during an outstanding
   replacement.
5. Update the inventory while leaving the legacy `lib/screens/users.dart`
   mutation paths unreachable and unchanged.

Keep both invitation-acceptance routes for later bounded sessions.
Checkout/Hive state, shifts, reports, returns, subscriptions, and catalog
mutations also remain outside this scope.

---

## Typed staff invitation email replacement handoff - 2026-07-30

### Completed in this session

The next bounded frontend milestone enables only typed
`replacePendingStaffEmail` from the canonical staff directory. Both
invitation-acceptance routes remain disabled.

Implemented behavior:

- `TenantStaffInvitationEmailReplacementGateway` is bound to one captured,
  canonically valid `TenantSession` and one strictly decoded
  `TenantStaffSummary`. It accepts no tenant ID, old target UID, or path and
  permits only owner/admin sessions through the frozen owner-as-admin rule.
- Email replacement intents apply only to canonical non-owner pending
  memberships whose invitation state is pending or sent. Accepted
  active/inactive memberships and the canonical owner fail before a callable
  request. Backend canonical invitation, identity ownership,
  duplicate-membership, cleanup, and authorization checks remain authoritative.
- The corrected email is trimmed, lowercased, validated with the existing staff
  invitation email normalizer, and rejected when it matches the pending row's
  normalized email. Each replacement intent owns one cryptographically
  generated request ID. Duplicate taps are single-flight, and retrying without
  changing the email reuses the same idempotency key.
- Callable responses are decoded fail-closed with exact fields and exact tenant
  agreement. A valid replacement UID distinct from the old UID, pending
  invitation state, positive JavaScript-safe invitation version, and
  pending-enqueue delivery metadata are all required.
- Eligible owner/admin directory rows expose an explicit confirmation explaining
  that the old pending membership is replaced. Managers remain read-only,
  cashiers remain route-denied, and dismissing confirmation performs no
  mutation. A successful current-session response refreshes only the bounded
  first staff page.
- Success and failure completions are discarded after tenant, actor UID,
  session epoch, target UID, target email, membership state, invitation state,
  or authorization changes. UI errors are fixed safe messages and never expose
  raw callable details.

Files in this chunk:

```text
docs/frontend_tenant_migration_inventory.md
lib/tenancy/tenancy.dart
lib/tenancy/tenant_staff_directory.dart
lib/tenancy/tenant_staff_invitation_email_replacement.dart
test/tenancy/tenant_staff_invitation_email_replacement_test.dart
PLAN.md
```

Validation evidence:

- `dart analyze lib/tenancy test/tenancy` reported no issues.
- `flutter test --no-pub test/tenancy` passed **132/132** tests; the focused
  invitation-email-replacement file passed **12/12**.
- `dart analyze lib/tenancy test/tenancy lib/main.dart lib/login_screen.dart`
  still reports the pre-existing `lib/main.dart` experimental
  `profilesSampleRate` warning; this chunk did not touch that file.
- Coverage proves email normalization and unchanged-email rejection,
  pending/sent eligibility, owner protection, owner-as-admin operation,
  manager/cashier denial, exact tenant/old-UID/email payload derivation,
  distinct replacement UID validation, strict delivery response decoding,
  explicit dismissal, duplicate-tap single flight, retry idempotency, safe
  errors, current-session refresh, and stale tenant/target completion
  rejection.

The five user-owned Firebase environment edits remain separate and must not be
staged with frontend code without confirming the environment mapping:

```text
.firebaserc
android/app/google-services.json
files/web/src/firebase-config.js
firebase.json
lib/firebase_options.dart
```

### Next bounded frontend chunk

Implement only typed `acceptVisibleTenantInvitation` from the authenticated
tenant-routing surface:

1. Add a session/user-bound callable gateway for `acceptVisibleTenantInvitation`
   only. Derive the tenant ID from a decoded visible pending membership and the
   current verified identity, create one request ID per acceptance intent, and
   strictly decode the exact backend result: tenant ID, caller UID, active
   membership state, accepted invitation state, role, and current tenant status.
2. Allow only the exact invited, verified, globally active caller to accept a
   visible pending membership whose invitation state is pending or sent. Keep
   token-proof acceptance, password setup, and unverified identity handling out
   of scope. Client checks are UX safeguards; backend auth-time, email-match,
   canonical membership, and tenant lifecycle checks remain authoritative.
3. Add an explicit in-app confirmation showing the business name and invited
   role, recoverable single-flight submission, stable retry idempotency, safe
   errors, stale-completion checks, and a bounded membership refresh only after
   success.
4. Test exact tenant/UID payload derivation, pending/sent eligibility,
   non-invited and unverified denial without calls, malformed responses,
   confirmation dismissal, duplicate taps, retry behavior, and user/tenant
   membership switches during an outstanding acceptance.
5. Update the inventory while leaving email-link token acceptance and legacy
   `lib/screens/users.dart` mutation paths unreachable and unchanged.

Checkout/Hive state, shifts, reports, returns, subscriptions, and catalog
mutations remain outside this scope.

---

## Typed visible invitation acceptance handoff - 2026-07-30

### Completed in this session

The next bounded frontend milestone enables only typed
`acceptVisibleTenantInvitation` from the authenticated tenant-routing selector.
Email-link token acceptance remains disabled.

Implemented behavior:

- `TenantVisibleInvitationAcceptanceGateway` is bound to the current verified,
  globally active identity and one decoded visible pending `TenantMembership`.
  It accepts no arbitrary tenant path or caller UID input.
- Acceptance intents apply only to visible non-owner pending memberships whose
  invitation state is pending or sent, whose canonical tenant and membership
  mirrors are present, and whose tenant lifecycle is active. Token-proof
  acceptance, password setup, unverified identity handling, auth-time checks,
  email-match checks, and canonical authorization remain backend-authoritative.
- Each acceptance intent owns one cryptographically generated request ID.
  Duplicate taps are single-flight, and retrying the same confirmation reuses
  the same idempotency key.
- Callable responses are decoded fail-closed with exact fields and exact
  agreement with the expected tenant, current caller UID, preserved role,
  active membership state, accepted invitation state, and active tenant state.
- Eligible verified selector rows expose an explicit confirmation showing the
  business name and invited role. Unverified users and ineligible memberships
  remain locked. A successful current-auth/current-routing response refreshes
  the bounded membership routing data.
- Success and failure completions are discarded after user, tenant membership,
  routing, or current-check changes. UI errors are fixed safe messages and
  never expose raw callable details.

Files in this chunk:

```text
docs/frontend_tenant_migration_inventory.md
lib/main.dart
lib/tenancy/tenancy.dart
lib/tenancy/tenant_routing_shell.dart
lib/tenancy/tenant_visible_invitation_acceptance.dart
test/tenancy/tenant_routing_shell_test.dart
test/tenancy/tenant_visible_invitation_acceptance_test.dart
PLAN.md
```

Validation evidence:

- `dart analyze lib/tenancy test/tenancy` reported no issues.
- `flutter test --no-pub test/tenancy` passed **142/142** tests; the focused
  visible-invitation-acceptance file passed **10/10**.
- `dart analyze lib/tenancy test/tenancy lib/main.dart lib/login_screen.dart`
  still reports the pre-existing `lib/main.dart` experimental
  `profilesSampleRate` warning; this chunk did not introduce it.
- Coverage proves exact tenant/current-UID binding, pending/sent eligibility,
  unverified and globally inactive denial without calls, accepted/suspended and
  owner-membership rejection, strict active/accepted response decoding,
  explicit cancellation, duplicate-tap single flight, retry idempotency, safe
  errors, bounded membership refresh after success, and stale user/tenant
  completion rejection.

The existing user-owned local edits remain separate and must not be staged with
frontend code:

```text
.vscode/settings.json
android/gradle.properties
pubspec.lock
```

### Next bounded frontend chunk

Implement only typed `acceptTenantInvitation` email-link token acceptance:

1. Add a callable gateway for `acceptTenantInvitation` that derives tenant ID,
   invitation version, and invitation token from a parsed, validated invitation
   link object, binds the current authenticated identity, creates one request ID
   per acceptance intent, and strictly decodes the active membership/accepted
   invitation response.
2. Allow only authenticated users whose visible route cannot use
   `acceptVisibleTenantInvitation`, such as new identities, unverified
   identities after verification, password-setup/direct email-link flows, or
   users requiring versioned token proof. Backend auth-time, token hash, email
   match, expiry, unused-token, canonical membership, and tenant lifecycle
   checks remain authoritative.
3. Add explicit confirmation for the parsed tenant name/role when available,
   recoverable single-flight submission, stable retry idempotency, safe errors,
   stale-completion checks, and a bounded membership refresh only after
   success.
4. Test invitation-link parsing and validation, exact tenant/version/token
   payload derivation, malformed responses, confirmation dismissal, duplicate
   taps, retry behavior, and user/link switches during an outstanding
   acceptance.
5. Update the inventory while leaving checkout/Hive state, shifts, reports,
   returns, subscriptions, and catalog mutations outside this scope.

---

## Typed email-link invitation acceptance handoff - 2026-07-30

### Completed in this session

The next bounded frontend milestone enables typed `acceptTenantInvitation`
from a versioned email invitation proof. The existing visible-invitation route
remains available for eligible verified users.

Implemented behavior:

- `TenantInvitationLink` parses the four proof fields emitted by the backend:
  tenant ID, invited UID, positive JavaScript-safe invitation version, and the
  exact 43-character URL-safe token. Links must be HTTPS. Partial fields,
  duplicates, unsafe document IDs, insecure schemes, invalid versions, and
  malformed tokens fail closed without retaining or displaying proof details.
- `TenantInvitationAcceptanceGateway` is bound to one parsed link and the
  current authenticated UID. It accepts no arbitrary tenant, target UID,
  invitation version, or token input. A link for another UID fails before a
  callable request. Backend recent-authentication, email-match, expiry,
  unused-token, canonical membership, root status, and tenant lifecycle checks
  remain authoritative.
- Each confirmation intent owns one cryptographically generated request ID.
  Duplicate taps are single-flight, and retrying the same proof reuses the same
  idempotency key. Callable responses require the exact five backend fields,
  exact tenant/UID agreement, a non-owner role, active membership, and accepted
  invitation state.
- App startup parses `Uri.base` once. Authenticated tenant users with a valid
  proof see an explicit confirmation; tenant name and invited role are shown
  when the canonically overlaid routing membership is available. Invalid links
  get a fixed safe state. Signing in, password setup, verification mechanics,
  token issuance, and Firebase recent-auth enforcement remain outside this
  narrow client boundary.
- Success and failure completions are discarded after Auth UID, proof link, or
  routing-current checks change. Success consumes the in-memory link and then
  performs the bounded tenant-routing refresh. Cancellation performs no
  mutation, and UI errors never expose callable or token details.

Files in this chunk:

```text
docs/frontend_tenant_migration_inventory.md
lib/main.dart
lib/tenancy/tenancy.dart
lib/tenancy/tenant_invitation_acceptance.dart
lib/tenancy/tenant_routing_shell.dart
test/tenancy/tenant_invitation_acceptance_test.dart
test/tenancy/tenant_routing_shell_test.dart
PLAN.md
```

Validation evidence:

- `dart analyze lib/tenancy test/tenancy` reported no issues.
- `flutter test --no-pub test/tenancy` passed **153/153** tests; the focused
  email-link invitation-acceptance file passed **10/10**.
- Focused routing plus invitation coverage passed **19/19** tests.
- `dart analyze lib/tenancy test/tenancy lib/main.dart lib/login_screen.dart`
  reports only the pre-existing `lib/main.dart` experimental
  `profilesSampleRate` warning; this chunk did not introduce it.
- Coverage proves strict URI parsing, exact tenant/version/token payload
  derivation, current-UID binding without calls for another user, exact
  response decoding, owner/role/membership-state rejection, explicit
  cancellation, duplicate-tap single flight, retry idempotency, safe errors,
  routing refresh only after success, and stale user/link completion rejection.

The existing user-owned local edits remain separate and must not be staged with
frontend code:

```text
.vscode/settings.json
android/gradle.properties
pubspec.lock
```

### Next bounded frontend chunk

Implement only typed `setDefaultTenant` for the currently open canonical
tenant session:

1. Add a session-bound callable gateway for `setDefaultTenant` that derives
   the tenant ID from a captured active `TenantSession`, creates one request ID
   per intent, and strictly decodes exact tenant/default-tenant agreement.
2. Expose an explicit “Make default” action from the tenant-safe landing route.
   Do not change the default as a side effect of opening or selecting a tenant,
   and do not add general tenant switching until the frozen switching blockers
   and pending-write checks are implemented.
3. Add explicit confirmation, recoverable single-flight submission, stable
   retry idempotency, safe errors, session-epoch stale-completion checks, and a
   bounded routing-profile refresh only after success.
4. Test owner/admin/manager/cashier active-member operation, exact payload and
   response validation, confirmation dismissal, duplicate taps, retry behavior,
   and tenant/session switches during an outstanding update.
5. Update the inventory while leaving checkout/Hive state, shifts, reports,
   returns, subscriptions, catalog mutations, and general tenant switching
   outside this scope.

---

## Invitation emulator contract handoff - 2026-07-30

### Completed in this session

The repository now has a repeatable, local-only Auth + Firestore + Functions
emulator boundary for both invitation-acceptance callables. The Windows
workstation also has portable Node.js 24.18.1 and Temurin JDK 21.0.12 under
`D:\firebase-emulator-tools`; those machine-local runtimes are not repository
artifacts.

Implemented behavior:

- `npm --prefix rules-tests run test:emulator:invitations` first compiles the
  production Functions source, copies that output into an ignored narrow
  Functions fixture, and exports only `acceptTenantInvitation` and
  `acceptVisibleTenantInvitation`. The fixture performs the same Firebase Admin
  bootstrap as the production entrypoint.
- The runner always uses the explicit
  `demo-multitenant-invitation-integration` project and localhost-only Auth,
  Firestore, and Functions hosts. It creates a deterministic local-only HMAC
  secret in an ignored temporary file, refuses to overwrite an existing local
  file, and removes the secret after emulator teardown.
- The integration tests seed Auth identities plus canonical root, tenant,
  owner, pending staff, membership mirror, and invitation documents. They sign
  in through the Auth emulator, invoke the real compiled callable endpoints,
  and verify both the response and committed staff/mirror/invitation state.
- Token acceptance proves that an unverified invited identity can consume a
  real versioned HMAC proof. Visible acceptance proves the verified-email,
  explicitly visible path. Both assert the backend's exact five-field response.
- Exercising the real backend exposed that the visible Flutter fake and decoder
  expected a sixth `tenantStatus` field that the callable never returns. The
  decoder and fake now enforce the actual five-field contract; canonical active
  tenant eligibility remains backend-authoritative and the client still checks
  the routed membership before submission.
- The default Rules test command now names only the three Rules test files, so
  it cannot accidentally discover the separate multi-emulator integration
  suite.

Files in this chunk:

```text
firebase.invitation-test.json
functions/integration/.gitignore
functions/integration/index.js
functions/integration/package.json
functions/integration/package-lock.json
lib/tenancy/tenant_visible_invitation_acceptance.dart
rules-tests/README.md
rules-tests/package.json
rules-tests/package-lock.json
rules-tests/scripts/run-invitation-emulator-tests.js
rules-tests/test/invitation-acceptance.integration.test.js
test/tenancy/tenant_visible_invitation_acceptance_test.dart
PLAN.md
```

Validation evidence:

- `npm --prefix rules-tests run test:emulator:invitations` passed **2/2** tests
  against Auth, Firestore, and Functions emulators using Node.js 24 and JDK 21.
- `npm --prefix rules-tests run test:emulator` passed the existing Firestore
  Rules suite **18/18** against the emulator.
- `npm --prefix functions test` passed **152/152** Functions tests.
- `flutter test --no-pub test/tenancy` passed **153/153** tests; the focused
  visible-invitation file passed **10/10**.
- `dart analyze lib/tenancy test/tenancy` reported no issues.

The existing user-owned local edits remain separate and must not be staged:

```text
.vscode/settings.json
android/gradle.properties
pubspec.lock
```

### Next bounded frontend chunk

Implement only typed `setDefaultTenant` for the currently open canonical
tenant session, following the five steps in the preceding handoff. Keep the
callable session-bound, require explicit confirmation, preserve stable retry
idempotency and session-epoch stale-completion checks, refresh routing only
after success, and leave general tenant switching and operational POS state
outside the scope.

---

## Typed default tenant selection handoff - 2026-07-30

### Completed in this session

The next bounded frontend milestone enables only explicit, typed
`setDefaultTenant` for the currently open canonical tenant session. Opening or
selecting a tenant still changes only the UID-local device selection.

Implemented behavior:

- `TenantDefaultGateway` captures one active `TenantSession` and exposes no
  arbitrary tenant or caller input. Owner, admin, manager, and cashier sessions
  can create an intent; the tenant ID in the callable payload always comes from
  the captured session.
- Each explicit confirmation owns one cryptographically generated request ID.
  Duplicate taps are single-flight, and a recoverable retry reuses the same
  idempotency key.
- Callable responses must contain exactly `tenantId` and `defaultTenantId`.
  Both values must be valid tenant document IDs and must exactly equal the
  captured session tenant.
- The tenant-safe landing route shows a distinct `Make default` action and an
  explicit business-name confirmation. A profile that already names the open
  tenant renders a disabled `Default business` state instead of submitting
  again.
- Success and failure completions are discarded after a UID, tenant, or session
  epoch change. Errors are fixed safe text. The routing shell reloads the root
  profile and bounded membership directory only after a successful current
  response.
- The former untyped directory/bootstrap mutation helper, which accepted an
  arbitrary tenant ID, was removed. The session-bound gateway is now the sole
  enabled Flutter mutation path for this callable.
- The local Auth + Firestore + Functions fixture now exports the real compiled
  `setDefaultTenant` handler. Its integration test signs in through the Auth
  emulator, asserts the exact two-field response, and verifies the committed
  root `defaultTenantId` and server timestamp.

Files in this chunk:

```text
docs/frontend_tenant_migration_inventory.md
functions/integration/index.js
lib/tenancy/firebase_tenant_gateway.dart
lib/tenancy/tenancy.dart
lib/tenancy/tenant_bootstrap.dart
lib/tenancy/tenant_default_tenant.dart
lib/tenancy/tenant_directory.dart
lib/tenancy/tenant_routing_shell.dart
rules-tests/README.md
rules-tests/test/invitation-acceptance.integration.test.js
test/tenancy/tenant_bootstrap_test.dart
test/tenancy/tenant_default_tenant_test.dart
test/tenancy/tenant_routing_shell_test.dart
PLAN.md
```

Validation evidence:

- `dart analyze lib/tenancy test/tenancy` reported no issues.
- `flutter test --no-pub test/tenancy` passed **165/165** tests; the focused
  default-tenant file passed **11/11**, and focused default/routing coverage
  passed **21/21**.
- `npm --prefix functions test` passed **152/152** Functions tests.
- `npm --prefix rules-tests run test:emulator` passed the Firestore Rules suite
  **18/18** using the portable Node.js 24 and JDK 21 runtimes.
- `npm --prefix rules-tests run test:emulator:invitations` passed **3/3** real
  callable tests against Auth, Firestore, and Functions emulators, including
  the new persisted default-tenant contract.

The existing user-owned local edits remain separate and must not be staged:

```text
.vscode/settings.json
android/gradle.properties
pubspec.lock
```

### Next bounded frontend chunk

Implement only typed `requestTenant` from authenticated tenant routing:

1. Add an identity-bound callable gateway for `requestTenant` that accepts no
   caller UID, normalizes the proposed business name and slug, creates one
   request ID per submission intent, and strictly decodes exact
   tenant/name/slug agreement with pending lifecycle state.
2. Expose the request form from selector and no-accessible-tenant routing states
   for eligible verified tenant users. Do not expose it to platform identities,
   globally disabled roots, or as an automatic side effect of sign-in.
3. Use recoverable single-flight submission, stable retry idempotency, safe
   limit/conflict errors, Auth/routing stale-completion checks, and a bounded
   routing refresh only after success so the new pending membership becomes
   visible without being opened.
4. Test exact validation and payload derivation, response mismatches,
   confirmation/submission behavior, duplicate taps, retry, UID changes, and
   success refresh without granting operational access.
5. Extend the local callable emulator boundary for the real `requestTenant`
   transaction while leaving lifecycle approval, general tenant switching,
   checkout/Hive state, shifts, reports, returns, subscriptions, and catalog
   mutations outside this scope.

---

## Typed tenant request handoff - 2026-07-30

### Completed in this session

The next bounded frontend milestone enables only explicit, typed
`requestTenant` from authenticated tenant routing. Successful requests remain
pending and are never opened as operational tenant sessions.

Implemented behavior:

- `TenantRequestGateway` captures the current verified, globally active tenant
  identity and accepts no caller UID. Platform identities, disabled roots, and
  unverified users fail closed before a callable request.
- Business names are trimmed, internal whitespace is collapsed, control
  characters are rejected, and the backend's 2-100 character boundary is
  enforced. Slugs are trimmed, lower-cased, bounded to 3-48 characters, and
  limited to lower-case letters, numbers, and non-repeated internal hyphens.
- Each reviewed submission owns one cryptographically generated request ID.
  Duplicate confirmation taps are single-flight, and a recoverable retry of
  the unchanged reviewed name/slug reuses the same idempotency key.
- Callable responses must contain exactly `tenantId`, `name`, `slug`, and a
  pending `status`. Tenant IDs are validated and the normalized name/slug must
  exactly match the captured intent.
- The business selector and no-accessible-tenant route expose an explicit
  request form only to eligible verified tenant users. Review and confirmation
  are separate actions; cancellation performs no mutation.
- Known slug conflicts and request-limit failures receive fixed safe guidance.
  Other backend, decoding, and eligibility failures use a generic safe error
  and never expose callable details.
- Auth UID and routing-state changes discard outstanding success or failure
  completions. Only a successful current response triggers the bounded root
  profile and membership-directory refresh; the resulting pending owner mirror
  is visible with a lock and is not opened.
- The local Auth + Firestore + Functions fixture exports the real compiled
  `requestTenant` handler. Its integration test signs in a verified applicant,
  submits normalized input, asserts the exact response, and verifies the
  canonical tenant, owner staff, membership mirror, slug reservation, and root
  counters committed by the transaction.

Files in this chunk:

```text
docs/frontend_tenant_migration_inventory.md
functions/integration/index.js
lib/tenancy/tenancy.dart
lib/tenancy/tenant_request.dart
lib/tenancy/tenant_routing_shell.dart
rules-tests/README.md
rules-tests/test/invitation-acceptance.integration.test.js
test/tenancy/tenant_request_test.dart
test/tenancy/tenant_routing_shell_test.dart
test/tenancy/tenant_visible_invitation_acceptance_test.dart
PLAN.md
```

Validation evidence:

- `dart analyze lib/tenancy test/tenancy` reported no issues.
- `flutter test --no-pub test/tenancy` passed **177/177** tests; the focused
  tenant-request file passed **10/10**.
- `npm --prefix functions test` passed **152/152** Functions tests.
- `npm --prefix rules-tests run test:emulator` passed the Firestore Rules suite
  **18/18** using portable Node.js 24 and JDK 21 runtimes.
- `npm --prefix rules-tests run test:emulator:invitations` passed **4/4** real
  callable tests against Auth, Firestore, and Functions emulators, including
  the new persisted pending-tenant contract.
- `flutter build apk --debug --no-pub --target-platform android-x64` completed
  successfully with a single Gradle worker after the unconstrained cold build
  exceeded the workstation's worker-thread capacity.
- The fresh debug APK installed on a newly provisioned API 35 Android emulator.
  Android reported boot completion, package
  `com.example.flutter_application_1` remained running as PID 2302, and
  `.MainActivity` was the top resumed activity with no fatal exception.

The Android 15 emulator SDK and AVD live under `D:\android-emulator-sdk` and
`D:\android-avds`; they are machine-local validation tooling, not repository
artifacts.

The existing user-owned local edits remain separate and must not be staged:

```text
.vscode/settings.json
android/gradle.properties
pubspec.lock
```

### Next bounded frontend chunk

Implement only the platform pending-tenant review slice backed by typed
`setTenantLifecycle` transitions:

1. Replace the platform placeholder with a claim-and-root-gated, read-only,
   paginated pending-tenant queue that derives canonical tenant IDs and owner
   metadata from Firestore. Do not enable general platform user management.
2. Add a tenant-record-bound gateway for pending-to-active and
   pending-to-rejected `setTenantLifecycle` transitions. Derive the tenant ID
   and current status from the decoded queue item, create one request ID per
   review intent, require a reason for rejection, and strictly decode exact
   tenant/previous/target status plus the fan-out operation ID.
3. Require explicit approve/reject confirmation, recoverable single-flight
   submission, stable retry idempotency, safe capacity/invariant errors, and
   Auth/platform/routing stale-completion checks. Refresh only the bounded
   pending queue after success.
4. Test strict queue decoding and pagination, unsupported transitions,
   response mismatches, confirmation dismissal, duplicate taps, retry,
   platform identity changes, and stale tenant records.
5. Extend the local callable emulator fixture for real pending approval and
   rejection transactions while leaving suspension/reactivation/archival,
   global-user status, tenant switching, checkout/Hive state, and operational
   POS screens outside this scope.

---

## Platform pending-tenant review handoff - 2026-07-30

### Completed in this session

The platform placeholder is replaced by the bounded pending-business review
slice. No general platform user management or operational tenant route was
enabled.

Implemented behavior:

- The routing shell now requires both an active canonical
  `platform_admin` root and the current Auth
  `platformRole == superAdmin` claim before it constructs the platform queue.
  A root/claim mismatch starts no queue reads and renders a fixed access state.
- The Firestore queue reads only canonical `tenants` whose status is `pending`,
  ordered by request time descending and tenant ID ascending. Pages are bounded
  to 1-50 items and use the exact timestamp/tenant cursor. A production
  composite index and a Rules-emulator query contract cover that ordering.
- Each tenant ID comes from its canonical document. Name, slug, owner UID,
  request timestamp, and canonical owner root metadata are decoded fail-closed.
  Disabled owners remain visible so an operator can reject an ineligible
  request; their status is shown explicitly and backend activation checks stay
  authoritative.
- `PlatformTenantReviewGateway` captures one decoded pending tenant and one
  claim-plus-root-gated operator. It exposes only pending-to-active approval and
  pending-to-rejected rejection, accepts no arbitrary tenant or current status,
  requires a normalized rejection reason, and creates one request ID per review
  intent.
- Callable responses must contain exactly tenant ID, previous status, target
  status, and fan-out operation ID. Tenant/status mismatches, extra fields,
  invalid IDs, stale records, and lost operator eligibility fail closed.
- Approve and reject each require explicit confirmation. Submission is
  single-flight, a recoverable retry reuses the same idempotency key, UI errors
  are fixed safe text, and Auth/routing/queue changes discard stale completions.
  Only a successful current response reloads the bounded first pending page.
- The local Auth + Firestore + Functions fixture exports the real compiled
  `setTenantLifecycle`. Integration coverage signs in a claimed platform
  operator and verifies both pending approval and rejection, including the
  exact four-field response, tenant and owner-mirror lifecycle state, owner
  active count, fan-out job, and privileged rejection reason audit.

Files in this chunk:

```text
docs/frontend_tenant_migration_inventory.md
firestore.indexes.json
functions/integration/index.js
lib/main.dart
lib/tenancy/platform_tenant_review.dart
lib/tenancy/tenancy.dart
lib/tenancy/tenant_routing_shell.dart
rules-tests/README.md
rules-tests/test/control-plane.test.js
rules-tests/test/invitation-acceptance.integration.test.js
test/tenancy/platform_tenant_review_test.dart
test/tenancy/tenant_routing_shell_test.dart
PLAN.md
```

Validation evidence:

- `dart analyze lib/tenancy test/tenancy` reported no issues.
- The wider analysis including `lib/main.dart` and `lib/login_screen.dart`
  reported only the pre-existing experimental `profilesSampleRate` warning.
- `flutter test --no-pub test/tenancy` passed **192/192** tests; focused
  platform review plus routing coverage passed **27/27**.
- `npm --prefix functions test` passed **152/152** Functions tests.
- `npm --prefix rules-tests run test:emulator` passed the Firestore Rules suite
  **19/19**, including the claimed-platform pending-queue query and denied
  no-claim query.
- `npm --prefix rules-tests run test:emulator:invitations` passed **6/6** real
  callable tests against Auth, Firestore, and Functions emulators, including
  persisted pending approval and rejection transactions.
- `flutter build apk --debug --no-pub --target-platform android-x64` completed
  successfully. The final APK installed on the API 35 emulator; package
  `com.example.flutter_application_1` remained alive as PID 8264,
  `.MainActivity` was the top resumed activity, and the post-launch fatal log
  scan returned zero entries.

Portable Node.js 24 and Temurin JDK 21 under
`D:\firebase-emulator-tools`, plus the API 35 SDK/AVD under
`D:\android-emulator-sdk` and `D:\android-avds`, remain machine-local test
tooling and are not repository artifacts.

The existing user-owned local edits remain separate and must not be staged:

```text
.vscode/settings.json
android/gradle.properties
pubspec.lock
```

### Next bounded frontend chunk

Implement only active-tenant suspension and suspended-tenant reactivation on
the typed platform lifecycle foundation:

1. Add a separate claim-and-root-gated, read-only paginated queue for active
   and suspended canonical tenants. Keep the pending review queue independent,
   preserve stable status/time/tenant ordering, and continue deriving tenant
   IDs and owner metadata only from canonical Firestore documents.
2. Extend the record-bound lifecycle gateway only for active-to-suspended and
   suspended-to-active transitions. Require a normalized reason for suspension,
   derive current/target status from the decoded record and action, and strictly
   validate the exact lifecycle response and fan-out operation ID.
3. Require explicit confirmation, stable retry idempotency, single-flight
   submission, safe invariant/capacity errors, stale Auth/claim/record checks,
   and refresh only the affected bounded queue after success.
4. Test status-filtered pagination, transition denial, reason validation,
   response mismatches, duplicate taps, retry, identity/record switches, and
   activation-capacity failures. Extend the real callable emulator boundary for
   one suspension and one reactivation transaction.
5. Leave archival, global-user status, general platform user management,
   tenant switching, checkout/Hive state, and operational POS screens outside
   this next chunk.

---

## Platform tenant suspension/reactivation handoff - 2026-07-30

### Completed in this session

The platform tenant-management route now adds only active-tenant suspension
and suspended-tenant reactivation on top of the existing pending review slice.
Archival, global-user administration, tenant switching, and operational tenant
screens remain disabled.

Implemented behavior:

- A separate claim-and-root-gated Firestore queue reads only canonical active
  and suspended tenants. It is bounded to 1-50 records and uses stable status,
  `updatedAt` descending, then tenant-ID ordering with an exact three-part
  cursor and a production composite index.
- Tenant IDs, lifecycle status, timestamps, names, slugs, owner UIDs, and owner
  root metadata are decoded fail-closed from canonical documents. Pending,
  rejected, archived, malformed, and ownerless records cannot enter this
  lifecycle queue.
- `PlatformTenantLifecycleGateway` binds one decoded tenant record and one
  claim-plus-root-gated operator. It exposes only active-to-suspended and
  suspended-to-active actions, accepts no arbitrary current status or tenant
  ID, and requires a normalized 3-1000 character reason for suspension.
- Each explicit confirmation owns one cryptographically generated request ID.
  Duplicate taps are single-flight and recoverable retry reuses the same
  idempotency key. Changing the reason creates a new reviewed intent.
- Callable responses must contain exactly the tenant ID, previous status,
  target status, and fan-out operation ID. Tenant/status mismatches, extra
  fields, malformed IDs, stale records, identity changes, and lost platform
  eligibility fail closed.
- Suspension and reactivation have distinct confirmations and fixed safe
  errors, including active-owner capacity guidance on reactivation. Auth,
  platform-route, record-status, record-timestamp, and queue-epoch checks
  discard stale success and failure completions.
- Pending review and active/suspended management are separate tabbed queues.
  A successful mutation refreshes only its affected bounded queue and does not
  open an operational tenant session.
- Firestore Rules emulator coverage proves the active/suspended query shape is
  readable only with the full platform claim/root authorization. The real
  callable integration fixture now verifies persisted suspension and
  reactivation state, owner counters, mirrors, fan-out responses, and
  privileged audit reasons.

Files in this chunk:

```text
docs/frontend_tenant_migration_inventory.md
firestore.indexes.json
lib/tenancy/platform_tenant_lifecycle.dart
lib/tenancy/platform_tenant_review.dart
lib/tenancy/tenancy.dart
lib/tenancy/tenant_routing_shell.dart
rules-tests/README.md
rules-tests/test/control-plane.test.js
rules-tests/test/invitation-acceptance.integration.test.js
test/tenancy/platform_tenant_lifecycle_test.dart
test/tenancy/tenant_routing_shell_test.dart
PLAN.md
```

Validation evidence:

- `dart analyze lib/tenancy test/tenancy` reported no issues.
- The wider analysis including `lib/main.dart` and `lib/login_screen.dart`
  reported only the pre-existing experimental `profilesSampleRate` warning.
- `flutter test --no-pub test/tenancy` passed **205/205** tests; the focused
  lifecycle file passed **13/13**.
- `npm --prefix functions test` passed **152/152** Functions tests.
- `npm --prefix rules-tests run test:emulator` passed the Firestore Rules suite
  **20/20** using portable Node.js 24 and JDK 21.
- `npm --prefix rules-tests run test:emulator:invitations` passed **7/7** real
  callable tests against Auth, Firestore, and Functions emulators, including
  the suspension and reactivation transactions.
- Android build/emulator validation was intentionally skipped for this chunk
  at the user's request.

The existing user-owned local edits remain separate and must not be staged:

```text
.vscode/settings.json
android/gradle.properties
pubspec.lock
```

### Next bounded frontend chunk

Implement only rejected-tenant archival on the typed platform lifecycle
foundation:

1. Add a separate claim-and-root-gated, read-only paginated queue for rejected
   canonical tenants, ordered by lifecycle update time and tenant ID. Keep the
   pending and active/suspended queues independent.
2. Add a rejected-record-bound gateway for rejected-to-archived
   `setTenantLifecycle`. Require a normalized archival reason and a destructive
   confirmation that includes the canonical business name and slug; derive the
   tenant ID and previous status exclusively from the decoded record.
3. Preserve stable retry idempotency, single-flight submission, strict exact
   response decoding, safe invariant errors, and Auth/claim/record/queue stale
   completion checks. Refresh only the rejected queue after success.
4. Test rejected-only pagination, all unsupported transitions, reason and
   confirmation validation, response mismatches, duplicate taps, retry,
   identity/record switches, and one real rejected-to-archived emulator
   transaction with owner counters, mirror, fan-out, and audit assertions.
5. Leave archival of active, suspended, or pending tenants, global-user status,
   general platform user management, tenant switching, checkout/Hive state,
   and operational POS screens outside this next chunk.

---

## Platform rejected-tenant archival handoff - 2026-07-30

### Completed in this session

The platform tenant-management route now adds only rejected-to-archived
lifecycle review. Archival of pending, active, or suspended tenants, global
user administration, tenant switching, and operational tenant screens remain
disabled.

Implemented behavior:

- A third, independent claim-and-root-gated Firestore queue reads only
  canonical rejected tenants. It is bounded to 1-50 records and uses stable
  `updatedAt` descending then tenant-ID ordering with an exact two-part cursor.
  The existing production `status`/`updatedAt`/document-ID composite index
  supports this equality-filtered query.
- Tenant IDs, rejected status, timestamps, names, slugs, owner UIDs, and owner
  root metadata are decoded fail-closed from canonical documents. Pending,
  active, suspended, archived, malformed, and ownerless records cannot enter
  the archival queue.
- `PlatformTenantArchivalGateway` binds one decoded rejected tenant and one
  claim-plus-root-gated operator. It exposes only rejected-to-archived,
  accepts no arbitrary tenant ID or previous/target status, requires a
  normalized 3-1000 character archival reason, and requires the exact
  canonical `business name (slug)` confirmation.
- Each reviewed archival intent owns one cryptographically generated request
  ID. Duplicate taps are single-flight, recoverable retry reuses the same
  idempotency key, and editing either confirmation field creates a new intent.
- Callable responses must contain exactly tenant ID, previous status, target
  status, and fan-out operation ID. Tenant/status mismatches, extra fields,
  malformed IDs, stale records, identity changes, and lost platform
  eligibility fail closed.
- The destructive form shows both canonical business name and slug, uses fixed
  safe errors, and discards stale success and failure completions using Auth,
  claim, record status/time, selected-record, and queue-epoch checks. Only a
  successful current response refreshes the rejected queue.
- Firestore Rules emulator coverage proves the rejected-only ordered query is
  readable only with full platform claim/root authorization. The real callable
  integration fixture verifies persisted archival status, owner mirror and
  counters, fan-out state, and privileged audit reason.

Files in this chunk:

```text
docs/frontend_tenant_migration_inventory.md
lib/tenancy/platform_tenant_archival.dart
lib/tenancy/platform_tenant_lifecycle.dart
lib/tenancy/tenancy.dart
lib/tenancy/tenant_routing_shell.dart
rules-tests/README.md
rules-tests/test/control-plane.test.js
rules-tests/test/invitation-acceptance.integration.test.js
test/tenancy/platform_tenant_archival_test.dart
test/tenancy/tenant_routing_shell_test.dart
PLAN.md
```

Validation evidence:

- `dart analyze lib/tenancy test/tenancy` reported no issues.
- The wider analysis including `lib/main.dart` and `lib/login_screen.dart`
  reported only the pre-existing experimental `profilesSampleRate` warning.
- `flutter test --no-pub test/tenancy` passed **217/217** tests; focused
  archival coverage passed **12/12**.
- `npm --prefix functions test` passed **152/152** Functions tests.
- `npm --prefix rules-tests run test:emulator` passed the Firestore Rules suite
  **21/21** using portable Node.js 24 and JDK 21.
- `npm --prefix rules-tests run test:emulator:invitations` passed **8/8** real
  callable tests against Auth, Firestore, and Functions emulators, including
  the rejected-to-archived transaction.
- Android build/emulator validation was intentionally skipped for this chunk
  at the user's request.

The first Rules-emulator launch selected system JDK 17 and stopped before
running tests because current Firebase tooling requires JDK 21. Both emulator
suites were then rerun successfully with the handover's portable Node.js 24
and Temurin JDK 21 under `D:\firebase-emulator-tools`; those tools remain
machine-local and are not repository artifacts.

The existing user-owned local edits remain separate and must not be staged:

```text
.vscode/settings.json
android/gradle.properties
pubspec.lock
```

### Next bounded frontend chunk

Implement only exact-UID platform global-user status review on the existing
recoverable saga boundary:

1. Add a claim-and-root-gated exact-UID lookup for a canonical root user and
   its authoritative affected tenant/admin-principal summary. Do not add a
   general user directory, search, pagination, bulk actions, or platform-role
   management.
2. Add a decoded-user-bound `setGlobalUserStatus` gateway for active-to-disabled
   and disabled-to-active only. Require a normalized reason and destructive
   UID confirmation for disabling, derive the UID and target status from the
   decoded record/action, and strictly decode operation ID, UID, target status,
   saga status, affected tenant IDs, attempt count, and optional safe error
   code.
3. Require explicit confirmation, stable retry idempotency, single-flight
   submission, stale Auth/claim/record checks, and safe handling of completed
   versus partially-failed saga responses. Refresh only the exact target after
   a current completion; require a new sign-in when the current operator is
   affected.
4. Test lookup authorization and decoding, transition/reason/confirmation
   denial, response mismatches, duplicate taps, retry, identity/target
   switches, affected-tenant warnings, and one real disable/reactivate emulator
   saga transaction including Auth disabled state, root state, token cutoff,
   operation record, and audit assertions.
5. Leave platform-admin grant/revoke, general platform user management,
   archival of non-rejected tenants, tenant switching, checkout/Hive state,
   and operational POS screens outside this next chunk.

---

## Platform exact-UID global-user status handoff - 2026-07-30

### Completed in this session

The platform tenant-management route now adds only exact-UID global-user
status review and active/disabled transitions. General user discovery,
platform-role administration, bulk actions, and operational tenant screens
remain disabled.

Implemented behavior:

- A fourth claim-and-root-gated platform tab accepts one exact canonical UID.
  It exposes no directory, search, pagination, bulk action, or role-management
  surface.
- `getGlobalUserStatusReview` performs bounded authoritative server scans of
  the target root, canonical staff memberships, owned tenants, and affected
  administrative principals. It returns a strict safe projection only after
  full platform authorization. Keeping this scan behind a callable preserves
  the frozen deny-by-default legacy root `staff` Rules boundary; a client
  collection-group query could not safely express that distinction.
- The Flutter adapter explicitly prepares one exact immutable review and
  strictly decodes all roots, tenant records, staff records, IDs, statuses,
  roles, and timestamps. Dependent administrator-root reads cannot replace the
  target snapshot.
- Affected-tenant summaries are derived from canonical ownership and staff
  evidence. The review warns when disabling the target would make an owner
  unavailable or leave a non-archived tenant without another active canonical
  tenant-user administrator.
- `PlatformGlobalUserStatusGateway` binds the decoded target and exposes only
  active-to-disabled and disabled-to-active. Both actions require a normalized
  3-1000 character reason; disabling additionally requires the exact target
  UID as destructive confirmation.
- Each reviewed intent owns one cryptographically generated request ID.
  Duplicate taps are single-flight, recoverable retry reuses the same
  idempotency key, target/identity changes fail closed, and the response must
  exactly agree on operation ID, UID, target status, saga status, affected
  tenant IDs, attempt count, and optional safe error code.
- Completed and partially-failed sagas are handled separately. Only a current
  completed response refreshes the exact target; a partial response remains
  retryable. Disabling the current operator signs out and requires a fresh
  sign-in rather than attempting an in-place refresh.
- Real emulator coverage proves tenant users cannot call the review, a fully
  authorized platform operator can, and disable/reactivate updates Auth,
  token cutoff, root state, operation steps, affected-tenant alert, and audit
  evidence while leaving advisory membership mirrors non-authoritative.

Files in this chunk:

```text
docs/frontend_tenant_migration_inventory.md
functions/integration/index.js
functions/src/index.ts
functions/src/lifecycle/globalStatusReview.ts
lib/tenancy/platform_global_user_status.dart
lib/tenancy/platform_tenant_lifecycle.dart
lib/tenancy/tenancy.dart
lib/tenancy/tenant_routing_shell.dart
rules-tests/README.md
rules-tests/scripts/run-invitation-emulator-tests.js
rules-tests/test/invitation-acceptance.integration.test.js
test/tenancy/platform_global_user_status_test.dart
test/tenancy/tenant_routing_shell_test.dart
PLAN.md
```

Validation evidence:

- `dart analyze lib/tenancy test/tenancy` reported no issues.
- `flutter test --no-pub --concurrency=1 test/tenancy` passed **233/233**
  tests; the new global-user coverage passed **16/16** within that suite.
- `npm --prefix functions test` passed **152/152** Functions tests.
- `npm --prefix rules-tests run test:emulator` passed the Firestore Rules suite
  **21/21** using portable Node.js 24 and JDK 21.
- `npm --prefix rules-tests run test:emulator:invitations` passed **9/9** real
  callable tests against Auth, Firestore, and Functions emulators, including
  exact review authorization and the disable/reactivate saga.
- Android build/emulator validation was intentionally skipped for this chunk
  at the user's request.

The first Rules-emulator launch selected system JDK 17 and stopped before any
test ran. The first full Functions-emulator launch also exhausted the default
worker heap. The final successful runs pinned the machine-local portable JDK
21 and Node.js 24 toolchain under `D:\firebase-emulator-tools` and set
`NODE_OPTIONS=--max-old-space-size=512`; these are not repository artifacts.

The existing user-owned local edits remain separate and must not be staged:

```text
.vscode/settings.json
android/gradle.properties
pubspec.lock
```

### Next bounded backend chunk

Implement only a secure operator entry point for the existing canonical
`grantPlatformAdmin` service:

1. Prefer a deliberately invoked Admin SDK/CLI workflow with an explicit
   project allowlist, authenticated actor identity, exact target UID, bounded
   reason, and destructive target confirmation. Do not expose a general
   in-app platform-user directory or make the service a broadly callable
   endpoint.
2. Preserve the service's authoritative eligibility scan, resumable identity
   transition, custom-claim compensation, audit evidence, and fail-closed
   claim-plus-root authorization boundary. Treat advisory counters and routing
   mirrors as non-authoritative.
3. Add strict input/project guards, deterministic operator-facing exit states,
   safe recoverable retry guidance, and tests proving configuration mistakes
   cannot target staging or production implicitly.
4. Add a real Auth/Firestore emulator grant transaction covering an eligible
   identity, an ineligible canonical tenant identity, claim/root completion,
   transition recovery, and audit evidence.
5. Leave platform-admin revocation, Flutter role-management UI, general user
   search, tenant switching, checkout/Hive state, deployment, and operational
   POS screens outside that chunk.

---

## Guarded platform-admin grant CLI handoff - 2026-07-31

### Completed in this session

The existing canonical `grantPlatformAdmin` saga now has a deliberately
invoked Admin SDK CLI. It is not exported as a callable, and no Flutter
role-management or general platform-user surface was added.

Implemented behavior:

- `grant-platform-admin` requires an explicit environment, the exact
  source-controlled project mapped to that environment, a second exact project
  confirmation, the actor UID, exact target UID, a second exact target
  confirmation, a stable request ID, and a normalized 3-1000 character reason.
  Production additionally requires `--confirm-production`.
- The allowlist is fixed to the frozen development, staging, and production
  projects. The only additional entry is the fixed demo integration project,
  which is rejected unless both Auth and Firestore emulator hosts resolve to
  localhost. Real-project execution is rejected when emulator variables are
  present.
- Application Default Credentials authenticate real-project Admin SDK access.
  The recorded actor is separately authorized from the exact enabled Auth
  identity, its `platformRole=superAdmin` claim, and an active canonical
  `platform_admin` root without an identity transition. Claim-only and
  root-only operators fail closed.
- The CLI delegates target mutation exclusively to the existing canonical
  service. Its collection-group staff and invitation scans, owner scan,
  resumable `granting_platform` transition, unrelated-claim preservation,
  completion compensation, and bounded audit evidence remain unchanged.
  Advisory counters can warn but cannot authorize or reject a grant.
- Operator output uses deterministic safe exit states: success `0`, invalid
  configuration `2`, operator denial `3`, canonical target ineligibility `4`,
  recoverable retry `5`, and unexpected safe failure `1`. Recoverable output
  directs the operator to retry the identical command with the same request ID
  and does not include provider or canonical evidence details.
- The real emulator fixture invokes the compiled CLI in child processes. It
  proves eligible claim/root completion with unrelated claim preservation,
  canonical staff/owner rejection despite zero counters, held-transition
  resumption, actor/reason/audit evidence, and transition cleanup.

Files in this chunk:

```text
functions/package.json
functions/src/cli/grantPlatformAdmin.test.ts
functions/src/cli/grantPlatformAdmin.ts
functions/src/platform/README.md
rules-tests/README.md
rules-tests/test/invitation-acceptance.integration.test.js
PLAN.md
```

Validation evidence:

- `npm --prefix functions test` passed **159/159** Functions tests, including
  **7/7** guarded CLI tests.
- `npm --prefix rules-tests run test:emulator` passed the Firestore Rules suite
  **21/21** using portable Node.js 24 and JDK 21.
- `npm --prefix rules-tests run test:emulator:invitations` passed **10/10** real
  Auth, Firestore, and Functions emulator tests, including the compiled CLI's
  eligible, ineligible, and resumed grant transactions.
- A focused CLI emulator run also passed **1/1** before the complete integration
  suite was run.
- Android build/emulator validation was intentionally skipped for this chunk
  at the user's request.

The first emulator attempt selected system JDK 17 and stopped before starting
any emulator because current Firebase tooling requires JDK 21. The focused
rerun and both complete emulator suites passed with portable Node.js 24 and
Temurin JDK 21 under `D:\firebase-emulator-tools`, plus
`NODE_OPTIONS=--max-old-space-size=512`. Those tools are machine-local and are
not repository artifacts. One focused CLI-only launch timed out Functions
discovery, which that test does not use; the subsequent full integration run
loaded all seven callable fixtures and passed.

The existing user-owned local edits remain separate and must not be staged:

```text
.vscode/settings.json
android/gradle.properties
pubspec.lock
```

### Next bounded backend chunk

Implement only canonical platform-admin revocation on a recoverable,
operator-only boundary:

1. Freeze and implement a private `revokePlatformAdmin` saga plus an Admin SDK
   CLI entry point; do not expose a callable, Flutter role-management UI,
   platform-user directory, search, or bulk action.
2. Require the same explicit project allowlist, authenticated claim-plus-root
   actor, exact target UID and confirmation, bounded reason, stable request ID,
   and production confirmation. The actor and target must differ.
3. Authorize from canonical roots and current Auth claims, verify again that
   the target has no canonical tenant membership/ownership/invitation, and
   prevent removal of the last fully active platform administrator using an
   authoritative bounded scan rather than counters.
4. Make claim removal the access-revoking step, persist resumable operation and
   audit evidence around the external Auth effect, revoke refresh tokens, and
   define a fail-closed retry path for root/claim disagreement. Do not restore
   a platform claim automatically.
5. Add unit and real Auth/Firestore emulator coverage for success, last-admin
   denial, target/actor mismatch, stale root/claim state, canonical tenant
   evidence, partial failure resumption, token cutoff, and audits. Leave
   tenant switching, checkout/Hive state, deployment, and operational POS
   screens outside that chunk.

---

## Guarded platform-admin revocation CLI handoff - 2026-07-31

### Completed in this session

Canonical platform-administrator revocation now exists only behind a
deliberately invoked Admin SDK CLI and a private resumable service. It is not
exported from `functions/src/index.ts`; no callable, Flutter role-management
surface, user directory, search, or bulk action was added.

Implemented behavior:

- `revoke-platform-admin` reuses the fixed development, staging, production,
  and localhost-only emulator allowlist. It requires the explicit environment,
  exact project and confirmation, claim-plus-root operator UID, exact target
  UID and confirmation, a stable request ID, a normalized 3-1000 character
  reason, and production confirmation. Actor and target must differ.
- The private service transactionally acquires
  `identityTransition=revoking_platform` plus an exact deterministic operation
  lock. Stable input and progress are stored under
  `platform_identity_operations`; privileged actor, reason, scan, phase,
  cutoff, and completion evidence are stored under `platform_audit_logs`.
- Before any Auth mutation it verifies the target's enabled `superAdmin` claim
  and active `platform_admin` root, repeats the canonical collection-group
  staff and invitation scans plus tenant-owner scan, and rejects any tenant
  evidence. Advisory root counters are never consulted for authorization.
- A bounded authoritative root/Auth scan requires proof of another fully
  active claim-plus-root administrator. A complete scan with no other active
  administrator rejects revocation; a truncated scan without positive proof
  fails recoverably. Identities already holding a transition cannot count.
- The saga durably records `claim_removal_pending` before removing only the
  `platformRole` claim. It then revokes refresh tokens, records the second-safe
  Auth cutoff, and atomically converts the root to `tenant_user` while clearing
  the transition and operation lock. Unrelated custom claims are preserved.
- A response loss after successful Auth claim removal resumes from the durable
  pending phase and never restores a platform claim. Initial root/claim
  disagreement rejects fail-closed; partial external or Firestore failures use
  exit `5` and require the identical command and request ID.
- Terminal target, canonical tenant-evidence, last-admin, and operation
  conflicts use deterministic safe denial states. Provider and canonical
  evidence details are absent from CLI error output.
- The real emulator fixture proves last-admin denial, successful CLI
  completion, idempotent replay, unrelated-claim preservation, refresh-token
  cutoff, root demotion, canonical evidence and stale-state rejection, and
  recovery after an ambiguous successful claim removal.
- The integration runner now gives Firebase's HTTP Functions discovery a
  bounded 60-second default through its supported
  `FUNCTIONS_DISCOVERY_TIMEOUT` override. This avoids the Firebase CLI's
  unreliable 10-second default on the current constrained Windows host and can
  still be explicitly overridden.

Files in this chunk:

```text
functions/package.json
functions/src/cli/revokePlatformAdmin.test.ts
functions/src/cli/revokePlatformAdmin.ts
functions/src/core/model.ts
functions/src/platform/README.md
functions/src/platform/revokePlatformAdmin.test.ts
functions/src/platform/revokePlatformAdmin.ts
rules-tests/README.md
rules-tests/scripts/run-invitation-emulator-tests.js
rules-tests/test/invitation-acceptance.integration.test.js
PLAN.md
```

Validation evidence:

- `npm --prefix functions test` passed **166/166** Functions tests.
- `npm --prefix rules-tests run test:emulator` passed the Firestore Rules suite
  **21/21** using portable Node.js 24 and JDK 21.
- A focused revocation integration run passed **2/2** real Auth/Firestore
  emulator tests after the harness used the Functions package's Firebase Admin
  instance for direct private-service calls.
- `npm --prefix rules-tests run test:emulator:invitations` passed **12/12** real
  Auth, Firestore, and Functions emulator tests, including every previous
  callable/grant contract and the new revocation transactions.
- Android build/emulator validation was intentionally skipped for this chunk
  at the user's request.

The first complete integration command wrapper expired after three minutes and
left one Firestore emulator process, which was identified by its exact command
line and stopped before retry. The first focused revocation run exposed a
test-only mixed-Firebase-Admin sentinel mismatch; using the Functions package's
Admin clients fixed it and the focused run passed. Two later full launches hit
Firebase CLI's 10-second Functions discovery timeout before loading any
callables. After the runner set the supported bounded 60-second discovery
override, the complete 12-test suite loaded all seven fixtures and passed.

All successful emulator runs pinned portable Node.js 24, Temurin JDK 21, and
`NODE_OPTIONS=--max-old-space-size=512` from `D:\firebase-emulator-tools`.
Those tools are machine-local and are not repository artifacts.

The existing user-owned local edits remain separate and must not be staged:

```text
.vscode/settings.json
android/gradle.properties
pubspec.lock
```

### Test iteration instructions for future sessions

Do not use the full Firebase integration harness as the normal edit/test loop.
On this machine the latest measured baselines were approximately 115 seconds
for the 166-test Functions command, 79 seconds for the 21-test Rules emulator,
208 seconds even for the filtered two-test revocation integration run, and 312
seconds for the complete 12-test integration run. Most of that time is build,
JVM/emulator startup, Functions discovery, cold worker, CLI process, and
teardown overhead rather than the focused assertions.

Use this three-level test discipline:

1. During implementation, keep TypeScript compilation current with watch or an
   incremental build and run only the affected compiled unit-test files. Run
   `git diff --check` alongside those tests. Do not rebuild and execute all 166
   Functions tests after every small edit.
2. When a behavior is coherent, run the smallest emulator combination it
   actually requires. Private Admin SDK grant/revoke sagas need Auth and
   Firestore, not the Functions emulator. A Node test-name filter skips test
   bodies but does not reduce emulator startup, so it is not a substitute for
   an Auth/Firestore-only runner.
3. After code and harness changes are frozen, run exactly one release-style
   sequence: full Functions tests, full Rules emulator tests when applicable,
   and the complete Auth/Firestore/Functions integration suite. Make no code
   cleanup or type refactor after that green pass; update handover text and
   commit. Any later code edit invalidates the pass and requires proportionate
   retesting.

Avoid the failure patterns observed in this session:

- Set command wrappers from measured baselines. The full integration suite
  needs a 10-12 minute outer bound on this host; a three-minute wrapper can
  terminate healthy work and orphan an emulator.
- Inspect the first infrastructure failure before retrying. Do not repeatedly
  relaunch after Functions discovery errors. The runner now defaults the
  supported `FUNCTIONS_DISCOVERY_TIMEOUT` to 60 seconds.
- When direct tests import compiled Functions code, construct Firestore, Auth,
  `FieldValue`, and other Admin objects from the Functions package's one
  `firebase-admin` installation. Mixing Admin installations creates foreign
  sentinel/prototype failures that do not represent production behavior.
- Perform refactors and type cleanup before the green validation sequence, and
  run at least `npm --prefix functions run build` immediately after every
  TypeScript edit.
- Reuse a known-current Functions build during focused emulator retries. Do not
  make both the unit command and every emulator command rebuild unchanged
  output.
- Keep one local emulator set alive for repeated focused runs when practical;
  use the isolated `emulators:exec` lifecycle for the final evidence run.
- One real compiled CLI success smoke test is sufficient per operator tool
  during iteration. Exercise rejection, idempotency, and partial recovery
  directly in one Admin test process; reserve repeated CLI subprocess coverage
  for the final suite when specifically required.

Keep test output and model context bounded:

- Remove inherited `DEBUG` from Firebase CLI child environments unless
  diagnosing a failure. Firebase treats any non-empty value, including the
  machine's `DEBUG=release`, as debug mode and otherwise emits command details,
  complete environments, and large expected-denial traces.
- Prefer Node's concise/dot reporter for green unit runs. Capture verbose
  emulator output to a local ignored log and print only test totals and timing;
  on failure print the failing assertion and a bounded tail, not the entire
  emulator log.
- Read targeted handover sections and diffs rather than repeatedly loading all
  of `PLAN.md` or complete generated output into context.
- Report only phase changes during long runs. Record exact commands, pass
  counts, toolchain pins, and meaningful failures once in the final handover.

Recommended harness remediation, in priority order:

1. Strip `DEBUG` from spawned Firebase environments and add concise reporters.
2. Add incremental Functions build plus separate `test:compiled` and
   `:no-build` emulator commands.
3. Add a dedicated Auth/Firestore-only platform-identity emulator runner.
4. Reduce repeated grant/revoke CLI subprocesses to one smoke invocation plus
   same-process saga cases.
5. Add one sequential `verify:handover` command with the pinned Node 24/JDK 21
   environment and appropriate measured timeouts.

### Next bounded frontend chunk

Implement only the tenant-switch safety coordinator and wire it into the typed
routing shell:

1. Add a session-bound `TenantSwitchCoordinator` with typed blockers for an
   unsynchronized checkout, submission in flight, other pending writes,
   unfinished cash count/shift close, unsaved tenant workflow, and unavailable
   online target validation. A server-confirmed open shift by itself must not
   block switching.
2. Require every registered tenant-scoped state source to return an explicit
   clean or blocked result; missing, malformed, or failed state inspection must
   fail closed. Keep checkout submission and cash-close implementation outside
   this chunk.
3. Revalidate the exact target against the canonical paginated tenant
   directory while online, retain the current session on any denial/failure,
   and persist the device-local last selection only after the new authorized
   session has opened.
4. Expose a bounded `Change business` path from the current safe tenant shell,
   invalidate prior-session asynchronous completions by epoch, and prevent
   duplicate concurrent switch attempts. Do not make legacy operational POS
   screens reachable.
5. Add unit/widget coverage for every blocker, open-shift non-blocking behavior,
   offline and inspection failures, stale target access, failed persistence,
   current-session preservation, successful epoch change, and stale async
   completion disposal.
6. Leave the encrypted Hive checkout outbox state machine, shift restoration,
   cashier cross-tenant shift restriction, stock mutation, receipts,
   deployment, and Android emulator validation outside that chunk.

---

## Tenant-switch safety coordinator handoff - 2026-07-31

### Completed in this session

The typed tenant routing shell now exposes a bounded `Change business` path
only from the current safe landing route. Legacy POS routes remain unreachable,
and no checkout, cash-close, shift-restoration, stock, receipt, or deployment
behavior was added.

Implemented behavior and safety decisions:

- A session-bound `TenantSwitchCoordinator` requires exactly one explicit
  inspection for checkout, other pending writes, cash/shift close, and unsaved
  tenant workflow state. Missing or duplicate sources, null results, thrown
  inspections, stale UID/tenant/epoch answers, mismatched source areas, and
  invalid blocker/area combinations all fail closed.
- Typed blockers cover unsynchronized checkout, checkout submission in flight,
  other pending writes, unfinished cash count/shift close, unsaved workflows,
  and unavailable online target validation. A server-confirmed open shift is
  represented explicitly and does not block unless cash-close work is also
  unfinished.
- The production safe landing route registers four explicit clean sources
  because it exposes no checkout, mutation queue, cash-close, or editable
  tenant workflow. This assertion must be replaced by real state owners before
  any corresponding operational route becomes reachable.
- Connectivity is checked before target validation. The exact target is then
  revalidated through the complete canonical paginated `listMyTenants`
  directory. Missing/inaccessible canonical targets are distinguished from
  transport, pagination, and malformed-response failures; none changes the
  current session.
- Successful switching opens the newly authorized session and advances its
  epoch before writing the UID-local last selection. A failed local write
  restores the prior tenant with another fresh epoch, so prior asynchronous
  work remains invalidated while the user stays in the original business.
- A concurrent attempt receives a deterministic in-progress blocker. Session
  changes during inspection, validation, or persistence abort safely. In
  particular, an Auth clear during persistence can never reopen the old tenant.
- The switcher lists only other accessible routing projections, keeps the
  dialog/current tenant on denials, shows bounded safe messages, and persists
  the device-local selection only after the target session has opened.
- Widget coverage proves that an outstanding tenant-A branding completion is
  discarded after a tenant-B epoch opens. The target is never used to unlock
  any legacy operational POS screen.

Files in this chunk:

```text
lib/main.dart
lib/tenancy/tenancy.dart
lib/tenancy/tenant_bootstrap.dart
lib/tenancy/tenant_routing_shell.dart
lib/tenancy/tenant_switch.dart
test/tenancy/tenant_routing_shell_test.dart
test/tenancy/tenant_switch_test.dart
PLAN.md
```

Validation evidence after implementation code was frozen:

- `flutter analyze --no-pub lib/tenancy test/tenancy` reported no issues.
- `flutter test --no-pub --concurrency=1 --reporter=compact test/tenancy`
  passed **254/254** tests. Before the final run, the focused coordinator and
  routing-shell command passed **34/34** tests.
- `npm --prefix functions test` passed **166/166** Functions tests using the
  portable Node.js 24 runtime and `NODE_OPTIONS=--max-old-space-size=512`.
- `npm --prefix rules-tests run test:emulator` passed the Firestore Rules
  emulator suite **21/21** with portable Node.js 24 and Temurin JDK 21.
- `npm --prefix rules-tests run test:emulator:invitations` passed **12/12**
  real Auth, Firestore, and Functions emulator integration tests.
- `git diff --check` was clean during focused validation. Android build and
  Android emulator validation were intentionally skipped as requested.

Meaningful failures and resolutions:

- The first stale-completion widget test used `pumpAndSettle` while deliberately
  holding tenant A's branding future open, so the harness timed out. It was
  changed to a bounded animation pump; the focused 34-test run and final
  254-test tenancy suite then passed.
- The first final Rules-emulator launch stopped before running a test because
  Firebase resolved the system JDK below version 21. `JAVA_HOME` already named
  the portable JDK, but its `bin` directory was not first on `PATH`. The
  corrected single retry explicitly prepended the Temurin JDK 21 `bin` path and
  passed 21/21. No Rules assertion failed.

The machine-local portable tools under `D:\firebase-emulator-tools` and the
captured logs under the system temporary directory are not repository
artifacts.

The existing user-owned local edits remain separate and must not be staged:

```text
.vscode/settings.json
android/gradle.properties
pubspec.lock
```

### Next bounded frontend chunk

Implement only the encrypted Hive checkout-outbox persistence foundation:

1. Add a versioned, encrypted local outbox keyed exactly by
   `{uid}:{tenantId}:{checkoutId}`, with strict tenant/UID validation,
   deterministic payload hashing, corruption detection, and a testable key
   provider boundary. Do not read or migrate legacy root POS Hive records.
2. Implement only the durable local transitions `saved_offline -> submitting
   -> awaiting_confirmation -> confirmed | needs_attention`, including
   persistent lease owner/expiry, attempt count, retry time, immutable payload,
   and hash agreement. Invalid transitions and malformed records must fail
   closed without deleting evidence.
3. Provide atomic single-checkout operations and restart-safe lease recovery.
   Lease expiry may make a record eligible for a later confirmation check but
   must never itself authorize blind resubmission.
4. Register a real checkout state source with `TenantSwitchCoordinator` so
   `saved_offline`, `submitting`, and `awaiting_confirmation` produce the
   appropriate unsynchronized/in-flight blockers. Keep the other safe-landing
   sources explicit and clean until their operational owners exist.
5. Add unit and Hive-backed restart coverage for tenant/UID isolation, every
   valid and invalid transition, duplicate workers, lease expiry, payload/hash
   mismatch, malformed storage, switch blockers, and Windows-compatible box
   reopen behavior.
6. Leave Firestore checkout submission/confirmation queries, stock mutation,
   product cache, receipt counters, shift restoration, cashier cross-tenant
   shift restriction, checkout UI, printers, deployment, and Android emulator
   validation outside that chunk.

---

## Encrypted Hive checkout-outbox foundation handoff - 2026-07-31

### Completed in this session

The safe routing shell now inspects a real encrypted checkout outbox. This
chunk adds local persistence and state transitions only; it does not submit a
sale to Firestore, mutate stock, expose checkout UI, or read/migrate any legacy
root POS Hive record.

Implemented behavior and safety decisions:

- The versioned `checkout-outbox-v1` Hive box is encrypted with a 32-byte AES
  key loaded through a testable provider boundary. Production stores that key
  in platform secure storage under a versioned name. A missing key is created
  from `Random.secure`; a malformed stored key fails closed and is never
  silently replaced.
- The dependency remains on `flutter_secure_storage` 9.2.4 so the repository's
  existing Android API 21 baseline is not raised by the version 10 API 23
  minimum. Generated Linux, macOS, and Windows plugin registration is included.
- Outbox keys are exactly `{uid}:{tenantId}:{checkoutId}`. UID, tenant, and
  checkout segments are validated and colons are rejected. Session scans use
  both UID and tenant prefixes, and the outbox never opens legacy Hive boxes.
- Payloads accept only finite JSON values, are deep-frozen, canonicalized by
  sorted map keys, and protected by deterministic SHA-256 hashes. Reusing a
  checkout key with a different payload is rejected. Stored hash or payload
  tampering is treated as corruption without deleting the raw evidence.
- Durable transitions are `saved_offline -> submitting ->
  awaiting_confirmation -> confirmed | needs_attention`. Submission leases
  persist owner and expiry, attempts are counted once, retry time is durable,
  and per-checkout mutations are serialized so duplicate local workers cannot
  both acquire the lease.
- An expired submission lease can move only to `awaiting_confirmation`; it
  never makes the checkout eligible for blind resubmission. Confirmation
  requires exact hash agreement. A mismatch becomes retained
  `needs_attention` evidence with the observed hash and bounded reason.
- Hive crash recovery is explicitly disabled for this evidence box. The first
  wrong-key test showed that Hive's default recovery can rebuild an encrypted
  box after a checksum failure, which could erase evidence. The final tests
  instead prove ciphertext contains no sale plaintext and reopens on Windows
  with the same key.
- The production `TenantSwitchCoordinator` checkout source is now backed by
  this outbox. `saved_offline`, `awaiting_confirmation`, and
  `needs_attention` block as unsynchronized; `submitting` blocks as in flight;
  only no records or all-confirmed records are clean. Malformed storage throws
  into the coordinator's existing fail-closed inspection path. The other
  safe-landing state owners remain explicit clean placeholders.

Files in this chunk:

```text
lib/checkout/checkout.dart
lib/checkout/checkout_outbox.dart
lib/checkout/secure_checkout_outbox_key.dart
lib/main.dart
lib/tenancy/tenant_switch.dart
linux/flutter/generated_plugin_registrant.cc
linux/flutter/generated_plugins.cmake
macos/Flutter/GeneratedPluginRegistrant.swift
pubspec.lock
pubspec.yaml
test/checkout/checkout_outbox_test.dart
test/checkout/secure_checkout_outbox_key_test.dart
windows/flutter/generated_plugin_registrant.cc
windows/flutter/generated_plugins.cmake
PLAN.md
```

Validation evidence after implementation code was frozen:

- `flutter analyze --no-pub lib/checkout lib/tenancy test/checkout
  test/tenancy` reported no issues.
- `flutter test --no-pub --concurrency=1 --reporter=compact test/checkout
  test/tenancy` passed **276/276** relevant Flutter tests. Before the final
  run, the focused checkout and tenant-switch command passed **39/39**.
- `npm --prefix functions test` passed **166/166** Functions tests using
  portable Node.js 24.18.1 and `NODE_OPTIONS=--max-old-space-size=512`.
- `npm --prefix rules-tests run test:emulator:invitations` passed **12/12**
  real Auth, Firestore, and Functions emulator integration tests using the
  same Node runtime, Temurin JDK 21, and a 60-second Functions discovery bound.
- The Firestore Rules emulator suite was not applicable because this chunk
  changed no Rules, Firestore operation, server authorization, or backend
  contract. Android build and Android emulator validation were intentionally
  skipped as requested.
- `git diff --check` was clean before final validation and final staging.

Meaningful failures and resolutions:

- `flutter pub get` resolved the two new direct dependencies and wrote the
  lock/plugin metadata, then exited because Windows Developer Mode is disabled
  and Flutter could not refresh plugin symlinks. The clean generated Linux
  symlink placeholders removed by that failed refresh were restored exactly;
  tests and analysis then ran with `--no-pub`. No repository artifact points
  at a machine-local package path.
- The first encrypted-reopen test expected a wrong key to be rejected, but
  Hive's default crash recovery instead printed `Recovering corrupted box` and
  opened a rebuilt box. Production opening now sets `crashRecovery: false`.
  Hive also caches failed opens and emits an additional uncaught error when a
  wrong-key probe is retried in one test process, so that brittle probe was
  replaced with stable ciphertext/no-plaintext and same-key Windows reopen
  coverage. The focused suite then passed 39/39.
- The first final integration launch stopped before loading tests because
  `JAVA_HOME` named the portable JDK's parent directory rather than its nested
  `jdk-21.0.12+8` root, leaving Java 17 authoritative. The exact JDK 21 `bin`
  path was prepended and the unchanged single retry passed 12/12.

The existing user-owned local edits remain separate and must not be staged:

```text
.vscode/settings.json
android/gradle.properties
pubspec.lock dependency-resolution updates for characters, matcher,
material_color_utilities, meta, test_api, and the Dart SDK constraint
```

The scoped `pubspec.lock` dependency entries for `crypto` and
`flutter_secure_storage` are part of this commit; the pre-existing version
updates listed above remain unstaged in the working tree.

### Next bounded frontend chunk

Implement only confirmation-safe checkout restart recovery; do not submit a
new Firestore sale in that chunk:

1. Add a typed confirmation gateway that waits for local Firestore pending
   writes to clear and reads the exact deterministic server sale while online.
   Return explicit matching, missing, mismatching, unavailable, and malformed
   results without trusting a tenant mirror.
2. Add a session/epoch-bound recovery coordinator for `submitting` leases that
   expired and `awaiting_confirmation` records. A matching server hash confirms
   the outbox; a mismatch records `needs_attention`; unavailable or pending
   state remains blocked and retains all evidence.
3. Add one narrowly authorized outbox transition for a confirmation-proven
   missing server sale to become retryable with a persisted backoff. Require
   proof that no local write is pending and no server sale exists; lease expiry
   alone must never authorize this transition or a submission.
4. Run recovery on startup/connectivity restoration for only the authenticated
   UID and selected tenant. Discard stale async results by session epoch and
   keep tenant switching blocked until the record is confirmed or safely made
   retryable.
5. Add unit, Hive-reopen, widget/session, and focused Firestore-emulator
   coverage for pending writes, matching/mismatching/missing server sales,
   unavailable connectivity, corrupt results, stale epochs, backoff, duplicate
   recovery workers, and evidence preservation.
6. Leave the initial Firestore batch submission, stock increments, checkout UI,
   product cache, receipt counters, shift restoration, cashier cross-tenant
   restriction, printers, deployment, and Android emulator validation outside
   that chunk.

---

## Confirmation-safe checkout restart recovery handoff - 2026-07-31

### Completed in this session

The encrypted checkout outbox now recovers uncertain prior submissions by
checking exact canonical Firestore sale evidence. This chunk remains
confirmation-only: it does not submit a new sale, decrement stock, expose
checkout UI, or make any legacy operational POS route reachable.

Implemented behavior and safety decisions:

- `FirebaseCheckoutConfirmationGateway` checks connectivity, waits for this
  Firestore client's pending writes with a bounded timeout, rechecks
  connectivity, and reads only
  `tenants/{tenantId}/sales/{checkoutId}` with `Source.server`. It never trusts
  a membership mirror or a cached sale document.
- Confirmation results are typed as matching, missing, mismatching, pending
  writes, unavailable, or malformed. A server sale must repeat the exact
  tenant ID and checkout ID and contain a lowercase 64-character SHA-256 hash;
  malformed identity or hash data fails closed and remains local evidence.
- A missing result carries evidence bound to the immutable UID, tenant,
  checkout ID, payload hash, and confirmation time. The outbox accepts that
  evidence only from `awaiting_confirmation`, rejects stale/future or hash-
  mismatched proof, preserves the prior attempt count, and persists a bounded
  retry backoff before returning to `saved_offline`.
- Lease expiry alone still moves `submitting` only to
  `awaiting_confirmation`. It never authorizes a submission or makes a record
  retryable. Pending writes, unavailable connectivity, malformed server data,
  active leases, and malformed local storage retain all evidence.
- `CheckoutRecoveryCoordinator` scans only the authenticated UID and selected
  tenant. It is bound to the captured session epoch and discards a server
  result if Auth, tenant, or epoch changes before mutation. Concurrent triggers
  never run duplicate workers; one follow-up run is queued so a connectivity
  restoration or tenant change is not lost behind an older check.
- Recovery runs after an authorized tenant session opens and whenever
  connectivity reports restoration. The routing shell's generic recovery hook
  does nothing without a selected session. Existing outbox-backed tenant-
  switch blockers remain in force for `saved_offline`, `submitting`,
  `awaiting_confirmation`, and `needs_attention`.
- Focused Firestore-emulator coverage proves the active canonical member can
  read the exact deterministic sale or observe it missing, while cross-tenant
  and globally disabled access remains denied. No Firestore Rules changed.

Files in this chunk:

```text
lib/checkout/checkout.dart
lib/checkout/checkout_confirmation.dart
lib/checkout/checkout_outbox.dart
lib/checkout/checkout_recovery.dart
lib/main.dart
lib/tenancy/tenant_routing_shell.dart
rules-tests/README.md
rules-tests/package.json
rules-tests/test/checkout-confirmation.test.js
test/checkout/checkout_confirmation_test.dart
test/checkout/checkout_recovery_test.dart
test/tenancy/tenant_routing_shell_test.dart
PLAN.md
```

Validation evidence after implementation code and harness changes were frozen:

- `flutter analyze --no-pub lib/checkout lib/tenancy test/checkout
  test/tenancy` reported no issues.
- `flutter test --no-pub --concurrency=1 --reporter=compact test/checkout
  test/tenancy` passed **294/294** relevant Flutter tests. Before the final
  run, focused checkout and routing-shell runs passed **55/55**, then **57/57**
  after the queued-recovery and corruption-retention hardening.
- With portable Node.js 24.18.1, JDK 21 at
  `D:\firebase-emulator-tools\jdk21\jdk-21.0.12+8`, inherited `DEBUG` removed,
  and `NODE_OPTIONS=--max-old-space-size=512`, `npm --prefix functions test`
  passed **166/166** Functions tests.
- With the same pinned Node/JDK environment,
  `npm --prefix rules-tests run test:emulator:checkout-confirmation` passed the
  focused Firestore-only suite **3/3** during development.
- `npm --prefix rules-tests run test:emulator` passed the final full Firestore
  Rules suite **24/24**.
- With `FUNCTIONS_DISCOVERY_TIMEOUT=60`,
  `npm --prefix rules-tests run test:emulator:invitations` passed **12/12** real
  Auth, Firestore, and Functions emulator integration tests.
- `git diff --check` was clean before the final release-style sequence.
  Android build and Android emulator validation were intentionally skipped as
  requested.

Meaningful failures and resolutions:

- The first broad incremental analyzer included `lib/main.dart` and exited on
  the existing experimental Sentry `profilesSampleRate` warning. No new type or
  implementation error was reported. The correctly scoped checkout/tenancy
  analyzer was clean before focused and final testing.
- One development analyzer warned that the test recovery callback's nullable
  `Future<Object?>` could complete without an explicit value. The callback now
  returns `null`; the next scoped analyzer reported no issues and the focused
  suite passed 57/57.
- A combined development formatting command accidentally included the Markdown
  README, so `dart format` printed Markdown parse diagnostics even though the
  subsequent analyzer and 57-test run completed. The command target was
  corrected to Dart sources only. No repository file was changed by that
  formatter error, and the final validation sequence had no failures or
  retries.

The existing user-owned local edits remain separate and must not be staged:

```text
.vscode/settings.json
android/gradle.properties
pubspec.lock dependency-resolution updates for characters, matcher,
material_color_utilities, meta, test_api, and the Dart SDK constraint
```

### Next bounded frontend chunk

Implement only the initial deterministic Firestore checkout submission worker,
using the existing encrypted outbox and confirmation recovery:

1. Add a strict typed sale payload/envelope parser for the frozen outbox
   payload. Validate immutable checkout identity, authenticated UID, selected
   tenant, positive integer line quantities, unique tenant-local product IDs,
   monetary snapshot fields, and bounded line counts before any write.
2. Add a typed Firestore submission gateway that performs one atomic batch:
   create `tenants/{tenantId}/sales/{checkoutId}` with the exact payload hash
   and server timestamp, and decrement each exact tenant product with
   `FieldValue.increment(-quantity)` plus server `updatedAt`. Do not write any
   legacy root collection.
3. Add a session/epoch-bound sync worker that acquires the durable outbox lease
   before the single `batch.commit()` call. A successful commit moves only to
   `awaiting_confirmation`; an ambiguous failure remains `submitting` for the
   existing expiry-and-confirmation recovery path. Never resubmit an expired
   lease directly.
4. Run submission only while online for due `saved_offline` records belonging
   to the authenticated UID and selected tenant. Serialize/coalesce duplicate
   triggers and preserve evidence on malformed payloads, stale epochs,
   unavailable writes, or lease loss.
5. Add unit, encrypted Hive-reopen, session/widget, and focused Firestore Rules
   emulator coverage for exact batch paths, stock decrements including negative
   stock, deterministic sale identity/hash, duplicate workers, ambiguous
   commit outcomes, stale sessions, and transition safety.
6. Leave checkout UI and draft creation, product cache, receipt counters,
   shift restoration, cashier cross-tenant shift restriction, returns,
   printers, deployment, and Android build/emulator validation outside that
   chunk.

---

## Deterministic checkout submission worker handoff - 2026-07-31

### Completed in this session

The encrypted outbox now submits due offline checkouts as one atomic Firestore
batch. This chunk adds only the submission path: it creates no checkout UI or
draft, caches no products, issues no receipt number, restores no shift, and
makes no legacy operational POS route reachable.

Implemented behavior and safety decisions:

- `CheckoutSalePayload` freezes the local sale contract at schema version 1 and
  parses it strictly before any write. It requires the payload to repeat the
  immutable outbox checkout ID, tenant ID, and authenticated UID, and it
  additionally requires the live session to own that UID and tenant. Unknown
  top-level and line fields are rejected rather than forwarded to Firestore.
- Lines are bounded to 1-16 because Firestore Rules can validate only sixteen
  explicit positions. Each line requires a valid tenant-local product document
  ID, a unique product across the sale, a positive integer quantity within
  1,000,000, and a non-negative integer unit price. Duplicate products are
  rejected so one batch never writes the same product twice.
- Monetary values are integer minor currency units, so the payload hash stays
  deterministic and no float rounding enters the evidence. The parser derives
  each line total, requires `subtotalMinor` to equal their sum, bounds
  `discountMinor` by the subtotal, and requires `totalMinor` to equal subtotal
  minus discount. Major-unit `total`, `subtotal`, `lineTotal`, `unitPrice`, and
  `cost` numbers are derived only for the written document, because the frozen
  backend reporting and reconciliation aggregate those field names. The
  conversion is exact under the server's `moneyToMinorUnits` rounding.
- `FirebaseCheckoutSubmissionGateway` performs one `batch.commit()`: it creates
  `tenants/{tenantId}/sales/{checkoutId}` with the exact payload hash and a
  server `createdAt`, and decrements each exact tenant product with
  `FieldValue.increment(-quantity)` plus a server `updatedAt`. It writes no
  legacy root collection. Before committing it re-derives every path from
  `TenantPaths` and refuses a write set that escaped the tenant, repeated a
  product, or carried a non-negative stock delta.
- Outcomes are typed as committed, rejected, ambiguous, or unavailable. A
  refusal is never treated as proof that the server holds no sale, because an
  offline SDK can still flush a queued batch later; only the existing
  confirmation gateway may decide a sale is absent. An unacknowledged commit
  times out into `ambiguous` rather than being retried.
- `CheckoutSubmissionWorker` runs only while online, only for the authenticated
  UID and selected tenant, and only for due `saved_offline` records. It
  acquires the durable outbox lease before the single commit, so a second local
  worker cannot submit the same checkout. Only an acknowledged commit moves the
  record to `awaiting_confirmation`; rejected, ambiguous, unavailable, and
  lost-lease outcomes deliberately leave it `submitting` for the existing
  expiry-and-confirmation recovery path. The worker never resubmits an expired
  lease and never invents a retry.
- A malformed payload is counted and skipped without taking a lease, changing
  state, or deleting evidence. Session, tenant, or epoch changes during a
  commit discard the result before any local mutation. Duplicate triggers are
  coalesced into one queued rerun, and losing connectivity mid-run stops the
  worker before it leases further checkouts.
- `main.dart` composes recovery before submission on the existing session and
  connectivity hook, so an uncertain prior attempt is always settled before a
  new batch is committed. The safe landing route and its outbox-backed tenant
  switch blockers are unchanged.

Files in this chunk:

```text
docs/frontend_tenant_migration_inventory.md
lib/checkout/checkout.dart
lib/checkout/checkout_sale.dart
lib/checkout/checkout_submission.dart
lib/checkout/checkout_sync.dart
lib/main.dart
rules-tests/README.md
rules-tests/package.json
rules-tests/test/checkout-submission.test.js
test/checkout/checkout_sale_test.dart
test/checkout/checkout_submission_test.dart
test/checkout/checkout_sync_test.dart
PLAN.md
```

Validation evidence after implementation code was frozen:

- `flutter analyze --no-pub lib/checkout lib/tenancy test/checkout test/tenancy`
  reported no issues.
- `flutter test --no-pub --concurrency=1 --reporter=compact test/checkout
  test/tenancy` passed **317/317** relevant Flutter tests, including **23** new
  tests: 7 payload-contract, 5 submission-gateway, and 11 sync-worker cases.
  The focused `test/checkout` command passed **62/62** during development.
- With portable Node.js 24.18.1, Temurin JDK 21 at
  `D:\firebase-emulator-tools\jdk21\jdk-21.0.12+8`, inherited `DEBUG` removed,
  and `NODE_OPTIONS=--max-old-space-size=512`, `npm --prefix functions test`
  passed **166/166** Functions tests.
- `npm --prefix rules-tests run test:emulator:checkout-submission` passed the
  focused Firestore-only suite **6/6** during development.
- `npm --prefix rules-tests run test:emulator` passed the full Firestore Rules
  suite **30/30** (24 existing plus the 6 new submission cases). No Rules file
  changed; the new tests prove the existing contract against the real batch.
- With `FUNCTIONS_DISCOVERY_TIMEOUT=60`,
  `npm --prefix rules-tests run test:emulator:invitations` passed **12/12** real
  Auth, Firestore, and Functions emulator integration tests.
- `git diff --check` was clean before the final release-style sequence. Android
  build and Android emulator validation were intentionally skipped as
  requested.

The new emulator coverage commits the exact write set the worker produces and
proves deterministic sale identity, a server-owned `createdAt`, exact stock
decrements into negative stock, replay denial, cross-tenant denial with an
atomically absent sale, non-decrementing stock denial, envelope spoofing
denial, and inactive-cashier denial.

Meaningful failures and resolutions:

- The final integration launch refused to start with `Refusing to overwrite
  existing Functions emulator configuration: functions/integration/.secret.local`.
  The file was the runner's own deterministic local-only placeholder left over
  from an earlier interrupted run; it is git-ignored and holds no real secret.
  Removing it and retrying once passed 12/12, and the runner removed the file
  again on exit.
- No test assertion failed in this session. Analyzer, focused, and final runs
  were green on their first execution.

The existing user-owned local edits remain separate and must not be staged:

```text
.vscode/settings.json
android/gradle.properties
pubspec.lock dependency-resolution updates for characters, matcher,
material_color_utilities, meta, test_api, and the Dart SDK constraint
```

### Next bounded frontend chunk

Implement only the tenant-scoped offline product cache and deterministic
checkout draft creation; do not build the checkout screen in that chunk:

1. Add an encrypted, tenant- and UID-scoped Hive product/price/category cache
   refreshed from the guarded catalog repository. Validate every cached
   document against the existing strict read models, reject cross-tenant or
   stale-epoch results, and treat malformed cache entries as a miss rather than
   as authority.
2. Add a deterministic checkout draft builder that produces exactly the frozen
   `CheckoutSalePayload` v1 contract from cached products: immutable checkout
   ID, authenticated UID, selected tenant, bounded unique lines, integer minor
   monetary snapshot, and business date. It must save through
   `HiveCheckoutOutbox.saveOffline` and never write Firestore directly.
3. Bind draft creation to one session epoch and one local lock so two
   concurrent drafts cannot reuse a checkout ID, and prove a reused ID with a
   different payload is still rejected as `checkout_already_exists`.
4. Surface a read-only pending-checkout evidence panel on the safe landing
   route showing outbox state counts only, with no submit, edit, cancel, or
   delete action.
5. Add unit, Hive-reopen, and session/widget coverage for cache isolation,
   stale-epoch refresh, malformed cache entries, draft-to-payload agreement
   with the parser, duplicate draft prevention, and switch-blocker interaction.
6. Leave receipt counters, the checkout screen and payment flow, shift
   restoration, cashier cross-tenant shift restriction, returns, printers,
   reports, deployment, and Android build/emulator validation outside that
   chunk.

---

## Offline catalog cache and checkout draft handoff - 2026-07-31

### Completed in this session

The encrypted checkout layer can now build a deterministic offline sale from a
locally cached catalog. This chunk adds only the cache, the draft builder, and
a read-only evidence panel: it creates no checkout screen or payment flow,
issues no receipt number, restores no shift, and makes no legacy operational
POS route reachable.

Implemented behavior and safety decisions:

- `HiveCheckoutCatalogCache` stores one snapshot per `{uid}:{tenantId}` key in
  the versioned, AES-encrypted `checkout-catalog-cache-v1` box. It never opens
  a legacy Hive box and never shares the outbox key: the derived cache and the
  sale evidence use two distinct secure-storage key names, so rotating or
  losing the cache key can never make checkout evidence unreadable. Hive crash
  recovery stays disabled for the same reason as the outbox.
- The cache is derived data and is never an authorization source. Only a
  canonical projection of the fields the strict read models require is written,
  so no Firestore sentinel, timestamp, or unrelated document field is
  persisted locally. Every read re-parses each entry through
  `TenantCategory.fromSnapshot`/`TenantProduct.fromSnapshot` and re-derives the
  exact `TenantPaths` document path.
- A record naming another UID or tenant, carrying another tenant's document
  path, failing the strict models, repeating a document, or using an unknown
  schema version is reported as a **miss**, not as authority. A malformed
  snapshot is refused whole rather than partially trusted, so a draft fails
  closed instead of silently omitting a product.
- `CheckoutCatalogCacheRefresher` reads only through the guarded
  `TenantCatalogRepository`, so the existing tenant-path derivation, 1-50 page
  bound, document-ID ordering, duplicate rejection, and cross-tenant refusal
  all still apply. It captures the session, re-checks UID, tenant, and epoch
  after every page and before the local write, bounds the refresh to 500
  categories and 2000 products, records whether the refresh was complete, and
  coalesces concurrent triggers into one queued rerun. A scope violation or
  transport failure leaves the previous cache untouched.
- `CheckoutDraftService` produces exactly the frozen `CheckoutSalePayload` v1
  contract: immutable checkout ID, authenticated UID, selected tenant, bounded
  unique lines, an integer minor-unit monetary snapshot, and a business date.
  It writes only through `HiveCheckoutOutbox.saveOffline` and touches no
  Firestore path.
- The draft is validated against the frozen parser through the new
  `CheckoutSalePayload.fromLocalPayload` factory **before** it is persisted, so
  a contract violation is refused while nothing durable exists. That factory is
  now the single parser; `fromOutboxRecord` delegates to it after checking the
  record's UID and tenant, and it additionally proves the supplied hash
  describes the exact payload.
- Cached major-unit prices are converted to integer minor units only when they
  are exactly representable. A price such as `120.555` is rejected as
  `price_not_representable` rather than silently rounded, so a recorded sale
  can never disagree with the catalog it was priced from.
- The business date uses a fixed Africa/Nairobi (UTC+3, no daylight saving)
  offset, so it stays deterministic without a timezone database.
- Draft creation captures the live session **when the draft is requested** and
  is serialized by one local lock. A draft queued behind another draft is
  discarded with `session_changed` if the UID, tenant, or epoch advanced, and
  two overlapping drafts can never receive the same checkout ID. A reused
  checkout ID replays idempotently for an identical payload and is rejected as
  `checkout_already_exists` when the payload differs.
- The safe landing route now renders a read-only pending-checkout evidence
  panel behind `TenantRouteGuard`, showing outbox state counts only. It exposes
  no submit, retry, edit, cancel, or delete action, renders nothing without an
  authorized session, and reports unavailable evidence without leaking internal
  error codes. The panel is injected by the composition root as a plain
  `Widget`, so tenancy code gains no dependency on the checkout domain.
- `main.dart` opens the cache with its own key and appends the catalog refresh
  after recovery and submission on the existing session/connectivity hook, so
  derived data never delays settling uncertain sale evidence.

Deliberately left outside this chunk: `TenantProduct` still exposes no cost
field, so drafts write no `unitCostMinor`. Restoring cost to the sale document
belongs with the reports migration that consumes it.

Files in this chunk:

```text
docs/frontend_tenant_migration_inventory.md
lib/checkout/checkout.dart
lib/checkout/checkout_catalog_cache.dart
lib/checkout/checkout_draft.dart
lib/checkout/checkout_evidence.dart
lib/checkout/checkout_outbox.dart
lib/checkout/checkout_sale.dart
lib/checkout/secure_checkout_outbox_key.dart
lib/main.dart
lib/tenancy/tenant_routing_shell.dart
test/checkout/checkout_catalog_cache_test.dart
test/checkout/checkout_draft_test.dart
test/checkout/checkout_evidence_test.dart
test/tenancy/tenant_routing_shell_test.dart
PLAN.md
```

Validation evidence after implementation code was frozen:

- `flutter analyze --no-pub lib/checkout lib/tenancy test/checkout test/tenancy`
  reported no issues.
- `flutter test --no-pub --concurrency=1 --reporter=compact test/checkout
  test/tenancy` passed **344/344** relevant Flutter tests, including **27** new
  tests: 10 catalog-cache, 11 draft, 5 evidence-panel, and 1 routing-shell
  case. Focused runs passed 10/10, 16/16, and 19/19 during development.
- With portable Node.js 24.18.1, Temurin JDK 21 at
  `D:\firebase-emulator-tools\jdk21\jdk-21.0.12+8`, inherited `DEBUG` removed,
  and `NODE_OPTIONS=--max-old-space-size=512`, `npm --prefix functions test`
  passed **166/166** Functions tests.
- `npm --prefix rules-tests run test:emulator` passed the full Firestore Rules
  suite **30/30**. No Rules file, Firestore operation, server authorization, or
  backend contract changed in this chunk; the suite was rerun because the new
  cache reads the `products` and `categories` collections through the guarded
  repository.
- With `FUNCTIONS_DISCOVERY_TIMEOUT=60`,
  `npm --prefix rules-tests run test:emulator:invitations` passed **12/12** real
  Auth, Firestore, and Functions emulator integration tests.
- `git diff --check` was clean before final validation and final staging.
  Android build and Android emulator validation were intentionally skipped as
  requested.

Meaningful failures and resolutions:

- The first focused Flutter run produced no output for roughly fifteen minutes
  at zero CPU. Inspecting the processes showed **two** identical
  `flutter_tools.snapshot test` invocations contending for the same build
  state, not a code or test defect. Both were stopped and one clean rerun from
  PowerShell passed 10/10 in under a second of test time. Prefer PowerShell for
  `flutter test` on this host and confirm no earlier run is still alive before
  relaunching.
- An early edit added an instance `storageKey` getter beside the existing
  static constant of the same name, which Dart forbids. The constructor now
  takes an optional `storageKey` parameter that defaults to the unchanged
  static value, so the existing key-provider tests were not disturbed.
- No test assertion failed in this session; every analyzer and test command in
  the final sequence was green on its first execution.

The existing user-owned local edits remain separate and must not be staged:

```text
.vscode/settings.json
android/gradle.properties
pubspec.lock dependency-resolution updates for characters, matcher,
material_color_utilities, meta, test_api, and the Dart SDK constraint
```

### Next bounded frontend chunk

Implement only per-device receipt numbering and the tenant checkout
configuration the draft builder still hard-codes:

1. Add an atomic Hive device receipt counter keyed exactly by
   `{tenantId}:{deviceId}:{businessDate}:receiptCounter`, deliberately not
   scoped by cashier UID, guarded by the draft service's existing local lock so
   two concurrent checkouts on one device cannot receive the same value.
2. Emit the frozen `CT-A7F-20260729-0042` receipt shape, record the cashier UID
   separately, and keep `checkoutId` as the database identity. Persist the
   receipt inside the immutable draft payload and extend the frozen
   `CheckoutSalePayload` v1 allow-list and Firestore Rules validation for it in
   the same chunk, or explicitly version the payload schema.
3. Resolve the device ID once per installation from durable local state and
   read `currency` (and any other required checkout configuration) from a
   guarded `tenants/{tenantId}/configuration` read instead of the current
   constructor value; fail closed when configuration is missing or malformed.
4. Add unit, Hive-reopen, and focused Rules-emulator coverage for two cashiers
   on one device receiving different receipt numbers, counter independence
   across devices, tenants, and business dates, restart continuity, business-day
   rollover at the Africa/Nairobi boundary, and rejection of a spoofed or
   duplicated receipt.
5. Leave the checkout screen and payment flow, shift restoration, cashier
   cross-tenant shift restriction, product cost/profit fields, returns,
   printers, reports, deployment, and Android build/emulator validation outside
   that chunk.

---

## Per-device receipt numbering and checkout configuration handoff - 2026-07-31

### Completed in this session

Offline drafts now carry a real per-device receipt number and are priced from
the tenant's own guarded checkout configuration instead of a hard-coded
constructor value. This chunk adds no checkout screen or payment flow, restores
no shift, and makes no legacy operational POS route reachable.

Implemented behavior and safety decisions:

- `HiveCheckoutReceiptCounters` allocates sequences atomically under the frozen
  key `{tenantId}:{deviceId}:{businessDate}:receiptCounter`. The key is
  deliberately not scoped by cashier UID, so two cashiers sharing one device
  draw from one sequence and can never collide. Allocation is serialized per
  key inside the box and additionally runs under the draft service's existing
  local lock.
- The counter box shares the checkout **outbox** encryption key rather than
  taking a third key. A counter and the sale evidence it numbers must share one
  fate: a rotated or lost key can never leave readable local sales beside a
  restarted counter. The derived catalog cache keeps its own separate key.
- Malformed durable receipt state always fails closed. A counter whose stored
  record does not parse, names another tenant/device/date, or holds a
  non-positive sequence raises `malformed_receipt_counter` instead of
  restarting at 1, because a restart would reissue a receipt a committed sale
  already carries. An exhausted daily sequence raises
  `receipt_sequence_exhausted` rather than wrapping.
- The receipt is `CT-A7F-20260729-0042`: the frozen `CT` prefix, a stable
  three-character uppercase-hex device code, the compact business date, and the
  sequence zero-padded to at least four digits. The device code is the first
  three hex characters of the SHA-256 digest of the installation identifier, so
  it is deterministic and never exposes the identifier. A busier device widens
  the sequence field instead of wrapping.
- The device identity is resolved once per installation from durable local
  state, memoized per process, and is not a caller input; `CheckoutDraftRequest`
  no longer accepts a `deviceId`. A corrupt stored identity is refused rather
  than regenerated. `checkoutId` remains the database identity and the sale
  still records the cashier UID separately in `soldById`.
- The frozen `CheckoutSalePayload` v1 allow-list gained `receiptNumber` and
  `receiptSequence`, and `deviceId` became required. The parser proves the
  receipt is exactly the value derived from this payload's device, business
  date, and sequence, so a locally altered receipt is refused before any write.
  No deployed data exists, and a hypothetical pre-existing local draft without a
  receipt is now refused as malformed and retained as evidence rather than
  submitted - the deliberate fail-closed outcome.
- `TenantCheckoutConfiguration` reads `tenants/{tenantId}/configuration/checkout`
  through the guarded `TenantReadRepository`, so the exact tenant path
  derivation and cross-tenant refusal still apply. It is cached with the offline
  catalog because Firestore offline persistence is unavailable on Windows. The
  catalog cache schema is now version 2; a version 1 record is reported as a
  miss rather than migrated, so a draft can never be priced with a currency the
  tenant never published. A missing or malformed configuration returns
  `configurationUnavailable` and leaves any previous cache untouched.
- The receipt sequence is allocated after every refusable check, so a rejected
  draft leaves an unused gap rather than a reused number. Gaps are safe;
  duplicates are not.
- Firestore Rules now validate the receipt on sale creation: `deviceId` and
  `businessDate` must be strings, `receiptSequence` a positive integer, and
  `receiptNumber` a string of at least the frozen 20-character width that
  matches a pattern constructed from that same sale's business date and
  sequence. A receipt that disagrees with its own envelope, is free text, uses
  another prefix, or lowercases the device code is denied.

Deliberately outside this chunk: Rules cannot recompute the SHA-256 device code
and cannot query other sales, so cross-sale receipt uniqueness is not a
server-enforced invariant. Uniqueness comes from the device-local atomic
counter; detecting a duplicate produced by local tampering or a restored backup
belongs to reconciliation. `CheckoutDraftService` and the receipt counters are
still not composed in `main.dart`, because no screen creates a draft yet.

Files in this chunk:

```text
docs/frontend_tenant_migration_inventory.md
firestore.rules
lib/checkout/checkout.dart
lib/checkout/checkout_catalog_cache.dart
lib/checkout/checkout_configuration.dart
lib/checkout/checkout_draft.dart
lib/checkout/checkout_receipt.dart
lib/checkout/checkout_sale.dart
rules-tests/README.md
rules-tests/package.json
rules-tests/test/checkout-receipt.test.js
rules-tests/test/checkout-submission.test.js
rules-tests/test/stock-and-sales.test.js
rules-tests/test/support.js
test/checkout/checkout_catalog_cache_test.dart
test/checkout/checkout_draft_test.dart
test/checkout/checkout_receipt_test.dart
test/checkout/checkout_sale_test.dart
test/checkout/checkout_submission_test.dart
test/checkout/checkout_sync_test.dart
PLAN.md
```

Validation evidence after implementation code was frozen:

- `flutter analyze --no-pub lib/checkout lib/tenancy test/checkout test/tenancy`
  reported no issues.
- `flutter test --no-pub --concurrency=1 --reporter=compact test/checkout
  test/tenancy` passed **367/367** relevant Flutter tests, including **23** new
  tests: 14 receipt-numbering, 5 draft, 2 payload-contract, and 2 catalog-cache
  cases. The focused `test/checkout` command passed **111/111** during
  development.
- With portable Node.js 24.18.1, Temurin JDK 21 at
  `D:\firebase-emulator-tools\jdk21\jdk-21.0.12+8`, inherited `DEBUG` removed,
  and `NODE_OPTIONS=--max-old-space-size=512`, `npm --prefix functions test`
  passed **166/166** Functions tests.
- `npm --prefix rules-tests run test:emulator:checkout-receipt` passed the
  focused Firestore-only suite **7/7** during development.
- `npm --prefix rules-tests run test:emulator` passed the full Firestore Rules
  suite **37/37** (30 existing plus the 7 new receipt cases, with two existing
  sale cases updated for the now-required fields).
- With `FUNCTIONS_DISCOVERY_TIMEOUT=60`,
  `npm --prefix rules-tests run test:emulator:invitations` passed **12/12** real
  Auth, Firestore, and Functions emulator integration tests.
- `git diff --check` was clean before final staging. Android build and Android
  emulator validation were intentionally skipped as requested.

Meaningful failures and resolutions:

- **The first Rules receipt validation denied a legitimate maximum-size sale.**
  The focused emulator run reported `Unable to evaluate the expression as the
  maximum of 1000 expressions to evaluate has been reached` in the denial
  traces. A new test that commits the largest allowed sale - 16 lines plus 16
  stock decrements in one batch - failed, and removing only `validSaleReceipt`
  made it pass, proving the new rule caused it rather than exposing an existing
  defect. The rule was rewritten to prove the shape, the embedded date, and the
  embedded sequence with one constructed pattern plus a minimum-width check
  instead of separate `split`/`int` comparisons. The maximum-size test now
  passes and stays in the suite as a permanent budget guard.
- **An unpadded receipt was briefly accepted.** The constructed pattern alone
  allowed `CT-A7F-20260729-1` because `0{0,3}` permits zero padding. Requiring
  `receiptNumber.size() >= 20` restored the frozen four-digit minimum width,
  since the fixed prefix, device code, and date always occupy 16 characters.
- **Reusing a checkout ID is no longer an idempotent replay.** Every draft draws
  its own receipt sequence, so a second draft for an existing checkout ID can
  never describe the same immutable payload; the outbox now always answers
  `checkout_already_exists` and the stored evidence is unchanged. This is
  stronger than the previous behavior and the draft test asserts it. Idempotent
  replay of a byte-identical payload remains covered at the
  `HiveCheckoutOutbox.saveOffline` level.
- No other test assertion failed; the analyzer and every command in the final
  sequence were green on their first execution.

The existing user-owned local edits remain separate and must not be staged:

```text
.vscode/settings.json
android/gradle.properties
pubspec.lock dependency-resolution updates for characters, matcher,
material_color_utilities, meta, test_api, and the Dart SDK constraint
```

### Next bounded frontend chunk

Implement only the guarded tenant shift lifecycle and the real tenant-switch
state sources it owns:

1. Add a strict shift read model and a guarded repository over
   `tenants/{tenantId}/shifts/{shiftId}` that derives every path from
   `TenantPaths`, rejects a cross-tenant or non-exact returned path, and refuses
   a shift whose `staffId` is not the authenticated cashier.
2. Add a session/epoch-bound shift controller that opens, restores, and closes
   exactly one shift for the selected tenant. Restoration must re-read the
   canonical server shift rather than trusting local state, and a server-
   confirmed open shift alone must still not block tenant switching.
3. Replace the safe landing route's asserted-clean cash-close and shift sources
   in `safeLandingTenantSwitchStateSources` with the real state owner, so
   unfinished cash counting or shift closing blocks switching for the documented
   reason while a merely open shift does not.
4. Enforce the frozen cashier restriction: a cashier may not open checkout in a
   second tenant on the same device while another tenant's shift remains open.
   Owners and managers may still inspect another tenant.
5. Compose the receipt counters and `CheckoutDraftService` in `main.dart` only
   as far as the shift surface requires, and record the resolved device identity
   once at startup.
6. Add unit, Hive-reopen, session/widget, and focused Firestore Rules emulator
   coverage for open/close authorization, foreign-cashier shift refusal, stale
   epochs, restoration after a restart, the open-shift non-blocking rule, the
   cash-close blocker, and the cashier cross-tenant restriction.
7. Leave the checkout screen and payment flow, receipts printing, product
   cost/profit fields, returns, reports, subscription and branding surfaces,
   deployment, and Android build/emulator validation outside that chunk.

---

## Guarded tenant shift lifecycle handoff - 2026-07-31

### Completed in this session

The safe landing route now owns a real, canonically authorized shift lifecycle,
and the tenant-switch coordinator's cash-close area is backed by that owner
instead of an asserted-clean placeholder. This chunk adds no checkout screen or
payment flow, no receipt printing, no reports, and makes no legacy operational
POS route reachable.

Implemented behavior and safety decisions:

- `TenantShift` is a strict read model for `tenants/{tenantId}/shifts/{shiftId}`.
  It requires the document to repeat the tenant and shift identity encoded in
  its own path, validates `staffId`, `deviceId`, `businessDate`, and `status`
  exactly, and reuses the checkout device-ID and Africa/Nairobi business-date
  validators so a shift and the sales recorded during it can never disagree
  about the business day. `startTime`/`endTime` are server-owned, so they are
  accepted as absent only while a write is still pending; any other shape is
  refused.
- `TenantShiftRepository` extends the existing guarded `TenantReadRepository`.
  Every path is derived from the session's `TenantPaths`, a returned path that
  is not the exact requested document still fails closed through
  `TenantScopeViolation`, and a shift whose `staffId` is not the authenticated
  cashier is refused as `foreign_shift`. A device therefore cannot restore or
  close a colleague's shift even if local state names it.
- Writes go through validated intents that only the repository can build, so no
  caller can name an arbitrary Firestore path. `FirebaseTenantShiftWriter`
  re-derives and re-checks the path before writing, adds `startTime`/`endTime`
  as server timestamps itself, and uses `set` for the open so a reused shift ID
  becomes a Rules-denied update rather than a silent overwrite. Outcomes are
  typed committed, rejected, ambiguous, or unavailable, matching the checkout
  submission contract.
- `TenantShiftController` owns exactly one shift per selected session. Every
  operation captures the live session, is serialized by one local lock, and
  re-checks UID, tenant, and epoch before publishing, so a tenant switch during
  an in-flight write can never update the new session's surface.
- Restoration always re-reads the canonical server shift. Durable local state
  only names the candidate shift; the server decides. A shift that is absent or
  already closed clears the local record, an open one confirms it, and a read
  that cannot complete leaves the record untouched and reports `unavailable`.
- Every write outcome is settled by the same canonical read. Only a successful
  read may conclude that nothing was written: an unacknowledged create whose
  settlement read also fails keeps its durable intent for the next attempt
  rather than being forgotten. The controller refuses to write while offline,
  so the common failure never leaves a phantom shift claim behind.
- `HiveTenantShiftState` stores one encrypted record per `{uid}:{tenantId}` in
  the versioned `tenant-shift-state-v1` box. It shares the checkout **outbox**
  key rather than taking a new one, because a shift and the sale evidence it
  contains must share exactly one fate; the derived catalog cache keeps its own
  separate key. Malformed durable state raises instead of restarting: unlike
  the derived cache, a shift record is evidence, and silently discarding it
  could reopen a closed shift or hide an unfinished cash count.
- `TenantShiftSwitchStateSource` replaces the asserted-clean cash-close source
  in `safeLandingTenantSwitchStateSources`. A server-confirmed open shift alone
  reports clean while carrying `hasServerConfirmedOpenShift`, exactly as the
  frozen baseline requires; only an unfinished cash count or an unsettled close
  blocks switching, and it keeps blocking across a restart because the flag is
  durable. Unreadable local state raises so the coordinator fails closed with
  `stateInspectionUnavailable`.
- An unsettled close deliberately stays `closing`. The counted cash and the
  blocked switch both survive until a canonical read proves the server accepted
  the close, so an ambiguous network outcome never silently releases the guard.
- The frozen cashier restriction is enforced at both ends. `openShift` refuses
  a cashier whose identity still holds an open or unsettled shift in another
  business on this device, and `TenantShiftCheckoutGate` refuses the checkout
  itself through the new `CheckoutStartGuard` hook on `CheckoutDraftService`.
  The refusal happens before a receipt sequence is allocated, so a blocked
  checkout consumes nothing. Owners, admins, and managers may still inspect and
  transact elsewhere. The restriction is scoped by cashier UID: a different
  identity's shift on the same device does not block this cashier.
- A guard that cannot answer refuses the checkout (`checkout_start_unavailable`)
  rather than allowing it, so unreadable local state can never widen where a
  cashier may sell.
- Firestore Rules now bind the shift document to its own identity: create
  requires the document ID to equal `shiftId`, the `tenantId` to match the path,
  `staffId` to be the caller, `status` to be `open`, a non-empty `deviceId`, a
  `yyyy-MM-dd` `businessDate`, `startTime == request.time`, and no `endTime`.
  Close requires the same cashier, preserves `shiftId`, `tenantId`, `staffId`,
  `deviceId`, `businessDate`, and `startTime`, allows only `open` to `closed`,
  requires `endTime == request.time` and a non-negative integer
  `closingCashMinor`, and restricts the changed keys to exactly the four close
  fields. Delete stays denied, so a closed shift is terminal.
- `main.dart` opens the receipt counters and shift-state boxes with the outbox
  key and resolves the installation device identity once at startup, so every
  shift and receipt this device records names the same device.

Deliberately outside this chunk, and important for the next session:

- The client writes no `totalSales` or `transactionCount` on close. Nightly
  reconciliation compares those sale-derived aggregates against the shift
  document, so shifts closed by this client will be reported as
  `invalid_or_missing_shift` until the shift-reporting migration writes them.
  Writing a device-local guess would be worse than an absent value, because one
  cashier's shift can span devices.
- Restoration re-reads only a shift named by durable local state. Discovering an
  open shift that the same cashier created on another device needs an indexed
  `staffId`/`status` query and a widened repository query boundary.
- `CheckoutDraftService` is still not composed in `main.dart` because no screen
  creates a draft. Its new `startGuard` parameter is optional so existing
  callers are unchanged; the shift-backed gate is exercised end to end through
  the real draft service in `test/shift/shift_checkout_gate_test.dart`.

Files in this chunk:

```text
docs/frontend_tenant_migration_inventory.md
firestore.rules
lib/checkout/checkout_draft.dart
lib/main.dart
lib/shift/shift.dart
lib/shift/shift_controller.dart
lib/shift/shift_local_state.dart
lib/shift/shift_panel.dart
lib/shift/tenant_shift.dart
lib/tenancy/tenant_routing_shell.dart
lib/tenancy/tenant_switch.dart
rules-tests/README.md
rules-tests/package.json
rules-tests/test/shift-lifecycle.test.js
test/shift/shift_checkout_gate_test.dart
test/shift/shift_controller_test.dart
test/shift/shift_local_state_test.dart
test/shift/shift_panel_test.dart
test/shift/tenant_shift_test.dart
PLAN.md
```

Validation evidence after implementation code was frozen:

- `flutter analyze --no-pub lib/shift lib/checkout lib/tenancy test/shift
  test/checkout test/tenancy` reported no issues.
- `flutter test --no-pub --concurrency=1 --reporter=compact test/shift
  test/checkout test/tenancy` passed **427/427** relevant Flutter tests,
  including **60** new tests: 16 read-model/repository/writer, 9 durable-state
  and switch-source, 23 controller, 6 checkout-gate, and 6 panel-widget cases.
- `npm --prefix rules-tests run test:emulator:shift-lifecycle` passed the
  focused Firestore-only suite **7/7** during development.
- `npm --prefix rules-tests run test:emulator` passed the full Firestore Rules
  suite **44/44** (37 existing plus the 7 new shift cases).
- With portable Node.js 24.18.1, Temurin JDK 21 at
  `D:\firebase-emulator-tools\jdk21\jdk-21.0.12+8`, inherited `DEBUG` removed,
  and `NODE_OPTIONS=--max-old-space-size=512`, `npm --prefix functions test`
  passed **166/166** Functions tests. No Functions source changed.
- With `FUNCTIONS_DISCOVERY_TIMEOUT=60`,
  `npm --prefix rules-tests run test:emulator:invitations` passed **12/12** real
  Auth, Firestore, and Functions emulator integration tests.
- `git diff --check` was clean before staging. Android build and Android
  emulator validation were intentionally skipped as requested.

Meaningful failures and resolutions:

- **The first panel widget test hung with no output.** Two causes. Real
  file-backed Hive I/O never completes inside a `testWidgets` fake-async zone,
  so every durable operation stalled; and `pumpAndSettle` cannot be used once
  the counted-cash field has focus, because the blinking cursor keeps
  scheduling frames. The panel test now opens an in-memory Hive box
  (`bytes: Uint8List(0)`) and pumps a bounded number of frames through a local
  `_settle` helper. Unit tests keep using file-backed boxes.
- **Piping `flutter test` through PowerShell `Select-Object` hid all progress**
  until the process exited, which made the hang look like a silent failure. Use
  `Start-Process` with redirected output files and an explicit
  `WaitForExit(milliseconds)` bound when a Flutter run may hang, then read the
  tail. Confirm no earlier `flutter_tester` process is still alive first.
- **A PowerShell `-replace` rewrite corrupted a typographic apostrophe** in the
  test file into mojibake. The panel message was reworded to plain ASCII, and
  source edits went back through the editing tools rather than shell text
  rewrites.
- **An early test asserted that an ambiguous create keeps its local record while
  the fake server showed the shift absent.** That was contradictory: a
  successful canonical read is exactly what may conclude nothing was written.
  The test now proves settlement by canonical read, and a second test covers the
  case where the settlement read itself fails and the durable intent survives.
- No other test assertion failed; the analyzer and every command in the final
  sequence were green on their first execution.

The existing user-owned local edits remain separate and must not be staged:

```text
.vscode/settings.json
android/gradle.properties
pubspec.lock dependency-resolution updates for characters, matcher,
material_color_utilities, meta, test_api, and the Dart SDK constraint
```

### Next bounded frontend chunk

Implement only the shift-scoped sale attribution and closing summary that the
frozen reconciliation contract already expects:

1. Bind a draft to the open shift: `CheckoutDraftService` must take the shift ID
   from the guarded shift controller instead of a caller-supplied
   `CheckoutDraftRequest.shiftId`, refuse a checkout with no canonical open
   shift, and prove the recorded `shiftId` belongs to the same tenant, cashier,
   and business date as the sale.
2. Extend the frozen `CheckoutSalePayload` v1 allow-list and the Firestore sale
   Rules so `shiftId` is required and validated, or explicitly version the
   payload schema in the same chunk.
3. Write the sale-derived `totalSales` and `transactionCount` aggregates when a
   shift closes, computed only from evidence the device can prove, and record
   how a multi-device shift is reconciled. Nightly reconciliation currently
   reports `invalid_or_missing_shift` for every shift this client closes, so
   this row is the reason to do it next.
4. Add a bounded, indexed open-shift discovery query behind the repository
   boundary so a cashier who restarts on a second device restores the same
   canonical shift instead of opening a duplicate.
5. Add unit, Hive-reopen, session/widget, and focused Firestore Rules emulator
   coverage for shift-bound sales, denial of an unbound or foreign-shift sale,
   close-time aggregate agreement, restart discovery, and the existing
   cash-close switch blocker.
6. Leave the checkout screen and payment flow, receipt printing, product
   cost/profit fields, returns, reports, subscription and branding surfaces,
   deployment, and Android build/emulator validation outside that chunk.

---

## Shift-scoped sale attribution and closing summary handoff - 2026-07-31

### Completed in this session

Every sale is now bound to a canonical shift, and a closing shift carries the
sale-derived aggregates nightly reconciliation already expects. This chunk adds
no checkout screen or payment flow, no receipt printing, no reports, and makes
no legacy operational POS route reachable.

Implemented behavior and safety decisions:

- `CheckoutDraftRequest.shiftId` is gone. The draft takes its shift from the
  required `CheckoutShiftBinder`, which the guarded shift lifecycle implements,
  so a caller can no longer name a shift the cashier does not hold. The binder
  is a constructor requirement rather than an option: a checkout with no proven
  open shift is refused instead of recorded as an unreconcilable sale.
- `TenantShiftCheckoutBinder` replaces `TenantShiftCheckoutGate`. It still
  enforces the frozen cashier cross-business restriction and additionally
  refuses `no_open_shift`, `shift_not_confirmed` (the server has not
  acknowledged the shift, so a sale bound to it might reference nothing), and
  `shift_closing` (the cash count has started). Unreadable local state still
  raises and becomes `checkout_start_unavailable`.
- The draft proves the bound shift describes this exact sale: a different
  cashier, business, or device fails closed as `shift_binding_mismatch`, and a
  different business day fails closed as `shift_business_date_mismatch`. The
  date must agree because reconciliation aggregates per shift **and** business
  date, so a shift left open across the Africa/Nairobi boundary must be closed
  rather than silently absorbing the next day's sales. All of this happens
  before the receipt sequence is allocated, so a refused checkout still consumes
  nothing.
- `CheckoutSalePayload` v1 now requires `shiftId`; it is no longer optional and
  is always written to the sale document. No deployed data exists, and a
  hypothetical pre-existing local draft without a shift is refused as malformed
  and retained as evidence rather than submitted.
- Firestore Rules bind the sale to the shift on create: the named shift must
  exist under the same tenant, name the calling cashier, and carry the same
  `deviceId` and `businessDate` as the sale. A closed shift is deliberately
  still accepted, because an offline sale may reach the server after its shift
  closed and refusing it would strand evidence the device can no longer correct;
  reconciliation reports that variance instead.
- `CheckoutOutboxShiftSalesLedger` summarizes one shift from the encrypted
  outbox: confirmed sales produce `transactionCount` and `totalSalesMinor`, and
  every unconfirmed local sale is counted as unsettled. `closeShift` refuses
  with `unsynchronized_shift_sales` while any sale is unsettled, so the shift
  keeps its counted cash and its tenant-switch blocker rather than publishing a
  total the server will contradict. An unattributed or malformed local sale
  raises instead of being skipped, because a silently dropped sale would
  understate the shift and turn a device defect into a permanent variance.
- The close writes `totalSalesMinor`, the major-unit `totalSales`, and
  `transactionCount`. Rules require all three, require non-negative integer and
  numeric types, refuse sales without a transaction, and restrict the changed
  keys to exactly the seven close fields. Nightly reconciliation therefore stops
  reporting `invalid_or_missing_shift` for shifts this client closes.
- A multi-device shift is resolved by preventing one, not by guessing. Bounded
  open-shift discovery re-adopts this cashier's canonical shift after durable
  local state is lost, so a reinstall no longer opens a duplicate; a shift open
  on **another** device is reported as `shift_open_on_other_device` and neither
  adopted nor duplicated, because the closing summary is built from local sale
  evidence only the issuing device holds. Two open shifts for one cashier on one
  device fail closed as `ambiguous_open_shift`. Server-side shift transfer
  between devices remains out of scope.
- Discovery runs through the repository boundary. `TenantReadRepository` gained
  bounded `field == value` filters that only a repository can supply: field
  names must be simple document fields, values must be bounded strings,
  integers, or booleans, at most four are accepted, and every returned document
  is still proved to be an exact child of this tenant's collection, unique, and
  ordered. `firestore.indexes.json` gained the matching
  `staffId`/`status`/`__name__` shift index.
- The shift panel shows the confirmed sales summary while the cash count is
  open, plus bounded messages for the other-device and unsynchronized-sales
  refusals.

Deliberately outside this chunk, and important for the next session:

- Rules cannot prove that a receipt is globally unique or that a shift's
  aggregates match the sales the server holds; only reconciliation can. The
  client guarantees are the device-local atomic counter and the refusal to close
  with unsettled sales.
- A `needs_attention` checkout (an observed payload hash that disagrees with
  local evidence) counts as unsettled indefinitely, so it blocks both the tenant
  switch and the shift close until it is resolved. That is deliberate: the
  device already cannot describe the shift, and the state needs attention.
- `CheckoutDraftService` is still not composed in `main.dart`, because no screen
  creates a draft. `main.dart` does compose the sales ledger into the shift
  controller.

Files in this chunk:

```text
docs/frontend_tenant_migration_inventory.md
firestore.indexes.json
firestore.rules
lib/checkout/checkout_draft.dart
lib/checkout/checkout_sale.dart
lib/main.dart
lib/shift/shift.dart
lib/shift/shift_controller.dart
lib/shift/shift_panel.dart
lib/shift/shift_sales_ledger.dart
lib/shift/tenant_shift.dart
lib/tenancy/tenant_repository.dart
rules-tests/README.md
rules-tests/package.json
rules-tests/test/checkout-receipt.test.js
rules-tests/test/checkout-submission.test.js
rules-tests/test/shift-lifecycle.test.js
rules-tests/test/shift-sale-attribution.test.js
rules-tests/test/stock-and-sales.test.js
rules-tests/test/support.js
test/checkout/checkout_draft_test.dart
test/checkout/checkout_sale_test.dart
test/checkout/checkout_submission_test.dart
test/checkout/checkout_sync_test.dart
test/shift/shift_checkout_binder_test.dart
test/shift/shift_controller_test.dart
test/shift/shift_panel_test.dart
test/shift/shift_sales_ledger_test.dart
test/shift/tenant_shift_test.dart
test/tenancy/tenant_repository_test.dart
PLAN.md
```

`test/shift/shift_checkout_gate_test.dart` was renamed to
`test/shift/shift_checkout_binder_test.dart` and rewritten for the binding
contract.

Validation evidence after implementation code was frozen:

- `flutter analyze --no-pub lib/shift lib/checkout lib/tenancy test/shift
  test/checkout test/tenancy` reported no issues. A whole-repository
  `flutter analyze` still reports the pre-existing legacy POS findings and the
  stale `test/widget_test.dart` reference to `MyApp`; neither was touched.
- `flutter test --no-pub --concurrency=1 --reporter=failures-only test/shift
  test/checkout test/tenancy` passed **458/458** relevant Flutter tests,
  including **31** new tests: 6 sales-ledger, 10 controller closing-summary and
  discovery, 5 draft-binding, 5 binder, 4 shift-repository, 3 payload-contract,
  2 collection-filter, and 1 panel case.
- `npm --prefix rules-tests run test:emulator:shift-sale-attribution` passed the
  focused Firestore-only suite **6/6** during development.
- `npm --prefix rules-tests run test:emulator` passed the full Firestore Rules
  suite **51/51** (44 existing plus the 6 new attribution cases and the new
  zero-summary close case, with the existing sale suites updated to seed a
  canonical shift).
- With portable Node.js and Temurin JDK 21 at
  `D:\firebase-emulator-tools\jdk21\jdk-21.0.12+8`, inherited `DEBUG` removed,
  and `NODE_OPTIONS=--max-old-space-size=512`, `npm --prefix functions test`
  passed **166/166** Functions tests. No Functions source changed.
- With `FUNCTIONS_DISCOVERY_TIMEOUT=60`,
  `npm --prefix rules-tests run test:emulator:invitations` passed **12/12** real
  Auth, Firestore, and Functions emulator integration tests.
- `git diff --check` was clean apart from expected Windows line-ending warnings,
  and `firestore.indexes.json` parsed as valid JSON. Android build and Android
  emulator validation were intentionally skipped as requested.

Meaningful failures and their resolutions:

- **The first shift-bound sale rule denied a legitimate maximum-size sale.** The
  focused emulator run reported `Unable to evaluate the expression as the
  maximum of 1000 expressions to evaluate has been reached` for the sixteen-line
  sale while the five behavioral cases passed, exactly as the receipt rule did
  in the previous chunk. Repeating `exists()` plus four `get()` calls for the
  same shift was the cost. The rule now reads the shift once into a Rules `let`
  binding, and budget was reclaimed by dropping the redundant
  `shift.data.tenantId` comparison (the path already scopes the tenant), the
  separate `businessDate`/`deviceId` type checks in the receipt rule (a
  non-string date cannot be split, and the device is compared against the
  shift's validated string), and the per-line `is map` check (a non-map line
  cannot answer a field access). Each of those cases still denies through an
  evaluation error, which the existing suites prove. The maximum-size sale now
  has a permanent budget guard in both the receipt and attribution suites.
- **Rules `let` bindings are eager.** A binding is evaluated before the
  short-circuiting condition, so `shiftId is string` is checked at the call site
  before `validSaleShift` runs, keeping a non-string shift a clean denial rather
  than relying on path-interpolation behavior.
- **The existing shift-lifecycle `extra-field` denial used `totalSales`.** That
  field is now a required close field, so the case was rewritten with an
  unrelated `cashierNote` key and joined by seven new denial cases for a
  missing, negative, fractional, string, or internally contradictory summary.
- No other test assertion failed; the analyzer and every command in the final
  sequence were green on their first execution.

The existing user-owned local edits remain separate and must not be staged:

```text
.vscode/settings.json
android/gradle.properties
pubspec.lock dependency-resolution updates for characters, matcher,
material_color_utilities, meta, test_api, and the Dart SDK constraint
```

### Next bounded chunk

Implement only the guarded shift-history read surface that a closed shift now
makes meaningful:

1. Add a strict read model and guarded repository for closed shifts in
   `tenants/{tenantId}/shifts`: bounded, indexed, ordered pages of this
   cashier's own closed shifts, plus owner/admin/manager access to every
   cashier's closed shifts in the tenant. Derive every path from `TenantPaths`
   and keep the exact-child, uniqueness, and ordering proofs.
2. Render a read-only shift history behind `TenantRouteGuard`, showing counted
   cash beside the sale-derived `totalSales`/`transactionCount` and naming the
   difference without recomputing either figure on the device.
3. Add the composite indexes those queries need, and prove the role boundary in
   the Firestore Rules emulator. A cashier may currently read every shift in the
   tenant; decide explicitly whether to narrow that rule and test the decision.
4. Add unit, widget, and focused Rules emulator coverage for pagination
   boundaries, a cross-tenant response, a wrong-role read, a tenant switch
   during an outstanding page, and a shift closed without a summary.
5. Leave the checkout screen and payment flow, receipt printing, returns,
   product cost/profit fields, subscription and branding surfaces, server-side
   cross-device shift transfer, deployment, and Android build/emulator
   validation outside that chunk.

---

## Guarded shift-history read surface handoff - 2026-08-01

### Completed in this session

A closed shift is now readable. The tenant-safe landing route reaches a
read-only history that shows counted cash beside the recorded sale-derived
totals, and the Firestore shift read boundary was deliberately narrowed to match
what the client already enforced. This chunk adds no checkout screen or payment
flow, no receipt printing, no reports, and makes no legacy operational POS route
reachable.

Implemented behavior and safety decisions:

- `TenantShiftHistoryEntry` is a strict read model for a closed
  `tenants/{tenantId}/shifts/{shiftId}`. Identity, path, device, business date,
  and status are still proved by `TenantShift`; the entry adds the close-only
  fields, refuses a shift that is not `closed`, and refuses a close with no
  counted cash.
- The sale-derived summary is present or absent as a whole. All three of
  `totalSalesMinor`, `totalSales`, and `transactionCount` must appear together,
  the major-unit mirror must round-trip to the authoritative minor units, and
  sales without a transaction are refused. A shift closed by an earlier client
  carries no summary at all, which the surface **names** rather than guesses:
  only the closing device held the local sale evidence, so inventing a total on
  a screen used to settle cash would be worse than reporting its absence.
- `cashVarianceMinor` is a subtraction of two recorded figures. The device
  deliberately recomputes neither side from local evidence - a shift can span
  devices and reconciliation is the authority on which figure is wrong - so the
  screen only names the difference as over, short, or matching.
- `TenantShiftHistoryRepository` extends the existing guarded
  `TenantReadRepository`. Pages are bounded and derived from the session's
  `TenantPaths`, and the exact-child, uniqueness, and ordering proofs still
  apply. A cashier's page is filtered by `staffId == uid` and `status ==
  'closed'`; owners, admins, and managers may additionally page every cashier.
  A cashier that asks for the wider scope is refused as
  `shift_history_forbidden` **before** any query is issued, and a transport that
  ignored the filter still fails closed as `foreign_shift`.
- `TenantReadRepository.readCollectionPage` gained a `descending` option so a
  history surface can page from the newest record. It reverses the document-ID
  ordering only - no other sort field is reachable from the boundary - and the
  ordering proof reverses with it, so a page returned the wrong way round is a
  `TenantScopeViolation` in both directions. The generated shift ID embeds a
  fixed-width millisecond timestamp, so descending document order is newest
  first; the recorded instants are still rendered and the ordering is never
  presented as proof of time.
- **The Firestore shift read rule was narrowed.** An active cashier previously
  read every shift in the business, including a colleague's counted cash. The
  rule is now `owner/admin/manager, or the shift's own cashier`. A cashier's
  list query must therefore carry `staffId == uid`, which is exactly what the
  history and open-shift-discovery repositories already send, so the server and
  the client now agree on one boundary instead of the client being stricter than
  the server. The `shift-lifecycle` case that asserted a colleague could read
  the shift was rewritten as a denial.
- `firestore.indexes.json` gained the two descending composite indexes those
  pages need: `staffId`/`status`/`__name__ DESC` and `status`/`__name__ DESC`.
  The ascending `staffId`/`status`/`__name__` index that open-shift discovery
  uses is unchanged.
- The route is rendered by `TenantShiftHistoryPanel` behind `TenantRouteGuard`,
  so a missing session, a role change, or a tenant switch during an outstanding
  page discards that page before it can reach the tree. The panel owns only the
  requested scope and a cursor stack; changing either restarts the guard through
  a new key, so an earlier page can never complete into the current one.
- The entry point is the shift panel's `View shift history` action, and it
  exists only when the composition root supplies a reader. Tenancy code keeps
  owning routing rather than the shift domain: `main.dart` passes the same
  `FirebaseTenantDocumentReader` the rest of the landing route uses, and the
  route opens under the same `TenantSessionScope`.

Deliberately outside this chunk, and important for the next session:

- Another cashier's shift is labelled by UID. Resolving it to a display name
  needs the canonical staff directory, which is a management-only read, so a
  manager-scoped history would have to join two guarded repositories.
- Descending pages are ordered by document ID, not by `endTime`. That is exact
  for shifts this client opened; a shift imported with a foreign ID scheme would
  sort by its ID, not its time.
- Rules still cannot prove that a shift's aggregates match the sales the server
  holds. The history reports what was recorded; reconciliation reports variance.

Files in this chunk:

```text
docs/frontend_tenant_migration_inventory.md
firestore.indexes.json
firestore.rules
lib/main.dart
lib/shift/shift.dart
lib/shift/shift_history.dart
lib/shift/shift_history_panel.dart
lib/shift/shift_panel.dart
lib/tenancy/tenant_repository.dart
rules-tests/README.md
rules-tests/package.json
rules-tests/test/shift-history.test.js
rules-tests/test/shift-lifecycle.test.js
test/shift/shift_history_panel_test.dart
test/shift/shift_history_test.dart
test/shift/shift_panel_test.dart
test/tenancy/tenant_repository_test.dart
PLAN.md
```

Validation evidence after implementation code was frozen:

- `flutter analyze --no-pub lib/shift lib/checkout lib/tenancy test/shift
  test/checkout test/tenancy` reported no issues. A whole-repository
  `flutter analyze` still reports the pre-existing legacy POS findings, the
  stale `test/widget_test.dart` reference to `MyApp`, and the experimental
  `profilesSampleRate` warning in `main.dart`; none was touched.
- `flutter test --no-pub --concurrency=1 --reporter=failures-only test/shift
  test/checkout test/tenancy` passed **482/482** relevant Flutter tests,
  including **24** new tests: 12 read-model and repository, 7 history-panel
  widget, 2 shift-panel navigation, and 3 base-repository ordering cases.
- `npm --prefix rules-tests run test:emulator:shift-history` passed the focused
  Firestore-only suite **5/5** during development, and
  `npm --prefix rules-tests run test:emulator:shift-lifecycle` passed **8/8**
  after the read rule changed.
- `npm --prefix rules-tests run test:emulator` passed the full Firestore Rules
  suite **56/56** (51 existing plus the 5 new history cases).
- With portable Node.js and Temurin JDK 21 at
  `D:\firebase-emulator-tools\jdk21\jdk-21.0.12+8`, inherited `DEBUG` removed,
  and `NODE_OPTIONS=--max-old-space-size=512`, `npm --prefix functions test`
  passed **166/166** Functions tests. No Functions source changed.
- With `FUNCTIONS_DISCOVERY_TIMEOUT=60`,
  `npm --prefix rules-tests run test:emulator:invitations` passed **12/12** real
  Auth, Firestore, and Functions emulator integration tests.
- `git diff --check` was clean apart from expected Windows line-ending
  warnings, and `firestore.indexes.json` parsed as valid JSON. Android build and
  Android emulator validation were intentionally skipped as requested.

Meaningful failures and their resolutions:

- **The manager scope test failed to find its own toggle.** The first
  history-panel fake reader ignored the repository's equality filters, so the
  own-scope page returned a colleague's shift, the repository correctly failed
  closed as `foreign_shift`, and the guard rendered the failure state instead of
  the segmented control. The fake now honours the filters it is given, which is
  also what makes the wider-scope assertion meaningful; the deliberately
  unfiltered transport stays in the unit suite, where failing closed is the
  assertion.
- No other test assertion failed; the analyzer and every command in the final
  sequence were green on their first execution.

### Correction committed immediately after `1a27d83`

**The narrowed read rule denied a read of an absent shift.** `resource` is null
for a document that does not exist, so `resource.data.staffId` raised an
evaluation error and the read was denied instead of answered. That broke the
frozen settlement contract from the previous chunk - only a successful read may
conclude that nothing was written - so an unacknowledged create would have
become `shift_unavailable` instead of clearing its durable intent. Neither the
Dart fakes nor the first emulator suite covered it, because every case read a
document that existed.

The rule now reads
`resource == null || resource.data.staffId == request.auth.uid` for the cashier
branch. A document that does not exist discloses nothing, so allowing the answer
is safe. `shift-history.test.js` gained a permanent regression case, and the
full Rules suite passed **57/57**. Apply the same reasoning to any future
`resource.data`-based read narrowing.

The existing user-owned local edits remain separate and must not be staged:

```text
.vscode/settings.json
android/gradle.properties
pubspec.lock dependency-resolution updates for characters, matcher,
material_color_utilities, meta, test_api, and the Dart SDK constraint
```

### Next bounded chunk

Implement only the guarded tenant sales-history read surface that shift history
now points at:

1. Add a strict read model and guarded repository for
   `tenants/{tenantId}/sales`: bounded, indexed, ordered pages of the sales
   recorded during one closed shift, plus a cashier's own recent sales. Reuse
   the frozen `CheckoutSalePayload` v1 field set, refuse a document whose
   `shiftId`, `soldById`, `deviceId`, or `businessDate` disagrees with the shift
   it is claimed to belong to, and keep the exact-child, uniqueness, and
   ordering proofs.
2. Decide and test the sale read boundary in Rules exactly as this chunk did for
   shifts: a cashier currently reads every sale in the business. Narrowing it to
   `soldById == uid` for cashiers would require every cashier-issued sale query
   to carry that filter, and management to keep the wider read.
3. Add the composite indexes those queries need, including the `shiftId` page.
4. Link a closed shift to its own sales from the history entry, so the recorded
   `transactionCount` can be inspected rather than trusted, without recomputing
   the shift's stored totals on the device.
5. Add unit, widget, and focused Rules emulator coverage for pagination
   boundaries, a cross-tenant response, a wrong-role read, a tenant switch
   during an outstanding page, and a sale whose shift attribution disagrees.
6. Leave the checkout screen and payment flow, receipt printing, returns,
   product cost/profit fields, subscription and branding surfaces, server-side
   cross-device shift transfer, deployment, and Android build/emulator
   validation outside that chunk.

---

## Guarded sale-history read surface handoff - 2026-08-01

### Completed in this session

A closed shift now links to the sales it recorded, and a cashier can look up
its own recent receipts. This chunk adds no checkout screen or payment flow, no
receipt printing, no returns, no product cost or profit surface, and makes no
legacy operational POS route reachable.

Implemented behavior and safety decisions:

- `TenantSale` is a strict read model for `tenants/{tenantId}/sales/{saleId}`.
  The document must repeat the identity encoded in its own path - Rules bind the
  document ID to the immutable `checkoutId` at create - declare the frozen v1
  payload schema, and add up: line totals must equal price times quantity, their
  sum must equal `subtotalMinor`, `totalMinor` must equal subtotal minus
  discount, and every major-unit mirror must round-trip to its authoritative
  minor units. An unsupported `payloadSchemaVersion` is refused outright rather
  than partially interpreted.
- The receipt is re-derived, not trusted. A sale whose `receiptNumber` is not
  what this exact device, business date, and sequence would produce is refused,
  which is the same proof the draft builder applies before submission and the
  Rules apply on create. A customer-facing number is never shown unless it
  describes its own sale.
- Product cost and profit fields the draft may write are parsed away rather than
  exposed. They stay outside this surface deliberately.
- `TenantSaleHistoryRepository` extends the guarded `TenantReadRepository`. It
  offers exactly two bounded pages: the sales of one canonical shift, and this
  cashier's own recent sales. A shift page proves every sale names that shift
  and agrees with its cashier, device, and business day; a sale that contradicts
  the shift fails the whole page closed, because on a screen used to inspect a
  shift, contradicting evidence must be reported rather than quietly listed as
  if it belonged. The shift identity is carried from the already-validated
  history entry, so the sales route needs no second read of the shift.
- **The sale read rule was deliberately left wider than the shift rule.** Any
  active staff member reads any sale in the business. A sale is the business's
  shared record of a transaction: a receipt lookup, a return against a
  colleague's sale, and the fail-closed confirmation of a deterministic sale
  path all need it, whereas a shift is one cashier's own cash record. Narrowing
  it to `soldById` would also turn an unreadable foreign sale into an endless
  submission retry instead of a reported mismatch. Three assertions pin that
  decision so a future narrowing has to change them on purpose.
- The screen states the figures the shift recorded and pages the sales beneath
  them. It computes no replacement total: a page tally would be a second,
  weaker aggregate that disagrees with reconciliation at every page boundary.
  Inspection is the point, recomputation is not.
- `firestore.indexes.json` gained `shiftId`/`__name__ DESC` and
  `soldById`/`__name__ DESC` for the two pages.

Deliberately outside this chunk, and important for the next session:

- A sale names its cashier by UID. Resolving it to a display name needs the
  management-only staff directory, the same open question the shift history has.
- There is no management-wide sales page. Every page carries an equality filter
  by construction (see below), so a business-wide sales list needs its own
  deliberate filter and index rather than an unfiltered scan.

Files in this chunk:

```text
docs/frontend_tenant_migration_inventory.md
firestore.indexes.json
firestore.rules
lib/sales/sale_history.dart
lib/sales/sale_history_panel.dart
lib/sales/sales.dart
lib/shift/shift_history_panel.dart
lib/tenancy/tenant_repository.dart
rules-tests/README.md
rules-tests/package.json
rules-tests/test/sale-history.test.js
test/sales/sale_history_panel_test.dart
test/sales/sale_history_test.dart
test/shift/shift_history_panel_test.dart
test/tenancy/tenant_repository_test.dart
PLAN.md
```

Validation evidence after implementation code was frozen:

- `flutter analyze --no-pub lib/sales lib/shift lib/checkout lib/tenancy
  test/sales test/shift test/checkout test/tenancy` reported no issues.
- `flutter test --no-pub --concurrency=1 --reporter=failures-only test/sales
  test/shift test/checkout test/tenancy` passed **503/503** relevant Flutter
  tests, including **21** new tests: 11 sale read-model and repository, 7
  sale-panel widget, 2 shift-to-sales navigation, and 1 base-repository
  descending-scan case.
- `npm --prefix rules-tests run test:emulator:sale-history` passed the focused
  Firestore-only suite **5/5** during development.
- `npm --prefix rules-tests run test:emulator` passed the full Firestore Rules
  suite **62/62** (57 existing plus the 5 new sale-history cases).
- `npm --prefix functions test` passed **166/166** Functions tests with the
  pinned Node 24 / Temurin JDK 21 environment. No Functions source changed.
- With `FUNCTIONS_DISCOVERY_TIMEOUT=60`,
  `npm --prefix rules-tests run test:emulator:invitations` passed **12/12** real
  Auth, Firestore, and Functions emulator integration tests.
- `git diff --check` was clean apart from expected Windows line-ending
  warnings, and `firestore.indexes.json` parsed as valid JSON. Android build and
  Android emulator validation were intentionally skipped as requested.

Meaningful failures and their resolutions:

- **Firestore does not support descending key scans.** The emulator refused an
  unfiltered `orderBy(documentId(), "desc")` page outright - not a Rules denial
  but a query-planner rejection - which no Dart fake could have caught. Both
  history repositories always send an equality filter, so no shipped query was
  affected, but the boundary now refuses to build an unfiltered descending page
  at all, turning a runtime query failure into an immediate programming error.
  The rule is recorded in `readCollectionPage`, the rules-tests README, and a
  unit test; the emulator case now issues the query the client would actually
  send.
- **A shift-history pagination test stopped finding its own button.** The new
  sales links made the list taller, so `ListView` no longer built the paging
  controls; the test scrolls to them first. Worth remembering for every future
  list surface in this app.
- No other test assertion failed; the analyzer and every other command in the
  final sequence were green on their first execution.

The existing user-owned local edits remain separate and must not be staged:

```text
.vscode/settings.json
android/gradle.properties
pubspec.lock dependency-resolution updates for characters, matcher,
material_color_utilities, meta, test_api, and the Dart SDK constraint
```

### Next bounded chunk

Implement only the guarded tenant staff-name resolution both history surfaces
now need, and nothing else:

1. Add a bounded, guarded lookup that resolves the cashier UIDs on one page of
   shifts or sales to canonical staff display names, reusing the existing
   `TenantStaffDirectoryRepository` boundary rather than a new path. Resolve
   only the UIDs actually on screen, cache them per session/epoch, and fall back
   to the UID when the caller may not read the staff record.
2. Decide explicitly whether a cashier may read a colleague's canonical staff
   document at all. The current rule allows it; the staff directory screen is
   already owner/admin/manager-only, so the decision is about the read boundary,
   not the screen. Test whichever decision is taken.
3. Show the resolved name beside the UID-labelled entries in shift history and
   sale history, keeping the UID visible wherever it is the authoritative
   identity.
4. Add unit, widget, and focused Rules emulator coverage for an unresolvable
   UID, a denied staff read, a tenant switch during resolution, and a page whose
   staff document disappears between reads.
5. Leave the checkout screen and payment flow, receipt printing, returns,
   product cost/profit fields, subscription and branding surfaces, server-side
   cross-device shift transfer, deployment, and Android build/emulator
   validation outside that chunk.

---

## Guarded staff-name resolution handoff - 2026-08-01

### Completed in this session

Both history surfaces now name the cashier they are attributing evidence to,
and the canonical staff read was narrowed so that name is only resolvable by a
role entitled to the record behind it. This chunk adds no checkout screen or
payment flow, no receipt printing, no returns, and makes no legacy operational
POS route reachable.

Implemented behavior and safety decisions:

- `TenantStaffNameResolver` extends the guarded `TenantReadRepository` and
  resolves `staff/{uid}` display names for the UIDs on one page. It is the one
  repository that deliberately does **not** fail a page closed: a display name
  is a convenience label and the UID beside it is the authoritative identity, so
  an unreadable, missing, or malformed record degrades to the UID rather than
  hiding a page of financial evidence. A `TenantScopeViolation` still
  propagates, because a transport answering outside this tenant is a broken
  boundary, not an unavailable label.
- Only the explicit `name` field is used. The staff record also carries an email
  and a phone number, and a history row is not the place to disclose either. A
  record whose `uid` does not match its own path resolves to nothing, exactly as
  the staff directory requires, because it describes somebody else.
- Resolution is bounded to 25 documents per page - a page is bounded, but its
  distinct cashiers are not necessarily few - and the remainder simply shows
  UIDs. Misses are cached, so a denied record is not re-requested on every page.
- One resolver exists per session. The cache key is UID, tenant, and epoch, so a
  tenant switch or re-open discards it and it can never label the next session's
  rows.
- **The canonical staff read rule was narrowed.** A cashier now reads only its
  own record; owners, admins, and managers read the whole roster, which is what
  the staff directory screen already required. The identity compared in the rule
  is the `{uid}` path wildcard rather than a document field, so - unlike the
  shift rule earlier in this session - an absent record still answers instead of
  raising an evaluation error. A cashier consequently sees a colleague's UID and
  a manager sees the name, with no client branching: the resolver degrades on
  its own.
- `tenantStaffLabel` keeps the UID visible beside every resolved name
  (`Brian (user-b)`), and labels the caller `You` or `You (Amina)`. The UID is
  the identity every sale, shift, and audit record is attributed by, so it is
  never replaced by a name.

Deliberately outside this chunk, and important for the next session:

- A colleague's name only ever appears on a management page. Both cashier-facing
  pages are scoped to the caller's own UID by construction, so the fallback is
  the normal path there, not an error.
- The resolver reads one document per distinct UID. A page dominated by distinct
  cashiers costs up to 25 reads; a denormalized `soldByName` on the sale would
  remove that cost but would also freeze a name that later changes.

Files in this chunk:

```text
docs/frontend_tenant_migration_inventory.md
firestore.rules
lib/sales/sale_history_panel.dart
lib/shift/shift_history_panel.dart
lib/tenancy/tenancy.dart
lib/tenancy/tenant_staff_names.dart
rules-tests/README.md
rules-tests/package.json
rules-tests/test/staff-directory-read.test.js
test/sales/sale_history_panel_test.dart
test/shift/shift_history_panel_test.dart
test/tenancy/tenant_staff_names_test.dart
PLAN.md
```

Validation evidence after implementation code was frozen:

- `flutter analyze --no-pub lib/sales lib/shift lib/checkout lib/tenancy
  test/sales test/shift test/checkout test/tenancy` reported no issues.
- `flutter test --no-pub --concurrency=1 --reporter=failures-only test/sales
  test/shift test/checkout test/tenancy` passed **514/514** relevant Flutter
  tests, including **11** new tests: 7 resolver and label, 3 sale-panel naming,
  and 1 shift-panel fallback case.
- `npm --prefix rules-tests run test:emulator:staff-directory-read` passed the
  focused Firestore-only suite **4/4** during development.
- `npm --prefix rules-tests run test:emulator` passed the full Firestore Rules
  suite **66/66** (62 existing plus the 4 new staff-read cases).
- `npm --prefix functions test` passed **166/166** Functions tests with the
  pinned Node 24 / Temurin JDK 21 environment. No Functions source changed.
- With `FUNCTIONS_DISCOVERY_TIMEOUT=60`,
  `npm --prefix rules-tests run test:emulator:invitations` passed **12/12** real
  Auth, Firestore, and Functions emulator integration tests.
- `git diff --check` was clean apart from expected Windows line-ending warnings.
  Android build and Android emulator validation were intentionally skipped as
  requested.

Meaningful failures and their resolutions:

- **Two widget tests asserted a colleague's row on a page that can never show
  one.** Both cashier-facing sale pages are scoped to the caller's own UID, so
  the fake reader correctly filtered the colleague's sale out. The tests now use
  the only page where a colleague appears - a manager inspecting another
  cashier's shift - which is also the only place the narrowed staff rule
  resolves a name.
- **A test source file ended up containing a raw control character.** The
  malformed-name case was written with a literal BEL instead of an escape. It
  was replaced with a visible `` through a checked script rather than a
  shell text rewrite, which is the same failure mode recorded in an earlier
  chunk.
- No other test assertion failed; the analyzer and every other command in the
  final sequence were green on their first execution.

The existing user-owned local edits remain separate and must not be staged:

```text
.vscode/settings.json
android/gradle.properties
pubspec.lock dependency-resolution updates for characters, matcher,
material_color_utilities, meta, test_api, and the Dart SDK constraint
```

### Next bounded chunk

Implement only the guarded daily sales summary the reporting contract already
expects, and nothing else:

1. Add a strict read model and guarded repository for the tenant's daily
   metrics documents that nightly reconciliation regenerates, deriving every
   path from `TenantPaths` and refusing a document that disagrees with the
   business date encoded in its own path. Confirm the canonical collection and
   field names against `functions/src/reconciliation/**` before designing the
   model; do not invent a schema the backend does not write. `TenantCollection`
   may need one new frozen segment, which is a deliberate path-contract change.
2. Render a management-only daily summary behind `TenantRouteGuard`, showing the
   reconciled figures as recorded, with an explicit `not yet reconciled` state
   for a day the workers have not processed. Do not aggregate sales on the
   device.
3. Decide and test the read boundary for those documents exactly as the last
   three chunks did, including the absent-document case, which is the normal
   state for today's date.
4. Add the composite indexes any bounded date-range page needs, remembering that
   a descending page must carry at least one equality filter.
5. Add unit, widget, and focused Rules emulator coverage for a missing day, a
   wrong-role read, a cross-tenant response, a tenant switch during an
   outstanding load, and a malformed metrics document.
6. Leave `getSalesComparison`, the legacy report screens, the checkout screen
   and payment flow, receipt printing, returns, product cost/profit fields,
   subscription and branding surfaces, deployment, and Android build/emulator
   validation outside that chunk.

---

## Guarded daily summary handoff - 2026-08-01

### Completed in this session

The tenant-safe landing route now reaches a management-only daily summary built
from the metrics nightly reconciliation regenerates. This chunk adds no
checkout screen or payment flow, no receipt printing, no legacy report screen,
no `getSalesComparison` call, and makes no legacy operational POS route
reachable.

Implemented behavior and safety decisions:

- The schema was read from `functions/src/reconciliation/processors.ts` and
  `model.ts` rather than invented: `tenants/{tenantId}/daily_metrics/
  {businessDate}` carries `sales`, `profit`, `transactions`,
  `incompleteCostLineCount`, `businessDate`, `transactionCount`, `shiftCount`,
  `tenantId`, `metricGeneration`, `sourceDirtyRevision`, `regeneratedAt`, and
  `updatedAt`.
- `TenantCollection` gained one frozen segment, `daily_metrics`. That is a
  deliberate path-contract change, and the enumerated path-contract test was
  updated with it rather than around it.
- `TenantDailyMetrics` requires the document to repeat the tenant and business
  date its own path encodes, and refuses a document whose two transaction
  counts disagree - the writer stores the same number twice, so a disagreement
  means the reconciliation processor did not write it. `regeneratedAt` is
  **required**, unlike the pending-write instants on a shift or a sale: the
  client never writes this document, so there is no state in which a
  server-owned timestamp is legitimately missing.
- `profit` may legitimately be negative and is parsed, but no screen displays
  it. It depends on product cost data whose completeness the document itself
  reports through `incompleteCostLineCount`, and product cost/profit surfaces
  are outside this chunk. The panel names the incomplete-cost count instead, so
  the gap is visible without publishing a figure built on it.
- **Days are read by exact document path, not by query.** A query cannot return
  a day that has no document, and today is normally unreconciled, so a query
  would silently omit exactly the day a manager is looking for. Reading the last
  N business dates by path makes an unreconciled day a first-class
  `not reconciled yet` result. It also needs no composite index at all, which is
  why this chunk adds none.
- The business dates are derived by subtracting whole days from the UTC instant
  and reusing `checkoutBusinessDate`, so the Africa/Nairobi boundary is applied
  by the one function that already owns it rather than by new date arithmetic.
- The load is bounded to 14 days, one document read each, and refuses a
  non-management session before issuing any read.
- **The Firestore rule is management-only and server-write-only.** A cashier
  reads its own sales and shifts but not the business's daily revenue. The role
  check touches no document field, so an unreconciled day still answers instead
  of raising an evaluation error - the same trap that had to be fixed for the
  shift rule earlier in this session, avoided here by construction.
- The route is injected into the safe landing screen the way the shift and
  checkout panels already are, so tenancy code keeps owning routing rather than
  the reporting domain, and the button only appears for the roles the reporting
  domain names.

Deliberately outside this chunk, and important for the next session:

- There is no date picker and no range beyond the trailing window. A specific
  historical day is reachable by `readDay`, but no surface offers it yet.
- `getSalesComparison` remains uncalled. It is the callable that answers
  period-over-period questions; this surface only reports regenerated days.

Files in this chunk:

```text
docs/frontend_tenant_migration_inventory.md
firestore.rules
lib/main.dart
lib/reporting/daily_metrics.dart
lib/reporting/daily_metrics_panel.dart
lib/reporting/reporting.dart
lib/tenancy/tenant_paths.dart
lib/tenancy/tenant_routing_shell.dart
rules-tests/README.md
rules-tests/package.json
rules-tests/test/daily-metrics.test.js
test/reporting/daily_metrics_panel_test.dart
test/reporting/daily_metrics_test.dart
test/tenancy/tenant_paths_test.dart
PLAN.md
```

Validation evidence after implementation code was frozen:

- `flutter analyze --no-pub lib/reporting lib/sales lib/shift lib/checkout
  lib/tenancy test/reporting test/sales test/shift test/checkout test/tenancy`
  reported no issues.
- `flutter test --no-pub --concurrency=1 --reporter=failures-only
  test/reporting test/sales test/shift test/checkout test/tenancy` passed
  **529/529** relevant Flutter tests, including **15** new tests: 10 read-model
  and repository, and 5 panel-widget cases.
- `npm --prefix rules-tests run test:emulator:daily-metrics` passed the focused
  Firestore-only suite **5/5** during development.
- `npm --prefix rules-tests run test:emulator` passed the full Firestore Rules
  suite **71/71** (66 existing plus the 5 new daily-metrics cases).
- `npm --prefix functions test` passed **166/166** Functions tests with the
  pinned Node 24 / Temurin JDK 21 environment. No Functions source changed.
- With `FUNCTIONS_DISCOVERY_TIMEOUT=60`,
  `npm --prefix rules-tests run test:emulator:invitations` passed **12/12** real
  Auth, Firestore, and Functions emulator integration tests.
- `git diff --check` was clean apart from expected Windows line-ending warnings.
  Android build and Android emulator validation were intentionally skipped as
  requested.

Meaningful failures and their resolutions:

- **The frozen path-contract test failed, exactly as it should have.**
  `tenant_paths_test.dart` enumerates every business collection, so adding
  `daily_metrics` broke it until the new segment was declared there too. The
  test was updated deliberately, with a comment recording why the contract
  changed; that guard is working as designed and must not be loosened.
- **A widget test built an owner membership with `isOwner: false`.** Canonical
  access refuses that combination, so the session never opened. The fixture now
  derives `isOwner` from the role.
- **A tenant-switch test completed only the first of several sequential reads.**
  The summary reads one day at a time, so completing the outstanding read once
  left the load unfinished. The test now drains the reads for a business before
  asserting.
- No other test assertion failed; the analyzer and every other command in the
  final sequence were green on their first execution.

The existing user-owned local edits remain separate and must not be staged:

```text
.vscode/settings.json
android/gradle.properties
pubspec.lock dependency-resolution updates for characters, matcher,
material_color_utilities, meta, test_api, and the Dart SDK constraint
```

### Next bounded chunk

Implement only the guarded tenant returns surface, which is the last read-only
operational vertical before any write-capable POS screen:

1. Add a strict read model and guarded repository for
   `tenants/{tenantId}/returns`, deriving every path from `TenantPaths`,
   refusing a return whose sale attribution disagrees, and keeping the
   exact-child, uniqueness, and ordering proofs. Confirm the canonical field
   names against `functions/src/operations/**` before designing the model.
2. Link a sale to the returns recorded against it from the sale-history entry,
   showing verified and pending returns distinctly.
3. Decide and test the returns read boundary in Rules exactly as the last four
   chunks did, including the absent-document case. Remember that a rule
   comparing `resource.data` denies a read of a document that does not exist,
   while a rule comparing a path wildcard or a role does not.
4. Add the composite indexes those pages need, remembering that a descending
   page must carry at least one equality filter.
5. Add unit, widget, and focused Rules emulator coverage for a missing return, a
   wrong-role read, a cross-tenant response, a tenant switch during an
   outstanding page, and a return that names a sale it does not belong to.
6. Leave return **creation** and `verifyReturnAndRestoreStock`, the checkout
   screen and payment flow, receipt printing, product cost/profit fields,
   subscription and branding surfaces, deployment, and Android build/emulator
   validation outside that chunk. This vertical stays read-only.

---

## Guarded returns read surface handoff - 2026-08-01

### Completed in this session

A sale now names the returns recorded against it. This is the last read-only
operational vertical: nothing on this surface creates, verifies, or restores
anything, and no checkout screen, payment flow, receipt printing, or legacy
operational POS route became reachable.

Implemented behavior and safety decisions:

- The schema was read from `functions/src/operations/returns.ts` and `domain.ts`
  rather than invented. `verifyReturnAndRestoreStock` is the only authority on
  this document: it reads `tenantId`, `saleId`, `itemsReturned`, `status`,
  `verified`, and `stockRestored`, and writes back `status`, `verified`,
  `verifiedBy`, `verifiedAt`, `stockRestored`, `stockRestoredAt`,
  `stockRestorationId`, and `updatedAt`. Rules bind `createdBy` and
  `status == 'pending'` on create. Nothing outside that set is modelled.
- `TenantCollection.returns` already existed, so **no path-contract change was
  needed** and the frozen enumeration test was not touched.
- **The terminal state is read from every field the server's own guard
  consults.** The callable refuses to verify when `status` is `verified` or
  `restored`, or when `verified`/`stockRestored` is true, and refuses a `status`
  that is neither absent nor `pending`. A document whose flags disagree - say
  `status: 'pending'` beside `stockRestored: true` - is therefore one the server
  would never verify, so listing it as awaiting verification would invite an
  action that cannot succeed. It fails the page closed instead.
- `restored` is read as the same state as `verified`, because the server's guard
  already treats the two spellings identically.
- A verified return must carry `verifiedBy`, `verifiedAt`, and
  `stockRestorationId`, and a pending one must carry none of them. Those fields
  are written by one server transaction and the client can never write them at
  all, so - unlike the pending-write instants on a sale or a shift - there is no
  state in which one is legitimately missing or legitimately early.
- A line is read as `productId ?? itemId`, exactly as `normalizeReturnStockLines`
  reads it, so the client and the server can never disagree about which product
  a line names. `productName` is an optional label; stock is restored by ID.
- The page always carries `saleId ==` and refuses a returned document naming a
  different sale. The remaining returnable quantity of a sale is computed from
  exactly these records, so a foreign one would misstate it.
- **The Firestore returns read rule was deliberately left as wide as the sale
  rule rather than narrowed like the shift rule.** `assertReturnWithinSale`
  bounds a restoration by the immutable sale minus every prior verified return,
  so the quantity a cashier may still request depends on returns other cashiers
  recorded. Narrowing to `createdBy` would hide that evidence and let one
  cashier record a return the server can never verify. The rule compares a role
  and no document field, so a sale with no returns still answers instead of
  raising an evaluation error. Assertions in both the Rules suite and the Dart
  suite pin the decision so a future narrowing has to change them on purpose.
- `return_verifications` and the resulting stock movements stay denied by the
  tenant catch-all. The return document itself carries the verifier, the
  instant, and the restoration ID, so the ledger behind it needs no client read.
- `firestore.indexes.json` gained `saleId`/`__name__ DESC`, the only index this
  page needs.

Deliberately outside this chunk, and important for the next session:

- There is no business-wide returns list. Every descending page carries an
  equality filter by construction, so a business-wide list would need its own
  deliberate filter, index, and read decision rather than an unfiltered scan.
- The page counts describe that page only. A running total for the sale would be
  a second, weaker aggregate that disagrees at every page boundary; the server
  is the only place the remaining returnable quantity is computed.
- The create rule is still the loose original: it binds only `createdBy` and
  `status == 'pending'`. Tightening it is the next chunk's work, and until then
  the read model is strictly stronger than the rule that admits the document.

Files in this chunk:

```text
docs/frontend_tenant_migration_inventory.md
firestore.indexes.json
firestore.rules
lib/returns/return_history.dart
lib/returns/return_history_panel.dart
lib/returns/returns.dart
lib/sales/sale_history_panel.dart
rules-tests/README.md
rules-tests/package.json
rules-tests/test/tenant-returns.test.js
test/returns/return_history_panel_test.dart
test/returns/return_history_test.dart
test/sales/sale_history_panel_test.dart
PLAN.md
```

Validation evidence after implementation code was frozen:

- `flutter analyze --no-pub lib/returns lib/reporting lib/sales lib/shift
  lib/checkout lib/tenancy test/returns test/reporting test/sales test/shift
  test/checkout test/tenancy` reported no issues.
- `flutter test --no-pub --concurrency=1 --reporter=failures-only test/returns
  test/reporting test/sales test/shift test/checkout test/tenancy` passed
  **553/553** relevant Flutter tests, including **24** new tests: 14 read-model
  and repository, 9 returns-panel widget, and 1 sale-to-returns navigation case.
- `npm --prefix rules-tests run test:emulator:tenant-returns` passed the focused
  Firestore-only suite **6/6** during development.
- `npm --prefix rules-tests run test:emulator` passed the full Firestore Rules
  suite **77/77** (71 existing plus the 6 new returns cases).
- `npm --prefix functions test` passed **166/166** Functions tests. No Functions
  source changed.
- With `FUNCTIONS_DISCOVERY_TIMEOUT=60`,
  `npm --prefix rules-tests run test:emulator:invitations` passed **12/12** real
  Auth, Firestore, and Functions emulator integration tests.
- `git diff --check` was clean apart from expected Windows line-ending warnings.
  Android build and Android emulator validation were intentionally skipped as
  requested.

Meaningful failures and their resolutions:

- **The pinned JDK 21 was gone from this machine.** `C:\tmp\chilltent-jdk21`
  had been cleared, leaving only Temurin 17, and `firebase-tools` refuses any
  Java before 21 outright - a one-line CLI error, not a test failure. Temurin
  21.0.12+8 was reinstalled to the same pinned path before any emulator command
  was retried. Every future session should check that path first rather than
  interpreting the message as a harness fault.
- No test assertion failed. The analyzer and every command in the final sequence
  were green on their first execution.

The existing user-owned local edits remain separate and must not be staged:

```text
.vscode/settings.json
android/gradle.properties
pubspec.lock dependency-resolution updates for characters, matcher,
material_color_utilities, meta, test_api, and the Dart SDK constraint
```

### Next bounded chunk

Implement only guarded return **creation**, which is the first write-capable
operational surface outside checkout, and nothing else:

1. Tighten the `returns` create rule. It currently binds only `createdBy` and
   `status == 'pending'`, so a client may still file a return under another
   business, name no sale, or write an unbounded `itemsReturned`. Bind
   `tenantId`, require a `saleId` string, require a server-owned
   `createdAt == request.time`, require the bounded line shape the way
   `validSaleLines` does, and forbid every verification field on create.
   Remember Firestore's 1000-expression budget and the absence of a list `every`
   operation: cap the line count explicitly, as the sale rule does.
2. Add a guarded write repository that builds the return intent from an
   already-validated `TenantSale` and the existing returns page, so a request
   can never exceed the immutable sale minus the returns already recorded
   against it. That is the same bound `assertReturnWithinSale` applies on the
   server; the client refusing early must not become the only check.
3. Decide and record the create boundary: which roles may record a return at
   all, and whether a cashier may return a colleague's sale. Test whichever
   decision is taken, including the absent-sale case.
4. Add the confirmation UI on the returns route: select lines and quantities
   from the sale, show the remaining returnable quantity per product, and
   require an explicit confirmation. A recorded return must clearly state that
   it has restored no stock yet.
5. Add unit, widget, and focused Rules emulator coverage for an over-quantity
   request, a return against a sale that does not exist, a wrong-role create, a
   forged `createdBy`, a create pre-declaring verification, a cross-tenant
   create, and a tenant switch during an outstanding write.
6. Leave `verifyReturnAndRestoreStock` and every stock-restoring path, the
   checkout screen and payment flow, receipt printing, product cost/profit
   fields, subscription and branding surfaces, deployment, and Android
   build/emulator validation outside that chunk.

---

## Guarded return creation handoff - 2026-08-01

### Completed in this session

A return can now be recorded from the sale it reverses. This is the first
write-capable operational surface outside checkout. It restores no stock, calls
no callable, and makes no legacy operational POS route reachable.

Implemented behavior and safety decisions:

- **The create rule was tightened from two conditions to a frozen contract.** It
  previously bound only `createdBy` and `status == 'pending'`, so a client could
  file a return under another business, name no sale, choose its own instant, or
  write an unbounded `itemsReturned`. It now also binds the document ID into the
  document, binds `tenantId`, requires `createdAt == request.time`, requires a
  3-500 character `reason`, and freezes the key set with `hasOnly` so no
  verification field and no unknown field can be smuggled in beside the request.
- `itemsReturned` **reuses `validSaleLines`**. A return line and a sale line are
  the same shape by construction, and a return can never carry more lines than
  the sale it reverses, which is capped at the same sixteen. Reusing the
  function keeps the two contracts identical rather than nearly identical.
- **The named sale must exist.** The verification callable reads the immutable
  sale to bound the restoration, so a return filed against nothing could never
  be verified. One `exists()` keeps that record out of the business entirely.
- **Recording and verifying are deliberately separate privileges.** Every active
  member may record a pending return - recording changes no stock - while
  restoration stays in the owner/admin/manager-only callable. A customer returns
  to whoever is at the till, so a cashier may record a return against a
  colleague's sale, and `createdBy` records who did.
- **The client subtracts pending returns as well as verified ones.** The
  server's `assertReturnWithinSale` counts only verified restorations. Two
  pending returns that each fit on their own can jointly exceed the sale, and
  the second verification would then fail with the customer already gone. The
  client bound is tighter on purpose and is never the only check.
- **An incomplete returns page refuses to produce a returnable quantity at
  all.** A partial list would overstate what is left, which is the one number
  this surface exists to state, so the record form is offered only on a first
  page with nothing behind it and says so otherwise.
- **The document ID is deterministic.** It hashes `tenantId`, `saleId`, the
  actor, and one request ID per confirmation intent - the same scoping the
  backend's idempotency keys use - so a double submit addresses one document and
  the create-only rule refuses the replay. The request ID is retained **only**
  across an ambiguous result: a rejected or unattempted write left nothing
  behind, and reusing its ID would deny an edited retry as a duplicate.
- An ambiguous write tells the user to reload rather than record again, and
  `TenantReturnRequestRepository.readReturn` settles it by exact path.
- The read model was tightened to exactly what the create rule now freezes:
  `returnId` must match its own path and `reason` is required. A return without
  a recorded reason is not auditable.
- The writer is injected from the composition root through the shift-history and
  sale-history routes. While it is absent every one of those routes is read-only,
  which is the same pattern the shift history and daily summary already use.

Deliberately outside this chunk, and important for the next session:

- Nothing calls `verifyReturnAndRestoreStock`. A recorded return stays pending
  forever until that chunk lands, and both the panel and the notice say so.
- The returns route is reachable only through shift history to sale history. A
  direct "find a receipt" entry point does not exist yet.

Files in this chunk:

```text
docs/frontend_tenant_migration_inventory.md
firestore.rules
lib/main.dart
lib/returns/return_history.dart
lib/returns/return_history_panel.dart
lib/returns/return_request.dart
lib/returns/returns.dart
lib/sales/sale_history_panel.dart
lib/shift/shift_history_panel.dart
lib/shift/shift_panel.dart
rules-tests/README.md
rules-tests/test/tenant-returns.test.js
test/returns/return_history_panel_test.dart
test/returns/return_history_test.dart
test/returns/return_request_test.dart
PLAN.md
```

Validation evidence after implementation code was frozen:

- `flutter analyze --no-pub lib/returns lib/reporting lib/sales lib/shift
  lib/checkout lib/tenancy test/returns test/reporting test/sales test/shift
  test/checkout test/tenancy` reported no issues. `lib/main.dart` still carries
  one pre-existing `profilesSampleRate is experimental` Sentry warning, which
  this chunk did not introduce and did not touch.
- `flutter test --no-pub --concurrency=1 --reporter=failures-only test/returns
  test/reporting test/sales test/shift test/checkout test/tenancy` passed
  **577/577** relevant Flutter tests, including **24** new tests: 18 request,
  intent, writer and settlement cases, and 6 record-form widget cases.
- `npm --prefix rules-tests run test:emulator:tenant-returns` passed the focused
  Firestore-only suite **9/9** during development.
- `npm --prefix rules-tests run test:emulator` passed the full Firestore Rules
  suite **80/80** (77 existing plus 3 new create-contract cases).
- `npm --prefix functions test` passed **166/166** Functions tests. No Functions
  source changed.
- With `FUNCTIONS_DISCOVERY_TIMEOUT=60`,
  `npm --prefix rules-tests run test:emulator:invitations` passed **12/12** real
  Auth, Firestore, and Functions emulator integration tests.
- `git diff --check` was clean apart from expected Windows line-ending warnings.
  Android build and Android emulator validation were intentionally skipped.

Meaningful failures and their resolutions:

- **A panel-level `setState` was silently restarting the guarded load and
  wiping the half-filled form.** `TenantRouteGuard` restarts whenever its loader
  changes identity - which is how a new loader is stopped from serving an old
  page - and a closure rebuilt on every frame changes identity every frame. The
  busy flag and the result notice therefore discarded the user's selected
  quantities and reason. The loader is now cached against the same key the guard
  is keyed by, so a rebuild reuses it and only a real page change reloads. Any
  future panel that keeps local state beside a guard needs the same treatment.
- **`scrollUntilVisible` stopped working once the form added a text field.** It
  resolves `find.byType(Scrollable)` to exactly one widget, and an `EditableText`
  carries its own. The returns widget tests now use a tall test surface instead,
  which builds every row. This is the second list-layout trap in these panels,
  after the shift-history pagination one.
- **A tenant switch during an outstanding returns page revealed a stronger
  invariant than the test asserted.** The route is opened for a sale in one
  business, so after a switch the new session cannot answer it at all and
  `describeReturnable` refuses the foreign sale. The test now asserts the
  fail-closed state rather than the next business's page, which is the correct
  behavior: another business's returns must never appear under that receipt.
- No other test assertion failed.

The existing user-owned local edits remain separate and must not be staged:

```text
.vscode/settings.json
android/gradle.properties
pubspec.lock dependency-resolution updates for characters, matcher,
material_color_utilities, meta, test_api, and the Dart SDK constraint
```

### Next bounded chunk

Implement only guarded return **verification**, which closes the returns
vertical, and nothing else:

1. Add a session-bound gateway for `verifyReturnAndRestoreStock` following the
   existing callable-gateway pattern (`lib/tenancy/tenant_staff_status.dart` is
   the closest model): derive the tenant from one captured live session, accept
   only a decoded `TenantReturn` as the target, create one request ID per
   confirmation intent, preserve it across a recoverable retry, and strictly
   decode the `{returnId, verificationId, restoredProducts}` response.
2. Offer the action on the returns route for owner/admin/manager only, on a
   pending return only, behind an explicit confirmation that names the exact
   products and units whose stock will be restored. A verified return must never
   offer it again.
3. Reconcile the response with the record: refuse a response naming a different
   return, and re-read the return by exact path after success so the surface
   shows the server's own verification evidence rather than an optimistic local
   state.
4. Decide and test what happens when the callable refuses - already verified, a
   quantity exceeding the immutable sale, a missing product, a missing sale -
   and make each refusal a distinct, actionable message rather than one generic
   failure. `functions/src/operations/returns.ts` names every case.
5. Add unit and widget coverage for a wrong-role attempt, an already-verified
   return, a refused call, an ambiguous call, a tenant switch during an
   outstanding call, and a response that names another return.
6. Leave the checkout screen and payment flow, receipt printing, product
   cost/profit fields, `getSalesComparison`, subscription and branding surfaces,
   deployment, and Android build/emulator validation outside that chunk.

---

## Guarded return verification handoff - 2026-08-01

### Completed in this session

The returns vertical is closed: a pending return can now be verified, which is
the only path in the app that increases stock. This chunk adds no checkout
screen or payment flow, no receipt printing, no `getSalesComparison` call, and
makes no legacy operational POS route reachable.

Implemented behavior and safety decisions:

- `TenantReturnVerificationGateway` follows the established callable-gateway
  pattern: the tenant comes from one captured live session and the return from
  one already-decoded canonical record, so nothing on the screen can name either.
  It is owner/admin/manager-only, which is exactly what the callable enforces.
- **One intent keeps one request ID across a retry**, so the server's own
  idempotency record settles a repeated attempt rather than restoring twice.
- **A verified return is terminal.** `canVerify` refuses it before any call, and
  the action is never rendered for it.
- **The response is reconciled against the record, not merely parsed.** It must
  name that return, restore exactly the products and units the return itself
  records - no extra product, no missing one, no different quantity - and its own
  `previousQuantity + quantityRestored == quantity` arithmetic is re-derived. A
  response that does not add up cannot describe a stock movement that happened,
  and this is the screen that states what moved. A negative `previousQuantity` is
  accepted: checkout may legitimately drive stock negative.
- **Each server refusal is a distinct, actionable outcome.** The code decides;
  `failed-precondition` covers several server conditions, so those are separated
  by the exact wording `functions/src/operations/returns.ts` raises. If that
  wording ever changes the case degrades to a truthful generic refusal - the
  classification only ever words a message, it never decides whether to retry.
- **Only an unknown outcome may have committed.** `mayHaveCommitted` is true for
  exactly one failure, and the panel responds to it by reloading rather than
  retrying. An unusable response is treated the same way, because the call may
  well have restored stock even when its answer could not be trusted.
- After success the page is re-read, so what is shown is the server's own
  verification evidence rather than optimistic local state.
- The confirmation names the exact products and units whose stock will move, and
  says it cannot be undone from this app.
- The two threaded capabilities were folded into one injected
  `TenantReturnActions`. Whatever is absent stays unavailable, so a route with no
  actions is exactly the read-only surface it was two chunks ago.

Deliberately outside this chunk, and important for the next session:

- Restoration cannot be reversed from the app. Correcting an over-restoration
  needs `adjustStock`, which no surface calls yet.
- The returns route is still reachable only through shift history to sale
  history. No "find a receipt" entry point exists.
- No Firestore Rules change was needed: verification writes are server-only and
  already denied to every client, which the existing suite proves.

Files in this chunk:

```text
docs/frontend_tenant_migration_inventory.md
lib/main.dart
lib/returns/return_actions.dart
lib/returns/return_history_panel.dart
lib/returns/return_verification.dart
lib/returns/returns.dart
lib/sales/sale_history_panel.dart
lib/shift/shift_history_panel.dart
lib/shift/shift_panel.dart
test/returns/return_history_panel_test.dart
test/returns/return_verification_test.dart
PLAN.md
```

Validation evidence after implementation code was frozen:

- `flutter analyze --no-pub lib/returns lib/reporting lib/sales lib/shift
  lib/checkout lib/tenancy test/returns test/reporting test/sales test/shift
  test/checkout test/tenancy` reported no issues.
- `flutter test --no-pub --concurrency=1 --reporter=failures-only test/returns
  test/reporting test/sales test/shift test/checkout test/tenancy` passed
  **593/593** relevant Flutter tests, including **16** new tests: 10 gateway and
  response-decoding cases and 6 verification-widget cases.
- `npm --prefix rules-tests run test:emulator` passed the full Firestore Rules
  suite **80/80**, unchanged: verification writes are server-only and the
  existing returns cases already prove no client may make them.
- `npm --prefix functions test` passed **166/166** Functions tests. No Functions
  source changed.
- With `FUNCTIONS_DISCOVERY_TIMEOUT=60`,
  `npm --prefix rules-tests run test:emulator:invitations` passed **12/12** real
  Auth, Firestore, and Functions emulator integration tests.
- `git diff --check` was clean apart from expected Windows line-ending warnings.
  Android build and Android emulator validation were intentionally skipped.

Meaningful failures and their resolutions:

- No test assertion failed. The analyzer and every command in the final sequence
  were green on their first execution.

The existing user-owned local edits remain separate and must not be staged:

```text
.vscode/settings.json
android/gradle.properties
pubspec.lock dependency-resolution updates for characters, matcher,
material_color_utilities, meta, test_api, and the Dart SDK constraint
```

### Next bounded chunk

Implement only the guarded receipt lookup that makes the returns vertical
reachable without walking through shift history, and nothing else:

1. Add a bounded, guarded lookup from a receipt number to its sale. The receipt
   encodes the device code, the business date, and the sequence, and
   `checkout_receipt.dart` already owns that format - parse with it rather than
   with new string handling, and refuse a malformed receipt before any read.
2. Decide how the sale is found. `receiptNumber` is not indexed and the sale
   document ID is the checkout ID, not the receipt, so this needs either a new
   equality filter plus index or a deliberate narrowing (for example
   `businessDate` plus `soldById`). Confirm what `firestore.indexes.json` and
   the sale read rule already allow before designing the query; remember a
   descending page must carry at least one equality filter.
3. Reach it from the tenant-safe landing route behind `TenantRouteGuard`,
   deciding and recording which roles may look up a receipt they did not issue.
   The sale read rule is already business-wide; the screen decision is separate.
4. From a found sale, open the existing sale detail and returns routes, so the
   record/verify flow this session built is reachable from a customer's receipt.
5. Add unit, widget, and focused Rules emulator coverage for a malformed
   receipt, a receipt with no matching sale, a receipt matching a sale in
   another business, a wrong-role lookup, and a tenant switch during a lookup.
6. Leave the checkout screen and payment flow, receipt printing, `adjustStock`
   and every other stock mutation, product cost/profit fields,
   `getSalesComparison`, subscription and branding surfaces, deployment, and
   Android build/emulator validation outside that chunk.

---

## Guarded receipt lookup handoff - 2026-08-01

### Completed in this session

A customer's receipt now reaches its sale directly from the tenant-safe landing
route, so the record-and-verify returns flow no longer requires walking through
shift history. This chunk adds no checkout screen or payment flow, no receipt
printing, no stock mutation beyond the verification already landed, and makes no
legacy operational POS route reachable.

Implemented behavior and safety decisions:

- **The receipt is parsed by `checkout_receipt.dart`, which owns the frozen
  format.** `TenantReceiptQuery` reuses `checkoutReceiptNumberPattern` and
  `validateCheckoutBusinessDate` rather than re-implementing the shape, so the
  lookup and the issuing device can never disagree about what a receipt is. A
  malformed receipt - wrong prefix, non-hex device code, a date like `20260231`,
  or a zero sequence that was never issued - is refused before any read, because
  it is a typing mistake rather than a query.
- **The query is an equality filter on `receiptNumber` with the default
  ascending key order, so it needs no composite index.** Firestore's automatic
  single-field index serves it, and the focused emulator suite issues the exact
  client query so a future regression is caught there rather than in production.
  A descending page would have needed a composite index and bought nothing.
- **A colliding receipt is reported, not resolved.** The device code is a
  three-character digest, so two devices can share one and receipt uniqueness is
  device-local - a limitation the rules README already records. Picking a sale
  would attribute a return to the wrong till, so up to five matches are listed
  and the screen says why. A unit test derives a genuinely colliding
  installation ID rather than contriving one.
- A returned sale must carry the exact requested receipt. The sale model already
  re-derives the receipt from the sale's own device, business date, and
  sequence, so this second comparison proves a transport that ignored the filter
  cannot answer with a different customer's sale.
- **Every active member may look a receipt up.** The sale read rule is already
  business-wide, and a receipt lookup is the counter operation a customer
  initiates: whoever is at the till must find it. Recording a return from it is
  open to the same roles; restoring stock stays management-only.
- Opening the route issues no read at all. Nothing is queried until a receipt is
  submitted, and one loader is cached per submitted receipt so a rebuild does
  not re-issue it - the same trap that had to be fixed for the returns panel.
- `main.dart` now builds one `TenantReturnActions` and shares it between the
  shift-history route and the receipt lookup, so both reach the same returns
  surface with the same capabilities.

Deliberately outside this chunk, and important for the next session:

- There is still no way to correct an over-restoration from the app;
  `adjustStock` remains uncalled.
- The lookup finds one receipt at a time. There is no browse-by-day sales list,
  which would need its own filter, index, and read decision.

Files in this chunk:

```text
docs/frontend_tenant_migration_inventory.md
lib/main.dart
lib/sales/receipt_lookup.dart
lib/sales/receipt_lookup_panel.dart
lib/sales/sales.dart
lib/tenancy/tenant_routing_shell.dart
rules-tests/README.md
rules-tests/package.json
rules-tests/test/receipt-lookup.test.js
test/sales/receipt_lookup_panel_test.dart
test/sales/receipt_lookup_test.dart
PLAN.md
```

Validation evidence after implementation code was frozen:

- `flutter analyze --no-pub lib/returns lib/reporting lib/sales lib/shift
  lib/checkout lib/tenancy test/returns test/reporting test/sales test/shift
  test/checkout test/tenancy` reported no issues. `lib/main.dart` still carries
  only the pre-existing `profilesSampleRate is experimental` Sentry warning.
- `flutter test --no-pub --concurrency=1 --reporter=failures-only test/returns
  test/reporting test/sales test/shift test/checkout test/tenancy` passed
  **611/611** relevant Flutter tests, including **18** new tests: 10 receipt
  query and repository cases and 8 lookup-panel widget cases.
- `npm --prefix rules-tests run test:emulator:receipt-lookup` passed the focused
  Firestore-only suite **4/4** during development.
- `npm --prefix rules-tests run test:emulator` passed the full Firestore Rules
  suite **84/84** (80 existing plus the 4 new receipt-lookup cases).
- `npm --prefix functions test` passed **166/166** Functions tests. No Functions
  source changed in any of this session's four chunks.
- With `FUNCTIONS_DISCOVERY_TIMEOUT=60`,
  `npm --prefix rules-tests run test:emulator:invitations` passed **12/12** real
  Auth, Firestore, and Functions emulator integration tests.
- `firestore.indexes.json` parsed as valid JSON, and `git diff --check` was
  clean apart from expected Windows line-ending warnings. Android build and
  Android emulator validation were intentionally skipped as requested.

Meaningful failures and their resolutions:

- No test assertion failed. The analyzer and every command in the final sequence
  were green on their first execution.

The existing user-owned local edits remain separate and must not be staged:

```text
.vscode/settings.json
android/gradle.properties
pubspec.lock dependency-resolution updates for characters, matcher,
material_color_utilities, meta, test_api, and the Dart SDK constraint
```

### Next bounded chunk

Implement only the guarded stock adjustment surface, which is the correction
path every restored-stock mistake currently has no answer for, and nothing else:

1. Add a session-bound gateway for `adjustStock` following the
   `verifyReturnAndRestoreStock` gateway landed this session: derive the tenant
   from one captured live session and the product from one already-decoded
   catalog record, create one request ID per confirmation intent, preserve it
   across a recoverable retry, and strictly decode the
   `{adjustmentId, productId, previousQuantity, quantity, quantityDelta}`
   response, re-deriving its arithmetic rather than trusting it.
2. Offer it to owner/admin/manager only, which is what the callable enforces.
   Require the typed adjustment `type` and a normalized reason; the server's
   `assertAdjustmentDirection` binds `restock`/`opening_balance` to a positive
   delta and `damage`/`waste` to a negative one, so the UI must not offer a
   combination the server will refuse.
3. Reach it from the existing read-only catalog route, on one product at a time.
   Show the current quantity as recorded, never a locally derived one, and state
   that stock may legitimately be negative.
4. Add a guarded read of that product's `stock_movements` so an adjustment can
   be seen in context. That subcollection is currently denied by the tenant
   catch-all, so this needs a deliberate Rules decision and its own focused
   emulator suite - remember an absent document must still answer.
5. Add unit, widget, and focused Rules emulator coverage for a wrong-role
   attempt, a refused direction, a malformed response, an ambiguous call, a
   tenant switch during an outstanding call, and a movement page that crosses
   tenants.
6. Leave the checkout screen and payment flow, receipt printing, product
   cost/profit fields, `getSalesComparison`, subscription and branding surfaces,
   deployment, and Android build/emulator validation outside that chunk.

---

## Guarded stock adjustment surface handoff - 2026-08-01

### Completed in this session

A restored-stock mistake finally has a correction path. The read-only catalog
now opens one product at a time onto a management-only surface that states the
stock the server recorded, pages the server-written ledger that explains it, and
corrects it through `adjustStock`. This chunk adds no checkout screen or payment
flow, no receipt printing, no product cost or profit surface, no
`getSalesComparison`, and makes no legacy operational POS route reachable.

Implemented behavior and safety decisions:

- `TenantStockAdjustmentGateway` is session- and product-bound, following the
  `verifyReturnAndRestoreStock` gateway landed in the previous session. The
  tenant comes from one captured live session and the product from one
  already-decoded `TenantProduct`, so no caller can name either. A product
  decoded in another business is refused before any call, which is why
  `TenantProduct` now carries the `tenantId` its own path encodes.
- **Every local refusal mirrors one the server performs**, so a mistake an
  operator can fix is reported on the form instead of costing a round trip and
  an idempotency record: a non-zero delta bounded by the server's
  `MAX_QUANTITY_DELTA`, the direction `assertAdjustmentDirection` binds, and the
  exact reason normalization `normalizeReason` applies - trimmed length checked
  first, whitespace runs collapsed afterwards, control characters refused. The
  normalized reason is what is sent, so what an operator confirmed is what the
  immutable record stores.
- **The UI never offers a combination the server refuses.** `restock` and
  `opening_balance` only add, `damage` and `waste` only remove, and only
  `inventory_count` and `correction` show a direction control. Choosing a
  removal-only type states the direction rather than asking for it.
- One request ID per confirmation intent, preserved **only** across an unknown
  outcome. Every other refusal is proof that nothing moved and releases the ID,
  so an edited retry is a new operation instead of failing as a duplicate;
  `already-exists` is classified as its own `duplicateRequest` outcome rather
  than as an unknown one, because it proves an earlier attempt settled and this
  one did not.
- The `{adjustmentId, productId, previousQuantity, quantity, quantityDelta}`
  response is reconciled against the intent: it must name that product, apply
  exactly that change, and `quantity == previousQuantity + quantityDelta` is
  re-derived rather than trusted. A response that cannot be trusted reports that
  the call may still have moved stock and reloads, because only the server can
  say.
- **`stock_movements` was a deliberate Rules decision, not an omission.** The
  subcollection was denied outright by the tenant catch-all. The read is now
  `owner/admin/manager` - narrower than the product document a cashier reads,
  because the current quantity is operational information every member needs at
  the till while the ledger names damage, waste, corrections, and who recorded
  them. That is management information in exactly the way `daily_metrics` is,
  and it is the same set of roles `adjustStock` enforces, so the surface that
  explains a stock figure and the surface that changes it agree. The role check
  touches no document field, so an absent movement and an empty ledger still
  answer. Writing stays server-only.
- `TenantProductStockRepository` re-reads the canonical product document on
  every page, so the quantity shown is always the server's most recent one
  rather than a figure carried between screens or derived from the ledger below
  it. A cashier is refused as `stock_ledger_forbidden` before any read is
  issued, and an absent product is reported rather than shown as an empty
  ledger.
- **The ledger page is ascending by document ID and is never presented as
  chronological.** A movement ID is a digest for an adjustment and
  `sale_{saleId}` for a sale, so document order carries no time information at
  all; each entry states its own recorded instants instead. Ascending order also
  keeps the page servable by Firestore's automatic index, so **no new composite
  index was needed** - a descending page would have required a filter and a
  composite index and bought nothing.
- The read model handles the three shapes the server actually writes. Only the
  writers that read the product inside their transaction record a before and
  after, so `previousQuantity`/`quantityAfter` are present or absent as a whole
  and must add up when present; a reconciled sale carries neither, which the
  screen names rather than filling in. An unmodelled `sourceType` degrades to
  `other` and is displayed verbatim: a server deploy adding a source is not
  evidence of anything wrong, and taking a working ledger down for it would be
  worse than naming it honestly.
- `TenantReadRepository` gained `readProductSubcollectionPage`, sharing one
  private page implementation with `readCollectionPage`, so the exact-child,
  uniqueness, page-size, and ordering proofs apply unchanged. It is deliberately
  `async` so an invalid product ID is a failed future like every other refusal
  there rather than a synchronous throw.
- The entry point is a tap on a catalog product, and it exists only when the
  composition root supplies a route **and** the guarded session allows the role.
  The route opens under the same `TenantSessionScope`, so a tenant switch
  invalidates it exactly as it does every other guarded route. Tenancy keeps
  owning routing: `main.dart` passes the builder through
  `TenantRoutingShell`/`TenantSafeLandingScreen` as the daily-summary and
  receipt-lookup routes already are.

Deliberately outside this chunk, and important for the next session:

- The ledger is per product and per page. There is no business-wide adjustment
  feed, and the tenant-level `stock_adjustments` and `audit_logs` collections
  stay unreachable from the app.
- An adjustment cannot be undone. Correcting one means recording another, which
  the confirmation dialog says outright.
- The screen shows the recorded quantity and the ledger side by side but never
  reconciles them: the ledger page is bounded, so a sum over it would be a
  second, weaker aggregate. That is reconciliation's job.

Files in this chunk:

```text
docs/frontend_tenant_migration_inventory.md
firestore.rules
lib/inventory/inventory.dart
lib/inventory/stock_actions.dart
lib/inventory/stock_adjustment.dart
lib/inventory/stock_adjustment_panel.dart
lib/inventory/stock_movements.dart
lib/main.dart
lib/tenancy/tenant_catalog.dart
lib/tenancy/tenant_paths.dart
lib/tenancy/tenant_repository.dart
lib/tenancy/tenant_routing_shell.dart
rules-tests/README.md
rules-tests/package.json
rules-tests/test/stock-movements.test.js
test/inventory/stock_adjustment_panel_test.dart
test/inventory/stock_adjustment_test.dart
test/inventory/stock_movements_test.dart
test/tenancy/tenant_catalog_test.dart
test/tenancy/tenant_paths_test.dart
test/tenancy/tenant_repository_test.dart
PLAN.md
```

Validation evidence after implementation code was frozen:

- `flutter analyze --no-pub lib/inventory lib/returns lib/reporting lib/sales
  lib/shift lib/checkout lib/tenancy test/inventory test/returns test/reporting
  test/sales test/shift test/checkout test/tenancy` reported no issues.
- `flutter test --no-pub --concurrency=1 --reporter=failures-only test/inventory
  test/returns test/reporting test/sales test/shift test/checkout test/tenancy`
  passed **653/653** relevant Flutter tests, including **42** new tests: 15
  adjustment-gateway and response cases, 10 movement read-model and repository
  cases, 11 stock-panel widget cases, 3 base-repository subcollection cases, 1
  tenant-path case, and 2 catalog cases.
- `npm --prefix rules-tests run test:emulator:stock-movements` passed the
  focused Firestore-only suite **6/6** during development.
- `npm --prefix rules-tests run test:emulator` passed the full Firestore Rules
  suite **90/90** (84 existing plus the 6 new stock-movement cases).
- `npm --prefix functions test` passed **166/166** Functions tests with the
  pinned Node 24 / Temurin JDK 21 environment. No Functions source changed.
- With `FUNCTIONS_DISCOVERY_TIMEOUT=60`,
  `npm --prefix rules-tests run test:emulator:invitations` passed **12/12** real
  Auth, Firestore, and Functions emulator integration tests.
- `git diff --check` was clean apart from expected Windows line-ending warnings.
  No index change was needed, so `firestore.indexes.json` was not touched.
  Android build and Android emulator validation were intentionally skipped as
  requested.

Meaningful failures and their resolutions:

- **`firebase emulators:exec` refused to start on the ambient JRE.** The shell's
  default Java is older than 21, and firebase-tools now hard-fails on that. The
  pinned `D:\firebase-emulator-tools\jdk21\jdk-21.0.12+8` and the portable
  Node 24 must be put on `PATH` for every emulator command in a fresh shell;
  the previous handovers recorded the toolchain but not that the ambient JRE
  wins by default.
- **A refused-then-retried adjustment reused its request ID in a widget test.**
  Calling `pumpWidget` twice with the same unkeyed panel updates the existing
  element, so `State` - and the retained request ID - survived what the test
  intended as a fresh screen. The retry contract is now two separate tests, one
  per outcome class. Worth remembering for every future panel test that wants a
  clean state.
- **A staff-name assertion expected a colleague's label for the signed-in
  user.** `tenantStaffLabel` renders the actor's own UID as `You (Amina)`, which
  is correct; the expectation was wrong and now documents that.
- **An invalid product ID threw synchronously out of the new subcollection
  page.** The path was derived in argument position, outside the `async` body,
  so an awaiting caller would have had to guard it separately from every other
  refusal. The method is now `async`.
- No other test assertion failed; the analyzer and every other command in the
  final sequence were green on their first execution.

The existing user-owned local edits remain separate and must not be staged:

```text
.vscode/settings.json
android/gradle.properties
pubspec.lock dependency-resolution updates for characters, matcher,
material_color_utilities, meta, test_api, and the Dart SDK constraint
```

### Next bounded chunk

Implement only the guarded business-wide stock adjustment feed and the
tenant-level records this chunk deliberately left unreachable, and nothing else:

1. Add a strict read model and guarded repository for
   `tenants/{tenantId}/stock_adjustments`: bounded, indexed, ordered pages of
   the manual adjustments recorded across the business, plus a page filtered to
   one product. Reuse the field set `functions/src/operations/stock.ts` writes,
   refuse a record whose `productId`, `quantityDelta`, or before/after figures
   disagree with themselves, and keep the exact-child, uniqueness, and ordering
   proofs.
2. Decide and test the `stock_adjustments` read boundary in Rules exactly as
   this chunk did for `stock_movements`. That collection is currently denied by
   the tenant catch-all, so it needs a deliberate decision and its own focused
   emulator suite - remember an absent document must still answer, and that a
   descending page needs an equality filter and a composite index.
3. Add the composite indexes those queries need and prove each query is servable
   by issuing the exact client query in the emulator suite, as the receipt
   lookup and the descending key-scan discovery already required.
4. Reach it from the read-only catalog route as a business-wide sibling of the
   per-product ledger, resolving actor UIDs through the existing
   `TenantStaffNameResolver` rather than a new lookup.
5. Add unit, widget, and focused Rules emulator coverage for pagination
   boundaries, a cross-tenant response, a wrong-role read, a tenant switch
   during an outstanding page, and an adjustment record that contradicts itself.
6. Leave the checkout screen and payment flow, receipt printing, product
   cost/profit fields, `getSalesComparison`, tenant-level `audit_logs`,
   subscription and branding surfaces, deployment, and Android build/emulator
   validation outside that chunk.

---

## Guarded business-wide stock adjustment feed handoff - 2026-08-01

### Completed in this session

The corrections a business records are now readable as a business, not only one
product at a time. The read-only catalog opens a management-only feed of every
manual `adjustStock` correction the server recorded, and the per-product stock
route opens the same feed narrowed to that product. This chunk adds no checkout
screen or payment flow, no receipt printing, no product cost or profit surface,
no `getSalesComparison`, no `audit_logs` surface, and makes no legacy
operational POS route reachable.

Implemented behavior and safety decisions:

- `TenantStockAdjustmentRecord` decodes what
  `functions/src/operations/stock.ts` writes and is the only authority on those
  field names. **Unlike the per-product ledger, a missing before or after is
  refused rather than tolerated**: `adjustStock` reads the product inside its
  own transaction, so every adjustment records both figures, and there is no
  shape here that legitimately omits one the way a reconciled sale movement
  does. `quantityAfter == previousQuantity + quantityDelta` is re-derived, and a
  record that cannot explain its own change is refused rather than listed as
  evidence.
- **The record does not repeat its own ID** - only the `stock_movements` entry
  below the product carries `movementId` - so its path is the one authority on
  which adjustment it is. The business it names must still agree with the path
  it was read from, and `productId`, `actorUid`, and `reason` are required
  because every real record carries them.
- An unmodelled `adjustmentType` degrades to a null typed category and is
  displayed verbatim, exactly as an unmodelled movement `sourceType` is: a
  server deploy adding a category is not evidence of anything wrong, and hiding
  a real correction would be worse than naming it honestly. `sourceType` is
  decoded rather than pinned to `manual_adjustment` for the same reason.
- **`stock_adjustments` was a deliberate Rules decision, not an omission.** The
  collection was denied outright by the tenant catch-all. The read is now
  `owner/admin/manager` - the same set `adjustStock` enforces and the same set
  that reads a product's ledger, so the surface that records a correction, the
  surface that explains one product's stock figure, and the surface that lists
  every correction agree about who may see them. It is deliberately **wider than
  `audit_logs`**, which stays owner/admin: that collection is the whole
  business's event trail, while this one is only the stock corrections a manager
  both records and answers for. The role check touches no document field, so an
  absent adjustment, an uncorrected product, and a business that has never
  corrected stock all still answer. Writing stays server-only.
- **Both pages are ascending by document ID and neither needed a composite
  index.** An adjustment ID is `sa_` plus a digest of the actor, operation,
  tenant, and request ID, so document order carries no time information at all;
  each record states its own recorded instant and the screen says outright that
  the list is not time order. The business-wide page carries no filter and the
  product page carries exactly one `productId ==` equality on the same ascending
  key order, both of which Firestore's automatic single-field index serves. A
  descending page would have required a filter and a composite index and bought
  nothing but a different arbitrary order, so `firestore.indexes.json` was not
  touched.
- A page narrowed to one product that answers with another product's correction
  fails closed as `foreign_product_adjustment`, and a cross-tenant response
  fails closed, because a filtered page returning foreign rows is a broken
  boundary rather than rows to skip past. A product filter that is not a
  document ID is refused before any query is issued.
- A cashier is refused as `stock_adjustments_forbidden` before any read is
  issued, so a role that may not see the corrections never reaches the server.
- The feed is reached from the read-only catalog when the composition root
  supplies a route **and** the guarded session allows the role, exactly as the
  per-product stock route already is. Tenancy keeps owning routing: `main.dart`
  passes the builder through `TenantRoutingShell` and `TenantSafeLandingScreen`
  into `TenantCatalogScreen`. The product-narrowed entry point needs no
  injection at all - both surfaces belong to the inventory domain, so the stock
  route opens it directly under its own session scope.
- Every route opens under the caller's `TenantSessionScope`, so a tenant switch
  during an outstanding page discards it before it can label another business's
  screen, which the widget suite proves.
- Actor UIDs are resolved through the existing `TenantStaffNameResolver` rather
  than a new lookup, one resolver per session epoch, degrading to the
  authoritative UID. Product names are deliberately **not** resolved: that would
  be one more document read per row for a label, and the product ID is the
  identity every other record is attributed by.

Deliberately outside this chunk, and important for the next session:

- The feed lists only manual corrections. Sales and verified returns move stock
  too, and the screen says so rather than implying this is every movement.
- Nothing on the surface can record, amend, or undo an adjustment. Correcting
  one still means recording another through the per-product route.
- The tenant-level `audit_logs` collection is readable by Rules but still has no
  client surface, and no business-wide movement or reconciliation feed exists.

Files in this chunk:

```text
docs/frontend_tenant_migration_inventory.md
firestore.rules
lib/inventory/inventory.dart
lib/inventory/stock_adjustment_feed.dart
lib/inventory/stock_adjustment_feed_panel.dart
lib/inventory/stock_adjustment_panel.dart
lib/main.dart
lib/tenancy/tenant_catalog.dart
lib/tenancy/tenant_paths.dart
lib/tenancy/tenant_routing_shell.dart
rules-tests/README.md
rules-tests/package.json
rules-tests/test/stock-adjustments.test.js
test/inventory/stock_adjustment_feed_panel_test.dart
test/inventory/stock_adjustment_feed_test.dart
test/inventory/stock_adjustment_panel_test.dart
test/tenancy/tenant_catalog_test.dart
test/tenancy/tenant_paths_test.dart
PLAN.md
```

Validation evidence after implementation code was frozen:

- `flutter analyze --no-pub lib/inventory lib/returns lib/reporting lib/sales
  lib/shift lib/checkout lib/tenancy lib/main.dart test/inventory test/returns
  test/reporting test/sales test/shift test/checkout test/tenancy` reported one
  pre-existing issue and nothing else: the Sentry `profilesSampleRate`
  experimental warning at `lib/main.dart:27`, which this chunk does not touch.
  Earlier handovers scoped the command without `lib/main.dart`, which is why it
  had not been reported before. Analyzing all of `lib` and `test` still reports
  the 477 known issues in the disabled legacy screens, services, widgets, and
  `test/widget_test.dart`; none is in a migrated surface.
- `flutter test --no-pub --concurrency=1 --reporter=failures-only test/inventory
  test/returns test/reporting test/sales test/shift test/checkout test/tenancy`
  passed **674/674** relevant Flutter tests, including **21** new tests: 5
  adjustment read-model cases, 7 feed-repository cases, 7 feed-panel widget
  cases, 1 product-stock-route entry-point case, and 1 catalog case.
- `npm --prefix rules-tests run test:emulator:stock-adjustments` passed the
  focused Firestore-only suite **6/6** during development.
- `npm --prefix rules-tests run test:emulator` passed the full Firestore Rules
  suite **96/96** (90 existing plus the 6 new stock-adjustment cases).
- `npm --prefix functions test` passed **166/166** Functions tests with the
  pinned Node 24 / Temurin JDK 21 environment. No Functions source changed.
- With `FUNCTIONS_DISCOVERY_TIMEOUT=60`,
  `npm --prefix rules-tests run test:emulator:invitations` passed **12/12** real
  Auth, Firestore, and Functions emulator integration tests.
- `git diff --check` was clean. No index change was needed, so
  `firestore.indexes.json` was not touched. Android build and Android emulator
  validation were intentionally skipped as requested.

Meaningful failures and their resolutions:

- No test assertion failed. Every command in the final sequence was green on its
  first execution.
- The emulator proves a query is **valid and permitted**, not that a composite
  index exists - the Firestore emulator serves any query it can plan. What the
  suite genuinely proves is the class of failure the descending key-scan
  rejection already exposed: a query shape Firestore refuses outright is caught
  here rather than in production. Index coverage itself is an argument about the
  automatic single-field index, recorded above and in `rules-tests/README.md`.
- The pinned toolchain must be put on `PATH` for every emulator command in a
  fresh shell, as the previous handover recorded: the ambient JRE is older than
  21 and firebase-tools hard-fails on it.

The existing user-owned local edits remain separate and must not be staged:

```text
.vscode/settings.json
android/gradle.properties
pubspec.lock dependency-resolution updates for characters, matcher,
material_color_utilities, meta, test_api, and the Dart SDK constraint
```

### Next bounded chunk

Implement only the guarded tenant audit-log surface, which is the last
tenant-level record this migration leaves unreachable, and nothing else:

1. Add a strict read model and guarded repository for
   `tenants/{tenantId}/audit_logs`: bounded, ascending, document-ID-ordered
   pages of the events the server writes, plus a page filtered to one event
   type. Reuse the field set the Functions writers are the only authority on,
   model each `eventType` explicitly, and degrade an unmodelled one to a
   verbatim row rather than failing a page closed - the same decision the
   movement `sourceType` and the adjustment category already document.
2. Keep the existing owner/admin Rules boundary and prove it rather than widen
   it: `audit_logs` is the whole business's event trail, which is deliberately
   narrower than the `owner/admin/manager` stock surfaces landed this session.
   Add its own focused emulator suite - an absent record must still answer, and
   a platform admin reads it while a manager does not.
3. Prove each client query is at least valid and permitted by issuing the exact
   page in that suite, and add a composite index only if a query shape actually
   requires one. Ascending key order with at most one equality filter needs
   none, as this session and the receipt lookup both recorded.
4. Reach it from the safe landing route as an owner/admin sibling of the daily
   summary, resolving actor UIDs through the existing `TenantStaffNameResolver`.
5. Add unit, widget, and focused Rules emulator coverage for pagination
   boundaries, a cross-tenant response, a manager and a cashier being refused, a
   tenant switch during an outstanding page, an unmodelled event type, and a
   record that contradicts its own path.
6. Leave the checkout screen and payment flow, receipt printing, product
   cost/profit fields, `getSalesComparison`, any business-wide movement or
   reconciliation feed, subscription and branding surfaces, deployment, and
   Android build/emulator validation outside that chunk.

---

## Guarded tenant activity log handoff - 2026-08-01

### Completed in this session

The last tenant-level record this migration left unreachable is now readable.
The safe landing route opens an owner/admin-only activity log of every event the
server recorded for the business, and the same page can be narrowed to exactly
one modelled event. This chunk adds no checkout screen or payment flow, no
receipt printing, no product cost or profit surface, no `getSalesComparison`, no
business-wide movement or reconciliation feed, and makes no legacy operational
POS route reachable.

Implemented behavior and safety decisions:

- `TenantAuditRecord` decodes what the ten tenant `audit_logs` writers agree on
  and nothing more: `tenants/onboarding.ts`, `lifecycle/tenantLifecycle.ts`,
  `lifecycle/impactScan.ts`, `recovery/ownerRecovery.ts`, `staff/issuance.ts`,
  `staff/acceptance.ts`, `staff/membership.ts` (through the `auditData` helper
  in `staff/shared.ts`), `operations/stock.ts`, `operations/returns.ts`, and
  `reconciliation/handlers.ts`. **Only the shared envelope is modelled** - the
  business, the event, its attribution, and when it was recorded. Each event
  also carries its own detail, and modelling sixteen payload shapes to render
  one line each would make the surface fail closed every time a writer added a
  field, which is exactly the outcome an audit trail must avoid.
- **Attribution is required, but its form differs and both are real.** Every
  staff-caused record carries `actorUid`; the tenant-readable lifecycle record
  and the impact-scan alert carry `actorType` (`platform_admin`, `platform`) and
  no `actorUid`, because the platform is not a member of the business it acted
  on. A record that names neither is refused as `unattributed_audit_record`
  rather than listed as evidence, and a platform event is attributed to the
  platform on screen rather than to a missing colleague.
- **A missing `createdAt` degrades the row rather than failing the page
  closed**, the same decision the per-product ledger and the stock correction
  feed already record. A row without a time still proves the event happened,
  names who caused it, and says what it was; denying an owner the whole trail
  over one missing convenience field would be strictly worse. This is
  deliberately the opposite call from the adjustment feed's before/after
  figures, which are refused because a correction that cannot explain its own
  change is not evidence of anything.
- An unmodelled `eventType` degrades to a null typed event and is displayed
  verbatim, exactly as an unmodelled movement `sourceType` and adjustment
  category are: a server deploy recording a new event is not evidence of
  anything wrong, and hiding a real event from the business's own trail would be
  far worse than naming it honestly. A unit test proves every modelled wire
  value is distinct and round-trips.
- **The record does not repeat its own ID** - the writers address it by the
  operation, request, or delivery ID the event belongs to - so its path is the
  one authority on which event it is. The business it names must still agree
  with the path it was read from.
- **The `audit_logs` Rules boundary was kept and proved rather than widened.**
  The read stays `owner/admin` plus `platformAdmin()`, deliberately narrower
  than the `owner/admin/manager` `stock_adjustments` and `daily_metrics`
  surfaces landed previously: a manager records and answers for stock
  corrections, while this collection also names who was invited, deactivated,
  and recovered, and carries every lifecycle change and critical administrative
  alert the platform caused. The platform reads it because it is the actor on
  those records. The rule itself is unchanged; only its reasoning is now written
  down beside it. The role check touches no document field, so an absent record
  and a business whose trail has not started both still answer. Writing stays
  server-only.
- **Both pages are ascending by document ID and neither needed a composite
  index.** An audit ID is the operation, request, or delivery ID the event
  belongs to - a digest for most writers and the tenant ID itself for
  `tenant_requested` - so document order carries no time information at all, and
  the screen says outright that the list is not time order. The business-wide
  page carries no filter and the narrowed page carries exactly one `eventType ==`
  equality on the same ascending key order, both of which Firestore's automatic
  single-field index serves. A descending page would have required a filter and
  a composite index and bought nothing but a different arbitrary order, so
  `firestore.indexes.json` was not touched.
- **The event filter is a typed enum, never a caller-supplied string.**
  `loadEventsOfType` accepts a `TenantAuditEventType`, so no caller can name an
  arbitrary field value. The consequence is deliberate: an event this client
  does not model cannot be filtered for, and the unfiltered page still lists it.
- A cross-tenant response fails closed as `cross_tenant_audit_record`, and a
  narrowed page that answers with another event fails closed as
  `foreign_audit_event_type`, because a filtered page returning foreign rows is
  a broken boundary rather than rows to skip past.
- A manager and a cashier are both refused as `audit_logs_forbidden` before any
  read is issued, so a role that may not see the trail never reaches the server.
- Narrowing the trail on screen restarts it. A cursor is a document ID inside
  one exact query, so carrying it across a filter change would page from a
  position the new query never established.
- The route is reached from the safe landing screen when the composition root
  supplies one **and** the guarded session allows the role, exactly as the daily
  summary and receipt lookup already are. Tenancy keeps owning routing:
  `main.dart` passes the builder through `TenantRoutingShell` into
  `TenantSafeLandingScreen`, and the route opens under the caller's
  `TenantSessionScope`, so a tenant switch during an outstanding page discards
  it before it can label another business's screen.
- Actor **and** target UIDs are resolved through the existing
  `TenantStaffNameResolver` - one resolver per session epoch, one bounded cap
  across both, degrading to the authoritative UID. Both are staff of the same
  business, so this is one existing lookup rather than a new one.

Deliberately outside this chunk, and important for the next session:

- The trail lists the envelope, not each event's own payload. A `staff_updated`
  row says who changed whom, not which fields changed.
- Nothing on the surface can record, amend, or remove an event.
- `platform_audit_logs` remains platform-only with no client surface, and no
  business-wide stock movement or reconciliation feed exists.

Files in this chunk:

```text
docs/frontend_tenant_migration_inventory.md
firestore.rules
lib/audit/audit.dart
lib/audit/audit_log.dart
lib/audit/audit_log_panel.dart
lib/main.dart
lib/tenancy/tenant_routing_shell.dart
rules-tests/README.md
rules-tests/package.json
rules-tests/test/audit-logs.test.js
test/audit/audit_log_panel_test.dart
test/audit/audit_log_test.dart
PLAN.md
```

Validation evidence after implementation code was frozen:

- `flutter analyze --no-pub lib/audit lib/inventory lib/returns lib/reporting
  lib/sales lib/shift lib/checkout lib/tenancy lib/main.dart test/audit
  test/inventory test/returns test/reporting test/sales test/shift test/checkout
  test/tenancy` reported one pre-existing issue and nothing else: the Sentry
  `profilesSampleRate` experimental warning at `lib/main.dart:28`, which this
  chunk does not touch.
- `flutter test --no-pub --concurrency=1 --reporter=failures-only test/audit
  test/inventory test/returns test/reporting test/sales test/shift test/checkout
  test/tenancy` passed **704/704** relevant Flutter tests, including **30** new
  tests: 9 audit read-model cases, 7 repository cases, 11 panel widget cases,
  and 3 safe-landing entry-point cases.
- `npm --prefix rules-tests run test:emulator:audit-logs` passed the focused
  Firestore-only suite **8/8** during development.
- `npm --prefix rules-tests run test:emulator` passed the full Firestore Rules
  suite **104/104** (96 existing plus the 8 new audit-log cases).
- `npm --prefix functions test` passed **166/166** Functions tests with the
  pinned Node 24 / Temurin JDK 21 environment. No Functions source changed.
- With `FUNCTIONS_DISCOVERY_TIMEOUT=60`,
  `npm --prefix rules-tests run test:emulator:invitations` passed **12/12** real
  Auth, Firestore, and Functions emulator integration tests.
- `git diff --check` was clean. No index change was needed, so
  `firestore.indexes.json` was not touched. Android build and Android emulator
  validation were intentionally skipped as requested.

Meaningful failures and their resolutions:

- No test assertion failed. Every command in the final sequence was green on its
  first execution.
- **Two pieces of speculative API were written and then removed before the
  validation sequence.** An `openTenantAuditLog` helper mirroring the stock feed
  had no caller, because the routing shell opens the screen directly under its
  own session scope; it was deleted along with the import it alone needed. The
  screen's pre-narrowed `eventType` entry point was kept instead of deleted, but
  only after it was given real coverage - including a rebuild with a different
  event, which proves `didUpdateWidget` re-narrows the page rather than leaving
  a stale filter in state. Prefer this order: delete what has no caller, and
  cover what survives.
- The pinned toolchain must be put on `PATH` for every emulator command in a
  fresh shell, as the previous handovers recorded: the ambient JRE is older than
  21 and firebase-tools hard-fails on it.
- The focused suite prints large expected-denial traces for the write-refusal
  cases. That is the harness's known behavior, not a failure; only totals were
  read.

The existing user-owned local edits remain separate and must not be staged:

```text
.vscode/settings.json
android/gradle.properties
pubspec.lock dependency-resolution updates for characters, matcher,
material_color_utilities, meta, test_api, and the Dart SDK constraint
```

### Next bounded chunk

Implement only the guarded business-wide stock movement feed - the reconciled
counterpart to the manual-correction feed landed previously - and nothing else:

1. Add a strict read model and guarded repository for a **collection-group**
   read of `stock_movements`, or an explicit decision not to use one. Today the
   ledger is reachable only one product at a time; a business asking "what moved
   this week" has no surface. Reuse the existing `TenantStockMovement` read
   model rather than adding a second authority on those field names, and keep
   the exact-child, uniqueness, and ordering proofs - note that a
   collection-group query returns paths the current `TenantReadRepository`
   child-path proof rejects, so that proof needs a deliberate extension rather
   than a bypass.
2. Decide and test the collection-group Rules boundary explicitly. A
   `match /{path=**}/stock_movements/{movementId}` rule is a different boundary
   from the per-product one and must be reasoned about on its own; if it cannot
   be made safe, record that and keep the per-product surface as the answer.
3. Add the composite indexes a collection-group page needs - a group query is
   **not** served by the automatic single-field index the way this session's and
   the previous session's key-ordered pages were - and prove each query is
   servable by issuing the exact client query in the emulator suite.
4. Reach it from the read-only catalog as a sibling of the correction feed,
   resolving actor UIDs through the existing `TenantStaffNameResolver`.
5. Add unit, widget, and focused Rules emulator coverage for pagination
   boundaries, a cross-tenant response, a wrong-role read, a tenant switch
   during an outstanding page, a movement whose figures contradict themselves,
   and a group query answering with a document below another business.
6. Leave the checkout screen and payment flow, receipt printing, product
   cost/profit fields, `getSalesComparison`, per-event audit payload detail, a
   `platform_audit_logs` surface, subscription and branding surfaces,
   deployment, and Android build/emulator validation outside that chunk.

---

## Guarded business-wide stock movement feed handoff - 2026-08-01

### Completed in this session

A business can finally ask "what moved this week". The read-only catalog now
opens a management-only page of every entry recorded against every product's
ledger at once, narrowable to one modelled source. This chunk adds no checkout
screen or payment flow, no receipt printing, no product cost or profit surface,
no `getSalesComparison`, no per-event audit payload detail, no
`platform_audit_logs` surface, and makes no legacy operational POS route
reachable.

Implemented behavior and safety decisions:

- **A collection group was used, and the decision was proved before it was
  designed.** The previous handover left "or an explicit decision not to use
  one" open, so the first thing this session did was put a candidate rule and
  the exact client query in front of the real emulator. It answered
  unambiguously: a `resource.data.tenantId` group rule authorizes a page that
  carries that equality filter, and refuses one that does not. That experiment
  decided the chunk; everything below follows from it.
- **The group boundary is narrowed in three independent places, not one.** The
  repository attaches the `tenantId ==` filter itself and refuses a caller that
  supplies one at all - even its own business - so there is exactly one author
  of the tenant binding. The Firestore rule authorizes the page by that same
  condition, so a page without it is refused by the server too. And
  `readProductSubcollectionGroupPage` still proves every returned path is an
  exact `tenants/{tenantId}/products/{productId}/stock_movements/{movementId}`
  child of this session's own root. Any one of the three failing leaves the
  other two standing.
- **`match /{ledgerPath=**}/stock_movements/{movementId}` is `list` only.** A
  rule nested under `products/{productId}` does not apply to a group query at
  all, so this is a genuinely separate boundary. Restricting it to `list` keeps
  the per-product rule the one authority on reading a single movement -
  including an **absent** one, which the group rule's `resource.data` comparison
  could not answer without raising an evaluation error. The focused suite proves
  a missing movement still answers, so the new rule demonstrably did not disturb
  the old one. `allow get, write: if false` beside it is documentation, not a
  denial: Firestore rules are permissive-OR and an `if false` never revokes what
  another rule granted.
- The roles are the same owner/admin/manager set the per-product ledger,
  `stock_adjustments`, and `adjustStock` itself use, so every stock surface
  agrees about who may see what moved. A cashier is refused as
  `stock_movement_feed_forbidden` before any query is issued.
- **The child-path proof was extended, not bypassed.** A group result is not
  below any single collection path, so `TenantDocumentGroupPage` is a distinct
  page type with a distinct proof: six segments, the products segment, the
  subcollection segment, this session's tenant, and two validated document IDs.
- **Ordering is compared segment by segment, because that is how Firestore
  orders `__name__`.** A product `p` sorts before `p-2`, while the joined paths
  `.../p/...` and `.../p-2/...` compare the other way round as plain text, since
  `-` is below `/`. A string comparison would have rejected a page Firestore
  ordered correctly, and a unit test pins exactly that pair.
- **The cursor is a whole document path, and Firestore refuses anything else.**
  A movement ID is unique only below its own product - a sale of two items
  writes `sale_{saleId}` under each - so a bare ID could not resume the page.
  The first emulator run failed on this and is recorded below; the client and
  the Rules suite now issue the identical string-path cursor.
- **A group query is not served by the automatic single-field index**, unlike
  every key-ordered page the last three chunks added, so
  `firestore.indexes.json` gained two `COLLECTION_GROUP`-scoped
  `stock_movements` indexes: `tenantId`/`__name__` and
  `tenantId`/`sourceType`/`__name__`. The `tenant_memberships` group index
  already in the file is the precedent for the shape.
- The source filter is a typed enum, never a caller-supplied string, exactly as
  the audit log's event filter is. `other` carries no wire value, so an
  unmodelled source cannot be filtered for and is refused as
  `unfilterable_movement_source` before any query - while the unnarrowed page
  still lists it verbatim. Narrowing restarts the page, because a cursor is a
  position inside one exact query.
- A cross-tenant document fails closed, and a narrowed page answering with
  another source fails closed as `foreign_movement_source`: a filtered page
  returning foreign rows is a broken boundary rather than rows to skip past.
- The read model is **reused, not duplicated**. `TenantStockMovement` stays the
  one authority on those field names; it only gained a display `label` per
  source. A reconciled sale records no actor and no before/after, so the screen
  says "the server" and "Before and after were not recorded" rather than
  inventing either.
- Rows are keyed by product **and** record, since one movement ID is unique only
  below its own product. A widget test seeds `sale_co-1` under two products and
  proves two distinct rows.
- The collection-group reader is a **separate injected boundary**
  (`TenantCollectionGroupReader`), deliberately not folded into
  `TenantDataReader`. Every other read in the app is bounded by a path this
  tenant owns; this one is not, so a surface that needs it asks for it by name
  and the composition root hands it over explicitly.
- The entry point is a catalog button that exists only when the composition root
  supplies a route **and** the guarded session allows the role, exactly as the
  per-product stock route and the correction feed already are. Tenancy keeps
  owning routing, and the route opens under the caller's `TenantSessionScope`,
  so a tenant switch during an outstanding page discards it.
- Actor UIDs resolve through the existing `TenantStaffNameResolver`, one
  resolver per session epoch, degrading to the authoritative UID. Product names
  are deliberately not resolved: that would be one document read per row for a
  label the product ID already identifies.

Deliberately outside this chunk, and important for the next session:

- The feed lists movements, not their sources. A `sale` row names the checkout
  it came from but does not open it, and there is no date range or product
  filter - both would need their own composite index and read decision.
- Nothing on the surface can record, amend, or undo a movement.
- No reconciliation feed exists, and `platform_audit_logs` still has no client
  surface.

Files in this chunk:

```text
docs/frontend_tenant_migration_inventory.md
firestore.indexes.json
firestore.rules
lib/inventory/inventory.dart
lib/inventory/stock_movement_feed.dart
lib/inventory/stock_movement_feed_panel.dart
lib/inventory/stock_movements.dart
lib/main.dart
lib/tenancy/tenant_catalog.dart
lib/tenancy/tenant_repository.dart
lib/tenancy/tenant_routing_shell.dart
rules-tests/README.md
rules-tests/package.json
rules-tests/test/stock-movement-feed.test.js
test/inventory/stock_movement_feed_panel_test.dart
test/inventory/stock_movement_feed_test.dart
test/tenancy/tenant_catalog_test.dart
test/tenancy/tenant_repository_test.dart
PLAN.md
```

Validation evidence after implementation code was frozen:

- `flutter analyze --no-pub lib/audit lib/inventory lib/returns lib/reporting
  lib/sales lib/shift lib/checkout lib/tenancy lib/main.dart test/audit
  test/inventory test/returns test/reporting test/sales test/shift test/checkout
  test/tenancy` reported one pre-existing issue and nothing else: the Sentry
  `profilesSampleRate` experimental warning at `lib/main.dart:28`, which this
  chunk does not touch.
- `flutter test --no-pub --concurrency=1 --reporter=failures-only test/audit
  test/inventory test/returns test/reporting test/sales test/shift test/checkout
  test/tenancy` passed **729/729** relevant Flutter tests, including **25** new
  tests: 10 feed read-model and repository cases, 9 feed-panel widget cases, 5
  base-repository collection-group cases, and 1 catalog entry-point case.
- `npm --prefix rules-tests run test:emulator:stock-movement-feed` passed the
  focused Firestore-only suite **8/8** during development.
- `npm --prefix rules-tests run test:emulator` passed the full Firestore Rules
  suite **112/112** (104 existing plus the 8 new movement-feed cases).
- `npm --prefix functions test` passed **166/166** Functions tests with the
  pinned Node 24 / Temurin JDK 21 environment. No Functions source changed.
- With `FUNCTIONS_DISCOVERY_TIMEOUT=60`,
  `npm --prefix rules-tests run test:emulator:invitations` passed **12/12** real
  Auth, Firestore, and Functions emulator integration tests.
- `git diff --check` was clean, and `firestore.indexes.json` parsed as valid
  JSON. Android build and Android emulator validation were intentionally
  skipped as requested.

Meaningful failures and their resolutions:

- **The collection-group cursor was wrong, and only the emulator said so.**
  `startAfter` with a `DocumentReference` was rejected outright: *"Expected a
  string for document ID in startAfter(), but got a object"*. Firestore wants
  the complete path as a **string** for a group page, and a bare document ID
  only for a page whose collection path it already knows. Both the Dart
  transport and the Rules suite now pass the string path. Worth remembering:
  this is a query-construction error the type system cannot catch and no Dart
  fake would have exposed.
- **Two test fakes answered pages their own filters excluded.** A cross-tenant
  case was written against a fake that honoured the `tenantId ==` filter, so the
  document was filtered out and the page succeeded empty rather than failing
  closed; it now uses the explicit `ignoreFilters` transport, which is the only
  honest way to exercise a check that exists for a transport ignoring the rule.
  The panel fake had the opposite problem - it ignored filters entirely, so
  narrowing the feed returned the wrong source and failed the page closed. A
  fake reader must model the filter contract in both directions.
- **A speculative `openTenantStockMovementFeed` helper was deleted before the
  validation sequence**, along with the import it alone needed. The catalog
  opens the screen through the injected route builder, so it had no caller. The
  pre-narrowed `source` entry point was kept instead of deleted, but only after
  a rebuild-with-a-different-source test proved `didUpdateWidget` re-narrows the
  page. This is the same order the previous handover recorded: delete what has
  no caller, cover what survives.
- The pinned toolchain must be put on `PATH` for every emulator command in a
  fresh shell, as every previous handover records: the ambient JRE is older than
  21 and firebase-tools hard-fails on it.
- The focused suite prints large expected-denial traces for the write-refusal
  cases. That is the harness's known behavior, not a failure; only totals were
  read.

The existing user-owned local edits remain separate and must not be staged:

```text
.vscode/settings.json
android/gradle.properties
pubspec.lock dependency-resolution updates for characters, matcher,
material_color_utilities, meta, test_api, and the Dart SDK constraint
```

### Next bounded chunk

Implement only the guarded reconciliation status surface - the last server
process whose outcome the app cannot see - and nothing else:

1. Add a strict read model and guarded repository for the reconciliation
   records `functions/src/reconciliation/**` writes. Confirm the canonical
   collection, its scope, and its field names against that source before
   designing anything; note that `reconciliation_jobs` is already a
   `COLLECTION_GROUP` index in `firestore.indexes.json`, so establish where it
   actually lives rather than assuming a tenant subcollection. If it turns out
   to be a platform-only queue, record that and surface the tenant-visible
   outcome instead - the daily summary already reports a day as reconciled or
   not, so this chunk must add the *why*, not a second answer to the same
   question.
2. Decide and test the Rules boundary exactly as the last four chunks did.
   Whatever the collection is, it is currently denied by a catch-all, so this
   needs a deliberate decision and its own focused emulator suite. If a group
   read is involved, reuse the `list`-only, `resource.data.tenantId` pattern
   landed this session rather than inventing a second one, and remember that an
   absent record must still answer.
3. Add only the composite indexes a query shape actually requires, and prove
   each query is valid and permitted by issuing the exact client page in that
   suite. A group query needs a `COLLECTION_GROUP` index; a key-ordered page
   with at most one equality filter needs none.
4. Reach it from the daily summary, which is where a manager already asks
   whether a day is reconciled, resolving any actor UIDs through the existing
   `TenantStaffNameResolver`.
5. Add unit, widget, and focused Rules emulator coverage for a day with no
   record, a failed run, a wrong-role read, a cross-tenant response, a tenant
   switch during an outstanding load, and a record that contradicts itself.
6. Leave the checkout screen and payment flow, receipt printing, product
   cost/profit fields, `getSalesComparison`, per-event audit payload detail, a
   `platform_audit_logs` surface, any business-wide date-range or product filter
   on the movement feed, subscription and branding surfaces, deployment, and
   Android build/emulator validation outside that chunk.

---

## Guarded reconciliation status surface handoff - 2026-08-01

### Completed in this session

The daily summary already said whether a day was reconciled. Each day now opens
a management-only page that says **why**: the server's own per-day verdict, and
a bounded page of the reconciliation runs behind it. This chunk adds no checkout
screen or payment flow, no receipt printing, no product cost or profit surface,
no `getSalesComparison`, no per-event audit payload detail, no
`platform_audit_logs` surface, and makes no legacy operational POS route
reachable.

Implemented behavior and safety decisions:

- **The canonical collection was confirmed against the source before anything
  was designed.** The previous handover flagged that `reconciliation_jobs` is
  already a `COLLECTION_GROUP` index and warned it might be a platform-only
  queue. It is not: `functions/src/reconciliation/jobs.ts` writes every job to
  `tenants/{tenantId}/reconciliation_jobs/{jobId}`, and that group index serves
  `listRetryableReconciliationTasks`, the server's own retry sweep across all
  businesses. So this chunk needed no group read and no group rule at all.
- **A run is not a verdict about a day, and the surface says so.** This decided
  the chunk. `processMetricsPage` takes the oldest outstanding business day in
  the whole business rather than the day its job names, so a *completed* run
  does **not** mean the day it was queued for was regenerated. A page of runs
  presented as a per-day answer would therefore have been a second - and wrong -
  answer to the question the daily summary already answers, which is exactly
  what the previous handover said this chunk must not be.
- **`reconciliation_dirty_days/{businessDate}` is the one per-day authority**,
  so it was brought in as the verdict. Its document ID *is* the business date,
  so it is read by exact document path rather than by query - the same reason
  the daily summary reads a day by path. A query cannot return a day that has no
  record, and "no sale reached the server for this day" is precisely the answer
  that absence carries. `TenantReconciliationDayOutcome` derives from that
  record alone: no sales, awaiting regeneration, regenerated, blocked, or a
  status this client does not model.
- **No composite index was added, deliberately.** The runs page carries one
  `localDate ==` equality on ascending `__name__`, which Firestore's automatic
  single-field index serves. That is the shape the previous handover named as
  needing none, and staying inside it is why a status filter was left out: it
  would be a second equality filter and belongs to its own decision.
- Both collections were denied by the `{serverCollection}/{document=**}`
  catch-all, so each got a deliberate rule. The roles are owner/admin/manager -
  the same set that reads `daily_metrics`, because this is the explanation of
  business-wide revenue, and whoever may not see the figure may not see why it
  is what it is. It is deliberately wider than the owner/admin `audit_logs`:
  this is reporting, not governance. Neither role check touches a document
  field, so a business date the server has never seen still answers rather than
  raising an evaluation error - the absence is the answer.
- Writing stays server-only in both. A client that could write here could mark
  a day clean so its sales were never aggregated, or clear the failure record of
  a run that never succeeded. Reconciliation stays requestable only through the
  callable, which enforces its own roles and idempotency.
- **Both read models refuse a record that contradicts its only writer.** A day
  claiming to be `clean` without naming the revision it published, or naming one
  the day never reached, or a `processedRevision` ahead of `revision`, or a
  `quarantined` day with no error code, is refused. A run `completed` before
  reaching `finalize` or without a completion instant, a `failed` run with no
  failure count or no error code, and a `quarantined` run with no error code are
  refused.
- **The quarantined-run failure-count check was deliberately dropped after
  reading the writer.** `listRetryableReconciliationTasks` quarantines a
  malformed job with `merge: true` and never touches `consecutiveFailureCount`,
  so requiring it to be positive there would have hidden exactly the run an
  owner most needs to see. Only `failed`, whose sole writer is
  `recordReconciliationFailure`, carries that requirement. A unit test pins the
  accepted quarantined-with-zero case.
- Unmodelled statuses, sources, and phases are carried verbatim as `other` and
  shown as themselves, exactly as the movement feed and audit log do. A server
  deploy that introduces one is not evidence of anything wrong, and reporting an
  unknown day state as "reconciled" or "pending" would be inventing an answer.
- A scheduled sweep records `system:nightly` and a sale trigger records
  `system:sale_trigger`. Neither is a document ID and neither is a member of the
  business, so neither is offered to `TenantStaffNameResolver`; the row says
  "the server" and names the actor string. A manual run's `requestedBy` **is** a
  UID and resolves through the existing resolver, one per session epoch.
- The entry point is a per-day button on the summary that exists only when the
  composition root supplies a route **and** the guarded session allows the role,
  exactly as the catalog's stock routes are. Tenancy keeps owning routing: the
  routing shell was not touched at all, because the reporting domain composes
  its own sibling route inside `dailySummaryRoute`. The route opens under the
  caller's `TenantSessionScope`, so a tenant switch discards it.
- Opening a different day restarts the runs page. A cursor is a position inside
  one exact query, so carrying it across a date change would page from somewhere
  that day never established; a widget test rebuilds the panel with another date
  and proves `didUpdateWidget` resets it.
- Server error codes are shown as the server codes they are (`Server code:
  resource-exhausted`), never rewritten into a sentence this app would be
  inventing.

Deliberately outside this chunk, and important for the next session:

- Nothing on the surface can queue, retry, or cancel a run; the
  `requestTenantReconciliation` callable has no client surface.
- There is no status filter on the runs page and no date-range view - both are a
  second equality filter and their own index decision.
- `reconciliation_anomalies`, `reconciliation_sale_receipts`,
  `shift_expectations`, `stock_checkpoints`, and `platform_reconciliation_sweeps`
  still have no client surface and stay denied by the catch-all.

Files in this chunk:

```text
docs/frontend_tenant_migration_inventory.md
firestore.rules
lib/main.dart
lib/reporting/daily_metrics_panel.dart
lib/reporting/reconciliation_status.dart
lib/reporting/reconciliation_status_panel.dart
lib/reporting/reporting.dart
lib/tenancy/tenant_paths.dart
rules-tests/README.md
rules-tests/package.json
rules-tests/test/reconciliation-status.test.js
test/reporting/daily_metrics_panel_test.dart
test/reporting/reconciliation_status_panel_test.dart
test/reporting/reconciliation_status_test.dart
test/tenancy/tenant_paths_test.dart
PLAN.md
```

Validation evidence after implementation code was frozen:

- `flutter analyze --no-pub lib/audit lib/inventory lib/returns lib/reporting
  lib/sales lib/shift lib/checkout lib/tenancy lib/main.dart test/audit
  test/inventory test/returns test/reporting test/sales test/shift test/checkout
  test/tenancy` reported one pre-existing issue and nothing else: the Sentry
  `profilesSampleRate` experimental warning at `lib/main.dart:28`, which this
  chunk does not touch.
- `flutter test --no-pub --concurrency=1 --reporter=failures-only test/audit
  test/inventory test/returns test/reporting test/sales test/shift test/checkout
  test/tenancy` passed **761/761** relevant Flutter tests, including **32** new
  tests: 21 read-model and repository cases, 9 status-panel widget cases, and 2
  daily-summary entry-point cases.
- `npm --prefix rules-tests run test:emulator:reconciliation-status` passed the
  focused Firestore-only suite **8/8** during development.
- `npm --prefix rules-tests run test:emulator` passed the full Firestore Rules
  suite **120/120** (112 existing plus the 8 new reconciliation cases).
- `npm --prefix functions test` passed **166/166** Functions tests with the
  pinned Node 24 / Temurin JDK 21 environment. No Functions source changed.
- With `FUNCTIONS_DISCOVERY_TIMEOUT=60`,
  `npm --prefix rules-tests run test:emulator:invitations` passed **12/12** real
  Auth, Firestore, and Functions emulator integration tests.
- `git diff --check` was clean. `firestore.indexes.json` was deliberately **not**
  touched. Android build and Android emulator validation were intentionally
  skipped as requested.

Meaningful failures and their resolutions:

- No test assertion failed. Every command in the final sequence was green on its
  first execution.
- **One speculative public method was deleted after the first green pass**, and
  the Dart half of the sequence was re-run rather than waved through.
  `readIntake` read only the day's verdict; the panel always needs the runs too,
  so it had a test-only caller. That is the same order the last two handovers
  recorded, so it is now applied without waiting to be told: delete what has no
  caller, cover what survives. `flutter analyze --no-pub lib/reporting
  test/reporting` reported no issues and the full relevant Flutter command
  passed **761/761** again. The Rules, Functions, and integration suites execute
  no Dart and were not re-run.
- **The test fakes model the filter contract in both directions from the
  start**, which the previous handover had to learn the hard way. The unit and
  panel fakes honour the repository's `localDate ==` filter, so the narrowed
  page is real; the one check that exists *for a transport ignoring the filter*
  uses an explicit `ignoreFilters` transport instead, because a fake that
  honoured it would have made that page succeed empty and prove nothing.
- The Firestore emulator does not enforce composite indexes, so "no index is
  needed" is a reasoning claim, not something the suite can prove. What the
  suite does prove is that the exact client query is **valid and permitted**;
  the index claim rests on the query being equality-plus-`__name__`, which is
  the automatic single-field index shape, and on it being `COLLECTION`-scoped
  rather than a group query.
- The pinned toolchain must be put on `PATH` for every emulator command in a
  fresh shell, as every previous handover records: the ambient JRE is older than
  21 and firebase-tools hard-fails on it.
- The focused suite prints large expected-denial traces for the write-refusal
  cases. That is the harness's known behavior, not a failure; only totals were
  read.

The existing user-owned local edits remain separate and must not be staged:

```text
.vscode/settings.json
android/gradle.properties
pubspec.lock dependency-resolution updates for characters, matcher,
material_color_utilities, meta, test_api, and the Dart SDK constraint
```

### Next bounded chunk

**Read "Standing decisions and unreachable capabilities" near the top of this
file first.** It was added after this chunk was committed, and it recommends a
different order: the account-verification and password-reset lockout is a
user-facing dead end and should come before the anomaly surface below. The
payment question is also resolved there - a sale records a manually chosen cash,
M-Pesa, or card tender, with integration deferred - which unblocks the checkout
screen. The chunk below stays specified and correct; it is no longer
automatically next.

Implement only the guarded reconciliation anomaly surface - the detail behind
the counts this session's runs report - and nothing else:

1. Add a strict read model and guarded repository for
   `tenants/{tenantId}/reconciliation_anomalies/{anomalyId}`. Confirm the
   canonical field names against `functions/src/reconciliation/jobs.ts` and
   `processors.ts` before designing anything: three writers use that collection
   with different shapes (`invalid_sale_lines`, `invalid_product_quantity`, and
   the stock/shift variance records), so decide explicitly which envelope is
   common and refuse only what contradicts itself. A run already reports *how
   many* stock and shift differences it found; this chunk must add *which ones*,
   not a second count.
2. Decide and test the Rules boundary exactly as this chunk did. The collection
   is currently denied by the `{serverCollection}/{document=**}` catch-all, so
   it needs a deliberate decision and its own focused emulator suite. Reuse the
   owner/admin/manager set the reconciliation surface landed here unless the
   payload argues otherwise, and keep the role check off document fields so an
   absent anomaly still answers.
3. Add only the composite indexes a query shape actually requires, and prove
   each query is valid and permitted by issuing the exact client page in that
   suite. A key-ordered page with at most one equality filter needs none;
   anything wider must be justified rather than indexed by reflex.
4. Reach it from the reconciliation status page landed this session, as a
   sibling of the runs list, resolving any actor UIDs through the existing
   `TenantStaffNameResolver`.
5. Add unit, widget, and focused Rules emulator coverage for a business with no
   anomalies, each modelled anomaly shape, an unmodelled `anomalyType`, a
   wrong-role read, a cross-tenant response, a tenant switch during an
   outstanding page, and a record that contradicts itself.
6. Leave the checkout screen and payment flow, receipt printing, product
   cost/profit fields, `getSalesComparison`, per-event audit payload detail, a
   `platform_audit_logs` surface, any client path that queues, retries, or
   cancels a reconciliation run, any status filter or date-range view on the
   runs page, subscription and branding surfaces, deployment, and Android
   build/emulator validation outside that chunk.

---

## Guarded account verification entry point handoff - 2026-08-01

### Completed in this session

An unverified identity could not verify its address from inside the app, while
`emailVerified` gated both of the only two things it could otherwise do. The
business selector now offers that identity the one action that releases it. This
chunk adds no password reset, no email delivery-status surface, no checkout
screen or payment flow, and makes no legacy operational POS route reachable.

Implemented behavior and safety decisions:

- **This closed a real lockout, not a missing convenience.** `emailVerified`
  gates requesting a business (`tenant_request.dart:68`) and accepting a visible
  invitation (`tenant_visible_invitation_acceptance.dart:65`), and nothing in
  the app could trigger the email. There was no direct Firebase fallback either.
  A new identity signing in unverified reached the selector and had no action of
  any kind available to it.
- **Acceptance is never presented as delivery.** `sendAccountVerification`
  answers `{accepted: true}` for a request it took responsibility for, which is
  deliberately not the same thing: an already-verified address is accepted and
  sends nothing, and a suppressed address is accepted and then dropped by the
  delivery pipeline. The panel therefore says "if this address can receive mail,
  a verification link is on its way", and a widget test asserts the copy carries
  no claim of sending. Anything stronger would assert something the client
  cannot know, and would also leak whether an address is suppressed.
- **The identity is reloaded, because `emailVerified` is a cached token claim.**
  It does not change when the user follows the link in their mailbox, so a
  "check again" built on the existing `isEmailVerified` callback would have told
  a verified user they were still unverified forever. `reloadIdentity` is a
  required injection rather than an optional one: without it the panel stays
  unreachable entirely, and a routing-shell test proves that. The composition
  root supplies `FirebaseAuth.instance.currentUser?.reload()`, and the shell
  restarts bootstrap afterwards so the refreshed claim is consulted.
- **One user intent carries one idempotency key.** The intent is created once
  and reused by every retry of that intent, so a user who taps twice or retries
  after a transport failure addresses the same delivery rather than queuing a
  second email. A widget test fails the transport, retries, and asserts both
  calls carried the identical `requestId`. A different UID discards the intent,
  so one identity's retry can never address another identity's delivery.
- The generated `requestId` is proved against the server's own
  `^[A-Za-z0-9][A-Za-z0-9._:-]{7,127}$` contract **before** any call, so a
  broken generator is a local programming error rather than a rejected round
  trip. A unit test runs the real generator fifty times against that pattern.
- The response is proved rather than assumed: exactly one key, exactly
  `accepted: true`. An extra field means the contract moved, and it is refused
  instead of being read as the response this client already knows.
- Every failure maps to a message that discloses nothing about the address. The
  five-minute recency rule is the one case named precisely, because it is the
  only one the user can act on - and it is the expected answer for any session
  that has been open a while.
- The account type is deliberately **not** checked client-side. Every identity
  signs in with an address and the server decides eligibility from the canonical
  root record; narrowing it here would hide the only recovery path from an
  identity the server would have served.
- The panel is offered only when the composition root supplies both the reload
  and the callable, exactly as every other injected surface is, and only while
  the identity is unverified and globally active.

Deliberately outside this chunk, and important for the next session:

- **Password reset is blocked on App Check** - see "Open decision" near the top
  of this file. It is not an oversight in this chunk: the callable rejects any
  request this client could make, and on Windows it is structurally unreachable.
- `getMyEmailDeliveryStatus` still has no surface, so a user whose address is
  suppressed sees the accepted message and never learns why nothing arrives.
  That is the honest limit of this chunk and the obvious next one.

Files in this chunk:

```text
PLAN.md
lib/main.dart
lib/tenancy/account_verification.dart
lib/tenancy/tenancy.dart
lib/tenancy/tenant_routing_shell.dart
test/tenancy/account_verification_test.dart
test/tenancy/tenant_routing_shell_test.dart
```

Validation evidence after implementation code was frozen:

- `flutter analyze --no-pub lib/audit lib/inventory lib/returns lib/reporting
  lib/sales lib/shift lib/checkout lib/tenancy lib/main.dart test/audit
  test/inventory test/returns test/reporting test/sales test/shift test/checkout
  test/tenancy` reported one pre-existing issue and nothing else: the Sentry
  `profilesSampleRate` experimental warning at `lib/main.dart:28`.
- `flutter test --no-pub --concurrency=1 --reporter=failures-only test/audit
  test/inventory test/returns test/reporting test/sales test/shift test/checkout
  test/tenancy` passed **778/778** relevant Flutter tests, including **17** new
  tests: 7 gateway cases, 7 panel widget cases, and 3 routing-shell entry-point
  cases. The focused `test/tenancy` command passed **300/300**.
- `git diff --check` was clean.
- **The emulator suites were deliberately not re-run.** `git diff --stat HEAD --
  firestore.rules functions rules-tests` was empty, so all three are
  byte-identical to this session's earlier green run - Rules **120/120**,
  Functions **166/166**, integration **12/12** - and none of them executes any
  Dart. Re-running them would have proved nothing, which is exactly what the
  test discipline in this file warns against. Android build and Android emulator
  validation were intentionally skipped as requested.

Meaningful failures and their resolutions:

- No test assertion failed. Every command was green on its first execution.
- **The chunk was cut in half after reading the server, not before.** It began
  as "the email lockout", meaning verification *and* password reset. Reading
  `functions/src/email/passwordReset.ts` showed `enforceAppCheck: true` plus
  `requireAppCheckedPublic`, which throws when `request.app` is absent - and the
  app has no `firebase_app_check` dependency at all. Writing that client would
  have shipped a button that fails every time it is pressed. The blocker and the
  three ways out are recorded near the top of this file instead.
- The reload requirement was also found by reading rather than by testing:
  `isEmailVerified` in `lib/main.dart` reads `currentUser.emailVerified`, which
  is a claim inside the cached ID token. A "check again" wired only to the
  existing bootstrap retry would have compiled, passed a naive test, and never
  worked in production.

The existing user-owned local edits remain separate and must not be staged:

```text
.vscode/settings.json
android/gradle.properties
pubspec.lock dependency-resolution updates for characters, matcher,
material_color_utilities, meta, test_api, and the Dart SDK constraint
```

### Next bounded chunk

Implement only the guarded email delivery-status surface - the missing half of
the verification loop - and nothing else:

1. Add a strict client boundary for `getMyEmailDeliveryStatus`. Note that it
   returns a bare **string**, not an object: either the exact
   `EMAIL_UNAVAILABLE_MESSAGE` from `functions/src/email/config.ts` or
   `"available"`. Decide explicitly whether the client re-displays the server's
   sentence or maps the two known answers to its own copy, and refuse any third
   value rather than showing it verbatim.
2. Reach it from the account verification panel added this session, so a user
   who requested the email and received nothing learns the address is
   undeliverable instead of tapping "send again" forever. It requires
   authentication but not verification, which is exactly the state that panel
   runs in.
3. Keep the enumeration boundary intact: the answer is about the caller's own
   address only, and no surface may reveal it for anybody else.
4. Add unit and widget coverage for both answers, an unrecognised answer, a
   transport failure, a signed-out caller, and an identity change during an
   outstanding load.
5. Leave password reset - blocked on the App Check decision above - the checkout
   screen and payment flow, receipt printing, product cost/profit fields,
   `getSalesComparison`, a `platform_audit_logs` surface, subscription and
   branding surfaces, deployment, and Android build/emulator validation outside
   that chunk.

---

## Guarded email delivery-status handoff - 2026-08-01

### Completed in this session

The verification loop is closed. A user who asks for a verification email and
receives nothing is now told the address cannot receive mail, instead of tapping
"send again" indefinitely. This chunk adds no password reset, no checkout screen
or payment flow, and makes no legacy operational POS route reachable.

Implemented behavior and safety decisions:

- **The server's sentence is matched as a sentinel, not displayed.** This was
  the explicit decision the previous handover asked for.
  `getMyEmailDeliveryStatus` returns a bare string - either `"available"` or the
  exact `EMAIL_UNAVAILABLE_MESSAGE` - and that message is returned identically
  for **four** different causes: the account carries no address, the root record
  is not eligible, an active suppression exists, or the recorded delivery status
  is unavailable. It therefore carries no per-cause information and adds nothing
  as display text, while the panel has context it lacks: the user has just asked
  for a specific email, so it can say "sending again will not help" rather than
  a generic support line. Matching the string exactly is unavoidable coupling;
  re-displaying it would have been avoidable coupling.
- **That collapsing is the server's enumeration boundary and the client does not
  try to see through it.** The read model has exactly two states, and nothing
  attempts to infer which of the four causes applied.
- **An unrecognised answer is never read as available.** The parser refuses
  anything that is not one of the two exact sentinels, and a unit test drives
  eleven near-misses through it - `"Available"`, `" available"`,
  `"unavailable"`, a truncated message, a map, a list, `null`, `true`, `1`. If
  the server's wording is ever edited, this fails closed and the panel simply
  says nothing. Telling a user their address works when the client can no longer
  tell would be worse than silence.
- **The status is read only once a request has been accepted**, which is exactly
  when the user starts waiting for a message. A failed send checks nothing,
  because there is no absence to explain yet, and a test pins that.
- **A failed or unrecognised status read is deliberately silent.** The action
  the user took succeeded; this is a diagnostic about it, and surfacing a failed
  diagnostic as an error on a successful send would misreport what happened. A
  test proves that neither the error line nor the undeliverable line appears in
  that case, while the accepted line still does.
- Deliverability belongs to the address it was asked about, so an identity
  change discards an outstanding read. A widget test defers the answer, swaps
  the identity, then completes it and proves the first identity's answer never
  labels the second one's.
- The callable takes **no argument at all**. The server derives the address from
  the authenticated token, so there is no parameter a caller could use to ask
  about anybody else, and the client boundary preserves that shape rather than
  inventing one.
- The surface is injected from the composition root like every other one. While
  the callable is absent the panel simply does not make the claim, rather than
  guessing or failing.

Deliberately outside this chunk, and important for the next session:

- Password reset remains blocked on the App Check decision recorded near the top
  of this file. Nothing here changes that.
- The panel never states *why* an address is undeliverable, and must not: that
  is the server's boundary, not a gap to fill later.

Files in this chunk:

```text
PLAN.md
lib/main.dart
lib/tenancy/account_verification.dart
lib/tenancy/email_delivery_status.dart
lib/tenancy/tenancy.dart
lib/tenancy/tenant_routing_shell.dart
test/tenancy/account_verification_test.dart
test/tenancy/email_delivery_status_test.dart
```

Validation evidence after implementation code was frozen:

- `flutter analyze --no-pub lib/audit lib/inventory lib/returns lib/reporting
  lib/sales lib/shift lib/checkout lib/tenancy lib/main.dart test/audit
  test/inventory test/returns test/reporting test/sales test/shift test/checkout
  test/tenancy` reported one pre-existing issue and nothing else: the Sentry
  `profilesSampleRate` experimental warning at `lib/main.dart:28`.
- `flutter test --no-pub --concurrency=1 --reporter=failures-only test/audit
  test/inventory test/returns test/reporting test/sales test/shift test/checkout
  test/tenancy` passed **789/789** relevant Flutter tests, including **11** new
  tests: 6 delivery-status cases and 5 verification-panel cases. The focused
  two-file command passed **25/25** during development.
- `git diff --check` was clean.
- **The emulator suites were deliberately not re-run.** `git diff --stat HEAD --
  firestore.rules functions rules-tests` was empty, so all three remain
  byte-identical to this session's green run - Rules **120/120**, Functions
  **166/166**, integration **12/12** - and none of them executes any Dart.
  Android build and Android emulator validation were intentionally skipped as
  requested.

Meaningful failures and their resolutions:

- No test assertion failed. Every command was green on its first execution.
- The one design question the previous handover left open - re-display the
  server's sentence, or map it - was decided by reading why the sentence exists
  rather than by preference. Four causes collapsing into one message is a
  deliberate privacy boundary, which makes the string a sentinel by
  construction. Recorded above so it is not reopened.

The existing user-owned local edits remain separate and must not be staged:

```text
.vscode/settings.json
android/gradle.properties
pubspec.lock dependency-resolution updates for characters, matcher,
material_color_utilities, meta, test_api, and the Dart SDK constraint
```

### Next bounded chunk

The read surfaces and the identity recovery paths are now closed. The largest
remaining piece of reachable product is the **checkout screen**, which the
tender decision near the top of this file unblocked. Before implementing it,
re-read the five-point warning in that section: the payload schema version, the
`payloadHash` breakage for a checkout already in `awaiting_confirmation`, the
unfrozen `sales` create rule key set, the frozen receipt pattern, and the
reconciliation boundary. Those are the hazards, not the UI.

Scope one bounded chunk of it - not the whole flow at once - and keep password
reset, receipt printing, product cost/profit fields, `getSalesComparison`, a
`platform_audit_logs` surface, subscription and branding surfaces, deployment,
and Android build/emulator validation outside it.

---

## Checkout tender contract - payload v2 handoff - 2026-08-02

### Completed in this session

The first bounded chunk of the checkout screen work: the **data contract** a
tender needs, not the UI. A sale can now record how the customer paid, the
server constrains what that value may be, and the two surfaces that already
display sales show it. All five hazards from the tender decision near the top of
this file are settled there rather than left as warnings.

No checkout screen, no payment integration, no receipt printing, and no legacy
operational POS route became reachable.

Implemented behavior and safety decisions:

- **A v1 payload still parses, and nothing migrates it.** This was the open
  question the decision asked to resolve, and the case that resolves it is a
  device holding an unsubmitted draft across the upgrade.
  `supportedCheckoutSalePayloadSchemaVersions` is `{1, 2}`. Refusing v1 would
  have stranded that draft; migrating it would have been worse, and the reason
  is mechanical rather than aesthetic: `checkoutPayloadHash` is taken over the
  **whole** payload, and `_parseRecord` re-derives it on every single read
  (`lib/checkout/checkout_outbox.dart:529`). An in-place migration would turn
  every stored record into `malformed_record` immediately, and would break the
  hash that an `awaiting_confirmation` record is matched against during
  confirmation. So a v1 draft is read, submitted, and confirmed unchanged.
- **The sale reports the version it was actually written under.** `_saleFields`
  now writes `payload.schemaVersion` instead of the module constant. Had it kept
  writing the constant, a v1 draft submitted after the upgrade would have
  claimed `payloadSchemaVersion: 2` while carrying no tender - a document that
  lies about its own contract, and one the new Rules would reject outright.
- **New drafts are always v2 and the tender is required, with no default.**
  `CheckoutDraftRequest.tender` is a required parameter. A default would have
  produced a value indistinguishable from an observed one; the tender is the one
  field here that only the person at the till knows.
- **Firestore Rules constrain the tender, and now require the schema version.**
  `validSaleTender` accepts a v1 sale carrying no tender, or a v2 sale naming
  exactly one of `cash`, `mpesa`, `card`. The `sales` create rule still does not
  freeze its key set with `hasOnly`, so without this check a client could have
  written any string at all and the field would have been evidence of nothing.
  The rule also newly **requires** `payloadSchemaVersion`: it previously ignored
  the field entirely, and a sale that does not say which contract it was written
  under cannot be checked against one. That tightening broke two pre-existing
  rules tests whose fixture omitted the field; both were fixtures, not clients -
  the real submission gateway has always written it.
- **The Rules expression budget was re-proved for the largest legal sale.**
  Firestore evaluates at most 1000 expressions per request, `validSaleLines`
  already spends 16 explicit positions, and the tender check adds work to the
  most expensive rule in the file. A new rules test commits a **16-line v2**
  sale and asserts it succeeds. The v1 budget stays proved by the existing
  `checkout-receipt` and `shift-sale-attribution` maximum-size tests.
- **The frozen receipt pattern was deliberately not touched.** The decision
  required choosing before editing it, and the answer is no:
  `CT-A7F-20260729-0042` is an identity that must stay derivable from device,
  business date, and sequence alone. It is proved by a Rules regex and three
  Dart call sites, and a tender embedded in it would become wrong the moment a
  tender were ever corrected. When receipt *printing* exists, the tender belongs
  in the printed body - which is a separate chunk and does not exist yet.
- **An unrecognised tender is refused, never displayed.** Both the payload
  parser and the `TenantSale` read model apply the same rule Firestore Rules
  apply on create, so a document that slipped past them - an import, a rule
  rollback - still fails closed. A v2 sale naming `cheque` fails its whole
  history page rather than rendering a payment method nothing recognises.
- **Every surface that shows a tender says it was not verified.**
  `checkoutTenderDisclaimer` is one shared constant used by both the sale
  history panel and the receipt lookup panel, so the claim cannot drift between
  screens. This matters most on receipt lookup, which is where a return starts:
  a bare "Paid by M-Pesa" there reads as a settled transaction, and nothing in
  this system has confirmed the money arrived.
- **A sale with no tender is described as an old record, not an unpaid sale.**
  `checkoutTenderUnrecordedMessage` states that the sale predates the field. A
  widget test asserts the word "unpaid" appears nowhere on such a page.
- Reconciliation was not touched. `aggregateSales` reads only the fields it
  names, and no Functions source changed in this chunk.

Deliberately outside this chunk, and important for the next session:

- **Nothing constructs a `CheckoutDraftRequest` outside tests.** The write half
  of the tender is still unreachable and stays unreachable until the checkout
  screen exists; that is this chunk's boundary, not an oversight. The read half
  is reachable today.
- A per-tender sales breakdown is not here and is not implied by recording the
  tender. It is new work in `functions/src/operations/domain.ts`.
- Password reset remains blocked on the App Check decision recorded near the top
  of this file.

Files in this chunk:

```text
PLAN.md
firestore.rules
lib/checkout/checkout.dart
lib/checkout/checkout_draft.dart
lib/checkout/checkout_sale.dart
lib/checkout/checkout_tender.dart
lib/sales/receipt_lookup_panel.dart
lib/sales/sale_history.dart
lib/sales/sale_history_panel.dart
rules-tests/test/checkout-submission.test.js
rules-tests/test/stock-and-sales.test.js
test/checkout/checkout_draft_test.dart
test/checkout/checkout_sale_test.dart
test/checkout/checkout_submission_test.dart
test/checkout/checkout_sync_test.dart
test/sales/receipt_lookup_panel_test.dart
test/sales/sale_history_panel_test.dart
test/sales/sale_history_test.dart
test/shift/shift_checkout_binder_test.dart
```

Validation evidence after implementation code was frozen:

- `flutter analyze --no-pub lib/audit lib/inventory lib/returns lib/reporting
  lib/sales lib/shift lib/checkout lib/tenancy lib/main.dart test/audit
  test/inventory test/returns test/reporting test/sales test/shift test/checkout
  test/tenancy` reported one pre-existing issue and nothing else: the Sentry
  `profilesSampleRate` experimental warning at `lib/main.dart:28`.
- `flutter test --no-pub --concurrency=1 --reporter=failures-only test/audit
  test/inventory test/returns test/reporting test/sales test/shift test/checkout
  test/tenancy` passed **800/800** relevant Flutter tests, up from 789, adding
  **11** tests: 4 payload-contract cases, 1 draft case, 3 sale read-model cases,
  and 3 widget cases across the two panels.
- `npm --prefix rules-tests run test:emulator` passed the Firestore Rules
  emulator suite **125/125**, up from 120, adding **5** rules tests: the three
  accepted tenders, ten refused tender shapes, the v1 compatibility pair, four
  refused schema versions, and the maximum-size v2 budget case.
- With `FUNCTIONS_DISCOVERY_TIMEOUT=60`,
  `npm --prefix rules-tests run test:emulator:invitations` passed **12/12** real
  Auth, Firestore, and Functions emulator integration tests.
- `npm --prefix functions test` was **deliberately not re-run**.
  `git diff --stat HEAD -- functions` was empty, so all 166 Functions tests
  remain byte-identical to this session's green integration environment and no
  Dart or Rules change can reach them.
- `git diff --check` was clean; only the expected Windows CRLF advisories for
  the two `rules-tests` files were printed. Android build and Android emulator
  validation were intentionally skipped as requested.

Meaningful failures and their resolutions:

- **The full Rules suite failed 2/125 on its first run**, in
  `rules-tests/test/stock-and-sales.test.js`: "a valid sale uses its
  deterministic checkout ID and is immutable" and "sale line validation covers
  all 16 supported positions and rejects overflow". Cause: that file's `sale()`
  fixture omitted `payloadSchemaVersion` entirely, which the old rule ignored
  and the new rule requires. This was the tightening working as intended on a
  fixture, not a regression in a client - `_saleFields` has always written the
  field. Resolved by giving the fixture `payloadSchemaVersion: 2` and a tender,
  and by adding an explicit `no-schema-version` denial case so the new
  requirement is proved rather than merely satisfied.
- **The emulator log showed "maximum of 1000 expressions" traces**, which is the
  exact hazard the sale rules comment warns about, so it was investigated rather
  than accepted. Every occurrence was inside a *denial* trace, where Firestore
  enumerates reasons for an already-refused batch; no successful commit produced
  one. It was proved rather than argued: the new maximum-size 16-line v2 sale
  test commits successfully.
- No other test assertion failed. The focused two-file Flutter command and the
  focused checkout-submission emulator command were green on first execution.

The existing user-owned local edits remain separate and must not be staged:

```text
.vscode/settings.json
android/gradle.properties
pubspec.lock dependency-resolution updates for characters, matcher,
material_color_utilities, meta, test_api, and the Dart SDK constraint
```

### Next bounded chunk

The tender contract is settled, so the next chunk is the **first reachable
checkout surface**: a guarded cart screen that lets a cashier build a sale and
save it offline, and nothing beyond that.

1. Add a guarded checkout route reachable only from the current safe tenant
   shell, reading products from the existing `HiveCheckoutCatalogCache`. It must
   not make any legacy operational POS screen reachable.
2. Compose `CheckoutDraftService` in `lib/main.dart` for the first time. Note
   what it already requires and do not weaken any of it: a `CheckoutShiftBinder`
   from the guarded shift lifecycle, the receipt counters, the outbox, and the
   session controller. A checkout with no proven open shift must stay refused.
3. Let the cashier pick exactly one `CheckoutTender` before the draft can be
   saved. There must be no default selection and no way to save without one -
   the payload contract already refuses an absent tender, and the screen must
   refuse it earlier and more legibly than a format exception.
4. End the chunk at `saveOffline`. Submission, confirmation, and recovery are
   already implemented and already automatic; this chunk adds no submit button,
   no retry, and no cancel.
5. Map every `CheckoutDraftException` code to a bounded message. Count them
   before estimating: there are **18 raised directly** in `checkout_draft.dart`,
   plus **4 shift-binder refusals** passed through verbatim (`no_open_shift`,
   `other_tenant_shift_open`, `shift_closing`, `shift_not_confirmed`), plus the
   `CheckoutReceiptException` codes rethrown as draft codes by
   `_resolvedDeviceId` and `allocateSequence` (`receipt_sequence_exhausted`,
   `malformed_receipt_counter`, `malformed_device_identity`) - about **25**
   distinct outcomes a cashier can reach. They are not one message: a closed
   shift, an open shift in another business, an exhausted receipt counter, and
   corrupt device identity each need a different next action. A screen that
   surfaces a raw code has not finished the work.
6. Add widget coverage for: a saved draft appearing in the existing evidence
   panel, a refused draft leaving nothing persisted, each distinct refusal
   message, a tenant switch during an outstanding save, and the no-open-shift
   refusal.
7. Leave receipt printing, the printed receipt body, a per-tender reporting
   breakdown, password reset, product cost/profit fields, `getSalesComparison`,
   a `platform_audit_logs` surface, subscription and branding surfaces,
   deployment, and Android build/emulator validation outside that chunk.

One scope question that chunk must answer explicitly rather than discover:
**does the cart expose the discount?** `CheckoutDraftRequest.discountMinor`
already exists, is already bounded by `invalid_discount`, and is already written
into the payload and the sale. So the screen either offers discount entry or
pins it to zero, and pinning it to zero is a real product answer - a discount a
cashier can apply at the till without a role check is a cash-shrinkage path, and
nothing in this app currently authorizes one. Decide it in the chunk; do not
leave the field reachable by accident.

---

## Reachable point-of-sale till handoff - 2026-08-02

### Completed in this session

The app can sell. A cashier reaches a till from the safe landing route, builds a
cart from the device's own offline catalog, states how the customer paid, and
saves the sale to the encrypted outbox - which the existing submission and
recovery workers then carry to Firestore on their own.

This was built as three separately committed increments, each with its own tests
green before the next began: the refusal vocabulary, the cart panel, then the
composition-root wiring.

Implemented behavior and safety decisions:

- **The discount is pinned to zero and has no control.** This was the scope
  question the previous handover refused to leave implicit.
  `CheckoutDraftRequest.discountMinor` exists and is validated, so a field wired
  to it would have handed every cashier an unaudited way to reduce a sale. No
  role check authorizes a till discount anywhere in this system, so offering one
  would have created a cash-shrinkage path nothing reviews. A widget test pins
  `discountMinor == 0` on every saved request, so re-introducing it has to be
  deliberate.
- **There is no default tender and no way to save without one.** The payload
  contract already refuses an absent tender; the screen refuses it earlier and
  more legibly, naming the reason next to a disabled button rather than
  presenting a dead control. A pre-selected method would be indistinguishable
  from one somebody observed.
- **Every refusal has its own sentence, and says who can clear it.**
  `CheckoutRefusal` maps 26 codes drawn from four different files. The
  classification that matters is not severity but whether the person at the till
  can act: `cashierCanFix` is false for a damaged receipt counter, a damaged
  device identity, an exhausted daily sequence, and an encryption-key failure,
  and the screen then says that retrying will not help. That is not cosmetic -
  the receipt counter is deliberately refused rather than restarted, because
  restarting it would reissue a receipt number a committed sale already carries,
  so inviting a retry there would invite exactly the wrong action forever.
- **An unrecognised code fails closed** to a generic sentence with
  `cashierCanFix: false`, and a failure that is not a `CheckoutDraftException`
  at all - a storage fault - still reaches the till as a sentence rather than a
  crash. A unit test drives every known code plus unknown input through both.
- **No message can leak a machine code.** A test asserts every sentence is plain
  ASCII, contains no underscore, is trimmed, ends in a full stop, and is between
  20 and 220 characters. The ASCII rule also caught this session's own slip: the
  first draft of the file introduced the only typographic apostrophes in the
  codebase, which the existing surfaces avoid by never using possessives.
- **The panel ends at `saveDraft`.** There is no submit, retry, or cancel
  control, matching the read-only evidence panel. Submission, confirmation, and
  recovery stay owned by the workers.
- **A refused sale keeps the cart; only a durable save clears it.** The cashier
  never has to ring a sale up twice because of a refusal, and the tender clears
  with the cart so it is never carried into the next customer unobserved.
- **Two narrow interfaces replaced two concrete dependencies.**
  `CheckoutCatalogSource` and `CheckoutDraftSink` now stand between the screen
  and `HiveCheckoutCatalogCache`/`CheckoutDraftService`. This is the same
  boundary `CheckoutShiftBinder` and `CheckoutEvidenceSource` already draw, and
  it means a checkout surface cannot reach the cache's write path, the session
  controller, the outbox, or the receipt counters.
- **`CheckoutSavedDraft` is what a surface learns from a save** - the checkout
  ID and the receipt - rather than the outbox record. No screen can read a
  lease, an attempt count, or a payload hash, so none can be tempted to act on a
  state the workers own.
- **The till opens under the same session scope as every read route**, and
  receives the live session controller, so a business switch invalidates a sale
  in progress exactly as it invalidates a read. The route appears only when the
  composition root injects one; a test proves the shell offers no till on its
  own.
- The draft service is constructed per navigation because it must bind to the
  live controller. That is safe: receipt allocation and every outbox mutation
  serialize on locks held by the boxes themselves, not by the service, so two
  instances can never issue the same receipt number.

Deliberately outside this chunk, and important for the next session:

- No receipt is printed and no printed receipt body exists. The cashier is told
  the receipt number; handing it to a customer on paper is a separate chunk.
- The cart offers no search, no categories, and no barcode entry. It lists the
  cached products as buttons, which is honest for a first till and will not
  scale past a small catalog.
- Nothing here submits, retries, or cancels a checkout.

Files in this chunk:

```text
PLAN.md
lib/checkout/checkout.dart
lib/checkout/checkout_cart_panel.dart
lib/checkout/checkout_catalog_cache.dart
lib/checkout/checkout_draft.dart
lib/checkout/checkout_refusal.dart
lib/main.dart
lib/tenancy/tenant_routing_shell.dart
test/checkout/checkout_cart_panel_test.dart
test/checkout/checkout_refusal_test.dart
test/tenancy/tenant_routing_shell_test.dart
```

Validation evidence after implementation code was frozen:

- `flutter analyze --no-pub lib/audit lib/inventory lib/returns lib/reporting
  lib/sales lib/shift lib/checkout lib/tenancy lib/main.dart test/audit
  test/inventory test/returns test/reporting test/sales test/shift test/checkout
  test/tenancy` reported one pre-existing issue and nothing else: the Sentry
  `profilesSampleRate` experimental warning at `lib/main.dart:28`.
- `flutter test --no-pub --concurrency=1 --reporter=failures-only test/audit
  test/inventory test/returns test/reporting test/sales test/shift test/checkout
  test/tenancy` passed **825/825**, up from 800, adding **25** tests: 7 refusal
  cases, 16 cart cases, and 2 routing-shell cases.
- `git diff --check` was clean.
- **The emulator suites were deliberately not re-run.**
  `git diff --stat 1322371..HEAD -- firestore.rules functions rules-tests` was
  empty, so all three remain byte-identical to the tender commit's green run -
  Rules **125/125**, Functions **166/166**, integration **12/12** - and this
  chunk changed only Dart. Android build and Android emulator validation were
  intentionally skipped as requested.

Meaningful failures and their resolutions:

- **The cart widget tests hung twice, for two stacked reasons, and the second
  one was a design fault rather than a test fault.** First, `pumpAndSettle`
  never returns while `TenantRouteGuard`'s default `CircularProgressIndicator`
  is on screen; the panel now supplies its own non-animating loading widget,
  which is better till behavior anyway. Second - and the real cause - the panel
  depended on `HiveCheckoutCatalogCache` and `CheckoutDraftService` concretely,
  so every widget test drove real encrypted disk I/O under a faked clock.
  `tester.pump` advances only fake time, so saves never completed; worse, the
  outbox serializes on a **static** per-box lock, so one abandoned mid-flight
  operation deadlocked every later test in the file. Introducing
  `CheckoutCatalogSource` and `CheckoutDraftSink` removed real I/O from the
  widget tests entirely: the file went from hanging past 500 seconds to passing
  in 15. The lesson worth keeping: a widget test that needs `runAsync` to pass
  is usually reporting a missing seam, not a timing problem.
- **The refusal mapping introduced the codebase's only typographic
  apostrophes.** Caught by grepping the existing surfaces rather than by a test,
  then pinned with an ASCII assertion. Removing them mechanically also dropped
  an article in two sentences ("cannot number receipt"), which the review of the
  applied diff caught.
- **The `checkout-failure` key was on a `Center`, not the `Text` it wrapped**,
  so the test that reads that message cast the wrong widget. The key moved to
  the `Text`.
- No other assertion failed. The refusal unit tests, the routing-shell tests,
  and the full suite were green on first execution.

The existing user-owned local edits remain separate and must not be staged:

```text
.vscode/settings.json
android/gradle.properties
pubspec.lock dependency-resolution updates for characters, matcher,
material_color_utilities, meta, test_api, and the Dart SDK constraint
```

### Next bounded chunk

The till works but is only usable for a demonstration-sized catalog: it renders
every cached product as a button, with no way to find anything. Make the cart
usable at a real till, and nothing else:

1. Add product search and category filtering to the cart, reading only the
   already-cached `CheckoutCatalogSnapshot`. It must issue no Firestore read:
   the whole point of the offline design is that a sale can be built with no
   network at all.
2. Add direct quantity entry, so selling twelve of something is not twelve taps.
   Keep the existing bounds - the draft still refuses a quantity outside 1 to
   1,000,000, and the cart still refuses a seventeenth line.
3. Show the cached stock figure per product, and decide explicitly whether the
   till refuses to sell below zero. Note before deciding: Firestore Rules
   deliberately permit signed stock, an offline device cannot know the true
   figure, and `checkout-submission.test.js` already proves a sale below zero
   commits. Refusing at the till would therefore be a local convenience, not a
   guarantee - and it would block a legitimate sale whenever the cached figure
   is merely stale. Record the answer either way.
4. Keep the receipt confirmation visible long enough to be read and copied; a
   cashier who taps save and immediately serves the next customer currently
   loses the number when the cart is next touched.
5. Add widget coverage for search, filtering, quantity entry, the stock display,
   and whatever step 3 decides.
6. Leave receipt printing, the printed receipt body, discounts, a per-tender
   reporting breakdown, password reset, product cost/profit fields,
   `getSalesComparison`, a `platform_audit_logs` surface, subscription and
   branding surfaces, deployment, and Android build/emulator validation outside
   that chunk.

---

## Usable till handoff - search, quantity, stock, receipt - 2026-08-02

### Completed in this session

The till stopped being demonstration-sized. A cashier can find a product in a
real catalog, sell twelve of it in one entry, see what this device last knew
about its stock, and still read the receipt number after the next customer has
been started. Only `lib/checkout/checkout_cart_panel.dart` and its test changed:
no contract, no rule, and no Functions source was touched.

Implemented behavior and safety decisions:

- **The cached stock figure is stated and never blocks a sale.** This was the
  scope question the previous handover refused to leave implicit, and the answer
  is that the till does not refuse to sell below zero. Three facts decide it and
  none of them is a preference: Firestore Rules deliberately permit signed
  stock, `checkout-submission.test.js` already proves a sale below zero commits,
  and an offline device holds a figure that was true at the last sync rather
  than now. A refusal here would therefore guarantee nothing on the server while
  reliably blocking a legitimate sale whenever the cache is merely stale. The
  existing stock surface already tells operators the same thing in the same
  words - "a sale is never blocked by a stock count" - so refusing at the till
  would also have made two screens disagree. Instead the product tile states the
  figure, the catalog header states when it was read, and a line that exceeds
  the cached figure carries a warning that says explicitly it is not a block.
  Widget tests pin both the warning and the sale going through, including a
  product whose cached quantity is already negative.
- **Search and filtering read the snapshot already in hand.** A test asserts the
  catalog source is read exactly once across two searches and two category
  changes. This is the whole point of the offline design: a sale must be
  buildable with no network, so a keystroke may not reach storage, let alone
  Firestore.
- **A product naming a category this device does not hold stays reachable.**
  Categories and products are paged separately and bounded separately, so the
  cache can legitimately hold a product whose category it does not. Filtering by
  the cached categories alone would have silently hidden something the till can
  sell, so an `Other` chip appears exactly when such a product exists. The
  filter also does not use a sentinel category ID - a real category could be
  named anything, including the sentinel - so the selection is a nullable ID
  plus an explicit `uncached only` flag.
- **A typed quantity that is not usable keeps the line and is left on screen.**
  The line retains its last usable quantity, so a half-typed number can never
  become the sale, and saving is blocked with a sentence naming the bound. The
  field is deliberately **not** snapped back to the last good value: doing so
  would leave a valid number on screen beside a message saying the quantity is
  wrong, with nothing left to correct. `_QuantityField` therefore overwrites
  itself only when the cart actually moved the number - a plus or minus tap -
  which is also what keeps the cursor from jumping mid-entry.
- **The monetary bound is refused at the till rather than by the payload.**
  Direct quantity entry makes an oversized sale reachable for the first time.
  The frozen contract refuses it as `draft_contract_violation`, whose mapped
  sentence tells a cashier to ask for help when the real answer is to type a
  smaller number. The cart now checks both the per-line total and the cart total
  against `maximumCheckoutMinorAmount`, and two tests cover them separately -
  one line past the bound, and two lines each inside it whose sum is not.
- **The receipt survives the next cart edit and is cleared only deliberately.**
  This reverses the previous chunk's rule, and the reason is that the rule was
  attached to the wrong thing: a refusal describes the cart on screen, but a
  receipt number describes a sale that is already finished. It is now cleared by
  the next save attempt or by the cashier closing it, and the sentence says so.
  A refused save also takes the earlier number off screen, because an older
  receipt sitting beside a refusal reads as if the refused sale saved.
- **A save that carried no receipt number now reports itself.**
  `CheckoutSavedDraft.receiptNumber` is nullable, and the previous panel rendered
  that case as silence - a durable, syncing sale with no confirmation at all,
  which is how the same sale gets rung up twice. It now says the sale is kept,
  says the number is unavailable, and offers no copy button to press.
- **A business switch destroys the cart rather than tidying it.** The cart moved
  into a `_CartEditor` keyed by `uid:tenantId:epoch`, so a tenant switch unmounts
  it and takes the lines, the search text, the chosen tender, and the previous
  receipt with it. The prior design cleared state by hand and could not clear the
  search controller safely from inside a build; a key does it structurally and
  cannot be forgotten in a later edit.
- **The till returns to neutral after a durable save.** The search box and the
  category filter clear with the cart, so the next customer is not served from a
  catalog narrowed by the previous one.
- The discount is still pinned to zero with no control, and there is still no
  default tender, no submit, no retry, and no cancel.

Deliberately outside this chunk, and important for the next session:

- No receipt is printed and no printed receipt body exists. Copying the number
  to the clipboard is not printing it.
- The catalog is still a flat wrap of buttons; there is no barcode entry, no
  scanner, and no paging for a very large catalog.
- Nothing here submits, retries, or cancels a checkout.

Files in this chunk:

```text
PLAN.md
lib/checkout/checkout_cart_panel.dart
test/checkout/checkout_cart_panel_test.dart
```

Validation evidence after implementation code was frozen:

- `flutter analyze --no-pub lib/audit lib/inventory lib/returns lib/reporting
  lib/sales lib/shift lib/checkout lib/tenancy lib/main.dart test/audit
  test/inventory test/returns test/reporting test/sales test/shift test/checkout
  test/tenancy` reported one pre-existing issue and nothing else: the Sentry
  `profilesSampleRate` experimental warning at `lib/main.dart:28`.
- `flutter test --no-pub --concurrency=1 --reporter=failures-only test/audit
  test/inventory test/returns test/reporting test/sales test/shift test/checkout
  test/tenancy` passed **850/850**, up from 825, adding **25** cart tests: 8 for
  search and category filtering, 6 for typed quantity and the monetary bound, 4
  for the stock display, 5 for the receipt, and 2 for what a business switch
  destroys.
- The focused file command
  `flutter test --no-pub --concurrency=1 test/checkout/checkout_cart_panel_test
  .dart` passed **41/41** during development.
- `git diff --check` was clean.
- **The emulator suites were not re-run for this chunk.** `git diff --stat
  1322371..HEAD -- firestore.rules functions rules-tests` is empty, so Rules
  **125/125**, Functions **166/166**, and integration **12/12** remain
  byte-identical to the tender commit's green run, and this chunk changed one
  Dart file. Android build and Android emulator validation were intentionally
  skipped as requested.

Meaningful failures and their resolutions:

- **The monetary-bound test failed on its first run** because the arithmetic in
  the test was wrong, not the code: 1,000,000 x KES 120.50 is 1.205e10 minor,
  well inside the 1e11 bound, so nothing blocked and `checkout-save-blocked` was
  absent. Resolved by pricing a fixture product at KES 250,000 to cross the
  line bound, and by adding a second case with two lines each inside the bound
  whose sum is not - which also proved the cart-total branch that the first case
  never reached.
- **`SystemChannels` is not exported by `material.dart`.** The analyzer first
  reported `package:flutter/services.dart` as an unnecessary import, because the
  clipboard test had not been written yet; it is required once
  `SystemChannels.platform` is mocked.
- No other assertion failed.

The existing user-owned local edits remain separate and must not be staged:

```text
.vscode/settings.json
android/gradle.properties
pubspec.lock dependency-resolution updates for characters, matcher,
material_color_utilities, meta, test_api, and the Dart SDK constraint
```

---

## Reconciliation can be asked for - 2026-08-02

### Completed in this session

`requestTenantReconciliation` has a caller. It was the second row of the
"Built, tested, and unreachable" table near the top of this file - server-side
complete with passing tests and no client entry point - and the recommended
order there was the checkout screen first, then the smaller unreachable rows.
The checkout screen is done, so this is that row.

An owner or administrator can now ask the server to reconcile from the
reconciliation status route, choosing a catch-up or a full check. Nothing else
about reconciliation became reachable: no retry, no cancel, no re-ordering, and
no way to aim a run at a particular day.

Implemented behavior and safety decisions:

- **The request is described as what the server actually does, not as what the
  page is about.** This is the decision that shaped the whole surface.
  `requestTenantReconciliation` files one job for the **whole business** under
  **today's** business date, and `processMetricsPage` then takes the oldest
  outstanding day in the business rather than the day the run was queued for. A
  button on a page titled "Reconciliation for 2026-07-15" therefore does not
  reconcile 2026-07-15, and a run queued from that page will not even appear in
  the list below it. The surface says so in its own keyed sentence, and the
  success notice repeats it. Labelling it "reconcile this day" would have been a
  promise the server never made.
- **Requesting is owner and administrator only, and a manager is told why.**
  `RECONCILIATION_REQUEST_ROLES` is `["owner", "admin"]`, deliberately narrower
  than the owner/admin/manager who may *read* this page. The sibling stock
  surface hides its form from anyone who cannot use it; this one shows a
  sentence instead, because a role boundary that is narrower than the page it
  sits on is surprising, and silence would read as a missing feature. The client
  refuses before the callable is reached, so an unauthorized session spends no
  round trip and creates no idempotency record.
- **The business is never an input.** The gateway is bound to one captured
  session and the only thing a caller chooses is the mode, so nothing can ask
  the server to reconcile another business. An intent created against one tenant
  and submitted through a gateway bound to another raises a `StateError` before
  the callable is reached, and a test proves nothing was sent.
- **Only an unknown outcome may have queued anything.** The handler enqueues the
  Cloud Task **after** its transaction commits, so a transport failure can leave
  a real job document behind. `mayHaveQueued` is true for `ambiguous` alone, and
  only that case keeps its request ID so a retry addresses the same idempotency
  record instead of spending the cooldown twice. Every settled refusal - denied,
  cooled down, duplicate, invalid - drops the ID, because reusing it would make
  the next attempt fail as a duplicate of an attempt that changed nothing.
- **`aborted` is classified as unknown, not refused.** It is the idempotency
  helper reporting that this exact request is still in flight, which means a job
  may already exist for it. Unlike the stock gateway, no case here is decided by
  matching an error *message*: every distinct condition the handler raises
  already carries its own code, so the classification is a pure code switch and
  cannot drift when server wording changes.
- **The response is reconciled against the intent.** It must name this business,
  the mode that was asked for, and the status `queued` - the only status the
  handler ever writes. A response failing any of those is a `FormatException`,
  and the page then says the answer could not be trusted, re-reads itself, and
  does **not** claim a job. Telling an owner their business is being re-checked
  on the strength of an answer that named another business would be worse than
  saying nothing.
- **Both cooldowns are stated before the tap and after a refusal.** The server
  allows one catch-up every 5 minutes and one full check every 24 hours, and the
  app cannot shorten either. The confirmation dialog names the cost, and the
  `resource-exhausted` notice names both allowances so the person knows how long
  the door is shut.
- The page re-reads itself after a success, an unknown outcome, and an
  untrustworthy answer, for the same reason the stock surface re-reads: what is
  shown must be the server's own record rather than an optimistic local one.

Deliberately outside this chunk, and important for the next session:

- Nothing here retries, cancels, quarantines, or re-orders a run, and nothing
  can target a specific business day. Those belong to the reconciliation
  workers.
- `getSalesComparison`, the subscription surfaces, and product cost/profit
  remain the unreached rows of that table. Password reset is still blocked on
  the App Check decision.

Files in this chunk:

```text
PLAN.md
lib/main.dart
lib/reporting/reconciliation_actions.dart
lib/reporting/reconciliation_request.dart
lib/reporting/reconciliation_status_panel.dart
lib/reporting/reporting.dart
test/reporting/reconciliation_request_test.dart
test/reporting/reconciliation_status_panel_test.dart
```

Validation evidence after implementation code was frozen:

- `flutter analyze --no-pub lib/audit lib/inventory lib/returns lib/reporting
  lib/sales lib/shift lib/checkout lib/tenancy lib/main.dart test/audit
  test/inventory test/returns test/reporting test/sales test/shift test/checkout
  test/tenancy` reported one pre-existing issue and nothing else: the Sentry
  `profilesSampleRate` experimental warning at `lib/main.dart:28`.
- `flutter test --no-pub --concurrency=1 --reporter=failures-only test/audit
  test/inventory test/returns test/reporting test/sales test/shift test/checkout
  test/tenancy` passed **886/886**, up from 850, adding **36** tests: 27 gateway
  cases - including all 13 error codes classified one by one - and 9 widget
  cases covering the role boundary, the scope sentence, confirmation and
  cancellation, the cooldown notice, request-ID retention in both directions,
  and an untrustworthy answer.
- `git diff --check` was clean.

Meaningful failures and their resolutions:

- **The first gateway test failed on its first run** because the fixture
  response said `mode: incremental` while the intent asked for `full`. The
  failure was the response check working exactly as designed - a response naming
  another mode is refused - so the fixture was corrected rather than the check.
- No other assertion failed.

The existing user-owned local edits remain separate and must not be staged:

```text
.vscode/settings.json
android/gradle.properties
pubspec.lock dependency-resolution updates for characters, matcher,
material_color_utilities, meta, test_api, and the Dart SDK constraint
```

### Session validation after both chunks were frozen

The two chunks above were committed separately, each with its own Dart tests
green first. This is the one release-style sequence run afterwards, with no code
edited between it and this text.

| Command | Result |
| --- | --- |
| `flutter analyze --no-pub` over the 17 in-scope lib/test paths | 1 pre-existing issue: the Sentry `profilesSampleRate` warning at `lib/main.dart:28` |
| `flutter test --no-pub --concurrency=1 --reporter=failures-only test/audit test/inventory test/returns test/reporting test/sales test/shift test/checkout test/tenancy` | **886/886**, up from 825 at session start |
| `npm --prefix rules-tests run test:emulator` | **125/125** |
| `FUNCTIONS_DISCOVERY_TIMEOUT=60 npm --prefix rules-tests run test:emulator:invitations` | **12/12** real Auth, Firestore, and Functions emulator tests |
| `npm --prefix functions test` | **166/166** |
| `git diff --check` | clean |

`git diff --stat 3cb7588..HEAD -- functions firestore.rules rules-tests
firestore.indexes.json` is empty: this session changed only Dart. The three
backend suites were run anyway rather than inherited, because the last handover
inherited them and one more green sequence is cheaper than an assumption.
Android build and Android emulator validation were intentionally skipped as
requested.

**The emulator toolchain broke and the fix belongs in every future handover.**
The first Rules run failed immediately with `firebase-tools no longer supports
Java version before 21`. The machine's default `java` is now Temurin **17.0.20**
(`JAVA_HOME=C:\Users\BonifaceMasota\develop\jdk-17`), which earlier sessions did
not face. The pinned portable runtimes recorded further up this file are still
present and still work; the exact prelude that makes every emulator command
succeed on this host is:

```powershell
$env:DEBUG = $null
$env:JAVA_HOME = 'D:\firebase-emulator-tools\jdk21\jdk-21.0.12+8'
$env:Path = "$env:JAVA_HOME\bin;D:\firebase-emulator-tools\node-v24.18.1-win-x64;$env:Path"
```

Note the path: the JDK is nested one level inside `jdk21`, and the older
`C:\tmp\chilltent-jdk21\jdk-21.0.12+8` location quoted around line 1091 also
still exists. Clearing `DEBUG` matters for the same reason recorded in the test
instructions - the machine sets `DEBUG=release`, which Firebase treats as debug
mode and answers with enormous logs.

### Next bounded chunk

The till now scales for a shop with a few dozen products and stops scaling
somewhere well below the 2,000 the cache admits. Make it hold a real catalog,
and nothing else:

1. **Bound what is rendered.** `_catalogSection` builds a `Wrap` containing every
   matching product, and a `Wrap` builds all of its children eagerly even inside
   a `ListView`. `CheckoutCatalogCacheRefresher` caches up to
   `maximumProducts = 2000`, so an unfiltered till currently builds two thousand
   buttons every frame. Cap the rendered matches, state how many matched and how
   many are shown, and tell the cashier to narrow the search. Do not change what
   can be sold - only what is drawn.
2. **Add exact-code entry.** A retail barcode scanner presents itself as a
   keyboard, so submitting the search field should add the product whose SKU
   matches exactly, then clear the field ready for the next scan. Ambiguity must
   refuse rather than guess: no exact match, or more than one, adds nothing and
   says so. Explicitly **not** camera scanning - that needs a plugin, runtime
   permissions, and Android build validation, all of which are outside this.
3. **Add a bounded way to abandon a sale.** A customer who walks away currently
   costs the cashier one tap per line. One "clear this sale" control behind a
   confirmation, clearing the cart and the tender and nothing else. Nothing is
   saved at that point, so this destroys no record.
4. Add widget coverage for the cap and its message, an exact-code hit, both
   ambiguous cases, the field clearing after a scan, and clearing a sale
   including its confirmation being cancelled.
5. Leave receipt printing, the printed receipt body, discounts, a per-tender
   reporting breakdown, password reset, product cost/profit fields,
   `getSalesComparison`, a `platform_audit_logs` surface, subscription and
   branding surfaces, deployment, and Android build/emulator validation outside
   that chunk.

One thing that chunk should check rather than assume: whether the till's cached
SKUs are unique. `HiveCheckoutCatalogCache.write` rejects duplicate product
**IDs** and says nothing about SKUs, and nothing in the Firestore Rules requires
a unique SKU either. If two products can share one, step 2's "exactly one match"
rule is doing real work and needs a test with a genuine collision, not a
theoretical one.

---

## A till that holds a real catalog - 2026-08-02

### Completed in this session

The chunk defined immediately above, implemented in the same session. One file
and its test changed; no contract, no rule, and no Functions source was touched.

Implemented behavior and safety decisions:

- **A SKU is not unique, and the till is built on that fact.** This was the
  question the previous section said to check rather than assume, and the answer
  is that nothing enforces uniqueness: `firestore.rules` never mentions `SKU`,
  and `HiveCheckoutCatalogCache.write` refuses only duplicate product **IDs**.
  Two products really can carry one code, so code entry refuses that case
  outright instead of adding the first match. A widget test uses a genuine
  collision rather than a hypothetical one.
- **Submitting the search adds a product; it never guesses.** A retail barcode
  scanner presents as a keyboard, so a scan arrives as typed text plus a submit,
  and that is all this needs - no plugin, no permission, no Android build. The
  resolution order is: exactly one product whose code matches exactly, else
  exactly one product visible in the list, else nothing plus a sentence naming
  which of the two ambiguities occurred. Camera scanning stays out; it would
  need a plugin and the Android validation this session excludes.
- **A code is matched across the whole cached catalog, not the filtered view.**
  A scanned code is unambiguous evidence about what is in the cashier's hand, so
  a category chip set ten minutes ago must not make the scanner useless. The
  filter is left exactly as it was afterwards rather than silently reset,
  because a cashier scanning through one category should stay in it.
- **The search clears after a successful add and the field is left alone after
  a refusal.** The first is so the next scan starts clean. The second is the
  same rule the quantity field follows: text the cashier can correct must stay
  on screen.
- **Only 60 product buttons are drawn, and the count is stated.** A `Wrap`
  builds every child eagerly even inside a `ListView`, and
  `CheckoutCatalogCacheRefresher` caches up to `maximumProducts = 2000`, so the
  unbounded version built two thousand buttons every frame. The cap bounds
  drawing only: a test proves a product past the cap is still sellable by its
  code, so nothing became unreachable.
- **A sale can be abandoned in one action.** A customer who walks away
  previously cost one tap per line. The control appears only when there is
  something to abandon, sits behind a confirmation, and clears the cart and the
  tender together. Nothing is persisted before `saveDraft`, so this destroys no
  record - and the dialog says so rather than implying otherwise.
- **Clearing a sale leaves the last receipt on screen.** It describes a
  different, finished sale, which is the same rule the previous chunk
  established for cart edits.

Files in this chunk:

```text
PLAN.md
lib/checkout/checkout_cart_panel.dart
test/checkout/checkout_cart_panel_test.dart
```

Validation evidence after implementation code was frozen:

- `flutter analyze --no-pub` over the 17 in-scope lib/test paths reported one
  pre-existing issue and nothing else: the Sentry `profilesSampleRate` warning
  at `lib/main.dart:28`.
- `flutter test --no-pub --concurrency=1 --reporter=failures-only test/audit
  test/inventory test/returns test/reporting test/sales test/shift test/checkout
  test/tenancy` passed **901/901**, up from 886, adding **15** cart tests: 8 for
  code entry including the shared-SKU collision, 3 for the render cap, and 4 for
  clearing a sale.
- `git diff --check` was clean.
- The three backend suites were **not** re-run for this chunk. They were run
  green earlier in this same session - Rules **125/125**, integration **12/12**,
  Functions **166/166** - and `git diff --stat 3cb7588..HEAD -- functions
  firestore.rules rules-tests firestore.indexes.json` is still empty. Android
  build and Android emulator validation were intentionally skipped as requested.

Meaningful failures and their resolutions:

- **The truncation edit produced a collection-`if` that no longer closed.**
  Wrapping the product `Wrap` in a spread list needed a matching `]`, which the
  analyzer caught immediately at the next statement rather than at the edit.
  Caught before any test ran.
- No test assertion failed in this chunk.

### Next bounded chunk

The till and the reconciliation request are both done, so the next work is not
in the checkout at all. Two candidates, in the order recommended:

1. **`getSalesComparison` has no caller** and has been excluded by name for
   roughly sixteen consecutive chunks - the longest-standing row of the "Built,
   tested, and unreachable" table near the top of this file. Read the handler
   before scoping it: decide what question it answers that
   `TenantDailyMetricsRepository` does not, which roles may ask it, and whether
   its answer is a read model that needs the same strict decoding the
   reconciliation request result got. If it turns out to duplicate the daily
   summary, say so and delete the row rather than building a surface nobody
   needs.
2. **The subscription surfaces.** `TenantPaths.currentSubscription` exists and
   Rules exist, and no repository reads either. Spec line 14 names subscription
   as a per-business concern, so this is a real gap rather than an oversight -
   but it is a larger chunk than it looks, and it should start with a read-only
   surface, never a write.

Leave outside either chunk: receipt printing, the printed receipt body,
discounts, camera barcode scanning, a per-tender reporting breakdown, password
reset (still blocked on the App Check decision recorded near the top of this
file), product cost/profit fields, a `platform_audit_logs` surface, branding
surfaces, deployment, and Android build/emulator validation.

Two practical notes for whoever picks this up:

- The emulator prelude in the session-validation table above is not optional on
  this machine any more. The default `java` is JDK 17 and every emulator command
  fails immediately without it.
- The checkout cart panel is now over 900 lines and holds search, filtering,
  quantity entry, code entry, tender, saving, and the receipt. It is coherent,
  but the next feature added to it should probably arrive with a split rather
  than after one.

---

## What a business has taken today - 2026-08-02

### Completed in this session

Candidate 1 of the chunk above: `getSalesComparison` now has a caller. The
question it was read for first, and the answer, are recorded below because the
previous handover asked for a decision rather than an implementation.

**It does not duplicate the daily summary, and the row stays.** The handler
reads the live `sales` collection, so it can answer for a day nightly
reconciliation has not touched. `TenantDailyMetricsRepository` reads
`daily_metrics` documents, which the reconciliation processor is the only writer
of, so **today is normally blank there** - and "how much have we taken today?"
is the single most-asked question at a counter. It also accepts a `soldById`
filter and any range up to 366 days, neither of which a per-day document can
express. Three genuinely different capabilities; the surface was built.

Implemented behavior and safety decisions:

- **The server name is a leftover and the client does not repeat it.** The
  response carries one `previous` block and nothing to compare it against, so
  every Dart name calls it what it is - the totals for a stretch of days - while
  the wire fields stay exactly as the handler declared them
  (`previousStartDate`, `previousEndDate`, `soldById`).
- **Profit is parsed, validated, and never displayed.** No product in this app
  carries a cost: `TenantProduct` has `price` only, and `CheckoutDraft`
  therefore never sets `unitCostMinor`, so every sale line reaches the server
  without cost data. The server's `profit` consequently equals its revenue, and
  showing it would report a margin of 100%. The surface states the
  `incompleteCostLineCount` instead, which is the same rule
  `lib/reporting/daily_metrics.dart` already follows and the reason the "Product
  cost / profit" row of the unreachable table is still open.
- **An answer that counts differently from what it read is refused.** No
  category filter is ever sent, and without one the handler counts one
  transaction per sale it scanned, so `transactions` must equal
  `scannedTransactions`. A disagreement means the response describes some other
  request, and it is rejected rather than shown. This is the same strict
  decoding the reconciliation request result got, applied to the one number an
  owner would act on.
- **The period is four fixed choices, not a date picker.** The server refuses a
  range over 366 days and refuses any period holding more than `SALES_QUERY_LIMIT
  = 5000` sales, so a free date range is a refusal waiting to happen. Today,
  7, 30, and 90 days all answer a question somebody actually asks.
- **A refusal keeps the chooser on screen.** `resource-exhausted` is answered
  with "choose a shorter period", and that sentence is worthless if the failure
  state replaces the chooser it refers to. A widget test picks a shorter period
  straight out of the refusal.
- **`failed-precondition` is not a transport failure.** The aggregation helpers
  raise it when a stored sale amount cannot be added exactly; that is a data
  problem in the business's own sales and asking again will not change it, so it
  is classified separately from the codes a retry can fix. There is no ambiguous
  outcome at all here - a read writes nothing, so every refusal is safe to
  repeat.
- **The member is never an input.** `Only mine` sends the captured session's own
  UID, so the filter cannot be pointed at another cashier. The business comes
  from the same session, and a query created against one business is refused by
  a gateway holding another.
- **Reading roles are the server's `REPORTING_ROLES`**, asserted in a test to be
  identical to `TenantDailyMetricsRepository.allowedRoles`: a period total is
  the same information over a different stretch of days, so it must not be
  visible to anyone the daily summary is not.
- **Reached from the daily summary, not the landing screen.** The summary is
  where somebody reads "Today is normally still unreconciled"; the button sits
  directly under that sentence, because it is the answer to it. The route opens
  under the same session scope as every other guarded route.

Files in this chunk:

```text
PLAN.md
lib/main.dart
lib/reporting/daily_metrics_panel.dart
lib/reporting/reporting.dart
lib/reporting/sales_totals.dart          (new)
lib/reporting/sales_totals_panel.dart    (new)
test/reporting/daily_metrics_panel_test.dart
test/reporting/sales_totals_panel_test.dart  (new)
test/reporting/sales_totals_test.dart        (new)
```

Validation evidence after implementation code was frozen:

- `flutter analyze --no-pub` over the 17 in-scope lib/test paths reported one
  pre-existing issue and nothing else: the Sentry `profilesSampleRate` warning
  at `lib/main.dart:28`.
- `flutter test --no-pub --concurrency=1 --reporter=failures-only test/audit
  test/inventory test/returns test/reporting test/sales test/shift test/checkout
  test/tenancy` passed **941/941**, up from 901, adding **40** tests: 27 gateway
  cases - including all 13 error codes classified one by one, the range each
  period resolves to, and seven rejected responses - 11 panel cases, and 2
  daily-summary cases for the new route and its role gate.
- `git diff --check` was clean.
- No backend suite was re-run for this chunk: it changed only Dart, and
  `git diff --stat 3cb7588..HEAD -- functions firestore.rules rules-tests
  firestore.indexes.json` is still empty. The session-end backend sequence is
  recorded below.

Meaningful failures and their resolutions:

- **No test assertion failed in this chunk**; the gateway and both widget files
  passed on their first run.
- One layout decision was changed before any test ran. The period chooser was
  first a four-segment `SegmentedButton`, which does not fit across a phone;
  four chips in a `Wrap` do, and that is already the pattern the checkout
  category filter uses.

### The subscription surface was examined and deliberately not built

The other candidate the previous handover offered. It was read before it was
scoped, and it should not be built yet:

- **Nothing writes the document.** `grep -i subscription functions/src` finds
  nothing at all. `firestore.rules` allows `read: activeStaff || platformAdmin`
  and `write: if false`, so only the Admin SDK or the console could ever create
  one, and no code in this repository does.
- **No field schema exists anywhere.** The spec names the path
  `/tenants/{tenantId}/subscription/current` and stops. Rules validate no field,
  because nothing may write it. There is no fixture, no read model, and no
  handler to copy a shape from.
- Building a strict read model would therefore mean **inventing** the contract,
  and the surface would read "no subscription record" in every environment that
  exists today. That is the "surface nobody needs" the previous handover warned
  about, one step earlier in the same reasoning.

The row stays in the unreachable table, with this recorded as the reason.
Whoever revisits it should start on the server - decide what a subscription
actually constrains, and which writer owns it - not with a Flutter screen.

### Next bounded chunk

Finish `getSalesComparison`. Its fourth parameter, `categoryId`, is still
unreached, and reaching it requires correcting a rule the chunk above
deliberately made strict:

1. **Offer a category filter** on the totals surface, built from
   `TenantCatalogRepository.loadCategories` - the same canonical categories the
   checkout filters by. The panel needs a `TenantDataReader`; the daily summary
   route already has one to pass.
2. **The `transactions == scannedTransactions` invariant is only valid without
   a category.** `aggregateSales` skips a sale that holds no matching line, so
   with a category requested the server legitimately counts fewer transactions
   than it read. Make the check conditional - equal without a category, no
   greater than with one - and test both directions with a real fixture.
3. **A category total is a different figure and must say so.** Without a
   category the server prefers the recorded sale total; with one it sums the
   matching lines only. Those are not the same money, and a screen that shows
   them under one label is lying by omission.
4. **A failed category load must not remove the total.** The whole-business
   figure does not depend on the picker, so an unreadable category list should
   leave the surface working with no filter rather than fail the route.
5. Add coverage for the payload carrying `categoryId`, the relaxed invariant in
   both directions, the changed label, an unreadable category list, and the
   filter surviving a period change.
6. Leave outside it: a per-cashier picker built from
   `TenantStaffDirectoryRepository` (the natural chunk after this one), the
   subscription surfaces, receipt printing, the printed receipt body, discounts,
   camera barcode scanning, a per-tender reporting breakdown, password reset,
   product cost/profit fields, a `platform_audit_logs` surface, branding
   surfaces, deployment, and Android build/emulator validation.

One defect found while building the surface above and deliberately left alone:
**no reporting screen prints a currency.** The daily summary shows
`Sales: 1250.50` and the new totals screen shows the same. The checkout does it
correctly, from `TenantCheckoutConfiguration.currency`. Fixing it means giving
both reporting routes the configuration read, and it should be one chunk that
fixes both rather than a detail smuggled into a filter.

---

## Which category is actually selling - 2026-08-02

### Completed in this session

The chunk defined immediately above, implemented in the same session.
`getSalesComparison` now has no unreached parameter left: `tenantId`,
`previousStartDate`, `previousEndDate`, `soldById`, and `categoryId` are all
sent from the app.

Implemented behavior and safety decisions:

- **The count invariant is now conditional, and both directions are proved.**
  Without a category the server counts one transaction per sale it read, so the
  two counts must agree exactly - a difference either way is refused. With a
  category `aggregateSales` skips a sale holding no matching line, so fewer
  counted than read is the normal answer and is accepted, while *more* counted
  than read is still refused: the handler cannot count a sale it never read.
  The chunk above deliberately shipped the strict version; relaxing it was the
  precondition for reaching `categoryId` at all.
- **A category total is a different figure, and the screen says so in
  numbers.** Without a category the handler prefers each sale's recorded total;
  with one it sums the matching **lines** and leaves the rest of every sale out.
  The surface states which, and states how many of the sales read held nothing
  in that category - `scannedTransactions - transactions`, which is exactly
  what the relaxed invariant now permits to be non-zero.
- **A filter is applied only while this business's own canonical list still
  contains it.** The loader reads the categories first and drops a selection the
  list does not name, so a category chosen in one business can never filter
  another's sales after a tenant switch, and a deleted category silently reverts
  to the whole catalog instead of filtering by an ID that no longer exists. The
  chip shown as selected is read back from the answer's own query, so what is
  highlighted is always the filter the figure was actually read with.
- **An unreadable category list does not remove the total.** The figure a
  manager came for does not depend on the filter list, so a failed category read
  degrades to "no filter available" and leaves the totals working. The one
  exception is `TenantScopeViolation`, which is rethrown: a reader answering
  outside this tenant is a broken boundary, not an unavailable label, and it
  fails the route with no figure shown.
- **A business with no categories is offered no chooser at all** - distinct from
  one whose list could not be read, which says so.
- **An invalid category never leaves the app.** It is validated with
  `validateTenantDocumentId` and refused locally as `invalidRequest`, the same
  meaning the handler would return, rather than spent on a round trip.
- `categoryId` and `soldById` are **absent** from the payload rather than sent
  as `null` when unused, which a test asserts: the handler's optional-field
  parsing and a `null` are not the same thing over the wire.

Files in this chunk:

```text
PLAN.md
lib/main.dart
lib/reporting/sales_totals.dart
lib/reporting/sales_totals_panel.dart
test/reporting/sales_totals_panel_test.dart
test/reporting/sales_totals_test.dart
```

Validation evidence after implementation code was frozen:

| Command | Result |
| --- | --- |
| `flutter analyze --no-pub` over the 17 in-scope lib/test paths | 1 pre-existing issue: the Sentry `profilesSampleRate` warning at `lib/main.dart:28` |
| `flutter test --no-pub --concurrency=1 --reporter=failures-only test/audit test/inventory test/returns test/reporting test/sales test/shift test/checkout test/tenancy` | **953/953**, up from 901 at session start |
| `npm --prefix rules-tests run test:emulator` | **125/125** |
| `FUNCTIONS_DISCOVERY_TIMEOUT=60 npm --prefix rules-tests run test:emulator:invitations` | **12/12** real Auth, Firestore, and Functions emulator tests |
| `npm --prefix functions test` | **166/166** |
| `git diff --check` | clean |

The three backend suites cover **both** chunks of this session and were run once
after the second was frozen. `git diff --stat 3cb7588..HEAD -- functions
firestore.rules rules-tests firestore.indexes.json` is empty: this session
changed only Dart. They were run anyway rather than inherited, for the same
reason the previous session gave - one more green sequence is cheaper than an
assumption. Android build and Android emulator validation were intentionally
skipped as requested. The emulator prelude recorded further up this file
(JDK 21 at `D:\firebase-emulator-tools\jdk21\jdk-21.0.12+8`, portable Node 24,
`DEBUG` cleared) was required and worked unchanged.

Meaningful failures and their resolutions:

- **The first category widget test failed, and the repository was right.**
  `TenantReadRepository` proves that a collection page arrives in ascending
  document-ID order, and the test fake answered `['drinks', 'bread']` in map
  order. The repository raised `TenantScopeViolation`, the category load
  degraded, and the chip the test tapped was never built. The fake was corrected
  to sort - Firestore does - rather than the proof relaxed. This is the ordering
  check doing exactly its job on a fixture that did not model the real reader.
- **One assertion was over-strict and was corrected, not the code.** The
  scope-violation test asserted the "category list unavailable" note was absent
  on a failed route. It is present, and truthfully so: that read is precisely
  what failed. The test now asserts the generic failure sentence and that no
  figure and no chip are shown.
- No other assertion failed.

The existing user-owned local edits remain separate and were never staged:

```text
.vscode/settings.json
android/gradle.properties
pubspec.lock
```

### Next bounded chunk

Two candidates, in the order recommended:

1. **Print the currency on both reporting routes.** Recorded as a defect one
   section above and still true: the daily summary and the totals screen both
   show a bare `1250.50`, while the checkout correctly prints
   `TenantCheckoutConfiguration.currency`. Give both reporting routes the same
   configuration read, decide what a missing or unreadable configuration
   document shows - a bare number is the honest fallback, an assumed `KES` is
   not - and cover both. Small, self-contained, and it removes an ambiguity from
   every figure the app reports.
2. **A per-cashier picker for the totals surface.** `TenantSalesScope` is
   currently `everyone` or `mine`; the server accepts any `soldById`, and
   `TenantStaffDirectoryRepository` already lists canonical staff with names.
   Check one thing before scoping it: that repository reads the **tenant root**
   document to find the owner UID, so confirm a manager may read it before
   assuming the picker works for every role the totals surface is open to. If
   not, the picker is owner/admin-only and the surface must say so rather than
   fail. Apply the same rule this chunk established for categories: a UID not in
   this business's own directory is never sent.

Leave outside either chunk: the subscription surfaces (examined and declined
above - start on the server, not in Flutter), receipt printing, the printed
receipt body, discounts, camera barcode scanning, a per-tender reporting
breakdown, password reset (still blocked on the App Check decision recorded near
the top of this file), product cost/profit fields, a `platform_audit_logs`
surface, branding surfaces, deployment, and Android build/emulator validation.

Two practical notes carried forward:

- The emulator prelude is not optional on this machine. The default `java` is
  JDK 17 and every emulator command fails immediately without it.
- `lib/reporting/sales_totals_panel.dart` now holds the period, scope, and
  category choosers plus the failure surface. It is still coherent at its
  current size, but a third filter should arrive with a split of the chooser
  row rather than after one - the same note the checkout cart panel carries.

---

## Every reported figure now names its currency - 2026-08-02

### Completed in this session

Candidate 1 of the chunk above, implemented in the same session. Both reporting
routes printed bare amounts; both now print the code the business published, or
say plainly that there is none.

Implemented behavior and safety decisions:

- **No currency is ever assumed, and there is no default.** The app targets no
  single country and the frozen model records the code per business in
  `configuration/checkout` precisely so nothing has to guess. A business trading
  in one currency and reported in another is a worse error than an unlabelled
  number, so a missing, unreadable, or malformed configuration produces a bare
  figure plus one sentence saying why - never `KES`, never a symbol.
- **The unlabelled case is genuinely the unconfigured one.** A business that has
  published no `configuration/checkout` cannot use the till at all:
  `CheckoutCatalogCacheRefresher` refuses with `configurationUnavailable`. So a
  business with sales to report has a currency, and the notice is a real
  configuration gap rather than routine noise. This is recorded in the read
  model itself, because it is the reason the degrade is acceptable.
- **A label may never cost a figure.** The currency is read after the figures on
  both routes and its failure is swallowed, so an offline or denied
  configuration read leaves the daily summary and the totals working exactly as
  before. The one exception is `TenantScopeViolation`, which is rethrown - the
  same rule the category list follows, for the same reason: a reader answering
  outside this tenant is a broken boundary, not a missing label.
- **A malformed code is dropped, not printed.** `TenantCheckoutConfiguration`
  already refuses anything that is not exactly `^[A-Z]{3}$`, so `shillings`,
  `kes`, and `7` all produce an unlabelled figure. A test proves the rejected
  value never reaches the screen.
- **The code is read once per session, not once per filter.** It is cached
  beside the category list on the totals route and keyed by UID, tenant, and
  epoch, so changing period, scope, or category spends no extra document read
  and no cached label can survive into another business. A widget test asserts
  the exact document paths read across a period change.
- The formatting is one shared `format` on the read model rather than a helper
  copied into each panel, so the two routes cannot drift apart.

Files in this chunk:

```text
PLAN.md
lib/reporting/daily_metrics_panel.dart
lib/reporting/reporting.dart
lib/reporting/reporting_currency.dart          (new)
lib/reporting/sales_totals_panel.dart
test/reporting/daily_metrics_panel_test.dart
test/reporting/reporting_currency_test.dart    (new)
test/reporting/sales_totals_panel_test.dart
```

Validation evidence after implementation code was frozen:

| Command | Result |
| --- | --- |
| `flutter analyze --no-pub` over the 17 in-scope lib/test paths | 1 pre-existing issue: the Sentry `profilesSampleRate` warning at `lib/main.dart:28` |
| `flutter test --no-pub --concurrency=1 --reporter=failures-only test/audit test/inventory test/returns test/reporting test/sales test/shift test/checkout test/tenancy` | **964/964**, up from 901 at session start |
| `npm --prefix rules-tests run test:emulator` | **125/125** |
| `FUNCTIONS_DISCOVERY_TIMEOUT=60 npm --prefix rules-tests run test:emulator:invitations` | **12/12** real Auth, Firestore, and Functions emulator tests |
| `npm --prefix functions test` | **166/166** |
| `git diff --check` | clean |

This is the second full backend sequence of the session; the first ran after the
category chunk was frozen and both were green. `git diff --stat
3cb7588..HEAD -- functions firestore.rules rules-tests firestore.indexes.json`
is empty throughout - all three chunks changed only Dart. Android build and
Android emulator validation were intentionally skipped as requested.

Meaningful failures and their resolutions:

- **One assertion was wrong about floating point, and the code was right.** The
  formatter test asserted `7.005` renders as `7.01`; the nearest double to 7.005
  is below it, so `toStringAsFixed(2)` correctly gives `7.00`. Asserting IEEE
  half-way behaviour proves nothing about this surface, so the case was replaced
  with `7.004` and `7.006`, which are unambiguous.
- No other assertion failed.

The existing user-owned local edits remain separate and were never staged:

```text
.vscode/settings.json
android/gradle.properties
pubspec.lock
```

### Next bounded chunk

**A per-cashier picker for the totals surface**, which is now the only obvious
gap left in the reporting routes:

1. `TenantSalesScope` is currently `everyone` or `mine`. The server accepts any
   `soldById`, and `TenantStaffDirectoryRepository` already lists canonical
   staff with display names, so a real picker is a small step from what exists.
2. **Check one thing before scoping it.** `TenantStaffDirectoryRepository
   .loadPage` reads the **tenant root** document to find the owner UID and
   throws a `FormatException` when it cannot. Confirm in `firestore.rules` that
   a manager may read the tenant root before assuming the picker works for every
   role the totals surface is open to. If a manager may not, the picker is
   owner/admin-only and the surface must say so rather than fail.
3. Apply the two rules the last two chunks established, which are now the
   pattern for any filter on this surface: a UID not in this business's own
   canonical directory is **never sent**, and a directory that cannot be read
   removes the picker rather than the total. `TenantScopeViolation` still fails
   the route.
4. Reuse `tenantStaffLabel` so the signed-in member reads as "You" and an
   unresolved name degrades to the authoritative UID, exactly as the sale
   history and reconciliation surfaces already do.
5. Add coverage for the payload carrying the chosen `soldById`, a staff member
   outside the directory never being sent, an unreadable directory leaving the
   total, the role boundary if step 2 finds one, and the picker surviving a
   period and a category change.

Leave outside it: the subscription surfaces (examined and declined earlier in
this file - start on the server, not in Flutter), receipt printing, the printed
receipt body, discounts, camera barcode scanning, a per-tender reporting
breakdown, password reset (still blocked on the App Check decision recorded near
the top of this file), product cost/profit fields, a `platform_audit_logs`
surface, branding surfaces, deployment, and Android build/emulator validation.

Practical notes carried forward:

- The emulator prelude is not optional on this machine. The default `java` is
  JDK 17 and every emulator command fails immediately without it.
- `lib/reporting/sales_totals_panel.dart` holds the period, scope, and category
  choosers, the currency notice, and the failure surface. A fourth chooser is
  the point at which the chooser row should become its own widget - add the
  split with the cashier picker, not after it.
- Collection-page test fakes must answer in **ascending document-ID order**.
  `TenantReadRepository` proves it and raises `TenantScopeViolation` otherwise,
  which surfaces as a degraded or failed route rather than an obvious error.
  This cost one debugging cycle in this session.

---

## Who sold what - 2026-08-02

### Completed in this session

The chunk defined immediately above, implemented in the same session. The
totals surface can now be narrowed to one named colleague.

**The check that chunk demanded first, and its answer:** a manager *may* read
the tenant root and the whole staff roster, so the picker needs no role
restriction. `firestore.rules:236` allows `read` on `/tenants/{tenantId}` to any
`activeStaff`, and `firestore.rules:247` allows a staff record to
`owner`, `admin`, or `manager` for any UID. Those are exactly the three roles
`TenantSalesTotalsGateway.allowedRoles` admits, so the surface and the roster it
reads agree by construction rather than by luck.

Implemented behavior and safety decisions:

- **The scope is derived, never claimed.** `createQuery` now takes a `soldById`
  instead of a scope and works out what naming that member *means* against the
  live session: nobody is `everyone`, the session's own UID is `mine`, anyone
  else is `oneMember`. A surface cannot assert that a figure is "your sales" -
  it can only name a member and be told.
- **A colleague is sent only if this business's own directory names them.**
  The same rule the category filter established, with one addition: the
  signed-in member is always answerable from the session itself, so **"only
  mine" survives a roster this role could not read**. A widget test switches
  businesses with a colleague selected and proves the UID is dropped rather
  than sent to the new one.
- **A member who has left is still offered.** Their sales are still in the
  period, and hiding them would make the per-member figures fail to add up to
  the whole-business one. The directory is presented as it is, not filtered by
  current status.
- **A label never discloses more than a name.** Only the canonical `name` is
  used, through the existing `tenantStaffLabel`, so the signed-in member reads
  as `You (…)` and a member with no recorded name degrades to the authoritative
  UID. A staff record also carries an email and a phone number; a test asserts
  no `@` address reaches the screen. This is the rule
  `TenantStaffNameResolver` already states, applied here rather than reinvented.
- **A roster longer than one page says so.** The page is bounded at 25 - the
  same bound `TenantStaffNameResolver.maximumResolvedUids` puts on one page of
  labels - and a business with more members is told the list is partial rather
  than silently shortened.
- **The roster is read once per session**, cached beside the category list and
  the currency and keyed by UID, tenant, and epoch. A widget test asserts the
  exact document paths and query count across a period change, so a third
  cached read cannot quietly become a read per filter.
- An unreadable roster removes the colleagues and says so; a
  `TenantScopeViolation` still fails the route. Three session-scoped reads now
  follow one rule, stated once.

Files in this chunk:

```text
PLAN.md
lib/reporting/sales_totals.dart
lib/reporting/sales_totals_panel.dart
test/reporting/sales_totals_panel_test.dart
test/reporting/sales_totals_test.dart
```

Validation evidence after implementation code was frozen:

| Command | Result |
| --- | --- |
| `flutter analyze --no-pub` over the 17 in-scope lib/test paths | 1 pre-existing issue: the Sentry `profilesSampleRate` warning at `lib/main.dart:28` |
| `flutter test --no-pub --concurrency=1 --reporter=failures-only test/audit test/inventory test/returns test/reporting test/sales test/shift test/checkout test/tenancy` | **972/972**, up from 901 at session start |
| `npm --prefix rules-tests run test:emulator` | **125/125** |
| `FUNCTIONS_DISCOVERY_TIMEOUT=60 npm --prefix rules-tests run test:emulator:invitations` | **12/12** real Auth, Firestore, and Functions emulator tests |
| `npm --prefix functions test` | **166/166** |
| `git diff --check` | clean |

This is the third full backend sequence of the session. `git diff --stat
3cb7588..HEAD -- functions firestore.rules rules-tests firestore.indexes.json`
is empty throughout: all four chunks changed only Dart. Android build and
Android emulator validation were intentionally skipped as requested.

Meaningful failures and their resolutions:

- **The cross-business test failed and found a fixture that could not express
  the claim.** The staff fake held one flat roster shared by every business, so
  a colleague selected in tenant A really was in tenant B's directory and was
  correctly sent. The fake was made per-business - which is what Firestore is -
  and the test then proved what it was written to prove. The production rule was
  never in doubt; the fixture could not exercise it.
- **One assertion was stale rather than wrong.** The "read once per filter" test
  listed only the configuration document; the roster adds the tenant root and
  the owner's record. Both new reads are real and happen once, so the expected
  list was extended rather than the caching relaxed.
- No other assertion failed.

The existing user-owned local edits remain separate and were never staged:

```text
.vscode/settings.json
android/gradle.properties
pubspec.lock
```

### The queue, and why it was re-ordered

The reporting routes are now complete against every server capability they have:
`getSalesComparison` has no unreached parameter, and every figure names its
currency. Three chunks are queued below **in order**. The first was added on
2026-08-02 after a question that turned up a real gap; the two behind it were
already queued and are unchanged, only pushed back.

**The gap.** Everything built across the last several sessions has been verified
by tests and never once by running the app. That is not an oversight in the
tests - it is that **the app cannot be pointed at the emulators at all**,
checked rather than assumed:

- `lib/` contains no `useAuthEmulator`, `useFirestoreEmulator`, or
  `useFunctionsEmulator` call anywhere. `lib/main.dart:36` calls
  `Firebase.initializeApp` and connects to the real dev project
  `multitenant-pos-b8326`.
- `firebase.json` has no `emulators` block. The suites run through
  `firebase emulators:exec --config ../firebase.test.json --project
  demo-multitenant-rules`, a separate config with a demo project, so there is no
  declared port a client could target.

So the emulators serve tests only, and the sole way to exercise the till today
is against a real project. That is the wrong default for local work and it is
why chunk 1 below now comes first.

### Next bounded chunk (1 of 3): reach the emulators from the app

Make the app runnable end-to-end locally, and nothing else.

1. **Declare the emulator ports.** Add an `emulators` block to `firebase.json`
   for auth, firestore, and functions with fixed ports. Do **not** touch
   `firebase.test.json`: every suite in this file depends on it, and a shared
   config would couple a developer's local run to the test harness.
2. **Add a debug-only switch**, ideally its own small file rather than more
   weight in `main.dart`. It must connect exactly once, before any Firebase call
   the app makes, behind an explicit `--dart-define` - never on by default.
3. **The host is derived, not hardcoded.** An Android emulator reaches the host
   machine at `10.0.2.2`, every other target at `localhost`. This is the one
   piece of the chunk that is pure logic, so it is the one piece that can carry
   real unit tests: platform to host, define-absent to disabled, and the release
   refusal below.
4. **Make it impossible to enable in a release build.** This is the whole safety
   argument for the chunk. A switch that silently fails to redirect writes test
   data into a real project; one that silently *does* redirect makes a real
   user's data vanish. Neither may be possible from a release binary - refuse
   loudly at startup rather than degrading to the real project.
5. **Add a seed script**, because an empty emulator cannot demonstrate anything:
   - `configuration/checkout` with a currency **first**. Without it
     `CheckoutCatalogCacheRefresher` refuses with `configurationUnavailable` and
     no sale can be rung up at all.
   - A tenant root with `ownerUid`, the owner's `staff` record, categories, and
     products carrying `SKU` and `price` - the scan path needs a real SKU, and
     the shared-SKU refusal is worth being able to see.
   - An Auth user with a known password and **`emailVerified` set**, or the
     account is stuck behind the verification gate at
     `lib/tenancy/tenant_request.dart:68` and never reaches a business.
   - Reuse the existing Node setup and its `firebase-admin` rather than adding a
     package; `rules-tests/scripts/run-invitation-emulator-tests.js` is the
     precedent for how such a script is invoked here.
   - **The script must refuse to run against anything but an emulator.** Seeding
     is destructive by nature and a mis-pointed run is unrecoverable; require
     the emulator host environment variables and abort when they are absent.
6. Leave outside it: any change to what the app *does*. This chunk adds a way to
   run it, not a feature.

**One standing exclusion has to be revisited for this chunk only.** Android
build and Android emulator validation have been skipped by instruction for
several sessions, including the one that added this. That is fine for Dart-only
work, but chunk 1 exists *precisely* so the app can be driven on Android - so
either the exclusion is lifted for it, or it ships a `10.0.2.2` path that has
never been executed. Ask before starting; do not quietly assume either answer.

### Then (2 of 3): split `lib/reporting/sales_totals_panel.dart`

Unchanged from when it was queued, only pushed back one place, and still worth
doing before anything new lands in that file. At 592 lines it holds three
choosers, three session-scoped reads, a currency notice, a category-basis
sentence, and the failure surface in one file. Nothing in it is wrong, and it is
the third file in this codebase to reach that point after the checkout cart
panel. Do it as a **refactor-only** chunk:

- Extract the three option types (`_CategoryOptions`, `_StaffOptions`, and the
  view record) and `_loadSessionContext`/`_readStaff` into one session-context
  file, since all three obey the single degrade/rethrow/cache rule stated below
  and that rule should live in one place.
- Extract the chooser row - period, member, category chips plus the
  unavailable/truncated notices - into its own widget, taking the current
  selections and the three callbacks.
- Change no behavior and add no test. The proof is the **existing 48 cases
  across `test/reporting/sales_totals_test.dart` (24) and
  `test/reporting/sales_totals_panel_test.dart` (24) passing untouched**, and
  `test/reporting` staying at **154**. If a test needs editing, the split has
  changed something it should not have.

Cheap now, expensive later.

### Then (3 of 3): a per-tender reporting breakdown

The largest remaining gap that real users would feel: `recordSaleTender` has
stored `cash`, `mpesa`, or `card` on every v2 sale since 2026-07-29, and nothing
anywhere reports it. Unlike every chunk in this session, it is **backend work
first**: `aggregateSales` in `functions/src/operations/domain.ts` returns no
tender split, so the honest sequence is a Functions change with its own unit
tests, then the Rules check, then a client surface. Scope the server half alone
before touching Dart.

Leave outside all three chunks: the subscription surfaces (examined and declined
earlier in this file - start on the server, not in Flutter), receipt printing,
the printed receipt body, discounts, camera barcode scanning, password reset
(still blocked on the App Check decision recorded near the top of this file),
product cost/profit fields, a `platform_audit_logs` surface, branding surfaces,
and deployment. Android build and emulator validation stay excluded from chunks
2 and 3; chunk 1 is the deliberate exception described above.

Practical notes carried forward:

- The emulator prelude is not optional on this machine. The default `java` is
  JDK 17 and every emulator command fails immediately without it.
- Collection-page test fakes must answer in **ascending document-ID order**, and
  must be keyed **per business**. `TenantReadRepository` proves the ordering and
  raises `TenantScopeViolation` otherwise, which surfaces as a degraded or
  failed route rather than an obvious error; a fake with one shared roster
  silently makes a cross-business test pass for the wrong reason. Each cost one
  debugging cycle in this session.
- Three session-scoped reads now follow one rule on the totals route -
  categories, staff, and currency: degrade on failure, rethrow
  `TenantScopeViolation`, cache by UID/tenant/epoch. Any fourth should join it
  rather than invent a fourth policy.

### State at handover

The session ended here deliberately, with **none of the three queued chunks
started**. Nothing is in flight and no work is half-applied. The queue was
re-ordered after the session's implementation work was already committed and
validated, so the re-ordering changed documentation only - the four commits
below are unaffected by it.

Four chunks were committed, each with its own green Dart run first:

```text
de14c38  Tell an owner what the business has taken today
731062a  Break the sales totals down by category
c26a65f  Say which currency a reported figure is in
f25515b  Total one colleague sales separately
```

Baselines for the next session to measure against:

| | Session start | Session end |
| --- | --- | --- |
| `flutter test` over the 17 in-scope paths | 901 | **972** |
| `test/reporting` alone | 123 | **154** |
| Rules / integration / Functions | 125 / 12 / 166 | **125 / 12 / 166** |

`git status --porcelain` shows exactly the three pre-existing user-owned edits
it showed at session start - `.vscode/settings.json`,
`android/gradle.properties`, and `pubspec.lock`. They were never staged and must
not be. Everything else in the working tree is committed.

---

## The app can reach the emulators - 2026-08-02

### Completed in this session

Chunk 1 of 3 from the queue immediately above, implemented in the same session.
The app can now be run end to end against a local emulator suite with one
`--dart-define` and one command, against a business that actually exists. This
chunk adds no feature: it adds a way to run what already exists.

**The standing Android exclusion was not lifted.** The previous handover asked
for that answer before starting, and the answer given for this session was to
skip Android build and Android emulator validation. So the `10.0.2.2` path ships
proved by unit tests and not by execution on a device. That is recorded here as
a known gap rather than presented as validated: the derivation is provable
without a device, the connection from a running Android emulator is not, and
nobody has run it.

Implemented behavior and safety decisions:

- **The switch cannot be enabled outside a debug build.** This is the whole
  safety argument. A switch that silently fails to redirect writes test data
  into a real project; one that silently redirects makes a real user's data
  vanish. `resolveFirebaseEmulatorTarget` therefore throws `not_a_debug_build`
  rather than degrading, and the gate is `kDebugMode` rather than
  `!kReleaseMode` so a **profile** build is refused too. Both the define and
  `kDebugMode` are compile-time constants, so a release binary built with the
  define throws at startup instead of quietly reaching production.
- **The refusal is checked before anything else.** A test passes a release build
  an invalid host *and* an invalid port and asserts the build-mode code still
  comes back: that is the failure a developer has to fix first, and reporting a
  port problem to somebody who is about to ship an emulator build would bury it.
- **Nothing is enabled by default, and a test proves it in this binary.** The
  test suite passes no define, so `firebaseEmulatorTargetFromEnvironment()`
  returns `null` and `firebaseEmulatorsConnected` is false. A future edit that
  makes the switch default-on fails that test.
- **The host is derived, and the derivation is the one piece with real unit
  tests.** An Android emulator reaches its host machine at `10.0.2.2`; every
  other target reaches it on loopback. A **web build running in a browser on
  Android** is loopback too, because it runs on the developer machine's own
  network stack - so the rule is the pair (`isWeb`, platform), not the reported
  platform alone. An explicit `FIREBASE_EMULATOR_HOST` overrides it for a
  physical handset on the LAN.
- **Both plugins' `automaticHostMapping` is turned off.** `cloud_firestore`,
  `firebase_auth`, and `cloud_functions` each silently rewrite `localhost` and
  `127.0.0.1` to `10.0.2.2` on Android. Leaving that on would mean the tested
  derivation is not the one in effect, so the derivation would be unprovable.
  One authority, tested.
- **A host that is not a bare address is refused, never guessed.** A scheme, an
  embedded port, a path, untrimmed whitespace, a leading hyphen or dot, and an
  over-long name all fail as `invalid_host`; a port outside 1-65535 fails as
  `invalid_port` for each of the three services separately.
- **The connect call sits deliberately *after* `firestore.settings` is
  assigned.** `useFirestoreEmulator` records its host by `copyWith` **inside**
  those same settings (`cloud_firestore-6.1.1/lib/src/firestore.dart:152`), so
  assigning a whole `Settings` object afterwards would discard the redirect and
  send a local run's writes to the real project. The ordering carries a comment
  saying so, because it looks arbitrary and is not.
- **Connecting twice is refused, and the flag is raised before the first call
  rather than after the last.** A partially applied redirect must not be retried
  into a mixed state where Auth is local and Firestore is not.
- **`firebase.json` gained the `emulators` block; neither test config was
  touched.** `firebase.test.json` and `firebase.invitation-test.json` keep their
  own ports (9199/8180/5101), so a developer's local run and the test harness
  cannot break each other. The dev ports are the Firebase defaults - 9099, 8080,
  5001 - and a unit test asserts the Dart constants equal them, because the app
  cannot read that file at runtime.
- **The seed script cannot run outside an emulator.** It requires
  `FIRESTORE_EMULATOR_HOST` and `FIREBASE_AUTH_EMULATOR_HOST` and aborts when
  either is absent. That is not a check but the guarantee itself: those two
  variables are what make `firebase-admin` incapable of reaching a real project.
  A set `GOOGLE_APPLICATION_CREDENTIALS` is refused as a second signal.
- **`configuration/checkout` is written first, deliberately.** Without it
  `CheckoutCatalogCacheRefresher` refuses with `configurationUnavailable` and no
  sale can be rung up however complete the catalog is.
- **The seed models the cases the till was built to handle**, so they can be
  seen rather than only asserted: two products sharing the SKU `5901234123457`
  (the collision the scan path refuses outright), a product with zero stock, one
  with **negative** stock, and one naming a category the catalog does not hold
  (the `Other` chip).
- **The seed verifies itself.** It re-reads `configuration/checkout`, the owner
  staff record, and the `tenant_memberships` mirror, and counts the products. A
  half-applied seed produces a confusing app - no till, no access, or no
  business in the list - rather than an obvious failure, so it is checked
  instead of assumed.
- The runner writes local-only secret and parameter files, refuses to overwrite
  either, and removes both on exit - the same pattern
  `run-invitation-emulator-tests.js` established. Neither is ever committed:
  `functions/.gitignore` already ignores `*.local`.

Deliberately outside this chunk:

- Nothing about what the app *does* changed. No route, no read model, no rule.
- Camera scanning, receipt printing, and every other standing exclusion are
  untouched.

Files in this chunk:

```text
PLAN.md
firebase.json
lib/dev/firebase_emulators.dart               (new)
lib/main.dart
rules-tests/README.md
rules-tests/package.json
rules-tests/scripts/run-dev-emulators.js      (new)
rules-tests/scripts/seed-dev-emulator.js      (new)
test/dev/firebase_emulators_test.dart         (new)
```

Validation evidence:

| Command | Result |
| --- | --- |
| `flutter analyze --no-pub` over the now **19** in-scope lib/test paths | 1 pre-existing issue: the Sentry `profilesSampleRate` warning at `lib/main.dart:29` |
| `flutter test --no-pub --concurrency=1 --reporter=failures-only test/audit test/dev test/inventory test/returns test/reporting test/sales test/shift test/checkout test/tenancy` | **987/987**, up from 972, adding **15** emulator-switch tests |
| `node scripts/run-dev-emulators.js --no-hold` from `rules-tests` | exit 0: Auth, Firestore, and Functions started, every endpoint initialized, the seed applied and verified, clean shutdown |
| `node scripts/seed-dev-emulator.js` with no emulator environment | exit 1 with the refusal sentence, nothing written |
| `git diff --check` | clean |

The Rules, Functions, and integration suites were **not** re-run for this chunk.
It changed no `firestore.rules`, no `functions/src`, and no `rules-tests/test`
file, and the live emulator run above exercised the same Functions build those
suites cover. Android build and Android emulator validation were skipped as
requested; see the note at the top of this section.

Meaningful failures and their resolutions:

- **The first two runs hung for over ten minutes each and produced no error.**
  Both stopped immediately after `Serving at port 8712`, which is HTTP function
  discovery *succeeding*. The cause was the next step: `functions/src` declares
  five secrets and six `defineString` parameters **with no default**, and the
  emulator stops at startup to ask for each one. With no terminal to answer, the
  run waits forever and prints nothing further. The invitation harness never hits
  this because its codebase exports only seven functions and loads none of the
  email configuration; this one loads `index.ts` entire. Resolved by writing both
  `functions/.secret.local` and `functions/.env.local` with local-only values,
  which is now documented in `rules-tests/README.md` as the reason and not just
  the fix. `CI=true` was added to the child environment in the same pass,
  matching the invitation runner.
- **Killing a hung run left `functions/.secret.local` behind**, and the next run
  refused to start because of it - the overwrite guard working exactly as
  intended on the file its own crash left. The cleanup now removes both files
  and tolerates either being absent.
- **`MetadataLookupWarning: 169.254.169.254` appears on every start** and is
  expected: the project ID is real, so `firebase-tools` probes for application
  default credentials before falling back. It costs one network timeout at
  startup and nothing else. The project ID cannot be swapped for a `demo-` one,
  because the emulators namespace data by project and the app is built against
  `multitenant-pos-b8326`; a demo namespace would be seeded and then invisible.
- No test assertion failed. Both Dart commands were green on first execution.

The existing user-owned local edits remain separate and were never staged:

```text
.vscode/settings.json
android/gradle.properties
pubspec.lock
```

---

## The totals panel, split - 2026-08-02

### Completed in this session

Chunk 2 of 3 from the queue above, implemented in the same session as chunk 1
and committed separately. **Refactor only: no behavior changed and no test was
added or edited.**

The proof is exactly what that chunk asked for: `test/reporting` still passes
**154/154**, the 24 cases in `test/reporting/sales_totals_test.dart` and the 24
in `test/reporting/sales_totals_panel_test.dart` untouched. Had any test needed
editing, the split would have changed something it should not have.

`lib/reporting/sales_totals_panel.dart` went from 636 lines holding three
choosers, three session-scoped reads, a currency notice, a category-basis
sentence and the failure surface, to 404 lines holding the route, the loader,
and the figure.

What moved, and why it moved together:

- **`sales_totals_session_context.dart`** holds `SalesTotalsCategoryOptions`,
  `SalesTotalsStaffOptions`, the new `SalesTotalsSessionContext`, the view
  record, and `SalesTotalsSessionContextLoader`. The three reads were already
  obeying one rule - degrade on failure, rethrow `TenantScopeViolation`, cache
  by UID/tenant/epoch - stated three times in three `catch` blocks and a
  hand-rolled cache key. It is now stated once, on the class that owns all
  three, which is the point the previous handover made when it said a fourth
  session-scoped read should join them rather than invent a fourth policy.
- **`sales_totals_choosers.dart`** holds the period, member, and category chips
  with their unavailable and truncated notices. They travel together because
  they are one control surface: all three stay on screen through a failure,
  since a period holding too many sales is refused precisely so a shorter one
  can be picked.

Two mechanical consequences worth recording, because both are behavior-neutral
and both look like changes:

- The three separate nullable fields (`_categories`, `_staff`, `_currency`)
  became one nullable `SalesTotalsSessionContext`. That is exactly equivalent:
  the old code assigned all three together after all three reads had finished,
  so no state existed in which one was present and another was not. The failure
  path's `?? unreadable` triple became one `?? SalesTotalsSessionContext.empty`
  built from the same three unreadable constants.
- The choosers are now a `Column` inside the same `ListView`, rather than
  children spliced directly into it. Every `ValueKey` is unchanged and in the
  same order, which is why no test moved.

Files in this chunk:

```text
PLAN.md
lib/reporting/reporting.dart
lib/reporting/sales_totals_choosers.dart          (new)
lib/reporting/sales_totals_panel.dart
lib/reporting/sales_totals_session_context.dart   (new)
```

Validation evidence:

| Command | Result |
| --- | --- |
| `flutter analyze --no-pub lib/reporting test/reporting` | no issues |
| `flutter test --no-pub --concurrency=1 --reporter=failures-only test/reporting` | **154/154**, unchanged, no test file edited |
| `flutter analyze --no-pub` over the 19 in-scope lib/test paths | 1 pre-existing issue: the Sentry `profilesSampleRate` warning at `lib/main.dart:29` |
| `flutter test --no-pub --concurrency=1 --reporter=failures-only` over the 9 in-scope test paths | **987/987** |
| `git diff --check` | clean |

The full analyze and test commands above cover chunks 1 and 2 together; they
were run once after both were frozen, and chunk 1 was committed from that same
green state. No backend suite was re-run: neither chunk changed
`firestore.rules`, `functions/src`, or any `rules-tests/test` file.

Meaningful failures and their resolutions:

- None. The split analyzed and passed on its first run, which is the outcome a
  refactor-only chunk is supposed to have.

The existing user-owned local edits remain separate and were never staged:

```text
.vscode/settings.json
android/gradle.properties
pubspec.lock
```

---

## What the business was paid with - 2026-08-02

### Completed in this session

Chunk 3 of 3 from the queue above, implemented in the same session as the two
before it. `recordSaleTender` has stored `cash`, `mpesa`, or `card` on every
schema v2 sale since 2026-07-29 and nothing anywhere reported it. It is now
reported.

This was **backend first**, as that chunk required: `aggregateSales` returned no
tender split, so the server half was scoped, written, and unit-tested before any
Dart was touched.

Implemented behavior and safety decisions:

- **`daily_metrics` documents were deliberately left alone.** The obvious
  implementation - add the split to `PeriodMetrics` - would have changed what
  the reconciliation processor **writes**, because `DailyMetrics extends
  PeriodMetrics` and `aggregateDailyMetrics` spreads the whole record into the
  stored document (`functions/src/reconciliation/model.ts:272`). That is a
  stored-schema change with a Rules surface and a strict Dart read model behind
  it, for a figure nothing asked for there. The split is instead a new
  `byTender` field on the **comparison response** only, where the question was
  actually asked. `PeriodMetrics` is byte-identical.
- **One definition of what a sale contributes, used by both.**
  `saleContribution` was extracted from `aggregateSales` and is what both the
  aggregate and the split are built from. A sale a category filter skips is
  skipped in both, and the revenue basis - recorded sale total without a
  category, matching lines with one - is decided once. The buckets therefore sum
  to the total by construction rather than by two implementations staying in
  step, and a unit test asserts the sum for both the filtered and unfiltered
  cases.
- **`unrecorded` and `other` are separate buckets, because they are different
  facts.** A sale with no `tender` at all is a schema v1 sale written before the
  field existed. A sale carrying a value nothing here models - an import, a rule
  rollback - is a data problem. Folding the second into the first would report a
  defect as history. Eleven near-miss values are driven through
  `saleTenderBucket` in a test: `"Cash"`, `" cash"`, `"CASH"`, `"cheque"`, `""`,
  a number, a boolean, a map, a list, `undefined`, and `null`.
- **An unrecognised tender does not fail the report.** The `TenantSale` read
  model refuses a single sale naming one, and that is right for a receipt
  lookup. Refusing here would deny a manager the whole period's takings because
  of one bad row, so the money is counted, bucketed as `other`, and the surface
  says plainly that some sales name a method the app does not recognise and that
  their takings are still inside the total.
- **The client checks the split rather than trusting it.** The counts must sum
  to the answer's own `transactions` and the amounts to its own `sales`, exactly.
  A split that does not add up is not a smaller version of the truth - it is a
  different figure wearing the same label, on the one surface an owner reads
  takings from - so it is a `FormatException` and the whole answer is refused. A
  widget test proves the figure disappears with it.
- **Sums are compared in whole minor units, never as doubles.** The server adds
  integers, so an exact split matches to the cent. A test pins the case that
  makes this necessary: buckets of 0.1 and 0.2 against a total of 0.3, which a
  double comparison would refuse even though the split is exactly right.
- **The check is on the sum, and the test says so.** One bucket a cent low and
  another a cent high is accepted, because nothing on the client can know
  independently what any single bucket should be; claiming to check one would be
  a check in name only.
- **The bucket set is closed and an unknown bucket is refused.** Ignoring a
  bucket this build does not know would silently report less money than the
  business took. A missing bucket, an extra one, and an empty object all fail.
- **An absent `byTender` is not a failure.** A server that reports no split is a
  server this surface shows no split for; the figure the manager came for is
  unaffected. This is the same rule this route already applies to its currency
  and its category list - a label may never cost a figure - and it is what makes
  the server field additive rather than a flag day.
- **The disclaimer is the shared constant, and the unrecorded note is not.**
  `checkoutTenderDisclaimer` is reused verbatim, so the claim that the payment
  is unverified cannot drift between the till, the sale history, the receipt
  lookup, and this report. `checkoutTenderUnrecordedMessage` was deliberately
  **not** reused: it says "This sale", which is a claim about one record and
  would be false over a period. The same fact is stated again in the plural, and
  a test asserts the word "unpaid sale" appears nowhere.
- **A method nobody used is absent, not a zero row.** A period with no card
  sales is better described by their absence, and the total above already says
  what the whole is.
- **The disclaimer appears only when a modelled tender was actually recorded.**
  A period of nothing but schema v1 sales would otherwise carry a sentence about
  nothing on screen.
- **No Firestore Rules change was needed, and this was checked rather than
  assumed.** `getSalesComparison` runs in a Cloud Function under the Admin SDK,
  so Rules are not evaluated on its read at all; and `tender` is a field of a
  `sales` document that `firestore.rules:319` already allows any active member
  to read whole. `validSaleTender` already constrains the write. The Rules suite
  was run anyway and is unchanged at 125/125.

Deliberately outside this chunk:

- No per-tender figure appears on the daily summary, the shift close, or any
  receipt. Reconciliation still stores no split.
- Nothing verifies a payment. This reports what a cashier asserted, and every
  surface that shows it says so.

Files in this chunk:

```text
PLAN.md
functions/src/operations/domain.test.ts
functions/src/operations/domain.ts
functions/src/operations/reports.ts
lib/reporting/sales_totals.dart
lib/reporting/sales_totals_panel.dart
test/reporting/sales_totals_panel_test.dart
test/reporting/sales_totals_test.dart
```

Validation evidence after implementation code was frozen:

| Command | Result |
| --- | --- |
| `flutter analyze --no-pub` over the 19 in-scope lib/test paths | 1 pre-existing issue: the Sentry `profilesSampleRate` warning at `lib/main.dart:29` |
| `flutter test --no-pub --concurrency=1 --reporter=failures-only test/audit test/dev test/inventory test/returns test/reporting test/sales test/shift test/checkout test/tenancy` | **1002/1002**, up from 987, adding **15** tests: 9 gateway cases and 6 widget cases |
| `npm --prefix functions test` | **171/171**, up from 166, adding **5** aggregation cases |
| `npm --prefix rules-tests run test:emulator` | **125/125**, unchanged |
| `FUNCTIONS_DISCOVERY_TIMEOUT=60000 npm --prefix rules-tests run test:emulator:invitations` | **12/12** real Auth, Firestore, and Functions emulator tests |
| `git diff --check` | clean |

`test/reporting` alone went from 154 to **169**. Android build and Android
emulator validation were skipped as requested.

Meaningful failures and their resolutions:

- **Two test fixtures did not add up, and the read model was right both times.**
  A gateway case meant to prove the minor-unit comparison used one bucket a cent
  low and another a cent high, which sums correctly and is therefore accepted -
  the test asserted the opposite of what it had built. It was replaced by the
  case that actually needs minor units (0.1 + 0.2 against 0.3) plus an explicit
  case recording that the check is on the sum. A widget fixture then zeroed
  three buckets without moving their money anywhere, so the split genuinely did
  not add up and the whole breakdown was correctly refused; the fixture was
  corrected to redistribute rather than the check relaxed.
- No other assertion failed. The Functions unit tests, the panel tests after the
  fixture correction, and all four suite-level commands were green.

The existing user-owned local edits remain separate and were never staged:

```text
.vscode/settings.json
android/gradle.properties
pubspec.lock
```

### Next bounded chunk

The three queued chunks are all done. Two candidates, in the order recommended:

1. **Run the app.** Chunk 1 of this session made that possible for the first
   time and nobody has done it. Start the emulators, seed them, sign in as the
   seeded owner, open a shift, ring up a sale, and read it back on the totals
   route. Everything in this codebase has been proved by tests and never once by
   use, so the first run is very likely to find something no test models - a
   layout that does not fit, a route that cannot be reached, a message that is
   wrong in context. **Ask first whether the Android exclusion is lifted for it:**
   the `10.0.2.2` path still has never been executed, so on Android that is what
   would be exercised, while a Windows or web run exercises only the loopback
   path. Fix what the run finds; do not add features in the same chunk.
2. **A per-tender figure where a cashier needs it: the shift close.** The report
   added here answers a manager's question over a period. The other place the
   split matters is counting a drawer, where only the cash bucket for one shift
   is relevant. That is a different query - one shift, not a date range - and
   `getSalesComparison` cannot express it, so scope the server half first as
   this chunk did.

Leave outside either chunk: the subscription surfaces (examined and declined
earlier in this file - start on the server, not in Flutter), receipt printing,
the printed receipt body, discounts, camera barcode scanning, password reset
(still blocked on the App Check decision recorded near the top of this file),
product cost/profit fields, a `platform_audit_logs` surface, branding surfaces,
and deployment.

Practical notes carried forward:

- The emulator prelude is not optional on this machine. The default `java` is
  JDK 17 and every emulator command fails immediately without it.
- **A local `firebase emulators:exec` against `firebase.json` needs both
  `functions/.secret.local` and `functions/.env.local`.** `functions/src`
  declares five secrets and six string parameters with no default, and the
  emulator stops at startup to ask for each one; with no terminal to answer, the
  run hangs silently after `Serving at port ...`. `run-dev-emulators.js` writes
  and removes both. If a run is killed, delete the leftovers before retrying -
  the script refuses to overwrite them, which is what it is for.
- Collection-page test fakes must answer in **ascending document-ID order**, and
  must be keyed **per business**.
- Three session-scoped reads on the totals route - categories, staff, currency -
  now live in `SalesTotalsSessionContextLoader` and obey one rule: degrade on
  failure, rethrow `TenantScopeViolation`, cache by UID/tenant/epoch. Any fourth
  should join it rather than invent a fourth policy.

---

## The first real run, and what it found - 2026-08-02

### Completed in this session

Two chunks, committed separately. The Android exclusion was lifted for this
session at the user's request, which is what made the first one possible: the
handover above had queued "run the app" and noted that the `10.0.2.2` path had
never been executed. It had not, and it did not work.

#### Chunk 1: make the first real run possible (`5405fcf`)

The app was driven end to end on an API 35 Android emulator against the local
Firebase suite: sign in as the seeded owner, open a shift, ring up three sales
across cash and M-Pesa, start a cash count, and read the figures back. Four
defects surfaced. Two are fixed here; the other two are below.

- **Android refused every emulator call, and the derivation was blameless.**
  Sign-in failed with `Cleartext HTTP traffic to 10.0.2.2 not permitted`. The
  emulators serve plain HTTP; Android has refused cleartext by default since
  API 28. `lib/dev/firebase_emulators.dart` resolved the host perfectly and the
  wire had simply never been used.
  `android/app/src/debug/res/xml/network_security_config.xml` now permits
  cleartext to exactly the hosts `derivedEmulatorHost` can return.
- **It lives in `src/debug`, which is the whole safety argument.** A release
  manifest never merges that source set, so a release binary keeps Android's
  default refusal however the file changes. That is the same guarantee the Dart
  switch already makes by throwing outside a debug build, restated where the
  platform is the one enforcing it. The test asserts the main and profile
  manifests do not name the config.
- **The permitted set is narrow, not blanket.** A `base-config` would cover
  whatever else a debug build talked to, and a test refuses one. The documented
  physical-handset path (`FIREBASE_EMULATOR_HOST` at a LAN address) is
  deliberately not covered; `rules-tests/README.md` says so and says what to do
  about it.
- **The config and the Dart derivation are tied together by test.**
  `test/dev/firebase_emulators_test.dart` reads the XML and asserts every host
  the switch can produce is named in it, so changing `androidEmulatorHostAddress`
  without changing the config fails in a second instead of five minutes into a
  Gradle build.
- **The theme was light and the scaffold was near-black.** On the landing route
  the branding heading, the `Shift` heading, and the shield icon were present
  and unreadable, while plain body text beside them was fine. `ThemeData` with
  no `brightness` is a light theme; only `headlineLarge` and `bodyMedium` were
  overridden, and the other seventy-odd uses of `titleMedium`, `headlineSmall`,
  `bodySmall`, `titleSmall`, and `titleLarge` took Material's near-black
  defaults. Measured contrast against the scaffold was **1.004:1**.
- **`brightness: Brightness.dark` is the whole fix, and the tests measure
  rather than restate it.** `test/theme_test.dart` computes the WCAG contrast
  ratio of every style in the theme against both the scaffold and the raised
  surface, at the AA threshold that applies to each size and weight. Removing
  the one line was verified to fail three of the four tests.
- **The blast radius was checked rather than assumed.** Every use of `bgMid`,
  `mutedGreen`, and `accentGreen` outside `theme.dart` is inside commented-out
  legacy code in `lib/config.dart`, no `AppBar` sets a colour, and no test
  asserted a theme colour. The app bar went from white-on-light to the dark
  surface, which is what the scaffold was always asking for.

#### Chunk 2: what the drawer should hold (`60a372f`)

The queued chunk was "a per-tender figure where a cashier needs it: the shift
close", and it was queued as server-first. **It is not server work at all.**
`ShiftSalesSummary` is built by `CheckoutOutboxShiftSalesLedger` from the
encrypted local outbox, not from a query, and every outbox payload has carried
`tender` since schema v2. `getSalesComparison` was never involved. The scope
note in the previous handover was wrong, and the code was read before it was
believed.

- **Nothing the server stores changed, and this was checked rather than
  assumed.** `TenantShiftRepository.buildCloseIntent` enumerates the fields it
  writes (`totalSalesMinor`, `transactionCount`), so growing
  `ShiftSalesSummary` cannot change the closing document. No Rules change and
  no Functions change: the Rules suite is unchanged at 125/125 and the
  Functions suite at 171/171.
- **The bucketing rule is the server's, copied rather than re-derived.**
  `saleTenderBucket` in `functions/src/operations/domain.ts` treats absent and
  null as `unrecorded`, the three exact wire values as themselves, and anything
  else as `other`. `_ShiftTenderSplitBuilder` does the same, so one sale lands
  in the same bucket whether it is counted at a till or reported over a period.
  A test drives nine near-misses through it: `Cash`, a leading space, `CASH`,
  `cheque`, the empty string, a number, a boolean, a map, and a list.
- **An unmodelled tender does not fail the close.** The total is known and
  correct either way; refusing would strand a cashier at the end of a shift
  over a value they never chose. It is bucketed and stated. This is the same
  decision the period report already made, for the same reason.
- **The buckets sum to the shift total by construction.** They are filled in
  the same pass, from the same already-validated `totalMinor`, that grows the
  total. `tendersDescribeTakings` checks it anyway for every other source of a
  split, and the panel shows no cash figure at all when it fails: the cash
  figure is what a drawer is measured against, so a wrong one becomes an
  accusation about the person counting it.
- **Expected cash waits for a complete shift.** This came directly out of the
  run. With two sales unsynchronized the surface said `Confirmed sales: 0
  transactions, 0 minor units`, offered an expected-cash figure of zero, and
  said nothing about the two sales until the cashier pressed Close and got a
  refusal back. The panel now states the unsynchronized count in the cashier's
  own terms and withholds the cash figure until every sale is accounted for. An
  expected-cash figure over an incomplete shift is not a smaller truth, it is a
  number the drawer will not match.
- **A shift with no cash sales still shows the figure.** Being told to expect
  nothing is an answer; an absent line is an unanswered question.
- **The disclaimer is the shared constant.** `checkoutTenderDisclaimer` is
  reused verbatim so the claim that the payment is unverified cannot drift
  between the till, the sale history, the receipt lookup, the period report,
  and this. It appears only when a modelled tender was actually recorded.
- **A missing bucket is an empty bucket, never a crash.** The ledger always
  writes all three, but `ShiftTenderSplit` is a public value read by the one
  screen that closes a till, so `bucket()` answers for every method.

Deliberately outside both chunks:

- Nothing verifies a payment. This still reports what a cashier asserted.
- No per-tender figure was added to the daily summary or any receipt, and
  reconciliation still stores no split.
- The two defects below were diagnosed, not fixed.

### Two defects found by the run and deliberately not fixed

Both are recorded with evidence because both deserve their own chunk.

1. **A saved sale is not submitted until the next app start.** This is the
   serious one. The till says "A saved sale is submitted and confirmed
   automatically". It is durable immediately and correct, but the submission
   worker only runs from `tenantSessionRecoveryFactory`, which fires on session
   open and on `connectivity.onConnectivityChanged`. Neither happens while a
   cashier stands at a till. Observed directly: three sales were rung up, the
   `sales` collection did not exist in Firestore at all,
   `checkout-outbox-v1.hive` held them as `savedOffline`, and the closing
   summary therefore reported zero. Force-stopping and relaunching the app
   submitted all of them and the collection appeared. A till left open all day
   would never sync and could never close its shift.
2. **The pending-checkout panel on the landing route is stale.** It is loaded
   through a route guard that does not re-run when the till is popped, so after
   ringing up two sales it still read "No checkouts are stored on this device."
   A relaunch showed "Saved offline: 2". This masked the defect above during
   diagnosis and would mask it for a cashier.

Also observed, and out of scope: the Sentry DSN in `lib/main.dart` is an
`http://` URL to an external host. Android blocks it in every build, so those
envelopes have never been delivered from an Android device, debug or release.
The debug config added here deliberately does not cover it, because permitting
cleartext to a real telemetry endpoint is not this chunk's call to make.

### Files in this session

```text
PLAN.md
android/app/src/debug/AndroidManifest.xml
android/app/src/debug/res/xml/network_security_config.xml
lib/shift/shift_panel.dart
lib/shift/shift_sales_ledger.dart
lib/theme.dart
rules-tests/README.md
test/dev/firebase_emulators_test.dart
test/shift/shift_panel_test.dart
test/shift/shift_sales_ledger_test.dart
test/theme_test.dart
```

### Validation evidence after implementation code was frozen

| Command | Result |
| --- | --- |
| `flutter analyze --no-pub lib/shift lib/dev lib/theme.dart test/shift test/dev test/theme_test.dart` | 1 pre-existing issue: an unused `cloud_firestore` import at `lib/theme.dart:2`, left alone because legacy `lib/pos/*` files import `theme.dart` and may take `Timestamp` transitively |
| `flutter test --no-pub --concurrency=1 --reporter=failures-only test/audit test/dev test/inventory test/returns test/reporting test/sales test/shift test/checkout test/tenancy test/theme_test.dart` | **1028/1028**, up from 1002, adding **26** tests |
| `npm --prefix functions test` | **171/171**, unchanged |
| `npm --prefix rules-tests run test:emulator` | **125/125**, unchanged |
| `FUNCTIONS_DISCOVERY_TIMEOUT=60000 npm --prefix rules-tests run test:emulator:invitations` | **12/12** real Auth, Firestore, and Functions emulator tests |
| `flutter build apk --debug --no-pub --target-platform android-x64 --dart-define=USE_FIREBASE_EMULATORS=true` | built, installed, and driven on the API 35 emulator |
| `git diff --check` | clean |

`test/shift` went from 111 to **131**, `test/dev` from 15 to **19**, and the new
`test/theme_test.dart` adds **4**.

### Meaningful failures and their resolutions

- **The dev emulator command died at startup, and it was the host, not the
  repo.** `npm --prefix rules-tests run emulators:dev` failed while registering
  the second Firestore trigger. `rules-tests/firestore-debug.log` showed the
  real cause: `java.lang.OutOfMemoryError: Unable to allocate 4194304 bytes` in
  the Firestore emulator's JVM, a native allocation the OS refused. A cold
  Gradle build was running at the same time on a host with 2 GB free. Run
  sequentially it starts and seeds every time. Nothing in the repository was at
  fault and nothing was changed for it.
- **Two `adb` binaries fought and killed the run.** `flutter run` reported
  `protocol fault (couldn't read status): connection reset`. Flutter uses
  `C:\Users\BonifaceMasota\develop\android-sdk\platform-tools\adb.exe`; the one
  first on `PATH` is a different binary under
  `C:\Users\BonifaceMasota\Android\Sdk`. A second server takes over the first
  one's port and both fail. Every later command used Flutter's copy explicitly.
- **`flutter run` does not accept `--target-platform`.** That flag belongs to
  `flutter build apk`. Building and installing separately turned out to be the
  better shape anyway: it lets Gradle finish and release its memory before the
  Firebase emulators start.
- **A double hyphen inside an XML comment failed the Android resource merger.**
  The comment described a `dart-define` flag. It cost a five-minute build to
  find out, so `test/dev/firebase_emulators_test.dart` now checks that one rule
  in a second. The comment was reworded rather than the check dropped.
- **A killed emulator run orphans its processes and leaves its local config.**
  The next start failed with `Could not start Authentication Emulator, port
  taken`. The practical note below already warned about the files; the
  listening ports need clearing too.
- No test assertion failed at any point. Every suite above was green on its
  first run after the code was frozen.

### The existing user-owned local edits remain separate and were never staged

```text
.vscode/settings.json
android/gradle.properties
pubspec.lock
```

### Next bounded chunk

**Submit a sale when it is saved.** Defect 1 above, and nothing else. It is the
largest real-user gap in the app and the run proved it end to end.

1. Give the composition root a trigger the till can fire. `main.dart` already
   feeds `tenantRecoveryTriggers` from connectivity changes; a broadcast
   controller merged into that stream is the smallest seam that does not push
   submission knowledge into the checkout screen. The screen already knows when
   a draft became durable, because it returns `CheckoutSavedDraft`, so it needs
   to signal rather than to submit.
2. **Change nothing about what submission does.** The worker, its leases, its
   idempotency, and the outbox state machine are frozen. This chunk changes
   when it runs. A save that fires a trigger while a submission is already in
   flight must be harmless, and that is the case worth a test.
3. Fix defect 2 in the same chunk, because it is the same story from the
   cashier's side: the pending-checkout panel must re-read when the till is
   popped, or the fix above is invisible until a relaunch.
4. Cover: a save triggers submission; a trigger during an in-flight submission
   does not double-submit; a failed submission leaves the record retryable; a
   trigger after a tenant switch does not submit the previous session's work;
   and the landing panel reflects a sale rung up moments earlier.
5. Re-run the app on the Android emulator to prove it, since that is the only
   thing that proved the defect. Ring up a sale and watch it reach Firestore
   without relaunching.

Leave outside it: the tender split anywhere new, receipt printing, the printed
receipt body, discounts, camera barcode scanning, password reset (still blocked
on the App Check decision recorded near the top of this file), product
cost/profit fields, a `platform_audit_logs` surface, branding surfaces, the
subscription surfaces, the Sentry DSN, and deployment.

### Practical notes carried forward

- The emulator prelude is not optional on this machine. The default `java` is
  JDK 17 and every emulator command fails immediately without it.
- **Do not run a Gradle build and the Firebase emulators at the same time.**
  This host has 2-3 GB free and the Firestore emulator's JVM dies with a native
  `OutOfMemoryError` when they compete. Build, let Gradle exit, then start the
  emulators.
- **Use Flutter's own `adb`**, at
  `C:\Users\BonifaceMasota\develop\android-sdk\platform-tools\adb.exe`. The one
  first on `PATH` is a different binary under
  `C:\Users\BonifaceMasota\Android\Sdk` and the two servers fight.
- **After killing an emulator run, clear both the local config and the ports.**
  `functions/.secret.local` and `functions/.env.local` survive a hard kill, and
  so do the processes listening on 9099, 8080, 5001, 4000, and 9150.
- Driving the app: `adb shell input tap` needs coordinates in device pixels
  (1080x2400 here), and the emulator's stylus handwriting tutorial will steal
  the first `input text` into a field. `adb shell settings put secure
  stylus_handwriting_enabled 0` stops it. Scripted taps must also wait for the
  app to actually be on screen; a cold start here took over thirty seconds.
- `adb shell run-as com.example.flutter_application_1 ls -la app_flutter/` shows
  the Hive files with sizes and timestamps. That is what proved a sale had been
  persisted locally while Firestore held nothing.
- The Firestore emulator's REST API answers a `Bearer owner` token with Rules
  bypassed, which is the quickest way to see what the app actually wrote.
- Collection-page test fakes must answer in **ascending document-ID order**, and
  must be keyed **per business**.

---

## A saved sale reaches the server while the till stays open - 2026-08-02

### Completed in this session

The chunk the previous handover named, and only that. Defect 1 - "a saved sale
is not submitted until the next app start" - and defect 2 - "the pending-checkout
panel on the landing route is stale" - are the same story from two sides, and
both are closed. Nothing about what submission *does* changed: the worker, its
leases, its idempotency, and the outbox state machine are untouched. What
changed is **when** it runs, and what runs alongside it.

Implemented behavior and safety decisions:

- **`CheckoutSyncSignals` is the one seam between a saved sale and the workers.**
  Before it, the submission worker ran only when a tenant session opened and
  when connectivity was restored, and neither happens while a cashier stands at
  a till. The observed consequence was severe: three sales rung up, the `sales`
  collection absent from Firestore entirely, and the shift impossible to close,
  because closing refuses while any sale is unsettled.
- **It carries two streams, because they answer two different questions.**
  `syncRequests` asks the workers to run and is what the routing shell consumes;
  `evidenceChanges` says local state may have moved, so a read-only surface
  should re-read. A durable save fires both. The end of a run fires only the
  second - a run must never ask for another run, which would be a loop rather
  than a refresh.
- **Both streams are cached in `late final` fields.** The routing shell decides
  whether to resubscribe by comparing `tenantRecoveryTriggers` with `identical`,
  and a broadcast controller hands out a **new** stream object on every `.stream`
  read, so an uncached getter would silently cancel and resubscribe on every
  rebuild of the composition root. A test pins the identity.
- **The till still only knows how to save.** The trigger is a decorator,
  `CheckoutSyncOnSaveDraftSink`, wrapped around the sink in `main.dart`. The
  screen gained no parameter and no knowledge of submission, so no surface can
  move a checkout through a state the sync and recovery workers own - the same
  boundary `CheckoutDraftSink` was introduced to draw.
- **The signal fires after the save, never instead of it.** A refusal propagates
  from the delegate untouched and asks for nothing, so nothing is ever requested
  on behalf of a sale that was not recorded. A test proves the record is already
  durable when the worker reaches it, because a signal that raced the write
  would find nothing and the defect would survive the fix.
- **A failed signal never turns a durable sale into a refusal.** The sale is on
  disk by then; reporting the signal's failure would send a cashier to ring the
  same sale up twice, and the reconnect trigger and the next session open still
  submit it. It is swallowed deliberately, with a test.
- **The shell now forwards *why* a run was asked for**, and this was the one
  change to a frozen contract: `TenantSessionRecovery` takes the trigger event,
  verbatim, and `null` when the shell itself asked because a session opened. The
  shell attaches no meaning to it.
- **That forwarding exists to stop a serious cost regression the fix would
  otherwise have introduced.** The recovery closure also runs
  `CheckoutCatalogCacheRefresher`, which pages every category and product from
  Firestore. Reusing the trigger for saves without distinguishing them would
  have re-read the whole catalog on **every single customer** - up to 2000
  products, the cache's own bound. A save now runs recovery and submission only;
  a reconnect still refreshes everything, which is exactly when fresh products
  are wanted.
- **The evidence panel re-reads on `evidenceChanges` and nothing else.** It is
  now stateful, and its guarded loader is cached against a generation counter,
  so an unrelated rebuild reuses it and only a real signal restarts the read -
  the trap recorded in the returns-panel handover, applied on purpose this time.
  A test asserts an unrelated rebuild costs zero reads.
- **The end of a run reports evidence changed from a `finally`.** A run that
  failed part-way through still moved something, and a panel that stayed stale
  because of the failure would hide exactly the sale that needs attention.

Deliberately outside this chunk:

- Nothing here submits, retries, or cancels a checkout from a surface. Every
  transition still belongs to the workers.
- The panel briefly renders nothing while it re-reads, because the guard has one
  loading state and this panel draws nothing for it. A Hive read is fast and the
  alternative is holding a figure the app has just been told may be wrong.

Files in this chunk:

```text
PLAN.md
lib/checkout/checkout.dart
lib/checkout/checkout_evidence.dart
lib/checkout/checkout_sync_signals.dart      (new)
lib/main.dart
lib/tenancy/tenant_routing_shell.dart
test/checkout/checkout_evidence_test.dart
test/checkout/checkout_sync_signals_test.dart  (new)
test/tenancy/tenant_routing_shell_test.dart
```

Validation evidence after implementation code was frozen:

| Command | Result |
| --- | --- |
| `flutter analyze --no-pub` over the 19 in-scope lib/test paths | 1 pre-existing issue: the Sentry `profilesSampleRate` warning at `lib/main.dart:29` |
| `flutter test --no-pub --concurrency=1 --reporter=failures-only test/audit test/dev test/inventory test/returns test/reporting test/sales test/shift test/checkout test/tenancy test/theme_test.dart` | **1044/1044**, up from 1028, adding **16** tests |
| `git diff --check` | clean |

The 16 new tests are 12 in the new signals file - 5 signal cases, 4 decorator
cases, and 3 seam cases that wire the signals to a real encrypted outbox and a
real `CheckoutSubmissionWorker` - plus 3 evidence-panel cases and 1 routing-shell
case for the forwarded trigger.

No backend suite was run for this chunk: it changed only Dart, and
`git diff --stat 3cb7588..HEAD -- functions firestore.rules rules-tests
firestore.indexes.json` is empty. The session-end sequence is recorded below.
Android build and Android emulator validation were skipped as requested - which
means the fix is proved by tests and not by the run that found the defect.

Meaningful failures and their resolutions:

- **The first panel refresh test found no updated count.** Two pumps deliver the
  signal and restart the guarded read; the third renders its answer. The read
  had happened - the call count was already correct - so the assertion, not the
  code, was one frame early.
- No other assertion failed.

---

## Which differences reconciliation found - 2026-08-02

### Completed in this session

The chunk specified after the reconciliation status surface and deferred when
the account-verification lockout was found. A run already reported **how many**
stock and shift differences it found; nothing said **which ones**, so a count
was alarming rather than actionable. It is now readable.

No checkout screen, payment integration, receipt printing, product cost or
profit surface, `platform_audit_logs` surface, subscription surface, or client
path that queues, retries, or cancels a run became reachable. Nothing on this
surface changes stock, a shift, or a sale.

Implemented behavior and safety decisions:

- **The four writers were read before anything was designed**, and they are the
  only authority on the field names: `jobs.ts` records an unusable sale, and
  `processors.ts` records an unreadable product quantity, three stock outcomes,
  and two shift outcomes. Seven kinds, four shapes.
- **Only the business and the kind are common, so only those are required.** The
  sale record carries no `jobId` and no `updatedAt`; the product-quantity record
  carries no figures at all; the stock and shift records carry different ones.
  Requiring a union of them would have refused three of the four real shapes.
- **Everything else is checked against the writer that produces it, and a record
  that contradicts that writer is refused.** `variance` is exactly
  `observedQuantity - expectedQuantity` in the one transaction that writes all
  three, so a stock record that misstates its own difference fails the page
  closed - the same rule the stock correction feed applies, and for the same
  reason: a record about a discrepancy that gets the discrepancy wrong is not
  evidence of anything.
- **The two kinds that look symmetrical are not, and both were pinned.**
  `stock_variance` is chosen only once the checkpoint chain is valid and every
  movement was readable, which leaves a non-zero variance as the sole remaining
  reason the record exists - so a zero variance there is refused. A
  `checkpoint_chain_invalid` record may legitimately have none, and a test says
  so. Likewise `invalid_or_missing_shift` must carry **neither** variance,
  because the writer computes both only when all four figures could be read, and
  `shift_variance` must carry both and not both zero.
- **A missing `createdAt` degrades the row rather than failing the page**, which
  is the opposite call from the figures above and deliberately so: a record
  without a time still proves the difference was found and says what it was,
  while a record that cannot explain its own difference proves nothing. That is
  the same split the activity log and the adjustment feed already record.
- **An unmodelled kind is carried verbatim.** A server deploy that records a new
  difference is not evidence of anything wrong, and hiding a real difference
  from the only surface that lists them would be far worse than naming it. It
  cannot be filtered for - `other` identifies no stored value - and the
  unnarrowed page still lists it, exactly as the movement feed handles sources.
- **The list is business-wide and says so on screen.** This decided the shape of
  the surface: a record carries **no business date**, because a stock anomaly is
  about a product and a shift anomaly is about a shift. It is reached from a
  page titled "Reconciliation for 2026-07-31", so narrowing it to that day would
  have silently hidden differences that are still open - and there is no field
  to narrow it by even if that were wanted.
- **The page computes no count of its own.** A page is bounded, so a tally over
  it would be a second and weaker figure that disagrees with the run at every
  page boundary. The run states the count; this states which ones.
- **Both query shapes need no composite index**, which is why
  `firestore.indexes.json` was not touched: the business-wide page carries no
  filter and the narrowed page carries exactly one `anomalyType ==` equality,
  both on ascending `__name__`, which is the automatic single-field index shape.
  The focused emulator suite issues both exact client queries.
- **The Rules boundary is owner/admin/manager**, the same set that reads the runs
  whose counts this explains and the `daily_metrics` those runs regenerate - a
  test asserts the two role lists are identical rather than merely similar. It
  is deliberately wider than the owner/admin `audit_logs`: this is reporting, not
  governance. The role check touches no document field, so an absent anomaly and
  a business that has never had one both still answer instead of raising an
  evaluation error. Writing stays server-only.
- **`TenantCollection` gained one frozen segment**, `reconciliation_anomalies`.
  That is a deliberate path-contract change, and the enumerated path-contract
  test was updated with it rather than around it - it failed first, exactly as
  that guard is designed to.
- **The route needs no injected builder.** Both it and the run list that points
  at it belong to the reporting domain, so nothing crosses a domain boundary;
  it opens under the caller's own `TenantSessionScope`, so a business switch
  discards an outstanding page before it can label another business's screen.

Deliberately outside this chunk, and important for the next session:

- Nothing here resolves a difference. A stock figure is still corrected from the
  product it belongs to, and a shift variance has no correction path at all.
- Product and shift IDs are shown, not resolved to names. A product name would
  be one document read per row for a label the ID already identifies.
- `reconciliation_sale_receipts`, `shift_expectations`, `stock_checkpoints`, and
  `platform_reconciliation_sweeps` still have no client surface.

Files in this chunk:

```text
PLAN.md
firestore.rules
lib/reporting/reconciliation_anomalies.dart              (new)
lib/reporting/reconciliation_anomalies_panel.dart        (new)
lib/reporting/reconciliation_status_panel.dart
lib/reporting/reporting.dart
lib/tenancy/tenant_paths.dart
rules-tests/package.json
rules-tests/test/reconciliation-anomalies.test.js        (new)
test/reporting/reconciliation_anomalies_panel_test.dart  (new)
test/reporting/reconciliation_anomalies_test.dart        (new)
test/reporting/reconciliation_status_panel_test.dart
test/tenancy/tenant_paths_test.dart
```

Validation evidence after implementation code was frozen:

| Command | Result |
| --- | --- |
| `flutter analyze --no-pub` over the 19 in-scope lib/test paths | 1 pre-existing issue: the Sentry `profilesSampleRate` warning at `lib/main.dart:29` |
| `flutter test --no-pub --concurrency=1 --reporter=failures-only test/audit test/dev test/inventory test/returns test/reporting test/sales test/shift test/checkout test/tenancy test/theme_test.dart` | **1079/1079**, up from 1044, adding **35** tests |
| `npm --prefix rules-tests run test:emulator:reconciliation-anomalies` | **6/6** during development |
| `npm --prefix rules-tests run test:emulator` | **131/131**, up from 125 |
| `FUNCTIONS_DISCOVERY_TIMEOUT=60000 npm --prefix rules-tests run test:emulator:invitations` | **12/12** real Auth, Firestore, and Functions emulator tests |
| `git diff --check` | clean |

The 35 new Dart tests are 24 read-model and repository cases, 10 panel widget
cases, and 1 status-panel case for the entry point; `test/reporting` went from
169 to **204**. `npm --prefix functions test` was not re-run: `git diff --stat
HEAD -- functions` is empty, so all 171 Functions tests remain byte-identical to
the previous session's green run and no Dart or Rules change can reach them.
`firestore.indexes.json` was deliberately not touched. Android build and Android
emulator validation were skipped as requested.

Meaningful failures and their resolutions:

- **The frozen path-contract test failed, exactly as it should have.**
  `tenant_paths_test.dart` enumerates every business collection, so adding
  `reconciliation_anomalies` broke it until the segment was declared there too,
  with a comment recording why the contract changed. That guard is working as
  designed and must not be loosened.
- **A cross-tenant repository test expected the wrong refusal, and the code was
  right.** The base repository's exact-child proof answers before the read model
  does, so the response fails as `TenantScopeViolation` rather than as a bad
  path - the stronger answer, since a transport replying outside this tenant is
  a broken boundary rather than one unreadable record. The assertion was
  corrected and a second test now covers a record that sits at the right path
  while naming another business, which is what `anomaly_identity_mismatch` is
  for.
- No other assertion failed.

The existing user-owned local edits remain separate and were never staged:

```text
.vscode/settings.json
android/gradle.properties
pubspec.lock
```

### Next bounded chunk

Two candidates, in the order recommended:

1. **Run the app again, and this time watch a sale reach Firestore without a
   restart.** The first chunk of this session fixed exactly the defect the last
   real run found, and it is proved by tests rather than by use. That run also
   left two things unverified: the `10.0.2.2` Android path has still never been
   executed by anybody, and nothing has exercised the new anomaly surface
   against real seeded data. Ask first whether the Android exclusion is lifted;
   a Windows or web run exercises only the loopback path.
2. **A correction path for a shift variance.** The anomaly surface now names one
   and offers nothing to do about it, which is honest but incomplete. A stock
   difference is corrected from the product; a shift difference has no answer at
   all today. Decide on the **server** first - whether a closed shift's summary
   may ever be amended, and by whom - because nothing in `firestore.rules`
   currently permits it and the frozen contract makes a closed shift terminal.

Leave outside either chunk: the subscription surfaces (examined and declined
earlier in this file - start on the server, not in Flutter), receipt printing,
the printed receipt body, discounts, camera barcode scanning, password reset
(still blocked on the App Check decision recorded near the top of this file),
product cost/profit fields, a `platform_audit_logs` surface, branding surfaces,
and deployment.

Practical notes carried forward:

- The emulator prelude is not optional on this machine. The default `java` is
  JDK 17 and every emulator command fails immediately without it:

```powershell
$env:DEBUG = $null
$env:JAVA_HOME = 'D:\firebase-emulator-tools\jdk21\jdk-21.0.12+8'
$env:Path = "$env:JAVA_HOME\bin;D:\firebase-emulator-tools\node-v24.18.1-win-x64;$env:Path"
```

- A local `firebase emulators:exec` against `firebase.json` needs both
  `functions/.secret.local` and `functions/.env.local`; `run-dev-emulators.js`
  writes and removes them, and refuses to overwrite leftovers from a killed run.
- Collection-page test fakes must answer in **ascending document-ID order**, be
  keyed **per business**, and model the equality-filter contract in **both**
  directions - a fake that honours filters cannot exercise a check that exists
  for a transport ignoring them, and a fake that ignores them makes every
  narrowed page prove the wrong thing. Both mistakes have now cost a debugging
  cycle each.

---

## A closed shift may be corrected to what its sales prove - 2026-08-04

### Completed in this session

The previous session's anomaly surface names a `shift_variance` and offers
nothing to do about it. The handover said to decide the **server** first -
whether a closed shift's summary may ever be amended, and by whom - because
nothing in `firestore.rules` permitted it and the frozen contract makes a closed
shift terminal. That decision is now made, implemented, and tested. No client
surface was added; the callable has no caller yet, which is the next chunk.

The decision, in one sentence: **yes, but only to the figure the immutable sales
already prove, only by an owner or administrator, and never to the counted
cash.**

Implemented behavior and safety decisions:

- **`amendShiftSummary` accepts no figure.** The caller names a shift and states
  a reason. The amended total is read from the settled `shift_expectations`
  record the metrics writer derived from the sales themselves, so the only
  reachable outcome is a shift that agrees with its own sales. A callable that
  took a total would be a way to write any number onto a closed shift.
- **The counted cash is out of reach, and the record says so.**
  `closingCashMinor` and `closingCash` are a physical count of a drawer.
  Amending one would erase a cash discrepancy, which is the single thing this
  path must be unable to do. The plan object never contains a cash key - a test
  asserts that over `Object.keys`, so the property is checked rather than
  intended - and both the amendment record and the audit entry carry
  `mutatesCountedCash: false`, in the same spirit as the existing
  `mutatesStock: false` and `mutatesShift: false`.
- **The expectation must be the settled one for this exact shift.** Verification
  must have finished (`needsVerification == false`), the generation it settled
  must still be the generation the record carries, and the outcome it settled on
  must be `variance`. A pending record is about to be recomputed, so a total
  taken from it is a total nothing has verified; `matched`, `quarantined`,
  `invalid_or_missing_shift`, and an already-amended record are all refused too.
  That last one is what makes a second amendment of one generation impossible
  rather than merely pointless.
- **`invalid_or_missing_shift` deliberately has no amendment path.** A shift
  that recorded no readable summary has no difference to resolve - nothing could
  be compared in the first place - so there is no figure the sales prove it
  should hold. Only a shift that recorded a summary can have one corrected.
- **The "nothing to amend" test is the verifier's own comparison, asked again.**
  The verifier compares major units, so this does too. The consequence is
  deliberate and documented: a shift whose stored *minor* units are broken while
  its major units are correct is **not** amendable here. That is a different
  defect from a reconciliation variance, and giving a governance callable a
  second purpose is worse than leaving it. A shift whose two representations
  disagree *and* whose major figure is genuinely wrong is amended - both are
  rewritten from one figure - and the record states
  `previousRepresentationsAgreed: false` so the second defect is not silently
  absorbed.
- **The amended total can never be one the client refuses to read.** The plan
  bounds it by the client's own `maximumShiftSalesMinor` and refuses takings over
  no transactions, which are exactly the two invariants `firestore.rules` and
  `ShiftClosingSummary._closingSummary` enforce. An amendment that left a shift
  no device could display would be worse than the variance it corrected.
- **The resolved difference is removed from the list, and only that one.**
  `reconciliation_anomalies` is the surface named for differences that are still
  open, and the verifier never deletes one, so a resolved variance would
  otherwise be listed forever. The record is read inside the transaction and
  cleared only when it names this business, this shift, and `shift_variance`; a
  record at that ID naming anything else is corruption rather than this shift's
  difference, so it is left exactly where it is and the amendment records
  `clearedAnomalyId: null`. Nothing is lost either way: the immutable
  `shift_amendments` record and the `audit_logs` entry both carry the
  difference, its direction, and the figures on both sides of it.
- **Deleting rather than flagging keeps the frozen query shape.** A `resolved`
  flag would require an `anomalyType ==` plus `resolved ==` page, which is the
  one composite index the previous chunk was careful not to need.
- **The expectation is settled in the same transaction, not marked pending.**
  Both figures were read there and the shift holds the expected one by
  construction, so recording the amended status is simply true, and it avoids a
  record left pending forever if no further run happens. A later metrics
  regeneration - an offline sale arriving after the close, which the sale rule
  deliberately accepts - produces a *new* generation, a fresh verification, and
  if it disagrees a new anomaly under a different digest. A later divergence is a
  new difference, not this one reopening.
- **Roles are owner/admin, deliberately narrower than the owner/admin/manager
  set that reads the difference.** Rewriting a record every client treats as
  terminal is governance rather than reporting, so it matches the set that may
  spend the manual reconciliation allowance and that reads `audit_logs`. A
  manager may see that a shift disagrees with its sales without being able to
  rewrite the shift. Authorization runs before the idempotency cache is
  consulted and again inside the transaction, as `adjustStock` does.
- **Two IDs became one definition each.** `shiftExpectationId` and
  `shiftAnomalyId` moved into `reconciliation/model.ts`, and `processors.ts` now
  imports them. Three writers must agree on the expectation document and two on
  the anomaly document; a second definition of either would amend a shift
  against another shift's expectation, or clear nothing and leave a resolved
  difference listed. Both are pinned by a test against the digest shape.
- **`shift_amendments` is readable by owner/admin/manager and writable by
  nobody.** Whoever may see the corrected figure may see why it changed. A
  cashier is excluded exactly as they are from `stock_adjustments`: the record
  names the owner who amended the shift and states their reason, which is the
  business's governance rather than one shift's operational information - and
  because the amendment never touches the counted cash, nothing the cashier
  counted and answers for is changed by a record they cannot read. The corrected
  shift itself stays readable to them.
- **The amendment opened no second way into a closed shift.** It adds fields to
  a closed document, so the Rules suite proves the cashier still cannot restate
  the corrected summary, re-close the shift, touch the counted cash, claim an
  amendment of their own, or reopen it - and that an owner cannot reach the shift
  document either. Amending runs through the callable or not at all.

Deliberately outside this chunk, and important for the next session:

- Nothing in the app calls `amendShiftSummary` yet. There is no gateway, no
  action on the anomaly row, and no `shift_amendments` read surface.
- No end-to-end emulator test exercises the callable. The only
  Auth/Firestore/Functions integration suite is the invitation one, and adding a
  second runner is its own piece of work.
- A `checkpoint_chain_invalid`, `invalid_stock_movement`, `invalid_sale_lines`,
  or `invalid_product_quantity` difference still has no resolution path. A stock
  figure is still corrected from the product it belongs to.

Files in this chunk:

```text
PLAN.md
firestore.rules
functions/src/index.ts
functions/src/reconciliation/amendment.ts        (new)
functions/src/reconciliation/amendment.test.ts   (new)
functions/src/reconciliation/amendments.ts       (new)
functions/src/reconciliation/index.ts
functions/src/reconciliation/model.ts
functions/src/reconciliation/model.test.ts
functions/src/reconciliation/processors.ts
rules-tests/package.json
rules-tests/test/shift-amendments.test.js        (new)
```

Validation evidence after implementation code was frozen:

| Command | Result |
| --- | --- |
| `npm --prefix functions run build` | clean |
| `node --test lib/reconciliation/amendment.test.js lib/reconciliation/model.test.js` | **22/22** during development |
| `npm --prefix rules-tests run test:emulator:shift-amendments` | **8/8** during development |
| `npm --prefix functions test` | **185/185**, up from 171, adding **14** tests |
| `npm --prefix rules-tests run test:emulator` | **139/139**, up from 131, adding **8** tests |
| `FUNCTIONS_DISCOVERY_TIMEOUT=60000 npm --prefix rules-tests run test:emulator:invitations` | **12/12** real Auth, Firestore, and Functions emulator tests |
| `git diff --check` | clean |

The 14 new Functions tests are 13 planner cases and 1 shared-identity case.
`flutter analyze` and `flutter test` were not re-run: `git diff --stat HEAD --
lib test` is empty, so no Dart code changed and no TypeScript or Rules change
can reach it. `firestore.indexes.json` was deliberately not touched - the
amendment feed's business-wide page and its one `shiftId ==` narrowing are both
the automatic single-field index shape, and the Rules suite issues both exact
client queries. Android build and Android emulator validation were skipped as
requested.

Meaningful failures and their resolutions:

- **The first focused run failed on two missing-document cases, and the test
  helper was at fault rather than the planner.** The helper gave its `shift` and
  `expectation` parameters defaults, so passing an explicit `undefined` silently
  substituted a *valid* document: JavaScript default parameters fire on an
  explicit `undefined`. Both cases passed without ever running the code they
  named. The defaults were removed and every call site now states both
  arguments, with a comment recording why the parameters are required. This is
  worth remembering - a defaulted test helper can make an absent-document case
  prove nothing at all.
- **One design decision was reversed while writing its test.** The "nothing to
  amend" check first required all three stored figures to match, which made a
  shift with correct major units and broken minor units amendable. That state
  cannot arise from the verifier - it would have settled as matched - so acting
  on it meant acting on a record contradicting its own writer. The check now
  asks exactly the verifier's question, and the test asserts the refusal and
  says why.
- No other assertion failed.

The existing user-owned local edits remain separate and were never staged:

```text
.vscode/settings.json
android/gradle.properties
pubspec.lock
```

### Next bounded chunk

**Make the correction reachable, from the row that reports the difference.**
The server now has exactly one way to resolve a shift variance and nothing calls
it. Implement, in this order:

1. A session-bound shift-amendment gateway in the reporting domain, modelled on
   `TenantReconciliationRequestGateway`: owner/admin only, business from the
   captured live session so no caller can name another, one intent per attempt
   carrying one server-pattern request ID, and a typed failure enum that
   distinguishes forbidden, not-amendable (`failed-precondition`), missing shift
   (`not-found`), duplicate request, and the genuinely ambiguous transport codes.
   Unlike the reconciliation request, this callable is a single Firestore
   transaction with no post-commit enqueue, so an ambiguous outcome is settled by
   re-reading the shift rather than being permanently unknowable - say so in the
   type.
2. Strict decoding of the response against the intent it was sent for: it must
   name this shift and business, and its `totalSalesMinor` and
   `transactionCount` must be the figures it claims to have written.
3. A bounded action on the `shift_variance` row of the existing anomalies panel,
   granted through `TenantReconciliationActions` exactly as the request callable
   is, so a build with no capability stays the read-only list it is today. It
   must require a typed reason, state plainly that the counted cash is not
   changed, and refresh the page after a success so the resolved difference
   disappears.
4. Widget coverage for: the action absent without the capability, absent for a
   manager, absent on every non-`shift_variance` kind, each typed refusal shown
   as a distinct message, and a tenant switch during an outstanding call
   discarding the result.

Leave outside that chunk: a `shift_amendments` read surface (the list of
corrections, as distinct from making one), any resolution path for the four
stock and sale differences, a second Auth/Firestore/Functions integration
runner, the subscription surfaces (examined and declined earlier in this file -
start on the server, not in Flutter), receipt printing, the printed receipt body,
discounts, camera barcode scanning, password reset (still blocked on the App
Check decision recorded near the top of this file), product cost/profit fields, a
`platform_audit_logs` surface, branding surfaces, and deployment.

Practical notes carried forward:

- The emulator prelude is not optional on this machine. The default `java` is
  JDK 17 and every emulator command fails immediately without it:

```powershell
$env:DEBUG = $null
$env:JAVA_HOME = 'D:\firebase-emulator-tools\jdk21\jdk-21.0.12+8'
$env:Path = "$env:JAVA_HOME\bin;D:\firebase-emulator-tools\node-v24.18.1-win-x64;$env:Path"
```

- A local `firebase emulators:exec` against `firebase.json` needs both
  `functions/.secret.local` and `functions/.env.local`; `run-dev-emulators.js`
  writes and removes them, and refuses to overwrite leftovers from a killed run.
- Collection-page test fakes must answer in **ascending document-ID order**, be
  keyed **per business**, and model the equality-filter contract in **both**
  directions.
- A test helper with default parameters cannot test an absent document. Require
  the parameters instead.

---

## The correction is reachable from the row that reports it - 2026-08-04

### Completed in this session

The chunk immediately above gave the server exactly one way to resolve a shift
variance and nothing called it. It is now reachable from the only surface that
names such a difference, granted by the composition root exactly as the
reconciliation request is, so a build without the capability is still the
read-only list it was.

Implemented behavior and safety decisions:

- **`TenantShiftAmendmentGateway` is session-bound and takes no business.** The
  business comes from one captured live session, so no caller can correct a shift
  somewhere else, and the only things a caller chooses are which shift and why.
  The corrected figure is not an input at any layer: the payload carries
  `tenantId`, `shiftId`, `reason`, and `requestId`, and a test pins that exact
  map.
- **Owner and administrator only, refused locally first.** The client enforces
  the server's own `SHIFT_AMENDMENT_ROLES` before anything is sent, so a manager
  reading the list gets an immediate, explained refusal rather than a round trip.
  A cashier never reaches the surface at all.
- **The reason is normalized exactly as `normalizeReason` will normalize it**,
  in the same order: trim, check the trimmed length against 3 and 500, collapse
  whitespace runs, then refuse remaining control characters. Sending the
  already-normalized value is what makes a retry hash to the *same* idempotency
  record instead of being refused as one request with two different inputs. Both
  boundary lengths and two non-whitespace control characters are tested.
- **`failed-precondition` is its own outcome, not a generic refusal.** It is the
  server saying this shift cannot be corrected - open, already agreeing with its
  sales, no settled variance yet, or no readable totals at all - which is the
  most likely refusal in practice and the one a person can act on. `not-found`
  is separated from it for the same reason.
- **The response is reconciled against the intent it was sent for.** It must
  name this business and this shift; `amendmentId`, `businessDate`, and every
  figure are strictly typed and bounded by the same `maximumShiftSalesMinor` the
  shift history read model enforces. The transaction identity
  `transactionVariance == previousTransactionCount - transactionCount` is
  asserted because both counts come from one comparison and it is exact.
- **The money identity is deliberately *not* asserted, and a test says why.**
  The recorded variance is measured from the shift's major-unit total, which may
  legitimately disagree with its stored minor units, so an identity that can fail
  honestly would refuse a real amendment. Two further reachable-but-surprising
  responses are accepted on purpose and tested: `clearedAnomalyId: null` (no
  difference was listed under this generation, or the record there described
  something else), and an amendment whose previous and new totals are equal.
- **Only the `shift_variance` row offers a correction.** `invalid_or_missing_shift`
  does not - with no readable totals nothing could be compared, so there is no
  figure the sales prove the shift should hold - and neither do the three stock
  kinds or the sale kind. A test asserts the button's presence on the one and its
  absence on the other four.
- **A manager is told about the one thing they cannot do, once.** The explanation
  appears only when the capability exists, the session cannot use it, *and* the
  page actually lists a shift variance, so a page of stock differences does not
  carry an irrelevant notice.
- **The dialog states the two facts that make agreeing to this safe:** the
  figure is not a choice, and the cash counted at close is not changed. A reason
  is required and is kept in the business's immutable amendment record beside the
  name of whoever asked for it.
- **The list is re-read from the server after a success, never edited locally.**
  The server deletes a resolved difference, so the second read is the proof that
  it is gone. A refusal that left the shift untouched deliberately does *not*
  re-read: showing a difference as resolved when it is not would be worse than
  showing it unresolved. An ambiguous outcome and an untrustworthy answer both
  re-read and say what they do not know.
- **One request ID survives only an ambiguous attempt.** Every other refusal
  clears it, because reusing an ID that settled nothing would make the next
  attempt fail as a duplicate. This mirrors the reconciliation request gateway.
- **A business switch during an outstanding correction discards it.** The session
  key is captured before the call and re-checked after it, and a widget test
  proves tenant A's correction never reports itself on tenant B's screen - and
  asserts the call was actually made first, so a missing notice cannot be a
  correction that was never sent.
- **The capability travels with the route.** The differences list is only
  reachable from the reconciliation status page, so the status panel passes its
  actions through, and a test on that route proves the button arrives. A
  capability that did not travel would be a callable nothing could ever call.
- **One server field was added:** `amendShiftSummary` now echoes `tenantId` in
  its response. Without it the client could not prove the server acted on the
  business it asked about before labelling that business's screen with the
  answer, which is the same guard the reconciliation request gateway applies.

Deliberately outside this chunk, and important for the next session:

- There is still no `shift_amendments` read surface. The corrections are
  recorded, readable by owner/admin/manager under the Rules committed in the
  previous chunk, and listed nowhere.
- No end-to-end emulator test exercises the callable. The only
  Auth/Firestore/Functions integration suite is the invitation one.
- The four stock and sale differences still have no resolution path.
- The differences list shows no currency code on its figures, exactly as before.
  It reads no `configuration/checkout` document, so the amounts in the row detail
  and in the success notice are bare, which is what that surface already did.

Files in this chunk:

```text
PLAN.md
functions/src/reconciliation/amendments.ts
lib/main.dart
lib/reporting/reconciliation_actions.dart
lib/reporting/reconciliation_anomalies_panel.dart
lib/reporting/reconciliation_status_panel.dart
lib/reporting/reporting.dart
lib/reporting/shift_amendment.dart                        (new)
test/reporting/reconciliation_anomalies_panel_test.dart
test/reporting/reconciliation_status_panel_test.dart
test/reporting/shift_amendment_test.dart                  (new)
```

Validation evidence after implementation code was frozen:

| Command | Result |
| --- | --- |
| `flutter analyze --no-pub lib/main.dart lib/reporting test/reporting` | 1 pre-existing issue: the Sentry `profilesSampleRate` warning at `lib/main.dart:29` |
| `flutter test --no-pub --concurrency=1 --reporter=failures-only test/reporting` | **250/250** during development, up from 204 |
| `flutter test --no-pub --concurrency=1 --reporter=failures-only test/audit test/dev test/inventory test/returns test/reporting test/sales test/shift test/checkout test/tenancy test/theme_test.dart` | **1125/1125**, up from 1079, adding **46** tests |
| `npm --prefix functions test` | **185/185** |
| `npm --prefix rules-tests run test:emulator` | **139/139** |
| `FUNCTIONS_DISCOVERY_TIMEOUT=60000 npm --prefix rules-tests run test:emulator:invitations` | **12/12** real Auth, Firestore, and Functions emulator tests |
| `git diff --check` | clean |

The 46 new Dart tests are 35 gateway cases, 10 panel widget cases, and 1
status-route case proving the capability travels. The Functions and Rules suites
were re-run because `amendments.ts` gained the echoed `tenantId`;
`firestore.rules` and `rules-tests` are byte-identical to the previous chunk's
green run. `firestore.indexes.json` was not touched. Android build and Android
emulator validation were skipped as requested.

Meaningful failures and their resolutions:

- **The widget suite would not compile: `FirebaseFunctionsException` was not
  imported** into the panel test, which had never needed `cloud_functions`
  before. Adding the import was the whole fix.
- **Two reasons in the "unusable reason" table were actually valid.** The list
  originally held `'Late sale '` and `'Late sale'`, both of which normalize to a
  perfectly good nine-character reason, so the case would have failed for the
  right reason only by accident. They were replaced with the two things that are
  genuinely refused - a NUL and a BEL, which whitespace collapsing does not
  remove - which is what the server's `\p{Cc}` check is actually for.
- **The status-panel reader fake answered one page for two collections.** The new
  route test seeded a shift difference and the runs query would have answered
  with it. The fake now answers `reconciliation_anomalies` separately, for the
  same reason its filter contract is modelled in both directions: a fake that
  conflates two collections makes a test prove the wrong thing.
- No other assertion failed.

The existing user-owned local edits remain separate and were never staged:

```text
.vscode/settings.json
android/gradle.properties
pubspec.lock
```

### Next bounded chunk

Two candidates, in the order recommended:

1. **Run the app and correct a real shift.** Two chunks of server and client work
   are now proved by tests and by nothing else. Seed a business date with sales
   whose shift summary is deliberately wrong, let a manual reconciliation settle
   the variance, then correct it from the differences list and watch the row
   disappear. This also exercises the two things the last real run left
   unverified: the `10.0.2.2` Android path has still never been executed by
   anybody, and nothing has exercised the anomaly surface against real seeded
   data. Ask first whether the Android exclusion is lifted; a Windows or web run
   exercises only the loopback path. `rules-tests/scripts/seed-dev-emulator.js`
   and `emulators:dev` are the existing way in.
2. **The list of corrections.** `shift_amendments` is written, its Rules boundary
   is committed and tested, and nothing reads it. A read model plus a bounded
   business-wide page narrowed by one `shiftId ==` equality - both already proved
   servable without a composite index by the Rules suite - would make the
   correction trail visible to the owner/admin/manager set that may see it,
   exactly as `stock_adjustments` is. Model it on
   `TenantStockAdjustmentRepository` and refuse a record that cannot explain its
   own correction, the same rule the differences read model applies.

Leave outside either chunk: any resolution path for the four stock and sale
differences, a second Auth/Firestore/Functions integration runner, currency
labels on the differences list, the subscription surfaces (examined and declined
earlier in this file - start on the server, not in Flutter), receipt printing, the
printed receipt body, discounts, camera barcode scanning, password reset (still
blocked on the App Check decision recorded near the top of this file), product
cost/profit fields, a `platform_audit_logs` surface, branding surfaces, and
deployment.

Practical notes carried forward:

- The emulator prelude is not optional on this machine. The default `java` is
  JDK 17 and every emulator command fails immediately without it:

```powershell
$env:DEBUG = $null
$env:JAVA_HOME = 'D:\firebase-emulator-tools\jdk21\jdk-21.0.12+8'
$env:Path = "$env:JAVA_HOME\bin;D:\firebase-emulator-tools\node-v24.18.1-win-x64;$env:Path"
```

- A local `firebase emulators:exec` against `firebase.json` needs both
  `functions/.secret.local` and `functions/.env.local`; `run-dev-emulators.js`
  writes and removes them, and refuses to overwrite leftovers from a killed run.
- Collection-page test fakes must answer in **ascending document-ID order**, be
  keyed **per business**, model the equality-filter contract in **both**
  directions, and answer **per collection**. All four mistakes have now cost a
  debugging cycle.
- A test helper with default parameters cannot test an absent document, and a
  table of "invalid" inputs is worth re-reading: two entries in this session's
  first draft were valid.

---

## The first run that corrected a real shift - 2026-08-04

### Completed in this session

Candidate 1 of the chunk above. The Android exclusion was lifted at the user's
request, so the app was driven end to end on an API 35 emulator against the
local Firebase suite: sign in as the seeded owner, open a shift, ring up a sale,
watch it reach Firestore, close the shift, plant a late-arriving sale, let
reconciliation find the variance, and correct it from the differences list.

**It found three defects. Two were severe and one of those means reconciliation
has never worked at all.** All three are fixed here, each with a regression test
that fails on the original code. No feature was added.

The chunk is worth recording as vindication of its own premise: eleven sessions
of test-driven work produced 1125 green Dart tests, 185 Functions tests, 139
Rules tests and 12 integration tests, and one hour of use found a server bug that
disabled an entire subsystem.

### Defect 1: the sale trigger has never once succeeded

`mergeSaleReconciliationJob` crashed on **every** sale:

```text
Error: Value for argument "data" is not a valid Firestore document.
FieldValue.delete() must appear at the top-level and can only be used in
update() or set() with {merge:true} (found in field "productCursor").
  at functions/lib/reconciliation/jobs.js:189
```

- `registerSaleReceipt` built **one** `commonJobData` object and passed it to
  `transaction.update` on one branch and `transaction.create` on the other. The
  requeue half of it clears `productCursor` and `pendingProductId` with
  `FieldValue.delete()`, which is legal in `update()` and rejected outright in
  `create()`.
- The create branch is the **first sale of every five-minute bucket**, and
  `mergeDirtyJob(undefined)` always returns `queued`, so the sentinels were always
  present and the write always threw. The trigger has `retry: true`, so it then
  failed forever.
- The consequence is not cosmetic. No `reconciliation_dirty_days` and no
  `reconciliation_jobs` were ever written from a sale, so **no daily metric was
  ever regenerated from sale activity and no stock or shift verification ever
  ran**. The nightly sweep creates jobs through a different path and is
  unaffected, but on this project nightly is a pub/sub schedule the emulator does
  not run, so nothing reconciled anything until this was fixed.
- **Why no test caught it.** A `FieldValue.delete()` is an ordinary object until
  the write is serialized, so the payload compiles, type-checks, and inspects
  fine. Only a real Firestore rejects it. Every one of the 185 Functions tests is
  pure.
- **The fix** extracts `saleTriggerJobFields`, which returns the create and
  update payloads **separately** because they are not the same document. The
  create payload cannot carry a sentinel because a brand-new job has no cursor to
  clear. `jobs.test.ts` asserts that property over every decision status, and was
  confirmed to fail (2 of 5 cases) when the sentinel is put back.

### Defect 2: a shift could not be closed on the day it sold anything

- A saved sale reached Firestore immediately - the previous chunk's fix works, and
  this run is the proof by use - but the local outbox record stopped at
  `awaiting_confirmation`, so the shift reported "1 sale on this device is not
  synchronized yet" and **refused to close**. A restart fixed it, which is what
  identified the cause.
- The composition root ran recovery **before** submission and never again, so a
  commit inside a pass left a record that only a *later* trigger could confirm.
  Submission and confirmation are two halves of the pipeline and only the first
  half was reachable from a save. A connectivity toggle did not settle it either;
  only session-open recovery did.
- **The fix** is `CheckoutSyncPass`: recover, submit, **recover again**, then
  refresh derived data. It is a tested unit rather than a closure in `main.dart`
  precisely because the order is the whole content. Running recovery twice is
  cheap and safe - a bounded local scan that confirms only what the server can be
  read to hold, and leaves anything it cannot settle exactly as it was.
- Verified on the device after the fix: the same flow now reports "Confirmed
  sales: 1 transactions, 6500 minor units" with no restart.

### Defect 3: the differences list needed no fix, and that is the finding

The correction path built in the two previous chunks worked first time, against
real seeded data, with no change required. Recorded because it is evidence about
those chunks rather than about this one:

- The row read "Its sales total is 230 short and its transaction count is 2 short
  against the sales recorded during it" - exactly the server's figures.
- The dialog carried both safety sentences, required a reason, and refused to
  submit without one.
- The success notice read "now records 345.00 instead of 115.00, over 3
  transactions rather than 1. The counted cash was not changed."
- The list re-read and reported "The server has recorded no unresolved
  differences for this business."
- Server state afterwards: `shift_amendments` recorded 11500/1 â†’ 34500/3 with
  `mutatesCountedCash: false`, the reason, and the cleared anomaly ID;
  `audit_logs` recorded `shift_summary_amended` with `salesVarianceMinor: -23000`;
  `reconciliation_anomalies` was **empty**; and `closingCashMinor` was still
  11500, untouched.
- The amended shift is still readable by the strict client model - the invariant
  the planner was written to guarantee. Shift history renders "Counted cash:
  115.00 / Recorded sales: 345.00 over 3 transactions / Counted cash is short by
  230.00", which is the truthful outcome: the late sales' cash never went into the
  drawer.

### `plant-late-sale.js`

A late-arriving sale is the one state nothing in the repository could produce -
the till refuses to sell without an open shift, and a shift refuses to close
while any sale is unsettled - so the correction path could only ever be proved by
tests. The new script writes one, and it is the scenario the `sales` create rule
was deliberately written to permit.

- It **clones a sale the app itself wrote** rather than inventing one, so every
  field has exactly the shape `_saleFields` produces and a mistake in the script
  cannot be mistaken for a defect in the surface being exercised. Only the
  identity fields move: a fresh checkout ID, the next receipt sequence, and the
  receipt number those two derive.
- It decrements the product in the same write the app would have used. Without
  that the trigger-owned stock movement would have nothing to account for and the
  run would report a *stock* difference beside the shift one - noise that looks
  like a defect.
- It carries the same emulator-only guard as the seeder: the two host variables
  are what make `firebase-admin` incapable of reaching a real project, so
  requiring them is the guarantee rather than a check.

### Also observed, and deliberately not fixed

- **The evidence panel renders inconsistently.** Under "Checkouts stored on this
  device" it sometimes lists all five states with their counts and sometimes only
  "Saved offline: 0", with at least one record present. Reproducible across two
  screenshots each way; not diagnosed.
- **"1 transactions".** The shift panel does not singularise its transaction
  count.
- **The login screen keeps a stale error across edits**, and the message it
  showed was a raw platform-channel name
  (`dev.flutter.pigeon.firebase_auth_platform_interface...`). It appeared only
  after a mistyped sign-in and did not recur on a clean run, so it was not chased;
  a raw channel name is not a sentence to show a user either way.
- The Sentry DSN is still an `http://` URL that Android blocks in every build, as
  the previous run recorded.
- The differences list still shows bare amounts with no currency code.

### Files in this chunk

```text
PLAN.md
functions/src/reconciliation/jobs.ts
functions/src/reconciliation/jobs.test.ts        (new)
lib/checkout/checkout.dart
lib/checkout/checkout_sync_pass.dart             (new)
lib/main.dart
rules-tests/package.json
rules-tests/scripts/plant-late-sale.js           (new)
test/checkout/checkout_sync_pass_test.dart       (new)
test/checkout/checkout_sync_signals_test.dart
```

### Validation evidence after implementation code was frozen

| Command | Result |
| --- | --- |
| `flutter analyze --no-pub` over the 21 in-scope lib/test paths | 2 pre-existing issues: the Sentry `profilesSampleRate` warning at `lib/main.dart:29` and the unused `cloud_firestore` import at `lib/theme.dart:2` |
| `flutter test --no-pub --concurrency=1 --reporter=failures-only test/audit test/dev test/inventory test/returns test/reporting test/sales test/shift test/checkout test/tenancy test/theme_test.dart` | **1131/1131**, up from 1125, adding **6** tests |
| `npm --prefix functions test` | **190/190**, up from 185, adding **5** tests |
| `npm --prefix rules-tests run test:emulator` | **139/139**, unchanged |
| `FUNCTIONS_DISCOVERY_TIMEOUT=60000 npm --prefix rules-tests run test:emulator:invitations` | **12/12** real Auth, Firestore, and Functions emulator tests |
| `flutter build apk --debug --no-pub --target-platform android-x64 --dart-define=USE_FIREBASE_EMULATORS=true` | built twice, installed and driven on the API 35 emulator |
| `git diff --check` | clean |

The 6 new Dart tests are 5 sync-pass ordering cases and 1 seam case that wires a
real encrypted outbox, a real submission worker, and a real recovery coordinator
and asserts a saved sale ends **confirmed**. The 5 new Functions tests pin the
create payload against sentinels over every decision status. The Rules suite is
unchanged because no rule changed; it was re-run because `functions/src` did.

### Meaningful failures and their resolutions

Beyond the three defects above, the run itself cost time in ways worth recording:

- **`adb shell input text` silently truncates at the first space.** The password
  landed in the email field and a reason arrived as one word. Use `%s` for each
  space, and screenshot after every field rather than after a chain.
- **Tapping by coordinate is fragile because the layout moves.** Selecting a
  tender removes the "Choose how the customer paid" line and shifts the save
  button up; adding cart lines pushes the tender chips off screen entirely.
  Screenshot, then tap, then screenshot.
- **`Get-NetTCPConnection` had to be used to clear orphaned emulator ports**
  after a killed run, in addition to the two local config files the previous
  handover already documented.
- **`JAVA_TOOL_OPTIONS=-Xmx512m` let the Firebase emulators start beside a
  running Android emulator** on this 2-3 GB host. Gradle still must not run at
  the same time as either.
- The Firestore emulator's REST API with a `Bearer owner` token bypasses Rules
  and was how every server assertion in this handover was made.

### The existing user-owned local edits remain separate and were never staged

```text
.vscode/settings.json
android/gradle.properties
pubspec.lock
```

### Next bounded chunk

**Audit every other `FieldValue.delete()` for the same defect.** Defect 1 was
found by use, not by search, and there are roughly forty more sentinel sites. The
specific hazard is a payload object shared between a `create`/`set`-without-merge
and an `update`. Three were checked by hand this session and are safe -
`processors.ts:583` is inside `set(..., {merge: true})`, and
`membershipMirrorStore`'s `initialRunData` carries no sentinel while its
`progressData` is update-only - but `email/*`, `platform/*`, and the remaining
`jobs.ts` sites were **not** verified. Do it properly:

1. Enumerate every `FieldValue.delete()` and classify its write kind. A sentinel
   is only legal in `update()` or `set(..., {merge: true})`.
2. Where a payload is shared between branches, split it as
   `saleTriggerJobFields` now does, and pin the create half with a test that
   asserts no sentinel - the pattern in `jobs.test.ts`, which was confirmed to
   fail on the original defect.
3. Consider one shared test helper for that assertion rather than repeating the
   `isEqual(FieldValue.delete())` walk.
4. Nothing about this needs a device. It is a bounded, mechanical audit with a
   real defect class behind it.

Then, in preference order:

- **A second integration runner for the sale trigger and reconciliation.** The
  invitation suite is the only Auth/Firestore/Functions harness, and defect 1
  would have been caught instantly by one test that creates a sale and asserts a
  dirty day appears. This is the harness gap the defect exposed.
- **The `shift_amendments` read surface**, still the untouched candidate 2 from
  the previous handover: written, readable by owner/admin/manager, listed nowhere.
- The evidence-panel rendering inconsistency and the "1 transactions" plural.

Leave outside all of them: any resolution path for the four stock and sale
differences, currency labels on the differences list, the subscription surfaces
(examined and declined earlier in this file - start on the server, not in
Flutter), receipt printing, the printed receipt body, discounts, camera barcode
scanning, password reset (still blocked on the App Check decision recorded near
the top of this file), product cost/profit fields, a `platform_audit_logs`
surface, branding surfaces, the Sentry DSN, and deployment.

### Practical notes carried forward

- The emulator prelude is not optional on this machine. The default `java` is
  JDK 17 and every emulator command fails immediately without it:

```powershell
$env:DEBUG = $null
$env:JAVA_HOME = 'D:\firebase-emulator-tools\jdk21\jdk-21.0.12+8'
$env:Path = "$env:JAVA_HOME\bin;D:\firebase-emulator-tools\node-v24.18.1-win-x64;$env:Path"
```

- **Driving the app end to end**, in the order that works on this host:
  1. `flutter build apk --debug --no-pub --target-platform android-x64
     --dart-define=USE_FIREBASE_EMULATORS=true`, and let Gradle exit.
  2. Start the Android emulator: `ANDROID_AVD_HOME=D:\android-avds`,
     `D:\android-emulator-sdk\emulator\emulator.exe -avd chilltent_api35
     -no-snapshot-save -no-boot-anim -gpu swiftshader_indirect -memory 1536`.
  3. Wait on `adb shell getprop sys.boot_completed`, then
     `adb shell settings put secure stylus_handwriting_enabled 0` or the first
     text entry is stolen.
  4. `npm --prefix rules-tests run emulators:dev` with
     `JAVA_TOOL_OPTIONS=-Xmx512m` so the Firestore JVM fits beside it.
  5. `adb install -r -t`, then `adb shell pm clear` before signing in if the Auth
     emulator has been restarted - its UIDs do not survive.
- Use Flutter's own `adb` at
  `C:\Users\BonifaceMasota\develop\android-sdk\platform-tools\adb.exe`; the one
  first on `PATH` is a different binary and the two servers fight.
- Do not run Gradle and either emulator at the same time on this host.
- After killing an emulator run, delete `functions/.secret.local` and
  `functions/.env.local` **and** clear anything still listening on 9099, 8080,
  5001, 4000, and 9150.
- `npm --prefix rules-tests run plant:late-sale` needs
  `FIRESTORE_EMULATOR_HOST` and `FIREBASE_AUTH_EMULATOR_HOST` in the shell, and
  a closed shift with at least one sale to clone.
- A `FieldValue.delete()` sentinel is an ordinary object until the write is
  serialized. No pure test can catch one in the wrong write kind; only a real
  Firestore or an explicit `isEqual(FieldValue.delete())` assertion can.

---

## The sentinel audit, and a guard that keeps it done - 2026-08-04

### Completed in this session

The chunk above: **audit every other `FieldValue.delete()` for defect 1's
shape.** All 129 sites were enumerated and classified, one fragile payload was
split, and the class is now closed by a test rather than by this paragraph.

**No second live instance of the defect existed.** That is the finding, and it is
worth stating plainly because the audit's value is not the bug it did not find -
it is that the class can no longer come back silently.

### What the audit actually found

Classified by the write each sentinel reaches:

| Verdict | Count | Meaning |
| --- | --- | --- |
| inside `update(...)` | 108 | always legal |
| inside `set(..., {merge: true})` | 7 | legal; every options argument read and confirmed |
| built away from its write | 13 | resolved by hand, below |
| inside `create(...)` or `set(...)` without a merge | **0** | the defect; none remained |

The 13 that are not lexically inside their write are the only ones that could
hide anything, because their legality depends on code elsewhere. They belong to
four payload builders:

- `jobs.ts#saleTriggerJobFields` (2) - the split fixed last session.
- `jobs.ts#advanceReconciliationJob` (5) - one `update` object handed to
  `transaction.update`; no create branch exists.
- `membershipMirrorStore.ts#progressData` (5) - **all eleven** call sites are
  `update(...)`, and a repair run document is created by `initialRunData`, which
  carries no sentinel.
- `membershipMirrorStore.ts#mirrorWriteData` (1) - **the one real hazard.**

`mirrorWriteData` was a single payload shared between `batch.update` and
`batch.create`, which is defect 1 exactly. It was not broken: its sentinel sat
behind `mirrorSnapshot.exists`, and the create branch runs only when
`!mirrorSnapshot.exists`, so the two conditions happened to agree. **Safety by
two `exists` reads agreeing in two places is not safety**, and nothing recorded
that they had to. It is now `mirrorWriteFields`, returning a tagged
`{kind, data}` pair built by two separate functions, so the create payload cannot
express a sentinel at all - the same structural remedy `saleTriggerJobFields`
got. The refactor is behaviour-preserving; the diff was checked case by case
against the four combinations of `exists` and `membershipStatus`, and the
redundant `{invitationStatus: decision.value.invitationStatus}` branch it
dropped was a re-set of a key the spread above it already supplied.

The three files whose `create` payloads spread a variable from a sentinel-bearing
file - `globalStatusStore.ts:216`, `revokePlatformAdmin.ts:240`,
`processors.ts:190`/`206` - were checked too. Each spreads a parsed input or a
computed metric, never a payload builder, so no sentinel can arrive that way.

### The guard, and why it needed two assertions

`functions/src/testing/sentinelAudit.ts` reads the source and classifies every
sentinel by bracket matching. Its test asserts two things, and the second is the
one that matters:

1. No sentinel sits inside a `create(...)` or an unmerged `set(...)`.
2. Every sentinel **built away from its write** belongs to one of four reviewed
   builders, each recorded with the reason it is safe.

Verified by putting a sentinel back into `mirrorCreateData`: **assertion 1 still
passed** and assertion 2 failed. A payload built away from its write is precisely
what defect 1 was, so the flat "reaches a rejecting write" check would never have
caught it. Assertion 2 fails whenever a new payload builder appears, which forces
somebody to go and look at where it is written. Three targeted mirror tests
failed at the same time, so the reintroduction is caught four ways.

Safety decisions in the scanner worth keeping:

- It blanks comments and string literals **preserving every offset** before
  matching. `FieldValue.delete()` is named in the doc comments of the very
  functions under audit, including the one whose defect started this, so a naive
  scan reports its own documentation.
- It skips `*.test.ts` and its own `testing/` directory, so every site it reports
  is one a deployed function can really write - otherwise the reviewed list
  becomes a list of test helpers.
- `owner` is the enclosing declaration name, not a line number, so the reviewed
  list survives any edit above it.
- A third test asserts the audit still reaches >100 sites in >10 files. A scanner
  that quietly read nothing would satisfy both real assertions perfectly.

`deleteSentinelPaths` in `functions/src/testing/writeSentinels.ts` is the shared
`isEqual` walk the handover asked for; `jobs.test.ts` now imports it instead of
carrying its own copy. It reports dotted paths rather than a boolean, and refuses
to walk into `Timestamp` or `DocumentReference` - the latter holds a live
`Firestore`, so a naive recursion is unbounded.

### Files in this chunk

```text
PLAN.md
functions/src/reconciliation/jobs.test.ts
functions/src/repair/membershipMirrorStore.ts
functions/src/repair/membershipMirrorStore.test.ts
functions/src/testing/sentinelAudit.ts            (new)
functions/src/testing/sentinelAudit.test.ts       (new)
functions/src/testing/writeSentinels.ts           (new)
```

No Dart, Rules, or index changes. Nothing about this chunk needed a device.

### Validation evidence after implementation code was frozen

| Command | Result |
| --- | --- |
| `npm --prefix functions test` | **206/206**, up from 190, adding **16** tests |
| `npm --prefix rules-tests run test:emulator` | **139/139**, unchanged |
| `FUNCTIONS_DISCOVERY_TIMEOUT=60000 npm --prefix rules-tests run test:emulator:invitations` | **12/12** real Auth, Firestore, and Functions emulator tests |
| `git diff --check` | clean |

The 16 new tests are 9 mirror payload cases and 7 audit cases. Dart was not
re-run because no Dart file changed. The Rules suite was re-run because
`functions/src` did, and the invitation runner because the membership mirror
repair path it exercises is the code that changed. Android build and Android
emulator validation were skipped as requested.

### Meaningful failures and their resolutions

- **The scanner called seven legal `set(..., {merge: true})` sites illegal.**
  `verdictForWrite` read the call frame's `close` offset, but a sentinel is
  reached *before* its call's closing paren, so `close` was always `undefined`
  and the options argument was parsed out of the entire rest of the file. It now
  matches the paren on demand. This is the whole reason the classifier is tested
  against synthetic source: the repo-wide assertion passed throughout, because
  those seven were being over-reported rather than missed.
- **The owner scan ate two names.** `progressData`'s own parameter type is an
  object literal, so the brace that should have opened its body had already been
  consumed; and `advanceReconciliationJob` declares `const update = {...}` several
  statements before the sentinel, which then mislabelled the next block that
  opened one. Fixed by pushing an anonymous scope for any brace opened while an
  argument or parameter list is still open, and by discarding a pending name at a
  top-level `;`. Both mistakes are now pinned by a test named after them.
- **A `Select-Object -First` in the pipeline made `npm` exit 255** on the Rules
  run and looked exactly like a suite failure. Truncating a pipe kills the
  producer. Redirect to a file, then filter the file.
- No assertion in the shipped code failed.

### The existing user-owned local edits remain separate and were never staged

```text
.vscode/settings.json
android/gradle.properties
pubspec.lock
.codex-app.png        (untracked)
.codex-live.png       (untracked)
.codex-live2.png      (untracked)
```

### Next bounded chunk

**A second integration runner: the sale trigger and reconciliation.** This is the
harness gap defect 1 exposed, and it is now the only preference-ordered item left
that no test covers. `run-invitation-emulator-tests.js` is the only
Auth/Firestore/Functions harness in the repository, and one test that writes a
sale and asserts a `reconciliation_dirty_days` document appears would have caught
defect 1 in seconds instead of after eleven sessions.

1. Model the runner on `scripts/run-invitation-emulator-tests.js`, including the
   `FUNCTIONS_DISCOVERY_TIMEOUT` allowance and the local `.env.local` /
   `.secret.local` handling that `run-dev-emulators.js` already gets right.
2. Assert what the pure tests cannot: a sale write produces a
   `reconciliation_dirty_days` entry **and** a `reconciliation_jobs` document, and
   the second sale in the same five-minute bucket takes the *update* branch
   without throwing. Both branches of `saleTriggerJobFields` in one run.
3. Drive one job to completion so a `daily_metrics` document is regenerated from
   sale activity - the thing that was silently never happening.
4. Keep it to the trigger and the job lifecycle. The nightly pub/sub schedule the
   emulator does not run stays out.

Then, in preference order:

- **The `shift_amendments` read surface**, still untouched: written, its Rules
  boundary committed and tested, readable by owner/admin/manager, listed nowhere.
  Model it on `TenantStockAdjustmentRepository` and refuse a record that cannot
  explain its own correction.
- The evidence-panel rendering inconsistency and the "1 transactions" plural.

Leave outside all of them: any resolution path for the four stock and sale
differences, currency labels on the differences list, the subscription surfaces
(examined and declined earlier in this file - start on the server, not in
Flutter), receipt printing, the printed receipt body, discounts, camera barcode
scanning, password reset (still blocked on the App Check decision recorded near
the top of this file), product cost/profit fields, a `platform_audit_logs`
surface, branding surfaces, the Sentry DSN, and deployment.

### Practical notes carried forward

- Everything in the previous session's list still applies, in particular the
  emulator prelude and the two local config files.
- The sentinel audit is `npm --prefix functions test`; it needs no emulator. To
  see the classification rather than the pass/fail, call
  `auditDeleteSentinels()` from `lib/testing/sentinelAudit.js`.
- Do not filter a long `npm` run through `Select-Object -First`. Redirect with
  `*>` to a file and filter that, or the exit code is meaningless.

---

## The harness that would have caught it - 2026-08-04

### Completed in this session

The first preference-ordered item of the chunk above: **a second integration
runner for the sale trigger and reconciliation.** It exists because defect 1 was
found by using the app rather than by any test, and the gap was structural - the
invitation suite was the only Auth/Firestore/Functions harness in the repository,
and reconciliation had no representation in it at all.

**The new suite reproduces defect 1 exactly.** Putting the two sentinels back into
`saleTriggerJobFields.create` fails all five tests, and the Functions emulator log
carries the original error verbatim:

```text
Error: Value for argument "data" is not a valid Firestore document.
FieldValue.delete() must appear at the top-level and can only be used in
update() or set() with {merge:true} (found in field "productCursor").
```

That is the point of the chunk. No production code changed.

### What the suite asserts

Five tests, in one emulator run, against real Auth, Firestore, and Functions:

1. **A sale creates the dirty day and the bucket job.** The regression: before the
   fix not one of the four documents existed. Asserts the receipt, the dirty day's
   trigger-owned counters, the job's identity, and the trigger-owned stock
   movement with its deterministic ID.
2. **The job a sale enqueues regenerates the day's metric.** The consequence the
   defect actually had, asserted directly - `daily_metrics` for the business date,
   with the sale's own figures, plus the dirty day turning `clean` and the shift
   expectation the verifier will later need. **No daily metric had ever been
   regenerated from sale activity on this project**, and nothing else would have
   done it: the nightly sweep is a pub/sub schedule the emulator does not run.
3. **A second sale in the same bucket clears the cursor the last pass left.** The
   `update` half of `saleTriggerJobFields`, where a sentinel is correct, proved by
   planting a cursor and watching it go.
4. **A replayed sale is registered once.** The trigger is `retry: true`, so the
   receipt document is the idempotency record.
5. **A sale with an unusable line is an anomaly, not a dropped sale.** The good
   line still moves stock.

### The races that had to be designed out, which is the real finding

**The task queue is emulated.** `runTenantReconciliationTask` really is dispatched
by `emulators:exec`, so writing a sale starts the whole job pipeline and it runs
while the test is still asserting. The first draft of this suite passed on the
first attempt **by luck**: it asserted `status == "queued"`, `revision == 0`, and
`attemptCount == 0` on a job that a worker was already claiming. Reading the
emulator log to find out whether tasks dispatched at all is what exposed it.

The rules the suite now follows, and the reason each holds:

- **Assert only trigger-owned fields.** A dirty day's `revision`,
  `saleReceiptCount`, `lastSaleId`, and `invalidLineCount` are written by
  `registerSaleReceipt` and by nothing else. Its `status` is not - the metrics
  phase sets it `clean` - so `status` is asserted only after waiting for the
  metric that changes it.
- **Assert only the job's immutable identity.** `source`, `sourceKey`, `mode`,
  `localDate`, `requestedBy`, `authority`, `mutatesStock`, `checkpointKind`, and
  `checkpointKey` are written identically by both branches and rewritten by no
  processor. `status`, `generation`, `revision`, and `attemptCount` are all live.
- **Make the update branch deterministic by hand.** The job is put into
  `completed` with a planted cursor before the second sale, so `mergeDirtyJob`
  returns `queued` - and therefore the sentinel-bearing payload - regardless of
  what the pipeline was doing. Waiting for a real pass instead would make a
  one-field assertion depend on the entire task chain.
- **The cleared cursor is safe to assert as absent**, because a `sale_trigger` job
  goes metrics then shifts and never enters the stock phase, so nothing
  downstream can put a cursor back. That is a property of `handlers.ts`, not an
  accident.
- **Wait out a nearly-finished five-minute bucket.** Both sales must share a
  bucket or the second takes the create branch again and proves nothing. The
  bucket comes from wall-clock time, so the test waits when fewer than 60 seconds
  remain.
- **One tenant per test.** The counters are per business, and a shared tenant
  would make every `saleReceiptCount` assertion depend on execution order.

Timings, consistent across two consecutive runs: the first receipt takes ~12-13s
(trigger cold start), the daily metric ~16s, and every later receipt ~300ms. The
timeouts are 30s and 90s, so roughly 2x and 5x headroom on this host.

### Harness decisions

- **Its own project, ports, and Functions codebase**, so it cannot collide with
  the invitation suite or a developer's `emulators:dev`: project
  `demo-multitenant-reconciliation-integration`, ports 9299/8280/5201, codebase
  `reconciliation-integration`.
- **The fixture exports two functions**, `mergeSaleReconciliationJob` and
  `runTenantReconciliationTask`. Exporting the whole index would pull in every
  `defineSecret`/`defineString` parameter, and each one without a default makes
  the emulator stop and wait for an answer that never comes - a run that looks
  like a hang after "Serving at port ...". The reconciliation dependency closure
  was checked and reaches none of the four parameter-bearing modules, which is why
  this harness needs **no** `.secret.local` or `.env.local` at all. A killed run
  therefore leaves nothing behind to clean up, unlike `emulators:dev`.
- **The fixture has no `node_modules` of its own**, unlike `functions/integration`.
  Node resolution walks up to `functions/node_modules`, which is the same install
  the copied `lib/` was compiled against - the version this suite ought to be
  exercising. Recorded because it is a real dependency on the parent install.

### Files in this chunk

```text
PLAN.md
firebase.reconciliation-test.json                          (new)
functions/reconciliation-integration/.gitignore            (new)
functions/reconciliation-integration/index.js              (new)
functions/reconciliation-integration/package.json          (new)
rules-tests/package.json
rules-tests/scripts/run-reconciliation-emulator-tests.js   (new)
rules-tests/test/sale-reconciliation.integration.test.js   (new)
```

No Dart, Rules, index, or `functions/src` change. Nothing needed a device.

### Validation evidence after implementation code was frozen

| Command | Result |
| --- | --- |
| `npm --prefix rules-tests run test:emulator:reconciliation` | **5/5** real Auth, Firestore, and Functions emulator tests, run twice with identical results |
| the same, with defect 1 reintroduced | **0/5**, with the original Firestore error in the Functions log |
| `npm --prefix functions test` | **206/206**, unchanged |
| `git diff --check` | clean |

The Dart, Rules, and invitation suites were not re-run: no Dart file, no rule, and
no `functions/src` file changed in this chunk. Android build and Android emulator
validation were skipped as requested.

### Meaningful failures and their resolutions

- **The suite passed while containing three races**, described above. Diagnosed by
  grepping the emulator log for task-queue activity rather than by a failure,
  which is the only reason it was caught at all. A green integration test whose
  assertions touch pipeline-owned state is not evidence.
- **The Write tool put two literal control bytes in the runner** where a
  `[\u0000-\u001f]` character class was intended, which made the file a binary as
  far as git and grep were concerned. Replaced with `/[^ -~]/` - printable ASCII
  only - which expresses the same guard with no escapes to mangle, and is the
  right test anyway for a string spliced into a command line.
- No assertion in the shipped suite failed.

### The existing user-owned local edits remain separate and were never staged

```text
.vscode/settings.json
android/gradle.properties
pubspec.lock
.codex-app.png        (untracked)
.codex-live.png       (untracked)
.codex-live2.png      (untracked)
```

### Next bounded chunk

**The `shift_amendments` read surface.** Written by `amendShiftSummary`, its Rules
boundary committed and tested by `rules-tests/test/shift-amendments.test.js`,
readable by the owner/admin/manager set - and listed nowhere. The correction trail
is invisible to the people allowed to see it.

1. A read model that refuses a record which cannot explain its own correction -
   the same rule the differences read model applies. An amendment names what it
   changed from, what to, whether it touched counted cash, and why.
2. A repository modelled on `TenantStockAdjustmentRepository`: a bounded
   business-wide page, and a page narrowed by one `shiftId ==` equality. Both were
   already proved servable without a composite index by the Rules suite.
3. A surface that lists them, beside the differences list the corrections come
   from.

Then, in preference order:

- The evidence-panel rendering inconsistency and the "1 transactions" plural, both
  observed during the real run two handovers ago.
- Extending the new reconciliation runner to the shift-verification phase, which
  is the half of the pipeline these five tests stop short of.

Leave outside all of them: any resolution path for the four stock and sale
differences, currency labels on the differences list, the subscription surfaces
(examined and declined earlier in this file - start on the server, not in
Flutter), receipt printing, the printed receipt body, discounts, camera barcode
scanning, password reset (still blocked on the App Check decision recorded near
the top of this file), product cost/profit fields, a `platform_audit_logs`
surface, branding surfaces, the Sentry DSN, and deployment.

### Practical notes carried forward

- `npm --prefix rules-tests run test:emulator:reconciliation` needs the emulator
  prelude and takes about 45 seconds. `JAVA_TOOL_OPTIONS=-Xmx512m` is what lets it
  start on this host.
- It uses fixed tenant IDs and does not import or export emulator data, so every
  run starts empty. If a persisted emulator is ever pointed at it, the counter
  assertions will fail for that reason and not a real one.
- `INTEGRATION_TEST_NAME_PATTERN` narrows it to one test, exactly as the
  invitation runner does.

---

## The corrections a business can finally see - 2026-08-04

### Completed in this session

The chunk above: **the `shift_amendments` read surface.** It was written by
`amendShiftSummary`, its Rules boundary was committed and tested, it was readable
by owner, admin, and manager - and it was listed nowhere. A correction that
rewrites a closed shift and then cannot be seen is not answerable, and the
differences list makes it worse: **a resolved difference is deleted from that
list**, so until now a correction left no visible trace anywhere in the app.

No server code changed. No rule changed. This is a read surface over a collection
that was already there.

### The read model, and what it refuses

`TenantShiftAmendmentRecord` decodes strictly, on the same principle the stock
correction feed and the differences list already hold: a row that misstates a
correction is worse than no row. Three refusals are worth recording as decisions
rather than validation:

- **`mutatesCountedCash` must be exactly `false`.** This is the one property that
  makes the whole collection safe to show, and the entire amendment path was built
  around never touching a drawer count. A record claiming otherwise is either a
  server that changed its guarantee without this client knowing, or a document no
  server wrote. Neither may be presented beside truthful corrections, so the page
  fails closed. `true`, `null`, `'false'`, `0`, and an absent field are all
  refused.
- **The transaction identity is exact and is asserted.**
  `transactionVariance == previousTransactionCount - transactionCount`, because
  those are whole counts from a single comparison. A record that breaks it did not
  come from `amendShiftSummary`.
- **The money identity is asserted only when the record says it applies.** The
  recorded variance is measured from the **major-unit** total the verifier
  compares, which may legitimately differ from the shift's stored minor units.
  When it does, the amendment records that through
  `previousRepresentationsAgreed: false` and overwrites both. So the identity is
  held only when that flag is `true`. Asserting it unconditionally would refuse
  exactly the internally inconsistent shifts this correction exists to repair -
  and those are the ones nothing else in the app reports at all.

That last one is a check the amendment *callable* cannot make: its response
carries no `previousRepresentationsAgreed`, so the stored record can be verified
more strictly than the answer that created it.

`sourceType` is carried verbatim rather than required to be
`reconciliation_shift_variance`, so a server that starts recording another kind of
correction here is named honestly instead of taking the trail down. An absent
`createdAt` or `requestId` is accepted: the correction happened, and hiding a
rewrite of a closed shift because its clock reading is missing is the worse
outcome.

### The repository and the surface

`TenantShiftAmendmentFeedRepository` is modelled on
`TenantStockAdjustmentFeedRepository`: a bounded business-wide page and a page
narrowed by one `shiftId ==` equality, both on ascending document-ID order, both
servable by Firestore's automatic single-field index and needing no composite
index. `rules-tests/test/shift-amendments.test.js` already proves both shapes,
which is why this needed no new Rules work.

- **Its role set is `owner`, `admin`, `manager` - deliberately wider than the
  owner-and-administrator set that may *make* a correction.** Rewriting a record
  every client treats as terminal is governance; seeing that it was rewritten, and
  why, is operational information a manager answering for that shift needs. The
  read and write surfaces disagreeing here is the design, and both a repository
  test and a widget test pin it.
- The page is **not** presented as chronological. An amendment ID is a digest of
  the actor, the operation, the business, and the request, so document order
  carries no time information; each record states its own instant.
- **The surface resolves no staff names.** `tenantStaffLabel` degrades to the bare
  UID, so the actor reads as "You" for the person who made the correction and as a
  UID otherwise. That keeps the correction trail readable when the staff directory
  is not, and costs no second read. Every other record in the business attributes
  its actor by UID for the same reason.
- The panel writes nothing and cannot: `shift_amendments` is `allow write: if
  false` for every client.

What a row says is derived from what actually moved. A correction may change the
money, the transaction count, or both, so the sentence names only the figures that
changed - and for a shift whose two money representations disagreed, it says the
totals were rewritten without either figure changing, which is the truth in that
case. The transaction count is singularised.

The entry point is on the differences list, beside the correction that produces
these records. It needs no injected capability, unlike the correction itself:
it is a read of the same business through the same reader, so there is nothing for
a composition root to grant or withhold.

### Files in this chunk

```text
PLAN.md
lib/reporting/reconciliation_anomalies_panel.dart
lib/reporting/reporting.dart
lib/reporting/shift_amendment_feed.dart               (new)
lib/reporting/shift_amendment_feed_panel.dart         (new)
lib/tenancy/tenant_paths.dart
test/reporting/shift_amendment_feed_test.dart         (new)
test/reporting/shift_amendment_feed_panel_test.dart   (new)
test/tenancy/tenant_paths_test.dart
```

No `functions/src`, Rules, or index change. Nothing needed a device or an
emulator.

### Validation evidence after implementation code was frozen

| Command | Result |
| --- | --- |
| `flutter analyze --no-pub lib/reporting lib/tenancy test/reporting test/tenancy` | no issues |
| `flutter test --no-pub --concurrency=1 --reporter=failures-only test/audit test/dev test/inventory test/returns test/reporting test/sales test/shift test/checkout test/tenancy test/theme_test.dart` | **1166/1166**, up from 1131, adding **35** tests |
| `git diff --check` | clean |

The 35 new tests are 20 read-model and repository cases and 15 widget cases. The
Functions, Rules, and both integration suites were not re-run: no `functions/src`
file, no rule, and no emulator fixture changed in this chunk. Android build and
Android emulator validation were skipped as requested.

A repo-wide `flutter analyze --no-pub lib test` reports **477 pre-existing
issues**, all in files outside every chunk in this file - `thermal_printer_service`,
`glass_card`, `pill_input`, `theme.dart`, and a `test/widget_test.dart` that
references a `MyApp` class which no longer exists. Analysing the in-scope paths is
the precedent every handover here has followed; the repo-wide figure is recorded so
nobody mistakes it for something this work introduced.

### Meaningful failures and their resolutions

- **The path contract's exhaustiveness guard failed first, as designed.**
  `tenant_paths_test.dart` asserts `TenantPaths.businessCollections` matches an
  explicit map, so adding `shiftAmendments` to the enum without adding it there
  fails - which is what forced the collection to be documented in both places.
- **The Write tool put a literal NUL byte in the read-model test** where the
  "reason contains a control character" case needed `\u0000`, which silently made
  that case pass a perfectly valid string. Fixed by rewriting it as the Dart
  escape. This is the same tool behaviour that mangled the reconciliation runner
  earlier in this session; the lesson is to check for control bytes after writing
  any file containing an escape in that range.
- Adding a required `onOpenAmendments` to the differences panel's private contents
  widget broke nothing: the existing panel tests build the public widget, so the
  599 reporting and tenancy tests passed unchanged.
- No assertion in the shipped code failed.

### The existing user-owned local edits remain separate and were never staged

```text
.vscode/settings.json
android/gradle.properties
pubspec.lock
.codex-app.png        (untracked)
.codex-live.png       (untracked)
.codex-live2.png      (untracked)
```

### Next bounded chunk

**The two defects the real run observed and left alone**, both recorded two
handovers above and neither yet chased:

1. **"1 transactions".** The shift panel does not singularise its transaction
   count. The differences panel and the new corrections trail both do, so this is
   an inconsistency with the surfaces beside it as much as a wording bug. Find
   every count in the shift surfaces that is rendered without a plural rule, not
   only the one that was seen.
2. **The evidence panel renders inconsistently.** Under "Checkouts stored on this
   device" it sometimes lists all five states with their counts and sometimes only
   "Saved offline: 0" with at least one record present. Reproducible across two
   screenshots each way and **not diagnosed**, so start by reproducing it in a
   widget test rather than by reading the panel: a rendering that differs between
   two builds of the same state is a state question, not a layout one.

Then, in preference order:

- Extending the reconciliation runner to the shift-verification phase, which is
  the half of the pipeline its five tests stop short of - and the half that
  produces the differences the new trail records corrections to.
- A `shiftId`-narrowed entry point into the corrections trail from shift history,
  which the repository already supports and which nothing yet opens.

Leave outside all of them: any resolution path for the four stock and sale
differences, currency labels on the differences list or the corrections trail, the
subscription surfaces (examined and declined earlier in this file - start on the
server, not in Flutter), receipt printing, the printed receipt body, discounts,
camera barcode scanning, password reset (still blocked on the App Check decision
recorded near the top of this file), product cost/profit fields, a
`platform_audit_logs` surface, branding surfaces, the Sentry DSN, the 477
pre-existing analyzer issues in the legacy files named above, and deployment.

### Practical notes carried forward

- Everything in the previous two sessions' lists still applies.
- `flutter analyze --no-pub lib test` is not a useful signal on this repository.
  Analyse the paths a chunk touched.
- After writing any file whose content includes a `\u00xx` escape, check it for
  literal control bytes before trusting it. Two files in this session needed
  repairing for exactly that.

---

## The two defects the real run left alone - 2026-08-04

### Completed in this session

The chunk above: **the "1 transactions" plural and the evidence panel's
inconsistent rendering**, both observed during the first real run three handovers
above and neither chased at the time.

One of them turned out to be a different defect from the one reported, and saying
so is the more useful outcome than a fix that matched the guess.

### The plural: eight sentences, not one

The reported symptom was one line in the shift panel. Searching for the class
rather than the instance found **eight** unpluralised counts across the shift and
reporting surfaces, several sitting beside counts that were already correct:

| Where | Was |
| --- | --- |
| `shift_panel` confirmed sales | `1 transactions, 1 minor units` |
| `shift_panel` expected cash | `1 minor units over 1 sale` |
| `shift_panel` unattributed tender | `worth 1 minor units. They are inside...` |
| `shift_history_panel` recorded sales | `over 1 transactions` |
| `daily_metrics_panel` daily sales | `over 1 transactions in 1 shift` |
| `daily_metrics_panel` cost data | `1 sale lines have no cost recorded` |
| `sales_totals_panel` category basis | `0 of the 1 sales read` |
| `sales_totals_panel` cost data | `1 sale lines have no cost` |

The daily summary line is the sharpest example: it pluralised `shiftCount`
correctly and `transactions` not at all, **in the same sentence**, so it could
produce both "12 transactions in 1 shift" and "1 transactions in 2 shifts".

Two decisions worth recording:

- **The agreement rule covers pronouns and verbs, not only nouns.** The
  unattributed-tender line now reads "It is inside the confirmed sales above" for
  one sale, matching what the unsettled-sales line beside it already did. That
  line was checked and is correct as written: `count == 1 ? 'sale names' :
  'sales name'` pairs a singular subject with "names" and a plural subject with
  "name", which reads wrong at a glance and is right.
- **"minor unit" was pluralised too**, even though the money presentation is
  part of the excluded currency work. Fixing "1 transaction" while leaving "1
  minor units" in the same sentence would have been worse than either.
- **Inline ternaries, not a helper.** The codebase already expresses this rule
  inline in a dozen places; a new shared helper would have made these eight sites
  the odd ones out.

**Every plural form is byte-identical to what it produced before**, which is why
the 979 existing shift, reporting, sales, checkout, and tenancy tests passed
unchanged after the edit. That is also the finding: **no test pinned any of these
sentences at a count of one.** Seven new tests do now.

### The evidence panel: the reported symptom was not the defect

The report was that the panel "sometimes lists all five states with their counts
and sometimes only `Saved offline: 0`, with at least one record present."

**There is no such state.** `_EvidenceContents` renders either the empty sentence
or all five lines as siblings of one `Column`; no input produces a subset. A test
now pins that, so an omission can never become the explanation. The most likely
reading of the screenshots is the landing screen's layout: the panel sits inside a
`Center` within a `SingleChildScrollView`, so tall content is cut off at both ends
and the lines below "Saved offline: 0" were simply below the fold. That is
recorded rather than changed - it is a deliberate look for a mostly-empty screen,
and the content is reachable by scrolling.

**But looking for it found a real defect beside it.** Every refresh signal changes
the loader's identity, which restarts `TenantRouteGuard` and puts it back into its
loading state - and that state was `SizedBox.shrink()`. So **the whole panel
vanished and reappeared on every signal**, and `CheckoutSyncPass` reports a change
more than once per sale, so a cashier watching for their sale saw the counts
flicker away repeatedly. That matches "sometimes lists all five states and
sometimes does not" at least as well as the layout does.

The fix keeps the last counts on screen while a fresh read is in flight, and says
they may be a moment old rather than leaving that to be inferred. Two safety
properties came with it:

- **The retained counts are dropped the instant the session key moves.** One
  business's local work shown under another business's name would be a worse
  defect than the blanking it replaces. Pinned by a test that switches business
  mid-read and asserts the previous counts disappear and nothing is shown until
  the new read answers.
- The cache is written by assigning a field inside the guard's builder, not by
  `setState`, so it adds no build cycle.

Confirmed by reverting the `loading` widget to `SizedBox.shrink()`: the refresh
test fails, the other ten pass.

### Files in this chunk

```text
PLAN.md
lib/checkout/checkout_evidence.dart
lib/reporting/daily_metrics_panel.dart
lib/reporting/sales_totals_panel.dart
lib/shift/shift_history_panel.dart
lib/shift/shift_panel.dart
test/checkout/checkout_evidence_test.dart
test/reporting/daily_metrics_panel_test.dart
test/reporting/sales_totals_panel_test.dart
test/shift/shift_history_panel_test.dart
test/shift/shift_panel_test.dart
```

No `functions/src`, Rules, or index change. Nothing needed a device or emulator.

### Validation evidence after implementation code was frozen

| Command | Result |
| --- | --- |
| `flutter analyze --no-pub lib/checkout lib/shift lib/reporting test/checkout test/shift test/reporting` | no issues |
| `flutter test --no-pub --concurrency=1 --reporter=failures-only test/audit test/dev test/inventory test/returns test/reporting test/sales test/shift test/checkout test/tenancy test/theme_test.dart` | **1175/1175**, up from 1166, adding **9** tests |
| the same with the evidence panel's `loading` reverted to `SizedBox.shrink()` | the refresh test fails, as it must |
| `git diff --check` | clean |

The 9 new tests are 3 evidence-panel cases and 6 singular-count cases. Android
build and Android emulator validation were skipped as requested.

### Cross-chunk validation for all four chunks in this session

Run once at the end, after every chunk was committed, so the four are known to
hold together and not only one at a time:

| Command | Result |
| --- | --- |
| `flutter test --no-pub --concurrency=1` over the 10 in-scope test paths | **1175/1175** |
| `npm --prefix functions test` | **206/206** |
| `npm --prefix rules-tests run test:emulator` | **139/139** |
| `FUNCTIONS_DISCOVERY_TIMEOUT=60000 npm --prefix rules-tests run test:emulator:invitations` | **12/12** |
| `npm --prefix rules-tests run test:emulator:reconciliation` | **5/5** |

Session totals: **1537 tests** across five suites, up from 1476 at the start of
the session, adding **61**. Nothing was left failing and no suite was skipped
except the Android build and Android emulator runs.

One practical note from that sequence: **the invitation suite alone takes about
nine minutes**, so running it and the reconciliation suite in one shell exceeds a
ten-minute command budget. Run them separately. A run killed that way left no
`.secret.local`, no `.env.local`, and no listening emulator port behind, which is
the first thing to check before starting another.

### Meaningful failures and their resolutions

- **A deferred-source widget test needs two pumps after completing a future**,
  not one: the first lets the guard's `await` resume, the second renders the
  frame. Both new evidence tests failed on the first assertion until that was
  understood.
- **`_controller(TenantRole.owner)` throws in the shift-history test.** Its
  `_membership` helper hard-codes `isOwner: false`, and a session refuses an
  `owner` role that is not the canonical owner. `TenantRole.manager` is the role
  that surface's management scope is tested with; the new test uses it.
- **`_response(overrides: ...)` in the sales-totals test reaches only the inner
  `previous` map**, so `scannedTransactions` silently kept its default and the
  assertion measured the wrong sentence. It is now an explicit parameter, with a
  comment saying why it is not an override.
- No assertion in the shipped code failed.

### The existing user-owned local edits remain separate and were never staged

```text
.vscode/settings.json
android/gradle.properties
pubspec.lock
.codex-app.png        (untracked)
.codex-live.png       (untracked)
.codex-live2.png      (untracked)
```

### Next bounded chunk

**Extend the reconciliation integration runner to the shift-verification phase.**
Its five tests stop after the metrics phase, and the shifts phase is the half that
produces the `shift_variance` differences the corrections trail now records
corrections to. The whole chain - sale, dirty day, job, metric, shift
expectation, verification, difference, correction - would then be proved end to
end by tests rather than by one manual run.

1. `processShiftPage` needs a real closed `shifts` document to verify an
   expectation against; the current fixture seeds only a tenant and a product, so
   the shift the sale names does not exist. Seed one whose summary is
   deliberately wrong, exactly as the manual run did by hand.
2. Assert a `reconciliation_anomalies` record of kind `shift_variance` appears
   with the figures the shift and its sales actually differ by.
3. Then call `amendShiftSummary` against it and assert the `shift_amendments`
   record, the rewritten shift, the settled expectation, and the removed
   difference - the four writes the correction makes in one transaction.
4. This needs a third export in the fixture (`amendShiftSummary`) and a check
   that its dependency closure still reaches no `defineSecret` parameter.

Then, in preference order:

- **A `shiftId`-narrowed entry point into the corrections trail from shift
  history.** The repository already supports it and nothing opens it, so a
  manager looking at one corrected shift cannot see its correction from there.
- **The landing screen's `Center` inside `SingleChildScrollView`**, if the
  evidence panel's cut-off is judged worth changing. It is a look-and-feel
  decision about the whole safe landing route, not a defect in the panel, so it
  wants a deliberate answer rather than a quiet edit.

Leave outside all of them: any resolution path for the four stock and sale
differences, currency labels anywhere, the subscription surfaces (examined and
declined earlier in this file - start on the server, not in Flutter), receipt
printing, the printed receipt body, discounts, camera barcode scanning, password
reset (still blocked on the App Check decision recorded near the top of this
file), product cost/profit fields, a `platform_audit_logs` surface, branding
surfaces, the Sentry DSN, the 477 pre-existing analyzer issues in the legacy
files, and deployment.

### Practical notes carried forward

- Everything in the previous three sessions' lists still applies.
- A plural fix that changes no plural form breaks no existing test, which means a
  green suite is no evidence the singular form was ever correct. Assert the count
  of one.
- `TenantRouteGuard`'s `loading` widget replaces the whole subtree. Any panel that
  re-reads on a signal blanks unless it passes its last value as that widget.

---

## The shift half of the pipeline, proved end to end - 2026-08-04

### Completed in this session

The chunk above: **the reconciliation integration runner now carries a real sale
through the shift-verification phase and out the other side through
`amendShiftSummary`.** Its five tests stopped after the metrics phase; there are
now seven, and the whole chain - sale, dirty day, job, metric, shift
expectation, verification, difference, correction - is proved by tests rather
than by the one manual run recorded four handovers above.

No production code changed. The two new tests exercise code that was already
shipped and already unit-tested; what they add is the first evidence that it
does what the pure tests say when a real Firestore, a real task queue, and a
real callable are involved. That is the same gap that let
`mergeSaleReconciliationJob` throw on every sale for eleven sessions.

### What the shifts phase had never actually done in this harness

The fixture seeded a tenant and a product and no `shifts` document at all. Every
run therefore *did* reach the shifts phase - and found the shift its own
expectation named missing, recorded `invalid_or_missing_shift`, and moved on
without a single assertion noticing. **The variance path had never run against a
real server**, which is the reason this chunk existed.

The seeded shift records 0.00 over 0 transactions: the state a shift is left in
when it closes before the sale filed against it reaches the server, which is
what `scripts/plant-late-sale.js` engineers by hand. Both recorded figures are
then wrong, so the verifier's two comparisons, the two figures it records, and
the amendment's two rewrites are each individually observable. A fixture that
got one of them right by accident would have proved half as much.

Decisions worth recording:

- **The anomaly is found by querying `shiftId`, not by recomputing its digest.**
  The verifier and the amendment callable derive `shiftAnomalyId` in two
  different modules from the same shift and generation. A test that recomputed
  the digest would agree with whichever one it copied; a test that queries by
  field and then asserts `clearedAnomalyId` equals the ID it found proves the
  two modules agree with *each other*. If they ever stopped agreeing, the listed
  difference would survive its own correction and that assertion fails.
- **The counted cash is asserted unchanged.** `closingCashMinor` is a physical
  count of a drawer and the single property that makes this path safe to expose
  is that it can never rewrite one. The fixture uses 12000 minor units so a test
  would notice it moving.
- **The job's completion is waited for, not sampled.** The file's existing rule
  is that anything the pipeline is still writing must not be asserted; the new
  test extends that rule rather than bending it, by waiting until the job is
  `completed` - after which nothing rewrites its counters - and only then
  asserting `shiftsProcessed` and `shiftVarianceCount`.
- **Idempotency and non-repeatability are different properties, and both are
  asserted.** Replaying the same `requestId` returns the stored answer and leaves
  `summaryAmendmentCount` at 1. A *fresh* `requestId` is refused with
  `FAILED_PRECONDITION`, because settling the expectation as `amended` in the
  same transaction makes a second correction of that generation impossible
  rather than merely pointless.
- **The seeded actor is an `admin`, not an `owner`.** `amendShiftSummary` admits
  both, but an `owner` staff record must also be named by the tenant's
  `ownerUid`, and these fixtures are owned by a uid with no Auth account. The
  authorization path is otherwise identical.

### The fixture's third export, and the rule it had to satisfy

`functions/reconciliation-integration/index.js` now exports `amendShiftSummary`
beside the trigger and the task worker. Its require closure was checked first:
`core/authorization`, `core/idempotency`, `core/validation`,
`operations/domain`, `reconciliation/model` - and not one reaches
`firebase-functions/params`. That matters because a `defineSecret` or
`defineString` without a default makes the emulator stop at startup to ask for a
value, and with no terminal to answer it looks like a run that hangs forever
after `Serving at port ...`. The rule and how to check it are now written in the
fixture and in the README rather than being folklore.

### Files in this chunk

```text
PLAN.md
functions/reconciliation-integration/index.js
rules-tests/README.md
rules-tests/test/sale-reconciliation.integration.test.js
```

No `functions/src`, Rules, index, or Dart change. Nothing needed a device.

### Validation evidence after implementation code was frozen

| Command | Result |
| --- | --- |
| `flutter test --no-pub --concurrency=1 --reporter=failures-only` over the 10 in-scope test paths | **1175/1175**, unchanged - no Dart was touched |
| `npm --prefix functions test` | **206/206** |
| `npm --prefix rules-tests run test:emulator` | **139/139** |
| `npm --prefix rules-tests run test:emulator:reconciliation` | **7/7**, up from 5, adding **2** |
| `FUNCTIONS_DISCOVERY_TIMEOUT=60000 npm --prefix rules-tests run test:emulator:invitations` | **12/12** |
| `git diff --check` | clean |

Session totals: **1539 tests** across five suites, up from 1537. Android build
and Android emulator validation were skipped as requested. Each emulator command
was run in its own shell; the invitation suite alone takes about four minutes on
this host and the Rules suite about three, so they still do not belong in one
ten-minute command budget together.

During development the two new tests were run alone with
`INTEGRATION_TEST_NAME_PATTERN=shift`, which matches only their names.

### Meaningful failures and their resolutions

- **The first full run failed, and the failure was a real flake this chunk made
  more likely.** `TRIGGER_TIMEOUT_MILLISECONDS` was 30 seconds, and the *first*
  trigger delivery of a cold run is the only one that pays for the Functions
  emulator starting a Node worker: it was measured at 25.4 and 23.0 seconds on
  this host, while every later delivery in the same run appeared in about 310ms.
  Adding one more function to the fixture was enough to take the first test over
  the bound. Raised to 60 seconds with the measurement written down. The bound
  exists so a trigger that never runs fails with a description of what it was
  waiting for rather than hanging; it was never a performance assertion, and the
  diagnostic line still reports the time actually taken.
- **A callable error's `status` is `FAILED_PRECONDITION`, not
  `failed-precondition`.** The wire contract uppercases it, which the invitation
  suite already knew and this one had to learn.
- No assertion in the shipped code failed. Both new tests passed on their first
  focused run.

### The existing user-owned local edits remain separate and were never staged

```text
.vscode/settings.json
android/gradle.properties
pubspec.lock
.codex-app.png        (untracked)
.codex-live.png       (untracked)
.codex-live2.png      (untracked)
```

### Next bounded chunk

**A `shiftId`-narrowed entry point into the corrections trail from shift
history.** The repository already supports the narrowed read and nothing opens
it, so a manager looking at one corrected shift in history cannot see the
correction that was made to it - they can only find it by opening the whole
business's trail and reading down. The amendment now has server-side end-to-end
evidence; this is the surface that makes one shift's correction reachable from
the shift itself.

1. `shift_history_panel` already renders each closed shift with its recorded
   sales and counted cash. A shift that carries `summaryAmendmentId` is one that
   was corrected, and that field is on the document the panel already reads, so
   the entry point needs no extra query to decide whether to offer itself.
   Confirm that before designing around it - the history read model may drop the
   field, in which case widening it is part of the chunk.
2. Open the existing corrections trail narrowed to that `shiftId`, the way the
   differences panel opens the trail today.
3. Say plainly on the history row that this shift's summary was corrected, and
   how many times, before offering the link. A silent link is worse than none:
   the row's own figures are the amended ones, and nothing currently says so.
4. Cover the un-corrected row offering nothing, the corrected row offering the
   link, the count agreeing with `summaryAmendmentCount`, and the narrowed trail
   opening with the right `shiftId`.

Then, in preference order:

- **The landing screen's `Center` inside `SingleChildScrollView`**, if the
  evidence panel's cut-off is judged worth changing. It is a look-and-feel
  decision about the whole safe landing route, not a defect in the panel, so it
  wants a deliberate answer rather than a quiet edit.
- **The stock half of the reconciliation runner.** The integration suite now
  covers metrics and shifts; `processStockPage` and its checkpoint chain are the
  remaining phase, and it is the one that mutates nothing but is hardest to
  reason about from pure tests.

Leave outside all of them: any resolution path for the four stock and sale
differences, currency labels anywhere, the subscription surfaces (examined and
declined earlier in this file - start on the server, not in Flutter), receipt
printing, the printed receipt body, discounts, camera barcode scanning, password
reset (still blocked on the App Check decision recorded near the top of this
file), product cost/profit fields, a `platform_audit_logs` surface, branding
surfaces, the Sentry DSN, the 477 pre-existing analyzer issues in the legacy
files, and deployment.

### Practical notes carried forward

- Everything in the previous four sessions' lists still applies.
- A green integration suite is no evidence a phase did the work it was named
  for. This one reached the shifts phase on every run for as long as it existed
  and recorded `invalid_or_missing_shift` every time, because the fixture never
  seeded the document the phase compares against. Assert what the phase
  concluded, not that it ran.
- The first trigger delivery of a cold emulator run costs about 25 seconds on
  this host. Any new timeout in that harness has to be set from that, not from
  the ~310ms every later delivery takes.

---

## One shift's correction, reachable from the shift itself - 2026-08-05

### Completed in this session

The chunk above: **shift history now says on the row when a closed shift's
recorded sales were corrected, how many times, and when - and opens the
corrections trail narrowed to that one shift.**

Step 1 of that chunk said to confirm the field was on the document the panel
already reads before designing around it. It was on the document and **not in
the read model**, so widening `TenantShiftHistoryEntry` was part of the work
rather than a lookup.

### The row says it before it offers anything

The link was never the point. `amendShiftSummary` rewrites `totalSales`,
`totalSalesMinor`, and `transactionCount`, so **the "Recorded sales" figure on a
corrected row is the rewritten one** - and until this chunk nothing on that row,
or on the whole page, said so. A manager reading a corrected shift saw a figure
presented exactly like every uncorrected one beside it.

So the row now states the correction first, and the link is offered after it:

```text
The recorded sales above were corrected 2 times after this shift closed, to the
total its own sales prove. The counted cash was not changed. Last corrected
2026-07-31 19:00 UTC.
```

Decisions worth recording:

- **A cashier is told, and is not offered the trail.** The trail is
  owner/admin/manager by both `firestore.rules` and its repository, deliberately
  excluding the cashier whose shift it is. But the *shift document* is readable
  by that cashier and carries the correction fields, and the figures on their own
  row are the rewritten ones. Hiding the correction from the person accountable
  for the shift would have been worse than withholding the reason, so the
  sentence is shown to every role that can read the shift and a second sentence
  names the roles that may read the record of who asked and why. This is the same
  shape the differences list already uses for a manager who may read it but not
  act on it.
- **The counted cash is named in the sentence, not left to be inferred.** It is
  the figure a cashier is accountable for and the one thing the amendment path
  guarantees it never writes. "This shift was corrected" alone would leave a
  reader wondering whether their drawer count had been rewritten too.
- **The gate is the trail's own repository, not this surface's management set.**
  `TenantShiftAmendmentFeedRepository.canReadInSession` and
  `TenantShiftHistoryRepository.canReadEveryCashier` name the same three roles
  today. They mean different things, and the authority on who may read the trail
  is the trail.
- **The page header was corrected too.** It claimed figures were "shown exactly
  as they were closed", which a corrected row makes false. It now says they are
  shown as the server holds them, never recomputed here, and that a corrected
  shift says so on its own row.
- **No injected capability, no route builder.** `_openCorrections` sits beside
  `_openSales` and is built the same way: the trail is a read of the same
  business through the same reader, so there is nothing for a composition root to
  grant or withhold. `main.dart` did not change.

### What the read model had to refuse

The four fields (`summaryAmendmentId`, `summaryAmendedGeneration`,
`summaryAmendmentCount`, `summaryAmendedAt`) are written by one transaction and
by one writer. **No client can write any of them**: the close rule restricts a
cashier's single update to the seven closing keys, and
`rules-tests/test/shift-amendments.test.js` already proves a forged
`summaryAmendmentId` is denied to both the cashier and the owner. So a partial or
incoherent set is either a server that changed its contract without this client
knowing or a document no server wrote, and it is refused rather than read as an
uncorrected shift - reporting a rewritten total as an original one is the single
outcome this surface must not produce.

Three lines drawn deliberately:

- **The three deterministic fields are required together; the instant is not.**
  `summaryAmendedAt` is a server timestamp, and every instant in this read model
  is decoded as absent-or-valid for that reason. Its absence limits what the row
  can say about *when*; it never puts the correction itself in doubt, and the row
  says so in words.
- **A corrected shift with no summary is refused**
  (`amended_shift_without_summary`). The correction rewrites the three summary
  fields, so this document could not have come from one, and the row would
  otherwise have to say both that no totals were recorded and that the totals
  were corrected.
- **`summaryAmendmentCount` below 1 is refused.** The server writes the ID and
  increments the count in the same update, so a corrected shift has had at least
  one correction.

### Files in this chunk

```text
PLAN.md
lib/shift/shift_history.dart
lib/shift/shift_history_panel.dart
test/shift/shift_history_panel_test.dart
test/shift/shift_history_test.dart
```

No `functions/src`, Rules, index, or composition-root change. Nothing needed a
device or an emulator: the amended shift shape is already pinned on the server
side by `rules-tests/test/shift-amendments.test.js` and by the integration
suite's `amendShiftSummary` assertions from the previous chunk.

### Validation evidence after implementation code was frozen

| Command | Result |
| --- | --- |
| `flutter analyze --no-pub lib/shift lib/reporting test/shift test/reporting` | no issues |
| `flutter test --no-pub --concurrency=1 --reporter=failures-only` over the 10 in-scope test paths | **1185/1185**, up from 1175, adding **10** tests |
| the same with `shiftId:` dropped from `_openCorrections` | the narrowed-trail test fails, as it must |
| the same with `canReadCorrections` forced to `true` | the cashier test fails, as it must |
| `git diff --check` | clean |

The 10 new tests are 6 read-model cases and 4 panel cases.

### Meaningful failures and their resolutions

- **A control-character escape written into a test file became a literal control
  byte**, exactly as the note carried forward two handovers above warned. The
  refused-generation case now builds the character with `String.fromCharCode(1)`
  and a comment saying why, so the source file can never carry one. The whole
  file was re-scanned for control bytes afterwards; none remain.
- **A `[IO.File]::WriteAllText` round-trip silently stripped the UTF-8 BOM** from
  `lib/shift/shift_history_panel.dart`, which showed up as a one-line change to
  the import at the top of the diff. Restored by prepending the three bytes, and
  the analyzer and the suite were re-run afterwards. Some files in this
  repository carry a BOM and some do not; a PowerShell rewrite is not
  byte-preserving and the diff is what catches it.
- **A PowerShell `Replace` using a CR-LF newline matched nothing**: these files
  use LF endings.
- No assertion in the shipped code failed.

### The existing user-owned local edits remain separate and were never staged

```text
.vscode/settings.json
android/gradle.properties
pubspec.lock
.codex-app.png        (untracked)
.codex-live.png       (untracked)
.codex-live2.png      (untracked)
```

### Next bounded chunk

**The stock half of the reconciliation integration runner.** The suite now
carries a real sale through the metrics phase and the shift-verification phase;
`processStockPage` and its checkpoint chain are the remaining phase, and it is
the one that mutates nothing but is hardest to reason about from pure tests.

1. Seed a product whose `stockOnHand` deliberately disagrees with what the sale
   filed against it moved, exactly as the shift fixture seeds a summary that is
   deliberately wrong.
2. Assert a `reconciliation_anomalies` record of kind `stock_variance` with the
   expected, observed, and variance figures the ledger and the product actually
   differ by - found by querying `productId`, not by recomputing its digest, for
   the same reason the shift anomaly is found that way.
3. Assert the phase's checkpoint and counters on the completed job, waiting for
   `completed` rather than sampling, as the shifts phase does.
4. Assert that a product whose ledger agrees produces **no** record. A phase that
   reports a difference for everything is as broken as one that reports none, and
   the fixture should make both observable in one run.

Then, in preference order:

- **The landing screen's `Center` inside `SingleChildScrollView`.** Still a
  look-and-feel decision about the whole safe landing route rather than a defect,
  and it still wants a deliberate answer rather than a quiet edit. Ask before
  changing it.
- **A `shiftId`-narrowed entry point from the differences list.** That list opens
  the trail unnarrowed even when the row it was clicked beside names one shift.
  It is the same narrowing this chunk added to history, applied to the other
  surface that already knows the shift ID.

Leave outside all of them: any resolution path for the four stock and sale
differences, currency labels anywhere, the subscription surfaces (examined and
declined earlier in this file - start on the server, not in Flutter), receipt
printing, the printed receipt body, discounts, camera barcode scanning, password
reset (still blocked on the App Check decision recorded near the top of this
file), product cost/profit fields, a `platform_audit_logs` surface, branding
surfaces, the Sentry DSN, the 477 pre-existing analyzer issues in the legacy
files, and deployment.

### Practical notes carried forward

- Everything in the previous five sessions' lists still applies.
- A read model that drops a field the server writes is invisible until a surface
  needs it. `TenantShiftHistoryEntry` had dropped four for as long as the
  amendment path existed, and no test could have noticed.
- Do not rewrite a source file with PowerShell unless the BOM is preserved
  explicitly. Check `git diff` for a changed first line afterwards.

---

## The stock half of the runner, entered for the first time - 2026-08-05

### Completed in this session

The chunk above: **the reconciliation integration suite now enters the stock
phase.** It had never been entered by any test, and it could not have been:
`processStockPage` is unreachable from a sale.

That is the finding, and it is the same shape as the one two handovers above.
A sale-trigger job advances metrics then **shifts** - the runner's own
`advanceReconciliationJob` chooses `job.source === "sale_trigger" ? "shifts" :
"stock"` - so every sale this suite has ever written skipped the phase entirely.
The file even said so in a comment, used as a reason an absent `productCursor`
was a stable fact. The only entry point that starts a job whose phases include
stock is `requestTenantReconciliation`, which is why the fixture now exports it.

### Why it takes two runs, and why that is not a workaround

A product with no carried `stock_reconciliation_state` is **baselined**, not
compared: the run records what it found as the truth to measure the next one
against, sets `expectedQuantity = observedQuantity`, and writes
`baseline_established`. So a stock variance is unreachable in a single run *by
construction*, and a test that expected one from a first run would be asserting
something the design forbids.

The test therefore tells one story in two runs:

1. A manual **`full`** run baselines both seeded products and checkpoints what it
   read. `full` is what makes `checkpointKind` `manual` rather than `none`, so it
   is the only manual mode that writes a `stock_checkpoints` record at all.
2. A sale files three units against one product. The trigger writes the ledger
   movement and deliberately nothing else - the till is what decrements a product
   - so this is the state left behind when that never happened.
3. A manual **`incremental`** run is the first comparison that can disagree. It
   finds the ledger accounting for three fewer than the product holds and records
   the `stock_variance`.

Decisions worth recording:

- **The second run is `incremental` on purpose, and it is the sharper of the
  two.** It takes no checkpoint of its own, so it has to read the earlier
  checkpoint, recompute its hash, and agree with it while writing nothing that
  could paper over a disagreement. `checkpointChainValid: true` on a run that
  wrote no checkpoint is the chain actually being verified. The test also asserts
  that run wrote **no** checkpoint document.
- **The checkpoint hash is never recomputed by the test.** `stockCheckpointHash`
  is one function in one module; a test that derived the hash would agree with
  whatever it copied. What is asserted instead is that the *next* run recomputed
  it and agreed, and that the carried state points at the exact checkpoint path
  the earlier run wrote. Same reasoning as the shift anomaly being found by query
  rather than by digest.
- **Two products, one sale.** The product no sale named is asserted `matched`
  with no listed difference, and the job's `stockVarianceCount` is asserted to be
  exactly 1 of 2 products processed. A phase that reported a difference for
  everything would be as broken as one that reported none, and only a second
  product makes both observable in one run.
- **The stock the run disagreed with is asserted unmoved.** `mutatesStock: false`
  is on the job, the verification, and the anomaly, and the product's `quantity`
  is re-read and asserted unchanged. Reconciliation reports a stock difference;
  correcting one is a stock adjustment made from the product.
- **The fixture export needed no closure check.**
  `requestTenantReconciliation` lives in the same `reconciliation/handlers`
  module the task worker already comes from, so exporting it loads nothing that
  was not already loaded and cannot reach a new `defineSecret` parameter. That is
  recorded in the fixture beside the rule it satisfies.

### The guard that would have made the whole test vacuous

`reconcileProduct` defers any product whose `updatedAt` is inside the last five
minutes and records `recent_write_deferred` instead of comparing it. It exists so
a sale's own product decrement is not read as a variance during the window before
its movement lands.

Every fixture in this file seeded `updatedAt: now`, which is inside that window.
**The stock phase would have run, deferred both products, and asserted nothing
about stock** - a green test proving only that the phase can decline to answer.
The fixture now seeds a settled product ten minutes in the past behind an
explicit `settledStock` option, with the reason written at the constant.

Confirmed by mutating the fixture back to `updatedAt: now`: the test fails with
`recent_write_deferred` where it expects `baseline_established`.

### Files in this chunk

```text
PLAN.md
functions/reconciliation-integration/index.js
rules-tests/README.md
rules-tests/test/sale-reconciliation.integration.test.js
```

No `functions/src`, Rules, index, or Dart change. No production code changed at
all: the new test exercises code that was already shipped and already
unit-tested, and what it adds is the first evidence that the phase does what the
pure tests say when a real Firestore, a real task queue, and a real callable are
involved.

### Validation evidence after implementation code was frozen

| Command | Result |
| --- | --- |
| `npm --prefix rules-tests run test:emulator:reconciliation` | **8/8**, up from 7, adding **1** |
| the same with the fixture's product seeded inside the deferral window | the new test fails with `recent_write_deferred`, as it must |
| `npm --prefix functions test` | **206/206** |
| `npm --prefix rules-tests run test:emulator` | **139/139** |
| `FUNCTIONS_DISCOVERY_TIMEOUT=60000 npm --prefix rules-tests run test:emulator:invitations` | **12/12** |
| `flutter test --no-pub --concurrency=1 --reporter=failures-only` over the 10 in-scope test paths | **1185/1185**, unchanged - no Dart was touched |
| `git diff --check` | clean |

During development the new test was run alone with
`INTEGRATION_TEST_NAME_PATTERN='baselines stock'`, which matches only its name.

Measured cost of the new test: **15.9 seconds** inside a warm suite, of which the
`full` run's eleven task dispatches were about 13 seconds cold and under a second
warm. The reconciliation suite as a whole is now **56 seconds**. The
`MANUAL_RUN_TIMEOUT_MILLISECONDS` bound of 180 seconds is set well above that on
purpose: like every bound in this file it exists so a run that never advances
fails saying what it was waiting for, and the diagnostic line still reports the
time actually taken.

### Session totals

| Suite | Result |
| --- | --- |
| `flutter test` over the 10 in-scope paths | 1185 |
| `npm --prefix functions test` | 206 |
| `npm --prefix rules-tests run test:emulator` | 139 |
| `npm --prefix rules-tests run test:emulator:reconciliation` | 8 |
| `npm --prefix rules-tests run test:emulator:invitations` | 12 |

**1550 tests across five suites**, up from 1539 at the start of the session,
adding **11** across the two chunks. Nothing was left failing and no suite was
skipped except the Android build and the Android emulator runs.

### Meaningful failures and their resolutions

- **The emulator refused to start**: `firebase-tools no longer supports Java
  version before 21`. The machine's default `java` is older; this workspace's
  portable Temurin JDK 21 and Node 24 live under `D:\firebase-emulator-tools`.
  Every emulator command in this session was run with `JAVA_HOME` and `PATH`
  pointed at them, which is what earlier handovers meant by "the pinned Node
  24/JDK 21 environment". The exact prelude is recorded below.
- **`npm --prefix rules-tests` failed with ENOENT on
  `rules-tests/rules-tests/package.json`.** The Bash and PowerShell tools share
  one working directory, and an earlier `cd rules-tests` had persisted into it.
  Set the location explicitly at the start of an emulator command.
- No assertion in the shipped code failed. The new test passed on its first
  focused run.

### The pinned emulator environment on this workstation

```powershell
Set-Location 'd:\flutterpos'
$env:JAVA_HOME = 'D:\firebase-emulator-tools\jdk21\jdk-21.0.12+8'
$env:Path = "D:\firebase-emulator-tools\node-v24.18.1-win-x64;$env:JAVA_HOME\bin;$env:Path"
$env:DEBUG = ''
```

`DEBUG` is cleared because this machine sets `DEBUG=release`, and the Firebase
CLI treats any non-empty value as debug mode and then prints complete
environments and expected-denial traces.

### The existing user-owned local edits remain separate and were never staged

```text
.vscode/settings.json
android/gradle.properties
pubspec.lock
.codex-app.png        (untracked)
.codex-live.png       (untracked)
.codex-live2.png      (untracked)
```

### Next bounded chunk

**A `shiftId`-narrowed entry point from the differences list**, the mirror of the
one shift history got in this session's first chunk. The differences list already
holds a `shift_variance` row that names one shift, and its "View shift
corrections already made" button opens the whole business's trail unnarrowed -
so an operator who has just corrected the shift in front of them has to read down
a business-wide list to find the record of what they did.

1. `openTenantShiftAmendments` already takes a `shiftId`; nothing on that surface
   passes one. The row's `anomaly.shiftId` is already proved non-null by the read
   model before the correction is offered.
2. Offer it per row rather than replacing the page-level button: the page-level
   one is the right thing for a list covering several shifts, and the narrowed
   one answers a different question.
3. After a correction succeeds, the row is gone - the difference is deleted - so
   the notice that names the new `shift_amendments` ID is the only place the
   narrowed trail can be reached from at that moment. Decide deliberately whether
   the notice should carry that link, and say which way and why.
4. Cover the row offering the narrowed trail, the trail opening with that exact
   `shiftId`, a row of another kind offering nothing, and a manager who may read
   the trail but not correct anything still reaching it.

Then, in preference order:

- **The landing screen's `Center` inside `SingleChildScrollView`.** Still a
  look-and-feel decision about the whole safe landing route rather than a defect,
  and it still wants a deliberate answer rather than a quiet edit. Ask first.
- **A stock difference the stock phase found, reached from the product it belongs
  to.** The runner now proves the `stock_variance` record exists with real
  figures; the product stock surface is where somebody would answer for it, and
  nothing there mentions that a difference is listed.

Leave outside all of them: any resolution path for the four stock and sale
differences, currency labels anywhere, the subscription surfaces (examined and
declined earlier in this file - start on the server, not in Flutter), receipt
printing, the printed receipt body, discounts, camera barcode scanning, password
reset (still blocked on the App Check decision recorded near the top of this
file), product cost/profit fields, a `platform_audit_logs` surface, branding
surfaces, the Sentry DSN, the 477 pre-existing analyzer issues in the legacy
files, and deployment.

### Practical notes carried forward

- Everything in the previous five sessions' lists still applies.
- **A phase can only be tested from a job whose mode reaches it.** Two chunks in
  a row have now found a phase that ran on every sale and concluded nothing, or
  that no sale could reach at all. Before asserting a phase's output, check which
  `source` and `mode` actually advance into it.
- **A first run of anything that carries state establishes a baseline.** Stock,
  and anything modelled on it, cannot report a difference until there is a stored
  expectation to differ from. Two runs are the minimum, and that is the design
  rather than a limitation of the harness.
- `reconcileProduct` defers a product written in the last five minutes. Any stock
  fixture has to seed a settled `updatedAt` or it tests the deferral instead.

---

## The same narrowing, from the other side - 2026-08-05

### Completed in this session

The chunk above: **the differences list now opens the corrections trail narrowed
to the shift the row names**, and keeps it reachable after the row has been
deleted.

`openTenantShiftAmendments` has taken a `shiftId` since the trail was written and
nothing had ever passed one. Shift history got the first caller earlier in this
session; this is the surface where the question is asked most often, because it is
the surface the correction is made from.

### Three places it is now offered, and one where it deliberately is not

- **Per row, for every row that names a shift** - not only the one kind that can
  be corrected. A shift corrected at a later generation can still be listed under
  an earlier one, because a `reconciliation_anomalies` record is keyed by shift
  *and generation* and a correction deletes only the generation it settled. So
  "has this already been dealt with?" is a real question on an
  `invalid_or_missing_shift` row, and the answer - including "never" - comes from
  the trail rather than from this list. A test pins that row offering the link
  while offering no correction.
- **Beside the notice, after a correction succeeds.** The row it resolved has
  been deleted by the server, so without this the correction just made would be
  reachable only by opening the whole business's trail and reading down. It is
  narrowed to the shift **the server's answer named**, not the shift this page
  asked about, which is the same rule the notice text already follows.
- **Beside the notice, after an outcome nobody knows.** Whether a correction was
  recorded is precisely the open question there, and the trail is the only place
  that answers it. Both the ambiguous refusal and the untrustworthy-answer path
  now offer it, and the untrustworthy-answer sentence was reworded to say so.
- **Not after a refusal that certainly changed nothing.** A definite refusal left
  the shift exactly as it was, so there is nothing new to look at, and a link
  there would imply otherwise. Pinned by its own test.

Two more decisions worth recording:

- **No role check was added, and adding one would have been wrong.**
  `TenantReconciliationAnomalyRepository.allowedRoles` and
  `TenantShiftAmendmentFeedRepository.allowedRoles` are the same three roles, so
  anyone who can read this page can read the trail. The manager who may read the
  list but not correct anything is the case that matters, and a test asserts that
  manager gets the trail link and no correction button.
- **The page-level button stays.** A list covering several shifts and one shift's
  own trail answer different questions, so the narrowed link was added beside the
  business-wide one rather than replacing it.

### Files in this chunk

```text
PLAN.md
lib/reporting/reconciliation_anomalies_panel.dart
test/reporting/reconciliation_anomalies_panel_test.dart
```

No `functions/src`, Rules, index, or composition-root change. Nothing needed a
device or an emulator.

### Validation evidence after implementation code was frozen

| Command | Result |
| --- | --- |
| `flutter analyze --no-pub lib/reporting test/reporting` | no issues |
| `flutter test --no-pub --concurrency=1 --reporter=failures-only` over the 10 in-scope test paths | **1191/1191**, up from 1185, adding **6** tests |
| the same with the row's link passing `null` instead of the shift, and the refusal branch keeping the shift | exactly the three tests that pin those two properties fail, as they must |
| `git diff --check` | clean |

The emulator suites were not re-run for this chunk: it changed one Flutter widget
and its test, and the four server suites had already been run green after the
previous chunk froze. Their totals are unchanged at 206, 139, 8, and 12.

### Meaningful failures and their resolutions

- **The panel test's fake reader answered every collection from one page.** It
  returns documents by cursor and filter but ignored the collection path, so the
  trail this page opens would have been served the differences list's own
  documents and failed its strict read model closed - a route that opened
  correctly would have looked broken. It now keys pages by exact collection path
  and falls back to the single page, so every existing test is unaffected.
- No assertion in the shipped code failed. All six new tests passed on their first
  run.

### Session totals

| Suite | Result |
| --- | --- |
| `flutter test` over the 10 in-scope paths | 1191 |
| `npm --prefix functions test` | 206 |
| `npm --prefix rules-tests run test:emulator` | 139 |
| `npm --prefix rules-tests run test:emulator:reconciliation` | 8 |
| `npm --prefix rules-tests run test:emulator:invitations` | 12 |

**1556 tests across five suites**, up from 1539 at the start of the session,
adding **17** across three chunks. Nothing was left failing and no suite was
skipped except the Android build and the Android emulator runs.

### The existing user-owned local edits remain separate and were never staged

```text
.vscode/settings.json
android/gradle.properties
pubspec.lock
.codex-app.png        (untracked)
.codex-live.png       (untracked)
.codex-live2.png      (untracked)
```

### Next bounded chunk

**A stock difference, reached from the product it belongs to.** The runner now has
end-to-end evidence that a `stock_variance` record exists with real expected,
observed, and variance figures, and the differences list renders it - but the
product stock surface, which is where somebody answers for a product's on-hand,
says nothing about a difference being listed against it. The correction for a
stock difference is a stock adjustment made from that surface, so the operator who
can act on it is the one who cannot currently see it.

1. `TenantProductStockRepository` reads the product; the difference lives in
   `reconciliation_anomalies` filtered by `productId ==`. Confirm that read is
   allowed to the roles the product stock surface is granted to before designing
   around it - the differences list is owner/admin/manager, and the stock surface
   may be wider.
2. State the figures the record carries and never recompute them: the ledger's
   expected quantity, the product's observed quantity, and which way they differ.
   The existing `_detail` sentence in the differences panel is the wording to
   match.
3. Distinguish the three stock kinds the phase can record -`stock_variance`,
   `invalid_stock_movement`, and `checkpoint_chain_invalid`. The last two are not
   quantity disagreements and an adjustment does not resolve them, so saying
   "correct this" for them would be wrong.
4. Do not add a resolution path. Recording an adjustment already exists on that
   surface; this chunk is about the difference being visible where the adjustment
   is made, and the existing excluded work stays excluded.
5. Cover a product with no difference showing nothing, one with a
   `stock_variance` showing the figures, one of each other kind saying what it is,
   and a failed or denied anomaly read leaving the stock surface itself readable.

Then, in preference order:

- **The landing screen's `Center` inside `SingleChildScrollView`.** Still a
  look-and-feel decision about the whole safe landing route rather than a defect,
  and it still wants a deliberate answer rather than a quiet edit. Ask first.
- **The stock phase's other two outcomes, against a real server.** The integration
  suite now proves the variance path; `invalid_stock_movement` and
  `checkpoint_chain_invalid` are the two the fixture could engineer next, and the
  second is the one that would catch two modules disagreeing about a checkpoint
  hash.

Leave outside all of them: any resolution path for the four stock and sale
differences, currency labels anywhere, the subscription surfaces (examined and
declined earlier in this file - start on the server, not in Flutter), receipt
printing, the printed receipt body, discounts, camera barcode scanning, password
reset (still blocked on the App Check decision recorded near the top of this
file), product cost/profit fields, a `platform_audit_logs` surface, branding
surfaces, the Sentry DSN, the 477 pre-existing analyzer issues in the legacy
files, and deployment.

### Practical notes carried forward

- Everything in the previous five sessions' lists still applies.
- **A fake reader that ignores the collection path makes any route this surface
  opens untestable.** Two panel fakes in this repository now key pages by exact
  path; a third that does not will fail the next route it opens for the wrong
  reason.
- A narrowing parameter that no caller passes is not a feature. Two surfaces in
  this session were the first callers of one that had existed, untested from the
  caller's side, since the trail was written.
