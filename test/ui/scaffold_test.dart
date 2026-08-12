import 'package:flutter/material.dart';
import 'package:flutter_application_1/theme.dart';
import 'package:flutter_application_1/ui/buttons.dart';
import 'package:flutter_application_1/ui/scaffold.dart';
import 'package:flutter_application_1/ui/tokens.dart';
import 'package:flutter_test/flutter_test.dart';

const _tokens = AppTokens.dark;

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
  group('the screen title is a piece of content, not a piece of chrome', () {
    testWidgets('it is `title.lg` below §4.1\'s expanded floor', (
      tester,
    ) async {
      // §2.2 gives `title.lg` "screen title (compact)". A `display` title at
      // phone width would be 32/40 in a 411-wide column.
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
      expect(style.height, _tokens.typography.titleLarge.height);
    });

    testWidgets('it is `display` at and above it', (tester) async {
      // §2.2 marks `display` "expanded only", and 1024 is where §4.1 says
      // expanded begins.
      await _pump(
        tester,
        const AppScaffold(
          contentWidth: AppContentWidth.records,
          title: 'Daily summary',
          body: SizedBox(),
        ),
        width: _expandedWidth,
      );

      final style = _styleOf(tester, 'Daily summary');
      expect(style.fontSize, _tokens.typography.display.fontSize);
      expect(style.fontWeight, _tokens.typography.display.fontWeight);
      expect(style.height, _tokens.typography.display.height);
    });

    test('the boundary the widget uses is the one already declared', () {
      // The predicate is exposed so this can be asked directly rather than
      // inferred from two pixel widths that happen to agree with it today.
      expect(PageHeader.showsDisplayTitle(_compactWidth), isFalse);
      expect(PageHeader.showsDisplayTitle(_expandedWidth), isTrue);
    });

    testWidgets('the role follows the screen, not the padded header box', (
      tester,
    ) async {
      // At exactly 1024 the header's own box is the page inset narrower. A role
      // resolved against a `LayoutBuilder` would flip at 1064 instead - a
      // fourth breakpoint produced by arithmetic that nobody declared.
      await _pump(
        tester,
        const AppScaffold(
          contentWidth: AppContentWidth.records,
          title: 'Activity log',
          body: SizedBox(),
        ),
        width: _expandedWidth,
      );

      expect(
        tester.getSize(find.byType(PageHeader)).width,
        lessThan(_expandedWidth),
      );
      expect(
        _styleOf(tester, 'Activity log').fontSize,
        _tokens.typography.display.fontSize,
      );
    });

    testWidgets('it carries `text.primary` at both roles', (tester) async {
      for (final width in <double>[_compactWidth, _expandedWidth]) {
        await _pump(
          tester,
          const AppScaffold(
          contentWidth: AppContentWidth.records,
          title: 'Manage catalog',
          body: SizedBox(),
        ),
          width: width,
        );
        expect(
          _styleOf(tester, 'Manage catalog').color,
          _tokens.colors.text.primary,
          reason: 'at $width',
        );
      }
    });

    testWidgets('it is never truncated - a long one wraps instead', (
      tester,
    ) async {
      // §5.2 says this of a record's identity and the same argument is stronger
      // for a screen: a person who cannot read the whole title does not know
      // which screen they are on.
      const title =
          'Adjustments: Fresh whole milk 500ml, refrigerated, case of twelve';
      await _pump(
        tester,
        const AppScaffold(
          contentWidth: AppContentWidth.records,
          title: title,
          body: SizedBox(),
        ),
        width: 411,
      );

      final text = tester.widget<Text>(find.text(title));
      expect(text.overflow, isNot(TextOverflow.ellipsis));
      expect(text.maxLines, isNull);
      // And it actually took more than one line at phone width, so the
      // assertion above is about a case that occurs rather than a hypothetical.
      expect(
        tester.getSize(find.text(title)).height,
        greaterThan(_tokens.typography.titleLarge.height! *
            _tokens.typography.titleLarge.fontSize!),
      );
    });

    testWidgets('a screen reader is told it is a heading', (tester) async {
      // An `AppBar.title` announced itself as a header. Moving the title out of
      // the toolbar must not quietly drop that.
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        const AppScaffold(
          contentWidth: AppContentWidth.records,
          title: 'Shift history',
          body: SizedBox(),
        ),
      );

      expect(
        tester.getSemantics(find.text('Shift history')),
        matchesSemantics(label: 'Shift history', isHeader: true),
      );
      handle.dispose();
    });
  });

  group('the title appears once', () {
    testWidgets('the toolbar no longer carries one', (tester) async {
      // §7's line, as an assertion. The `AppBar` is still there - it owns the
      // way back - and its title slot is empty.
      await _pump(
        tester,
        const AppScaffold(
          contentWidth: AppContentWidth.records,
          title: 'Find a receipt',
          body: SizedBox(),
        ),
      );

      expect(tester.widget<AppBar>(find.byType(AppBar)).title, isNull);
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Find a receipt'),
        ),
        findsNothing,
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
    testWidgets('is absent when none is given', (tester) async {
      await _pump(
        tester,
        const AppScaffold(
          contentWidth: AppContentWidth.records,
          title: 'Sales totals',
          body: SizedBox(),
        ),
      );

      expect(
        find.descendant(
          of: find.byType(PageHeader),
          matching: find.byType(Text),
        ),
        findsOneWidget,
      );
    });

    testWidgets('takes the density body role and `text.secondary`', (
      tester,
    ) async {
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
      final body = _tokens.density.body(_tokens.typography);
      expect(style.fontSize, body.fontSize);
      expect(style.color, _tokens.colors.text.secondary);
    });

    testWidgets('follows the screen density rather than a fixed size', (
      tester,
    ) async {
      // §3 gives comfortable `body.lg` and compact `body.md`. A subtitle that
      // ignored the density would be the only line on the page that did.
      await _pump(
        tester,
        Builder(
          builder: (context) => Theme(
            data: Theme.of(context).copyWith(
              extensions: <ThemeExtension<dynamic>>[
                AppTokens.of(context).withDensity(AppDensity.compact),
              ],
            ),
            child: const AppScaffold(
              contentWidth: AppContentWidth.records,
              title: 'Activity log',
              subtitle: 'Every event this business recorded',
              body: SizedBox(),
            ),
          ),
        ),
      );

      expect(
        _styleOf(tester, 'Every event this business recorded').fontSize,
        _tokens.typography.bodyMedium.fontSize,
      );
    });
  });

  group('the primary action', () {
    test('the side-by-side boundary is the other declared constant', () {
      // `AppLayout.contract.mediumFloor` was written to answer exactly "is there
      // room for two things side by side" and had zero consumers until now.
      expect(
        PageHeader.placesActionBesideTitle(AppLayout.contract.mediumFloor - 1),
        isFalse,
      );
      expect(
        PageHeader.placesActionBesideTitle(AppLayout.contract.mediumFloor),
        isTrue,
      );
    });

    testWidgets('sits at the trailing edge of the title on a wide screen', (
      tester,
    ) async {
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
        width: AppLayout.contract.mediumFloor,
      );

      final title = tester.getRect(find.text('Manage catalog'));
      final action = tester.getRect(find.byType(AppButton));
      expect(action.left, greaterThan(title.right));
      expect(action.top, title.top);
    });

    testWidgets('drops under the title on a phone', (tester) async {
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
        width: 411,
      );

      final title = tester.getRect(find.text('Manage catalog'));
      final action = tester.getRect(find.byType(AppButton));
      expect(action.top, greaterThanOrEqualTo(title.bottom));
      expect(action.left, title.left);
    });

    testWidgets('a long title never squeezes it, at either arrangement', (
      tester,
    ) async {
      // The failure this guards against is the one `tenant_safe_landing_test`
      // guards against in the toolbar, in its other direction: a title and a
      // control competing for one row until one of them is unreadable. The
      // widest button label in the app is measured against the longest title a
      // route can carry, which is a product name.
      const title =
          'Adjustments: Fresh whole milk 500ml, refrigerated, case of twelve';
      for (final width in <double>[411, AppLayout.contract.mediumFloor, 1440]) {
        await _pump(
          tester,
          AppScaffold(
            contentWidth: AppContentWidth.records,
            title: title,
            primaryAction: AppButton(
              label: 'Record an adjustment',
              onPressed: () {},
            ),
            body: const SizedBox(),
          ),
          width: width,
          height: 2400,
        );

        expect(tester.takeException(), isNull, reason: 'at $width');
        final action = tester.getRect(find.byType(AppButton));
        expect(action.right, lessThanOrEqualTo(width), reason: 'at $width');
        expect(action.left, greaterThanOrEqualTo(0), reason: 'at $width');
        // The title keeps a column it can be read in rather than being
        // squeezed to a stack of single letters, which is what a `Row` that
        // gives an unflexed action all the width it asks for produces. A third
        // of the screen is the floor rather than half because `flutter test`
        // renders every glyph as a square of the font size, so a five-word
        // button label measures far wider here than it does in Roboto.
        expect(
          tester.getSize(find.text(title)).width,
          greaterThan(width / 3),
          reason: 'at $width',
        );
      }
    });

    testWidgets('is absent from the layout when none is given', (tester) async {
      await _pump(
        tester,
        const AppScaffold(
          contentWidth: AppContentWidth.records,
          title: 'Stock movements',
          body: SizedBox(),
        ),
      );

      expect(
        find.descendant(
          of: find.byType(PageHeader),
          matching: find.byType(Row),
        ),
        findsNothing,
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
    double pageWidth(WidgetTester tester) =>
        tester.getSize(find.byType(PageHeader)).width +
        AppScaffold.horizontalInset(_tokens.spacing) * 2;

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

      expect(
        tester.getTopLeft(find.text('a record')).dx,
        tester.getTopLeft(find.text('Manage catalog')).dx -
            AppScaffold.horizontalInset(_tokens.spacing),
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

      final left = tester.getTopLeft(find.text('Checkout settings')).dx;
      final inset = AppScaffold.horizontalInset(_tokens.spacing);
      expect(left - inset, (1440 - _tokens.layout.reading) / 2);
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
      final padding = tester.widget<Padding>(
        find
            .ancestor(
              of: find.byType(PageHeader),
              matching: find.byType(Padding),
            )
            .first,
      );
      final inset = padding.padding.resolve(TextDirection.ltr);
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

    testWidgets('the header and the content are a section gap apart', (
      tester,
    ) async {
      // §3's own row for the gap between one section of a page and the next.
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

      final header = tester.getRect(find.byType(PageHeader));
      final content = tester.getRect(find.text('first line of content'));
      expect(
        content.top - header.bottom,
        _tokens.density.sectionGap,
      );
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
      final header = tester.getRect(find.byType(PageHeader));
      final body = tester.getRect(find.byKey(const ValueKey('body')));
      expect(body.top, header.bottom + _tokens.density.sectionGap);
      expect(body.bottom, height);
      expect(bar.bottom, lessThanOrEqualTo(header.top));
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
}
