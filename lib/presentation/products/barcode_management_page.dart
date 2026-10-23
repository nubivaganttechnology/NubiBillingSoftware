import 'package:barcode_widget/barcode_widget.dart' as barcode_ui;
import 'package:flutter/material.dart';

import '../../core/utils/stock_quantity_formatter.dart';
import '../../data/models/product_model.dart';
import '../../data/models/product_variant_model.dart';
import '../../l10n/app_localizations.dart';
import '../../data/repositories/product_repository.dart';
import 'barcode_printing_page.dart';

enum _BarcodeSection { printing, lookup }

/// Independent dashboard module for local variant barcode operations.
class BarcodeManagementPage extends StatefulWidget {
  const BarcodeManagementPage({
    super.key,
    required this.products,
    required this.businessName,
    this.loadReceivedVariantIds = _noneReceived,
    this.loadReceivedVariantPricing,
    this.loadVariantBatches,
    this.availableQuantities = const {},
    this.initialProductId,
    this.initialVariantId,
  });

  final List<ProductModel> products;
  final String businessName;
  final Future<Set<String>> Function() loadReceivedVariantIds;
  final Future<Map<String, ({int mrp, int sellingPrice})>> Function()?
  loadReceivedVariantPricing;
  final Future<List<VariantBatchPriceOption>> Function(String variantId)?
  loadVariantBatches;
  final Map<String, int> availableQuantities;

  static Future<Set<String>> _noneReceived() async => const {};
  final String? initialProductId;
  final String? initialVariantId;

  @override
  State<BarcodeManagementPage> createState() => _BarcodeManagementPageState();
}

class _BarcodeManagementPageState extends State<BarcodeManagementPage> {
  _BarcodeSection _section = _BarcodeSection.printing;
  String? _selectedProductId;
  String? _selectedVariantId;

  @override
  void initState() {
    super.initState();
    _selectedProductId = widget.initialProductId;
    _selectedVariantId = widget.initialVariantId;
  }

  @override
  void didUpdateWidget(BarcodeManagementPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialProductId != oldWidget.initialProductId ||
        widget.initialVariantId != oldWidget.initialVariantId) {
      _selectedProductId = widget.initialProductId;
      _selectedVariantId = widget.initialVariantId;
    }
  }

  void _selectForPrint(String productId, String variantId) {
    setState(() {
      _selectedProductId = productId;
      _selectedVariantId = variantId;
      _section = _BarcodeSection.printing;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    // Compute executive KPI stats
    int totalVariants = 0;
    int barcodedCount = 0;
    int missingBarcodeCount = 0;
    int inStockReadyCount = 0;

    for (final product in widget.products) {
      if (product.status != 'ACTIVE') continue;
      for (final variant in product.variants) {
        if (variant.status != 'ACTIVE') continue;
        totalVariants++;
        final hasBarcode =
            variant.barcode != null && variant.barcode!.trim().isNotEmpty;
        if (hasBarcode) {
          barcodedCount++;
        } else {
          missingBarcodeCount++;
        }
        final stock = widget.availableQuantities[variant.variantId] ?? 0;
        if (hasBarcode && stock > 0) {
          inStockReadyCount++;
        }
      }
    }

    final barcodedPct = totalVariants > 0
        ? ((barcodedCount / totalVariants) * 100).toStringAsFixed(0)
        : '0';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Executive Header with KPI Pills
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF132B45),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.qr_code_2_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              l10n?.barcodeDashboard ?? 'Barcode',
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                fontSize: 20,
                              ),
                            ),
                            if (widget.businessName.isNotEmpty) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEFF6FF),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: const Color(0xFFBFDBFE),
                                  ),
                                ),
                                child: Text(
                                  widget.businessName,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF2563EB),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        Text(
                          l10n?.barcodeSubtitle ?? 'Select eligible variants, preview labels, and print or download.',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.textTheme.bodySmall?.color?.withValues(
                              alpha: 0.7,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Horizontal Executive Metric Strip
              LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 700;
                  final metrics = <Widget>[
                    _BarcodeKpiPill(
                      icon: Icons.inventory_2_outlined,
                      color: const Color(0xFF132B45),
                      bgColor: const Color(0xFF132B45).withValues(alpha: 0.08),
                      value: '$totalVariants',
                      label: l10n?.totalVariants ?? 'Total Variants',
                      badge: 'Catalog',
                    ),
                    _BarcodeKpiPill(
                      icon: Icons.qr_code_2_rounded,
                      color: const Color(0xFF059669),
                      bgColor: const Color(0xFFDCFCE7),
                      value: '$barcodedCount',
                      label: l10n?.barcodedItems ?? 'Barcoded',
                      badge: '$barcodedPct%',
                    ),
                    _BarcodeKpiPill(
                      icon: Icons.warning_amber_rounded,
                      color: missingBarcodeCount > 0
                          ? const Color(0xFFD97706)
                          : const Color(0xFF64748B),
                      bgColor: missingBarcodeCount > 0
                          ? const Color(0xFFFEF3C7)
                          : const Color(0xFFF1F5F9),
                      value: '$missingBarcodeCount',
                      label: l10n?.missingBarcode ?? 'Missing Barcode',
                      badge: missingBarcodeCount > 0 ? 'Action' : 'All set',
                    ),
                    _BarcodeKpiPill(
                      icon: Icons.print_outlined,
                      color: const Color(0xFF2563EB),
                      bgColor: const Color(0xFFEFF6FF),
                      value: '$inStockReadyCount',
                      label: l10n?.printReady ?? 'Print Ready',
                      badge: 'In Stock',
                    ),
                  ];
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: compact
                        ? Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final metric in metrics)
                                SizedBox(
                                  width: (constraints.maxWidth - 36) / 2,
                                  child: metric,
                                ),
                            ],
                          )
                        : Row(
                            children: [
                              for (var i = 0; i < metrics.length; i++) ...[
                                if (i > 0)
                                  Container(
                                    width: 1,
                                    height: 28,
                                    color: const Color(0xFFE2E8F0),
                                  ),
                                Expanded(child: metrics[i]),
                              ],
                            ],
                          ),
                  );
                },
              ),
            ],
          ),
        ),

        // Navigation Segmented Control
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<_BarcodeSection>(
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: const Color(0xFF132B45),
                selectedForegroundColor: Colors.white,
                foregroundColor: const Color(0xFF475569),
                backgroundColor: const Color(0xFFF8FAFC),
                side: const BorderSide(color: Color(0xFFCBD5E1)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
              ),
              segments: [
                ButtonSegment(
                  value: _BarcodeSection.printing,
                  icon: const Icon(Icons.qr_code_scanner, size: 18),
                  label: Text(l10n?.barcodePrinting ?? 'Barcode Printing'),
                ),
                ButtonSegment(
                  value: _BarcodeSection.lookup,
                  icon: const Icon(Icons.manage_search, size: 18),
                  label: Text(l10n?.barcodeLookup ?? 'Barcode Lookup'),
                ),
              ],
              selected: {_section},
              onSelectionChanged: (selection) =>
                  setState(() => _section = selection.single),
            ),
          ),
        ),
        const SizedBox(height: 4),

        // Active Section Content
        Expanded(
          child: switch (_section) {
            _BarcodeSection.printing => BarcodePrintingPage(
              key: ValueKey(
                'single-${_selectedProductId ?? widget.initialProductId}-${_selectedVariantId ?? widget.initialVariantId}',
              ),
              products: widget.products,
              businessName: widget.businessName,
              loadReceivedVariantIds: widget.loadReceivedVariantIds,
              loadReceivedVariantPricing: widget.loadReceivedVariantPricing,
              loadVariantBatches: widget.loadVariantBatches,
              availableQuantities: widget.availableQuantities,
              initialProductId: _selectedProductId ?? widget.initialProductId,
              initialVariantId: _selectedVariantId ?? widget.initialVariantId,
              showBackButton: false,
            ),
            _BarcodeSection.lookup => _BarcodeLookupPage(
              products: widget.products,
              availableQuantities: widget.availableQuantities,
              onSelectForPrint: _selectForPrint,
            ),
          },
        ),
      ],
    );
  }
}

class _BarcodeKpiPill extends StatelessWidget {
  const _BarcodeKpiPill({
    required this.icon,
    required this.color,
    required this.bgColor,
    required this.value,
    required this.label,
    required this.badge,
  });

  final IconData icon;
  final Color color;
  final Color bgColor;
  final String value;
  final String label;
  final String badge;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: bgColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        badge,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF64748B),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BarcodeLookupPage extends StatefulWidget {
  const _BarcodeLookupPage({
    required this.products,
    this.availableQuantities = const {},
    this.onSelectForPrint,
  });

  final List<ProductModel> products;
  final Map<String, int> availableQuantities;
  final void Function(String productId, String variantId)? onSelectForPrint;

  @override
  State<_BarcodeLookupPage> createState() => _BarcodeLookupPageState();
}

class _BarcodeLookupPageState extends State<_BarcodeLookupPage> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final trimmedQuery = _query.trim();
    final matches = trimmedQuery.isEmpty
        ? const <(ProductModel, ProductVariantModel)>[]
        : [
            for (final product in widget.products)
              for (final variant in product.variants)
                if (variant.barcode != null &&
                    variant.barcode!.toLowerCase().contains(
                      trimmedQuery.toLowerCase(),
                    ))
                  (product, variant),
          ];

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      children: [
        // Scanner Hero Search Card
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF132B45),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.qr_code_scanner_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n?.findProductByBarcode ??
                                'Find a product by its saved barcode',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: const Color(0xFF0F172A),
                            ),
                          ),
                          const Text(
                            'Aim hardware laser scanner or type SKU / Barcode',
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _search,
                  autofocus: true,
                  onChanged: (value) => setState(() => _query = value),
                  decoration: InputDecoration(
                    labelText: 'Barcode number',
                    hintText:
                        l10n?.typeOrScanBarcode ?? 'Type or scan a barcode',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    suffixIcon: _query.isNotEmpty
                        ? IconButton(
                            tooltip: 'Clear search',
                            onPressed: () {
                              _search.clear();
                              setState(() => _query = '');
                            },
                            icon: const Icon(Icons.clear, size: 18),
                          )
                        : null,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (trimmedQuery.isNotEmpty && matches.isEmpty)
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.search_off_rounded,
                      size: 36,
                      color: Color(0xFF94A3B8),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      l10n?.barcodeNotFound ?? 'Barcode not found',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'No catalog variant matches this code. Check the number or assign this barcode in Products.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        for (final (product, variant) in matches)
          Card(
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF132B45),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.qr_code_2_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    product.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: product.isActive
                                        ? const Color(0xFFDCFCE7)
                                        : const Color(0xFFFEE2E2),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: product.isActive
                                          ? const Color(0xFF86EFAC)
                                          : const Color(0xFFFECACA),
                                    ),
                                  ),
                                  child: Text(
                                    product.status,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: product.isActive
                                          ? const Color(0xFF15803D)
                                          : const Color(0xFFB91C1C),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${variant.name} · Barcode ${variant.barcode} · ${product.status}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1, color: Color(0xFFF1F5F9)),
                  const SizedBox(height: 12),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    alignment: WrapAlignment.spaceBetween,
                    spacing: 12,
                    runSpacing: 10,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Rendered Barcode Preview
                          if (variant.barcode != null &&
                              variant.barcode!.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: const Color(0xFFE2E8F0),
                                ),
                              ),
                              child: SizedBox(
                                width: 110,
                                height: 32,
                                child: barcode_ui.BarcodeWidget(
                                  barcode: barcode_ui.Barcode.code128(),
                                  data: variant.barcode!,
                                  drawText: false,
                                ),
                              ),
                            ),
                          const SizedBox(width: 10),
                          // Stock Pill
                          Builder(
                            builder: (context) {
                              final stock =
                                  widget.availableQuantities[variant
                                      .variantId] ??
                                  0;
                              final inStock = stock > 0;
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: inStock
                                      ? const Color(0xFFF0FDF4)
                                      : const Color(0xFFFEF2F2),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: inStock
                                        ? const Color(0xFFBBF7D0)
                                        : const Color(0xFFFECACA),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      inStock
                                          ? Icons.check_circle_rounded
                                          : Icons.warning_amber_rounded,
                                      size: 13,
                                      color: inStock
                                          ? const Color(0xFF16A34A)
                                          : const Color(0xFFDC2626),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      inStock
                                          ? '${formatStockQuantity(stock)} In Stock'
                                          : 'Out of Stock',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: inStock
                                            ? const Color(0xFF15803D)
                                            : const Color(0xFFB91C1C),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Pricing Block
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                'MRP INR ${(variant.mrp / 100).toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                              Text(
                                'Selling INR ${(variant.sellingPrice / 100).toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                            ],
                          ),
                          if (widget.onSelectForPrint != null) ...[
                            const SizedBox(width: 10),
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF132B45),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              icon: const Icon(Icons.print_rounded, size: 15),
                              label: const Text(
                                'Print Label',
                                style: TextStyle(fontSize: 12),
                              ),
                              onPressed: () {
                                widget.onSelectForPrint?.call(
                                  product.productId,
                                  variant.variantId,
                                );
                              },
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
