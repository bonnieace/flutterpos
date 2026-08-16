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
import 'package:flutter_application_1/ui/buttons.dart';
import 'package:flutter_application_1/ui/states.dart';
import 'package:flutter_application_1/ui/tokens.dart';

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
  const _Host({required this.title, this.hint, this.action});

  final String title;
  final String? hint;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppTokens.componentOf(context).colors.surface.base,
    body: EmptyState(title: title, hint: hint, action: action),
  );
}
