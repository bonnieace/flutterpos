import 'dart:async';

/// Asks the routing shell to re-run its bootstrap from scratch.
///
/// **For the work the composition root does above the shell rather than inside
/// it.** `TenantRoutingShell` learns about a new identity from
/// `authUidChanges`, and about everything else from the flow that changed it -
/// accepting an invitation, requesting a tenant, switching business - because
/// those flows are the shell's own routes and can call back into it directly.
/// A route *pushed over* the shell has no such reach, and the sign-in screen's
/// account-creation wizard is one: it creates the tenant and then pops,
/// revealing a shell whose last bootstrap ran before the tenant existed.
///
/// This is the callback those pushed routes do not have, in the stream shape
/// the shell already takes its other out-of-band events in.
final class TenantBootstrapRefreshSignals {
  TenantBootstrapRefreshSignals();

  final StreamController<Object?> _requests =
      StreamController<Object?>.broadcast();

  /// Cached deliberately: the routing shell compares this stream by identity to
  /// decide whether to resubscribe, and a broadcast controller hands out a new
  /// stream object on every `.stream` read.
  late final Stream<Object?> requests = _requests.stream;

  /// A wizard pushed above the shell has created the business it was opened to
  /// create. What the shell resolved before it existed is now wrong.
  void requestAfterBusinessCreated() =>
      _add(const TenantBusinessCreatedRefreshRequest());

  Future<void> dispose() async {
    await _requests.close();
  }

  void _add(Object? event) {
    if (_requests.isClosed) return;
    _requests.add(event);
  }
}

/// Why a refresh was asked for, so a log or a test can say which edge ran.
final class TenantBusinessCreatedRefreshRequest {
  const TenantBusinessCreatedRefreshRequest();

  @override
  String toString() => 'TenantBusinessCreatedRefreshRequest()';
}
