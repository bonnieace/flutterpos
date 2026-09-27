/// `ProvenanceLine`'s matrix, per `claude.md` hard rule 5 and `design.md` §10.
///
/// **A provenance line is a readout, so §5's nine states are not its matrix.**
/// There is no hover, no focus, no press, no disabled and no loading, because
/// there is nothing to do to it — the same argument `StatusBadge` and `Callout`
/// make one file over. What varies is the three things the seven call sites it
/// replaced actually vary: **one line or a pair**, **whether it fits on one
/// line**, and **what it sits under**.
///
/// **The density pair is the point of having two images rather than one.**
/// §5.2 states `caption` flat, and `caption` is one of the roles `AppDensity`
/// does not swap — only the body role moves, 16 to 14. So provenance is 12
/// beside a 16 body at comfortable and 12 beside a 14 body at compact, and the
/// two captures exist to show the line holding still while its neighbours move.
/// If a future change made provenance density-aware, these are the two pictures
/// that would stop being a pair.
///
/// **The absent case is a row with no provenance, deliberately.** An optional
/// line's real state matrix has three entries and the third is *nothing drawn*,
/// which only reads as a state when it is beside the ones that draw something.
library;

import 'package:flutter/material.dart';
import 'package:uzapay_pos/ui/states.dart';
import 'package:uzapay_pos/ui/tokens.dart';

import 'harness.dart';

void main() {
  // Named in a record rather than read off the type: `AppDensity` is a class of
  // static consts rather than an enum, so it has no `name` - the same shape
  // `93-status-*` uses one file over.
  for (final density in <({String name, AppDensity value})>[
    (name: 'comfortable', value: AppDensity.comfortable),
    (name: 'compact', value: AppDensity.compact),
  ]) {
    screenshotCase(
      '96-provenance-${density.name}',
      build: () => _Host(density: density.value, label: density.name),
      fullPage: false,
    );
  }
}

/// One record's worth of text, so a provenance line can be seen doing its job
/// rather than floating.
///
/// The shape is `RecordList`'s card form — title, subtitle, provenance — because
/// that is where five of the seven replaced sites sat, and the relationship
/// between the three type roles is the thing worth photographing. A grey box
/// above it would show the style and none of the relationship.
final class _Row extends StatelessWidget {
  const _Row({required this.label, required this.title, this.lines = const []});

  /// What this case is showing, in the picture rather than in a filename.
  final String label;

  final String title;

  /// Zero, one or two provenance lines.
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Padding(
      padding: EdgeInsets.only(bottom: tokens.spacing.s16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.colors.surface.raised,
          border: Border.all(color: tokens.colors.surface.borderSubtle),
          borderRadius: BorderRadius.circular(tokens.radius.md),
        ),
        child: Padding(
          padding: EdgeInsets.all(tokens.spacing.s16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label,
                style: tokens.typography.labelEyebrow.copyWith(
                  color: tokens.colors.text.tertiary,
                ),
              ),
              SizedBox(height: tokens.spacing.s8),
              Text(
                title,
                style: tokens.typography.titleMedium.copyWith(
                  color: tokens.colors.text.primary,
                ),
              ),
              SizedBox(height: tokens.spacing.s4),
              Text(
                'Dairy and chilled · KES 65.00',
                style: tokens.density
                    .body(tokens.typography)
                    .copyWith(color: tokens.colors.text.secondary),
              ),
              if (lines.isNotEmpty) SizedBox(height: tokens.spacing.s12),
              for (final line in lines) ProvenanceLine(line),
            ],
          ),
        ),
      ),
    );
  }
}

final class _Host extends StatelessWidget {
  const _Host({required this.density, required this.label});

  final AppDensity density;

  /// The density's name, for the heading. See the note at the call site.
  final String label;

  @override
  Widget build(BuildContext context) => Builder(
    builder: (context) => Theme(
      data: Theme.of(context).copyWith(
        extensions: <ThemeExtension<dynamic>>[
          AppTokens.componentOf(context).withDensity(density),
        ],
      ),
      child: Builder(
        builder: (context) {
          final tokens = AppTokens.componentOf(context);
          return Scaffold(
            body: SafeArea(
              child: Padding(
                padding: EdgeInsets.all(tokens.spacing.s24),
                child: ListView(
                  children: <Widget>[
                    Text(
                      'ProvenanceLine - $label',
                      style: tokens.typography.titleLarge.copyWith(
                        color: tokens.colors.text.primary,
                      ),
                    ),
                    SizedBox(height: tokens.spacing.s20),
                    const _Row(
                      label: 'ONE LINE',
                      title: 'Fresh whole milk 500ml',
                      lines: <String>['Recorded 2026-08-01 09:00 UTC by Amina'],
                    ),
                    // The reconciliation run's shape: an actor and a pair of
                    // instants are two facts, so §5.2 gives them two lines and
                    // nothing sits between them.
                    const _Row(
                      label: 'A PAIR',
                      title: 'Reconciliation run',
                      lines: <String>[
                        'Requested by Amina',
                        'Started 2026-08-01 09:00 UTC, finished 09:00 UTC',
                      ],
                    ),
                    // Long enough to wrap at 411 and not at 1440, so the pair of
                    // viewports shows both. §5.2 sets no maximum here and none
                    // of the seven replaced sites set one either: a provenance
                    // line that ellipsised would drop the actor, which is the
                    // half a person is usually looking for.
                    const _Row(
                      label: 'LONGER THAN ITS LINE',
                      title: 'Stock correction',
                      lines: <String>[
                        'Recorded 2026-08-01 09:00 UTC by Amina Wanjiru, '
                            'reason: damaged in transit, counted twice against '
                            'the delivery note',
                      ],
                    ),
                    const _Row(
                      label: 'ABSENT - NOTHING IS DRAWN',
                      title: 'White bread, sliced',
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}
