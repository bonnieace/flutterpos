/// The till: `design.md` §11 step **7**, in the components that already exist.
///
/// **This screen had none of the redesign until 2026-08-16, and it is the one a
/// cashier uses all day.** Ten chunks migrated the back office around it because
/// §11 step 7 also names four components nobody has specified. Those four are a
/// reason not to *finish* the step and were never a reason not to start it: the
/// tier inversion, the page frame, the two fields and the twelve `textTheme`
/// reads need none of them.
///
/// **The defect §2.1 was written about was still on this screen.** That
/// section's own worked example reads *"**Clear this sale** is `destructive`,
/// **Save sale** is `primary`. Today the destructive action is the more
/// prominent of the two."* It was: *Clear this sale* was an `OutlinedButton`
/// with the theme's mint outline and *Save sale* was a `FilledButton`, so the
/// two read as equals with the destructive one first. They are now
/// [AppButtonTier.destructive] and [AppButtonTier.primary].
///
/// **What is deliberately still Material, and why each one is not guessed at.**
/// §5.1 gives all five a row and §5.2 specifies none of them:
///
/// - `QuantityStepper` (§5.1 priority **1**) - the minus and the bin are still
///   `IconButton`s. "minus + delete, no plus" is §5.1's own description of the
///   defect, and the component that fixes it decides what a stepper *is*.
/// - `FilterChipBar` - the category and tender choosers are still
///   `ChoiceChip`s. §4.3 gives `FilterChips` a row and §2.3 now guards the chip
///   radius alone, which is an open decision rather than a settled value.
/// - `ConfirmDialog` - the clear-sale confirmation is still an `AlertDialog`
///   with `AppButton`s in it. §7 asks for a filled destructive confirm and §2.1
///   has no filled destructive tier; see `PLAN.md`.
/// - `AppSheet` - the compact cart is still `showModalBottomSheet`. It is what
///   blocks the *responsive* half of this step, not this one.
/// - `RollingNumber` - the total is a `StatTile` that redraws, not one that
///   rolls. §6.2's row for it is motion, and motion is step 10's.
///
/// **The band boundary moved and the numbers behind it are §4.1's and §4.2's.**
/// The split used to be `medium` (768), which was this app's own inherited
/// figure; §4.3 gives `Sale` *"products + cart sheet"* at `compact` **and**
/// `medium` and two panes only at `expanded`, so a 900-wide tablet is a sheet
/// now. The cart pane is [AppLayout.salePane] - 420, declared in step 6a and
/// read by nothing until this file.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../inventory/product_visual.dart';
import '../tenancy/tenant_catalog.dart';
import '../tenancy/tenant_route_guard.dart';
import '../tenancy/tenant_session.dart';
import '../ui/buttons.dart';
import '../ui/chips.dart';
import '../ui/dialogs.dart';
import '../ui/snackbar.dart';
import '../ui/fields.dart';
import '../ui/press.dart';
import '../ui/rolling_number.dart';
import '../ui/scaffold.dart';
import '../ui/sheet.dart';
import '../ui/skeleton.dart';
import '../ui/status.dart';
import '../ui/stepper.dart';
import '../ui/tokens.dart';
import 'checkout_catalog_cache.dart';
import 'checkout_draft.dart';
import 'checkout_print_failures.dart';
import 'checkout_refusal.dart';
import 'checkout_sale.dart';
import 'checkout_tender.dart';

/// The largest number of product buttons the till draws at once.
///
/// `CheckoutCatalogCacheRefresher` caches up to two thousand products, and the
/// products are laid out in a `Wrap`, which builds every child eagerly even
/// inside a `ListView`. This bounds the drawing only: a product past the cap is
/// still reachable by search and still reachable by its exact code.
const int maximumRenderedCheckoutProducts = 60;

/// The widest a product tile is allowed to grow before the grid takes another
/// column, and how tall one is in each of the two compositions.
///
/// **Named rather than moved into the token layer, and that is the honest
/// place for them.** `claude.md` hard rule 2 forbids a magic number in a
/// widget; it does not turn every measurement into a token, and neither
/// `design.md` §2.3 nor Profound Verdant states any product-tile geometry.
/// Inventing `size.productTile` would be inventing a token, which the same file
/// forbids one rule earlier.
///
/// **The extent is what picks the column count, and 260 is the figure that makes
/// this app's counts the served designs' counts.** ST-035 asks for two columns at
/// its base width, three at `lg` and four at `xl`; the browse render draws two on
/// a phone. At 260 the grid takes two at a 411 phone and at an 834 tablet, three
/// at a 1024 desktop, and four at a 1440 till - all four, from one number, with no
/// second breakpoint deciding columns. It was 230, which took **five** at 1440 and
/// squeezed the price line until it ellipsised.
const double _productTileExtent = 260;

/// How tall a tile is where the cart is a pane on the same screen.
///
/// ST-035's desktop card is name, code, then the money and the cached figure,
/// with no picture at all: a till screen shows the cart beside the grid, so the
/// grid's job is density rather than recognition. 124 holds that stack with a
/// name that takes both its lines. 128, measured the same way as the compact
/// figure below and for the same reason: 124 overflows by 4.
const double _wideProductTileHeight = 128;

/// How tall a tile is where the cart is behind a tap.
///
/// The recovered mobile browse render leads with a picture band, because on a
/// phone the grid is what a cashier is aiming at with a thumb and a name in
/// 181 logical pixels is not. [_productThumbnailBandHeight] plus the same stack
/// as above, less the code line the phone has no room for.
///
/// **210 is measured rather than added up, and it is the floor.** A `GridView`
/// cell is a fixed box and a `Column` that does not fit one throws, so the
/// figure was taken by letting it throw: 206 and 198 both overflow a two-line
/// name, 210 does not. The arithmetic of the named parts predicts 202, and the
/// difference is what the text stack's own line boxes measure rather than what
/// their `height` multipliers say - which is exactly why this is not arithmetic
/// in a comment. It is also the strict case: a widget test draws in the test
/// font, which is square and wraps sooner than either shipped face.
/// **246 since 2026-09-04**, which is 210 plus the 36 the picture band grew
/// by. A photograph is drawn whole rather than cropped now - see
/// `TenantProductVisual` - and a whole bottle in a band twice as wide as it is
/// tall is a bottle two centimetres high. The band is nearly square instead,
/// which is the shape a product photograph is taken in.
const double _compactProductTileHeight = 246;

/// The height of the picture band across the top of a compact tile.
///
/// Named for the same reason as the three figures above. It was the browse
/// render's own `h-24`; **132 since 2026-09-04**, when the picture stopped
/// being cropped to fill it. At 411 the grid gives a tile about 182 wide, so
/// this is very nearly a square - which is the shape a product photograph is
/// taken in, and the only one a cut-out on transparency reads at.
const double _productThumbnailBandHeight = 132;

/// The side of the picture square on a cart line, asked for on 2026-08-23.
///
/// Named for the same reason as the figures above: a thumbnail is not a
/// spacing, a radius or a size token, and no source this app has stated a
/// cart-line picture geometry. It is [AppButtonSize] `md`'s own 48, so the
/// picture, the name beside it and the 48-square remove button at the far end
/// of the row all sit on one line without any of them setting the height.
const double _cartLineThumbnailSide = 48;

/// The value the category bar carries for "products whose category this device
/// does not hold".
///
/// **A sentinel at the one call site that needs one, rather than a mode in the
/// component.** `_uncachedCategoriesOnly` is tracked separately from
/// `_categoryId` precisely because a real category could legitimately be named
/// anything, so the panel maps that flag onto this value on the way in and back
/// off it on the way out. `FilterChipBar` stays a plain single selection.
///
/// It is a category *ID*, and Firestore document IDs cannot contain a slash, so
/// no real category can collide with it.
const String _uncachedSentinel = 'uncached/only';

/// A till that can price a sale and cannot save one.
///
/// §2.1's `info` is *"offline, read-only, informational"*, and a panel with no
/// [CheckoutDraftSink] is exactly read-only. It is deliberately **not** a
/// refusal: nothing was attempted, so nothing failed.
const AppNotice _unavailable = AppNotice.offline(
  'Saving a sale is unavailable on this device.',
);

/// Guarded point-of-sale route for the selected tenant session.
///
/// **The one screen §4.2 gives `full` to, and until now nothing read that
/// row.** `AppContentWidth.full` has been declared since step 6a and answers
/// `null` from `AppLayout.maxWidthOf`, because the sale is the only page in the
/// app that is not centred inside a maximum: §4.2's third row is *"products
/// flex, cart pane fixed 420"*, and a till that gave back the edges of a wide
/// screen would be spending the space a cashier is aiming at.
final class TenantCheckoutScreen extends StatelessWidget {
  const TenantCheckoutScreen({super.key, required this.cache, this.drafts});

  final CheckoutCatalogSource cache;

  /// Absent until the composition root supplies it; the cart then prices a
  /// sale but cannot save one, exactly as the returns route behaves.
  final CheckoutDraftSink? drafts;

  @override
  Widget build(BuildContext context) => AppScaffold(
    title: 'Register',
    contentWidth: AppContentWidth.full,
    body: TenantCheckoutPanel(cache: cache, drafts: drafts),
  );
}

/// Builds one offline sale from the cached catalog and saves it to the outbox.
///
/// The panel ends at [CheckoutDraftSink.saveDraft]. Submission,
/// confirmation, and recovery are already owned by the sync and recovery
/// workers and run on their own, so there is deliberately no submit, retry, or
/// cancel control here - the same rule the read-only evidence panel follows.
///
/// Four scope decisions are recorded here because each is easy to reverse by
/// accident:
///
/// - **The discount is pinned to zero and has no control.**
///   `CheckoutDraftRequest.discountMinor` exists and is validated, so leaving a
///   field wired to it would hand every cashier an unaudited way to reduce a
///   sale. No role check authorizes a till discount today, so the cart does not
///   offer one. Adding it later is additive; adding it now would be a cash
///   shrinkage path nothing reviews.
/// - **There is no default tender.** A pre-selected payment method would be
///   indistinguishable from an observed one, and the whole point of the field
///   is that a person looked at how the customer paid.
/// - **The cached stock figure is shown and never blocks a sale.** Firestore
///   Rules deliberately permit signed stock, the stock surface already states
///   that a sale is never blocked by a stock count, and this device holds a
///   figure that was true at the last sync rather than now. Refusing to sell
///   below zero here would therefore guarantee nothing on the server while
///   reliably blocking a legitimate sale whenever the cached figure is merely
///   stale - a cashier told "out of stock" by a device that cannot know is
///   worse than one told what the device last saw. So the till states the
///   figure, states when it was read, warns when a line exceeds it, and sells.
/// - **Search and filtering read only the cached snapshot.** The till issues no
///   Firestore read of its own; a sale must be buildable with no network at
///   all, which is the entire reason the offline catalog exists.
/// - **Submitting the search adds a product by its code, and refuses to
///   guess.** A retail barcode scanner presents itself as a keyboard, so a scan
///   arrives here as typed text followed by a submit. Nothing is added unless
///   the query resolves to exactly one product, because a till that picks one
///   of two candidates sells the wrong thing silently. Nothing in Firestore
///   Rules or in [HiveCheckoutCatalogCache] makes a SKU unique - only the
///   product ID is checked for duplicates - so two products really can carry
///   one code, and that case is refused rather than resolved.
/// - **Only a bounded number of products is drawn.** A `Wrap` builds every
///   child eagerly even inside a `ListView`, and the cache admits up to two
///   thousand products, so the list is capped at
///   [maximumRenderedCheckoutProducts] and says how many matched. This changes
///   what is drawn and never what can be sold: a capped-out product is still
///   reachable by search and still reachable by its code.
final class TenantCheckoutPanel extends StatefulWidget {
  const TenantCheckoutPanel({super.key, required this.cache, this.drafts});

  final CheckoutCatalogSource cache;
  final CheckoutDraftSink? drafts;

  /// Whether [screenWidth] gets the two-pane till.
  ///
  /// **Back to `medium` on 2026-08-22, and back to the number it started on.**
  /// This asked for `medium` originally - 768, the previous app's own split -
  /// then moved to `expanded` because `design.md` §4.3's `Sale` row reads
  /// *products + cart sheet* at `compact` **and** `medium`, with two panes only
  /// at `expanded`. Profound Verdant reverses that row: its tablet band is a
  /// "2-column split (Items + Cart)" from 768 up, and `CLAUDE.md` makes
  /// `design.md` implementation history rather than visual authority. So the
  /// figure returns to where it began, now for a stated reason rather than by
  /// inheritance. `docs/stitch/OPEN_QUESTIONS.md` item 21 records the decision.
  ///
  /// **This is the whole of that decision, and it is deliberately not a
  /// breakpoint change.** `AppLayout.expandedFloor` stays at 1024 rather than
  /// moving to Profound Verdant's 1280: at 1194 - an 11-inch tablet held
  /// sideways - a record table is denser and faster to scan than the stacked
  /// cards the narrower band would give it, which is what an operational
  /// surface wants. Asking `medium` here means the till no longer depends on
  /// that floor either way.
  ///
  /// **The screen's width, not the panel's box**, which is the rule §4.1 states
  /// and `PageHeader.showsDisplayTitle` argues for at length: a band is a
  /// property of the surface a person is looking at, and resolving it inside a
  /// padded page invents a fourth boundary by arithmetic. This used to be a
  /// `LayoutBuilder` over the panel's own constraints, which were the window's
  /// only because nothing sat between them.
  ///
  /// Exposed so a test can ask the same question the widget asks, rather than
  /// asserting a pixel width and hoping the two agree - the same reason
  /// `PageHeader` exposes its two.
  static bool showsTwoPanes(double screenWidth) =>
      AppLayout.contract.isAtLeast(screenWidth, AppBreakpoint.medium);

  @override
  State<TenantCheckoutPanel> createState() => _TenantCheckoutPanelState();
}

final class _TenantCheckoutPanelState extends State<TenantCheckoutPanel> {
  /// One loader per session, so a tenant switch reloads rather than reusing
  /// another business's catalog.
  String? _loaderKey;
  TenantGuardedLoader<CheckoutCatalogSnapshot>? _loader;

  static String _sessionKey(TenantSession session) =>
      '${session.uid}:${session.tenantId}:${session.epoch}';

  TenantGuardedLoader<CheckoutCatalogSnapshot> _loaderFor(
    TenantSession session,
  ) {
    final key = _sessionKey(session);
    if (key == _loaderKey && _loader != null) return _loader!;
    _loaderKey = key;
    return _loader = (session) async {
      final snapshot = await widget.cache.read(
        uid: session.uid,
        tenantId: session.tenantId,
      );
      // A missing or foreign snapshot is refused rather than priced against.
      if (snapshot == null || !snapshot.ownsSession(session)) {
        throw const CheckoutDraftException('catalog_cache_unavailable');
      }
      return snapshot;
    };
  }

  @override
  Widget build(BuildContext context) =>
      TenantRouteGuard<CheckoutCatalogSnapshot>(
        load: (session) => _loaderFor(session)(session),
        // **Deliberately not the guard's default spinner, and since 2026-08-27
        // not a sentence either.** This read is a Hive box on the device, so
        // there is nothing to spin about; what there is, is a known shape. The
        // skeleton draws it, the search field above it is real, and the two
        // together mean a cashier sees the till rather than a message about it.
        loading: const _CheckoutSkeleton(key: ValueKey('checkout-loading')),
        denied: const Center(
          key: ValueKey('checkout-denied'),
          child: Text('Selling is unavailable for this business.'),
        ),
        failure: (context, error) => Center(
          child: Text(
            key: const ValueKey('checkout-failure'),
            CheckoutRefusal.forError(error).message,
          ),
        ),
        // Keyed by session: a business switch discards the cart, the search
        // text, the chosen tender, and the previous receipt rather than
        // carrying any of them into another business.
        builder: (context, session, snapshot) => _CartEditor(
          key: ValueKey('checkout-editor-${_sessionKey(session)}'),
          snapshot: snapshot,
          drafts: widget.drafts,
        ),
      );
}

/// The till while its catalog is still being read off the device.
///
/// **The chrome is real and only the data shimmers**, which is decision 35 and
/// is the whole difference between this and a loading screen. A cashier opening
/// the till sees the till: the search field with its label and its helper, the
/// pane at its real width, the grid at its real geometry. What is missing is the
/// products, and that is the only thing drawn as a placeholder.
///
/// **The search field is real but disabled**, which is the one judgement call in
/// here. Its frame, its label and its helper do not come from the read, so by
/// decision 35 they render - but it cannot search a list that is not loaded yet,
/// and a field that accepts keystrokes and silently drops them is worse than one
/// that says it is not ready. `AppTextField` draws its own disabled state, so
/// this states the fact rather than faking it.
///
/// **It mirrors `_productGrid`'s geometry rather than approximating it**: the
/// same tile extent, the same two heights, the same spacings, the same padding.
/// That is the point of the whole exercise - when the snapshot lands, the tiles
/// are already exactly where the placeholders were and nothing moves.
///
/// **The cart pane's width is reserved on a wide layout.** The cart is genuinely
/// empty rather than loading, so nothing in it shimmers; but leaving it out
/// would let the products pane load at full width and then jump narrower when
/// the snapshot arrived, which is the same jolt this exists to remove.
final class _CheckoutSkeleton extends StatelessWidget {
  const _CheckoutSkeleton({super.key});

  /// How many placeholder tiles to draw.
  ///
  /// **Named here rather than tokenised, and it is not
  /// [maximumRenderedCheckoutProducts].** That constant is a cap on real work;
  /// this is a guess at how many tiles fill a screen before scrolling, and the
  /// two would drift into each other if they shared a name. Twelve covers a
  /// phone twice over and a till screen once, which is as much as a placeholder
  /// needs to say - past the fold nobody is looking.
  static const int _tiles = 12;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final dense = TenantCheckoutPanel.showsTwoPanes(
      MediaQuery.sizeOf(context).width,
    );
    final pane = SkeletonGroup(
      semanticLabel: 'Reading the product list on this device.',
      child: ListView(
        padding: EdgeInsets.symmetric(
          horizontal: AppScaffold.horizontalInset(tokens.spacing),
          vertical: tokens.spacing.s12,
        ),
        children: <Widget>[
          // Real, and the same call `_browseHead` makes.
          AppTextField(
            key: const ValueKey('checkout-search'),
            label: 'Search by name or code',
            leading: Icons.search,
            enabled: false,
            helper: 'Tap a product to add it to the sale.',
          ),
          SizedBox(height: tokens.spacing.s8),
          // Every category label is `_snapshot.categories`, so the bar is data
          // and shimmers. The heights are `FilterChipBar`'s own.
          SizedBox(
            height: _chipHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _chips,
              separatorBuilder: (context, _) =>
                  SizedBox(width: tokens.spacing.s8),
              itemBuilder: (context, index) => SkeletonBlock(
                width: index.isEven ? _wideChipWidth : _narrowChipWidth,
                height: _chipHeight,
                radius: tokens.radius.md,
              ),
            ),
          ),
          SizedBox(height: tokens.spacing.s12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: _productTileExtent,
              mainAxisExtent: dense
                  ? _wideProductTileHeight
                  : _compactProductTileHeight,
              crossAxisSpacing: tokens.spacing.s8,
              mainAxisSpacing: tokens.spacing.s8,
            ),
            itemCount: _tiles,
            itemBuilder: (context, index) => _ProductTileSkeleton(
              key: ValueKey('checkout-product-skeleton-$index'),
              dense: dense,
            ),
          ),
        ],
      ),
    );
    if (!dense) return pane;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(child: pane),
        Container(width: 1, color: tokens.colors.surface.borderStrong),
        SizedBox(width: tokens.layout.salePane),
      ],
    );
  }

  /// The placeholder category bar's shape.
  ///
  /// **Three figures this component owns, for the reason `EmptyState.markSize`
  /// gives**: no source this app has states a chip's box, `FilterChipBar` sizes
  /// itself from its labels, and there are no labels yet. Two widths alternating
  /// is what stops a row of identical boxes reading as a table.
  static const double _chipHeight = 32;
  static const double _wideChipWidth = 88;
  static const double _narrowChipWidth = 64;
  static const int _chips = 5;
}

/// One product tile's *parts*, not its outline.
///
/// **The first version of this was a single filled rectangle at the tile's
/// height, and that was a real shortcoming rather than a simplification.** A
/// solid block says only *something is coming here*; it does not say the thing
/// coming has a name at the top and a price at the bottom. A cashier who can
/// see that structure already knows where to look before the words arrive,
/// which is the entire argument for drawing a skeleton instead of a spinner.
///
/// **It mirrors [_ProductTile]'s two bodies, because that widget has two.**
/// `_bandedBody` at compact is a thumbnail band over a name, with the price and
/// the *add* glyph on one row at the foot; `_denseBody` at wide has no image and
/// carries a product code under the name instead. The same `space.8` padding,
/// the same `Spacer`, the same `space.4` before the price - so when the snapshot
/// lands, every line is already where it will be.
///
/// **The line heights are the type roles the real tile sets**, read off the
/// token layer rather than guessed: `title.md` for the name, `mono` for the code
/// and the price, `caption` for the stock figure. A placeholder measured from a
/// different scale would move the moment real text replaced it.
final class _ProductTileSkeleton extends StatelessWidget {
  const _ProductTileSkeleton({super.key, required this.dense});

  /// The wide till's flatter tile, which trades the picture for a code line.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    const tone = SkeletonTone.onRaised;
    final name = SkeletonLine(
      widthFactor: 0.85,
      style: tokens.typography.titleMedium,
      tone: tone,
    );
    final price = SkeletonLine(
      widthFactor: 0.5,
      style: tokens.typography.mono,
      tone: tone,
    );
    final stock = SkeletonLine(
      widthFactor: 0.35,
      style: tokens.typography.caption,
      tone: tone,
    );

    if (dense) {
      return _card(
        tokens,
        height: _wideProductTileHeight,
        child: Padding(
          padding: EdgeInsets.all(tokens.spacing.s8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              name,
              SkeletonLine(widthFactor: 0.4, style: tokens.typography.mono),
              const Spacer(),
              SizedBox(height: tokens.spacing.s4),
              price,
              stock,
            ],
          ),
        ),
      );
    }

    return _card(
      tokens,
      height: _compactProductTileHeight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // The picture band. It is the one part of the tile that is a solid
          // block on purpose - a photograph has no internal structure to
          // promise.
          SkeletonBlock(
            height: _productThumbnailBandHeight,
            radius: tokens.radius.sm,
            tone: tone,
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.all(tokens.spacing.s8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  name,
                  const Spacer(),
                  SizedBox(height: tokens.spacing.s4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[price, stock],
                        ),
                      ),
                      SizedBox(width: tokens.spacing.s4),
                      // The *add* control, which is a circle rather than a
                      // square - and its size is `_addGlyph`'s own arithmetic
                      // rather than a number copied off it: a `space.16` icon
                      // inside `space.4` of padding on every side.
                      SkeletonBlock(
                        width: _addGlyphSide(tokens.spacing),
                        height: _addGlyphSide(tokens.spacing),
                        radius: tokens.radius.pill,
                        tone: tone,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The tile's own card, drawn for real.
  ///
  /// **The frame does not shimmer, and that is decision 35 applied inside a
  /// component rather than across a page.** A tile's surface, its border and its
  /// radius do not come from the read - every tile has them whatever the catalog
  /// says - so they are painted exactly as `_ProductTile` paints them, and only
  /// the lines inside are placeholders. Drawing the whole tile as one block, as
  /// the first version did, threw the grid away: what came back was a page of
  /// floating fragments with no tiles around them.
  static Widget _card(
    AppTokens tokens, {
    required double height,
    required Widget child,
  }) => SizedBox(
    height: height,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.colors.surface.raised,
        borderRadius: BorderRadius.circular(tokens.radius.md),
        border: Border.all(color: tokens.colors.surface.borderSubtle),
      ),
      child: child,
    ),
  );

  /// The *add* glyph's diameter, derived the way `_addGlyph` builds it rather
  /// than measured off a screenshot - so a change to either token moves both.
  static double _addGlyphSide(AppSpacing spacing) =>
      spacing.s16 + spacing.s4 * 2;
}

/// The editable cart for one loaded catalog snapshot and one live session.
final class _CartEditor extends StatefulWidget {
  const _CartEditor({super.key, required this.snapshot, required this.drafts});

  final CheckoutCatalogSnapshot snapshot;
  final CheckoutDraftSink? drafts;

  @override
  State<_CartEditor> createState() => _CartEditorState();
}

final class _CartEditorState extends State<_CartEditor> {
  /// Requested quantity per product, in insertion order.
  final Map<String, int> _quantities = <String, int>{};

  /// Lines whose typed quantity is not a usable whole number. The line keeps
  /// its last usable quantity, so a half-typed number never becomes the sale.
  final Set<String> _unusableQuantities = <String>{};

  final TextEditingController _search = TextEditingController();

  /// The selected category, or null for every category. Never set while
  /// [_uncachedCategoriesOnly] is true.
  String? _categoryId;

  /// Whether only products naming a category this device does not hold are
  /// listed. Tracked separately from [_categoryId] rather than as a sentinel
  /// ID, because a real category could legitimately be named anything.
  bool _uncachedCategoriesOnly = false;

  CheckoutTender? _tender = CheckoutTender.cash;
  bool _saving = false;
  CheckoutRefusal? _refusal;

  /// The last durable save. It deliberately survives every later cart edit and
  /// is cleared only by the next save attempt or by the cashier closing it: a
  /// receipt number describes a finished sale, not the cart on screen, and a
  /// cashier who saves and immediately serves the next customer must still be
  /// able to read and copy it.
  // **No `_saved` field since 2026-08-26.** It held the last durable save so a
  // later `build` could render it, and survived every cart edit for the reason
  // its comment gave: a cashier who saved and immediately served the next
  // customer had to be able to read the receipt number off the screen. The
  // number is on the paper now, and the outcome is reported once, when it
  // arrives, by `_reportSave` - so there is nothing left to hold.

  /// Why the last submitted search added nothing. Cleared by the next edit.
  ///
  /// Bumped on every state change, so the compact layout's cart sheet can
  /// follow along.
  ///
  /// The sheet is pushed as its own route and therefore does not rebuild when
  /// this element does. Rather than route every mutation through a second
  /// callback - and risk one of them being missed - [setState] is overridden
  /// below to bump this, which is the one place every change already passes
  /// through.
  final ValueNotifier<int> _revision = ValueNotifier<int>(0);

  CheckoutCatalogSnapshot get _snapshot => widget.snapshot;

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _revision.value++;
  }

  @override
  void dispose() {
    _search.dispose();
    _revision.dispose();
    super.dispose();
  }

  // --- Catalog filtering -----------------------------------------------

  /// Whether any cached product names a category this device does not hold.
  ///
  /// Such a product must stay reachable, otherwise filtering would silently
  /// hide something the till can legitimately sell.
  bool get _hasUncachedCategories => _snapshot.products.any(
    (product) => _snapshot.categoryById(product.categoryId) == null,
  );

  List<TenantProduct> get _visibleProducts {
    final query = _search.text.trim().toLowerCase();
    return <TenantProduct>[
      for (final product in _snapshot.products)
        if (_matchesCategory(product) && _matchesQuery(product, query)) product,
    ];
  }

  bool _matchesCategory(TenantProduct product) {
    if (_uncachedCategoriesOnly) {
      return _snapshot.categoryById(product.categoryId) == null;
    }
    final selected = _categoryId;
    return selected == null || product.categoryId == selected;
  }

  bool _matchesQuery(TenantProduct product, String query) =>
      query.isEmpty ||
      product.name.toLowerCase().contains(query) ||
      product.sku.toLowerCase().contains(query);

  void _selectCategory({String? categoryId, bool uncachedOnly = false}) {
    setState(() {
      _categoryId = uncachedOnly ? null : categoryId;
      _uncachedCategoriesOnly = uncachedOnly;
    });
  }

  /// Empties the cart without saving anything.
  ///
  /// Nothing is persisted until [_save], so this destroys no record - only the
  /// lines a cashier rang up for a customer who left. The saved receipt is
  /// deliberately untouched: it describes a different, finished sale.
  void _clearSale() {
    setState(() {
      _quantities.clear();
      _unusableQuantities.clear();
      _tender = CheckoutTender.cash;
      _clearRefusal();
    });
  }

  // --- Cart editing -----------------------------------------------------

  void _add(TenantProduct product) {
    if (!_quantities.containsKey(product.id) &&
        _quantities.length >= maximumCheckoutSaleLines) {
      setState(() {
        _refusal = CheckoutRefusal.forCode('invalid_line_count');
      });
      return;
    }
    setState(() {
      final next = (_quantities[product.id] ?? 0) + 1;
      _quantities[product.id] = next > maximumCheckoutLineQuantity
          ? maximumCheckoutLineQuantity
          : next;
      _unusableQuantities.remove(product.id);
      _clearRefusal();
    });
  }

  void _decrement(String productId) {
    setState(() {
      final next = (_quantities[productId] ?? 0) - 1;
      if (next < 1) {
        _quantities.remove(productId);
      } else {
        _quantities[productId] = next;
      }
      _unusableQuantities.remove(productId);
      _clearRefusal();
    });
  }

  void _remove(String productId) {
    setState(() {
      _quantities.remove(productId);
      _unusableQuantities.remove(productId);
      _clearRefusal();
    });
  }

  /// Applies a directly typed quantity for a line already in the cart.
  void _setQuantity(String productId, String raw) {
    if (!_quantities.containsKey(productId)) return;
    final parsed = int.tryParse(raw.trim());
    setState(() {
      _clearRefusal();
      if (parsed == null ||
          parsed < 1 ||
          parsed > maximumCheckoutLineQuantity) {
        _unusableQuantities.add(productId);
        return;
      }
      _unusableQuantities.remove(productId);
      _quantities[productId] = parsed;
    });
  }

  void _chooseTender(CheckoutTender tender) {
    setState(() {
      _tender = tender;
      _clearRefusal();
    });
  }

  /// Clears the previous attempt's refusal and code notice so neither can sit
  /// beside a cart the cashier has since changed. The saved receipt is
  /// deliberately not cleared here; it describes a sale that is already
  /// finished.
  void _clearRefusal() {
    _refusal = null;
  }

  // --- Pricing ----------------------------------------------------------

  /// The cart total, or null when a selected price cannot be recorded exactly.
  ///
  /// The returned value may exceed [maximumCheckoutMinorAmount]; that is a
  /// separate refusal, reported by [_blocker] rather than hidden here.
  int? get _totalMinor {
    var total = 0;
    for (final entry in _quantities.entries) {
      final minor = _unitPriceMinor(entry.key);
      if (minor == null) return null;
      total += minor * entry.value;
    }
    return total;
  }

  int? _unitPriceMinor(String productId) {
    final product = _snapshot.productById(productId);
    return product == null ? null : checkoutMinorUnitsFromMajor(product.price);
  }

  /// Whether any line total, or the cart total, is beyond what a sale records.
  ///
  /// Direct quantity entry makes this reachable at the till: the frozen payload
  /// contract refuses it as `draft_contract_violation`, which tells a cashier to
  /// ask for help when the real answer is to type a smaller number.
  bool _exceedsRecordableAmount(int? total) {
    if (total == null) return false;
    if (total > maximumCheckoutMinorAmount) return true;
    for (final entry in _quantities.entries) {
      final minor = _unitPriceMinor(entry.key);
      if (minor != null && minor * entry.value > maximumCheckoutMinorAmount) {
        return true;
      }
    }
    return false;
  }

  /// Why saving is not offered yet, or null when the sale may be saved.
  ///
  /// The cart states the reason rather than presenting a dead button, because
  /// a disabled control with no explanation is how a till stalls.
  String? _blocker(int? total) {
    if (_quantities.isEmpty) return 'Add at least one item to save this sale.';
    if (_unusableQuantities.isNotEmpty) {
      return 'Enter a whole quantity between 1 and '
          '${_grouped(maximumCheckoutLineQuantity)} for every item.';
    }
    if (total == null) {
      return 'Remove the item whose price cannot be recorded exactly.';
    }
    if (_exceedsRecordableAmount(total)) {
      return 'This sale is larger than this register can record. Reduce a '
          'quantity.';
    }
    if (_tender == null) return 'Choose how the customer paid.';
    return null;
  }

  // --- Saving -----------------------------------------------------------

  Future<void> _save() async {
    final drafts = widget.drafts;
    final tender = _tender;
    if (drafts == null || tender == null || _saving) return;

    setState(() {
      _saving = true;
      _clearRefusal();
    });

    CheckoutSavedDraft? saved;
    CheckoutRefusal? refusal;
    try {
      saved = await drafts.saveDraft(
        CheckoutDraftRequest(
          tender: tender,
          lines: <CheckoutDraftLineRequest>[
            for (final entry in _quantities.entries)
              CheckoutDraftLineRequest(
                productId: entry.key,
                quantity: entry.value,
              ),
          ],
        ),
      );
    } catch (error) {
      refusal = CheckoutRefusal.forError(error);
    }

    // The await above can outlive this route: a tenant switch or a pop while
    // the draft was being written must not write state into a dead element.
    if (!mounted) return;
    setState(() {
      _saving = false;
      _refusal = refusal;
      // The cart is cleared only when the draft is durable, so a refused sale
      // keeps every line the cashier already rang up.
      if (saved != null) {
        _quantities.clear();
        _unusableQuantities.clear();
        _tender = CheckoutTender.cash;
        // The till returns to its neutral state for the next customer rather
        // than leaving them a catalog narrowed by somebody else's search.
        _search.clear();
        _categoryId = null;
        _uncachedCategoriesOnly = false;
      }
    });
    if (saved == null) return;
    // **The sheet closes first, then the outcome is reported.** On a phone the
    // cart is a sheet over the till, and a snack bar or a modal raised while it
    // is still up would be dismissed along with it - or worse, would be
    // anchored to a route that is going away. Closing first means both layouts
    // report onto the till, which is the surface the cashier is left looking at.
    final navigator = _cartSheetNavigator;
    if (navigator != null && navigator.canPop()) navigator.pop();
    if (!mounted) return;
    _reportSave(context, saved);
  }

  // --- Rendering --------------------------------------------------------

  /// How many units the cart holds, for the compact layout's badge.
  int get _itemCount =>
      _quantities.values.fold<int>(0, (sum, quantity) => sum + quantity);

  @override
  Widget build(BuildContext context) {
    final total = _totalMinor;
    final currency = _snapshot.configuration.currency;
    return KeyedSubtree(
      key: const ValueKey('checkout-cart'),
      child: TenantCheckoutPanel.showsTwoPanes(MediaQuery.sizeOf(context).width)
          ? _wideLayout(context, currency, total)
          : _compactLayout(context, currency, total),
    );
  }

  /// Products beside a cart that is always on screen.
  ///
  /// **§4.2's third row, in its own words: "products flex, cart pane fixed
  /// 420".** The proportion used to be a 3:2 flex, which is the previous app's
  /// and which gave the cart 560 pixels of a 1400 window and 200 of a 500 one.
  /// [AppLayout.salePane] is the figure §4.2 states, and it is the last of the
  /// three content widths that had no reader.
  Widget _wideLayout(BuildContext context, String currency, int? total) {
    final tokens = AppTokens.componentOf(context);
    return Row(
      key: const ValueKey('checkout-wide'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _productsPane(context, currency, dense: true)),
        // §2.1's hairline, which is what separates two regions everywhere else
        // in this app. `VerticalDivider` paints `dividerColor`, and the theme's
        // is the same role - this reads it by name rather than by inheritance.
        //
        // **`border.strong`, not `border.subtle`.** This is the boundary between
        // the catalog and the sale, and §9's 3:1 row applies "where a person
        // must perceive a boundary" - which is the argument `_CartBar` already
        // makes for its own top edge on a phone. A subtle hairline is for
        // separating rows inside one region.
        Container(width: 1, color: tokens.colors.surface.borderStrong),
        SizedBox(
          width: tokens.layout.salePane,
          // **The surface steps are the whole of ST-035's two-region
          // composition, and they are wide-only.** That design gives the cart
          // `surface-container-low` with its header and footer a step up at
          // `surface-container` and its list of lines a step *down* at
          // `surface` - three levels, so the pane reads as a place rather than
          // as the right-hand end of the products. In this app's roles that is
          // the page ground, `raised`, and `sunken`.
          //
          // They are not passed to the sheet. A sheet's own ground is §2.1's
          // `overlay`, a step above `raised`, so a `raised` header inside one
          // draws recessed and a `sunken` list draws two steps down - which is
          // the depth inversion §2.1 exists to prevent. The sheet keeps the
          // hairlines, and `_cartPane` takes the difference as an argument
          // rather than guessing it from whether a controller arrived.
          child: _cartPane(context, currency, total, stepped: true),
        ),
      ],
    );
  }

  /// Products at full width, with the cart one tap away.
  ///
  /// The cart is a sheet rather than a section further down the same scroll,
  /// because the two are used alternately: every item added is a trip to the
  /// cart and back, and on a phone that was a scroll past the whole catalog in
  /// each direction. The bar states the total without the sheet being open, so
  /// the number a customer is waiting for is never behind a tap.
  Widget _compactLayout(BuildContext context, String currency, int? total) =>
      Column(
        key: const ValueKey('checkout-compact'),
        children: [
          Expanded(child: _productsPane(context, currency, dense: false)),
          _CartBar(
            currency: currency,
            total: total,
            itemCount: _itemCount,
            onOpen: () => _openCartSheet(context, currency),
          ),
        ],
      );

  /// The navigator hosting the cart sheet, while one is open.
  ///
  /// A save closes the sheet, so the cashier is returned to the products for
  /// the next customer rather than having to dismiss the cart by hand between
  /// every sale. It is null whenever no sheet is up, which is what stops a
  /// save on the two-pane till trying to pop the route behind it.
  NavigatorState? _cartSheetNavigator;

  Future<void> _openCartSheet(BuildContext context, String currency) async {
    _cartSheetNavigator = Navigator.of(context);
    try {
      await _showCartSheet(context, currency);
    } finally {
      _cartSheetNavigator = null;
    }
  }

  Future<void> _showCartSheet(BuildContext context, String currency) {
    return showAppSheet<void>(
      context,
      // **Full rather than the 0.7 detent, chosen by the product owner on
      // 2026-08-23.** The cart is the whole task once it is open, and the
      // half-height opening spent a drag before the tender chips were
      // reachable. `AppSheetDetent.half` remains the floor, so the sheet still
      // drags down to the old height and dismisses from there.
      initialDetent: AppSheetDetent.full,
      builder: (sheetContext, controller) => ValueListenableBuilder<int>(
        valueListenable: _revision,
        // The sheet is a route of its own, so this element does not rebuild
        // when the panel behind it does. [_revision] is what keeps the two in
        // step - without it, adding an item from inside the sheet would leave
        // the sheet showing the cart as it was when it opened.
        builder: (context, _, _) =>
            _cartPane(context, currency, _totalMinor, controller: controller),
      ),
    );
  }

  /// Everything a cashier needs once the items are chosen.
  ///
  /// **A head, a scrolling middle and a foot, which is what both served designs
  /// draw and what this used to be one long `ListView` of.** ST-035's cart is a
  /// fixed header with the sale's name and its destructive action, a
  /// `flex-1 overflow-y-auto` list of lines, and a footer holding the total, the
  /// tender and the save. What that buys on a phone is the whole point: the save
  /// was the last thing in a scroll, so a cashier with six items had to scroll
  /// past all of them to press it, and the total went off the top of the sheet
  /// while they did.
  ///
  /// **The three regions are separated by hairlines rather than by a surface
  /// step**, which is where this diverges from ST-035's `surface-container`
  /// header and footer. This same pane renders inside `AppSheet`, whose ground is
  /// §2.1's `surface.overlay` - a step *above* `raised` - so painting the head
  /// and foot `raised` there would draw them recessed into the sheet and invert
  /// the depth §2.1 is built on. A hairline reads the same on both grounds, and
  /// it is what `_CartBar` and the browse head already use.
  Widget _cartPane(
    BuildContext context,
    String currency,
    int? total, {
    ScrollController? controller,
    bool stepped = false,
  }) {
    final tokens = AppTokens.componentOf(context);
    final inset = AppScaffold.horizontalInset(tokens.spacing);
    return ColoredBox(
      color: stepped ? tokens.colors.surface.base : Colors.transparent,
      child: Column(
        key: const ValueKey('checkout-cart-pane'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // **Only the two-pane cart keeps a fixed head.** In the sheet it
          // was a non-scrolling strip holding a heading that repeated what the
          // sheet already was, and it blocked the drag: a gesture starting on
          // it moved nothing. The clear moves into the scrolling content
          // below, still at the top and still far from the save.
          if (stepped) _cartHead(context, tokens, inset, stepped: stepped),
          Expanded(
            child: ColoredBox(
              color: stepped
                  ? tokens.colors.surface.sunken
                  : Colors.transparent,
              child: ListView(
                // The sheet hands this controller down and the scrollable it
                // is given is what couples the drag to the content. It goes to
                // the middle region, because that is the one that scrolls.
                controller: controller,
                padding: EdgeInsets.symmetric(
                  horizontal: inset,
                  vertical: tokens.spacing.s12,
                ),
                children: <Widget>[
                  // The sheet's own clear, in the position the fixed head used
                  // to hold. §2.1's worked example still applies - it is the
                  // destructive tier, and the save is at the far end of the
                  // pane in `_cartFoot`.
                  if (!stepped && _quantities.isNotEmpty) ...<Widget>[
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: AppButton(
                        key: const ValueKey('checkout-clear-sale'),
                        label: 'Clear this sale',
                        icon: Icons.delete_outline,
                        tier: AppButtonTier.destructive,
                        size: AppButtonSize.sm,
                        onPressed: _saving
                            ? null
                            : () => _confirmClearSale(context),
                      ),
                    ),
                    SizedBox(height: tokens.spacing.s8),
                  ],
                  ..._saleLines(context, tokens, currency),
                  SizedBox(height: tokens.spacing.s16),
                  // **§7's "Long copy" pattern, and this is policy rather than
                  // state.** "Anything over two lines that explains *policy*
                  // rather than *the current state* goes in a `Disclosure`" -
                  // and what a saved sale does afterwards is the policy this
                  // panel's own class comment spends four paragraphs on. It was
                  // permanent body text at the foot of every cart.
                  const Disclosure(
                    key: ValueKey('checkout-submission-disclosure'),
                    // 30 characters, inside
                    // `Disclosure.summaryCharacterBudget`.
                    summary: 'What happens to a saved sale',
                    child: Text(
                      key: ValueKey('checkout-submission-policy'),
                      'A saved sale is submitted and confirmed automatically. '
                      'It cannot be edited, retried, or deleted here.',
                    ),
                  ),
                ],
              ),
            ),
          ),
          _cartFoot(context, tokens, currency, total, inset, stepped: stepped),
        ],
      ),
    );
  }

  /// The sale's name, and the one action that abandons it.
  ///
  /// **The clear moved up here from under the total**, which is ST-035's own
  /// arrangement and closes the last of §2.1's worked example: the destructive
  /// action and the primary one are now at opposite ends of the pane rather than
  /// adjacent, so a thumb reaching for the save cannot land on the clear.
  Widget _cartHead(
    BuildContext context,
    AppTokens tokens,
    double inset, {
    required bool stepped,
  }) => DecoratedBox(
    decoration: BoxDecoration(
      color: stepped ? tokens.colors.surface.raised : null,
      border: Border(
        bottom: BorderSide(color: tokens.colors.surface.borderSubtle),
      ),
    ),
    child: Padding(
      padding: EdgeInsets.symmetric(
        horizontal: inset,
        vertical: tokens.spacing.s8,
      ),
      child: Row(
        children: <Widget>[
          Expanded(child: SectionHeading('This sale')),
          // Offered only when there is something to abandon, and never for a
          // saved sale: nothing here is persisted, so this destroys no
          // record.
          //
          // **§2.1's own worked example, closed.** "Clear this sale is
          // `destructive`, Save sale is `primary`. Today the destructive
          // action is the more prominent of the two." It was an
          // `OutlinedButton` wearing the theme's mint outline directly above
          // a `FilledButton`; it is §2.1's destructive tier now - red label,
          // red border, transparent container - and the primary one is the
          // save, at the other end of the pane.
          if (_quantities.isNotEmpty)
            AppButton(
              key: const ValueKey('checkout-clear-sale'),
              label: 'Clear this sale',
              icon: Icons.delete_outline,
              tier: AppButtonTier.destructive,
              size: AppButtonSize.sm,
              onPressed: _saving ? null : () => _confirmClearSale(context),
            ),
        ],
      ),
    ),
  );

  /// The lines themselves, or the sentence that says there are none.
  List<Widget> _saleLines(
    BuildContext context,
    AppTokens tokens,
    String currency,
  ) => <Widget>[
    if (_quantities.isEmpty)
      Text(
        key: const ValueKey('checkout-cart-empty'),
        'No items yet. Add a product to start the sale.',
        style: tokens.density
            .body(tokens.typography)
            .copyWith(color: tokens.colors.text.secondary),
      )
    else
      for (final entry in _quantities.entries)
        _CartLine(
          key: ValueKey('checkout-line-${entry.key}'),
          product: _snapshot.productById(entry.key),
          productId: entry.key,
          quantity: entry.value,
          quantityUnusable: _unusableQuantities.contains(entry.key),
          currency: currency,
          onQuantityChanged: (raw) => _setQuantity(entry.key, raw),
          onIncrement: () {
            final product = _snapshot.productById(entry.key);
            if (product != null) _add(product);
          },
          onDecrement: () => _decrement(entry.key),
          onRemove: () => _remove(entry.key),
        ),
  ];

  /// What the customer is waiting for: the figure, the assertion, the save.
  ///
  /// It does not scroll. Everything in it is either the answer to *how much* or
  /// the control that ends the sale, and neither may be below a fold.
  Widget _cartFoot(
    BuildContext context,
    AppTokens tokens,
    String currency,
    int? total,
    double inset, {
    required bool stepped,
  }) => DecoratedBox(
    decoration: BoxDecoration(
      color: stepped ? tokens.colors.surface.raised : null,
      border: Border(
        top: BorderSide(color: tokens.colors.surface.borderStrong),
      ),
    ),
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        inset,
        tokens.spacing.s12,
        inset,
        tokens.spacing.s16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _totalLine(tokens, currency, total),
          SizedBox(height: tokens.spacing.s12),
          ..._tenderSection(context, tokens),
          ..._saveSection(context, tokens, total),
        ],
      ),
    ),
  );

  /// The one figure a customer is waiting to hear.
  ///
  /// **A line rather than a card, which is what both served designs draw.** It
  /// was a `StatTile` - a bordered box with a label above a figure - and §2.2's
  /// "the one figure a stat tile exists for" is what put it there. Both designs
  /// put the word and the figure at opposite ends of one line above the tender,
  /// and a card inside a footer that is already a bordered region is a box in a
  /// box. The role is unchanged: `numeric.hero`, tabular, and now in
  /// [AppTextRoles.money] - the pair `OPEN_QUESTIONS.md` decision 23 chose for
  /// this surface.
  ///
  /// **The untotalled branch is not a figure at all**, because there is none:
  /// §2.1's `problem` says "difference found, **unreadable**", and a price this
  /// till cannot record exactly is a record it cannot read.
  Widget _totalLine(AppTokens tokens, String currency, int? total) {
    if (total == null) {
      return Callout(
        key: const ValueKey('checkout-total-unavailable'),
        status: AppStatus.problem,
        message:
            'This sale cannot be totalled because one item has a price the '
            'register cannot record exactly.',
      );
    }
    // **The word takes its own width and the figure takes the rest**, which is
    // the opposite of the obvious arrangement and is the one that does not
    // throw. `numeric.hero` is 30, and `maximumCheckoutMinorAmount` admits a
    // seventeen-character figure - a total this till refuses but must still
    // draw while it says so. Given half a 411 phone that overflows, and a
    // `Row` that overflows throws. The label is four glyphs and never needs
    // protecting; the figure is what may have to ellipsise, and only in the
    // branch `_blocker` is already explaining.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        SectionHeading('Total'),
        SizedBox(width: tokens.spacing.s12),
        // §6.2's "Total recalculates - digits roll; only changed digits move,
        // `spring.smooth`, no haptic". The one figure in this app that changes
        // while a person is looking at it.
        //
        // **§6.3 is why this is safe on the sale path**: the string is formatted
        // from `total`, which is already computed, and the roll plays over it.
        // Nothing here sits between an input and its record.
        //
        // **`numeric.hero` and not `mono`**, which is the one place decision 23
        // stops short of the design. ST-035 sets this figure in `data-mono` and
        // ST-036 sets it in the interface face, so the two disagree - and
        // `RollingNumber` asserts a tabular style for a reason a mono face does
        // not satisfy by being fixed-width: the assertion is what stops every
        // digit position shifting mid-roll. The colour, which both designs agree
        // on, moves; the face, which they do not, stays.
        Expanded(
          child: Align(
            alignment: Alignment.bottomRight,
            child: RollingNumber(
              value: '$currency ${_money(total)}',
              textKey: const ValueKey('checkout-total'),
              style: tokens.typography.numericHero.copyWith(
                color: tokens.colors.text.money,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Reports one durable save, and leaves the till's shape alone doing it.
  ///
  /// **Three outcomes, three different surfaces, and the split is by whether
  /// anybody has to do anything.** Until 2026-08-26 all three were inline
  /// `Callout`s that stayed until the cashier pressed *Close*, so the common
  /// case - a sale that saved and printed - pushed the cart down the screen and
  /// cost a press, to carry a sentence nobody needed to act on.
  ///
  /// - **Saved, with a receipt number**: [showAppSnackBar]. It withdraws itself
  ///   and the till is ready for the next customer without a press. The number
  ///   is on the paper in the customer's hand, which is the owner's own
  ///   reasoning for dropping *Copy receipt number* at the same time.
  /// - **Saved, but no receipt number could be stated**: [showAppNoticeDialog].
  ///   A cashier must not read a number out that the till could not produce, so
  ///   this one cannot be allowed to withdraw itself unseen.
  /// - **The receipt did not print**: the same modal. Nothing came out, so
  ///   there is no paper carrying the number, and the queue needs visiting.
  ///
  /// Both modals are shown from here rather than rendered, so the till's own
  /// layout is unchanged by any of them.
  void _reportSave(BuildContext context, CheckoutSavedDraft saved) {
    final receipt = saved.receiptNumber;
    final printFailure = saved.receiptPrintFailure;
    // Every printing sentence comes from `checkout_print_failures.dart`, which
    // is the one place in that slice holding English. This screen invents none.
    final printNotice = printFailure == null
        ? null
        : PrinterFailureNotice.of(printFailure);

    if (receipt == null) {
      // §2.1's `attention` - "unreconciled, pending, **awaiting**" - because
      // nothing failed: the sale is durable and syncs either way, and what is
      // awaited is the number.
      unawaited(
        showAppNoticeDialog(
          context,
          title: 'Saved without a receipt number',
          notice: const AppNotice.unknown(
            'The sale is saved on this device and syncs on its own, but the '
            'register could not state a receipt number for it.',
          ),
          stillTrue:
              'The sale is not lost and nothing needs ringing up again. Ask '
              'for help before giving the customer a receipt number.',
          dismissKey: const ValueKey('checkout-dismiss-receipt'),
        ),
      );
      return;
    }

    if (printNotice != null) {
      unawaited(
        showAppNoticeDialog(
          context,
          title: 'Saved as $receipt',
          notice: printNotice,
          // **Where the receipt went, which the notice above cannot say.**
          // Those sentences are read by the print queue panel too, so telling
          // somebody already standing in that queue to open it would be
          // nonsense - the route belongs here, at the surface that needs it.
          //
          // It names a destination and does not become one: `Receipts waiting`
          // is a real entry on the business home, and a button here would be a
          // routing condition, which hard rule 1 keeps out of a visual change.
          stillTrue:
              'The sale itself is saved and syncs on its own. Open Receipts '
              'waiting from the business home to send this one again.',
          dismissKey: const ValueKey('checkout-dismiss-receipt'),
        ),
      );
      return;
    }

    showAppSnackBar(
      context,
      AppNotice.confirmed('Saved as $receipt. It syncs on its own.'),
    );
  }

  /// The catalog: what is sellable, and how it is found.
  ///
  /// **The pane is a fixed head over a scrolling grid, which is what both served
  /// designs draw and what this used to be one long `ListView` of.** ST-035's
  /// search row and category row are their own bars above a `flex-1
  /// overflow-y-auto` grid, and the browse render's are sticky above one. What
  /// that buys is not tidiness: a cashier who scrolls to the twentieth product
  /// used to lose the search field and the category chips off the top of the
  /// screen, and the fastest way to reach a product is to type its name.
  ///
  /// The grid replaced a `Wrap` of buttons whose widths followed their labels,
  /// so a long product name made its own tile wider than its neighbours and
  /// nothing lined up. A cashier scans this by position, so the columns are
  /// fixed and the tiles are not.
  Widget _productsPane(
    BuildContext context,
    String currency, {
    required bool dense,
  }) {
    final tokens = AppTokens.componentOf(context);
    return KeyedSubtree(
      key: const ValueKey('checkout-products-pane'),
      child: _productGrid(context, tokens, currency, dense: dense),
    );
  }

  /// The search and the category filters, drawn as the grid's first rows.
  ///
  /// **This scrolls away with the products, chosen by the product owner on
  /// 2026-08-23.** It was a fixed region above the grid with the catalog's
  /// freshness sentence in a band of its own; on a phone that spent most of a
  /// short screen on standing context before a single product was visible.
  /// The band is gone, the hairline that separated a *fixed* head from its
  /// content went with it, and what remains is content in the pane's own
  /// `ListView`.
  ///
  /// **The partial-catalog warning stays**, and is the one thing here that was
  /// not merely context: a device holding part of the product list can fail to
  /// find a product that exists, and nothing else on this screen says so.
  Widget _browseHead(BuildContext context, AppTokens tokens) {
    // §2.2's `caption` row - "timestamps, attribution" - in `text.tertiary`,
    // which §2.1 names the floor for anything a person is expected to read.
    final quiet = tokens.typography.caption.copyWith(
      color: tokens.colors.text.tertiary,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (!_snapshot.complete) ...<Widget>[
          Text(
            key: const ValueKey('checkout-catalog-partial'),
            'This device holds only part of the product list for this '
            'business, so a product may be missing from it.',
            style: quiet,
          ),
          SizedBox(height: tokens.spacing.s8),
        ],
        // §5.2's field. The leading glyph is the "optional in the strong
        // sense" case that section describes: a magnifier says *this one is
        // searched*, which the label cannot say faster, and the till is where
        // a cashier is not reading.
        AppTextField(
          key: const ValueKey('checkout-search'),
          label: 'Search by name or code',
          leading: Icons.search,
          controller: _search,
          textInputAction: TextInputAction.search,
          // Searching filters the list and adds nothing. Adding is the card's
          // own tap, which is the only way a product enters the sale. Barcode
          // scanning is not wired to this field yet.
          onChanged: (_) => setState(() {}),
          helper: 'Tap a product to add it to the sale.',
        ),
        if (_snapshot.categories.isNotEmpty ||
            _hasUncachedCategories) ...<Widget>[
          SizedBox(height: tokens.spacing.s8),
          // **The one bar whose selection is not simply a value**, because
          // "Other" is a *mode* - products naming a category this device does
          // not hold - and is tracked separately from `_categoryId` rather
          // than as a sentinel ID, since a real category could legitimately be
          // named anything. The sentinel lives here, at the one call site that
          // has the problem, instead of in the component.
          FilterChipBar<String>(
            semanticLabel: 'Narrow the products by category',
            selected: _uncachedCategoriesOnly ? _uncachedSentinel : _categoryId,
            onSelected: (value) => value == _uncachedSentinel
                ? _selectCategory(uncachedOnly: true)
                : _selectCategory(categoryId: value),
            options: <FilterChipOption<String>>[
              const FilterChipOption<String>(
                key: ValueKey('checkout-category-all'),
                value: null,
                label: 'All',
              ),
              for (final category in _snapshot.categories)
                FilterChipOption<String>(
                  key: ValueKey('checkout-category-${category.id}'),
                  value: category.id,
                  label: category.name,
                ),
              if (_hasUncachedCategories)
                const FilterChipOption<String>(
                  key: ValueKey('checkout-category-other'),
                  value: _uncachedSentinel,
                  label: 'Other',
                ),
            ],
          ),
        ],
        SizedBox(height: tokens.spacing.s12),
      ],
    );
  }

  /// The products themselves, and the three answers when there are none to draw.
  Widget _productGrid(
    BuildContext context,
    AppTokens tokens,
    String currency, {
    required bool dense,
  }) {
    final quiet = tokens.typography.caption.copyWith(
      color: tokens.colors.text.tertiary,
    );
    final body = tokens.density
        .body(tokens.typography)
        .copyWith(color: tokens.colors.text.secondary);
    final matches = _visibleProducts;
    // A `Wrap` builds every child eagerly even inside a `ListView`, and the
    // cache admits two thousand products. Only what is drawn is bounded; every
    // match stays sellable by narrowing the search or entering its code.
    final visible = matches.length > maximumRenderedCheckoutProducts
        ? matches.sublist(0, maximumRenderedCheckoutProducts)
        : matches;
    return ListView(
      padding: EdgeInsets.symmetric(
        horizontal: AppScaffold.horizontalInset(tokens.spacing),
        vertical: tokens.spacing.s12,
      ),
      children: <Widget>[
        // **The saved-sale notice is not drawn on either layout any more.** It
        // used to be rendered here for the phone alone, because the phone's
        // cart is a sheet that a save closes and the confirmation would have
        // left with it. A snack bar is shown over whatever is on screen, so
        // that whole asymmetry is gone: both layouts now report the same way,
        // from `_reportSave`, and neither reserves space for it.
        _browseHead(context, tokens),
        // **Two full-page-ish states that stay prose, deliberately.** §5.1 gives
        // `EmptyState` a row and §5.2 specifies it nowhere, and step 9 already
        // took this decision once for screen 08: giving one of the three missing
        // full-page states a bespoke treatment here is how a fourth
        // implementation of an empty state gets written. They take a §2.2 role
        // and no shape of their own.
        if (_snapshot.products.isEmpty)
          Text(
            key: const ValueKey('checkout-catalog-empty'),
            'This device holds no products for this business yet. Connect to '
            'sync them before selling.',
            style: body,
          )
        else if (visible.isEmpty)
          Text(
            key: const ValueKey('checkout-catalog-no-matches'),
            'No product on this device matches that search. Clear it to see the '
            'whole list.',
            style: body,
          )
        else ...<Widget>[
          if (matches.length > visible.length) ...<Widget>[
            Text(
              key: const ValueKey('checkout-catalog-truncated'),
              'Showing ${visible.length} of ${matches.length} matching '
              'products. Narrow the search, or enter a code to add one '
              'directly.',
              style: quiet,
            ),
            SizedBox(height: tokens.spacing.s8),
          ],
          GridView.builder(
            // The cap above is what makes eager building safe, so the grid does
            // not need to be lazy and must not scroll itself - it sits inside
            // the pane's own scroll.
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              // An extent rather than a column count, so one grid serves a phone
              // and a till screen without a second breakpoint deciding columns.
              //
              // **The extent and the two heights are this component's own and
              // are not §2.3's to supply.** A tile is not a spacing, a radius or
              // a size token - no source this app has stated any product-tile
              // geometry - and the reasoning behind each figure is on the
              // constant. The two *gaps* are §2.3's.
              maxCrossAxisExtent: _productTileExtent,
              mainAxisExtent: dense
                  ? _wideProductTileHeight
                  : _compactProductTileHeight,
              crossAxisSpacing: tokens.spacing.s8,
              mainAxisSpacing: tokens.spacing.s8,
            ),
            itemCount: visible.length,
            itemBuilder: (context, index) {
              final product = visible[index];
              final minor = checkoutMinorUnitsFromMajor(product.price);
              return _ProductTile(
                key: ValueKey('checkout-product-${product.id}'),
                product: product,
                // The panel words both figures, so one place decides how a
                // cached number is stated - the same reason the single `detail`
                // sentence this replaced was worded here. They are two strings
                // now because the design sets them in two roles: money is
                // `mono` in `text.money`, and the count is a caption.
                price: minor == null
                    ? 'Price unusable'
                    : '$currency ${_money(minor)}',
                priceUnusable: minor == null,
                stock: '${product.quantity} in stock',
                quantityInCart: _quantities[product.id] ?? 0,
                dense: dense,
                onTap: () => _add(product),
              );
            },
          ),
        ],
        SizedBox(height: tokens.spacing.s20),
      ],
    );
  }

  /// **§7's destructive pattern, in an `AlertDialog` on purpose.**
  ///
  /// `ConfirmDialog` is §5.1's own row for this and does not exist yet.
  ///
  /// **The confirm is §2.1's outlined destructive tier, and that is now the
  /// specification rather than a workaround.** §7 used to ask for a *filled*
  /// destructive confirm while §2.1 defined no filled destructive container at
  /// all; the tier below was chosen because inventing the missing colour is what
  /// `claude.md` forbids, and `design.md` **v0.6** withdrew the word on
  /// 2026-08-16 at the product owner's direction. Nothing here changed when it
  /// did, which is the outcome an amendment should have.
  Future<void> _confirmClearSale(BuildContext context) async {
    // **§7's own worked example, in §5.1's own component.** The consequence and
    // the reassurance were one paragraph; they are the two rows §7 asks for -
    // what happens, then what is still true, which is §8 rule 6.
    final confirmed = await showConfirmDialog(
      context,
      title: 'Clear this sale?',
      consequence: 'Every item is removed and the payment method is cleared.',
      stillTrue: 'Nothing has been saved yet, so no record is lost.',
      confirmLabel: 'Clear it',
      cancelLabel: 'Keep it',
      confirmKey: const ValueKey('checkout-clear-confirm'),
      cancelKey: const ValueKey('checkout-clear-cancel'),
    );
    if (confirmed && mounted) _clearSale();
  }

  List<Widget> _tenderSection(BuildContext context, AppTokens tokens) =>
      <Widget>[
        // **Cash is preselected, chosen by the product owner on 2026-08-23.**
        // This reverses the panel's original scope decision - "a pre-selected
        // payment method would be indistinguishable from an observed one" -
        // in favour of the speed of the common case. The consequence is
        // recorded rather than hidden: a sale whose tender nobody touched now
        // records `cash`, so the shift close's cash-against-sales comparison
        // and everything reconciliation derives from it can no longer tell an
        // observed cash sale from an unset one.
        //
        // `_blocker`'s null branch is kept as a guard rather than deleted: it
        // is now unreachable from the UI, and is what would still refuse the
        // save if a future path cleared the tender again.
        FilterChipBar<CheckoutTender>(
          semanticLabel: 'How the customer paid',
          selected: _tender,
          onSelected: (value) => value == null ? null : _chooseTender(value),
          options: <FilterChipOption<CheckoutTender>>[
            for (final option in CheckoutTender.values)
              FilterChipOption<CheckoutTender>(
                key: ValueKey('checkout-tender-${option.wireValue}'),
                value: option,
                label: option.label,
              ),
          ],
        ),
        SizedBox(height: tokens.spacing.s20),
      ];

  List<Widget> _saveSection(
    BuildContext context,
    AppTokens tokens,
    int? total,
  ) {
    if (widget.drafts == null) {
      return <Widget>[
        Callout(
          key: const ValueKey('checkout-unavailable'),
          status: _unavailable.status,
          message: _unavailable.message,
        ),
      ];
    }
    final blocker = _blocker(total);
    return <Widget>[
      // **§2.1's one `primary` per screen region.** It was a `FilledButton`
      // with a label that changed to "Saving..." mid-press, which is the exact
      // thing §2.1's loading row forbids - the container is held, the label is
      // replaced by a spinner, and the width is frozen so the button does not
      // resize under the finger that pressed it.
      AppButton(
        key: const ValueKey('checkout-save'),
        label: 'Save sale',
        tier: AppButtonTier.primary,
        expand: true,
        loading: _saving,
        onPressed: blocker == null && !_saving ? _save : null,
      ),
      if (blocker case final reason?) ...[
        SizedBox(height: tokens.spacing.s8),
        Text(
          key: const ValueKey('checkout-save-blocked'),
          reason,
          style: tokens.typography.caption.copyWith(
            color: tokens.colors.text.tertiary,
          ),
        ),
      ],
      if (_refusal case final refused?) ...[
        SizedBox(height: tokens.spacing.s16),
        // Every branch of [CheckoutRefusal] is a sale that was **not** written,
        // which is `AppNotice.refused` whatever `cashierCanFix` says: that flag
        // decides what to do next, not whether anything happened.
        Callout(
          key: const ValueKey('checkout-refusal'),
          status: AppNotice.refused(refused.message).status,
          message: refused.message,
        ),
        // §8 rule 6, "say what is still true", and it is a different fact from
        // the refusal itself - so it stays its own line rather than being
        // concatenated into one paragraph a cashier has to read to the end of.
        if (!refused.cashierCanFix) ...[
          SizedBox(height: tokens.spacing.s4),
          Text(
            key: const ValueKey('checkout-refusal-needs-help'),
            'Trying again will not clear this on its own.',
            style: tokens.typography.caption.copyWith(
              color: tokens.colors.text.tertiary,
            ),
          ),
        ],
      ],
    ];
  }
}

//// One sellable product in the grid.
///
/// **A depleted product is marked and stays sellable.** The panel's own scope
/// decision is that the cached figure never blocks a sale - it is what this
/// device last saw, not what the shop holds - so this changes what a cashier
/// can see at a glance and never what they can ring up. It is marked with a
/// glyph and a figure rather than by colour alone, because colour alone is not
/// readable to everyone and does not survive a photocopied training sheet.
///
/// **Two compositions, chosen by §4.1's band, because the two served designs
/// are two different tiles rather than one tile at two widths.** ST-035's till
/// card is dense text - name, code, then price and the cached figure on one row
/// - and carries no picture at all, because on that screen the cart is already
/// beside the grid and the grid's job is to fit as many products as it can. The
/// recovered mobile browse render leads with a picture band and drops the code,
/// because on a phone the grid is the whole screen and a thumb is aiming at it.
///
/// **The count badge is compact-only, and that is the same argument.** It says
/// how many of this product are already in the sale, which on a till screen the
/// cart pane says better and in full. On a phone the cart is behind a tap, so
/// the tile is the only place that fact can be.
final class _ProductTile extends StatelessWidget {
  const _ProductTile({
    super.key,
    required this.product,
    required this.price,
    required this.stock,
    required this.priceUnusable,
    required this.quantityInCart,
    required this.dense,
    required this.onTap,
  });

  final TenantProduct product;

  /// The money, worded by the panel so that one place decides how a cached
  /// figure is stated. `Price unusable` where this till cannot record it.
  final String price;

  /// The cached stock figure, stated verbatim and never rounded to a word.
  ///
  /// **`-3 in stock` rather than `Out of stock`, which is where this diverges
  /// from both served designs.** They write the state; this writes the figure,
  /// because the figure is the thing a cashier is checking and because a cached
  /// count in this app can be *negative* - Firestore Rules permit signed stock
  /// deliberately - and no word carries that. `0 in stock` says what `Out of
  /// stock` says; `-3 in stock` says something it cannot.
  final String stock;

  /// Whether [price] is a refusal rather than an amount.
  ///
  /// [AppTextRoles.money] is for money. A price this till cannot record
  /// exactly is not an amount, so it takes §2.1's `problem` instead.
  final bool priceUnusable;

  /// How many of this product the sale already holds. Zero for none.
  final int quantityInCart;

  /// Whether this is the till-screen card rather than the phone one.
  final bool dense;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final depleted = product.quantity <= 0;
    final problem = tokens.colors.status.problem;
    // §2.3's row for "cards, rows, sheets".
    final radius = BorderRadius.circular(tokens.radius.md);
    // **A tile already in the sale is outlined in the action colour**, at the
    // same one-pixel width every other border in this app is drawn at. Both
    // served designs draw two; a second border width is a value §2.3 does not
    // have, and the badge beside it carries the same fact as a figure.
    final Color border;
    if (depleted) {
      border = problem.border;
    } else if (quantityInCart > 0 && !dense) {
      border = tokens.colors.action.primary.container;
    } else {
      border = tokens.colors.surface.borderSubtle;
    }
    return PressSurface(
      // §2.4's press, and §5.1's own replacement for the `InkWell` this used to
      // be. The ripple was already dead at the theme since step 2; what was
      // missing on the most-pressed control in the app was the scale.
      borderRadius: radius,
      onPressed: onTap,
      fillWidth: true,
      fillHeight: true,
      hoverOverlay: tokens.colors.action.secondary.hoverFill(),
      pressedOverlay: tokens.colors.action.secondary.pressedFill(),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.colors.surface.raised,
          borderRadius: radius,
          // **A depleted tile keeps its red edge and never relies on it.** §9
          // forbids status by hue alone, and the glyph and the figure below are
          // what carry it; the border is the same signal drawn again.
          border: Border.all(color: border),
        ),
        // The band bleeds to the card's own corners rather than sitting inside
        // the padding, which is what the browse render draws and what stops a
        // 96-pixel rectangle looking like a second, smaller card.
        child: ClipRRect(
          borderRadius: radius,
          child: dense
              ? _denseBody(tokens, problem)
              : _bandedBody(tokens, problem),
        ),
      ),
    );
  }

  /// ST-035's till card: no picture, and the code a scanner reads is on it.
  ///
  /// **`MainAxisSize.max`, which is what makes a grid of these a grid.**
  /// `PressSurface.fillHeight` offers the whole cell but the constraints it
  /// passes on are loose, so a `min` column shrink-wrapped its own text and sat
  /// centred in the cell - a row of tiles with a one-line name beside a two-line
  /// one drew two different card heights with ragged gaps between the rows. The
  /// `Spacer` below was inert for the same reason: a flex child of a `min`
  /// column gets no space to take.
  ///
  /// **The price and the cached figure take two lines here, where ST-035 puts
  /// them on one.** That row works in the served design because its stock label
  /// is set at ten pixels; §2.1 makes `caption` at twelve the floor for anything
  /// a person is expected to read, and this app has no role below it. Two
  /// figures at `mono` 14 and `caption` 12 do not both fit the 158 logical
  /// pixels a three-column grid leaves at 1024 - the first attempt drew
  /// `KES 145.…` - and an ellipsised price on a till is the one thing this
  /// screen may not do. So they stack, which also makes the two tiles one
  /// grammar: name, then money, then the figure.
  Widget _denseBody(AppTokens tokens, AppStatusRole problem) => Padding(
    padding: EdgeInsets.all(tokens.spacing.s8),
    child: Column(
      mainAxisSize: MainAxisSize.max,
      // `stretch`, so the card fills the grid cell it was given rather than
      // shrink-wrapping its longest line: `PressSurface.fillWidth` offers the
      // whole cell but passes loose constraints on, so a `start` column drew
      // four cards of four different widths with ragged gutters between them.
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _name(tokens),
        // **§2.2's `mono` row - "record IDs and SKUs, strings a person compares
        // character by character".** ST-035 puts the product's code under its
        // name in `data-mono`, and this is the one surface where a cashier
        // reads a code off the screen to check it against the one in their
        // hand.
        if (product.sku.isNotEmpty)
          Text(
            key: ValueKey('checkout-product-code-${product.id}'),
            product.sku,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tokens.typography.mono.copyWith(
              color: tokens.colors.text.tertiary,
            ),
          ),
        const Spacer(),
        SizedBox(height: tokens.spacing.s4),
        _price(tokens),
        _stock(tokens, problem),
      ],
    ),
  );

  /// The browse render's phone card: a picture band, then the same facts.
  ///
  /// **The name is at the top and the money is at the bottom**, which is the
  /// render's own `justify-between` and is what lets a cashier read down the
  /// price column of a grid whose names are one line and two. See [_denseBody]
  /// for why the columns are `max` rather than `min`.
  Widget _bandedBody(AppTokens tokens, AppStatusRole problem) => Column(
    mainAxisSize: MainAxisSize.max,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      // **The badge is Material's, painted from §2.1**, which is the decision
      // `_CartBar` already took for the same figure: a count of items in a cart
      // is not a problem and must not be drawn in the palette's critical
      // colour.
      //
      // Inset by `space.4` on both axes rather than left on Material's default,
      // which hangs the label over the corner - and this card clips to its own
      // radius, so a hanging badge is a cut badge.
      Badge(
        key: ValueKey('checkout-product-count-${product.id}'),
        isLabelVisible: quantityInCart > 0,
        alignment: AlignmentDirectional.topEnd,
        offset: Offset(-tokens.spacing.s4, tokens.spacing.s4),
        backgroundColor: tokens.colors.action.primary.container,
        textColor: tokens.colors.action.primary.label,
        label: Text('$quantityInCart'),
        child: SizedBox(
          height: _productThumbnailBandHeight,
          width: double.infinity,
          child: TenantProductVisual(product: product),
        ),
      ),
      Expanded(
        child: Padding(
          padding: EdgeInsets.all(tokens.spacing.s8),
          child: Column(
            mainAxisSize: MainAxisSize.max,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _name(tokens),
              const Spacer(),
              SizedBox(height: tokens.spacing.s4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        _price(tokens),
                        _stock(tokens, problem),
                      ],
                    ),
                  ),
                  SizedBox(width: tokens.spacing.s4),
                  _addGlyph(tokens),
                ],
              ),
            ],
          ),
        ),
      ),
    ],
  );

  /// The *add* glyph at the card's foot, asked for on 2026-08-23.
  ///
  /// **An affordance, not a second button.** The whole tile is already the
  /// control - `PressSurface` wraps it and its `onTap` adds the product - so a
  /// nested button here would be a second target for one action, announce the
  /// same thing twice to a screen reader, and start a gesture fight with the
  /// tile underneath it. It carries no gesture and is excluded from semantics
  /// for exactly that reason; §9's 48dp minimum is met by the tile, which is
  /// what a thumb is actually hitting.
  Widget _addGlyph(AppTokens tokens) => ExcludeSemantics(
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.colors.action.primary.container,
        shape: BoxShape.circle,
      ),
      child: Padding(
        padding: EdgeInsets.all(tokens.spacing.s4),
        child: Icon(
          Icons.add,
          size: tokens.spacing.s16,
          color: tokens.colors.action.primary.label,
        ),
      ),
    ),
  );

  /// §2.2's `title.md`: "card title, **record name**".
  Widget _name(AppTokens tokens) => Text(
    product.name,
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
    style: tokens.typography.titleMedium.copyWith(
      color: tokens.colors.text.primary,
    ),
  );

  /// The money, in the pair `docs/stitch/OPEN_QUESTIONS.md` decision 23 chose
  /// for this surface: [AppTypeRoles.mono] and [AppTextRoles.money].
  Widget _price(AppTokens tokens) => Text(
    key: ValueKey('checkout-product-price-${product.id}'),
    price,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: tokens.typography.mono.copyWith(
      color: priceUnusable
          ? tokens.colors.status.problem.fg
          : tokens.colors.text.money,
    ),
  );

  /// The cached figure, with §2.1's `problem` glyph on it where it is spent.
  ///
  /// **No coloured dot for the ordinary case.** Both served designs put a
  /// six-pixel disc beside the figure; six is a size neither §2.3 nor Profound
  /// Verdant has, and a dot that is present whatever the state signifies
  /// nothing. The glyph slot carries the one case that means something.
  Widget _stock(AppTokens tokens, AppStatusRole problem) {
    final depleted = product.quantity <= 0;
    final figure = Text(
      key: ValueKey('checkout-product-stock-${product.id}'),
      stock,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: tokens.typography.caption.copyWith(
        color: depleted ? problem.fg : tokens.colors.text.tertiary,
      ),
    );
    if (!depleted) return figure;
    return Row(
      key: ValueKey('checkout-product-depleted-${product.id}'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          AppStatus.problem.defaultIcon,
          size: StatusBadge.iconSize,
          color: problem.fg,
        ),
        SizedBox(width: tokens.spacing.s4),
        Flexible(child: figure),
      ],
    );
  }
}

/// The compact layout's standing cart summary.
///
/// It states the total without the sheet being open, because that is the
/// number a customer is waiting to hear and putting it behind a tap is what
/// made the old single-scroll layout slow.
final class _CartBar extends StatelessWidget {
  const _CartBar({
    required this.currency,
    required this.total,
    required this.itemCount,
    required this.onOpen,
  });

  final String currency;
  final int? total;
  final int itemCount;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final accent = tokens.colors.action.primary;
    final unavailable = total == null;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.colors.surface.raised,
        // The bar is the only thing separating the products from the page edge
        // on a phone, so its top edge is a boundary a person must perceive -
        // §9's own words for when the 3:1 row applies rather than not.
        border: Border(
          top: BorderSide(color: tokens.colors.surface.borderStrong),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: tokens.spacing.s16,
            vertical: tokens.spacing.s12,
          ),
          child: Row(
            children: [
              // **The word and the figure are two texts as of Phase 03, and the
              // browse render is why.** Its bar sets `Total:` as a label and the
              // amount as money - which is the whole of `OPEN_QUESTIONS.md`
              // decision 23 - and `Total: KES 130.00` in one string cannot carry
              // two roles. `numeric.body` was the right role for a sentence and
              // is the wrong one for a figure that is the point of the bar.
              //
              // **A `StatLine` here overflowed at 411, which is worth recording
              // rather than quietly reverting.** That component is a label
              // column and a right-aligned figure column, sized for a card where
              // several of them stack; this strip has one figure and about 200
              // logical pixels to put it in beside the control, so the label
              // column and the figure column fought over the same room.
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Total',
                      style: tokens.typography.labelMedium.copyWith(
                        color: tokens.colors.text.secondary,
                      ),
                    ),
                    Text(
                      key: const ValueKey('checkout-cart-bar-total'),
                      unavailable
                          ? 'Unavailable'
                          : '$currency ${_money(total!)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tokens.typography.mono.copyWith(
                        color: unavailable
                            ? tokens.colors.status.problem.fg
                            : tokens.colors.text.money,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: tokens.spacing.s12),
              Badge(
                key: const ValueKey('checkout-cart-badge'),
                isLabelVisible: itemCount > 0,
                // **Painted from §2.1 rather than from Material's default**,
                // which is the error red - a count of items in a cart is not a
                // problem, and drawing it in the palette's critical colour is
                // precisely the "one colour doing seven jobs" §1 objects to.
                backgroundColor: accent.container,
                textColor: accent.label,
                label: Text('$itemCount'),
                child: AppButton(
                  key: const ValueKey('checkout-open-cart'),
                  // §8 rule 3 and §5.2: a button label is "always a verb phrase
                  // naming the effect". It said "Cart", which is the noun for
                  // where it goes rather than the verb for what it does - and
                  // §11 step 11's copy pass could not reach this screen,
                  // because the whole file was step 7's.
                  //
                  // **`primary`, which the browse render draws and this did
                  // not.** §2.1 allows one primary per screen *region*; the bar
                  // is a region of its own on the one layout where the save is
                  // not on screen at all, so nothing here competes with it.
                  label: 'Open the cart',
                  tier: AppButtonTier.primary,
                  icon: Icons.shopping_cart_outlined,
                  onPressed: onOpen,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _CartLine extends StatelessWidget {
  const _CartLine({
    super.key,
    required this.product,
    required this.productId,
    required this.quantity,
    required this.quantityUnusable,
    required this.currency,
    required this.onQuantityChanged,
    required this.onIncrement,
    required this.onDecrement,
    required this.onRemove,
  });

  /// Null when the cached catalog no longer holds the product.
  final TenantProduct? product;
  final String productId;
  final int quantity;

  /// Whether the field currently holds something that is not a usable
  /// quantity. The line still carries [quantity], its last usable value.
  final bool quantityUnusable;

  final String currency;
  final ValueChanged<String> onQuantityChanged;

  /// Adds one more of this line's product. **Not a new operation** - it is what
  /// pressing the product's tile in the grid already does, through the same
  /// callback, surfaced where a person is already looking.
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final resolved = product;
    final minor = resolved == null
        ? null
        : checkoutMinorUnitsFromMajor(resolved.price);
    final note = tokens.typography.caption.copyWith(
      color: tokens.colors.text.tertiary,
    );
    return Padding(
      padding: EdgeInsets.only(bottom: tokens.spacing.s8),
      child: DecoratedBox(
        // A `Card` painted Material's own surface and elevation. §2.1 is blunt
        // that "depth is expressed by surface step, never by drop shadow", and
        // a raised surface with a hairline is what a card is everywhere else in
        // this app - `Callout` is made of the same two rows.
        decoration: BoxDecoration(
          color: tokens.colors.surface.raised,
          border: Border.all(color: tokens.colors.surface.borderSubtle),
          borderRadius: BorderRadius.circular(tokens.radius.md),
        ),
        child: Padding(
          padding: EdgeInsets.all(tokens.spacing.s12),
          // **Three rows rather than one, which is ST-036's card.** The name
          // and the removal share the top row, what the line comes to is on its
          // own beneath, and the stepper is under that. It was all one row, so
          // the name had about 130 logical pixels of a 420 pane and the controls
          // had the rest.
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  // **The picture, asked for on 2026-08-23.** A cashier
                  // checking a cart against a counter reads pictures faster
                  // than names, and the grid they picked from is all pictures.
                  // An unavailable product has none to draw, and its line says
                  // so in words rather than reserving a hole where a picture
                  // would be.
                  if (resolved != null) ...<Widget>[
                    SizedBox(
                      key: ValueKey('checkout-line-image-$productId'),
                      height: _cartLineThumbnailSide,
                      width: _cartLineThumbnailSide,
                      child: TenantProductVisual(product: resolved),
                    ),
                    SizedBox(width: tokens.spacing.s8),
                  ],
                  Expanded(
                    child: Text(
                      resolved?.name ?? 'Unavailable product',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tokens.typography.titleMedium.copyWith(
                        color: tokens.colors.text.primary,
                      ),
                    ),
                  ),
                  SizedBox(width: tokens.spacing.s8),
                  // **The removal sits with the name, which is ST-036's own
                  // arrangement.** §5.1's complaint names "delete" as part of
                  // the stepper's defect, and what was wrong with it is that it
                  // sat *inside* the count control - one press away from a
                  // decrement, doing something a decrement cannot be undone
                  // from. Removing a line is a record action, so it sits with
                  // the record's name.
                  //
                  // **It shared the stepper's row until it did not fit.** A
                  // stepper is 188 wide at its widest bound and a labelled
                  // button about 150; a 411 phone leaves 347 inside the card,
                  // and a `Row` that does not fit throws rather than shrinking.
                  // Splitting them gives each its own width, and it is the
                  // served design's layout rather than a workaround for one.
                  //
                  // **A glyph with a name nobody sees, since 2026-08-23.**
                  // The note this replaces argued that §9 wants a word on the
                  // one control that discards a line - and §9 wants a
                  // *semantic label*, which [AppIconButton] requires. What the
                  // visible word bought was a red bordered box as wide as the
                  // product name beside it, on every line of the cart. Both
                  // served designs draw a 44-square bin in `text-error` with a
                  // 30% edge; this is that, at §9's 48.
                  AppIconButton(
                    key: ValueKey('checkout-line-remove-$productId'),
                    icon: Icons.delete_outline,
                    semanticLabel: resolved == null
                        ? 'Remove this line'
                        : 'Remove ${resolved.name}',
                    tier: AppButtonTier.destructive,
                    onPressed: onRemove,
                  ),
                ],
              ),
              Text(
                key: ValueKey('checkout-line-amount-$productId'),
                minor == null
                    ? 'This item cannot be priced on this device.'
                    : '$quantity x $currency ${_money(minor)}'
                          ' = $currency ${_money(minor * quantity)}',
                // **`mono` in `text.money`, which is `OPEN_QUESTIONS.md`
                // decision 23 for this surface.** It was `numeric.body` in
                // `text.secondary` - the right role for money inside a sentence
                // and the wrong one for the figure the customer is being
                // charged. Both served designs set a line amount in `data-mono`
                // and `currency-kes`.
                //
                // **The unit price stays in the string, where both designs drop
                // it.** They show only what the line comes to, because their
                // stepper carries the count; this keeps `2 x KES 20.00 = KES
                // 40.00` because *how much is one* is the question a cashier is
                // asked across a counter, and the app's own answer to it should
                // not need arithmetic. A line that cannot be priced is not money
                // and takes `problem` instead.
                style: tokens.typography.mono.copyWith(
                  color: minor == null
                      ? tokens.colors.status.problem.fg
                      : tokens.colors.text.money,
                ),
              ),
              SizedBox(height: tokens.spacing.s8),
              // **§5.1's priority 1, and the plus is the whole of it.** That
              // row's "Replaces" column reads "minus + delete, no plus", so a
              // cashier who rang up one loaf and needed two had to leave the
              // cart, find the tile in the grid and press it again.
              //
              // **The minus still does exactly what it did**, including removing
              // the line at one: that is state logic and `claude.md` hard rule 1
              // keeps it out of a visual change. Whether a stepper should
              // *disable* at one instead is a behaviour question and is in
              // `PLAN.md`, not decided here.
              Align(
                alignment: Alignment.centerLeft,
                child: QuantityStepper(
                  key: ValueKey('checkout-line-quantity-$productId'),
                  // **No visible label, and that is the component's own note.**
                  // Sixteen lines each saying *Quantity* over a minus, a number
                  // and a plus is the word repeated at a control that names
                  // itself - and it cost enough height to push the save off a
                  // phone. A screen reader still hears it.
                  quantity: quantity,
                  maximum: maximumCheckoutLineQuantity,
                  onChanged: onQuantityChanged,
                  // Null where the cached catalog no longer holds the product:
                  // there is nothing to add another of.
                  onIncrement: product == null ? null : onIncrement,
                  onDecrement: onDecrement,
                  error: quantityUnusable
                      ? 'Not a quantity this register can sell. This line still '
                            'has $quantity.'
                      : null,
                ),
              ),
              // Stated, never enforced: the cached figure is what this device
              // last saw, and the server permits stock to go negative.
              if (resolved != null && quantity > resolved.quantity)
                Padding(
                  padding: EdgeInsets.only(top: tokens.spacing.s4),
                  child: Text(
                    key: ValueKey('checkout-line-stock-$productId'),
                    'This device last saw ${resolved.quantity} in stock. The '
                    'sale is not blocked by that count.',
                    style: note,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

String _money(int minorUnits) => (minorUnits / 100).toStringAsFixed(2);

/// Thousands separators, so a bound quoted to a cashier stays readable and
/// stays derived from the constant it describes.
String _grouped(int value) {
  final digits = value.toString();
  final buffer = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) buffer.write(',');
    buffer.write(digits[index]);
  }
  return buffer.toString();
}
