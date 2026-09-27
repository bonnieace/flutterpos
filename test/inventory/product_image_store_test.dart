import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:uzapay_pos/inventory/inventory.dart';
import 'package:uzapay_pos/tenancy/tenancy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('product image validation', () {
    test('accepts JPEG, PNG, and WebP by content signature', () {
      final candidates = <TenantProductImageCandidate>[
        TenantProductImageCandidate(
          bytes: Uint8List.fromList(<int>[0xff, 0xd8, 0xff, 0x00]),
          fileName: 'photo.bin',
        ),
        TenantProductImageCandidate(
          bytes: Uint8List.fromList(<int>[
            0x89,
            0x50,
            0x4e,
            0x47,
            0x0d,
            0x0a,
            0x1a,
            0x0a,
          ]),
          fileName: 'photo.bin',
        ),
        TenantProductImageCandidate(
          bytes: Uint8List.fromList('RIFF0000WEBP'.codeUnits),
          fileName: 'photo.bin',
        ),
      ];

      expect(candidates.map((candidate) => candidate.type), <Object?>[
        TenantProductImageType.jpeg,
        TenantProductImageType.png,
        TenantProductImageType.webp,
      ]);
    });

    test('rejects empty, oversized, and unsupported files', () {
      expect(
        () => TenantProductImageCandidate(
          bytes: Uint8List(0),
          fileName: 'empty.png',
        ),
        throwsA(
          isA<TenantProductImageException>().having(
            (error) => error.code,
            'code',
            'invalid_image_size',
          ),
        ),
      );
      expect(
        () => TenantProductImageCandidate(
          bytes: Uint8List(maximumTenantProductImageBytes + 1),
          fileName: 'large.png',
        ),
        throwsA(
          isA<TenantProductImageException>().having(
            (error) => error.code,
            'code',
            'invalid_image_size',
          ),
        ),
      );
      expect(
        () => TenantProductImageCandidate(
          bytes: Uint8List.fromList('GIF89a'.codeUnits),
          fileName: 'wrong.png',
        ),
        throwsA(
          isA<TenantProductImageException>().having(
            (error) => error.code,
            'code',
            'unsupported_image_type',
          ),
        ),
      );
    });
  });

  testWidgets('a product without an image renders stable initials', (
    tester,
  ) async {
    final product = TenantProduct.fromDocument(
      path: 'tenants/tenant-a/products/product-a',
      data: const <String, Object?>{
        'name': 'Brown Bread',
        'SKU': 'BR-1',
        'price': 65,
        'quantity': 4,
        'categoryId': 'bakery',
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox.square(
            dimension: 64,
            child: TenantProductVisual(product: product),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('product-image-fallback-product-a')),
      findsOneWidget,
    );
    expect(find.text('BB'), findsOneWidget);
  });
}
