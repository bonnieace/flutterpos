# Open questions

Do not answer these by drawing a plausible control. Record the product decision, then update the
relevant phase and coverage ledger.

## Resolved for Phase 00

1. Working visual references are surface `#071610` and primary `#4BE277`. These are semantic design
   inputs, not permission to hardcode colors in later Flutter screens.
2. Normalize selected existing screen IDs in place. Do not create successors or archive history in
   Phase 00.
3. `list_screens` later recovered titles and artifacts for the six earlier retrieval gaps: ST-005
   Staff Management desktop, ST-006 Receipt & Printing Status mobile, ST-007 Inventory & Stock
   Movements mobile, ST-008 Staff Directory mobile, ST-018 Analytical Reports desktop, and ST-021
   Inventory Management desktop. They remain untouched and require content review before reuse.
4. ST-001 is the working desktop new-sale candidate; ST-011 and ST-009 are its mobile browse/review
   counterparts.
5. Phase 00 did not approve its draft chart content because the underlying metrics were not verified,
   not because charts are prohibited. Presentation parity is not required: supported metrics may be
   redesigned as charts, statistics, tables, or combinations during the analytics phase.
6. Tax/VAT remains unsupported and is absent from normalized designs. Editable business branding is
   deferred; current settings scope is currency plus printer linkage.

## Resolved for Phase 01

1. Authentication uses email and password only. Phase 01 adds no password reset, registration,
   social sign-in, SSO, subscription, or support workflow.
2. Email verification remains out-of-band: request/send the message, then explicitly recheck with
   `I have verified`; the UI does not collect a verification code.
3. A business request collects business name and slug, has a review/confirmation step, and remains
   pending until platform review. It does not provision a tenant automatically.
4. Invalid or expired invitations do not offer retry. The recovery is to continue without the link or
   ask the inviter to send a new invitation, according to the evidenced failure.
5. Platform routing is not a role picker: only a root `platform_admin` with the separate
   `platformRole=superAdmin` claim reaches the platform console. Platform operations remain Phase 09.

## Resolved for Phase 02

1. Mobile home navigation uses a deliberate shift-first, single-column task hub. It is not a cropped
   desktop sidebar and does not use a generic persistent bottom navigation bar.
2. Owner inherits Administrator access. Manager and Cashier homes omit forbidden routes entirely;
   they do not advertise them as disabled tiles.
3. Own shift is content on the home rather than a navigation destination. Its single forward action
   follows the active phase: Open shift, Start cash count, or Close shift.
4. Checkout synchronization evidence and receipt-print queue evidence remain separate. A confirmed
   sale does not imply that its receipt printed.
5. Tenant switching requires another accessible membership, clean inspected local state, and online
   target revalidation. Blocked/offline states keep the current business open.

## Resolved for Phase 03

1. Checkout records Cash, M-Pesa, or Card as the cashier's assertion; it does not verify payment.
2. `Save sale` is the only primary transaction action. Checkout adds no VAT/tax, discount, or draft
   control, and stock shortage remains non-blocking.
3. A locally saved sale is durable before server confirmation. `Confirmed by server` is a later,
   quiet status and is not required before the cashier can retain the receipt number.
4. Receipt printing follows durability. Printer failure never rolls back or relabels the sale; the
   cashier closes the success notice and uses Receipts waiting from the business home.
5. Tablet checkout is a distinct two-region browse/cart composition at 834px. Mobile remains a staged
   browse then cart/review flow rather than shrinking the desktop terminal.

## Resolved for Phase 04

1. Cashier catalog access is read-only and does not expose management or stock-route actions.
2. Manager may create categories/products and set the required first product price, but existing
   price/cost correction, recorded-cost removal, and retirement are Owner/Administrator-only and are
   omitted from Manager correction surfaces.
3. Bulk catalog input is pasted comma-, tab-, or semicolon-delimited text with a required header,
   row-by-row preview, explicit commit, and retained row outcomes. There is no `.xlsx` or file upload.
4. Stock is the server's recorded quantity, may be negative, and never blocks a sale. The product
   does not model reorder points, low-stock thresholds, suppliers, or purchase orders.
5. A stock adjustment is permanent, requires a typed reason and audit context, and is corrected by
   recording another adjustment. Adjustment feeds list manual corrections; movement feeds also
   include sales and verified returns.
6. Movement and ledger ordering is by product/record ID rather than time. Every record therefore
   carries its recorded time and actor/server provenance explicitly.

## Resolved for Phase 05

1. Chart-based presentation is limited to directly evidenced comparisons: two exact daily sales bars
   and exact-value tender bars/rows. Reconciliation state, anomalies, run detail, and shift amendments
   use status/stat/provenance/table treatments because exact source and actionability matter more than
   shape comparison.
2. Daily summary and sales totals are readable by Owner, Administrator, and Manager. Profit and margin
   are Owner/Administrator-only and disappear entirely for Manager or incomplete cost coverage.
3. Sales totals describe server-held sales and remain distinct from reconciled daily figures. Tender
   is cashier-recorded and unverified; `Not recorded` means older tender metadata is absent, not unpaid.
4. Reconciled, unusable-line, and different are distinct states. Unusable lines can coexist with a
   reconciled status but require separate attention language and never count toward stock or profit.
5. Reconciliation requests and shift-total corrections are Owner/Administrator-only. Manager may read
   anomaly and amendment history but receives no mode, request, correction, or reason controls.

## Product decisions needed before affected phases

7. Should business profile/receipt branding become editable in-app, or remain backend/seed-managed?
   The active checkout setting currently exposes currency; printer has its own route.
8. Is tax/VAT permanently out of product scope or only deferred? It remains excluded until an
   explicit product and implementation scope exists.
9. Should historical discount display remain visible on sale/receipt details while checkout continues
   to prohibit new discount entry?
11. Should platform superAdmin screens share the tenant visual shell or use a deliberately separate
    operations shell?

## Non-blocking audit limitations

- The built-in Stitch connector in this chat retained an unauthenticated transport. Read-only audit
  calls succeeded through the configured API-key endpoint instead; a fresh Codex session should
  reload the connector configuration.
- Stitch retrieval was intermittent: `list_screens` ultimately returned all 26 screens, while some
  individual `get_screen` calls still alternated between success, invalid argument, not found, and
  service unavailable.
- Several post-edit downloadable HTML/screenshot artifacts remained stale even though the mutation
  response returned concrete DOM operations. Those screens remain render-review items, not approved.
- Phase 01 source screens ST-028 through ST-031 were returned by successful generation/edit responses
  but are not present in `get_project.screenInstances`; they need canvas-link review. ST-027 and ST-029
  also retained pre-correction downloadable screenshots after successful DOM edits.
- Phase 02 correction returned derived successors ST-032/ST-033 instead of overwriting ST-012/ST-023.
  Final DOM corrections succeeded, but ST-033 still serves its pre-correction artifact, ST-032
  individual retrieval is intermittent, and project retrieval later returned invalid argument.
- Phase 03 correction returned derived successors instead of overwriting ST-026/ST-009/ST-011.
  ST-035 is retrievable and visually reviewed. ST-036 returned invalid argument after successful
  generation, and response truncation hid the exact mobile-browse successor ID. Project instances
  still omit every Phase 03 successor. Per the operating contract, neither mobile screen was
  regenerated; recover and review them in the Stitch UI.
- Phase 04 correction returned derived successors rather than overwriting ST-002/ST-007. The first
  ST-037/ST-038 pair was superseded by ST-039/ST-040 after visual review found compressed routes,
  role-mode navigation, generic bottom navigation, invented products, and missing audit states.
  ST-039's final audit-record correction completed without a new source ID, but retrieval still serves
  the pre-correction artifact; ST-040 immediately returns invalid argument. Do not regenerate either
  merely to refresh retrieval; review them in the Stitch UI.
- Phase 05 correction returned derived ST-041/ST-042 rather than overwriting ST-019/ST-020/ST-022/
  ST-025. ST-041 is retrievable and partially verified, but its exact shift-correction action label
  and dense provenance still need review. ST-042 was later superseded by approved mobile correction
  ST-043. ST-043 is freshly retrievable and removes the invented comparison/date/totals, but artifact
  inspection shows omitted exact filter, oldest-first, server-trigger, counted-cash, server-derived,
  ordering, and evidence-provenance phrases. These are bounded copy/provenance defects, not permission
  to invent replacement values.
- The final approved copy-only ST-041/ST-043 mutation reports those phrases and the desktop action
  label as corrected. ST-041 still serves its pre-edit artifact and ST-043 retrieval is invalid, so
  both require canvas review. The mutation log changed `Expected: 12` to `Expectation ID: 12`; this is
  a known semantic defect and must be restored to `Expected: 12` before canonical approval. Phase 05
  is nevertheless closed; do not regenerate either screen merely to refresh retrieval.
- Phase 06 CREATE returned rejected ST-044/ST-045, and approved corrections produced successor chain
  ST-046/ST-047, ST-049/ST-048, and ST-050. The approved in-place ST-048 correction removes the
  invented Ceramic Mug, 16% tax, and refund amount; its retrieval remains stale. ST-050's inspected
  pre-final artifact renders Sections 03-05 without forbidden content. The final approved in-place
  ST-050 DOM correction adds `Cash over` and desktop `No closing summary` and raises all Section 03-05
  controls to at least 48px. Direct canvas-code copies then proved both first edits had not persisted.
  The approved exact-ID reapplications completed with concrete DOM operations, but mobile retrieval
  remains cached and desktop retrieval is invalid. Fresh canvas-code copies are required before
  canonical promotion or any additional mutation; Phase 06 execution itself is closed.
- Local screenshots are deterministic widget renders, not physical-device proof. Native keyboard,
  focus, printing, scroll performance, and motion need later device review.
