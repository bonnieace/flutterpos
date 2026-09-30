import 'dart:io';
import 'dart:math';

import 'package:uzapay_pos/checkout/checkout.dart';
import 'package:uzapay_pos/platform/device_identity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory directory;
  late Box<dynamic> box;
  late HiveCheckoutReceiptCounters counters;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('checkout-receipt-test-');
    Hive.init(directory.path);
    box = await _openBox();
    counters = _counters(box);
  });

  tearDown(() async {
    await Hive.close();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  group('the number as printed', () {
    // Chosen by the product owner on 2026-09-29: the cashier's first name, the
    // till and the day's sequence. The stored number is untouched.
    const stored = 'CT-7F2-20260929-0001';

    test('leads with the first name and drops the date', () {
      expect(
        printedCheckoutReceiptNumber(stored, servedBy: 'John Kamau'),
        'JOHN-CT-7F2-001',
      );
    });

    test('prints the till and sequence alone where there is no name', () {
      for (final servedBy in <String?>[null, '', '   ', '--']) {
        expect(
          printedCheckoutReceiptNumber(stored, servedBy: servedBy),
          'CT-7F2-001',
          reason: '$servedBy',
        );
      }
    });

    test('keeps a long name to ten letters and drops punctuation', () {
      expect(
        printedCheckoutReceiptNumber(stored, servedBy: 'Wanjiru-Nyambura'),
        'WANJIRUNYA-CT-7F2-001',
      );
      expect(
        printedCheckoutReceiptNumber(stored, servedBy: "O'Brien"),
        'OBRIEN-CT-7F2-001',
      );
    });

    test('keeps a letter the printer will substitute rather than losing it', () {
      // `ReceiptText.forPrinter` maps it on the way to paper; dropping it here
      // would shorten a name without trace.
      expect(
        printedCheckoutReceiptNumber(stored, servedBy: 'Gĩkũyũ'),
        'GĨKŨYŨ-CT-7F2-001',
      );
    });

    test('pads to three digits and widens rather than wrapping', () {
      for (final (sequence, printed) in <(String, String)>[
        ('0001', '001'),
        ('0999', '999'),
        ('1000', '1000'),
        ('123456', '123456'),
      ]) {
        expect(
          printedCheckoutReceiptNumber(
            'CT-7F2-20260929-$sequence',
            servedBy: 'John',
          ),
          'JOHN-CT-7F2-$printed',
        );
      }
    });

    test('returns a number it cannot read exactly as it is', () {
      // A customer must never be handed a receipt with no number on it.
      expect(
        printedCheckoutReceiptNumber('not-a-receipt', servedBy: 'John'),
        'not-a-receipt',
      );
    });

    test('reads back as the till and sequence, with or without the rest', () {
      for (final typed in <String>[
        'JOHN-CT-7F2-001',
        'john-ct-7f2-001',
        ' CT-7F2-001 ',
        '7F2-001',
        'JOHN-7F2-1',
        'GĨKŨYŨ-CT-7F2-001',
      ]) {
        final reference = parsePrintedCheckoutReceipt(typed);
        expect(reference, isNotNull, reason: typed);
        expect(reference!.deviceCode, '7F2', reason: typed);
        expect(reference.sequence, 1, reason: typed);
      }
    });

    test('reads nothing that is not a printed number', () {
      for (final typed in <String>[
        '',
        '0042',
        stored,
        'JOHN-CT-7G2-001',
        'JOHN-CT-7F2-000',
        'JOHN-CT-7F2-1000000',
        'JOHN CT-7F2-001',
      ]) {
        expect(parsePrintedCheckoutReceipt(typed), isNull, reason: typed);
      }
    });
  });

  group('frozen receipt shape', () {
    test('emits the CT-A7F-20260729-0042 shape', () {
      final receipt = formatCheckoutReceiptNumber(
        deviceId: _deviceId,
        businessDate: '2026-07-29',
        sequence: 42,
      );

      expect(receipt, matches(checkoutReceiptNumberPattern));
      final parts = receipt.split('-');
      expect(parts.first, checkoutReceiptPrefix);
      expect(parts[1], checkoutReceiptDeviceCode(_deviceId));
      expect(parts[1], hasLength(checkoutReceiptDeviceCodeLength));
      expect(parts[2], '20260729');
      expect(parts[3], '0042');
    });

    test('derives a stable device code that never exposes the device ID', () {
      final code = checkoutReceiptDeviceCode(_deviceId);

      expect(code, checkoutReceiptDeviceCode(_deviceId));
      expect(code, isNot(checkoutReceiptDeviceCode(_otherDeviceId)));
      expect(code, matches(RegExp(r'^[0-9A-F]{3}$')));
    });

    test('widens rather than wrapping a busy sequence', () {
      expect(
        formatCheckoutReceiptNumber(
          deviceId: _deviceId,
          businessDate: '2026-07-29',
          sequence: 9999,
        ).split('-')[3],
        '9999',
      );
      expect(
        formatCheckoutReceiptNumber(
          deviceId: _deviceId,
          businessDate: '2026-07-29',
          sequence: 10000,
        ).split('-')[3],
        '10000',
      );
      expect(
        () => formatCheckoutReceiptNumber(
          deviceId: _deviceId,
          businessDate: '2026-07-29',
          sequence: 0,
        ),
        throwsArgumentError,
      );
      expect(
        () => formatCheckoutReceiptNumber(
          deviceId: _deviceId,
          businessDate: '2026-07-29',
          sequence: maximumCheckoutReceiptSequence + 1,
        ),
        throwsArgumentError,
      );
    });

    test('refuses an unusable device ID or business date', () {
      expect(() => checkoutReceiptDeviceCode('device-a'), throwsArgumentError);
      expect(() => checkoutReceiptDeviceCode(''), throwsArgumentError);
      expect(
        () => formatCheckoutReceiptNumber(
          deviceId: _deviceId,
          businessDate: '29-07-2026',
          sequence: 1,
        ),
        throwsArgumentError,
      );
      expect(
        () => formatCheckoutReceiptNumber(
          deviceId: _deviceId,
          businessDate: '2026-02-30',
          sequence: 1,
        ),
        throwsArgumentError,
      );
    });

    test('uses the frozen counter key, unscoped by cashier UID', () {
      final key = checkoutReceiptCounterKey(
        tenantId: 'tenant-a',
        deviceId: _deviceId,
        businessDate: '2026-07-29',
      );

      expect(key, 'tenant-a:$_deviceId:2026-07-29:receiptCounter');
      expect(key.contains('user'), isFalse);
      expect(
        key,
        isNot(HiveCheckoutReceiptCounters.deviceIdentityKey),
        reason: 'The reserved identity key can never collide with a counter.',
      );
      expect(
        HiveCheckoutReceiptCounters.deviceIdentityKey.contains(':'),
        isFalse,
      );
    });
  });

  group('durable device identity', () {
    test('resolves exactly once and survives a restart', () async {
      final first = await counters.resolveDeviceId();
      final again = await counters.resolveDeviceId();
      expect(again, first);
      validateCheckoutDeviceId(first);

      await counters.close();
      box = await _openBox();
      final restored = await _counters(box).resolveDeviceId();

      expect(restored, first);
    });

    test('binds a new identity to the device the platform names', () async {
      final first = await _counters(
        box,
        hardware: const _Hardware('android-id-a'),
      ).resolveDeviceId();

      // What a reinstall leaves behind: the app's own data is gone, and the
      // platform still answers the same thing.
      await box.delete(HiveCheckoutReceiptCounters.deviceIdentityKey);
      final second = await _counters(
        box,
        seed: 29,
        hardware: const _Hardware('android-id-a'),
      ).resolveDeviceId();

      expect(
        checkoutDeviceHardwareDigest(second),
        checkoutDeviceHardwareDigest(first),
        reason: 'The same till must be recognisable as itself.',
      );
      expect(
        checkoutDeviceHardwareDigest(first),
        deriveCheckoutDeviceHardwareDigest('android-id-a'),
      );
      expect(
        first,
        contains(deriveCheckoutDeviceHardwareDigest('android-id-a')),
      );
    });

    test('gives a reinstalled till a receipt code of its own', () async {
      final first = await _counters(
        box,
        hardware: const _Hardware('android-id-a'),
      ).resolveDeviceId();
      await box.delete(HiveCheckoutReceiptCounters.deviceIdentityKey);
      final second = await _counters(
        box,
        seed: 29,
        hardware: const _Hardware('android-id-a'),
      ).resolveDeviceId();

      // The counter died with the app's data. If the receipt device code came
      // back unchanged the restarted sequence would reissue today's numbers.
      expect(second, isNot(first));
      expect(
        checkoutReceiptDeviceCode(second),
        isNot(checkoutReceiptDeviceCode(first)),
      );
    });

    test('separates two devices that answer differently', () async {
      final first = await _counters(
        box,
        hardware: const _Hardware('android-id-a'),
      ).resolveDeviceId();
      await box.delete(HiveCheckoutReceiptCounters.deviceIdentityKey);
      final second = await _counters(
        box,
        hardware: const _Hardware('android-id-b'),
      ).resolveDeviceId();

      expect(
        checkoutDeviceHardwareDigest(second),
        isNot(checkoutDeviceHardwareDigest(first)),
      );
    });

    test('falls back to random where the platform offers nothing', () async {
      final deviceId = await _counters(
        box,
        hardware: const _Hardware(null),
      ).resolveDeviceId();

      validateCheckoutDeviceId(deviceId);
      await box.delete(HiveCheckoutReceiptCounters.deviceIdentityKey);
      final second = await _counters(
        box,
        seed: 29,
        hardware: const _Hardware(null),
      ).resolveDeviceId();

      expect(
        checkoutDeviceHardwareDigest(second),
        isNot(checkoutDeviceHardwareDigest(deviceId)),
        reason: 'Nothing durable was offered, so nothing durable is claimed.',
      );
    });

    test('leaves an identity that is already stored alone', () async {
      final first = await counters.resolveDeviceId();

      final restored = await _counters(
        box,
        hardware: const _Hardware('android-id-a'),
      ).resolveDeviceId();

      // Rebinding would change the receipt device code of a till mid-day and
      // orphan the counter standing behind it.
      expect(restored, first);
    });

    test('never regenerates a corrupt installation identity', () async {
      await box.put(HiveCheckoutReceiptCounters.deviceIdentityKey, {
        'schemaVersion': HiveCheckoutReceiptCounters.schemaVersion,
        'deviceId': 'workstation-1',
      });

      await expectLater(
        _counters(box).resolveDeviceId(),
        throwsA(
          isA<CheckoutReceiptException>().having(
            (error) => error.code,
            'code',
            'malformed_device_identity',
          ),
        ),
      );
    });

    test('generates distinct identities on distinct installations', () async {
      final other = HiveCheckoutReceiptCounters.fromBox(
        await Hive.openBox<dynamic>('checkout-receipt-counters-other'),
        clock: _clock,
        random: Random(99),
      );

      expect(
        await other.resolveDeviceId(),
        isNot(await counters.resolveDeviceId()),
      );
    });
  });

  group('atomic device counters', () {
    test('gives two cashiers on one device different sequences', () async {
      // The counter is device-scoped, so the cashier UID never appears in it.
      final first = await counters.allocateSequence(
        tenantId: 'tenant-a',
        deviceId: _deviceId,
        businessDate: '2026-07-29',
      );
      final second = await counters.allocateSequence(
        tenantId: 'tenant-a',
        deviceId: _deviceId,
        businessDate: '2026-07-29',
      );

      expect((first, second), (1, 2));
    });

    test(
      'serializes concurrent allocations without repeating a value',
      () async {
        final allocated = await Future.wait<int>([
          for (var index = 0; index < 25; index++)
            counters.allocateSequence(
              tenantId: 'tenant-a',
              deviceId: _deviceId,
              businessDate: '2026-07-29',
            ),
        ]);

        expect(allocated.toSet(), hasLength(25));
        expect(allocated.reduce(max), 25);
      },
    );

    test('keeps counters independent per device, tenant, and date', () async {
      Future<int> allocate({
        String tenantId = 'tenant-a',
        String deviceId = _deviceId,
        String businessDate = '2026-07-29',
      }) => counters.allocateSequence(
        tenantId: tenantId,
        deviceId: deviceId,
        businessDate: businessDate,
      );

      expect(await allocate(), 1);
      expect(await allocate(), 2);
      expect(await allocate(deviceId: _otherDeviceId), 1);
      expect(await allocate(tenantId: 'tenant-b'), 1);
      expect(await allocate(businessDate: '2026-07-30'), 1);
      expect(await allocate(), 3);
    });

    test('continues the sequence after an encrypted restart', () async {
      await counters.allocateSequence(
        tenantId: 'tenant-a',
        deviceId: _deviceId,
        businessDate: '2026-07-29',
      );
      await counters.allocateSequence(
        tenantId: 'tenant-a',
        deviceId: _deviceId,
        businessDate: '2026-07-29',
      );
      await counters.close();

      box = await _openBox();
      final reopened = _counters(box);

      expect(
        await reopened.lastSequence(
          tenantId: 'tenant-a',
          deviceId: _deviceId,
          businessDate: '2026-07-29',
        ),
        2,
      );
      expect(
        await reopened.allocateSequence(
          tenantId: 'tenant-a',
          deviceId: _deviceId,
          businessDate: '2026-07-29',
        ),
        3,
      );
    });

    test('never restarts a malformed or foreign counter', () async {
      final key = checkoutReceiptCounterKey(
        tenantId: 'tenant-a',
        deviceId: _deviceId,
        businessDate: '2026-07-29',
      );
      final valid = <String, Object?>{
        'schemaVersion': HiveCheckoutReceiptCounters.schemaVersion,
        'tenantId': 'tenant-a',
        'deviceId': _deviceId,
        'businessDate': '2026-07-29',
        'sequence': 4,
        'updatedAtMs': 0,
      };
      Future<void> expectRefused(Object? stored) async {
        await box.put(key, stored);
        await expectLater(
          counters.allocateSequence(
            tenantId: 'tenant-a',
            deviceId: _deviceId,
            businessDate: '2026-07-29',
          ),
          throwsA(
            isA<CheckoutReceiptException>().having(
              (error) => error.code,
              'code',
              'malformed_receipt_counter',
            ),
          ),
        );
      }

      await box.put(key, valid);
      expect(
        await counters.allocateSequence(
          tenantId: 'tenant-a',
          deviceId: _deviceId,
          businessDate: '2026-07-29',
        ),
        5,
      );
      Map<String, Object?> mutated(Map<String, Object?> changes) =>
          <String, Object?>{...valid, ...changes};

      await expectRefused(mutated(const {'sequence': 0}));
      await expectRefused(mutated(const {'sequence': '6'}));
      await expectRefused(mutated(const {'schemaVersion': 99}));
      await expectRefused(mutated(const {'tenantId': 'tenant-b'}));
      await expectRefused(mutated(const {'businessDate': '2026-07-30'}));
      await expectRefused('not-a-record');
    });

    test('refuses to wrap an exhausted daily sequence', () async {
      await box.put(
        checkoutReceiptCounterKey(
          tenantId: 'tenant-a',
          deviceId: _deviceId,
          businessDate: '2026-07-29',
        ),
        <String, Object?>{
          'schemaVersion': HiveCheckoutReceiptCounters.schemaVersion,
          'tenantId': 'tenant-a',
          'deviceId': _deviceId,
          'businessDate': '2026-07-29',
          'sequence': maximumCheckoutReceiptSequence,
          'updatedAtMs': 0,
        },
      );

      await expectLater(
        counters.allocateSequence(
          tenantId: 'tenant-a',
          deviceId: _deviceId,
          businessDate: '2026-07-29',
        ),
        throwsA(
          isA<CheckoutReceiptException>().having(
            (error) => error.code,
            'code',
            'receipt_sequence_exhausted',
          ),
        ),
      );
    });
  });
  group('a stored identity is the identity', () {
    /// #111: the pre-hardware rebinding is gone. SIT clears app data rather
    /// than migrating it, so there is no identity left that was minted before
    /// the platform could be asked - and a stored ID is now simply returned.
    const stored = 'dev-0123456789abcdef0123456789abcdef';

    test('is returned unchanged, whatever the platform now answers', () async {
      await box
          .put(HiveCheckoutReceiptCounters.deviceIdentityKey, <String, Object?>{
            'schemaVersion': HiveCheckoutReceiptCounters.schemaVersion,
            'deviceId': stored,
            'createdAtMs': 0,
          });

      expect(
        await _counters(
          box,
          hardware: const _Hardware('android-id-a'),
        ).resolveDeviceId(),
        stored,
      );
    });

    test(
      'an identity minted with the platform is stable across launches',
      () async {
        final minted = await _counters(
          box,
          hardware: const _Hardware('android-id-a'),
        ).resolveDeviceId();

        // A platform that starts answering differently - a re-signed build, a
        // second Android user - cannot move a till that already has an ID.
        final again = await _counters(
          box,
          hardware: const _Hardware('android-id-b'),
        ).resolveDeviceId();

        expect(again, minted);
        // The durable half still digests the platform's answer on a fresh mint,
        // which is the behaviour this issue was careful to keep.
        expect(
          checkoutDeviceHardwareDigest(minted),
          deriveCheckoutDeviceHardwareDigest('android-id-a'),
        );
      },
    );
  });
}

const String _deviceId = 'dev-0123456789abcdef0123456789abcdef';
const String _otherDeviceId = 'dev-fedcba9876543210fedcba9876543210';

DateTime _clock() => DateTime.utc(2026, 7, 29, 12);

Future<Box<dynamic>> _openBox() => Hive.openBox<dynamic>(
  HiveCheckoutReceiptCounters.boxName,
  encryptionCipher: HiveAesCipher(_encryptionKey),
  crashRecovery: false,
);

HiveCheckoutReceiptCounters _counters(
  Box<dynamic> box, {
  int seed = 11,
  DeviceHardwareIdentity? hardware,
}) => HiveCheckoutReceiptCounters.fromBox(
  box,
  clock: _clock,
  random: Random(seed),
  hardwareIdentity: hardware,
);

/// What the platform answers, including when it answers nothing.
final class _Hardware implements DeviceHardwareIdentity {
  const _Hardware(this._value);

  final String? _value;

  @override
  Future<String?> read() async => _value;
}

final List<int> _encryptionKey = List<int>.generate(
  HiveCheckoutReceiptCounters.encryptionKeyBytes,
  (index) => (index * 3) % 256,
);
