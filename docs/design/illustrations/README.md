# Illustration visibility audit

Audited and repainted 2026-10-13 against the active `AppTokens.uzapay` theme.
The baseline findings below explain the changes implemented at the end.

The subsequent [workflow coverage audit](COVERAGE.md) and
[implementation](IMPLEMENTATION.md) add 40 purpose-drawn scenes and connect
the missing and mismatched screen states, with current previews and validation.

The [layout and copy audit](LAYOUT_AND_COPY.md) covers the later centering and
shorter descriptions across the illustrated states.

## Cause

The original `lib/ui/illustration.dart` applied `_UndrawPalette` to every `AppIllustration`.
The mapper preserves only the source accent (`#6C63FF`), changing it to mint.
Every other source color is assigned to one of seven text or surface colors
based on luminance. Skin, hair, clothing and object materials lose their hues.
Several distinct source colors also land in the same bucket, erasing shading.

The darkest four ramp stops have weak separation from the actual backgrounds:

| Mapped color | Page `#0D1F16` | Raised/dialog `#132A1F` |
| --- | ---: | ---: |
| `#2C5340` | 1.97:1 | 1.75:1 |
| `#1C3328` | 1.27:1 | 1.13:1 |
| `#132A1F` | 1.13:1 | 1.00:1 |
| `#08140E` | 1.10:1 | 1.23:1 |

These are opaque color contrast measurements, not a claim that decorative
illustrations must pass a text accessibility threshold. SVG opacity can make
the visible separation weaker still.

## Culprits

| Priority | Assets | Visible loss and affected uses |
| --- | --- | --- |
| Highest | `file-search.svg`, `no-data.svg` | Large document fills and details become background greens. Search results, customer/supplier records, sales and reporting empty states. |
| Highest | `schedule.svg`, `calendar.svg` | Calendar grids/panels and skin lose separation. Shift gate, Start your shift dialog, shift history and monthly reports. |
| Highest | `approve.svg` | Shirt, skin, document rows and leaves become dark green. Onboarding completion, notifications, production, business requests and shift-close outcomes. |
| Next | `empty.svg`, `access-denied.svg` | Shirts, skin, device details and plants fade. Empty catalog, restricted expenses/branding and unsuccessful shift-close outcomes. |
| Next | `printing-invoices.svg`, `logistics.svg` | Multiple original grays merge into white; other panels vanish into dark green. Printing/boxes lose depth. Customer and supplier directories use logistics; printing-invoices is currently a preview asset. |
| Color/fidelity | `team.svg`, `my-files.svg`, `empty-wallet.svg` | The main shapes remain readable, but natural skin and dark hair become green/sage/white. Staff directory and catalog ledger previews lose character and depth. |
| Color/fidelity | `mail-sent.svg` | Envelope planes become dark green. Verification stays recognizable through the outline and mint check, but the envelope loses its paper material. |
| Preview only | `empty-cart.svg` | Cart body is nearly background-colored; clothing tones merge into white. No current production call site. |

All 14 SVGs pass through the same restriction. The priority above is a visual
judgment from fresh raster captures, rather than a ranking by source color count.

## Suggested correction

Add dedicated illustration roles to `AppTokens`: cool blue/violet, warm
coral/amber, natural skin tones, contrasting paper/object fills, ink and shading.
Keep mint as a brand accent. Map materials and source color families deliberately
instead of treating every color as a point on a surface ramp. Keep neighboring
planes distinct, and check each illustration against both page and dialog grounds.
Simply adding another accent would leave the disappearing object fills unresolved.

The assets are already vector artwork; the flattening happens in the renderer.
Replacing them with higher-resolution raster files would not fix this mapping.

## Implemented artwork

All 14 scenes now use a coordinated palette of jade, teal, sky blue, lilac,
coral and amber, with warm skin tones, chestnut hair, blue-gray ink and cream
paper. SVG paint IDs distinguish materials and details sharing a source color.
Gentle gradients add depth to the wallet, paper panels, clothing and search lens.
Calendar entries, receipt icons and staff outfits receive individual accents.
The envelope also has an opaque front plane so it stays visible on dark ground.

The colors live in `AppColorRoles.illustration`, including gradient stops;
they follow theme interpolation. Unknown future source colors retain hue.
All opaque scene pigments meet 3:1 against page and raised/dialog backgrounds.
Symbol ink instead meets 3:1 against the accents it is drawn inside. These
measurements do not assert that every anti-aliased line or translucent SVG
shadow meets 3:1. The vector artwork remains crisp at different display sizes.

## Evidence

`screenshots/audit/illustration-before.png` preserves the original comparison.
`screenshots/audit/illustration-artistic-gallery.png` shows the repainted set on
both page and dialog backgrounds, each constrained to a 168px square. Reproduce:

```powershell
flutter test tool/screenshots/illustration_audit_test.dart --reporter expanded
```

Regression checks cover background contrast, symbol contrast, paint markers,
gradient references, skin/paper materials, opacity, unknown-color hue and SVG
cache separation between scenes. The gallery and empty-state captures establish
static appearance in the current widget renderer; no device run was performed.

Validation: 170 focused tests and screenshot cases passed; targeted Flutter
analysis reported no issues.
