/// `EmptyState`'s matrix, per `claude.md` hard rule 5 and §10 — and the only
/// picture there is of `design.md` §6.4's asset **6**, which is drawn rather
/// than sourced.
///
/// **The mark is captured at rest, and that is the honest limit of a
/// screenshot.** §10 says it in as many words: "the harness cannot see motion.
/// Screenshots prove layout and copy; they say nothing about whether a spring is
/// interruptible." What these prove is that the box is drawn, sized and coloured
/// from the theme. That it draws *on* — 240ms of outline, then the lid tipping
/// on `spring.gentle`, then stillness — is a device check.
///
/// Three states: with everything §7's pattern allows, with only the statement,
/// and the mark on its own at the size a call site gets.
library;

import 'package:flutter/material.dart';
import 'package:uzapay_pos/ui/buttons.dart';
import 'package:uzapay_pos/ui/states.dart';
import 'package:uzapay_pos/ui/tokens.dart';

import 'harness.dart';

void main() {
  screenshotCase(
    '96-emptystate-full',
    build: () => _Host(
      title: 'No products yet',
      hint: 'Add one from Manage catalog, or import a spreadsheet.',
      action: AppButton(
        label: 'Add a product',
        tier: AppButtonTier.primary,
        onPressed: () {},
      ),
    ),
    fullPage: false,
  );

  screenshotCase(
    '96-emptystate-statement-only',
    // What a cashier sees: the same read, and no route out of it, because
    // stocking the catalog is not their role. §7 makes the action conditional
    // on "if the person can" and this is the other side of that condition.
    build: () => const _Host(title: 'No products on this device yet'),
    fullPage: false,
  );

  // **One capture per illustration, in the copy its call sites actually use.**
  // Thirteen drawings cover the twenty `EmptyState` call sites; several are
  // shared, which is the point - a person who learns what the wallet means on
  // the expenses page should meet the same wallet under a category heading.
  //
  // These exist to be looked at side by side. An illustration that reads on its
  // own and wrong beside the other twelve is still wrong, and that is a
  // judgement no single screen's capture can support.
  for (final scene in _illustrated) {
    screenshotCase(
      '96d-illustration-${scene.asset.replaceAll('.svg', '')}',
      build: () => _Host(
        title: scene.title,
        hint: scene.hint,
        illustration: scene.asset,
      ),
      fullPage: false,
      // One viewport: these are being judged as artwork, and the mark is a
      // fixed 168 square that does not respond to width. The layout around it
      // is already photographed by the three cases above.
      viewports: <ScreenshotViewport>[screenshotViewports.first],
    );
  }

  screenshotCase(
    '96-emptystate-no-action',
    build: () => const _Host(
      title: 'No closed shifts yet',
      hint: 'A shift appears here once it has been closed.',
    ),
    fullPage: false,
  );
}

final class _Host extends StatelessWidget {
  const _Host({required this.title, this.hint, this.action, this.illustration});

  final String title;
  final String? hint;
  final Widget? action;
  final String? illustration;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppTokens.componentOf(context).colors.surface.base,
    body: EmptyState(
      title: title,
      hint: hint,
      action: action,
      illustration: illustration,
    ),
  );
}


/// The thirteen drawings, with the copy of a call site that uses each.
const List<_Scene> _illustrated = <_Scene>[
  _Scene(
    'no-data.svg',
    'No sales yet',
    'A sale appears here once it has been confirmed.',
  ),
  _Scene(
    'file-search.svg',
    'No matching sales',
    'Try another date or staff member.',
  ),
  _Scene('empty.svg', 'No products yet', null),
  _Scene(
    'empty-wallet.svg',
    'Nothing recorded this month',
    'Record rent, wages, fuel or a repair and it counts against profit from '
        'then on.',
  ),
  _Scene(
    'schedule.svg',
    'No shift is open',
    'Open one to start selling.',
  ),
  _Scene(
    'access-denied.svg',
    'Expenses are not shown for this role',
    'An owner or an administrator can record and review them.',
  ),
  _Scene('approve.svg', 'No pending business requests', null),
  _Scene(
    'team.svg',
    'No staff yet',
    'Invite somebody to give them access to this business.',
  ),
  _Scene(
    'calendar.svg',
    'This month has not started',
    'Choose a month that has.',
  ),
  _Scene(
    'printing-invoices.svg',
    'No receipts are waiting',
    'A receipt appears here only if it did not reach the printer.',
  ),
  // Three the twenty wired call sites do not reach yet: the stock feeds, the
  // ledgers of record and the till's own cart all answer an empty read with a
  // bare sentence rather than an `EmptyState`, so there is nowhere to hang a
  // drawing until that changes. Captured anyway, because the decision to
  // convert them should be taken looking at what it would buy.
  _Scene(
    'logistics.svg',
    'No stock movement has been recorded',
    'Receiving, selling or adjusting stock puts an entry here.',
  ),
  _Scene(
    'my-files.svg',
    'No event has been recorded for this business',
    'Every change worth answering for is written here as it happens.',
  ),
  _Scene(
    'empty-cart.svg',
    'No items yet',
    'Add a product to start the sale.',
  ),
];

/// One drawing and the words it sits under.
final class _Scene {
  const _Scene(this.asset, this.title, this.hint);

  final String asset;
  final String title;
  final String? hint;
}
