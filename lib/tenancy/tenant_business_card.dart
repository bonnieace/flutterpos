/// A business, drawn as a card: its brand, how it is trading, and what
/// pressing it does.
///
/// **Redrawn 2026-10-13 from `docs/design/businesses/`.** It was a white
/// printed receipt, and on the app's green surfaces it was the only paper on
/// any screen. The developer asked for *My businesses* to match the other
/// designs, so the card speaks the vocabulary Books, the customer account and
/// the home tiles do: a raised surface, the name in the interface face,
/// eyebrow labels, one mono figure. A dashed rule is all that is left of the
/// receipt. *Choose a business* draws its rows with it too.
library;

import 'package:flutter/material.dart';

import '../inventory/product_image_provider.dart';
import '../ui/press.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'tenant_membership.dart';
import 'tenant_types.dart';

/// Why a business cannot be opened, as a card's status line.
///
/// **The words are the membership's standing**, as *My businesses* has
/// printed it since 2026-10-08; *Choose a business* reads the same line.
BusinessCardStatus businessCardStanding(TenantMembership membership) =>
    switch (membership.tenantStatus) {
      TenantStatus.suspended => const BusinessCardStatus(
        status: AppStatus.problem,
        icon: Icons.block,
        word: 'Suspended',
        detail: 'can’t be opened',
      ),
      TenantStatus.archived => const BusinessCardStatus(
        status: AppStatus.neutral,
        icon: Icons.lock_outline,
        word: 'Archived',
        detail: 'can’t be opened',
      ),
      TenantStatus.active => switch (membership.membershipStatus) {
        MembershipStatus.pending => const BusinessCardStatus(
          status: AppStatus.neutral,
          icon: Icons.hourglass_top,
          word: 'Invited',
          detail: 'can’t be opened yet',
        ),
        MembershipStatus.inactive => const BusinessCardStatus(
          status: AppStatus.neutral,
          icon: Icons.lock_outline,
          word: 'Deactivated',
          detail: 'can’t be opened',
        ),
        MembershipStatus.active => const BusinessCardStatus(
          status: AppStatus.neutral,
          icon: Icons.lock_outline,
          word: 'Unavailable',
          detail: 'can’t be opened',
        ),
      },
    };

/// Business cards, one per row on a phone and in columns from
/// [AppLayoutTokens.mediumFloor]: 2 across, 3 from
/// [AppLayoutTokens.expandedFloor], [AppSpacing.s20] apart as on the home.
///
/// **Top-aligned, not stretched.** A business that cannot be opened is short
/// by nature, and stretching it would draw an empty band where figures go.
final class BusinessCardGrid extends StatelessWidget {
  const BusinessCardGrid({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final layout = tokens.layout;
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= layout.expandedFloor
        ? 3
        : width >= layout.mediumFloor
        ? 2
        : 1;
    final gap = columns == 1 ? tokens.spacing.s16 : tokens.spacing.s20;
    final rows = <Widget>[];
    for (var start = 0; start < children.length; start += columns) {
      if (start > 0) rows.add(SizedBox(height: gap));
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (var index = 0; index < columns; index++) ...<Widget>[
              if (index > 0) SizedBox(width: gap),
              Expanded(
                child: start + index < children.length
                    ? children[start + index]
                    : const SizedBox.shrink(),
              ),
            ],
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }
}

/// A status line under the name: a glyph and a word, so colour never carries
/// it alone, and an optional quieter clause after it.
final class BusinessCardStatus {
  const BusinessCardStatus({
    required this.status,
    required this.icon,
    required this.word,
    this.detail,
  });

  final AppStatus status;
  final IconData icon;
  final String word;
  final String? detail;
}

/// The card's one figure: an eyebrow naming the day, and the amount.
///
/// [value] arrives formatted (`KES 910`, or an em dash where nothing was
/// counted). The card sets a leading currency code small, as Books and the
/// customer account do, and the number in mono.
final class BusinessCardFigure {
  const BusinessCardFigure({
    required this.label,
    required this.value,
    this.hero = false,
  });

  final String label;
  final String value;

  /// Today's live figure at [AppTypeRoles.numericHero]; any other day's at
  /// [AppTypeRoles.numericCompact], so a last counted day never reads as
  /// today.
  final bool hero;
}

/// One eyebrow-labelled fact in the row under the figure.
final class BusinessCardFact {
  const BusinessCardFact(this.label, this.value, {this.numeric = false})
    : future = null;

  /// A fact whose value is read after the card is drawn; it is left off
  /// until it resolves, and stays off if it resolves to null.
  const BusinessCardFact.later(this.label, Future<String?> this.future)
    : value = '',
      numeric = false;

  final String label;
  final String value;
  final bool numeric;
  final Future<String?>? future;
}

/// What pressing the card does, printed as its footer row.
final class BusinessCardAction {
  const BusinessCardAction({
    required this.icon,
    required this.label,
    this.detail,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final String? detail;

  /// A spinner in place of [icon] while the action runs.
  final bool busy;
}

/// The card itself.
///
/// **The whole card is the one press target**, as the receipt was: the footer
/// row says what pressing does, it is not a separate button.
final class BusinessCard extends StatelessWidget {
  const BusinessCard({
    super.key,
    required this.name,
    required this.semanticLabel,
    this.slogan,
    this.logoUrl,
    this.status,
    this.figure,
    this.facts = const <BusinessCardFact>[],
    this.action,
    this.onPressed,
    this.here = false,
    this.still = false,
    this.namePlaceholder = false,
    this.below,
  });

  final String name;
  final String? slogan;
  final Uri? logoUrl;
  final BusinessCardStatus? status;
  final BusinessCardFigure? figure;
  final List<BusinessCardFact> facts;
  final BusinessCardAction? action;
  final VoidCallback? onPressed;
  final String semanticLabel;

  /// The business this session is in: the card's edge takes the ok edge.
  final bool here;

  /// A business that cannot be opened: its name drops to secondary text.
  final bool still;

  /// [name] is a placeholder (the add sheet before anything is typed).
  final bool namePlaceholder;

  /// Anything the card carries under its footer, such as an inline form.
  /// It sits outside the press target.
  final Widget? below;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final colors = tokens.colors;
    final type = tokens.typography;
    final space = tokens.spacing;
    final radius = BorderRadius.circular(tokens.radius.md);
    final pad = space.s16;
    final disabled = action != null && onPressed == null && !action!.busy;

    Widget eyebrow(String words) => Text(
      words.toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: type.labelEyebrow.copyWith(color: colors.text.tertiary),
    );

    final nameOnly =
        status == null && (slogan == null || slogan!.trim().isEmpty);
    final head = Padding(
      padding: EdgeInsets.all(pad),
      child: Row(
        // A name alone sits level with the logo rather than at its top edge.
        crossAxisAlignment: nameOnly
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: <Widget>[
          _Logo(url: logoUrl),
          SizedBox(width: space.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: type.titleMedium.copyWith(
                    color: namePlaceholder
                        ? colors.text.tertiary
                        : still
                        ? colors.text.secondary
                        : colors.text.primary,
                  ),
                ),
                if (slogan case final words? when words.trim().isNotEmpty)
                  Text(
                    words,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: type.bodyMedium.copyWith(
                      color: colors.text.secondary,
                    ),
                  ),
                if (status case final line?) ...<Widget>[
                  SizedBox(height: space.s4),
                  _StatusLine(line),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    final shown = figure;
    final figureBlock = shown == null
        ? null
        : Padding(
            padding: EdgeInsets.fromLTRB(pad, pad, pad, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                eyebrow(shown.label),
                SizedBox(height: space.s8),
                _Amount(shown),
              ],
            ),
          );

    final factRow = facts.isEmpty
        ? null
        : Padding(
            padding: EdgeInsets.all(pad),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (var index = 0; index < 3; index++) ...<Widget>[
                  if (index > 0) SizedBox(width: space.s12),
                  Expanded(
                    child: index < facts.length
                        ? _Fact(fact: facts[index], eyebrow: eyebrow)
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          );

    final footer = action == null
        ? null
        : _Footer(action: action!, disabled: disabled);

    final card = DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface.raised,
        border: Border.all(
          color: here ? colors.status.ok.border : colors.surface.cardEdge,
        ),
        borderRadius: radius,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          head,
          if (figureBlock != null || factRow != null)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: pad),
              child: const _DashedRule(),
            ),
          ?figureBlock,
          ?factRow,
          ?footer,
        ],
      ),
    );

    // **What a screen reader hears is the card, not only its name**, so the
    // figure and facts are read here and the tree below is one stop.
    final spoken = <String>[
      semanticLabel,
      if (shown != null) '${shown.label} ${shown.value}.',
      for (final fact in facts)
        if (fact.future == null) '${fact.label} ${fact.value}.',
    ].join(' ');
    final press = onPressed;
    final Widget surface = press == null
        ? Semantics(
            container: true,
            label: spoken,
            excludeSemantics: true,
            child: card,
          )
        : PressSurface(
            onPressed: press,
            borderRadius: radius,
            hoverOverlay: colors.action.tertiary.hoverWash(),
            pressedOverlay: colors.action.tertiary.pressedWash(),
            reservesRingGutter: false,
            fillWidth: true,
            semanticLabel: spoken,
            excludeSemantics: true,
            child: card,
          );
    final extra = below;
    if (extra == null) return surface;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        surface,
        SizedBox(height: space.s8),
        extra,
      ],
    );
  }
}

/// The business's own logo, or the store glyph on a field square.
///
/// **Never a monogram in an identity hue**: a business without a logo is
/// shown as a shop, not as a coloured letter.
final class _Logo extends StatelessWidget {
  const _Logo({required this.url});

  final Uri? url;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final colors = tokens.colors;
    final size = tokens.spacing.s48;
    final glyph = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.surface.field,
        borderRadius: BorderRadius.circular(tokens.radius.md),
      ),
      child: Icon(
        Icons.storefront_outlined,
        size: tokens.icons.card,
        color: colors.text.secondary,
      ),
    );
    final logo = url;
    if (logo == null) return glyph;
    return ClipRRect(
      borderRadius: BorderRadius.circular(tokens.radius.md),
      child: SizedBox.square(
        dimension: size,
        child: Image(
          image: TenantCachedNetworkImage(
            logo,
            cache: TenantImageCacheScope.of(context),
          ),
          fit: BoxFit.cover,
          excludeFromSemantics: true,
          errorBuilder: (_, _, _) => glyph,
        ),
      ),
    );
  }
}

final class _StatusLine extends StatelessWidget {
  const _StatusLine(this.line);

  final BusinessCardStatus line;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final colors = tokens.colors;
    final caption = tokens.typography.caption;
    final role = line.status.role(tokens);
    // Neutral words read in primary text: the neutral role's ink is a grey
    // meant for a badge on its own wash, not for a word on a card.
    final wordColour = line.status == AppStatus.neutral
        ? colors.text.primary
        : role.fg;
    return Text.rich(
      TextSpan(
        children: <InlineSpan>[
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: EdgeInsets.only(right: tokens.spacing.s4),
              child: Icon(
                line.icon,
                size: caption.fontSize,
                color: line.status == AppStatus.neutral
                    ? colors.text.tertiary
                    : role.fg,
              ),
            ),
          ),
          TextSpan(
            text: line.word,
            style: caption.copyWith(
              color: wordColour,
              fontWeight: tokens.typography.labelEyebrow.fontWeight,
            ),
          ),
          if (line.detail case final detail?)
            TextSpan(
              text: ' · $detail',
              style: caption.copyWith(color: colors.text.tertiary),
            ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

final class _Amount extends StatelessWidget {
  const _Amount(this.figure);

  final BusinessCardFigure figure;

  /// `KES 910` → `KES`, `910`. Anything without a leading code - an em dash,
  /// an unknown currency's bare number - is printed whole.
  static final RegExp _coded = RegExp(r'^([A-Z]{3})\s+(.+)$');

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final colors = tokens.colors;
    final type = tokens.typography;
    final match = _coded.firstMatch(figure.value.trim());
    final code = match?.group(1);
    final amount = match?.group(2) ?? figure.value;
    final empty = amount == '—';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: <Widget>[
        if (code != null) ...<Widget>[
          Text(
            code,
            style: type.labelEyebrow.copyWith(
              color: colors.text.tertiary,
              fontWeight: type.numericBody.fontWeight,
            ),
          ),
          SizedBox(width: tokens.spacing.s8),
        ],
        Flexible(
          child: Text(
            amount,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: (figure.hero ? type.numericHero : type.numericCompact)
                .copyWith(
                  color: empty ? colors.text.tertiary : colors.text.primary,
                ),
          ),
        ),
      ],
    );
  }
}

final class _Fact extends StatelessWidget {
  const _Fact({required this.fact, required this.eyebrow});

  final BusinessCardFact fact;
  final Widget Function(String) eyebrow;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final colors = tokens.colors;
    final type = tokens.typography;
    Widget body(String value) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        eyebrow(fact.label),
        SizedBox(height: tokens.spacing.s8),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: (fact.numeric ? type.numericBody : type.labelMedium).copyWith(
            color: value == '—' ? colors.text.tertiary : colors.text.primary,
          ),
        ),
      ],
    );
    final later = fact.future;
    if (later == null) return body(fact.value);
    return FutureBuilder<String?>(
      future: later,
      builder: (context, snapshot) {
        final value = snapshot.data;
        if (value == null) return const SizedBox.shrink();
        return body(value);
      },
    );
  }
}

final class _Footer extends StatelessWidget {
  const _Footer({required this.action, required this.disabled});

  final BusinessCardAction action;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final colors = tokens.colors;
    final type = tokens.typography;
    final space = tokens.spacing;
    final ink = disabled ? colors.text.disabled : colors.text.primary;
    final quiet = disabled ? colors.text.disabled : colors.text.secondary;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.surface.borderSubtle)),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: space.s48 + space.s8),
        child: Padding(
          padding: EdgeInsets.fromLTRB(space.s16, space.s8, space.s8, space.s8),
          child: Row(
            children: <Widget>[
              if (action.busy)
                SizedBox.square(
                  dimension: tokens.icons.row,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colors.action.primary.container,
                    backgroundColor: colors.surface.borderStrong,
                  ),
                )
              else
                Icon(action.icon, size: tokens.icons.row, color: quiet),
              SizedBox(width: space.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      action.label,
                      style: type.labelMedium.copyWith(color: ink),
                    ),
                    if (action.detail case final detail?)
                      Text(
                        detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: type.caption.copyWith(
                          color: disabled
                              ? colors.text.disabled
                              : colors.text.tertiary,
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(
                width: space.s40,
                child: Icon(
                  Icons.chevron_right,
                  size: tokens.icons.card,
                  color: quiet,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The receipt's printed rule, kept as a dashed hairline in the strong
/// border: dashes and gaps of [AppSpacing.s4].
final class _DashedRule extends StatelessWidget {
  const _DashedRule();

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return SizedBox(
      height: tokens.layout.chartHairline,
      width: double.infinity,
      child: CustomPaint(
        painter: _DashPainter(
          color: tokens.colors.surface.borderStrong,
          dash: tokens.spacing.s4,
        ),
      ),
    );
  }
}

final class _DashPainter extends CustomPainter {
  const _DashPainter({required this.color, required this.dash});

  final Color color;
  final double dash;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = size.height;
    final y = size.height / 2;
    for (var x = 0.0; x < size.width; x += dash * 2) {
      canvas.drawLine(Offset(x, y), Offset(x + dash, y), paint);
    }
  }

  @override
  bool shouldRepaint(_DashPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.dash != dash;
}
