import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../data/catalogue/catalogue_contract.dart';
import '../../data/models/product_model.dart';
import '../../data/models/product_variant_model.dart';
import '../../l10n/app_localizations.dart';
import '../../data/models/stock_transaction_audit_model.dart';
import '../procurement/purchase_entry_page.dart';
import '../app_controller.dart';
import '../products/product_thumbnail.dart';

enum _InventoryViewMode { table, cards }

enum _InventorySortOption {
  nameAsc,
  nameDesc,
  stockAsc,
  stockDesc,
  priceDesc,
  recent,
}

class InventoryDashboardPage extends StatefulWidget {
  const InventoryDashboardPage({
    super.key,
    required this.controller,
    required this.onOpenProducts,
  });

  final AppController controller;
  final VoidCallback onOpenProducts;

  @override
  State<InventoryDashboardPage> createState() => _InventoryDashboardPageState();
}

class _InventoryDashboardPageState extends State<InventoryDashboardPage> {
  final _search = TextEditingController();
  String _status = 'ALL';
  String _selectedCategory = 'ALL';
  _InventorySortOption _sortOption = _InventorySortOption.nameAsc;
  _InventoryViewMode _viewMode = _InventoryViewMode.table;
  DateTime? _updatedSince;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.controller.loadProducts();
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _search.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _refresh() async {
    setState(() => _isRefreshing = true);
    try {
      await widget.controller.loadProducts();
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  Future<void> _exportCsv(
    List<_InventoryRow> rows,
    AppLocalizations? l10n,
  ) async {
    final csv = StringBuffer(
      'Product,Variant,SKU,Barcode,Brand,Category,Unit,Selling Price (INR),MRP (INR),Available Stock,Reorder Level,Status,Valuation (INR)\n',
    );
    for (final row in rows) {
      csv.writeln(
        [
          _csv(row.product.name),
          _csv(row.variant.name),
          _csv(row.variant.sku ?? ''),
          _csv(row.variant.barcode ?? ''),
          _csv(row.product.brand ?? ''),
          _csv(row.product.category ?? ''),
          _csv(
            _formatUnit(row.variant.baseUnitId, row.variant.commercialUnitName),
          ),
          (row.variant.sellingPrice / 100).toStringAsFixed(2),
          (row.variant.mrp / 100).toStringAsFixed(2),
          _formatStock(row.stock),
          row.variant.reorderLevel,
          row.status,
          row.valuationRupees.toStringAsFixed(2),
        ].join(','),
      );
    }
    final path = await FilePicker.saveFile(
      dialogTitle: l10n?.exportCsv ?? 'Export inventory CSV',
      fileName: 'inventory_export_${DateTime.now().millisecondsSinceEpoch}.csv',
      bytes: utf8.encode(csv.toString()),
    );
    if (path != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n?.inventoryExportedSuccess ??
                'Inventory exported successfully.',
          ),
          backgroundColor: const Color(0xFF16A34A),
        ),
      );
    }
  }

  String _csv(String value) => '"${value.replaceAll('"', '""')}"';

  Future<void> _importCsv(AppLocalizations? l10n) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    if (!mounted || result.isEmpty) return;
    final bytes = await result.single.readAsBytes();
    final text = utf8.decode(bytes);
    final lines = const LineSplitter().convert(text);
    final errors = <String>[];
    if (lines.isEmpty) errors.add('The CSV file is empty.');
    if (lines.isNotEmpty && !lines.first.toLowerCase().contains('product')) {
      errors.add('The first row must contain the Product column header.');
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF132B45).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.upload_file_rounded,
                color: Color(0xFF132B45),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              l10n?.importPreviewTitle ?? 'Import CSV Preview',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (errors.isEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF16A34A).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFF16A34A).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.check_circle_outline,
                        color: Color(0xFF16A34A),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${lines.length - 1} valid row(s) detected in file.',
                          style: const TextStyle(
                            color: Color(0xFF16A34A),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Product batch verification complete. Proceeding with import will update catalog inventory records according to matched SKUs.',
                  style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDC2626).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFFDC2626).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: Color(0xFFDC2626),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          errors.join('\n'),
                          style: const TextStyle(
                            color: Color(0xFFDC2626),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n?.close ?? 'Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final l10n = AppLocalizations.of(context);

    if (!controller.canManageProducts()) {
      return Center(
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.lock_person_outlined,
                size: 56,
                color: Color(0xFFDC2626),
              ),
              const SizedBox(height: 16),
              Text(
                l10n?.noAccessInventory ?? 'You do not have permission to access the Inventory module.',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final allRows = _rows(controller);
    final filteredRows = allRows.where(_matches).toList()..sort(_comparator);

    final totalCount = allRows.length;
    final inStockCount = allRows.where((r) => r.status == 'IN_STOCK').length;
    final lowStockCount = allRows.where((r) => r.status == 'LOW').length;
    final outOfStockCount = allRows.where((r) => r.status == 'OUT').length;
    final inactiveCount = allRows.where((r) => r.status == 'INACTIVE').length;

    double totalValuation = 0.0;
    for (final r in allRows) {
      totalValuation += r.valuationRupees;
    }

    // Unique categories for filter dropdown
    final categories = <String>{'ALL'};
    for (final r in allRows) {
      final cat = r.product.category?.trim();
      if (cat != null && cat.isNotEmpty) categories.add(cat);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 720;
        final isTablet =
            constraints.maxWidth >= 720 && constraints.maxWidth < 1100;

        return SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 12 : 24,
            vertical: isMobile ? 12 : 20,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Header Bar with Title, Outlet Badge, Language Switcher & Primary Actions
              _buildHeaderBar(context, l10n, isMobile),
              const SizedBox(height: 16),

              // 2. Executive KPI Intelligence Summary Cards
              _buildKpiSection(
                context,
                l10n: l10n,
                isMobile: isMobile,
                isTablet: isTablet,
                totalCount: totalCount,
                inStockCount: inStockCount,
                lowStockCount: lowStockCount,
                outOfStockCount: outOfStockCount,
                inactiveCount: inactiveCount,
                totalValuation: totalValuation,
              ),
              const SizedBox(height: 16),

              // 3. Search, Filter Chips, Sort & View Mode Console
              _buildFilterConsole(
                context,
                l10n: l10n,
                categories: categories,
                isMobile: isMobile,
                filteredCount: filteredRows.length,
                totalCount: totalCount,
              ),
              const SizedBox(height: 16),

              // 4. Main Inventory Data Content (Table or Cards View)
              if (controller.productsLoading && allRows.isEmpty)
                Container(
                  height: 320,
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
                      Text('Loading store catalog & stock balances...'),
                    ],
                  ),
                )
              else if (filteredRows.isEmpty)
                _buildEmptyState(context, l10n)
              else if (_viewMode == _InventoryViewMode.table && !isMobile)
                _buildTableView(context, filteredRows, l10n)
              else
                _buildCardsView(context, filteredRows, l10n),
            ],
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // HEADER BAR & CONTROLS
  // ---------------------------------------------------------------------------

  Widget _buildHeaderBar(
    BuildContext context,
    AppLocalizations? l10n,
    bool isMobile,
  ) {
    final outletName =
        widget.controller.currentOutlet?.outletName ?? 'Default Store';
    final currentCode = widget.controller.currentLocale.languageCode;

    final langLabel = switch (currentCode) {
      'hi' => 'हिंदी',
      'bn' => 'বাংলা',
      _ => 'English',
    };

    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 12,
      children: [
        // Title & Location
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: isMobile ? 350 : 700),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF132B45),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.inventory_2_rounded,
                      color: Color(0xFFC18B35),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      l10n?.inventoryDashboardTitle ??
                          'Inventory Intelligence & Operations',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F172A),
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    l10n?.inventoryDashboardSubtitle ?? 'Real-time stock monitoring, valuations, reorder alerts & movement management',
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 12,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
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
                          outletName,
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
              ),
            ],
          ),
        ),

        // Action Toolbar: Language Switcher, Refresh, Import, Export, Add New Item
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // Language selector button
            PopupMenuButton<Locale>(
              tooltip: l10n?.language ?? 'Language / भाषा / ভাষা',
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
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
              tooltip: l10n?.refreshTooltip ?? 'Refresh stock data',
              icon: _isRefreshing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded, size: 18),
              onPressed: _isRefreshing ? null : _refresh,
              style: IconButton.styleFrom(
                backgroundColor: Colors.white,
                side: const BorderSide(color: Color(0xFFCBD5E1)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),

            // Import CSV
            OutlinedButton.icon(
              onPressed: () => _importCsv(l10n),
              icon: const Icon(Icons.upload_file_outlined, size: 16),
              label: Text(l10n?.importCsv ?? 'Import CSV'),
              style: OutlinedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF0F172A),
                side: const BorderSide(color: Color(0xFFCBD5E1)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
            ),

            // Export CSV
            OutlinedButton.icon(
              onPressed: () {
                final rows = _rows(widget.controller).where(_matches).toList();
                if (rows.isNotEmpty) _exportCsv(rows, l10n);
              },
              icon: const Icon(Icons.download_outlined, size: 16),
              label: Text(l10n?.exportCsv ?? 'Export CSV'),
              style: OutlinedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF0F172A),
                side: const BorderSide(color: Color(0xFFCBD5E1)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
            ),

            // Add New Item Button
            FilledButton.icon(
              onPressed: widget.onOpenProducts,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(
                l10n?.addNewItem ?? 'Add New Product',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF132B45),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                elevation: 1,
              ),
            ),
          ],
        ),
      ],
    );
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

  // ---------------------------------------------------------------------------
  // EXECUTIVE KPI CARDS SECTION
  // ---------------------------------------------------------------------------

  Widget _buildKpiSection(
    BuildContext context, {
    required AppLocalizations? l10n,
    required bool isMobile,
    required bool isTablet,
    required int totalCount,
    required int inStockCount,
    required int lowStockCount,
    required int outOfStockCount,
    required int inactiveCount,
    required double totalValuation,
  }) {
    final healthRatio = totalCount > 0
        ? ((inStockCount / totalCount) * 100).round()
        : 100;

    final cards = [
      // 1. Total Products
      _KpiCard(
        title: l10n?.totalItems ?? 'Total Products / SKUs',
        value: totalCount.toString(),
        subtitle: '$totalCount Active • $inactiveCount Inactive',
        icon: Icons.inventory_2_rounded,
        accentColor: const Color(0xFF2563EB),
        isSelected: _status == 'ALL',
        onTap: () => setState(() => _status = 'ALL'),
      ),

      // 2. Optimal In-Stock
      _KpiCard(
        title: l10n?.inStockItems ?? 'Optimal Stock',
        value: inStockCount.toString(),
        subtitle:
            '$healthRatio% ${l10n?.healthyCatalogRatio ?? "healthy stock"}',
        icon: Icons.check_circle_rounded,
        accentColor: const Color(0xFF16A34A),
        isSelected: _status == 'IN_STOCK',
        onTap: () => setState(() => _status = 'IN_STOCK'),
      ),

      // 3. Low Stock Alerts
      _KpiCard(
        title: l10n?.lowStockAlertCount ?? 'Low Stock Alerts',
        value: lowStockCount.toString(),
        subtitle: l10n?.reorderRequired ?? 'Action Required',
        icon: Icons.warning_amber_rounded,
        accentColor: const Color(0xFFD97706),
        isAlert: lowStockCount > 0,
        isSelected: _status == 'LOW',
        onTap: () => setState(() => _status = 'LOW'),
      ),

      // 4. Out of Stock
      _KpiCard(
        title: l10n?.outOfStock ?? 'Out of Stock',
        value: outOfStockCount.toString(),
        subtitle: '0 units remaining',
        icon: Icons.error_outline_rounded,
        accentColor: const Color(0xFFDC2626),
        isAlert: outOfStockCount > 0,
        isSelected: _status == 'OUT',
        onTap: () => setState(() => _status = 'OUT'),
      ),

      // 5. Estimated Stock Valuation
      _KpiCard(
        title: l10n?.estimatedInventoryValue ?? 'Estimated Stock Value',
        value: _formatCurrency(totalValuation),
        subtitle: 'Retail catalog value',
        icon: Icons.account_balance_wallet_rounded,
        accentColor: const Color(0xFFC18B35),
        isSelected: false,
        onTap: null,
      ),
    ];

    if (isMobile) {
      return Column(
        children: cards
            .map(
              (c) =>
                  Padding(padding: const EdgeInsets.only(bottom: 8), child: c),
            )
            .toList(),
      );
    }

    if (isTablet) {
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: cards.map((c) => SizedBox(width: 220, child: c)).toList(),
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

  // ---------------------------------------------------------------------------
  // FILTER, SEARCH, SORT & VIEW TOGGLE CONSOLE
  // ---------------------------------------------------------------------------

  Widget _buildFilterConsole(
    BuildContext context, {
    required AppLocalizations? l10n,
    required Set<String> categories,
    required bool isMobile,
    required int filteredCount,
    required int totalCount,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Row 1: Search box + Status Chips + Category Dropdown
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              // Search Input Box
              SizedBox(
                width: isMobile ? double.infinity : 340,
                child: TextField(
                  controller: _search,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      size: 20,
                      color: Color(0xFF64748B),
                    ),
                    suffixIcon: _search.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: () {
                              _search.clear();
                              setState(() {});
                            },
                          )
                        : null,
                    hintText:
                        l10n?.searchInventoryPlaceholder ??
                        'Search by product name, SKU, barcode...',
                    hintStyle: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF94A3B8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    isDense: true,
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                        color: Color(0xFF132B45),
                        width: 1.5,
                      ),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),

              // Status Filter Segmented Control
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildStatusChip(
                      label: l10n?.filterAll ?? 'All',
                      value: 'ALL',
                      color: const Color(0xFF2563EB),
                    ),
                    const SizedBox(width: 6),
                    _buildStatusChip(
                      label: l10n?.filterInStock ?? 'In Stock',
                      value: 'IN_STOCK',
                      color: const Color(0xFF16A34A),
                    ),
                    const SizedBox(width: 6),
                    _buildStatusChip(
                      label: l10n?.filterLowStock ?? 'Low Stock',
                      value: 'LOW',
                      color: const Color(0xFFD97706),
                    ),
                    const SizedBox(width: 6),
                    _buildStatusChip(
                      label: l10n?.filterOutOfStock ?? 'Out of Stock',
                      value: 'OUT',
                      color: const Color(0xFFDC2626),
                    ),
                    const SizedBox(width: 6),
                    _buildStatusChip(
                      label: l10n?.filterInactive ?? 'Inactive',
                      value: 'INACTIVE',
                      color: const Color(0xFF64748B),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 12),

          // Row 2: Category Filter, Time Range, Sort Dropdown & View Mode Switcher
          Wrap(
            spacing: 12,
            runSpacing: 10,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Left: Category & Updated Since filters
              Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // Category Dropdown
                  if (categories.length > 2)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFCBD5E1)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedCategory,
                          isDense: true,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1E293B),
                          ),
                          items: categories.map((cat) {
                            return DropdownMenuItem(
                              value: cat,
                              child: Text(
                                cat == 'ALL'
                                    ? (l10n?.category ?? 'Category: All')
                                    : cat,
                              ),
                            );
                          }).toList(),
                          onChanged: (val) =>
                              setState(() => _selectedCategory = val ?? 'ALL'),
                        ),
                      ),
                    ),

                  // Updated Time Filter
                  FilterChip(
                    selected: _updatedSince != null,
                    label: Text(
                      _updatedSince == null
                          ? (l10n?.allTime ?? 'All Time')
                          : (l10n?.last30Days ?? 'Last 30 days'),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: _updatedSince != null
                            ? FontWeight.bold
                            : FontWeight.w500,
                        color: _updatedSince != null
                            ? const Color(0xFF132B45)
                            : const Color(0xFF64748B),
                      ),
                    ),
                    avatar: Icon(
                      Icons.history_rounded,
                      size: 14,
                      color: _updatedSince != null
                          ? const Color(0xFF132B45)
                          : const Color(0xFF64748B),
                    ),
                    onSelected: (selected) {
                      setState(() {
                        _updatedSince = selected
                            ? DateTime.now().subtract(const Duration(days: 30))
                            : null;
                      });
                    },
                    backgroundColor: const Color(0xFFF8FAFC),
                    selectedColor: const Color(0xFFC18B35)
                        .withValues(alpha: 0.15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    side: BorderSide(
                      color: _updatedSince != null
                          ? const Color(0xFFC18B35)
                          : const Color(0xFFCBD5E1),
                    ),
                  ),

                  // Results Count Indicator
                  Text(
                    '$filteredCount of $totalCount items',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),

              // Right: Sort By + View Mode (Table / Cards)
              Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // Sort By Dropdown
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFCBD5E1)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<_InventorySortOption>(
                        value: _sortOption,
                        isDense: true,
                        icon: const Icon(
                          Icons.sort_rounded,
                          size: 16,
                          color: Color(0xFF64748B),
                        ),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1E293B),
                        ),
                        items: [
                          DropdownMenuItem(
                            value: _InventorySortOption.nameAsc,
                            child: Text(l10n?.sortNameAsc ?? 'Name (A to Z)'),
                          ),
                          DropdownMenuItem(
                            value: _InventorySortOption.nameDesc,
                            child: Text(l10n?.sortNameDesc ?? 'Name (Z to A)'),
                          ),
                          DropdownMenuItem(
                            value: _InventorySortOption.stockAsc,
                            child: Text(
                              l10n?.sortStockAsc ?? 'Stock (Low to High)',
                            ),
                          ),
                          DropdownMenuItem(
                            value: _InventorySortOption.stockDesc,
                            child: Text(
                              l10n?.sortStockDesc ?? 'Stock (High to Low)',
                            ),
                          ),
                          DropdownMenuItem(
                            value: _InventorySortOption.priceDesc,
                            child: Text(
                              l10n?.sortPriceDesc ?? 'Price (High to Low)',
                            ),
                          ),
                          DropdownMenuItem(
                            value: _InventorySortOption.recent,
                            child: Text(
                              l10n?.sortRecentlyUpdated ?? 'Recently Updated',
                            ),
                          ),
                        ],
                        onChanged: (opt) {
                          if (opt != null) setState(() => _sortOption = opt);
                        },
                      ),
                    ),
                  ),

                  // Table vs Cards toggle
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFCBD5E1)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildViewModeButton(
                          icon: Icons.table_rows_rounded,
                          tooltip: l10n?.viewModeTable ?? 'Table View',
                          isSelected: _viewMode == _InventoryViewMode.table,
                          onTap: () => setState(
                            () => _viewMode = _InventoryViewMode.table,
                          ),
                        ),
                        _buildViewModeButton(
                          icon: Icons.grid_view_rounded,
                          tooltip: l10n?.viewModeCards ?? 'Card View',
                          isSelected: _viewMode == _InventoryViewMode.cards,
                          onTap: () => setState(
                            () => _viewMode = _InventoryViewMode.cards,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip({
    required String label,
    required String value,
    required Color color,
  }) {
    final isSelected = _status == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => setState(() => _status = value),
      selectedColor: color.withValues(alpha: 0.15),
      backgroundColor: Colors.white,
      side: BorderSide(
        color: isSelected ? color : const Color(0xFFCBD5E1),
        width: isSelected ? 1.5 : 1,
      ),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
        color: isSelected ? color : const Color(0xFF475569),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    );
  }

  Widget _buildViewModeButton({
    required IconData icon,
    required String tooltip,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Icon(
            icon,
            size: 17,
            color: isSelected
                ? const Color(0xFF132B45)
                : const Color(0xFF64748B),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // MODERN DATA TABLE VIEW (DESKTOP & TABLET ERP)
  // ---------------------------------------------------------------------------

  Widget _buildTableView(
    BuildContext context,
    List<_InventoryRow> rows,
    AppLocalizations? l10n,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tableWidth = constraints.maxWidth < 960
            ? 960.0
            : constraints.maxWidth;
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: tableWidth,
              child: Column(
                children: [
                  // Table Header
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF8FAFC),
                      border: Border(
                        bottom: BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 4,
                          child: Text(
                            l10n?.productNameCol ?? 'Product & Brand',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                              color: Color(0xFF475569),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            '${l10n?.sku ?? "SKU"} / ${l10n?.barcode ?? "Barcode"}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                              color: Color(0xFF475569),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            l10n?.unit ?? 'Unit / Pack',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                              color: Color(0xFF475569),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            l10n?.sellingPriceLabel ?? 'Selling Price',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                              color: Color(0xFF475569),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            l10n?.currentStock ?? 'Stock & Level',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                              color: Color(0xFF475569),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            l10n?.stockValuationLabel ?? 'Valuation',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                              color: Color(0xFF475569),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              l10n?.action ?? 'Actions',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                                color: Color(0xFF475569),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Table Rows
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: rows.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, color: Color(0xFFF1F5F9)),
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      return _buildTableRow(
                        context,
                        row,
                        l10n,
                        isEven: index.isEven,
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTableRow(
    BuildContext context,
    _InventoryRow row,
    AppLocalizations? l10n, {
    required bool isEven,
  }) {
    final statusColor = _statusColor(row.status);
    final statusLabel = _statusLabel(row.status, l10n);

    // Stock ratio against reorder level
    final double stockLevelRatio;
    if (row.variant.reorderLevel <= 0) {
      stockLevelRatio = row.stock > 0 ? 1.0 : 0.0;
    } else {
      stockLevelRatio = (row.stock / (row.variant.reorderLevel * 2)).clamp(
        0.0,
        1.0,
      );
    }

    return Container(
      color: isEven ? Colors.white : const Color(0xFFFAFAFC),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 1. Product Thumbnail & Name & Category Badge
          Expanded(
            flex: 4,
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 42,
                    height: 42,
                    child: ProductThumbnail(
                      url: row.product.productImage,
                      name: row.product.name,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.product.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: Color(0xFF0F172A),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Wrap(
                        spacing: 4,
                        runSpacing: 2,
                        children: [
                          if (row.product.brand?.isNotEmpty == true)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2563EB)
                                    .withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                row.product.brand!,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF2563EB),
                                ),
                              ),
                            ),
                          if (row.product.category?.isNotEmpty == true)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF132B45)
                                    .withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                row.product.category!,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF132B45),
                                ),
                              ),
                            ),
                          if (!row.product.isActive)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.grey.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                l10n?.inactive ?? 'Inactive',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 2. SKU & Barcode
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.variant.sku ?? row.variant.variantId,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E293B),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (row.variant.barcode?.isNotEmpty == true)
                  Text(
                    row.variant.barcode!,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF64748B),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),

          // 3. Unit / Pack
          Expanded(
            flex: 2,
            child: Text(
              _formatUnit(
                row.variant.baseUnitId,
                row.variant.commercialUnitName,
              ),
              style: const TextStyle(fontSize: 13, color: Color(0xFF334155)),
            ),
          ),

          // 4. Selling Price & MRP
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '₹${(row.variant.sellingPrice / 100).toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
                if (row.variant.mrp > row.variant.sellingPrice)
                  Text(
                    'MRP: ₹${(row.variant.mrp / 100).toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF94A3B8),
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
              ],
            ),
          ),

          // 5. Stock Level Gauge & Status Badge
          Expanded(
            flex: 3,
            child: InkWell(
              onTap: () {
                if (row.stock <= 0) {
                  _handleDirectIncreaseAttempt();
                } else {
                  _showStockActions(row);
                }
              },
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      _formatStock(row.stock),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: statusColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: stockLevelRatio,
                    minHeight: 4,
                    backgroundColor: const Color(0xFFE2E8F0),
                    valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                  ),
                ),
                if (row.variant.reorderLevel > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'Min: ${row.variant.reorderLevel}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                  ),
              ],
            ),
            ),
          ),

          // 6. Valuation
          Expanded(
            flex: 2,
            child: Text(
              '₹${row.valuationRupees.toStringAsFixed(2)}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF334155),
              ),
            ),
          ),

          // 7. Action Buttons
          Expanded(
            flex: 2,
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                IconButton(
                  tooltip: l10n?.stockMovement ?? 'Stock Action',
                  icon: const Icon(
                    Icons.tune_rounded,
                    size: 18,
                    color: Color(0xFF132B45),
                  ),
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(),
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFF132B45)
                        .withValues(alpha: 0.08),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () => _showStockActions(row),
                ),
                IconButton(
                  tooltip: l10n?.viewSpecs ?? 'View Details',
                  icon: const Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: Color(0xFF64748B),
                  ),
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(),
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFFF1F5F9),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () => _showProductDetails(row),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // VISUAL CARD GRID VIEW
  // ---------------------------------------------------------------------------

  Widget _buildCardsView(
    BuildContext context,
    List<_InventoryRow> rows,
    AppLocalizations? l10n,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = constraints.maxWidth < 600 ? double.infinity : 340.0;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: rows.map((row) {
            return SizedBox(
              width: cardWidth,
              child: _buildItemCard(context, row, l10n),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildItemCard(
    BuildContext context,
    _InventoryRow row,
    AppLocalizations? l10n,
  ) {
    final statusColor = _statusColor(row.status);
    final statusLabel = _statusLabel(row.status, l10n);

    final double stockLevelRatio;
    if (row.variant.reorderLevel <= 0) {
      stockLevelRatio = row.stock > 0 ? 1.0 : 0.0;
    } else {
      stockLevelRatio = (row.stock / (row.variant.reorderLevel * 2)).clamp(
        0.0,
        1.0,
      );
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top: Thumbnail + Name + Status Pill
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: ProductThumbnail(
                      url: row.product.productImage,
                      name: row.product.name,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.product.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Color(0xFF0F172A),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${row.variant.sku ?? row.variant.variantId} • ${_formatUnit(row.variant.baseUnitId, row.variant.commercialUnitName)}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF64748B),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Middle: Stock Level with Progress Bar
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFF1F5F9)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          l10n?.currentStock ?? 'Current Stock',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF64748B),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _formatStock(row.stock),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: statusColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: stockLevelRatio,
                      minHeight: 5,
                      backgroundColor: const Color(0xFFE2E8F0),
                      valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                    ),
                  ),
                  if (row.variant.reorderLevel > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Text(
                              '${l10n?.reorderThreshold ?? "Reorder"}: ${row.variant.reorderLevel}',
                              style: const TextStyle(
                                fontSize: 10,
                                color: Color(0xFF94A3B8),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Val: ₹${row.valuationRupees.toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Price & Actions row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '₹${(row.variant.sellingPrice / 100).toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      if (row.product.brand?.isNotEmpty == true)
                        Text(
                          row.product.brand!,
                          style: const TextStyle(
                            fontSize: 10,
                            color: Color(0xFF2563EB),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: l10n?.viewSpecs ?? 'View Details',
                      icon: const Icon(Icons.info_outline_rounded, size: 18),
                      padding: const EdgeInsets.all(6),
                      constraints: const BoxConstraints(),
                      onPressed: () => _showProductDetails(row),
                    ),
                    const SizedBox(width: 4),
                    FilledButton.tonalIcon(
                      onPressed: () => _showStockActions(row),
                      icon: const Icon(Icons.tune_rounded, size: 14),
                      label: Text(
                        l10n?.quickAdjust ?? 'Adjust',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
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
    );
  }

  // ---------------------------------------------------------------------------
  // EMPTY STATE
  // ---------------------------------------------------------------------------

  Widget _buildEmptyState(BuildContext context, AppLocalizations? l10n) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.search_off_rounded,
                size: 48,
                color: Color(0xFF94A3B8),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              l10n?.noInventoryItems ?? 'No inventory items found',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              l10n?.noInventorySubtitle ??
                  'Try adjusting your search keywords or filter status above',
              style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  _search.clear();
                  _status = 'ALL';
                  _selectedCategory = 'ALL';
                  _updatedSince = null;
                });
              },
              icon: const Icon(Icons.clear_all_rounded, size: 16),
              label: Text(l10n?.clearFilters ?? 'Clear Filters'),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // PRODUCT & STOCK DETAILS MODAL
  // ---------------------------------------------------------------------------

  Future<void> _showProductDetails(_InventoryRow row) async {
    final l10n = AppLocalizations.of(context);
    final statusColor = _statusColor(row.status);
    final statusLabel = _statusLabel(row.status, l10n);

    final purchaseRatePaise = row.variant.purchaseRate;
    final sellingPricePaise = row.variant.sellingPrice;
    final marginPercent = purchaseRatePaise > 0
        ? (((sellingPricePaise - purchaseRatePaise) / purchaseRatePaise) * 100)
              .toStringAsFixed(1)
        : null;

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 44,
                height: 44,
                child: ProductThumbnail(
                  url: row.product.productImage,
                  name: row.product.name,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.product.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    row.variant.sku ?? row.variant.variantId,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF64748B),
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                statusLabel,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: statusColor,
                ),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Divider(height: 16),
              // Specs Grid
              Wrap(
                spacing: 16,
                runSpacing: 12,
                children: [
                  _buildSpecItem(
                    l10n?.brand ?? 'Brand',
                    row.product.brand ?? '—',
                  ),
                  _buildSpecItem(
                    l10n?.category ?? 'Category',
                    row.product.category ?? '—',
                  ),
                  _buildSpecItem(
                    l10n?.unit ?? 'Unit',
                    _formatUnit(
                      row.variant.baseUnitId,
                      row.variant.commercialUnitName,
                    ),
                  ),
                  if (row.variant.commercialUnitName != null &&
                      row.variant.commercialUnitName!.trim().isNotEmpty &&
                      !row.variant.commercialUnitName!.toUpperCase().startsWith(
                        'SYS_UNIT_',
                      ) &&
                      row.variant.commercialUnitName !=
                          _formatUnit(
                            row.variant.baseUnitId,
                            row.variant.commercialUnitName,
                          ))
                    _buildSpecItem(
                      'Commercial Unit',
                      row.variant.commercialUnitName!,
                    ),
                  _buildSpecItem(
                    l10n?.hsn ?? 'HSN Code',
                    row.variant.hsnCode ?? row.product.hsnCode ?? '—',
                  ),
                  _buildSpecItem(
                    l10n?.taxRateLabel ?? 'Tax Rate',
                    '${(row.variant.defaultGstRateBps / 100).toStringAsFixed(1)}% GST',
                  ),
                  _buildSpecItem(
                    l10n?.reorderThreshold ?? 'Reorder Level',
                    '${row.variant.reorderLevel}',
                  ),
                  _buildSpecItem(
                    l10n?.currentStock ?? 'Available Stock',
                    _formatStock(row.stock),
                    color: statusColor,
                    isBold: true,
                  ),
                  _buildSpecItem(
                    l10n?.sellingPriceLabel ?? 'Selling Price',
                    '₹${(row.variant.sellingPrice / 100).toStringAsFixed(2)}',
                    isBold: true,
                  ),
                  _buildSpecItem(
                    l10n?.purchaseRateLabel ?? 'Purchase Rate',
                    purchaseRatePaise > 0
                        ? '₹${(purchaseRatePaise / 100).toStringAsFixed(2)}'
                        : '—',
                  ),
                  _buildSpecItem(
                    l10n?.mrpLabel ?? 'MRP',
                    row.variant.mrp > 0
                        ? '₹${(row.variant.mrp / 100).toStringAsFixed(2)}'
                        : '—',
                  ),
                  if (marginPercent != null)
                    _buildSpecItem(
                      'Est. Gross Margin',
                      '$marginPercent%',
                      color: const Color(0xFF16A34A),
                    ),
                  _buildSpecItem(
                    l10n?.stockValuationLabel ?? 'Stock Valuation',
                    '₹${row.valuationRupees.toStringAsFixed(2)}',
                    isBold: true,
                  ),
                ],
              ),
              if (row.product.description?.isNotEmpty == true) ...[
                const SizedBox(height: 14),
                const Text(
                  'Description:',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  row.product.description!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF334155),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text(l10n?.close ?? 'Close'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(dialogCtx);
              _showStockActions(row);
            },
            icon: const Icon(Icons.tune_rounded, size: 16),
            label: Text(l10n?.stockMovement ?? 'Adjust Stock'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF132B45),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpecItem(
    String label,
    String value, {
    Color? color,
    bool isBold = false,
  }) {
    return SizedBox(
      width: 145,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              color: color ?? const Color(0xFF1E293B),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // SECURE STOCK ACTION & QUANTITY CONTROL HUB
  // ---------------------------------------------------------------------------

  void _handleDirectIncreaseAttempt() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'This product has no recorded stock. Please enter a purchase receipt, authorized opening stock, or stock adjustment.',
        ),
        backgroundColor: Color(0xFFDC2626),
      ),
    );
  }

  Future<void> _showStockActions(_InventoryRow row) async {
    final l10n = AppLocalizations.of(context);
    final c = widget.controller;
    final isInitialized = await c.hasOpeningStockBeenInitialized(row.variant.variantId) || row.stock > 0;
    if (!mounted) return;
    final isZeroStock = row.stock <= 0;
    final cleanUnit = _formatUnit(
      row.variant.baseUnitId,
      row.variant.commercialUnitName,
    );

    final canPurchase = c.canCreatePurchases() || c.canManagePurchases();
    final canOpening = c.canAddOpeningStock();
    final canAdjust = c.canAdjustStock();
    final canHistory = c.canViewInventory();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF132B45).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.inventory_2_outlined,
                      color: Color(0xFF132B45),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          row.product.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${row.variant.name}${cleanUnit.isNotEmpty ? " • $cleanUnit" : ""}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: !isInitialized
                          ? const Color(0xFFD97706).withValues(alpha: 0.1)
                          : (isZeroStock
                              ? const Color(0xFFDC2626).withValues(alpha: 0.1)
                              : const Color(0xFF16A34A).withValues(alpha: 0.1)),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: !isInitialized
                            ? const Color(0xFFD97706).withValues(alpha: 0.3)
                            : (isZeroStock
                                ? const Color(0xFFDC2626).withValues(alpha: 0.3)
                                : const Color(0xFF16A34A).withValues(alpha: 0.3)),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          !isInitialized
                              ? '0'
                              : (isZeroStock ? '0' : _formatStock(row.stock)),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: !isInitialized
                                ? const Color(0xFFD97706)
                                : (isZeroStock
                                    ? const Color(0xFFDC2626)
                                    : const Color(0xFF16A34A)),
                          ),
                        ),
                        Text(
                          !isInitialized
                              ? 'Stock Not Initialized'
                              : (isZeroStock
                                  ? (l10n?.stockStatusOut ?? 'Out of Stock')
                                  : (l10n?.inStock ?? 'In Stock')),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: !isInitialized
                                ? const Color(0xFFD97706)
                                : (isZeroStock
                                    ? const Color(0xFFDC2626)
                                    : const Color(0xFF16A34A)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Divider(height: 1),
              const SizedBox(height: 10),

              if (canPurchase)
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2563EB).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.shopping_bag_outlined,
                      color: Color(0xFF2563EB),
                      size: 20,
                    ),
                  ),
                  title: const Text(
                    'Add Purchase',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  subtitle: const Text(
                    'Receive inventory from verified vendor bill.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _openPurchaseEntry(row);
                  },
                ),

              if (canOpening && !isInitialized)
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D9488).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.playlist_add_check_circle_outlined,
                      color: Color(0xFF0D9488),
                      size: 20,
                    ),
                  ),
                  title: const Text(
                    'Add Opening Stock',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  subtitle: const Text(
                    'Register existing physical stock during setup.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _showOpeningStockDialog(row);
                  },
                ),

              if (canAdjust)
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isInitialized
                          ? const Color(0xFFD97706).withValues(alpha: 0.1)
                          : Colors.grey.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.tune_rounded,
                      color: isInitialized
                          ? const Color(0xFFD97706)
                          : Colors.grey,
                      size: 20,
                    ),
                  ),
                  title: Text(
                    'Stock Adjustment',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: isInitialized ? null : Colors.grey,
                    ),
                  ),
                  subtitle: Text(
                    isInitialized
                        ? 'Physical corrections, breakage, damage, or counts.'
                        : 'Blocked: Requires purchase or opening stock first.',
                    style: TextStyle(
                      fontSize: 12,
                      color: isInitialized
                          ? const Color(0xFF64748B)
                          : Colors.grey,
                    ),
                  ),
                  trailing: Icon(
                    isInitialized ? Icons.chevron_right : Icons.lock_outline,
                    size: 20,
                    color: isInitialized ? null : Colors.grey,
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    if (!isInitialized) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'This product has no received purchase or opening stock. Please receive a purchase or register existing inventory through Opening Stock.',
                          ),
                          backgroundColor: Color(0xFFDC2626),
                        ),
                      );
                      return;
                    }
                    _showStockAdjustmentDialog(row);
                  },
                ),

              if (canHistory)
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF64748B).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.history_rounded,
                      color: Color(0xFF64748B),
                      size: 20,
                    ),
                  ),
                  title: const Text(
                    'Stock History',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  subtitle: const Text(
                    'Immutable audit ledger of stock movements.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _showStockHistoryDialog(row);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _openPurchaseEntry(_InventoryRow row) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          body: PurchaseEntryPage(
            controller: widget.controller,
            onClose: () {
              Navigator.pop(context);
              widget.controller.loadProducts();
            },
          ),
        ),
      ),
    );
  }

  Future<void> _showOpeningStockDialog(_InventoryRow row) async {
    final alreadyInit = await widget.controller.hasOpeningStockBeenInitialized(
      row.variant.variantId,
    );
    if (!mounted) return;
    if (alreadyInit || row.stock > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Opening stock has already been initialized for this product at this outlet.',
          ),
          backgroundColor: Color(0xFFDC2626),
        ),
      );
      return;
    }

    final cleanUnit = _formatUnit(
      row.variant.baseUnitId,
      row.variant.commercialUnitName,
    );

    final audit = await showDialog<StockTransactionAuditModel>(
      context: context,
      builder: (dialogCtx) => _OpeningStockDialog(
        controller: widget.controller,
        row: row,
        cleanUnit: cleanUnit,
      ),
    );

    if (audit != null && mounted) {
      await widget.controller.loadProducts();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Opening stock recorded successfully.'),
          backgroundColor: Color(0xFF16A34A),
        ),
      );
    }
  }

  Future<void> _showStockAdjustmentDialog(_InventoryRow row) async {
    final isInitialized = await widget.controller.hasOpeningStockBeenInitialized(
      row.variant.variantId,
    ) || row.stock > 0;
    if (!mounted) return;
    if (!isInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This product has no received purchase or opening stock. Please receive a purchase or register existing inventory through Opening Stock.',
          ),
          backgroundColor: Color(0xFFDC2626),
        ),
      );
      return;
    }

    final cleanUnit = _formatUnit(
      row.variant.baseUnitId,
      row.variant.commercialUnitName,
    );

    final result = await showDialog<StockTransactionAuditModel>(
      context: context,
      builder: (dialogCtx) => _StockAdjustmentDialog(
        controller: widget.controller,
        row: row,
        cleanUnit: cleanUnit,
      ),
    );

    if (result != null && mounted) {
      await widget.controller.loadProducts();
      if (!mounted) return;
      if (result.isPendingApproval) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Stock adjustment is awaiting approval.'),
            backgroundColor: Color(0xFFD97706),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Stock adjustment applied successfully.'),
            backgroundColor: Color(0xFF16A34A),
          ),
        );
      }
    }
  }

  Future<void> _showStockHistoryDialog(_InventoryRow row) async {
    final cleanUnit = _formatUnit(
      row.variant.baseUnitId,
      row.variant.commercialUnitName,
    );

    final changed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => _StockHistoryDialog(
        controller: widget.controller,
        row: row,
        cleanUnit: cleanUnit,
      ),
    );

    if (changed == true && mounted) {
      await widget.controller.loadProducts();
    }
  }

  // ---------------------------------------------------------------------------
  // HELPERS, PARSERS & CALCULATIONS
  // ---------------------------------------------------------------------------

  List<_InventoryRow> _rows(AppController controller) {
    return [
      for (final product in controller.products)
        for (final variant in product.variants)
          _InventoryRow(
            product: product,
            variant: variant,
            stock: controller.productStock[variant.variantId] ?? 0,
          ),
    ];
  }

  bool _matches(_InventoryRow row) {
    final query = _search.text.trim().toLowerCase();
    final searchable = [
      row.product.name,
      row.variant.name,
      row.variant.sku ?? '',
      row.variant.barcode ?? '',
      row.product.brand ?? '',
      row.product.category ?? '',
    ].join(' ').toLowerCase();

    if (query.isNotEmpty && !searchable.contains(query)) return false;

    if (_selectedCategory != 'ALL' &&
        row.product.category?.trim().toLowerCase() !=
            _selectedCategory.trim().toLowerCase()) {
      return false;
    }

    if (_updatedSince != null &&
        (row.product.updatedAt == null ||
            row.product.updatedAt!.isBefore(_updatedSince!))) {
      return false;
    }

    if (_status == 'INACTIVE' && row.product.isActive) return false;
    if (_status != 'INACTIVE' && !row.product.isActive && _status != 'ALL') {
      return false;
    }
    if (_status == 'OUT' && row.stock > 0) return false;
    if (_status == 'LOW' &&
        (row.stock <= 0 || row.stock > row.variant.reorderLevel)) {
      return false;
    }
    if (_status == 'IN_STOCK' && row.stock <= row.variant.reorderLevel) {
      return false;
    }
    return true;
  }

  int _comparator(_InventoryRow a, _InventoryRow b) {
    switch (_sortOption) {
      case _InventorySortOption.nameAsc:
        return a.product.name.toLowerCase().compareTo(
          b.product.name.toLowerCase(),
        );
      case _InventorySortOption.nameDesc:
        return b.product.name.toLowerCase().compareTo(
          a.product.name.toLowerCase(),
        );
      case _InventorySortOption.stockAsc:
        return a.stock.compareTo(b.stock);
      case _InventorySortOption.stockDesc:
        return b.stock.compareTo(a.stock);
      case _InventorySortOption.priceDesc:
        return b.variant.sellingPrice.compareTo(a.variant.sellingPrice);
      case _InventorySortOption.recent:
        final dateA = a.product.updatedAt ?? DateTime(2000);
        final dateB = b.product.updatedAt ?? DateTime(2000);
        return dateB.compareTo(dateA);
    }
  }


  Color _statusColor(String status) {
    return switch (status) {
      'OUT' => const Color(0xFFDC2626),
      'LOW' => const Color(0xFFD97706),
      'INACTIVE' => const Color(0xFF64748B),
      _ => const Color(0xFF16A34A),
    };
  }

  String _statusLabel(String status, AppLocalizations? l10n) {
    return switch (status) {
      'OUT' => l10n?.stockStatusOut ?? 'Out of Stock',
      'LOW' => l10n?.stockStatusLow ?? 'Low Stock',
      'INACTIVE' => l10n?.stockStatusInactive ?? 'Inactive',
      _ => l10n?.stockStatusHealthy ?? 'Healthy',
    };
  }
}

// -----------------------------------------------------------------------------
// DATA ROW CLASS
// -----------------------------------------------------------------------------

class _InventoryRow {
  const _InventoryRow({
    required this.product,
    required this.variant,
    required this.stock,
  });

  final ProductModel product;
  final ProductVariantModel variant;
  final int stock;

  String get status {
    if (!product.isActive) return 'INACTIVE';
    if (stock <= 0) return 'OUT';
    if (stock <= variant.reorderLevel) return 'LOW';
    return 'IN_STOCK';
  }

  double get stockUnit => (stock >= 1000 ? stock / 1000 : stock).toDouble();
  double get sellingPriceRupees => variant.sellingPrice / 100.0;
  double get purchaseRateRupees => variant.purchaseRate / 100.0;
  double get valuationRupees =>
      stockUnit *
      (sellingPriceRupees > 0 ? sellingPriceRupees : purchaseRateRupees);
}

// -----------------------------------------------------------------------------
// EXECUTIVE KPI CARD WIDGET
// -----------------------------------------------------------------------------

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
    this.isAlert = false,
    this.isSelected = false,
    this.onTap,
  });

  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color accentColor;
  final bool isAlert;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSelected
              ? accentColor
              : isAlert
              ? accentColor.withValues(alpha: 0.5)
              : const Color(0xFFE2E8F0),
          width: isSelected ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isSelected
                ? accentColor.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.02),
            blurRadius: isSelected ? 8 : 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF64748B),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: accentColor),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              if (isAlert)
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.only(right: 4),
                  decoration: BoxDecoration(
                    color: accentColor,
                    shape: BoxShape.circle,
                  ),
                ),
              Expanded(
                child: Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: isAlert ? FontWeight.bold : FontWeight.w500,
                    color: isAlert ? accentColor : const Color(0xFF94A3B8),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: card,
      );
    }
    return card;
  }
}

// -----------------------------------------------------------------------------
// STOCK & CURRENCY FORMATTERS
// -----------------------------------------------------------------------------

String _formatStock(int thousandths) {
  if (thousandths >= 1000) {
    final value = thousandths / 1000;
    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '');
  }
  return thousandths.toString();
}

String _formatCurrency(num amount) {
  if (amount >= 10000000) {
    return '₹${(amount / 10000000).toStringAsFixed(2)} Cr';
  } else if (amount >= 100000) {
    return '₹${(amount / 100000).toStringAsFixed(2)} L';
  } else if (amount >= 1000) {
    return '₹${(amount / 1000).toStringAsFixed(1)} k';
  }
  return '₹${amount.toStringAsFixed(2)}';
}

String _formatUnit(String? baseUnitId, [String? commercialUnitName]) {
  if (commercialUnitName != null &&
      commercialUnitName.trim().isNotEmpty &&
      !commercialUnitName.trim().toUpperCase().startsWith('SYS_UNIT_')) {
    return commercialUnitName.trim();
  }
  if (baseUnitId == null || baseUnitId.trim().isEmpty) return '';
  final trimmed = baseUnitId.trim();

  for (final entry in CatalogueContract.unitIds.entries) {
    if (entry.value.toUpperCase() == trimmed.toUpperCase()) {
      return entry.key;
    }
  }

  if (trimmed.toUpperCase().startsWith('SYS_UNIT_')) {
    final cleaned = trimmed.substring('SYS_UNIT_'.length);
    final upper = cleaned.toUpperCase();
    if (upper == 'LTR' || upper == 'LITRE') return 'Litre';
    if (upper == 'ML' || upper == 'MILLILITRE') return 'ml';
    if (upper == 'KG' || upper == 'KILOGRAM') return 'Kg';
    if (upper == 'GM' || upper == 'GRAM') return 'g';
    if (upper == 'PCS' || upper == 'PIECE') return 'Piece';
    if (upper == 'BOX') return 'Box';
    if (upper == 'CAN') return 'Can';
    if (upper == 'BUCKET') return 'Bucket';
    final words = cleaned.replaceAll('_', ' ').toLowerCase().split(' ');
    return words
        .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }
  return trimmed;
}


// -----------------------------------------------------------------------------
// STOCK & CURRENCY PARSERS
// -----------------------------------------------------------------------------

int? _parseRupeesToPaise(String value) {
  final normalized = value.trim().replaceAll(',', '');
  final match = RegExp(r'^\d+(?:\.\d{1,2})?$').firstMatch(normalized);
  if (match == null) return null;
  final parts = normalized.split('.');
  final rupees = int.tryParse(parts.first);
  if (rupees == null) return null;
  final paise = parts.length == 1
      ? 0
      : int.tryParse(parts[1].padRight(2, '0'));
  if (paise == null) return null;
  return rupees * 100 + paise;
}

int? _parseStockQuantity(String value) {
  final normalized = value.trim().replaceAll(',', '');
  if (!RegExp(r'^\d+(?:\.\d{1,3})?$').hasMatch(normalized)) return null;
  final parts = normalized.split('.');
  final whole = int.tryParse(parts.first);
  if (whole == null) return null;
  final fraction = parts.length == 1
      ? 0
      : int.parse(parts[1].padRight(3, '0'));
  return whole * 1000 + fraction;
}

// -----------------------------------------------------------------------------
// DEDICATED STATEFUL DIALOG WIDGETS (SAFELY ENCAPSULATED CONTROLLER LIFECYCLE)
// -----------------------------------------------------------------------------

class _OpeningStockDialog extends StatefulWidget {
  const _OpeningStockDialog({
    required this.controller,
    required this.row,
    required this.cleanUnit,
  });

  final AppController controller;
  final _InventoryRow row;
  final String cleanUnit;

  @override
  State<_OpeningStockDialog> createState() => _OpeningStockDialogState();
}

class _OpeningStockDialogState extends State<_OpeningStockDialog> {
  late final TextEditingController _quantity;
  late final TextEditingController _cost;
  late final TextEditingController _reason;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _quantity = TextEditingController();
    _cost = TextEditingController();
    _reason = TextEditingController(text: 'Initial setup opening inventory');
  }

  @override
  void dispose() {
    _quantity.dispose();
    _cost.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return; // Prevent duplicate rapid submission
    final l10n = AppLocalizations.of(context);
    final qty = _parseStockQuantity(_quantity.text);
    final unitCost = _parseRupeesToPaise(_cost.text);

    if (qty == null || qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n?.enterQuantityError ?? 'Enter a quantity greater than zero.',
          ),
          backgroundColor: const Color(0xFFDC2626),
        ),
      );
      return;
    }

    if (unitCost == null || unitCost <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unit purchase cost is required for opening stock.'),
          backgroundColor: Color(0xFFDC2626),
        ),
      );
      return;
    }

    if (_reason.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A reason is required for opening stock.'),
          backgroundColor: Color(0xFFDC2626),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (confirmCtx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text('Confirm Opening Stock Registration'),
        content: Text(
          'You are registering   at ₹ per unit (Total Valuation: ₹).\n\nOpening stock permanently establishes the starting physical inventory baseline and cannot be re-entered. Do you want to proceed?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(confirmCtx).pop(false),
            child: Text(l10n?.cancel ?? 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(confirmCtx).pop(true),
            child: const Text('Confirm & Post'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;

    setState(() => _saving = true);
    try {
      final audit = await widget.controller.addOpeningStock(
        productId: widget.row.product.productId,
        variantId: widget.row.variant.variantId,
        quantity: qty,
        reason: _reason.text.trim(),
        unitCostPaise: unitCost,
        unit: widget.cleanUnit,
      );
      if (!mounted) return;
      Navigator.of(context).pop(audit);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'),
          backgroundColor: const Color(0xFFDC2626),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final qtyVal = _parseStockQuantity(_quantity.text) ?? 0;
    final costVal = _parseRupeesToPaise(_cost.text) ?? 0;
    final totalValuationRupees =
        (qtyVal > 0 && costVal > 0) ? (qtyVal * costVal) / 100000.0 : 0.0;

    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF0D9488).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.playlist_add_check_circle_outlined,
              color: Color(0xFF0D9488),
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Register Opening Stock',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Text(
                  '${widget.row.product.name} • ${widget.row.variant.name}',
                  style: const TextStyle(
                    fontSize: 12,
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
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Current Stock:',
                      style: TextStyle(fontSize: 12, color: Color(0xFF475569)),
                    ),
                    Text(
                      _formatStock(widget.row.stock),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _quantity,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: widget.cleanUnit.isNotEmpty
                      ? 'Opening Quantity (${widget.cleanUnit})'
                      : 'Opening Quantity',
                  hintText: 'e.g. 10 or 25',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _cost,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Unit Purchase Cost (₹) *',
                  hintText: 'e.g. 150.00',
                  prefixText: '₹ ',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _reason,
                decoration: const InputDecoration(
                  labelText: 'Reason / Setup Note *',
                  hintText: 'Required for opening stock audit provenance',
                ),
              ),
              if (qtyVal > 0) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFFCBD5E1),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'New Available Stock:',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF475569),
                            ),
                          ),
                          Text(
                            _formatStock(qtyVal),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF16A34A),
                            ),
                          ),
                        ],
                      ),
                      if (costVal > 0) ...[
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Total Inventory Valuation:',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF475569),
                              ),
                            ),
                            Text(
                              '₹${totalValuationRupees.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF132B45),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(l10n?.cancel ?? 'Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: Text(_saving ? (l10n?.saving ?? 'Saving...') : 'Confirm Opening Stock'),
        ),
      ],
    );
  }
}

class _StockAdjustmentDialog extends StatefulWidget {
  const _StockAdjustmentDialog({
    required this.controller,
    required this.row,
    required this.cleanUnit,
  });

  final AppController controller;
  final _InventoryRow row;
  final String cleanUnit;

  @override
  State<_StockAdjustmentDialog> createState() => _StockAdjustmentDialogState();
}

class _StockAdjustmentDialogState extends State<_StockAdjustmentDialog> {
  late final TextEditingController _quantity;
  late final TextEditingController _cost;
  late final TextEditingController _reason;
  late String _transactionType;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _quantity = TextEditingController();
    _cost = TextEditingController();
    _reason = TextEditingController();
    _transactionType = StockTransactionAuditModel.typeAdjustmentIn;
  }

  @override
  void dispose() {
    _quantity.dispose();
    _cost.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return; // Prevent duplicate rapid submission
    final l10n = AppLocalizations.of(context);
    final isIncrease = _transactionType == StockTransactionAuditModel.typeAdjustmentIn ||
        _transactionType == StockTransactionAuditModel.typeCountCorrection;
    final qty = _parseStockQuantity(_quantity.text);
    final unitCost = _parseRupeesToPaise(_cost.text);

    if (qty == null || qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n?.enterQuantityError ?? 'Enter a quantity greater than zero.',
          ),
          backgroundColor: const Color(0xFFDC2626),
        ),
      );
      return;
    }

    if (!isIncrease) {
      if (widget.row.stock <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Stock cannot be reduced because the available quantity is 0.'),
            backgroundColor: Color(0xFFDC2626),
          ),
        );
        return;
      }
      if (qty > widget.row.stock) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Insufficient available stock. Please check the quantity.'),
            backgroundColor: Color(0xFFDC2626),
          ),
        );
        return;
      }
    }

    if (_reason.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A reason is required for every stock movement.'),
          backgroundColor: Color(0xFFDC2626),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final result = await widget.controller.requestOrApplyAdjustment(
        productId: widget.row.product.productId,
        variantId: widget.row.variant.variantId,
        quantity: qty,
        isIncrease: isIncrease,
        transactionType: _transactionType,
        reason: _reason.text.trim(),
        unit: widget.cleanUnit,
        unitCostPaise: unitCost,
      );

      if (!mounted) return;
      Navigator.of(context).pop(result);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'),
          backgroundColor: const Color(0xFFDC2626),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isIncrease = _transactionType == StockTransactionAuditModel.typeAdjustmentIn ||
        _transactionType == StockTransactionAuditModel.typeCountCorrection;
    final qtyVal = _parseStockQuantity(_quantity.text) ?? 0;
    final projected = isIncrease ? widget.row.stock + qtyVal : widget.row.stock - qtyVal;
    final isNegative = projected < 0;

    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFD97706).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.tune_rounded,
              color: Color(0xFFD97706),
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Stock Adjustment',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Text(
                  '${widget.row.product.name} • ${widget.row.variant.name}',
                  style: const TextStyle(
                    fontSize: 12,
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
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Current Available Stock:',
                      style: TextStyle(fontSize: 12, color: Color(0xFF475569)),
                    ),
                    Text(
                      _formatStock(widget.row.stock),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _transactionType,
                decoration: const InputDecoration(
                  labelText: 'Adjustment Reason Type',
                ),
                items: const [
                  DropdownMenuItem(
                    value: StockTransactionAuditModel.typeAdjustmentIn,
                    child: Text('Positive Adjustment (Found / Unrecorded Stock)'),
                  ),
                  DropdownMenuItem(
                    value: StockTransactionAuditModel.typeCountCorrection,
                    child: Text('Physical Stock Count Correction'),
                  ),
                  DropdownMenuItem(
                    value: StockTransactionAuditModel.typeAdjustmentOut,
                    child: Text('Negative Adjustment (Store Consumption / Sample)'),
                  ),
                  DropdownMenuItem(
                    value: StockTransactionAuditModel.typeDamageLoss,
                    child: Text('Damage / Breakage / Expiry Loss'),
                  ),
                ],
                onChanged: _saving
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() => _transactionType = value);
                        }
                      },
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _quantity,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: widget.cleanUnit.isNotEmpty
                      ? 'Quantity (${widget.cleanUnit})'
                      : 'Quantity',
                  hintText: 'e.g. 5 or 12.5',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _reason,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Reason for Adjustment *',
                  hintText: 'Required for stock adjustment audit trail',
                ),
              ),
              if (qtyVal > 0) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isNegative
                        ? const Color(0xFFDC2626).withValues(alpha: 0.1)
                        : const Color(0xFF16A34A).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isNegative
                          ? const Color(0xFFDC2626).withValues(alpha: 0.3)
                          : const Color(0xFF16A34A).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    isNegative
                        ? 'Warning: Resulting balance cannot become negative (${_formatStock(projected)})'
                        : 'Projected Available Stock: ${_formatStock(projected)}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isNegative
                          ? const Color(0xFFDC2626)
                          : const Color(0xFF16A34A),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(l10n?.cancel ?? 'Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: Text(_saving ? (l10n?.saving ?? 'Saving...') : 'Submit Adjustment'),
        ),
      ],
    );
  }
}

class _StockHistoryDialog extends StatefulWidget {
  const _StockHistoryDialog({
    required this.controller,
    required this.row,
    required this.cleanUnit,
  });

  final AppController controller;
  final _InventoryRow row;
  final String cleanUnit;

  @override
  State<_StockHistoryDialog> createState() => _StockHistoryDialogState();
}

class _StockHistoryDialogState extends State<_StockHistoryDialog> {
  bool _hasChanges = false;
  late Future<List<StockTransactionAuditModel>> _historyFuture;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  void _loadHistory() {
    _historyFuture = widget.controller.getStockHistory(
      variantId: widget.row.variant.variantId,
    );
  }

  Future<void> _approve(String txId) async {
    await widget.controller.approveAdjustment(txId);
    _hasChanges = true;
    if (mounted) {
      setState(() => _loadHistory());
    }
  }

  Future<void> _reject(String txId) async {
    await widget.controller.rejectAdjustment(txId);
    _hasChanges = true;
    if (mounted) {
      setState(() => _loadHistory());
    }
  }

  @override
  Widget build(BuildContext context) {
    final canApprove = widget.controller.canApproveAdjustment();

    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF132B45).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.history_rounded,
              color: Color(0xFF132B45),
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Stock Movement Audit History',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Text(
                  '${widget.row.product.name} • ${widget.row.variant.name} (${_formatStock(widget.row.stock)} ${widget.cleanUnit})',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 750,
        height: 450,
        child: FutureBuilder<List<StockTransactionAuditModel>>(
          future: _historyFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            }
            final list = snapshot.data ?? [];
            if (list.isEmpty) {
              return const Center(
                child: Text('No stock movement transactions recorded yet.'),
              );
            }
            return ListView.separated(
              itemCount: list.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final tx = list[index];
                final isIncrease = tx.newQuantity >= tx.previousQuantity;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Icon(
                        isIncrease
                            ? Icons.arrow_downward_rounded
                            : Icons.arrow_upward_rounded,
                        color: isIncrease
                            ? const Color(0xFF16A34A)
                            : const Color(0xFFDC2626),
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  tx.transactionType,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: tx.isApproved
                                        ? const Color(0xFF16A34A).withValues(alpha: 0.1)
                                        : tx.isPendingApproval
                                            ? const Color(0xFFD97706).withValues(alpha: 0.1)
                                            : const Color(0xFFDC2626).withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    tx.approvalStatus,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: tx.isApproved
                                          ? const Color(0xFF16A34A)
                                          : tx.isPendingApproval
                                              ? const Color(0xFFD97706)
                                              : const Color(0xFFDC2626),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              '${tx.createdAt.toLocal().toString().split('.').first} • Reason: ${tx.reason}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${isIncrease ? "+" : "-"}${_formatStock(tx.changedQuantity)}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: isIncrease
                                  ? const Color(0xFF16A34A)
                                  : const Color(0xFFDC2626),
                            ),
                          ),
                          Text(
                            'Balance: ${_formatStock(tx.newQuantity)}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                      if (tx.isPendingApproval && canApprove) ...[
                        const SizedBox(width: 10),
                        IconButton(
                          tooltip: 'Approve Adjustment',
                          icon: const Icon(
                            Icons.check_circle_outline,
                            color: Color(0xFF16A34A),
                            size: 20,
                          ),
                          onPressed: () => _approve(tx.transactionId),
                        ),
                        IconButton(
                          tooltip: 'Reject Adjustment',
                          icon: const Icon(
                            Icons.cancel_outlined,
                            color: Color(0xFFDC2626),
                            size: 20,
                          ),
                          onPressed: () => _reject(tx.transactionId),
                        ),
                      ],
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(_hasChanges),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
