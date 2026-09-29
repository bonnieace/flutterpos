import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:in_app_update/in_app_update.dart';

import '../observability/app_telemetry.dart';

/// The two questions the gate asks Google Play, so a test can answer them.
abstract interface class PlayUpdates {
  Future<AppUpdateInfo> checkForUpdate();
  Future<AppUpdateResult> performImmediateUpdate();
}

/// [PlayUpdates] answered by the Play Core library on the device.
final class InAppPlayUpdates implements PlayUpdates {
  const InAppPlayUpdates();

  @override
  Future<AppUpdateInfo> checkForUpdate() => InAppUpdate.checkForUpdate();

  @override
  Future<AppUpdateResult> performImmediateUpdate() =>
      InAppUpdate.performImmediateUpdate();
}

/// Puts any newer build Play holds in front of an Android install from Play.
///
/// **Ported from AquaFlow's `feat/sentry`**: asked on the first frame and on
/// every return to the foreground, and answered with Play's own full-screen
/// update, which restarts the app into the new build. Every newer build is
/// offered this way; nothing reads Play's update priority.
///
/// **Not while a sale is on the till.** The restart would lose a cart that has
/// not been saved, so a return to the foreground with one skips the check and
/// the next return asks again. It is read twice, because a cashier can start a
/// sale in the time Play takes to answer.
///
/// **Declining is allowed**, as it was in AquaFlow: nothing is blocked, and the
/// next return to the foreground offers it again.
///
/// **An install Play does not own is not a failure.** A sideloaded SIT build,
/// or an emulator with no Play Store, is refused by Play every time it asks,
/// so those refusals are dropped and anything else is reported.
final class PlayUpdateGate extends StatefulWidget {
  const PlayUpdateGate({
    super.key,
    required this.saleInProgress,
    required this.child,
    this.updates = const InAppPlayUpdates(),
  });

  final bool Function() saleInProgress;
  final PlayUpdates updates;
  final Widget child;

  @override
  State<PlayUpdateGate> createState() => _PlayUpdateGateState();
}

final class _PlayUpdateGateState extends State<PlayUpdateGate>
    with WidgetsBindingObserver {
  /// Play Core's `InstallErrorCode`s for an install it cannot update: not
  /// installed from Play (-10), no Play Store (-9), no update API (-3).
  static const _notUpdatableByPlay = <int>{-10, -9, -3};

  static final _installError = RegExp(r'Install Error\((-?\d+)\)');

  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    if (kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android ||
        _checking ||
        widget.saleInProgress()) {
      return;
    }
    _checking = true;
    try {
      final info = await widget.updates.checkForUpdate();
      final available =
          info.updateAvailability == UpdateAvailability.updateAvailable ||
          info.updateAvailability ==
              UpdateAvailability.developerTriggeredUpdateInProgress;
      if (!available || !info.immediateUpdateAllowed) return;
      if (widget.saleInProgress()) return;
      final result = await widget.updates.performImmediateUpdate();
      if (result == AppUpdateResult.inAppUpdateFailed) {
        AppTelemetry.captureHandled(
          StateError('The Play update did not complete.'),
          StackTrace.current,
          boundary: 'app.play_update',
          code: 'in-app-update-failed',
        );
      }
    } on PlatformException catch (error, stackTrace) {
      final match = _installError.firstMatch(error.message ?? '');
      final code = match == null ? null : int.parse(match.group(1)!);
      if (_notUpdatableByPlay.contains(code)) return;
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        boundary: 'app.play_update',
        code: code == null ? null : 'play-install-error$code',
      );
    } catch (error, stackTrace) {
      AppTelemetry.captureHandled(
        error,
        stackTrace,
        boundary: 'app.play_update',
      );
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
