/// `Pagination`'s state matrix, per `claude.md` hard rule 5 and §10.
///
/// **Three rows: the first page, a middle page, and the last.** They are the
/// whole matrix, because the two `AppButton`s inside carry `hover`,
/// `focus-visible` and `pressed` and are already photographed in
/// `90-appbutton-*`, and `loading`, `error`, `read-only` and `empty` have no
/// meaning for a bar that moves between pages.
///
/// **Captured at both bands, and the phone is the one that matters.** Two
/// 48-high pills with two-word labels plus a page statement do not fit 411
/// logical pixels beside each other; the `Wrap` is what keeps that from being
/// an overflow, and this is the picture that shows it running to two lines.
library;

import 'package:flutter/material.dart';
import 'package:flutter_application_1/ui/pagination.dart';
import 'package:flutter_application_1/ui/tokens.dart';

import 'harness.dart';

void main() {
  screenshotCase(
    '95-pagination-first-page',
    // What eleven of the thirteen screens used to draw as a lone `Next page`.
    build: () => const _Host(pageNumber: 1, hasPrevious: false),
    fullPage: false,
  );

  screenshotCase(
    '95-pagination-middle',
    build: () => const _Host(pageNumber: 4),
    fullPage: false,
  );

  screenshotCase(
    '95-pagination-last-page',
    build: () => const _Host(pageNumber: 9, hasNext: false),
    fullPage: false,
  );
}

final class _Host extends StatelessWidget {
  const _Host({
    required this.pageNumber,
    this.hasPrevious = true,
    this.hasNext = true,
  });

  final int pageNumber;
  final bool hasPrevious;
  final bool hasNext;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.componentOf(context);
    return Scaffold(
      backgroundColor: tokens.colors.surface.base,
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(tokens.spacing.s24),
          child: Pagination(
            pageNumber: pageNumber,
            onPrevious: hasPrevious ? () {} : null,
            onNext: hasNext ? () {} : null,
          ),
        ),
      ),
    );
  }
}
