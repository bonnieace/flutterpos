import 'dart:io';

import 'package:flutter/material.dart';
import 'package:uzapay_pos/ui/illustration.dart';
import 'package:uzapay_pos/ui/tokens.dart';

import 'harness.dart';

// Authored artwork on the page and dialog grounds, at the empty-state size.
void main() {
  final assets =
      Directory('assets/illustrations')
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.svg'))
          .map((file) => file.uri.pathSegments.last)
          .toList()
        ..sort();
  const priority = [
    'customers.svg',
    'returns.svg',
    'inventory.svg',
    'stock-count.svg',
    'customer-account.svg',
    'customer-purchases.svg',
    'stock-review.svg',
    'production.svg',
    'categories.svg',
    'stock-movements.svg',
    'stock-adjustment.svg',
    'product-ledger.svg',
    'suppliers.svg',
    'audit-history.svg',
    'notifications.svg',
    'reconciliation.svg',
  ];
  final ordered = [
    ...priority,
    ...assets.where((asset) => !priority.contains(asset)),
  ];
  for (var offset = 0; offset < ordered.length; offset += 16) {
    final page = offset ~/ 16 + 1;
    final shown = ordered.skip(offset).take(16);
    screenshotCase(
      'illustration-artistic-gallery-${page.toString().padLeft(2, '0')}',
      fullPage: false,
      viewports: const [
        ScreenshotViewport(
          name: 'audit',
          size: Size(1440, 1080),
          devicePixelRatio: 1,
        ),
      ],
      build: () => Builder(
        builder: (context) {
          final tokens = AppTokens.componentOf(context);
          return Scaffold(
            backgroundColor: tokens.colors.surface.base,
            body: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Artistic illustrations: page background (left), dialog background (right)',
                    style: tokens.typography.titleMedium.copyWith(
                      color: tokens.colors.text.primary,
                    ),
                  ),
                ),
                Expanded(
                  child: GridView.count(
                    crossAxisCount: 4,
                    childAspectRatio: 1.44,
                    children: [
                      for (final asset in shown)
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              asset,
                              style: tokens.typography.caption.copyWith(
                                color: tokens.colors.text.secondary,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                SizedBox.square(
                                  dimension: 168,
                                  child: ColoredBox(
                                    color: tokens.colors.surface.base,
                                    child: AppIllustration(
                                      asset: asset,
                                      size: 168,
                                    ),
                                  ),
                                ),
                                SizedBox.square(
                                  dimension: 168,
                                  child: ColoredBox(
                                    color: tokens.colors.surface.raised,
                                    child: AppIllustration(
                                      asset: asset,
                                      size: 168,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
