/// One Settings screen with the settings inside it.
///
/// **What this replaces was five separate routes on the home menu**, each its
/// own page, each reached and left one at a time. They are one page now with a
/// tab apiece, which is the shape a person expects of settings and the shape
/// that has somewhere to put the next one.
///
/// **This is a container change and nothing else.** Every tab hosts the *panel*
/// each of those routes already wrapped in its own `AppScaffold`, so each keeps
/// its own `TenantRouteGuard`, its own role list, and its own denied, loading
/// and failure states. Nothing about what any setting does, who may change it,
/// or what it says when refused is decided here. `claude.md` hard rule 1 holds.
///
/// **A tab's panel is not built until its tab is opened**, and that is a real
/// property rather than an optimisation. Each of these panels reads a document
/// when it mounts; building all six at once would turn opening Settings from one
/// read into six, which would be a behaviour change wearing a layout change's
/// clothes. Once opened, a tab stays built, so going back to it does not read
/// again.
library;

import 'package:flutter/material.dart';

import '../ui/scaffold.dart';
import '../ui/states.dart';
import '../ui/tabs.dart';
import '../ui/tokens.dart';
import 'tenant_session_controller.dart';
import 'tenant_types.dart';

/// One tab of the settings screen.
final class TenantSettingsTab {
  const TenantSettingsTab({
    required this.tabKey,
    required this.label,
    required this.allowedRoles,
    required this.builder,
  });

  /// Stable across renames, because the home menu links to a tab by it.
  final String tabKey;

  /// The word on the tab. Sentence case, §8 rule 7.
  final String label;

  /// Who is offered it.
  ///
  /// **The same list the panel's own guard enforces**, and offered here only so
  /// a tab nobody may open is not drawn. The guard inside is still what decides;
  /// this is the menu layer, exactly as the home destinations are.
  final List<TenantRole> allowedRoles;

  final WidgetBuilder builder;
}

final class TenantSettingsScreen extends StatelessWidget {
  const TenantSettingsScreen({
    super.key,
    required this.tabs,
    this.initialTabKey,
  });

  final List<TenantSettingsTab> tabs;

  /// Which tab opens first, so the home menu can still link to one setting.
  final String? initialTabKey;

  @override
  Widget build(BuildContext context) {
    final session = TenantSessionScope.of(context).session;
    final visible = <TenantSettingsTab>[
      for (final tab in tabs)
        if (session != null && session.canAccess(allowedRoles: tab.allowedRoles))
          tab,
    ];

    if (visible.isEmpty) {
      // The reports hub's answer to the same question, and for the same reason:
      // a role with nothing here is told so, rather than shown an empty strip.
      return const AppScaffold(
        title: 'Settings',
        contentWidth: AppContentWidth.reading,
        body: EmptyState(
          key: ValueKey('settings-none'),
          title: 'No settings are shown for this role',
          hint: 'Ask an owner or administrator to change a business setting.',
        ),
      );
    }

    final initial = visible.indexWhere((tab) => tab.tabKey == initialTabKey);
    return DefaultTabController(
      length: visible.length,
      initialIndex: initial < 0 ? 0 : initial,
      child: AppScaffold(
        title: 'Settings',
        contentWidth: AppContentWidth.reading,
        // **The strip goes in the body under the page header, not in the
        // toolbar.** §7's page pattern is header, then callout, then filters,
        // then content, and a tab strip is this page's filter row - leaving it
        // in `AppBar.bottom` would put it above the title it belongs to. The
        // platform console made the same move for the same reason.
        body: Column(
          children: <Widget>[
            AppTabs(
              tabs: <String>[for (final tab in visible) tab.label],
            ),
            Expanded(
              child: TabBarView(
                children: <Widget>[
                  for (var index = 0; index < visible.length; index++)
                    _LazySettingsTab(
                      index: index,
                      builder: visible[index].builder,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Builds its tab's panel the first time that tab is looked at, and then keeps it.
///
/// `TabBarView` builds the pages either side of the selected one so a swipe has
/// something to show, which for these panels would mean firing a Firestore read
/// for a setting nobody has opened. This holds an empty box until its own index
/// is the selected one.
final class _LazySettingsTab extends StatefulWidget {
  const _LazySettingsTab({required this.index, required this.builder});

  final int index;
  final WidgetBuilder builder;

  @override
  State<_LazySettingsTab> createState() => _LazySettingsTabState();
}

class _LazySettingsTabState extends State<_LazySettingsTab> {
  TabController? _controller;
  bool _opened = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = DefaultTabController.of(context);
    if (identical(controller, _controller)) return;
    _controller?.removeListener(_handleTabChanged);
    _controller = controller..addListener(_handleTabChanged);
    _handleTabChanged();
  }

  @override
  void dispose() {
    _controller?.removeListener(_handleTabChanged);
    super.dispose();
  }

  void _handleTabChanged() {
    final controller = _controller;
    if (_opened || controller == null) return;
    if (controller.index != widget.index) return;
    // Opened once is opened for good: coming back to a tab must not read the
    // document again.
    if (mounted) setState(() => _opened = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_opened) return const SizedBox.shrink();
    // **The scroll view and the page inset each tab's own route used to
    // supply.** Every one of these panels was written to sit inside
    // `AppScaffold`'s body *under a screen that wrapped it in exactly this*,
    // because `AppScaffold` pads nothing horizontally - "the 20 every body pads
    // itself with". Hosting the bare panel dropped both, so the first build of
    // this screen ran its text to the window edge and gave a long form nowhere
    // to scroll. Supplying it here rather than in each builder is what keeps
    // the four tabs identical.
    return SingleChildScrollView(
      padding: EdgeInsets.all(
        AppScaffold.horizontalInset(AppTokens.componentOf(context).spacing),
      ),
      child: widget.builder(context),
    );
  }
}
