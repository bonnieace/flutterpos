/// The catalog a sales record is drawn against, so a sale line can show the
/// product's own photograph instead of a package glyph.
///
/// **The line has an id and nothing else to draw with.** `TenantSaleLine`
/// records what a product was called and what it cost at the moment of the
/// sale, because a sale is immutable evidence and must not change when the
/// catalog does. A picture is not evidence, so it is looked up rather than
/// recorded - and looked up in the offline catalog the till already keeps, so
/// a day's sales cost no reads to illustrate and illustrate the same offline
/// as online.
///
/// **A miss is a row without a picture, never a failed page.** The cache is a
/// Hive box that may be cold, may belong to another business, or may not hold a
/// product that has since been deleted. Every one of those draws the glyph the
/// row drew before this existed.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../checkout/checkout_catalog_cache.dart';
import '../tenancy/tenant_catalog.dart';
import '../tenancy/tenant_session.dart';

/// Reads one session's cached catalog once and offers it to the rows beneath.
final class SaleLineProducts extends StatefulWidget {
  const SaleLineProducts({
    super.key,
    required this.catalog,
    required this.session,
    required this.child,
  });

  /// Absent where no cache was composed in - a test, or a build with no Hive
  /// behind it. The rows below then draw their glyph and nothing waits.
  final CheckoutCatalogSource? catalog;

  /// Null before the guard has admitted a session. Nothing is read until one
  /// arrives, and a different one is read again.
  final TenantSession? session;

  final Widget child;

  /// The product [productId] names, or null while the cache is still being
  /// read and for ever if it does not hold it.
  static TenantProduct? of(BuildContext context, String productId) => context
      .dependOnInheritedWidgetOfExactType<_SaleLineProductScope>()
      ?.snapshot
      ?.productById(productId);

  @override
  State<SaleLineProducts> createState() => _SaleLineProductsState();
}

class _SaleLineProductsState extends State<SaleLineProducts> {
  CheckoutCatalogSnapshot? _snapshot;

  /// The session the outstanding read was started for, so a switch that lands
  /// out of order cannot show one business's pictures under another's sales.
  String? _reading;

  static String? _keyOf(TenantSession? session) =>
      session == null ? null : '${session.uid}:${session.tenantId}';

  @override
  void initState() {
    super.initState();
    unawaited(_read());
  }

  @override
  void didUpdateWidget(covariant SaleLineProducts oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.catalog != oldWidget.catalog ||
        _keyOf(widget.session) != _keyOf(oldWidget.session)) {
      unawaited(_read());
    }
  }

  Future<void> _read() async {
    final catalog = widget.catalog;
    final session = widget.session;
    final key = _keyOf(session);
    _reading = key;
    if (catalog == null || session == null) {
      if (_snapshot != null) setState(() => _snapshot = null);
      return;
    }
    CheckoutCatalogSnapshot? snapshot;
    try {
      snapshot = await catalog.read(
        uid: session.uid,
        tenantId: session.tenantId,
      );
    } on Object {
      // An unreadable cache is a page of glyphs, which is the page that was
      // drawn before pictures were on offer at all.
      snapshot = null;
    }
    if (!mounted || _reading != key) return;
    // The cart's own rule: a snapshot that is not this session's is a miss.
    setState(
      () => _snapshot = snapshot != null && snapshot.ownsSession(session)
          ? snapshot
          : null,
    );
  }

  @override
  Widget build(BuildContext context) =>
      _SaleLineProductScope(snapshot: _snapshot, child: widget.child);
}

final class _SaleLineProductScope extends InheritedWidget {
  const _SaleLineProductScope({required this.snapshot, required super.child});

  final CheckoutCatalogSnapshot? snapshot;

  @override
  bool updateShouldNotify(_SaleLineProductScope oldWidget) =>
      !identical(snapshot, oldWidget.snapshot);
}
