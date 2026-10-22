import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../../data/services/invoice_print_service.dart';

class PrintFormatDialog extends StatefulWidget {
  const PrintFormatDialog({
    super.key,
    required this.data,
    this.initialFormat = InvoicePrintFormat.a4Standard,
    this.initialCustomWidthMm = 80.0,
    this.onSaveDefaultFormat,
  });

  final InvoicePrintData data;
  final InvoicePrintFormat initialFormat;
  final double initialCustomWidthMm;
  final void Function(InvoicePrintFormat format, double customWidthMm)?
      onSaveDefaultFormat;

  static Future<void> show({
    required BuildContext context,
    required InvoicePrintData data,
    String? defaultFormatString,
    double defaultCustomWidthMm = 80.0,
    void Function(InvoicePrintFormat format, double customWidthMm)?
        onSaveDefaultFormat,
  }) async {
    final initialFormat = _parseFormat(defaultFormatString);
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => PrintFormatDialog(
        data: data,
        initialFormat: initialFormat,
        initialCustomWidthMm: defaultCustomWidthMm,
        onSaveDefaultFormat: onSaveDefaultFormat,
      ),
    );
  }

  static InvoicePrintFormat _parseFormat(String? formatStr) {
    switch (formatStr) {
      case 'A5_COMPACT':
        return InvoicePrintFormat.a5Compact;
      case 'THERMAL_80MM':
        return InvoicePrintFormat.thermal80mm;
      case 'THERMAL_58MM':
        return InvoicePrintFormat.thermal58mm;
      case 'CUSTOM':
        return InvoicePrintFormat.custom;
      case 'A4_STANDARD':
      default:
        return InvoicePrintFormat.a4Standard;
    }
  }

  static String formatToString(InvoicePrintFormat format) {
    switch (format) {
      case InvoicePrintFormat.a5Compact:
        return 'A5_COMPACT';
      case InvoicePrintFormat.thermal80mm:
        return 'THERMAL_80MM';
      case InvoicePrintFormat.thermal58mm:
        return 'THERMAL_58MM';
      case InvoicePrintFormat.custom:
        return 'CUSTOM';
      case InvoicePrintFormat.a4Standard:
        return 'A4_STANDARD';
    }
  }

  @override
  State<PrintFormatDialog> createState() => _PrintFormatDialogState();
}

class _PrintFormatDialogState extends State<PrintFormatDialog> {
  late InvoicePrintFormat _selectedFormat;
  late final TextEditingController _customWidthController;
  bool _rememberAsDefault = false;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _selectedFormat = widget.initialFormat;
    _customWidthController = TextEditingController(
      text: widget.initialCustomWidthMm.toStringAsFixed(0),
    );
  }

  @override
  void dispose() {
    _customWidthController.dispose();
    super.dispose();
  }

  double get _customWidthMm =>
      double.tryParse(_customWidthController.text.trim()) ?? 80.0;

  static PdfPageFormat _pageFormatFor(
    InvoicePrintFormat format,
    double customWidthMm,
  ) {
    switch (format) {
      case InvoicePrintFormat.a4Standard:
        return PdfPageFormat.a4;
      case InvoicePrintFormat.a5Compact:
        return PdfPageFormat.a5;
      case InvoicePrintFormat.thermal80mm:
        return PdfPageFormat.roll80;
      case InvoicePrintFormat.thermal58mm:
        return PdfPageFormat.roll57;
      case InvoicePrintFormat.custom:
        return PdfPageFormat(
          customWidthMm * PdfPageFormat.mm,
          double.infinity,
          marginAll: 2.5 * PdfPageFormat.mm,
        );
    }
  }

  Future<void> _handlePrint() async {
    setState(() => _isProcessing = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      if (_rememberAsDefault && widget.onSaveDefaultFormat != null) {
        widget.onSaveDefaultFormat!(_selectedFormat, _customWidthMm);
      }
      final bytes = await InvoicePrintService.buildPdf(
        data: widget.data,
        format: _selectedFormat,
        customWidthMm: _customWidthMm,
      );
      if (!mounted) return;
      Navigator.pop(context);
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: widget.data.invoiceNumber,
        format: _pageFormatFor(_selectedFormat, _customWidthMm),
        dynamicLayout: false,
      );
    } catch (e) {
      messenger?.showSnackBar(
        SnackBar(content: Text('Print error: $e')),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _handleShare() async {
    setState(() => _isProcessing = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      if (_rememberAsDefault && widget.onSaveDefaultFormat != null) {
        widget.onSaveDefaultFormat!(_selectedFormat, _customWidthMm);
      }
      final bytes = await InvoicePrintService.buildPdf(
        data: widget.data,
        format: _selectedFormat,
        customWidthMm: _customWidthMm,
      );
      if (!mounted) return;
      Navigator.pop(context);
      final invoiceNum = widget.data.invoiceNumber;
      await SharePlus.instance.share(
        ShareParams(
          text: 'Invoice $invoiceNum',
          files: [
            XFile.fromData(
              bytes,
              name: '$invoiceNum.pdf',
              mimeType: 'application/pdf',
            ),
          ],
        ),
      );
    } catch (e) {
      messenger?.showSnackBar(
        SnackBar(content: Text('Share error: $e')),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.print_outlined, color: theme.colorScheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Select Print Format',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  'Invoice ${widget.data.invoiceNumber}',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => Navigator.pop(context),
            tooltip: 'Cancel',
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 6),
              _buildOptionTile(
                format: InvoicePrintFormat.a4Standard,
                icon: Icons.description_outlined,
                title: 'A4 Standard Laser/Inkjet Invoice',
                subtitle:
                    'Full sheet GST tax invoice with HSN summary, terms, bank details & signature',
              ),
              _buildOptionTile(
                format: InvoicePrintFormat.a5Compact,
                icon: Icons.article_outlined,
                title: 'A5 Compact Half-Page Invoice',
                subtitle:
                    'Economical half-page layout (fits 2 bills per A4 page)',
              ),
              _buildOptionTile(
                format: InvoicePrintFormat.thermal80mm,
                icon: Icons.receipt_long_outlined,
                title: '80mm (3-inch) Thermal POS Slip',
                subtitle:
                    'Standard continuous roll receipt with itemized list & UPI QR code',
              ),
              _buildOptionTile(
                format: InvoicePrintFormat.thermal58mm,
                icon: Icons.receipt_outlined,
                title: '58mm (2-inch) Thermal POS Slip',
                subtitle:
                    'Compact roll receipt for portable Bluetooth & mini thermal printers',
              ),
              _buildOptionTile(
                format: InvoicePrintFormat.custom,
                icon: Icons.straighten_outlined,
                title: 'Custom Size Thermal / Paper',
                subtitle:
                    'Specify any roll width in millimeters (e.g., 58mm, 72mm, 80mm, 100mm)',
              ),

              // Interactive custom width input
              if (_selectedFormat == InvoicePrintFormat.custom) ...[
                const SizedBox(height: 10),
                Container(
                  margin: const EdgeInsets.only(left: 48, right: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceVariant.withOpacity(0.35),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: theme.colorScheme.outline.withOpacity(0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Text(
                        'Paper Width:',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 90,
                        child: TextField(
                          controller: _customWidthController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            isDense: true,
                            suffixText: 'mm',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 8,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '(40mm - 150mm)',
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 12),
              const Divider(),

              // Remember preference checkbox
              CheckboxListTile(
                value: _rememberAsDefault,
                onChanged: (val) =>
                    setState(() => _rememberAsDefault = val ?? false),
                title: const Text(
                  'Remember as default format',
                  style: TextStyle(fontSize: 13),
                ),
                subtitle: const Text(
                  'Future bills will default to this format in settings',
                  style: TextStyle(fontSize: 11),
                ),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
              ),
            ],
          ),
        ),
      ),
      actions: [
        OutlinedButton.icon(
          onPressed: _isProcessing ? null : _handleShare,
          icon: const Icon(Icons.share_outlined, size: 18),
          label: const Text('Share PDF'),
        ),
        FilledButton.icon(
          onPressed: _isProcessing ? null : _handlePrint,
          icon: _isProcessing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.print_outlined, size: 18),
          label: const Text('Print Bill'),
        ),
      ],
    );
  }

  Widget _buildOptionTile({
    required InvoicePrintFormat format,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final isSelected = _selectedFormat == format;
    final theme = Theme.of(context);

    return InkWell(
      onTap: () => setState(() => _selectedFormat = format),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primary.withOpacity(0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary
                : theme.colorScheme.outline.withOpacity(0.2),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Radio<InvoicePrintFormat>(
              value: format,
              groupValue: _selectedFormat,
              onChanged: (val) {
                if (val != null) setState(() => _selectedFormat = val);
              },
            ),
            Icon(
              icon,
              size: 24,
              color: isSelected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.w500,
                      color: isSelected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
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
