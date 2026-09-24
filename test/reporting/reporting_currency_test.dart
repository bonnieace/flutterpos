import 'package:flutter_application_1/reporting/reporting.dart';
import 'package:flutter_application_1/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a published code labels every figure', () async {
    final currency = await _read(_Reader(<String, Object?>{'currency': 'KES'}));

    expect(currency.isKnown, isTrue);
    expect(currency.code, 'KES');
    expect(currency.format(1250.5), 'KES 1250.50');
    expect(currency.format(0), 'KES 0');
  });

  test('an absent configuration leaves a bare figure', () async {
    // A business that has published nothing cannot use the till either, so an
    // unlabelled figure here always describes an unconfigured business.
    final currency = await _read(_Reader(null));

    expect(currency.isKnown, isFalse);
    expect(currency.code, isNull);
    expect(currency.format(1250.5), '1250.50');
  });

  test('an unusable code is dropped rather than shown', () async {
    for (final value in <Object?>['shillings', 'kes', '', 7, null]) {
      final currency = await _read(
        _Reader(<String, Object?>{'currency': value}),
      );

      expect(currency.isKnown, isFalse, reason: '$value');
      expect(currency.format(1250.5), '1250.50', reason: '$value');
    }
  });

  test('an unreadable configuration loses the label, not the figure', () async {
    final currency = await _read(_Reader.failing(StateError('offline')));

    expect(currency.isKnown, isFalse);
    expect(currency.format(1250.5), '1250.50');
  });

  test('a reader answering outside the business is not degraded', () async {
    // A broken tenant boundary is not a missing label, and must reach the
    // route rather than be swallowed into an unlabelled figure.
    await expectLater(
      _read(_Reader.crossTenant()),
      throwsA(isA<TenantScopeViolation>()),
    );
  });

  test('the notice explains the missing code without naming one', () {
    expect(TenantReportingCurrency.unknownNotice, contains('no currency'));
    expect(TenantReportingCurrency.unknown.isKnown, isFalse);
  });

  test('a whole amount has no decimals, and cents always have two', () {
    // Since 2026-09-23: `.00` on a whole amount is noise, but `7.5` would read
    // as a different number from `7.50`.
    const currency = TenantReportingCurrency.unknown;

    expect(currency.format(7), '7');
    expect(currency.format(7.5), '7.50');
    expect(currency.format(7.004), '7');
    expect(currency.format(7.006), '7.01');
    expect(currency.format(-3.05), '-3.05');
  });
}

Future<TenantReportingCurrency> _read(_Reader reader) =>
    TenantReportingCurrency.read(
      session: TenantSession.active(
        uid: 'manager-a',
        tenantId: 'tenant-a',
        role: TenantRole.manager,
      ),
      reader: reader,
    );

final class _Reader implements TenantDocumentReader {
  _Reader(this._data) : _error = null, _crossTenant = false;
  _Reader.failing(Object error)
    : _data = null,
      _error = error,
      _crossTenant = false;
  _Reader.crossTenant()
    : _data = const <String, Object?>{'currency': 'KES'},
      _error = null,
      _crossTenant = true;

  final Map<String, Object?>? _data;
  final Object? _error;
  final bool _crossTenant;

  @override
  Future<TenantDocumentSnapshot?> getDocument(String path) {
    final error = _error;
    if (error != null) return Future<TenantDocumentSnapshot?>.error(error);
    final data = _data;
    if (data == null) return Future<TenantDocumentSnapshot?>.value();
    return Future<TenantDocumentSnapshot?>.value(
      TenantDocumentSnapshot(
        path: _crossTenant ? 'tenants/tenant-z/configuration/checkout' : path,
        data: data,
      ),
    );
  }
}
