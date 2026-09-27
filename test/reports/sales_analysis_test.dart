/// The arithmetic a sales report prints.
///
/// The case this file cares most about is the one the report exists for: that
/// the product which sells the most is not the product which earns the most,
/// and that a line with no recorded cost is left out of that ranking rather
/// than counted as pure profit.
library;

import 'package:uzapay_pos/checkout/checkout_tender.dart';
import 'package:uzapay_pos/reports/analysis/sales_analysis.dart';
import 'package:uzapay_pos/reports/report_period.dart';
import 'package:uzapay_pos/returns/return_offsets.dart';
import 'package:uzapay_pos/sales/sale_history.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sales.dart';

TenantReportPeriod _period() =>
    TenantReportPeriod(startDate: '2026-09-09', endDate: '2026-09-15');

TenantSalesAnalysis _analysis(
  List<TenantSale> sales, {
  List<TenantSale>? previous,
}) => TenantSalesAnalysis.from(
  period: _period(),
  sales: sales,
  previous: previous,
);

TenantSale _sale({
  required String id,
  required String soldById,
  required int unitPriceMinor,
}) => fixtureSale(
  id: id,
  businessDate: '2026-09-10',
  soldById: soldById,
  lines: <Map<String, Object?>>[
    saleLine(
      productId: 'p-1',
      name: 'Thing',
      quantity: 1,
      unitPriceMinor: unitPriceMinor,
    ),
  ],
);

void main() {
  test('partial returns net every sales measure and the comparison', () {
    final current = fixtureSale(
      id: 'co-current',
      businessDate: '2026-09-10',
      discountMinor: 2000,
      lines: <Map<String, Object?>>[
        saleLine(
          productId: 'p-1',
          name: 'Thing',
          quantity: 2,
          unitPriceMinor: 10000,
          unitCostMinor: 6000,
        ),
      ],
    );
    final prior = fixtureSale(
      id: 'co-prior',
      businessDate: '2026-09-03',
      lines: <Map<String, Object?>>[
        saleLine(
          productId: 'p-1',
          name: 'Thing',
          quantity: 2,
          unitPriceMinor: 10000,
          unitCostMinor: 6000,
        ),
      ],
    );
    final analysis = TenantSalesAnalysis.from(
      period: _period(),
      sales: <TenantSale>[current],
      previous: <TenantSale>[prior],
      returnOffsets: <String, TenantSaleReturnOffset>{
        current.id: describeReturnOffset(current, const {'p-1': 1}),
      },
      previousReturnOffsets: <String, TenantSaleReturnOffset>{
        prior.id: describeReturnOffset(prior, const {'p-1': 1}),
      },
    );

    expect(analysis.revenueMinor, 9000);
    expect(analysis.costMinor, 6000);
    expect(analysis.discountMinor, 1000);
    expect(analysis.transactions, 1);
    expect(analysis.itemsSold, 1);
    expect(analysis.items.single.revenueMinor, 9000);
    expect(analysis.items.single.quantity, 1);
    expect(analysis.tenders.single.minor, 9000);
    expect(analysis.dailyMinor['2026-09-10'], 9000);
    expect(analysis.previousRevenueMinor, 10000);
    expect(analysis.previousTransactions, 1);
  });

  test('fully returned sale leaves no transaction, cost, or product', () {
    final sale = _sale(
      id: 'co-full',
      soldById: 'user-a',
      unitPriceMinor: 10000,
    );
    final analysis = TenantSalesAnalysis.from(
      period: _period(),
      sales: <TenantSale>[sale],
      returnOffsets: <String, TenantSaleReturnOffset>{
        sale.id: describeReturnOffset(sale, const {'p-1': 1}),
      },
    );

    expect(analysis.revenueMinor, 0);
    expect(analysis.transactions, 0);
    expect(analysis.itemsSold, 0);
    expect(analysis.items, isEmpty);
    expect(analysis.tenders, isEmpty);
    expect(analysis.fullyReturnedSales, 1);
  });

  group('the best seller is not the best earner', () {
    test('margin ranks differently from takings', () {
      final analysis = _analysis(<TenantSale>[
        fixtureSale(
          id: 'co-1',
          businessDate: '2026-09-10',
          lines: <Map<String, Object?>>[
            // Moves a lot, earns little.
            saleLine(
              productId: 'p-flour',
              name: 'Maize flour',
              quantity: 40,
              unitPriceMinor: 18000,
              unitCostMinor: 16200,
            ),
            // Moves little, earns a lot.
            saleLine(
              productId: 'p-oil',
              name: 'Cooking oil',
              quantity: 12,
              unitPriceMinor: 42000,
              unitCostMinor: 29000,
            ),
          ],
        ),
      ]);

      expect(
        analysis.bestSeller?.name,
        'Maize flour',
        reason: 'It took the most, which is what the sales screen ranks by.',
      );
      expect(
        analysis.bestEarner?.name,
        'Cooking oil',
        reason:
            '40 x 1800 = 72,000 against 12 x 13,000 = 156,000. Nothing in the '
            'app shows this today, and it is the decision a shopkeeper can '
            'act on.',
      );
      expect(
        analysis.sellerEarnerDiffer,
        isTrue,
        reason:
            'The condition for printing the sentence is a field, so a '
            'renderer cannot forget to make the comparison.',
      );
    });

    test('a line with no recorded cost carries no margin at all', () {
      final analysis = _analysis(<TenantSale>[
        fixtureSale(
          id: 'co-1',
          businessDate: '2026-09-10',
          lines: <Map<String, Object?>>[
            saleLine(
              productId: 'p-soap',
              name: 'Soap',
              quantity: 10,
              unitPriceMinor: 9000,
            ),
          ],
        ),
      ]);

      final soap = analysis.items.single;

      expect(
        soap.marginMinor,
        isNull,
        reason:
            'An unknown margin is not a hundred per cent one. Treating it as '
            'pure profit would put the worst-kept records at the top of a '
            'list about profitability, which is exactly backwards.',
      );
      expect(
        analysis.byMargin,
        isEmpty,
        reason: 'So it is left out of the ranking rather than ranked first.',
      );
      expect(analysis.bestEarner, isNull);
      expect(
        analysis.sellerEarnerDiffer,
        isFalse,
        reason: 'With no earner there is no disagreement to claim.',
      );
    });

    test('costed and uncosted lines of the same product are counted', () {
      final analysis = _analysis(<TenantSale>[
        fixtureSale(
          id: 'co-1',
          businessDate: '2026-09-10',
          lines: <Map<String, Object?>>[
            saleLine(
              productId: 'p-rice',
              name: 'Rice',
              quantity: 2,
              unitPriceMinor: 30000,
              unitCostMinor: 22000,
            ),
          ],
        ),
        fixtureSale(
          id: 'co-2',
          businessDate: '2026-09-11',
          sequence: 2,
          lines: <Map<String, Object?>>[
            saleLine(
              productId: 'p-rice',
              name: 'Rice',
              quantity: 3,
              unitPriceMinor: 30000,
            ),
          ],
        ),
      ]);

      final rice = analysis.items.single;

      expect(rice.quantity, 5);
      expect(rice.linesWithoutCost, 1);
      expect(
        rice.isCostComplete,
        isFalse,
        reason:
            'Its margin is computed over part of what sold, and the report '
            'has to be able to say so.',
      );
    });
  });

  group('the margin figure states its own denominator', () {
    test('cost coverage is the share of lines that can be costed', () {
      final analysis = _analysis(<TenantSale>[
        fixtureSale(
          id: 'co-1',
          businessDate: '2026-09-10',
          lines: <Map<String, Object?>>[
            saleLine(
              productId: 'a',
              name: 'A',
              quantity: 1,
              unitPriceMinor: 1000,
              unitCostMinor: 600,
            ),
            saleLine(
              productId: 'b',
              name: 'B',
              quantity: 1,
              unitPriceMinor: 1000,
              unitCostMinor: 600,
            ),
            saleLine(
              productId: 'c',
              name: 'C',
              quantity: 1,
              unitPriceMinor: 1000,
            ),
          ],
        ),
      ]);

      expect(analysis.lineCount, 3);
      expect(analysis.linesWithoutCost, 1);
      expect(analysis.costCoverage, closeTo(2 / 3, 0.0001));
      expect(
        analysis.isCostComplete,
        isFalse,
        reason:
            'The `incompleteCostLineCount` discipline: print the figure, state '
            'the denominator, count the missing rather than guess it.',
      );
      expect(
        analysis.marginMinor,
        1800,
        reason:
            '3000 taken less the 1200 that was actually recorded as cost. The '
            'third line contributes its takings and no cost, so the margin is '
            'an overstatement and the report says so.',
      );
    });

    test('a period with nothing sold has no margin rate to quote', () {
      final analysis = _analysis(const <TenantSale>[]);

      expect(analysis.marginRate, isNull);
      expect(analysis.discountRate, isNull);
      expect(
        analysis.costCoverage,
        1,
        reason: 'No lines means none are missing a cost.',
      );
    });
  });

  group('how the period was paid for', () {
    test('a sale with no recorded tender is named, not dropped', () {
      final analysis = _analysis(<TenantSale>[
        fixtureSale(
          id: 'co-1',
          businessDate: '2026-09-10',
          tender: 'cash',
          lines: <Map<String, Object?>>[
            saleLine(
              productId: 'a',
              name: 'A',
              quantity: 1,
              unitPriceMinor: 1000,
            ),
          ],
        ),
        fixtureSale(
          id: 'co-2',
          businessDate: '2026-09-10',
          sequence: 2,
          tender: null,
          lines: <Map<String, Object?>>[
            saleLine(
              productId: 'a',
              name: 'A',
              quantity: 1,
              unitPriceMinor: 3000,
            ),
          ],
        ),
      ]);

      expect(
        analysis.tenders.map((t) => t.label),
        containsAll(<String>['Not recorded', 'Cash']),
        reason:
            'A sale recorded before the app stored a tender is a real sale. '
            'Dropping it would make the shares add up to less than the '
            'takings.',
      );
      expect(
        analysis.tenders.fold(0, (sum, t) => sum + t.minor),
        analysis.revenueMinor,
        reason: 'The mix totals the takings exactly, or it is not a mix.',
      );
      expect(
        analysis.tenders.first.tender,
        isNull,
        reason: 'It is the largest, so it leads - unrecorded or not.',
      );
    });

    test('the tender enum survives the round trip', () {
      final analysis = _analysis(<TenantSale>[
        fixtureSale(
          id: 'co-1',
          businessDate: '2026-09-10',
          tender: 'mpesa',
          lines: <Map<String, Object?>>[
            saleLine(
              productId: 'a',
              name: 'A',
              quantity: 1,
              unitPriceMinor: 1000,
            ),
          ],
        ),
      ]);

      expect(analysis.tenders.single.tender, CheckoutTender.mpesa);
      expect(analysis.tenders.single.label, 'M-Pesa');
    });
  });

  group('the shape of the period', () {
    test('every day is charted, including the ones that took nothing', () {
      final analysis = _analysis(<TenantSale>[
        fixtureSale(
          id: 'co-1',
          businessDate: '2026-09-10',
          lines: <Map<String, Object?>>[
            saleLine(
              productId: 'a',
              name: 'A',
              quantity: 1,
              unitPriceMinor: 5000,
            ),
          ],
        ),
      ]);

      expect(analysis.dailyMinor.length, 7);
      expect(analysis.dailyMinor['2026-09-10'], 5000);
      expect(analysis.dailyMinor['2026-09-11'], 0);
      expect(
        analysis.quietDays,
        6,
        reason: 'A shut day is a fact about the business, drawn as a zero.',
      );
      expect(analysis.bestDay, '2026-09-10');
    });

    test('weekday totals land on the right day', () {
      // 2026-09-10 is a Thursday.
      final analysis = _analysis(<TenantSale>[
        fixtureSale(
          id: 'co-1',
          businessDate: '2026-09-10',
          lines: <Map<String, Object?>>[
            saleLine(
              productId: 'a',
              name: 'A',
              quantity: 1,
              unitPriceMinor: 5000,
            ),
          ],
        ),
      ]);

      expect(
        analysis.weekdayMinor[3],
        5000,
        reason: 'Monday is index 0, so Thursday is 3.',
      );
      expect(TenantSalesAnalysis.weekdayNames[3], 'Thu');
      expect(
        analysis.weakestWeekday,
        3,
        reason:
            'The weakest day the shop actually traded on, not the weakest of '
            'the seven - six of them have no trading to be weak.',
      );
    });

    test('the basket median is the middle sale', () {
      final analysis = _analysis(<TenantSale>[
        for (final (index, units) in <int>[1, 9, 3].indexed)
          fixtureSale(
            id: 'co-$index',
            businessDate: '2026-09-10',
            sequence: index + 1,
            lines: <Map<String, Object?>>[
              saleLine(
                productId: 'a',
                name: 'A',
                quantity: units,
                unitPriceMinor: 1000,
              ),
            ],
          ),
      ]);

      expect(
        analysis.medianBasket,
        3,
        reason: 'Sorted 1, 3, 9 - the middle one, not the mean of 4.3.',
      );
    });
  });

  group('the comparison and the netting', () {
    test('takings move against the period before', () {
      final analysis = _analysis(
        <TenantSale>[
          fixtureSale(
            id: 'co-1',
            businessDate: '2026-09-10',
            lines: <Map<String, Object?>>[
              saleLine(
                productId: 'a',
                name: 'A',
                quantity: 1,
                unitPriceMinor: 12000,
              ),
            ],
          ),
        ],
        previous: <TenantSale>[
          fixtureSale(
            id: 'co-0',
            businessDate: '2026-09-02',
            lines: <Map<String, Object?>>[
              saleLine(
                productId: 'a',
                name: 'A',
                quantity: 1,
                unitPriceMinor: 10000,
              ),
            ],
          ),
        ],
      );

      expect(analysis.change, closeTo(0.2, 0.0001));
      expect(analysis.previousTransactions, 1);
    });

    test('a period that was read and was empty is not an unread one', () {
      // **The bug a device run found.** A shop with no trading last month got
      // the sentence "the period before this one could not be read", which is
      // a claim about the evidence rather than about the shop. Read-and-empty
      // and not-read are different facts and the report says different things
      // about them.
      final empty = _analysis(<TenantSale>[
        _sale(id: 'co-1', soldById: 'u-a', unitPriceMinor: 12000),
      ], previous: const <TenantSale>[]);

      expect(
        empty.previousRevenueMinor,
        0,
        reason: 'It was read. Nothing was taken. That is a figure, not a gap.',
      );
      expect(
        empty.previousTransactions,
        0,
        reason: 'And no caveat about unreadable records is warranted.',
      );
    });

    test('no earlier window read means no comparison invented', () {
      final analysis = _analysis(<TenantSale>[
        fixtureSale(
          id: 'co-1',
          businessDate: '2026-09-10',
          lines: <Map<String, Object?>>[
            saleLine(
              productId: 'a',
              name: 'A',
              quantity: 1,
              unitPriceMinor: 12000,
            ),
          ],
        ),
      ]);

      expect(analysis.previousRevenueMinor, isNull);
      expect(analysis.change, isNull);
    });

    test('a discount rate is of what would otherwise have been taken', () {
      final analysis = _analysis(<TenantSale>[
        fixtureSale(
          id: 'co-1',
          businessDate: '2026-09-10',
          discountMinor: 1000,
          lines: <Map<String, Object?>>[
            saleLine(
              productId: 'a',
              name: 'A',
              quantity: 1,
              unitPriceMinor: 10000,
            ),
          ],
        ),
      ]);

      expect(analysis.revenueMinor, 9000);
      expect(
        analysis.discountRate,
        closeTo(0.1, 0.0001),
        reason:
            '1000 off a 10,000 subtotal. Measuring it against the 9000 that '
            'was taken would understate every discount ever given.',
      );
    });
  });

  group('the whole fortnight', () {
    test('the fixture contains the disagreement the report is about', () {
      final analysis = fixtureSalesAnalysis();

      expect(analysis.sellerEarnerDiffer, isTrue);
      expect(analysis.bestSeller?.name, 'Maize flour 2kg');
      expect(analysis.bestEarner?.name, 'Cooking oil 1L');
      expect(
        analysis.isCostComplete,
        isFalse,
        reason: 'Soap records no cost, which is the ordinary case.',
      );
      expect(analysis.quietDays, 1, reason: 'The shop was shut on the 14th.');
      expect(analysis.change, isNotNull);
    });
  });
}
