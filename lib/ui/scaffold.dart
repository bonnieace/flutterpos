/// `AppScaffold` and `PageHeader`: `design.md` §11 step **5a**.
///
/// **Step 5 is split, and only half of it is here.** `DESIGN-AUDIT.md` §6
/// decision 3 divides §11 step 5 into 5a - the page frame, visual only - and 5b
/// - §4.4's navigation model, which is a behaviour change and needs a device
/// check. This file is 5a. Nothing in it reads a route, decides a destination,
/// or changes what any screen does.
///
/// **The defect it closes is §7's, stated in one line: "Title appears once."**
/// Today every route builds its own `Scaffold(appBar: AppBar(title: Text(…)))`,
/// which is Material's title slot and is therefore stuck at Material's size and
/// Material's position. §2.2 does not agree with either: it gives the screen
/// title `display` **32 / 40 at weight 700** on an expanded surface, which no
/// 56-high toolbar can hold, and `title.lg` 22 / 28 on a compact one. A screen
/// title that big is a piece of *content*, not a piece of chrome, so it moves
/// into the page and the toolbar keeps only what is genuinely chrome: the way
/// back, and the app-level actions that were already sitting beside the title.
///
/// **The cost of that is real and is written down rather than discovered.** A
/// route now spends a toolbar *and* a header before its content starts, where
/// it used to spend a toolbar. On a 411 x 891 phone that is roughly 128 logical
/// pixels of frame instead of 56. It buys §7's page pattern and §2.2's title
/// roles, and whether it reads as generous or as wasteful is a judgement no
/// screenshot settles - see `PLAN.md`, which carries it as a device-run item.
///
/// **Which states apply, and why the other six do not.** §5's matrix is the
/// matrix of a *control*. A page frame is not one: it has no hover, no
/// focus-visible, no pressed, no disabled and no loading, because there is
/// nothing to do to it - the one thing on it that can be pressed is the
/// caller's own [PageHeader.primaryAction], which is an `AppButton` and brings
/// its own six. `error` and `empty` belong to the *content* a screen puts in
/// [AppScaffold.body], and they are `ErrorState` and `EmptyState` in §5.1,
/// neither of which exists yet. What actually varies here is the frame's own
/// shape - title alone, title and subtitle, with and without a primary action,
/// with and without toolbar actions, and the two title roles either side of
/// §4.1's `expanded` boundary - and that is the matrix in the harness.
///
/// **5b's second half landed here rather than in a screen, which is §4.4's own
/// instruction.** "The side menu belongs to `AppScaffold`, not to a nested
/// `Navigator`" - so the frame owns the navigation column: its width, its
/// scroll, and the fact that it sits outside the page's content maximum the way
/// the toolbar already does. [AppScaffold.navigation] is that slot. It is empty
/// at 25 of the 26 call sites and the reason is a decision rather than an
/// unfinished sweep; see that field.
///
/// **One of the two things step 5a deliberately left is now done, in step 6.**
/// §4.2's content widths are in: [AppScaffold.contentWidth] is required at every
/// call site, and the seam step 5a built - one widget between every route and
/// its content - is what let 25 screens get a maximum width on one day. See that
/// field for why it is required rather than defaulted.
///
/// **The other is still owed:**
///
/// - **It resolves no density.** §3 says density is "chosen by the screen", and
///   this is the widget a screen would choose it on; `lib/ui/tokens.dart` has
///   been carrying that as owed since step 1. It is still owed. The rule §3
///   attaches to it - "a touch device never gets 32px targets whatever its
///   width" - needs a way to answer *is this a pointer device*, and Flutter has
///   no honest one; inventing a policy for it inside a restyling chunk is what
///   `claude.md` forbids. Recorded in `PLAN.md` as a question rather than
///   answered here.
library;

import 'package:flutter/material.dart';

import 'buttons.dart';
import 'home_navigation.dart';
import 'press.dart';
import 'tokens.dart';

/// A screen's title, its optional subtitle, and its optional primary action.
///
/// §7's page pattern, first row: *`PageHeader` (title, optional subtitle,
/// optional primary action) → optional `Callout` → filters → content →
/// pagination*. This is that row and nothing else; the rest of the pattern is
/// the caller's body, in that order.
///
/// **The title role is chosen by width, and the boundary is not a new one.**
/// §2.2 marks `display` "expanded only" and `title.lg` "screen title
/// (compact)", so the role has to be resolved against §4.1's `expanded` floor.
/// **Step 6 renamed that floor rather than moving it**: step 5a read
/// `tenantTableBreakpoint` in `records.dart`, which was 1024, and this now reads
/// [AppBreakpoint.expanded] off [AppLayout], which is the same 1024 under
/// §4.1's own name. Nothing about which role a given width gets has changed.
///
/// **It draws no padding of its own.** [AppScaffold] pads it, because the
/// padding that matters is the page's and a header that carried its own would
/// double it wherever a caller placed one inside an already-padded column.
final class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.primaryAction,
  });

  /// The screen's name, in the shopkeeper's words. Sentence case, §8 rule 7.
  ///
  /// **Never truncated.** §5.2 says that of a record's identity and the same
  /// argument is stronger here: a person who cannot read the whole title does
  /// not know which screen they are on. A long one wraps.
  final String title;

  /// One line under the title, where the screen needs to say which slice of
  /// something it is showing - a date, a product, a period.
  ///
  /// Optional, and populated at no call site yet: every route migrated in step
  /// 5a kept its existing title verbatim, because rewriting a title into a
  /// title-and-subtitle pair is a copy decision and §11 step 11 is the copy
  /// pass.
  final String? subtitle;

  /// The one action this page exists for, at the trailing edge of the title.
  ///
  /// A `Widget` rather than an `AppButton`, for the same reason `Callout`'s
  /// own action slot is: this component decides where an action sits and
  /// nothing at all about what it does.
  final Widget? primaryAction;

  /// Whether a [screenWidth] is wide enough for §2.2's `display` title role.
  ///
  /// **The screen's width, not the header's own box, and the difference is not
  /// pedantry.** §4.1 states its ranges as properties of the surface a person
  /// is looking at. The header's box is the page inset narrower than that, so
  /// resolving the role against a `LayoutBuilder` would flip it at 1064 on a
  /// padded page - a fourth breakpoint, produced by arithmetic, that nobody
  /// declared and nobody could look up.
  ///
  /// Exposed so a test can ask the same question the widget asks, rather than
  /// asserting a pixel width and hoping the two agree.
  ///
  /// **Reads [AppLayout.contract] rather than a theme, because a static has no
  /// context to read one from.** That is safe here and would not be for a
  /// density: [AppLayout] is the one part of the token set nothing overrides
  /// per subtree, and `test/ui/tokens_test.dart` asserts the registered set
  /// carries this exact contract so the two cannot drift.
  static bool showsDisplayTitle(double screenWidth) =>
      AppLayout.contract.isAtLeast(screenWidth, AppBreakpoint.expanded);

  /// Whether [screenWidth] has room for the title and the action side by side.
  ///
  /// **§4.1's `medium` floor, and it is the question the constant behind it was
  /// written to answer.** `tenantWideLayoutBreakpoint`'s own comment said it
  /// "answers *is there room for two things side by side*", which is exactly
  /// this; `DESIGN-AUDIT.md` §5 records that it had **zero consumers** until
  /// step 5a, and step 6 folded it into [AppLayout.mediumFloor] at the same
  /// number.
  ///
  /// **Below it the action goes under the title rather than beside it**, and
  /// that is a correctness rule rather than a preference. Laid side by side on
  /// a phone, a `Row` hands the action all the width it asks for and the title
  /// takes what is left - which for a long product name and a five-word button
  /// is a two-pixel column of wrapped letters. §5.2's "never truncated" is
  /// about the title staying *readable*, and a title squeezed to nothing fails
  /// it more completely than an ellipsis would.
  static bool placesActionBesideTitle(double screenWidth) =>
      AppLayout.contract.isAtLeast(screenWidth, AppBreakpoint.medium);

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final screenWidth = MediaQuery.sizeOf(context).width;
    // **`display.compact` below the boundary, not `title.lg`, since
    // 2026-08-23.** The design names two screen-title sizes and they are
    // `headline-lg` 32 and `headline-lg-mobile` 28 - it has no 22 for a page
    // title, and every mobile composition in the export draws the screen's
    // name at 28. `title.lg` is the *section* role and stays one.
    final titleStyle = showsDisplayTitle(screenWidth)
        ? tokens.typography.display
        : tokens.typography.displayCompact;
    final words = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // A heading to a screen reader, which is what an `AppBar.title`
        // announced before this component took the title off it. Losing that on
        // the way would be a silent accessibility regression in a change whose
        // whole subject is the title.
        Semantics(
          header: true,
          child: Text(
            title,
            style: titleStyle.copyWith(color: tokens.colors.text.primary),
          ),
        ),
        if (subtitle case final line?) ...<Widget>[
          SizedBox(height: tokens.spacing.s4),
          Text(
            line,
            style: tokens.density
                .body(tokens.typography)
                .copyWith(color: tokens.colors.text.secondary),
          ),
        ],
      ],
    );

    if (primaryAction case final action?) {
      if (placesActionBesideTitle(screenWidth)) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(child: words),
            SizedBox(width: tokens.spacing.s16),
            action,
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          words,
          SizedBox(height: tokens.spacing.s16),
          action,
        ],
      );
    }
    return words;
  }
}

/// The frame every route in the migrated tree sits in.
///
/// Replaces the ad-hoc `Scaffold(appBar: AppBar(title: Text(…)), body: …)` that
/// every route wrote for itself - §5.1's first two rows, `AppScaffold`
/// replacing "ad-hoc `Scaffold` per route" and `PageHeader` replacing
/// "duplicated title + subtitle".
///
/// ```
/// ┌─────────────────────────────────┐
/// │ ←                     [actions] │  toolbar: the way back, and chrome
/// ├──────────┬──────────────────────┤
/// │ New sale │ Manage catalog  [Add]│  navigation: §4.4's menu, expanded only
/// │ Catalog  │                      │  PageHeader: title, subtitle, action
/// │ Receipts │ …content…            │  density.sectionGap, then body
/// ```
///
/// **The toolbar keeps `AppBar` rather than being hand-drawn**, and that is a
/// `claude.md` hard rule 1 decision rather than a shortcut: `AppBar` owns the
/// leading control and its "should there be a way back from here" logic, the
/// safe-area inset, the scrolled-under treatment and the toolbar's own
/// semantics. Redrawing it would move routing behaviour into a visual change.
/// What it no longer owns is the title.
///
/// **It is not styled here either.** `spiritTheme`'s `AppBarTheme` already
/// paints it `surface.base` with no elevation, which is §2.1's "depth is a
/// surface step, never a drop shadow". A second opinion about the toolbar in
/// this file is a second place for it to drift.
final class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    required this.title,
    required this.body,
    required this.contentWidth,
    this.subtitle,
    this.primaryAction,
    this.actions = const <Widget>[],
    this.toolbarTitle,
    this.automaticallyImplyLeading = true,
    this.navigation = const <HomeDestination>[],
    this.onTitlePressed,
    this.titleActionLabel,
  }) : assert(
         onTitlePressed == null || titleActionLabel != null,
         'A title that is a control has to say what it opens: a chevron is '
         'not a word, and §9 does not let a control announce itself by its '
         'glyph.',
       );

  /// The screen's name. See [PageHeader.title].
  final String title;

  /// Which of §4.2's rows this screen's content is.
  ///
  /// **Required rather than defaulted, and that is a decision.** §4.2 opens
  /// "Every screen has a max content width", and it gives a different one to a
  /// form than to a table - so there is no value that is right when a call site
  /// says nothing. A default would also be silently wrong for the majority
  /// here: 20 of this app's 25 routes are record lists, so defaulting to
  /// [AppContentWidth.reading] would quietly narrow most of the app to 720 and
  /// defaulting to [AppContentWidth.records] would quietly widen every form to
  /// 1200. Requiring it puts the judgement in the diff, where a reviewer can
  /// disagree with it per screen.
  ///
  /// **What it fixes is §4.2's own example.** The catalog row whose *Correct*
  /// link sat 1,300 pixels from the product name it belongs to was an
  /// unconstrained `ListView` in a 1440 window; at 1200 the two are 1,160
  /// apart, and the rest of the distance is `RecordList`'s to close in the
  /// second half of this step.
  final AppContentWidth contentWidth;

  /// See [PageHeader.subtitle].
  final String? subtitle;

  /// See [PageHeader.primaryAction].
  final Widget? primaryAction;

  /// Chrome that belongs to the app rather than to the page - signing out,
  /// refreshing - kept in the toolbar where it already was.
  ///
  /// **Not the same slot as [primaryAction], and the split is the point.**
  /// §7 gives the page header "an optional primary action", meaning the thing
  /// the page exists for. *Sign out* is not what any of these pages exists for;
  /// it is beside the title today only because the toolbar is where a Material
  /// app puts everything. Moving it into the header would promote it.
  final List<Widget> actions;

  /// A brand lockup in the toolbar, for a route that has no way back.
  ///
  /// **Not the screen's title, and it is the one thing that may sit here.**
  /// §7's "title appears once" moved the page title into [PageHeader] and this
  /// does not undo that: the export's top bar carries the *product* name, in
  /// the accent, beside its mark - on the landing route, which is the only
  /// route with no back arrow to fill the slot. Every other call site leaves
  /// it null and gets the bare toolbar §7 describes.
  final Widget? toolbarTitle;

  /// Forwarded to [AppBar.automaticallyImplyLeading] unchanged.
  final bool automaticallyImplyLeading;

  /// Makes the screen's own name the control that changes what it names.
  ///
  /// **One call site, and it is the home.** The title there is the business's
  /// name, which is the fact a person checks to find out which business they
  /// are in - so it is also where they reach to leave it. It carried a
  /// *Change business* tile in the grid until 2026-09-03, three screens of
  /// scrolling below the name it was about.
  ///
  /// Null everywhere else, which draws the plain title this frame has always
  /// drawn: a title that is sometimes a button and looks identical either way
  /// is worse than one that is never a button, which is the rule `ShiftBanner`
  /// states for the same reason.
  final VoidCallback? onTitlePressed;

  /// What pressing the title does, for a screen reader.
  ///
  /// **Required in practice**, since a chevron is not a word: §9 does not let
  /// a control announce itself by its glyph. Asserted rather than defaulted so
  /// a second call site has to say what its own title opens.
  final String? titleActionLabel;

  /// §4.4's navigation destinations, drawn as a persistent side menu at
  /// `expanded` and as nothing at all below it, where the page's own cards
  /// carry them.
  ///
  /// **A list of destinations rather than a `Widget` slot, and that is the
  /// opposite decision from [primaryAction] on purpose.** An action is the
  /// page's and the frame decides only where it sits; a navigation column is
  /// the *frame's*, and §4.4 fixes its width, its band and its relationship to
  /// the content maximum. A `Widget` here would let a call site put anything in
  /// a 256-wide column beside every page and call it navigation.
  ///
  /// **Empty at every call site but the home, and that is a decision rather
  /// than an unfinished sweep.** §4.4 asks for the menu on every route on the
  /// stated grounds that "`Navigator.pop` keeps meaning what it means", and on
  /// a route reached by a push it stops meaning it: every destination here is a
  /// `push`, so a menu on a pushed route grows the stack a route per press and
  /// a person who pressed three of them meets a back arrow three deep. The two
  /// things that would fix it are a nested `Navigator`, which §4.4 forbids by
  /// name, and popping to the home before pushing, which is a routing condition
  /// that `claude.md` hard rule 1 keeps out of a visual change. `PLAN.md`
  /// carries it as an open decision; the slot is here so answering it is one
  /// call site rather than a component.
  final List<HomeDestination> navigation;

  /// Everything below the header, in §7's order: optional `Callout`, filters,
  /// content, pagination.
  final Widget body;

  /// The page's own horizontal inset.
  ///
  /// **A component decision on §2.3's scale, not a token, and it is
  /// provisional.** No section of `design.md` states a page padding; §4.2
  /// states a maximum content *width*, which is a different thing and is now
  /// [contentWidth]. `space.20` is what the three largest list screens in this
  /// app already pad their bodies with (`EdgeInsets.all(20)` on the catalog,
  /// the daily summary and reconciliation status), so the header lines up with
  /// the content under it on the screens where lining up is most visible.
  ///
  /// **The three routes that padded 24 now pad this**, which is the unification
  /// step 5a recorded as owed: checkout settings and the shell's two invitation
  /// screens were 4 pixels out from their own headers. Nothing else moved to
  /// reach it - the figure is still 20 and every other body already used it.
  static double horizontalInset(AppSpacing spacing) => spacing.s20;

  /// The page column §4.2's maximum is applied to.
  ///
  /// **A testing seam, and it is one because the thing it names stopped being
  /// findable.** A test measured `PageHeader` to learn how wide the page came
  /// out; the header block is gone and the column it sat in has no type of its
  /// own, so the frame names it rather than a test guessing at a `Column`.
  static const Key pageKey = ValueKey('app-scaffold-page');

  /// How tall the bar is when a route names what it is scoped to.
  ///
  /// The two lines the bar actually draws, plus `space.8` above and below.
  ///
  /// **Measured, not budgeted.** The title renders 31 high and the subtitle 21
  /// with no gap between them - 52 - and the 80 this used to be centred them
  /// with 14 of empty bar underneath the subtitle, on top of the gap the page
  /// column already spends and the 20 every body pads itself with. Exposed so
  /// a test can ask the question rather than asserting a pixel height and
  /// hoping the two agree.
  static const double toolbarHeightWithSubtitle = 68;

  /// Whether `AppBar` will draw something in its leading slot.
  ///
  /// The same three things `AppBar` itself asks: whether it may imply one at
  /// all, whether the `Scaffold` has a drawer for a hamburger to open, and
  /// whether there is a route beneath this one for a back arrow to pop.
  bool _hasLeading(BuildContext context, bool hasDrawer) =>
      automaticallyImplyLeading &&
      (hasDrawer || (ModalRoute.of(context)?.canPop ?? false));

  @override
  Widget build(BuildContext context) {
    // `componentOf`, not `of`: a route is pumped by widget tests that build
    // their own bare `ThemeData`, and crashing in all of them buys nothing. See
    // the accessor's own note for why the fallback cannot shrink a tap target.
    final tokens = AppTokens.componentOf(context);
    // The surface a person is looking at, not this frame's box - §4.1's ranges
    // and `PageHeader.showsDisplayTitle`'s note say the same thing, and the
    // menu is resolved against the same width the header's role is.
    final screenWidth = MediaQuery.sizeOf(context).width;
    // **The screen's name is in the toolbar as of 2026-08-23, and the header
    // block is gone.**
    //
    // §7 moved the title *out* of the toolbar on the grounds that §2.2 gives a
    // screen title `display` 32 and no 56-high bar can hold one. That was a
    // faithful reading of a document, and the design it was written for is not
    // the design this app is built to: the export's own mobile header is
    // `<h1 class="text-section-title text-on-surface">This sale</h1>` inside a
    // 64-high bar, beside the back arrow. 22 fits, and §2.2's 32 is what the
    // *desktop* compositions use for a page that has room for it.
    //
    // **What it bought is the whole reason it moved back.** The frame spent 20
    // above the title, a 33-pixel line, a subtitle, and a section gap - about
    // 130 logical pixels of every route, before a single record. On a 360
    // handset that is a fifth of the screen saying which screen you are
    // already on. The product owner asked for it back on 2026-08-23; the
    // toolbar was already drawing a bar of chrome and now it says something.
    //
    // §7's "title appears once" is unchanged and still asserted: it appears in
    // the toolbar, and nowhere else.
    final page = Column(
      key: pageKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // **`space.8`, and it is the only gap this column spends.** Every body
        // in the tree pads itself - `horizontalInset`'s note names the 20 the
        // list screens use on all four sides - so a `space.16` here was a
        // second opinion stacked on a first, and the two of them put 36 pixels
        // of nothing between the toolbar and the first row of a page.
        SizedBox(height: tokens.spacing.s8),
        Expanded(child: body),
      ],
    );
    final maximum = tokens.layout.maxWidthOf(contentWidth);
    // **The header and the body are constrained together, above the body's
    // own padding.** §4.2 caps *content*, and a screen whose title sat at the
    // window edge while its records sat in a centred 1200 column would read
    // as two pages. Constraining the shared column is also what keeps the
    // header's 20 inset lined up with the 20 every body pads itself with.
    //
    // **The toolbar is deliberately outside it.** A back arrow that drifted
    // inwards on a wide window, away from the corner every platform puts it
    // in, would be chrome obeying a content rule.
    //
    // **[AppContentWidth.full] adds no widget rather than an unbounded one.**
    // `maxWidthOf` answers null there, and a `ConstrainedBox` that constrains
    // nothing is a line of code that has to be read before it can be ignored.
    final Widget content = maximum == null
        ? page
        : Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maximum),
              child: page,
            ),
          );
    // **The destinations are a drawer below `expanded` and a column above
    // it**, which is the design's own arrangement: its mobile top bar carries
    // a `menu` button and its desktop draws the sidebar permanently. Building
    // the drawer is what puts the hamburger in the toolbar - `Scaffold` adds
    // it as the leading control whenever there is a drawer and no way back -
    // so a route with no destinations gets neither, unchanged.
    final drawn = navigation.isEmpty
        ? null
        : HomeNavigation.showsMenu(screenWidth)
        ? _NavigationColumn(destinations: navigation, tokens: tokens)
        : null;
    final hasDrawer =
        navigation.isNotEmpty && !HomeNavigation.showsMenu(screenWidth);
    return Scaffold(
      backgroundColor: tokens.colors.surface.base,
      drawer: hasDrawer
          ? _NavigationDrawer(destinations: navigation, tokens: tokens)
          : null,
      appBar: AppBar(
        automaticallyImplyLeading: automaticallyImplyLeading,
        // **Taller when there is a subtitle**, which is the export's own
        // header: a title and a small second line naming what the page is
        // scoped to. Six routes carry one - which reconciliation run, which
        // shift, which receipt - and it is the kind of fact a person needs
        // before they read a single row.
        toolbarHeight: subtitle == null ? null : toolbarHeightWithSubtitle,
        // **No middle spacing where a leading control supplies the gap, and
        // the ordinary inset where none does.** `NavigationToolbar` reserves
        // 16 on each side of the title by default; between a hamburger, a
        // reload glyph and a way out there are 144 pixels of control on a
        // pushed route already, and the 32 was the difference between
        // `Dev Corner Shop` and `Dev Corner S…` on a real handset.
        //
        // **The sentence that justified it was "the leading control's own 48
        // square is the gap", and on the home there is no leading control.**
        // It has no drawer and nothing to pop, so the business's name was
        // printed hard against the edge of the screen. Reported on a device on
        // 2026-09-03.
        titleSpacing: _hasLeading(context, hasDrawer) ? 0 : tokens.spacing.s16,
        // `section-title`, which is the role the export's own header uses and
        // the largest §2.2 has that fits a toolbar. Never wrapped: a title on
        // two lines in a 56-high bar pushes the page down for a word, so a
        // long one ellipsises.
        title: _Title(
          title: title,
          subtitle: subtitle,
          onPressed: onTitlePressed,
          actionLabel: titleActionLabel,
        ),
        // **The one action a page exists for goes at the trailing edge.** It
        // sat beside the title in the header block; the block is gone, and the
        // trailing edge of the bar is where the export puts a page's own
        // control.
        actions: actions.isEmpty && primaryAction == null
            ? null
            : <Widget>[
                ...actions,
                if (primaryAction case final action?) action,
              ],
      ),
      body: drawn == null
          ? content
          : Row(
              // Both columns run the full height of the body. A menu that
              // stopped where its last row does would leave the page's
              // background showing through a column of chrome.
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                drawn,
                // **The maximum is measured against the page, and the page is
                // what is left after the menu.** §4.2 caps content, the menu is
                // not content, and centring 1200 in the whole window would push
                // a table under a column that is drawn on top of nothing.
                Expanded(child: content),
              ],
            ),
    );
  }
}

/// The screen's name, and where it is also the way to a different one.
///
/// **The affordance is a chevron after the words, not a styling of them.** A
/// title that changed colour or weight when it became pressable would be a
/// second title role; a glyph beside it is an addition, and it is the one the
/// platform's own switchers use.
final class _Title extends StatelessWidget {
  const _Title({
    required this.title,
    required this.subtitle,
    required this.onPressed,
    required this.actionLabel,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onPressed;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    // `section-title`, which is the role the export's own header uses and the
    // largest §2.2 has that fits a toolbar. Never wrapped: a title on two
    // lines in a 56-high bar pushes the page down for a word, so a long one
    // ellipsises.
    final lines = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: tokens.typography.titleLarge.copyWith(
            color: tokens.colors.text.primary,
          ),
        ),
        if (subtitle case final line?)
          Text(
            line,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tokens.typography.bodyMedium.copyWith(
              color: tokens.colors.text.secondary,
            ),
          ),
      ],
    );
    final press = onPressed;
    if (press == null) return Semantics(header: true, child: lines);
    return Semantics(
      header: true,
      button: true,
      label: '$title. $actionLabel.',
      excludeSemantics: true,
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: PressSurface(
          // Named so a test can address the control rather than the words in
          // it: the label is the business's name and changes per fixture.
          key: const ValueKey('screen-title-action'),
          borderRadius: BorderRadius.circular(tokens.radius.md),
          onPressed: press,
          excludeSemantics: true,
          child: Padding(
            // Only on the trailing side: the leading edge is already inset by
            // the toolbar, and padding it again would undo that.
            padding: EdgeInsetsDirectional.only(end: tokens.spacing.s8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Flexible(child: lines),
                SizedBox(width: tokens.spacing.s4),
                Icon(
                  Icons.expand_more,
                  size: AppButton.iconSize,
                  color: tokens.colors.text.secondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// §4.4's side menu, in the column the frame allocates for it.
///
/// **It scrolls on its own, and that is the answer to a question §4.4 does not
/// ask.** Eleven rows are about 600 tall, and `expanded` starts at 1024 wide
/// with no floor under the height at all - a 1024 x 600 window is a landscape
/// tablet and a half-height desktop window. A column that overflowed would
/// stripe the bottom of the navigation on the one band that has it. Its scroll
/// is separate from the page's, so scrolling a long table does not carry the
/// destinations off the top of the screen, which is the whole point of the menu
/// being persistent.
final class _NavigationColumn extends StatelessWidget {
  const _NavigationColumn({required this.destinations, required this.tokens});

  final List<HomeDestination> destinations;
  final AppTokens tokens;

  @override
  Widget build(BuildContext context) => Padding(
    // The page's own inset on the outside, and none on the inside: the content
    // beside it pads itself by the same 20, so the gap between the two columns
    // is the page inset rather than a figure invented here.
    padding: EdgeInsets.fromLTRB(
      AppScaffold.horizontalInset(tokens.spacing),
      tokens.spacing.s20,
      0,
      tokens.spacing.s20,
    ),
    child: SizedBox(
      width: HomeNavigation.menuWidth,
      child: SingleChildScrollView(
        child: HomeNavigation.menu(destinations: destinations),
      ),
    ),
  );
}

/// The product's mark and name, for [AppScaffold.toolbarTitle].
///
/// The export's top-bar lockup: a bordered 32-square tile carrying the mark,
/// then `UzaPay` at `body.lg` weight 700 in the accent. Every value is
/// a role - `surface.field` behind the tile, `border.strong` around it,
/// `radius.sm` on its corner, and `action.primary.container` for both the
/// glyph and the name.
///
/// **The name is a constant and not a token**, which is the one thing here
/// that could be argued with: it is the product's name rather than a business
/// name, so it is not read from a tenant document and there is nothing for it
/// to vary with.
final class AppBrandLockup extends StatelessWidget {
  const AppBrandLockup({super.key});

  /// The export's `w-8 h-8` mark tile.
  static const double markSize = 32;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final accent = tokens.colors.action.primary.container;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: markSize,
          height: markSize,
          decoration: BoxDecoration(
            color: tokens.colors.surface.field,
            borderRadius: BorderRadius.circular(tokens.radius.sm),
            border: Border.all(color: tokens.colors.surface.borderStrong),
          ),
          child: Padding(
            padding: EdgeInsets.all(tokens.spacing.s4),
            child: Image.asset('images/uzapay-mark.png', fit: BoxFit.contain),
          ),
        ),
        SizedBox(width: tokens.spacing.s8),
        // **Flexible, because the toolbar shares its middle slot.** A title
        // box is offered whatever the leading and trailing slots leave, and on
        // a phone with two actions beside it that is under 210 - narrower than
        // this lockup measures in the test face. It never wraps: a product
        // name on two lines in a 56-high toolbar is worse than an ellipsis.
        Flexible(
          child: Text(
            'UzaPay',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tokens.typography.bodyLarge.copyWith(
              color: accent,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

/// A section's name inside a page. The export's `h2`.
///
/// **`title.lg`, which is the design's `section-title`, and it replaced 35
/// inline copies of `title.md`.** Every exported composition names a section
/// with `font-section-title text-section-title text-on-surface` - 22 / 600 -
/// and the app was drawing them at 18 / 500, which put a section's name a
/// half-step above the body it introduced instead of a full one. The copies
/// were identical, so this is one value rather than thirty-five.
///
/// **Not [PageHeader], and the two are not interchangeable.** A page has one
/// title, at `display` or `display.compact`, and §7 says it appears once. A
/// section is a division *inside* that page, and a screen may have several.
final class SectionHeading extends StatelessWidget {
  const SectionHeading(this.text, {super.key});

  /// The section's name, in the shopkeeper's words. Sentence case, §8 rule 7.
  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Semantics(
      header: true,
      child: Text(
        text,
        style: tokens.typography.titleLarge.copyWith(
          color: tokens.colors.text.primary,
        ),
      ),
    );
  }
}

/// The destinations as a drawer, below `expanded`.
///
/// **A `Drawer` rather than a panel of this app's own**, for the reason
/// `AppScaffold` wraps `AppBar` rather than redrawing one: the framework owns
/// the scrim, the edge drag, the focus trap, the escape handling and the
/// route that closes it. What this file owns is what the panel is made of.
///
/// **It closes itself before it pushes.** A destination's own callback is a
/// `Navigator.push`, so without this the drawer would still be open underneath
/// the route that just arrived and would be there again on the way back.
/// `Navigator.pop` on the drawer's own route is not a routing *condition* -
/// nothing decides differently, the panel simply shuts - which is what keeps
/// it inside `claude.md` hard rule 1.
final class _NavigationDrawer extends StatelessWidget {
  const _NavigationDrawer({required this.destinations, required this.tokens});

  final List<HomeDestination> destinations;
  final AppTokens tokens;

  @override
  Widget build(BuildContext context) => Drawer(
    backgroundColor: tokens.colors.surface.base,
    shape: const RoundedRectangleBorder(),
    width: HomeNavigation.menuWidth,
    child: SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: EdgeInsets.fromLTRB(
              tokens.spacing.s16,
              tokens.spacing.s24,
              tokens.spacing.s16,
              tokens.spacing.s24,
            ),
            child: const AppBrandLockup(),
          ),
          Divider(height: 1, color: tokens.colors.surface.borderSubtle),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: tokens.spacing.s8,
                vertical: tokens.spacing.s16,
              ),
              child: HomeNavigation.drawer(
                destinations: <HomeDestination>[
                  for (final destination in destinations)
                    HomeDestination(
                      destinationKey: destination.destinationKey,
                      label: destination.label,
                      icon: destination.icon,
                      status: destination.status,
                      isPrimary: destination.isPrimary,
                      group: destination.group,
                      onPressed: destination.onPressed == null
                          ? null
                          : () {
                              Navigator.of(context).pop();
                              destination.onPressed!();
                            },
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
