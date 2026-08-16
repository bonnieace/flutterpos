/// `AppTabs`: `design.md` §5.1's priority-3 row for "platform tabs".
///
/// **It wraps `TabBar` rather than redrawing one, and that is the same decision
/// `AppScaffold` made about `AppBar`.** `TabBar` owns the `TabController`
/// handshake, the indicator's travel, the scroll-into-view of a selected tab
/// and the tab semantics; hand-drawing it would move selection behaviour into a
/// visual change, which `claude.md` hard rule 1 forbids. What this file owns is
/// everything §2.1, §2.2 and §9 have to say about how it looks.
///
/// **It fixes a §9 failure nobody had listed.** A Material text tab is
/// **46** logical pixels high — `_kTabHeight` in the SDK — and §9's touch-target
/// row is 48 × 48, pass/fail. The four tabs on the platform route have been two
/// pixels short since they were written, and no audit caught it because §9's
/// own "known current failures" list names `Correct` / `Retire` and `Previous` /
/// `Next` and stops. The height here comes from `density.minimumTapTarget`, so
/// it is the same 48 every other control in this app is measured against.
///
/// **The one number this component names is the indicator's weight**, and it is
/// read rather than chosen: `design.md` states exactly one stroke width
/// anywhere — §2.1's focus ring at 2px — so the indicator takes that token
/// instead of Material's coincidentally-equal default. If the ring ever moves,
/// the indicator moves with it, which is the property a literal `2` would not
/// have.
library;

import 'package:flutter/material.dart';

import 'tokens.dart';

/// A strip of tabs, in this system's type and colour.
///
/// Requires a `TabController` above it, exactly as `TabBar` does — usually a
/// `DefaultTabController`. This component deliberately does not create one:
/// which tab is selected is state, and a component that owned it would be a
/// behaviour change wearing a visual component's clothes.
final class AppTabs extends StatelessWidget implements PreferredSizeWidget {
  const AppTabs({super.key, required this.tabs, this.isScrollable = true});

  /// One label per tab, in order. Sentence case, §8 rule 7 — this widget does
  /// not case them.
  final List<String> tabs;

  /// Scrolling by default, because the strip this replaces has four labels of
  /// three words each and a phone is 411 logical pixels wide. §4.3 gives
  /// `FilterChips` "horizontal scroll, one line" at `compact` for the same
  /// reason and a tab strip is the same shape of problem.
  final bool isScrollable;

  /// §9's touch-target row, which Material's own tab height misses by two.
  static double get height => AppDensity.comfortable.minimumTapTarget.height;

  @override
  Size get preferredSize => Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final accent = tokens.colors.action.primary.container;
    return TabBar(
      isScrollable: isScrollable,
      // §2.2's `label.lg`: the role for "buttons, tabs, chips" in a document
      // that names tabs in that row by name.
      labelStyle: tokens.typography.labelLarge,
      unselectedLabelStyle: tokens.typography.labelLarge,
      labelColor: tokens.colors.text.primary,
      unselectedLabelColor: tokens.colors.text.secondary,
      indicatorColor: accent,
      indicatorWeight: tokens.colors.action.focusRing.width,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: tokens.colors.surface.borderSubtle,
      // **The selected tab says so twice**, which is §9's "status conveyed by
      // container + icon + label, never hue alone" applied to a selection: the
      // label goes from `text.secondary` to `text.primary` *and* the indicator
      // appears under it. Hue alone would be the accent-coloured label a first
      // pass at this reached for.
      tabs: <Widget>[
        for (final label in tabs) Tab(height: height, text: label),
      ],
    );
  }
}
