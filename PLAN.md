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
