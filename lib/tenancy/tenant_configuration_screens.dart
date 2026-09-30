import 'package:flutter/material.dart';

import '../ui/measure.dart';
import '../ui/scaffold.dart';
import '../ui/tabs.dart';
import '../ui/tokens.dart';

/// Hosts one existing configuration panel without changing its permissions or writes.
final class TenantConfigurationPage extends StatelessWidget {
  const TenantConfigurationPage({
    super.key,
    required this.title,
    required this.builder,
  });

  final String title;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) => AppScaffold(
    title: title,
    contentWidth: AppContentWidth.reading,
    body: SingleChildScrollView(
      padding: EdgeInsets.all(
        AppScaffold.horizontalInset(AppTokens.componentOf(context).spacing),
      ),
      child: Builder(builder: builder),
    ),
  );
}

/// A home for the configuration subjects that will grow over time.
final class TenantConfigurationsScreen extends StatelessWidget {
  const TenantConfigurationsScreen({
    super.key,
    required this.currencyBuilder,
    required this.stockCountsBuilder,
    required this.agreedPricesBuilder,
  });

  final WidgetBuilder currencyBuilder;
  final WidgetBuilder stockCountsBuilder;

  /// Who may sell for a price agreed with the customer. Added on 2026-09-29
  /// beside *Stock counts*, because it is set up the same way: per person.
  final WidgetBuilder agreedPricesBuilder;

  static const List<String> _tabs = <String>[
    'Currency',
    'Stock counts',
    'Agreed prices',
  ];

  /// Whether every label fits in an equal share of [width].
  ///
  /// **Measured, because the third tab broke the fixed strip on a small
  /// phone.** At 320 wide the three shares cut *Stock counts* and *Agreed
  /// prices* off mid-word, seen on an emulator on 2026-09-29. Where the
  /// labels fit, the strip keeps its equal shares; where they do not, it
  /// scrolls rather than cutting a word.
  static bool _labelsFit(BuildContext context, double width) {
    final tokens = AppTokens.componentOf(context);
    final share = width / _tabs.length;
    final scaler = MediaQuery.textScalerOf(context);
    for (final label in _tabs) {
      final needed =
          measureTextWidth(
            label,
            tokens.typography.labelLarge,
            textScaler: scaler,
          ) +
          kTabLabelPadding.horizontal;
      if (needed > share) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final inset = AppScaffold.horizontalInset(
      AppTokens.componentOf(context).spacing,
    );
    return DefaultTabController(
      length: _tabs.length,
      child: AppScaffold(
        title: 'Configs',
        contentWidth: AppContentWidth.reading,
        body: Column(
          children: <Widget>[
            // `AppTabs` rather than a bare `TabBar`: the system's type and
            // colours, and §9's 48 where Material's tab is 46.
            LayoutBuilder(
              builder: (context, constraints) => AppTabs(
                key: const ValueKey('configurations-tabs'),
                tabs: _tabs,
                isScrollable: !_labelsFit(context, constraints.maxWidth),
              ),
            ),
            Expanded(
              child: TabBarView(
                children: <Widget>[
                  _ConfigurationTab(builder: currencyBuilder, inset: inset),
                  _ConfigurationTab(builder: stockCountsBuilder, inset: inset),
                  _ConfigurationTab(builder: agreedPricesBuilder, inset: inset),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _ConfigurationTab extends StatefulWidget {
  const _ConfigurationTab({required this.builder, required this.inset});

  final WidgetBuilder builder;
  final double inset;

  @override
  State<_ConfigurationTab> createState() => _ConfigurationTabState();
}

final class _ConfigurationTabState extends State<_ConfigurationTab>
    with AutomaticKeepAliveClientMixin<_ConfigurationTab> {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return SingleChildScrollView(
      padding: EdgeInsets.all(widget.inset),
      child: Builder(builder: widget.builder),
    );
  }
}
