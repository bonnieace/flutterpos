# Product reference map

This map connects current behavior, rendered evidence, and Stitch coverage. “Stitch” describes the
read-only 2026-08-20 canvas audit; it does not approve a screen.

## Evidence corpus

The checked-in `screenshots/` gallery is generated from real route classes with deterministic fake
repositories. It proves widget composition at the captured viewport and state; it does not prove
device behavior, backend integration, motion, native printing, or exhaustive authorization.

| Viewport set | Count | Purpose |
|---|---:|---|
| `web/` | 147 | 1440x900 desktop/browser state |
| `mobile/` | 129 | 411x891 phone state |
| `tablet/` | 18 | 834x1000 selective responsive contracts |
| `web-full/` | 25 | Full desktop content height |
| `mobile-full/` | 39 | Full mobile content height |
| `tablet-full/` | 1 | Full tablet content height |
| **Total** | **359** | 37 product workflow/state groups plus 10 component/system boards |

Regeneration and index commands are documented in `screenshots/README.md`. Treat the test harness
comments that cite root `design.md` as historical context, not a new Stitch layout constraint.

## Domain map

| Domain | Active implementation | Local screenshot groups | Roles | Responsive evidence | Stitch coverage and disposition |
|---|---|---|---|---|---|
| Authentication and tenant entry | `lib/main.dart`, `lib/tenancy/` | 01-09 | Public/member; platform superAdmin for 09 | Web/mobile | Phase 01 created desktop/mobile sign-in and tenant-entry state suites. Platform operations remain excluded; corrected/stale artifacts require final canvas review. |
| Role-aware home/navigation | `TenantSafeLandingScreen`, `TenantShiftPanel` | 10-12, 99 | All members; actions vary | Web/mobile, proposal states | Phase 02 corrected the desktop/mobile direction through ST-032/ST-033: exact role routes, shift-first mobile task hub, device-local checkout/print evidence, and tenant-switch states. Fresh corrected renders remain to review. |
| Staff | `TenantStaffDirectoryScreen`, tenancy callables | 13, 13b, 13c | Owner/admin write; manager read | Web/mobile | One desktop screen exists with wrong branding, invented roles and granular permissions. `REPLACE`. |
| Checkout/sale | `lib/checkout/`, checkout route wiring | 14, 15, 15b | All active roles | Web/mobile/tablet contract | Phase 03 produced ST-035 as the visually reviewed desktop/tablet direction and derived mobile browse/cart successors. VAT, Pay/verification, draft, discount, stock blocking, and print rollback are excluded; mobile renders and browse-source ID still need canvas review. |
| Checkout configuration | `checkout_configuration*` | 16 | Owner/admin | Web/mobile | No verified canonical screen. Business Settings drafts largely invent settings; currency-only screen should be `CREATE`. |
| Catalog read/manage | `lib/inventory/catalog*` | 17-20 | Read all; manage owner/admin/manager; money/retire owner/admin | Web/mobile/tablet contract | Phase 04 produced ST-039/ST-040 role-aware route suites covering read-only, management, correction, retirement, and pasted-text bulk preview/commit. Final renders remain to review. |
| Stock | `stock_adjustment*`, `stock_movement*`, product ledger | 21-24 | Owner/admin/manager | Web/mobile/tablet contract | Phase 04 added recorded stock, non-blocking negative stock, permanent reasoned adjustments, movement feed, product ledger, audit provenance, and responsive record transformations in ST-039/ST-040. Final renders remain to review. |
| Reporting/reconciliation | `lib/reporting/` | 25-30 | Management, with owner/admin-only writes/profit | Web/mobile | Phase 05 working set is ST-041 desktop plus ST-043 mobile; ST-042 is superseded. Final copy corrections completed in the mutation log, but downloadable retrieval is stale/invalid and one expected-value label needs visual correction before canonical promotion. Export remains excluded. `REVIEW`; Phase 05 is closed. |
| Sales/receipts/returns | `lib/sales/`, `lib/returns/` | 31, 33, 34 | Receipt/return request all; restore management | Web/mobile | No verified receipt lookup/history/return canonical screen. `CREATE`. |
| Shift history | `lib/shift/`, reporting amendments | 12, 30, 32, 33 | Own shift all; management history manager+ | Web/mobile | Reconciliation screens cover only part of the domain. `CORRECT` plus `CREATE`. |
| Activity/audit | `lib/audit/` | 35 | Owner/admin | Web/mobile | No verified Stitch screen. `CREATE`. |
| Printer/receipt queue | `checkout_print_*`, receipt body/queue | 36-37 | Config owner/admin; queue all | Web/mobile | Three desktop printer screens exist. Check against actual host/port/width/cutter/test and queue semantics; `CORRECT`, retain high-fidelity reference if accurate. |
| Design components/states | `lib/ui/`, route panels | 90-99 | N/A | Web/mobile/tablet matrices | No dedicated Stitch component inventory. Derive reusable patterns after canonical workflow screens, not from old `AppLayout.contract`. |

## Product workflow families

| Group | Families represented |
|---|---|
| 01-09 | Sign in; refused/unreachable/caps-lock; choose business; verify email; request business; no businesses; invitation acceptance/invalidity; account failure; platform operator states. |
| 10-13 | Owner/cashier homes; shift open/count; staff directory editing/read-only. |
| 14-20 | Empty/cart checkout; saved-not-printed; currency config; read/manage catalog; product correction; bulk preview/commit. |
| 21-24 | Product stock, differences, corrections, movements, ledger. |
| 25-30 | Daily summary, sales totals, reconciliation status/differences/run, shift corrections. |
| 31-35 | Receipt lookup/found, shift history/sales, returns, activity log. |
| 36-37 | Printer configuration states and print queue states. |
| 90-99 | Button, transition, field, disclosure, dialog/frame, tabs/layout/filter/navigation/pagination, page/list states, quantity/stat, motion/banner/sync, and owner-home proposal boards. |

## Architecture and state constraints

- Flutter Material application; Firebase Auth, Firestore, and callable functions provide the remote
  boundary.
- Firestore offline persistence is enabled. Encrypted Hive stores tenant choice, checkout outbox,
  catalog cache, receipt counters, shift state, and print queue.
- Connectivity recovery runs checkout recovery, submission, and catalog refresh in that order.
- Tenant switching requires connectivity and is blocked by relevant local checkout/cash-close state.
- Sale durability precedes receipt printing. A print failure leaves a retryable job and does not
  reverse or relabel the sale.
- The active application does not use `lib/pos/**` or `lib/screens/**`; those are legacy evidence only.

## Existing Stitch design clusters

The canvas appears to contain original, normalized, and high-fidelity clusters. Pairing by position
and title is an inference until the six unreadable source screens are recovered.

- Sale: original desktop, normalized desktop, mobile product browse, mobile review/pay.
- Manager home: original desktop, normalized desktop, mobile.
- Printer: original desktop, normalized desktop, high-fidelity desktop.
- Settings: original desktop and normalized desktop.
- Reconciliation: original desktop, normalized desktop, mobile.
- Reporting: normalized desktop and mobile analytics.
- Inventory: normalized desktop.
- Staff: original desktop.
- Brand: one logo screen.

The canvas does not yet represent the full product. Missing domains must be designed from active
behavior and screenshot evidence, not filled with generic POS assumptions.
