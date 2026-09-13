import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

const _token = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';

Uri _invitation({String version = '4'}) => Uri.parse(
  'https://pos.example.test/staff/invitation?tenantId=tenant-a&uid=user-a'
  '&invitationVersion=$version&invitationToken=$_token',
);

final class _FakeSource implements InvitationLinkSource {
  _FakeSource([this.launch]);

  final Uri? launch;
  final StreamController<Uri> controller = StreamController<Uri>.broadcast();
  int takes = 0;

  @override
  Future<Uri?> takeLaunchLink() async {
    takes++;
    return launch;
  }

  @override
  Stream<Uri> get links => controller.stream;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('an arrival', () {
    test('is nothing at all for a URI carrying no invitation', () {
      // The app answers two other App Links. Neither may put a screen in front
      // of somebody: they exist to bring the app forward, not to say anything.
      expect(
        TenantInvitationArrival.fromUri(
          Uri.parse('https://pos.example.test/auth/verified'),
        ),
        isNull,
      );
    });

    test('is the link itself when the URI carries a whole one', () {
      final arrival = TenantInvitationArrival.fromUri(_invitation());

      expect(arrival?.invalid, isFalse);
      expect(arrival?.link?.tenantId, 'tenant-a');
      expect(arrival?.link?.invitedUid, 'user-a');
      expect(arrival?.link?.invitationVersion, 4);
      expect(arrival?.link?.invitationToken, _token);
    });

    test('is invalid, rather than absent, for a half-written one', () {
      // Dropping it would leave somebody who followed a link looking at a
      // screen that never mentions the link.
      expect(
        TenantInvitationArrival.fromUri(
          Uri.parse('https://pos.example.test/staff/invitation?tenantId=t'),
        )?.invalid,
        isTrue,
      );
      expect(
        TenantInvitationArrival.fromUri(_invitation(version: '0'))?.invalid,
        isTrue,
      );
    });
  });

  group('the intake', () {
    test('reads the launch link once, before anything is built', () async {
      final source = _FakeSource(_invitation());
      final intake = InvitationLinkIntake(source);

      await intake.start();

      expect(source.takes, 1);
      expect(intake.launchArrival?.link?.tenantId, 'tenant-a');
      expect(intake.arrival.value?.invalid, isFalse);
      await intake.dispose();
    });

    test('says nothing is waiting when the app was opened some other way', () async {
      final intake = InvitationLinkIntake(_FakeSource());

      await intake.start();

      expect(intake.launchArrival, isNull);
      expect(intake.arrival.value, isNull);
      await intake.dispose();
    });

    test('forwards a link followed while the app is already up', () async {
      final source = _FakeSource();
      final intake = InvitationLinkIntake(source);
      await intake.start();
      final arrivals = <TenantInvitationArrival>[];
      intake.arrivals.listen(arrivals.add);

      source.controller.add(_invitation());
      source.controller.add(Uri.parse('https://pos.example.test/auth/verified'));
      await pumpEventQueue();

      expect(arrivals.single.link?.tenantId, 'tenant-a');
      expect(intake.arrival.value?.invalid, isFalse);
      await intake.dispose();
    });

    test('a link that cannot be read is reported as unreadable, not as waiting', () async {
      // **Three states, not two.** `TenantInvitationArrival.invalid()` is not
      // null, so while this was a bool a broken link read as *an invitation is
      // waiting* - and the sign-in screen promised a business that would never
      // be offered, to somebody whose password had never been set because
      // setting it is what following the link does.
      final intake = InvitationLinkIntake(
        _FakeSource(Uri.parse(
          'https://pos.example.test/staff/invitation?tenantId=t',
        )),
      );

      await intake.start();

      expect(intake.arrival.value, isNotNull);
      expect(intake.arrival.value!.invalid, isTrue);
      expect(intake.arrival.value!.link, isNull);
      await intake.dispose();
    });

    test('stops saying an invitation waits once it has been settled', () async {
      final intake = InvitationLinkIntake(_FakeSource(_invitation()));
      await intake.start();
      expect(intake.arrival.value?.invalid, isFalse);

      intake.settled();

      expect(intake.arrival.value, isNull);
      await intake.dispose();
    });
  });

  group('the platform source', () {
    const channel = MethodChannel(PlatformInvitationLinkSource.channelName);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test('takes the launch URL the intent carried', () async {
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return _invitation().toString();
      });

      final source = PlatformInvitationLinkSource();

      expect(await source.takeLaunchLink(), _invitation());
      expect(calls, ['takeLaunchLink']);
      await source.dispose();
    });

    test('reports no link on a platform that has no such channel', () async {
      // Every platform but Android, where this is not a failure: there is no
      // link to report because nothing can deliver one.
      final source = PlatformInvitationLinkSource();

      expect(await source.takeLaunchLink(), isNull);
      await source.dispose();
    });

    test('turns a link pushed by the activity into a stream event', () async {
      final source = PlatformInvitationLinkSource();
      final seen = <Uri>[];
      source.links.listen(seen.add);

      await messenger.handlePlatformMessage(
        PlatformInvitationLinkSource.channelName,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('launchLink', _invitation().toString()),
        ),
        (_) {},
      );
      await pumpEventQueue();

      expect(seen.single, _invitation());
      await source.dispose();
    });
  });
}
