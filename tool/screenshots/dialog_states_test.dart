/// `ConfirmDialog`'s state matrix, per `claude.md` hard rule 5 and §10: a
/// component is not done until each of its states appears in the harness.
///
/// **Three rows, not §5's nine, and the missing six are missing on purpose.**
/// `enabled`, `loading` — the confirm has been pressed and the write is in flight
/// — and `disabled`, a question whose answer is not available yet. `hover`,
/// `focus-visible` and `pressed` belong to the two `AppButton`s inside it and are
/// already photographed in `90-appbutton-*`; `error`, `read-only` and `empty` have
/// no meaning for a question.
///
/// **Captured at both bands, which is a lesson rather than a default.** Step 4
/// shipped a `Disclosure` whose summary truncated on a phone and nobody saw it for
/// two days, because that component's matrix was `web` only. A dialog is the
/// sharpest case for the same failure: an `AlertDialog` insets itself from the
/// window and then pads its own content, so a phone gives it roughly 200 logical
/// pixels where a page gives about 250 — and the two buttons here are 48-high
/// pills with verb phrases on them.
library;

import 'package:flutter/material.dart';
import 'package:flutter_application_1/ui/buttons.dart';
import 'package:flutter_application_1/ui/dialogs.dart';
import 'package:flutter_application_1/ui/tokens.dart';

import 'harness.dart';

void main() {
  for (final tier in AppButtonTier.values) {
    screenshotCase(
      '94-confirmdialog-${tier.name}',
      build: () => _Dialog(tier: tier),
      fullPage: false,
    );
  }

  screenshotCase(
    '94-confirmdialog-loading',
    // §2.1's loading row is a spinner, which never reaches a quiet frame.
    settle: false,
    build: () => const _Dialog(loading: true),
    fullPage: false,
  );

  screenshotCase(
    '94-confirmdialog-disabled',
    build: () => const _Dialog(answerable: false),
    fullPage: false,
  );

  screenshotCase(
    '94-confirmdialog-without-reassurance',
    build: () => const _Dialog(stillTrue: null),
    fullPage: false,
  );
}

/// §7's own worked example, drawn.
///
/// The strings are that section's verbatim — *"Clear this sale — 3 items, KES
/// 135.00 will be discarded. Nothing is recorded."* — so the picture is of the
/// pattern the document specifies rather than of copy invented for a capture.
final class _Dialog extends StatelessWidget {
  const _Dialog({
    this.tier = AppButtonTier.destructive,
    this.loading = false,
    this.answerable = true,
    this.stillTrue = 'Nothing has been saved yet, so no record is lost.',
  });

  final AppButtonTier tier;
  final bool loading;
  final bool answerable;
  final String? stillTrue;

  @override
  Widget build(BuildContext context) => Scaffold(
    // **The ground behind the dialog, and it is not decoration.** Pumped as a
    // bare `home` the capture came out on the binding's white default, which
    // reads as though §2.1's scrim - black at 60% - were white. A picture that
    // misleads about a colour is worse than no picture.
    backgroundColor: AppTokens.componentOf(context).colors.surface.base,
    body: _dialog(),
  );

  Widget _dialog() => ConfirmDialog(
    title: 'Clear this sale?',
    consequence:
        'Every item is removed and the payment method is cleared. 3 items, '
        'KES 135.00 will be discarded.',
    stillTrue: stillTrue,
    confirmLabel: 'Clear it',
    cancelLabel: 'Keep it',
    tier: tier,
    loading: loading,
    onConfirm: answerable ? () {} : null,
    onCancel: () {},
  );
}
