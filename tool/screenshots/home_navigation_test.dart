/// Step 5b: `design.md` §4.4's `HomeNavigation`, photographed.
///
/// **The matrix of this component is §4.4's own table**, so every case is
/// captured at all three bands: a two-column grid below 768, a three-column grid
/// to 1023, and the side menu at 1024 and above. `RecordList` is the precedent -
/// a component whose subject is the responsive contract itself has to be seen at
/// each band or the contract is reviewed on part of its cases.
///
/// **The `web` captures moved in the second half and the other two did not.**
/// The menu is the frame's now rather than the body's, so at 1440 it is a
/// full-height column beside the page instead of a block inside it, and the
/// content beside it starts where the column ends. Below 1024 nothing about
/// these pictures changed, which is the check: the cards are content and the
/// second half did not touch content.
///
/// **The states are the ones a destination actually has.** §5's matrix is a
/// control's: `enabled`, `disabled` and this component's own addition - a card
/// carrying a condition - are properties and fit in one capture each.
/// `hover`, `focus-visible` and `pressed` are `PressSurface`'s and are
/// photographed once, in `98-press-states`, against the widget that draws them
/// for every pressable surface in this app; drawing them again here would
/// photograph the same three overlays a second time. `loading`, `error` and
/// `read-only` do not apply: a destination has no value to be wrong about and
/// nothing to load - the route it opens does its own loading, behind its own
/// guard.
///
/// **`empty` is a real case here and it is the one worth keeping.** A session
/// offered nothing at all draws no frame rather than an empty bordered box, and
/// the picture is the evidence that it draws nothing rather than something
/// small.
library;

import 'package:flutter/material.dart';
import 'package:uzapay_pos/ui/home_navigation.dart';
import 'package:uzapay_pos/ui/scaffold.dart';
import 'package:uzapay_pos/ui/tokens.dart';

import 'harness.dart';

/// The eleven destinations the landing route actually offers an owner, in the
/// order §4.4 asks for: the primary first, then by frequency, with the two
/// account controls last.
List<HomeDestination> _owner() => <HomeDestination>[
  HomeDestination(
    destinationKey: const ValueKey('start-checkout'),
    label: 'New sale',
    icon: Icons.point_of_sale,
    isPrimary: true,
    onPressed: () {},
  ),
  HomeDestination(
    label: 'View read-only catalog',
    icon: Icons.inventory_2_outlined,
    onPressed: () {},
  ),
  HomeDestination(
    label: 'Manage catalog',
    icon: Icons.edit_note_outlined,
    onPressed: () {},
  ),
  HomeDestination(
    label: 'View daily summary',
    icon: Icons.insights_outlined,
    onPressed: () {},
  ),
  HomeDestination(
    label: 'Find a receipt',
    icon: Icons.receipt_long_outlined,
    onPressed: () {},
  ),
  HomeDestination(
    label: 'Checkout settings',
    icon: Icons.tune_outlined,
    onPressed: () {},
  ),
  HomeDestination(
    label: 'View activity log',
    icon: Icons.fact_check_outlined,
    onPressed: () {},
  ),
  HomeDestination(
    label: 'View staff directory',
    icon: Icons.people_outline,
    onPressed: () {},
  ),
  HomeDestination(
    label: 'Change business',
    icon: Icons.swap_horiz,
    onPressed: () {},
  ),
  const HomeDestination(
    label: 'Default business',
    icon: Icons.star,
    onPressed: null,
  ),
];

/// The same eleven, each saying what it knows - which is the whole argument for
/// a card over a tab, and the state a `Wrap` of pills could not carry at all.
List<HomeDestination> _stateful() => <HomeDestination>[
  HomeDestination(
    destinationKey: const ValueKey('start-checkout'),
    label: 'New sale',
    icon: Icons.point_of_sale,
    isPrimary: true,
    status: 'Shift open since 07:12',
    onPressed: () {},
  ),
  HomeDestination(
    label: 'View daily summary',
    icon: Icons.insights_outlined,
    status: '3 unresolved differences',
    onPressed: () {},
  ),
  HomeDestination(
    label: 'Manage catalog',
    icon: Icons.edit_note_outlined,
    status: '2 products out of stock',
    onPressed: () {},
  ),
  HomeDestination(
    label: 'Find a receipt',
    icon: Icons.receipt_long_outlined,
    status: '17 sales today',
    onPressed: () {},
  ),
  HomeDestination(
    label: 'View staff directory',
    icon: Icons.people_outline,
    status: '1 invitation pending',
    onPressed: () {},
  ),
  HomeDestination(
    label: 'Change business',
    icon: Icons.swap_horiz,
    onPressed: () {},
  ),
];

/// A cashier, who is offered three things and no account controls.
List<HomeDestination> _cashier() => <HomeDestination>[
  HomeDestination(
    destinationKey: const ValueKey('start-checkout'),
    label: 'New sale',
    icon: Icons.point_of_sale,
    isPrimary: true,
    onPressed: () {},
  ),
  HomeDestination(
    label: 'View read-only catalog',
    icon: Icons.inventory_2_outlined,
    onPressed: () {},
  ),
  HomeDestination(
    label: 'Find a receipt',
    icon: Icons.receipt_long_outlined,
    onPressed: () {},
  ),
];

final class _Page extends StatelessWidget {
  const _Page({required this.destinations});

  final List<HomeDestination> destinations;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final inset = AppScaffold.horizontalInset(tokens.spacing);
    // **The drawer's own rendering, drawn in the page.** Both hosts show the
    // same rows and the frame decides which one a band gets - the persistent
    // column at `expanded`, the drawer below it - so photographing the rows
    // directly is what shows them at every band without a capture having to
    // open a panel first. The frame's column is photographed by the same
    // `navigation` argument at `expanded`, where it draws beside this.
    return AppScaffold(
      title: 'Dev Corner Shop',
      contentWidth: AppContentWidth.records,
      navigation: destinations,
      body: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.fromLTRB(inset, 0, inset, tokens.spacing.s24),
          child: HomeNavigation.drawer(destinations: destinations),
        ),
      ),
    );
  }
}

void main() {
  /// A session offered nothing at all. The picture is the evidence that the
  /// component draws *nothing* rather than an empty bordered frame - §5.1 gives
  /// that case to `EmptyState`, which does not exist, and a box containing no
  /// destinations would be a fourth implementation of one.
  screenshotCase(
    '95-home-navigation-empty',
    viewports: responsiveViewports,
    build: () => const _Page(destinations: <HomeDestination>[]),
  );

  screenshotCase(
    '95-home-navigation-owner',
    viewports: responsiveViewports,
    build: () => _Page(destinations: _owner()),
  );

  screenshotCase(
    '95-home-navigation-stateful',
    viewports: responsiveViewports,
    build: () => _Page(destinations: _stateful()),
  );

  screenshotCase(
    '95-home-navigation-cashier',
    viewports: responsiveViewports,
    build: () => _Page(destinations: _cashier()),
  );
}
