/// The content model's invariants, which are the report's honesty rules.
///
/// Two of the three things this feature promises are kept by types rather than
/// by discipline, and this is where that is checked: a chart cannot exist
/// without the figures that make it readable without colour, and a value that
/// was never measured cannot be written in a form anything will add up.
library;

import 'package:flutter_application_1/reports/report_document.dart';
import 'package:flutter_application_1/reports/report_table.dart';
import 'package:flutter_application_1/reports/report_visual.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/documents.dart';

TenantReportDatum _datum(String label, double value, {double? was}) =>
    TenantReportDatum(
      label: label,
      value: value,
      formatted: value.toStringAsFixed(2),
      comparison: was,
      comparisonFormatted: was?.toStringAsFixed(2),
    );

void main() {
  group('a colour never carries a fact alone', () {
    test('a chart cannot be built with no rows', () {
      expect(
        () => TenantReportVisual(
          kind: TenantReportVisualKind.ranked,
          caption: 'Nothing',
          valueAxisLabel: 'Takings',
          data: const <TenantReportDatum>[],
        ),
        throwsArgumentError,
        reason:
            'Hard rule 4 is kept by the constructor rather than by each of '
            'eight reports remembering it.',
      );
    });

    test('a comparison must arrive with the text that prints it', () {
      expect(
        () => TenantReportDatum(
          label: 'Mon',
          value: 10,
          formatted: '10.00',
          comparison: 8,
        ),
        throwsA(isA<AssertionError>()),
        reason:
            'A plotted comparison with no printed figure beside it is a bar '
            'nobody can read a number off.',
      );
    });

    test('a section that draws nothing and lists nothing is refused', () {
      expect(
        () => TenantReportSection(heading: 'Empty', summary: 'Nothing here.'),
        throwsArgumentError,
        reason: 'That is a heading, not a section.',
      );
    });

    test('a table row must match its columns', () {
      expect(
        () => TenantReportTable(
          columns: const <TenantReportColumn>[
            TenantReportColumn(
              heading: 'Name',
              kind: TenantReportColumnKind.text,
            ),
            TenantReportColumn(
              heading: 'Total',
              kind: TenantReportColumnKind.money,
            ),
          ],
          rows: <List<TenantReportCell>>[
            <TenantReportCell>[const TenantReportTextCell('short')],
          ],
        ),
        throwsArgumentError,
        reason: 'A ragged table silently shifts figures under wrong headings.',
      );
    });
  });

  group('a value that was never measured', () {
    test('never prints as a dash, a blank, or a nought', () {
      const cell = TenantReportAbsentCell('closed without a count');

      expect(
        cell.text,
        isNotEmpty,
        reason: 'A blank cell gets summed as nought by whoever opens the file.',
      );
      expect(
        cell.text,
        isNot('-'),
        reason:
            'Accounting convention already reads a dash in a money column as '
            'nought, which is the one thing this cell denies.',
      );
      expect(
        cell.text,
        isNot('0'),
        reason: 'Printing nought invents a till that balanced.',
      );
      expect(
        double.tryParse(cell.text),
        isNull,
        reason:
            'Whatever it says must not parse as a number, or a spreadsheet '
            'will coerce it into one.',
      );
    });

    test('it is drawable by the fallback faces', () {
      // The bug this guards: an em dash is unambiguous to a reader and cannot
      // be drawn by the `pdf` package's built-in faces at all, so it rendered
      // as nothing - and nothing is exactly what this cell must never be.
      // Those faces are what a device falls back to when an asset read fails,
      // so this is a production path, not a test one.
      expect(
        TenantReportAbsentCell.notRecorded.codeUnits.every((c) => c < 128),
        isTrue,
        reason:
            'The built-in PDF faces have no Unicode support. Anything above '
            'ASCII silently disappears from the page.',
      );
    });

    test('a value withheld for a reason other than ignorance says which', () {
      // "Not recorded" against a voided expense would be false: the amount is
      // perfectly well known, it just must never be totalled, because that
      // money did not leave the business. Two different facts, two words.
      const voided = TenantReportAbsentCell(
        'voided after it was entered',
        shown: TenantReportAbsentCell.voided,
      );

      expect(voided.text, 'voided');
      expect(
        voided.text,
        isNot(TenantReportAbsentCell.notRecorded),
        reason: 'A voided amount is known. An unevidenced one is not.',
      );
      expect(
        double.tryParse(voided.text),
        isNull,
        reason: 'It still must not coerce to a number.',
      );
    });

    test('it carries why, not just that', () {
      const cell = TenantReportAbsentCell('closed without a count');

      expect(
        cell.reason,
        'closed without a count',
        reason:
            'A reader should not have to guess whether the till was empty or '
            'the shift was never counted.',
      );
    });

    test('a table counts its absences so a section can own up to them', () {
      final table = TenantReportTable(
        columns: const <TenantReportColumn>[
          TenantReportColumn(
            heading: 'Shift',
            kind: TenantReportColumnKind.text,
          ),
          TenantReportColumn(
            heading: 'Variance',
            kind: TenantReportColumnKind.money,
          ),
        ],
        rows: <List<TenantReportCell>>[
          <TenantReportCell>[
            const TenantReportTextCell('Mon'),
            const TenantReportMoneyCell(minor: 4500, formatted: '45.00'),
          ],
          <TenantReportCell>[
            const TenantReportTextCell('Tue'),
            const TenantReportAbsentCell('closed without a count'),
          ],
          <TenantReportCell>[
            const TenantReportTextCell('Wed'),
            const TenantReportAbsentCell('closed without a count'),
          ],
        ],
      );

      expect(
        table.absences,
        2,
        reason:
            'So no section can quietly fill with dashes while its summary '
            'talks about averages.',
      );
    });

    test('money keeps its minor units all the way to the cell', () {
      const cell = TenantReportMoneyCell(minor: 486350, formatted: 'KES 4863.50');

      expect(
        cell.major,
        4863.50,
        reason: 'The workbook writes a number, so nothing rounds on the way.',
      );
      expect(
        cell.text,
        'KES 4863.50',
        reason: 'And the page prints what the analysis already formatted.',
      );
    });
  });

  group('the analytic arithmetic a chart carries', () {
    test('concentration is the largest share of the whole', () {
      final visual = TenantReportVisual(
        kind: TenantReportVisualKind.composition,
        caption: 'Share',
        valueAxisLabel: 'Takings',
        data: <TenantReportDatum>[
          _datum('Mpesa', 60),
          _datum('Cash', 30),
          _datum('Card', 10),
        ],
      );

      expect(visual.total, 100);
      expect(visual.concentration, 0.6);
    });

    test('a period with nothing in it has no concentration to quote', () {
      final visual = TenantReportVisual(
        kind: TenantReportVisualKind.composition,
        caption: 'Share',
        valueAxisLabel: 'Spend',
        data: <TenantReportDatum>[_datum('Rent', 0), _datum('Wages', 0)],
      );

      expect(
        visual.concentration,
        isNull,
        reason:
            'A share of nothing is a division by zero, not a finding. The '
            'section must say nothing was spent instead.',
      );
    });

    test('head count answers how few take most of the whole', () {
      final visual = TenantReportVisual(
        kind: TenantReportVisualKind.ranked,
        caption: 'By person',
        valueAxisLabel: 'Takings',
        data: <TenantReportDatum>[
          _datum('Grace', 50),
          _datum('Peter', 30),
          _datum('Amina', 10),
          _datum('Joseph', 6),
          _datum('Mary', 4),
        ],
      );

      expect(
        visual.headCountFor(0.5),
        1,
        reason: 'Grace alone is half the takings.',
      );
      expect(
        visual.headCountFor(0.75),
        2,
        reason:
            'Two of five took 80%. "2 of 9 staff took 58% of takings" says '
            'more than any single share does, and this is that arithmetic.',
      );
    });

    test('a change against nothing is not a percentage', () {
      final rose = _datum('Sat', 100, was: 80);
      final fromNothing = _datum('Sun', 100, was: 0);

      expect(rose.change, closeTo(0.25, 0.0001));
      expect(rose.changeLabel, 'up 25.0%');
      expect(
        fromNothing.change,
        isNull,
        reason:
            'A rise from nothing is not a percentage, and printing one would '
            'be a division nobody can check.',
      );
    });

    test('a fall reads as a fall', () {
      expect(_datum('Tue', 60, was: 80).changeLabel, 'down 25.0%');
    });

    test('a distance from a reference line is not a change over time', () {
      // The bug this guards: the staff report draws each person's average sale
      // against the shop's median. The arithmetic is identical to a
      // period-on-period change, and the sentence is not - "down 25%" claims
      // her takings fell, when all it says is she sits under the middle.
      final person = _datum('Grace', 613, was: 820);

      expect(person.changeLabel, 'down 25.2%');
      expect(person.differenceLabel, '25.2% below');
      expect(
        person.labelFor(TenantReportComparisonKind.reference),
        '25.2% below',
        reason:
            'Up and down are claims about time. A median is a line, not a '
            'past, and a report must not invent a trend out of a comparison.',
      );
      expect(
        person.labelFor(TenantReportComparisonKind.priorPeriod),
        'down 25.2%',
      );
    });

    test('sitting exactly on the reference reads as level, not unchanged', () {
      final person = _datum('Peter', 820, was: 820);

      expect(person.changeLabel, 'unchanged');
      expect(
        person.differenceLabel,
        'level with it',
        reason:
            '"Unchanged" would say his average held steady, which is a fact '
            'about last month that this chart does not carry.',
      );
    });

    test('peak and trough reach across both series', () {
      final visual = TenantReportVisual(
        kind: TenantReportVisualKind.comparison,
        caption: 'Against last',
        valueAxisLabel: 'Takings',
        data: <TenantReportDatum>[_datum('Mon', 40, was: 90)],
      );

      expect(
        visual.peak,
        90,
        reason:
            'An axis drawn to this period alone would run the comparison bar '
            'off the top of the chart.',
      );
    });
  });

  group('the document assembles what both renderers must agree on', () {
    test('a sheet name is cut to what Excel will accept', () {
      final section = TenantReportSection(
        heading: 'A section heading far longer than a worksheet tab allows',
        summary: 'x',
        table: TenantReportTable(
          columns: const <TenantReportColumn>[
            TenantReportColumn(
              heading: 'A',
              kind: TenantReportColumnKind.text,
            ),
          ],
          rows: <List<TenantReportCell>>[
            <TenantReportCell>[const TenantReportTextCell('a')],
          ],
        ),
      );

      expect(
        section.sheetName.length,
        lessThanOrEqualTo(31),
        reason: 'Excel refuses a longer tab name outright.',
      );
    });

    test('characters Excel forbids in a tab name are dropped', () {
      final section = TenantReportSection(
        heading: 'Profit / loss [Q3]',
        summary: 'x',
        table: TenantReportTable(
          columns: const <TenantReportColumn>[
            TenantReportColumn(
              heading: 'A',
              kind: TenantReportColumnKind.text,
            ),
          ],
          rows: <List<TenantReportCell>>[
            <TenantReportCell>[const TenantReportTextCell('a')],
          ],
        ),
      );

      for (final forbidden in <String>['/', r'\', '[', ']', '*', '?', ':']) {
        expect(
          section.sheetName.contains(forbidden),
          isFalse,
          reason: '$forbidden makes the workbook unopenable.',
        );
      }
    });

    test('the two formats name the same file with different extensions', () {
      final document = fixtureDocument();

      expect(
        document.filename(TenantReportFormat.pdf),
        'mama-njeri-stores-sales-2026-09-01-to-2026-09-22.pdf',
      );
      expect(
        document.filename(TenantReportFormat.excel),
        'mama-njeri-stores-sales-2026-09-01-to-2026-09-22.xlsx',
      );
    });
  });
}
