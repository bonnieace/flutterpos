import 'package:flutter/material.dart';

import '../ui/scaffold.dart';
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
  });

  final WidgetBuilder currencyBuilder;
  final WidgetBuilder stockCountsBuilder;

  @override
  Widget build(BuildContext context) {
    final inset = AppScaffold.horizontalInset(
      AppTokens.componentOf(context).spacing,
    );
    return DefaultTabController(
      length: 2,
      child: AppScaffold(
        title: 'Configs',
        contentWidth: AppContentWidth.reading,
        body: Column(
          children: <Widget>[
            const TabBar(
              tabs: <Tab>[
                Tab(text: 'Currency'),
                Tab(text: 'Stock counts'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: <Widget>[
                  _ConfigurationTab(builder: currencyBuilder, inset: inset),
                  _ConfigurationTab(builder: stockCountsBuilder, inset: inset),
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
