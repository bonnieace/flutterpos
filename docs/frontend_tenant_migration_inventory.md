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
| `lib/pos/pos.dart` | `shifts`, `categories`, `alcohol`, `alcoholsales` | `shifts`, `categories`, `products`, `sales` below `TenantPaths` | Disabled checkout; neither the read-only catalog nor the offline catalog cache enables this screen. The encrypted Hive outbox, draft builder, and single-flight submission worker now own the sale write path, and any future checkout UI must produce its drafts through `CheckoutDraftService`. |
| `lib/pos/services/returns_service.dart` | `alcoholsales`, `returns`, `staff`, `shifts` | `sales`, `returns`, `staff`, `shifts` below `TenantPaths` | Disabled returns workflow. |
| `lib/pos/reports.dart` | `categories`, `staff`, `alcoholsales`, `alcohol` | `categories`, `staff`, `sales`, `products` below `TenantPaths` | Disabled report screen. |
| `lib/pos/reports/debtpayment.dart` | `hwsales` | normalized `sales` snapshots below `TenantPaths` | Disabled legacy report; schema normalization required. |
| `lib/pos/reports/monthlyreports.dart` | `hwsales`, `hstock` | normalized `sales` and `products`/daily metrics below `TenantPaths` | Disabled legacy report; schema normalization required. |
| `lib/pos/reports/productreport.dart` | `hwsales` | normalized `sales` snapshots below `TenantPaths` | Disabled legacy report. |
| `lib/pos/reports/paymentsfreq.dart` | `alcoholsales` | `sales` snapshots below `TenantPaths` | Disabled legacy report. |
| `lib/pos/reports/shift_reports.dart` | `shifts` | `shifts` below `TenantPaths` | Disabled report. |
| `lib/pos/reports/profits.dart` | `alcoholsales`, `alcohol` | `sales`, `products` below `TenantPaths` | Disabled report. |
| `lib/pos/reports/salesReports.dart` | `alcoholsales`, `staff` | `sales`, `staff` below `TenantPaths` | Disabled report. |
| `lib/checkout/checkout_submission.dart` | None | `sales/{checkoutId}` and `products/{productId}` below `TenantPaths` | Current single-flight checkout write path. One atomic batch creates the deterministic sale with a server `createdAt` and decrements only the exact tenant products named by the immutable payload. It writes no legacy root collection and no checkout UI is reachable. |
| `lib/checkout/checkout_confirmation.dart` | None | `sales/{checkoutId}` below `TenantPaths` | Current server-only confirmation read for uncertain submissions. |
| `lib/checkout/checkout_catalog_cache.dart` | None | `categories` and `products` below `TenantPaths`, read only through `TenantCatalogRepository` | Current encrypted offline catalog cache. It reads no Firestore path of its own, is keyed by `{uid}:{tenantId}`, re-validates every cached document through the strict catalog read models, and is derived data that never authorizes anything. |
| `lib/checkout/checkout_draft.dart` | None | None; writes only the encrypted local outbox | Current deterministic draft builder. It produces the frozen `CheckoutSalePayload` v1 contract from cached products and saves through `HiveCheckoutOutbox.saveOffline`; it never writes Firestore and is not reachable from any screen. |
| `lib/tenancy/firebase_tenant_gateway.dart` | `users/{uid}` | Remains the caller's root routing profile | Current and intentional; Rules restrict it to the caller. |
| `lib/tenancy/platform_tenant_review.dart` | `tenants`, `users/{ownerUid}` | Remains the canonical platform pending-tenant queue and owner profile metadata | Current claim-and-root-gated, read-only platform queue. It is bounded, ordered by request time and tenant ID, and exposes only pending tenants for explicit lifecycle review. |
| `lib/tenancy/platform_tenant_lifecycle.dart` | `tenants`, `users/{ownerUid}` | Remains the canonical platform active/suspended tenant queue and owner profile metadata | Current claim-and-root-gated, read-only platform queue. It is independent from pending review, bounded, and ordered by status, last update time, and tenant ID. It enables only explicit suspension and reactivation review. |
| `lib/tenancy/platform_tenant_archival.dart` | `tenants`, `users/{ownerUid}` | Remains the canonical platform rejected-tenant queue and owner profile metadata | Current claim-and-root-gated, read-only platform queue. It is independent from pending and active/suspended management, bounded, and ordered by lifecycle update time and tenant ID. It enables only explicit rejected-to-archived review. |
| `lib/tenancy/platform_global_user_status.dart` | `users/{uid}`, canonical tenant ownership and staff/admin evidence | Remains the canonical exact-UID platform global-user review | Current claim-and-root-gated exact lookup. A bounded server callable performs the authoritative canonical scans and returns one strict projection, preserving the deny-by-default legacy root `staff` boundary. It does not expose a directory, search, pagination, bulk action, or platform-role management. |

`lib/main.dart` configures `FirebaseFirestore` but does not select a collection.
All operational replacements above must be constructed from `TenantPaths`; no
repository may accept a raw root collection or arbitrary document path.

## Callable usage

| Owner | Current callable | Replacement | State |
| --- | --- | --- | --- |
| `lib/screens/create_user.dart` | `createStaffUser` | `inviteStaff({tenantId, ...})` | Legacy and disabled. |
| `lib/screens/users.dart` | `toggleStaffStatus` | `setStaffStatus({tenantId, uid, status, requestId})` | Legacy and disabled. |
| `lib/pos/reports.dart` | `getSalesComparison` | Same callable with tenant ID from the guarded session | Current backend API, frontend screen still disabled. |
| `lib/tenancy/firebase_tenant_gateway.dart` | `listMyTenants` | No replacement | Current read-only tenant-routing API. The former arbitrary-tenant default mutation helper was removed. |
| `lib/tenancy/tenant_default_tenant.dart` | `setDefaultTenant` | No replacement | Current all-active-role landing action. The gateway derives the tenant and caller binding from one captured active session, creates one request ID per confirmation intent, and strictly decodes exact tenant/default-tenant agreement. |
| `lib/tenancy/tenant_request.dart` | `requestTenant` | No replacement | Current verified tenant-user routing action. The gateway binds the current identity without accepting a caller UID, normalizes the proposed name and slug, creates one request ID per reviewed submission, and strictly decodes the pending tenant response. Success refreshes routing so the pending membership is visible but never opened. |
| `lib/tenancy/platform_tenant_review.dart` | `setTenantLifecycle` | No replacement | Current platform-only pending review action. The gateway binds one decoded pending tenant and the claim-plus-root-gated operator, permits only pending-to-active approval or pending-to-rejected rejection, requires a rejection reason, creates one request ID per intent, and strictly decodes exact previous/target status and fan-out operation agreement. |
| `lib/tenancy/platform_tenant_lifecycle.dart` | `setTenantLifecycle` | No replacement | Current platform-only active/suspended lifecycle action. The gateway binds one decoded canonical record and the claim-plus-root-gated operator, permits only active-to-suspended or suspended-to-active, requires a normalized suspension reason, preserves one request ID across recoverable retry, and strictly decodes exact previous/target status and fan-out operation agreement. |
| `lib/tenancy/platform_tenant_archival.dart` | `setTenantLifecycle` | No replacement | Current platform-only rejected archival action. The gateway binds one decoded rejected record and the claim-plus-root-gated operator, permits only rejected-to-archived, requires a normalized archival reason plus the exact canonical `business name (slug)` confirmation, preserves one request ID across recoverable retry, and strictly decodes exact rejected/archived status and fan-out operation agreement. |
| `lib/tenancy/platform_global_user_status.dart` | `getGlobalUserStatusReview` | No replacement | Current platform-only exact-UID review. The callable performs bounded authoritative root, ownership, canonical staff, and administrative-principal scans behind claim-plus-root authorization and returns only the strict review projection needed by the screen. |
| `lib/tenancy/platform_global_user_status.dart` | `setGlobalUserStatus` | No replacement | Current platform-only active/disabled action. The gateway binds one decoded root user, requires a normalized reason and exact UID confirmation for disabling, preserves one request ID across recoverable retry, and strictly decodes operation, target, affected-tenant, attempt, and partial-failure agreement. |
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
