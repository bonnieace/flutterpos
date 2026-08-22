# RBAC matrix

This matrix is derived from active Dart authorization lists and route composition. UI labels must
follow these exact tenant roles: `owner`, `admin`, `manager`, `cashier`. Owner satisfies checks that
allow administrator; there is no general role hierarchy. Platform `superAdmin` is a separate Firebase
custom claim and is not a fifth tenant role.

> **Checked against the code on 2026-08-22, and now checked on every run.**
> `test/tenancy/rbac_matrix_test.dart` holds one entry per row and asserts the guard behind it, so
> this file stopped being a snapshot. **Every row agreed** {M} all 31 named role lists in `lib/` hold
> exactly what the table below gives them, and the scan in that file also fails if a role list exists
> anywhere in `lib/` that no row governs, so a capability cannot be added without a decision here.
>
> Two structural findings worth carrying, because they are why the agreement is not luck:
>
> - **The navigation is fed from the guards themselves.** `lib/main.dart` passes each role-gated slot
>   the repository's own constant {M} `dailySummaryRoles: TenantDailyMetricsRepository.allowedRoles`
>   and eleven more of that shape. So the list the landing route hides by and the list the repository
>   refuses by are the *same object*, and "hidden actions must also be guarded" below holds by
>   construction rather than by review.
> - **Two rows are a scope rather than a route.** *View management shift history* gates reading
>   another cashier's shifts, not the route: a cashier opens shift history and sees their own, and
>   `shift_history_panel.dart` hides the scope control behind the same predicate the repository
>   enforces. *Staff directory* is the mirror {M} a manager reaches the route and the screen's own
>   `_readOnly` resolves true exactly when the session holds neither write gateway.
>
> What is **not** checked here is the server. `firestore.rules` and the callables are the real
> boundary and `rules-tests/` is where that is proven; a client list agreeing with this table while
> the server disagreed is exactly the false comfort the last line of this file warns about.

Legend: **Full** = view and normal action; **Read** = view only or narrower action; **Own** = own
shift/session scope; **No** = no route/action.

| Capability | Owner | Administrator | Manager | Cashier | Evidence/constraint |
|---|---:|---:|---:|---:|---|
| Open business home | Full | Full | Full | Full | Active membership and tenant session required. |
| New sale / tender assertion | Full | Full | Full | Full | Checkout is available to every active member. |
| Local receipts waiting | Full | Full | Full | Full | Device-local print queue status. |
| Read-only catalog | Full | Full | Full | Full | Cashier may read stock through catalog. |
| Receipt lookup | Full | Full | Full | Full | `TenantReceiptLookupRepository.allowedRoles`. |
| Record pending return | Full | Full | Full | Full | Return request on a sale; verification differs below. |
| Change/default business | Full | Full | Full | Full | Only when another accessible membership exists; switching requires connectivity. |
| Open/close own shift | Own | Own | Own | Own | Session-bound local/server state. |
| View management shift history | Full | Full | Full | No | Manager-or-above management history. |
| Manage catalog operational fields | Full | Full | Full | No | Product/category operations for owner/admin/manager. |
| Change price or cost | Full | Full | No | No | Money fields are narrower than general catalog editing. |
| Retire product | Full | Full | No | No | `retireRoles`. |
| Bulk catalog changes/import | Full | Full | Full | No | Same management route boundary; money restrictions still apply. |
| Product stock and ledger | Full | Full | Full | No | Dedicated stock routes. |
| Create stock correction | Full | Full | Full | No | Reasoned/manual adjustment. |
| View stock adjustment/movement feeds | Full | Full | Full | No | Includes wider collection-group movement read. |
| Daily summary | Full | Full | Full | No | `TenantDailyMetricsRepository.allowedRoles`. |
| Sales totals | Full | Full | Full | No | Management reporting. |
| Reconciliation status/anomalies | Full | Full | Full | No | Read scope. |
| Request reconciliation run | Full | Full | No | No | Write/action restricted to owner/admin. |
| Shift amendment/correction action | Full | Full | No | No | Amendment feed may be readable to manager. |
| Profit/margin report | Full | Full | No | No | More restricted than daily summary. |
| Staff directory | Full | Full | Read | No | Manager sees read-only directory. |
| Invite/edit/disable/resend/cancel staff | Full | Full | No | No | Administrator capability; owner inherits it. |
| Checkout currency settings | Full | Full | No | No | Only currently supported checkout setting. |
| Printer configuration/test | Full | Full | No | No | Configuration write roles. Queue view remains broadly accessible. |
| Activity log | Full | Full | No | No | `TenantAuditLogRepository.allowedRoles`. |
| Verify return and restore stock | Full | Full | Full | No | Management verification. |

## Platform administration

The screenshot families `09a`-`09d` cover platform admission queue, tenant archive, and global-user
status. Those surfaces require the separate `platformRole == superAdmin` claim. A tenant owner or
administrator is not automatically a platform operator. Stitch currently has no verified canonical
platform-admin screen.

**Verified 2026-08-22: the separation is structural, not a role check.** The claim is read in exactly
one place {M} `lib/main.dart:409`, from the Firebase ID token {M} and reaches the shell as
`hasPlatformSuperAdminClaim`. It is consumed only by `TenantBootstrapKind.platform`, which is a
*different routing phase* from the tenant one and carries a `PlatformReviewIdentity` rather than a
`TenantMembership`. So no value of `TenantRole` can reach a platform surface, and no platform claim
grants a tenant capability. That is why the four role columns above have no platform row.

## Design implications

- Do not invent roles such as “Senior Cashier” or “Inventory Clerk”.
- Do not add granular permission toggles; active authorization is role-list based.
- A manager variant is materially different from an administrator variant on staff, money fields,
  reconciliation actions, profit, settings, printer, and audit surfaces.
- A cashier home should remain intentionally narrow, not appear as a disabled manager dashboard.
- Hidden actions must also be guarded in product code during implementation; visual hiding alone is
  never authorization.
