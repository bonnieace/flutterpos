/// Choosing one product from the catalog inside a form - a delivery line, a
/// production batch.
///
/// **The catalog's own search**, so a product is found by the same name words
/// and code prefixes the Inventory screen finds it by, and a product this
/// device added a moment ago is found too: the search is read through the
/// overlay that draws queued changes.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../tenancy/tenant_catalog.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_session.dart';
import '../ui/fields.dart';
import '../ui/record_list.dart';
import '../ui/sheet.dart';
import '../ui/states.dart';
import '../ui/status.dart';
import '../ui/tokens.dart';
import 'catalog_management.dart';

/// Opens the picker and answers with the product chosen, or null.
///
/// [excludedIds] are products the form already holds, offered as already
/// added rather than twice. [admits] narrows what may be chosen - production
/// admits only products made here - and [refusedHint] says why a product that
/// matched the search was not offered.
Future<TenantProduct?> showTenantProductPicker(
  BuildContext context, {
  required TenantSession session,
  required TenantDataReader reader,
  TenantProductSearchReader? productSearchReader,
  Set<String> excludedIds = const <String>{},
  bool Function(TenantProduct product)? admits,
  String? refusedHint,
  String title = 'Add a product',
}) => showAppSheet<TenantProduct>(
  context,
  initialDetent: AppSheetDetent.full,
  builder: (sheetContext, scrollController) => _ProductPicker(
    session: session,
    reader: reader,
    productSearchReader: productSearchReader,
    excludedIds: excludedIds,
    admits: admits,
    refusedHint: refusedHint,
    title: title,
    scrollController: scrollController,
    onChosen: (product) => Navigator.of(sheetContext).pop(product),
  ),
);

final class _ProductPicker extends StatefulWidget {
  const _ProductPicker({
    required this.session,
    required this.reader,
    required this.productSearchReader,
    required this.excludedIds,
    required this.admits,
    required this.refusedHint,
    required this.title,
    required this.scrollController,
    required this.onChosen,
  });

  final TenantSession session;
  final TenantDataReader reader;
  final TenantProductSearchReader? productSearchReader;
  final Set<String> excludedIds;
  final bool Function(TenantProduct product)? admits;
  final String? refusedHint;
  final String title;
  final ScrollController scrollController;
  final ValueChanged<TenantProduct> onChosen;

  @override
  State<_ProductPicker> createState() => _ProductPickerState();
}

enum _PickerPhase { idle, reading, ready, failed }

final class _ProductPickerState extends State<_ProductPicker> {
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;
  _PickerPhase _phase = _PickerPhase.idle;
  List<TenantProduct> _found = const <TenantProduct>[];
  int _refused = 0;
  int _generation = 0;

  /// How many matches one search offers. A picker is for finding one product,
  /// and a longer list is a sign the search needs another word.
  static const int pageSize = 20;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(AppMotion.standard.long.duration, () => _read(value));
  }

  Future<void> _read(String value) async {
    final term = tenantProductSearchTerm(value);
    if (term.length < 2) {
      setState(() {
        _phase = _PickerPhase.idle;
        _found = const <TenantProduct>[];
      });
      return;
    }
    final generation = ++_generation;
    setState(() => _phase = _PickerPhase.reading);
    try {
      final repository = TenantCatalogRepository(
        session: widget.session,
        reader: widget.reader,
        productSearchReader: widget.productSearchReader,
      );
      final page = await repository.searchProducts(
        pageSize: pageSize,
        searchPrefix: term,
      );
      if (!mounted || generation != _generation) return;
      final live = page.items.where((product) => !product.retired).toList();
      final admits = widget.admits;
      setState(() {
        _found = admits == null ? live : live.where(admits).toList();
        _refused = live.length - _found.length;
        _phase = _PickerPhase.ready;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() => _phase = _PickerPhase.failed);
    }
  }

  RecordItem _record(TenantProduct product) {
    final added = widget.excludedIds.contains(product.id);
    return RecordItem(
      id: product.id,
      recordKey: ValueKey('product-picker-row-${product.id}'),
      title: product.name,
      subtitle: product.sku,
      status: added
          ? RecordStatus(
              status: AppStatus.info,
              label: 'Added',
              badgeKey: ValueKey('product-picker-added-${product.id}'),
            )
          : null,
      attributes: <RecordAttribute>[
        RecordAttribute(label: 'In stock', value: '${product.quantity}'),
      ],
      actions: <RecordAction>[
        RecordAction(
          label: 'Choose',
          icon: Icons.add,
          actionKey: ValueKey('product-picker-choose-${product.id}'),
          onPressed: added ? null : () => widget.onChosen(product),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final Widget body = switch (_phase) {
      _PickerPhase.idle => Text(
        key: const ValueKey('product-picker-hint'),
        'Type at least 2 characters from a product name word or code.',
        style: tokens.typography.caption.copyWith(
          color: tokens.colors.text.tertiary,
        ),
      ),
      _PickerPhase.reading => const LoadingState(message: 'Searching'),
      _PickerPhase.failed => const ErrorState(
        key: ValueKey('product-picker-failure'),
        badgeLabel: 'Not read',
        statement: 'The catalog could not be searched.',
        stillTrue: 'Nothing has been added.',
      ),
      _PickerPhase.ready => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (_refused > 0 && widget.refusedHint != null) ...<Widget>[
            Callout(
              key: const ValueKey('product-picker-refused'),
              status: AppStatus.info,
              message: widget.refusedHint!,
            ),
            SizedBox(height: tokens.spacing.s12),
          ],
          RecordList(
            identityLabel: 'Product',
            items: <RecordItem>[for (final product in _found) _record(product)],
            empty: const EmptyState(
              key: ValueKey('product-picker-empty'),
              title: 'No product matches',
              hint: 'Try another word from its name, or its code.',
              illustration: 'file-search.svg',
            ),
          ),
        ],
      ),
    };
    return ListView(
      key: const ValueKey('product-picker'),
      controller: widget.scrollController,
      padding: EdgeInsets.all(tokens.spacing.s24),
      children: <Widget>[
        Text(
          widget.title,
          style: tokens.typography.titleMedium.copyWith(
            color: tokens.colors.text.primary,
          ),
        ),
        SizedBox(height: tokens.spacing.s16),
        AppTextField(
          key: const ValueKey('product-picker-search'),
          controller: _search,
          label: 'Search products',
          leading: Icons.search,
          autofocus: true,
          onChanged: _onChanged,
        ),
        SizedBox(height: tokens.spacing.s16),
        body,
      ],
    );
  }
}
