import 'package:flutter_test/flutter_test.dart';
import 'package:testflutter/data/services/barcode_label_print_service.dart';

void main() {
  const service = BarcodeLabelPrintService();

  test(
    'expands requested quantities without changing stored barcode values',
    () {
      const lines = [
        BarcodeLabelLine(
          productName: 'Legacy item',
          variantName: 'Small',
          barcode: '1',
          quantity: 2,
        ),
        BarcodeLabelLine(
          productName: 'Internal item',
          variantName: '20 Litre',
          barcode: '700000000003',
          quantity: 3,
        ),
      ];

      final labels = BarcodeLabelPrintService.expandLabels(lines);

      expect(labels, hasLength(5));
      expect(labels.take(2).map((label) => label.barcode), ['1', '1']);
      expect(labels.skip(2).map((label) => label.barcode), [
        '700000000003',
        '700000000003',
        '700000000003',
      ]);
    },
  );

  test(
    'Code 128 PDF renders short legacy and 12-digit values as stored',
    () async {
      final bytes = await service.buildPdf(const [
        BarcodeLabelLine(
          productName: 'Legacy item',
          variantName: 'Small',
          barcode: '1',
          quantity: 1,
        ),
        BarcodeLabelLine(
          productName: 'Internal item',
          variantName: '20 Litre',
          barcode: '700000000003',
          quantity: 1,
        ),
      ], const BarcodeLabelOptions(widthMm: 50, heightMm: 25));

      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
      expect(bytes.length, greaterThan(500));
    },
  );

  test(
    'printing refuses a missing barcode instead of generating one',
    () async {
      await expectLater(
        service.buildPdf(const [
          BarcodeLabelLine(
            productName: 'Unassigned item',
            variantName: 'Default',
            barcode: '',
            quantity: 1,
          ),
        ], const BarcodeLabelOptions(widthMm: 50, heightMm: 25)),
        throwsArgumentError,
      );
    },
  );

  test(
    'shared layout gives long names two lines and reclaims disabled fields',
    () {
      const longName =
          'ASIAN PAINTS DAMP PROOF ULTRA COOL PU WEATHER PROTECTION';
      final longLines = BarcodeLabelLayout.estimateProductLines(
        longName,
        50,
        25,
      );
      final full = BarcodeLabelLayout(
        widthMm: 50,
        heightMm: 25,
        showBusiness: true,
        showProduct: true,
        productLines: longLines,
        showVariant: true,
        showMrp: true,
        showSellingPrice: true,
      );
      final minimal = BarcodeLabelLayout(
        widthMm: 50,
        heightMm: 25,
        showBusiness: false,
        showProduct: false,
        productLines: 0,
        showVariant: false,
        showMrp: false,
        showSellingPrice: false,
      );

      expect(longLines, 2);
      expect(full.barcodeQuietZoneMm, greaterThanOrEqualTo(2));
      expect(minimal.barcodeHeightMm, greaterThan(full.barcodeHeightMm));
    },
  );

  test('preset and custom dimensions scale the barcode and margins', () {
    final layouts = [
      for (final (width, height) in [
        (50.0, 25.0),
        (50.0, 30.0),
        (40.0, 25.0),
        (65.0, 35.0),
      ])
        BarcodeLabelLayout(
          widthMm: width,
          heightMm: height,
          showBusiness: true,
          showProduct: true,
          productLines: 1,
          showVariant: true,
          showMrp: true,
          showSellingPrice: true,
        ),
    ];

    expect(layouts.every((layout) => layout.barcodeHeightMm > 0), isTrue);
    expect(layouts.every((layout) => layout.barcodeWidthMm > 0), isTrue);
    expect(layouts[1].barcodeHeightMm, greaterThan(layouts[0].barcodeHeightMm));
    expect(layouts[2].productFontPt, lessThan(layouts[0].productFontPt));
  });

  test(
    'full compact label fits with two-line product name and both prices',
    () async {
      final bytes = await service.buildPdf(
        const [
          BarcodeLabelLine(
            productName:
                'ASIAN PAINTS DAMP PROOF ULTRA COOL PU WEATHER PROTECTION',
            variantName: '10 Litre',
            barcode: '700000000001',
            quantity: 1,
            mrp: 50000,
            sellingPrice: 45000,
          ),
        ],
        const BarcodeLabelOptions(
          widthMm: 50,
          heightMm: 25,
          businessName: 'Suman Enterprises',
          showBusinessName: true,
          showProductName: true,
          showVariant: true,
          showMrp: true,
          showSellingPrice: true,
        ),
      );

      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
      expect(bytes.length, greaterThan(500));
    },
  );
}
