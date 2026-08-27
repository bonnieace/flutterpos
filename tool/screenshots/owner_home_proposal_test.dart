/// **A proposal, not a step.** One picture of what the owner's landing route
/// could be, so the direction can be judged before any of it is planned.
///
/// This file writes `99-owner-home-proposal` and changes nothing else. It lives
/// in the harness rather than in `lib/` deliberately: every figure on it is a
/// literal, so it commits no repository read, moves no route and ships no
/// behaviour - `claude.md` hard rule 1 stays intact because there is nothing
/// here for it to apply to. If the direction is accepted, the work of *earning*
/// these figures is a separate change with its own review.
///
/// **What it is arguing against is `10-business-home-owner`**, which today
/// carries a tagline, a role sentence, a dev notice, a sentence about the shift,
/// a five-line text list of device counts, a three-line paragraph about what the
/// panel cannot do, and eleven cards - and not one number. The three §7 rows it
/// breaks are quoted at the call sites below.
///
/// **Two things this picture is not.** It is not evidence the app runs, per
/// `screenshots/README.md`. And it is not a component change: every widget here
/// is the one already built for steps 4, 5a, 5b and 8, composed differently.
/// That is the whole claim being made - the atoms were fine and the composition
/// was never done.
library;

import 'package:flutter/material.dart';
import 'package:flutter_application_1/ui/buttons.dart';
import 'package:flutter_application_1/ui/home_navigation.dart';
import 'package:flutter_application_1/ui/scaffold.dart';
import 'package:flutter_application_1/ui/stats.dart';
import 'package:flutter_application_1/ui/status.dart';
import 'package:flutter_application_1/ui/tokens.dart';

import 'harness.dart';

/// A section's name, above the section.
///
/// `title.md` / `text.primary` from §2.2, which is what the reporting screens
/// already label a group of figures with. Not `label.eyebrow`: §2.2 restricts
/// that role to field group labels, and `stats.dart` records the same refusal.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Text(
      text,
      style: tokens.typography.titleMedium.copyWith(
        color: tokens.colors.text.primary,
      ),
    );
  }
}

/// The card recipe `StatTile` uses, for the one section that is not a stat.
///
/// `surface.raised` with a `border.subtle` hairline at `radius.md`, padded
/// `space.16` - §2.1 and §2.3, and the same four values `StatTile` composes, read
/// off the tokens here rather than restated as numbers.
class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.colors.surface.raised,
        border: Border.all(color: tokens.colors.surface.borderSubtle),
        borderRadius: BorderRadius.circular(tokens.radius.md),
      ),
      child: Padding(padding: EdgeInsets.all(tokens.spacing.s16), child: child),
    );
  }
}

/// The shift, as a standing and two controls instead of a sentence.
///
/// Today this reads "No shift is open in this business." - a sentence, which §9
/// is indifferent to and which buries the one fact somebody about to trade needs
/// in prose. A shift has a standing, `StatusBadge` is §2.1's container plus icon
/// plus word, and `PLAN.md` already settled that a shift has one.
class _ShiftSection extends StatelessWidget {
  const _ShiftSection();

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Shift',
                  style: tokens.typography.labelMedium.copyWith(
                    color: tokens.colors.text.secondary,
                  ),
                ),
              ),
              const StatusBadge(status: AppStatus.ok, label: 'Open'),
            ],
          ),
          SizedBox(height: tokens.spacing.s8),
          // §8 rule 2: state what is true, then what it means. The figure is the
          // elapsed time, which is what the legacy hub ticked every minute and
          // what the migrated home dropped.
          Text(
            'Opened 06:30 by Amina · 2h 14m',
            style: tokens.typography.numericBody.copyWith(
              color: tokens.colors.text.primary,
            ),
          ),
          SizedBox(height: tokens.spacing.s12),
          Row(
            children: <Widget>[
              AppButton(
                label: 'Close shift',
                tier: AppButtonTier.secondary,
                onPressed: () {},
              ),
              SizedBox(width: tokens.spacing.s12),
              AppButton(
                label: 'Shift history',
                tier: AppButtonTier.tertiary,
                onPressed: () {},
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Today's money: one hero figure, then the rest in flow.
///
/// **One `StatTile`, not four, and the arithmetic forced it before taste did.**
/// `StatRow` measures the widest figure at `numeric.hero` - 28px at weight 700 -
/// and `KES 910.00` is about 155 logical pixels of glyphs, so a tile needs ~187
/// with §2.3's padding. A 411-wide phone offers 371 after the page inset, which
/// fits **one**: four money tiles would stack into 436 pixels and eat the fold
/// they exist to occupy. §2.2 says the same thing in words - `numeric.hero` is
/// "the one figure a stat tile exists for" - so the takings are the hero and
/// everything supporting them is `numeric.body` in a `StatLine`.
///
/// The figures are 2026-08-16's from `25-daily-summary`, so this picture and that
/// one describe the same day of the same shop.
class _TodaySection extends StatelessWidget {
  const _TodaySection();

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const _SectionLabel('Today'),
        SizedBox(height: tokens.spacing.s8),
        const StatRow(
          tiles: <StatTile>[
            StatTile(
              label: 'Sales',
              value: 'KES 910.00',
              icon: Icons.payments_outlined,
              detail: 'taken today, across 2 shifts',
            ),
          ],
        ),
        SizedBox(height: tokens.spacing.s4),
        const StatLine(label: 'Transactions', value: '3'),
        const StatLine(label: 'Profit', value: 'KES 274.00'),
        const StatLine(label: 'Margin', value: '30.1%'),
      ],
    );
  }
}

/// What this device is still holding, in the three components §7 names for it.
///
/// §7's *Offline / read-only* row: "A persistent `Callout` in `status.info`, not
/// prose buried in a panel. The checkout queue counts belong in a `StatRow`, not
/// a five-line list." §7's *Long copy* row: "Anything over two lines that
/// explains *policy* rather than *the current state* goes in a `Disclosure`."
///
/// `checkout_evidence.dart` today is the five-line list, the buried prose and the
/// policy paragraph at once - and is still on `Theme.of(context).textTheme` with
/// a `SizedBox(height: 6)`, so it never reached the token layer at all. This is
/// the same information with each part in the component the document names:
/// the one fact that changes what a person does is the `Callout`, the counts are
/// a `StatRow`, and the policy is folded away.
///
/// **The counts are `StatLine`s inside the disclosure rather than a `StatRow`,
/// and that is a deviation worth naming.** §7 says `StatRow`; five hero figures
/// at one column on a phone is 500 pixels of mostly zeros, which is the failure
/// §5.2 describes for the catalog form. A column of `numeric.body` figures with a
/// shared right edge is what §2.2 specifies for exactly this shape. The
/// disagreement is real and belongs in the decision, not in a widget.
class _DeviceSection extends StatelessWidget {
  const _DeviceSection();

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Callout(
          status: AppStatus.info,
          message:
              '2 sales are saved on this device and have not reached the '
              'server yet. They are sent automatically.',
        ),
        SizedBox(height: tokens.spacing.s12),
        const Disclosure(
          summary: 'What this device holds',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              StatLine(label: 'Saved offline', value: '2'),
              StatLine(label: 'Submitting', value: '0'),
              StatLine(label: 'Awaiting confirmation', value: '0'),
              StatLine(label: 'Needs attention', value: '0'),
              StatLine(label: 'Confirmed', value: '11'),
            ],
          ),
        ),
      ],
    );
  }
}

/// Five destinations where there were eleven.
///
/// **What happened to the other six, one by one**, because a grid that shrank
/// without saying where things went is a grid nobody can check:
///
/// - *New sale* keeps §4.4's primary card. Unchanged.
/// - *View read-only catalog* and *Manage catalog* were the same destination at
///   two permission levels drawn as two places. They are **Catalog**, and which
///   controls it offers is the screen's own decision about the session's role -
///   which is how every other route here already decides it.
/// - *View daily summary*, *Find a receipt* → **Money**. Reconciliation and
///   period totals are already reachable from the summary, so this is the parent
///   those three were always children of.
/// - *View staff directory* → **Staff**.
/// - *Checkout settings*, *View activity log* → **Settings**.
/// - *Change business* and *Make default* leave the grid entirely. **Neither was
///   ever a destination**: `make-default-tenant` opens a confirmation, and when
///   the business already is the default the card becomes a permanently disabled
///   one reading "Default business" - a status indicator sitting in a navigation
///   grid. Both are account-level and belong beside *Sign out*.
///
/// `HomeDestination.status` carries each one's own condition rather than a
/// description of itself, which is what its doc comment asks for: "*3 unresolved
/// differences*, *shift open, 17 sales*, *2 waiting to send*". A destination with
/// nothing new to say is given no line, per the same comment.
List<HomeDestination> _destinations() => <HomeDestination>[
  HomeDestination(
    destinationKey: const ValueKey('start-checkout'),
    label: 'New sale',
    icon: Icons.point_of_sale,
    isPrimary: true,
    onPressed: () {},
  ),
  HomeDestination(
    destinationKey: const ValueKey('catalog'),
    label: 'Catalog',
    icon: Icons.inventory_2_outlined,
    status: '2 products out of stock',
    onPressed: () {},
  ),
  HomeDestination(
    destinationKey: const ValueKey('money'),
    label: 'Money',
    icon: Icons.query_stats,
    status: 'reconciled to today',
    onPressed: () {},
  ),
  HomeDestination(
    destinationKey: const ValueKey('staff'),
    label: 'Staff',
    icon: Icons.people_outline,
    status: '1 invitation not yet accepted',
    onPressed: () {},
  ),
  HomeDestination(
    destinationKey: const ValueKey('settings'),
    label: 'Settings',
    icon: Icons.tune,
    onPressed: () {},
  ),
];

/// The proposed route.
///
/// **The order is the argument.** An owner opens this app to find out what the
/// shop took, so the money is first and is above the fold at 411 x 891 with the
/// shift and the primary action beside it. Where they might *go* is below what
/// they came to *know* - which is the same ranking `tenant_routing_shell.dart`
/// already reasoned its way to for the shift panel, applied to the figures it
/// never had.
///
/// **What left the top of the screen.** The branding panel's tagline
/// ("Everything the corner needs"), the shield, and "Signed in as Owner" - about
/// 240 pixels of the 631 a phone body has, spent on things a person who just
/// signed in already knows. The role becomes the header's subtitle, which is one
/// word in the slot §7 gives it.
class _OwnerHomeProposal extends StatelessWidget {
  const _OwnerHomeProposal();

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final inset = AppScaffold.horizontalInset(tokens.spacing);
    final gap = tokens.density.sectionGap;
    final destinations = _destinations();
    return AppScaffold(
      title: 'Dev Corner Shop',
      subtitle: 'Owner',
      contentWidth: AppContentWidth.records,
      navigation: destinations,
      actions: <Widget>[
        AppButton(
          label: 'Sign out',
          tier: AppButtonTier.tertiary,
          onPressed: () {},
        ),
      ],
      body: Padding(
        padding: EdgeInsets.fromLTRB(inset, 0, inset, gap),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // §8 rule 1's own example, kept exactly as it is: this sentence is
              // already the shopkeeper's words and the rule cites it approvingly.
              const Callout(
                status: AppStatus.info,
                message: "Some screens aren't available yet.",
              ),
              SizedBox(height: gap),
              const _TodaySection(),
              SizedBox(height: gap),
              const _ShiftSection(),
              SizedBox(height: gap),
              if (!HomeNavigation.showsMenu(
                MediaQuery.sizeOf(context).width,
              )) ...<Widget>[
                const _SectionLabel('Go to'),
                SizedBox(height: tokens.spacing.s8),
                HomeNavigation.drawer(destinations: destinations),
                SizedBox(height: gap),
              ],
              const _DeviceSection(),
            ],
          ),
        ),
      ),
    );
  }
}

void main() {
  screenshotCase(
    '99-owner-home-proposal',
    build: () => const _OwnerHomeProposal(),
  );
}
