# Illustration coverage and subject audit

Baseline source audit: 2026-10-13, before the workflow illustration changes.
The tables below record the original gaps. They have now been addressed; see
[the implementation and previews](IMPLEMENTATION.md) for the resulting subjects.

The palette work improved existing SVGs. It did not give screens their own
subjects or replace text-only/default-box empty states. This audit checks both
the subject of existing artwork and the places that have no illustration.

## Findings that need dedicated subjects

| Screen/state | Current artwork | Finding | Suggested subject | Source |
| --- | --- | --- | --- | --- |
| Customers: no customers yet | `logistics.svg` | Delivery boxes and a trolley represent suppliers/stock, not customers. | Customers at a shop/customer address book | [Directory](../../../lib/customers/customer_directory_panel.dart:684) |
| Customers: nobody owes anything | `file-search.svg` | A document search does not express a clear credit balance. | Settled customer account | [Credit filter](../../../lib/customers/customer_directory_panel.dart:675) |
| Customer account: no entries | `file-search.svg` | Search artwork is used without a search. | Account ledger with customer identity | [Account](../../../lib/customers/customer_record_panel.dart:665) |
| Customer purchase history: no purchases | `file-search.svg` | No purchase is represented. | Customer with shopping bag/receipt history | [Purchases](../../../lib/customers/customer_record_panel.dart:1058) |
| Customer record missing | `file-search.svg` | Generic lookup illustration rather than a missing person record. | Unavailable customer card, or compact search cue | [Missing customer](../../../lib/customers/customer_record_panel.dart:163) |
| Returns: no returns on the selected day | `file-search.svg` | The search meaning is valid, but no returns subject appears. Mobile cards and desktop rows share it. | Returned parcel, reverse arrow and receipt | [Mobile](../../../lib/returns/return_feed_panel.dart:612), [desktop](../../../lib/returns/return_feed_panel.dart:774) |
| Sales: every sale was returned | `file-search.svg` | This is a completed return state, not an unsuccessful search. | Returned goods/fully refunded receipt | [Sales state](../../../lib/sales/sales_report_panel.dart:2672) |
| Production: no batches | `approve.svg` | An approval/check scene is unrelated to making stock. | Batch preparation/workbench/finished products | [Production](../../../lib/production/production_panel.dart:388) |
| Suppliers: no suppliers | `logistics.svg` | Related to deliveries, but gives the directory no identity distinct from delivery history. | Supplier/vendor contacts with delivery goods | [Suppliers](../../../lib/suppliers/supplier_directory_panel.dart:667) |
| Supplier record missing | `file-search.svg` | Generic lookup rather than a supplier record. | Unavailable supplier card | [Missing supplier](../../../lib/suppliers/supplier_record_panel.dart:175) |
| Audit: no events/no events on the selected day | `file-search.svg` | The unfiltered state is an empty history, not a search. A filtered state can reasonably use search imagery. | Business activity timeline/audit ledger | [Event list](../../../lib/audit/audit_log_panel.dart:544), [day filter](../../../lib/audit/audit_log_panel.dart:559) |
| Inventory categories: none/page empty | `my-files.svg` | Filing documents is loosely related, but it does not show product categories. | Product tags and grouped shelf items | [Categories](../../../lib/inventory/catalog_management_panel.dart:3855) |
| Inventory categories: read failed | `no-data.svg` inside `EmptyState` | A failed read is shown through the same visual pattern as an empty collection. | A clear unavailable/read-failed state; artwork must support that meaning | [Read failure](../../../lib/inventory/catalog_management_panel.dart:3848) |
| Notifications: nothing waiting | `approve.svg` | Generic approval gives this page little identity. | Clear notification inbox/receipt delivery tray | [Notifications](../../../lib/checkout/checkout_notifications_screen.dart:268) |
| Shift gate: shift closed on this device | `schedule.svg` | Same open-shift calendar scene is used for a closed shift. | Closed cash drawer/end-of-shift scene | [Closed gate](../../../lib/shift/shift_gate.dart:446) |

Filtered customer/supplier/staff searches may keep a shared search cue. Reuse
is appropriate when the *state* has the same meaning. Customer accounts,
production batches and fully returned sales need different subject matter.

## Default box used instead of a relevant illustration

These calls supply neither `illustration` nor `icon`, so `EmptyState` draws the
shared native `_EmptyMark` box. There are 10 call sites, including duplicated
mobile/desktop rendering of the same stock-review state.

| Screen/state | Suggested subject | Source |
| --- | --- | --- |
| Stock count: no local catalog | Shelf/catalog awaiting sync | [Count](../../../lib/inventory/stock_take_panel.dart:182) |
| Stock count: nothing to count | Empty shelf with count clipboard | [Count](../../../lib/inventory/stock_take_panel.dart:193) |
| Stock count review: no submitted counts | Stock-count clipboard/review tray | [Review](../../../lib/inventory/stock_take_review_panel.dart:429) |
| Stock count review: filters match no counts | Search within count sheets | [Mobile](../../../lib/inventory/stock_take_review_panel.dart:470), [desktop](../../../lib/inventory/stock_take_review_panel.dart:644) |
| Stock-count schedule: nobody to assign | Counter/staff assignment and calendar | [Schedule](../../../lib/inventory/stock_take_settings_panel.dart:518) |
| Price agreement permissions: no staff | Staff with price tag/approval authority | [Price permissions](../../../lib/checkout/checkout_price_agreement_panel.dart:288) |
| Settings: none available for this role | Settings/access restriction | [Settings](../../../lib/tenancy/tenant_settings_screen.dart:143) |
| Shift history: unavailable for this role | Restricted shift ledger | [Shift access](../../../lib/shift/shift_history_panel.dart:523) |
| Onboarding: session ended | Session/sign-in cue | [Session](../../../lib/tenancy/onboarding_flow.dart:1720) |

## Main screens and workflow states with no scene artwork

| Screen/state | Current treatment | Suggested subject/scale | Source |
| --- | --- | --- | --- |
| Main Inventory: no products / no search or filter matches | Text only, supplied to both product-list layouts | Shelves/products; product search variant | [Main inventory](../../../lib/inventory/catalog_management_panel.dart:1948) |
| Stock movements: no entries / no entries of a selected source | Text only | Goods moving in/out | [Movements](../../../lib/inventory/stock_movement_feed_panel.dart:325) |
| Manual stock adjustments: no entries, business or product scope | Text only | Product quantity correction | [Adjustments](../../../lib/inventory/stock_adjustment_feed_panel.dart:236) |
| Product stock ledger: no movements | Text only | Product with stock ledger | [Ledger](../../../lib/inventory/stock_product_ledger_panel.dart:266) |
| Product stock detail: no movement history | Text only | Compact stock movement record | [Stock detail](../../../lib/inventory/stock_adjustment_panel.dart:902) |
| Bulk catalog: no products on page | Text only | Product selection/import tray | [Bulk products](../../../lib/inventory/bulk_catalog_panel.dart:1357) |
| Bulk catalog: no categories to move products into | Text only | Compact tags/category grouping | [Bulk categories](../../../lib/inventory/bulk_catalog_panel.dart:1279) |
| Stock count due: prompt / blocking dialog | Text and actions; inline notice also has no scene | Compact shelf and count clipboard | [Due dialog](../../../lib/inventory/stock_take_gate.dart:384), [inline notice](../../../lib/inventory/stock_take_gate.dart:339) |
| Checkout cart: no sale items | Receipt glyph plus text on desktop; text on compact layout | Compact shopping basket/cart | [Desktop](../../../lib/checkout/checkout_cart_panel.dart:1782), [compact](../../../lib/checkout/checkout_cart_panel.dart:1845) |
| Checkout product browser: no cached products | Text only | Catalog awaiting device sync | [Offline catalog](../../../lib/checkout/checkout_cart_panel.dart:2866) |
| Checkout product browser: no matches | Text only | Compact product search | [Search](../../../lib/checkout/checkout_cart_panel.dart:2873) |
| Returns against one sale: no return history | Text only | Compact returned goods/history | [Sale returns](../../../lib/returns/return_history_panel.dart:736) |
| Unresolved reconciliation differences: none / no kind matches | Text only on mobile and desktop | Balanced ledger/reconciliation | [Differences](../../../lib/reporting/reconciliation_anomalies_panel.dart:583) |
| Shift corrections: no correction history, business or shift scope | Text only | Corrected ledger/history | [Corrections](../../../lib/reporting/shift_amendment_feed_panel.dart:255) |
| Reconciliation status: no queued runs for day | Text only inside the runs section | Compact check queue | [Runs](../../../lib/reporting/reconciliation_status_panel.dart:581) |
| Reconciliation run detail: missing run | Informational callout | Compact missing check record, if artwork is wanted | [Run detail](../../../lib/reporting/reconciliation_run_panel.dart:258) |
| Print queue: no waiting receipts | Text only inside Notifications | Compact printer/receipt cue | [Print queue](../../../lib/checkout/checkout_print_queue_panel.dart:152) |
| Supplier delivery form: no added products | Text only | Compact delivery invoice/items | [Delivery form](../../../lib/suppliers/supplier_delivery_panel.dart:607) |
| Production batch cost breakdown: no costs | Text inside a card; figures remain above | Compact cost sheet, if artwork is wanted | [Cost breakdown](../../../lib/production/production_cost_screen.dart:91) |
| Business selection: no memberships | Storefront glyph, text and Retry | Business/shop access scene | [Selector](../../../lib/tenancy/tenant_routing_shell.dart:2078) |
| USB printer picker: no discovered helper printers | USB informational callout | Compact printer connection cue | [USB](../../../lib/checkout/checkout_usb_printer_panel.dart:540) |
| Bluetooth printer picker: search finds no devices | Informational callout | Compact nearby-printer search cue | [Bluetooth](../../../lib/checkout/checkout_bluetooth_printer_panel.dart:780) |

These are confirmed places without scene illustrations, rather than a mandate
to put a large illustration into every section. The print queue, cost breakdown,
delivery form and printer pickers contain other content; compact artwork or the
existing concise notice may suit their space better.

## Full-page empty states using only a glyph

All 13 `EmptyState(icon: ...)` call sites are listed below. Their icons match the
meaning, but they have no authored scene artwork.

| Screen/state | Glyph | Source |
| --- | --- | --- |
| Email receipts: none sent | Mail | [Email](../../../lib/email_receipts/email_receipts_screen.dart:434) |
| WhatsApp receipts: none sent | Chat | [WhatsApp](../../../lib/whatsapp/e_receipt_settings_panel.dart:554) |
| Platform alerts: no alerts | Notification bell | [Alerts](../../../lib/tenancy/platform_console_activity.dart:87) |
| Platform activity: no events | Timeline | [Activity](../../../lib/tenancy/platform_console_activity.dart:389) |
| Platform businesses: no search matches | Search | [Search](../../../lib/tenancy/platform_console_businesses.dart:292) |
| Platform businesses: none archived | Box/archive | [Archived](../../../lib/tenancy/platform_console_businesses.dart:306) |
| Platform businesses: none suspended | Pause | [Suspended](../../../lib/tenancy/platform_console_businesses.dart:311) |
| Platform businesses: nothing needs attention | Check | [Attention](../../../lib/tenancy/platform_console_businesses.dart:316) |
| Platform businesses: none exist | Storefront | [Businesses](../../../lib/tenancy/platform_console_businesses.dart:321) |
| Platform business detail: deleted/missing | Storefront | [Missing business](../../../lib/tenancy/platform_console_businesses.dart:588) |
| Platform accounts: no search matches | Search | [Account search](../../../lib/tenancy/platform_console_people.dart:166) |
| Platform accounts: no accounts fitting filter | Group | [Accounts](../../../lib/tenancy/platform_console_people.dart:178) |
| Platform account detail: missing account | Person | [Missing account](../../../lib/tenancy/platform_console_people.dart:532) |

## Existing reuse that fits, with optional tailoring

| Screen family | Existing asset | Assessment |
| --- | --- | --- |
| Expenses and expense categories | `empty-wallet.svg` | Fits spending/money; a purpose-built expense ledger would be an optional refinement. |
| Expense/receipt-branding access restrictions | `access-denied.svg` | Appropriate shared access state. |
| Staff directory | `team.svg`; `file-search.svg` for search | Team is a relevant subject; shared search can remain. |
| Supplier delivery history | `logistics.svg` | Delivery/stock movement imagery fits. |
| Sales report empty day | `no-data.svg` | Generic documents fit records; a till/receipt illustration would give Sales a stronger identity. |
| Sales receipt lookup in the active Sales report | `file-search.svg` | Appropriate search cue; a receipt-specific version is optional. |
| Weekly top-items and transaction charts | `no-data.svg` | Suitable generic empty data, but not custom chart artwork. |
| Monthly report empty month | `no-data.svg` | Suitable generic records; report/chart tailoring is optional. |
| Monthly report future month | `calendar.svg` | Calendar is directly relevant. |
| Open-shift gate/dialog and shift history | `schedule.svg` | Relevant time/shift subject; a cash-drawer version would distinguish shifts from stock-count scheduling. |
| Shift close outcome | `approve.svg` / `access-denied.svg` | Shared completion/refusal meaning is valid. |
| Onboarding verification | `mail-sent.svg` | Directly relevant. |
| Onboarding completion | `approve.svg` | Shared successful completion meaning is valid. |

## Repainted assets that the current app does not show

- `empty-cart.svg`: no production call site, despite Checkout having an empty cart.
- `printing-invoices.svg`: no production call site, despite having a print queue.
- `empty.svg`: referenced by the retained `TenantCatalogScreen`/panel, but that
  screen has no instantiation elsewhere in `lib`. Main composes
  `TenantCatalogManagementScreen` for Inventory instead (`lib/main.dart:2076`).

Two more retained UI implementations can mislead a source-only illustration
count: `TenantSaleHistoryScreen` has `no-data.svg`, and the old platform lifecycle
screen has `approve.svg`. Their screen constructors also have no callers elsewhere
in `lib`. The active sales screen and platform console have their own states.

`TenantReceiptLookupPanel` has a text-only not-found result
(`lib/sales/receipt_lookup_panel.dart:235`); the current main routing instead sends
receipt lookup to the Sales report (`lib/main.dart:1740`). Keep that retained
implementation separate from the active receipt-not-found state above.

## Scope and evidence

The explicit state inventory contains 61 `EmptyState`/direct `AppIllustration`
call sites across nonlegacy source: 38 with SVG artwork, 10 with the default box,
and 13 with a glyph. These count code locations, including mobile/desktop
duplicates and the four SVG locations inside retained, uninstantiated screens;
they are not counts of unique live screens.

The tables above also include explicit empty lists, missing records and workflow
prompts implemented without either component. Live forms, populated tables,
charts, product photos and loading/error notices are evaluated by their purpose;
having no decorative scene in a normal form is not itself a coverage defect.

Evidence is a static review of current widgets, their empty conditions and the
route composition in `lib/main.dart`. No device traversal or UI changes were
performed. `coverage-call-sites.json` records the extracted call-site inventory.

Recommended first set: customers/accounts, returns, inventory/products, stock
count/review, production, product categories, stock movements/adjustments, then
reconciliation and notification/receipt delivery scenes.

## Explicit component call-site inventory

| Location | State/title expression | Artwork |
| --- | --- | --- |
| [lib/audit/audit_log_panel.dart:544](../../../lib/audit/audit_log_panel.dart:544) | page.isEventScoped | file-search.svg |
| [lib/audit/audit_log_panel.dart:559](../../../lib/audit/audit_log_panel.dart:559) | 'Nothing from ${_dayLabel(day!)} on this page' | file-search.svg |
| [lib/checkout/checkout_notifications_screen.dart:268](../../../lib/checkout/checkout_notifications_screen.dart:268) | 'No notifications available' | approve.svg |
| [lib/checkout/checkout_price_agreement_panel.dart:288](../../../lib/checkout/checkout_price_agreement_panel.dart:288) | 'Nobody to choose yet' | Default box |
| [lib/customers/customer_directory_panel.dart:675](../../../lib/customers/customer_directory_panel.dart:675) | 'Nobody owes you anything' | file-search.svg |
| [lib/customers/customer_directory_panel.dart:684](../../../lib/customers/customer_directory_panel.dart:684) | hasQuery ? 'No matching customers' : 'No customers yet' | file-search.svg, logistics.svg |
| [lib/customers/customer_record_panel.dart:163](../../../lib/customers/customer_record_panel.dart:163) | 'This customer is not in this business' | file-search.svg |
| [lib/customers/customer_record_panel.dart:665](../../../lib/customers/customer_record_panel.dart:665) | 'Nothing on their account yet' | file-search.svg |
| [lib/customers/customer_record_panel.dart:1058](../../../lib/customers/customer_record_panel.dart:1058) | 'No purchases yet' | file-search.svg |
| [lib/email_receipts/email_receipts_screen.dart:434](../../../lib/email_receipts/email_receipts_screen.dart:434) | 'No receipts sent yet' | Icons.mail_outline |
| [lib/expenses/expense_category_panel.dart:189](../../../lib/expenses/expense_category_panel.dart:189) | 'Nothing under ${category.label.toLowerCase()}' | empty-wallet.svg |
| [lib/expenses/expense_panel.dart:447](../../../lib/expenses/expense_panel.dart:447) | 'Expenses are not shown for this role' | access-denied.svg |
| [lib/expenses/expense_panel.dart:755](../../../lib/expenses/expense_panel.dart:755) | 'Nothing recorded ${rangeLabel.toLowerCase()}' | empty-wallet.svg |
| [lib/inventory/catalog_management_panel.dart:3848](../../../lib/inventory/catalog_management_panel.dart:3848) | 'Categories could not be read' | no-data.svg |
| [lib/inventory/catalog_management_panel.dart:3855](../../../lib/inventory/catalog_management_panel.dart:3855) | _page == 0 | my-files.svg |
| [lib/inventory/stock_take_panel.dart:182](../../../lib/inventory/stock_take_panel.dart:182) | 'No catalog on this device yet' | Default box |
| [lib/inventory/stock_take_panel.dart:193](../../../lib/inventory/stock_take_panel.dart:193) | 'Nothing to count' | Default box |
| [lib/inventory/stock_take_review_panel.dart:429](../../../lib/inventory/stock_take_review_panel.dart:429) | 'No counts yet' | Default box |
| [lib/inventory/stock_take_review_panel.dart:470](../../../lib/inventory/stock_take_review_panel.dart:470) | 'No counts match' | Default box |
| [lib/inventory/stock_take_review_panel.dart:644](../../../lib/inventory/stock_take_review_panel.dart:644) | 'No counts match' | Default box |
| [lib/inventory/stock_take_settings_panel.dart:518](../../../lib/inventory/stock_take_settings_panel.dart:518) | 'Nobody to ask yet' | Default box |
| [lib/production/production_panel.dart:388](../../../lib/production/production_panel.dart:388) | 'No batches yet' | approve.svg |
| [lib/reporting/monthly_report_panel.dart:329](../../../lib/reporting/monthly_report_panel.dart:329) | 'This month has not started' | calendar.svg |
| [lib/reporting/monthly_report_panel.dart:341](../../../lib/reporting/monthly_report_panel.dart:341) | 'Nothing was recorded in ${report.month.label}' | no-data.svg |
| [lib/reporting/weekly_report_charts.dart:272](../../../lib/reporting/weekly_report_charts.dart:272) | 'No sales this week' | no-data.svg |
| [lib/reporting/weekly_report_charts.dart:516](../../../lib/reporting/weekly_report_charts.dart:516) | 'No transactions this week' | no-data.svg |
| [lib/returns/return_feed_panel.dart:612](../../../lib/returns/return_feed_panel.dart:612) | 'No returns on $recordedOn' | file-search.svg |
| [lib/returns/return_feed_panel.dart:774](../../../lib/returns/return_feed_panel.dart:774) | 'No returns on $recordedOn' | file-search.svg |
| [lib/sales/sales_report_panel.dart:2571](../../../lib/sales/sales_report_panel.dart:2571) | 'Receipt not found' | file-search.svg |
| [lib/sales/sales_report_panel.dart:2672](../../../lib/sales/sales_report_panel.dart:2672) | allReturned | file-search.svg, no-data.svg |
| [lib/sales/sale_history_panel.dart:346](../../../lib/sales/sale_history_panel.dart:346) | 'No sales yet' | no-data.svg |
| [lib/shift/shift_gate.dart:432](../../../lib/shift/shift_gate.dart:432) | 'No shift is open' | schedule.svg |
| [lib/shift/shift_gate.dart:446](../../../lib/shift/shift_gate.dart:446) | 'Shift closed on this device' | schedule.svg |
| [lib/shift/shift_gate.dart:574](../../../lib/shift/shift_gate.dart:574) |  | schedule.svg |
| [lib/shift/shift_history_panel.dart:523](../../../lib/shift/shift_history_panel.dart:523) | 'Shift history is not available here' | Default box |
| [lib/shift/shift_history_panel.dart:692](../../../lib/shift/shift_history_panel.dart:692) | 'No closed shifts on this day' | schedule.svg |
| [lib/shift/shift_panel.dart:825](../../../lib/shift/shift_panel.dart:825) |  | approve.svg, access-denied.svg |
| [lib/suppliers/supplier_delivery_history.dart:297](../../../lib/suppliers/supplier_delivery_history.dart:297) | 'No deliveries yet' | logistics.svg |
| [lib/suppliers/supplier_directory_panel.dart:667](../../../lib/suppliers/supplier_directory_panel.dart:667) | _hasQuery ? 'No matching suppliers' : 'No suppliers yet' | file-search.svg, logistics.svg |
| [lib/suppliers/supplier_record_panel.dart:175](../../../lib/suppliers/supplier_record_panel.dart:175) | 'This supplier is not in this business' | file-search.svg |
| [lib/tenancy/onboarding_flow.dart:1529](../../../lib/tenancy/onboarding_flow.dart:1529) | onboarding-verify-illustration | mail-sent.svg |
| [lib/tenancy/onboarding_flow.dart:1720](../../../lib/tenancy/onboarding_flow.dart:1720) | 'Your session has ended' | Default box |
| [lib/tenancy/onboarding_flow.dart:1763](../../../lib/tenancy/onboarding_flow.dart:1763) | onboarding-complete-illustration | approve.svg |
| [lib/tenancy/platform_console_activity.dart:87](../../../lib/tenancy/platform_console_activity.dart:87) | 'No alerts' | Icons.notifications_none |
| [lib/tenancy/platform_console_activity.dart:389](../../../lib/tenancy/platform_console_activity.dart:389) | 'Nothing here yet' | Icons.timeline |
| [lib/tenancy/platform_console_businesses.dart:292](../../../lib/tenancy/platform_console_businesses.dart:292) | 'No business matches “$query”' | Icons.search |
| [lib/tenancy/platform_console_businesses.dart:306](../../../lib/tenancy/platform_console_businesses.dart:306) | 'No archived businesses' | Icons.inventory_2_outlined |
| [lib/tenancy/platform_console_businesses.dart:311](../../../lib/tenancy/platform_console_businesses.dart:311) | 'No suspended businesses' | Icons.pause_circle_outline |
| [lib/tenancy/platform_console_businesses.dart:316](../../../lib/tenancy/platform_console_businesses.dart:316) | 'Nothing needs attention' | Icons.check_circle_outline |
| [lib/tenancy/platform_console_businesses.dart:321](../../../lib/tenancy/platform_console_businesses.dart:321) | 'No businesses yet' | Icons.storefront_outlined |
| [lib/tenancy/platform_console_businesses.dart:588](../../../lib/tenancy/platform_console_businesses.dart:588) | 'This business no longer exists' | Icons.storefront_outlined |
| [lib/tenancy/platform_console_people.dart:166](../../../lib/tenancy/platform_console_people.dart:166) | 'Nobody matches “$_query”' | Icons.search |
| [lib/tenancy/platform_console_people.dart:178](../../../lib/tenancy/platform_console_people.dart:178) | 'Nobody here' | Icons.group_outlined |
| [lib/tenancy/platform_console_people.dart:532](../../../lib/tenancy/platform_console_people.dart:532) | 'No account has this ID' | Icons.person_outline |
| [lib/tenancy/platform_tenant_lifecycle.dart:855](../../../lib/tenancy/platform_tenant_lifecycle.dart:855) | 'No active or suspended businesses' | approve.svg |
| [lib/tenancy/tenant_branding_panel.dart:403](../../../lib/tenancy/tenant_branding_panel.dart:403) | 'Receipt branding is not shown for this role' | access-denied.svg |
| [lib/tenancy/tenant_catalog.dart:802](../../../lib/tenancy/tenant_catalog.dart:802) | 'No categories yet' | empty.svg |
| [lib/tenancy/tenant_catalog.dart:850](../../../lib/tenancy/tenant_catalog.dart:850) | 'No products yet' | empty.svg |
| [lib/tenancy/tenant_settings_screen.dart:143](../../../lib/tenancy/tenant_settings_screen.dart:143) | 'No settings are shown for this role' | Default box |
| [lib/tenancy/tenant_staff_directory.dart:1458](../../../lib/tenancy/tenant_staff_directory.dart:1458) | _hasQuery ? 'No matching staff' : 'No staff yet' | file-search.svg, team.svg |
| [lib/whatsapp/e_receipt_settings_panel.dart:554](../../../lib/whatsapp/e_receipt_settings_panel.dart:554) | 'No receipts sent yet' | Icons.chat_outlined |
