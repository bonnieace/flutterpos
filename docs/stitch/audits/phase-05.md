> # RETIRED — 2026-08-27
>
> **Not authority.** The Stitch redesign, its phase briefs, handovers, open questions, coverage
> and audit trail are all retired. The pre-multitenancy app's look and flow is what recent work
> has been rebuilding on the multitenant backend, and **the developer directs that screen by
> screen** — their request outranks anything written here.
>
> Kept for reference and for the reasoning it records. Do not treat any decision, brief, matrix or
> checklist in this directory as a constraint on work the developer has asked for.

# Phase 05 audit — reporting and reconciliation

Date: 2026-08-20

Project: `7478406619239162026`

Operation: one approved `CORRECT` mutation
Design system: Profound Verdant `assets/4c1cc58b4aed4b1693e6f8113ba1009a`, retained and not mutated

## Scope and evidence

Phase 05 used active `lib/reporting/` behavior, local screenshot groups 25-30, the RBAC matrix, and
existing Stitch sources ST-019, ST-020, ST-022, and ST-025. The approved correction covered daily
summary, scoped sales totals, profit completeness, reconciliation states, run detail, request action,
anomalies, and permanent shift amendments. CSV/export, forecasts, invented comparisons/calculations,
Manager profit, Manager writes, and all Phase 06 work were excluded.

The four existing source screens were selected together so Stitch could preserve their product
purpose. Stitch completed successfully but returned two derived consolidated suites instead of
overwriting the selected sources:

- ST-041 `80bcf18734c44f5dad68f49caf544058` — desktop, 2560x4752.
- ST-042 `7dbcfee9a4134038804e32ed000c8e9b` — mobile, 780x1768.

No second mutation was issued.

## Grounded visualization decision

Only two visual comparisons are justified by the available records: direct-label bars for daily sales
on 2026-08-17 and 2026-08-18, and exact-value tender bars/rows for the selected sales-total query.
Neither introduces a percentage, trend, target, forecast, or new grouping. Reconciliation states,
anomalies, one-run detail, and amendment history remain status/stat/provenance/table compositions,
where identifiers, before/after values, and action consequences are the primary reading task.

## Post-mutation verification

ST-041 was retrieved successfully after mutation. Its fresh screenshot and HTML confirm:

- exact daily values KES 910.00 and KES 1,225.00;
- exact total KES 6,420.50 and supported tender breakdown;
- the four-missing-cost profit refusal and no fabricated partial profit;
- `Payment recorded by the cashier; not verified.`;
- distinct reconciliation/unusable/different treatments;
- run `rj_000001`, amendment `sm_a1b2c3`, and `Ask for a check`;
- Profound Verdant identity and separate Manager read-only history.

ST-041 is not approved as canonical. The exact Owner/Administrator action label `Correct this shift's
totals` is absent from the HTML, and the 4752px overview is too dense to verify every difference-row
identifier and timestamp at the rendered review scale. It is `NORMALIZED / PARTIAL REVIEW`.

ST-042 failed individual retrieval immediately after the successful mutation. The artifact returned
inside the mutation response was still inspected and is materially non-conforming: it shows only an
incomplete reporting fragment, uses `Aug 18, 2023`, invents `+14% vs Prev` and unsupported totals, and
omits the required Phase 05 mobile reconciliation/profit-refusal/tender anchors. Under the stale-
retrieval rule it was not regenerated. It is `NON-CANONICAL / REWORK` and requires an explicitly
approved later mobile-only correction after Stitch UI review.

## Approved remediation

The user subsequently approved the recommended bounded Phase 05 remediation. A combined edit of
ST-041/ST-042 was rejected immediately as invalid and made no mutation. The same approved operation
was narrowed to the blocking mobile screen and succeeded as derived successor:

- ST-043 `e54d5ed714c44b9caa93b580c9c01eff` — mobile, 780x7794.

ST-043 was retrieved successfully after mutation. Its fresh screenshot and HTML verify:

- a full-height, single-column mobile composition without generic bottom navigation;
- exact KES 910.00, KES 1,225.00, and KES 6,420.50 reporting anchors;
- the four-line profit refusal, exact cashier-verification disclaimer, and no ST-042 `+14%`/2023/
  invented-total content;
- Owner/Administrator and Manager-labelled specimens, supported profit treatment, and read-only
  Manager history;
- matched, unusable-line, and different states, including all seven supported difference kinds;
- run `rj_000001`, amendment `sm_a1b2c3`, `Ask for a check`, and `Correct this shift's totals`.

The remediation is materially improved but not fully canonical. HTML inspection did not find exact
copy for Last 7/30/90 days, named-colleague scope, oldest-first processing, requester
`system:sale_trigger`, counted-cash unchanged, server-derived replacement totals, feed ordering, or
the manager/evidence identifiers. These omissions leave provenance and action-explanation acceptance
partial. No further mutation was issued in this remediation pass. ST-042 is superseded by ST-043.

## Final copy-only pass

The user explicitly instructed the agent to finish Phase 05, authorizing one final copy-only
correction on ST-041/ST-043. Stitch reported successful in-place DOM operations:

- ST-041: `Apply Correction` changed to exact `Correct this shift’s totals`.
- ST-043: full period/scope labels restored; whole-business/oldest-first request scope added;
  `system:sale_trigger` requester added; server-derived totals and unchanged counted-cash explanations
  added; Manager amendment history gained unchanged-transaction/cash, `manager-dev`, and non-
  chronological whole-business feed statements.

The operation did not change layout, numeric values, roles, navigation, design-system tokens, or
Phase 06 scope. However, the operation log also shows one incorrect transformation: the existing
anomaly row `Source ID: sl_99x88 | Expected: 12 | Recorded: 10` became `Source ID: sl_99x88 |
Expectation ID: 12 | Recorded: 10`. The value 12 is an expected quantity, not an expectation ID; the
new label is explicitly non-canonical.

Required post-mutation retrieval was attempted once. ST-041 remained retrievable but served the same
pre-edit artifact containing `Apply Correction`; ST-043 returned invalid argument. Under the operating
contract, no regeneration or repeated mutation was issued to force a fresh render. Both screens are
therefore `NORMALIZED / RENDER REVIEW`, with the anomaly label called out for canvas correction before
canonical promotion.

## RBAC and product-truth result

- Desktop direction preserves Owner/Administrator profit and write specimens and a Manager read-only
  specimen without Manager profit/write controls.
- Profit figures are suppressed when cost coverage is incomplete.
- Reconciled, unusable-line, and different states are not collapsed into one success treatment.
- Reconciliation request scope remains whole-business and distinct from the selected date.
- Shift amendments preserve server-derived replacement totals, unchanged counted cash, reason, actor,
  and evidence provenance in the intended direction.
- ST-043 removes the earlier incomplete/invented mobile data and represents the responsive/RBAC
  direction. Final mutation content and the known anomaly-label defect require canvas review.

## Repository and system impact

No Flutter, Firebase, schema, rules, deployment, or design-system change was made. Repository changes
are limited to the durable Stitch control documents and this audit.

## Final status

Phase 05 execution is closed as `COMPLETED / RENDER REVIEW`:

- ST-041: `NORMALIZED / RENDER REVIEW`.
- ST-042: `NON-CANONICAL / SUPERSEDED`.
- ST-043: `NORMALIZED / RENDER REVIEW`.
- Phase acceptance: required scope was executed and the mutation log covers the final copy, while
  stale retrieval and the known `Expectation ID: 12` mislabel prevent canonical approval.

## Recommended next phase

Proceed to Phase 06 for sales, receipts, returns, and shift history. Keep the ST-041/ST-043 fresh-render
check and restoration of `Expected: 12` as explicit visual-review debt; do not reopen Phase 05 or
regenerate screens merely to refresh retrieval. Phase 06 must not expand reporting/reconciliation.
