> # RETIRED — 2026-08-27
>
> **Not authority.** The Stitch redesign, its phase briefs, handovers, open questions, coverage
> and audit trail are all retired. The pre-multitenancy app's look and flow is what recent work
> has been rebuilding on the multitenant backend, and **the developer directs that screen by
> screen** — their request outranks anything written here.
>
> Kept for reference and for the reasoning it records. Do not treat any decision, brief, matrix or
> checklist in this directory as a constraint on work the developer has asked for.

# Phase 03 — Sale and checkout

## Objective

Create the canonical fast sale path across desktop, tablet, and mobile while preserving offline and
printing truth.

## Evidence to open

- Screenshot groups 14, 15, 15b, 16, and relevant 90-98 component states.
- `lib/checkout/`, checkout cache/outbox/sync, receipt body, and print queue.
- Stitch ST-001, ST-009, ST-011, ST-026.

## Required screens/states

- Empty product browse, search/filter, cart populated, quantity editing/removal.
- Tender selection as an assertion, save busy/success/error, saved locally/server confirmed.
- Stock warning that does not block sale.
- Sale durable but printer failed; route to receipts waiting.
- Desktop multi-region, tablet two-region, and mobile staged browse/review compositions.

## Exclusions

- VAT/tax calculation, externally verified payment, new discount input, save-draft action, stock
  blocking, or rollback because printing failed.

## Acceptance criteria

- Primary sale action is unambiguous and never claims payment verification.
- Connectivity and print outcomes are distinct from sale durability.
- Price, quantity, totals, currency, and receipt evidence remain legible under realistic density.
- Role and tenant context remain visible without competing with the sale path.
