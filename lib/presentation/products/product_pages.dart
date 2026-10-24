import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import '../../data/models/product_attribute.dart';
import '../../data/models/central_product_master.dart';
import '../../data/models/resolved_product_template.dart';

import 'package:flutter/material.dart';

import 'package:flutter/services.dart';
import '../../data/models/product_model.dart';
import '../../data/models/quantity_discount_slab.dart';
import '../../data/models/product_master_value.dart';
import '../../data/models/product_variant_model.dart';
import '../../core/utils/stock_quantity_formatter.dart';
import '../app_controller.dart';
import 'product_thumbnail.dart';
import '../widgets/nubi_form.dart';
import '../widgets/sync_task_dialog.dart';
import 'barcode_printing_page.dart';
import '../../l10n/app_localizations.dart';

class ProductManagementPage extends StatefulWidget {
  const ProductManagementPage({
    super.key,
    required this.controller,
    this.onOpenBarcodeModule,
  });
  final AppController controller;
  final void Function(String productId, String variantId)? onOpenBarcodeModule;
  @override
  State<ProductManagementPage> createState() => _ProductManagementPageState();
}

enum _ProductViewMode { table, cards }

class _ProductManagementPageState extends State<ProductManagementPage> {
  final _search = TextEditingController();
  final _tableHorizontalController = ScrollController();
  final _tableVerticalController = ScrollController();
  ProductMasterValue? _brandFilter, _categoryFilter, _subcategoryFilter;
  String _statusFilter = 'ALL';
  bool _multiVariantOnly = false;
  bool _stockAlertsOnly = false;
  _ProductViewMode _viewMode = _ProductViewMode.table;
  bool _showBarcodePrinting = false;
  String? _barcodeProductId, _barcodeVariantId;
  final _selected = <String>{};

  void _openBarcodePrinting({String? productId, String? variantId}) {
    final openModule = widget.onOpenBarcodeModule;
    if (openModule != null) {
      openModule(productId ?? '', variantId ?? '');
      return;
    }
    setState(() {
      _showBarcodePrinting = true;
      _barcodeProductId = productId;
      _barcodeVariantId = variantId;
    });
  }

  Future<void> _status(List<String> ids, String status) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          status == 'DELETED' ? 'Delete products?' : 'Change product status?',
        ),
        content: Text(
          status == 'DELETED'
              ? 'Products will be archived. Historical transactions and variants will be preserved.'
              : 'Apply this change to ${ids.length} product(s)?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed == true &&
        await widget.controller.setProductStatus(ids, status) &&
        mounted) {
      setState(() => _selected.clear());
    }
  }

  Future<void> _bulkRemoveFromOutlet(
    BuildContext context,
    AppController controller,
  ) async {
    final outletName = controller.currentOutlet?.outletName ?? 'this outlet';
    final count = _selected.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove $count product(s) from $outletName?'),
        content: Text(
          'These $count product(s) will be removed from $outletName. '
          'Product and variant masters will remain preserved in the catalogue and any other outlets.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('confirm-bulk-remove-from-outlet'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove from this outlet'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      final selectedList = _selected.toList();
      final removedCount = await controller.removeProductsFromCurrentOutlet(
        selectedList,
      );
      if (mounted) {
        setState(() => _selected.clear());
      }
      if (context.mounted && removedCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$removedCount product(s) removed from $outletName.'),
          ),
        );
      }
    }
  }

  Future<void> _openAddExistingProductsDialog(
    BuildContext context,
    AppController controller,
  ) async {
    final outletName = controller.currentOutlet?.outletName ?? 'this outlet';
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        var loading = true;
        List<ProductModel> available = [];
        final selected = <String>{};
        var filterText = '';

        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            if (loading) {
              controller.loadProductsAvailableToAddToOutlet().then((list) {
                if (ctx.mounted) {
                  setDialogState(() {
                    loading = false;
                    available = list;
                  });
                }
              });
            }

            final filtered = available.where((p) {
              if (filterText.isEmpty) return true;
              final q = filterText.toLowerCase();
              return p.name.toLowerCase().contains(q) ||
                  (p.brand ?? '').toLowerCase().contains(q) ||
                  (p.category ?? '').toLowerCase().contains(q) ||
                  p.variants.any(
                    (v) =>
                        v.name.toLowerCase().contains(q) ||
                        (v.sku ?? '').toLowerCase().contains(q) ||
                        (v.barcode ?? '').toLowerCase().contains(q),
                  );
            }).toList();

            return AlertDialog(
              title: Text('Add Existing Products to $outletName'),
              content: SizedBox(
                width: 600,
                height: 450,
                child: loading
                    ? const Center(child: CircularProgressIndicator())
                    : available.isEmpty
                    ? const Center(
                        child: Text(
                          'All active business products are already placed at this outlet.',
                          textAlign: TextAlign.center,
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.search),
                              hintText: 'Search available products...',
                              isDense: true,
                            ),
                            onChanged: (v) =>
                                setDialogState(() => filterText = v.trim()),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Checkbox(
                                value:
                                    filtered.isNotEmpty &&
                                    filtered.every(
                                      (p) => selected.contains(p.productId),
                                    ),
                                onChanged: (v) => setDialogState(() {
                                  if (v == true) {
                                    for (final p in filtered) {
                                      selected.add(p.productId);
                                    }
                                  } else {
                                    for (final p in filtered) {
                                      selected.remove(p.productId);
                                    }
                                  }
                                }),
                              ),
                              Text(
                                selected.isEmpty
                                    ? 'Select all (${filtered.length})'
                                    : '${selected.length} of ${filtered.length} selected',
                              ),
                            ],
                          ),
                          const Divider(height: 1),
                          Expanded(
                            child: ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (_, _) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, i) {
                                final prod = filtered[i];
                                final isChecked = selected.contains(
                                  prod.productId,
                                );
                                return CheckboxListTile(
                                  value: isChecked,
                                  title: Text(prod.name),
                                  subtitle: Text(
                                    '${prod.brand ?? ''} · ${prod.category ?? ''} · ${prod.variants.length} variant(s)',
                                  ),
                                  onChanged: (v) => setDialogState(() {
                                    if (v == true) {
                                      selected.add(prod.productId);
                                    } else {
                                      selected.remove(prod.productId);
                                    }
                                  }),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  key: const ValueKey('add-selected-to-outlet-btn'),
                  onPressed: selected.isEmpty
                      ? null
                      : () async {
                          Navigator.pop(dialogCtx);
                          final count = selected.length;
                          final ok = await controller
                              .addExistingProductsToCurrentOutlet(
                                selected.toList(),
                              );
                          if (ok && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Added $count product(s) to $outletName.',
                                ),
                              ),
                            );
                          }
                        },
                  child: Text('Add to $outletName'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.controller.loadProducts();
      widget.controller.loadProductMasters();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    _tableHorizontalController.dispose();
    _tableVerticalController.dispose();
    super.dispose();
  }

  PopupMenuItem<Locale> _buildLanguagePopupItem(
    Locale locale,
    String title,
    bool isSelected,
  ) {
    return PopupMenuItem(
      value: locale,
      child: Row(
        children: [
          Icon(
            isSelected ? Icons.check_circle_rounded : Icons.circle_outlined,
            size: 16,
            color: isSelected ? const Color(0xFF16A34A) : Colors.grey,
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? const Color(0xFF132B45) : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      final l10n = AppLocalizations.of(context);

      if (!c.canManageProducts()) {
        return Center(
          child: Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.lock_person_outlined,
                  size: 56,
                  color: Color(0xFFDC2626),
                ),
                SizedBox(height: 16),
                Text(
                  'You do not have Product access.',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      }

      final businessProducts = c.products;
      if (_showBarcodePrinting) {
        final businessName =
            c.businesses
                .where(
                  (business) => business.businessId == c.appContext?.businessId,
                )
                .firstOrNull
                ?.businessName ??
            '';
        return BarcodePrintingPage(
          key: ValueKey('barcode-print-$_barcodeProductId-$_barcodeVariantId'),
          products: businessProducts,
          businessName: businessName,
          loadReceivedVariantIds: c.loadBarcodeReceivedVariantIds,
          loadReceivedVariantPricing: c.loadBarcodeReceivedVariantPricing,
          loadVariantBatches: c.loadVariantBatches,
          availableQuantities: c.productStock,
          showBulkTools: false,
          initialProductId: _barcodeProductId,
          initialVariantId: _barcodeVariantId,
          onClose: () => setState(() {
            _showBarcodePrinting = false;
            _barcodeProductId = null;
            _barcodeVariantId = null;
          }),
        );
      }

      final query = _search.text.trim().toLowerCase();
      final products = businessProducts.where((p) {
        final matchesQuery =
            query.isEmpty ||
            [
              p.name,
              p.brand ?? '',
              p.category ?? '',
              ...p.variants.expand(
                (v) => [v.name, v.sku ?? '', v.barcode ?? ''],
              ),
            ].any((v) => v.toLowerCase().contains(query));

        final matchesMultiVariant = !_multiVariantOnly || p.variants.length > 1;

        final matchesStockAlerts =
            !_stockAlertsOnly ||
            p.variants.any((v) => (c.productStock[v.variantId] ?? 0) <= 0);

        return matchesQuery &&
            matchesMultiVariant &&
            matchesStockAlerts &&
            (_brandFilter == null ||
                p.brandId == _brandFilter!.id ||
                p.brand == _brandFilter!.name) &&
            (_categoryFilter == null ||
                p.categoryId == _categoryFilter!.id ||
                p.category == _categoryFilter!.name) &&
            (_subcategoryFilter == null ||
                p.subcategoryId == _subcategoryFilter!.id ||
                p.subcategory == _subcategoryFilter!.name) &&
            (_statusFilter == 'ALL' || p.status.toUpperCase() == _statusFilter);
      }).toList();

      final variants = businessProducts.fold<int>(
        0,
        (sum, p) => sum + p.variants.length,
      );

      final totalCount = businessProducts.length;
      final activeCount = businessProducts.where((p) => p.isActive).length;
      final inactiveCount = businessProducts.where((p) => !p.isActive).length;
      Map<String, int> stockMap;
      try {
        stockMap = c.productStock;
      } catch (_) {
        stockMap = const {};
      }
      final stockAlertsCount = businessProducts
          .where(
            (p) =>
                p.variants.any((v) => (stockMap[v.variantId] ?? 0) <= 0),
          )
          .length;
      final activeRatio = totalCount > 0
          ? ((activeCount / totalCount) * 100).round()
          : 100;

      final currentCode = c.currentLocale.languageCode;
      final langLabel = switch (currentCode) {
        'hi' => 'हिंदी',
        'bn' => 'বাংলা',
        _ => 'English',
      };

      return LayoutBuilder(
        builder: (context, constraints) {
          final isMobile = constraints.maxWidth < 720;
          final isTablet =
              constraints.maxWidth >= 720 && constraints.maxWidth < 1100;

          if (isMobile) {
            Widget mobileProductTile(ProductModel product) => _ProductTile(
              key: ValueKey('mobile-product-${product.productId}'),
              compact: true,
              product: product,
              controller: c,
              selected: _selected.contains(product.productId),
              onSelect: (selected) => setState(
                () => selected
                    ? _selected.add(product.productId)
                    : _selected.remove(product.productId),
              ),
              onStatus: (status) => _status([product.productId], status),
              onPrintBarcode: (variant) => _openBarcodePrinting(
                productId: product.productId,
                variantId: variant.variantId,
              ),
            );

            return CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      _buildHeaderBar(
                        context,
                        l10n: l10n,
                        controller: c,
                        langLabel: langLabel,
                        currentCode: currentCode,
                        isMobile: true,
                      ),
                      if (c.placementBackfillNotice != null) ...[
                        const SizedBox(height: 8),
                        Card(
                          color: Theme.of(context)
                              .colorScheme
                              .secondaryContainer,
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Text(c.placementBackfillNotice!),
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      _buildKpiSection(
                        context,
                        l10n: l10n,
                        isMobile: true,
                        isTablet: false,
                        totalCount: totalCount,
                        activeCount: activeCount,
                        inactiveCount: inactiveCount,
                        variantsCount: variants,
                        stockAlertsCount: stockAlertsCount,
                        activeRatio: activeRatio,
                      ),
                      if (c.products.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _buildFilterConsole(
                          context,
                          l10n: l10n,
                          controller: c,
                          isMobile: true,
                          filteredCount: products.length,
                          totalCount: totalCount,
                        ),
                      ],
                      if (c.productsError != null) ...[
                        const SizedBox(height: 8),
                        MaterialBanner(
                          content: Text(c.productsError!),
                          actions: [
                            TextButton(
                              onPressed: c.loadProducts,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 8),
                      _buildBulkActionStrip(context, c, products, l10n),
                      const SizedBox(height: 4),
                    ]),
                  ),
                ),
                if (c.productsLoading && businessProducts.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Container(
                      alignment: Alignment.center,
                      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('Loading catalogue products...'),
                        ],
                      ),
                    ),
                  )
                else if (products.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: _buildEmptyState(context, c, l10n),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final product = products[index];
                        if (_viewMode == _ProductViewMode.cards) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _ProductCard(
                              key: ValueKey('mobile-card-${product.productId}'),
                              product: product,
                              controller: c,
                              selected: _selected.contains(product.productId),
                              onSelect: (selected) => setState(
                                () => selected
                                    ? _selected.add(product.productId)
                                    : _selected.remove(product.productId),
                              ),
                              onStatus: (status) =>
                                  _status([product.productId], status),
                              onPrintBarcode: (variant) => _openBarcodePrinting(
                                productId: product.productId,
                                variantId: variant.variantId,
                              ),
                              onEdit: () => _editProduct(context, product),
                            ),
                          );
                        }
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          clipBehavior: Clip.antiAlias,
                          child: mobileProductTile(product),
                        );
                      }, childCount: products.length),
                    ),
                  ),
              ],
            );
          }

          return Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 12 : 18,
              vertical: isMobile ? 6 : 8,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. HEADER BAR: Title, Scope Badge, Language Selector & Action Buttons
                _buildHeaderBar(
                  context,
                  l10n: l10n,
                  controller: c,
                  langLabel: langLabel,
                  currentCode: currentCode,
                  isMobile: isMobile,
                ),

                if (c.placementBackfillNotice != null) ...[
                  const SizedBox(height: 6),
                  Card(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(c.placementBackfillNotice!),
                    ),
                  ),
                ],

                SizedBox(height: isMobile ? 4 : 6),

                // 2. EXECUTIVE KPI CARDS SECTION
                _buildKpiSection(
                  context,
                  l10n: l10n,
                  isMobile: isMobile,
                  isTablet: isTablet,
                  totalCount: totalCount,
                  activeCount: activeCount,
                  inactiveCount: inactiveCount,
                  variantsCount: variants,
                  stockAlertsCount: stockAlertsCount,
                  activeRatio: activeRatio,
                ),

                SizedBox(height: isMobile ? 4 : 6),

                // 3. SEARCH, FILTER & VIEW CONSOLE
                if (c.products.isNotEmpty) ...[
                  _buildFilterConsole(
                    context,
                    l10n: l10n,
                    controller: c,
                    isMobile: isMobile,
                    filteredCount: products.length,
                    totalCount: totalCount,
                  ),
                  SizedBox(height: isMobile ? 4 : 6),
                ],

                if (c.productsError != null) ...[
                  const SizedBox(height: 8),
                  MaterialBanner(
                    content: Text(c.productsError!),
                    actions: [
                      TextButton(
                        onPressed: c.loadProducts,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ],

                SizedBox(height: isMobile ? 3 : 5),

                // 4. BULK SELECTION ACTION STRIP
                _buildBulkActionStrip(context, c, products, l10n),

                SizedBox(height: isMobile ? 3 : 5),

                // 5. MAIN PRODUCTS DATA CONTENT (Table or Cards View)
                Expanded(
                  child: c.productsLoading && businessProducts.isEmpty
                      ? Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: const Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 16),
                              Text('Loading catalogue products...'),
                            ],
                          ),
                        )
                      : products.isEmpty
                      ? _buildEmptyState(context, c, l10n)
                      : _viewMode == _ProductViewMode.table
                      ? _buildTableView(context, constraints, c, products)
                      : _buildCardsView(context, c, products, constraints),
                ),
              ],
            ),
          );
        },
      );
    },
  );

  Widget _buildHeaderBar(
    BuildContext context, {
    required AppLocalizations? l10n,
    required AppController controller,
    required String langLabel,
    required String currentCode,
    required bool isMobile,
  }) {
    final title = Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 10,
      runSpacing: 4,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF132B45),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.widgets_rounded,
                color: Color(0xFFC18B35),
                size: 18,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Products',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
        if (controller.currentOutlet != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF132B45).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.storefront_outlined,
                  size: 13,
                  color: Color(0xFF132B45),
                ),
                const SizedBox(width: 4),
                Text(
                  controller.currentOutlet!.outletName,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF132B45),
                  ),
                ),
              ],
            ),
          ),
      ],
    );

    final actions = <Widget>[
      // Language Selector Dropdown
      PopupMenuButton<Locale>(
        tooltip: l10n?.languageSelector ?? 'Language / भाषा / ভাষা',
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onSelected: (locale) => widget.controller.setLocale(locale),
        itemBuilder: (_) => [
          _buildLanguagePopupItem(
            const Locale('en'),
            'English',
            currentCode == 'en',
          ),
          _buildLanguagePopupItem(
            const Locale('hi'),
            'हिंदी (Hindi)',
            currentCode == 'hi',
          ),
          _buildLanguagePopupItem(
            const Locale('bn'),
            'বাংলা (Bengali)',
            currentCode == 'bn',
          ),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFCBD5E1)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.translate_rounded,
                size: 16,
                color: Color(0xFF132B45),
              ),
              const SizedBox(width: 6),
              Text(
                langLabel,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF132B45),
                ),
              ),
              const Icon(
                Icons.arrow_drop_down,
                size: 16,
                color: Color(0xFF64748B),
              ),
            ],
          ),
        ),
      ),

      // Refresh button
      IconButton.outlined(
        tooltip: l10n?.refreshTooltip ?? 'Refresh',
        onPressed: controller.productsLoading ? null : controller.loadProducts,
        icon: controller.productsLoading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.refresh, size: 18),
        style: IconButton.styleFrom(
          backgroundColor: Colors.white,
          side: const BorderSide(color: Color(0xFFCBD5E1)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),

      // Barcode Printing Button
      OutlinedButton.icon(
        onPressed: () => _openBarcodePrinting(),
        icon: const Icon(Icons.qr_code_2, size: 18),
        label: Text(l10n?.barcodePrinting ?? 'Barcode Printing'),
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF0F172A),
          side: const BorderSide(color: Color(0xFFCBD5E1)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
      ),

      // Add Existing to Outlet Button
      if (controller.canAddExistingProductsToOutlet)
        OutlinedButton.icon(
          key: const ValueKey('add-existing-to-outlet-btn'),
          onPressed: () => _openAddExistingProductsDialog(context, controller),
          icon: const Icon(Icons.playlist_add, size: 18),
          label: Text(l10n?.addExistingToOutlet ?? 'Add Existing to Outlet'),
          style: OutlinedButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: const Color(0xFF0F172A),
            side: const BorderSide(color: Color(0xFFCBD5E1)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
        ),

      // Add Product Button
      if (controller.canCreateProducts())
        FilledButton.icon(
          key: const ValueKey('add-product-btn'),
          onPressed: controller.productSaving
              ? null
              : () => _addProduct(context),
          icon: const Icon(Icons.add, size: 18),
          label: Text(
            l10n?.addProduct ?? 'Add Product',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF132B45),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            elevation: 1,
          ),
        ),
    ];

    return LayoutBuilder(
      builder: (context, headerConstraints) {
        final compact = isMobile || headerConstraints.maxWidth < 750;
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              title,
              const SizedBox(height: 6),
              Wrap(
                alignment: WrapAlignment.start,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 6,
                runSpacing: 6,
                children: actions,
              ),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            title,
            const SizedBox(width: 12),
            Expanded(
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: actions,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildKpiSection(
    BuildContext context, {
    required AppLocalizations? l10n,
    required bool isMobile,
    required bool isTablet,
    required int totalCount,
    required int activeCount,
    required int inactiveCount,
    required int variantsCount,
    required int stockAlertsCount,
    required int activeRatio,
  }) {
    final cards = [
      _ProductKpiCard(
        title: l10n?.totalProducts ?? 'Products',
        value: '$totalCount',
        subtitle: '$variantsCount variants in catalogue',
        icon: Icons.inventory_2_rounded,
        accentColor: const Color(0xFF2563EB),
        isSelected:
            _statusFilter == 'ALL' && !_stockAlertsOnly && !_multiVariantOnly,
        onTap: () => setState(() {
          _statusFilter = 'ALL';
          _stockAlertsOnly = false;
          _multiVariantOnly = false;
        }),
      ),
      _ProductKpiCard(
        title: l10n?.activeProducts ?? 'Active',
        value: '$activeCount',
        subtitle: '$activeRatio% active catalogue ratio',
        icon: Icons.check_circle_rounded,
        accentColor: const Color(0xFF16A34A),
        isSelected: _statusFilter == 'ACTIVE' && !_stockAlertsOnly,
        onTap: () => setState(() {
          _statusFilter = 'ACTIVE';
          _stockAlertsOnly = false;
        }),
      ),
      _ProductKpiCard(
        title: l10n?.inactiveProducts ?? 'Inactive',
        value: '$inactiveCount',
        subtitle: 'Paused or archived items',
        icon: Icons.pause_circle_outline_rounded,
        accentColor: const Color(0xFF64748B),
        isSelected: _statusFilter == 'INACTIVE' && !_stockAlertsOnly,
        onTap: () => setState(() {
          _statusFilter = 'INACTIVE';
          _stockAlertsOnly = false;
        }),
      ),
      _ProductKpiCard(
        title: l10n?.totalVariants ?? 'Variants',
        value: '$variantsCount',
        subtitle: 'Across all specification lines',
        icon: Icons.dashboard_customize_rounded,
        accentColor: const Color(0xFF8B5CF6),
        isSelected: _multiVariantOnly,
        onTap: () => setState(() => _multiVariantOnly = !_multiVariantOnly),
      ),
      _ProductKpiCard(
        title: l10n?.stockAlerts ?? 'Stock Alerts',
        value: '$stockAlertsCount',
        subtitle: stockAlertsCount > 0
            ? 'Out of stock items require action'
            : 'All items in stock',
        icon: Icons.warning_amber_rounded,
        accentColor: const Color(0xFFD97706),
        isAlert: stockAlertsCount > 0,
        isSelected: _stockAlertsOnly,
        onTap: () => setState(() => _stockAlertsOnly = !_stockAlertsOnly),
      ),
    ];

    if (isMobile) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (int i = 0; i < cards.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              SizedBox(width: 210, child: cards[i]),
            ],
          ],
        ),
      );
    }

    return Row(
      children: [
        for (int i = 0; i < cards.length; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          Expanded(child: cards[i]),
        ],
      ],
    );
  }

  Widget _buildFilterConsole(
    BuildContext context, {
    required AppLocalizations? l10n,
    required AppController controller,
    required bool isMobile,
    required int filteredCount,
    required int totalCount,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 10 : 12,
        vertical: isMobile ? 6 : 6,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          // Search Input Box
          SizedBox(
            width: isMobile ? double.infinity : 230,
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                prefixIcon: const Icon(
                  Icons.search,
                  size: 18,
                  color: Color(0xFF64748B),
                ),
                suffixIcon: _search.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: () {
                          _search.clear();
                          setState(() {});
                        },
                      )
                    : null,
                hintText:
                    l10n?.searchProductPlaceholder ??
                    'Search product, brand, SKU...',
                hintStyle: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF94A3B8),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                isDense: true,
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(
                    color: Color(0xFF132B45),
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),

          // Brand dropdown
          SizedBox(
            width: isMobile ? 130 : 145,
            child: DropdownButtonFormField<String>(
              initialValue: _brandFilter?.id,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l10n?.brand ?? 'Brand',
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                isDense: true,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                ),
              ),
              items: [
                DropdownMenuItem(
                  value: '',
                  child: Text(l10n?.allBrands ?? 'All Brands'),
                ),
                for (final value
                    in controller.productMasterValues['BRAND'] ??
                        const <ProductMasterValue>[])
                  DropdownMenuItem(
                    value: value.id,
                    child: Text(
                      value.name,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (id) => setState(
                () => _brandFilter =
                    (controller.productMasterValues['BRAND'] ??
                            const <ProductMasterValue>[])
                        .where((v) => v.id == id)
                        .firstOrNull,
              ),
            ),
          ),

          // Category dropdown
          SizedBox(
            width: isMobile ? 130 : 155,
            child: DropdownButtonFormField<String>(
              initialValue: _categoryFilter?.id,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l10n?.category ?? 'Category',
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                isDense: true,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                ),
              ),
              items: [
                DropdownMenuItem(
                  value: '',
                  child: Text(l10n?.allCategories ?? 'All Categories'),
                ),
                for (final value
                    in controller.productMasterValues['CATEGORY'] ??
                        const <ProductMasterValue>[])
                  DropdownMenuItem(
                    value: value.id,
                    child: Text(
                      value.name,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (id) async {
                final value =
                    (controller.productMasterValues['CATEGORY'] ??
                            const <ProductMasterValue>[])
                        .where((v) => v.id == id)
                        .firstOrNull;
                setState(() {
                  _categoryFilter = value;
                  _subcategoryFilter = null;
                });
                if (value != null) {
                  await controller.loadProductMasters(categoryId: value.id);
                }
                if (mounted) setState(() {});
              },
            ),
          ),

          // Subcategory dropdown (if category selected)
          if (_categoryFilter != null)
            SizedBox(
              width: isMobile ? 130 : 155,
              child: DropdownButtonFormField<String>(
                initialValue: _subcategoryFilter?.id,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Subcategory',
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  isDense: true,
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                  ),
                ),
                items: [
                  DropdownMenuItem(
                    value: '',
                    child: Text(
                      l10n?.allSubcategories ?? 'All Subcategories',
                    ),
                  ),
                  for (final value
                      in controller
                              .productMasterValues['SUBCATEGORY:${_categoryFilter!.id}'] ??
                          const <ProductMasterValue>[])
                    DropdownMenuItem(
                      value: value.id,
                      child: Text(
                        value.name,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (id) => setState(
                  () => _subcategoryFilter =
                      (controller.productMasterValues['SUBCATEGORY:${_categoryFilter!.id}'] ??
                              const <ProductMasterValue>[])
                          .where((v) => v.id == id)
                          .firstOrNull,
                ),
              ),
            ),

          // Status Dropdown
          SizedBox(
            width: isMobile ? 115 : 125,
            child: DropdownButtonFormField<String>(
              initialValue: _statusFilter,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Status',
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                isDense: true,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                ),
              ),
              items: [
                DropdownMenuItem(
                  value: 'ALL',
                  child: Text(l10n?.allStatuses ?? 'All Statuses'),
                ),
                DropdownMenuItem(
                  value: 'ACTIVE',
                  child: Text(l10n?.statusActive ?? 'Active'),
                ),
                DropdownMenuItem(
                  value: 'INACTIVE',
                  child: Text(l10n?.statusInactive ?? 'Inactive'),
                ),
              ],
              onChanged: (value) =>
                  setState(() => _statusFilter = value ?? 'ALL'),
            ),
          ),

          // Reset filters button
          if (_brandFilter != null ||
              _categoryFilter != null ||
              _statusFilter != 'ALL' ||
              _multiVariantOnly ||
              _stockAlertsOnly)
            TextButton.icon(
              onPressed: () => setState(() {
                _brandFilter = null;
                _categoryFilter = null;
                _subcategoryFilter = null;
                _statusFilter = 'ALL';
                _multiVariantOnly = false;
                _stockAlertsOnly = false;
              }),
              icon: const Icon(Icons.filter_alt_off_outlined, size: 15),
              label: const Text('Reset', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
            ),

          // View Mode Toggle + Counter Badge
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$filteredCount of $totalCount',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF475569),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Table / Cards View Switcher
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.all(2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildViewModeButton(
                      icon: Icons.table_chart_outlined,
                      isSelected: _viewMode == _ProductViewMode.table,
                      tooltip: l10n?.viewModeTable ?? 'Table View',
                      onTap: () => setState(
                        () => _viewMode = _ProductViewMode.table,
                      ),
                    ),
                    _buildViewModeButton(
                      icon: Icons.grid_view_rounded,
                      isSelected: _viewMode == _ProductViewMode.cards,
                      tooltip: l10n?.viewModeCards ?? 'Card View',
                      onTap: () => setState(
                        () => _viewMode = _ProductViewMode.cards,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildViewModeButton({
    required IconData icon,
    required bool isSelected,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        child: Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Icon(
            icon,
            size: 18,
            color: isSelected
                ? const Color(0xFF132B45)
                : const Color(0xFF64748B),
          ),
        ),
      ),
    );
  }

  Widget _buildBulkActionStrip(
    BuildContext context,
    AppController controller,
    List<ProductModel> products,
    AppLocalizations? l10n,
  ) {
    final allSelected =
        products.isNotEmpty &&
        products.every((p) => _selected.contains(p.productId));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: _selected.isNotEmpty
            ? const Color(0xFF132B45).withValues(alpha: 0.04)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: _selected.isNotEmpty
            ? Border.all(color: const Color(0xFF132B45).withValues(alpha: 0.2))
            : null,
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => setState(() {
              if (allSelected) {
                _selected.clear();
              } else {
                for (final p in products) {
                  _selected.add(p.productId);
                }
              }
            }),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Checkbox(
                  value: allSelected,
                  onChanged: (v) => setState(() {
                    for (final p in products) {
                      v == true
                          ? _selected.add(p.productId)
                          : _selected.remove(p.productId);
                    }
                  }),
                ),
                const Text(
                  'Select all',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ],
            ),
          ),

          if (_selected.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF132B45),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_selected.length} selected',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
            if (controller.currentOutlet != null) ...[
              if (controller.canUpdateProducts()) ...[
                FilledButton.tonal(
                  key: const ValueKey('bulk-remove-from-outlet'),
                  onPressed: () => _bulkRemoveFromOutlet(context, controller),
                  child: const Text('Remove from this outlet'),
                ),
                TextButton(
                  key: const ValueKey('bulk-activate-outlet'),
                  onPressed: () => _status(_selected.toList(), 'ACTIVE'),
                  child: const Text('Activate'),
                ),
              ],
            ] else ...[
              if (controller.canUpdateProducts()) ...[
                TextButton(
                  onPressed: () => _status(_selected.toList(), 'ACTIVE'),
                  child: const Text('Activate'),
                ),
                TextButton(
                  onPressed: () => _status(_selected.toList(), 'INACTIVE'),
                  child: const Text('Deactivate'),
                ),
              ],
              if (controller.canDeleteProducts())
                TextButton(
                  onPressed: () => _status(_selected.toList(), 'DELETED'),
                  child: const Text('Delete'),
                ),
            ],
            TextButton(
              onPressed: () => setState(() => _selected.clear()),
              child: const Text('Clear selection'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState(
    BuildContext context,
    AppController controller,
    AppLocalizations? l10n,
  ) {
    final isOutletEmpty = controller.products.isEmpty;
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        constraints: const BoxConstraints(maxWidth: 440),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF132B45).withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.widgets_outlined,
                size: 32,
                color: Color(0xFF132B45),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              isOutletEmpty
                  ? (l10n?.noProductsFound ??
                        'No Products are assigned to this outlet.')
                  : (l10n?.noProductsFound ?? 'No Products match your search.'),
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F172A),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              isOutletEmpty
                  ? (l10n?.noProductsOutletSubtitle ??
                        'No Products are assigned to this outlet. Add a new Product.')
                  : (l10n?.noProductsFoundSubtitle ??
                        'Try adjusting your search keywords or filter status.'),
              style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
              textAlign: TextAlign.center,
            ),
            if (!isOutletEmpty) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => setState(() {
                  _search.clear();
                  _brandFilter = null;
                  _categoryFilter = null;
                  _subcategoryFilter = null;
                  _statusFilter = 'ALL';
                  _multiVariantOnly = false;
                  _stockAlertsOnly = false;
                }),
                icon: const Icon(Icons.clear_all, size: 16),
                label: const Text('Clear Filters'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTableView(
    BuildContext context,
    BoxConstraints constraints,
    AppController controller,
    List<ProductModel> products,
  ) {
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: LayoutBuilder(
        builder: (context, cardConstraints) {
          final isTablet = cardConstraints.maxWidth < 850;
          if (cardConstraints.maxWidth < 700) {
            // Keep the phone list as the primary vertical scrollable.
            return Scrollbar(
              controller: _tableVerticalController,
              thumbVisibility: true,
              trackVisibility: true,
              child: ListView.separated(
                controller: _tableVerticalController,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                itemCount: products.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 1, color: Color(0xFFF1F5F9)),
                itemBuilder: (context, i) => _ProductTile(
                  key: ValueKey('product-tile-compact-${products[i].productId}'),
                  compact: true,
                  product: products[i],
                  controller: controller,
                  selected: _selected.contains(products[i].productId),
                  onSelect: (v) => setState(
                    () => v
                        ? _selected.add(products[i].productId)
                        : _selected.remove(products[i].productId),
                  ),
                  onStatus: (status) => _status([products[i].productId], status),
                  onPrintBarcode: (variant) => _openBarcodePrinting(
                    productId: products[i].productId,
                    variantId: variant.variantId,
                  ),
                ),
              ),
            );
          }
          final minWidth = isTablet
              ? ProductTableColumns.tabletMinimumWidth
              : ProductTableColumns.minimumWidth;
          final tableWidth = cardConstraints.maxWidth < minWidth
              ? minWidth
              : cardConstraints.maxWidth;

          return Scrollbar(
            controller: _tableVerticalController,
            thumbVisibility: true,
            trackVisibility: true,
            scrollbarOrientation: ScrollbarOrientation.right,
            notificationPredicate: (notification) =>
                notification.metrics.axis == Axis.vertical,
            child: Scrollbar(
              controller: _tableHorizontalController,
              thumbVisibility: true,
              trackVisibility: true,
              scrollbarOrientation: ScrollbarOrientation.bottom,
              notificationPredicate: (notification) =>
                  notification.metrics.axis == Axis.horizontal,
              child: SingleChildScrollView(
                controller: _tableHorizontalController,
                scrollDirection: Axis.horizontal,
                physics: const ClampingScrollPhysics(),
                child: SizedBox(
                  width: tableWidth,
                  height: cardConstraints.maxHeight,
                  child: Column(
                    children: [
                      if (cardConstraints.maxWidth >= 700)
                        ProductTableColumns.header(tablet: isTablet),
                      Expanded(
                        child: ListView.separated(
                          controller: _tableVerticalController,
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: EdgeInsets.zero,
                          itemCount: products.length,
                          separatorBuilder: (_, _) =>
                              const Divider(height: 1, color: Color(0xFFF1F5F9)),
                          itemBuilder: (context, i) => _ProductTile(
                            key: ValueKey('product-tile-${products[i].productId}'),
                            compact: cardConstraints.maxWidth < 700,
                            tablet: isTablet,
                            product: products[i],
                            controller: controller,
                            selected: _selected.contains(products[i].productId),
                            onSelect: (v) => setState(
                              () => v
                                  ? _selected.add(products[i].productId)
                                  : _selected.remove(products[i].productId),
                            ),
                            onStatus: (status) =>
                                _status([products[i].productId], status),
                            onPrintBarcode: (variant) => _openBarcodePrinting(
                              productId: products[i].productId,
                              variantId: variant.variantId,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCardsView(
    BuildContext context,
    AppController controller,
    List<ProductModel> products,
    BoxConstraints constraints,
  ) {
    final columns = constraints.maxWidth > 1200
        ? 3
        : constraints.maxWidth > 700
        ? 2
        : 1;

    return Scrollbar(
      controller: _tableVerticalController,
      thumbVisibility: true,
      trackVisibility: true,
      child: GridView.builder(
        controller: _tableVerticalController,
        physics: const AlwaysScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          mainAxisExtent: 220,
        ),
        itemCount: products.length,
        itemBuilder: (context, index) {
          final product = products[index];
          return _ProductCard(
            product: product,
            controller: controller,
            selected: _selected.contains(product.productId),
            onSelect: (v) => setState(
              () => v
                  ? _selected.add(product.productId)
                  : _selected.remove(product.productId),
            ),
            onStatus: (status) => _status([product.productId], status),
            onPrintBarcode: (variant) => _openBarcodePrinting(
              productId: product.productId,
              variantId: variant.variantId,
            ),
            onEdit: () => _editProduct(context, product),
          );
        },
      ),
    );
  }

  Future<void> _refreshProducts() async {
    await widget.controller.loadProducts();
    await widget.controller.loadProductMasters();
    if (mounted) setState(() {});
  }

  Future<void> _addProduct(BuildContext context) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            _StructuredProductFormPage(controller: widget.controller),
      ),
    );
    if (saved == true && mounted) {
      await _refreshProducts();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Product and Variant saved and synced.'),
            backgroundColor: Color(0xFF10263D),
          ),
        );
      }
    }
  }

  Future<void> _editProduct(BuildContext context, ProductModel product) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _StructuredProductFormPage(
          controller: widget.controller,
          product: product,
        ),
      ),
    );
    if (saved == true && mounted) {
      await _refreshProducts();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Product updated and synced.'),
            backgroundColor: Color(0xFF10263D),
          ),
        );
      }
    }
  }
}

class _ProductKpiCard extends StatelessWidget {
  const _ProductKpiCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
    this.isSelected = false,
    this.isAlert = false,
    this.onTap,
  });

  final String title, value, subtitle;
  final IconData icon;
  final Color accentColor;
  final bool isSelected, isAlert;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: isSelected
            ? BorderSide(color: accentColor, width: 2)
            : const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      color: isSelected
          ? accentColor.withValues(alpha: 0.05)
          : Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, size: 15, color: accentColor),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF64748B),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isAlert)
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Color(0xFFDC2626),
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: isSelected ? accentColor : const Color(0xFF0F172A),
                        letterSpacing: -0.3,
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    super.key,
    required this.product,
    required this.controller,
    required this.selected,
    required this.onSelect,
    required this.onStatus,
    required this.onPrintBarcode,
    required this.onEdit,
  });

  final ProductModel product;
  final AppController controller;
  final bool selected;
  final ValueChanged<bool> onSelect;
  final ValueChanged<String> onStatus;
  final ValueChanged<ProductVariantModel> onPrintBarcode;
  final VoidCallback onEdit;

  String get stockSummary {
    if (!controller.canViewStorage()) return '—';
    if (product.variants.map((v) => v.baseUnitId).toSet().length > 1) {
      return '—';
    }
    final total = product.variants.fold<num>(
      0,
      (sum, v) => sum + (controller.productStock[v.variantId] ?? 0),
    );
    return formatStockQuantity(total);
  }

  String get priceRange {
    if (product.variants.isEmpty) return '—';
    final prices = product.variants.map((v) => v.sellingPrice / 100).toList()
      ..sort();
    if (prices.first == prices.last) {
      return '₹${prices.first.toStringAsFixed(2)}';
    }
    return '₹${prices.first.toStringAsFixed(0)} - ₹${prices.last.toStringAsFixed(0)}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final brand = _masterName(
      controller,
      'BRAND',
      product.brandId,
      product.brand,
    );
    final category = _masterName(
      controller,
      'CATEGORY',
      product.categoryId,
      product.category,
    );

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected ? const Color(0xFF132B45) : const Color(0xFFE2E8F0),
          width: selected ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: Checkbox + Brand/Category Chips + Popup Menu
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 8, 2),
            child: Row(
              children: [
                Checkbox(
                  value: selected,
                  onChanged: (v) => onSelect(v ?? false),
                ),
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (brand.isNotEmpty && brand != 'Unavailable')
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF132B45)
                                .withValues(alpha: 0.07),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            brand,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF132B45),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      if (category.isNotEmpty && category != 'Unavailable')
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            category,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF475569),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  key: ValueKey('product-actions-${product.productId}'),
                  onSelected: (action) async {
                    if (action == 'edit') {
                      onEdit();
                    } else if (action == 'duplicate') {
                      final saved = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          builder: (_) => _StructuredProductFormPage(
                            controller: controller,
                            product: product,
                            duplicate: true,
                          ),
                        ),
                      );
                      if (saved == true) {
                        await controller.loadProducts();
                        await controller.loadProductMasters();
                      }
                    } else if (action == 'view') {
                      final attributes = await controller.loadProductTemplate(
                        product.subcategoryId ?? '',
                      );
                      if (!context.mounted) return;
                      showDialog<void>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text(product.name),
                          content: SizedBox(
                            width: 500,
                            child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ProductThumbnail(
                                    url: product.productImage,
                                    name: product.name,
                                  ),
                                  Text(product.description ?? ''),
                                  Text('HSN: ${product.hsnCode ?? '—'}'),
                                  for (final entry
                                      in product.attributeValues.entries)
                                    Text(
                                      '${attributes.where((a) => a.id == entry.key).firstOrNull?.name ?? 'Additional detail'}: ${_displayValue(controller, entry.value)}',
                                    ),
                                ],
                              ),
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('Close'),
                            ),
                          ],
                        ),
                      );
                    } else if (action == 'remove_from_outlet' ||
                        action == 'manage_outlet_assignment') {
                      final outletName =
                          controller.currentOutlet?.outletName ?? 'this outlet';
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Remove from this outlet?'),
                          content: Text(
                            '${product.name} will be removed from $outletName. '
                            'The product and variant masters will remain preserved in the catalogue and other outlets.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              key: const ValueKey('confirm-remove-from-outlet'),
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Remove from this outlet'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true && context.mounted) {
                        final removed = await controller
                            .removeProductFromCurrentOutlet(product.productId);
                        if (removed && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '${product.name} removed from $outletName.',
                              ),
                            ),
                          );
                        }
                      }
                    } else {
                      onStatus(action);
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'view',
                      child: Text(l10n?.viewProduct ?? 'View'),
                    ),
                    if (controller.canCreateProducts())
                      PopupMenuItem(
                        value: 'duplicate',
                        child: Text(l10n?.duplicateProduct ?? 'Duplicate'),
                      ),
                    if (controller.canUpdateProducts())
                      PopupMenuItem(
                        value: 'edit',
                        child: Text(
                          l10n?.editProduct ?? 'Edit Product / Manage Variants',
                        ),
                      ),
                    if (controller.canUpdateProducts() &&
                        controller.currentOutlet != null) ...[
                      const PopupMenuItem(
                        key: ValueKey('manage-outlet-assignment'),
                        value: 'manage_outlet_assignment',
                        child: Text('Manage outlet assignment'),
                      ),
                      if (product.isActive)
                        const PopupMenuItem(
                          key: ValueKey('remove-from-outlet'),
                          value: 'remove_from_outlet',
                          child: Text('Remove from this outlet'),
                        )
                      else
                        const PopupMenuItem(
                          key: ValueKey('activate-in-outlet'),
                          value: 'ACTIVE',
                          child: Text('Activate in this outlet'),
                        ),
                    ],
                    if (controller.currentOutlet == null) ...[
                      if (controller.canUpdateProducts())
                        PopupMenuItem(
                          value: product.isActive ? 'INACTIVE' : 'ACTIVE',
                          child: Text(
                            product.isActive
                                ? (l10n?.statusInactive ?? 'Deactivate')
                                : (l10n?.statusActive ?? 'Activate'),
                          ),
                        ),
                      if (controller.canDeleteProducts())
                        PopupMenuItem(
                          value: 'DELETED',
                          child: Text(l10n?.deleteProduct ?? 'Delete'),
                        ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // Main Info: Thumbnail + Name + Code
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ProductThumbnail(url: product.productImage, name: product.name),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (product.productCode?.isNotEmpty == true) ...[
                        const SizedBox(height: 2),
                        Text(
                          product.productCode!,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF64748B),
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: Color(0xFFF1F5F9)),

          // Key Metrics: Variants, Stock, Price Range
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n?.totalVariants ?? 'Variants',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${product.variants.length}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n?.currentStock ?? 'Stock',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      stockSummary,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF132B45),
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      l10n?.sellingPriceLabel ?? 'Price',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      priceRange,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF16A34A),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Footer: Status Badge + Sync Badge + Edit Button
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                _ProductBadge(
                  label: product.isActive ? 'Active' : 'Inactive',
                  backgroundColor: product.isActive
                      ? Colors.green.shade100
                      : Colors.red.shade100,
                  color: product.isActive
                      ? Colors.green.shade900
                      : Colors.red.shade900,
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: 'Synchronization: ${product.syncStatus}',
                  child: _ProductBadge(
                    label: switch (product.syncStatus) {
                      'SYNCED' => 'Synced',
                      'ERROR' => 'Error',
                      'SYNCING' => 'Syncing',
                      _ => 'Pending',
                    },
                    icon: switch (product.syncStatus) {
                      'SYNCED' => Icons.cloud_done_outlined,
                      'ERROR' => Icons.error_outline,
                      'SYNCING' => Icons.sync,
                      _ => Icons.cloud_upload_outlined,
                    },
                  ),
                ),
                const Spacer(),
                if (controller.canUpdateProducts())
                  TextButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 14),
                    label: Text(l10n?.editVariant ?? 'Edit'),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _masterName(
  AppController c,
  String type,
  String? id, [
  String? fallback,
]) {
  final found = (c.productMasterValues[type] ?? [])
      .where((v) => v.id == id)
      .firstOrNull;
  if (found != null) return found.name;
  if (fallback != null &&
      !fallback.startsWith('SYS_') &&
      !fallback.startsWith('PM_')) {
    return fallback;
  }
  return 'Unavailable';
}

String _displayValue(AppController c, dynamic value) {
  if (value == null) return '';
  if (value is List) {
    return value
        .map((v) => _displayValue(c, v))
        .where((v) => v.isNotEmpty)
        .join(', ');
  }
  final text = value.toString();
  final master = c.productMasterValues.values
      .expand((v) => v)
      .where((v) => v.id == text)
      .firstOrNull;
  if (master != null) return master.name;
  return text.startsWith('SYS_') || text.startsWith('PM_')
      ? 'Unavailable'
      : text;
}

/// The header and rows share widths, padding, flex and alignment.
class ProductTableColumns {
  static const minimumWidth = 880.0;
  static const tabletMinimumWidth = 680.0;
  static const widths = <double?>[
    38,
    52,
    null,
    null,
    null,
    64,
    78,
    80,
    80,
    36,
    36,
  ];
  static const descriptiveFlex = {2: 3, 3: 2, 4: 2};
  static Widget row(List<Widget> cells, {bool tablet = false}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Row(
      children: [
        for (var i = 0; i < cells.length; i++)
          if (tablet && (i == 3 || i == 4))
            const SizedBox.shrink()
          else if (widths[i] != null)
            SizedBox(
              width: widths[i],
              child: Align(
                alignment: i == 6
                    ? Alignment.centerRight
                    : Alignment.center,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: cells[i],
                ),
              ),
            )
          else
            Expanded(
              flex: descriptiveFlex[i] ?? 1,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: cells[i],
              ),
            ),
      ],
    ),
  );
  static Widget header({bool tablet = false}) => SizedBox(
    height: 36,
    child: row([
      for (final title in [
        '',
        '',
        'Product',
        'Brand',
        'Category',
        'Variants',
        'Stock',
        'Status',
        'Sync',
        '',
        '',
      ])
        Text(
          title,
          maxLines: 1,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
        ),
    ], tablet: tablet),
  );
}

class _ProductBadge extends StatelessWidget {
  const _ProductBadge({
    required this.label,
    this.icon,
    this.backgroundColor,
    this.color,
  });
  final String label;
  final IconData? icon;
  final Color? backgroundColor;
  final Color? color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    decoration: BoxDecoration(
      color:
          backgroundColor ??
          Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: (Theme.of(context).textTheme.labelSmall ?? const TextStyle())
                .copyWith(color: color, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

class _ProductTile extends StatefulWidget {
  const _ProductTile({
    super.key,
    this.compact = false,
    this.tablet = false,
    required this.product,
    required this.controller,
    required this.selected,
    required this.onSelect,
    required this.onStatus,
    required this.onPrintBarcode,
  });
  final bool compact, tablet;
  final ProductModel product;
  final AppController controller;
  final bool selected;
  final ValueChanged<bool> onSelect;
  final ValueChanged<String> onStatus;
  final ValueChanged<ProductVariantModel> onPrintBarcode;
  @override
  State<_ProductTile> createState() => _ProductTileState();
}

class _ProductTileState extends State<_ProductTile> {
  bool expanded = false;
  ProductModel get product => widget.product;
  AppController get controller => widget.controller;
  bool get selected => widget.selected;
  ValueChanged<bool> get onSelect => widget.onSelect;
  ValueChanged<String> get onStatus => widget.onStatus;
  ValueChanged<ProductVariantModel> get onPrintBarcode => widget.onPrintBarcode;
  String get stockSummary {
    if (!controller.canViewStorage()) return '—';
    if (product.variants.map((v) => v.baseUnitId).toSet().length > 1) {
      return '—';
    }
    final total = product.variants.fold<num>(
      0,
      (sum, v) => sum + (controller.productStock[v.variantId] ?? 0),
    );
    return formatStockQuantity(total);
  }

  Widget _row(List<Widget> cells) {
    if (!widget.compact) {
      return ProductTableColumns.row(cells, tablet: widget.tablet);
    }
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                cells[0],
                cells[1],
                const SizedBox(width: 8),
                Expanded(child: cells[2]),
                cells[9],
                cells[10],
              ],
            ),
          ),
          Row(
            children: [
              Text('${product.variants.length} variants'),
              const SizedBox(width: 16),
              Text('Stock $stockSummary'),
              const Spacer(),
              cells[7],
              const SizedBox(width: 8),
              cells[8],
            ],
          ),
        ],
      ),
    );
  }

  void edit(BuildContext context) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            _StructuredProductFormPage(controller: controller, product: product),
      ),
    );
    if (saved == true) {
      await controller.loadProducts();
      await controller.loadProductMasters();
    }
  }
  @override
  Widget build(BuildContext context) => Column(
    children: [
      SizedBox(
        height: widget.compact ? 130 : 54,
        child: _row([
          Checkbox(value: selected, onChanged: (v) => onSelect(v ?? false)),
          ProductThumbnail(url: product.productImage, name: product.name),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(product.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(
                product.productCode ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          Text(
            _masterName(controller, 'BRAND', product.brandId, product.brand),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            _masterName(
              controller,
              'CATEGORY',
              product.categoryId,
              product.category,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text('${product.variants.length}'),
          Text(stockSummary, maxLines: 1, softWrap: false),
          _ProductBadge(
            label: product.isActive ? 'Active' : 'Inactive',
            backgroundColor: product.isActive
                ? Colors.green.shade100
                : Colors.red.shade100,
            color: product.isActive
                ? Colors.green.shade900
                : Colors.red.shade900,
          ),
          Tooltip(
            message: product.syncStatus == 'ERROR'
                ? (controller.sync?.error ??
                      'Synchronization failed. Retry using the global sync indicator.')
                : 'Synchronization: ${product.syncStatus}',
            child: _ProductBadge(
              label: switch (product.syncStatus) {
                'SYNCED' => 'Synced',
                'ERROR' => 'Error',
                'SYNCING' => 'Syncing',
                _ => 'Pending',
              },
              icon: switch (product.syncStatus) {
                'SYNCED' => Icons.cloud_done_outlined,
                'ERROR' => Icons.error_outline,
                'SYNCING' => Icons.sync,
                _ => Icons.cloud_upload_outlined,
              },
            ),
          ),
          PopupMenuButton<String>(
            key: ValueKey('product-actions-${product.productId}'),
            onSelected: (action) async {
              if (action == 'duplicate') {
                final saved = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => _StructuredProductFormPage(
                      controller: controller,
                      product: product,
                      duplicate: true,
                    ),
                  ),
                );
                if (saved == true) {
                  await controller.loadProducts();
                  await controller.loadProductMasters();
                }
              } else if (action == 'view') {
                final attributes = await controller.loadProductTemplate(
                  product.subcategoryId ?? '',
                );
                if (!context.mounted) return;
                showDialog<void>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(product.name),
                    content: SizedBox(
                      width: 500,
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ProductThumbnail(
                              url: product.productImage,
                              name: product.name,
                            ),
                            Text(product.description ?? ''),
                            Text('HSN: ${product.hsnCode ?? '—'}'),
                            for (final entry in product.attributeValues.entries)
                              Text(
                                '${attributes.where((a) => a.id == entry.key).firstOrNull?.name ?? 'Additional detail'}: ${_displayValue(controller, entry.value)}',
                              ),
                          ],
                        ),
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                );
              } else if (action == 'edit') {
                edit(context);
              } else if (action == 'remove_from_outlet' ||
                  action == 'manage_outlet_assignment') {
                final outletName =
                    controller.currentOutlet?.outletName ?? 'this outlet';
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Remove from this outlet?'),
                    content: Text(
                      '${product.name} will be removed from $outletName. '
                      'The product and variant masters will remain preserved in the catalogue and other outlets.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        key: const ValueKey('confirm-remove-from-outlet'),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Remove from this outlet'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true && context.mounted) {
                  final removed = await controller
                      .removeProductFromCurrentOutlet(product.productId);
                  if (removed && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '${product.name} removed from $outletName.',
                        ),
                      ),
                    );
                  }
                }
              } else {
                onStatus(action);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'view', child: Text('View')),
              if (controller.canCreateProducts())
                const PopupMenuItem(
                  value: 'duplicate',
                  child: Text('Duplicate'),
                ),
              if (controller.canUpdateProducts())
                const PopupMenuItem(
                  value: 'edit',
                  child: Text('Edit Product / Manage Variants'),
                ),
              if (controller.canUpdateProducts() &&
                  controller.currentOutlet != null) ...[
                const PopupMenuItem(
                  key: ValueKey('manage-outlet-assignment'),
                  value: 'manage_outlet_assignment',
                  child: Text('Manage outlet assignment'),
                ),
                if (product.isActive)
                  const PopupMenuItem(
                    key: ValueKey('remove-from-outlet'),
                    value: 'remove_from_outlet',
                    child: Text('Remove from this outlet'),
                  )
                else
                  const PopupMenuItem(
                    key: ValueKey('activate-in-outlet'),
                    value: 'ACTIVE',
                    child: Text('Activate in this outlet'),
                  ),
              ],
              if (controller.currentOutlet == null) ...[
                if (controller.canUpdateProducts())
                  PopupMenuItem(
                    value: product.isActive ? 'INACTIVE' : 'ACTIVE',
                    child: Text(product.isActive ? 'Deactivate' : 'Activate'),
                  ),
                if (controller.canDeleteProducts())
                  const PopupMenuItem(value: 'DELETED', child: Text('Delete')),
              ],
            ],
          ),
          IconButton(
            onPressed: () => setState(() => expanded = !expanded),
            icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
          ),
        ]),
      ),
      if (expanded)
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: [
              for (final label in [
                'Specification',
                'SKU',
                'Barcode',
                'Pack / Unit',
                'Shade',
                'Selling price',
                'Stock',
                'GST',
                'Status',
                'Actions',
              ])
                DataColumn(label: Text(label)),
            ],
            rows: [
              for (final v in product.variants)
                DataRow(
                  cells: [
                    DataCell(
                      SizedBox(
                        width: 180,
                        child: Text(
                          v.attributeValues.isEmpty
                              ? _displayValue(controller, v.name)
                              : v.attributeValues.values
                                    .map(
                                      (value) =>
                                          _displayValue(controller, value),
                                    )
                                    .where((value) => value.isNotEmpty)
                                    .take(3)
                                    .join(' '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    DataCell(Text(v.sku ?? '—')),
                    DataCell(Text(v.barcode ?? '—')),
                    DataCell(
                      Text(
                        '${v.packSize ?? ''} ${_masterName(controller, 'UNIT', v.packUnitId ?? v.baseUnitId)}'
                            .trim(),
                      ),
                    ),
                    DataCell(Text(v.shadeCode ?? '—')),
                    DataCell(
                      Text('₹${(v.sellingPrice / 100).toStringAsFixed(2)}'),
                    ),
                    DataCell(
                      Text(
                        controller.canViewStorage()
                            ? formatStockQuantity(
                                controller.productStock[v.variantId] ?? 0,
                              )
                            : '—',
                      ),
                    ),
                    DataCell(Text('${v.defaultGstRateBps / 100}%')),
                    DataCell(
                      _ProductBadge(
                        label: v.status.toUpperCase() == 'ACTIVE'
                            ? 'Active'
                            : 'Inactive',
                        backgroundColor: v.status.toUpperCase() == 'ACTIVE'
                            ? Colors.green.shade100
                            : Colors.red.shade100,
                        color: v.status.toUpperCase() == 'ACTIVE'
                            ? Colors.green.shade900
                            : Colors.red.shade900,
                      ),
                    ),
                    DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip:
                                !product.isActive ||
                                    v.status.toUpperCase() != 'ACTIVE'
                                ? 'Barcode disabled: Inactive'
                                : (controller.canViewStorage() &&
                                      (controller.productStock[v.variantId] ??
                                              0) <=
                                          0)
                                ? 'Barcode disabled: No stock available'
                                : 'Print Barcode',
                            onPressed:
                                (!product.isActive ||
                                    v.status.toUpperCase() != 'ACTIVE' ||
                                    (controller.canViewStorage() &&
                                        (controller.productStock[v.variantId] ??
                                                0) <=
                                            0))
                                ? null
                                : () => onPrintBarcode(v),
                            icon: const Icon(Icons.print_outlined),
                          ),
                          if (controller.canUpdateProducts())
                            TextButton(
                              onPressed: () => edit(context),
                              child: const Text('Edit Variant'),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
    ],
  );
}

class _StructuredProductFormPage extends StatefulWidget {
  const _StructuredProductFormPage({
    required this.controller,
    this.product,
    this.duplicate = false,
  });
  final ProductModel? product;
  final bool duplicate;
  final AppController controller;

  @override
  State<_StructuredProductFormPage> createState() =>
      _StructuredProductFormPageState();
}

class _StructuredProductFormPageState
    extends State<_StructuredProductFormPage> {
  bool get _editing => widget.product != null && !widget.duplicate;
  final _name = TextEditingController(),
      _description = TextEditingController(),
      _imageUrl = TextEditingController();
  bool _imageExplicitlyRemoved = false;
  final _hsn = TextEditingController(), _gst = TextEditingController(text: '0');
  String _productStatus = 'ACTIVE';
  final _formKey = GlobalKey<FormState>();
  final _nameFocus = FocusNode();
  final _hsnFocus = FocusNode();
  ProductMasterValue? _brand, _category, _subcategory;
  final _productValues = <String, dynamic>{};
  final _rows = <Map<String, dynamic>>[{}];
  final _productQuantitySlabs = <QuantityDiscountSlab>[];
  ResolvedProductTemplate? _resolvedTemplate;
  List<ProductAttribute> get _template =>
      _resolvedTemplate?.attributes ?? const [];
  bool get _hasUsableTemplate {
    final selectedId = _subcategory?.id;
    final resolved = _resolvedTemplate;
    return selectedId != null &&
        resolved != null &&
        resolved.subcategoryId == selectedId &&
        resolved.readiness == TemplateReadinessState.ready &&
        resolved.attributes.isNotEmpty;
  }

  List<ProductAttribute> _appliedTemplate = [];
  bool _loading = false, _saving = false, _templateLoading = false;
  String? _error;
  int _request = 0;
  StreamSubscription<void>? _syncSubscription;
  Timer? _centralSearchDebounce;
  Completer<Iterable<_CentralProductOption>>? _centralSearchCompleter;
  int _centralSearchRequest = 0;
  bool _centralSearchLoading = false;
  String? _centralSearchError;
  String? _masterProductId;
  String? _selectedMasterProductName;
  @override
  void initState() {
    super.initState();
    _initializeSafely();
    _syncSubscription = widget.controller.sync?.changes.stream.listen((
      _,
    ) async {
      final selected = _subcategory;
      final request = _request;
      if (!mounted || selected == null) return;
      try {
        await _loadMasters(categoryId: _category?.id);
        if (!mounted ||
            request != _request ||
            _subcategory?.id != selected.id) {
          return;
        }
        final resolved = await widget.controller.resolveProductTemplate(
          selected.id,
        );
        if (!mounted ||
            request != _request ||
            _subcategory?.id != selected.id) {
          return;
        }
        setState(() {
          _resolvedTemplate = resolved;
          if (resolved.subcategoryId == selected.id &&
              resolved.readiness == TemplateReadinessState.ready &&
              resolved.attributes.isNotEmpty) {
            _error = null;
          }
          _reconcileTemplateValues(resolved.attributes);
        });
      } catch (e) {
        if (mounted && request == _request && _subcategory?.id == selected.id) {
          setState(() => _error = e.toString());
        }
      }
    });
  }

  Future<void> _initializeSafely() async {
    final request = _request;
    try {
      await _initialize();
    } catch (e) {
      if (mounted && request == _request) {
        setState(() => _error = 'Unable to load saved product details: $e');
      }
    }
  }

  Future<void> _initialize() async {
    final p = widget.product;
    final initializeRequest = _request;
    await _loadMasters(categoryId: p?.categoryId);
    if (p == null || !mounted || initializeRequest != _request) return;
    _masterProductId = p.masterProductId;
    _selectedMasterProductName = p.name;
    _hsn.text = p.hsnCode ?? '';
    _productValues.remove('hsnCode');
    _gst.text = (p.defaultGstRateBps / 100).toString();
    _productStatus = p.status;
    _name.text = widget.duplicate ? '${p.name} Copy' : p.name;
    _description.text = p.description ?? '';
    _imageUrl.text =
        ProductModel.parseProductImage({'productImage': p.productImage}) ?? '';
    _imageExplicitlyRemoved = false;
    _brand = _values('BRAND')
        .where((v) => v.id == p.brandId || v.name == p.brand)
        .firstOrNull;
    _category = _values('CATEGORY')
        .where((v) => v.id == p.categoryId || v.name == p.category)
        .firstOrNull;
    if (_category == null && p.categoryId != null) {
      _category = ProductMasterValue(
        id: p.categoryId!,
        name: '${p.category ?? p.categoryId} (Legacy classification)',
        status: 'INACTIVE',
      );
    }
    _subcategory = _values('SUBCATEGORY:${p.categoryId}')
        .where((v) => v.id == p.subcategoryId || v.name == p.subcategory)
        .firstOrNull;
    if (_subcategory == null && p.subcategoryId != null) {
      _subcategory = ProductMasterValue(
        id: p.subcategoryId!,
        name: '${p.subcategory ?? p.subcategoryId} (Legacy classification)',
        status: 'INACTIVE',
        categoryId: p.categoryId,
      );
    }
    _productValues.addAll(p.attributeValues);
    _productValues.remove('hsnCode');
    _productQuantitySlabs.clear();
    _productQuantitySlabs.addAll(p.quantitySlabs);
    _rows.clear();
    for (final v in p.variants) {
      _rows.add({
        ...v.attributeValues,
        'variantId': v.variantId,
        '_baseUnit': v.baseUnitId,
        '_packUnit': v.packUnitId ?? v.baseUnitId,
        '_savedAttributes': Map<String, dynamic>.from(v.attributeValues),
        'packSize':
            v.attributeValues['packSize'] ??
            num.tryParse(v.packSize ?? '') ??
            v.packSize,
        '_commercialUnit': v.commercialUnitId ?? v.baseUnitId,
        '_packaging':
            v.baseQuantityPerCommercialUnit != 1 ||
            (v.commercialUnitId != null && v.commercialUnitId != v.baseUnitId),
        '_conversion': v.baseQuantityPerCommercialUnit,
        'barcode': v.barcode,
        '_sku': v.sku,
        '_gstOverrideVisible':
            v.gstOverride == true ||
            v.gstOverride == null && v.defaultGstRateBps != p.defaultGstRateBps,
        'defaultGstRateBps':
            v.gstOverride == true ||
                v.gstOverride == null &&
                    v.defaultGstRateBps != p.defaultGstRateBps
            ? v.defaultGstRateBps
            : null,
        'status': v.status,
        'sellingPrice': v.sellingPrice,
        'purchaseRate': v.purchaseRate,
        'mrp': v.mrp,
      });
    }
    if (widget.duplicate) {
      for (final row in _rows) {
        row.remove('variantId');
        row.remove('_sku');
        row.remove('barcode');
      }
    }
    if (_subcategory != null) {
      final selectedId = _subcategory!.id;
      final request = _request;
      final resolved = await widget.controller.resolveProductTemplate(
        selectedId,
      );
      if (!mounted || request != _request || _subcategory?.id != selectedId) {
        return;
      }
      _resolvedTemplate = resolved;
      if (resolved.subcategoryId == selectedId &&
          resolved.readiness == TemplateReadinessState.ready &&
          resolved.attributes.isNotEmpty) {
        _error = null;
      }
      _reconcileTemplateValues(resolved.attributes);
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _centralSearchDebounce?.cancel();
    final pendingSearch = _centralSearchCompleter;
    if (pendingSearch != null && !pendingSearch.isCompleted) {
      pendingSearch.complete(const []);
    }
    unawaited(_syncSubscription?.cancel());
    _nameFocus.dispose();
    _hsnFocus.dispose();
    _hsn.dispose();
    _gst.dispose();
    _name.dispose();
    _description.dispose();
    _imageUrl.dispose();
    super.dispose();
  }

  List<ProductMasterValue> _values(String type) =>
      widget.controller.productMasterValues[type] ?? [];

  void _onProductNameChanged(String value) {
    setState(() {
      _centralSearchLoading = value.trim().length >= 2;
      _centralSearchError = null;
      if (_masterProductId != null &&
          value.trim() != _selectedMasterProductName) {
        _masterProductId = null;
        _selectedMasterProductName = null;
      }
    });
  }

  Future<Iterable<_CentralProductOption>> _centralProductOptions(
    TextEditingValue value,
  ) {
    final request = ++_centralSearchRequest;
    _centralSearchDebounce?.cancel();
    final pending = _centralSearchCompleter;
    if (pending != null && !pending.isCompleted) {
      pending.complete(const []);
    }
    final query = value.text.trim();
    if (query.length < 2) return Future.value(const []);

    final completer = Completer<Iterable<_CentralProductOption>>();
    _centralSearchCompleter = completer;
    _centralSearchDebounce = Timer(const Duration(milliseconds: 150), () async {
      try {
        final products = await widget.controller.searchCentralProductMaster(
          query,
        );
        if (!mounted || request != _centralSearchRequest) return;
        setState(() {
          _centralSearchLoading = false;
          _centralSearchError = null;
        });
        completer.complete([
          for (final product in products) _CentralProductOption(product, query),
          if (products.isEmpty) _CentralProductOption.custom(query),
        ]);
      } catch (error) {
        if (!mounted || request != _centralSearchRequest) return;
        if (kDebugMode) debugPrint('Central product search failed: $error');
        setState(() {
          _centralSearchLoading = false;
          _centralSearchError = 'Unable to search products';
        });
        completer.complete(const []);
      }
    });
    return completer.future;
  }

  Future<void> _selectCentralProduct(CentralProductMaster product) async {
    final previousSubcategoryId = _subcategory?.id;
    final previousMasterProductId = _masterProductId;
    if (kDebugMode) {
      debugPrint(
        'Central product selected: masterProductId=${product.masterProductId}, '
        'productName="${product.productName}", categoryId=${product.categoryId}, '
        'subcategoryId=${product.subcategoryId}, '
        'previousSubcategoryId=$previousSubcategoryId, '
        'templateRowsBeforeReset=${_template.length}, '
        'templateAttributeIdsBeforeReset=${_template.map((a) => a.id).toList()}',
      );
    }
    final brand = ProductMasterValue(
      id: product.brandId,
      name: product.brandName,
      status: 'ACTIVE',
      scopeType: product.scopeType ?? 'SYSTEM',
    );
    final category = ProductMasterValue(
      id: product.categoryId,
      name: product.categoryName,
      status: 'ACTIVE',
      scopeType: product.scopeType ?? 'SYSTEM',
    );
    final subcategory = ProductMasterValue(
      id: product.subcategoryId,
      name: product.subcategoryName,
      status: 'ACTIVE',
      scopeType: product.scopeType ?? 'SYSTEM',
      categoryId: product.categoryId,
    );
    setState(() {
      _name.text = product.productName;
      _masterProductId = product.masterProductId;
      _selectedMasterProductName = product.productName;
      _brand = brand;
      _category = category;
      _centralSearchLoading = false;
      _centralSearchError = null;
    });
    await _selectSubcategory(
      subcategory,
      forceReset: previousMasterProductId != product.masterProductId,
    );
  }

  Future<void> _loadMasters({String? categoryId}) async {
    setState(() => _loading = true);
    await widget.controller.loadProductMasters(categoryId: categoryId);
    if (mounted) setState(() => _loading = false);
  }

  void _reconcileTemplateValues(
    List<ProductAttribute> template, {
    bool resetDefaults = false,
  }) {
    void reconcile(Map<String, dynamic> values, String level) {
      final applicable = template.where(
        (a) => a.level == level && a.id != 'hsnCode',
      );
      final ids = applicable.map((a) => a.id).toSet();
      values.removeWhere(
        (key, _) =>
            !key.startsWith('_') &&
            !{
              'variantId',
              'barcode',
              'status',
              'defaultGstRateBps',
            }.contains(key) &&
            !ids.contains(key),
      );
      values.remove('sellingPrice');
      values.remove('purchaseRate');
      values.remove('mrp');
      for (final a in applicable) {
        dynamic value = values[a.id];
        if (a.dataType == 'SELECT' && value != null) {
          final display = _displayValue(widget.controller, value);
          value = a.options.contains(value)
              ? value
              : a.options.contains(display)
              ? display
              : null;
        } else if (a.dataType == 'MULTI_SELECT' && value != null) {
          value = value is List
              ? value
                    .map(
                      (v) => a.options.contains(v)
                          ? v
                          : _displayValue(widget.controller, v),
                    )
                    .where(a.options.contains)
                    .toList()
              : null;
          if (value is List && value.isEmpty) value = null;
        }
        final previous = _appliedTemplate
            .where((old) => old.id == a.id && old.level == a.level)
            .firstOrNull;
        final defaultChanged =
            previous != null &&
            jsonEncode(previous.defaultValue) != jsonEncode(a.defaultValue);
        final fallback = level == 'VARIANT' ? _productValues : null;
        if ((resetDefaults || defaultChanged) &&
                previous != null &&
                jsonEncode(value) == jsonEncode(previous.defaultValue) ||
            value == null) {
          value = a.initialValue(values, fallback);
        }
        // Invalid catalogue defaults must never become editable selections.
        if (a.dataType == 'SELECT' && !a.options.contains(value)) value = null;
        if (a.dataType == 'MULTI_SELECT' && value != null) {
          value = value is List
              ? value.where(a.options.contains).toList()
              : null;
        }
        values[a.id] = value;
      }
      values.remove('_savedAttributes');
    }

    reconcile(_productValues, 'PRODUCT');
    for (final row in _rows) {
      if (resetDefaults) {
        row['_packaging'] = false;
        row['_conversion'] = null;
        row['_baseUnit'] = null;
        row['_commercialUnit'] = null;
        row['_packUnit'] = null;
      }
      reconcile(row, 'VARIANT');
    }
    _clearHidden(_productValues, 'PRODUCT');
    for (final row in _rows) {
      _clearHidden(row, 'VARIANT');
      _applyUnitDefault(row, classificationChanged: resetDefaults);
    }
    _onColourTypeChanged();
    _appliedTemplate = template;
  }

  List<String> _renderedTemplateAttributeIds() {
    final rendered = <String>[];
    for (final attribute in _template) {
      if (attribute.id == 'hsnCode' ||
          attribute.id == 'colourMode' &&
              _template.any((value) => value.id == 'colourType') ||
          attribute.id == 'unit' &&
              !_template.any((value) => value.id == 'packSize') &&
              _template.any((value) => value.id == 'soldAs') ||
          _template.any(
            (parent) =>
                parent.measurementUnitAttributeId == attribute.id &&
                parent.level == attribute.level,
          )) {
        continue;
      }
      final visible = attribute.level == 'PRODUCT'
          ? attribute.isVisible(_productValues, null, _rows)
          : _rows.any((row) => attribute.isVisible(_productValues, row, _rows));
      if (visible) rendered.add(attribute.id);
    }
    return rendered;
  }

  void _onColourTypeChanged() {
    for (final row in _rows) {
      final modeVal =
          (row['colourType'] ??
                  row['colorType'] ??
                  row['colourMode'] ??
                  _productValues['colourType'] ??
                  _productValues['colourMode'])
              ?.toString()
              .trim();
      if (modeVal == null) continue;

      final modeLower = modeVal.toLowerCase();
      final isFixed = modeLower.contains('fixed');
      final isReady =
          modeLower.contains('ready') || modeLower.contains('multiple');
      final isTintable =
          modeLower.contains('tintable') || modeLower.contains('base');
      final isClear =
          modeLower.contains('clear') || modeLower.contains('transparent');
      final isNA =
          modeLower.contains('not applicable') || modeLower.contains('n/a');

      if (isFixed) {
        row.remove('shade');
        row.remove('shadeCode');
        row.remove('colourFamily');
        row.remove('colorFamily');
        row.remove('baseType');
        row.remove('baseCode');
      } else if (isReady) {
        row.remove('baseType');
        row.remove('baseCode');
      } else if (isTintable) {
        row.remove('shade');
        row.remove('shadeCode');
        row.remove('colourFamily');
        row.remove('colorFamily');
      } else if (isClear || isNA) {
        row.remove('shade');
        row.remove('shadeCode');
        row.remove('colourFamily');
        row.remove('colorFamily');
        row.remove('baseType');
        row.remove('baseCode');
      }
    }

    final anyFixed = _rows.any((r) {
      final ct =
          (r['colourType'] ??
                  r['colorType'] ??
                  r['colourMode'] ??
                  _productValues['colourType'] ??
                  _productValues['colourMode'])
              ?.toString()
              .toLowerCase() ??
          '';
      return ct.contains('fixed');
    });

    if (!anyFixed) {
      _productValues.remove('productColour');
      _productValues.remove('colour');
    }
  }

  void _clearHidden(Map<String, dynamic> values, String level) {
    for (final a in _template.where(
      (a) =>
          a.level == level &&
          !a.isVisible(
            level == 'VARIANT' ? _productValues : values,
            level == 'VARIANT' ? values : null,
            _rows,
          ),
    )) {
      values.remove(a.id);
    }
  }

  void _applyUnitDefault(
    Map<String, dynamic> row, {
    bool classificationChanged = false,
  }) {
    final rules = _resolvedTemplate?.unitRules ?? const ResolvedUnitRule();
    rules.reconcileVariantState(
      row,
      preserveExisting: _editing && !classificationChanged,
    );
    // Display selections may be names; persistence keeps the actual master ID.
    for (final key in ['_packUnit', '_commercialUnit', '_baseUnit']) {
      final value = row[key];
      final master = _values('UNIT')
          .where((u) => u.id == value || u.name == value)
          .firstOrNull;
      if (master != null) row[key] = master.id;
    }
  }

  Future<void> _selectSubcategory(
    ProductMasterValue? value, {
    bool forceReset = false,
  }) async {
    if (!forceReset &&
        value != null &&
        _subcategory?.id == value.id &&
        _hasUsableTemplate) {
      return;
    }
    final previousSubcategoryId = _subcategory?.id;
    final subcategoryChanged = previousSubcategoryId != value?.id;
    final resetState = subcategoryChanged || forceReset;
    final request = ++_request;
    final oldTemplateIds = _template.map((attribute) => attribute.id).toSet();
    if (kDebugMode && resetState) {
      debugPrint(
        'Product subcategory changed: previousSubcategoryId=$previousSubcategoryId, '
        'subcategoryId=${value?.id}, templateRowsBeforeReset=${_template.length}',
      );
    }
    setState(() {
      _subcategory = value;
      _resolvedTemplate = null;
      _appliedTemplate = [];
      _error = null;
      _templateLoading = value != null;
      if (resetState) {
        _productValues.clear();
        if (!_editing) {
          _rows
            ..clear()
            ..add({});
        } else {
          for (final row in _rows) {
            row.removeWhere(
              (key, _) =>
                  oldTemplateIds.contains(key) ||
                  const {
                    '_savedAttributes',
                    '_packaging',
                    '_conversion',
                    '_baseUnit',
                    '_commercialUnit',
                    '_packUnit',
                  }.contains(key),
            );
          }
        }
      }
    });
    if (kDebugMode && resetState) {
      debugPrint(
        'Product template state reset: previousSubcategoryId=$previousSubcategoryId, '
        'subcategoryId=${value?.id}, templateRowsAfterReset=${_template.length}',
      );
    }
    if (value == null) return;
    try {
      final resolved = await widget.controller.resolveProductTemplate(value.id);
      final template = resolved.attributes;
      if (!mounted || request != _request || _subcategory?.id != value.id) {
        return;
      }
      setState(() {
        _resolvedTemplate = resolved;
        _error = null;
        _reconcileTemplateValues(template, resetDefaults: true);
      });
      if (kDebugMode) {
        debugPrint(
          'Product template loaded: subcategoryId=${value.id}, '
          'templateRowsAfterReload=${template.length}, '
          'attributeIdsRendered=${_renderedTemplateAttributeIds()}',
        );
      }
    } catch (e) {
      if (mounted && request == _request && _subcategory?.id == value.id) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted && request == _request && _subcategory?.id == value.id) {
        setState(() => _templateLoading = false);
      }
    }
  }

  Future<ProductMasterValue?> _addMaster(
    String type, {
    String? categoryId,
  }) async {
    final name = TextEditingController();
    final code = TextEditingController();
    final route = DialogRoute<ProductMasterValue>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text('Add ${_masterLabel(type)}'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  autofocus: true,
                  enableInteractiveSelection: true,
                  decoration: InputDecoration(
                    labelText: '${_masterLabel(type)} name',
                    hintText: _suggestion(type),
                  ),
                ),
                if (type == 'SHADE' || type == 'HSN')
                  TextField(
                    controller: code,
                    enableInteractiveSelection: true,
                    decoration: InputDecoration(
                      labelText: type == 'SHADE' ? 'Shade Code' : 'HSN Code',
                    ),
                  ),
                if (type == 'SUBCATEGORY')
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'This value will be linked to the selected Category.',
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (name.text.trim().isEmpty) return;
                final created = await widget.controller.createProductMaster(
                  masterType: type,
                  name: name.text,
                  categoryId: categoryId,
                  code: code.text,
                );
                if (!dialogContext.mounted) return;
                if (created != null) {
                  Navigator.pop(dialogContext, created);
                } else {
                  setState(
                    () => _error = widget.controller.productMastersError,
                  );
                }
              },
              child: const Text('Save & Select'),
            ),
          ],
        ),
      ),
    );
    final result = await Navigator.of(context, rootNavigator: true).push(route);
    // The dialog still uses these controllers during its closing animation.
    await route.completed;
    name.dispose();
    code.dispose();
    return result;
  }

  String _masterLabel(String type) => switch (type) {
    'BRAND' => 'Brand / Company',
    'CATEGORY' => 'Category',
    'SUBCATEGORY' => 'Subcategory',
    'SHADE' => 'Shade / Colour',
    'PACK_SIZE' => 'Pack Size',
    'UNIT' => 'Unit',
    'HSN' => 'HSN Code',
    'USAGE' => 'Usage',
    'SURFACE' => 'Surface',
    'SEGMENT' => 'Segment / Grade',
    'FINISH' => 'Finish',
    'COLOUR_FAMILY' => 'Colour Family',
    'BASE_TYPE' => 'Base Type',
    'DILUTION_TYPE' => 'Dilution / Thinner Type',
    'NUMBER_OF_COATS' => 'Number of Coats',
    _ => type,
  };

  String? _suggestion(String type) => switch (type) {
    'BRAND' => 'Enter brand / company name',
    'CATEGORY' => 'Enter category name',
    'SUBCATEGORY' => 'Enter subcategory name',
    'UNIT' => 'e.g. Litre, ml, Kg, Piece',
    'PACK_SIZE' => 'e.g. 1 L, 4 L, 10 L',
    _ => null,
  };

  Widget _masterPicker({
    required String type,
    required ProductMasterValue? selected,
    required List<ProductMasterValue> options,
    required ValueChanged<ProductMasterValue?> onSelected,
    String? emptyMessage,
    String? categoryId,
  }) => _ProductMasterPicker(
    label: _masterLabel(type),
    selected: selected,
    options: options,
    emptyMessage: emptyMessage,
    validator: (v) =>
        v == null ? 'Select ${_masterLabel(type).toLowerCase()}' : null,
    canAdd: widget.controller.canCreateProductMasters(),
    onSelected: onSelected,
    onAdd: () async {
      final value = await _addMaster(type, categoryId: categoryId);
      if (value != null && mounted) onSelected(value);
    },
  );

  Widget _section(String title, Widget child) => NubiFormSection(
    title: title,
    subtitle: switch (title) {
      'Product Identity' => 'Basic information used to identify this product.',
      'Product Specifications' =>
        'Classification, tax and product-specific specifications.',
      'Sellable Variants / SKUs' =>
        'Add each size, pack, shade or other sellable variation.',
      _ => 'Add an optional image to identify the product quickly.',
    },
    child: child,
  );

  List<String> _measurementOptions(
    ProductAttribute parent,
    ProductAttribute unit,
  ) {
    if (unit.id == 'unit' ||
        unit.id == 'packUnit' ||
        unit.semanticRole == 'PACK_UNIT') {
      final allowed = _resolvedTemplate?.unitRules.allowedPackUnits ?? const [];
      if (allowed.isNotEmpty) return allowed;
      if (unit.options.isNotEmpty) return unit.options;
      return _values('UNIT').map((u) => u.name).toList();
    }
    final dimension = parent.measurementDimension ?? unit.measurementDimension;
    if (dimension == null) {
      return unit.options;
    }
    return unit.options
        .where(
          (option) => _values('UNIT').any(
            (master) =>
                (master.id == option || master.name == option) &&
                master.measurementDimension?.toUpperCase() ==
                    dimension.toUpperCase(),
          ),
        )
        .toList();
  }

  String _attributeHint(ProductAttribute attribute) {
    if (attribute.hintText?.trim().isNotEmpty == true) {
      return attribute.hintText!;
    }
    return switch (attribute.dataType) {
      'SELECT' => 'Select ${attribute.name.toLowerCase()}',
      'MULTI_SELECT' => 'Select one or more',
      'NUMBER' =>
        attribute.exampleValue == null
            ? 'Enter a number'
            : 'e.g. ${attribute.exampleValue}',
      _ => 'Enter ${attribute.name.toLowerCase()}',
    };
  }

  Widget _measuredAttribute(
    ProductAttribute a,
    Map<String, dynamic> values,
    String key, {
    Map<String, dynamic>? fallback,
  }) {
    final unit = _template
        .where(
          (u) => u.id == a.measurementUnitAttributeId && u.level == a.level,
        )
        .firstOrNull;
    if (unit == null) return _attribute(a, values, key, fallback: fallback);
    final options = _measurementOptions(a, unit);
    final selection = values[unit.id];
    final unitRequired = unit.isRequired(values, fallback);
    return NubiFieldGrid(
      breakpoint: 420,
      children: [
        _attribute(a, values, key, fallback: fallback),
        NubiFormColumn(
          gap: 4,
          children: [
            DropdownButtonFormField<String>(
              key: ValueKey('$key-measurement-$selection'),
              isExpanded: true,
              validator: (v) =>
                  unitRequired && v == null ? 'Select a size unit' : null,
              initialValue: options.contains(selection)
                  ? selection as String?
                  : null,
              decoration: InputDecoration(
                labelText: '${unit.name}${unitRequired ? ' *' : ''}',
                hintText: unit.hintText ?? 'Select size unit',
                errorText: selection != null && !options.contains(selection)
                    ? 'Choose a compatible measurement unit'
                    : null,
              ),
              items: [
                for (final option in options)
                  DropdownMenuItem(
                    value: option,
                    child: Text(
                      _displayValue(widget.controller, option),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (v) => setState(() {
                values[unit.id] = v;
                if (unit.level == 'VARIANT') _applyUnitDefault(values);
              }),
            ),
            if (unit.allowAddNewOption &&
                widget.controller.canCreateProductMasters())
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => _addOption(unit, values),
                  child: const Text('+ Add option'),
                ),
              ),
          ],
        ),
      ],
    );
  }

  String _soldAsLabel(Map<String, dynamic> row) {
    if (row['soldAs'] != null) {
      return _displayValue(widget.controller, row['soldAs']);
    }
    if (row['unit'] != null) {
      return _displayValue(widget.controller, row['unit']);
    }
    if (row['_commercialUnit'] != null) {
      return _masterName(
        widget.controller,
        'UNIT',
        row['_commercialUnit'] as String?,
      );
    }
    return 'Item';
  }

  Widget _sellingFields(Map<String, dynamic> row) {
    final packaged = row['_packaging'] == true;
    final hasSoldAsInTemplate = _template.any(
      (a) =>
          a.level == 'VARIANT' &&
          (a.id == 'soldAs' ||
              a.name == 'Sold As' ||
              a.semanticRole == 'SELLING_UNIT'),
    );
    final allUnits = _values('UNIT');

    final rules = _resolvedTemplate?.unitRules ?? const ResolvedUnitRule();
    List<ProductMasterValue> filterUnits(List<String> allowed) => allUnits
        .where(
          (u) => rules.allows(u.id, allowed) || rules.allows(u.name, allowed),
        )
        .toList();
    final soldAsAllowed = rules.allowedSellingUnits.isNotEmpty
        ? rules.allowedSellingUnits
        : rules.allowedPackUnits;
    var soldAsOptions = filterUnits(soldAsAllowed);
    if (soldAsOptions.isEmpty) {
      soldAsOptions = allUnits;
    }
    final baseUnitOptions = filterUnits(rules.allowedBaseUnits);

    Widget unitPicker(
      String label,
      String key,
      List<ProductMasterValue> options,
    ) => _ProductMasterPicker(
      label: label,
      selected:
          options
              .where((u) => u.id == row[key] || u.name == row[key])
              .firstOrNull ??
          allUnits
              .where((u) => u.id == row[key] || u.name == row[key])
              .firstOrNull,
      options: options,
      validator: (v) => v == null
          ? 'Select ${label.replaceAll(' *', '').toLowerCase()}'
          : null,
      canAdd: false,
      onSelected: (u) => setState(() {
        row[key] = u?.id;
      }),
      onAdd: () {},
    );

    final conversionFactor = row['_conversion'];
    final baseUnitId = row['_baseUnit'] as String?;
    final soldAsText = _soldAsLabel(row);
    final baseUnitText = _masterName(widget.controller, 'UNIT', baseUnitId);
    final showPreview =
        packaged &&
        soldAsText.isNotEmpty &&
        baseUnitText.isNotEmpty &&
        conversionFactor != null &&
        (conversionFactor is num) &&
        conversionFactor > 0;

    return NubiFieldGrid(
      children: [
        if (!hasSoldAsInTemplate)
          unitPicker('Sold As *', '_commercialUnit', soldAsOptions),
        NubiWideField(
          child: Material(
            color: Colors.transparent,
            child: CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Allow loose / converted sale'),
              value: packaged,
              onChanged: !rules.conversionAllowed
                  ? null
                  : (v) => setState(() {
                      row['_packaging'] = v == true;
                      _applyUnitDefault(row);
                    }),
            ),
          ),
        ),
        if (packaged) ...[
          TextFormField(
            key: ValueKey('contains-${identityHashCode(row)}'),
            validator: (v) {
              final quantity = num.tryParse(v ?? '');
              return quantity == null || !quantity.isFinite || quantity <= 0
                  ? 'Enter a quantity greater than zero'
                  : null;
            },
            initialValue: row['_conversion']?.toString(),
            decoration: const InputDecoration(
              labelText: 'Contains *',
              hintText: 'e.g. 12',
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (v) => setState(() {
              row['_conversion'] = num.tryParse(v);
            }),
          ),
          unitPicker('Base Unit *', '_baseUnit', baseUnitOptions),
          if (showPreview)
            NubiWideField(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '1 $soldAsText = $conversionFactor $baseUnitText',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }

  Future<void> _pasteImageUrl() async {
    final input = TextEditingController(text: _imageUrl.text);
    final route = DialogRoute<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Product image'),
        content: TextField(
          controller: input,
          decoration: const InputDecoration(
            labelText: 'Image URL',
            hintText: 'https://example.com/product.jpg',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, input.text.trim()),
            child: const Text('Preview'),
          ),
        ],
      ),
    );
    final value = await Navigator.of(context, rootNavigator: true).push(route);
    await route.completed;
    input.dispose();
    if (value != null && mounted) {
      setState(() {
        _imageUrl.text = value.trim();
        _imageExplicitlyRemoved = value.trim().isEmpty;
      });
    }
  }

  final Map<String, String> _optionQueries = {};

  Widget _attribute(
    ProductAttribute a,
    Map<String, dynamic> values,
    String key, {
    Map<String, dynamic>? fallback,
  }) {
    final rules = _resolvedTemplate?.unitRules ?? const ResolvedUnitRule();
    final allUnits = _values('UNIT');
    final options =
        (a.id == 'unit' || a.id == 'packUnit' || a.semanticRole == 'PACK_UNIT')
        ? (rules.allowedPackUnits.isNotEmpty
            ? rules.allowedPackUnits
            : (a.options.isNotEmpty
                ? a.options
                : allUnits.map((u) => u.name).toList()))
        : (a.id == 'soldAs' ||
              a.id == 'sellingUnit' ||
              a.semanticRole == 'SELLING_UNIT')
        ? (rules.allowedSellingUnits.isNotEmpty
            ? rules.allowedSellingUnits
            : (a.options.isNotEmpty
                ? a.options
                : allUnits.map((u) => u.name).toList()))
        : a.options;
    final required = a.isRequired(values, fallback);
    final label = '${a.name}${required ? ' *' : ''}';
    void change(dynamic v) => setState(() {
      values[a.id] = v;
      if (a.id == 'colourType') {
        if (v == 'Ready Colour') {
          values['colourMode'] = 'Multiple Ready Colours';
        } else if (v == 'Tintable Base') {
          values['colourMode'] = 'Tintable Base';
        } else if (v == 'Clear / Transparent') {
          values['colourMode'] = 'Clear / Transparent';
        } else if (v == 'Not Applicable') {
          values['colourMode'] = 'Not Applicable';
        }
      } else if (a.id == 'colourMode') {
        if (v == 'Multiple Ready Colours') {
          values['colourType'] = 'Ready Colour';
        } else if (v == 'Tintable Base') {
          values['colourType'] = 'Tintable Base';
        } else if (v == 'Clear / Transparent') {
          values['colourType'] = 'Clear / Transparent';
        } else if (v == 'Not Applicable') {
          values['colourType'] = 'Not Applicable';
        }
        if (v == 'Fixed Colour') {
          values['productColour'] ??=
              _template
                  .where((x) => x.id == 'productColour')
                  .firstOrNull
                  ?.defaultValue ??
              'White';
        } else {
          values.remove('productColour');
        }
      }
      _clearHidden(values, a.level);
      if (a.level == 'PRODUCT') {
        for (final row in _rows) {
          _clearHidden(row, 'VARIANT');
        }
      }
      if (a.level == 'VARIANT') _applyUnitDefault(values);
    });
    if (a.dataType == 'BOOLEAN') {
      return Material(
        color: Colors.transparent,
        child: SwitchListTile(
          title: Text(label),
          value: values[a.id] == true,
          onChanged: change,
        ),
      );
    }
    if (a.dataType == 'MULTI_SELECT') {
      return FormField<List>(
        key: ValueKey('$key-${values[a.id]}'),
        validator: (_) =>
            required &&
                (values[a.id] is! List || (values[a.id] as List).isEmpty)
            ? 'Select ${a.name.toLowerCase()}'
            : null,
        builder: (field) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelLarge),
            if (field.hasError)
              Text(
                field.errorText!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: 6),
            Text(
              _attributeHint(a),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            TextField(
              decoration: const InputDecoration(
                hintText: 'Search options',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) =>
                  setState(() => _optionQueries[key] = v.toLowerCase()),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final o in options.where(
                  (o) =>
                      (values[a.id] as List? ?? []).contains(o) ||
                      _displayValue(
                        widget.controller,
                        o,
                      ).toLowerCase().contains(_optionQueries[key] ?? ''),
                ))
                  FilterChip(
                    label: Text(_displayValue(widget.controller, o)),
                    selected: (values[a.id] as List? ?? []).contains(o),
                    onSelected: (selected) {
                      final v = List<String>.from(values[a.id] as List? ?? []);
                      selected ? v.add(o) : v.remove(o);
                      change(v);
                    },
                  ),
              ],
            ),
          ],
        ),
      );
    }
    if (a.dataType == 'SELECT') {
      return FormField<String>(
        key: ValueKey('$key-${values[a.id]}'),
        initialValue: values[a.id] as String?,
        validator: (v) =>
            required && v == null ? 'Select ${a.name.toLowerCase()}' : null,
        builder: (field) => LayoutBuilder(
          builder: (context, constraints) => DropdownMenu<String>(
            width: constraints.maxWidth,
            label: Text(label),
            hintText: _attributeHint(a),
            errorText: field.errorText,
            initialSelection: options.contains(values[a.id])
                ? values[a.id] as String?
                : null,
            enableFilter: true,
            enableSearch: true,
            requestFocusOnTap: true,
            dropdownMenuEntries: [
              for (final o in options)
                DropdownMenuEntry(
                  value: o,
                  label: _displayValue(widget.controller, o),
                ),
            ],
            onSelected: (v) {
              field.didChange(v);
              change(v);
            },
          ),
        ),
      );
    }
    return TextFormField(
      key: ValueKey(key),
      validator: (v) {
        if (v?.trim().isEmpty ?? true) {
          return required ? 'Enter ${a.name.toLowerCase()}' : null;
        }
        if (a.dataType == 'NUMBER') {
          final number = num.tryParse(v!);
          if (number == null || !number.isFinite) return 'Enter a valid number';
          if (a.minimumExclusive != null && number <= a.minimumExclusive!) {
            return 'Enter a size greater than zero';
          }
        }
        return null;
      },
      initialValue: values[a.id]?.toString() ?? '',
      decoration: InputDecoration(
        labelText: label,
        hintText: _attributeHint(a),
      ),
      keyboardType: a.dataType == 'NUMBER'
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      onChanged: (v) => change(a.dataType == 'NUMBER' ? num.tryParse(v) : v),
    );
  }

  Future<void> _addOption(
    ProductAttribute attribute,
    Map<String, dynamic> values,
  ) async {
    final selectedId = _subcategory?.id;
    final request = _request;
    final input = TextEditingController();
    final route = DialogRoute<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add ${attribute.name}'),
        content: TextField(
          controller: input,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Option name',
            hintText: 'Enter ${attribute.name.toLowerCase()}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, input.text),
            child: const Text('Add Option'),
          ),
        ],
      ),
    );
    final name = await Navigator.of(context, rootNavigator: true).push(route);
    await route.completed;
    input.dispose();
    if (name == null ||
        !mounted ||
        selectedId == null ||
        request != _request ||
        _subcategory?.id != selectedId) {
      return;
    }
    try {
      final existing = attribute.options.where(
        (o) => o.trim().toLowerCase() == name.trim().toLowerCase(),
      );
      final option = existing.isNotEmpty
          ? existing.first
          : await widget.controller.createProductAttributeOption(
              attribute.id,
              name,
            );
      final resolved = await widget.controller.resolveProductTemplate(
        selectedId,
      );
      if (mounted && request == _request && _subcategory?.id == selectedId) {
        setState(() {
          _resolvedTemplate = resolved;
          _error = null;
          _reconcileTemplateValues(resolved.attributes);
          values[attribute.id] = attribute.dataType == 'MULTI_SELECT'
              ? {
                  ...List<String>.from(values[attribute.id] as List? ?? []),
                  option,
                }.toList()
              : option;
        });
      }
    } catch (e) {
      if (mounted && request == _request && _subcategory?.id == selectedId) {
        setState(() => _error = e.toString());
      }
    }
  }

  Widget _fields(
    String level,
    Map<String, dynamic> values,
    String prefix, {
    String section = 'ESSENTIAL',
  }) {
    final fallback = level == 'VARIANT' ? _productValues : null;
    return NubiFieldGrid(
      children: [
        for (final a in _template.where(
          (a) =>
              a.level == level &&
              a.section == section &&
              a.isVisible(
                level == 'VARIANT' ? _productValues : values,
                level == 'VARIANT' ? values : null,
                _rows,
              ) &&
              a.id != 'hsnCode' &&
              (a.id != 'colourMode' ||
                  !_template.any((x) => x.id == 'colourType')) &&
              (a.id != 'unit' ||
                  _template.any((x) => x.id == 'packSize') ||
                  !_template.any((x) => x.id == 'soldAs')) &&
              !_template.any(
                (parent) =>
                    parent.measurementUnitAttributeId == a.id &&
                    parent.level == a.level,
              ),
        ))
          (a.dataType == 'MULTI_SELECT'
              ? NubiWideField(
                  child: _attributeWithAction(
                    a,
                    values,
                    '$_request-$prefix-${a.id}',
                    fallback: fallback,
                  ),
                )
              : _attributeWithAction(
                  a,
                  values,
                  '$_request-$prefix-${a.id}',
                  fallback: fallback,
                )),
      ],
    );
  }

  Widget _attributeWithAction(
    ProductAttribute a,
    Map<String, dynamic> values,
    String key, {
    Map<String, dynamic>? fallback,
  }) => NubiFormColumn(
    gap: 4,
    children: [
      _measuredAttribute(a, values, key, fallback: fallback),
      if (a.allowAddNewOption &&
          widget.controller.canCreateProductMasters() &&
          {'SELECT', 'MULTI_SELECT'}.contains(a.dataType))
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => _addOption(a, values),
            child: const Text('+ Add option'),
          ),
        ),
    ],
  );

  Future<void> _save() async {
    if (_formKey.currentState?.validate() == false) return;
    if (_subcategory == null ||
        _templateLoading ||
        !_hasUsableTemplate ||
        _brand == null ||
        _category == null) {
      setState(
        () => _error = _subcategory != null && !_hasUsableTemplate
            ? 'Product template unavailable for this subcategory.'
            : 'Select Brand, Category and Subcategory and load its template.',
      );
      return;
    }
    for (final attribute in _template.where(
      (a) => a.measurementUnitAttributeId != null,
    )) {
      final unit = _template
          .where(
            (u) =>
                u.id == attribute.measurementUnitAttributeId &&
                u.level == attribute.level,
          )
          .firstOrNull;
      if (unit == null) continue;
      for (final values
          in attribute.level == 'PRODUCT' ? [_productValues] : _rows) {
        if (!_measurementOptions(attribute, unit).contains(values[unit.id]) &&
            (unit.required || values[unit.id] != null)) {
          setState(
            () =>
                _error = 'Select a compatible size unit for ${attribute.name}.',
          );
          return;
        }
      }
    }
    final uri = Uri.tryParse(_imageUrl.text.trim());
    if (_imageUrl.text.trim().isNotEmpty &&
        (uri == null ||
            !{'http', 'https'}.contains(uri.scheme) ||
            uri.host.isEmpty)) {
      setState(() => _error = 'Enter a valid HTTP or HTTPS image URL.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final enteredUrl = _imageUrl.text.trim();
    String imageToSave;
    if (enteredUrl.isNotEmpty) {
      imageToSave = enteredUrl;
    } else if (_imageExplicitlyRemoved) {
      imageToSave = '';
    } else if (_editing && widget.product != null) {
      imageToSave =
          ProductModel.parseProductImage({
            'productImage': widget.product!.productImage,
          }) ??
          '';
    } else {
      imageToSave = '';
    }
    final fields = <String, dynamic>{
      'brandId': _brand!.id,
      'brand': _brand!.name,
      'categoryId': _category!.id,
      'categoryName': _category!.name,
      'subcategoryId': _subcategory!.id,
      'subcategory': _subcategory!.name,
      if (_masterProductId != null || _editing)
        'masterProductId': _masterProductId,
      'attributeValues': {
        for (final a in _template.where(
          (a) =>
              a.level == 'PRODUCT' &&
              a.id != 'hsnCode' &&
              a.isVisible(_productValues, null, _rows),
        ))
          a.id: _productValues[a.id],
      },
      'hsnCode': _hsn.text.trim(),
      'defaultGstRateBps': (double.tryParse(_gst.text) ?? -1) * 100 ~/ 1,
      if (_editing) 'status': _productStatus,
      'description': _description.text.trim(),
      'quantitySlabs': _productQuantitySlabs.map((s) => s.toMap()).toList(),
      'productImage': imageToSave,
      'imageUrl': imageToSave,
    };
    final variants = <Map<String, dynamic>>[
      for (final row in _rows)
        {
          if (_editing && row['variantId'] != null)
            'variantId': row['variantId'],
          'barcode': row['barcode'],
          'status': row['status'] ?? 'ACTIVE',
          ...{
            for (final key in ['barcode', 'status', 'defaultGstRateBps'])
              key: row[key],
          },
          'attributeValues': {
            for (final a in _template.where(
              (a) =>
                  a.level == 'VARIANT' &&
                  a.id != 'hsnCode' &&
                  a.isVisible(_productValues, row, _rows),
            ))
              a.id: row[a.id],
          },
          'displayName': _template
              .where(
                (a) =>
                    a.level == 'VARIANT' &&
                    a.isVisible(_productValues, row, _rows),
              )
              .map((a) => row[a.id])
              .where((v) => v != null)
              .join(' - '),
          'packSize': row['packSize'],
          'packUnitId':
              _values('UNIT')
                  .where(
                    (u) =>
                        u.id == row['packUnit'] ||
                        u.name == row['packUnit'] ||
                        u.id == row['unit'] ||
                        u.name == row['unit'],
                  )
                  .firstOrNull
                  ?.id ??
              row['_packUnit'] ??
              row['_baseUnit'] ??
              row['_commercialUnit'],
          'unitId': row['_packaging'] == true
              ? row['_baseUnit']
              : (row['soldAs'] != null
                    ? (_values('UNIT')
                              .where(
                                (u) =>
                                    u.id == row['soldAs'] ||
                                    u.name == row['soldAs'],
                              )
                              .firstOrNull
                              ?.id ??
                          row['soldAs'])
                    : (row['unit'] != null
                          ? (_values('UNIT')
                                    .where(
                                      (u) =>
                                          u.id == row['unit'] ||
                                          u.name == row['unit'],
                                    )
                                    .firstOrNull
                                    ?.id ??
                                row['unit'])
                          : row['_commercialUnit'])),
          'baseUnitId': row['_packaging'] == true
              ? row['_baseUnit']
              : (row['soldAs'] != null
                    ? (_values('UNIT')
                              .where(
                                (u) =>
                                    u.id == row['soldAs'] ||
                                    u.name == row['soldAs'],
                              )
                              .firstOrNull
                              ?.id ??
                          row['soldAs'])
                    : (row['unit'] != null
                          ? (_values('UNIT')
                                    .where(
                                      (u) =>
                                          u.id == row['unit'] ||
                                          u.name == row['unit'],
                                    )
                                    .firstOrNull
                                    ?.id ??
                                row['unit'])
                          : row['_commercialUnit'])),
          'commercialUnitId': row['soldAs'] != null
              ? (_values('UNIT')
                        .where(
                          (u) =>
                              u.id == row['soldAs'] || u.name == row['soldAs'],
                        )
                        .firstOrNull
                        ?.id ??
                    row['soldAs'])
              : (row['unit'] != null
                    ? (_values('UNIT')
                              .where(
                                (u) =>
                                    u.id == row['unit'] ||
                                    u.name == row['unit'],
                              )
                              .firstOrNull
                              ?.id ??
                          row['unit'])
                    : row['_commercialUnit']),
          'commercialUnitName':
              _values('UNIT')
                  .where(
                    (u) =>
                        u.id ==
                        (row['soldAs'] != null
                            ? (_values('UNIT')
                                      .where(
                                        (u) =>
                                            u.id == row['soldAs'] ||
                                            u.name == row['soldAs'],
                                      )
                                      .firstOrNull
                                      ?.id ??
                                  row['soldAs'])
                            : (row['unit'] != null
                                  ? (_values('UNIT')
                                            .where(
                                              (u) =>
                                                  u.id == row['unit'] ||
                                                  u.name == row['unit'],
                                            )
                                            .firstOrNull
                                            ?.id ??
                                        row['unit'])
                                  : row['_commercialUnit'])),
                  )
                  .firstOrNull
                  ?.name ??
              (row['soldAs'] ?? row['unit'] as String?),
          'baseQuantityPerCommercialUnit': row['_packaging'] == true
              ? row['_conversion']
              : 1,
        },
    ];

    if (_editing && widget.product != null) {
      final plan = await widget.controller.computeReclassificationPlan(
        productId: widget.product!.productId,
        newCategoryId: _category!.id,
        newSubcategoryId: _subcategory!.id,
        productFields: fields,
        variants: variants,
      );

      if (plan != null && plan.classificationChanged && plan.isDestructive) {
        if (!mounted) return;
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Confirm Reclassification Impact'),
            content: Text(
              '${plan.buildImpactSummary()}\n\nAre you sure you want to save these changes?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Confirm & Save'),
              ),
            ],
          ),
        );

        if (confirm != true) {
          if (mounted) setState(() => _saving = false);
          return;
        }
      }
    }

    if (!mounted) return;
    final ok = await showSyncTaskDialog<bool>(
      context: context,
      title: _editing ? 'Saving Product Updates' : 'Saving New Product',
      task: (updateStatus) async {
        updateStatus('Saving product & variant specifications...');
        final saveOk = !_editing
            ? await widget.controller.createStructuredProduct(
                name: _name.text,
                productFields: fields,
                variants: variants,
              )
            : await widget.controller.saveStructuredProductEdit(
                productId: widget.product!.productId,
                name: _name.text,
                productFields: fields,
                variants: variants,
              );
        if (!saveOk) return false;

        updateStatus('Uploading data to cloud server...');
        final synced = await widget.controller.syncNowWithServer();

        if (synced) {
          updateStatus('Syncing offline database...');
          await widget.controller.loadProducts();
          await widget.controller.loadProductMasters();
          updateStatus('Product saved & synchronized with server!');
        } else {
          updateStatus('Product saved locally in offline database.');
          await widget.controller.loadProducts();
        }
        return true;
      },
    );
    if (!mounted) return;
    if (ok == true) {
      setState(() => _saving = false);
      Navigator.pop(context, true);
      return;
    }

    if (!_editing) {
      final dup = widget.controller.lastProductDuplicateDetails;
      if (dup != null && dup['productId'] != null) {
        final existingId = dup['productId'] as String;
        final existingName = dup['productName'] as String? ?? _name.text;
        final outletName =
            widget.controller.currentOutlet?.outletName ?? 'this outlet';
        final addExisting = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Product Exists in Business'),
            content: Text(
              'A product named "$existingName" already exists in this business, '
              'but is not active in $outletName.\n\n'
              'Would you like to add the existing product to $outletName instead of creating a new one?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                key: const ValueKey('confirm-add-existing-product-to-outlet'),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('Add to $outletName'),
              ),
            ],
          ),
        );
        if (addExisting == true && mounted) {
          final assigned = await widget.controller
              .addExistingProductsToCurrentOutlet([existingId]);
          if (mounted) {
            setState(() => _saving = false);
            if (assigned) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Added "$existingName" to $outletName.'),
                ),
              );
              Navigator.pop(context, true);
              return;
            }
          }
        }
      }
    }

    setState(() {
      _saving = false;
      _error = widget.controller.productsError;
    });
  }

  Widget _identityFields() => NubiFormColumn(
    children: [
      RawAutocomplete<_CentralProductOption>(
        textEditingController: _name,
        focusNode: _nameFocus,
        displayStringForOption: (option) =>
            option.product?.productName ?? option.query,
        optionsBuilder: _centralProductOptions,
        onSelected: (option) {
          final product = option.product;
          if (product != null) {
            unawaited(_selectCentralProduct(product));
          } else {
            setState(() {
              _masterProductId = null;
              _selectedMasterProductName = null;
            });
          }
        },
        fieldViewBuilder: (context, controller, focus, onSubmit) =>
            TextFormField(
              validator: (v) => (v?.trim().length ?? 0) < 2
                  ? 'Enter at least 2 characters'
                  : null,
              controller: controller,
              focusNode: focus,
              onChanged: _onProductNameChanged,
              decoration:
                  const InputDecoration(
                    labelText: 'Product Name *',
                    hintText: 'Search central products or enter a custom name',
                  ).copyWith(
                    suffixIcon: _centralSearchLoading
                        ? const Padding(
                            padding: EdgeInsets.all(14),
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : null,
                    helperText: _centralSearchError,
                  ),
            ),
        optionsViewBuilder: (context, select, options) => Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: (MediaQuery.sizeOf(context).width - 64)
                    .clamp(0, 520)
                    .toDouble(),
                maxHeight: 320,
              ),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final option = options.elementAt(index);
                  final product = option.product;
                  if (product == null) {
                    return ListTile(
                      title: Text('Add "${option.query}" as custom product'),
                      subtitle: const Text(
                        'Continue without a central master reference',
                      ),
                      onTap: () => select(option),
                    );
                  }
                  return ListTile(
                    dense: true,
                    title: Text(product.productName),
                    subtitle: Text(
                      '${product.brandName}  ·  ${product.categoryName} > ${product.subcategoryName}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: product.rangeName == null
                        ? null
                        : Text(product.rangeName!),
                    onTap: () => select(option),
                  );
                },
              ),
            ),
          ),
        ),
      ),
      NubiFieldGrid(
        children: [
          _masterPicker(
            type: 'BRAND',
            selected: _brand,
            options: _values('BRAND'),
            onSelected: (v) => setState(() => _brand = v),
          ),
          _masterPicker(
            type: 'CATEGORY',
            selected: _category,
            options: _values('CATEGORY'),
            onSelected: (v) async {
              if (_category?.id == v?.id) return;
              setState(() {
                _category = v;
                _subcategory = null;
                if (!_editing) {
                  _productValues.clear();
                  _rows
                    ..clear()
                    ..add({});
                }
                _resolvedTemplate = null;
                _appliedTemplate = [];
              });
              await _selectSubcategory(null);
              await _loadMasters(categoryId: v?.id);
            },
          ),
          if (_category != null)
            _masterPicker(
              type: 'SUBCATEGORY',
              selected: _subcategory,
              options: _values('SUBCATEGORY:${_category!.id}'),
              categoryId: _category!.id,
              onSelected: _selectSubcategory,
            ),
        ],
      ),
    ],
  );

  int _moneyOrPercentage(String input) {
    final value = double.tryParse(input);
    return value == null || !value.isFinite ? -1 : (value * 100).round();
  }

  String? _validateGst(String? input) {
    final value = double.tryParse(input ?? '');
    return value == null || !value.isFinite || value < 0 || value > 28
        ? 'Enter a rate from 0 to 28'
        : null;
  }

  Widget _detailsFields() => NubiFormColumn(
    children: [
      NubiFieldGrid(
        children: [
          RawAutocomplete<ProductMasterValue>(
            textEditingController: _hsn,
            focusNode: _hsnFocus,
            displayStringForOption: (v) => v.code ?? v.name,
            optionsBuilder: (value) => _values('HSN').where(
              (v) => '${v.code ?? ''} ${v.name}'.toLowerCase().contains(
                value.text.toLowerCase(),
              ),
            ),
            optionsViewBuilder: (context, select, options) => Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 4,
                child: SizedBox(
                  width: 320,
                  height: 200,
                  child: ListView(
                    children: [
                      for (final option in options)
                        ListTile(
                          title: Text(option.name),
                          subtitle: Text(option.code ?? ''),
                          onTap: () => select(option),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            fieldViewBuilder: (context, controller, focus, submit) =>
                TextFormField(
                  validator: (v) {
                    final value = v?.trim() ?? '';
                    if (value.isEmpty) {
                      return _template.any(
                            (a) => a.id == 'hsnCode' && a.required,
                          )
                          ? 'Enter HSN / SAC'
                          : null;
                    }
                    return RegExp(r'^\d{4,8}$').hasMatch(value)
                        ? null
                        : 'Use 4 to 8 digits';
                  },
                  controller: controller,
                  focusNode: focus,
                  decoration: const InputDecoration(
                    labelText: 'HSN / SAC',
                    hintText: 'Search HSN master or enter 4-8 digits',
                  ),
                ),
          ),
          TextFormField(
            validator: _validateGst,
            controller: _gst,
            decoration: const InputDecoration(
              labelText: 'Default GST (%)',
              hintText: 'e.g. 18',
            ),
            keyboardType: TextInputType.number,
          ),
          if (_editing)
            TextFormField(
              initialValue: widget.product!.productCode,
              readOnly: true,
              decoration: const InputDecoration(
                labelText: 'Product code',
                hintText: 'Automatically generated',
              ),
            ),
          if (_editing)
            DropdownButtonFormField<String>(
              initialValue: _productStatus,
              decoration: const InputDecoration(labelText: 'Product status'),
              items: const [
                DropdownMenuItem(value: 'ACTIVE', child: Text('Active')),
                DropdownMenuItem(value: 'INACTIVE', child: Text('Inactive')),
              ],
              onChanged: (v) => _productStatus = v ?? 'ACTIVE',
            ),
        ],
      ),
      _fields('PRODUCT', _productValues, 'product'),
      TextField(
        controller: _description,
        minLines: 3,
        maxLines: 5,
        decoration: const InputDecoration(
          labelText: 'Description',
          hintText: 'Add optional product description, notes or specifications',
        ),
      ),
    ],
  );

  void _duplicateVariant(Map<String, dynamic> source) {
    final copy = Map<String, dynamic>.from(source)
      ..remove('variantId')
      ..remove('_sku')
      ..remove('barcode');
    copy['_savedAttributes'] = Map<String, dynamic>.from(
      source['_savedAttributes'] as Map? ?? {},
    );
    setState(() => _rows.add(copy));
  }

  String _variantTitle(Map<String, dynamic> row, int index) {
    final unit = _soldAsLabel(row);
    final size = row['packSize']?.toString() ?? '';
    final label = [size, unit].where((s) => s.isNotEmpty && s != 'Item').join(' ');
    return label.isEmpty ? 'Variant ${index + 1}' : 'Variant ${index + 1} ($label)';
  }

  Widget _variantCard(int i) {
    final row = _rows[i];
    return NubiVariantCard(
      key: ValueKey(identityHashCode(row)),
      title: _variantTitle(row, i),
      onDuplicate: () => _duplicateVariant(row),
      onRemove: _rows.length > 1
          ? () => setState(() => _rows.removeAt(i))
          : null,
      child: NubiFormColumn(
        children: [
          _fields('VARIANT', row, 'sku-${identityHashCode(row)}'),
          NubiFieldGrid(
            children: [
              TextFormField(
                initialValue: row['_sku'] as String?,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'SKU *',
                  hintText: 'Automatically generated on save',
                ),
              ),
              TextFormField(
                initialValue: row['barcode'] as String?,
                decoration: const InputDecoration(
                  labelText: 'Barcode',
                  hintText: 'Scan or enter barcode',
                ),
                onChanged: (v) => row['barcode'] = v,
              ),
            ],
          ),
          _sellingFields(row),
          NubiFieldGrid(
            children: [
              DropdownButtonFormField<String>(
                initialValue: row['status'] as String? ?? 'ACTIVE',
                decoration: const InputDecoration(labelText: 'Status *'),
                items: const [
                  DropdownMenuItem(value: 'ACTIVE', child: Text('Active')),
                  DropdownMenuItem(value: 'INACTIVE', child: Text('Inactive')),
                ],
                onChanged: (v) => row['status'] = v,
              ),
              TextButton.icon(
                onPressed: () => setState(() {
                  row['_gstOverrideVisible'] =
                      row['_gstOverrideVisible'] != true;
                  if (row['_gstOverrideVisible'] != true) {
                    row['defaultGstRateBps'] = null;
                  }
                }),
                icon: const Icon(Icons.tune, size: 18),
                label: Text(
                  row['_gstOverrideVisible'] == true
                      ? 'Use product GST'
                      : 'Override GST',
                ),
              ),
              if (row['_gstOverrideVisible'] == true)
                TextFormField(
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? null : _validateGst(v),
                  initialValue: row['defaultGstRateBps'] == null
                      ? ''
                      : ((row['defaultGstRateBps'] as num) / 100).toString(),
                  decoration: const InputDecoration(
                    labelText: 'Variant GST (%)',
                    hintText: 'Blank inherits product Default GST',
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (v) => row['defaultGstRateBps'] = v.trim().isEmpty
                      ? null
                      : _moneyOrPercentage(v),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _quantitySlabsSection() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF93C5FD), width: 1.5),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.discount_outlined, size: 20, color: Colors.blue.shade700),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Automatically apply tiered discounts during billing when customers purchase bulk quantities (e.g. 50-100 pcs: 5%, 101-150 pcs: 8%).',
                  style: TextStyle(fontSize: 13, color: Colors.black87),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: () => _promptAddQuantitySlab(context),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add Tier Slab'),
              ),
            ],
          ),
          if (_productQuantitySlabs.isNotEmpty) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Container(
                color: Colors.white,
                child: Table(
                  border: TableBorder.all(color: Colors.grey.shade200),
                  columnWidths: const {
                    0: FlexColumnWidth(2),
                    1: FlexColumnWidth(2),
                    2: FlexColumnWidth(2.5),
                    3: FlexColumnWidth(1),
                  },
                  children: [
                    TableRow(
                      decoration: BoxDecoration(color: Colors.grey.shade100),
                      children: const [
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Text('Quantity Range', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        ),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Text('Discount Type', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        ),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Text('Discount Value', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        ),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Text('Action', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        ),
                      ],
                    ),
                    for (var i = 0; i < _productQuantitySlabs.length; i++)
                      _buildSlabTableRow(i),
                  ],
                ),
              ),
            ),
          ] else ...[
            const SizedBox(height: 12),
            Text(
              'No volume discount tiers added yet. Click "Add Tier Slab" to create one.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
            ),
          ],
        ],
      ),
    );
  }

  TableRow _buildSlabTableRow(int index) {
    final slab = _productQuantitySlabs[index];
    final rangeText = slab.maxQty != null
        ? '${slab.minQty} - ${slab.maxQty} units'
        : '${slab.minQty}+ units (and above)';
    final typeText = slab.discountType == 'PERCENTAGE'
        ? 'Percentage (%)'
        : 'Flat (₹ per unit)';
    final valueText = slab.discountType == 'PERCENTAGE'
        ? '${slab.discountValue}%'
        : '₹${slab.discountValue.toStringAsFixed(2)} / unit';

    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Text(rangeText, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Text(typeText, style: const TextStyle(fontSize: 13)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: Text(
              valueText,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green.shade800),
            ),
          ),
        ),
        Center(
          child: IconButton(
            icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
            tooltip: 'Remove Slab',
            onPressed: () {
              setState(() {
                _productQuantitySlabs.removeAt(index);
              });
            },
          ),
        ),
      ],
    );
  }

  Future<void> _promptAddQuantitySlab(BuildContext context) async {
    final minController = TextEditingController(text: '50');
    final maxController = TextEditingController(text: '100');
    final valController = TextEditingController(text: '5');
    var discountType = 'PERCENTAGE';
    var isNoMaxLimit = false;

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.add_shopping_cart, color: Colors.blue),
              SizedBox(width: 8),
              Text('Add Quantity Discount Tier'),
            ],
          ),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Define a quantity range and the discount to apply automatically:',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: minController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: const InputDecoration(
                            labelText: 'Min Quantity *',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: maxController,
                          enabled: !isNoMaxLimit,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: InputDecoration(
                            labelText: isNoMaxLimit ? 'No Upper Limit' : 'Max Quantity',
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Checkbox(
                        value: isNoMaxLimit,
                        onChanged: (val) {
                          setDialogState(() {
                            isNoMaxLimit = val ?? false;
                            if (isNoMaxLimit) maxController.clear();
                          });
                        },
                      ),
                      const Text('No upper limit (e.g. 150+ units)', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: discountType,
                    decoration: const InputDecoration(
                      labelText: 'Discount Type',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'PERCENTAGE',
                        child: Text('Percentage Discount (%)'),
                      ),
                      DropdownMenuItem(
                        value: 'FLAT_PER_UNIT',
                        child: Text('Flat Discount Per Unit (₹)'),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => discountType = val);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: valController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: discountType == 'PERCENTAGE'
                          ? 'Discount Percentage (e.g. 5 for 5%)'
                          : 'Discount Rupees Per Unit (e.g. 10 for ₹10/unit)',
                      border: const OutlineInputBorder(),
                      isDense: true,
                      prefixText: discountType == 'FLAT_PER_UNIT' ? '₹ ' : null,
                      suffixText: discountType == 'PERCENTAGE' ? '%' : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final min = int.tryParse(minController.text.trim());
                final max = isNoMaxLimit ? null : int.tryParse(maxController.text.trim());
                final value = double.tryParse(valController.text.trim());

                if (min == null || min <= 0) return;
                if (!isNoMaxLimit && (max == null || max < min)) return;
                if (value == null || value <= 0) return;

                setState(() {
                  _productQuantitySlabs.add(
                    QuantityDiscountSlab(
                      minQty: min,
                      maxQty: max,
                      discountType: discountType,
                      discountValue: value,
                    ),
                  );
                  _productQuantitySlabs.sort((a, b) => a.minQty.compareTo(b.minQty));
                });
                Navigator.pop(dialogCtx);
              },
              child: const Text('Add Slab'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _saveButton() => FilledButton.icon(
    style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
    onPressed:
        _saving ||
            _loading ||
            _templateLoading ||
            (_subcategory != null && !_hasUsableTemplate)
        ? null
        : _save,
    icon: _saving
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.check, size: 20),
    label: Text(_saving ? 'Saving…' : 'Save Product'),
  );

  @override
  Widget build(BuildContext context) => NubiFormTheme(
    child: Builder(
      builder: (context) {
        final mobile = MediaQuery.sizeOf(context).width < 650;
        final validationBannerVisible =
            _error != null || widget.controller.productMastersError != null;
        final templateBannerVisible =
            _subcategory != null && !_templateLoading && !_hasUsableTemplate;
        return Scaffold(
          appBar: AppBar(
            title: Text(
              _editing ? 'Edit Product' : 'Add Product',
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            actions: [
              if (!mobile)
                Padding(
                  padding: const EdgeInsets.only(right: 24),
                  child: _saveButton(),
                ),
            ],
          ),
          bottomNavigationBar: mobile
              ? SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: _saveButton(),
                  ),
                )
              : null,
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: EdgeInsets.all(mobile ? 16 : 28),
                  children: [
                    if (_loading || _saving || _templateLoading)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 20),
                        child: LinearProgressIndicator(),
                      ),
                    if (validationBannerVisible)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: MaterialBanner(
                          content: Text(
                            _error ?? widget.controller.productMastersError!,
                          ),
                          actions: [
                            TextButton(
                              onPressed: () async {
                                setState(() => _error = null);
                                await _loadMasters(categoryId: _category?.id);
                                if (_subcategory != null) {
                                  await _selectSubcategory(_subcategory);
                                }
                              },
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    _section('Product Identity', _identityFields()),
                    if (_subcategory == null)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 28),
                        child: Text(
                          'Select a subcategory to see product details and sellable variations.',
                        ),
                      ),
                    if (templateBannerVisible)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 28),
                        child: Card(
                          color: Theme.of(context).colorScheme.errorContainer
                              .withValues(alpha: 0.3),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.warning_amber_rounded,
                                  color: Theme.of(context).colorScheme.error,
                                  size: 28,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Product template unavailable for this subcategory.',
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onErrorContainer,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    if (_subcategory != null &&
                        !_templateLoading &&
                        _hasUsableTemplate) ...[
                      _section('Product Specifications', _detailsFields()),
                      _section(
                        'Quantity-Based Volume Discounts (Optional)',
                        _quantitySlabsSection(),
                      ),
                      _section(
                        'Sellable Variants / SKUs',
                        NubiFormColumn(
                          gap: 24,
                          children: [
                            for (var i = 0; i < _rows.length; i++)
                              _variantCard(i),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: OutlinedButton.icon(
                                onPressed: () => setState(() {
                                  final row = <String, dynamic>{
                                    for (final a in _template.where(
                                      (a) =>
                                          a.level == 'VARIANT' &&
                                          a.defaultValue != null,
                                    ))
                                      a.id: a.defaultValue,
                                  };
                                  _rows.add(row);
                                  _applyUnitDefault(row);
                                }),
                                icon: const Icon(Icons.add),
                                label: const Text('Add Variant'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (_template.any((a) => a.section == 'TECHNICAL'))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 24),
                        child: Card(
                          child: ExpansionTile(
                            title: const Text('Technical Details'),
                            initiallyExpanded: false,
                            maintainState: true,
                            childrenPadding: const EdgeInsets.all(20),
                            children: [
                              _fields(
                                'PRODUCT',
                                _productValues,
                                'technical',
                                section: 'TECHNICAL',
                              ),
                              for (final row in _rows)
                                _fields(
                                  'VARIANT',
                                  row,
                                  'technical-${identityHashCode(row)}',
                                  section: 'TECHNICAL',
                                ),
                            ],
                          ),
                        ),
                      ),
                    _section(
                      'Product Image',
                      NubiImagePicker(
                        hasImage: _imageUrl.text.isNotEmpty,
                        onPaste: _pasteImageUrl,
                        onRemove: () => setState(() {
                          _imageUrl.clear();
                          _imageExplicitlyRemoved = true;
                        }),
                        preview: _imageUrl.text.isEmpty
                            ? const DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.all(
                                    Radius.circular(12),
                                  ),
                                ),
                                child: Center(
                                  child: Icon(
                                    Icons.add_photo_alternate_outlined,
                                    size: 48,
                                  ),
                                ),
                              )
                            : ProductThumbnail(
                                url: _imageUrl.text,
                                name: _name.text,
                                editor: true,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

class _CentralProductOption {
  const _CentralProductOption(this.product, this.query);

  const _CentralProductOption.custom(this.query) : product = null;

  final CentralProductMaster? product;
  final String query;
}

class _ProductMasterPicker extends StatefulWidget {
  const _ProductMasterPicker({
    required this.label,
    required this.selected,
    required this.options,
    required this.canAdd,
    required this.onSelected,
    required this.onAdd,
    this.emptyMessage,
    this.validator,
  });

  final String label;
  final ProductMasterValue? selected;
  final List<ProductMasterValue> options;
  final bool canAdd;
  final ValueChanged<ProductMasterValue?> onSelected;
  final VoidCallback onAdd;
  final String? emptyMessage;
  final String? Function(ProductMasterValue?)? validator;

  @override
  State<_ProductMasterPicker> createState() => _ProductMasterPickerState();
}

class _ProductMasterPickerState extends State<_ProductMasterPicker> {
  late final TextEditingController _text;
  final _focus = FocusNode();
  // Invalidate queued writes when a newer selection arrives.
  int _textUpdateVersion = 0;
  String get label => widget.label;
  ProductMasterValue? get selected => widget.selected;
  List<ProductMasterValue> get options => widget.options;
  bool get canAdd => widget.canAdd;
  ValueChanged<ProductMasterValue?> get onSelected => widget.onSelected;
  VoidCallback get onAdd => widget.onAdd;
  String? get emptyMessage => widget.emptyMessage;
  String? Function(ProductMasterValue?)? get validator => widget.validator;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: selected?.name ?? '');
  }

  @override
  void didUpdateWidget(covariant _ProductMasterPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    final selectionChanged =
        oldWidget.selected?.id != selected?.id ||
        oldWidget.selected?.name != selected?.name;
    final optionsChanged =
        oldWidget.options.map((v) => v.id).join(',') !=
        options.map((v) => v.id).join(',');
    if (!selectionChanged && !optionsChanged) return;

    final version = ++_textUpdateVersion;
    final nextText = selected?.name ?? (optionsChanged ? '' : null);
    if (nextText == null || _text.text == nextText) return;
    final previousValue = _text.value;
    // TextFormField notifies its ancestor Form when the controller changes.
    // This picker can update inside LayoutBuilder, so wait until layout ends.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          version != _textUpdateVersion ||
          _text.value != previousValue) {
        return;
      }
      _text.value = TextEditingValue(
        text: nextText,
        selection: TextSelection.collapsed(offset: nextText.length),
      );
    });
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) => Row(
      children: [
        Expanded(
          child: RawAutocomplete<ProductMasterValue>(
            textEditingController: _text,
            focusNode: _focus,
            displayStringForOption: (value) => value.name,
            optionsBuilder: (text) {
              final query = text.text.trim().toLowerCase();
              if (query.isEmpty) return options;
              return options.where(
                (value) => '${value.name} ${value.code ?? ''}'
                    .toLowerCase()
                    .contains(query),
              );
            },
            onSelected: onSelected,
            fieldViewBuilder: (context, textController, focusNode, onSubmit) =>
                TextFormField(
                  validator: (_) => validator?.call(selected),
                  controller: textController,
                  focusNode: focusNode,
                  enableInteractiveSelection: true,
                  onChanged: (value) {
                    if (selected != null && value != selected!.name) {
                      onSelected(null);
                    }
                  },
                  decoration: InputDecoration(
                    labelText: label,
                    hintText: options.isEmpty
                        ? (emptyMessage ?? 'No values yet')
                        : switch (label.replaceAll(' *', '')) {
                            'Brand / Company' => 'Search or select brand',
                            'Category' => 'Select product category',
                            'Subcategory' => 'Select product subcategory',
                            'Selling Unit' ||
                            'Sold As' => 'Search or select sold as unit',
                            _ =>
                              'Search or select ${label.replaceAll(' *', '').toLowerCase()}',
                          },
                    suffixIcon: const Icon(Icons.search, size: 18),
                  ),
                ),
            optionsViewBuilder: (context, onSelect, values) => Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 5,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: 260,
                    maxWidth: bounds.maxWidth - (canAdd ? 48 : 0),
                  ),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: values.length,
                    itemBuilder: (context, index) {
                      final value = values.elementAt(index);
                      return ListTile(
                        dense: true,
                        title: Text(value.name),
                        subtitle: value.code == null ? null : Text(value.code!),
                        onTap: () => onSelect(value),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
        if (canAdd)
          IconButton(
            tooltip: 'Add ${label.replaceAll(' *', '')}',
            onPressed: onAdd,
            icon: const Icon(Icons.add_circle_outline),
          ),
      ],
    ),
  );
}

Future<bool> showQuickProductDialog(
  BuildContext context,
  AppController controller,
) async =>
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _StructuredProductFormPage(controller: controller),
      ),
    ) ==
    true;
