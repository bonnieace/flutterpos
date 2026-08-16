# Animated assets — `design.md` §6.4

**Empty on purpose.** The eight assets are sourced rather than authored, at the
product owner's direction on 2026-08-16, and the files are downloaded by hand
rather than fetched by a build step.

## The sourcing rule, which is not optional

An asset here is **monochrome or line-art**. That is the whole of what makes an
authored file survive a palette change: `lottie` can override a colour at runtime
through a value delegate, and a delegate addresses a *named layer*, so a file with
twenty differently-coloured shapes cannot be tinted from the theme and must be
refused. §6.4 originally rejected this whole format on exactly that ground.

## Licence

Free-tier LottieFiles, under the [Lottie Simple
License](https://lottiefiles.com/page/license): commercial use permitted,
attribution not required, modifications are derivative works under the same terms.
That last clause matters only if these files are ever redistributed as a library,
which they are not.

Record every file's source URL in the table below as it lands.

## The eight

| # | Asset | Where it goes | File | Source |
| --- | --- | --- | --- | --- |
| 1 | Check mark, draws on | Save sale | `check.json` | https://lottiefiles.com/free-animation/check-mark-success-h9SJbwh6ky |
| 2 | Sync glyph, four states | `SyncIndicator` | `sync.json` | https://lottiefiles.com/19991-cloud-sync-loading-loop-animation |
| 3 | Cash count result | Shift close | — | state machine; compose from 1 and a warning mark |
| 4 | Upload to server | Top bar queue button | `upload.json` | https://lottiefiles.com/12740-uploading-to-cloud |
| 5 | Reconciliation result | Reconciliation run | — | state machine; compose from 1 and a warning mark |
| 6 | Empty state mark | `EmptyState` | `empty.json` | https://lottiefiles.com/free-animation/empty-box-XtO1oiZwG6 |
| 7 | Business approved | Platform approval | `approved.json` | https://lottiefiles.com/free-animation/cat-line-animation-art-FRvtghbpW2 |
| 8 | Shift opened mark | `ShiftBanner` | — | reuse 1 at `spring.snappy` |

**Three have no link and that is deliberate.** Assets 3 and 5 are *state machines* —
balanced / short / over, clean / differences found — and a single generic file cannot
carry three outcomes honestly; they are composed from the check mark and a warning
mark with this app's own status colours, which also sidesteps colour-baking entirely.
Asset 8 is asset 1 played once.

## Budget, from §6.4 and still binding

Total external payload ≤ 120KB, any single asset ≤ 64KB, one concurrent asset, zero
idle loops on an operational screen, **zero assets on the sale path**.
