# Animated assets — `design.md` §6.4

The eight assets are sourced rather than authored, at the product owner's
direction on 2026-08-16, and the files are downloaded by hand rather than
fetched by a build step.

## What is here, audited 2026-08-16

Four files, **62KB of a 120KB budget**. Every one was read for its colour count
rather than eyeballed, because §6.4's sourcing rule is the whole of what makes an
authored asset survive a palette change.

| File | Size | Colours | Verdict |
| --- | --- | --- | --- |
| `approved.json` | 3.3KB | **1** — `#000000` | ✅ pure line art, one delegate tints it |
| `upload.json` | 17KB | **2** — black, white | ✅ line art |
| `sync.json` | 8.0KB | **3** — `#00B8FF`, `#F4B624`, white | ⚠️ tintable, but three delegates |
| `empty.json` | 33KB | **7** — beiges and oranges | ❌ **fails the rule** |

**`empty.json` is a coloured illustration, not line art**, and its seven warm
browns and oranges have nothing to do with this palette. §6.4's own withdrawn
sentence predicted exactly this file: *"generic mascots that will not match this
palette or this product, and using one is worse than using nothing."* It should
be replaced with a monochrome empty state before it is wired to anything.

**Tinting is not deferrable, and this is the thing to know.** `approved.json` is
pure `#000000` on a page whose background is `#0D1F16` — it is *invisible* until
it is tinted. The product owner's call was to defer colour-following until a
second palette exists; that stands for *following*, but the first tint has to
happen before any of these renders at all.

`sync.json`'s three colours are near-misses rather than matches: `#00B8FF` is not
`status.info` `#6FB7F2` and `#F4B624` is not `status.attention` `#F2C14E`. Close
enough to look like a mistake rather than a decision, which is worse than far off.

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
