> # RETIRED — 2026-08-27
>
> **Not authority.** The Stitch redesign, its phase briefs, handovers, open questions, coverage
> and audit trail are all retired. The pre-multitenancy app's look and flow is what recent work
> has been rebuilding on the multitenant backend, and **the developer directs that screen by
> screen** — their request outranks anything written here.
>
> Kept for reference and for the reasoning it records. Do not treat any decision, brief, matrix or
> checklist in this directory as a constraint on work the developer has asked for.

# Initial read-only audit — 2026-08-20

## Outcome

The repository, 359-image local screenshot corpus, current RBAC, connected Stitch project, 26 screen
instances, and Profound Verdant design system were inventoried. The project is useful as a visual
starting point but is not product-safe as-is. No Stitch mutation and no product-code change occurred.

## Method and source order

1. Active Dart/Firebase-facing code for behavior and permission truth.
2. `tool/screenshots/` definitions and generated `screenshots/` output for rendered-state evidence.
3. Read-only Stitch project, design-system, and per-screen retrieval.
4. Existing repository documentation for history and unresolved scope.

The native connector in the open chat retained a stale unauthenticated session. The configured API
key succeeded against the same Stitch MCP endpoint for read-only calls. A future Codex session should
reload configuration; no credential is stored in this repository.

## Repository findings

- Active domains: authentication/tenancy, checkout, shift, inventory, reporting, sales, returns,
  audit, printing, and reusable UI infrastructure.
- Remote boundary: Firebase Auth, Firestore, and callable functions.
- Local/offline boundary: Firestore persistence plus encrypted Hive state for tenant choice,
  checkout outbox/cache/counters, shift state, and print queue.
- Active tenant roles: owner, admin, manager, cashier. Owner inherits admin access only; manager is
  not a generic administrator. Platform superAdmin is a separate claim.
- Legacy `lib/pos/**` and `lib/screens/**` do not define the active product.
- The reusable theme seam is `AppTokens`; the current layout seam (`AppLayout.contract` and its
  consumers) is too prescriptive to serve as the new Stitch composition authority.

## Screenshot findings

- 359 PNGs: 147 web, 129 mobile, 18 tablet, 25 web-full, 39 mobile-full, 1 tablet-full.
- 37 numbered product workflow/state groups and 10 component/system boards.
- The harness uses real active route classes with deterministic fakes. It is current-state context,
  not a backend/device proof.
- Checkout visibly records a tender without verification, does not expose VAT, and does not block a
  sale on stock. Printing failure is a separate post-save state.
- Owner and cashier homes already demonstrate materially different navigation.

## Stitch findings

- Project `7478406619239162026` contains 26 screen instances.
- 20 source screens were retrieved; six returned invalid argument and remain unidentified.
- `list_screens` also returned invalid argument, so project instance metadata is the inventory source.
- One design system exists: `assets/4c1cc58b4aed4b1693e6f8113ba1009a`, Profound Verdant v1.
- Existing clusters cover sale, manager home, printer, settings, reconciliation, analytics, inventory,
  staff, and a logo. Authentication, tenant entry, receipt lookup, returns, activity, much of stock,
  print queue, and platform operations lack verified canonical screens.

## Highest-risk contradictions

- VAT/tax UI despite no active tax capability.
- “Pay now” language despite tender being asserted rather than externally verified.
- Manager telemetry, low-stock thresholds, and terminal/cloud status without product data sources.
- Staff roles and granular permissions that do not exist.
- Broad business settings, CSV export, and analytics affordances without active surfaces.
- Wrong “Kijani POS” branding on original screens.

## Design-system assessment

Profound Verdant's dark-green identity, compact shapes, high-density operational guidance, and
spacious management guidance are reusable. Its literal color definitions conflict internally, so the
semantic token model is accepted while exact literals remain an open question. The redesign should
later flow through a reusable Flutter theme extension; no screen should hardcode theme values.

## Stop condition

The audit/setup phase is complete when the documentation is reviewed and any blocking questions are
answered. Do not start Phase 00 or mutate Stitch without a new explicit approval naming the operation
and target IDs.
