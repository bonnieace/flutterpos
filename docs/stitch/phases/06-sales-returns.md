# Phase 06 — Sales history, receipts, shifts, and returns

## Objective

Connect receipt lookup, shift history, shift sales, sale detail, return request, and management stock
restoration into a coherent evidence trail.

## Evidence to open

- Screenshot groups 31-34 and print queue group 37 where receipt recovery intersects.
- `lib/sales/`, `lib/shift/`, `lib/returns/`.
- Receipt numbering and immutable queued print bytes.

## Required screens/states

- Receipt lookup empty/searching/not found/found.
- Shift history and per-shift sales.
- Sale detail with recorded tender, lines, receipt identity, and historical discount display if
  supported by the stored sale.
- Return request by any active role and management verification/stock restoration.
- Already returned, partially returnable, validation, and remote failure states where evidenced.

## Exclusions

- New checkout discount entry, refund-provider integration, payment reversal claims, or regenerated
  historical receipt facts.

## Acceptance criteria

- Original sale evidence remains immutable and traceable.
- Request and verification roles are visibly distinct.
- Return/restock consequences are explicit before confirmation.
- Receipt and shift navigation works at all target breakpoints.
