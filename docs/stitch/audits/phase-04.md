# Phase 04 catalog and stock audit — 2026-08-20

Project: `7478406619239162026`

Operation: `CORRECT` existing desktop/mobile inventory screens; Stitch returned derived successors
Design-system asset: `assets/4c1cc58b4aed4b1693e6f8113ba1009a` (retained, not mutated)

## Result

Phase 04 selected ST-002 `084c238a51814cdca8b47a9cd2af594b` and ST-007
`220deae97920481393a45bf3e395384a`. ST-002 returned invalid argument during pre-mutation retrieval;
ST-007 was retrievable and visibly contained unsupported reorder thresholds, low-stock treatment,
invented products, role-mode tabs, and generic mobile navigation.

Stitch returned four derived screens during correction:

- ST-037 `8fff386768994eed8fa3dbd08f173684` — first desktop successor, superseded.
- ST-038 `df83e2b93aa74dbb8d809e281093f8cb` — first mobile successor, superseded.
- ST-039 `1273644f84ce4978a64bcff21fee7728` — final desktop route suite.
- ST-040 `04e000e868734d41a53b30acbc810703` — final mobile route suite.

No Flutter/Firebase code, design-system asset, later-phase screen, or unrelated Stitch source was
changed. No screen was deleted, moved, grouped, hidden, or archived.

## Evidence and role contract

The correction was grounded in screenshot groups 17–24 and active files under `lib/inventory/`,
including catalog management, bulk catalog, stock adjustment/feed, stock movement/feed, movement
labels, and product ledger panels.

- Every active role may read the catalog.
- Owner, Administrator, and Manager may create categories/products and perform operational catalog
  and stock work.
- Only Owner/Administrator may change an existing price or cost, remove a recorded cost, or retire a
  product. Manager may set the required first price while creating a product but cannot supply cost.
- Cashier has no catalog or stock write surface.
- Bulk input is pasted delimited text; preview writes nothing and commit applies exactly the preview.
- Recorded stock may be negative and never blocks a sale.
- Adjustments are permanent and reasoned. Adjustment feed, all-source movement feed, and product
  ledger retain before/after, reason/source, actor, and recorded time.

## First-render conflicts and correction

ST-037/ST-038 removed visible reorder quantities but still failed Phase 04:

- Desktop compressed unrelated navigation and stock adjustment into the catalog form.
- Mobile retained generic bottom navigation and role-mode tabs.
- Both used invented products and omitted most bulk, audit, failure, and responsive evidence.

A bounded correction produced vertically extended ST-039/ST-040 route suites. The fresh ST-039
render and HTML verified:

- Owner/Administrator, Manager, and Cashier structures are separate.
- Manager money/retire controls and Cashier write/stock actions are absent.
- `Preview, writing nothing`, `Apply exactly this`, and row-level `Unknown category: Snacks` appear.
- Product stock, permanent-adjustment copy, 834px tablet transformation, loading/empty/error/offline
  states, and the exact non-blocking stock sentence appear.
- Reorder, low-stock, purchase-order, `.xlsx`, generic sync, and switch-user content are absent.

The audit-record section still collapsed adjustments, movements, and ledger into one table, used
`Before/After`, and substituted invented actor/source examples. A final in-place correction required
three distinct route specimens, exact `Before and after`, the evidenced +24 manual adjustment and -2
sale/source `co-1`, explicit provenance, and removal of a supplier-oriented reason placeholder.

That final edit completed without returning a new screen ID, but immediate ST-039 retrieval continued
to serve its pre-correction screenshot/HTML. ST-040 returned invalid argument immediately after its
successful generation. Per the operating contract, neither screen was regenerated or repeatedly
edited. The final working set remains render-review-required.

## Acceptance summary

- Role-narrow fields/actions structurally clear: passed in correction specification; core desktop
  role structure visually reviewed, final render review pending.
- Stock never implies sales blocking: passed in fresh desktop artifact.
- Actor, time, reason, and before/after audit context: final correction completed; stale retrieval
  prevents visual approval.
- Mobile records avoid horizontal truncation: passed in correction output; visual review pending.
- Empty, loading, read error, offline write, bulk preview/error/commit, negative stock, adjustment,
  movement, and ledger states: covered in the final working direction.
- Final status: `NORMALIZED / REVIEW`; neither ST-039 nor ST-040 is approved while retrieval is stale.

## Recommended next phase

Proceed to Phase 05, reporting and reconciliation, after a Stitch UI review confirms ST-039/ST-040
and their canvas linkage. Do not fold receipts/returns, staff, settings/printing, or platform
administration into Phase 05.
