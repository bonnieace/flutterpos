> # RETIRED — 2026-08-27
>
> **Not authority.** The Stitch redesign, its phase briefs, handovers, open questions, coverage
> and audit trail are all retired. The pre-multitenancy app's look and flow is what recent work
> has been rebuilding on the multitenant backend, and **the developer directs that screen by
> screen** — their request outranks anything written here.
>
> Kept for reference and for the reasoning it records. Do not treat any decision, brief, matrix or
> checklist in this directory as a constraint on work the developer has asked for.

# Wave 0 components audit — 2026-08-22

Scope: the six components `prompt.md`'s Wave 0 list names and the foundations audit left unaudited —
**disabled, read-only, offline, busy, confirmation, provenance**. `EmptyState`, `LoadingState` and
`ErrorState` were audited with the foundations and exist in `lib/ui/states.dart`.

Written during the unsupervised run, at commit `b440c71`. No Dart file was changed by this audit;
Findings 5 and 6 are the two that ask for a change and each says exactly what.

**The headline is that four of the six need nothing built.** The orchestration prompt's list was
written before anybody looked, and it reads as six missing components. What is actually there is five
of the six already implemented — three as control *states* with photographed matrices, one as a
dialog, one as a status readout — and exactly one genuinely absent. Building six would mean building
four competing second systems next to working ones, which is the failure `prompt.md`'s own working
discipline names: *"do not create a competing local design system"*.

---

## Method

Each row below is a grep across `lib/` excluding `lib/pos/**` and `lib/screens/**`, cross-checked
against the case list in `tool/screenshots/`. A component counts as **covered** only when both hold:
something in `lib/ui/` implements it, and a screenshot case photographs the state. `CLAUDE.md` hard
rule 5 makes the second half mandatory, so an implementation nothing photographs is not done.

## Summary

| Component | Verdict | Where it lives | What photographs it |
|---|---|---|---|
| disabled | **Covered** | a state on six controls | `90-appbutton-disabled`, `92-appfield-states`, `93-disclosure-*`, `94-confirmdialog-disabled`, `95-filterchipbar-disabled`, `97-quantitystepper-disabled` |
| busy | **Covered** | `AppButton.loading`, `LoadingState` | `90-appbutton-loading`, `94-confirmdialog-loading`, `96-loadingstate-short`, `96-loadingstate-long` |
| confirmation | **Covered** | `ConfirmDialog`, `showConfirmDialog` | `94-confirmdialog-{tier}`, `-disabled`, `-loading`, `-without-reassurance` |
| offline | **Covered** | `SyncIndicator`, `SyncQueuePanel`, `AppNotice.offline` | `98-syncindicator-button`, `98-syncindicator-panel`, `93-status-{density}` |
| read-only | **Covered as a control state; inconsistent as a notice, and half of it unphotographed** | `AppTextField.readOnly`; `Callout(status: info)` at six sites | `92-appfield-states` has the field. Of the six notices, only three are in a picture: `13c`, `17`, `36c` |
| provenance | **Absent** | no component; the same expression written out **seven times** across five files | nothing photographs it as itself |

---

## Finding 1 — disabled is a state on six controls, and all six are photographed

Not a component, and the distinction matters: `DESIGN_RULES.md`'s accessibility line calls read-only
and disabled **states** — *"Keyboard focus, hover, pressed, loading, disabled, error, and read-only
states must be visible where relevant"* — and every control that can be disabled already carries one.

| Control | How it disables | Photographed as |
|---|---|---|
| `AppButton` | `onPressed: null` (`buttons.dart:189` treats loading as separate) | `90-appbutton-disabled` |
| `AppTextField`, `AppSelect` | `enabled: false` | `92-appfield-states` rows *disabled* and *AppSelect - disabled* |
| `Disclosure` | `enabled: false` (`status.dart:427`) | `93-disclosure-{state}` |
| `ConfirmDialog` | confirm action null | `94-confirmdialog-disabled` |
| `FilterChipBar` | per-chip | `95-filterchipbar-disabled` |
| `QuantityStepper` | `enabled: false`, plus `no-increment` / `no-decrement` at the bounds | `97-quantitystepper-disabled` and the two bound cases |

**A page-level "everything here is disabled" treatment does not exist and should not be built.**
`RBAC_MATRIX.md`'s design implications rule it out directly: *"A cashier home should remain
intentionally narrow, not appear as a disabled manager dashboard."* The app already obeys that —
`11-business-home-cashier`'s own caption reads *"Four of the owner's buttons are absent rather than
disabled."* Absent, not disabled, is the decided treatment for a capability a role does not have.

## Finding 2 — busy is `AppButton.loading` plus `LoadingState`, and the split is deliberate

Two different facts, two treatments, and neither is missing.

- **A control is working**: `AppButton.loading` holds the container and replaces the label with an
  indicator (`buttons.dart:124`), and `_enabled` is `onPressed != null && !loading` — so loading is
  explicitly *not* disabled. The screen-reader label becomes `'$label, working'` (`buttons.dart:307`),
  which is §9's requirement that state never be visual only.
- **A read has not answered**: `LoadingState`, whose message is **required** because the four things
  it covers on the routing shell alone are checking a sign-in, opening an account, opening a business
  and signing out.

**What panels do have is a `busy` flag threaded per control** — `enabled: !busy` on each field, seen
in `catalog_management_panel.dart`, `checkout_configuration_panel.dart` and
`checkout_print_configuration_panel.dart`. That is per-control and reads correctly; a shared
"page is busy" wrapper would have to decide which controls a write locks, which is business meaning
and does not belong in `lib/ui/`. Left alone deliberately.

## Finding 3 — confirmation is `ConfirmDialog`, with the widest matrix of the six

`dialogs.dart:232` and `showConfirmDialog` at `:367`. Its matrix carries one case per tier plus
disabled, loading, and `without-reassurance` — the last being the case that exists because a
confirmation with nothing reassuring to say must not invent one. `AppDialog.maximumWidth` reads
`AppLayout.contract.reading`, so it takes §4.2's row rather than a number.

Nothing to build. Worth noting for later phases: `Disclosure.dialogSummaryCharacterBudget` (24) is a
separate, tighter budget from the 32 used outside a dialog, so a confirmation that folds long copy has
its own limit already.

## Finding 4 — offline has three treatments and they are three different facts

This is the one row where the *count* looks like duplication and is not. `DESIGN_RULES.md` requires
exactly this separation: *"Distinguish `saved locally`, `confirmed`, `waiting to print`, `printer
unavailable`, and `reconciliation differs`; these are different facts."*

- `SyncIndicator` — a count on a control, with `needsAttention` deciding the badge role. Its own note
  records the rule that makes it useful: *"confirmed checkouts are not news; two saved offline are."*
- `SyncQueuePanel` — the five-line queue itself, with its own empty message.
- `AppNotice.offline(...)` — one sentence about a write that was not attempted, fixed at
  `AppStatus.info` (`status.dart:129`), rendered by the caller as a `Callout`.

All three are photographed. The mapping from a real connectivity state onto §2.1's five statuses stays
with the caller, which is the same rule `AppNotice` and `ShiftBanner` both state: a component in
`lib/ui/` that decided which status a shift or a queue *is* would be deciding business meaning.

## Finding 5 — read-only is two facts wearing one word, and one of six sites renders it wrong

**The control state is covered.** `AppTextField.readOnly` (`fields.dart:128`) is distinct from
`enabled` and is photographed as its own row in `92-appfield-states`: *"read-only — holds a value that
may not be changed."*

**The notice is where the drift is.** Six sites tell a person that a surface cannot be changed, and
they resolve into a clean two-tier pattern that five of the six already follow:

| Site | Rendering | The condition means |
|---|---|---|
| `catalog-read-only` (`tenant_catalog.dart:423`) | `Callout(info)` **with a title** | route capability absent |
| `staff-directory-read-only` (`tenant_staff_directory.dart:374`) | `Callout(info)` **with a title** | **role** — `session.canAccess` |
| `catalog-management-read-only` (`catalog_management_panel.dart:823`) | `Callout(info)`, untitled | build — `writer != null` |
| `catalog-management-product-read-only` (`:923`) | `Callout(info)`, untitled | build |
| `printer-configuration-read-only` (`checkout_print_configuration_panel.dart:464`) | `Callout(info)`, untitled | build — `canPublish` |
| `checkout-configuration-read-only` (`checkout_configuration_panel.dart:347`) | **a bare `Text`** | build — `canPublish` |

**The pattern, stated from the evidence rather than invented:** a **titled** `info` `Callout` is the
standing of the whole page, and an **untitled** one is a single control that is not available here.
That is not a rule anybody wrote down; it is what five sites independently agreed on, and it is worth
writing down precisely because the sixth did not.

⛔ **`checkout-configuration-read-only` is a defect, not a variant.** It is the same fact, under the
same `!canPublish` condition, in the same feature folder as
`printer-configuration-read-only` — which is a `Callout` — and it renders as body prose with **no
container, no glyph and no status role at all**. §9 and `DESIGN_RULES.md` both require that status
never be carried by colour alone; this site carries it by *nothing*, which is the same failure one
step further along. It is the exact shape `AppNotice`'s own note describes: *"seven panels invented the
same half-model independently… rendered it as a bare `Text`."*

⛔ **And here is how it survived: three of the six notices are photographed by nothing.** Every
capture that reaches one of the build-gated sites injects the writer, so the notice never renders in
the picture:

| Notice | In a screenshot? |
|---|---|
| `catalog-read-only` | **yes** — `17-read-only-catalog` |
| `staff-directory-read-only` | **yes** — `13c-staff-directory-read-only` |
| `printer-configuration-read-only` | **yes** — `36c-printer-settings-read-only` |
| `catalog-management-read-only` | no — `18-manage-catalog` passes `FakeCatalogWriter()` |
| `catalog-management-product-read-only` | no — same capture, same reason |
| `checkout-configuration-read-only` | no — `16-checkout-settings` passes `FakeCheckoutConfigurationWriter()` |

That is a `CLAUDE.md` hard rule 5 failure in its own right, independent of the rendering defect, and it
is the mechanism: the one site that renders read-only wrongly is a site no picture has ever contained.
The three that are photographed are the three that are right. Fixing the rendering without adding the
captures would leave the same hole open for the next site.

**Recommendation: fix the site, and pin the pattern with a scan rather than a new component.**
`Callout` already is the read-only component and already has a photographed matrix
(`93-status-{density}` renders all five statuses). A `ReadOnlyNotice` wrapper would add a name, a
second matrix and six migrated call sites in order to choose `AppStatus.info` — abstraction where a
one-line correction and a tripwire do the same work. The repository's own habit is the tripwire: the
48dp guarantee, the `pubspec.yaml` family scan, and the harness width-region scan are all source scans
over things a type cannot express. So:

1. Render `checkout-configuration-read-only` as an untitled `info` `Callout`, matching its four
   siblings. Presentational only; the `!canPublish` condition is untouched.
2. Add a scan asserting every `ValueKey` ending `-read-only` sits on a `Callout` with
   `status: AppStatus.info`, so a seventh site cannot quietly invent a seventh rendering.
3. Photograph the three notices that no capture contains, by adding the write-less variant of each
   surface. That is what makes rule 5 true here rather than nearly true, and it is the check that
   would have caught the defect in 1.

**One site is deliberately silent and must stay that way.** `checkout_print_queue_panel.dart:190`
omits the retry action entirely when `onRetry` is null and says nothing about it — no notice. That is
the decided treatment, recorded in `37c-receipts-waiting-read-only`'s caption: *"a statement of what is
waiting, and no control that would fail."* The scan must not push a notice onto it.

**And the two facts must not be collapsed.** `staff-directory-read-only` fires on a **role** and its
copy names the roles that can act; the other five fire because a **build** has no writer injected and
say "this build". A future component that merged them would make the app claim a permission boundary
where there is only a missing dependency. `RBAC_MATRIX.md` has exactly one role-based read-only row —
*Staff directory | Full | Full | Read | No* — and that is the only site allowed to speak in role
terms.

## Finding 6 — provenance is the one genuinely absent component

§5.2 gives provenance a specification — `caption` / `text.tertiary`, the instant first and then the
actor — and **nothing implements it**. What exists is the same expression written out seven times
across five files:

```dart
Text(
  <label>,
  style: tokens.typography.caption.copyWith(color: tokens.colors.text.tertiary),
)
```

| Site | What it renders |
|---|---|
| `record_list.dart:703` | `item.provenance`, card form |
| `record_list.dart:1237` | `item.provenance`, table form — **byte-identical to the card one** |
| `daily_metrics_panel.dart:353` | `Reconciled {instant}`, commented *"§5.2's provenance row"* |
| `reconciliation_run_panel.dart:391` | `Requested by {actor}`, commented *"§5.2's provenance **rows**"* |
| `reconciliation_run_panel.dart:398` | the instants — the second of that pair |
| `reconciliation_status_panel.dart:514` | the instants, commented *"§5.2's provenance row"* |
| `reconciliation_anomalies_panel.dart:649` | `reconciliationDifferenceProvenance(anomaly)` |

Four of those carry a comment naming the section they are implementing by hand, which is the clearest
possible signal that the abstraction is missing rather than declined. **The two inside `RecordList` are
identical to each other**, so one component replaces both without a parameter to tell them apart.

**The style pair is not the identifying feature, and that is worth stating because it rules out the
cheap fix.** `caption` with `text.tertiary` appears **29 times** in `lib/` and only these seven are
provenance; the other 22 are stat details, helper lines, cart notes and figure captions. So a source
scan over the style would be wrong, and unlike Finding 5 this cannot be pinned by a tripwire. The
concept needs a name, which means it needs a widget.

⛔ **The drift this prevents has already happened once.** `stock_adjustment_panel.dart:737` folds a
provenance string into a `Callout.message` after a `\n`, so it renders at the callout's body style and
colour rather than at `caption` / `text.tertiary`. That is the same sentence about the same kind of
fact, two type roles away from where §5.2 puts it, and no test or picture distinguishes them.

`RecordList` has the data side half-solved: `RecordItem.provenance` is a `String?` with a
`provenanceKey` (`record_list.dart:267`), and six callers build the label —
`audit_log_panel.dart:325`, `stock_movement_labels.dart:170` and `:214`,
`shift_amendment_feed_panel.dart:331`, `return_history_panel.dart:607`,
`stock_adjustment_panel.dart:737`. So the *label* has owners and the *rendering* has none.

**Recommendation: build `ProvenanceLine` in `lib/ui/states.dart`, following the shape of the three
states already there**, and migrate all seven renderings. It takes a string and nothing else — the
label format stays with the callers that already own it, for the same reason `ShiftBanner` takes a
status rather than a shift. Its matrix is what actually varies: one line, a pair of lines, a label long
enough to wrap, and both densities. `AUTONOMOUS_HANDOVER.md` §7 requires each of those in the harness
before it is done.

**One thing to check while migrating, not to decide here:** `record_list.dart:921` uses the caption
style inside the narrow-loss column allocator, and it is **arithmetic rather than a rendering** —
`text()` returns a width. It must keep measuring the same style the component draws, so the two have to
move together or the table's columns will be allocated against a style nothing paints.

---

## What this audit does not cover

- **RBAC route guards against `RBAC_MATRIX.md`**, and **test fixtures built from supported Chilltent
  facts**. Both are the rest of `AUTONOMOUS_HANDOVER.md` order-of-work item 2 and neither is a
  component; they are audited separately.
- **Whether the copy at any read-only site is the right copy.** This audit checks that a fact is
  rendered as the kind of thing it is, not that its wording is final.
- **Motion.** No component here animates except `Disclosure`'s reveal and `EmptyState`'s draw-on, both
  already recorded as device checks. A screenshot cannot show either.
