/// `docs/stitch/RBAC_MATRIX.md`, as an executable contract.
///
/// **The matrix is derived from this code and nothing checked that it stayed
/// derived.** It says so in its own first line — *"This matrix is derived from
/// active Dart authorization lists and route composition"* — which makes it a
/// snapshot of a moment, and a snapshot of authorization is the kind of document
/// that is quietly wrong for months. Wave 0's order of work asks for the guards
/// to be checked against it; this is that check, written so it runs again every
/// time rather than once.
///
/// **Three things it asserts, and the third is the one that matters.**
///
/// 1. Every role list in the app holds exactly the roles the matrix gives its
///    row. Quoted per entry, so a disagreement names the row to go and read.
/// 2. `owner` satisfies `admin` and nothing else satisfies anything — the matrix's
///    *"Owner satisfies checks that allow administrator; there is no general role
///    hierarchy"*, which is what makes `[admin]` mean owner-and-administrator and
///    `[admin, manager]` mean three roles rather than two.
/// 3. **The set of role lists in `lib/` is exactly the set below.** A source
///    scan, because the failure this catches is a *new* guard rather than a
///    changed one: a capability added next month with its own list would pass
///    every assertion in 1 and appear in no row of the matrix. This is the only
///    assertion here that a reader would not think to write.
///
/// **What it deliberately does not assert.** Whether a *route* is offered to a
/// role, which is `tenant_routing_shell.dart`'s business and is already
/// structurally safe — see the note on [_navigationIsFedFromTheGuards]. And
/// whether the server agrees: `firestore.rules` and the callables are the real
/// boundary, and `rules-tests/` is where that is proven. A client-side list that
/// matched a matrix while the server disagreed would be exactly the false
/// comfort `RBAC_MATRIX.md`'s last line warns about — *"visual hiding alone is
/// never authorization"*.
library;

import 'dart:io' show Directory, File;

import 'package:uzapay_pos/audit/audit_log.dart';
import 'package:uzapay_pos/checkout/checkout_configuration.dart';
import 'package:uzapay_pos/checkout/checkout_price_agreement.dart';
import 'package:uzapay_pos/checkout/checkout_print_configuration.dart';
import 'package:uzapay_pos/customers/customers.dart';
import 'package:uzapay_pos/email_receipts/email_receipts.dart';
import 'package:uzapay_pos/expenses/expense_repository.dart';
import 'package:uzapay_pos/inventory/bulk_catalog.dart';
import 'package:uzapay_pos/inventory/catalog_management.dart';
import 'package:uzapay_pos/inventory/stock_adjustment.dart';
import 'package:uzapay_pos/inventory/stock_adjustment_feed.dart';
import 'package:uzapay_pos/inventory/stock_movement_feed.dart';
import 'package:uzapay_pos/inventory/stock_movements.dart';
import 'package:uzapay_pos/inventory/stock_take.dart';
import 'package:uzapay_pos/inventory/stock_take_review.dart';
import 'package:uzapay_pos/inventory/stock_take_schedule.dart';
import 'package:uzapay_pos/production/production_batch.dart';
import 'package:uzapay_pos/reporting/daily_metrics.dart';
import 'package:uzapay_pos/reporting/profit_report.dart';
import 'package:uzapay_pos/reporting/reconciliation_anomalies.dart';
import 'package:uzapay_pos/reporting/reconciliation_request.dart';
import 'package:uzapay_pos/reporting/reconciliation_status.dart';
import 'package:uzapay_pos/reporting/sales_totals.dart';
import 'package:uzapay_pos/reporting/shift_amendment.dart';
import 'package:uzapay_pos/reporting/shift_amendment_feed.dart';
import 'package:uzapay_pos/returns/return_request.dart';
import 'package:uzapay_pos/whatsapp/whatsapp.dart';
import 'package:uzapay_pos/returns/return_verification.dart';
import 'package:uzapay_pos/returns/return_history.dart';
import 'package:uzapay_pos/sales/receipt_lookup.dart';
import 'package:uzapay_pos/sales/sale_history.dart';
import 'package:uzapay_pos/shift/abandoned_shift.dart';
import 'package:uzapay_pos/shift/shift_history.dart';
import 'package:uzapay_pos/suppliers/supplier.dart';
import 'package:uzapay_pos/tenancy/tenant_staff_directory.dart';
import 'package:uzapay_pos/tenancy/tenant_staff_invitation.dart';
import 'package:uzapay_pos/tenancy/tenant_branding_writer.dart';
import 'package:uzapay_pos/tenancy/tenant_setup_checklist.dart';
import 'package:uzapay_pos/tenancy/tenant_staff_invitation_cancellation.dart';
import 'package:uzapay_pos/tenancy/tenant_staff_invitation_email_replacement.dart';
import 'package:uzapay_pos/tenancy/tenant_staff_invitation_resend.dart';
import 'package:uzapay_pos/tenancy/tenant_staff_status.dart';
import 'package:uzapay_pos/tenancy/tenant_staff_update.dart';
import 'package:uzapay_pos/tenancy/tenant_types.dart';
import 'package:flutter_test/flutter_test.dart';

/// The four roles, spelled the way the matrix spells them.
const _o = TenantRole.owner;
const _a = TenantRole.admin;
const _m = TenantRole.manager;
const _c = TenantRole.cashier;

/// The operational three, which is the commonest shape in the app.
const _management = <TenantRole>[_o, _a, _m];

/// Every named role list in the active app, against the matrix row that governs
/// it.
///
/// Keyed by `Class.member` so a failure names the symbol, and ordered by the
/// matrix rather than by file so the two can be read side by side.
final Map<String, ({List<TenantRole> expected, String row})>
_guards = <String, ({List<TenantRole> expected, String row})>{
  // | Receipt lookup | Full | Full | Full | Full |
  'TenantReceiptLookupRepository.allowedRoles': (
    expected: TenantReceiptLookupRepository.allowedRoles,
    row: 'Receipt lookup: every active member.',
  ),
  // | Record pending return | Full | Full | Full | Full |
  'TenantReturnRequestRepository.allowedRoles': (
    expected: TenantReturnRequestRepository.allowedRoles,
    row: 'Record pending return: every active member. Verification differs.',
  ),
  // | View management shift history | Full | Full | Full | No |
  //
  // **The route is open to everyone and the *scope* is what this gates.** A
  // cashier reads their own closed shifts; reading another cashier's is the
  // management scope, and `shift_history_panel.dart` hides the scope toggle
  // behind the same predicate the repository enforces.
  'TenantShiftHistoryRepository.managementRoles': (
    expected: TenantShiftHistoryRepository.managementRoles,
    row: 'View management shift history: manager-or-above.',
  ),
  // | Close an abandoned shift | Full | Full | Full | No |
  //
  // **Finding one and ending one are two different permissions, deliberately.**
  // This list gates the *finding*: it is a read of another cashier's shift, so
  // it matches the row above it exactly. Ending one is narrower and is not a
  // client decision at all - `closeAbandonedShift` re-checks owner-or-admin on
  // the server, inside the transaction that closes it, because a manager who
  // could end a colleague's shift could erase a drawer nobody had counted.
  'TenantAbandonedShiftRepository.allowedRoles': (
    expected: TenantAbandonedShiftRepository.allowedRoles,
    row: 'Close an abandoned shift: manager-or-above finds, server decides.',
  ),
  // | Manage catalog operational fields | Full | Full | Full | No |
  'TenantCatalogManagementRepository.allowedRoles': (
    expected: TenantCatalogManagementRepository.allowedRoles,
    row: 'Manage catalog operational fields: owner/admin/manager.',
  ),
  // | Change price or cost | Full | Full | No | No |
  'TenantCatalogManagementRepository.costRoles': (
    expected: TenantCatalogManagementRepository.costRoles,
    row: 'Change price or cost: money fields are narrower than the catalog.',
  ),
  // | Retire product | Full | Full | No | No |
  'TenantCatalogManagementRepository.retireRoles': (
    expected: TenantCatalogManagementRepository.retireRoles,
    row: 'Retire product: retireRoles.',
  ),
  // | Bulk catalog changes/import | Full | Full | Full | No |
  'TenantBulkCatalogRepository.allowedRoles': (
    expected: TenantBulkCatalogRepository.allowedRoles,
    row: 'Bulk catalog changes/import: the same management route boundary.',
  ),
  // | Product stock and ledger | Full | Full | Full | No |
  'TenantProductStockRepository.allowedRoles': (
    expected: TenantProductStockRepository.allowedRoles,
    row: 'Product stock and ledger: dedicated stock routes.',
  ),
  // | Create stock correction | Full | Full | Full | No |
  'TenantStockAdjustmentGateway.allowedRoles': (
    expected: TenantStockAdjustmentGateway.allowedRoles,
    row: 'Create stock correction: reasoned/manual adjustment.',
  ),
  // | View stock adjustment/movement feeds | Full | Full | Full | No |
  'TenantStockAdjustmentFeedRepository.allowedRoles': (
    expected: TenantStockAdjustmentFeedRepository.allowedRoles,
    row: 'View stock adjustment feed.',
  ),
  'TenantStockMovementFeedRepository.allowedRoles': (
    expected: TenantStockMovementFeedRepository.allowedRoles,
    row: 'View stock movement feed, including the collection-group read.',
  ),
  // | Take a stock count | Full | Full | Full | Full |
  //
  // **The one inventory capability a cashier has**, and the reason it is safe
  // is that it writes no quantity: a count is an observation, and accepting it
  // is the separate row below.
  'TenantStockTakeGateway.allowedRoles': (
    expected: TenantStockTakeGateway.allowedRoles,
    row: 'Take a stock count: every active member, because it moves no stock.',
  ),
  // | Read a stock count's lines | Full | Full | Full | No |
  // | Accept a stock count | Full | Full | Full | No |
  'TenantStockTakeReviewRepository.allowedRoles': (
    expected: TenantStockTakeReviewRepository.allowedRoles,
    row: "Read a stock count's lines, and accept it.",
  ),
  // | Set the counting schedule | Full | Full | No | No |
  'TenantStockTakeScheduleRepository.writeRoles': (
    expected: TenantStockTakeScheduleRepository.writeRoles,
    row: 'Set the counting schedule.',
  ),
  'TenantStockTakeSchedulePublisher.allowedRoles': (
    expected: TenantStockTakeSchedulePublisher.allowedRoles,
    row: 'Set the counting schedule, from the settings tab that publishes it.',
  ),
  // | Set who can agree a price | Full | Full | No | No |
  'TenantPriceAgreementRepository.writeRoles': (
    expected: TenantPriceAgreementRepository.writeRoles,
    row: 'Set who can agree a price.',
  ),
  'TenantPriceAgreementPublisher.allowedRoles': (
    expected: TenantPriceAgreementPublisher.allowedRoles,
    row: 'Set who can agree a price, from the settings tab that publishes it.',
  ),
  // | Daily summary | Full | Full | Full | No |
  'TenantDailyMetricsRepository.allowedRoles': (
    expected: TenantDailyMetricsRepository.allowedRoles,
    row: 'Daily summary: TenantDailyMetricsRepository.allowedRoles.',
  ),
  // | Sales totals | Full | Full | Full | No |
  'TenantSalesTotalsGateway.allowedRoles': (
    expected: TenantSalesTotalsGateway.allowedRoles,
    row: 'Sales totals: management reporting.',
  ),
  // | Reconciliation status/anomalies | Full | Full | Full | No |
  'TenantReconciliationStatusRepository.allowedRoles': (
    expected: TenantReconciliationStatusRepository.allowedRoles,
    row: 'Reconciliation status: read scope.',
  ),
  'TenantReconciliationAnomalyRepository.allowedRoles': (
    expected: TenantReconciliationAnomalyRepository.allowedRoles,
    row: 'Reconciliation anomalies: read scope.',
  ),
  // | Request reconciliation run | Full | Full | No | No |
  'TenantReconciliationRequestGateway.allowedRoles': (
    expected: TenantReconciliationRequestGateway.allowedRoles,
    row: 'Request reconciliation run: write restricted to owner/admin.',
  ),
  // | Shift amendment/correction action | Full | Full | No | No |
  //
  // Two lists, and the matrix splits them in the same sentence: *"Amendment
  // feed may be readable to manager."* The action is owner/admin; the record
  // of who acted is management-wide.
  'TenantShiftAmendmentGateway.allowedRoles': (
    expected: TenantShiftAmendmentGateway.allowedRoles,
    row: 'Shift amendment action: owner/admin.',
  ),
  'TenantShiftAmendmentFeedRepository.allowedRoles': (
    expected: TenantShiftAmendmentFeedRepository.allowedRoles,
    row: 'Shift amendment feed: readable to manager.',
  ),
  // | Profit/margin report | Full | Full | No | No |
  'TenantProfitReport.allowedRoles': (
    expected: TenantProfitReport.allowedRoles,
    row: 'Profit/margin report: more restricted than the daily summary.',
  ),
  // | Staff directory | Full | Full | Read | No |
  //
  // **`[admin, manager]`, which is three roles and not two.** Owner
  // satisfies admin, so this is owner/admin/manager and no cashier — and the
  // *Read* in the matrix's manager column is the screen's own `_readOnly`,
  // which is true exactly when the session holds neither the invitation nor
  // the update gateway below.
  'TenantStaffDirectoryScreen.allowedRoles': (
    expected: TenantStaffDirectoryScreen.allowedRoles,
    row: 'Staff directory: manager sees it read-only; cashier not at all.',
  ),
  // | Invite/edit/disable/resend/cancel staff | Full | Full | No | No |
  'TenantStaffInvitationGateway.allowedRoles': (
    expected: TenantStaffInvitationGateway.allowedRoles,
    row: 'Invite staff: administrator capability, owner inherits it.',
  ),
  'TenantStaffUpdateGateway.allowedRoles': (
    expected: TenantStaffUpdateGateway.allowedRoles,
    row: 'Edit staff: administrator capability.',
  ),
  'TenantStaffStatusGateway.allowedRoles': (
    expected: TenantStaffStatusGateway.allowedRoles,
    row: 'Disable staff: administrator capability.',
  ),
  'TenantStaffInvitationResendGateway.allowedRoles': (
    expected: TenantStaffInvitationResendGateway.allowedRoles,
    row: 'Resend invitation: administrator capability.',
  ),
  'TenantStaffInvitationCancellationGateway.allowedRoles': (
    expected: TenantStaffInvitationCancellationGateway.allowedRoles,
    row: 'Cancel invitation: administrator capability.',
  ),
  'TenantStaffInvitationEmailReplacementGateway.allowedRoles': (
    expected: TenantStaffInvitationEmailReplacementGateway.allowedRoles,
    row: 'Replace a pending invitation email: administrator capability.',
  ),
  // | Checkout currency settings | Full | Full | No | No |
  'TenantCheckoutConfigurationPublisher.allowedRoles': (
    expected: TenantCheckoutConfigurationPublisher.allowedRoles,
    row: 'Checkout currency settings: the only supported checkout setting.',
  ),
  // | Printer configuration/test | Full | Full | No | No |
  'TenantPrinterConfigurationRepository.writeRoles': (
    expected: TenantPrinterConfigurationRepository.writeRoles,
    row: 'Printer configuration: configuration write roles.',
  ),
  'TenantPrinterConfigurationPublisher.allowedRoles': (
    expected: TenantPrinterConfigurationPublisher.allowedRoles,
    row: 'Printer configuration: the publisher reads writeRoles.',
  ),
  // | Activity log | Full | Full | No | No |
  'TenantAuditLogRepository.allowedRoles': (
    expected: TenantAuditLogRepository.allowedRoles,
    row: 'Activity log: TenantAuditLogRepository.allowedRoles.',
  ),
  // | Verify return and restore stock | Full | Full | Full | No |
  'TenantReturnVerificationGateway.allowedRoles': (
    expected: TenantReturnVerificationGateway.allowedRoles,
    row: 'Verify return and restore stock: management verification.',
  ),
  // **The seven below were unregistered until 2026-09-10.** Each is a guard
  // that grew after the matrix was last derived, which is the failure the
  // source scan exists to catch: they satisfied every other assertion here
  // while appearing in no row at all. The roles are the app's three ordinary
  // shapes - owner/admin, the management three, every active member - and the
  // one worth a second look is expenses, which excludes manager where most
  // owner/admin capabilities do too.
  //
  // | Record and read expenses | Full | Full | No | No |
  'TenantExpenseRepository.allowedRoles': (
    expected: TenantExpenseRepository.allowedRoles,
    row: 'Expenses: owner/administrator only, like the other money settings.',
  ),
  // | Suppliers, deliveries and production | Full | Full | Full | No |
  //
  // **Added 2026-09-24 with the feature, at the developer's direction.** The
  // roles that receive and produce stock; a manager may set a product's cost
  // through a delivery or a batch because each is a permanent record of how
  // the figure was reached, while editing the cost directly stays owner and
  // administrator (`TenantCatalogManagementRepository.costRoles`).
  'TenantSupplierRepository.allowedRoles': (
    expected: TenantSupplierRepository.allowedRoles,
    row:
        'Suppliers, deliveries and production: the management three, as '
        'the roles that receive stock.',
  ),
  'TenantProductionRepository.allowedRoles': (
    expected: TenantProductionRepository.allowedRoles,
    row:
        'Production: the management three; a completed batch sets the '
        'product\'s cost as a permanent record of how it was reached.',
  ),
  // | Business details and logo | Full | Full | No | No |
  'TenantBrandingPublisher.allowedRoles': (
    expected: TenantBrandingPublisher.allowedRoles,
    row:
        'Publish business details: owner/administrator, as the receipt '
        'header it writes is business-wide.',
  ),
  // | Setup checklist | Full | Full | No | No |
  'TenantSetupChecklist.allowedRoles': (
    expected: TenantSetupChecklist.allowedRoles,
    row:
        'Setup checklist: owner/administrator, being the list of things only '
        'they can finish.',
  ),
  // | Receipt lookup, management scope | Full | Full | Full | No |
  //
  // **The scope, not the route.** `allowedRoles` above opens receipt lookup to
  // every active member; this is the wider read a manager gets, the same
  // split `TenantShiftHistoryRepository.managementRoles` makes.
  'TenantReceiptLookupRepository.managementRoles': (
    expected: TenantReceiptLookupRepository.managementRoles,
    row: 'Receipt lookup management scope: reading beyond your own receipts.',
  ),
  // | Sale history report | Full | Full | Full | Full |
  'TenantSaleHistoryRepository.reportRoles': (
    expected: TenantSaleHistoryRepository.reportRoles,
    row: 'Sale history report: every active member, over their own sales.',
  ),
  // | Sale history report, management scope | Full | Full | Full | No |
  'TenantSaleHistoryRepository.managementReportRoles': (
    expected: TenantSaleHistoryRepository.managementReportRoles,
    row:
        'Sale history management scope: reading the sales of another '
        'member.',
  ),
  // | Return history | Full | Full | Full | Full |
  'TenantReturnHistoryRepository.allowedRoles': (
    expected: TenantReturnHistoryRepository.allowedRoles,
    row: 'Return history: every active member, as recording one is.',
  ),
  // **The eight registered on 2026-10-01, with customers, WhatsApp receipts
  // and credit.** Seven came with plan 1 and were missed here, which is the
  // failure this file's source scan exists to catch; the eighth is the
  // statement. Server-side, the same roles are `CUSTOMER_CREATE_ROLES`,
  // `CUSTOMER_UPDATE_ROLES` and the `activity`, `configuration` and
  // `receipt_deliveries` rules.
  //
  // | Add a customer (at the till) | Full | Full | Full | Full |
  'TenantCustomerRepository.createRoles': (
    expected: TenantCustomerRepository.createRoles,
    row:
        'Add a customer: everyone who sells, because the till is where a '
        'customer is met.',
  ),
  // | Customers screen, corrections, credit limits | Full | Full | Full | No |
  'TenantCustomerRepository.manageRoles': (
    expected: TenantCustomerRepository.manageRoles,
    row:
        'Customers screen: the management three, who correct a customer and '
        'give them credit.',
  ),
  // | Customer statement and who owes | Full | Full | Full | No |
  'TenantCustomerCreditRepository.statementRoles': (
    expected: TenantCustomerCreditRepository.statementRoles,
    row:
        'Customer statement and who owes: the management three, as the '
        'ledger rule reads.',
  ),
  // | Loyalty and WhatsApp settings | Full | Full | No | No |
  'TenantLoyaltyRepository.writeRoles': (
    expected: TenantLoyaltyRepository.writeRoles,
    row: 'Loyalty settings: owner/administrator, like every configuration.',
  ),
  'TenantLoyaltyPublisher.allowedRoles': (
    expected: TenantLoyaltyPublisher.allowedRoles,
    row: 'Publish loyalty settings: owner/administrator.',
  ),
  'TenantEReceiptRepository.writeRoles': (
    expected: TenantEReceiptRepository.writeRoles,
    row: 'WhatsApp receipt settings: owner/administrator.',
  ),
  'TenantEReceiptPublisher.allowedRoles': (
    expected: TenantEReceiptPublisher.allowedRoles,
    row: 'Publish WhatsApp receipt settings: owner/administrator.',
  ),
  // | Receipt deliveries | Full | Full | Full | No |
  'TenantReceiptDeliveryRepository.readRoles': (
    expected: TenantReceiptDeliveryRepository.readRoles,
    row:
        'Receipt deliveries: the management three, who can act on a failed '
        'one.',
  ),
  // **The three registered on 2026-10-03 with email receipts**, the WhatsApp
  // three again for the inbox. Server-side, the `configuration` and
  // `email_receipt_deliveries` rules.
  'TenantEmailReceiptRepository.writeRoles': (
    expected: TenantEmailReceiptRepository.writeRoles,
    row: 'Email receipt settings: owner/administrator.',
  ),
  'TenantEmailReceiptPublisher.allowedRoles': (
    expected: TenantEmailReceiptPublisher.allowedRoles,
    row: 'Publish email receipt settings: owner/administrator.',
  ),
  // | Email receipt deliveries | Full | Full | Full | No |
  'TenantEmailReceiptDeliveryRepository.readRoles': (
    expected: TenantEmailReceiptDeliveryRepository.readRoles,
    row:
        'Email receipt deliveries: the management three, as for WhatsApp.',
  ),
};

/// What each guard should hold, written out rather than read off the guard.
///
/// **The two halves of the map above and below are the whole point.** The map
/// reads the app's own constants, which makes the failure message name the
/// symbol; this one is authored from the matrix, which makes the assertion mean
/// something. A single map would assert that a list equals itself.
const Map<String, List<TenantRole>> _fromTheMatrix = <String, List<TenantRole>>{
  'TenantReceiptLookupRepository.allowedRoles': <TenantRole>[_o, _a, _m, _c],
  'TenantReturnRequestRepository.allowedRoles': <TenantRole>[_o, _a, _m, _c],
  'TenantShiftHistoryRepository.managementRoles': _management,
  // Finding one is the same read as the row above; ending one is the server's.
  'TenantAbandonedShiftRepository.allowedRoles': _management,
  'TenantCatalogManagementRepository.allowedRoles': _management,
  'TenantCatalogManagementRepository.costRoles': <TenantRole>[_o, _a],
  'TenantCatalogManagementRepository.retireRoles': <TenantRole>[_o, _a],
  'TenantBulkCatalogRepository.allowedRoles': _management,
  'TenantProductStockRepository.allowedRoles': _management,
  'TenantStockAdjustmentGateway.allowedRoles': _management,
  'TenantStockAdjustmentFeedRepository.allowedRoles': _management,
  'TenantStockMovementFeedRepository.allowedRoles': _management,
  // Every active member, which is the widest list in the inventory surface and
  // the whole point of the feature: counting moves no stock.
  'TenantStockTakeGateway.allowedRoles': <TenantRole>[_o, _a, _m, _c],
  'TenantStockTakeReviewRepository.allowedRoles': _management,
  'TenantStockTakeScheduleRepository.writeRoles': <TenantRole>[_o, _a],
  'TenantStockTakeSchedulePublisher.allowedRoles': <TenantRole>[_o, _a],
  'TenantPriceAgreementRepository.writeRoles': <TenantRole>[_o, _a],
  'TenantPriceAgreementPublisher.allowedRoles': <TenantRole>[_o, _a],
  'TenantDailyMetricsRepository.allowedRoles': _management,
  'TenantSalesTotalsGateway.allowedRoles': _management,
  'TenantReconciliationStatusRepository.allowedRoles': _management,
  'TenantReconciliationAnomalyRepository.allowedRoles': _management,
  'TenantReconciliationRequestGateway.allowedRoles': <TenantRole>[_o, _a],
  'TenantShiftAmendmentGateway.allowedRoles': <TenantRole>[_o, _a],
  'TenantShiftAmendmentFeedRepository.allowedRoles': _management,
  'TenantProfitReport.allowedRoles': <TenantRole>[_o, _a],
  // Owner is absent from the literal and present in the effect: owner satisfies
  // admin. The assertion below on the hierarchy is what makes that safe to
  // write here.
  'TenantStaffDirectoryScreen.allowedRoles': <TenantRole>[_a, _m],
  'TenantStaffInvitationGateway.allowedRoles': <TenantRole>[_a],
  'TenantStaffUpdateGateway.allowedRoles': <TenantRole>[_a],
  'TenantStaffStatusGateway.allowedRoles': <TenantRole>[_a],
  'TenantStaffInvitationResendGateway.allowedRoles': <TenantRole>[_a],
  'TenantStaffInvitationCancellationGateway.allowedRoles': <TenantRole>[_a],
  'TenantStaffInvitationEmailReplacementGateway.allowedRoles': <TenantRole>[_a],
  'TenantCheckoutConfigurationPublisher.allowedRoles': <TenantRole>[_o, _a],
  'TenantPrinterConfigurationRepository.writeRoles': <TenantRole>[_o, _a],
  'TenantPrinterConfigurationPublisher.allowedRoles': <TenantRole>[_o, _a],
  'TenantAuditLogRepository.allowedRoles': <TenantRole>[_o, _a],
  'TenantReturnVerificationGateway.allowedRoles': _management,
  // **The seven registered on 2026-09-10, authored from the roles the
  // developer approved rather than read off the guard.** Each grew after the
  // matrix was last derived and appeared in no row, which is the failure the
  // source scan exists to catch.
  'TenantExpenseRepository.allowedRoles': <TenantRole>[_o, _a],
  'TenantBrandingPublisher.allowedRoles': <TenantRole>[_o, _a],
  'TenantSetupChecklist.allowedRoles': <TenantRole>[_o, _a],
  'TenantReceiptLookupRepository.managementRoles': _management,
  'TenantSaleHistoryRepository.reportRoles': <TenantRole>[_o, _a, _m, _c],
  'TenantSaleHistoryRepository.managementReportRoles': _management,
  'TenantReturnHistoryRepository.allowedRoles': <TenantRole>[_o, _a, _m, _c],
  // Registered 2026-09-24 with suppliers and production.
  'TenantSupplierRepository.allowedRoles': _management,
  'TenantProductionRepository.allowedRoles': _management,
  // Registered 2026-10-01 with customers, WhatsApp receipts and credit.
  'TenantCustomerRepository.createRoles': <TenantRole>[_o, _a, _m, _c],
  'TenantCustomerRepository.manageRoles': _management,
  'TenantCustomerCreditRepository.statementRoles': _management,
  'TenantLoyaltyRepository.writeRoles': <TenantRole>[_o, _a],
  'TenantLoyaltyPublisher.allowedRoles': <TenantRole>[_o, _a],
  'TenantEReceiptRepository.writeRoles': <TenantRole>[_o, _a],
  'TenantEReceiptPublisher.allowedRoles': <TenantRole>[_o, _a],
  'TenantReceiptDeliveryRepository.readRoles': _management,
  // Registered 2026-10-03 with email receipts.
  'TenantEmailReceiptRepository.writeRoles': <TenantRole>[_o, _a],
  'TenantEmailReceiptPublisher.allowedRoles': <TenantRole>[_o, _a],
  'TenantEmailReceiptDeliveryRepository.readRoles': _management,
};

/// Why this file does not assert which routes a role is offered.
///
/// **Because the composition root makes it structurally impossible to drift.**
/// `lib/main.dart` feeds every role-gated navigation slot from the guard's own
/// constant — `dailySummaryRoles: TenantDailyMetricsRepository.allowedRoles`,
/// `auditLogRoles: TenantAuditLogRepository.allowedRoles`, and nine more of
/// exactly that shape. So the list the landing route hides by and the list the
/// repository refuses by are the *same object*, and `RBAC_MATRIX.md`'s
/// *"Hidden actions must also be guarded in product code"* holds by construction
/// rather than by review.
///
/// A test asserting it would have to reach into the shell's constructor
/// arguments, and it would pass for the wrong reason: what makes this safe is
/// that there is only one list, not that two lists agree.
const String _navigationIsFedFromTheGuards = 'see lib/main.dart:428-626';

void main() {
  group('every guard holds the roles RBAC_MATRIX.md gives its row', () {
    test('the two maps cover the same guards', () {
      // A guard added to one map and not the other would otherwise be silently
      // unchecked, which is the failure this whole file exists to prevent.
      expect(_guards.keys.toSet(), _fromTheMatrix.keys.toSet());
      expect(_navigationIsFedFromTheGuards, isNotEmpty);
    });

    for (final entry in _guards.entries) {
      test(entry.key, () {
        expect(
          entry.value.expected,
          _fromTheMatrix[entry.key],
          reason:
              '${entry.key} no longer holds what RBAC_MATRIX.md gives it. '
              'The row: ${entry.value.row}\n'
              'If the capability genuinely changed, the matrix is the document '
              'to change first — it is the derived artifact, and a code change '
              'that leaves it stale makes every later reading of it wrong.',
        );
      });
    }
  });

  group('the hierarchy is one rule and not a ladder', () {
    test('owner satisfies admin, and that is the whole of it', () {
      // RBAC_MATRIX.md: "Owner satisfies checks that allow administrator; there
      // is no general role hierarchy." Both halves, because the second is what
      // makes `[admin, manager]` three roles and `[manager]` exactly one.
      expect(TenantRole.owner.canAccess(<TenantRole>[_a]), isTrue);
      expect(TenantRole.owner.canAccess(<TenantRole>[_o]), isTrue);
      expect(TenantRole.admin.canAccess(<TenantRole>[_o]), isFalse);
      expect(TenantRole.admin.canAccess(<TenantRole>[_m]), isFalse);
      expect(TenantRole.manager.canAccess(<TenantRole>[_a]), isFalse);
      expect(TenantRole.manager.canAccess(<TenantRole>[_c]), isFalse);
      expect(TenantRole.cashier.canAccess(<TenantRole>[_m]), isFalse);
      expect(TenantRole.owner.canAccess(<TenantRole>[_m]), isFalse);
    });

    test('a manager reaches the staff directory and no cashier does', () {
      // The one row where the matrix says `Read` rather than Full or No, worked
      // through the hierarchy rather than asserted as a literal.
      const directory = TenantStaffDirectoryScreen.allowedRoles;
      expect(TenantRole.owner.canAccess(directory), isTrue);
      expect(TenantRole.admin.canAccess(directory), isTrue);
      expect(TenantRole.manager.canAccess(directory), isTrue);
      expect(TenantRole.cashier.canAccess(directory), isFalse);

      // And the manager's *Read* is the absence of both write gateways, which is
      // exactly the condition `tenant_staff_directory.dart` resolves `_readOnly`
      // from. Asserted here so the two cannot come apart.
      expect(
        TenantRole.manager.canAccess(TenantStaffInvitationGateway.allowedRoles),
        isFalse,
      );
      expect(
        TenantRole.manager.canAccess(TenantStaffUpdateGateway.allowedRoles),
        isFalse,
      );
    });

    test('there are exactly four tenant roles', () {
      // RBAC_MATRIX.md: "Do not invent roles such as 'Senior Cashier' or
      // 'Inventory Clerk'." A fifth would make every row of the matrix a
      // statement about an incomplete set.
      expect(TenantRole.values, <TenantRole>[_o, _a, _m, _c]);
      expect(TenantRole.values.map((role) => role.wireValue), <String>[
        'owner',
        'admin',
        'manager',
        'cashier',
      ]);
    });
  });

  test('no role list exists in lib/ that the matrix has no row for', () {
    // **A source scan, and the only assertion here a reader would not think to
    // write.** Everything above checks guards that already exist. What it cannot
    // check is a capability added next month with a role list of its own: that
    // would pass every test above by not appearing in them, and appear in no row
    // of `RBAC_MATRIX.md` either.
    //
    // Three declaration shapes are in the app and all three are matched:
    // `static const List<TenantRole> allowedRoles = <TenantRole>[...]`, the same
    // with the type left off, and an alias to another class's list. `lib/pos/**`
    // and `lib/screens/**` are excluded — legacy, read-only, and reachable from
    // nothing that runs.
    final declared = <String>{};
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final path = file.path.replaceAll(r'\', '/');
      if (path.contains('/pos/') || path.contains('/screens/')) continue;

      final source = file.readAsStringSync();
      final classes = <(int, String)>[
        for (final match in RegExp(
          r'^(?:final\s+|abstract\s+|base\s+|sealed\s+)*class\s+(\w+)',
          multiLine: true,
        ).allMatches(source))
          (match.start, match.group(1)!),
      ];
      String ownerAt(int at) {
        var owner = '?';
        for (final (start, name) in classes) {
          if (start > at) break;
          owner = name;
        }
        return owner;
      }

      for (final match in RegExp(
        r'static\s+const\s+(?:List<TenantRole>\s+)?(\w*[Rr]oles)\s*=',
      ).allMatches(source)) {
        declared.add('${ownerAt(match.start)}.${match.group(1)}');
      }
    }

    expect(
      declared,
      isNotEmpty,
      reason:
          'No role list was recognised anywhere in lib/. Either authorization '
          'moved out of static constants, or this scan needs updating — it has '
          'not stopped being needed.',
    );
    expect(
      declared.difference(_guards.keys.toSet()),
      isEmpty,
      reason:
          'A role list exists in lib/ that no row of RBAC_MATRIX.md governs. '
          'Add the row to the matrix and the entry to this file, or say in the '
          'matrix why the capability is deliberately outside it.',
    );
    expect(
      _guards.keys.toSet().difference(declared),
      isEmpty,
      reason:
          'This file names a role list that lib/ no longer declares. If the '
          'capability was removed, its row leaves the matrix too.',
    );
  });
}
