import 'package:uzapay_pos/reporting/reporting.dart';
import 'package:uzapay_pos/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('what a profit figure is worth', () {
    test('a fully costed period is complete and carries its margin', () {
      final report = TenantProfitReport.from(
        sales: 1250.5,
        profit: 430.25,
        incompleteCostLineCount: 0,
      );

      expect(report.basis, TenantProfitBasis.complete);
      expect(report.isShowable, isTrue);
      expect(report.profit, 430.25);
      // 43025 / 125050, exactly as the server's own minor units divide.
      expect(report.marginPercent, closeTo(34.4062, 0.0001));
    });

    test('the margin is divided in whole minor units, not in doubles', () {
      // 0.1 + 0.2 in doubles is the standard example; the server added these
      // as integers, so the ratio must come out of integers too.
      final report = TenantProfitReport.from(
        sales: 0.3,
        profit: 0.1,
        incompleteCostLineCount: 0,
      );

      expect(report.marginPercent, closeTo(33.3333, 0.0001));
    });

    test('a loss is a complete answer, and its margin is negative', () {
      final report = TenantProfitReport.from(
        sales: 100,
        profit: -25,
        incompleteCostLineCount: 0,
      );

      expect(report.basis, TenantProfitBasis.complete);
      expect(report.marginPercent, closeTo(-25, 0.0001));
    });

    test('one uncosted line withholds the figure and the margin', () {
      final report = TenantProfitReport.from(
        sales: 1250.5,
        profit: 430.25,
        incompleteCostLineCount: 1,
      );

      expect(report.basis, TenantProfitBasis.incomplete);
      expect(report.isShowable, isFalse);
      // The figure is still carried - it is refused, not erased - but nothing
      // may divide by it.
      expect(report.profit, 430.25);
      expect(report.marginPercent, isNull);
    });

    test('a profit equal to the takings is refused, never shown as 100%', () {
      // The exact shape every period before products carried costs produces:
      // no line has a cost, so the server subtracts nothing.
      final report = TenantProfitReport.from(
        sales: 4820.75,
        profit: 4820.75,
        incompleteCostLineCount: 96,
      );

      expect(report.basis, TenantProfitBasis.incomplete);
      expect(report.marginPercent, isNull);
    });

    test('a profit larger than the takings is inconsistent', () {
      // A negative total cost, which nothing that writes either figure can
      // produce: profit is revenue minus a sum of non-negative line costs.
      final report = TenantProfitReport.from(
        sales: 100,
        profit: 100.01,
        incompleteCostLineCount: 0,
      );

      expect(report.basis, TenantProfitBasis.inconsistent);
      expect(report.isShowable, isFalse);
      expect(report.marginPercent, isNull);
    });

    test('an impossible figure outranks an incomplete one', () {
      // Most-specific cause first. An incomplete figure is at least the
      // arithmetic it claims to be; this one is not, and saying "some lines
      // have no cost" would name a cause that does not explain it.
      final report = TenantProfitReport.from(
        sales: 100,
        profit: 250,
        incompleteCostLineCount: 4,
      );

      expect(report.basis, TenantProfitBasis.inconsistent);
    });

    test('a period that took nothing has no margin to report', () {
      final report = TenantProfitReport.from(
        sales: 0,
        profit: 0,
        incompleteCostLineCount: 0,
      );

      // Complete: there is no line without a cost. But a margin on no takings
      // is a division by zero, not a figure of zero.
      expect(report.basis, TenantProfitBasis.complete);
      expect(report.isShowable, isTrue);
      expect(report.marginPercent, isNull);
    });

    test('a sub-cent difference is rounded the way the server rounds', () {
      // 100.004 and 100.0 are the same figure in whole minor units, so this is
      // a zero cost rather than a negative one.
      final report = TenantProfitReport.from(
        sales: 100,
        profit: 100.004,
        incompleteCostLineCount: 0,
      );

      expect(report.basis, TenantProfitBasis.complete);
      expect(report.marginPercent, closeTo(100, 0.0001));
    });
  });

  group('who may be shown one', () {
    test('an owner and an administrator may; nobody else may', () {
      expect(TenantProfitReport.allowedRoles, <TenantRole>[
        TenantRole.owner,
        TenantRole.admin,
      ]);
      for (final role in TenantRole.values) {
        expect(
          TenantProfitReport.canSeeInSession(_session(role)),
          role == TenantRole.owner || role == TenantRole.admin,
          reason: 'role ${role.name}',
        );
      }
    });

    test('a manager reads the takings and is shown no margin', () {
      // The tier the standing product-cost decision named, over a document a
      // manager can read: this is a surface boundary, not a secrecy guarantee.
      expect(
        TenantDailyMetricsRepository.allowedRoles,
        contains(TenantRole.manager),
      );
      expect(
        TenantSalesTotalsGateway.allowedRoles,
        contains(TenantRole.manager),
      );
      expect(
        TenantProfitReport.canSeeInSession(_session(TenantRole.manager)),
        isFalse,
      );
    });
  });
}

TenantSession _session(TenantRole role) =>
    TenantSession.active(uid: 'user-a', tenantId: 'tenant-a', role: role);
