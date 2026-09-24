# Supplier receiving & production — build plan

Written 2026-09-24 on `feature/suppliers-production`, before any code, from the decisions in
[`supplier-production-mvp-response.md`](supplier-production-mvp-response.md) and the conversation
that followed it. This is the working plan for one unsupervised run; it is not a record of what
shipped. The developer outranks it.

**Standing constraints for this run:** no deploys of any kind; local commits after each slice;
verification is automated only — functions tests, rules tests on the local emulator, Flutter
unit/widget tests, the screenshot harness. No APK, no device run. Existing designs under
`docs/design/**` (staff, expenses, stock counts, report sheet) are the visual reference; there are
no new artboards.

**Baseline at `ea66eff`:** functions 602/602, Flutter 3626/3626, analyzer 0 errors / 109 warnings
/ 386 infos. Nothing below may add an analyzer error or a warning in a touched file.

---

## Decisions this plan builds on

| Area | Decision |
|---|---|
| Cost | Every cost-bearing event writes `products.cost`. No second cost field. |
| Cost type | New product field `costType`: `purchased` \| `produced`, labelled *Bought in* / *Made here*. Display only. Absent = purchased. Not a money field, so managers may set it. |
| Roles | Owner, admin, manager: suppliers, deliveries, production. Direct cost edits stay owner/admin. Cashiers: none of it. |
| Suppliers | Own collection, server-written, case/space-folded duplicate names refused, inactive not deleted. |
| Deliveries | Their **own record** — one supplier, one reference, many product lines. Started from Suppliers. Sent in pages of 16 lines. Restock / `adjustStock` untouched. |
| Production | One product per batch, completed in one step, no drafts. ≥1 expense row, every row > 0. Cost per unit rounded half-up to the cent; a unit cost that rounds to zero is refused. Batches are never edited. |
| Home | Suppliers and Production tiles in the Inventory group, always shown to the three roles. Printer tile removed (Settings → Printer tab is unchanged). |
| Reports | Report sheet gains an optional subject dropdown beside the period (all / one supplier; all / one product). Supplier report and production report. |

---

## Design points the code forced (from mapping the queue, rules and reports)

1. **A refused queued record blocks its whole `targetPath` group for good, and nothing in the app
   can acknowledge it today.** So:
   - Production and delivery records get **their own document path** (`production_batches/{id}`,
     `supplier_deliveries/{id}`), not the product path — a refusal strands that one record, not
     every later stock change to the product.
   - The server refuses **only malformed input**. Anything that can change while a record waits
     offline (product retired, supplier made inactive, product switched to *Bought in*) is checked
     on the form only, never on the server.
2. **One queued record can only project onto one document today.** Both new kinds touch the
   product *and* their own record, so the overlay gains a "paths this record touches" step used by
   `getDocument`, `getCollectionPage` and `searchTenantProducts` (which also feeds the till's
   catalog cache).
3. **Pages of one delivery share a `targetPath`** (as stock-take pages do) so they drain in order.
   Operation IDs zero-pad the page number — the queue sorts by `createdAt` then operation ID as a
   string, and `-10` sorts before `-2`.
4. **Nothing orders a record behind a queued create on a different path.** A delivery page waits
   while any of its products, or its supplier, is still an unsent create on this device; a
   production batch waits for its product. Same deferral shape as products waiting for queued
   categories (`_awaitsQueuedCategory`).
5. **Confirmation re-reads `targetPath` before a resend.** The new read rules must let the
   submitting roles `get` a document that does not exist yet (role-only rules do), and payloads
   carry a key the stored document never has (`page`, `expenses`-as-sent, `requestId`) so a read
   can never falsely confirm a callable.
6. **Period reads are hard-wired to `createdAt`.** Deliveries and batches carry `createdAt`, so the
   existing instant-range read serves both reports with no reader change.
7. **Reconciliation's stock verifier sums `quantityDelta` ordered by `recordedAt`.** Every new
   movement carries both, and every product write sets `updatedAt`.
8. **The report builder only receives the period** at eight call sites. The subject is added as an
   optional second builder on the run, so none of the eight change.
9. **Home tile colour is chosen by grid position**, so adding two tiles and removing one shifts
   the hue of later tiles. Keying hue by destination is the home README's proposal and is out of
   scope; it is reported, not fixed.

---

## Data model

```
tenants/{t}/products/{p}
    costType            NEW  'purchased' | 'produced'   (absent = purchased)
    cost, quantity      existing — now also written by deliveries and production

tenants/{t}/suppliers/{supplierId}                                    NEW, server-written
    name, phone?, email?, address?, taxReference?, notes?
    active, createdBy, createdAt, updatedBy?, updatedAt?, lastDeliveryAt?

tenants/{t}/supplier_deliveries/{deliveryId}                          NEW, server-written
    tenantId, deliveryId, supplierId, supplierName, reference|null, actorUid, createdAt
    lines[]  {productId, productName, quantity, unitCostMinor|null, previousCostMinor|null,
              previousQuantity, quantityAfter, adjustmentId, page}
    lineCount, unitCount, valueMinor, costlessLineCount
    pagesRecorded[], pageCount|null, complete, updatedAt

tenants/{t}/production_batches/{batchId}                              NEW, server-written
    tenantId, batchId, batchNumber, productId, productName, quantity
    expenses[] {description, amountMinor}, totalCostMinor, unitCostMinor, previousCostMinor|null
    previousQuantity, quantityAfter, adjustmentId, actorUid, createdAt

stock_adjustments/{id} + products/{p}/stock_movements/{id}           existing shape, new sources
    sourceType 'supplier_delivery' | 'production', adjustmentType 'restock'
    + supplierId/deliveryId/reference/unitCostMinor   or   + batchId/batchNumber/unitCostMinor
```

Read rules for the three new collections: `hasTenantRole(tenantId, ['owner','admin','manager'])`,
`write: if false`. New composite indexes (added to `firestore.indexes.json`, **not deployed**):
`supplier_deliveries (supplierId ↑, createdAt ↓, __name__ ↓)` and
`production_batches (productId ↑, createdAt ↓, __name__ ↓)`.

---

## Slices

Each slice ends with its tests green, `flutter analyze` clean for touched files, and a local commit.

### Slice 1 — Foundations

**Server**
- `costType` on `createProduct` and `updateProduct` (accepted keys, validation, write, fingerprint,
  audit, response). Not in `MONETARY_PRODUCT_FIELDS`. Not added to bulk import or bulk update.
- `functions/src/operations/suppliers.ts`: `createSupplier` (idempotent on `supplierId`, like
  `createCategory`) and `updateSupplier` (fields + `active`, plain transaction, like
  `renameCategory`). Folded-name scan inside the transaction, capped at 500. Pure `read*`/`apply*`
  functions exported and tested with `FakeFirestore`.
- Registered in `operations/index.ts` and `index.ts`.
- `firestore.rules`: the three new read-only blocks. `rules-tests`: access-grid rows plus a
  `suppliers-production.test.js` suite, added to the `test` script list.
- `firestore.indexes.json`: the two indexes.

**Client**
- `TenantCollection` / `TenantPaths`: suppliers, supplier deliveries, production batches.
- `TenantProduct.costType`, read permissively (the strict model must never lose the catalog over it).
- Add/Edit product forms: *Bought in / Made here* control; intents, `TenantProductField`, update
  result check, edit-draft fingerprint.
- `lib/suppliers/`: `TenantSupplier` read model and form validation mirroring the server.
- Queue kinds `supplierCreate`, `supplierUpdate` (every exhaustive switch, gateway routing, overlay
  projection, evidence label, duplicate-name wording) and a queued supplier writer.

**Tests:** functions (costType create/update, supplier create/update/duplicate/scan cap), rules,
Dart (read model, validation, queue kinds, overlay, product form choice).

### Slice 2 — Suppliers screens
- Home: Suppliers tile (Inventory group, three roles). Printer tile and its `printerSettingsRoles`
  plumbing removed; `tenant_settings_menu_test` updated.
- `TenantSuppliersScreen`: guard with cached loader, full read of the directory (≤500, as the
  duplicate check), search and Active/Inactive/All filter on the device, local paging, row menu
  (View, Edit, Mark inactive / Reactivate with a confirmation), *Add supplier*.
- Add/Edit supplier form: sheet on phones, dialog wider (the staff pattern).
- Supplier record: contact details, Edit, Mark inactive; the deliveries section lands in slice 3.
- Screenshot captures and captions; widget tests.

### Slice 3 — Supplier deliveries
**Server:** `receiveSupplierDelivery` — one page (≤16 lines) per call, idempotent on
`deliveryId:page`. Per line: quantity added, cost set when a unit cost is given, `stock_adjustments`
+ `stock_movements` (`supplier_delivery`). Header merged from every page (out-of-order safe),
supplier `lastDeliveryAt`, one audit entry per page. Refuses a product named twice in a page or
already received on another page of the same delivery.

**Client**
- Queue kind `supplierDeliveryPage`: multi-path overlay (header + each product), deferral behind
  queued product/supplier creates, zero-padded page operation IDs.
- *Receive delivery* route, from the Suppliers screen (pick supplier) and from a supplier record
  (pre-selected): reference, product lines via a product picker sheet (catalog search, retired
  excluded, no duplicates), per-line quantity and optional unit cost, and a confirmation that lists
  every stock and cost change as "from X to Y".
- Supplier record: delivery history (newest first, paged), each delivery expandable to its lines.
- Ledger source label *Supplier delivery*.
- Optional, last: warn (never refuse) when the supplier already has a delivery with that reference.

### Slice 4 — Production
**Server:** `completeProduction` — idempotent on `batchId`. Recomputes the total and cost per unit
from the rows (never trusts client totals), refuses a zero unit cost, writes the batch, product
quantity + cost, the ledger pair (`production`) and an audit entry.

**Client**
- Queue kind `productionComplete`: multi-path overlay (batch + product), deferral behind a queued
  product create.
- Home: Production tile (Inventory group, three roles).
- Production screen: batch list (newest first, paged, rows expandable to their expense rows),
  *Record production*, report action.
- Record production route: product picker limited to *Made here* and not retired; quantity; expense
  rows pre-filled from that product's last batch; *Keep these out of Expenses* `Disclosure`; live
  total and cost per unit; *Complete production* disabled until valid; confirmation stating the
  stock and cost change.
- Batch numbers per device and date, following the receipt-number shape.
- Ledger source label *Production*.

### Slice 5 — Reports
- Report sheet: optional subject (`TenantReportSubject`) — options loaded when the sheet opens,
  *All …* first, inactive suppliers labelled; side by side with the period from the medium band,
  stacked on phones. The subject reaches the builder, the document title and the filename.
  Reports without a subject render exactly as before (sheet test pins it).
- Supplier report: deliveries per supplier, units, value received, products supplied, unit-cost
  changes per product, lines with no cost, restocks with no supplier recorded; "value received, not
  amount owed" stated.
- Production report: batches and units per product, cost per unit per batch and its change,
  total production spend.
- Analysis tests; render samples; truncation captioned with the date actually reached.

### Close-out
Full `flutter test`, `flutter analyze`, functions `npm test`, rules suite on the emulator, screenshot
harness + index. A final report of what is done, what is not, and what still needs a device.

---

## Explicitly not in this run
Deploys; device runs; `HISTORY.md`; the product-document update (deferred by the developer);
push notifications; an in-app way to clear a refused queued record (existing gap, reported);
the existing reports' truncation caveat (existing bug, reported); keying home tile colour by
destination.
