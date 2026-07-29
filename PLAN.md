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
