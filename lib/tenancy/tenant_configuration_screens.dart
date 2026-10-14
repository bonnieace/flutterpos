import 'package:flutter/material.dart';

import '../ui/scaffold.dart';
import '../ui/tabs.dart';
import '../ui/tokens.dart';

/// Hosts one existing configuration panel without changing its permissions or writes.
final class TenantConfigurationPage extends StatelessWidget {
  const TenantConfigurationPage({
    super.key,
    required this.title,
    required this.builder,
    this.ownsScroll = false,
  });

  final String title;
  final WidgetBuilder builder;

  /// See [TenantSettingsDestination.ownsScroll].
  final bool ownsScroll;

  @override
  Widget build(BuildContext context) => AppScaffold(
    title: title,
    contentWidth: AppContentWidth.records,
    body: ownsScroll
        ? Builder(builder: builder)
        : SingleChildScrollView(
            padding: EdgeInsets.all(
              AppScaffold.horizontalInset(
                AppTokens.componentOf(context).spacing,
              ),
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
    required this.agreedPricesBuilder,
  });

  final WidgetBuilder currencyBuilder;

  /// Who may sell for a price agreed with the customer. Added on 2026-09-29
  /// beside the stock count rota, because it is set up the same way: per
  /// person. The rota moved to the *Stock counts* screen's own *Settings* tab
  /// on 2026-10-04, and loyalty to the *Customers* screen's own tab the same
  /// day, which leaves this screen two tabs - a switch.
  final WidgetBuilder agreedPricesBuilder;

  List<String> get _tabs => const <String>['Currency', 'Agreed prices'];

  /// The glyph each tab's own panel already leads with, for the icon tabs a
  /// third tab would turn these into: the currency field's and the
  /// agreed-price rows'.
  List<IconData> get _icons => const <IconData>[
    Icons.payments_outlined,
    Icons.handshake_outlined,
  ];

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
            // Three tabs draw as icon tabs, packed from the start and
            // scrolling where they do not fit, and two as a switch; `AppTabs`
            // decides both, which is the measuring this screen used to do for
            // itself. The inset puts the tabs over the panels' own text.
            AppTabs(
              key: const ValueKey('configurations-tabs'),
              tabs: _tabs,
              icons: _icons,
              inset: inset,
            ),
            Expanded(
              child: TabBarView(
                children: <Widget>[
                  _ConfigurationTab(builder: currencyBuilder, inset: inset),
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
