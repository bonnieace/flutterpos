import 'package:uzapay_pos/checkout/checkout.dart';
import 'package:uzapay_pos/tenancy/tenant_types.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _document({
  Object? transport = 'direct_tcp',
  Object? host = '192.168.1.50',
  Object? port = 9100,
  Object? paperWidth = 'columns_32',
  Object? hasCutter = true,
  Object? bridgeToken,
}) => <String, Object?>{
  'transport': transport,
  'host': host,
  'port': port,
  'paperWidth': paperWidth,
  'hasCutter': hasCutter,
  if (bridgeToken != null) 'bridgeToken': bridgeToken,
};

void main() {
  group('the strict read model', () {
    test('parses the canonical document', () {
      final configuration = TenantPrinterConfiguration.fromMap(_document());

      expect(configuration.transport, PrinterTransportKind.directTcp);
      expect(configuration.endpoint.host, '192.168.1.50');
      expect(configuration.endpoint.port, 9100);
      expect(configuration.paperWidth, PrinterPaperWidth.columns32);
      expect(configuration.paperWidth.columns, 32);
      expect(configuration.hasCutter, isTrue);
      expect(configuration.bridgeToken, isNull);
    });

    test('ignores unknown fields so a later setting cannot break printing', () {
      // The same asymmetry `TenantCheckoutConfiguration` uses: every field this
      // slice depends on must be exactly valid, and anything else is not its
      // business.
      final configuration = TenantPrinterConfiguration.fromMap(<String, Object?>{
        ..._document(),
        'logoUrl': 'https://example.test/logo.png',
        'footerLines': <String>['Thank you'],
      });

      expect(configuration.endpoint.host, '192.168.1.50');
    });

    test('refuses every field this slice depends on being wrong', () {
      for (final broken in <Map<String, Object?>>[
        _document(transport: 'bluetooth'),
        _document(transport: null),
        _document(host: 42),
        _document(port: '9100'),
        _document(paperWidth: 'columns_64'),
        _document(paperWidth: null),
        _document(hasCutter: 'yes'),
        _document(bridgeToken: 7),
      ]) {
        expect(
          () => TenantPrinterConfiguration.fromMap(broken),
          throwsA(isA<FormatException>()),
          reason: broken.toString(),
        );
      }
    });

    test('an address the transport would refuse fails here, not at the socket', () {
      // `PrinterEndpoint`'s refusals become the document's refusals, so a config
      // carrying a URL fails closed on read rather than on the first sale.
      expect(
        () => TenantPrinterConfiguration.fromMap(_document(host: 'http://p')),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => TenantPrinterConfiguration.fromMap(_document(port: 0)),
        throwsA(isA<FormatException>()),
      );
    });

    test('round-trips through the offline cache projection', () {
      final configuration = TenantPrinterConfiguration.fromMap(
        _document(bridgeToken: 'shared-token'),
      );

      final again = TenantPrinterConfiguration.fromMap(
        configuration.toCacheEntry(),
      );

      expect(again, configuration);
      expect(again.bridgeToken, 'shared-token');
    });
  });

  group('fail closed', () {
    test('an absent document refuses rather than defaulting', () {
      // §2: the borrowed repository does `catch (_)` and falls back to a
      // built-in `192.168.100.100`, which on a customer LAN is **someone
      // else's device**. There is no default address here, ever.
      const absent = TenantConfiguredPrinter.absent();

      expect(absent.canPrint, isFalse);
      expect(absent.configuration, isNull);
      expect(
        absent.require,
        throwsA(
          const PrinterTransportException(PrinterTransportCode.notConfigured),
        ),
      );
    });

    test('a malformed document is a state, not a failure', () {
      // The strict read model refuses it and printing therefore refuses to
      // run - so the one person who can correct it must be able to see it and
      // overwrite it, not be shown the cashier's refusal.
      const malformed = TenantConfiguredPrinter.malformed();

      expect(malformed.state, TenantPrinterConfigurationState.malformed);
      expect(malformed.canPrint, isFalse);
      expect(
        malformed.require,
        throwsA(
          const PrinterTransportException(PrinterTransportCode.notConfigured),
        ),
      );
    });

    test('a configured printer hands over its own configuration', () {
      final configuration = TenantPrinterConfiguration.fromMap(_document());
      final configured = TenantConfiguredPrinter.configured(configuration);

      expect(configured.canPrint, isTrue);
      expect(configured.require(), configuration);
    });
  });

  group('the document it lives in', () {
    test('is printer, beside checkout, under the same existing rule', () {
      // `firestore.rules` already carries `match /configuration/{documentId}`
      // with read for active staff and write for owner and admin, so this
      // document needed no rules change - which was checked rather than
      // assumed.
      expect(TenantPrinterConfigurationRepository.documentId, 'printer');
      expect(
        TenantPrinterConfigurationRepository.writeRoles,
        <TenantRole>[TenantRole.owner, TenantRole.admin],
      );
    });

    test('the two roll widths are the two layouts a formatter must handle', () {
      expect(PrinterPaperWidth.columns32.columns, 32);
      expect(PrinterPaperWidth.columns48.columns, 48);
      expect(PrinterPaperWidth.tryParse('columns_48'), PrinterPaperWidth.columns48);
      expect(PrinterPaperWidth.tryParse('columns_58mm'), isNull);
      expect(PrinterPaperWidth.tryParse(58), isNull);
    });
  });
}
