# FlutterPOS — Supplier Receiving & Lightweight Production MVP

## Engineering response and revised plan

**Status:** Revised by engineering after reviewing the draft against the codebase, 24 Sep 2026.
This version replaces the draft as the one to build from.

Your draft's scope is right, and so is its costing model: the latest batch sets the cost, and each
sale keeps the cost it was sold at. Most of the changes below come from three findings:

1. Part of the draft is **already built**, so this version marks it done instead of asking for it again.
2. The draft had **no rule separating production costs from the Expenses screen**, so the same
   costs could be counted twice.
3. It **added a second cost field**. This version uses the one the app already has.

Items marked **(Engineering call)** are defaults engineering chose where the draft was silent.
Tell us if you want any of them different.

---

## 0. What changed from your draft

| Your draft | Revised | Why |
|---|---|---|
| New `productionCostPerUnit` field, chosen by `costType` at checkout | Production writes the product's **existing cost field** | The till already reads that field and copies it onto every sale. One field means no checkout change and no chance of the two disagreeing. |
| `costType` drives which cost a sale uses | `costType` is **display only** | With one cost field there is nothing for it to choose between. |
| Snapshot cost onto sale lines (§8) | **Already built** | Every sale line already stores the cost it was sold at, and saved sales cannot be edited. Needs a test so it stays that way, not new work. |
| Silent on the Expenses screen | Production costs **must not** also be entered in Expenses, and the screen says so | Net profit is sales minus the cost of what was sold, minus expenses. Flour entered in both places is counted twice and understates profit. |
| Unit cost captured at receiving, but product cost only edited by hand | The **latest delivery's unit cost becomes the product's cost**, like production | One rule for both ways stock arrives. Otherwise a typed cost of KES 50 would change nothing and users would not know why. |
| Draft calculations exist; drafts must not change cost | **No saved drafts.** Nothing is recorded until *Complete production* | Managers can complete batches themselves (§3), so a draft would only add an approval step nobody needs. |
| Expense amounts may be zero | **Every expense row must be above zero, and a batch needs at least one** | A batch with no cost would set the cost to 0 and show a 100% margin on every sale after it. Refused on the form and by the server. |
| "Cost per unit calculated deterministically" | **Rounded half-up to the cent.** The batch keeps the exact total | Product costs are stored to two decimals. KES 1,000 ÷ 3 is stored as 333.33, and the batch still shows 1,000. |
| Batch numbers like `PB-001` | Numbered **per device and date**, like receipts | Batches can be recorded offline, and offline devices cannot share one running counter. |
| "Sales use the current cost when finalized" | The cost is fixed **when the till records the sale** | The till prices each sale from its own copy of the catalog, not at the later server confirmation. See §7. |

---

## 1. MVP intent

Unchanged. The MVP adds:

- **A. Supplier-linked receiving.** The existing restock can record a supplier, a supplier
  reference and a unit cost.
- **B. Lightweight production.** Record what a batch cost to make, and add its output to
  inventory in one step.

The product's existing quantity stays the inventory the till sells from. No warehouse,
raw-material, or manufacturing-accounting system is introduced.

---

## 2. Already in the app, so not new work

| Capability | Where it stands |
|---|---|
| Freezing the unit cost onto each sale line | **Built.** Profit is calculated from the sale line, and returns take back the cost the line was sold at. |
| A stock-in mechanism | **Built.** *Restock* is an existing adjustment type. Receiving adds fields to it; it is not a second stock system. |
| A permanent stock ledger | **Built.** Every stock change records who made it, when, the quantity before and after, and a reason. Production becomes one more kind of entry. |
| Stock counts that tolerate movement mid-count | **Built.** A stock take applies the difference it found, so a batch completed during a count still adds up. |
| Offline stock changes | **Built.** Stock changes made offline are queued and sent when the device reconnects. Production uses the same queue (§8). |

---

## 3. Who can do what

| Action | Owner | Admin | Manager | Cashier |
|---|:-:|:-:|:-:|:-:|
| Create and edit suppliers | ✅ | ✅ | ✅ | — |
| Receive stock (with or without a supplier and unit cost) | ✅ | ✅ | ✅ | — |
| Complete a production batch | ✅ | ✅ | ✅ | — |
| Edit a product's cost directly | ✅ | ✅ | — | — |
| Sell | ✅ | ✅ | ✅ | ✅ |

**The rule:** a manager may change a product's cost **only with evidence**: a production batch
with its expense rows, or a delivery with its unit cost. Typing a new figure straight into the
product stays owner/admin only, as it is today.

Both kinds of evidence are permanent records naming who made the change. That is what makes
it reasonable to trust managers with it. For the safety net, see §12.

---

## 4. Supplier receiving

### 4.1 User experience

```
Receive Stock

Product       Coca Cola 500ml
Quantity      20
Unit cost     KES 50.00                [Optional]

Supplier      ABC Distributors         [Optional]
Reference     INV-48392                [Optional]
Reason        Received from ABC Distributors · INV-48392
                                       [Pre-filled, editable]

[Receive]
```

The confirmation states the effect in words before anything is saved:

```
Coca Cola 500ml: 40 → 60 in stock
Cost changes from KES 45.00 to KES 50.00 for every sale from now on.

[Receive]   [Back]
```

- **Reason (Engineering call).** Every stock change in the app already needs a reason of at least
  three characters. On this form it is pre-filled from the supplier and reference, so the person
  does not type it twice.
- **Unit cost (Engineering call).** Optional. Left blank, the product's cost is not changed, and
  the confirmation leaves the cost line out.
- Quantity is a whole number from 1 to 1,000,000, the existing limit for any single stock change.

### 4.2 Supplier records

| Field | Notes |
|---|---|
| Name | Required. **Duplicates are refused**: names that differ only in capitals or spacing count as the same supplier, the rule categories use. Otherwise one supplier's history splits in two. |
| Phone, email, address | Optional |
| Tax/business reference | Optional |
| Notes | Optional |
| Active / inactive | **(Engineering call)** Inactive suppliers disappear from the picker but keep their history. Suppliers cannot be deleted. |

A supplier holds no stock. Its history is the list of deliveries recorded against it.

### 4.3 What a delivery records

The existing restock record, plus:

- supplier (when chosen)
- supplier reference (when entered)
- unit cost (when entered)

It keeps everything a restock already records: product, quantity before and after, reason, who,
when, and a request identity that stops a retry being counted twice.

### 4.4 Out of scope (unchanged from your draft)

Purchase orders, goods-received-note lifecycle, supplier payables, payment tracking, purchase
accounting, and full duplicate-invoice protection.

---

## 5. Production

### 5.1 User experience

```
Produce Stock                                  (working name)

Product            Bread
Quantity produced  100

Production costs
ⓘ Keep these out of Expenses                 ⌄
--------------------------------
Flour              KES 2,000.00
Labour             KES   500.00
Gas                KES   200.00
Packaging          KES   300.00
[+ Add cost]
--------------------------------
Total              KES 3,000.00
Cost per unit      KES    30.00

[Complete production]
```

The line **"Keep these out of Expenses"** opens, using the app's existing expandable info
component, to read:

> These costs become part of what each unit costs. If you also record them in Expenses they are
> counted twice, and your profit will look lower than it was.

The confirmation, like receiving:

```
Bread: 12 → 112 in stock
Cost changes from KES 28.00 to KES 30.00 for every sale from now on.

[Complete production]   [Back]
```

Whether the menu item reads *Produce Stock* or *Cost of Production* is still yours to decide. It
changes nothing underneath.

### 5.2 Validation

These checks run on the form **and** again on the server. *Complete production* stays disabled
until they all pass.

- Quantity produced is a whole number from 1 to 1,000,000.
- At least one expense row.
- Every row has a description and an amount **above zero**. **(Engineering call)** A row with a
  zero amount is refused: it adds nothing to the cost and usually means a row someone forgot to
  fill in.
- **(Engineering call)** A completely empty row at the end of the list is ignored rather than
  treated as an error, so an accidental *Add cost* does not block the form.
- Amounts have at most two decimal places.

Because every row is above zero, the total always is too. A batch with no cost cannot be created.

### 5.3 Cost per unit

```
cost per unit = total cost ÷ quantity produced, rounded half-up to the cent
```

The batch stores the exact total and the rounded cost per unit. With 3 units at KES 1,000, the
batch reads *Total KES 1,000.00 · KES 333.33 each*, and the product's cost becomes 333.33.

### 5.4 Completing a batch

*Complete production* is the only step. Nothing is recorded before it, and there are no saved
drafts. On completion, as one indivisible operation:

1. The production batch is saved.
2. The product's quantity increases by the quantity produced.
3. The product's cost becomes the batch's cost per unit.
4. A stock-ledger entry of type *Production* is recorded, pointing at the batch.
5. An audit entry records who completed it.

Either all five happen or none do. A batch can never exist without its stock, and stock can
never arrive without its batch.

### 5.5 The batch record

```
Production batch  PB-1E6-20260924-0001

Product      Bread
Quantity     100
Expenses     Flour 2,000.00 · Labour 500.00 · Gas 200.00 · Packaging 300.00
Total cost   KES 3,000.00
Cost/unit    KES 30.00
Previous     KES 28.00
Completed    24 Sep 2026, 06:42, by <person>
```

The batch also stores the cost it replaced, so the history shows each change and not just
each new figure. The batch number format shown is illustrative; see §0 for why it is per device
and date.

### 5.6 Mistakes

A completed batch is **never edited or voided**. It stays exactly as entered, as a record of
what happened. A mistake is corrected the way stock and cost are corrected today:

- Wrong quantity: a *Correction* stock adjustment (owner, admin or manager).
- Wrong cost: an owner or admin edits the product's cost.

**Why fixing it quickly matters:** every sale recorded before the fix keeps the wrong cost
permanently, because saved sales cannot be edited. See §12 for the notification that shortens
that window.

---

## 6. The product cost rule

**The latest event that states a cost sets the product's cost.** That event is a completed
production batch, a delivery with a unit cost, or an owner/admin edit.

```
Batch 1    100 Bread   KES 30.00/unit  → cost 30.00
Batch 2    100 Bread   KES 35.00/unit  → cost 35.00
```

- **(Engineering call)** This applies whichever kind of product it is. A *Produced* product that
  is occasionally bought in takes its cost from that delivery. `costType` only decides which
  actions the inventory screen offers first.
- There is no FIFO, LIFO, weighted average, batch depletion or lot tracking (unchanged from your draft).

---

## 7. Sales and historical profit

**Already built.** When the till records a sale, it copies the product's current cost onto each
line. That line never changes afterwards, so a later batch cannot rewrite past profit.

```
24 Sep   Bread sold at KES 50, cost at sale KES 30   → stays 30
30 Sep   Batch 2 sets cost to KES 35
01 Oct   Bread sold at KES 50, cost at sale KES 35
```

**One timing detail product should know.** Each till prices sales from its own copy of the
catalog. That copy refreshes when the till reconnects or the app starts, not the instant a batch
is completed on another device. For a short while after a batch, a till may still record the
previous cost. This is also how a hand-edited cost behaves today.

A product with no cost recorded yet, such as a new product before its first batch, sells
normally. Its lines are counted as *cost not recorded* in profit reports rather than given a cost
of zero.

---

## 8. Offline behaviour

Production and receiving work offline, like every other stock change in the app.

- The new quantity shows **on that device immediately**.
- The batch, the new cost, and the ledger entry are recorded **when the device reconnects**. Until
  then, other devices do not see them.
- A retry after a dropped connection can never record the batch twice.

On an offline device, *Completed* therefore means "completed and queued". The screen says so, the
way stock changes already do.

---

## 9. Data model (conceptual)

Field names and paths follow existing conventions. They are listed here to show shape, not
naming.

```
products/{productId}
    quantity          existing — the stock the till sells from
    cost              existing — now also set by production and deliveries
    costType          NEW — purchased | produced   (display only)

suppliers/{supplierId}                               NEW
    name, phone?, email?, address?, taxReference?, notes?, active
    createdAt, createdBy

stock adjustment (existing restock record)
    + supplierId?        NEW
    + supplierReference? NEW
    + unitCost?          NEW

production_batches/{batchId}                         NEW
    batchNumber
    productId
    quantityProduced
    expenses[]           description, amount
    totalCost
    unitCost
    previousCost
    completedAt, completedBy

stock ledger entry
    + source type "production", pointing at the batch   NEW

sale line
    unit cost at sale    existing — no change
```

---

## 10. Acceptance criteria

### Supplier receiving

- [ ] Suppliers can be created, edited, and marked inactive by owners, admins and managers.
- [ ] Duplicate supplier names (ignoring capitals and spacing) are refused.
- [ ] Inactive suppliers are hidden from the picker and keep their history.
- [ ] Restock accepts an optional supplier, reference and unit cost.
- [ ] The reason is pre-filled from supplier and reference, and editable.
- [ ] A delivery with a unit cost sets the product's cost. One without leaves it unchanged.
- [ ] The confirmation states the quantity change and, when there is one, the cost change.
- [ ] A supplier's history lists its deliveries.
- [ ] Restock with no supplier and no cost behaves exactly as it does today.

### Production

- [ ] A product can be marked *Produced*. This changes which actions the screen offers, and nothing else.
- [ ] Owners, admins and managers can complete a batch from inventory actions.
- [ ] The form refuses: quantity below 1 or above 1,000,000, no expense rows, a row with no
      description, a row with an amount of zero or less, and more than two decimal places. The
      server refuses the same inputs.
- [ ] A completely empty trailing row is ignored.
- [ ] Cost per unit is the total ÷ quantity, rounded half-up to the cent.
- [ ] The "Keep these out of Expenses" explanation is on the production screen.
- [ ] The confirmation states the quantity change and the cost change.
- [ ] Completing saves the batch, increases quantity, sets cost, and records a *Production*
      ledger entry and an audit entry: all or none.
- [ ] A completed batch cannot be edited or voided.
- [ ] A retried completion never records the batch twice.
- [ ] Completing offline shows the new quantity on that device and records the rest on reconnect.

### Cost and profit

- [ ] Direct edits to a product's cost remain owner/admin only.
- [ ] Sales copy the cost current on the till at the moment of sale. *(Already built; add a test so it stays that way.)*
- [ ] A later batch or delivery does not change the cost on any past sale. *(Already built; add a test so it stays that way.)*

### Scope protection (unchanged from your draft)

- [ ] No warehouse stock, raw-material quantities, or material-consumption ledger.
- [ ] No purchase orders or supplier payables.
- [ ] No FIFO/LIFO/weighted-average costing, and no batch depletion.
- [ ] Existing till behaviour is unchanged.

---

## 11. Known limitations, accepted for the MVP

| Limitation | Why it is acceptable now |
|---|---|
| Users who keep entering ingredients in Expenses will double-count them | The production screen tells them not to. We cannot detect it, because the two records share nothing. |
| A wrong cost stays on every sale recorded before someone fixes it | The same is true of a hand-edited cost today. The confirmation wording makes the change hard to miss, and §12 closes the gap later. |
| A till may record the previous cost briefly after a batch | Same as a hand-edited cost today (§7). |
| Quantities are whole numbers | Existing app-wide rule. No 2.5 kg batches. |
| Batches are not numbered in one running sequence per business | Offline recording rules it out (§0). |

---

## 12. Future work

- **Push notifications for critical actions.** Owners and admins are notified when a manager
  changes a product's cost through a batch or a delivery, so they can check it while few sales
  have used the new cost. This will be built as part of a wider notifications feature for critical
  actions, **not** in this MVP.
- **Purchases.** Purchase orders, goods received and payables can sit above today's receiving
  without changing inventory or till behaviour.
- **Manufacturing.** Raw-material receiving, recipes/BOM and automatic consumption can replace how
  a batch's cost is *calculated* while keeping the batch itself.

---

## 13. Core MVP rule

```
SUPPLIER RECEIVING
Supplier → Restock → existing inventory   (unit cost, if given, becomes the product's cost)

PRODUCTION
Expenses → Complete production → existing inventory   (cost per unit becomes the product's cost)

PROFIT
Product's cost → frozen on each sale when the till records it → past profit never changes
```
