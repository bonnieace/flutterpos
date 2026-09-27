import 'package:flutter/semantics.dart';
import 'package:flutter/material.dart';
import 'package:uzapay_pos/theme.dart';
import 'package:uzapay_pos/ui/buttons.dart';
import 'package:uzapay_pos/ui/home_navigation.dart';
import 'package:uzapay_pos/ui/scaffold.dart';
import 'package:uzapay_pos/ui/tokens.dart';
import 'package:flutter_test/flutter_test.dart';

final _tokens = spiritTheme.extension<AppTokens>()!;

/// A width below §4.1's `expanded` floor, and one above it.
///
/// Written as arithmetic on the declared floor rather than as two literals, so
/// a test cannot keep passing after the boundary moves. Step 6 renamed the
/// declaration - `tenantTableBreakpoint` in `records.dart` became
/// `AppLayout.expandedFloor` - and did not move it.
final double _compactWidth = AppLayout.contract.expandedFloor - 1;
final double _expandedWidth = AppLayout.contract.expandedFloor;

/// Mounts [child] at [width], under the app's own theme.
Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  double? width,
  double height = 800,
  ThemeData? theme,
}) async {
  tester.view.physicalSize = Size(width ?? _compactWidth, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(theme: theme ?? spiritTheme, home: child),
  );
}

TextStyle _styleOf(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style!;

void main() {
  group('the screen title is chrome again, and says why', () {
    // **§7 moved the title out of the toolbar and 2026-08-23 moved it back.**
    // The original reading was faithful to `design.md` §2.2, which gives a
    // screen title `display` 32 - and no 56-high bar holds one. The design
    // this app is now built to writes its own mobile header as
    // `<h1 class="text-section-title">This sale</h1>` inside the bar, and 22
    // fits.
    //
    // What the header block cost is the reason it went: 20 above the title, a
    // 33-pixel line, a subtitle and a section gap - about 130 logical pixels
    // of every route, before a single record, on a screen 640 tall.
    testWidgets('it is `title.lg`, which is the export\'s own header role', (
      tester,
    ) async {
      await _pump(
        tester,
        const AppScaffold(
          contentWidth: AppContentWidth.records,
          title: 'Daily summary',
          body: SizedBox(),
        ),
      );

      final style = _styleOf(tester, 'Daily summary');
      expect(style.fontSize, _tokens.typography.titleLarge.fontSize);
      expect(style.fontWeight, _tokens.typography.titleLarge.fontWeight);
      expect(style.color, _tokens.colors.text.primary);
    });

    testWidgets('the same role at every band', (tester) async {
      // The header block resolved two roles against §4.1's `expanded` floor,
      // which is what `display` versus `title.lg` was for. A toolbar is the
      // same height on every surface, so there is one role and no boundary.
      for (final width in <double>[411, 834, 1440]) {
        await _pump(
          tester,
          const AppScaffold(
            contentWidth: AppContentWidth.records,
            title: 'Daily summary',
            body: SizedBox(),
          ),
          width: width,
        );
        expect(
          _styleOf(tester, 'Daily summary').fontSize,
          _tokens.typography.titleLarge.fontSize,
          reason: 'at $width',
        );
      }
    });

    testWidgets('a long one ellipsises rather than wrapping the bar', (
      tester,
    ) async {
      // §5.2 says a record's identity is never truncated below two lines and
      // the header block read that as "a long title wraps". A bar cannot: a
      // second line there pushes the whole page down for a word. One line,
      // ellipsised, and the route is still named by the way back to it.
      await _pump(
        tester,
        const AppScaffold(
          contentWidth: AppContentWidth.records,
          title: 'Reconciliation differences for the Nairobi Westlands branch',
          body: SizedBox(),
        ),
      );

      final title = tester.widget<Text>(
        find.text(
          'Reconciliation differences for the Nairobi Westlands branch',
        ),
      );
      expect(title.maxLines, 1);
      expect(title.overflow, TextOverflow.ellipsis);
    });

    testWidgets('a screen reader is told it is a heading', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        const AppScaffold(
          contentWidth: AppContentWidth.records,
          title: 'Activity log',
          body: SizedBox(),
        ),
      );

      expect(
        tester
            .getSemantics(find.text('Activity log'))
            .hasFlag(SemanticsFlag.isHeader),
        isTrue,
      );
      handle.dispose();
    });
  });

  group('the title appears once', () {
    testWidgets('in the toolbar, and nowhere in the body', (tester) async {
      // §7's rule is unchanged; only the place it holds true has moved.
      await _pump(
        tester,
        const AppScaffold(
          contentWidth: AppContentWidth.records,
          title: 'Find a receipt',
          body: SizedBox(),
        ),
      );

      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Find a receipt'),
        ),
        findsOneWidget,
      );
      expect(find.text('Find a receipt'), findsOneWidget);
    });

    testWidgets('a body that names the same thing is left alone', (
      tester,
    ) async {
      // The frame does not deduplicate. If a screen's content repeats its own
      // title that is the screen's business - and, on the one route where the
      // two strings can differ, deciding which is the title is a product
      // question rather than a framing one.
      await _pump(
        tester,
        const AppScaffold(
          contentWidth: AppContentWidth.records,
          title: 'Returns',
          body: Center(child: Text('Returns')),
        ),
      );

      expect(find.text('Returns'), findsNWidgets(2));
    });
  });

  group('the subtitle', () {
    testWidgets('is absent when none is given, and costs no height', (
      tester,
    ) async {
      await _pump(
        tester,
        const AppScaffold(
          contentWidth: AppContentWidth.records,
          title: 'Sales totals',
          body: SizedBox(),
        ),
      );

      expect(
        find.descendant(of: find.byType(AppBar), matching: find.byType(Text)),
        findsOneWidget,
      );
      expect(
        tester.widget<AppBar>(find.byType(AppBar)).toolbarHeight,
        isNull,
        reason: 'a bar with one line keeps Material\'s own height',
      );
    });

    testWidgets('names what the page is scoped to, under the title', (
      tester,
    ) async {
      // Six routes carry one - which reconciliation run, which shift, which
      // receipt - and it is the kind of fact a person needs before they read a
      // single row. The export's own header does the same: a title and a
      // small second line under it.
      await _pump(
        tester,
        const AppScaffold(
          contentWidth: AppContentWidth.records,
          title: 'Reconciliation status',
          subtitle: '2026-08-12 UTC',
          body: SizedBox(),
        ),
      );

      final style = _styleOf(tester, '2026-08-12 UTC');
      expect(style.fontSize, _tokens.typography.bodyMedium.fontSize);
      expect(style.color, _tokens.colors.text.secondary);
      expect(
        tester.getTopLeft(find.text('2026-08-12 UTC')).dy,
        greaterThan(tester.getTopLeft(find.text('Reconciliation status')).dy),
      );
      expect(
        tester.widget<AppBar>(find.byType(AppBar)).toolbarHeight,
        AppScaffold.toolbarHeightWithSubtitle,
      );
    });
  });

  group('the primary action', () {
    testWidgets('sits at the trailing edge of the bar', (tester) async {
      // It sat beside the title in the header block. The block is gone, and
      // the trailing edge of the bar is where the export puts a page's own
      // control.
      await _pump(
        tester,
        AppScaffold(
          contentWidth: AppContentWidth.records,
          title: 'Manage catalog',
          primaryAction: AppButton(
            label: 'Add a product',
            tier: AppButtonTier.primary,
            onPressed: () {},
          ),
          body: const SizedBox(),
        ),
      );

      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Add a product'),
        ),
        findsOneWidget,
      );
      expect(
        tester.getCenter(find.text('Add a product')).dx,
        greaterThan(tester.getCenter(find.text('Manage catalog')).dx),
      );
    });

    testWidgets('follows any toolbar actions rather than replacing them', (
      tester,
    ) async {
      await _pump(
        tester,
        AppScaffold(
          contentWidth: AppContentWidth.records,
          title: 'Manage catalog',
          actions: <Widget>[
            AppButton(
              label: 'Sign out',
              tier: AppButtonTier.tertiary,
              onPressed: () {},
            ),
          ],
          primaryAction: AppButton(
            label: 'Add a product',
            tier: AppButtonTier.primary,
            onPressed: () {},
          ),
          body: const SizedBox(),
        ),
      );

      expect(
        tester.getCenter(find.text('Add a product')).dx,
        greaterThan(tester.getCenter(find.text('Sign out')).dx),
      );
    });
  });

  group('the toolbar keeps what is chrome and nothing else', () {
    testWidgets('actions are rendered in the app bar, not in the header', (
      tester,
    ) async {
      // *Sign out* is not what any of these pages exists for. Promoting it into
      // the header would say that it is.
      await _pump(
        tester,
        AppScaffold(
          contentWidth: AppContentWidth.records,
          title: 'Choose a business',
          actions: <Widget>[
            AppButton(
              label: 'Sign out',
              tier: AppButtonTier.tertiary,
              onPressed: () {},
            ),
          ],
          body: const SizedBox(),
        ),
      );

      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Sign out'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(PageHeader),
          matching: find.text('Sign out'),
        ),
        findsNothing,
      );
    });

    testWidgets('an empty action list leaves the slot null', (tester) async {
      // Not an empty list: `AppBar` treats null and `[]` differently for
      // layout, and every route in this app that has no actions had null
      // before.
      await _pump(
        tester,
        const AppScaffold(
          contentWidth: AppContentWidth.records,
          title: 'Product catalog',
          body: SizedBox(),
        ),
      );

      expect(tester.widget<AppBar>(find.byType(AppBar)).actions, isNull);
    });

    testWidgets('the way back is still the app bar\'s to draw', (tester) async {
      // `claude.md` hard rule 1: a visual change does not move routing
      // behaviour. `AppBar` decides whether there is a way back from here, and
      // it still does.
      await _pump(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const AppScaffold(
                    contentWidth: AppContentWidth.records,
                    title: 'Product stock ledger',
                    body: SizedBox(),
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byType(BackButton), findsOneWidget);
      expect(
        tester.widget<AppBar>(find.byType(AppBar)).automaticallyImplyLeading,
        isTrue,
      );
    });

    testWidgets('a route may refuse the implied leading control', (
      tester,
    ) async {
      await _pump(
        tester,
        const AppScaffold(
          contentWidth: AppContentWidth.records,
          title: 'Business invitation',
          automaticallyImplyLeading: false,
          body: SizedBox(),
        ),
      );

      expect(
        tester.widget<AppBar>(find.byType(AppBar)).automaticallyImplyLeading,
        isFalse,
      );
    });
  });

  group('every page has a max content width - design.md §4.2', () {
    /// The width of the page column: the header's laid-out box plus the two
    /// insets the frame draws around it.
    ///
    /// Measured off the laid-out header rather than off a `ConstrainedBox`,
    /// because a constraint that is applied and then not honoured by anything
    /// below it would still be found by `find.byType`. **Not off the title
    /// text**, which is inside a start-aligned column and sizes to its own
    /// glyphs rather than to the page.
    // The page column itself, which §4.2's maximum is applied to. It measured
    // `PageHeader` until 2026-08-23, when the header block moved into the bar
    // and stopped being part of the page at all.
    double pageWidth(WidgetTester tester) =>
        tester.getSize(find.byKey(AppScaffold.pageKey)).width;

    testWidgets('a reading surface stops at 720 on a wide window', (
      tester,
    ) async {
      await _pump(
        tester,
        const AppScaffold(
          contentWidth: AppContentWidth.reading,
          title: 'Checkout settings',
          body: SizedBox(),
        ),
        width: 1440,
      );

      expect(pageWidth(tester), _tokens.layout.reading);
    });

    testWidgets('a record list stops at 1200 on the same window', (
      tester,
    ) async {
      await _pump(
        tester,
        const AppScaffold(
          contentWidth: AppContentWidth.records,
          title: 'Manage catalog',
          body: SizedBox(),
        ),
        width: 1440,
      );

      expect(pageWidth(tester), _tokens.layout.records);
    });

    testWidgets('a `full` page takes the whole window', (tester) async {
      // §4.2's third row states no maximum at all. Nothing in `lib/` passes
      // this yet - the sale is step 7's - and it is asserted anyway, because
      // the row exists and a page that quietly got 1200 instead would be a
      // sale screen missing 240 pixels of products.
      await _pump(
        tester,
        const AppScaffold(
          contentWidth: AppContentWidth.full,
          title: 'New sale',
          body: SizedBox(),
        ),
        width: 1440,
      );

      expect(pageWidth(tester), 1440);
    });

    testWidgets('no maximum fires on a phone, whichever row a page is', (
      tester,
    ) async {
      // 411 is narrower than every figure §4.2 states, so all three rows must
      // render identically there. A constraint that fired here would be one
      // that had been written as a fixed width by mistake, and it would show
      // as a column of content with ground down both sides of a phone.
      for (final width in AppContentWidth.values) {
        await _pump(
          tester,
          AppScaffold(
            contentWidth: width,
            title: 'Daily summary',
            body: const SizedBox(),
          ),
          width: 411,
        );

        expect(
          pageWidth(tester),
          411,
          reason: '$width must not constrain a 411-wide window',
        );
      }
    });

    testWidgets('the toolbar is not constrained with the content', (
      tester,
    ) async {
      // The back arrow belongs in the window's corner, where every platform
      // puts it. A toolbar that obeyed the content rule would drift inwards on
      // a wide window and read as chrome that had been laid out as content.
      await _pump(
        tester,
        const AppScaffold(
          contentWidth: AppContentWidth.reading,
          title: 'Checkout settings',
          body: SizedBox(),
        ),
        width: 1440,
      );

      expect(tester.getSize(find.byType(AppBar)).width, 1440);
      expect(pageWidth(tester), _tokens.layout.reading);
    });

    testWidgets('the header and the body are constrained together', (
      tester,
    ) async {
      // §4.2 caps *content*, and a title at the window edge above records in a
      // centred column would read as two pages rather than one.
      await _pump(
        tester,
        const AppScaffold(
          contentWidth: AppContentWidth.records,
          title: 'Manage catalog',
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(height: 10, child: Text('a record')),
          ),
        ),
        width: 1440,
      );

      // **The body alone now.** The title is in the toolbar, which §4.2 does
      // not constrain - a back arrow that drifted inwards on a wide window,
      // away from the corner every platform puts it in, would be chrome
      // obeying a content rule.
      expect(
        tester.getTopLeft(find.text('a record')).dx,
        tester.getTopLeft(find.byKey(AppScaffold.pageKey)).dx,
      );
    });

    testWidgets('the page column is centred rather than pinned left', (
      tester,
    ) async {
      // §4.2's own word for both constrained rows is "centred".
      await _pump(
        tester,
        const AppScaffold(
          contentWidth: AppContentWidth.reading,
          title: 'Checkout settings',
          body: SizedBox(),
        ),
        width: 1440,
      );

      final left = tester.getTopLeft(find.byKey(AppScaffold.pageKey)).dx;
      expect(left, (1440 - _tokens.layout.reading) / 2);
    });

    testWidgets('`full` adds no constraining widget at all', (tester) async {
      // `maxWidthOf` answers null rather than infinity so this branch builds
      // nothing. Counting the frame's own `ConstrainedBox`es is the only way
      // to tell "unconstrained" from "constrained to the window".
      Future<int> boxes(AppContentWidth width) async {
        await _pump(
          tester,
          AppScaffold(
            contentWidth: width,
            title: 'New sale',
            body: const SizedBox(),
          ),
          width: 1440,
        );
        return find
            .descendant(
              of: find.byType(Scaffold),
              matching: find.byType(ConstrainedBox),
            )
            .evaluate()
            .length;
      }

      expect(
        await boxes(AppContentWidth.records),
        await boxes(AppContentWidth.full) + 1,
      );
    });
  });

  group('the frame reads the token layer and nothing else', () {
    testWidgets('the page is painted `surface.base`', (tester) async {
      await _pump(
        tester,
        const AppScaffold(
          contentWidth: AppContentWidth.records,
          title: 'Shift corrections',
          body: SizedBox(),
        ),
      );

      expect(
        tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
        _tokens.colors.surface.base,
      );
    });

    test('the horizontal inset is a value on §2.3\'s scale', () {
      expect(
        _tokens.spacing.all,
        contains(AppScaffold.horizontalInset(_tokens.spacing)),
      );
    });

    testWidgets('every gap the frame draws is on that scale too', (
      tester,
    ) async {
      await _pump(
        tester,
        const AppScaffold(
          contentWidth: AppContentWidth.records,
          title: 'Unresolved differences',
          subtitle: 'Four kinds, one list',
          body: SizedBox(),
        ),
      );

      final permitted = <double>{
        ..._tokens.spacing.all,
        _tokens.density.sectionGap,
        0,
      };
      // The frame draws one gap of its own now - the space above the body,
      // where the header block used to sit - and it is on the scale like
      // every other.
      final gap = tester.widget<SizedBox>(
        find
            .descendant(
              of: find.byKey(AppScaffold.pageKey),
              matching: find.byType(SizedBox),
            )
            .first,
      );
      final inset = EdgeInsets.all(gap.height ?? 0);
      for (final value in <double>[
        inset.left,
        inset.top,
        inset.right,
        inset.bottom,
      ]) {
        expect(permitted, contains(value));
      }
      for (final box in tester.widgetList<SizedBox>(
        find.descendant(
          of: find.byType(AppScaffold),
          matching: find.byType(SizedBox),
        ),
      )) {
        if (box.height case final height? when height > 0) {
          expect(permitted, contains(height));
        }
      }
    });

    testWidgets('the bar and the content are one spacing step apart', (
      tester,
    ) async {
      // **`space.8`, down from 16 on 2026-08-26 and 24 before that.** The
      // header block was a section of the page and needed §3's gap under it;
      // a toolbar is chrome with its own edge. The 16 was still a second
      // opinion on top of the 20 every body pads itself with, which the
      // product owner read as wasted ground under the title.
      await _pump(
        tester,
        const AppScaffold(
          contentWidth: AppContentWidth.records,
          title: 'Bulk catalog changes',
          body: Align(
            alignment: Alignment.topLeft,
            child: Text('first line of content'),
          ),
        ),
      );

      final bar = tester.getRect(find.byType(AppBar));
      final content = tester.getRect(find.text('first line of content'));
      expect(content.top - bar.bottom, _tokens.spacing.s8);
    });

    testWidgets('the body is given every pixel below the header', (
      tester,
    ) async {
      const height = 800.0;
      await _pump(
        tester,
        const AppScaffold(
          contentWidth: AppContentWidth.records,
          title: 'Staff directory',
          body: SizedBox.expand(key: ValueKey('body')),
        ),
        height: height,
      );

      final bar = tester.getRect(find.byType(AppBar));
      final body = tester.getRect(find.byKey(const ValueKey('body')));
      expect(body.top, bar.bottom + _tokens.spacing.s8);
      expect(body.bottom, height);
    });
  });

  group('it survives a tree that is not this app', () {
    testWidgets('a bare `ThemeData` falls back rather than throwing', (
      tester,
    ) async {
      // 46 widget-test files build their own theme, as does any preview. The
      // fallback is `AppTokens.dark`, which is the stricter density on every
      // dimension §9 measures - see the accessor's own note.
      await _pump(
        tester,
        const AppScaffold(
          contentWidth: AppContentWidth.records,
          title: 'Reconciliation run',
          body: SizedBox(),
        ),
        theme: ThemeData(brightness: Brightness.dark),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Reconciliation run'), findsOneWidget);
      expect(
        _styleOf(tester, 'Reconciliation run').fontSize,
        _tokens.typography.titleLarge.fontSize,
      );
    });

    testWidgets('a `PageHeader` outside an `AppScaffold` draws itself', (
      tester,
    ) async {
      // §5.1 lists the two components separately, so one has to work without
      // the other.
      await _pump(
        tester,
        const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(20),
            child: PageHeader(title: 'Stock adjustments'),
          ),
        ),
      );

      expect(find.text('Stock adjustments'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('the navigation column - design.md §4.4', () {
    /// The width the page column ends up with, measured the same way §4.2's
    /// group measures it: off the laid-out header rather than off a constraint
    /// that may or may not be honoured below it.
    // The page column itself, which §4.2's maximum is applied to. It measured
    // `PageHeader` until 2026-08-23, when the header block moved into the bar
    // and stopped being part of the page at all.
    double pageWidth(WidgetTester tester) =>
        tester.getSize(find.byKey(AppScaffold.pageKey)).width;

    /// The inset the frame draws to the left of the menu, plus the menu.
    final double columnCost =
        AppScaffold.horizontalInset(_tokens.spacing) + HomeNavigation.menuWidth;

    List<HomeDestination> destinations([int count = 3]) => <HomeDestination>[
      for (var index = 0; index < count; index++)
        HomeDestination(
          destinationKey: ValueKey('destination-$index'),
          label: 'Destination $index',
          icon: Icons.inventory_2_outlined,
          isPrimary: index == 0,
          onPressed: () {},
        ),
    ];

    Widget page({
      List<HomeDestination> navigation = const <HomeDestination>[],
      AppContentWidth contentWidth = AppContentWidth.records,
    }) => AppScaffold(
      contentWidth: contentWidth,
      title: 'Dev Corner Shop',
      navigation: navigation,
      body: const SizedBox(),
    );

    testWidgets('a route that names no destinations draws no column', (
      tester,
    ) async {
      // 26 of the 27 call sites, and the picture every one of them already
      // has: an empty slot has to cost nothing at all, not a column of ground.
      await _pump(tester, page(), width: 1440);

      expect(find.byType(HomeNavigation), findsNothing);
      expect(pageWidth(tester), _tokens.layout.records);
    });

    testWidgets('an empty destination list draws no column either', (
      tester,
    ) async {
      // A role offered nothing is not the same call site as a route that names
      // nothing, and it must not leave 276 pixels of empty column behind.
      await _pump(
        tester,
        page(navigation: const <HomeDestination>[]),
        width: 1440,
      );

      expect(find.byType(HomeNavigation), findsNothing);
      expect(pageWidth(tester), _tokens.layout.records);
    });

    testWidgets('the menu draws at §4.1\'s expanded floor and not below it', (
      tester,
    ) async {
      await _pump(
        tester,
        page(navigation: destinations()),
        width: _compactWidth,
      );
      expect(find.byType(HomeNavigation), findsNothing);
      // The page keeps the whole window below the floor - the cards are the
      // body's there, and a frame that reserved the column anyway would
      // narrow every phone by 276 pixels for a menu nobody can see.
      expect(pageWidth(tester), _compactWidth);

      await _pump(
        tester,
        page(navigation: destinations()),
        width: _expandedWidth,
      );
      expect(find.byType(HomeNavigation), findsOneWidget);
    });

    testWidgets('the column is §4.4\'s declared width', (tester) async {
      await _pump(tester, page(navigation: destinations()), width: 1440);

      expect(
        tester.getSize(find.byType(HomeNavigation)).width,
        HomeNavigation.menuWidth,
      );
    });

    testWidgets('the menu sits at the page inset, outside the maximum', (
      tester,
    ) async {
      // The same argument the toolbar already gets: chrome that drifted inwards
      // on a wide window, away from the edge, would be chrome obeying a content
      // rule. At 1600 the content maximum fires and the menu must not move.
      await _pump(tester, page(navigation: destinations()), width: 1600);

      expect(
        tester.getRect(find.byType(HomeNavigation)).left,
        AppScaffold.horizontalInset(_tokens.spacing),
      );
    });

    testWidgets('the content maximum is measured against what is left', (
      tester,
    ) async {
      // 1440 less the column is 1164, which is under §4.2's 1200 - so the
      // maximum does not fire and the page is the remainder. A page still
      // measured against the window would be 1200 wide in a 1164 space and
      // would overflow under the menu.
      await _pump(tester, page(navigation: destinations()), width: 1440);

      expect(pageWidth(tester), 1440 - columnCost);
    });

    testWidgets('the maximum still fires where the remainder is wider', (
      tester,
    ) async {
      await _pump(tester, page(navigation: destinations()), width: 1600);

      expect(pageWidth(tester), _tokens.layout.records);
      // Centred in what is left rather than in the window: the page's own
      // centre is the middle of the space beside the menu.
      expect(
        tester.getRect(find.byKey(AppScaffold.pageKey)).center.dx,
        closeTo((columnCost + 1600) / 2, 0.5),
      );
    });

    testWidgets('the toolbar spans the window rather than the page', (
      tester,
    ) async {
      await _pump(tester, page(navigation: destinations()), width: 1440);

      expect(tester.getSize(find.byType(AppBar)).width, 1440);
    });

    testWidgets('the menu scrolls on its own', (tester) async {
      // A column of eleven rows is about 600 tall and `expanded` puts no floor
      // under the height, so the one band that has a menu is also the band a
      // half-height window lands in. Its scrollable is its own: scrolling a
      // long page must not carry the destinations off the top.
      await _pump(
        tester,
        AppScaffold(
          contentWidth: AppContentWidth.records,
          title: 'Dev Corner Shop',
          navigation: destinations(11),
          body: ListView(
            children: <Widget>[
              for (var index = 0; index < 40; index++)
                SizedBox(height: 40, child: Text('Row $index')),
            ],
          ),
        ),
        width: _expandedWidth,
        height: 400,
      );

      expect(tester.takeException(), isNull);
      expect(
        find.ancestor(
          of: find.byType(HomeNavigation),
          matching: find.byType(Scrollable),
        ),
        findsOneWidget,
      );
      // Two scrollables that are not one inside the other - the menu's and the
      // page's.
      expect(find.byType(Scrollable), findsNWidgets(2));
      expect(
        find.descendant(
          of: find.byType(ListView),
          matching: find.byType(HomeNavigation),
        ),
        findsNothing,
      );
    });

    testWidgets('every destination is reachable in the column', (tester) async {
      var pressed = 0;
      await _pump(
        tester,
        AppScaffold(
          contentWidth: AppContentWidth.records,
          title: 'Dev Corner Shop',
          navigation: <HomeDestination>[
            HomeDestination(
              destinationKey: const ValueKey('open'),
              label: 'Open',
              icon: Icons.point_of_sale,
              onPressed: () => pressed++,
            ),
          ],
          body: const SizedBox(),
        ),
        width: _expandedWidth,
      );

      await tester.tap(find.byKey(const ValueKey('open')));
      await tester.pumpAndSettle();

      expect(pressed, 1);
    });
  });
}
