# Flutter tenant migration inventory

This inventory freezes the remaining root Firestore and callable migration
surface as of 2026-07-29. A row is not authorization to enable its screen. The
legacy hub, checkout, remaining mutations, reports, and returns remain
unreachable until each row is migrated and tested behind a live
`TenantSession`.

## Root Firestore paths

| Owner | Current root collections | Tenant-scoped replacement | State |
| --- | --- | --- | --- |
| `lib/config.dart` | `store` | `tenants/{tenantId}/configuration/branding` | Old page is commented out; read-only branding is now migrated separately. |
| `lib/pos/goods.dart` | `categories`, `alcohol` | `categories`, `products` below `TenantPaths` | Legacy screen and all mutations remain disabled. A separate guarded, paginated read-only catalog now uses the tenant paths. |
| `lib/services/bulk_update_service.dart` | `alcohol` | `products` below `TenantPaths` | Disabled mutation/import workflow. |
| `lib/services/bulk_upload_service.dart` | `alcohol` | `products` below `TenantPaths` | Disabled mutation/import workflow. |
| `lib/screens/users.dart` | `staff` | `staff` below `TenantPaths` | Legacy screen and mutations remain disabled. A separate owner/admin/manager-guarded, paginated directory uses canonical tenant paths, with typed owner/admin `inviteStaff` issuance, `updateStaffUser` editing, accepted non-owner `setStaffStatus` changes, and pending-member invitation resend/cancellation/email-replacement actions enabled. |
| `lib/services/shift_service.dart` | `staff`, `shifts`, `alcoholsales` | `staff`, `shifts`, `sales` below `TenantPaths` | Disabled shift and sales workflow. |
| `lib/screens/return_detail_screen.dart` | `alcohol`, `returns` | `products`, `returns` below `TenantPaths`; stock restoration through `verifyReturnAndRestoreStock` | Disabled mutation workflow. |
| `lib/screens/returns_screen.dart` | `staff`, `returns` | `staff`, `returns` below `TenantPaths` | Disabled returns workflow. |
| `lib/screens/main_hub_screen.dart` | `staff`, `store`, `shifts` | `staff`, `configuration/branding`, `shifts` below `TenantPaths` | Entire legacy hub remains unreachable. |
| `lib/pos/inv.dart` | `alcohol` | `products` below `TenantPaths` | Disabled stock mutation screen. |
| `lib/pos/pos.dart` | `shifts`, `categories`, `alcohol`, `alcoholsales` | `shifts`, `categories`, `products`, `sales` below `TenantPaths` | Disabled checkout; the read-only catalog does not enable this screen and checkout must use the later Hive single-flight state machine. |
| `lib/pos/services/returns_service.dart` | `alcoholsales`, `returns`, `staff`, `shifts` | `sales`, `returns`, `staff`, `shifts` below `TenantPaths` | Disabled returns workflow. |
| `lib/pos/reports.dart` | `categories`, `staff`, `alcoholsales`, `alcohol` | `categories`, `staff`, `sales`, `products` below `TenantPaths` | Disabled report screen. |
| `lib/pos/reports/debtpayment.dart` | `hwsales` | normalized `sales` snapshots below `TenantPaths` | Disabled legacy report; schema normalization required. |
| `lib/pos/reports/monthlyreports.dart` | `hwsales`, `hstock` | normalized `sales` and `products`/daily metrics below `TenantPaths` | Disabled legacy report; schema normalization required. |
| `lib/pos/reports/productreport.dart` | `hwsales` | normalized `sales` snapshots below `TenantPaths` | Disabled legacy report. |
| `lib/pos/reports/paymentsfreq.dart` | `alcoholsales` | `sales` snapshots below `TenantPaths` | Disabled legacy report. |
| `lib/pos/reports/shift_reports.dart` | `shifts` | `shifts` below `TenantPaths` | Disabled report. |
| `lib/pos/reports/profits.dart` | `alcoholsales`, `alcohol` | `sales`, `products` below `TenantPaths` | Disabled report. |
| `lib/pos/reports/salesReports.dart` | `alcoholsales`, `staff` | `sales`, `staff` below `TenantPaths` | Disabled report. |
| `lib/tenancy/firebase_tenant_gateway.dart` | `users/{uid}` | Remains the caller's root routing profile | Current and intentional; Rules restrict it to the caller. |

`lib/main.dart` configures `FirebaseFirestore` but does not select a collection.
All operational replacements above must be constructed from `TenantPaths`; no
repository may accept a raw root collection or arbitrary document path.

## Callable usage

| Owner | Current callable | Replacement | State |
| --- | --- | --- | --- |
| `lib/screens/create_user.dart` | `createStaffUser` | `inviteStaff({tenantId, ...})` | Legacy and disabled. |
| `lib/screens/users.dart` | `toggleStaffStatus` | `setStaffStatus({tenantId, uid, status, requestId})` | Legacy and disabled. |
| `lib/pos/reports.dart` | `getSalesComparison` | Same callable with tenant ID from the guarded session | Current backend API, frontend screen still disabled. |
| `lib/tenancy/firebase_tenant_gateway.dart` | `listMyTenants`, `setDefaultTenant` | No replacement | Current tenant-routing APIs. |
| `lib/tenancy/tenant_staff_invitation.dart` | `inviteStaff` | No replacement | Current owner/admin-only form. The gateway derives the tenant from its captured live session, creates one request ID per intent, and strictly decodes the response. |
| `lib/tenancy/tenant_staff_update.dart` | `updateStaffUser` | No replacement | Current owner/admin-only editor. The gateway derives the tenant and target UID from its captured session and decoded staff summary, preserves the owner role, and strictly decodes the response. |
| `lib/tenancy/tenant_staff_status.dart` | `setStaffStatus` | No replacement | Current owner/admin-only confirmation flow for accepted non-owner memberships. The gateway derives the tenant and target UID, permits only active/inactive transitions, creates one request ID per intent, and strictly decodes the response. |
| `lib/tenancy/tenant_staff_invitation_resend.dart` | `resendStaffInvitation` | No replacement | Current owner/admin-only confirmation flow for canonical pending invitations. The gateway derives the tenant and target UID, accepts only pending/sent invitation states, creates one request ID per intent, and strictly decodes the pending-enqueue delivery response. |
| `lib/tenancy/tenant_staff_invitation_cancellation.dart` | `cancelTenantInvitation` | No replacement | Current owner/admin-only destructive confirmation flow for canonical pending invitations. The gateway derives the tenant and target UID, normalizes the required audit reason, creates one request ID per intent, and strictly decodes the cancelled response with null delivery metadata. |
| `lib/tenancy/tenant_staff_invitation_email_replacement.dart` | `replacePendingStaffEmail` | No replacement | Current owner/admin-only confirmation flow for canonical pending invitations. The gateway derives the tenant and old target UID, normalizes the corrected email, rejects unchanged normalized addresses, creates one request ID per intent, and strictly decodes a distinct replacement UID with pending-enqueue delivery metadata. |
| `lib/tenancy/tenant_visible_invitation_acceptance.dart` | `acceptVisibleTenantInvitation` | No replacement | Current verified-user-only confirmation flow for visible pending tenant memberships in the routing selector. The gateway derives the tenant from the visible membership, binds the current verified/global-active caller, creates one request ID per intent, and strictly decodes the active membership/accepted invitation response. |
| `lib/tenancy/tenant_invitation_acceptance.dart` | `acceptTenantInvitation` | No replacement | Current authenticated email-link proof flow. The gateway derives the tenant, invited UID, invitation version, and token from one validated HTTPS invitation URI, binds the current Auth UID, creates one request ID per intent, and strictly decodes the active membership/accepted invitation response. |

Before enabling an operational route, search again for both direct Firestore
calls and collection references initialized in constructors. This inventory is
a migration checklist, not a substitute for a final adversarial path audit.
