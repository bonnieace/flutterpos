import 'package:flutter_application_1/checkout/checkout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('checkout sync pass', () {
    test('recovers, submits, then recovers again before derived data', () async {
      final steps = <String>[];
      final pass = _pass(steps);

      await pass.run(refreshDerivedData: true);

      // The second recovery is the whole point. A commit leaves the record
      // awaiting confirmation, and only a confirmation read may conclude the
      // server holds the sale - so without it a till could not close its shift
      // until some later trigger settled the record.
      expect(steps, [
        'recover',
        'submit',
        'recover',
        'refreshCatalog',
        'evidenceChanged',
      ]);
    });

    test('a pass a sale asked for confirms it but re-reads no catalog', () async {
      final steps = <String>[];
      final pass = _pass(steps);

      await pass.run(refreshDerivedData: false);

      // Refreshing here would make a till pay for every product in the business
      // on every customer; confirming is not optional in the same way.
      expect(steps, ['recover', 'submit', 'recover', 'evidenceChanged']);
    });

    test('a failed submission still reports that evidence moved', () async {
      final steps = <String>[];
      final pass = CheckoutSyncPass(
        recover: () async => steps.add('recover'),
        submit: () async {
          steps.add('submit');
          throw StateError('the network went away mid-commit');
        },
        refreshCatalog: () async => steps.add('refreshCatalog'),
        reportEvidenceChanged: () => steps.add('evidenceChanged'),
      );

      // A part-way pass has still moved something, and a surface that stayed
      // stale because of the failure would hide exactly the sale needing
      // attention.
      await expectLater(
        pass.run(refreshDerivedData: true),
        throwsA(isA<StateError>()),
      );
      expect(steps, ['recover', 'submit', 'evidenceChanged']);
    });

    test('a failed first recovery never submits', () async {
      final steps = <String>[];
      final pass = CheckoutSyncPass(
        recover: () async {
          steps.add('recover');
          throw StateError('the confirmation read failed');
        },
        submit: () async => steps.add('submit'),
        refreshCatalog: () async => steps.add('refreshCatalog'),
        reportEvidenceChanged: () => steps.add('evidenceChanged'),
      );

      // Submitting before an uncertain prior attempt is settled is how a sale
      // gets committed twice, so the pass must stop here.
      await expectLater(
        pass.run(refreshDerivedData: true),
        throwsA(isA<StateError>()),
      );
      expect(steps, ['recover', 'evidenceChanged']);
    });

    test('a failed catalog refresh does not lose the evidence report', () async {
      final steps = <String>[];
      final pass = CheckoutSyncPass(
        recover: () async => steps.add('recover'),
        submit: () async => steps.add('submit'),
        refreshCatalog: () async {
          steps.add('refreshCatalog');
          throw StateError('the catalog page failed');
        },
        reportEvidenceChanged: () => steps.add('evidenceChanged'),
      );

      await expectLater(
        pass.run(refreshDerivedData: true),
        throwsA(isA<StateError>()),
      );
      // Derived data failing must not hide a sale that was settled first.
      expect(steps, [
        'recover',
        'submit',
        'recover',
        'refreshCatalog',
        'evidenceChanged',
      ]);
    });
  });
}

CheckoutSyncPass _pass(List<String> steps) => CheckoutSyncPass(
  recover: () async => steps.add('recover'),
  submit: () async => steps.add('submit'),
  refreshCatalog: () async => steps.add('refreshCatalog'),
  reportEvidenceChanged: () => steps.add('evidenceChanged'),
);
