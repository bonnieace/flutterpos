/// `AppMeter`: how much of a known whole is accounted for.
///
/// **A proportion, never a progress bar.** The difference is whether the figure
/// is still moving. A progress indicator says *wait*; this says *this many of
/// that many*, about something that has already finished happening - 118 of 240
/// products counted, 38 of 42 pages arrived. Nothing here animates for that
/// reason: a bar that grew every time a list rebuilt would be motion attached to
/// a fact that did not change, and `design.md` §2.4 spends springs on things that
/// move rather than on things that are merely drawn.
///
/// **It takes two counts, not a fraction.** A caller handing over `0.49` has
/// already done the division, which is where a divide-by-zero and a ratio above
/// one come from; both are this widget's to refuse and it refuses them by never
/// being told the answer. It is also what lets the semantic label say "118 of
/// 240" rather than "49 percent", which is what a screen reader should hear.
///
/// **The colour is a status and the words are the caller's.** Hard rule 4: a
/// meter alone conveys nothing, so every surface drawing one prints the two
/// figures beside it. This widget will not print them - a component that wrote
/// its own label would be a component deciding what a screen means - but
/// [semanticLabel] is required so the non-visual reading is never the bar alone.
library;

import 'package:flutter/material.dart';

import 'status.dart';
import 'tokens.dart';

/// A filled proportion of a track, in one of §2.1's five status colours.
final class AppMeter extends StatelessWidget {
  const AppMeter({
    super.key,
    required this.filled,
    required this.of,
    required this.status,
    required this.semanticLabel,
  });

  /// How many of [of] are accounted for. Clamped into range rather than
  /// asserted: a server that reports 41 counted lines against 40 in scope is
  /// describing a real thing - a product retired between the count and the read
  /// - and a screen that threw on it would be a screen that cannot draw the
  /// truth.
  final int filled;

  /// The whole. Zero draws an empty track: "none of nothing" is not an error,
  /// and it is what an empty category looks like.
  final int of;

  /// Which of §2.1's five this fill wears.
  final AppStatus status;

  /// What the bar says when it is not being looked at. Required - see the
  /// library note.
  final String semanticLabel;

  /// The track's thickness.
  ///
  /// **`space.8`, which is a spacing token doing a sizing job**, and that is
  /// deliberate over adding a ninth value to a scale `design.md` §2.3 closes at
  /// ten. Hard rule 2 asks for the token layer rather than a literal; it does
  /// not ask for a new token per measurement, and 8 is the value on the scale
  /// that a thumb-width surface wants. A thinner track is a pointer idiom.
  static double trackOf(AppTokens tokens) => tokens.spacing.s8;

  /// The share of the track that is filled, in `0..1`.
  ///
  /// Exposed so a test can assert the arithmetic without measuring a rendering,
  /// the same reason `RecordList.formFor` is.
  static double fractionOf(int filled, int of) {
    if (of <= 0 || filled <= 0) return 0;
    return filled >= of ? 1 : filled / of;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final track = trackOf(tokens);
    final radius = BorderRadius.circular(tokens.radius.pill);
    return Semantics(
      label: semanticLabel,
      // The bar is one fact, not a container of facts: a screen reader that
      // walked into it would find two anonymous boxes.
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: radius,
        child: SizedBox(
          height: track,
          child: DecoratedBox(
            decoration: BoxDecoration(color: tokens.colors.surface.borderSubtle),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: FractionallySizedBox(
                widthFactor: fractionOf(filled, of),
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: status.role(tokens).fg),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
