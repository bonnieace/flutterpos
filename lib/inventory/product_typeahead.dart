/// Inline catalog search for forms that select a product.
library;

import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';

import '../tenancy/tenant_catalog.dart';
import '../tenancy/tenant_repository.dart';
import '../tenancy/tenant_session.dart';
import '../ui/fields.dart';
import '../ui/tokens.dart';
import 'catalog_management.dart';

final class TenantProductTypeAhead extends StatefulWidget {
  const TenantProductTypeAhead({
    super.key,
    required this.session,
    required this.reader,
    required this.label,
    required this.onSelected,
    this.productSearchReader,
    this.selected,
    this.excludedIds = const <String>{},
    this.admits,
    this.refusedHint,
    this.onEdited,
    this.enabled = true,
    this.autofocus = false,
  });

  final TenantSession session;
  final TenantDataReader reader;
  final TenantProductSearchReader? productSearchReader;
  final String label;
  final TenantProduct? selected;
  final Set<String> excludedIds;
  final bool Function(TenantProduct)? admits;
  final String? refusedHint;
  final ValueChanged<TenantProduct> onSelected;
  final VoidCallback? onEdited;
  final bool enabled;
  final bool autofocus;

  @override
  State<TenantProductTypeAhead> createState() => _TenantProductTypeAheadState();
}

final class _TenantProductTypeAheadState extends State<TenantProductTypeAhead> {
  late final TextEditingController _search = TextEditingController(
    text: widget.selected?.name,
  );
  int _refused = 0;
  int _searchGeneration = 0;

  @override
  void didUpdateWidget(covariant TenantProductTypeAhead oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected?.id != oldWidget.selected?.id &&
        widget.selected != null) {
      _search.text = widget.selected!.name;
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<List<TenantProduct>?> _suggest(String value) async {
    final generation = ++_searchGeneration;
    final term = tenantProductSearchTerm(value);
    if (term.length < 2) return null;
    final page = await TenantCatalogRepository(
      session: widget.session,
      reader: widget.reader,
      productSearchReader: widget.productSearchReader,
    ).searchProducts(pageSize: 20, searchPrefix: term);
    final live = page.items.where((product) => !product.retired).toList();
    final admits = widget.admits;
    final offered = admits == null ? live : live.where(admits).toList();
    if (mounted && generation == _searchGeneration) {
      setState(() => _refused = live.length - offered.length);
    }
    return offered;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    final caption = tokens.typography.caption.copyWith(
      color: tokens.colors.text.tertiary,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TypeAheadField<TenantProduct>(
          controller: _search,
          debounceDuration: AppMotion.standard.long.duration,
          suggestionsCallback: _suggest,
          builder: (context, controller, focusNode) => AppTextField(
            key: const ValueKey('product-typeahead-search'),
            controller: controller,
            focusNode: focusNode,
            label: widget.label,
            enabled: widget.enabled,
            autofocus: widget.autofocus,
            leading: Icons.search,
            helper: 'Type at least 2 characters from a name or code.',
            onChanged: (value) {
              if (tenantProductSearchTerm(value).length < 2 && _refused != 0) {
                setState(() => _refused = 0);
              }
              if (widget.selected != null && value != widget.selected!.name) {
                widget.onEdited?.call();
              }
            },
          ),
          itemBuilder: (context, product) {
            final added = widget.excludedIds.contains(product.id);
            return ListTile(
              key: ValueKey('product-typeahead-${product.id}'),
              title: Text(product.name),
              subtitle: Text(
                <String>[
                  if (product.sku.isNotEmpty) product.sku,
                  '${product.quantity} in stock',
                ].join(' · '),
              ),
              trailing: added
                  ? Text(
                      'Added',
                      key: ValueKey('product-typeahead-added-${product.id}'),
                    )
                  : null,
              enabled: !added,
            );
          },
          onSelected: (product) {
            if (!widget.enabled || widget.excludedIds.contains(product.id)) {
              return;
            }
            _search.text = product.name;
            widget.onSelected(product);
          },
          emptyBuilder: (context) => Padding(
            padding: EdgeInsets.all(tokens.spacing.s16),
            child: Text(
              _refused > 0 && widget.refusedHint != null
                  ? 'No eligible product matches.'
                  : 'No product matches. Try another name word or code.',
              style: caption,
            ),
          ),
          errorBuilder: (context, error) => Padding(
            padding: EdgeInsets.all(tokens.spacing.s16),
            child: Text('The catalog could not be searched.', style: caption),
          ),
        ),
        if (_refused > 0 && widget.refusedHint != null) ...<Widget>[
          SizedBox(height: tokens.spacing.s8),
          Text(widget.refusedHint!, style: caption),
        ],
      ],
    );
  }
}
