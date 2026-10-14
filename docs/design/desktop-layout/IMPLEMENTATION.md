# Desktop layout changes

The expanded audit covers 21 screens/tabs plus shared components. Desktop
composition now changes across the audited workflows instead of only increasing
the width of a phone layout.

## Implemented

- Add/Edit Product: media alongside fields; compact action footer.
- Product framing: canvas alongside controls.
- Network, Bluetooth, USB and system printing: status/current device alongside
  setup, discovery or test controls. Both USB transports are included.
- Branding: logo alongside name and slogan.
- Bulk catalog: independently scrolling controls and preview/report panes;
  desktop result table with full row explanations kept visible.
- Stock-count entry: progress beside counting rows. Recorded stock remains
  hidden from the counter. Count review: aligned difference table.
- Customer Purchases: shared Sales table with no added write actions.
- Email and WhatsApp sent receipts: recipient, receipt, delivery status, trigger
  and time columns; delivery reasons remain visible. Settings retain form width.
- Production entry and batch costs, supplier delivery and reconciliation run:
  related sections occupy neighboring regions on desktop.
- Sales totals: summary and breakdown/comparison sections share the desktop.
- Settings: two-column destination layout.
- Notifications: source and time form a separate desktop metadata column.

## Shared components

`AppWorkspace` measures its available width, retaining vertical reading order
when constrained. `AppTabs` now measures the host width rather than the window.
It retains the existing segmented and scrolling tab designs, keyboard traversal
and selection state. Pagination segments contract within narrower panes.

`showAppSheet` opens a centered desktop dialog and retains phone bottom sheets.
Its caller still controls dismissal, receives the scroll controller and owns
the form state and submit behavior. Desktop dialogs provide the existing close
control and omit the drag handle. Fitted informational bottom sheets retain
their existing presentation.

Existing controllers, repository calls, validation, permissions and callbacks
are retained. No backend, routing conditions or financial calculations changed.

## Verification

Validation includes workflow tests, responsive component geometry, desktop
dialog draft/dismissal behavior, and separate phone/desktop receipt history
checks. Static screenshot captures exercise real screen widgets with fixtures;
they establish layout appearance, not a live backend or printer-device run.

Results: **536 tests across 27 focused test files passed**, with affected groups
rerun after fixes. **44 phone/desktop captures passed**. Targeted analysis of
the 26 changed application files and four test files was clean; the final bulk
and network-printer refinements were also analyzed separately. `git diff --check`
passed. No live backend or physical-printer run was performed.

Representative desktop captures:

- [Add Product](../../../screenshots/web/18h-add-a-product.png)
- [Edit Product](../../../screenshots/web/19c-correct-a-product-image.png)
- [Network printer](../../../screenshots/web/36b-printer-configured.png)
- [USB printer](../../../screenshots/web/36l-printer-usb-in-use.png)
- [Bulk preview](../../../screenshots/web/20b-bulk-report-previewed.png)
- [Count review](../../../screenshots/web/38b-the-count.png)
- [Production](../../../screenshots/web/production-record.png)
