> # RETIRED — 2026-08-27
>
> **Not authority.** The Stitch redesign, its phase briefs, handovers, open questions, coverage
> and audit trail are all retired. The pre-multitenancy app's look and flow is what recent work
> has been rebuilding on the multitenant backend, and **the developer directs that screen by
> screen** — their request outranks anything written here.
>
> Kept for reference and for the reasoning it records. Do not treat any decision, brief, matrix or
> checklist in this directory as a constraint on work the developer has asked for.

# Phases 01 and 02, structurally — 2026-08-22

Scope: the routing and permission contracts `prompt.md` asks to be implemented before any product
stream starts — *"Implement Phases 01 and 02 structurally during this wave because every tenant
workflow depends on their routing and permission contracts."*

Written during the unsupervised run, at commit `1687709`. **No Dart file was changed by this audit**,
and that is the finding rather than the caveat: every structural acceptance criterion of both phases is
already met, and four of the eight are now asserted by tests rather than by reading. What is left in
both phases is composition and copy, which is Wave 1's work and is bounded below.

---

## Phase 01 — authentication and tenant entry

### Acceptance criteria, against the code

| Criterion | State | Evidence |
|---|---|---|
| Each state has a single clear recovery action | **Met** | The sign-in surface draws exactly one action, `Sign in` (`login_screen.dart:392`). Refused and unreachable both recover by pressing it again, which is what ST-028 shows too: its refusal and connection specimens each carry one `Sign in` and nothing else. |
| Responsive compositions preserve labels, errors, focus, 48px | **Met, and photographed** | `01-sign-in` at both viewports, `01c-sign-in-refused-there`, `01d-sign-in-unreachable`, `01e-sign-in-caps-locked`. Field labels, the error notice and the focus ring are in the captures; 48px is enforced globally by the `AppDensity.compact` tripwire in `test/ui/tokens_test.dart`. |
| Tenant roles and platform claim are never conflated | **Met, and now asserted** | `test/tenancy/rbac_matrix_test.dart`. The `superAdmin` claim is read in one place (`main.dart:409`), reaches the shell as one callback, and is consumed only by `TenantBootstrapKind.platform` — a *different routing phase*, carrying a `PlatformReviewIdentity` rather than a `TenantMembership`. No value of `TenantRole` can reach a platform surface. |
| Copy does not promise unavailable recovery or provisioning | **Met** | Nothing in `login_screen.dart`, `sign_in.dart` or `account_verification.dart` offers a password reset, and `screenshots/README.md` records why: *"Recovering a forgotten password — the callable has no client surface."* The failure mapping's own note says the fallback "names no cause", because "telling somebody with a correct password to check their password is how a real fault stays hidden". |

### Two divergences from ST-028, both deliberate

**1. The refusal sentence is the app's, not the design's.** ST-028 shows *"Check the email address and
password for this account."* The app says *"That email address and password do not match an account.
Check both and try again."* — and it says something different for six other codes: an invalid address,
a disabled account, too many attempts, a provider that does not allow password sign-in, and two input
defects.

Kept as the app's, on `DESIGN_RULES.md` §8's grounds: the app's sentence states **what happened** and
then what to do, where the design's states only what to do. Collapsing seven answers into one would
lose the distinction the code already makes, and `prompt.md` is explicit that active code defines
behaviour. This is a copy divergence rather than a pixel one, and no layout depends on it.

**2. ST-028's mobile caps-lock hint has no counterpart, and should not get one.** The design shows
*"Caps Lock is on."* as a green hint under the password field on a phone.

The app answers the same need in a different place: the sign-in keypad — the on-screen keypad a till
with no hardware keyboard gets — carries its own caps state, and `01e-sign-in-caps-locked` is the
picture of it. **That capture is `web` only, deliberately: the keypad does not appear below 1264**, so
there is no keypad on a phone to be shifted.

Implementing the design's version would mean detecting a *physical* keyboard's lock state and
rendering a new field hint from it. That is new state and new logic, which `CLAUDE.md` hard rule 1
forbids in a visual change. **Recorded as design debt against Phase 01 rather than filled in**: if the
product wants a caps-lock hint on a phone, it is a behaviour slice with its own authorisation.

### What remains for Phase 01, and it is not structural

`LIVE_PHASE_HANDOFF.md` freezes the *design* at `PARTIAL / HOLD FOR REVIEW` and its pending list is
about Stitch artifacts, not Flutter: ST-027 still serving `Retry Connection` and `Remember me on this
terminal`, ST-031's overlapping lower cards and nested invalid-invitation card, and bounded copy on the
mobile successor. **None of that is implementable from here** — this session has no connector, the
export is the whole of the design truth, and the pending items are corrections to make *in Stitch*.

The app's own side of those items is already right where it can be checked: the app says `Sign in` and
`Remember me`, not `Retry Connection` and `Remember me on this terminal`.

---

## Phase 02 — role-aware home and navigation

### Acceptance criteria, against the code

| Criterion | State | Evidence |
|---|---|---|
| Every visible route is code-backed and role-correct | **Met, structurally** | `lib/main.dart` feeds each role-gated navigation slot the guard's **own constant** — `dailySummaryRoles: TenantDailyMetricsRepository.allowedRoles` and eleven more of that shape. The list the landing route hides by and the list the repository refuses by are the same object, so the matrix's *"Hidden actions must also be guarded in product code"* holds by construction. All 31 role lists are asserted against `RBAC_MATRIX.md` in `test/tenancy/rbac_matrix_test.dart`. |
| Mobile navigation is designed deliberately, not cropped | **Met, and photographed** | `HomeNavigation.showsMenu` draws the side menu at `expanded` and a **card grid** below it, with `columnsFor` giving 2 columns at `compact` and 3 at `medium`. That is a different rendering, not a narrowed one. `95-home-navigation-owner`, `-cashier`, `-empty`, `-stateful` at every width region, and `test/tenancy/tenant_safe_landing_test.dart` asserts the desktop destinations sit *beside* the page rather than in it. |
| Shift and local evidence have factual labels and recovery paths | **Met** | The shift is a `ShiftBanner` — status, standing in words, one line of detail, exactly one action, and §4.4's *"never a destination"* asserted at `test/ui/banner_test.dart:42`. Local evidence is the five-count readout below. |
| Owners do not lose administrator permissions; managers do not gain them | **Met, and now asserted** | `TenantRole.owner.canAccess([admin])` is true and nothing else satisfies anything, asserted both ways in `rbac_matrix_test.dart`. The staff directory row is worked through the hierarchy rather than as a literal: owner, admin and manager reach it; cashier does not; and the manager's *Read* is `_readOnly` being true exactly when neither write gateway is present. |

### The app is already right where ST-032 and ST-033 are wrong

`LIVE_PHASE_HANDOFF.md` records two defects in the served designs. Both are checked here and **neither
is present in the app**:

- **`Own shift panel` as a navigation destination.** Both artifacts still show it. In the app the shift
  is a banner and never a route — `grep` for `ownShiftRoute` or `Own shift panel` across the active
  tree finds nothing, and `ShiftBanner`'s own note carries §4.4's rule verbatim.
- **`KES 4,200.00 confirmed`.** ST-033 states the evidence as money. The app states it as **counts**,
  in exactly the five states the handoff says the served design does not show:
  `Saved offline`, `Submitting`, `Awaiting confirmation`, `Needs attention`, `Confirmed`
  (`checkout_evidence.dart:288-303`), each a count of checkouts and none of them a currency. Asserted
  in `test/checkout/checkout_evidence_test.dart`.

This is `prompt.md`'s *"Fidelity is not the goal where the design is factually wrong"* in its clearest
form: implementing ST-033 faithfully would replace a correct readout with an incorrect one.

### What remains for Phase 02

Composition, not contract. The role homes are the app's existing layout wearing the new tokens; ST-032
and ST-033 are the intended arrangement and both are `NORMALIZED / RENDER REVIEW`, meaning corrected
and never visually confirmed. Recomposing them is Wave 1 work and must carry the two corrections above
rather than the artifacts' own copy.

---

## Why this audit adds no test

Every structural claim above is already asserted somewhere, and four of them became assertions during
this run rather than before it:

| Claim | Where it is asserted |
|---|---|
| Roles and the platform claim are never conflated | `test/tenancy/rbac_matrix_test.dart` (new) |
| Owner inherits administrator; nobody else inherits anything | same (new) |
| Every role list matches `RBAC_MATRIX.md` | same, 31 lists (new) |
| No role list exists that the matrix has no row for | same, a source scan (new) |
| The shift is never a destination | `test/ui/banner_test.dart` |
| Desktop destinations sit beside the page | `test/tenancy/tenant_safe_landing_test.dart` |
| The evidence readout is five counts | `test/checkout/checkout_evidence_test.dart` |
| No fixture or copy names a fact the product lacks | `test/dev/product_vocabulary_test.dart` (new) |

Adding a ninth test that re-asserted one of these through a different route would be coverage theatre.
**What both phases still need is a visual pass, and a visual pass needs the composition decisions Wave
1 owns.**

## What this audit does not establish

- **That either phase is pixel-correct.** Neither is. ST-032 and ST-033 are `NORMALIZED / RENDER
  REVIEW`; ST-027 and ST-031 have named defects in the served artifacts; Phase 01 is frozen at
  `PARTIAL / HOLD FOR REVIEW`. Nothing here should be read as approval of a pixel.
- **That the server agrees.** Client-side role lists are asserted against a document. `firestore.rules`
  and the callables are the real boundary and `rules-tests/` is where that is shown.
- **Anything about motion.** No screenshot can show it, and nothing in this audit's scope touches it.
