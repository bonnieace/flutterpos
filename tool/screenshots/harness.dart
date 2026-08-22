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
///    string renders as a filled rectangle. The app's own bundled faces are
///    loaded from `fonts/` - Hanken Grotesk and JetBrains Mono, the two
///    families `pubspec.yaml` declares - so a capture shows the typography the
///    app actually ships. The Material icon font still comes from the SDK
///    cache, because it is the SDK's asset rather than the app's.
///
///    **This harness used to inject Roboto over the app's theme**, and worse,
///    over nine component themes one at a time, because no type role named a
///    family and a component theme's text style replaces rather than merges.
///    `AppTypeRoles` names the family on every role as of 2026-08-22, so the
///    injection has no job left and is gone. A capture is now the app's theme
///    unmodified, which is the property that makes it evidence.
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
import 'package:flutter_application_1/ui/tokens.dart';
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

/// A tablet, or a half-screen desktop window. `design.md` §4.1's `medium` band.
///
/// **New in step 6's second half, and it is the first band this harness could
/// not photograph.** §4.1 has had three bands since it was written and the two
/// viewports above straddle both floors, which was enough while every
/// difference between them was a maximum firing or not firing. §4.3 changes
/// that: `medium` is the only band with a rendering of its own - two-column
/// cards - and a contract whose middle row no picture shows is a contract
/// reviewed on two of its three cases.
///
/// **It is not in [screenshotViewports], deliberately.** Adding it there would
/// render every screen in the app a third time for a band in which almost every
/// one of them is identical to the phone, and 128 more images is a diff nobody
/// reads. The component matrices that have a `medium` case ask for it by name.
const ScreenshotViewport tabletViewport = ScreenshotViewport(
  name: 'tablet',
  size: Size(834, 1000),
  devicePixelRatio: 1,
);

const List<ScreenshotViewport> screenshotViewports = <ScreenshotViewport>[
  webViewport,
  mobileViewport,
];

/// Every band §4.1 declares, for a capture whose subject is the responsive
/// contract itself.
const List<ScreenshotViewport> everyBandViewports = <ScreenshotViewport>[
  webViewport,
  tabletViewport,
  mobileViewport,
];

final GlobalKey _rootKey = GlobalKey();

/// The theme every screenshot is taken under: the app's own, unmodified.
///
/// **It returns `spiritTheme` and nothing else, and that is the point.** This
/// function used to rebuild nine component themes to force a font family into
/// them, because `AppTypeRoles` named none and a component theme's text style
/// *replaces* the text theme's rather than merging onto it - so `ListTile`,
/// `Chip`, `InputDecoration`, `SnackBar` and `Dialog` each arrived at the
/// engine with no family and rendered as filled rectangles.
///
/// Naming the family on the roles themselves fixed that at the source, in the
/// app rather than in the harness. The function is kept rather than inlined so
/// that every capture still routes through one named place if a future
/// difference between shipped and photographed is ever justified - but the
/// honest state today is that there is no difference at all.
ThemeData screenshotTheme() => spiritTheme;

bool _fontsLoaded = false;

/// Loads the app's bundled faces from `fonts/`, and the Material icon font
/// from the Flutter SDK's cache.
///
/// The two families and the six faces below are exactly what `pubspec.yaml`
/// declares. They are listed again here rather than parsed out of the manifest
/// because a test binary has no asset bundle to read: `flutter test` does not
/// build one, which is the same reason the icon font has to be fetched by path.
/// A face added to `pubspec.yaml` and not to this list will render in the
/// engine's fallback, so the two lists move together.
///
/// The SDK root is read from `FLUTTER_ROOT`, which the `flutter` tool sets for
/// the process it spawns, and derived from the running Dart executable if it is
/// absent - `dart-sdk/bin/dart` sits four levels below the SDK root.
Future<void> loadScreenshotFonts() async {
  if (_fontsLoaded) return;
  final appFonts = Directory('fonts');
  if (!appFonts.existsSync()) {
    throw StateError(
      'The `fonts/` directory of this app was not found. Screenshots must be '
      'run from the repository root, because the faces are loaded by relative '
      'path.',
    );
  }

  final interface = FontLoader(AppTypeRoles.interfaceFamily);
  for (final face in const <String>[
    'HankenGrotesk-Regular.ttf',
    'HankenGrotesk-Medium.ttf',
    'HankenGrotesk-SemiBold.ttf',
    'HankenGrotesk-Bold.ttf',
  ]) {
    interface.addFont(_fontBytes(appFonts, face));
  }
  await interface.load();

  final mono = FontLoader(AppTypeRoles.monoFamily);
  for (final face in const <String>[
    'JetBrainsMono-Regular.ttf',
    'JetBrainsMono-Medium.ttf',
  ]) {
    mono.addFont(_fontBytes(appFonts, face));
  }
  await mono.load();

  final icons = FontLoader('MaterialIcons')
    ..addFont(
      _fontBytes(_materialFontsDirectory(), 'materialicons-regular.otf'),
    );
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
  final file = File('${directory.path}${Platform.pathSeparator}$name.png');
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: viewport.devicePixelRatio);
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
Iterable<String> get capturedScreenshots => _captured.toList()..sort();

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
