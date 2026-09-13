/// The screen where a photograph is placed inside its square.
///
/// Opened from the catalog form's image well, over the photograph chosen
/// there. See `product_image_framing.dart` for why the placement is baked into
/// the bytes rather than remembered beside them.
///
/// **Nothing on this screen scrolls, and that is the whole reason it works.**
/// The first version put the canvas in a `ListView` so the controls could
/// never overflow. A `Scrollable` owns a vertical drag recogniser, the canvas
/// owns a scale recogniser, and both entered the gesture arena for the same
/// touch - so a drag that was even slightly vertical went to the page and the
/// picture did not move. It read as a photograph that was hard to get hold of,
/// and it was worst on a cut-out, where the part that looks draggable is a
/// small subject in a large transparent field. The canvas takes the room that
/// is left and the controls are a fixed block beneath it, so no scrollable
/// exists to compete.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ui/buttons.dart';
import '../ui/card.dart';
import '../ui/scaffold.dart';
import '../ui/states.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'product_image_framing.dart';
import 'product_image_store.dart';

/// Opens the framing editor over [image], answering with the framed photograph
/// or null if it was left alone.
///
/// [baker] is the seam a widget test replaces: the real one starts an isolate,
/// and a test that starts an isolate to check a button is a slow test that
/// fails for reasons of its own.
Future<TenantProductImageCandidate?> showProductFramingEditor(
  BuildContext context, {
  required TenantProductImageCandidate image,
  TenantProductFramingBaker baker = bakeProductFraming,
}) => Navigator.of(context).push<TenantProductImageCandidate>(
  MaterialPageRoute<TenantProductImageCandidate>(
    builder: (_) => ProductFramingScreen(image: image, baker: baker),
  ),
);

final class ProductFramingScreen extends StatefulWidget {
  const ProductFramingScreen({
    super.key,
    required this.image,
    this.baker = bakeProductFraming,
  });

  final TenantProductImageCandidate image;
  final TenantProductFramingBaker baker;

  @override
  State<ProductFramingScreen> createState() => _ProductFramingScreenState();
}

final class _ProductFramingScreenState extends State<ProductFramingScreen> {
  /// Decoded once, at the size it is drawn at rather than at the size it was
  /// photographed at, for the reason `TenantProductVisual` gives: a
  /// twelve-megapixel photograph is eighty megabytes of pixels and this screen
  /// needs a few hundred of them across.
  late final ImageProvider<Object> _provider = ResizeImage(
    MemoryImage(widget.image.bytes),
    width: framedProductImageSide,
    height: framedProductImageSide,
    policy: ResizeImagePolicy.fit,
  );

  /// **A notifier rather than `setState`, because this changes every frame of
  /// a drag.** Rebuilding the whole screen sixty times a second - scaffold,
  /// buttons, footer and all - is what makes a direct-manipulation gesture
  /// feel heavy, and heavy is indistinguishable from wrong when the thing
  /// under your finger is supposed to be the picture itself. Only the picture
  /// and the readout listen.
  final ValueNotifier<_Grip> _grip = ValueNotifier<_Grip>(const _Grip());

  ImageStream? _stream;
  ImageStreamListener? _listener;

  /// Null until the photograph has been decoded far enough to say how wide it
  /// is against how tall. Nothing can be framed before that is known, so the
  /// canvas draws its ground and the controls are disabled.
  double? _aspect;

  bool _busy = false;
  String? _failure;

  /// The framing and the finger position a pinch started from.
  _Grip _gestureStart = const _Grip();
  Offset _gestureFocal = Offset.zero;

  /// The canvas's measured side, cached from the last layout so the gesture
  /// handlers can work in canvas fractions. Written during build because
  /// `LayoutBuilder` is the only thing that knows it, and read only by
  /// callbacks that cannot run before a layout has happened.
  double _side = 1;

  @override
  void initState() {
    super.initState();
    _stream = _provider.resolve(ImageConfiguration.empty);
    _listener = ImageStreamListener(_accept, onError: _refuse);
    _stream!.addListener(_listener!);
  }

  @override
  void dispose() {
    final stream = _stream;
    final listener = _listener;
    if (stream != null && listener != null) stream.removeListener(listener);
    _grip.dispose();
    super.dispose();
  }

  void _accept(ImageInfo info, bool synchronous) {
    if (!mounted) return;
    final aspect = info.image.width / info.image.height;
    // Opens on what every surface already draws, so pressing the primary
    // action without touching anything is a no-op rather than a change.
    _grip.value = _Grip(framing: TenantProductFraming.filling(aspect));
    setState(() => _aspect = aspect);
  }

  void _refuse(Object error, StackTrace? stackTrace) {
    if (!mounted) return;
    setState(
      () => _failure =
          'That photograph could not be opened. Choose a different one.',
    );
  }

  void _onScaleStart(ScaleStartDetails details) {
    _gestureStart = _grip.value;
    _gestureFocal = details.localFocalPoint / _side;
    _grip.value = _grip.value.holding();
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final aspect = _aspect;
    if (aspect == null) return;
    final focal = details.localFocalPoint / _side;
    final scale = (_gestureStart.framing.scale * details.scale).clamp(
      minimumFramingScale,
      maximumFramingScale,
    );
    // Zoom about the fingers rather than about the middle, so the part of the
    // photograph under a pinch stays under it. The same expression covers a
    // one-finger drag, where `details.scale` is 1 and this reduces to the
    // start centre moved by however far the finger travelled.
    final growth = scale / _gestureStart.framing.scale;
    _place(
      TenantProductFraming(
        scale: scale,
        center: focal + (_gestureStart.framing.center - _gestureFocal) * growth,
        rotation: _snapped(_gestureStart.framing.rotation + details.rotation),
      ),
      held: true,
    );
  }

  void _onScaleEnd(ScaleEndDetails details) =>
      _grip.value = _grip.value.released();

  void _zoomBy(double factor) {
    // Pinching is not an option for everyone, and §9 does not let the only way
    // to reach a state be a two-finger gesture.
    _place(
      TenantProductFraming(
        scale: _grip.value.framing.scale * factor,
        center: _grip.value.framing.center,
        rotation: _grip.value.framing.rotation,
      ),
    );
  }

  /// A quarter turn, for a photograph that arrived on its side and for anyone
  /// who cannot hold two fingers on a screen and twist them.
  void _turnBy(double quarters) {
    final framing = _grip.value.framing;
    _place(
      TenantProductFraming(
        scale: framing.scale,
        center: framing.center,
        rotation: framing.rotation + quarters * math.pi / 2,
      ),
    );
  }

  /// A tilt within [_snapWindow] of square is treated as square.
  ///
  /// Without this, straight is a value a hand cannot hit: a twist gesture
  /// leaves a degree or two behind every time, and a product photograph that
  /// is one degree off reads as a mistake rather than as a choice. The window
  /// is small enough that a deliberate slight tilt is still reachable just
  /// outside it.
  static double _snapped(double rotation) {
    const quarter = math.pi / 2;
    final nearest = (rotation / quarter).roundToDouble() * quarter;
    return (rotation - nearest).abs() < _snapWindow ? nearest : rotation;
  }

  void _place(TenantProductFraming framing, {bool held = false}) {
    final aspect = _aspect;
    if (aspect == null) return;
    _grip.value = _Grip(framing: framing.clampedTo(aspect), held: held);
  }

  Future<void> _use() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      final framed = await widget.baker(
        source: widget.image,
        framing: _grip.value.framing,
      );
      if (!mounted) return;
      Navigator.of(context).pop(framed);
    } on TenantProductImageException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failure = error.code == 'invalid_image_size'
            ? 'That framing made a file too large to save. Zoom out a little '
                  'and try again.'
            : 'That photograph could not be framed. Choose a different one.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final ready = _aspect != null && !_busy;
    return AppScaffold(
      key: const ValueKey('product-framing-screen'),
      title: 'Position and zoom',
      subtitle: 'Whatever is inside the square is what every screen will show.',
      // A form's row rather than a table's: this is one picture and four
      // controls, and §4.2 gives that the reading width.
      contentWidth: AppContentWidth.reading,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // **The picture takes every pixel that is left over.** A framing
          // control is only as precise as the surface it is drawn on: the
          // first version gave it 350 and the rest of the screen to padding,
          // and placing a subject inside a third of a phone is guesswork.
          Expanded(child: _stage(tokens)),
          _controls(tokens, ready: ready),
          _footer(tokens, ready: ready),
        ],
      ),
    );
  }

  Widget _stage(AppTokens tokens) => Padding(
    padding: EdgeInsets.symmetric(horizontal: tokens.spacing.s20),
    child: Center(
      child: AspectRatio(
        aspectRatio: 1,
        child: DecoratedBox(
          decoration: BoxDecoration(
            // Recessed rather than raised: the square is a hole cut in the
            // page that the photograph sits behind, which is what makes the
            // area outside it read as "not kept" without a word being spent.
            color: tokens.colors.surface.sunken,
            borderRadius: BorderRadius.circular(tokens.radius.lg),
            border: Border.all(color: tokens.colors.surface.borderStrong),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(tokens.radius.lg),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final side = constraints.biggest.shortestSide;
                if (side.isFinite && side > 0) _side = side;
                return Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    if (_aspect case final aspect?)
                      // Opaque, so the whole square is the handle - including
                      // the transparent parts of a cut-out, which is exactly
                      // where a thumb lands when the subject is small.
                      GestureDetector(
                        key: const ValueKey('product-framing-canvas'),
                        behavior: HitTestBehavior.opaque,
                        onScaleStart: _onScaleStart,
                        onScaleUpdate: _onScaleUpdate,
                        onScaleEnd: _onScaleEnd,
                        child: ValueListenableBuilder<_Grip>(
                          valueListenable: _grip,
                          builder: (context, grip, _) => _picture(
                            tokens,
                            grip: grip,
                            aspect: aspect,
                            side: side,
                          ),
                        ),
                      ),
                    if (_busy)
                      ColoredBox(
                        color: tokens.colors.surface.scrim,
                        child: const LoadingState(
                          key: ValueKey('product-framing-working'),
                          message: 'Saving this framing',
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    ),
  );

  Widget _picture(
    AppTokens tokens, {
    required _Grip grip,
    required double aspect,
    required double side,
  }) {
    final placement = grip.framing.placementFor(aspect);
    return Stack(
      children: <Widget>[
        Positioned(
          left: placement.left * side,
          top: placement.top * side,
          width: placement.width * side,
          height: placement.height * side,
          // The rectangle already carries the photograph's own aspect, so
          // `fill` is exact rather than a stretch.
          // Turned about its own middle, which is where the rectangle above
          // is centred - so the tilt costs the placement nothing and the
          // baker reproduces it from the one angle.
          child: Transform.rotate(
            angle: grip.framing.rotation,
            filterQuality: FilterQuality.medium,
            child: Image(
              image: _provider,
              fit: BoxFit.fill,
              filterQuality: FilterQuality.medium,
              semanticLabel: 'The photograph being framed',
            ),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _FramingGuide(
                marks: tokens.colors.surface.borderStrong,
                thirds: tokens.colors.surface.borderSubtle,
                showThirds: grip.held,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _controls(AppTokens tokens, {required bool ready}) => Padding(
    padding: EdgeInsets.fromLTRB(
      tokens.spacing.s20,
      tokens.spacing.s16,
      tokens.spacing.s20,
      0,
    ),
    child: AppCard(
      padding: EdgeInsets.all(tokens.spacing.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              AppIconButton(
                key: const ValueKey('product-framing-zoom-out'),
                icon: Icons.zoom_out,
                semanticLabel: 'Zoom out',
                onPressed: ready ? () => _zoomBy(1 / _zoomStep) : null,
              ),
              SizedBox(width: tokens.spacing.s8),
              AppIconButton(
                key: const ValueKey('product-framing-zoom-in'),
                icon: Icons.zoom_in,
                semanticLabel: 'Zoom in',
                onPressed: ready ? () => _zoomBy(_zoomStep) : null,
              ),
              SizedBox(width: tokens.spacing.s8),
              AppIconButton(
                key: const ValueKey('product-framing-turn-left'),
                icon: Icons.rotate_left,
                semanticLabel: 'Turn a quarter left',
                onPressed: ready ? () => _turnBy(-1) : null,
              ),
              SizedBox(width: tokens.spacing.s8),
              AppIconButton(
                key: const ValueKey('product-framing-turn-right'),
                icon: Icons.rotate_right,
                semanticLabel: 'Turn a quarter right',
                onPressed: ready ? () => _turnBy(1) : null,
              ),
              SizedBox(width: tokens.spacing.s8),
              Expanded(
                child: ValueListenableBuilder<_Grip>(
                  valueListenable: _grip,
                  builder: (context, grip, _) => Text(
                    key: const ValueKey('product-framing-readout'),
                    _readout(grip.framing),
                    textAlign: TextAlign.end,
                    style: tokens.typography.numericCompact.copyWith(
                      color: tokens.colors.text.secondary,
                    ),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: tokens.spacing.s8),
          Row(
            children: <Widget>[
              Expanded(
                child: AppButton(
                  key: const ValueKey('product-framing-whole'),
                  label: 'Whole photo',
                  size: AppButtonSize.sm,
                  expand: true,
                  onPressed: ready
                      ? () => _place(
                          TenantProductFraming.whole(
                            rotation: _grip.value.framing.rotation,
                          ),
                        )
                      : null,
                ),
              ),
              SizedBox(width: tokens.spacing.s8),
              Expanded(
                child: AppButton(
                  key: const ValueKey('product-framing-fill'),
                  label: 'Fill the frame',
                  size: AppButtonSize.sm,
                  expand: true,
                  onPressed: ready && _aspect != null
                      ? () => _place(
                          TenantProductFraming.filling(
                            _aspect!,
                            rotation: _grip.value.framing.rotation,
                          ),
                        )
                      : null,
                ),
              ),
            ],
          ),
          SizedBox(height: tokens.spacing.s8),
          Text(
            'Drag to move it. Pinch to zoom, twist to tilt. Zoom out past the '
            'edges to leave a margin.',
            style: tokens.typography.caption.copyWith(
              color: tokens.colors.text.tertiary,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _footer(AppTokens tokens, {required bool ready}) => Padding(
    padding: EdgeInsets.fromLTRB(
      tokens.spacing.s20,
      tokens.spacing.s12,
      tokens.spacing.s20,
      0,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (_failure case final failure?) ...<Widget>[
          Callout(
            key: const ValueKey('product-framing-failed'),
            status: AppStatus.problem,
            message: failure,
          ),
          SizedBox(height: tokens.spacing.s12),
        ],
        SafeArea(
          top: false,
          minimum: EdgeInsets.only(bottom: tokens.spacing.s12),
          child: AppActionRow(
            expandActions: true,
            actions: <Widget>[
              AppButton(
                key: const ValueKey('product-framing-cancel'),
                label: 'Cancel',
                tier: AppButtonTier.tertiary,
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
              ),
              AppButton(
                key: const ValueKey('product-framing-apply'),
                label: 'Use this framing',
                tier: AppButtonTier.primary,
                loading: _busy,
                onPressed: ready ? _use : null,
              ),
            ],
          ),
        ),
      ],
    ),
  );

  /// The zoom, said in the only unit that means anything here.
  ///
  /// 100% is the whole photograph - the *Whole photo* preset - rather than
  /// some ratio to the original pixels, which nobody framing a picture of a
  /// bottle is thinking about.
  static String _readout(TenantProductFraming framing) {
    final zoom = '${(framing.scale * 100).round()}%';
    final degrees = (framing.rotation * 180 / math.pi).round() % 360;
    return degrees == 0 ? zoom : '$zoom  $degrees°';
  }

  /// How close to a quarter turn counts as square. Two degrees.
  static const double _snapWindow = 0.035;

  /// One press of a zoom control. A quarter is large enough to be worth a tap
  /// and small enough to land on a framing somebody meant.
  static const double _zoomStep = 1.25;
}

/// The framing, plus whether a finger is currently on it.
///
/// One value rather than two notifiers so a frame of a drag is one rebuild.
final class _Grip {
  const _Grip({
    this.framing = const TenantProductFraming.whole(),
    this.held = false,
  });

  final TenantProductFraming framing;

  /// Whether the guide lines are shown. They are drawn only while a gesture is
  /// in progress: standing on the picture the rest of the time, they would be
  /// drawing over the thing being judged.
  final bool held;

  _Grip holding() => _Grip(framing: framing, held: true);
  _Grip released() => _Grip(framing: framing);

  @override
  bool operator ==(Object other) =>
      other is _Grip && other.framing == framing && other.held == held;

  @override
  int get hashCode => Object.hash(framing, held);
}

/// Corner marks always; thirds only while the picture is being moved.
///
/// A crop surface with no marks on it is a picture on a dark rectangle, and
/// there is nothing to say where its edges are once the photograph has been
/// zoomed past them.
final class _FramingGuide extends CustomPainter {
  const _FramingGuide({
    required this.marks,
    required this.thirds,
    required this.showThirds,
  });

  final Color marks;
  final Color thirds;
  final bool showThirds;

  @override
  void paint(Canvas canvas, Size size) {
    if (showThirds) {
      final line = Paint()
        ..color = thirds
        ..strokeWidth = _hairline;
      for (var step = 1; step < 3; step++) {
        final x = size.width * step / 3;
        final y = size.height * step / 3;
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
        canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
      }
    }
    final mark = Paint()
      ..color = marks
      ..strokeWidth = _markWeight
      ..strokeCap = StrokeCap.square;
    final arm = size.shortestSide * _armFraction;
    for (final corner in <(Offset, double, double)>[
      (Offset.zero, 1, 1),
      (Offset(size.width, 0), -1, 1),
      (Offset(0, size.height), 1, -1),
      (Offset(size.width, size.height), -1, -1),
    ]) {
      final (origin, dx, dy) = corner;
      canvas.drawLine(origin, origin.translate(arm * dx, 0), mark);
      canvas.drawLine(origin, origin.translate(0, arm * dy), mark);
    }
  }

  @override
  bool shouldRepaint(_FramingGuide old) =>
      old.showThirds != showThirds ||
      old.marks != marks ||
      old.thirds != thirds;

  static const double _hairline = 1;
  static const double _markWeight = 3;

  /// How far a corner mark reaches along each edge, as a fraction of the
  /// square. Small enough to stay out of the picture, long enough to read as a
  /// corner rather than as a speck.
  static const double _armFraction = 0.08;
}
