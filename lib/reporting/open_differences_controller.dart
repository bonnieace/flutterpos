import 'dart:async';

import 'package:flutter/foundation.dart';

import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_session.dart';
import '../tenancy/tenant_session_controller.dart';
import 'reconciliation_status.dart';
import '../observability/app_telemetry.dart';

/// How many recorded differences the selected business has not settled.
///
/// **It exists so a launcher can carry a badge.** The differences themselves
/// live in a collection keyed by digest, which can be neither ordered nor
/// counted without listing it, and a home screen must not pay for a collection
/// scan to decide whether to draw a figure. The server keeps one document with
/// the count in it and this reads that.
///
/// **A figure it does not have is null, never zero.** No completed run, an
/// unreadable document, a role that may not see differences at all - each of
/// those is *unknown*, and drawing a confident nought over any of them would
/// tell a shopkeeper their books are clean on the strength of a failed read.
final class TenantOpenDifferencesController extends ChangeNotifier {
  TenantOpenDifferencesController({
    required TenantSessionController sessionController,
    required TenantDataReader reader,
    Stream<void>? refreshSignals,
  }) : _sessionController = sessionController,
       _reader = reader {
    _sessionController.addListener(_onSessionChanged);
    _refreshSubscription = refreshSignals?.listen((_) => unawaited(refresh()));
    unawaited(refresh());
  }

  final TenantSessionController _sessionController;
  final TenantDataReader _reader;
  StreamSubscription<void>? _refreshSubscription;
  bool _disposed = false;

  /// The session the in-flight read belongs to, so a tenant switch mid-read can
  /// never publish one business's figure onto another's home.
  TenantSession? _pending;

  int? _openCount;

  /// The count, or null while it is unknown.
  int? get openCount => _openCount;

  void _onSessionChanged() {
    // The old business's figure must go the instant the session does, rather
    // than linger on the new one's home until a read comes back.
    if (_openCount != null) {
      _openCount = null;
      notifyListeners();
    }
    unawaited(refresh());
  }

  /// Re-reads the count for whichever session is selected now.
  Future<void> refresh() async {
    final session = _sessionController.session;
    _pending = session;
    if (session == null ||
        !TenantReconciliationStatusRepository.canReadInSession(session)) {
      _publish(session, null);
      return;
    }
    int? count;
    try {
      final summary = await TenantReconciliationStatusRepository(
        session: session,
        reader: _reader,
      ).readOpenDifferences();
      count = summary?.openCount;
    } catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        boundary: 'reporting.open_differences_read',
      );
      // **Unknown rather than none.** A read that failed says nothing about the
      // shop, and a badge is not worth failing a home screen over.
      count = null;
    }
    _publish(session, count);
  }

  void _publish(TenantSession? session, int? count) {
    if (_disposed || !identical(_pending, session)) return;
    if (_openCount == count) return;
    _openCount = count;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _refreshSubscription?.cancel();
    _sessionController.removeListener(_onSessionChanged);
    super.dispose();
  }
}
