# Returns: accounting — a design, 2026-10-13

One board for what `ACCOUNTING_WORKFLOW_DISCOVERY.md` adds to Returns (D-09, D-28, D-36, D-45, D-47,
D-49; Phase A and D). Open [`index.html`](index.html). Self-contained HTML.

**This is a proposal.** Nothing in `lib/` was changed. Filing a return is unchanged and not
drawn.

## The question the screen is opened with

*Is this return right, and what happens to the goods and the money?*

## Decisions drawn

1. **Verify and Reject are the two answers to a pending return,** side by side with words.
   Today's icon-only verify and view buttons become labelled. *Reject* is for managers and up and
   needs a reason (D-09, D-25).
2. **Condition is chosen per line, and a line can be split** (15 sellable, 5 damaged).
   - *Damaged* still restores stock, and writes a `damage` adjustment in the same step (D-45).
   - The amber marks the loss, not an error.
3. **Replace or don't replace appears only for goods from an order** (D-49). Each option says what
   happens to the invoice and to the order. An over-delivered extra skips it (D-47).
4. **Rejecting says what it undoes:** the netting on the sale's day, because returns count when
   filed (D-28).
   - A checkbox, ticked when the return handed cash back, keeps that refund in the shift.
   - The return is then filed again against the right sale.
5. **The money on verification follows the spec:**
   - the outstanding on the sale's invoice is cancelled first;
   - anything beyond what was owed becomes money waiting for a manager (D-36).

## Gaps and questions

1. **Splitting a line's condition** is drawn as two rows, each with a stepper. The spec says "each
   returned line", but a line of 20 is rarely all one condition. Confirm.
2. **Rejecting a return whose refund really happened** leaves a refund with no return behind it
   until the new return is filed. Should the rejection and the new filing be one step, picking the
   right receipt in the same dialog?
3. **Damaged goods' cost.** The `damage` adjustment needs a cost. Is it the product's average at
   the return's date or at the sale's? D-37 (moving average) is silent. Drawn without a figure.

## What it takes

- **Phase A:** rejecting a return; `status: rejected`; netting that excludes rejected returns,
  on both device and server, with the vectors updated.
- **Also Phase A:** condition per line, writing the damage adjustment in the same transaction.
- **Phase D:** the replace choice and its order effect.

None of it is a restyle.

## Accessibility

- Condition is a two-option segmented control with a glyph on the chosen side.
- The checkbox shows a tick, not only a fill.
- The reject confirm is outlined in problem red and names its action.
