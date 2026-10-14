# Large-screen layout audit

Audited the current Flutter source on 2026-10-13, tracing screen wrappers,
shared layout components and entry points from `main.dart` and the routing shell.
Existing desktop captures were inspected as visual references; these were not
new device runs or fresh captures for this audit.

The initial pass found **5 clear cases** where a populated desktop page or tab retains the
mobile vertical composition, and **8 additional screens/tabs** that retain a
720px capped mobile composition. Those eight are opportunities for a desktop
layout, rather than evidence of uncontrolled full-window stretching.

The expanded pass also includes **8 more screens/tabs**: Add Product, Edit
Product, product-image framing, branding, and the Network, Bluetooth, USB and
Print dialog printer modes. This brings the screen/tab scope to **21**, with
shared components tracked separately. The initial classification of product
forms as already adapted was too generous: paired fields did not change their
overall one-column composition.

## Expanded scope and implementation

Implementation is complete; validation results are recorded in
[IMPLEMENTATION.md](IMPLEMENTATION.md).

| Additional surface | Finding | Change |
| --- | --- | --- |
| Add Product and Edit Product | `_ProductFormLayout` explicitly kept one column at every width; the route capped it at 720px. | Product media beside editable fields, within the record-width desktop host; compact footer actions. |
| Product image framing | Canvas, controls and footer stayed vertically stacked. | Desktop canvas beside scrollable controls. |
| Network printer | Helper/status, address, port, paper and testing stacked in a reading-width host. | Connection/status beside configuration and test actions. |
| Bluetooth printer | Current printer and discovery/device list stacked. | Current printer/status beside discovery and available devices. |
| USB printer | Current device/helper status and choosing another device stacked, for both helper and browser transports. | Separate standing and device-selection regions. |
| Print dialog mode | Status, paper width, test and help stacked. | Standing information beside configuration and test controls. |
| Branding | Logo, name, slogan and save action stacked. | Logo beside identity fields. |

Shared components also needed inspection:

- `AppTabs`: already hugs two labels on wide hosts and scrolls larger tab sets;
  width decisions now use the actual host constraint rather than window width.
- `showAppSheet`: desktop forms now open in centered dialogs, preserving the
  caller's dismissal policy and scroll-controller contract. Phones keep sheets.
- `Pagination`: desktop navigation segments must contract inside narrower
  workspace panes rather than assuming the full window is available.
- `AppWorkspace`: shared constrained two-region composition, with existing
  reading order retained on compact hosts.
- `AppNotificationFeed`: desktop source/time metadata occupies an aligned
  separate column; expansion, dismissal and actions remain available.
- Form actions: product and stock-count desktop actions no longer request
  equal full-width expansion.

## Clear cases

| Screen or tab | Current large-screen behavior | Evidence | Suggested desktop treatment |
| --- | --- | --- | --- |
| Bulk catalog changes/import | The same long `ListView` holds controls, product checkboxes, preview and result cards at every width. The 1200px cap spreads product text and checkboxes far apart. Preview results remain individual stacked cards. | [Body](../../../lib/inventory/bulk_catalog_panel.dart:1086), [product selection](../../../lib/inventory/bulk_catalog_panel.dart:1365), [preview rows](../../../lib/inventory/bulk_catalog_panel.dart:1530), [existing desktop capture](../../../screenshots/web/20b-bulk-report-previewed.png) | Selection table and aligned preview/result columns; compact controls and a clearly separated review area. |
| Stock-count detail: “The count” | The review index has a desktop table, but opening one count returns to stacked product cards and a wide pinned accept button. The detail screen has a 1200px cap and no desktop branch for its difference lines. | [Detail frame](../../../lib/inventory/stock_take_review_panel.dart:804), [detail body](../../../lib/inventory/stock_take_review_panel.dart:919), [difference cards](../../../lib/inventory/stock_take_review_panel.dart:959), [existing desktop capture](../../../screenshots/web/38b-the-count.png) | A difference table with Product, Counted, Recorded and Difference columns, plus a compact review/action area. Keep the current difference ordering and acceptance semantics. |
| Customer record: Purchases tab | The account statement gains a desktop table, but purchase history always loops over `TenantSaleCard` inside a `Column`. The containing customer page expands to the desktop record surface. | [Purchases](../../../lib/customers/customer_record_panel.dart:1032), [sale cards](../../../lib/customers/customer_record_panel.dart:1061), [statement desktop branch](../../../lib/customers/customer_record_panel.dart:669) | Purchase table using the same sale columns and receipt-opening behavior as Sales. |
| Notifications | The populated page is always a `ListView` containing `AppNotificationFeed`, capped at 1200px. Feed items keep the same expandable mobile row structure. The page's `LayoutBuilder` centers only the empty state. | [Page cap](../../../lib/checkout/checkout_notifications_screen.dart:85), [populated feed](../../../lib/checkout/checkout_notifications_screen.dart:278), [shared row](../../../lib/ui/notification_feed.dart:227) | A compact desktop feed with aligned source/time/status/actions, or a feed beside the selected notification's details. |
| Sales totals | The page always stacks takings, payment breakdown, day/shift figures and profit cards in one `ListView` at a 1200px cap. `StatRow` adapts the tiles inside some cards, but the main sections never become a desktop composition. | [Body](../../../lib/reporting/sales_totals_panel.dart:467), [section cards](../../../lib/reporting/sales_totals_panel.dart:622), [existing desktop capture](../../../screenshots/web/26-sales-totals.png) | A dashboard with related summary/payment/profit sections beside each other and aligned shift comparisons. Preserve every financial caveat and role restriction. |

## Capped mobile compositions

These pages stop growing at 720px, so their main symptom is a narrow, tall
workflow surrounded by unused space. A basic one-column form can be correct;
these are the richer workflows and histories worth reviewing.

| Screen or tab | What stays mobile | Evidence | Suggested desktop treatment |
| --- | --- | --- | --- |
| Count stock: entry screen | One product card per row and a full-width hand-in button; the same composition at every width. This is separate from the already adapted count-review index. | [720px frame](../../../lib/inventory/stock_take_panel.dart:89), [body](../../../lib/inventory/stock_take_panel.dart:205), [existing desktop capture](../../../screenshots/web/16i-stock-count.png) | Compact counting rows/table and a separate progress/action area. Keep the blind-count rule: do not expose recorded stock to the person counting. |
| Receive delivery | Supplier, reference, line cards and submit action remain one vertical list. Its width check changes padding, not the composition. | [Frame](../../../lib/suppliers/supplier_delivery_panel.dart:194), [body](../../../lib/suppliers/supplier_delivery_panel.dart:537), [existing desktop capture](../../../screenshots/web/supplier-delivery-form.png) | Supplier/reference alongside a delivery-lines editor; aligned product/quantity/cost columns. |
| Record production | Product, quantity, costs, calculated figures and completion action remain in one scrolling list. Width changes only the inset. Description/amount rows have the same structure on phone and desktop. | [Frame](../../../lib/production/production_form_panel.dart:153), [body](../../../lib/production/production_form_panel.dart:502), [existing desktop capture](../../../screenshots/web/production-record.png) | Product/quantity and batch summary beside the cost editor. |
| Production batch costs | Summary tiles adapt, but costs and batch metadata stay vertically stacked in the same reading-width page. | [Frame and content](../../../lib/production/production_cost_screen.dart:69) | Cost breakdown beside batch metadata and unit-cost summary. |
| Reconciliation run detail | Status, counts, timestamps and explanations stay in one reading-width list. | [Frame](../../../lib/reporting/reconciliation_run_panel.dart:63), [body](../../../lib/reporting/reconciliation_run_panel.dart:197), [existing desktop capture](../../../screenshots/web/29-one-reconciliation-run.png) | Run summary beside execution/details, with aligned labeled facts. |
| Settings index | The navigation choices remain one column of `_SettingRow` widgets; no desktop groups or grid. Individual setting forms should be assessed separately. | [Frame](../../../lib/tenancy/tenant_settings_screen.dart:265), [index](../../../lib/tenancy/tenant_settings_screen.dart:337), [existing desktop capture](../../../screenshots/web/16c-settings-index.png) | Grouped settings navigation or a settings sidebar and selected panel. |
| Email receipts: Sent receipts tab | Settings and history share the 720px cap; sent receipts always use repeated `_DeliveryRow` widgets. Width checks mainly adjust insets and empty-state positioning. | [Frame](../../../lib/email_receipts/email_receipts_screen.dart:150), [sent list](../../../lib/email_receipts/email_receipts_screen.dart:446) | Desktop receipt/delivery-status table; keep the simple settings form at reading width. |
| WhatsApp receipts: Sent receipts tab | The history keeps the mobile receipt-row composition inside the same reading-width tab host. Local row layout adjustments do not create a desktop history view. | [Frame](../../../lib/whatsapp/e_receipt_settings_panel.dart:204), [sent list](../../../lib/whatsapp/e_receipt_settings_panel.dart:569) | Desktop receipt/delivery-status table; keep consent, recipient and status meaning intact. |

## Screens already adapting

These were checked to avoid treating every `Column` or `ListView` as a fault:

| Area | Existing adaptation |
| --- | --- |
| Checkout | Separate product/cart panes and desktop cart rows; responsive product grid. |
| Inventory | Desktop product table with wider filter/action arrangement. Add/edit forms belong to the expanded scope above; paired fields alone were insufficient. |
| Customers | Desktop directory and account-statement tables. The Purchases tab is the remaining exception above. |
| Suppliers | Desktop directory and supplier-delivery history tables. The receive-delivery form is the remaining workflow above. |
| Production | Desktop batch table; the entry and cost-detail pages are the remaining workflows above. |
| Sales and returns | Desktop Sales report and business return-history tables. |
| Expenses | Desktop expense and category-detail tables. |
| Stock counts | Desktop count-review index; entry and individual count details are the exceptions above. |
| Stock movements/adjustments/product ledger | Shared `RecordList` switches from phone cards to larger-screen forms/tables. |
| Staff, business audit and shift history | Desktop record tables. |
| Daily summary and reconciliation | Desktop daily-summary, differences and queued-run tables; individual run detail is listed above. |
| Shift corrections | Shared responsive `RecordList`. |
| Weekly report | Explicit desktop composition with side-by-side sections and responsive metric/filter layout. |
| Monthly report | Responsive `StatRow` becomes a multi-column summary. Its sparse desktop content is a report-content limitation, not a stretched mobile list. |
| Platform console | Responsive overview grid, compact/desktop record rows, responsive facts and side-by-side detail sections. |
| Business home | Responsive destination/dashboard grids and desktop navigation. |

Authentication, onboarding, business selection, simple settings and small
dialogs intentionally use constrained reading/form layouts. Their lack of a
table or a second pane alone does not establish a desktop defect. Retained
legacy screens and uninstantiated standalone lookup/queue screens were excluded
from the count.

The shared mechanisms were checked explicitly: `AppScaffold` caps reading pages
at 720px and record pages at 1200px; a cap alone does not change composition.
`RecordList` changes form by screen breakpoint, `RecordSheet` supplies desktop
tables, and `StatRow` measures and reflows summary tiles. Finding no local
`LayoutBuilder` therefore was not used as proof that a page fails to adapt.

Start with Bulk catalog, individual count details and customer Purchases, where
repeated comparable records still use mobile rows/cards despite desktop space.
Notifications and Sales totals follow. Then review the capped workflows with
the product owner to decide where a table, separate summary or side panel is
useful.
