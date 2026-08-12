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
    final titleStyle = showsDisplayTitle(screenWidth)
        ? tokens.typography.display
        : tokens.typography.titleLarge;
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
/// ├─────────────────────────────────┤
/// │ Manage catalog     [Add product]│  PageHeader: title, subtitle, action
/// │                                 │  density.sectionGap
/// │ …content…                       │  body
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
    this.automaticallyImplyLeading = true,
  });

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

  /// Forwarded to [AppBar.automaticallyImplyLeading] unchanged.
  final bool automaticallyImplyLeading;

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

  @override
  Widget build(BuildContext context) {
    // `componentOf`, not `of`: a route is pumped by widget tests that build
    // their own bare `ThemeData`, and crashing in all of them buys nothing. See
    // the accessor's own note for why the fallback cannot shrink a tap target.
    final tokens = AppTokens.componentOf(context);
    final inset = horizontalInset(tokens.spacing);
    final page = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: EdgeInsets.fromLTRB(inset, tokens.spacing.s20, inset, 0),
          child: PageHeader(
            title: title,
            subtitle: subtitle,
            primaryAction: primaryAction,
          ),
        ),
        // §3's own row for the gap between one section of a page and the
        // next. The header and the content are two sections.
        SizedBox(height: tokens.density.sectionGap),
        Expanded(child: body),
      ],
    );
    final maximum = tokens.layout.maxWidthOf(contentWidth);
    return Scaffold(
      backgroundColor: tokens.colors.surface.base,
      appBar: AppBar(
        automaticallyImplyLeading: automaticallyImplyLeading,
        actions: actions.isEmpty ? null : actions,
      ),
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
      body: maximum == null
          ? page
          : Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maximum),
                child: page,
              ),
            ),
    );
  }
}
