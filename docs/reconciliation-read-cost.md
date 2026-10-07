# Reconciliation and report read costs

## Scheduling

- Sale, return and repayment receipts keep their idempotent ledger/dirty-day writes, but do not enqueue reconciliation jobs.
- A shift's transition to `closed` queues one durable job for that shift. It processes the shift's business date, then verifies that day's shift expectations; it skips stock. The normal close flow already refuses unsynchronized local sales. Later arrivals remain dirty for overnight catch-up.
- The 05:30 Africa/Nairobi sweep processes dirty days and checks stock. On Sundays it carries a weekly checkpoint; on the tenant's stable monthly shard day it instead runs the full 35-day check and monthly checkpoint.
- Existing weekly/monthly scheduler exports join the same 05:30 sweep and deterministic job IDs, so they cannot start additional stock scans. Manual catch-up/full checks and durable retry recovery remain available.

## Live totals

`sales_daily_totals` holds gross/net sales, profit completeness, counts and tender splits per date, staff and category scope. `sales_total_contributions` remembers each sale's last applied contribution. Sale/return write triggers re-read current records and transactionally apply the difference, making duplicate and out-of-order events harmless. Monetary deltas use integer minor units. Repayments remain shift-tender evidence; they are not counted a second time as sales revenue.

`getSalesComparison` reads these summaries. A warm request reads a readiness document and a summary per date, plus canonical authorization. Transaction lists, item rankings and returns detail still have their own reads; this change does not remove those.

Existing dates initialize on first request, paging sales and persisting progress every 100 records. This is a one-time source scan, not a zero-cost migration; a large cold report may need a retry while the server initializes it. Live events and initialization use the same idempotent projection. Overnight/full reconciliation rechecks contributions and repairs totals, guarding repair batches against concurrent live deltas.

Cashiers are forced to their authenticated UID on the server, cannot request another member, and receive no profit figures. The Sales Report shows their own full-day totals, independent of its 20-row transaction page. Owners/admins/managers retain business/staff scopes. Summary collections have no client read/write grant; the callable is the access boundary. Device totals remain available offline and are replaced by the server answer.

The projection trades some additional writes/storage for fewer repeated reads. It remains eventually consistent while Firestore triggers are pending. Existing reconciliation bounds (5,000 sales/day) remain; per-sale projection fanout is bounded rather than partially publishing a very large category set.

## Rollout

Deploy the Functions changes and `firestore.indexes.json`, then distribute the Flutter update. The new index supports shift-close verification by date. Backend changes alone do not expose cashier totals in older app builds. New collections initialize automatically; no destructive migration is needed.

## Validation

- 111 focused backend tests passed (reports, projections, receipt intake, reconciliation processors/jobs/sweeps).
- 130 Flutter tests passed (totals, offline aggregation, cashier Sales Report and reconciliation status).
- 11 Auth/Firestore/Functions emulator tests passed, including cashier self-scope and shift-close execution.
- Targeted Flutter analysis passed. The broader backend run initially passed 757/758 tests. Its remaining sentinel-audit failure was subsequently fixed by reviewing and registering the email/WhatsApp `sent` payloads; the Functions build and all seven sentinel-audit tests now pass.
