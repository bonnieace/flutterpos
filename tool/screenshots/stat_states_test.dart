/// Step 8's state matrix: `StatTile`, `StatRow` and `StatLine`.
///
/// **Photographed at all three bands rather than two, deliberately.** The
/// lesson `PLAN.md` records from 2026-08-14 is that a component matrix taken at
/// one width hides the states a narrow screen creates: step 4's `93-disclosure-*`
/// captures are `web` only, and a truncated summary shipped and survived two
/// days because of it. A stat row's whole behaviour is how many tiles it puts
/// across a width, so a picture of it at one width is a picture of none of it.
///
/// **Which of §5's nine states apply, and why the rest do not.** A stat tile is
/// a readout, like `StatusBadge` and `Callout`: there is nothing to do to it, so
/// it has no hover, focus-visible, pressed, disabled or loading. What varies is
/// what it says - a count, money, a figure with a standing, a figure with
/// nothing under it - and how many of them fit. `empty` is a row with no tiles,
/// which draws nothing at all, and that is asserted in `test/ui/stats_test.dart`
/// rather than photographed: a picture of nothing is not evidence.
library;

import 'package:flutter/material.dart';
import 'package:uzapay_pos/ui/card.dart';
import 'package:uzapay_pos/ui/stats.dart';
import 'package:uzapay_pos/ui/status.dart';
import 'package:uzapay_pos/ui/tokens.dart';

import 'harness.dart';

/// The figures this app actually shows, rather than lorem numbers.
///
/// The four counts are the staff directory's own strip and the two money
/// figures are the period totals'; the negative stock is the one tile in the app
/// with a standing, and it is the case the component was changed for.
class _StatMatrix extends StatelessWidget {
  const _StatMatrix({required this.title, required this.tiles});

  final String title;
  final List<StatTile> tiles;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(tokens.spacing.s20),
        child: StatRow(tiles: tiles),
      ),
    );
  }
}

/// The home's grid: nested tiles with their glyphs in wells, in the panel the
/// home draws round them.
///
/// **Every reading a home tile can give, in one panel**: money, a count, the em
/// dash of a day nothing was counted for, a badge on unsent sales, a detail
/// line, and a loss.
class _HomeGridMatrix extends StatelessWidget {
  const _HomeGridMatrix();

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final accent = tokens.colors.accent;
    final green = accent.identityAt(AppIdentityAccent.green);
    return Scaffold(
      appBar: AppBar(title: const Text('StatTile - nested, on the home')),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(tokens.spacing.s20),
        child: AppCard(
          padding: EdgeInsets.all(tokens.spacing.s8),
          radius: tokens.radius.xl,
          child: StatRow(
            gap: tokens.spacing.s8,
            tiles: <StatTile>[
              StatTile(
                label: "Today's sales",
                value: 'KES 910.00',
                money: true,
                icon: Icons.payments_outlined,
                accent: tokens.colors.text.money,
                nested: true,
                status: AppStatus.attention,
                statusLabel: '2 not sent',
              ),
              StatTile(
                label: 'Transactions',
                value: '23',
                icon: Icons.receipt_long_outlined,
                accent: accent.identityAt(AppIdentityAccent.blue),
                nested: true,
              ),
              StatTile(
                label: 'Shifts',
                value: '—',
                icon: Icons.schedule_outlined,
                accent: tokens.colors.text.secondary,
                nested: true,
                detail: 'Opened today',
              ),
              StatTile(
                label: 'Net profit',
                value: 'KES -241.50',
                money: true,
                icon: Icons.savings_outlined,
                accent: green,
                nested: true,
                status: AppStatus.problem,
                statusLabel: 'Loss',
                detail: 'After cost of goods and expenses',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A column of `StatLine`s: money in flow, which is the other half of step 8.
class _LineMatrix extends StatelessWidget {
  const _LineMatrix({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(tokens.spacing.s20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Paid by',
              style: tokens.typography.titleMedium.copyWith(
                color: tokens.colors.text.primary,
              ),
            ),
            SizedBox(height: tokens.spacing.s4),
            // The figures a period actually splits into, with the widest and
            // the narrowest amounts in the same column - which is the whole
            // argument for tabular figures and a shared right edge.
            const StatLine(
              label: 'Cash',
              detail: '20 sales',
              value: 'KES 2000.25',
            ),
            const StatLine(
              label: 'M-Pesa',
              detail: '10 sales',
              value: 'KES 1800.50',
            ),
            const StatLine(
              label: 'Card',
              detail: '5 sales',
              value: 'KES 900.00',
            ),
            const StatLine(
              label: 'Not recorded',
              detail: '1 sale',
              value: 'KES 100.00',
            ),
            const StatLine(
              label: 'Unrecognised',
              detail: '1 sale',
              value: 'KES 20.00',
            ),
            SizedBox(height: tokens.density.sectionGap),
            Text(
              'A day, and its total',
              style: tokens.typography.titleMedium.copyWith(
                color: tokens.colors.text.primary,
              ),
            ),
            SizedBox(height: tokens.spacing.s4),
            const StatLine(
              label: 'Sales',
              value: 'KES 1250.50',
              emphasis: true,
            ),
            const StatLine(label: 'Transactions', value: '12'),
            const StatLine(label: 'Shifts', value: '2'),
            const StatLine(label: 'Profit', value: 'KES 430.25'),
            const StatLine(label: 'Margin', value: '34.4%'),
          ],
        ),
      ),
    );
  }
}

void main() {
  screenshotCase(
    '97-stat-counts',
    viewports: responsiveViewports,
    build: () => const _StatMatrix(
      title: 'StatTile - counts',
      tiles: <StatTile>[
        StatTile(
          label: 'Staff',
          value: '4',
          icon: Icons.people_outline,
          detail: 'on this page',
        ),
        StatTile(
          label: 'Active',
          value: '3',
          icon: Icons.check_circle_outline,
          detail: 'can sign in and sell',
        ),
        StatTile(
          label: 'Pending',
          value: '1',
          icon: Icons.hourglass_empty,
          detail: 'invited, not yet accepted',
        ),
        StatTile(
          label: 'Owners & admins',
          value: '2',
          icon: Icons.workspace_premium_outlined,
          detail: 'full access',
        ),
      ],
    ),
  );

  screenshotCase(
    '97-stat-money',
    viewports: responsiveViewports,
    build: () => const _StatMatrix(
      title: 'StatTile - money',
      tiles: <StatTile>[
        StatTile(
          label: 'Sales',
          value: 'KES 4820.75',
          icon: Icons.payments_outlined,
          detail: 'taken over this period',
        ),
        StatTile(
          label: 'Sales',
          value: '37',
          icon: Icons.receipt_long_outlined,
          detail: 'counted in this total',
        ),
      ],
    ),
  );

  screenshotCase(
    '97-stat-standing',
    viewports: responsiveViewports,
    build: () => const _StatMatrix(
      title: 'StatTile - a figure with a standing',
      tiles: <StatTile>[
        StatTile(
          label: 'Recorded stock',
          value: '-3',
          icon: Icons.inventory_2_outlined,
          detail: 'held by the server',
          status: AppStatus.problem,
          statusLabel: 'Below zero',
        ),
        StatTile(
          label: 'Ledger entries',
          value: '12',
          icon: Icons.receipt_long_outlined,
          detail: 'on this page, more to load',
        ),
      ],
    ),
  );

  screenshotCase(
    '97-stat-home-grid',
    viewports: responsiveViewports,
    build: () => const _HomeGridMatrix(),
  );

  screenshotCase(
    '97-stat-lines',
    viewports: responsiveViewports,
    build: () => const _LineMatrix(title: 'StatLine - money in flow'),
  );
}
