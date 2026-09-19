/// `AppTabs`'s matrix, per `claude.md` hard rule 5 and §10.
///
/// **Two rows: the selected tab and the rest.** That is the whole matrix a tab
/// strip has — `loading`, `error`, `read-only` and `empty` mean nothing for it,
/// and `hover`, `focus-visible` and `pressed` are `TabBar`'s own and cannot be
/// photographed here any more than a ripple could.
///
/// **The phone capture is the one worth reading.** Four labels of two and three
/// words are far wider than 411 logical pixels, so the strip scrolls; this is
/// the picture of what a person actually sees first, which is two and a half
/// tabs.
library;

import 'package:flutter/material.dart';
import 'package:flutter_application_1/ui/tabs.dart';
import 'package:flutter_application_1/ui/tokens.dart';

import 'harness.dart';

void main() {
  screenshotCase(
    '95-apptabs-first-selected',
    // The platform route's own two, verbatim.
    build: () => const _Host(),
    fullPage: false,
  );

  screenshotCase(
    '95-apptabs-second-selected',
    build: () => const _Host(initialIndex: 1),
    fullPage: false,
  );
}

final class _Host extends StatelessWidget {
  const _Host({this.initialIndex = 0});

  final int initialIndex;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return DefaultTabController(
      // Two, because two is what `AppTabs` below is given. This said four, and
      // `TabBar` asserts the controller's length against the tabs it is handed:
      // "Controller's length property (4) does not match the number of tabs
      // (2)". The comment above has always said two.
      length: 2,
      initialIndex: initialIndex,
      child: Scaffold(
        backgroundColor: tokens.colors.surface.base,
        body: const Column(
          children: <Widget>[
            AppTabs(
              tabs: <String>[
                'Active & suspended',
                'Global user status',
              ],
            ),
          ],
        ),
      ),
    );
  }
}
