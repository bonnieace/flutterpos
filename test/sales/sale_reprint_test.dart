import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:uzapay_pos/checkout/checkout.dart';
import 'package:uzapay_pos/sales/sales.dart';
import 'package:uzapay_pos/tenancy/tenant_session.dart';
import 'package:uzapay_pos/tenancy/tenant_types.dart';
import 'package:flutter_esc_pos_utils/flutter_esc_pos_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

const String _deviceId = 'dev-0123456789abcdef0123456789abcdef';
const String _businessDate = '2026-07-29';
const String _payloadHash =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late HivePrintJobQueue queue;
  late CapabilityProfile profile;
  late _FakeTransport transport;

  setUpAll(() async {
    profile = await CapabilityProfile.load();
  });

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('sale-reprint-test-');
    Hive.init(directory.path);
    queue = HivePrintJobQueue.fromBox(
      await Hive.openBox<dynamic>(HivePrintJobQueue.boxName),
    );
    transport = _FakeTransport();
  });

  tearDown(() async {
    await Hive.close();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  CheckoutTenantReceiptReprinter subject(
    _Callable callable, {
    TenantConfiguredPrinter? printer,
  }) => CheckoutTenantReceiptReprinter(
    dispatcher: CheckoutPrintDispatcher(
      queue: queue,
      transport: transport,
      profile: profile,
    ),
    callable: callable,
    readContext: (_) async =>
        TenantReceiptPrintContext(printer: printer ?? _printer()),
    requestIdFactory: () => 'reprint-abcdefgh',
  );

  test('records the reprint, then prints it', () async {
    final callable = _Callable();

    final report = await subject(callable).reprint(
      session: _session(role: TenantRole.manager),
      sale: _sale(),
    );

    expect(report.outcome, TenantReceiptReprintOutcome.printed);
    expect(report.reasonCode, isNull);
    // The audit names the sale, the receipt on it, and the business - which is
    // exactly what the callable proves against the immutable sale document.
    expect(callable.payloads.single, <String, Object?>{
      'tenantId': 'tenant-a',
      'saleId': 'co-1',
      'receiptNumber': _receipt(),
      'requestId': 'reprint-abcdefgh',
    });
    expect(transport.sends, hasLength(1));
  });

  test('a cashier is refused before anything is recorded', () async {
    final callable = _Callable();

    final report = await subject(callable).reprint(
      session: _session(role: TenantRole.cashier),
      sale: _sale(),
    );

    expect(report.outcome, TenantReceiptReprintOutcome.refused);
    expect(report.reasonCode, TenantReceiptReprintCode.forbidden);
    expect(callable.payloads, isEmpty);
    expect(transport.sends, isEmpty);
  });

  test('a sale from another business is refused before anything else', () async {
    final callable = _Callable();

    final report = await subject(callable).reprint(
      session: _session(role: TenantRole.owner),
      sale: _sale(tenantId: 'tenant-b'),
    );

    expect(report.outcome, TenantReceiptReprintOutcome.refused);
    expect(report.reasonCode, TenantReceiptReprintCode.notFound);
    expect(callable.payloads, isEmpty);
  });

  test('every audit refusal is named, and none of them prints', () async {
    // **The whole reason a reprint goes through the server at all.** If the
    // record cannot be written, no second piece of paper comes out.
    const refusals = <String, String>{
      'permission-denied': TenantReceiptReprintCode.forbidden,
      'unauthenticated': TenantReceiptReprintCode.forbidden,
      // A callable that was never deployed answers 404. It must never be
      // reported as a missing sale - see TenantReceiptReprintCode.serviceMissing.
      'not-found': TenantReceiptReprintCode.serviceMissing,
      'unimplemented': TenantReceiptReprintCode.serviceMissing,
      'failed-precondition': TenantReceiptReprintCode.notFound,
      // Never the missing-sale sentence: this one is a defect in what the
      // client sent, not a fact about the business's records.
      'invalid-argument': TenantReceiptReprintCode.refused,
      'unavailable': TenantReceiptReprintCode.unavailable,
      'deadline-exceeded': TenantReceiptReprintCode.unavailable,
      'internal': TenantReceiptReprintCode.refused,
    };
    for (final entry in refusals.entries) {
      final callable = _Callable(failWith: entry.key);

      final report = await subject(callable).reprint(
        session: _session(role: TenantRole.manager),
        sale: _sale(),
      );

      expect(
        report.outcome,
        TenantReceiptReprintOutcome.refused,
        reason: entry.key,
      );
      expect(report.reasonCode, entry.value, reason: entry.key);
      expect(transport.sends, isEmpty, reason: entry.key);
      expect(queue.read(_receipt()), isNull, reason: entry.key);
    }
  });

  test('a device with no connection records nothing and says so', () async {
    final callable = _Callable(throwPlain: true);

    final report = await subject(callable).reprint(
      session: _session(role: TenantRole.manager),
      sale: _sale(),
    );

    expect(report.outcome, TenantReceiptReprintOutcome.refused);
    expect(report.reasonCode, TenantReceiptReprintCode.unavailable);
    expect(transport.sends, isEmpty);
  });

  test('a business with no printer is refused, and records nothing', () async {
    final callable = _Callable();

    final report = await subject(
      callable,
      printer: const TenantConfiguredPrinter.absent(),
    ).reprint(session: _session(role: TenantRole.owner), sale: _sale());

    expect(report.outcome, TenantReceiptReprintOutcome.refused);
    expect(report.reasonCode, PrinterTransportCode.notConfigured);
    expect(callable.payloads, isEmpty);
  });

  test('a recorded reprint the printer would not take is queued, not lost', () async {
    transport.failWith = PrinterTransportCode.unreachable;
    final callable = _Callable();

    final report = await subject(callable).reprint(
      session: _session(role: TenantRole.manager),
      sale: _sale(),
    );

    // The audit line exists and the bytes are durable. No paper, and the
    // sentence must not claim otherwise.
    expect(report.outcome, TenantReceiptReprintOutcome.queued);
    expect(report.reasonCode, PrinterTransportCode.unreachable);
    expect(callable.payloads, hasLength(1));
    expect(queue.read(_receipt())!.state, PrintJobState.needsAttention);
  });
}

TenantSession _session({required TenantRole role}) =>
    TenantSession.active(uid: 'user-a', tenantId: 'tenant-a', role: role);

String _receipt() => formatCheckoutReceiptNumber(
  deviceId: _deviceId,
  businessDate: _businessDate,
  sequence: 42,
);

TenantSale _sale({String tenantId = 'tenant-a'}) => TenantSale.fromDocument(
  path: 'tenants/$tenantId/sales/co-1',
  data: <String, Object?>{
    'checkoutId': 'co-1',
    'tenantId': tenantId,
    'soldById': 'user-a',
    'payloadHash': _payloadHash,
    'payloadSchemaVersion': 2,
    'tender': 'cash',
    'currency': 'KES',
    'businessDate': _businessDate,
    'shiftId': 'shift-a',
    'deviceId': _deviceId,
    'receiptNumber': _receipt(),
    'receiptSequence': 42,
    'items': <Object?>[
      <String, Object?>{
        'productId': 'product-1',
        'name': 'Tusker',
        'quantity': 2,
        'unitPriceMinor': 500,
        'lineTotalMinor': 1000,
      },
    ],
    'subtotalMinor': 1000,
    'subtotal': 10.0,
    'discountMinor': 0,
    'discount': 0.0,
    'totalMinor': 1000,
    'total': 10.0,
    'createdAt': Timestamp.fromDate(DateTime.utc(2026, 7, 29, 9)),
  },
);

TenantConfiguredPrinter _printer() => TenantConfiguredPrinter.configured(
  TenantPrinterConfiguration(
    transport: PrinterTransportKind.directTcp,
    endpoint: PrinterEndpoint(host: '192.168.1.50', port: 9100),
    paperWidth: PrinterPaperWidth.columns32,
    hasCutter: true,
  ),
);

/// Records every payload the audit callable was handed, and answers as told.
final class _Callable implements RecordReceiptReprintCallable {
  _Callable({this.failWith, this.throwPlain = false});

  final String? failWith;

  /// Anything that is not a `FirebaseFunctionsException` - a socket giving up
  /// before the call was made.
  final bool throwPlain;
  final List<Map<String, Object?>> payloads = <Map<String, Object?>>[];

  @override
  Future<Object?> call(Map<String, Object?> payload) async {
    if (throwPlain) throw const SocketException('no route to host');
    if (failWith case final code?) {
      throw FirebaseFunctionsException(code: code, message: code);
    }
    payloads.add(payload);
    return <String, Object?>{
      'auditId': 'rp_1',
      'saleId': payload['saleId'],
      'receiptNumber': payload['receiptNumber'],
    };
  }
}

final class _FakeTransport implements PrinterTransport {
  String? failWith;
  final List<List<int>> sends = <List<int>>[];

  @override
  PrinterTransportCapability get capability => const PrinterTransportCapability(
    kind: PrinterTransportKind.directTcp,
    endpointIsPrinter: true,
    label: 'Fake',
  );

  @override
  Future<void> probe(PrinterEndpoint endpoint) async {}

  @override
  Future<void> send(PrinterEndpoint endpoint, List<int> bytes) async {
    if (failWith case final code?) throw PrinterTransportException(code);
    sends.add(List<int>.unmodifiable(bytes));
  }

  @override
  Future<void> dispose() async {}
}
