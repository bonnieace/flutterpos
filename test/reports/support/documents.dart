/// Fixture documents, built the way an analysis would build one.
///
/// Shared so the PDF test, the workbook test and the sample-rendering tool all
/// draw the same thing. A renderer bug that only shows up on one fixture is a
/// renderer bug nobody finds.
library;

import 'dart:typed_data';

import 'package:uzapay_pos/reporting/reporting_currency.dart';
import 'package:uzapay_pos/reports/report_document.dart';
import 'package:uzapay_pos/reports/report_identity.dart';
import 'package:uzapay_pos/reports/report_period.dart';
import 'package:uzapay_pos/reports/report_scope.dart';
import 'package:uzapay_pos/reports/report_table.dart';
import 'package:uzapay_pos/reports/report_visual.dart';
import 'package:uzapay_pos/tenancy/tenant_types.dart';

/// The instant every fixture is generated at, so nothing drifts with the clock.
DateTime fixtureClock() => DateTime.utc(2026, 9, 22, 11, 30);

TenantReportIdentity fixtureIdentity({
  String businessName = 'Mama Njeri Stores',
  String? slogan = 'Fresh every morning',
  TenantReportingCurrency? currency,
  Uint8List? logo,
}) => TenantReportIdentity(
  businessName: businessName,
  slogan: slogan,
  logo: logo,
  currency: currency ?? TenantReportingCurrency.forTesting('KES'),
  generatedAt: fixtureClock(),
  generatedByName: 'Grace Wanjiru',
  generatedByRole: TenantRole.owner,
);

/// A period of three weeks to 22 September.
TenantReportPeriod fixturePeriod() =>
    TenantReportPeriod(startDate: '2026-09-01', endDate: '2026-09-22');

/// A document exercising all five visual kinds and both table shapes.
///
/// Deliberately awkward: it carries an absent cell, a caveat, a negative
/// variance and a category with nothing in it, because those are the cases a
/// renderer gets wrong and a tidy fixture would never show.
TenantReportDocument fixtureDocument({
  TenantReportIdentity? identity,
  TenantReportScope? scope,
}) {
  final period = fixturePeriod();
  final who = identity ?? fixtureIdentity();

  return TenantReportDocument(
    kind: TenantReportKind.sales,
    identity: who,
    scope:
        scope ??
        TenantReportScope(
          period: period,
          documentsRead: 412,
          caveats: <TenantReportCaveat>[
            TenantReportCaveat.missingCost(lines: 14, of: 286),
          ],
        ),
    subtitle:
        'Takings, margin and what moved, against the three weeks before it.',
    headline: <TenantReportFigure>[
      TenantReportFigure(
        label: 'Takings',
        value: who.money(486350),
        comparison: who.money(431200),
        amount: 4863.50,
        amountComparison: 4312.00,
      ),
      TenantReportFigure(
        label: 'Gross margin',
        value: who.money(151980),
        comparison: who.money(139400),
        amount: 1519.80,
        amountComparison: 1394.00,
        note: 'Over 272 of 286 lines. The rest record no cost.',
      ),
      const TenantReportFigure(
        label: 'Transactions',
        value: '286',
        amount: 286,
        amountKind: TenantReportColumnKind.count,
      ),
    ],
    sections: <TenantReportSection>[
      TenantReportSection(
        heading: 'Takings by day',
        summary:
            'Takings rose 12.8% on the three weeks before. Every Monday of the '
            'period was below its own week average, and the 14th was the '
            'weakest trading day in six weeks.',
        visual: TenantReportVisual(
          kind: TenantReportVisualKind.trend,
          caption: 'Daily takings across the period',
          valueAxisLabel: 'Takings',
          comparisonLabel: 'The period before',
          data: <TenantReportDatum>[
            for (var i = 0; i < 22; i++)
              TenantReportDatum(
                label: '${i + 1} Sep',
                value: 14000 + (i % 7) * 3200 + (i * 210),
                formatted: who.money(
                  ((14000 + (i % 7) * 3200 + (i * 210)) * 100).round(),
                ),
                comparison: 13000 + (i % 7) * 2600,
                comparisonFormatted: who.money(
                  ((13000 + (i % 7) * 2600) * 100).round(),
                ),
              ),
          ],
        ),
      ),
      TenantReportSection(
        heading: 'By weekday',
        summary:
            'Saturday carries 23% of the week. Tuesday is the quietest day and '
            'has been for the whole period.',
        visual: TenantReportVisual(
          kind: TenantReportVisualKind.comparison,
          caption: 'This period against the one before it',
          valueAxisLabel: 'Takings',
          comparisonLabel: 'The period before',
          data: <TenantReportDatum>[
            for (final (index, day) in <String>[
              'Mon',
              'Tue',
              'Wed',
              'Thu',
              'Fri',
              'Sat',
              'Sun',
            ].indexed)
              TenantReportDatum(
                label: day,
                value: 52000 + index * 8400,
                formatted: who.money((52000 + index * 8400) * 100),
                comparison: 49000 + index * 7100,
                comparisonFormatted: who.money((49000 + index * 7100) * 100),
                emphasis: day == 'Sat',
              ),
          ],
        ),
      ),
      TenantReportSection(
        heading: 'What earned the most',
        summary:
            'Ranked by margin rather than by takings. Maize flour is the '
            'best seller and the fourth best earner; cooking oil sells a third '
            'as often and earns more.',
        visual: TenantReportVisual(
          kind: TenantReportVisualKind.ranked,
          caption: 'Top products by gross margin',
          valueAxisLabel: 'Margin',
          data: <TenantReportDatum>[
            for (final (name, margin) in <(String, int)>[
              ('Cooking oil 1L', 28400),
              ('Sugar 2kg', 24100),
              ('Rice 5kg', 19800),
              ('Maize flour 2kg', 18200),
              ('Milk 500ml', 12600),
              ('Bread white', 9400),
              ('Soap bar', 6100),
            ])
              TenantReportDatum(
                label: name,
                value: margin.toDouble(),
                formatted: who.money(margin * 100),
                emphasis: name == 'Cooking oil 1L',
              ),
          ],
        ),
      ),
      TenantReportSection(
        heading: 'How it was paid for',
        summary:
            'Mpesa passed cash this period for the first time, at 54% of '
            'takings against 41% in the three weeks before.',
        visual: TenantReportVisual(
          kind: TenantReportVisualKind.composition,
          caption: 'Share of takings by tender',
          valueAxisLabel: 'Takings',
          data: <TenantReportDatum>[
            TenantReportDatum(
              label: 'Mpesa',
              value: 262600,
              formatted: who.money(26260000),
            ),
            TenantReportDatum(
              label: 'Cash',
              value: 189200,
              formatted: who.money(18920000),
            ),
            TenantReportDatum(
              label: 'Card',
              value: 34550,
              formatted: who.money(3455000),
            ),
            // A tender nothing was taken in. It must still be listed: a
            // category with nothing in it is a fact, and dropping it would
            // make the ring claim there were only three ways to pay.
            TenantReportDatum(
              label: 'Not recorded',
              value: 0,
              formatted: who.money(0),
            ),
          ],
        ),
      ),
      TenantReportSection(
        heading: 'Till variance by shift',
        summary:
            'Four shifts closed over and two short. One closed with no count '
            'at all and is not in the arithmetic below.',
        visual: TenantReportVisual(
          kind: TenantReportVisualKind.variance,
          caption: 'Declared against expected, by shift',
          valueAxisLabel: 'Variance',
          data: <TenantReportDatum>[
            for (final (label, minor) in <(String, int)>[
              ('Mon morning', 45000),
              ('Mon evening', -12000),
              ('Tue morning', 8000),
              ('Wed evening', -31000),
              ('Thu morning', 15000),
              ('Fri evening', 2000),
            ])
              TenantReportDatum(
                label: label,
                value: minor / 100,
                formatted: who.signedMoney(minor),
              ),
          ],
        ),
        table: TenantReportTable(
          columns: const <TenantReportColumn>[
            TenantReportColumn(
              heading: 'Shift',
              kind: TenantReportColumnKind.text,
            ),
            TenantReportColumn(
              heading: 'Cashier',
              kind: TenantReportColumnKind.text,
            ),
            TenantReportColumn(
              heading: 'Takings',
              kind: TenantReportColumnKind.money,
            ),
            TenantReportColumn(
              heading: 'Variance',
              kind: TenantReportColumnKind.money,
            ),
          ],
          rows: <List<TenantReportCell>>[
            <TenantReportCell>[
              const TenantReportTextCell('Mon morning'),
              const TenantReportTextCell('Grace'),
              TenantReportMoneyCell(minor: 84500, formatted: who.money(84500)),
              TenantReportMoneyCell(minor: 45000, formatted: who.money(45000)),
            ],
            <TenantReportCell>[
              const TenantReportTextCell('Mon evening'),
              const TenantReportTextCell('Peter'),
              TenantReportMoneyCell(minor: 61200, formatted: who.money(61200)),
              TenantReportMoneyCell(
                minor: -12000,
                formatted: who.signedMoney(-12000),
              ),
            ],
            // The case the whole cell hierarchy exists for. This shift closed
            // with no evidence, so its variance is unknown - not nought.
            <TenantReportCell>[
              const TenantReportTextCell('Tue evening'),
              const TenantReportTextCell('Grace'),
              TenantReportMoneyCell(minor: 52300, formatted: who.money(52300)),
              const TenantReportAbsentCell('closed without a count'),
            ],
          ],
        ),
        notes: const <String>[
          'A shift that closed without a count has no variance to report. It '
          'is shown as not recorded and left out of the totals, because '
          'counting it as nought would invent a till that balanced.',
        ],
      ),
    ],
  );
}
