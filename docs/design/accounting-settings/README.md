# Settings: accounting — a design, 2026-10-13

Three boards for the settings in `ACCOUNTING_WORKFLOW_DISCOVERY.md` (D-06, D-07, D-21, D-30, D-42;
§11 Rollout; Phases B, C and E). Open [`index.html`](index.html). Self-contained HTML.

**This is a proposal.** Nothing in `lib/` was changed.

## The boards

| Board | What it shows |
| --- | --- |
| [Configs: invoicing](configs-invoicing.html) | A fourth Configs tab: the invoicing switch, payment terms, sending, the letterhead fields, and at 1440 a live preview |
| [Not-stocked products](product-not-stocked.html) | *Stocked* or *Not stocked* on the product form, *Price set at sale*, and Inventory's *Not stocked* filter |
| [Home and customer terms](home-and-forms.html) | Quotes, Orders and Invoices on the home at 1232 and in the phone launcher; payment terms on the customer form |

## Decisions drawn

1. **Invoicing is a fourth Configs tab,** which turns the tabs into scrolling icon tabs on a phone
   (`AppTabs`' own rule).
2. **The switch is the rollout flag** (`configuration/invoicing.enabled`). Turning it on the first
   time asks for the start day, which becomes `goLiveAt` (D-30).
3. **Send invoices is a setting:**
   - *by itself, on issue* (the default, spec question 5's recommendation);
   - or *only when someone presses Send*.
4. **The letterhead is "On every document".** It holds the phone, address, KRA PIN, how to pay,
   the terms on quotes and the signature lines. Name, slogan and logo stay in Business details, and
   the tab says so. The KRA PIN is labelled print-only.
5. **The live preview at 1440 is the real renderer,** cropped to what the fields change.
6. **Stocked or Not stocked is a `ChoiceCardGroup` near the top of the product form,** because it
   changes the fields under it. *Price set at sale* is a switch.
7. **A product's kind is fixed once it has stock movements.**
8. **Inventory gets a *Not stocked* filter.** Not-stocked products are left out of counts,
   low-stock warnings and stock value.
9. **The new home cards go after Customers**: Customers, then Quotes, Orders and Invoices.
   - Two-line descriptions.
   - The Customers card's description changes to "what they owe".
   - Invoices is shown to managers and up.
10. **Payment terms sit with *Can buy on credit* on the customer form,** for managers. Terms apply
    to new invoices only.

## Gaps and questions

1. **Letterhead in Configs or Business details?** D-42 says Configs. Business details already holds
   the name, slogan and logo for receipts. Drawn as the ruling says, with a pointer; moving it all
   into Business details would put one letterhead in one place.
2. **Turning invoicing off again.** What happens to open invoices if the switch goes off? Drawn as
   a switch with no confirmation; it needs one, and a rule.
3. **Who sees Invoices on the home.** Drawn as managers and up, matching the customer record's role
   gate. Cashiers take payments from the customer directory (CF-4) and do not need the list.
4. **Glyph colours** on the new cards are placeholders for the next unused 400 identity tokens.
5. **The system's *Cancellation fee* product** is made the first time it is needed. Should it be
   seeded at go-live instead?

## What it takes

- **Phase B:** the product form choice, `stocked: false` and `openPrice: true`; Inventory's filter
  and the stock report exclusions.
- **Phase C:** the letterhead fields and the preview.
- **Phase E:** the invoicing switch, terms and sending; per-customer terms; the home cards
  (Phase D for Quotes and Orders).

The home cards need the 2-line description test updated. None of this is a restyle.

## Accessibility

- Switches have labels and states.
- The choice cards are `ChoiceCardGroup`.
- The read-only state for managers uses the existing callout and shows the values as text.
