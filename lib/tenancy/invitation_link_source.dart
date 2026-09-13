/// Where an emailed staff invitation enters the app.
///
/// **The link had nowhere to arrive until 2026-09-08.** `main` read it out of
/// `Uri.base`, which carries a query string on the web and, on Android, is the
/// app's own working directory - so `TenantInvitationLink.fromUriIfPresent`
/// answered `null` on every launch a phone has ever made, and the emailed proof
/// could not be acted on at all. The invitation's landing page said to accept in
/// the app; the app, for exactly those invitees, said to use the link in the
/// email. This file is the missing half of that circle.
///
/// **Two arrivals, because a link is followed in two situations.** The app is
/// closed and the link starts it, or the app is already running and Android
/// hands the new intent to the existing activity. The first is a value waiting
/// to be taken before the first frame; the second is an event. `MainActivity`
/// answers both over one channel and this turns them into one stream of
/// [TenantInvitationArrival].
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'tenant_invitation_acceptance.dart';

/// A staff invitation link the app was handed, valid or not.
///
/// Malformed is a state rather than a dropped event: a link that arrived and
/// could not be read is exactly what the *This invitation link is invalid*
/// screen exists to say, and silently ignoring it would leave somebody who
/// followed a link staring at a screen that never mentions it.
@immutable
final class TenantInvitationArrival {
  const TenantInvitationArrival.valid(TenantInvitationLink this.link)
    : invalid = false;

  const TenantInvitationArrival.invalid() : link = null, invalid = true;

  final TenantInvitationLink? link;
  final bool invalid;

  /// Reads one arrival from a URI, or null when the URI is about something else.
  ///
  /// The two other App Links this app answers - `/auth/verified`, and the
  /// password-reset page's own continue URL - carry no invitation fields and
  /// produce nothing here, which is what brings the app to the foreground
  /// without also putting a screen in front of somebody.
  static TenantInvitationArrival? fromUri(Uri uri) {
    try {
      final link = TenantInvitationLink.fromUriIfPresent(uri);
      return link == null ? null : TenantInvitationArrival.valid(link);
    } on FormatException {
      return const TenantInvitationArrival.invalid();
    }
  }
}

/// The platform's answer to "what URL opened this app, and what opens it next".
abstract interface class InvitationLinkSource {
  /// The URL the app was launched with, or null. Answers null a second time:
  /// the launch link is consumed, so a rebuilt activity cannot replay it.
  Future<Uri?> takeLaunchLink();

  /// URLs followed while the app was already running.
  Stream<Uri> get links;
}

/// Reads the launch URL from the host page's own address.
///
/// The web and desktop answer, and what `main` did on every platform before the
/// channel existed. There is no second arrival: a running page is not handed
/// another URL without being reloaded.
final class UriBaseInvitationLinkSource implements InvitationLinkSource {
  const UriBaseInvitationLinkSource([this._base]);

  final Uri? _base;

  @override
  Future<Uri?> takeLaunchLink() async => _base ?? Uri.base;

  @override
  Stream<Uri> get links => const Stream<Uri>.empty();
}

/// Reads both arrivals from `MainActivity` over `pos/launch-link`.
final class PlatformInvitationLinkSource implements InvitationLinkSource {
  PlatformInvitationLinkSource({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName) {
    _channel.setMethodCallHandler(_receive);
  }

  static const String channelName = 'pos/launch-link';

  final MethodChannel _channel;
  final StreamController<Uri> _links = StreamController<Uri>.broadcast();

  Future<Object?> _receive(MethodCall call) async {
    if (call.method != 'launchLink') return null;
    final parsed = _parse(call.arguments);
    if (parsed != null && !_links.isClosed) _links.add(parsed);
    return null;
  }

  @override
  Future<Uri?> takeLaunchLink() async {
    try {
      return _parse(await _channel.invokeMethod<String>('takeLaunchLink'));
    } on MissingPluginException {
      // A platform with no such channel was launched some other way. Not a
      // failure: every platform but Android reaches this, and reports no link
      // because there is no link to report.
      return null;
    } on PlatformException {
      return null;
    }
  }

  @override
  Stream<Uri> get links => _links.stream;

  Future<void> dispose() async {
    _channel.setMethodCallHandler(null);
    await _links.close();
  }

  static Uri? _parse(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return Uri.tryParse(value);
  }
}

/// The app's single view of "is there an invitation waiting, and which one".
///
/// Owns the launch link so `main` can seed the routing shell with it before the
/// first frame, and the stream so a link followed later reaches the same shell
/// without the app being restarted.
final class InvitationLinkIntake {
  InvitationLinkIntake(this._source);

  final InvitationLinkSource _source;
  final StreamController<TenantInvitationArrival> _arrivals =
      StreamController<TenantInvitationArrival>.broadcast();
  final ValueNotifier<TenantInvitationArrival?> _arrival =
      ValueNotifier<TenantInvitationArrival?>(null);
  StreamSubscription<Uri>? _subscription;

  /// The arrival that started the app, read once by [start].
  TenantInvitationArrival? launchArrival;

  /// Arrivals after the launch one.
  Stream<TenantInvitationArrival> get arrivals => _arrivals.stream;

  /// The invitation this app was opened by, and whether it could be read.
  ///
  /// **Three states, because there are three.** This was a `bool` until
  /// 2026-09-12, and `TenantInvitationArrival.invalid()` is not null - so a
  /// malformed link read as *an invitation is waiting* and the sign-in screen
  /// told somebody to sign in for a business that would never be offered. The
  /// screen that says the link is unreadable needs a `uid` and a bootstrap
  /// result to draw, so the one person who could not reach it was the signed-out
  /// invitee holding the broken link.
  ///
  /// Read by the sign-in screen, which is where a signed-out invitee lands after
  /// following a link and would otherwise be shown the app's front door with no
  /// explanation of why it opened. Null draws nothing.
  ValueListenable<TenantInvitationArrival?> get arrival => _arrival;

  /// Reads the launch link and subscribes to later ones. Awaited before
  /// `runApp`, so the first frame already knows.
  Future<void> start() async {
    final launch = await _source.takeLaunchLink();
    launchArrival = launch == null
        ? null
        : TenantInvitationArrival.fromUri(launch);
    _arrival.value = launchArrival;
    _subscription = _source.links.listen((uri) {
      final arrival = TenantInvitationArrival.fromUri(uri);
      if (arrival == null || _arrivals.isClosed) return;
      _arrival.value = arrival;
      _arrivals.add(arrival);
    });
  }

  /// The invitation has been accepted, refused, or dismissed as unreadable.
  void settled() => _arrival.value = null;

  Future<void> dispose() async {
    await _subscription?.cancel();
    _arrival.dispose();
    await _arrivals.close();
  }
}
