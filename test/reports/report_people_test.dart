/// A report names the people it ranks, and says so when it cannot.
///
/// **The defect this covers shipped.** Four reports grouped their figures by
/// UID and printed the UID, so 'Who recorded them' read as a column of
/// forty-character identifiers on a document meant to be sent to somebody.
/// `TenantReportIdentity.generatedByName` had already written down the rule -
/// "printing the uid would be worse than printing nothing, it identifies
/// nobody a reader knows" - and four tables broke it.
///
/// So these assert the two halves: that a resolved name is what prints, and
/// that an unresolved one degrades to the identifier *and* says why, rather
/// than leaving a reader to guess what the string is.
library;

import 'package:uzapay_pos/reports/report_people.dart';
import 'package:uzapay_pos/reports/report_scope.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('labelling', () {
    test('prints the display name where one was resolved', () {
      const people = TenantReportPeople(<String, String>{
        'cashier-a': 'Amina Juma',
      });

      expect(
        people.label('cashier-a'),
        'Amina Juma',
        reason: 'The name alone, because the UID beside it on a printed row is '
            'clutter to every reader who is not this app.',
      );
    });

    test('falls back to the identifier rather than to nothing', () {
      const people = TenantReportPeople(<String, String>{});

      expect(
        people.label('cashier-b'),
        'cashier-b',
        reason:
            'An empty cell would merge two people into one unreadable row. '
            'The identifier is at least an identity, and it is what the '
            'screens already show.',
      );
    });

    test('never invents a name for an unknown UID', () {
      const people = TenantReportPeople(<String, String>{
        'cashier-a': 'Amina Juma',
      });

      expect(people.isNamed('cashier-a'), isTrue);
      expect(
        people.isNamed('cashier-b'),
        isFalse,
        reason: 'A neighbouring row is not evidence about this one.',
      );
    });

    test('none() names nobody', () {
      const people = TenantReportPeople.none();

      expect(people.label('owner-a'), 'owner-a');
      expect(
        people.unnamed(<String>['owner-a', 'cashier-a']),
        2,
        reason: 'This is what a renderer test and an unreachable directory '
            'both get, and both must still render every row.',
      );
    });
  });

  group('the caveat', () {
    test('is absent where every person was named', () {
      const people = TenantReportPeople(<String, String>{
        'cashier-a': 'Amina Juma',
        'cashier-b': 'Peter Mwangi',
      });

      expect(
        people.caveat(
          <String>['cashier-a', 'cashier-b'],
          noun: 'recorded a return',
        ),
        isNull,
        reason:
            'A caveat on a report that withheld nothing teaches a reader to '
            'skip the ones that matter.',
      );
    });

    test('counts only the people the report actually lists', () {
      const people = TenantReportPeople(<String, String>{
        'cashier-a': 'Amina Juma',
      });

      final caveat = people.caveat(
        // 'cashier-c' recorded something but falls outside the listed rows.
        <String>['cashier-a', 'cashier-b'],
        noun: 'recorded a return',
      );

      expect(caveat, isNotNull);
      expect(
        caveat!.sentence,
        startsWith('1 of the people'),
        reason: 'The count must match the rows a reader can see, or it sends '
            'them looking for a row that is not on the page.',
      );
    });

    test('carries the role-restricted kind, not a generic one', () {
      const people = TenantReportPeople.none();

      expect(
        people.caveat(<String>['cashier-a'], noun: 'worked a shift')!.kind,
        TenantReportCaveatKind.roleRestricted,
        reason: 'This is a permission boundary, not a missing measurement, and '
            'the two are acted on differently: one is asking a colleague, the '
            'other is fixing the data.',
      );
    });

    test('says the figures are whole and only the label is not', () {
      const people = TenantReportPeople.none();

      final sentence = people
          .caveat(<String>['cashier-a', 'cashier-b'], noun: 'took a count')!
          .sentence;

      expect(
        sentence,
        contains('took a count'),
        reason: 'It names which table it is about.',
      );
      expect(
        sentence,
        contains('figures beside them are complete'),
        reason:
            'Without this a reader discounts the numbers too, which is the '
            'opposite of what the caveat is for.',
      );
    });

    test('counts to one', () {
      const people = TenantReportPeople.none();

      final sentence =
          people.caveat(<String>['cashier-a'], noun: 'made a change')!.sentence;

      expect(
        sentence,
        startsWith('1 of the people who made a change is shown'),
        reason: '"1 of the people ... are shown" undermines every figure '
            'printed beside it.',
      );
      expect(sentence, contains('beside it are complete'));
      expect(sentence, isNot(contains('them')));
    });
  });
}
