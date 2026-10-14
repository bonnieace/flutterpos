import 'package:flutter/material.dart';

import 'tokens.dart';

/// Related workflow regions share a row when their actual available space
/// supports it. On smaller surfaces they retain their original reading order.
final class AppWorkspace extends StatelessWidget {
  const AppWorkspace({
    super.key,
    required this.leading,
    required this.trailing,
    this.leadingFlex = 1,
    this.trailingFlex = 2,
    this.spaceWhenStacked = false,
  });

  final Widget leading;
  final Widget trailing;
  final int leadingFlex;
  final int trailingFlex;
  final bool spaceWhenStacked;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide =
            constraints.maxWidth >=
            tokens.layout.expandedFloor - tokens.spacing.s24 * 2;
        if (!wide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              leading,
              if (spaceWhenStacked) SizedBox(height: tokens.spacing.s24),
              trailing,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: leadingFlex, child: leading),
            SizedBox(width: tokens.spacing.s24),
            Expanded(flex: trailingFlex, child: trailing),
          ],
        );
      },
    );
  }
}
