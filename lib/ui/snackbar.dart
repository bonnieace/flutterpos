/// `AppSnackBar`: the transient half of [AppNotice], for a write whose answer
/// arrives after the surface that asked for it has gone.
///
/// **It exists because a sheet cannot hold its own confirmation.** [Callout] is
/// §5.1's row for a notice that *stays* — it is part of a page, and it is read
/// where it sits. A sheet that closes on success has nowhere to put one: the
/// widget carrying it is being torn down at the moment there is finally
/// something to say. So the sentence has to land on the surface underneath, and
/// that is what this is for.
///
/// **It decides nothing that [Callout] has not already decided.** Both take an
/// [AppNotice], both read the status triple from §2.1, both draw a container
/// plus a glyph plus the words, and neither tints the prose — §2.1's rule is
/// that the status is the container, the icon and the word, not that every
/// word is coloured. A call site names *what happened* and never picks a
/// colour, which is the whole argument [AppNotice] makes one level up.
///
/// **`radius.md`, and `OPEN_QUESTIONS.md` decision 26a is why it is not a
/// pill.** That decision lists "the snack bar" among the components that
/// deliberately do not take `radius.pill`, and names no replacement. `md` is
/// §2.3's row for "cards, rows, sheets" and is what [Callout] already reads, so
/// the two notices that carry the same sentence are the same shape rather than
/// two shapes for one meaning.
///
/// **The state matrix is the five statuses**, plus with and without an action.
/// A snack bar has no hover, no focus and no disabled of its own; the action it
/// may carry brings those, and it is an `AppButton`, which has them already.
library;

import 'package:flutter/material.dart';

import 'status.dart';
import 'tokens.dart';

/// Shows [notice] over whatever is on screen, and replaces any notice already
/// up.
///
/// **Every write outcome comes here, at the product owner's direction on
/// 2026-09-03.** There used to be a `noticeIsTransient` rule beside this: a
/// confirmation withdrew itself and everything else - a refusal, an unknown
/// outcome, an offline skip - stayed inline in a [Callout], on the argument
/// that a sentence naming a next step must not disappear before it is read.
/// The direction reverses that. A page reports what it did over itself, and
/// the only thing left inline is a **field saying what is wrong with what was
/// typed into it** - which belongs beside the field, not over the page, and is
/// not what this is for.
///
/// The dwell still differs by status: see [AppSnackBar.dwell] and its longer
/// sibling, so an answer somebody has to act on stays up longer than one they
/// only have to see.
///
/// **Replaces rather than queues, and that is the decision.** Material's
/// messenger queues, so two writes in quick succession would show the first
/// answer for its full dwell before the second appeared — which on a till means
/// reading a stale sentence about money. The last answer is the true one.
///
/// Returns null where there is no [ScaffoldMessenger] above [context] — which
/// is a widget test pumping this component bare rather than a state to design
/// for, so it degrades silently instead of throwing.
ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? showAppSnackBar(
  BuildContext context,
  AppNotice notice, {
  Widget? action,
  Duration? dwell,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return null;
  final tokens = AppTokens.componentOf(context);
  messenger.removeCurrentSnackBar();
  return messenger.showSnackBar(
    SnackBar(
      // The surface is drawn by [AppSnackBar] rather than by Material, so it
      // takes §2.1's status container instead of the theme's inverse grey. The
      // three overrides below are what stop Material painting its own box
      // around this one.
      backgroundColor: Colors.transparent,
      elevation: 0,
      padding: EdgeInsets.zero,
      behavior: SnackBarBehavior.floating,
      duration: dwell ?? AppSnackBar.dwellFor(notice.status),
      margin: EdgeInsets.all(tokens.spacing.s16),
      content: ConstrainedBox(
        // **Bounded at §4.2's reading width, and it is a defect fix as well as
        // a typographic one.** A floating snack bar spans the whole window, so
        // on the two-pane till it lay across the bottom of *both* panes - and
        // the cart's `Save` control is at the bottom of the right-hand one. A
        // cashier ringing up two sales in a row had the confirmation for the
        // first one sitting on the button for the second. Found by the till's
        // own test, whose second `tap` reported that it "would not hit test".
        //
        // `layout.reading` is §4.2's row for a line of prose, which is what
        // this is; a 1400-pixel-wide sentence was the wrong measure anyway.
        constraints: BoxConstraints(maxWidth: tokens.layout.reading),
        child: AppSnackBar(notice: notice, action: action),
      ),
    ),
  );
}

/// One [AppNotice] as a transient block: the container, the glyph and the
/// words.
final class AppSnackBar extends StatelessWidget {
  const AppSnackBar({super.key, required this.notice, this.action});

  final AppNotice notice;

  /// One control at the trailing edge — "Undo", "Open". Left to the caller so
  /// this component decides nothing about what an action does, exactly as
  /// [Callout.action] is.
  final Widget? action;

  /// The leading glyph, at §5.2's only named leading-icon size.
  ///
  /// The same figure and the same recorded reason as [Callout.glyphSize]: §5.1
  /// gives this kind of block a row and no measurements, so the size is
  /// borrowed from a named row rather than invented.
  static const double glyphSize = Callout.glyphSize;

  /// How long a notice stays up before it withdraws itself.
  ///
  /// **Named here rather than tokenised, for the reason [Callout.glyphSize]
  /// gives.** `design.md` §2.4's durations are transitions — 80ms to 320ms, for
  /// something changing opacity or colour — and a dwell is not one of those. A
  /// `motion.dwell` role would be inventing a token to launder a number.
  ///
  /// Four seconds is Material's own default, kept so the affordance stays the
  /// one people already have the reflex for.
  static const Duration dwell = Duration(seconds: 4);

  /// The same, for a notice a person may need to act on.
  ///
  /// **A refusal and an unknown outcome get longer, and this is an
  /// accessibility figure rather than a taste one.** §9 requires that status is
  /// never carried by colour alone, and these two sentences are the ones whose
  /// *content* is load-bearing — "the adjustment response could not be trusted"
  /// takes longer to read than "stock changed from 10 to 7", and it is the one
  /// a person has to do something about.
  static const Duration actionableDwell = Duration(seconds: 7);

  /// Which of the two [notice]'s status earns.
  static Duration dwellFor(AppStatus status) => switch (status) {
    AppStatus.problem || AppStatus.attention => actionableDwell,
    AppStatus.ok || AppStatus.info || AppStatus.neutral => dwell,
  };

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final role = notice.status.role(tokens);
    final body = tokens.density.body(tokens.typography);
    return Semantics(
      container: true,
      // A sentence that appears without being asked for, over a surface the
      // reader is already on, is exactly what a live region is for: without
      // this the confirmation for a write is never announced at all.
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          // **The opaque surface is under the status container, not instead of
          // it.** §2.1's `bg` is translucent in Profound Verdant, and a
          // translucent block floating over a scrolling list would let the
          // words behind it show through the words in front.
          color: tokens.colors.surface.overlay,
          borderRadius: BorderRadius.circular(tokens.radius.md),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: role.bg,
            border: Border.all(color: role.border),
            borderRadius: BorderRadius.circular(tokens.radius.md),
          ),
          child: Padding(
            padding: EdgeInsets.all(tokens.spacing.s16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  notice.status.defaultIcon,
                  size: AppSnackBar.glyphSize,
                  color: role.fg,
                ),
                SizedBox(width: tokens.spacing.s12),
                Expanded(
                  child: Text(
                    notice.message,
                    style: body.copyWith(color: tokens.colors.text.primary),
                  ),
                ),
                if (action case final control?) ...<Widget>[
                  SizedBox(width: tokens.spacing.s12),
                  control,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

