/// Step 5a's state matrix, which `claude.md` hard rule 5 and `design.md` §10
/// both require before a component is finished.
///
/// **A page frame is not a control, so §5's nine states are not its matrix.**
/// It has no hover, no focus-visible, no pressed, no disabled and no loading -
/// there is nothing to do to it. The one pressable thing on it is the caller's
/// own primary action, which is an `AppButton` and already has its six captures
/// under `90-*`. `error` and `empty` belong to the content a screen puts in the
/// body, and they are `ErrorState` and `EmptyState` in §5.1, neither of which
/// exists yet.
///
/// What actually varies is the frame's own shape, and that is what these
/// capture: title alone, title with a subtitle, with and without a primary
/// action, with and without toolbar actions, with and without a way back, at
/// both densities, and with a title long enough to make the two arrangements of
/// the action row differ.
///
/// **Every case is captured at both viewports and that is doing double duty
/// here.** 1440 is above §4.1's `expanded` floor and 411 is below it, so each
/// pair shows §2.2's two screen-title roles - `display` 32 / 40 and `title.lg`
/// 22 / 28 - and the two arrangements of the action row, beside the title and
/// under it, without a separate case for either.
library;

import 'package:flutter/material.dart';
import 'package:flutter_application_1/ui/buttons.dart';
import 'package:flutter_application_1/ui/scaffold.dart';
import 'package:flutter_application_1/ui/status.dart';
import 'package:flutter_application_1/ui/tokens.dart';

import 'harness.dart';

/// A body that looks like a page rather than like a placeholder.
///
/// §7's pattern is *header → optional `Callout` → filters → content →
/// pagination*, and the point of photographing the frame is to see where the
/// header sits relative to what comes after it. A grey box would show the
/// spacing and none of the relationship.
class _Body extends StatelessWidget {
  const _Body({this.callout = false});

  final bool callout;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return ListView(
      padding: EdgeInsets.symmetric(horizontal: tokens.spacing.s20),
      children: <Widget>[
        if (callout) ...<Widget>[
          const Callout(
            status: AppStatus.info,
            message:
                'Three sales are queued on this device and will be sent when '
                'the connection returns.',
          ),
          SizedBox(height: tokens.density.sectionGap),
        ],
        for (final row in const <({String name, String detail})>[
          (name: 'Fresh whole milk 500ml', detail: 'KES 65.00 · 24 in stock'),
          (name: 'White bread, sliced', detail: 'KES 70.00 · 11 in stock'),
          (name: 'Cooking oil 1L', detail: 'KES 320.00 · 6 in stock'),
          (name: 'Sugar 1kg', detail: 'KES 180.00 · 40 in stock'),
        ])
          Padding(
            padding: EdgeInsets.only(bottom: tokens.spacing.s12),
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
                      row.name,
                      style: tokens.typography.titleMedium.copyWith(
                        color: tokens.colors.text.primary,
                      ),
                    ),
                    SizedBox(height: tokens.spacing.s4),
                    Text(
                      row.detail,
                      style: tokens.typography.numericBody.copyWith(
                        color: tokens.colors.text.secondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// One frame, at one density.
class _Frame extends StatelessWidget {
  const _Frame({
    required this.title,
    this.subtitle,
    this.action = false,
    this.signOut = false,
    this.callout = false,
    this.density = AppDensity.comfortable,
  });

  final String title;
  final String? subtitle;
  final bool action;
  final bool signOut;
  final bool callout;
  final AppDensity density;

  @override
  Widget build(BuildContext context) => Builder(
    builder: (context) => Theme(
      data: Theme.of(context).copyWith(
        extensions: <ThemeExtension<dynamic>>[
          AppTokens.componentOf(context).withDensity(density),
        ],
      ),
      child: AppScaffold(
        title: title,
        // The body below is a list of records, and step 6 requires every page
        // to say which of §4.2's rows it is. `95-*` is the matrix that varies
        // this; here it is held fixed so these stay pictures of the header.
        contentWidth: AppContentWidth.records,
        subtitle: subtitle,
        primaryAction: action
            ? AppButton(
                label: 'Add a product',
                icon: Icons.add,
                tier: AppButtonTier.primary,
                onPressed: () {},
              )
            : null,
        actions: signOut
            ? <Widget>[
                AppButton(
                  label: 'Sign out',
                  tier: AppButtonTier.tertiary,
                  onPressed: () {},
                ),
              ]
            : const <Widget>[],
        body: _Body(callout: callout),
      ),
    ),
  );
}

/// The same frame, one route deep, so the toolbar draws the way back.
///
/// A `Navigator` with two pages rather than a tap in `afterPump`: the leading
/// control appears because there is a route underneath, and building that
/// stack directly is the honest way to photograph it. Every route in the app
/// except the shell's own is reached this way.
class _PushedFrame extends StatelessWidget {
  const _PushedFrame({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Navigator(
    onDidRemovePage: (_) {},
    pages: <Page<void>>[
      const MaterialPage<void>(child: Scaffold(body: SizedBox())),
      MaterialPage<void>(
        child: _Frame(title: title, subtitle: subtitle, action: true),
      ),
    ],
  );
}

void main() {
  screenshotCase(
    '94-page-frame-title',
    build: () => const _Frame(title: 'Manage catalog'),
  );

  screenshotCase(
    '94-page-frame-subtitle',
    build: () => const _Frame(
      title: 'Reconciliation status',
      subtitle: 'Business day 2026-08-12 UTC',
    ),
  );

  screenshotCase(
    '94-page-frame-action',
    build: () => const _Frame(
      title: 'Manage catalog',
      subtitle: 'Everything this business sells',
      action: true,
      callout: true,
    ),
  );

  screenshotCase(
    '94-page-frame-toolbar-actions',
    build: () => const _Frame(title: 'Choose a business', signOut: true),
  );

  // The case that decided the action row's two arrangements: a product name is
  // the longest title any route in this app carries, and §5.2 forbids
  // truncating it.
  screenshotCase(
    '94-page-frame-long-title',
    build: () => const _Frame(
      title:
          'Adjustments: Fresh whole milk 500ml, refrigerated, case of twelve',
      action: true,
    ),
  );

  screenshotCase(
    '94-page-frame-compact',
    build: () => const _Frame(
      title: 'Activity log',
      subtitle: 'Every event this business recorded',
      action: true,
      density: AppDensity.compact,
    ),
  );

  screenshotCase(
    '94-page-frame-pushed',
    build: () => const _PushedFrame(
      title: 'Product stock ledger',
      subtitle: 'Fresh whole milk 500ml',
    ),
  );
}
