> # RETIRED — 2026-08-27
>
> **Not authority.** The Stitch redesign, its phase briefs, handovers, open questions, coverage
> and audit trail are all retired. The pre-multitenancy app's look and flow is what recent work
> has been rebuilding on the multitenant backend, and **the developer directs that screen by
> screen** — their request outranks anything written here.
>
> Kept for reference and for the reasoning it records. Do not treat any decision, brief, matrix or
> checklist in this directory as a constraint on work the developer has asked for.

# Stitch export map — 2026-08-22

Local export root: `docs/stitch/stitch_chilltent_pos_redesign_system/` (gitignored, 18 MB, 78 folders).

This session has **no Stitch MCP connector**. The MCP audit recorded in `LIVE_PHASE_HANDOFF.md` was
performed by a different agent in a different session and cannot be repeated here. The extracted
project export replaces it as the local design source. This map joins each export folder to the
`SCREEN_INDEX.md` logical ID so every later phase can cite an exact local file instead of a screen ID
it cannot fetch.

Each folder holds `code.html` (the served markup, with the full Profound Verdant token block inlined
as a Tailwind config) and `screen.png`. `profound_verdant/` holds `DESIGN.md` and no screen.

## Export freshness — verified by content, not by file date

Every defect the 2026-08-21 live handoff recorded is present in the export, so the export agrees with
what Stitch served during that audit:

| Handoff-recorded defect | Export evidence |
|---|---|
| ST-027 serves `Retry Connection` and `Remember me on this terminal` | both strings present in `chilltent_pos_sign_in_states_desktop` |
| ST-033 serves `KES 4,200.00` and `Own shift panel` | both present in `chilltent_pos_role_aware_home_navigation_mobile` |
| ST-036 invents a save-failure cause | `Storage full or write error.` present in `chilltent_pos_new_sale_mobile_cart` |
| ST-039 uses `Before/After` | present in `chilltent_pos_catalog_stock_route_suite_desktop` |
| ST-048 serves `Ceramic Mug` and `Tax (16%)` | both present in `..._mobile_suite_final_normalized` |
| ST-040 is "9 KB, stops after `1. Cashier — Product catalog`" | `..._mobile_route_suite/code.html` is **9,218 bytes** and ends with the generator comment `Add more specimens following the prompt instructions` |
| Phase 01 mobile successor is "the complete eight-section direction with no bottom navigation" | `..._mobile_final_phase_01_canonical_suite/code.html` has exactly **8** `<section>` elements and **0** bottom-nav references |

The two structural fingerprints (9,218 bytes; 8 sections and no bottom nav) are the strongest
evidence: they match values the handoff measured independently.

## Profound Verdant palette — the recorded discrepancy is resolved

`DESIGN_RULES.md` required that neither literal be promoted while the design-system source named both
`#071610` and `#0A1A14` for surface, and both `#4BE277` and `#22C55E` for primary. Reading
`profound_verdant/DESIGN.md` against all 76 exported `code.html` files resolves it. The two pairs were
never competing candidates for one role.

| Value | Role in the DESIGN.md frontmatter | Occurrences in served HTML | Files (of 76) |
|---|---|---:|---:|
| `#071610` | `surface`, `surface-dim`, `background` | 243 | 75 |
| `#0A1A14` | **no token — appears only in the prose** | 0 | **0** |
| `#4BE277` | `primary` | 85 | 75 |
| `#22C55E` | `primary-container` | 75 | 75 |
| `#132A1F` | `surface-elevated` | 83 | 75 |
| `#0D1F16` | `surface-card` | 75 | 75 |
| `#45F28D` | `currency-kes` | 75 | 75 |
| `#D4E7DD` | `on-surface`, `on-background` | 237 | 75 |

Findings:

1. The **YAML frontmatter is authoritative**; the prose beneath it has drifted. The prose sentences
   "The background uses `#0A1A14`", "Level 0 (Base): `#0A1A14`", and "Primary (#22C55E)" all
   contradict the frontmatter of their own file.
2. `#0A1A14` is **not a token at all** and renders in zero screens. It must not enter the theme layer
   under any role.
3. `#4BE277` and `#22C55E` are **two distinct roles**, both rendered in all 75 screens. `#22C55E` is
   `primary-container`, not an alternative primary.
4. `OPEN_QUESTIONS.md` Phase 00 item 1 already recorded `#071610` and `#4BE277` as the working
   reference. That reference was correct, and is now evidenced rather than assumed.

## How the join was derived

The export carries **no Stitch screen IDs** — none of the handoff's 32-hex IDs appear in any exported
file, and the HTML contains no id-shaped strings. The join therefore uses two independent keys:

1. **Title slug.** Folder names are slugified `<title>` values, which match the `SCREEN_INDEX.md`
   "Title returned by Stitch" column.
2. **Render aspect ratio.** `screen.png` is a thumbnail capped at 1600 px on the long edge, so the
   short edge encodes the native aspect ratio recorded in the index's "Device / size" column. This
   reproduced the expected dimensions exactly for 66 of 73 screens, including six independent
   confirmations in the Phase 09 family alone (ST-065 1600x1524, ST-066 330, ST-067 322, ST-068 79,
   ST-069 64, ST-070 46).

All 73 logical IDs matched. Where the index recorded duplicate titles, the export disambiguates with a
`_1` or `_2` suffix, and the aspect ratio selects between them.

### ST-072 versus ST-073 — resolved on content, not on the suffix

This pair needed care: the two share a title, their thumbnails differ by one pixel (280 against 281),
and the suffix ordering is **not** ST-number order, so the suffix alone is not evidence. Getting it
backwards would implement a rejected design as canonical.

`audits/phase-09.md` rejects ST-072 "because its fresh artifact pollutes unrelated state chips with
retry-help copy". Diffing the two files shows `_2` injects `Reuses the same operation/request ID.`
into six unrelated chips — `Archived`, `invalid`, `permission denied` (twice), `failure`,
`remote failure`, and `current-operator self-disable routing to unavailable` — nine occurrences
against two in `_1`.

That is the audit's rejection reason exactly, and it agrees with the aspect-ratio result:

- `..._final_successor_suite_desktop_1` = **ST-073**, `CANONICAL CANDIDATE / VISUAL REVIEWED`
- `..._final_successor_suite_desktop_2` = **ST-072**, `NON-CANONICAL / REJECTED`

## Screens in the export but absent from SCREEN_INDEX.md

Four folders have no logical ID. Two are the "fetchable but unlisted" sources the handoff flagged as
canonical, so the export is strictly more complete than both `list_screens` and the index.

| Folder | Bytes | Identification |
|---|---:|---|
| `chilltent_pos_tenant_entry_states_mobile_final_phase_01_canonical_suite` | 17,163 | Phase 01 mobile successor `f852fbf76f1d403295e87c500f0ba12b`. Handoff: "directly fetchable but absent from both the project instance list and `list_screens`". Eight sections, no bottom nav, matching the handoff description. **Canonical Phase 01 mobile.** |
| `chilltent_pos_new_sale_mobile_browse` | 16,545 | Phase 03 recovered mobile browse `78f9a1cdd0c74850ad97f7ed06eb2548`. Handoff: "the previously lost mobile browse source is now recovered". |
| `chilltent_pos_settings_printing_mobile_phase_08_final_completion` | 44,539 | Phase 08 mobile final completion **v1**. ST-062 is the `v2` folder; this predecessor is unlisted. |
| `chilltent_pos_settings_printing_desktop_canonical_final_normalized` | 22,198 | Phase 08 desktop variant sharing ST-061's aspect ratio (171x1600). Lineage unresolved — Phase 10 item. |

## Known export defects and index disagreements

- **ST-044 is an empty screen.** `sales_receipts_shifts_returns_desktop_tablet/code.html` is 224 bytes
  and its entire body is the comment `No design needed based on guidelines`. It is already
  `NON-CANONICAL / SUPERSEDED`, so this blocks nothing, but it is not a usable reference.
- **`logo/` has no `code.html`**, only `screen.png` (1024x1024, matching ST-015).
- **Seven aspect-ratio disagreements** with the index's recorded native size. In each case the export
  render is taller than the index says, which suggests the index sizes are stale rather than that the
  join is wrong — the title slug is unambiguous for all seven. ST-049 and ST-050 are not 1600-capped
  at all, so those two were exported as full renders rather than thumbnails.

| Logical ID | Folder | Export render | Index expects |
|---|---|---|---|
| ST-006 | `receipt_printing_status` | 491x1600 | 525x1600 |
| ST-008 | `staff_directory` | 706x1600 | 780x950 |
| ST-009 | `review_order_pay` | 580x1600 | 637x1600 |
| ST-019 | `shift_reconciliation` | 567x1600 | 602x1600 |
| ST-036 | `chilltent_pos_new_sale_mobile_cart` | 534x1600 | 582x1600 |
| ST-049 | `..._desktop_suite_final_normalized` | 585x5203 | 293x1600 |
| ST-050 | `..._desktop_suite_complete_normalized` | 1920x6024 | 293x1600 |

## Full map

Status is carried over verbatim from `SCREEN_INDEX.md`; this map does not re-adjudicate any screen.
`NORMALIZED` records a completed edit operation, not visual approval.

| Logical ID | Export folder | `code.html` bytes | Domain | Status |
|---|---|---:|---|---|
| ST-001 | `new_sale_terminal_desktop_normalized` | 25003 | Checkout | NORMALIZED / RENDER REVIEW |
| ST-002 | `inventory_management_desktop_normalized` | 25433 | Catalog/stock | NORMALIZED / SUPERSEDED |
| ST-003 | `business_settings_desktop` | 19691 | Configuration | NON-CANONICAL / UNTOUCHED |
| ST-004 | `printer_receipt_management_desktop_normalized` | 31041 | Printing | NON-CANONICAL / UNTOUCHED |
| ST-005 | `staff_management_desktop_normalized` | 22045 | Staff | REVIEW / UNTOUCHED |
| ST-006 | `receipt_printing_status` | 16599 | Printing | REVIEW / UNTOUCHED |
| ST-007 | `inventory_stock_movements` | 22586 | Catalog/stock | NON-CANONICAL / SUPERSEDED |
| ST-008 | `staff_directory` | 17007 | Staff | REVIEW / UNTOUCHED |
| ST-009 | `review_order_pay` | 19764 | Checkout | NORMALIZED / SUPERSEDED |
| ST-010 | `printer_receipt_management_high_fidelity` | 29897 | Printing | CANONICAL CANDIDATE / RENDER REVIEW |
| ST-011 | `new_sale_products` | 20560 | Checkout | NORMALIZED / SUPERSEDED |
| ST-012 | `manager_dashboard_desktop_normalized` | 20388 | Home/navigation | NORMALIZED / SUPERSEDED |
| ST-013 | `shift_reconciliation_desktop` | 21476 | Reconciliation | NON-CANONICAL / UNTOUCHED |
| ST-014 | `staff_management_desktop` | 24845 | Staff | NORMALIZED / PARTIAL REVIEW |
| ST-015 | `logo` | 0 | Brand asset | REVIEW / UNTOUCHED |
| ST-016 | `manager_dashboard_desktop` | 20476 | Home/navigation | NON-CANONICAL / UNTOUCHED |
| ST-017 | `printer_receipt_management_desktop` | 31040 | Printing | NON-CANONICAL / UNTOUCHED |
| ST-018 | `analytical_reports_desktop` | 26128 | Reporting | REVIEW / UNTOUCHED |
| ST-019 | `shift_reconciliation` | 17767 | Reconciliation | NORMALIZED / RENDER REVIEW |
| ST-020 | `sales_analytics_reports` | 18639 | Reporting | NORMALIZED / RENDER REVIEW |
| ST-021 | `inventory_management_desktop` | 28309 | Catalog/stock | REVIEW / UNTOUCHED |
| ST-022 | `shift_reconciliation_desktop_normalized` | 21482 | Reconciliation | NORMALIZED / RENDER REVIEW |
| ST-023 | `manager_dashboard` | 15099 | Home/navigation | NORMALIZED / SUPERSEDED |
| ST-024 | `business_settings_desktop_normalized` | 19619 | Configuration | NORMALIZED / PARTIAL REVIEW |
| ST-025 | `analytical_reports_desktop_normalized` | 26134 | Reporting | NORMALIZED / PARTIAL REVIEW |
| ST-026 | `new_sale_terminal_desktop` | 25444 | Checkout | NON-CANONICAL / SUPERSEDED |
| ST-027 | `chilltent_pos_sign_in_states_desktop` | 15698 | Authentication | NORMALIZED / RENDER REVIEW |
| ST-028 | `chilltent_pos_sign_in_states_mobile` | 15800 | Authentication | CANONICAL CANDIDATE / VISUAL REVIEWED |
| ST-029 | `chilltent_pos_tenant_entry_states_mobile` | 10330 | Tenant entry | NORMALIZED / RENDER REVIEW |
| ST-030 | `chilltent_pos_tenant_entry_states_desktop` | 18361 | Tenant entry | NON-CANONICAL / SUPERSEDED |
| ST-031 | `chilltent_pos_tenant_entry_states_desktop_normalized` | 19895 | Tenant entry | CANONICAL CANDIDATE / VISUAL REVIEWED |
| ST-032 | `chilltent_pos_role_aware_home_navigation_desktop` | 18669 | Home/navigation | NORMALIZED / RENDER REVIEW |
| ST-033 | `chilltent_pos_role_aware_home_navigation_mobile` | 14881 | Home/navigation | NORMALIZED / RENDER REVIEW |
| ST-034 | `chilltent_pos_new_sale_desktop_tablet` | 22095 | Checkout | NORMALIZED / SUPERSEDED |
| ST-035 | `chilltent_pos_new_sale_desktop_tablet_normalized` | 26315 | Checkout | CANONICAL CANDIDATE / VISUAL REVIEWED |
| ST-036 | `chilltent_pos_new_sale_mobile_cart` | 22349 | Checkout | NORMALIZED / RENDER REVIEW |
| ST-037 | `chilltent_pos_catalog_stock_desktop` | 29587 | Catalog/stock | NON-CANONICAL / SUPERSEDED |
| ST-038 | `chilltent_pos_catalog_stock_mobile` | 33739 | Catalog/stock | NON-CANONICAL / SUPERSEDED |
| ST-039 | `chilltent_pos_catalog_stock_route_suite_desktop` | 30622 | Catalog/stock | NORMALIZED / RENDER REVIEW |
| ST-040 | `chilltent_pos_catalog_stock_mobile_route_suite` | 9218 | Catalog/stock | NORMALIZED / RENDER REVIEW |
| ST-041 | `chilltent_pos_reporting_reconciliation_desktop_suite` | 24460 | Reporting/reconciliation | NORMALIZED / RENDER REVIEW |
| ST-042 | `chilltent_pos_reporting_reconciliation_mobile_suite` | 10444 | Reporting/reconciliation | NON-CANONICAL / SUPERSEDED |
| ST-043 | `chilltent_pos_reporting_reconciliation_mobile_suite_normalized` | 21604 | Reporting/reconciliation | NORMALIZED / RENDER REVIEW |
| ST-044 | `sales_receipts_shifts_returns_desktop_tablet` | 224 | Sales/receipts/shifts/returns | NON-CANONICAL / SUPERSEDED |
| ST-045 | `sales_receipts_shifts_returns_mobile` | 11705 | Sales/receipts/shifts/returns | NON-CANONICAL / SUPERSEDED |
| ST-046 | `chilltent_pos_sales_receipts_returns_desktop_suite_normalized` | 11747 | Sales/receipts/shifts/returns | NON-CANONICAL / SUPERSEDED |
| ST-047 | `chilltent_pos_sales_receipts_returns_mobile_suite_normalized` | 22521 | Sales/receipts/shifts/returns | NON-CANONICAL / SUPERSEDED |
| ST-048 | `chilltent_pos_sales_receipts_returns_mobile_suite_final_normalized` | 25532 | Sales/receipts/shifts/returns | NORMALIZED / RENDER REVIEW |
| ST-049 | `chilltent_pos_sales_receipts_returns_desktop_suite_final_normalized` | 20826 | Sales/receipts/shifts/returns | NON-CANONICAL / SUPERSEDED |
| ST-050 | `chilltent_pos_sales_receipts_returns_desktop_suite_complete_normalized` | 35089 | Sales/receipts/shifts/returns | NORMALIZED / RENDER REVIEW |
| ST-051 | `chilltent_pos_staff_access_desktop_tablet_1` | 17652 | Staff/access | NON-CANONICAL / SUPERSEDED |
| ST-052 | `chilltent_pos_staff_access_mobile_1` | 12100 | Staff/access | NON-CANONICAL / SUPERSEDED |
| ST-053 | `chilltent_pos_staff_access_desktop_tablet_2` | 29401 | Staff/access | NORMALIZED / SUPERSEDED |
| ST-054 | `chilltent_pos_staff_access_mobile_2` | 17598 | Staff/access | NON-CANONICAL / SUPERSEDED |
| ST-055 | `chilltent_pos_staff_access_desktop_tablet_final_normalized` | 30399 | Staff/access | CANONICAL CANDIDATE / VISUAL REVIEWED |
| ST-056 | `chilltent_pos_staff_access_mobile_final_normalized` | 29318 | Staff/access | CANONICAL CANDIDATE / VISUAL REVIEWED |
| ST-057 | `chilltent_pos_settings_printing_desktop_tablet_normalized` | 12138 | Configuration/printing | NON-CANONICAL / SUPERSEDED |
| ST-058 | `chilltent_pos_settings_printing_mobile_normalized` | 14115 | Configuration/printing | NON-CANONICAL / SUPERSEDED |
| ST-059 | `chilltent_pos_settings_printing_desktop_canonical_phase_08_normalized` | 22195 | Configuration/printing | NORMALIZED / PARTIAL REVIEW |
| ST-060 | `chilltent_pos_settings_printing_mobile_final_normalized` | 34000 | Configuration/printing | NORMALIZED / PARTIAL REVIEW |
| ST-061 | `chilltent_pos_settings_printing_desktop_canonical_final_completion` | 25642 | Configuration/printing | NORMALIZED / RENDER REVIEW |
| ST-062 | `chilltent_pos_settings_printing_mobile_phase_08_final_completion_v2` | 34180 | Configuration/printing | NORMALIZED / RENDER REVIEW |
| ST-063 | `chilltent_pos_settings_printing_mobile_canonical` | 12307 | Configuration/printing | NON-CANONICAL / REJECTED |
| ST-064 | `chilltent_pos_settings_printing_desktop_canonical` | 14552 | Configuration/printing | NON-CANONICAL / REJECTED |
| ST-065 | `chilltent_pos_platform_operations_desktop_tablet_phase_09` | 19526 | Platform operations | NON-CANONICAL / SUPERSEDED |
| ST-066 | `chilltent_pos_platform_operations_mobile_phase_09` | 14835 | Platform operations | NON-CANONICAL / SUPERSEDED |
| ST-067 | `chilltent_pos_platform_operations_global_authority_phase_09_canonical_suite` | 50400 | Platform operations | NON-CANONICAL / SUPERSEDED |
| ST-068 | `chilltent_pos_platform_operations_mobile_phase_09_canonical_suite` | 35141 | Platform operations | NON-CANONICAL / SUPERSEDED |
| ST-069 | `chilltent_pos_platform_operations_mobile_canonical_phase_09_suite` | 41176 | Platform operations | NORMALIZED / SUPERSEDED |
| ST-070 | `chilltent_pos_platform_operations_mobile_phase_09_final_normalized_suite` | 53590 | Platform operations | CANONICAL CANDIDATE / VISUAL REVIEWED |
| ST-071 | `chilltent_pos_platform_operations_global_authority_final_canonical_suite_desktop` | 51637 | Platform operations | NORMALIZED / PARTIAL VISUAL REVIEW |
| ST-072 | `chilltent_pos_platform_operations_global_authority_final_successor_suite_desktop_2` | 53827 | Platform operations | NON-CANONICAL / REJECTED |
| ST-073 | `chilltent_pos_platform_operations_global_authority_final_successor_suite_desktop_1` | 53293 | Platform operations | CANONICAL CANDIDATE / VISUAL REVIEWED |

## Using this map

- Cite `docs/stitch/stitch_chilltent_pos_redesign_system/<folder>/code.html` as the design reference
  for a phase, alongside the logical ID.
- The export is a **local design input, not an approval**. A `RENDER REVIEW` or `PARTIAL REVIEW`
  status stays unapproved, and the pending-work lists in `LIVE_PHASE_HANDOFF.md` remain in force.
- The export cannot be refreshed from this session. If a screen must change, that is a Stitch mutation
  requiring both explicit user authorization and a session that has the connector.
