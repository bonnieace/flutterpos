/// `ConfirmDialog`: `design.md` §5.1's row for the pattern §7 calls *destructive
/// action*, and the first of the five components §11 step 7 was blocked on.
///
/// **§7 states the pattern and this file is it, in one place instead of twelve.**
/// *"Never immediate. `action.destructive` opens a `ConfirmDialog` naming the
/// specific record and the specific consequence: 'Clear this sale — 3 items, KES
/// 135.00 will be discarded. Nothing is recorded.'"* Twelve `AlertDialog`s across
/// nine files each rebuilt that shape by hand, and every one of them made the same
/// four decisions again - which surface, which radius, which order the two buttons
/// go in, and what tier the confirm takes.
///
/// **The confirm's tier is inherited, not chosen, and that is the one rule here
/// worth defending.** A dialog opened by a `destructive` button confirms with
/// `destructive`; one opened by a `primary` button confirms with `primary`. §8 rule
/// 4 asks that "the verb persists - the button says *Correct*, the dialog says
/// *Correct*, the confirmation says *Corrected*", and a confirm that changed
/// *appearance* on the way would break that rule in shape while keeping it in
/// words. It also removes the one decision twelve call sites were each making
/// differently.
///
/// **§7 used to ask for a *filled* destructive confirm and §2.1 defines none.**
/// That contradiction was live for a day; `design.md` **v0.6** withdrew the word on
/// 2026-08-16 rather than adding a fifth action role, so the confirm is §2.1's
/// outlined destructive tier - which is what the app already drew.
///
/// **It refuses children, deliberately.** Three of the twelve dialogs it replaces
/// hold *fields* - correcting a product, adjusting stock, changing the currency -
/// and a component that took a `Widget` body would absorb them and quietly become
/// "any dialog". They are a different component, `AppDialog`, which does not exist;
/// until it does they stay `AlertDialog`s and this one takes strings.
///
/// **The state matrix is three rows, not §5's nine.** `enabled`, `loading` - the
/// confirm has been pressed and the write is in flight - and `disabled`, which is a
/// confirm that may not be pressed yet. `hover`, `focus-visible` and `pressed`
/// belong to the two `AppButton`s inside it and arrive with them; `error`,
/// `read-only` and `empty` have no meaning for a question.
library;

import 'package:flutter/material.dart';

import 'buttons.dart';
import 'tokens.dart';

/// A question with two answers, one of which does something.
///
/// Built by [showConfirmDialog] rather than by a call site, so the route, the
/// scrim and the return value are decided here too.
final class ConfirmDialog extends StatelessWidget {
  const ConfirmDialog({
    super.key,
    required this.title,
    required this.consequence,
    required this.confirmLabel,
    this.stillTrue,
    this.cancelLabel = 'Cancel',
    this.tier = AppButtonTier.destructive,
    this.loading = false,
    this.onConfirm,
    this.onCancel,
    this.confirmKey,
    this.cancelKey,
  });

  /// The question, as a verb phrase matching the control that opened it.
  ///
  /// §8 rule 4. "Clear this sale?" is opened by *Clear this sale*, and the
  /// confirmation afterwards says *Cleared*. This widget cannot enforce that and
  /// its callers must.
  final String title;

  /// What will happen, naming the **specific record** and the **specific
  /// consequence**. §7 gives the worked example and it is worth copying: "3
  /// items, KES 135.00 will be discarded."
  final String consequence;

  /// What is **not** affected, where that is worth saying.
  ///
  /// §8 rule 6 - "say what is still true" - which this app is already good at:
  /// "Nothing has been saved yet, so no record is lost." Optional, because on a
  /// dialog that reverses nothing there is nothing to reassure about.
  final String? stillTrue;

  /// The label on the button that does the thing. A verb phrase, §5.2.
  final String confirmLabel;

  /// The label on the button that does not.
  ///
  /// Defaulted rather than required, because "Cancel" is right for most of the
  /// twelve and a call site with a better word - "Keep it" - says so.
  final String cancelLabel;

  /// The tier of the control that opened this dialog. See the library note: it is
  /// inherited so the verb persists in shape as well as in words.
  final AppButtonTier tier;

  /// §2.1's loading row on the confirm: the container is held, the label becomes a
  /// spinner, the width is frozen. The cancel is disabled while it runs, because a
  /// write in flight cannot be called off from here.
  final bool loading;

  /// Null disables the confirm - a question whose answer is not available yet.
  final VoidCallback? onConfirm;

  final VoidCallback? onCancel;

  /// Keys on the two buttons, for a call site whose tests already address them.
  ///
  /// **A component would normally own its own keys**, and this one does by
  /// default. These exist because the eight dialogs it replaces were each keyed
  /// for their own screen - `bulk-catalog-confirm`, `product-stock-confirm` - and
  /// their tests tap those. Renaming eight screens' keys to centralise them would
  /// be churn in the suite for no assertion gained, and a key is the call site's
  /// identity rather than the component's.
  final Key? confirmKey;
  final Key? cancelKey;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return AlertDialog(
      // §2.1: "dialogs, menus, bottom sheets". The theme already paints
      // `dialogTheme` this colour; naming it here is what makes the component
      // independent of a theme that may not be this app's - a dialog is pushed
      // onto a route with its own context, which is exactly where a token read
      // through `componentOf` earns its fallback.
      backgroundColor: tokens.colors.surface.overlay,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        // §2.3's row for "dialogs, bottom sheets".
        borderRadius: BorderRadius.circular(tokens.radius.lg),
      ),
      insetPadding: EdgeInsets.all(tokens.spacing.s24),
      titlePadding: EdgeInsets.fromLTRB(
        tokens.spacing.s24,
        tokens.spacing.s24,
        tokens.spacing.s24,
        tokens.spacing.s12,
      ),
      contentPadding: EdgeInsets.symmetric(horizontal: tokens.spacing.s24),
      actionsPadding: EdgeInsets.all(tokens.spacing.s24),
      title: Text(
        title,
        style: tokens.typography.titleMedium.copyWith(
          color: tokens.colors.text.primary,
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              consequence,
              style: tokens.typography.bodyLarge.copyWith(
                color: tokens.colors.text.secondary,
              ),
            ),
            if (stillTrue case final reassurance?) ...<Widget>[
              SizedBox(height: tokens.spacing.s12),
              Text(
                reassurance,
                style: tokens.typography.bodyMedium.copyWith(
                  color: tokens.colors.text.tertiary,
                ),
              ),
            ],
          ],
        ),
      ),
      // **A `Wrap`, not a `Row`**, and for the reason the staff forms already
      // recorded: two 48-high pills with verb phrases on them do not fit a phone
      // beside each other, and a `Row` answers that by overflowing. `end`
      // alignment keeps the confirm at the trailing edge on one line and puts it
      // on top when they stack, which is the order a person reads them in.
      actions: <Widget>[
        Wrap(
          alignment: WrapAlignment.end,
          spacing: tokens.spacing.s12,
          runSpacing: tokens.spacing.s8,
          children: <Widget>[
            AppButton(
              key: cancelKey ?? const ValueKey('confirm-dialog-cancel'),
              label: cancelLabel,
              // **`tertiary`, which is what all eight of the dialogs this
              // replaces already used** - not `secondary`, which §2.1 calls "the
              // ordinary case" and which a first reading of the row suggests.
              // The tree had one answer at eight sites and it is the better one:
              // a cancel is the *absence* of the action, and giving it an outline
              // makes a dialog read as two choices of equal weight when only one
              // of them does anything.
              tier: AppButtonTier.tertiary,
              onPressed: loading ? null : onCancel,
            ),
            AppButton(
              key: confirmKey ?? const ValueKey('confirm-dialog-confirm'),
              label: confirmLabel,
              tier: tier,
              loading: loading,
              onPressed: onConfirm,
            ),
          ],
        ),
      ],
    );
  }
}

/// Asks [title] and answers whether it was confirmed.
///
/// Returns `false` rather than null when the dialog is dismissed without an
/// answer, so a call site is never made to write `confirmed == true` to guard
/// against a barrier tap. **Not confirming and dismissing are the same outcome**
/// - nothing happens - and giving them two representations is how a null slips
/// through as a yes.
///
/// **The barrier is dismissible only for a destructive question**, which is a
/// decision rather than Material's default. On a destructive dialog a stray tap
/// outside lands on *cancel*, which is the safe answer, so being able to leave by
/// accident costs nothing. On any other tier the safe answer is not obvious - a
/// `primary` confirm sits at the end of a flow somebody has typed into - so it
/// must be answered rather than escaped.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String consequence,
  required String confirmLabel,
  String? stillTrue,
  String cancelLabel = 'Cancel',
  AppButtonTier tier = AppButtonTier.destructive,
  Key? confirmKey,
  Key? cancelKey,
}) async {
  final answer = await showDialog<bool>(
    context: context,
    barrierDismissible: tier == AppButtonTier.destructive,
    barrierColor: AppTokens.componentOf(context).colors.surface.scrim,
    builder: (context) => ConfirmDialog(
      title: title,
      consequence: consequence,
      stillTrue: stillTrue,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      tier: tier,
      confirmKey: confirmKey,
      cancelKey: cancelKey,
      onConfirm: () => Navigator.of(context).pop(true),
      onCancel: () => Navigator.of(context).pop(false),
    ),
  );
  return answer ?? false;
}
