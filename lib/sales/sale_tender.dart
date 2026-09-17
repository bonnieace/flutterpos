import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../checkout/checkout_tender.dart';
import '../tenancy/tenant_session.dart';
import '../ui/buttons.dart';
import '../ui/dialogs.dart';
import '../ui/tokens.dart';
import 'sale_history.dart';

/// Narrow callable boundary for `setSaleTender`.
abstract interface class SetSaleTenderCallable {
  Future<Object?> call(Map<String, Object?> payload);
}

/// Firebase adapter for `setSaleTender`.
final class FirebaseSetSaleTenderCallable implements SetSaleTenderCallable {
  FirebaseSetSaleTenderCallable({FirebaseFunctions? functions})
    : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    final result = await _functions
        .httpsCallable('setSaleTender')
        .call<Object?>(payload);
    return result.data;
  }
}

/// Why a payment method was not recorded.
enum TenantSaleTenderFailure {
  /// Somebody other than the cashier who rang the sale up.
  forbidden,

  /// The sale is not there to answer for.
  notFound,

  /// The sale already names the method that was chosen.
  alreadyRecorded,

  /// The shift this sale belongs to has been counted off, so its split has
  /// already been reconciled against and may no longer move.
  shiftClosed,

  /// The server refused for a reason this app does not model.
  refused,

  /// The answer never arrived. It may or may not have been recorded.
  ambiguous,
}

final class TenantSaleTenderException implements Exception {
  const TenantSaleTenderException(this.failure);

  final TenantSaleTenderFailure failure;

  @override
  String toString() => 'TenantSaleTenderException(${failure.name})';
}

/// What a person is told when a payment method could not be recorded.
///
/// One sentence per outcome, in the vocabulary the rest of the app uses: what
/// happened, and what is still true. The sale is untouched in every branch,
/// which is the fact worth saying first - nobody reading this is at risk of
/// having lost a sale.
String tenantSaleTenderFailureMessage(TenantSaleTenderFailure failure) =>
    switch (failure) {
      TenantSaleTenderFailure.forbidden =>
        'Only the cashier who rang this sale up can say how it was paid for. '
            'The sale itself is unchanged.',
      TenantSaleTenderFailure.notFound =>
        'This sale could not be found on the server. It may not have finished '
            'sending yet; try again once it has.',
      TenantSaleTenderFailure.alreadyRecorded =>
        'This sale already names that payment method, so nothing was changed.',
      TenantSaleTenderFailure.shiftClosed =>
        'That shift has been counted off, so the payment method on its sales '
            'can no longer be changed. The sale itself is unchanged.',
      TenantSaleTenderFailure.refused =>
        'The server did not record this payment method. The sale itself is '
            'unchanged.',
      TenantSaleTenderFailure.ambiguous =>
        'There was no answer from the server, so this may or may not have been '
            'recorded. Check the sale before trying again.',
    };

typedef TenantSaleTenderRequestIdFactory = String Function();

/// Session- and sale-bound gateway for answering *how was this paid for?*
///
/// **The only write a sale ever takes after it is created**, and the surface
/// that offers it names neither the business nor the sale: the tenant comes
/// from one captured live session and the sale from one already-decoded
/// canonical record, so no caller can point this at something else.
///
/// **One way, once.** A sale that already names a method is never offered this,
/// and the server refuses it a second time regardless - everything downstream
/// leans on a sale not moving under it, and completing a blank is a different
/// act from editing money after the fact.
final class TenantSaleTenderGateway {
  TenantSaleTenderGateway({
    required TenantSession session,
    required TenantSale target,
    required SetSaleTenderCallable callable,
    TenantSaleTenderRequestIdFactory? requestIdFactory,
  }) : _session = session,
       _target = target,
       _callable = callable,
       _requestIdFactory = requestIdFactory ?? _secureSaleTenderRequestId;

  final TenantSession _session;
  final TenantSale _target;
  final SetSaleTenderCallable _callable;
  final TenantSaleTenderRequestIdFactory _requestIdFactory;

  /// Whether answering this sale would replace a method already on it.
  ///
  /// **Both a blank and a recorded method can be answered for**, and what
  /// separates them is the shift rather than the sale: a blank may be filled
  /// whenever, and a recorded method may be corrected only until its shift is
  /// counted off. This surface cannot see the shift without a read of its own,
  /// so the server is the authority and its refusal is what says so - see
  /// [TenantSaleTenderFailure.shiftClosed].
  static bool replaces(TenantSale target) => target.tender != null;

  /// Whether [session] is the cashier who rang [target] up.
  ///
  /// Checked here as well as on the server so the action is never offered to
  /// somebody it would refuse. The server is what enforces it.
  static bool canRecordInSession(TenantSession session, TenantSale target) =>
      session.canAccess() && target.soldById == session.uid;

  Future<void> record(CheckoutTender tender) async {
    if (!canRecordInSession(_session, _target)) {
      throw const TenantSaleTenderException(TenantSaleTenderFailure.forbidden);
    }
    if (_target.tender == tender) {
      throw const TenantSaleTenderException(
        TenantSaleTenderFailure.alreadyRecorded,
      );
    }
    if (_target.tenantId != _session.tenantId) {
      throw const TenantSaleTenderException(TenantSaleTenderFailure.forbidden);
    }
    final requestId = _requestIdFactory();
    if (!_requestIdPattern.hasMatch(requestId)) {
      throw StateError('The sale tender request ID generator is invalid.');
    }
    try {
      await _callable.call(<String, Object?>{
        'tenantId': _session.tenantId,
        'saleId': _target.id,
        'tender': tender.wireValue,
        'requestId': requestId,
      });
    } on FirebaseFunctionsException catch (error) {
      throw TenantSaleTenderException(_classify(error));
    } on TimeoutException {
      throw const TenantSaleTenderException(TenantSaleTenderFailure.ambiguous);
    } catch (_) {
      throw const TenantSaleTenderException(TenantSaleTenderFailure.ambiguous);
    }
  }
}

/// Classifies a refusal from the callable.
///
/// The code decides the outcome, and the one ambiguous code is separated by the
/// exact wording `functions/src/operations/saleTender.ts` raises. If that
/// wording ever changes the case degrades to
/// [TenantSaleTenderFailure.refused], which still reports truthfully that
/// nothing was recorded.
TenantSaleTenderFailure _classify(FirebaseFunctionsException error) {
  final message = error.message ?? '';
  return switch (error.code) {
    'permission-denied' ||
    'unauthenticated' => TenantSaleTenderFailure.forbidden,
    'not-found' => TenantSaleTenderFailure.notFound,
    'unavailable' ||
    'deadline-exceeded' ||
    'internal' ||
    'aborted' ||
    'unknown' => TenantSaleTenderFailure.ambiguous,
    'failed-precondition' when message.contains('counted off') =>
      TenantSaleTenderFailure.shiftClosed,
    'failed-precondition' when message.contains('already names') =>
      TenantSaleTenderFailure.alreadyRecorded,
    _ => TenantSaleTenderFailure.refused,
  };
}

String _secureSaleTenderRequestId() {
  final random = Random.secure();
  final bytes = List<int>.generate(18, (_) => random.nextInt(256));
  return 'set-sale-tender-${base64Url.encode(bytes).replaceAll('=', '')}';
}

final RegExp _requestIdPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{7,127}$');

/// Asks how one sale was paid for, and returns the answer.
///
/// **The three methods and nothing else**, including no way to say *still not
/// recorded*: that is what the sale already says, and Cancel is how a person
/// leaves it saying so. Offering it as a fourth choice would invite a second
/// decision where there is only one to make.
///
/// A sale that already names a method reads as a correction rather than an
/// answer, and says what it is replacing.
Future<CheckoutTender?> showSaleTenderDialog(
  BuildContext context, {
  required TenantSale sale,
}) => showAppDialog<CheckoutTender>(
  context,
  barrierDismissible: true,
  builder: (dialogContext) => _SaleTenderDialog(sale: sale),
);

final class _SaleTenderDialog extends StatelessWidget {
  const _SaleTenderDialog({required this.sale});

  final TenantSale sale;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return AppDialog(
      key: const ValueKey('sale-tender-dialog'),
      title: 'Set payment method',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            'How did the customer pay for ${sale.receiptNumber}?',
            style: tokens.typography.bodyMedium,
          ),
          SizedBox(height: tokens.spacing.s8),
          // Said here because this dialog is a surface that records a tender,
          // and `checkout_tender.dart` requires every one of them to say what
          // the value is evidence of. The second sentence is the bound: a
          // correction is possible while the drawer is still being filled, and
          // stops once it has been counted against.
          Text(
            sale.tender == null
                ? 'This records what you say happened. It is not a verified '
                      'payment.'
                : 'This sale says ${sale.tender!.label}. Changing it records '
                      'what you say happened, and is only possible until the '
                      'shift is counted off.',
            key: const ValueKey('sale-tender-caveat'),
            style: tokens.typography.caption.copyWith(
              color: tokens.colors.text.tertiary,
            ),
          ),
          SizedBox(height: tokens.spacing.s16),
          for (final tender in CheckoutTender.values) ...<Widget>[
            AppButton(
              key: ValueKey('sale-tender-choice-${tender.wireValue}'),
              label: tender.label,
              tier: AppButtonTier.secondary,
              onPressed: () => Navigator.of(context).pop(tender),
            ),
            SizedBox(height: tokens.spacing.s8),
          ],
        ],
      ),
      actions: <Widget>[
        AppButton(
          key: const ValueKey('sale-tender-cancel'),
          label: 'Cancel',
          tier: AppButtonTier.tertiary,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
