# RBAC matrix

This matrix is derived from active Dart authorization lists and route composition. UI labels must
follow these exact tenant roles: `owner`, `admin`, `manager`, `cashier`. Owner satisfies checks that
allow administrator; there is no general role hierarchy. Platform `superAdmin` is a separate Firebase
custom claim and is not a fifth tenant role.

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

## Design implications

- Do not invent roles such as “Senior Cashier” or “Inventory Clerk”.
- Do not add granular permission toggles; active authorization is role-list based.
- A manager variant is materially different from an administrator variant on staff, money fields,
  reconciliation actions, profit, settings, printer, and audit surfaces.
- A cashier home should remain intentionally narrow, not appear as a disabled manager dashboard.
- Hidden actions must also be guarded in product code during implementation; visual hiding alone is
  never authorization.
