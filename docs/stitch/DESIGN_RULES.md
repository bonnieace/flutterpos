# Stitch design rules

These rules guide Stitch exploration without importing the old Flutter layout contract.

## Product character

Chilltent POS is a trustworthy, high-density retail operating tool. It should feel calm, legible,
fast, and durable under imperfect connectivity. Operational surfaces prioritize scan speed and
touch accuracy; management surfaces may use more whitespace, but never decorative emptiness.

The current direction is **Profound Verdant**: dark green, tonal surfaces, restrained accents,
Hanken Grotesk for interface text, and JetBrains Mono where aligned figures or machine-readable
identifiers materially help. Corners are compact (generally 4-8 px in the Stitch system), tables
are flat rather than card-per-row, and status is never color-only.

## Theme and reuse contract

- Name tokens by meaning: `surface/base`, `surface/raised`, `text/primary`, `text/muted`,
  `action/primary`, `status/success`, `status/warning`, `status/error`, and so on.
- Do not bake literal colors, font sizes, radii, spacing, shadows, or motion into individual screens.
- Preserve a single semantic mapping layer so a future light theme or brand palette does not require
  screen-by-screen editing.
- Treat the current Profound Verdant values as a theme instance, not the product's identity itself.
- Resolve the design-system source discrepancy before implementation: its surface prose mentions
  both `#071610` and `#0A1A14`, and its primary definitions include both `#4BE277` and `#22C55E`.
  Until resolved, use semantic names in documentation and do not promote either literal as canonical.
- In Flutter implementation, map approved tokens into `ThemeData`/`AppTokens` (or a successor
  `ThemeExtension`). The old `AppLayout.contract` must not determine the new compositions.

## Layout principles

- Desktop: persistent navigation is acceptable; use the width for simultaneous context and action,
  especially a three-region sale surface when it improves flow.
- Tablet (768-1279 logical px): design deliberately, not as a squeezed desktop. Prefer two regions,
  collapsible navigation, and stable touch targets.
- Mobile (<768 logical px): one primary task per view, bottom sheets or staged flows for secondary
  context, and no hidden destructive action caused by overflow.
- Desktop (>1280 logical px): constrain reading-heavy pages but let operational grids/tables use
  available width.
- Keep primary actions stable across breakpoints. Do not move authorization-dependent controls into
  ambiguous overflow menus.
- Minimum interactive target: 48 logical px. Keyboard focus, hover, pressed, loading, disabled,
  error, and read-only states must be visible where relevant.

## Operational patterns

- Checkout optimizes product selection, cart inspection, tender assertion, durable save, and print
  outcome. The current product does not verify payment and does not collect VAT.
- A sale may be saved offline. Sync status must communicate evidence without blocking the sale path.
- Printing occurs after the sale is durable; printer failure creates a recoverable queue state and
  never implies the sale failed.
- Stock may warn but does not block a sale. Corrections need reason, actor, and audit context.
- Tables use aligned data, explicit empty/loading/error states, sticky context where useful, and a
  card/list transformation on narrow widths rather than horizontal truncation.
- Money, counts, receipt numbers, dates, and statuses need strong alignment and readable hierarchy.

## Content and truthfulness

- Product name is **Chilltent POS**. Do not use “Kijani POS” or generic “Operational Hub” branding.
- Use exact role labels: Owner, Administrator, Manager, Cashier.
- Do not depict controls unless the active code supports the action and the role may invoke it.
- Distinguish `saved locally`, `confirmed`, `waiting to print`, `printer unavailable`, and
  `reconciliation differs`; these are different facts.
- Do not call a payment “verified” or “processed” when the app only records the selected tender.
- Dates, currency, quantities, and examples should be plausible but must not imply unsupported
  locale, tax, export, terminal, scheduling, or reorder-threshold capabilities.

## Data visualization

- Charts, graphs, and other data visualizations are encouraged when they materially improve
  comprehension of metrics and dimensions supported by active product data.
- Presentation does not need to preserve the current UI. A supported table, statistic, or textual
  total may become a line chart, bar chart, stacked comparison, composition chart, sparkline, metric
  card, table, or combination chosen for the analytical question.
- Do not invent metrics, data sources, dimensions, calculations, comparison periods, forecasts, or
  analytical capabilities merely to populate a visualization. Every value and grouping must be
  derivable from evidenced records.
- Do not add charts for decoration. Prefer the representation that makes the supported information
  clearest at the target viewport.
- Profit and margin visualizations obey the same role and cost-completeness safeguards as textual
  figures. If incomplete costs prevent a complete figure, a chart must not imply one.

In short: **innovate in presentation; do not hallucinate data.**

## Review checklist

A screen is not canonical until it passes product behavior, RBAC, responsive, state, content,
accessibility, token reuse, and cross-screen consistency review. A visually polished but invented
workflow remains `CORRECT` or `REPLACE`, never `KEEP`.
