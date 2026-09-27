/// That a report actually renders, and what can honestly be claimed from that.
///
/// **What these tests prove:** a document carrying all five visual kinds, an
/// absent cell, a negative variance, an empty category and a caveat lays out
/// end to end without throwing, produces a real PDF, and does so entirely in
/// pure Dart - no widget tree, no `View`, no pumped frame, no binding. That
/// last property is the one the whole renderer design rests on, so it is worth
/// a test on its own.
///
/// **What they do not prove:** that the thing looks right. `pdf` cannot parse
/// its own output, and `tool/screenshots` rasterises a Flutter widget tree
/// which none of this ever enters. Fidelity is checked by eye, against the
/// files `tool/reports/render_samples.dart` writes, and on a device. Nothing
/// here should ever be reported as proof that a document is well laid out.
library;

import 'dart:io';

import 'package:uzapay_pos/reporting/reporting_currency.dart';
import 'package:uzapay_pos/reports/render/report_fonts.dart';
import 'package:uzapay_pos/reports/render/pdf_report.dart';
import 'package:uzapay_pos/reports/report_document.dart';
import 'package:uzapay_pos/reports/report_scope.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/documents.dart';

void main() {
  group('a document renders to a PDF', () {
    test('the bytes are a PDF', () async {
      final file = await TenantPdfReportRenderer.standard().render(
        fixtureDocument(),
      );

      expect(
        String.fromCharCodes(file.bytes.take(5)),
        '%PDF-',
        reason: 'A PDF says so in its first five bytes.',
      );
      expect(
        file.bytes.length,
        greaterThan(2000),
        reason:
            'A document with five charts and a table that came out under a '
            'couple of kilobytes did not draw what it was given.',
      );
    });

    test('it renders with no Flutter binding at all', () async {
      // The property the whole design rests on: `package:pdf/widgets.dart` is
      // standalone Dart, so a report can be built in a plain test with no
      // widget tree to mount and no frame to pump. If this ever starts needing
      // `TestWidgetsFlutterBinding.ensureInitialized`, something has reached
      // for a Flutter API and the renderer has stopped being pure.
      await expectLater(
        TenantPdfReportRenderer.standard().render(fixtureDocument()),
        completes,
      );
    });

    test('the file names itself after the business, report and period', () async {
      final file = await TenantPdfReportRenderer.standard().render(
        fixtureDocument(),
      );

      expect(
        file.filename,
        'mama-njeri-stores-sales-2026-09-01-to-2026-09-22.pdf',
        reason:
            'Leading with the business and ending with the dates means a '
            'folder of these sorts itself.',
      );
      expect(file.mimeType, 'application/pdf');
    });

    test('the share sheet is told what it is carrying', () async {
      final file = await TenantPdfReportRenderer.standard().render(
        fixtureDocument(),
      );

      expect(file.subject, contains('Sales report'));
      expect(
        file.text,
        contains('Mama Njeri Stores'),
        reason:
            'A file arriving in somebody else s mail should say whose '
            'business it is about without being opened.',
      );
    });
  });

  group('the awkward cases lay out rather than throw', () {
    test('a business with no logo, no slogan and no currency', () async {
      final identity = fixtureIdentity(
        slogan: null,
        currency: TenantReportingCurrency.unknown,
      );

      final file = await TenantPdfReportRenderer.standard().render(
        fixtureDocument(identity: identity),
      );

      expect(
        file.bytes.length,
        greaterThan(2000),
        reason:
            'The commonest business in this app has published a name and '
            'nothing else. That is the default case, not an edge one.',
      );
    });

    test('a truncated read still renders, carrying its caveat', () async {
      final period = fixturePeriod();
      final document = fixtureDocument(
        scope: TenantReportScope(
          period: period,
          documentsRead: 250,
          coveredFrom: '2026-09-14',
          coveredTo: '2026-09-22',
          caveats: <TenantReportCaveat>[
            TenantReportCaveat.truncated(
              asked: period,
              reachedFrom: '2026-09-14',
              reachedTo: '2026-09-22',
              records: 250,
            ),
          ],
        ),
      );

      expect(
        document.scope.isComplete,
        isFalse,
        reason: 'It reached nine days of the twenty-two asked for.',
      );
      await expectLater(
        TenantPdfReportRenderer.standard().render(document),
        completes,
      );
    });

    test('a report with no sections at all', () async {
      final who = fixtureIdentity();
      final document = TenantReportDocument(
        kind: TenantReportKind.returns,
        identity: who,
        scope: TenantReportScope(
          period: fixturePeriod(),
          documentsRead: 0,
        ),
        subtitle: 'Nothing was returned in this period.',
        headline: const <TenantReportFigure>[],
        sections: const <TenantReportSection>[],
      );

      final file = await TenantPdfReportRenderer.standard().render(document);

      expect(
        String.fromCharCodes(file.bytes.take(5)),
        '%PDF-',
        reason:
            'A quiet period is a real answer. The cover page and the scope '
            'block still have to print, or the person cannot tell an empty '
            'period from a failed read.',
      );
    });
  });

  group('the brand sets the document', () {
    test('a run with no renderer injected loads the bundled faces', () async {
      // **The bug a device run found and no unit test could.** Every test here
      // passes `.standard()` on purpose, so the one path nothing exercised was
      // the one the app actually takes - and it reached for the built-in-faces
      // renderer, putting real reports in Helvetica with nothing embedded
      // while every sample rendered in Hanken Grotesk.
      //
      // `bundled()` degrades to the built-in faces when no bundle can be read,
      // which is what happens here, so this asserts the wiring rather than the
      // glyphs: the run must not name `.standard()` itself.
      // Comments are stripped first: the explanation above this very rule
      // names the thing it forbids, and a scan that read prose would fail on
      // its own reasoning.
      final source = (await File('lib/reports/report_run.dart').readAsLines())
          .where((line) => !line.trimLeft().startsWith('//'))
          .join(' ');

      expect(
        source.contains('TenantPdfReportRenderer.standard()'),
        isFalse,
        reason:
            'The delivery path must load the bundled faces. Falling back to '
            'the built-in renderer here is what shipped a Helvetica report.',
      );
      expect(
        source.contains('TenantReportFonts.bundled()'),
        isTrue,
        reason: 'And it loads them through the cached accessor.',
      );
    });

    test('the bundled faces are held across reports', () async {
      // Six TrueType files is most of a megabyte, and parsing them is the
      // slowest part of a short report. Two reports must share one read.
      final first = TenantReportFonts.bundled();
      final second = TenantReportFonts.bundled();

      expect(
        identical(first, second),
        isTrue,
        reason: 'The future itself is cached, so concurrent asks share a read.',
      );
      await first;
    });
  });

  group('the currency rule reaches paper', () {
    test('a published code labels every figure', () {
      final who = fixtureIdentity(
        currency: TenantReportingCurrency.forTesting('KES'),
      );

      expect(who.money(486350), 'KES 4863.50');
      expect(
        who.signedMoney(-12000),
        '-KES 120',
        reason: 'A variance reads as a direction before it reads as a number.',
      );
      expect(
        who.currencyNotice,
        isNull,
        reason: 'There is nothing to apologise for when a code is published.',
      );
    });

    test('no published code means a bare figure and a sentence', () {
      final who = fixtureIdentity(
        currency: TenantReportingCurrency.unknown,
      );

      expect(
        who.money(486350),
        '4863.50',
        reason:
            'Reporting never guesses a currency. There is no defensible '
            'default and a wrong code is worse than none.',
      );
      expect(
        who.currencyNotice,
        TenantReportingCurrency.unknownNotice,
        reason: 'The document says why the figures are unlabelled.',
      );
    });

    test('the notice is carried in the document caveats', () {
      final document = fixtureDocument(
        identity: fixtureIdentity(currency: TenantReportingCurrency.unknown),
      );

      expect(
        document.caveats,
        contains(TenantReportingCurrency.unknownNotice),
        reason:
            'Assembled once on the document so the PDF and the workbook '
            'cannot print different lists of what went wrong.',
      );
    });
  });

  group('the filename survives a business name that fights it', () {
    test('punctuation and case are flattened', () {
      final who = fixtureIdentity(businessName: "Mama Njeri's Duka & Sons!");

      expect(
        who.slug,
        'mama-njeri-s-duka-sons',
        reason:
            'The file crosses a share sheet into whatever filesystem the '
            'person picked. A name that arrives mangled is worse than one '
            'that arrives plain.',
      );
    });

    test('a name that is entirely punctuation still yields a filename', () {
      expect(
        fixtureIdentity(businessName: '!!!').slug,
        'report',
        reason: 'An empty filename is not a filename.',
      );
    });

    test('a very long name is cut rather than carried', () {
      final who = fixtureIdentity(
        businessName: 'The Extremely Long Trading Company Of Greater Nairobi '
            'And Surrounding Districts Limited',
      );

      expect(who.slug.length, lessThanOrEqualTo(40));
      expect(who.slug, startsWith('the-extremely-long'));
    });
  });
}
