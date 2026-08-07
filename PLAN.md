# Chilltent POS — Frozen Implementation Baseline

Current state only. Every dated session handover lives in [HISTORY.md](HISTORY.md),
verbatim and in order — go there for why a decision was made, what a chunk
deliberately left out, and which failures cost a debugging cycle.

Last verified against the code on **2026-08-07**. Claims in this file are checked
against source, not inherited from the log; corrections are noted where they were
made.

---

## Status board

### Tracks

| Track | State | What is left |
| --- | --- | --- |
| **Cloud Functions** | ~95% | 46 handlers, 272 unit tests. No live Brevo, no deployment. |
| **Firestore Rules & contracts** | ~95% | Every collection a client reads is covered. `subscription` has rules and no writer. |
| **Flutter client** | ~75% | The sell-and-settle loop works. No catalog management, no configuration writing, no printing, no subscription. |
| **Deployment & operations** | ~5% | Nothing deployed anywhere. Only the dev project is even mapped. |

### Can a shop do this yet?

Green means a person could do it in a running app today. Not green if only the
callable exists, and not green if it is merely tested.

| Capability | | Where it stands |
| --- | --- | --- |
| Sign in | 🟢 | `LoginScreen` |
| Verify an email address | 🟢 | Offered on the business selector to an unverified identity |
| Recover a forgotten password | 🔴 | `requestPasswordReset` has no caller — blocked on App Check, see open decisions |
| Request a new business | 🟢 | "Request business" on the selector |
| Accept a staff invitation | 🟢 | In-app for a verified identity; email-link proof otherwise |
| Switch business / set default | 🟢 | "Change business", "Make default" |
| Invite, edit, deactivate staff | 🟢 | "View staff directory" → typed gateways |
| Open and close a shift | 🟢 | Shift panel on the landing route |
| Ring up a sale | 🟢 | "New sale" → cart, tender, saved offline, submitted automatically |
| **Add or edit a product** | 🔴 | **No write path exists anywhere in the migrated code.** Catalog is read-only; the seed script is the only way a product gets in |
| **Set the currency / checkout configuration** | 🔴 | Read-only. Without it the till refuses to sell at all |
| Adjust stock | 🟢 | Product stock route → `adjustStock` |
| Record a return | 🟢 | From a sale, via receipt lookup or shift history |
| Verify a return, restoring stock | 🟢 | Owner/admin/manager, on a pending return |
| Look up a receipt | 🟢 | "Find a receipt" |
| Read daily and period totals | 🟢 | Daily summary, plus period totals by member and category |
| Ask for reconciliation | 🟢 | Owner/admin, from the reconciliation status route |
| See why a day disagrees, and correct a shift | 🟢 | Differences list → `amendShiftSummary` |
| Print a receipt | 🔴 | No printed body exists |
| See a subscription | 🔴 | Path and rules exist; nothing reads or writes it |
| Platform: review, approve, suspend, archive a business | 🟢 | Platform tabs |
| Platform: disable or reactivate an identity | 🟢 | Exact-UID review tab |
| Platform: grant or revoke platform admin | 🟡 | Operator CLI only, deliberately not in-app |

**The two bolded rows are the gap that matters: a shop cannot stock itself.**
Everything downstream of a product existing works, and nothing puts one there except
`rules-tests/scripts/seed-dev-emulator.js`. This was never a decision — it was
defaulted into, one bounded chunk at a time, and is now an open decision below.

### Rollout position

The fifteen frozen steps, with what is actually true:

| # | Step | State |
| --- | --- | --- |
| 1 | Freeze schemas, contracts, invariants, indexes | ✅ |
| 2 | Central authorization and idempotency wrappers | ✅ |
| 3 | Platform eligibility scans, identity-transition locks | ✅ |
| 4 | Tenant routing, pagination, selection, onboarding limits | ✅ |
| 5 | Owner/admin invariants, global-status saga, recovery CLI | ✅ |
| 6 | Membership mirrors, fan-out, repair | ✅ |
| 7 | Invitations, tokenless acceptance, password reset, suppression | ⚠️ server complete; password reset unreachable from any client |
| 8 | Brevo delivery, webhook normalization, action pages | ⚠️ implemented, never exercised against live Brevo |
| 9 | `TenantSession`, switching, shift restoration, epochs | ✅ |
| 10 | Encrypted Hive cache, single-flight checkout, receipt counters | ✅ |
| 11 | Stock, sales, returns, subscriptions, reconciliation, reporting | ⚠️ all but subscription; catalog management missing |
| 12 | Emulator, multi-device, Windows-offline, email, adversarial tests | ⚠️ emulator suites green; no multi-device, no Windows-offline, no live email |
| 13 | Deploy development, then staging | ❌ not started |
| 14 | Enable App Check on validated platforms | ❌ not started; no `firebase_app_check` dependency |
| 15 | Promote the identical release to production | ❌ not started |

### Test baselines

| Suite | Command | Count |
| --- | --- | --- |
| Flutter | `flutter test --no-pub --concurrency=1 --reporter=failures-only` | **1251** ⚠️ |
| Functions | `npm --prefix functions test` | **272** |
| Rules | `npm --prefix rules-tests run test:emulator` | **141** |
| Reconciliation integration | `npm --prefix rules-tests run test:emulator:reconciliation` | **10** |
| Invitation integration | `FUNCTIONS_DISCOVERY_TIMEOUT=60000 npm --prefix rules-tests run test:emulator:invitations` | **12** |

**1686 tests across five suites.** `flutter test` takes no path list — the one
uncompilable file that forced that workaround was deleted on 2026-08-07. Functions
was re-run and measured at 272 on 2026-08-07; the three emulator counts are carried
from the run that last touched them and were not re-measured in this split.

⚠️ **The Flutter suite is not reliably green.** Measured twice on 2026-08-07: one
run **1250 passed, 1 failed**, the next **1251 passed**. The failure is
`test/checkout/checkout_sync_signals_test.dart:333` — the seam case that wires a
real encrypted outbox, a real submission worker, and a real recovery coordinator and
asserts a saved sale ends `confirmed`; it observed `awaitingConfirmation`. The file
passes **13/13** run alone, so it is order- or state-dependent rather than a
regression. The outbox serializes on a **static** per-box lock, which is the same
mechanism that deadlocked this file once before, so that is the first place to look.
Do not read a single green run as proof.

---

## Corrections made in this split

Eight stale claims were found by checking source rather than the log, and are
already fixed in the text below: the export count (44 → **46**), the public
callable list (21 → **23**), the tender write half (reachable since 2026-08-02),
`getSalesComparison` and `requestTenantReconciliation` (both reached), the tenant
path contract (9 → **15** collections), the user-owned file list (five Firebase
edits → **three** unrelated files), and the environment mapping (only dev exists in
`.firebaserc`). The full before-and-after is the 2026-08-07 entry in
[HISTORY.md](HISTORY.md).

Two claims were checked and **hold**: `requestPasswordReset` still has no caller,
and `lib/main copy.dart` is still a 48-line stray that should be deleted.

---

## Standing decisions and unreachable capabilities

### A sale records how it was paid for, chosen manually

Resolved 2026-08-01 by the product owner, implemented 2026-08-02. The cashier
selects the tender at the point of sale — **cash, M-Pesa, or card** — and it is
recorded on the sale. No payment *integration* is in scope: nothing authorizes a
card, queries an STK push, or reconciles a provider statement. The recorded
tender is the cashier's assertion, and every surface that displays it says so
through the shared `checkoutTenderDisclaimer`.

The five hazards are settled, not open:

1. **A v1 payload still parses and is never rewritten.**
   `supportedCheckoutSalePayloadSchemaVersions = {1, 2}`. Version is read from
   the payload, never from the current constant.
2. **That is why the hash still matches.** `checkoutPayloadHash` covers the whole
   payload and `_parseRecord` re-derives it on every read, so an in-place
   migration would make every stored record `malformed_record`.
3. **Rules constrain the tender** through `validSaleTender`, and now *require*
   `payloadSchemaVersion`, which the rule previously ignored.
4. **The receipt pattern was not touched.** `CT-A7F-20260729-0042` is an identity,
   derivable from device, business date, and sequence alone.
5. **Reconciliation needed no change.** A per-tender breakdown was added to
   `getSalesComparison` only, not to stored `daily_metrics`.

### Built, tested, and still unreachable

| Capability | State |
| --- | --- |
| `requestPasswordReset` | **Blocked on App Check.** Still no caller — see below. |
| Subscription | `TenantPaths.currentSubscription` and rules exist; **nothing reads it and nothing writes it**. `grep -i subscription functions/src` finds nothing at all, so there is no schema to model. Start on the server, not in Flutter. |
| Product cost / profit | `profit` is parsed at `lib/reporting/daily_metrics.dart:64` and deliberately never displayed. No product carries a cost, so the server's profit equals its revenue; showing it would report a 100% margin. |
| Catalog management | Not "unreachable" so much as unbuilt: there is no product create, update, or delete anywhere in the migrated client. |
| Checkout configuration writing | Same. The till reads `configuration/checkout` and refuses to sell without it. |

---

## Open decisions

### Public password reset needs App Check, which this app has none of

`requestPasswordReset` is declared `enforceAppCheck: true` **and** calls
`requireAppCheckedPublic`, which throws `failed-precondition` when `request.app` is
absent. There is no `firebase_app_check` dependency in `pubspec.yaml` and no
initialization, so the callable would reject every request the client could make.
Signing in first is no workaround: reset is a *public* endpoint used by someone who
cannot authenticate, so unlike every other callable it has no authenticated
fallback.

The harder half is Windows. Built-in App Check providers cover Apple, Android, and
web only, and the spec already records Windows relying on authentication until a
tested custom provider exists. A public endpoint has no authentication to rely on,
so **in-app password reset is structurally unreachable on Windows** — the platform
the whole Hive offline design exists for. Three ways out, none obviously right:

1. Add `firebase_app_check` and offer reset on Apple, Android, and web only, telling
   a Windows user to reset elsewhere. Cheapest; leaves the primary POS platform
   without recovery.
2. Implement the custom Windows provider the spec anticipates. Most faithful, by far
   the most work.
3. Relax the endpoint to accept an unattested request under different rate limiting.
   Weakens a deliberate enumeration boundary; not to be done casually.

Until this is decided, a user who forgets their password has no in-app recovery on
any platform.

### Whether the app should be able to stock itself

Never stated as a decision, which is why it went unnoticed. Every operational
surface downstream of a product works and nothing creates one. Either a guarded
catalog-management vertical in the client, or a deliberate statement that a catalog
is provisioned out-of-band and the seed script is the supported route. It should be
chosen rather than defaulted into.

---

## Identity, Tenancy, and Public Interfaces

### Environments

`dev multitenant-pos-b8326`, `staging chilltent-pos-staging`,
`prod chilltent-pos-prod`. CI must always receive an explicit environment/project
mapping. **Only `dev` is mapped in `.firebaserc` today** (`default` and `control`
both point at it); staging and production exist in this spec and nowhere else.

### Root model

```text
/users/{uid}
  email, displayName
  accountType                 // tenant_user | platform_admin
  identityOrigin              // self_signup | staff_invitation | platform_bootstrap
  identityTransition?         // granting_platform | revoking_platform | cleanup_pending
  globalStatus                // active | disabled
  defaultTenantId?
  membershipCount, ownedTenantCount, ownedActiveTenantCount
  createdAt, updatedAt

/users/{uid}/tenant_memberships/{tenantId}
  tenantId, tenantName, tenantSlug
  role                        // owner | admin | manager | cashier
  membershipStatus            // pending | active | inactive
  tenantStatus                // pending | active | suspended | rejected | archived
  invitationStatus, isOwner
  createdAt, joinedAt, updatedAt, mirrorVersion
```

Mirrors, counters, and `defaultTenantId` are advisory. They never authorize
access. Canonical authorization remains `/tenants/{tenantId}` and
`/tenants/{tenantId}/staff/{uid}`, and every staff document carries a
server-controlled `uid` for collection-group scans.

Platform collections: `/platform_config`, `/platform_audit_logs`,
`/platform_user_operations`, `/platform_identity_operations`,
`/platform_membership_repair_runs`, `/owner_recovery_cases`, `/email_deliveries`,
`/email_suppressions`, `/tenant_slugs`.

### Tenant path contract

`TenantPaths.businessCollections`, all fifteen. The enumeration is frozen and
`test/tenancy/tenant_paths_test.dart` fails when it changes without being declared
there: `products`, `categories`, `sales`, `shifts`, `returns`, `staff`,
`configuration`, `subscription`, `audit_logs`, `stock_adjustments`,
`daily_metrics`, `reconciliation_jobs`, `reconciliation_dirty_days`,
`reconciliation_anomalies`, `shift_amendments` — plus one product subcollection,
`stock_movements`.

### Tenant routing and limits

`listMyTenants({pageSize?, cursor?})` — default 20, maximum 50, ordered by
membership creation descending then tenant ID, server-issued opaque cursor, each
result overlaid with canonical tenant and staff state, returning `items`,
`nextCursor`, `hasMore`.

Login order: device-local last selection if canonically valid; else
`defaultTenantId` if valid; else the sole accessible tenant; else the selector.
Pending, rejected, suspended, and inactive memberships are shown without granting
access. Opening a tenant updates only the device-local selection; `defaultTenantId`
changes only through an explicit "Make default".

Limits, enforced when requesting, approving, or reactivating:
`maxPendingTenantsPerUser: 3`, `maxTenantRequestsPer24Hours: 5`,
`maxOwnedActiveTenantsPerUser: 25`.

### Shared authorization

```text
requireAppCheckedPublic()
requireAuthenticatedUser({allowUnverified})
requireVerifiedTenantApplicant()
requirePendingTenantInvite(tenantId)
requireTenantMember(tenantId, allowedRoles)
requirePlatformAdmin()
```

`requireTenantMember` verifies auth exists, root `globalStatus == active`, tenant
exists and is active, canonical staff membership exists, staff status is active,
and the tenant-local role is allowed. No handler implements these independently.

Idempotency keys are scoped by `actorUid + operation + tenantId/global-scope + requestId`.

### Public callable interfaces

Twenty-three `onCall` endpoints. The last two were added after the original list
was frozen and are marked:

```text
sendAccountVerification({requestId})
requestPasswordReset({email, requestId})
getMyEmailDeliveryStatus()
listMyTenants({pageSize?, cursor?})
setDefaultTenant({tenantId, requestId})
requestTenant({name, slug, requestId})
setTenantLifecycle({tenantId, status, reason?, requestId})
setGlobalUserStatus({uid, status, reason, requestId})
getGlobalUserStatusReview({uid})                          // added later
inviteStaff({tenantId, email, name, phone, role, requestId})
updateStaffUser({tenantId, uid, name, phone, role, requestId})
setStaffStatus({tenantId, uid, status, requestId})
replacePendingStaffEmail({tenantId, uid, email, requestId})
resendStaffInvitation({tenantId, uid, requestId})
cancelTenantInvitation({tenantId, uid, reason, requestId})
acceptTenantInvitation({tenantId, invitationVersion, invitationToken, requestId})
acceptVisibleTenantInvitation({tenantId, requestId})
reviewEmailSuppression({email, action, reason, confirmation?, evidenceReference?, requestId})
adjustStock({tenantId, productId, quantityDelta, type, reason, requestId})
verifyReturnAndRestoreStock({tenantId, returnId, requestId})
getSalesComparison({tenantId, previousStartDate, previousEndDate, soldById?, categoryId?})
requestTenantReconciliation({tenantId, mode, requestId})
amendShiftSummary({tenantId, shiftId, reason, requestId})  // added later
```

### Full export surface

`functions/src/index.ts` exports **46** handlers — callables above, plus task
workers, triggers, retry workers, and schedulers:

```text
cleanupAbandonedStaffIdentities  consumePendingPlatformAlert
consumeTenantMembershipFanout    deliverAccountVerification
deliverPasswordReset             deliverPlatformAlertNotification
deliverStaffInvitation           mergeSaleReconciliationJob
receiveBrevoEmailWebhook         repairCanonicalStaffMirror
repairTenantRoutingProjection    retryGlobalUserStatusOperations
retryMembershipRepairTasks       retryPlatformAlertNotifications
retryStaffInvitationDeliveries   retryTenantReconciliationTasks
runMembershipRepairTask          runReconciliationTenantDiscoveryTask
runTenantReconciliationTask      startNightlyTenantReconciliation
startStaggeredMonthlyReconciliation  startWeeklyMembershipRepair
startWeeklyStockCheckpoints
```

`grantPlatformAdmin` and `revokePlatformAdmin` are deliberately **not** exported.
They are Admin SDK CLIs (`npm --prefix functions run grant-platform-admin`,
`revoke-platform-admin`) with a fixed project allowlist, actor authorization, exact
target confirmation, and deterministic exit states. Do not re-export the legacy
root-collection staff or reporting handlers.

---

## Platform, Ownership, and Membership Integrity

**Platform-admin eligibility** requires all three: `platformRole == "superAdmin"`
in the Auth claim, `accountType == "platform_admin"`, and `globalStatus == "active"`.
Granting never trusts counters: it places `identityTransition=granting_platform`
transactionally, runs `collectionGroup("staff").where("uid","==",target)`, searches
tenants by `ownerUid`, confirms no membership or unresolved invitation of any kind,
then sets the account type and merges the claim. Any canonical membership clears
the transition and rejects. The same scans are mandatory before deleting an
abandoned invitation-created identity. `requestTenant` rejects platform identities
and `inviteStaff` rejects platform targets — platform identities hold no tenant
memberships in v1.

**Owner invariant.** Every non-archived tenant has exactly one owner, with
`tenant.ownerUid` equal to the owner staff UID and that staff role `owner`. The
owner has all administrator permissions, cannot be demoted or deactivated through
ordinary APIs, and counts as an administrative principal — a globally active user
with an active membership and role `owner` or `admin`. Normal membership and role
operations must retain at least one. Global security disabling is the deliberate
exception: it proceeds even when it removes the last principal, then raises a
critical `tenant_owner_unavailable` or `no_active_administrator` alert, identifies
affected tenants, notifies operators, suspends nothing automatically, and directs
operators to owner recovery.

**Global-status saga.** `/platform_user_operations/{requestId}` records uid, target
status, per-step Firestore/Auth/claim status, overall
`pending | completed | partially_failed`, attempt count, requester, reason,
affected tenants, and last error code. Disable order: create the operation and set
root `globalStatus=disabled`; determine tenants losing a principal; raise alerts;
disable Firebase Auth; remove platform privilege; revoke refresh tokens; finish
audits. Reactivate order: enable Auth; set root active; complete audits; require a
new sign-in; **never restore platform claims automatically.** A private retry
worker resumes partial failures, and root status is checked by both Rules and
Functions, so a failed Auth update does not restore access.

**Owner recovery** is operator-only, unavailable through Flutter and the dashboard.
Normal recovery replaces an owner with an existing active admin. Exceptional
recovery promotes a verified, globally active tenant user who is not yet an
administrator, and additionally requires a recorded
`/owner_recovery_cases/{caseId}`, a support reference, `--exceptional`, typed
confirmation of the slug and both UIDs, a second confirmation flag, a written
reason, and proof the replacement is not a platform identity. Default outcome: the
old owner becomes an inactive admin and the replacement the active owner, in one
transaction updating the tenant, canonical staff, mirrors, owner counters,
lifecycle history, and both audits. Both paths preserve exactly-one-owner.

**Membership-mirror repair.** Canonical membership and mirror update
transactionally; tenant-wide name and status changes fan out asynchronously.
Targeted repair runs after a failed fan-out and a paginated full repair runs
weekly. Canonical data always wins. Repair fixes missing or orphaned mirrors, wrong
tenant/role/membership/invitation/lifecycle status, incorrect counts, wrong owner
flags, invalid `defaultTenantId`, and mirrors without canonical staff. Summaries
are audited and never authorize anything.

---

## Invitations and Email

**Invitation proof.** `/tenants/{tenantId}/staff_invitations/{uid}` is server-only
and holds the version, a versioned HMAC of the token, key version, issue and expiry
instants, used-at, status, invited email, inviter, and latest delivery ID. Each
attempt generates 32 random bytes, stores only the HMAC, increments the version,
expires after seven days, invalidates older versions, and gets its own delivery
record. Acceptance requires matching tenant, UID, invited email, version, hash,
expiry, unused state, and authentication no older than five minutes.

**Existing-user in-app acceptance.** `acceptVisibleTenantInvitation` requires the
caller to be the exact invited UID, a globally active root, a verified Firebase
email matching `invitedEmail`, a pending canonical membership, invitation status
pending or sent, `auth_time` under five minutes, and an active tenant. Flutter must
visibly show the business name, invited role, and an accept/cancel confirmation
first. The transaction activates the membership, updates the mirror, marks the
invitation accepted, consumes any outstanding token, and writes the tenant audit.
Versioned token proof remains mandatory for new identities, unverified identities,
password setup, and direct email-link acceptance.

**Email correction.** A tenant administrator never changes a shared identity's
global Auth email. Correcting a pending address cancels that invitation and creates
or reuses the identity for the corrected address. Before disabling or cleaning an
abandoned provisional UID: canonical staff collection-group scan, tenant owner
query, pending invitation scan, identity-transition check.

**Password-reset task.** The public endpoint enqueues a private Cloud Task carrying
the normalized email. The worker performs the Auth lookup and creates a delivery
only for an eligible identity. Plaintext never enters Firestore or normal logs, and
the public response is always `{"accepted": true}`. Before sending, the worker
confirms the Auth user's current email HMAC still matches the requested hash.

**Suppression mapping.** Permanent: hard bounce, invalid recipient, spam complaint,
and a provider block whose exact reason confirms permanent invalidity, prior
complaint, or prior hard bounce. Temporary: soft bounce, mailbox full, greylisting,
rate limit, timeout, temporary policy or reputation block, and **unknown blocked
reasons** — only a versioned, tested reason-code mapping may reclassify one.

**Suppression review.** `reviewEmailSuppression` is platform-admin-only. It
normalizes in memory, calculates current and supported previous HMAC versions,
finds matching records without storing plaintext, returns only redacted category,
event date, status, and reason class, and audits inspection and clearing. Clearing
a hard bounce or invalid recipient requires confirmation the address was corrected
or independently verified; clearing a complaint requires
`confirmation=clear_spam_complaint` and an evidence reference. Clearing marks the
record inactive with `clearedAt`, `clearedBy`, and a reason — never deleting
history. Tenant administrators cannot inspect or clear global suppression.

`getMyEmailDeliveryStatus()` answers for the caller's own address only and returns
one of two exact strings. The client matches them as sentinels rather than
displaying the server's sentence, because that sentence covers four different
causes and is itself the enumeration boundary. The public reset flow never reveals
this state.

**Brevo webhook privacy.** Persist only `providerMessageId`, `eventType`,
`providerTimestamp`, `recipientHash`, `normalizedReasonCode`, `processedAt`,
`payloadSchemaVersion`. Unparseable payloads may be encrypted in quarantine for
seven days; no raw payload is retained indefinitely. Continue using
provider-independent delivery, Admin action links, the Brevo HTTP API,
authenticated webhooks, source-controlled templates, SPF, DKIM, DMARC, a custom
return path, and disabled tracking.

---

## Offline Operations, Stock, and Receipts

**Tenant switching** is blocked by an unsynchronized checkout, a submission in
flight, other tracked pending writes, an unfinished cash count or shift close, an
unsaved tenant-scoped workflow, or no connectivity for target validation. **A
server-confirmed open shift alone does not block switching.** Owners and managers
may inspect another tenant while a shift stays open; a cashier cannot open checkout
in a second tenant on the same device while another tenant's shift remains open.
Returning restores only that tenant's own validated shift.

**Hive checkout state machine**, keyed `{uid}:{tenantId}:{checkoutId}`:

```text
saved_offline → submitting → awaiting_confirmation → confirmed | needs_attention
```

Each record holds submission attempt, persistent lease, retry time, payload, and
payload hash. Only one sync worker may call `batch.commit()` for a checkout, and
lease expiry permits a confirmation check, **never blind resubmission**. On restart:
inspect the local deterministic sale, wait if Firestore reports pending writes,
query the server when online, confirm a matching hash, flag a mismatch, and retry
only when no pending write and no server sale exist.

A saved sale triggers the sync pass immediately through `CheckoutSyncSignals` rather
than waiting for the next session open or connectivity change. The pass is
recover → submit → **recover again** → refresh derived data; the second recovery is
what settles a commit made during the same pass. Hive stores encrypted
tenant-specific product, price, configuration, shift, draft, printer, and sync
state; Firestore offline persistence is unavailable on Windows, so Hive remains the
cross-platform offline source.

**Stock rules.** Sale-line quantity is a positive integer; product quantity is
signed and may be negative. Checkout uses `FieldValue.increment(-quantity)` and
`FieldValue.serverTimestamp()`, and may change only product `quantity` and
`updatedAt`; positive changes require trusted adjustment, return, or import logic.
**The till does not refuse to sell below zero** — Rules permit signed stock, an
offline device holds a figure that was true at the last sync, and refusing would
block a legitimate sale while guaranteeing nothing on the server.

**Receipt sequence.** Counter key
`{tenantId}:{deviceId}:{businessDate}:receiptCounter`, deliberately not scoped by
cashier UID, allocated atomically in Hive under the checkout coordinator's local
lock, so two checkouts on one device cannot share a value. The receipt is
`CT-A7F-20260729-0042`; the sale records cashier UID separately and `saleId` remains
the database identity. Malformed counter state fails closed rather than restarting,
because restarting would reissue a number a committed sale already carries.

---

## Reconciliation, Rules, and Testing

### Reconciliation

Sale triggers merge one job per tenant per five-minute server-receipt bucket.
Nightly processing runs at 05:30 `Africa/Nairobi`, paginates tenants through
chained Cloud Tasks, enqueues one deterministic task per active tenant, and
regenerates dirty daily metrics while verifying stock and shifts. Weekly
checkpoints at 04:30 Sunday retain expected and observed quantities separately;
staggered monthly discovery at 04:45 validates the checkpoint chain, with a
ten-minute recovery scheduler. **Reconciliation never silently changes stock.**

A stock comparison concludes through one tested function,
`stockComparisonOutcome` in `reconciliation/model.ts`, ordered most-specific
cause first: an unreadable movement outranks an unverifiable chain, which
outranks a quantity variance. A first run **baselines** rather than compares, so
a variance needs two runs. A product written in the last five minutes is
deferred, carrying nothing forward.

Three bounds share one Firestore write budget and none is safe to raise alone:
5,000 sales read per business date, 200 stale shift expectations deleted, 200
distinct shifts written — 402 writes against the limit of 500.

The backoff ladder is 15s, 30s, 60s, 120s, 240s, 480s, 960s. Quarantine at eight
consecutive failures fires at the seventh rung, so the one-hour cap is unreachable;
the threshold must also stay below the queue's `maxAttempts: 12`, or the queue
abandons the task before the job quarantines itself and no alert is ever written.

The claim lease is ten minutes against a seven-minute worker deadline. The
three-minute margin is what stops a worker inside its own deadline from losing its
lease, which is the only way two workers reach one job's processors at once.

### Rules

Rules authorize from root global status, canonical tenant, and canonical staff
membership — never from mirrors or counters. Platform access requires both the
claim and an active platform record. Tenant membership operations involving platform
identities are rejected. Invitation proof, suppression, delivery, repair, lifecycle,
saga, subscription, and audit records are server-write-only. Positive direct stock
updates, return approval, and legacy root operational collections are denied.

Role boundaries, each decided deliberately rather than by default:

| Collection | Read |
| --- | --- |
| `sales`, `returns` | any active member — a receipt lookup and a return against a colleague's sale both need it |
| `shifts` | owner/admin/manager, or the shift's own cashier |
| `staff` | owner/admin/manager, or the member's own record |
| `daily_metrics`, `stock_adjustments`, `stock_movements`, `reconciliation_*`, `shift_amendments` | owner/admin/manager |
| `audit_logs` | owner/admin, plus platform |

App Check built-in providers cover Apple, Android, and web. Windows relies on
authentication, canonical authorization, rate limiting, and idempotency until a
tested custom provider exists. Enforcement is currently set on the public
password-reset endpoint only.

### Required tests

The frozen list is honoured: canonical platform-grant scans despite zero counters;
grant and invitation cannot race through `identityTransition`; abandoned identities
survive while a membership exists; exactly one owner per non-archived tenant; staff
operations retain an active principal; global disable proceeds but alerts; both
recovery paths restore an owner; verified users accept in-app without a token and
unverified ones cannot; token and tokenless acceptance cannot both complete;
suppression inspection is platform-only and audited; complaint clearing needs
stronger confirmation; password reset never reveals suppression; two cashiers on one
device get different receipts; counters are independent per device, tenant, and
date; confirmed open shifts do not block owner/manager switching while pending
checkout and cash-close do; mirror repair fixes routing without touching
authorization; Windows checkout survives restart using Hive; App Check is enabled
only for validated platforms.

---

## Working on this repository

### The emulator prelude is not optional

The machine's default `java` is JDK 17 and firebase-tools hard-fails on anything
below 21. Every emulator command needs this first:

```powershell
if (Test-Path Env:DEBUG) { Remove-Item Env:DEBUG }
$env:JAVA_HOME = 'D:\firebase-emulator-tools\jdk21\jdk-21.0.12+8'
$env:Path = "D:\firebase-emulator-tools\node-v24.18.1-win-x64;$env:JAVA_HOME\bin;$env:Path"
```

`DEBUG` is cleared because this machine sets `DEBUG=release`, and Firebase treats
any non-empty value as debug mode, answering with complete environments and
enormous expected-denial traces.

### Standing traps

- **A local `emulators:exec` against `firebase.json` needs `functions/.secret.local`
  and `functions/.env.local`.** Five secrets and six string parameters have no
  default, so the emulator stops to ask and the run hangs silently after
  `Serving at port ...`. `run-dev-emulators.js` writes and removes both and refuses
  to overwrite leftovers from a killed run — delete them, and clear the ports.
- **The Auth emulator reserves three ports:** `port`, `port + 200`, `port + 400`.
  Dev 9099, invitations 9199, reconciliation 9699; a fourth may not use 9299, 9399,
  9499, 9599, 9899, or 10099.
- **Never free a port by killing an emulator you did not start** — a held run may be
  holding seeded data. Read its command line; `--hold` is the tell.
- **Do not run Gradle and the emulators together**: 2–3 GB free, and the Firestore
  JVM dies with a native `OutOfMemoryError`.
- **Use Flutter's own `adb`** at
  `C:\Users\BonifaceMasota\develop\android-sdk\platform-tools\adb.exe`; the one first
  on `PATH` is a different binary and the two servers fight.
- **A cold emulator's first trigger delivery costs ~25 s**, every later one ~310 ms.
  Set timeouts from the first. The reconciliation integration suite needs **more than
  ten minutes** of wall clock — background it.
- **Collection-page test fakes must** answer in ascending document-ID order, be keyed
  per business, be keyed per collection, and model the equality-filter contract in
  both directions. All four mistakes have cost a debugging cycle.
- **`TenantRouteGuard` reloads on a session change, not a rebuild** — a second
  `pumpWidget` into the same tree keeps the first answer, so tear the tree down
  between cases. Its `loading` widget replaces the whole subtree, so any panel that
  re-reads on a signal blanks unless it passes its last value as that widget.
- **Render the screen before diagnosing the screen**, with real fonts via
  `FontLoader` over `<flutter>/bin/cache/artifacts/material_fonts` — without them
  every glyph is a filled box. Set `debugShowCheckedModeBanner: false`, or read the
  banner as a clipped app-bar action. Two layout claims here were wrong and were
  settled in minutes by one rendering each.
- **Do not revert a mutation with `git checkout -- <path>`** in a session that also
  edits that file. Hold the original in memory and restore in a `finally`.
- **A `.cmd` cannot be spawned from Node without `shell: true`** — it fails as
  `EINVAL` with no output. Call
  `node functions/node_modules/typescript/bin/tsc -p functions/tsconfig.json`.
- **`node --test` needs `--test-reporter=tap`** before its output is filtered; the
  default failure marker is `✖`, so filtering for `not ok` reports a silent pass.
  **`Select-Object -First N` terminates the upstream command** and reports a
  meaningless exit code — capture with `Out-String`, then filter.
- **Do not rewrite a source file with PowerShell** unless the BOM is preserved; check
  `git diff` for a changed first line afterwards.

### Repository state

`flutter analyze --no-pub lib test` reports **477 pre-existing issues**, all in the
disabled legacy island (`lib/pos/**`, `lib/screens/**`, `thermal_printer_service`,
`glass_card`, `pill_input`, `theme.dart`) plus the experimental Sentry
`profilesSampleRate` warning at `lib/main.dart:29`. Analyse the paths a chunk
touches. The legacy screens reference each other but nothing in `lib/main.dart` or
the tenancy shell reaches them, so they are a closed unreachable island.

`lib/main copy.dart` is a 48-line stray in `lib/` and should be deleted; it is noted
only so nobody mistakes it for a live entry point.

The Sentry DSN in `lib/main.dart` is an `http://` URL. Android blocks cleartext in
every build, so those envelopes have never been delivered from a device. The debug
network-security config deliberately does not cover it.

These local edits are user-owned, are not this work's, and must never be staged:

```text
.vscode/settings.json
android/gradle.properties
pubspec.lock
.codex-app.png .codex-live.png .codex-live2.png   (untracked)
```

---

## Next bounded chunk

**Cover `registerSaleReceipt`'s own defences.** It is the entry point every
reconciliation job comes from — one Firestore trigger per sale — and it already runs
against the in-memory Firestore double, but only down its simplest path. Each branch
below is one it takes on real data and none is asserted anywhere:

1. **The receipt is the idempotency key.** A redelivered `onDocumentCreated` must
   return the first delivery's task and invalid-line count without writing a second
   movement or double-counting the dirty day; a receipt whose `tenantId`,
   `businessDate`, or `jobId` disagrees with the retry must throw `already-exists`.
2. **`saleMovements` combines lines per product and rejects the rest.** Two lines of
   one product become one movement with `lineCount: 2`; a non-object line, a missing
   or over-long or slash-bearing `productId`, a non-integer or non-positive quantity,
   and an unsafe integer sum each count as invalid. `items` that is not an array is
   one invalid line; anything past the hundredth is counted and dropped.
3. **Invalid lines write a `reconciliation_anomalies` document**, only when there is
   at least one, and increment the dirty day's `invalidLineCount` by the same figure
   — the only place a malformed sale is visible to an operator.
4. **A bucket belonging to another source throws.** `dirty_<bucket>` is a predictable
   ID, so a job created there by anything but the sale trigger must be refused.
5. The movement document ID switches to a hash past 120 characters of sale ID — the
   branch that keeps a Firestore path legal.

Do not add `collectionGroup`, `in`, or `<=` to the double for this; none of the
above needs them.

### Then, in preference order

- **Run the app against the emulators**, looking at the reconciliation and stock
  surfaces. Queued five times and the oldest behavioural item: neither the
  deleted-product ledger nor the run route has been seen outside a widget test. A
  seeded emulator set may still be held open — check before starting a new one.
  **This needs a decision first:** whether the Android exclusion is lifted, because
  a Windows or web run exercises only the loopback path. Ask.
- **Chase the one intermittent Flutter failure** recorded in the baselines below.
- **`ensureSweep` and `processTenantDiscoveryPage`** are the last two reachable
  uncovered exports in `jobs.ts` — the 50-tenant page boundary, monthly shard-day
  filter, page-document idempotency, and sweep identity collision are all in reach
  of the double. `listRetryableReconciliationTasks` is not: it needs
  `collectionGroup`, an `in` filter, and `<=`.
- **`regenerateDailyMetric` writes `daily_metrics` with `merge: false` and no
  `createdAt`**, unlike every other document in this pipeline. Probably deliberate;
  nothing says which.

### Standing exclusions

Outside every chunk until deliberately scheduled: a resolution path for the four
stock and sale differences, currency labels on the differences list, the subscription
surfaces, receipt printing and the printed receipt body, discounts, camera barcode
scanning, password reset (blocked on the App Check decision above), product
cost/profit fields, a `platform_audit_logs` surface, branding surfaces, the Sentry
DSN, the 477 pre-existing analyzer issues, a root-widget smoke test and the startup
seams it would need, and deployment.

---

## Assumptions

- The mono-tenant Firebase project remains untouched.
- The shared Firebase projects begin empty.
- Standard users may own or join several tenants.
- Tenant switching requires connectivity; the current tenant remains offline-first.
- Platform identities are dedicated and membership-free.
- Public ownership transfer remains deferred; operator recovery is included.
- Offline revocation takes effect when connectivity returns.
- Consolidated portfolios, shared billing, and group-wide permissions remain future work.
