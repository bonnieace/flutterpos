import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:uzapay_pos/observability/app_telemetry.dart';
import 'package:uzapay_pos/platform/play_update_gate.dart';

void main() {
  late _Play play;
  late RecordingAppTelemetry telemetry;
  var saleInProgress = false;

  setUp(() {
    play = _Play();
    telemetry = RecordingAppTelemetry(retain: true);
    saleInProgress = false;
  });

  Future<void> pump(WidgetTester tester) => AppTelemetry.withInstance(
    telemetry,
    () async {
      await tester.pumpWidget(
        PlayUpdateGate(
          saleInProgress: () => saleInProgress,
          updates: play,
          child: const SizedBox(),
        ),
      );
      await tester.pump();
    },
  );

  Future<void> resume(WidgetTester tester) => AppTelemetry.withInstance(
    telemetry,
    () async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
    },
  );

  testWidgets('a newer build is put in front on the first frame', (
    tester,
  ) async {
    await pump(tester);
    expect(play.checks, 1);
    expect(play.updates, 1);
  });

  testWidgets('nothing newer, nothing shown', (tester) async {
    play.info = _info(UpdateAvailability.updateNotAvailable);
    await pump(tester);
    expect(play.checks, 1);
    expect(play.updates, 0);
  });

  testWidgets('a return to the foreground asks again', (tester) async {
    await pump(tester);
    await resume(tester);
    expect(play.checks, 2);
    expect(play.updates, 2);
  });

  testWidgets('a sale on the till skips the check until the next return', (
    tester,
  ) async {
    play.info = _info(UpdateAvailability.updateNotAvailable);
    await pump(tester);
    play.info = _info(UpdateAvailability.updateAvailable);

    saleInProgress = true;
    await resume(tester);
    expect(play.checks, 1);

    saleInProgress = false;
    await resume(tester);
    expect(play.checks, 2);
    expect(play.updates, 1);
  });

  testWidgets('a sale started while Play answers is not interrupted', (
    tester,
  ) async {
    final answer = Completer<AppUpdateInfo>();
    play.pending = answer;
    await pump(tester);

    saleInProgress = true;
    answer.complete(_info(UpdateAvailability.updateAvailable));
    await tester.pump();
    expect(play.updates, 0);
  });

  testWidgets('an install Play does not own reports nothing', (tester) async {
    play.failure = _installError(-10);
    await pump(tester);
    expect(telemetry.failures, isEmpty);
  });

  testWidgets('a Play Store the app cannot bind to reports nothing', (
    tester,
  ) async {
    // Seen on the google_apis emulator on 2026-09-29: Play Core's own
    // exception, with no install error code in it.
    play.failure = PlatformException(
      code: 'TASK_FAILURE',
      message: 'Failed to bind to the service.',
    );
    await pump(tester);
    expect(telemetry.failures, isEmpty);
  });

  testWidgets('any other Play refusal is reported with its code', (
    tester,
  ) async {
    play.failure = _installError(-100);
    await pump(tester);
    final failure = telemetry.failures.single;
    expect(failure.operation.name, 'app.play_update');
    expect(failure.code, 'play-install-error-100');
  });

  testWidgets('an update that failed is reported, a declined one is not', (
    tester,
  ) async {
    play.result = AppUpdateResult.userDeniedUpdate;
    await pump(tester);
    expect(telemetry.failures, isEmpty);

    play.result = AppUpdateResult.inAppUpdateFailed;
    await resume(tester);
    expect(telemetry.failures.single.code, 'in-app-update-failed');
  });
}

AppUpdateInfo _info(UpdateAvailability availability) => AppUpdateInfo(
  updateAvailability: availability,
  immediateUpdateAllowed: true,
  immediateAllowedPreconditions: null,
  flexibleUpdateAllowed: true,
  flexibleAllowedPreconditions: null,
  availableVersionCode: 4,
  installStatus: InstallStatus.unknown,
  packageName: 'ke.co.uzapay.pos',
  clientVersionStalenessDays: 0,
  updatePriority: 0,
);

/// What the plugin raises when Play Core refuses the check.
PlatformException _installError(int code) => PlatformException(
  code: 'TASK_FAILURE',
  message: '$code: Install Error($code): refused by Play.',
);

final class _Play implements PlayUpdates {
  AppUpdateInfo info = _info(UpdateAvailability.updateAvailable);
  AppUpdateResult result = AppUpdateResult.success;
  PlatformException? failure;
  Completer<AppUpdateInfo>? pending;
  var checks = 0;
  var updates = 0;

  @override
  Future<AppUpdateInfo> checkForUpdate() async {
    checks++;
    final error = failure;
    if (error != null) throw error;
    return pending?.future ?? info;
  }

  @override
  Future<AppUpdateResult> performImmediateUpdate() async {
    updates++;
    return result;
  }
}
