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
import 'status.dart';
import 'tokens.dart';

/// One dialog surface, worn by both components in this file.
///
/// **Extracted rather than copied, and that is §1's own complaint.** The four
/// values below - `surface.overlay`, `radius.lg`, `space.24`, and the trailing
/// `Wrap` of actions - were about to be written a second time for [AppDialog],
/// which is how a system ends up with two dialogs that differ by four pixels
/// nobody chose. `ConfirmDialog`'s rendering is unchanged by this: it passes
/// no [maximumWidth] and the arithmetic above it is identical.
final class _DialogFrame extends StatelessWidget {
  const _DialogFrame({
    required this.content,
    required this.actions,
    this.title,
    this.maximumWidth,
    this.scrollable = true,
  });

  final String? title;
  final Widget content;
  final List<Widget> actions;

  /// Null means "as wide as `AlertDialog` would make it", which is what
  /// `ConfirmDialog` has always been.
  final double? maximumWidth;

  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    Widget body = content;
    if (scrollable) body = SingleChildScrollView(child: body);
    if (maximumWidth case final limit?) {
      body = ConstrainedBox(
        constraints: BoxConstraints(maxWidth: limit),
        child: body,
      );
    }
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
      title: title == null
          ? null
          : Text(
              title!,
              style: tokens.typography.titleMedium.copyWith(
                color: tokens.colors.text.primary,
              ),
            ),
      content: body,
      // A question remains one horizontal sentence at every width: safe answer
      // first, committing or destructive answer last. `AppActionRow` lets long
      // labels contract without changing that order into a vertical stack.
      actions: actions.isEmpty
          ? null
          : <Widget>[AppActionRow(actions: actions)],
    );
  }
}

/// A dialog that holds something other than a question.
///
/// **§5.1 does not list this component and that is recorded rather than worked
/// around.** `DESIGN-PROPOSAL-COMPONENTS.md` §1 split it out deliberately:
/// *"`ConfirmDialog` refuses children — it takes strings and two actions — and
/// the three form-bearing dialogs stay `AlertDialog` until somebody specifies
/// `AppDialog`. Flagging this rather than quietly widening the component is the
/// whole point of writing it down first."* This is that specification, and
/// every value in it is read off a row `design.md` already has.
///
/// **The one measurement that had to be derived is the width, and §4.3 supplies
/// it.** That section's `Form` row is "single column, **720 max**" and §4.2
/// gives "reading and forms" the same 720, so a dialog holding a form takes
/// [AppLayout.reading] rather than a number of its own. What it replaces is a
/// hardcoded `SizedBox(width: 440)` in the business switcher — the only width
/// any of these dialogs ever stated, chosen by one call site for itself.
///
/// **Its scrim is not dismissible by default**, which is the other half of the
/// decision `ConfirmDialog` records. A stray tap outside a *question* lands on
/// cancel, which is safe; a stray tap outside a **form** throws away everything
/// typed into it. `DESIGN-PROPOSAL-COMPONENTS.md` §1's open question 1 proposed
/// exactly this split and it is applied here.
///
/// **The state matrix is the child's.** A container for a form has no `hover`,
/// `pressed`, `loading` or `error` of its own — every one of those belongs to
/// the fields and buttons inside it, which are `AppTextField`s and `AppButton`s
/// and arrive with their own. What this component varies is whether it has a
/// title and whether it has actions, and the harness photographs both.
final class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    required this.content,
    this.title,
    this.actions = const <Widget>[],
    this.scrollable = true,
  });

  /// The verb, matching the control that opened it. §8 rule 4.
  ///
  /// Optional, because one of the four dialogs this replaces is a form that
  /// carries its own heading and would otherwise say the same word twice —
  /// which is §7's "title appears once" arriving in a dialog.
  final String? title;

  /// The form, the list, or whatever else is not a sentence.
  ///
  /// **Named `content` rather than `child`, which is not a style choice.**
  /// `sort_child_properties_last` requires a `child` argument to be written
  /// last, and on these call sites the child is a hundred-line form with two
  /// buttons after it - so the lint would push [actions] above a block nobody
  /// scrolls past. `AlertDialog` calls the same slot `content` for the same
  /// reason.
  final Widget content;

  /// Laid out exactly as `ConfirmDialog`'s are. Empty where the child owns its
  /// own controls, which is the set-default form's arrangement.
  final List<Widget> actions;

  /// Whether this component scrolls the child.
  ///
  /// **True by default, so a call site deletes its own `SingleChildScrollView`
  /// rather than nesting one.** A form in a dialog on a phone is taller than
  /// the window more often than not, and two scroll views inside each other is
  /// an unbounded-height error rather than a cosmetic problem.
  final bool scrollable;

  /// §4.3's `Form` row - "single column, 720 max" - which is also §4.2's row
  /// for "reading and forms". Not a number this component chose.
  static double get maximumWidth => AppLayout.contract.reading;

  @override
  Widget build(BuildContext context) => _DialogFrame(
    title: title,
    content: content,
    actions: actions,
    maximumWidth: maximumWidth,
    scrollable: scrollable,
  );
}

/// Opens [builder] as a dialog, with this system's scrim behind it.
///
/// **The scrim is the reason this exists rather than a bare `showDialog`.**
/// §2.1 has a `surface.scrim` role and Material's default is `black54`; four
/// call sites were each getting the second one by saying nothing.
Future<T?> showAppDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool barrierDismissible = false,
}) => showDialog<T>(
  context: context,
  barrierDismissible: barrierDismissible,
  barrierColor: AppTokens.componentOf(context).colors.surface.scrim,
  builder: builder,
);

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
    return _DialogFrame(
      title: title,
      content: Column(
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
      actions: <Widget>[
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

/// One answer, because there is only one: an outcome a person has to see.
///
/// **The third way this app reports a write, and the narrowest.** A `Callout`
/// is for a sentence about the state of a page that stays true while the page
/// is up. `AppSnackBar` is for a momentary answer nobody has to act on. This is
/// for the outcome in between — one a person **must** deal with before carrying
/// on, and which a snack bar would take off the screen before they had.
///
/// **It is a modal on purpose and that is the cost it is worth.** The till's
/// saved-sale confirmation used to be an inline `Callout` that stayed until it
/// was closed, which pushed the cart down the screen for every sale — the
/// common case paying the price of the rare one. Success is a snack bar now;
/// this is what the rare one gets instead, so the sale screen keeps its shape
/// and the exception still cannot be missed.
///
/// It carries the status the way every other notice surface does: §2.1's
/// container, glyph and word, out of the [AppNotice] the caller already built.
final class NoticeDialog extends StatelessWidget {
  const NoticeDialog({
    super.key,
    required this.title,
    required this.notice,
    this.stillTrue,
    this.dismissLabel = 'Close',
    this.onDismiss,
    this.dismissKey,
    this.actionLabel,
    this.onAction,
    this.actionKey,
    this.optOutLabel,
    this.onOptOut,
    this.optOutKey,
  });

  /// What happened, as a phrase rather than a question. §8 rule 4: this dialog
  /// asks nothing, so its title states rather than asks.
  final String title;

  /// The outcome itself, which decides the container and the glyph.
  final AppNotice notice;

  /// What is **not** affected. §8 rule 6, and it matters more here than on a
  /// question: this dialog exists because something went sideways, and the
  /// first thing a person needs is the bound on it.
  final String? stillTrue;

  final String dismissLabel;
  final VoidCallback? onDismiss;
  final Key? dismissKey;

  /// The one thing that fixes what [notice] reports, when there is one - *Set
  /// up printer* beside a receipt that had nowhere to go. It takes the primary
  /// tier, and the dismissal steps down to secondary beside it.
  final String? actionLabel;
  final VoidCallback? onAction;
  final Key? actionKey;

  /// *Don't show again*, for a notice a person may reasonably not want. Under
  /// the reassurance rather than in the action row: the row never wraps, and a
  /// third button there would squeeze all three labels on a phone.
  final String? optOutLabel;
  final VoidCallback? onOptOut;
  final Key? optOutKey;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final hasAction = actionLabel != null;
    return _DialogFrame(
      title: title,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // The `Callout` rather than a bare paragraph, so the status reaches a
          // reader as a container and a glyph rather than as the tone of the
          // sentence. The same component the page would have used inline.
          Callout(
            key: const ValueKey('notice-dialog-notice'),
            status: notice.status,
            message: notice.message,
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
          if (optOutLabel case final label?) ...<Widget>[
            SizedBox(height: tokens.spacing.s8),
            AppButton(
              key: optOutKey ?? const ValueKey('notice-dialog-opt-out'),
              label: label,
              tier: AppButtonTier.tertiary,
              onPressed: onOptOut,
            ),
          ],
        ],
      ),
      actions: <Widget>[
        AppButton(
          key: dismissKey ?? const ValueKey('notice-dialog-dismiss'),
          label: dismissLabel,
          // `primary` while it is the only control here, and §2.1 permits
          // exactly one primary per region. A lone `tertiary` would read as
          // though the dialog had a second answer somewhere off screen.
          tier: hasAction ? AppButtonTier.secondary : AppButtonTier.primary,
          onPressed: onDismiss,
        ),
        if (actionLabel case final label?)
          AppButton(
            key: actionKey ?? const ValueKey('notice-dialog-action'),
            label: label,
            tier: AppButtonTier.primary,
            onPressed: onAction,
          ),
      ],
    );
  }
}

/// Which way out of a [NoticeDialog] a person took.
enum NoticeDialogChoice { dismissed, action, optedOut }

/// Shows [notice] as a modal that has to be dismissed before anything else.
///
/// **The barrier does not dismiss it.** Every other route out of this dialog is
/// a deliberate press, because the whole reason it is a modal rather than a
/// snack bar is that the outcome must not be able to disappear unnoticed.
///
/// **It answers with the press rather than acting on it.** The dialog is off
/// the screen before the caller opens anything, so a route pushed for
/// [actionLabel] lands on the page the dialog came from, not over the dialog.
Future<NoticeDialogChoice> showAppNoticeDialog(
  BuildContext context, {
  required String title,
  required AppNotice notice,
  String? stillTrue,
  String dismissLabel = 'Close',
  Key? dismissKey,
  String? actionLabel,
  Key? actionKey,
  String? optOutLabel,
  Key? optOutKey,
}) async {
  final choice = await showDialog<NoticeDialogChoice>(
    context: context,
    barrierDismissible: false,
    barrierColor: AppTokens.componentOf(context).colors.surface.scrim,
    builder: (context) => NoticeDialog(
      title: title,
      notice: notice,
      stillTrue: stillTrue,
      dismissLabel: dismissLabel,
      dismissKey: dismissKey,
      onDismiss: () => Navigator.of(context).pop(NoticeDialogChoice.dismissed),
      actionLabel: actionLabel,
      actionKey: actionKey,
      onAction: () => Navigator.of(context).pop(NoticeDialogChoice.action),
      optOutLabel: optOutLabel,
      optOutKey: optOutKey,
      onOptOut: () => Navigator.of(context).pop(NoticeDialogChoice.optedOut),
    ),
  );
  // A system back press is the one way out that is not a button.
  return choice ?? NoticeDialogChoice.dismissed;
}
