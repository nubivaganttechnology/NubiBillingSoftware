import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class BarcodeLabelLine {
  const BarcodeLabelLine({
    required this.productName,
    required this.variantName,
    required this.barcode,
    required this.quantity,
    this.mrp = 0,
    this.sellingPrice = 0,
  });

  final String productName;
  final String variantName;
  final String barcode;
  final int quantity;
  final int mrp;
  final int sellingPrice;
}

class BarcodeLabelOptions {
  const BarcodeLabelOptions({
    required this.widthMm,
    required this.heightMm,
    this.businessName,
    this.showBusinessName = true,
    this.showProductName = true,
    this.showVariant = true,
    this.showMrp = false,
    this.showSellingPrice = false,
  });

  final double widthMm;
  final double heightMm;
  final String? businessName;
  final bool showBusinessName;
  final bool showProductName;
  final bool showVariant;
  final bool showMrp;
  final bool showSellingPrice;
}

/// Proportional measurements shared by the Flutter preview/PNG and PDF/print
/// renderers. Measurements are expressed in millimetres and point sizes.
class BarcodeLabelLayout {
  BarcodeLabelLayout({
    required this.widthMm,
    required this.heightMm,
    required this.showBusiness,
    required this.showProduct,
    required this.productLines,
    required this.showVariant,
    required this.showMrp,
    required this.showSellingPrice,
  }) : scale = (widthMm / 50 < heightMm / 25 ? widthMm / 50 : heightMm / 25)
           .clamp(0.65, 1.5),
       heightScale = (heightMm / 25).clamp(0.65, 1.6);

  final double widthMm;
  final double heightMm;
  final bool showBusiness;
  final bool showProduct;
  final int productLines;
  final bool showVariant;
  final bool showMrp;
  final bool showSellingPrice;
  final double scale;
  final double heightScale;

  double get outerMarginMm => (1.0 * scale).clamp(0.55, 1.4);
  double get barcodeQuietZoneMm => (2.0 * scale).clamp(1.6, 3.2);
  double get sectionGapMm => 0.18 * scale;
  double get businessFontPt => (6.0 * scale).clamp(5.0, 8.0);
  double get productFontPt => (7.4 * scale).clamp(5.3, 9.5);
  double get variantFontPt => (6.1 * scale).clamp(5.0, 8.0);
  double get barcodeNumberFontPt => (7.0 * scale).clamp(5.5, 9.0);
  double get priceFontPt => (6.0 * scale).clamp(5.0, 8.0);
  double get businessLineMm => businessFontPt * 0.37;
  double get productLineMm => productFontPt * 0.39;
  double get variantLineMm => variantFontPt * 0.37;
  double get barcodeNumberLineMm => barcodeNumberFontPt * 0.39;
  double get priceLineMm => priceFontPt * 0.37;
  double get productLinesHeightMm => productLineMm * productLines;
  double get verticalInsetMm => 0.25 * scale;

  double get barcodeHeightMm {
    final sections = <double>[
      if (showBusiness) businessLineMm,
      if (showProduct) productLinesHeightMm,
      if (showVariant) variantLineMm,
      barcodeNumberLineMm,
      if (showMrp || showSellingPrice) priceLineMm,
    ];
    final gaps = sections.length > 1 ? sectionGapMm * (sections.length - 1) : 0;
    final remaining =
        heightMm -
        2 * outerMarginMm -
        2 * verticalInsetMm -
        sections.fold<double>(0, (sum, value) => sum + value) -
        gaps;
    return remaining.clamp(3.8 * scale, 13.0 * heightScale).toDouble();
  }

  double get innerWidthMm => (widthMm - 2 * outerMarginMm).clamp(1, widthMm);
  double get barcodeWidthMm =>
      (innerWidthMm - 2 * barcodeQuietZoneMm).clamp(1, innerWidthMm);

  static double flutterFontSize(double fontPt) =>
      fontPt * (3.0 / (72.0 / 25.4));

  static String fitText(
    String value, {
    required double availableWidthMm,
    required double fontSizePt,
    int maxLines = 1,
  }) {
    final averageGlyphWidthMm = fontSizePt * (25.4 / 72) * 0.53;
    final charsPerLine = (availableWidthMm / averageGlyphWidthMm).floor().clamp(
      1,
      1000,
    );
    final maxCharacters = charsPerLine * maxLines;
    if (value.length <= maxCharacters) return value;
    var cutAt = maxCharacters - 1;
    final boundary = value.lastIndexOf(' ', cutAt);
    if (boundary > maxCharacters * 0.55) cutAt = boundary;
    return '${value.substring(0, cutAt).trimRight()}…';
  }

  static int estimateProductLines(
    String value,
    double widthMm,
    double heightMm,
  ) {
    if (value.isEmpty) return 1;
    final scale = (widthMm / 50 < heightMm / 25 ? widthMm / 50 : heightMm / 25)
        .clamp(0.65, 1.5);
    final fontPt = (7.4 * scale).clamp(5.3, 9.5);
    final charsPerLine =
        (widthMm.clamp(1, widthMm) / (fontPt * (25.4 / 72) * 0.53))
            .floor()
            .clamp(1, 1000);
    return (value.length / charsPerLine).ceil().clamp(1, 2);
  }
}

/// Builds exact-size, one-label-per-page Code 128 PDFs and opens the system
/// printer dialog. It only consumes barcode snapshots supplied by the caller.
class BarcodeLabelPrintService {
  const BarcodeLabelPrintService();

  static List<BarcodeLabelLine> expandLabels(List<BarcodeLabelLine> lines) => [
    for (final line in lines)
      for (var copy = 0; copy < line.quantity; copy++)
        BarcodeLabelLine(
          productName: line.productName,
          variantName: line.variantName,
          barcode: line.barcode,
          quantity: 1,
          mrp: line.mrp,
          sellingPrice: line.sellingPrice,
        ),
  ];

  Future<Uint8List> buildPdf(
    List<BarcodeLabelLine> lines,
    BarcodeLabelOptions options,
  ) async {
    final labels = expandLabels(lines);
    if (labels.isEmpty) throw ArgumentError('Add at least one label.');
    if (labels.any((line) => line.barcode.isEmpty)) {
      throw ArgumentError('Barcode not assigned to this variant.');
    }
    if (options.widthMm <= 0 || options.heightMm <= 0) {
      throw ArgumentError('Label width and height must be positive.');
    }

    final pdf = pw.Document();
    final pageFormat = PdfPageFormat(
      options.widthMm * PdfPageFormat.mm,
      options.heightMm * PdfPageFormat.mm,
    );
    for (final label in labels) {
      pdf.addPage(
        pw.Page(
          pageFormat: pageFormat,
          margin: pw.EdgeInsets.all(
            BarcodeLabelLayout(
                  widthMm: options.widthMm,
                  heightMm: options.heightMm,
                  showBusiness: false,
                  showProduct: false,
                  productLines: 0,
                  showVariant: false,
                  showMrp: false,
                  showSellingPrice: false,
                ).outerMarginMm *
                PdfPageFormat.mm,
          ),
          build: (_) => _label(label, options),
        ),
      );
    }
    return pdf.save();
  }

  Future<void> printLabels(
    List<BarcodeLabelLine> lines,
    BarcodeLabelOptions options,
  ) async {
    final bytes = await buildPdf(lines, options);
    await Printing.layoutPdf(
      name: 'NubiBill Barcode Labels',
      onLayout: (_) async => bytes,
      dynamicLayout: false,
    );
  }

  pw.Widget _label(BarcodeLabelLine line, BarcodeLabelOptions options) {
    final showBusiness =
        options.showBusinessName && (options.businessName ?? '').isNotEmpty;
    final showProduct = options.showProductName && line.productName.isNotEmpty;
    final showVariant = options.showVariant && line.variantName.isNotEmpty;
    final showMrp = options.showMrp;
    final showSellingPrice = options.showSellingPrice;
    final layout = BarcodeLabelLayout(
      widthMm: options.widthMm,
      heightMm: options.heightMm,
      showBusiness: showBusiness,
      showProduct: showProduct,
      productLines: showProduct
          ? BarcodeLabelLayout.estimateProductLines(
              line.productName,
              options.widthMm,
              options.heightMm,
            )
          : 0,
      showVariant: showVariant,
      showMrp: showMrp,
      showSellingPrice: showSellingPrice,
    );
    final contentWidth = layout.innerWidthMm * PdfPageFormat.mm;

    pw.Widget text(
      String value, {
      required double fontSize,
      bool bold = false,
      bool monospace = false,
      int maxLines = 1,
      pw.TextAlign align = pw.TextAlign.center,
    }) => pw.Text(
      value,
      maxLines: maxLines,
      textAlign: align,
      overflow: pw.TextOverflow.clip,
      style: pw.TextStyle(
        font: monospace
            ? (bold ? pw.Font.courierBold() : pw.Font.courier())
            : (bold ? pw.Font.helveticaBold() : pw.Font.helvetica()),
        fontSize: fontSize,
      ),
    );

    final priceText = [
      if (showMrp) 'MRP INR ${(line.mrp / 100).toStringAsFixed(2)}',
      if (showSellingPrice)
        'Sell INR ${(line.sellingPrice / 100).toStringAsFixed(2)}',
    ];

    return pw.SizedBox(
      width: contentWidth,
      height: (options.heightMm - 2 * layout.outerMarginMm) * PdfPageFormat.mm,
      child: pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          if (showBusiness) ...[
            text(
              BarcodeLabelLayout.fitText(
                options.businessName!,
                availableWidthMm: layout.innerWidthMm,
                fontSizePt: layout.businessFontPt,
              ),
              fontSize: layout.businessFontPt,
              bold: true,
            ),
            pw.SizedBox(height: layout.sectionGapMm * PdfPageFormat.mm),
          ],
          if (showProduct) ...[
            text(
              BarcodeLabelLayout.fitText(
                line.productName,
                availableWidthMm: layout.innerWidthMm,
                fontSizePt: layout.productFontPt,
                maxLines: 2,
              ),
              fontSize: layout.productFontPt,
              bold: true,
              maxLines: 2,
            ),
            pw.SizedBox(height: layout.sectionGapMm * PdfPageFormat.mm),
          ],
          if (showVariant) ...[
            text(
              BarcodeLabelLayout.fitText(
                line.variantName,
                availableWidthMm: layout.innerWidthMm,
                fontSizePt: layout.variantFontPt,
              ),
              fontSize: layout.variantFontPt,
            ),
            pw.SizedBox(height: layout.sectionGapMm * PdfPageFormat.mm),
          ],
          pw.SizedBox(
            height: layout.barcodeHeightMm * PdfPageFormat.mm,
            child: pw.Center(
              child: pw.BarcodeWidget(
                barcode: pw.Barcode.code128(),
                data: line.barcode,
                width: layout.barcodeWidthMm * PdfPageFormat.mm,
                height: layout.barcodeHeightMm * PdfPageFormat.mm,
                drawText: false,
              ),
            ),
          ),
          pw.SizedBox(height: layout.sectionGapMm * PdfPageFormat.mm),
          text(
            line.barcode,
            fontSize: layout.barcodeNumberFontPt,
            bold: true,
            monospace: true,
          ),
          if (priceText.isNotEmpty) ...[
            pw.SizedBox(height: layout.sectionGapMm * PdfPageFormat.mm),
            if (showMrp && showSellingPrice)
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Expanded(
                    child: text(
                      priceText[0],
                      fontSize: layout.priceFontPt,
                      align: pw.TextAlign.left,
                    ),
                  ),
                  pw.Expanded(
                    child: text(
                      priceText[1],
                      fontSize: layout.priceFontPt,
                      align: pw.TextAlign.right,
                    ),
                  ),
                ],
              )
            else
              text(
                priceText.single,
                fontSize: layout.priceFontPt,
                align: pw.TextAlign.center,
              ),
          ],
        ],
      ),
    );
  }
}
