# Membership mirror repair

These workers repair routing data only. Neither a mirror, a repair run, nor an
advisory counter is read by an authorization decision.

## Durable flows

- A canonical staff write creates a deterministic user repair.
- A tenant lifecycle `membership_fanout_jobs` document creates a deterministic
  tenant repair. Tenant pages project canonical tenant/staff/root data, and
  enqueue deterministic user repairs to rebuild counters and defaults.
- Every Sunday at 03:15 `Africa/Nairobi`, a deterministic full run pages root
  users and the global membership-mirror collection group. The second phase is
  what discovers mirrors whose parent root document no longer exists.
- A ten-minute sweeper re-enqueues pending jobs and jobs with expired leases.

Pages are capped at 75 documents. Progress uses full document-path cursors for
collection-group scans, and each Cloud Task is named from the run ID and stored
revision. A committed page is therefore safe if the process exits before it can
enqueue the next task.

`platform_membership_repair_runs/{runId}` is both the resumable control record
and the audit summary. It records scanned, created, updated, deleted, unchanged,
invalid, root-counter, default-selection, discovery, and issue totals.
Parent tenant/full runs wait for all deterministic user children and retain both
their direct `summary`, aggregated `childSummary`, and final `aggregateSummary`.

## Lifecycle counter coordination

`setTenantLifecycle` may adjust the owner's advisory counts immediately. The
fan-out worker never applies another increment/decrement. Its user follow-up
recomputes all three counts from canonical staff and tenant records and
overwrites the advisory values. Archived ownership contributes to membership
count, but not `ownedTenantCount` or `ownedActiveTenantCount`.

## Deployment requirements

Export all handlers in `membershipMirrorHandlers.ts` from the Functions entry
point. Deployment requires Cloud Tasks, Cloud Scheduler, Eventarc, and the
Firestore API. The Functions runtime service account needs permission to
enqueue `runMembershipRepairTask`.

The tenant orphan scan needs a collection-group composite index on
`tenant_memberships`: `tenantId ASC, __name__ ASC`. The canonical user scan
uses the collection-group single-field index on `staff.uid` with document-name
ordering. Do not exempt either field from indexing.
