/// `ShiftBanner`: `design.md` §5.2, added in v0.7 from the product owner's own
/// drawing, and the sentence §4.4 has carried unbuilt since v0.5 — *"the shift
/// control is a persistent banner and is never a destination"*.
///
/// **One row: a status container, the standing in words, one line of detail, and
/// exactly one action.** The action is the *next thing to do* rather than a menu
/// of everything possible, which is what keeps a banner a banner. The rest of
/// the shift's controls live behind it, in the sheet tapping it opens — and a
/// sheet is not a route, so §4.4's "never a destination" holds.
///
/// **The standing is in words and in colour, never in colour alone**, which is
/// §9 and is the whole reason this is a component rather than a coloured strip:
/// *No shift open*, *Shift open*, *Cash count unfinished* are three sentences a
/// person reads, and the container and the glyph agree with them.
///
/// **It is presentational.** It takes a status, three strings and a widget, and
/// knows nothing about shifts — the mapping from a shift's real state onto
/// §2.1's five is the caller's, for the reason `AppNotice` gives one level up:
/// a component that decided which status a shift *is* would be deciding
/// business meaning from `lib/ui/`.
library;

import 'package:flutter/material.dart';

import 'press.dart';
import 'status.dart';
import 'tokens.dart';

/// The shift, as a standing rather than a sentence.
final class ShiftBanner extends StatelessWidget {
  const ShiftBanner({
    super.key,
    required this.status,
    required this.heading,
    required this.detail,
    this.action,
    this.onOpenDetails,
    this.icon,
  });

  /// Which of §2.1's five this shift's standing is.
  final AppStatus status;

  /// The standing in words. `label.lg` in the status's own foreground — the one
  /// place in this app where a status colour carries text, because the word
  /// *is* the status here rather than a label beside it.
  final String heading;

  /// One line under it: when it opened, what it holds, what it is waiting for.
  final String detail;

  /// The single next thing to do. Null while there is nothing — a shift being
  /// opened by somebody else on another device, for one.
  final Widget? action;

  /// Opens the sheet carrying the controls that are not the next thing to do:
  /// the counted-cash field, refreshing, and the shift's history.
  ///
  /// Null makes the banner inert rather than hiding anything, because a banner
  /// that is sometimes tappable and looks identical either way is worse than
  /// one that never is.
  final VoidCallback? onOpenDetails;

  /// Overrides [AppStatus.defaultIcon] where a call site has a better glyph.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final role = status.role(tokens);
    final radius = BorderRadius.circular(tokens.radius.md);
    // **A card, with the status on the words rather than on the box, since
    // 2026-08-23.** The export draws this exact panel as
    // `bg-surface-card border border-surface-elevated rounded-xl p-4
    // flex flex-col gap-4`: a plain card holding a coloured status line, a
    // figure, and one full-width control beneath. Tinting the whole container
    // made the busiest surface on the landing route a coloured slab, and it
    // put the shift's own action on the same row as its reading.
    final body = Padding(
      padding: EdgeInsets.all(tokens.spacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                icon ?? status.defaultIcon,
                size: Callout.glyphSize,
                color: role.fg,
              ),
              SizedBox(width: tokens.spacing.s8),
              Expanded(
                child: Text(
                  // The export sets this line in `label-caps`, uppercased.
                  // §2.2 permits uppercase on `label.eyebrow` and on nothing
                  // else, and this is that role.
                  heading.toUpperCase(),
                  style: tokens.typography.labelEyebrow.copyWith(
                    color: role.fg,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: tokens.spacing.s8),
          Text(
            detail,
            style: tokens.typography.bodyMedium.copyWith(
              color: tokens.colors.text.secondary,
            ),
          ),
          if (action case final control?) ...<Widget>[
            SizedBox(height: tokens.spacing.s16),
            control,
          ],
        ],
      ),
    );
    return Semantics(
      container: true,
      // The standing is announced with the words rather than left to the
      // colour, which is the same rule `StatusBadge` follows.
      label: '$heading. $detail',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.colors.surface.raised,
          border: Border.all(color: tokens.colors.surface.borderSubtle),
          borderRadius: radius,
        ),
        child: onOpenDetails == null
            ? body
            : PressSurface(
                borderRadius: radius,
                onPressed: onOpenDetails,
                fillWidth: true,
                excludeSemantics: true,
                hoverOverlay: tokens.colors.action.secondary.hoverFill(),
                pressedOverlay: tokens.colors.action.secondary.pressedFill(),
                child: body,
              ),
      ),
    );
  }
}
