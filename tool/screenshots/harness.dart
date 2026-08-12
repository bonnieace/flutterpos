/// Renders the app's screens off-device and writes a PNG of each one.
///
/// This is a screenshot generator wearing a widget test's clothes. It lives
/// outside `test/` deliberately: `flutter test` walks that directory, and these
/// files assert nothing, so counting them in the suite baseline would make the
/// figure in `PLAN.md` mean two different things.
///
/// Two things have to be arranged before a widget test can produce a picture a
/// person can read, and both are done here once:
///
/// 1. **Real fonts.** `flutter test` ships a metrics-only test face, so every
///    string renders as a filled rectangle. The Flutter SDK already carries
///    Roboto and the Material icon font for exactly this reason, and both are
///    loaded from its cache. The app's theme names no family at all - see the
///    note in `lib/theme.dart` - so the family is applied to the text theme
///    here rather than guessed at by the engine.
/// 2. **A repaint boundary at the root**, so the whole view including the app
///    bar can be rasterized. `toImage` is asynchronous work the test binding
///    will not run on its own, which is why every capture goes through
///    `tester.runAsync`.
///
/// Sizes straddle both breakpoints `AppLayout` declares in `lib/ui/tokens.dart`:
/// the phone is `design.md` §4.1's `compact` band and gets the stacked card
/// layout, and the desktop is `expanded` and gets the table. They also straddle
/// §4.2's content maxima in both directions - 1440 is wider than every one of
/// them and 411 is narrower than every one - so the pair shows a page both
/// constrained and unconstrained.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_application_1/theme.dart';
import 'package:flutter_test/flutter_test.dart';

/// Where the PNGs land, relative to the repository root.
const String screenshotDirectory = 'screenshots';

/// One viewport a screen is rendered at.
final class ScreenshotViewport {
  const ScreenshotViewport({
    required this.name,
    required this.size,
    required this.devicePixelRatio,
  });

  /// The subdirectory the file is written to.
  final String name;

  /// Logical pixels, which is what every breakpoint in this app is expressed
  /// in.
  final Size size;

  final double devicePixelRatio;

  @override
  String toString() => name;
}

/// A desktop browser window. `design.md` §4.1's `expanded` band, so the
/// surfaces that have a table draw it.
const ScreenshotViewport webViewport = ScreenshotViewport(
  name: 'web',
  size: Size(1440, 900),
  devicePixelRatio: 1,
);

/// A phone. 411 x 891 is the figure `tenant_routing_shell.dart` measured its
/// landing route against, so it is the width the layout notes in this app are
/// already written about.
const ScreenshotViewport mobileViewport = ScreenshotViewport(
  name: 'mobile',
  size: Size(411, 891),
  devicePixelRatio: 2,
);

const List<ScreenshotViewport> screenshotViewports = <ScreenshotViewport>[
  webViewport,
  mobileViewport,
];

final GlobalKey _rootKey = GlobalKey();

/// The theme every screenshot is taken under: the app's own, with a font
/// family named so the strings are legible.
///
/// `spiritTheme` names no family, which on a device means "whatever the
/// platform's default face is" and in a widget test means the test face. Naming
/// Roboto here is the closest honest stand-in: it is the default face on
/// Android and the one Flutter bundles for exactly this purpose.
///
/// The text theme is not enough on its own. A **component** theme's text style
/// *replaces* the text theme's rather than merging onto it - `ListTile` picks
/// `listTileTheme.subtitleTextStyle` outright when it is set - so a style this
/// app names without a family arrives at the engine with none, and renders as
/// filled rectangles. Every style the theme names is therefore given the family
/// here, which is the same thing a real platform does for all of them at once.
ThemeData screenshotTheme() {
  const family = 'Roboto';
  TextStyle? named(TextStyle? style) => style?.copyWith(fontFamily: family);
  final base = spiritTheme;
  final listTile = base.listTileTheme;
  final chip = base.chipTheme;
  final input = base.inputDecorationTheme;
  final snackBar = base.snackBarTheme;
  final dialog = base.dialogTheme;
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: family),
    primaryTextTheme: base.primaryTextTheme.apply(fontFamily: family),
    listTileTheme: listTile.copyWith(
      titleTextStyle: named(listTile.titleTextStyle),
      subtitleTextStyle: named(listTile.subtitleTextStyle),
      leadingAndTrailingTextStyle: named(
        listTile.leadingAndTrailingTextStyle,
      ),
    ),
    chipTheme: chip.copyWith(
      labelStyle: named(chip.labelStyle),
      secondaryLabelStyle: named(chip.secondaryLabelStyle),
    ),
    inputDecorationTheme: input.copyWith(
      hintStyle: named(input.hintStyle),
      labelStyle: named(input.labelStyle),
      floatingLabelStyle: named(input.floatingLabelStyle),
      helperStyle: named(input.helperStyle),
      errorStyle: named(input.errorStyle),
      prefixStyle: named(input.prefixStyle),
      suffixStyle: named(input.suffixStyle),
      counterStyle: named(input.counterStyle),
    ),
    snackBarTheme: snackBar.copyWith(
      contentTextStyle: named(snackBar.contentTextStyle),
    ),
    dialogTheme: dialog.copyWith(
      titleTextStyle: named(dialog.titleTextStyle),
      contentTextStyle: named(dialog.contentTextStyle),
    ),
  );
}

bool _fontsLoaded = false;

/// Loads Roboto and the Material icon font out of the Flutter SDK's cache.
///
/// The SDK root is read from `FLUTTER_ROOT`, which the `flutter` tool sets for
/// the process it spawns, and derived from the running Dart executable if it is
/// absent - `dart-sdk/bin/dart` sits four levels below the SDK root.
Future<void> loadScreenshotFonts() async {
  if (_fontsLoaded) return;
  final fonts = _materialFontsDirectory();
  final roboto = FontLoader('Roboto');
  for (final face in const <String>[
    'roboto-regular.ttf',
    'roboto-medium.ttf',
    'roboto-bold.ttf',
    'roboto-italic.ttf',
  ]) {
    roboto.addFont(_fontBytes(fonts, face));
  }
  await roboto.load();

  final icons = FontLoader('MaterialIcons')
    ..addFont(_fontBytes(fonts, 'materialicons-regular.otf'));
  await icons.load();
  _fontsLoaded = true;
}

Future<ByteData> _fontBytes(Directory directory, String name) async {
  final file = File('${directory.path}${Platform.pathSeparator}$name');
  return ByteData.sublistView(await file.readAsBytes());
}

Directory _materialFontsDirectory() {
  for (final root in <String?>[
    Platform.environment['FLUTTER_ROOT'],
    _sdkRootFromExecutable(),
  ]) {
    if (root == null || root.isEmpty) continue;
    final directory = Directory(
      <String>[
        root,
        'bin',
        'cache',
        'artifacts',
        'material_fonts',
      ].join(Platform.pathSeparator),
    );
    if (directory.existsSync()) return directory;
  }
  throw StateError(
    'The Flutter SDK material_fonts cache was not found. Set FLUTTER_ROOT, or '
    'run `flutter precache` so the fonts are downloaded.',
  );
}

String? _sdkRootFromExecutable() {
  var directory = File(Platform.resolvedExecutable).parent;
  for (var level = 0; level < 4; level++) {
    directory = directory.parent;
  }
  return directory.path;
}

/// Renders [child] at [viewport] and writes `<name>.png` under that viewport's
/// directory.
///
/// [settle] is the escape hatch for a screen that never reaches a quiet frame -
/// an indeterminate spinner, for one - where `pumpAndSettle` would time out.
Future<void> captureScreen(
  WidgetTester tester, {
  required String name,
  required ScreenshotViewport viewport,
  required Widget child,
  bool settle = true,
  bool fullPage = true,
  Future<void> Function(WidgetTester tester)? afterPump,
}) async {
  // Reading font files and handing them to the engine is real I/O, and a
  // widget test body runs in a fake-async zone where a real future never
  // completes. `runAsync` is the only place this work can happen.
  await tester.runAsync(loadScreenshotFonts);
  // The test binding suppresses shadows so goldens stay comparable across
  // engine revisions. These are pictures for a person, so the elevation the app
  // actually draws is what should be in them.
  //
  // Restored in a `finally` rather than a tear-down, and this is not a style
  // choice: the binding asserts that no painting debug variable was left
  // changed, and it does that *before* tear-downs run. A capture that threw
  // half way would leave the flag set, and every test after it would fail that
  // assertion instead of reporting its own reason - which is exactly what
  // happened once.
  final shadowsDisabled = debugDisableShadows;
  debugDisableShadows = false;
  try {
    tester.view.physicalSize = viewport.size * viewport.devicePixelRatio;
    tester.view.devicePixelRatio = viewport.devicePixelRatio;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      RepaintBoundary(
        key: _rootKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: screenshotTheme(),
          home: child,
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 32));
    }
    if (afterPump != null) {
      await afterPump(tester);
      if (settle) await tester.pumpAndSettle();
    }

    await _write(tester, name: name, viewport: viewport);
    if (fullPage) await _writeFullPage(tester, name: name, viewport: viewport);
  } finally {
    debugDisableShadows = shadowsDisabled;
  }
}

/// Re-renders the screen tall enough to hold all of it, and writes that too.
///
/// Most routes here are taller than the window they open in, so the viewport
/// picture above shows what a person sees on arrival and this one shows what
/// they see after scrolling - which is the difference between a screenshot and
/// a review of a screen. Nothing is written when nothing is below the fold.
///
/// The height comes from the scroll position rather than from a guess, so the
/// image ends where the content does instead of trailing empty ground. It is
/// measured again after the resize because a wider- or taller-laid-out screen
/// can change its own extent; three passes is enough for every screen here and
/// the loop stops as soon as nothing is left over.
Future<void> _writeFullPage(
  WidgetTester tester, {
  required String name,
  required ScreenshotViewport viewport,
}) async {
  var height = viewport.size.height;
  var grew = false;
  for (var pass = 0; pass < 3; pass++) {
    final extent = _verticalOverflow(tester);
    if (extent <= 1) break;
    height = (height + extent).clamp(viewport.size.height, _maximumFullHeight);
    grew = true;
    tester.view.physicalSize =
        Size(viewport.size.width, height) * viewport.devicePixelRatio;
    await tester.pumpAndSettle();
    if (height >= _maximumFullHeight) break;
  }
  if (!grew) return;
  await _write(
    tester,
    name: name,
    viewport: ScreenshotViewport(
      name: '${viewport.name}-full',
      size: Size(viewport.size.width, height),
      devicePixelRatio: viewport.devicePixelRatio,
    ),
  );
}

/// A screen taller than this is written truncated rather than turned into an
/// image nothing will open.
const double _maximumFullHeight = 4400;

/// How much vertical content sits below the fold, across every vertical
/// scrollable on the screen.
///
/// The maximum rather than the first: a route can hold a horizontal chip strip
/// and a vertical list at once, and only one of them is the page.
double _verticalOverflow(WidgetTester tester) {
  var extent = 0.0;
  for (final element in find.byType(Scrollable).evaluate()) {
    final state = element as StatefulElement;
    final scrollable = state.state as ScrollableState;
    if (scrollable.axisDirection != AxisDirection.down) continue;
    if (!scrollable.position.hasContentDimensions) continue;
    final overflow = scrollable.position.maxScrollExtent;
    if (overflow > extent) extent = overflow;
  }
  return extent;
}

/// Rasterizes the current frame and writes it, without pumping anything.
///
/// Used by a capture that had to drive the screen first - opening a dialog, or
/// typing into a form - and wants the picture of where it ended up.
Future<void> writeCurrentFrame(
  WidgetTester tester, {
  required String name,
  required ScreenshotViewport viewport,
}) => _write(tester, name: name, viewport: viewport);

Future<void> _write(
  WidgetTester tester, {
  required String name,
  required ScreenshotViewport viewport,
}) async {
  final boundary =
      _rootKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final directory = Directory(
    '$screenshotDirectory${Platform.pathSeparator}${viewport.name}',
  )..createSync(recursive: true);
  final file = File(
    '${directory.path}${Platform.pathSeparator}$name.png',
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(
      pixelRatio: viewport.devicePixelRatio,
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (data == null) {
      throw StateError('Encoding $name at ${viewport.name} produced no bytes.');
    }
    await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
  });
  _captured.add('${viewport.name}/$name.png');
}

final Set<String> _captured = <String>{};

/// Every file this run wrote, for the summary a run prints at the end.
Iterable<String> get capturedScreenshots =>
    _captured.toList()..sort();

/// Declares one screen at every viewport, as a group of tests.
///
/// The builder is called once per viewport rather than once in total, because a
/// screen holds controllers and a session, and reusing one across two pumps
/// would render the second at whatever state the first left behind.
void screenshotCase(
  String name, {
  required Widget Function() build,
  bool settle = true,
  bool fullPage = true,
  Future<void> Function(WidgetTester tester)? afterPump,
  List<ScreenshotViewport> viewports = screenshotViewports,
}) {
  for (final viewport in viewports) {
    testWidgets('$name @ ${viewport.name}', (tester) async {
      await captureScreen(
        tester,
        name: name,
        viewport: viewport,
        child: build(),
        settle: settle,
        fullPage: fullPage,
        afterPump: afterPump,
      );
    });
  }
}
