# Illustration layout and copy audit

The follow-up reviewed 76 illustrated state call sites, plus the directly
rendered checkout, shift, onboarding and business-selection scenes.

19 additional placements needed centering: 16 `IllustratedMessage` rows and
3 illustrated `Callout` notices. They now use 168px artwork above centered copy.
Existing `EmptyState` and direct artwork placements were already centered.
The shift-close artwork was centered but small; it now uses the same scene size.
The renderer explicitly constrains each SVG to its scene square, so wide source
artwork cannot silently grow wider than other illustrations. Verification and
completion headings/captions are centered over the onboarding illustrations.

| Placements fixed | Count |
| --- | ---: |
| Bulk catalog: categories and products | 2 |
| Stock movements, adjustments, product ledger and stock detail | 4 |
| Stock-count held screen and due dialog | 2 |
| Receipt print queue | 1 |
| Production batch costs | 1 |
| Returns against a sale | 1 |
| Receipt lookup | 1 |
| Reconciliation differences and queued runs | 2 |
| Shift corrections | 1 |
| Supplier delivery entry | 1 |
| Bluetooth and USB printer notices | 2 |
| Missing reconciliation run notice | 1 |
| **Total** | **19** |

Copy was shortened in 63 of the 76 state call sites, covering 89 title, hint
and conditional-message variants. The remaining states already used brief copy.
Onboarding verification, completion and business selection were also reviewed
and shortened. Messages retain the action or explanation that matters, including
syncing requirements, blocked versus optional counting, filtered searches and
role restrictions. Transaction and permission behavior is unchanged.

Examples:

- Stock count: "Count and submit the stock to unlock this register."
- Optional count: "Count when ready. You can keep selling."
- Stock movements: "No stock movements yet."
- Customer list: "No customers yet" / "Add customers here or at the register."
- Receipt lookup: "Receipt not found. Check the number and business."

[The full audit](layout-copy-audit.json) records every reviewed state, its
component, whether centering changed, and the copy before and after this edit.
Line numbers refer to the source before formatting; use the file and message to
find a state in the final source.

Previews:

- [Stock count due: desktop](../../../screenshots/web/workflow-stock-count-blocking.png)
- [Stock count due: phone](../../../screenshots/mobile/workflow-stock-count-blocking.png)
- [Illustrated printer notice](../../../screenshots/mobile/workflow-illustrated-notice.png)
- [Centered stock movement state](../../../screenshots/web/workflow-compact-message.png)

Validation of the final code passed 1,184 tests across 52 test files, plus 22
desktop/phone captures. Targeted analysis of 55 source/test/capture files reported
no issues. The component checks assert centered artwork and copy, a 168px scene
square, copy below the artwork, and no overflow at 320px with doubled text size.
Workflow checks cover counting gates, transaction controls, permission states
and the existing list/filter behavior. Captures establish appearance and layout;
they do not claim a device/backend run.
