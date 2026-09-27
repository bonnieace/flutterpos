/// `LoadingState` and `ErrorState`'s matrices, per `claude.md` hard rule 5 and
/// §10 — the other two of §5.1's three full-page states.
///
/// `EmptyState`'s three captures are in `empty_state_test.dart` and stay there;
/// splitting the file rather than folding these in keeps the mark's pictures,
/// which are the only picture §6.4's asset 6 has, in a file named after it.
///
/// **The loading captures do not settle, and that is not a workaround.**
/// `CircularProgressIndicator` rotates forever, so `pumpAndSettle` would time
/// out — which is itself the difference between this state and the other two:
/// an empty state and a failure are still, and a wait is not. The frame these
/// write is therefore one arbitrary rotation, so **a loading image moving
/// between runs means nothing** and only its layout and its sentence are
/// evidence.
library;

import 'package:flutter/material.dart';
import 'package:uzapay_pos/ui/buttons.dart';
import 'package:uzapay_pos/ui/states.dart';
import 'package:uzapay_pos/ui/status.dart';
import 'package:uzapay_pos/ui/tokens.dart';

import 'harness.dart';

void main() {
  screenshotCase(
    '96-loadingstate-short',
    build: () => const _LoadingHost(message: 'Opening the business.'),
    settle: false,
    fullPage: false,
  );

  screenshotCase(
    '96-loadingstate-long',
    // The longest sentence any call site passes today, so the picture shows
    // what a wrapping message does to the column rather than only the happy
    // one-liner.
    build: () =>
        const _LoadingHost(message: 'Reading active and suspended businesses.'),
    settle: false,
    fullPage: false,
  );

  screenshotCase(
    '96-errorstate-full',
    // §7's worked example, exactly as that section writes it: "2 sale lines
    // could not be read, so they moved no stock."
    build: () => _ErrorHost(
      badgeLabel: 'Not read',
      statement: '2 sale lines could not be read.',
      identifier: 'SALE-2026-0042',
      detail: 'The device lost its connection part-way through the read.',
      stillTrue: 'They moved no stock, and the sale itself is unchanged.',
      actions: <Widget>[
        AppButton(
          label: 'Retry',
          tier: AppButtonTier.primary,
          onPressed: () {},
        ),
        AppButton(label: 'Sign out', onPressed: () {}),
      ],
    ),
    fullPage: false,
  );

  screenshotCase(
    '96-errorstate-statement-only',
    // What the route guard's own default draws, which is what most of the app
    // gets: no identifier, because the thing that would not read is a page
    // rather than a record.
    build: () => const _ErrorHost(
      badgeLabel: 'Not read',
      statement: 'This page could not be read.',
      stillTrue: 'Nothing was changed.',
    ),
    fullPage: false,
  );

  screenshotCase(
    '96-errorstate-neutral',
    // The dead end that is not a fault. `problem` and `neutral` differ in hue
    // *and* in the word on the badge, which is §9's rule; this pair is the
    // picture that shows both changing together.
    build: () => _ErrorHost(
      status: AppStatus.neutral,
      badgeLabel: 'Unavailable',
      statement: 'Platform administrator access is not available.',
      stillTrue: 'Your businesses are unaffected.',
      actions: <Widget>[AppButton(label: 'Sign out', onPressed: () {})],
    ),
    fullPage: false,
  );
}

final class _LoadingHost extends StatelessWidget {
  const _LoadingHost({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppTokens.componentOf(context).colors.surface.base,
    body: LoadingState(message: message),
  );
}

final class _ErrorHost extends StatelessWidget {
  const _ErrorHost({
    required this.badgeLabel,
    required this.statement,
    this.identifier,
    this.detail,
    this.stillTrue,
    this.status = AppStatus.problem,
    this.actions = const <Widget>[],
  });

  final String badgeLabel;
  final String statement;
  final String? identifier;
  final String? detail;
  final String? stillTrue;
  final AppStatus status;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppTokens.componentOf(context).colors.surface.base,
    body: ErrorState(
      badgeLabel: badgeLabel,
      statement: statement,
      identifier: identifier,
      detail: detail,
      stillTrue: stillTrue,
      status: status,
      actions: actions,
    ),
  );
}
