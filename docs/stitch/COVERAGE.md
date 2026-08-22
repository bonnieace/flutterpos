# Redesign coverage ledger

Status meanings:

- `EVIDENCED` - supported by active code and local rendered evidence.
- `STITCHED` - represented in Stitch, but not necessarily correct.
- `MISSING` - product capability exists but no verified Stitch screen covers it.
- `CONFLICT` - a Stitch screen depicts unsupported or contradictory behavior.
- `INFERENCE` - plausible relationship that still needs verification.
- `DEFERRED` - intentionally outside the current redesign scope.
- `NORMALIZED / REVIEW` - corrected in Stitch, with fresh visual confirmation still required.

## Coverage summary

| Area | Code/screenshot | Stitch | Status | Required disposition |
|---|---|---|---|---|
| Sign-in and entry failures | Yes | Desktop/mobile state suites created | NORMALIZED / REVIEW | Default, refused, unreachable, caps-lock, and busy states are covered; desktop correction artifact remains stale. |
| Tenant selection and entry | Yes | Desktop/mobile state suites created | NORMALIZED / REVIEW | Choose/default, verify, request, no-business, invite, account failure, and routing split are covered; mobile correction artifact and canvas linkage need review. |
| Platform operations | Yes | Desktop ST-073 and mobile ST-070 | CANONICAL CANDIDATE / VISUAL REVIEWED | Fresh exact-ID HTML/screenshots verify the distinct shell, admission, lifecycle, archive, exact-UID global status, consequence/state evidence, responsive composition, and 48px controls. ST-071/ST-072 remain superseded/rejected history. |
| Owner/admin/manager/cashier home | Yes | Desktop/mobile role-aware suites corrected | NORMALIZED / REVIEW | ST-032/ST-033 encode exact route differences, shift-first mobile flow, device-local evidence, and switch states; final corrected renders remain to review. |
| Staff directory | Yes | Desktop/tablet and mobile lifecycle suites | CANONICAL CANDIDATE / VISUAL REVIEWED | ST-055/ST-056 verify exact roles, Owner/Administrator write, Manager zero-write composition, invite/edit/status/email/resend/cancel actions, confirmations, validation/failure states, and responsive behavior. |
| New sale | Yes | Desktop/tablet/mobile corrected | NORMALIZED / REVIEW | ST-035 is visually reviewed; mobile browse/cart successors need fresh canvas review and mobile-browse ID recovery. No tax, draft, verified-payment, stock-blocking, or print-rollback behavior remains in the working direction. |
| Currency setting | Yes | Desktop/mobile Phase 08 suites | NORMALIZED / RENDER REVIEW | ST-061/ST-062 mutation logs cover the one persisted ISO 4217 code and its read/write lifecycle; served artifacts predate the final operations. |
| Business settings | Currency only in active UI | Phase 08 desktop/mobile suites plus conflicting originals | NORMALIZED / RENDER REVIEW | ST-061/ST-062 retain only supported currency/printer configuration. ST-003/ST-024 remain historical; branding/profile/tax/location/contact/language/sync settings are not canonical. |
| Catalog | Yes | Desktop/mobile/tablet route suites corrected | NORMALIZED / REVIEW | ST-039/ST-040 separate Cashier read-only, Manager operational, and Owner/Administrator money/retire capability; bulk delimited-text preview/commit and failure states are covered. Final renders need review. |
| Stock corrections/movements/ledger | Yes | Desktop/mobile/tablet route suites corrected | NORMALIZED / REVIEW | Recorded stock, permanent reasoned adjustments, manual-only adjustment feed, all-source movement feed, product ledger, provenance, negative-stock truth, and responsive records are covered; final renders need review. |
| Daily metrics and totals | Yes | Desktop/mobile suites corrected | NORMALIZED / REVIEW | ST-041/ST-043 retain exact supported totals and a direct-label two-day comparison without derived change. Final filter/scope copy mutation completed; fresh artifacts require review. Export remains unsupported. |
| Reconciliation | Yes | Desktop/mobile suites corrected | NORMALIZED / REVIEW | ST-041/ST-043 distinguish matched, unusable-line, and different states and include request/run/amendment evidence. Final action/provenance copy mutation completed; retrieval is stale/invalid and one expected-value label is non-canonical. |
| Profit/margin completeness | Yes | Desktop/mobile complete/refusal specimens | NORMALIZED / REVIEW | ST-041/ST-043 show owner/admin profit only when complete, suppress incomplete figures, and omit Manager profit. |
| Receipt lookup | Yes | ST-048 mobile / ST-050 desktop | NORMALIZED / REVIEW | Full lookup evidence is present. Mobile truth correction completed in the mutation log but its artifact is stale; desktop is freshly reviewed. |
| Shift history and sale detail | Yes | ST-048 mobile / ST-050 desktop | NORMALIZED / REVIEW | Core routes and sale evidence are present. The final ST-050 DOM correction adds `Cash over` and desktop `No closing summary` and raises all Section 03-05 controls to at least 48px; current render still needs canvas review. |
| Returns | Yes | ST-048 mobile / ST-050 desktop | NORMALIZED / REVIEW | Request/verification separation, failure matrix, confirmations, and tablet transformation are covered. Mobile forbidden-content removal needs fresh canvas review. |
| Activity log | Yes | No | MISSING | Create owner/admin view. |
| Printer configuration | Yes | Desktop/mobile Phase 08 suites | NORMALIZED / RENDER REVIEW | ST-061/ST-062 correction logs use only direct-TCP host, port, 32/48 columns, cutter, save, and endpoint-probe concepts and cover read/write/test outcomes. Fresh final renders remain pending. |
| Print queue/retry | Yes | Desktop/mobile Phase 08 suites | NORMALIZED / RENDER REVIEW | ST-061/ST-062 logs cover device-local empty/populated/unreadable/sending/success/setup/browser/read-only/retry-failure states and preserve sale durability. Fresh final renders remain pending. |
| Responsive component states | Yes, groups 90-99 | No inventory | MISSING | Establish after workflow compositions stabilize. |

## Confirmed product capabilities

### Identity, tenancy, and access

- Sign in, verification, invitation acceptance/failure, business selection/request/no-access states.
- Multiple memberships and default/current business selection.
- Active canonical membership required for tenant access.
- Four tenant roles only: owner, admin, manager, cashier.
- Separate platform superAdmin admission/archive/global-user workflows.

### Sale and offline operation

- Browse cached catalog, build cart, choose/assert tender, and durably save a sale.
- Offline outbox, reconnect recovery/submission, evidence counts, and catalog refresh.
- Stock shortage is informational and does not block sale.
- Payment method is recorded, not externally verified.
- Receipt number allocation and post-durability printing.
- Failed printing queues immutable receipt bytes for retry.

### Catalog, stock, and reporting

- Read-only catalog for all active members.
- Product/category management, bulk delimited-text preview/commit, and narrowed money/retire actions.
- Recorded stock, corrections, movement feed, and per-product ledger.
- Daily metrics, sales totals, reconciliation status/anomalies/run, shift amendments, and profit/margin
  with cost-completeness safeguards.
- Receipt lookup, shift sales, returns, and activity/audit history.

## Unsupported content currently visible in Stitch

| Draft content | Finding | Rule for correction |
|---|---|---|
| “Kijani POS” and “Operational Hub” | Wrong or unapproved branding | Use Chilltent POS and task-specific page language. |
| VAT 16%, VAT rate, prices include tax | No active tax capability found | Remove; do not imply tax calculation or configuration. |
| “Pay now” / processed-payment implication | App records asserted tender only | Use language such as record/save sale; never claim verification. |
| Save draft button | No corresponding checkout UI action evidenced | Remove unless a code-backed workflow is identified. |
| Dashboard terminals/cloud/local DB telemetry | No active data source or route found | Remove invented metrics and connectivity claims. |
| Reorder points and low-stock thresholds | No threshold model found | Show recorded quantities/differences only. |
| Granular staff permissions | Authorization is fixed role-list based | Replace with exact role selection and role-derived capability copy. |
| Senior Cashier / Inventory Clerk | Roles do not exist | Use Owner, Administrator, Manager, Cashier only. |
| Staff scheduling/last shift controls | Not supported in staff management | Remove or explicitly scope a future product feature. |
| Registration/location/contact/support fields | Not found in active settings capability | Remove from canonical settings. |
| Sync interval and language controls | Not found | Remove. Connectivity behavior is automatic. |
| Export CSV | No active export surface found | Remove unless product and implementation scope explicitly add it. |
| Category charts/payment breakdown visualizations | Underlying data may partly exist; the current presentation is not a constraint | Visualizations are permitted when derived entirely from supported underlying metrics. The visualization itself may be new; the underlying data and calculation must be evidenced. |

## Required state coverage

Every canonical workflow should account for applicable loading, populated, empty, validation error,
remote error, offline/stale, permission/read-only, disabled/busy, success, and partial-success states.
The following product-specific states are mandatory:

- Sale saved locally versus server-confirmed.
- Sale saved but receipt not printed.
- Printer unconfigured, unreachable, waiting queue, retrying, and unreadable queue record.
- Shift closed/open, cash count, close pending, reconciliation matched/different/unusable lines.
- Catalog stale/offline, no products, stock difference, adjustment validation.
- Profit complete versus unavailable because one or more sale lines lack cost.
- Tenant switch available versus blocked by local state/offline.
- Staff administrator edit versus manager read-only.

## Phase 01 coverage result

- Sign-in default, refused credentials, unreachable service, caps-lock, and busy states are represented
  on desktop and mobile with visible labels and 48 px targets.
- Email verification uses out-of-band `Send verification email` / `I have verified` behavior; no code
  entry or password-reset flow is depicted in the corrected working set.
- Choose business, request business and confirmation, no-business, valid/invalid invitation, and
  account-open failure states are represented responsively.
- Tenant membership and platform admission remain separate. The platform-routing note requires both
  root `platform_admin` account type and the separate `platformRole=superAdmin` claim; Phase 01 does
  not include platform operational screens.
- ST-030 is a recorded non-canonical intermediate conflict. ST-027 and ST-029 need fresh render review;
  ST-028 through ST-031 also need project-canvas linkage review.

## Phase 02 coverage result

- Owner and Administrator retain the shared common routes plus Manage catalog, View daily summary,
  Checkout settings, Printer, View activity log, and View staff directory.
- Manager retains common routes plus Manage catalog, View daily summary, and read-only staff directory;
  restricted settings, printer, audit, profit, and write actions are absent rather than disabled.
- Cashier is intentionally narrow: New sale, Receipts waiting, View read-only catalog, Find a receipt,
  eligible tenant controls, own shift content, and Sign out.
- Own shift is home content, not a navigation destination. The working set covers no-shift, open,
  unfinished cash-count, and offline/unconfirmed wording with one forward action per state.
- Checkout evidence is a read-only device-local readout with Saved offline, Submitting, Awaiting
  confirmation, Needs attention, and Confirmed. Receipts waiting remains a separate print fact.
- Tenant switching is represented as available, blocked by unfinished cash count/shift close, and
  unavailable offline. Switching never bypasses state inspection or online target revalidation.
- ST-032 and ST-033 require fresh corrected-render and canvas-link review; no Phase 02 screen is approved.

## Phase 03 coverage result

- Desktop uses a dense browse/cart composition with legible products, quantities, KES prices and
  total, tender assertion, and one `Save sale` action. The same working screen includes the required
  labeled 834px two-region tablet specimen.
- Mobile remains staged: product browse/search/filter with a sticky cart summary, followed by a
  separate cart/review surface with quantity editing, removal, KES 135.00 total, tender assertion,
  and `Save sale`.
- Stock shortage is informational and does not disable the product or block saving. Tender records
  what the cashier asserts and never claims external verification.
- Local durability, later server confirmation, and receipt-print failure are separate facts. The
  durable receipt remains successful when printing fails; recovery points the cashier to Receipts
  waiting from the business home without inventing a direct checkout action.
- The first desktop successor used an invented connection-specific save error and omitted the tablet
  specimen. ST-035 corrected both with the active generic refusal text and a visible 834px layout.
- ST-035 was freshly retrieved and visually reviewed. ST-036 and the mobile-browse successor remain
  render-review items because retrieval became invalid/stale; the browse successor ID must be
  recovered from the Stitch UI rather than regenerated.

## Phase 04 coverage result

- Cashier receives a read-only catalog with product, category, code, recorded stock, and unit price;
  catalog-write and stock-route actions are absent.
- Manager receives category/product creation, operational name/code/category correction, pasted-text
  bulk work, stock adjustment, movements, and ledgers. Existing-price correction, cost, cost removal,
  and retirement are omitted; the required first price remains available when creating a product.
- Owner/Administrator additionally receives existing unit-price/unit-cost correction, recorded-cost
  removal, and retirement. Retirement preserves sales and ledger history and moves no stock.
- Bulk work is comma/tab/semicolon-delimited pasted text with row-by-row preview, row errors, explicit
  apply/create commit, and committed results. `.xlsx` and file-upload behavior remain excluded.
- Recorded stock may be negative and never blocks a sale. Adjustments require type, direction where
  applicable, units, and a free-text reason; they are permanent and corrected by another adjustment.
- Manual adjustment feed, all-source movement feed, and one-product ledger retain signed delta,
  before/after, type, reason/source, actor, and recorded UTC time. Lists do not imply chronological
  order.
- Desktop includes a deliberate 834px tablet transformation; mobile uses stacked record cards rather
  than horizontal table truncation. Loading, empty, read-error, and offline-write states are included.
- The first successors ST-037/ST-038 were rejected for compressed/unsupported navigation and missing
  evidence. ST-039/ST-040 are the corrected working set. ST-039's core layout was visually reviewed,
  but its final audit-record correction serves a stale artifact; ST-040 retrieval is invalid. Both
  remain `NORMALIZED / REVIEW`.

## Phase 05 coverage result

- The analytical question is resolved narrowly: exact-value bars materially help compare the two
  evidenced daily sales totals and tender amounts; reconciliation, anomaly, run, and amendment data
  remain clearer as status cards, statistics, provenance rows, and tables. No derived trend,
  percentage, forecast, or unsupported dimension is allowed.
- ST-041 includes exact daily sales/transaction/shift values, owner/admin complete profit, a missing-
  cost refusal with no profit/margin figures, exact sales totals and tender buckets, server-held scope
  language, and the cashier-recorded-payment disclaimer.
- ST-041 separates matched, unusable-line, and different reconciliation specimens; includes the
  owner/admin request action, run `rj_000001`, and amendment `sm_a1b2c3`; and includes a read-only
  Manager history specimen. Its shift-correction action does not use the required exact label, and
  dense provenance rows still need full-size canvas review.
- ST-042 was not an acceptable responsive counterpart. An approved mobile remediation produced
  ST-043, a fresh 780x7794 single-column successor with supported daily/tender figures, profit
  refusal, Manager summary, matched/unusable/different states, all seven anomaly kinds, request/run/
  correction actions, and Manager amendment history. ST-042 is superseded.
- A final copy-only mutation reports successful restoration of Last 7/30/90 days, named-colleague
  scope, oldest-first processing, `system:sale_trigger`, counted cash, server-derived replacement
  totals, non-chronological ordering, and Manager history provenance. It also reports the exact ST-041
  correction-action label.
- Post-mutation retrieval is stale for ST-041 and invalid for ST-043. The mutation log additionally
  shows `Expected: 12` incorrectly relabelled as `Expectation ID: 12`; that label is not product truth.
- Phase 05 is `COMPLETED / RENDER REVIEW`: scope execution is closed, while neither screen is canonical
  until the current canvas render and anomaly label are reviewed. No Flutter or Firebase code changed.

## Phase 06 coverage result — completed, render review required

- The authorized CREATE operation returned desktop/tablet ST-044 and mobile ST-045 using the retained
  Profound Verdant asset.
- ST-044 cannot support any acceptance claim: its downloadable screenshot is blank, its HTML is only
  a 224-byte shell, and individual retrieval returns invalid argument.
- ST-045 is freshly retrievable and visually reviewed, but it stops after receipt lookup, adds an
  unsupported generic bottom bar, and omits sale detail, shift history, shift sales, returns,
  confirmations, role separation, tablet behavior, and most required state specimens.
- The approved CORRECT operation on ST-044/ST-045 returned derived successors ST-046/ST-047.
- ST-046 is retrievable but is still a 2048px receipt-only fragment, contains conflicting `Kijani POS`
  branding, and omits sale/shift/return/tablet/state coverage. It is non-canonical.
- ST-047 is a 780x7452 long-form mobile successor. It removes generic bottom navigation and includes
  the core lookup, immutable sale, shift, return, and confirmation trail. It remains partial: artifact
  inspection does not find not-found/remote lookup, historical discount, no-closing-summary, the full
  failure matrix, or immutable stock-restoration ID evidence; individual retrieval is invalid.
- The approved final correction on ST-046/ST-047 returned ST-049 desktop and ST-048 mobile.
- ST-049 reports 14000px but its HTML ends after Section 02. Shift history, returns, confirmations,
  failure matrix, and the tablet specimen are absent.
- ST-048 is long-form and includes missing labels, but invents `Ceramic Mug - Green`, `Tax (16%)`, and
  `Amount to refund: KES 850.00`. These contradict active data and explicit exclusions.
- The approved surgical correction updated ST-048 in place and returned derived desktop ST-050 from
  ST-049. ST-048's DOM log removes the invented mug, tax, and refund content, but retrieval remains on
  its pre-edit artifact. ST-050 freshly rendered Sections 03-05 and contained no forbidden content.
- The final approved in-place ST-050 correction appends `Cash over` and desktop `No closing summary`
  cards. Its DOM-operation log also raises the shift filters/actions/pagination and both return-dialog
  action groups to at least 48px; Section 05 contains no interactive controls.
- Direct canvas-code copies proved the first final edits had not persisted. The approved exact-ID
  reapplications completed with concrete DOM operations for both screens; mobile retrieval remains
  cached and desktop retrieval is invalid.
- Phase 06 remains `COMPLETED / RENDER REVIEW`: required scope execution is closed, while fresh
  canvas-code inspection is required before canonical promotion or any additional edit.
- No Flutter, Firebase, schema, rule, deployment, or design-system change was made.

## Phase 07 coverage result — completed and visually reviewed

- The authorized `REPLACE` operation created desktop ST-051 and mobile ST-052. Artifact inspection
  rejected them because the desktop stopped after its directory and invented access-management
  routes, while mobile rendered two records, used `Admin`, and added unsupported navigation.
- The first approved correction produced ST-053/ST-054. ST-053 rendered the principal directory,
  Manager read-only composition, forms, five confirmations, failure states, and tablet frame, but
  retained bounded copy/tablet gaps. ST-054 ended after Manager read-only and kept icon-only actions.
- The final approved correction produced ST-055/ST-056. Fresh retrieval reports desktop
  2560x10764 and mobile 780x12822; both downloadable HTML files and full-height screenshots were
  inspected.
- ST-055/ST-056 use only Owner, Administrator, Manager, and Cashier. Owner/Administrator receive
  code-backed invitation, correction, activation/deactivation, resend, cancellation, and email-
  replacement actions; Manager sections contain zero buttons or inputs; Cashier has no directory
  route.
- Canonical rows keep membership and invitation progress distinct. Invalid/expired link recovery is
  outside the directory, has no Accept/Retry action, and directs the invitee to continue without the
  link or ask the inviter for a new invitation.
- Both suites include labeled forms, validation, busy, safe remote failure, success evidence, and all
  five person-specific consequence confirmations. Mobile actions are text-labeled; desktop and
  mobile controls resolve to at least 48px.
- The 834px tablet frame contains both Owner/Administrator write and Manager zero-write specimens
  without horizontal overflow. Unsupported permission models, roles, scheduling, last-shift/PIN,
  owner transfer, staff deletion, and unrelated navigation are absent.
- Phase 07 is `COMPLETED / VISUAL REVIEWED`. No Flutter, Firebase, schema, rule, deployment, or
  design-system change was made.

## Phase 08 coverage result — completed, render review

- The authorized `REPLACE` operation created desktop ST-057 and mobile ST-058. Artifact inspection
  rejected them because the desktop stopped after currency and mobile stopped after a minimal queue.
- Device-specific bounded corrections produced ST-059 and ST-060. Their downloadable HTML and
  full-height screenshots were inspected rather than accepting the generation summaries.
- Both successors limit checkout settings to the ISO 4217 currency code and printer settings to
  direct-TCP address, port, 32/48-column paper, and cutter behavior. Unsupported business, tax,
  branding, locale, synchronization, transport-selection, bridge-token, and receipt-preview controls
  are absent from the visible artifacts.
- Both state that the queue is device-local, preserve sale success independently of print outcome,
  use `sent` rather than claiming paper printed, and disclose unreadable durable records.
- Later bounded corrections produced ST-061/ST-062. Their successful DOM-operation logs add the
  printer read/write/test matrix, queue empty/read-only/busy/success/failure recovery, desktop 834px
  tablet specimen, and explicit interaction ledgers. The final mobile micro-correction records the
  missing failure endpoint and disabled loading semantics.
- Individual retrieval still serves the pre-operation ST-061/ST-062 HTML/screenshot files. The
  corrected pair is therefore mutation-reviewed and requires fresh canvas-code/render inspection.
- Fresh fallback generations ST-063/ST-064 were downloaded and rejected: mobile ends during Printer
  configuration, while desktop contains only one currency form, one printer form, and one queue row.
- Phase 08 is `COMPLETED / RENDER REVIEW`, not canonical approval. No Flutter, Firebase, schema,
  rule, deployment, or design-system change was made.

## Phase 09 coverage result — completed, mixed visual and mutation review

- The authorized `CREATE` operation returned incomplete desktop ST-065 and mobile ST-066; both were
  rejected after direct artifact inspection.
- Approved bounded corrections produced desktop ST-067 and mobile successor chain ST-068, ST-069,
  and final ST-070.
- ST-070 was freshly downloaded and inspected as HTML and a full-height screenshot. It contains all
  seven sections: distinct platform authority, pending admission, active/suspended lifecycle,
  rejected archive, exact-UID global user status, consequence matrix, and mobile interaction ledger.
- The mobile route specimens cover loading, empty, validation, busy, success evidence, conflict,
  permission loss, missing records, and remote failure. All interactive controls resolve to at least
  48px, including the partial-operation retry.
- Admission and tenant lifecycle use `setTenantLifecycle` with only pending→active/rejected,
  active↔suspended, and rejected→archived. Global disable/reactivation uses
  `setGlobalUserStatus`, one exact Firebase Auth UID, reason/confirmation guards, operation evidence,
  tenant impact warnings, and safe same-operation retry.
- User-copied current ST-067 canvas code confirmed that its reported corrections did not persist.
  A fresh correction produced ST-071, whose directly inspected HTML/screenshot verify the complete
  shell and primary product truth but retain bounded consequence, archived-warning, retry-help, and
  global busy/success defects. Its exact micro-correction event `356c191b` also did not persist.
- The explicitly authorized last fresh variant ST-072 fixes every bounded ST-071 defect and retains
  the correct callables and 48px controls, but incorrectly repeats the retry-operation help beneath
  unrelated invalid, permission, failure, self-disable, and archived-status chips. Direct exact-ID
  retrieval is invalid; the returned HTML and screenshot were inspected and rejected.
- A subsequent explicitly authorized cleanup produced desktop ST-073. Direct exact-ID retrieval
  succeeds and serves fresh HTML/screenshot files. Inspection verifies that retry help appears once
  visibly beneath its correct button, no paragraph is nested inside a span, all lifecycle/state
  corrections remain present, both real callables have the exact 5/2 row split, and all 48
  interactive elements meet the 48px minimum.
- No tenant-role authority, billing, portfolio management, owner transfer, bulk user action, role
  grant/revoke control, or invented callable is present in the final direction.
- Phase 09 is `COMPLETED / VISUAL REVIEWED`: desktop ST-073 and mobile ST-070 are canonical
  candidates. No Flutter, Firebase, schema, rule, deployment, or design-system change was made.

## Scope exclusions for the design audit

- No Flutter implementation changes.
- No server schema, callable, rule, index, deployment, or seed changes.
- No invented subscription/billing surface; backend schema is absent.
- No `.xlsx` import; current bulk flow is delimited text.
- No backfill of historical missing product costs.
- No new discount entry workflow. Discount data may exist historically, but the current checkout UI
  intentionally does not expose one.
- No archive/delete/move/group action in Stitch during this audit.
