/// A second copy of a receipt that has already been issued.
///
/// **The product owner asked for this on the sale card on 2026-09-06**, and the
/// thing that makes it more than a print button is what
/// `docs/printer_transport.md` §7 requires of it: a reprint is audited.
/// `HivePrintJobQueue.reprint` has carried that seam unused since it was
/// written - *"until one is passed, a reprint still refuses to happen
/// silently"* - and `recordReceiptReprint` is now the writer on the other end
/// of it.
///
/// **The order is audit, then paper, and it is not an implementation detail.**
/// The record is written first, so a reprint that was not recorded never
/// happens; the opposite order loses the audit line exactly when it matters,
/// which is a crash or a lost connection midway through. It also means an
/// offline device cannot reprint at all, and that is the honest outcome rather
/// than a limitation: the audit trail is what makes a duplicate receipt
/// answerable for, and a duplicate nobody can trace is what this control would
/// otherwise be.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';

import '../checkout/checkout_print_dispatch.dart';
import '../checkout/checkout_print_transport_base.dart';
import '../checkout/checkout_print_configuration.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_types.dart';
import 'sale_history.dart';

/// The roles a second copy of a receipt is a decision for.
///
/// The same three that verify a return and adjust stock, and the same three the
/// callable enforces. A cashier rings a sale up and prints its one receipt;
/// asking for another is a supervisor's call, because a duplicate receipt is a
/// cash-handling problem rather than a convenience.
const List<TenantRole> tenantReceiptReprintRoles = <TenantRole>[
  TenantRole.owner,
  TenantRole.admin,
  TenantRole.manager,
];

/// What became of one reprint request.
enum TenantReceiptReprintOutcome {
  /// Recorded, and the printer took every byte.
  printed,

  /// Recorded and durably queued; the printer has not taken it yet. The queue
  /// will keep trying, and the *Print queue* screen shows it.
  queued,

  /// Nothing was recorded and nothing was printed.
  refused,
}

/// One reprint's outcome and, where there is one, the reason it is not
/// [TenantReceiptReprintOutcome.printed].
final class TenantReceiptReprintReport {
  const TenantReceiptReprintReport.printed()
    : outcome = TenantReceiptReprintOutcome.printed,
      reasonCode = null;

  const TenantReceiptReprintReport.queued(String this.reasonCode)
    : outcome = TenantReceiptReprintOutcome.queued;

  const TenantReceiptReprintReport.refused(String this.reasonCode)
    : outcome = TenantReceiptReprintOutcome.refused;

  final TenantReceiptReprintOutcome outcome;

  /// A [PrinterTransportCode], or one of this file's own refusal codes.
  final String? reasonCode;
}

/// Refusals that are about the audit rather than about the printer.
abstract final class TenantReceiptReprintCode {
  /// This session may not reprint, or its membership ended.
  static const String forbidden = 'reprint_forbidden';

  /// The sale, or the receipt on it, is not what was named.
  static const String notFound = 'reprint_sale_not_found';

  /// There is no `recordReceiptReprint` on the other end.
  ///
  /// **Its own code because a device found the two sharing one**, on
  /// 2026-09-06: a callable that has never been deployed answers 404, which
  /// arrives here as `not-found` exactly as a missing sale would, and the
  /// screen told an owner that the sale they were looking at was not in their
  /// business. The server now raises `failed-precondition` for that branch, so
  /// `not-found` means this and nothing else.
  static const String serviceMissing = 'reprint_service_missing';

  /// The device could not reach the server, so nothing was recorded.
  static const String unavailable = 'reprint_unavailable';

  /// The server refused for a reason this client does not model.
  static const String refused = 'reprint_refused';
}

/// Narrow callable boundary for `recordReceiptReprint`.
abstract interface class RecordReceiptReprintCallable {
  Future<Object?> call(Map<String, Object?> payload);
}

/// Firebase adapter for `recordReceiptReprint`.
final class FirebaseRecordReceiptReprintCallable
    implements RecordReceiptReprintCallable {
  FirebaseRecordReceiptReprintCallable({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    final result = await _functions
        .httpsCallable('recordReceiptReprint')
        .call<Object?>(payload);
    return result.data;
  }
}

/// Everything the heading of a receipt needs, resolved for one session.
///
/// The composition root builds this because it is the only place holding the
/// branding, the logo cache and the configured printer at once - the same
/// pieces, resolved the same way, that the sale path's first copy used.
final class TenantReceiptPrintContext {
  const TenantReceiptPrintContext({
    required this.printer,
    this.businessName,
    this.servedBy,
    this.logo,
    this.slogan,
  });

  final TenantConfiguredPrinter printer;
  final String? businessName;
  final String? servedBy;
  final Uint8List? logo;
  final String? slogan;
}

/// Puts a second copy of one recorded sale's receipt on paper.
abstract interface class TenantReceiptReprinter {
  Future<TenantReceiptReprintReport> reprint({
    required TenantSession session,
    required TenantSale sale,
  });
}

/// The audit call and the durable print queue, in that order.
final class CheckoutTenantReceiptReprinter implements TenantReceiptReprinter {
  CheckoutTenantReceiptReprinter({
    required CheckoutPrintDispatcher dispatcher,
    required RecordReceiptReprintCallable callable,
    required Future<TenantReceiptPrintContext> Function(TenantSession session)
    readContext,
    String Function()? requestIdFactory,
  }) : _dispatcher = dispatcher,
       _callable = callable,
       _readContext = readContext,
       _requestId = requestIdFactory ?? secureReceiptReprintRequestId;

  final CheckoutPrintDispatcher _dispatcher;
  final RecordReceiptReprintCallable _callable;
  final Future<TenantReceiptPrintContext> Function(TenantSession) _readContext;
  final String Function() _requestId;

  @override
  Future<TenantReceiptReprintReport> reprint({
    required TenantSession session,
    required TenantSale sale,
  }) async {
    if (!session.canAccess(allowedRoles: tenantReceiptReprintRoles)) {
      return const TenantReceiptReprintReport.refused(
        TenantReceiptReprintCode.forbidden,
      );
    }
    if (sale.tenantId != session.tenantId) {
      return const TenantReceiptReprintReport.refused(
        TenantReceiptReprintCode.notFound,
      );
    }
    final TenantReceiptPrintContext context;
    try {
      context = await _readContext(session);
    } catch (_) {
      return const TenantReceiptReprintReport.refused(
        PrinterTransportCode.notConfigured,
      );
    }
    // **One request ID for this one act.** The callable is idempotent per
    // request ID, so a reprint that is asked for twice records two audit lines
    // - which is right, because it is two pieces of paper - while a single
    // request that is retried underneath records one.
    final requestId = _requestId();

    try {
      final result = await _dispatcher.reprint(
        sale,
        printer: context.printer,
        businessName: context.businessName,
        servedBy: context.servedBy,
        logo: context.logo,
        slogan: context.slogan,
        onReprint: () => _record(session, sale, requestId),
      );
      return switch (result.outcome) {
        CheckoutPrintOutcome.sent => const TenantReceiptReprintReport.printed(),
        CheckoutPrintOutcome.queued => TenantReceiptReprintReport.queued(
          result.reasonCode ?? PrinterTransportCode.unreachable,
        ),
        CheckoutPrintOutcome.refused => TenantReceiptReprintReport.refused(
          result.reasonCode ?? PrinterTransportCode.notConfigured,
        ),
      };
    } on _ReprintRefused catch (refusal) {
      // The audit refused, so `CheckoutPrintDispatcher.reprint` queued nothing
      // and sent nothing. That is the contract, not a partial failure.
      return TenantReceiptReprintReport.refused(refusal.code);
    }
  }

  /// Writes the audit line, or throws the refusal that stops the reprint.
  Future<void> _record(
    TenantSession session,
    TenantSale sale,
    String requestId,
  ) async {
    try {
      await _callable(<String, Object?>{
        'tenantId': session.tenantId,
        'saleId': sale.id,
        'receiptNumber': sale.receiptNumber,
        'requestId': requestId,
      });
    } on FirebaseFunctionsException catch (error) {
      throw _ReprintRefused(switch (error.code) {
        'permission-denied' || 'unauthenticated' => TenantReceiptReprintCode
            .forbidden,
        'not-found' || 'unimplemented' => TenantReceiptReprintCode
            .serviceMissing,
        'failed-precondition' => TenantReceiptReprintCode.notFound,
        // **Not the missing-sale sentence.** `invalid-argument` means this
        // client sent the server something it will not accept, which is a
        // defect here rather than a fact about the shop's records - and saying
        // "that sale is not in this business" about a sale on screen is exactly
        // how the 2026-09-06 receipt-pattern bug presented.
        'invalid-argument' => TenantReceiptReprintCode.refused,
        'unavailable' || 'deadline-exceeded' => TenantReceiptReprintCode
            .unavailable,
        _ => TenantReceiptReprintCode.refused,
      });
    } catch (_) {
      throw const _ReprintRefused(TenantReceiptReprintCode.unavailable);
    }
  }
}

/// Carries an audit refusal out through the queue's `onReprint` seam.
final class _ReprintRefused implements Exception {
  const _ReprintRefused(this.code);

  final String code;
}

/// A fresh request ID for one reprint.
String secureReceiptReprintRequestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(18, (_) => random.nextInt(256));
  return 'reprint-${base64Url.encode(bytes).replaceAll('=', '')}';
}
