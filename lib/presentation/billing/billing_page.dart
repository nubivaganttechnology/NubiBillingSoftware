import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../data/models/business_settings_model.dart';
import '../../data/models/customer_model.dart';
import '../../data/models/invoice_model.dart';
import '../../data/models/product_variant_model.dart';
import '../../data/repositories/product_repository.dart'
    show VariantBatchPriceOption;
import '../../data/services/invoice_print_service.dart';
import '../../domain/billing/bill_calculator.dart';
import '../../domain/billing/billing_models.dart';
import '../../domain/customers/customer_validators.dart';
import '../../l10n/app_localizations.dart';
import '../app_controller.dart';
import '../customers/customer_form.dart';
import 'widgets/print_format_dialog.dart';
import 'widgets/upi_qr_widget.dart';

class BillingPage extends StatefulWidget {
  const BillingPage({super.key, required this.controller, this.onBillSaved});
  final AppController controller;
  final VoidCallback? onBillSaved;

  @override
  State<BillingPage> createState() => _BillingPageState();
}

class _PaymentValidationResult {
  final bool isValid;
  final String? warningMessage;
  final String? infoMessage;
  final int excessPaise;
  const _PaymentValidationResult({
    required this.isValid,
    this.warningMessage,
    this.infoMessage,
    this.excessPaise = 0,
  });
}

class _BillingPageState extends State<BillingPage> {
  bool get _supportsCameraBarcodeScanning =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  final _quantity = TextEditingController(text: '1');
  final _discount = TextEditingController(text: '0.00');
  final _billDiscount = TextEditingController(text: '0.00');
  final _cash = TextEditingController(text: '0.00');
  final _upi = TextEditingController(text: '0.00');
  final _sellingPrice = TextEditingController();
  final _mrp = TextEditingController();
  final _gstRate = TextEditingController();
  final _gstin = TextEditingController();
  ProductVariantModel? _selected;
  VariantBatchPriceOption? _selectedBatch;
  CustomerModel? _selectedCustomer;
  List<CustomerModel> _customers = const [];
  final _lines = <BillLineInput>[];
  bool _gst = true;
  int? _billGstRateBps;
  bool _saving = false;
  bool _makeDefaultPrice = false;
  bool _inStockOnly = false;
  int _productPickerVersion = 0;
  PaymentMode _paymentMode = PaymentMode.cash;
  DateTime? _dueDate;
  bool _isAutoCalculatingPayment = false;

  void _onPaymentModeChanged(PaymentMode mode) {
    setState(() {
      _paymentMode = mode;
      _syncPaymentInputsForCurrentTotal();
    });
  }

  void _onSplitCashChanged(String value) {
    if (_isAutoCalculatingPayment) return;
    final cashPaise = _parseMoney(value);
    if (cashPaise != null) {
      final remainder = (total.grandTotalPaise - cashPaise).clamp(
        0,
        total.grandTotalPaise,
      );
      _isAutoCalculatingPayment = true;
      _upi.text = (remainder / 100).toStringAsFixed(2);
      _isAutoCalculatingPayment = false;
    }
    setState(() {});
  }

  void _onSplitUpiChanged(String value) {
    if (_isAutoCalculatingPayment) return;
    final upiPaise = _parseMoney(value);
    if (upiPaise != null) {
      final remainder = (total.grandTotalPaise - upiPaise).clamp(
        0,
        total.grandTotalPaise,
      );
      _isAutoCalculatingPayment = true;
      _cash.text = (remainder / 100).toStringAsFixed(2);
      _isAutoCalculatingPayment = false;
    }
    setState(() {});
  }

  void _syncPaymentInputsForCurrentTotal() {
    final grandTotalStr = (total.grandTotalPaise / 100).toStringAsFixed(2);
    switch (_paymentMode) {
      case PaymentMode.cash:
        _cash.text = grandTotalStr;
        _upi.text = '0.00';
        _dueDate = null;
        break;
      case PaymentMode.upi:
        _cash.text = '0.00';
        _upi.text = grandTotalStr;
        _dueDate = null;
        break;
      case PaymentMode.split:
        _dueDate = null;
        final currentCash = _parseMoney(_cash.text) ?? 0;
        if (currentCash == 0 || currentCash > total.grandTotalPaise) {
          final half = total.grandTotalPaise ~/ 2;
          _cash.text = (half / 100).toStringAsFixed(2);
          _upi.text = ((total.grandTotalPaise - half) / 100).toStringAsFixed(2);
        } else {
          final remaining = total.grandTotalPaise - currentCash;
          _upi.text = (remaining / 100).toStringAsFixed(2);
        }
        break;
      case PaymentMode.udhaar:
        _cash.text = '0.00';
        _upi.text = '0.00';
        _dueDate ??= DateTime.now().add(const Duration(days: 30));
        break;
    }
  }

  AppController get controller => widget.controller;
  CalculatedBill get total => const BillCalculator().calculate(
    lines: _lines,
    taxMode: _gst ? BillingTaxMode.gst : BillingTaxMode.nonGst,
    taxStructure: TaxStructure.intraState,
  );

  BusinessSettingsModel? _businessSettings;

  Map<String, ({int mrp, int sellingPrice})> _receivedPricing = {};

  @override
  void initState() {
    super.initState();
    _quantity.addListener(_onQuantityChanged);
    _loadBusinessSettings();
    _loadPricing();
  }

  void _onQuantityChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant BillingPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller.appContext?.businessId !=
            widget.controller.appContext?.businessId ||
        oldWidget.controller.currentOutlet?.outletId !=
            widget.controller.currentOutlet?.outletId) {
      _loadBusinessSettings();
      _loadPricing();
    }
  }

  Future<void> _loadPricing() async {
    try {
      final pricing =
          await widget.controller.loadBarcodeReceivedVariantPricing();
      if (mounted) setState(() => _receivedPricing = pricing);
    } catch (_) {}
  }

  int _effectiveSellingPrice(ProductVariantModel variant) {
    if (variant.sellingPrice > 0) return variant.sellingPrice;
    return _receivedPricing[variant.variantId]?.sellingPrice ?? 0;
  }

  int _effectiveMrp(ProductVariantModel variant) {
    if (variant.mrp > 0) return variant.mrp;
    return _receivedPricing[variant.variantId]?.mrp ?? 0;
  }

  Future<List<VariantBatchPriceOption>> _getVariantBatches(
    String variantId,
  ) async {
    try {
      return await widget.controller.loadVariantBatches(variantId);
    } catch (_) {
      return const [];
    }
  }

  Future<void> _loadBusinessSettings() async {
    try {
      final repo = widget.controller.settingsRepository;
      final appContext = widget.controller.appContext;
      final token = widget.controller.idToken;
      if (repo == null || appContext?.businessId == null || token == null) {
        return;
      }
      final s = await repo.loadSettings(
        businessId: appContext!.businessId!,
        tenantId: appContext.ownerUid,
        token: token,
      );
      if (mounted) setState(() => _businessSettings = s);
    } catch (_) {}
  }

  List<ProductVariantModel> get variants => [
    for (final product in controller.products) ...product.variants,
  ];

  int _availableStockUnits(ProductVariantModel variant) {
    if (!variant.trackStock) return 999999;
    final rawStock = controller.productStock[variant.variantId] ?? 0;
    if (rawStock <= 0) return 0;
    return rawStock >= 1000 ? (rawStock / 1000).floor() : rawStock;
  }

  int _currentCartQuantity(String variantId) {
    return _lines
        .where((line) => line.variantId == variantId)
        .fold<int>(0, (sum, line) => sum + line.quantity);
  }

  @override
  void dispose() {
    _quantity.removeListener(_onQuantityChanged);
    _quantity.dispose();
    _discount.dispose();
    _billDiscount.dispose();
    _cash.dispose();
    _upi.dispose();
    _sellingPrice.dispose();
    _mrp.dispose();
    _gstRate.dispose();
    _gstin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = controller.currentOutlet;
    final l10n = AppLocalizations.of(context);
    if (controller.appContext?.businessId == null || current == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.storefront_outlined,
              size: 48,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 12),
            Text(
              l10n?.selectOutletBeforeBilling ??
                  'Select an outlet before billing.',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 1050;
        final horizontalPadding = constraints.maxWidth < 600 ? 12.0 : 20.0;
        final verticalPadding = constraints.maxWidth < 600 ? 12.0 : 16.0;

        return ListView(
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: verticalPadding,
          ),
          children: [
            _buildTerminalHeader(context, l10n, current),
            const SizedBox(height: 16),
            if (isDesktop)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left Pane: Scanner, Product edit card, Line items table
                  Expanded(
                    flex: 64,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildScannerDock(context, l10n),
                        if (_selected != null) ...[
                          const SizedBox(height: 14),
                          _ProductDetailsCard(
                            l10n: l10n,
                            variant: _selected!,
                            stock: controller.productStock,
                            sellingPrice: _sellingPrice,
                            mrp: _mrp,
                            gstRate: _gstRate,
                            makeDefault: _makeDefaultPrice,
                            saving: _saving,
                            isGst: _gst,
                            onMakeDefaultChanged: (value) =>
                                setState(() => _makeDefaultPrice = value),
                            onSavePricing: _savePricing,
                          ),
                        ],
                        const SizedBox(height: 16),
                        _buildCartSection(context, l10n),
                      ],
                    ),
                  ),
                  const SizedBox(width: 18),
                  // Right Pane: Customer Dock, Summary, Payment Console
                  SizedBox(
                    width: 390,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _customerCard(l10n),
                        if (_gst) ...[
                          const SizedBox(height: 10),
                          _gstinField(l10n),
                        ],
                        const SizedBox(height: 14),
                        _buildSummaryAndPaymentConsole(context, l10n),
                      ],
                    ),
                  ),
                ],
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _customerCard(l10n),
                  if (_gst) ...[const SizedBox(height: 10), _gstinField(l10n)],
                  const SizedBox(height: 14),
                  _buildScannerDock(context, l10n),
                  if (_selected != null) ...[
                    const SizedBox(height: 14),
                    _ProductDetailsCard(
                      l10n: l10n,
                      variant: _selected!,
                      stock: controller.productStock,
                      sellingPrice: _sellingPrice,
                      mrp: _mrp,
                      gstRate: _gstRate,
                      makeDefault: _makeDefaultPrice,
                      saving: _saving,
                      isGst: _gst,
                      onMakeDefaultChanged: (value) =>
                          setState(() => _makeDefaultPrice = value),
                      onSavePricing: _savePricing,
                    ),
                  ],
                  const SizedBox(height: 16),
                  _buildCartSection(context, l10n),
                  const SizedBox(height: 20),
                  _buildSummaryAndPaymentConsole(context, l10n),
                ],
              ),
          ],
        );
      },
    );
  }

  Widget _buildTerminalHeader(
    BuildContext context,
    AppLocalizations? l10n,
    dynamic current,
  ) {
    final theme = Theme.of(context);
    final outletName = current.outletName ?? '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blueGrey.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 10,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF10263D), Color(0xFF1D3B5E)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.point_of_sale_rounded,
                    color: Color(0xFFD9A441),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l10n?.posBillingTerminal ?? 'POS Billing Terminal',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFD9A441)
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              outletName,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF8A5D00),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            DateFormat.yMMMd().format(DateTime.now()),
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<bool>(
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: [
                  ButtonSegment(
                    value: true,
                    icon: const Icon(Icons.receipt_long, size: 16),
                    label: Text(l10n?.gst ?? 'GST'),
                  ),
                  ButtonSegment(
                    value: false,
                    icon: const Icon(Icons.receipt, size: 16),
                    label: Text(l10n?.nonGst ?? 'Non-GST'),
                  ),
                ],
                selected: {_gst},
                onSelectionChanged: (value) => _onTaxModeChanged(value.first),
              ),
              if (_lines.isNotEmpty) ...[
                const SizedBox(width: 8),
                IconButton(
                  tooltip: l10n?.clearCart ?? 'Clear Cart',
                  icon: Icon(
                    Icons.delete_sweep_outlined,
                    color: Colors.red.shade700,
                  ),
                  onPressed: () {
                    setState(() {
                      _lines.clear();
                      _billDiscount.text = '0.00';
                      _syncPaymentInputsForCurrentTotal();
                    });
                  },
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _scanProductBarcode(
    BuildContext context,
    TextEditingController searchController,
    FocusNode searchFocusNode,
  ) async {
    if (!_supportsCameraBarcodeScanning) return;

    final code = await showDialog<String>(
      context: context,
      builder: (_) => _BarcodeScannerDialog(
        onBarcode: (value) => Navigator.of(context).pop(value),
      ),
    );
    if (!mounted || code == null || code.isEmpty) return;

    final normalizedCode = code.toLowerCase();
    final variant =
        variants
            .where(
              (item) => item.barcode?.trim().toLowerCase() == normalizedCode,
            )
            .firstOrNull ??
        variants
            .where((item) => item.sku?.trim().toLowerCase() == normalizedCode)
            .firstOrNull;

    if (variant == null) {
      searchController
        ..text = code
        ..selection = TextSelection.collapsed(offset: code.length);
      searchFocusNode.requestFocus();
      _message('No product matches barcode: $code');
      return;
    }

    final quantity = int.tryParse(_quantity.text) ?? 1;
    searchController.clear();
    final added = await _addOrIncrementVariant(variant, quantity);
    if (added) {
      _clearProductSelection();
    }
  }

  Widget _buildScannerDock(BuildContext context, AppLocalizations? l10n) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.blueGrey.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: constraints.maxWidth > 580
                      ? 320
                      : constraints.maxWidth,
                  child: Autocomplete<ProductVariantModel>(
                    key: ValueKey(_productPickerVersion),
                    displayStringForOption: (variant) => variant.displayName,
                    optionsBuilder: (value) {
                      final query = value.text.trim().toLowerCase();
                      var sourceList = variants;
                      if (_inStockOnly) {
                        sourceList = sourceList
                            .where(
                              (v) =>
                                  !v.trackStock || _availableStockUnits(v) > 0,
                            )
                            .toList();
                      }
                      if (query.isEmpty) {
                        final list = List<ProductVariantModel>.from(sourceList);
                        list.sort((a, b) {
                          final aInStock =
                              !a.trackStock || _availableStockUnits(a) > 0;
                          final bInStock =
                              !b.trackStock || _availableStockUnits(b) > 0;
                          if (aInStock && !bInStock) return -1;
                          if (!aInStock && bInStock) return 1;
                          return a.displayName.compareTo(b.displayName);
                        });
                        return list;
                      }
                      final matches = sourceList
                          .where(
                            (variant) =>
                                [
                                  variant.displayName,
                                  variant.productName ?? '',
                                  variant.name,
                                  variant.sku ?? '',
                                  variant.barcode ?? '',
                                ].any(
                                  (field) =>
                                      field.toLowerCase().contains(query),
                                ),
                          )
                          .toList();
                      matches.sort((a, b) {
                        final aInStock =
                            !a.trackStock || _availableStockUnits(a) > 0;
                        final bInStock =
                            !b.trackStock || _availableStockUnits(b) > 0;
                        if (aInStock && !bInStock) return -1;
                        if (!aInStock && bInStock) return 1;

                        final aBarcodeExact =
                            (a.barcode?.trim().toLowerCase() == query);
                        final bBarcodeExact =
                            (b.barcode?.trim().toLowerCase() == query);
                        if (aBarcodeExact && !bBarcodeExact) return -1;
                        if (!aBarcodeExact && bBarcodeExact) return 1;

                        final aSkuExact =
                            (a.sku?.trim().toLowerCase() == query);
                        final bSkuExact =
                            (b.sku?.trim().toLowerCase() == query);
                        if (aSkuExact && !bSkuExact) return -1;
                        if (!aSkuExact && bSkuExact) return 1;

                        final aNameExact =
                            (a.displayName.toLowerCase() == query);
                        final bNameExact =
                            (b.displayName.toLowerCase() == query);
                        if (aNameExact && !bNameExact) return -1;
                        if (!aNameExact && bNameExact) return 1;

                        return 0;
                      });
                      return matches;
                    },
                    onSelected: (value) async {
                      final batches = await _getVariantBatches(value.variantId);
                      final activeBatches =
                          batches.where((b) => b.availableQty > 0).toList();
                      final distinctPrices = activeBatches
                          .map((b) => b.sellingPricePaise)
                          .where((p) => p > 0)
                          .toSet();

                      VariantBatchPriceOption? chosen;
                      if (distinctPrices.length > 1) {
                        if (!context.mounted) return;
                        chosen = await showDialog<VariantBatchPriceOption>(
                          context: context,
                          barrierDismissible: false,
                          builder: (ctx) => _LotPriceSelectionDialog(
                            variant: value,
                            batches: activeBatches,
                          ),
                        );
                      } else if (activeBatches.isNotEmpty) {
                        chosen = activeBatches.first;
                      }

                      if (!mounted) return;
                      setState(() {
                        _selected = value;
                        _selectedBatch = chosen;
                        final effectiveSell =
                            (chosen != null && chosen.sellingPricePaise > 0)
                                ? chosen.sellingPricePaise
                                : _effectiveSellingPrice(value);
                        final effectiveMrp =
                            (chosen != null && chosen.mrpPaise > 0)
                                ? chosen.mrpPaise
                                : _effectiveMrp(value);
                        _sellingPrice.text =
                            effectiveSell > 0 ? _formatMoney(effectiveSell) : '';
                        _mrp.text =
                            effectiveMrp > 0 ? _formatMoney(effectiveMrp) : '';
                        final effectiveRate = _gst
                            ? (_billGstRateBps ?? value.defaultGstRateBps)
                            : 0;
                        _gstRate.text = (effectiveRate / 100).toStringAsFixed(
                          2,
                        );
                        _makeDefaultPrice = false;
                      });
                    },
                    fieldViewBuilder:
                        (
                          context,
                          textController,
                          focusNode,
                          onFieldSubmitted,
                        ) => TextField(
                          controller: textController,
                          focusNode: focusNode,
                          onSubmitted: (value) async {
                            final query = value.trim();
                            if (query.isEmpty) return;

                            // 1. Check exact barcode match
                            final barcodeMatches = variants
                                .where(
                                  (v) =>
                                      v.barcode != null &&
                                      v.barcode!.trim().toLowerCase() ==
                                          query.toLowerCase(),
                                )
                                .toList();
                            if (barcodeMatches.isNotEmpty) {
                              final qty = int.tryParse(_quantity.text) ?? 1;
                              final added = await _addOrIncrementVariant(barcodeMatches.first, qty);
                              textController.clear();
                              if (added) {
                                _clearProductSelection();
                                focusNode.requestFocus();
                              }
                              return;
                            }

                            // 2. Check exact SKU match
                            final skuMatches = variants
                                .where(
                                  (v) =>
                                      v.sku != null &&
                                      v.sku!.trim().toLowerCase() ==
                                          query.toLowerCase(),
                                )
                                .toList();
                            if (skuMatches.isNotEmpty) {
                              final qty = int.tryParse(_quantity.text) ?? 1;
                              final added = await _addOrIncrementVariant(skuMatches.first, qty);
                              textController.clear();
                              if (added) {
                                _clearProductSelection();
                                focusNode.requestFocus();
                              }
                              return;
                            }

                            // 3. Check exact displayName match
                            final singleMatches = variants
                                .where(
                                  (v) =>
                                      v.displayName.toLowerCase() ==
                                      query.toLowerCase(),
                                )
                                .toList();
                            if (singleMatches.length == 1) {
                              final qty = int.tryParse(_quantity.text) ?? 1;
                              final added = await _addOrIncrementVariant(singleMatches.first, qty);
                              textController.clear();
                              if (added) {
                                _clearProductSelection();
                                focusNode.requestFocus();
                              }
                              return;
                            }

                            onFieldSubmitted();
                          },
                          decoration: InputDecoration(
                            labelText:
                                l10n?.scanBarcodeLabel ??
                                'Scan barcode / Search product',
                            hintText:
                                l10n?.scanBarcodeOrSearch ??
                                'Scan barcode or search name/SKU',
                            prefixIcon: _supportsCameraBarcodeScanning
                                ? IconButton(
                                    tooltip: 'Scan barcode with camera',
                                    onPressed: () => _scanProductBarcode(
                                      context,
                                      textController,
                                      focusNode,
                                    ),
                                    icon: const Icon(
                                      Icons.qr_code_scanner,
                                      color: Color(0xFF10263D),
                                    ),
                                  )
                                : null,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            suffixIcon: textController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 18),
                                    onPressed: () {
                                      textController.clear();
                                      _clearProductSelection();
                                    },
                                  )
                                : null,
                          ),
                        ),
                    optionsViewBuilder: (context, onSelected, options) => Align(
                      alignment: Alignment.topLeft,
                      child: Material(
                        elevation: 6,
                        borderRadius: BorderRadius.circular(10),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxHeight: 320,
                            maxWidth: 420,
                          ),
                          child: ListView.separated(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            shrinkWrap: true,
                            itemCount: options.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final variant = options.elementAt(index);
                              final isStockTracked = variant.trackStock;
                              final stockUnits = _availableStockUnits(variant);
                              final isOutOfStock =
                                  isStockTracked && stockUnits <= 0;

                              return ListTile(
                                dense: true,
                                title: Text.rich(
                                  TextSpan(
                                    text: variant.displayName,
                                    children: [
                                      if (isOutOfStock)
                                        TextSpan(
                                          text:
                                              '  [${l10n?.outOfStock ?? "Out of stock"}]',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.red.shade800,
                                          ),
                                        ),
                                    ],
                                  ),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                    color: isOutOfStock
                                        ? Colors.grey.shade700
                                        : null,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  'SKU: ${variant.sku ?? '—'}${variant.barcode != null && variant.barcode!.isNotEmpty ? " • ${variant.barcode}" : ""}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      _rupees(_effectiveSellingPrice(variant)),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                        vertical: 1,
                                      ),
                                      decoration: BoxDecoration(
                                        color: !isStockTracked
                                            ? Colors.blue.withValues(
                                                alpha: 0.12,
                                              )
                                            : (stockUnits > 5
                                                ? Colors.green.withValues(
                                                    alpha: 0.12,
                                                  )
                                                : (stockUnits > 0
                                                      ? Colors.orange
                                                          .withValues(
                                                            alpha: 0.15,
                                                          )
                                                      : Colors.red.withValues(
                                                          alpha: 0.15,
                                                        ))),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        !isStockTracked
                                            ? 'Untracked'
                                            : (stockUnits > 5
                                                ? '${l10n?.inStock ?? "In Stock"}: $stockUnits'
                                                : (stockUnits > 0
                                                      ? '${l10n?.lowStock ?? "Low"}: $stockUnits'
                                                      : (l10n?.outOfStock ??
                                                            'Out of stock'))),
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: !isStockTracked
                                              ? Colors.blue.shade800
                                              : (stockUnits > 5
                                                  ? Colors.green.shade800
                                                  : (stockUnits > 0
                                                        ? Colors.orange
                                                            .shade900
                                                        : Colors.red.shade800)),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                onTap: () => onSelected(variant),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                FilterChip(
                  selected: _inStockOnly,
                  label: Text(
                    l10n != null ? '${l10n.inStock} only' : 'In-stock only',
                  ),
                  avatar: Icon(
                    _inStockOnly
                        ? Icons.check_circle
                        : Icons.inventory_2_outlined,
                    size: 16,
                    color: _inStockOnly
                        ? Colors.green.shade800
                        : Colors.blueGrey,
                  ),
                  selectedColor: Colors.green.shade50,
                  checkmarkColor: Colors.green.shade800,
                  onSelected: (val) {
                    setState(() {
                      _inStockOnly = val;
                      _productPickerVersion++;
                    });
                  },
                ),
                SizedBox(
                  width: (_selected != null &&
                          _selected!.trackStock &&
                          ((int.tryParse(_quantity.text) ?? 1) +
                                  _currentCartQuantity(_selected!.variantId) >
                              _availableStockUnits(_selected!)))
                      ? 110
                      : 90,
                  child: TextField(
                    controller: _quantity,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: l10n?.qty ?? 'Qty',
                      errorText: (_selected != null &&
                              _selected!.trackStock &&
                              ((int.tryParse(_quantity.text) ?? 1) +
                                      _currentCartQuantity(
                                        _selected!.variantId,
                                      ) >
                                  _availableStockUnits(_selected!)))
                          ? 'Max: ${(_availableStockUnits(_selected!) - _currentCartQuantity(_selected!.variantId)).clamp(0, 999999)}'
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _discount,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: l10n?.discount ?? 'Discount (₹)',
                      prefixText: '₹',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: (_selected != null &&
                            _selected!.trackStock &&
                            _availableStockUnits(_selected!) <= 0)
                        ? Colors.red.shade700
                        : const Color(0xFF10263D),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: _selected == null ? null : _addLine,
                  icon: Icon(
                    (_selected != null &&
                            _selected!.trackStock &&
                            _availableStockUnits(_selected!) <= 0)
                        ? Icons.block
                        : Icons.add_shopping_cart,
                    size: 18,
                  ),
                  label: Text(
                    (_selected != null &&
                            _selected!.trackStock &&
                            _availableStockUnits(_selected!) <= 0)
                        ? (l10n?.outOfStock ?? 'Out of stock')
                        : (l10n?.addToCart ?? 'Add to cart'),
                  ),
                ),
                if (_lines.isNotEmpty)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: _clearProductSelection,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: Text(
                      l10n?.addAnotherProduct ?? 'Add another product',
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildCartSection(BuildContext context, AppLocalizations? l10n) {
    final totalUnits = _lines.fold<int>(0, (sum, line) => sum + line.quantity);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.blueGrey.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 6,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    const Icon(
                      Icons.shopping_bag_outlined,
                      size: 20,
                      color: Color(0xFF10263D),
                    ),
                    Text(
                      l10n?.cartItems ?? 'Cart Items',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10263D).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${_lines.length} items • $totalUnits ${l10n?.unit ?? "units"}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF10263D),
                        ),
                      ),
                    ),
                  ],
                ),
                if (_lines.isNotEmpty)
                  Text(
                    '${l10n?.subtotal ?? "Subtotal"}: ${_rupees(total.subtotalPaise)}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (_lines.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.remove_shopping_cart_outlined,
                      size: 32,
                      color: Colors.grey.shade400,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    l10n?.cartEmpty ?? 'No items in this bill.',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n?.cartEmptySubtitle ?? 'Scan a barcode or search products above to start billing.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                  ),
                ],
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(
                  Theme.of(context).colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.4),
                ),
                dataRowMinHeight: 48,
                dataRowMaxHeight: 68,
                columns: [
                  DataColumn(
                    label: Text(
                      l10n?.sku ?? 'SKU',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      l10n?.name ?? 'Name',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      l10n?.qty ?? 'Qty',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      l10n?.price ?? 'Price',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      l10n?.discount ?? 'Discount',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      l10n?.taxable ?? 'Taxable',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      l10n?.gst ?? 'GST',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      l10n?.total ?? 'Total',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      l10n?.action ?? 'Action',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
                rows: [
                  for (var index = 0; index < _lines.length; index++)
                    DataRow(
                      cells: [
                        DataCell(
                          Text(
                            _lines[index].sku,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        DataCell(
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                _lines[index].name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                              if (_findBarcodeForVariant(
                                _lines[index].variantId,
                              ).isNotEmpty)
                                Text(
                                  'Barcode: ${_findBarcodeForVariant(_lines[index].variantId)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        DataCell(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(
                                  Icons.remove_circle_outline,
                                  size: 20,
                                ),
                                tooltip: 'Decrease quantity',
                                splashRadius: 16,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 28,
                                  minHeight: 28,
                                ),
                                onPressed: () => _updateLineQuantity(
                                  index,
                                  _lines[index].quantity - 1,
                                ),
                              ),
                              InkWell(
                                onTap: () =>
                                    _promptQuantityEdit(context, index),
                                borderRadius: BorderRadius.circular(4),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: Colors.grey.shade400,
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '${_lines[index].quantity}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.add_circle_outline,
                                  size: 20,
                                ),
                                tooltip: 'Increase quantity',
                                splashRadius: 16,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 28,
                                  minHeight: 28,
                                ),
                                onPressed: () => _updateLineQuantity(
                                  index,
                                  _lines[index].quantity + 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                        DataCell(
                          Text(
                            _rupees(_lines[index].unitPricePaise),
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        DataCell(
                          InkWell(
                            onTap: () => _promptDiscountEdit(context, index),
                            borderRadius: BorderRadius.circular(4),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: _lines[index].discountPaise > 0
                                    ? const Color(0xFFDCFCE7)
                                    : Colors.grey.shade100,
                                border: Border.all(
                                  color: _lines[index].discountPaise > 0
                                      ? const Color(0xFF86EFAC)
                                      : Colors.grey.shade300,
                                ),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _lines[index].discountPaise > 0
                                        ? '-₹${(_lines[index].discountPaise / 100).toStringAsFixed(2)}'
                                        : '₹0.00',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: _lines[index].discountPaise > 0
                                          ? const Color(0xFF15803D)
                                          : Colors.grey.shade600,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(
                                    Icons.edit,
                                    size: 11,
                                    color: Colors.grey.shade600,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        DataCell(
                          Text(
                            _rupees(total.lines[index].taxablePaise),
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        DataCell(
                          _gst
                              ? InkWell(
                                  onTap: () =>
                                      _promptGstRateEdit(context, index),
                                  borderRadius: BorderRadius.circular(4),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primaryContainer
                                          .withValues(alpha: 0.3),
                                      border: Border.all(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary
                                            .withValues(alpha: 0.5),
                                      ),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          '${_lines[index].gstRateBps ~/ 100}%',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Icon(
                                          Icons.edit,
                                          size: 12,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              : Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade200,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    '0%',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                        ),
                        DataCell(
                          Text(
                            _rupees(total.lines[index].lineTotalPaise),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        DataCell(
                          IconButton(
                            tooltip: 'Delete',
                            splashRadius: 18,
                            onPressed: () => setState(() {
                              _lines.removeAt(index);
                              final totalDiscount = _lines.fold<int>(
                                0,
                                (sum, l) => sum + l.discountPaise,
                              );
                              _billDiscount.text =
                                  (totalDiscount / 100).toStringAsFixed(2);
                              _syncPaymentInputsForCurrentTotal();
                            }),
                            icon: Icon(
                              Icons.delete_outline,
                              size: 20,
                              color: Colors.red.shade600,
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
    );
  }

  Widget _buildSummaryAndPaymentConsole(
    BuildContext context,
    AppLocalizations? l10n,
  ) {
    final validation = _validatePayment();
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.blueGrey.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.receipt_long_outlined,
                  size: 20,
                  color: Color(0xFF10263D),
                ),
                const SizedBox(width: 8),
                Text(
                  l10n?.billSummary ?? 'Bill Summary',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _summary(l10n?.subtotal ?? 'Subtotal', total.subtotalPaise),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF16A34A).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFF16A34A).withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.discount_outlined,
                        size: 16,
                        color: Color(0xFF16A34A),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        l10n?.discount ?? 'Discount',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: Color(0xFF15803D),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(
                    width: 120,
                    height: 36,
                    child: TextField(
                      controller: _billDiscount,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      textAlign: TextAlign.end,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF15803D),
                      ),
                      decoration: InputDecoration(
                        prefixText: '₹ ',
                        prefixStyle: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF15803D),
                        ),
                        hintText: '0.00',
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide:
                              const BorderSide(color: Color(0xFF86EFAC)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide:
                              const BorderSide(color: Color(0xFF86EFAC)),
                        ),
                      ),
                      onChanged: _onBillDiscountChanged,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (_gst) ...[
              _summary(l10n?.taxable ?? 'Taxable', total.taxableTotalPaise),
              _summary(
                l10n?.cgstSgst ?? 'CGST + SGST',
                total.cgstPaise + total.sgstPaise,
              ),
            ] else ...[
              _summary(l10n?.gstTurnedOff ?? 'GST (Turned off)', 0),
            ],
            _summary(l10n?.roundOff ?? 'Round off', total.roundOffPaise),
            const SizedBox(height: 10),
            // Grand Total Banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF10263D), Color(0xFF1C3A5E)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF10263D).withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n?.grandTotal ?? 'Grand Total',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            letterSpacing: 0.5,
                          ),
                        ),
                        Text(
                          '${_lines.length} items • ${_gst ? (l10n?.gst ?? "GST") : (l10n?.nonGst ?? "Non-GST")}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _rupees(total.grandTotalPaise),
                    style: const TextStyle(
                      color: Color(0xFFFFD54F),
                      fontWeight: FontWeight.w900,
                      fontSize: 22,
                    ),
                  ),
                ],
              ),
            ),
            if (_gst) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.percent, size: 16),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            l10n?.billGstRate ??
                                'Bill GST Rate (Apply to all):',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: () => _showSetAllGstDialog(context),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
                            child: Text(
                              l10n?.customPercent ?? 'Custom %',
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [0, 5, 12, 18, 28].map((rate) {
                        return ActionChip(
                          label: Text('$rate%'),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          onPressed: () => _applyGstRateToAll(rate * 100),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              l10n?.paymentOption ?? 'PAYMENT OPTION',
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(fontWeight: FontWeight.bold, letterSpacing: 0.5),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  avatar: const Icon(Icons.payments_outlined, size: 16),
                  label: Text(l10n?.paymentModeFullCash ?? 'Full Cash'),
                  selected: _paymentMode == PaymentMode.cash,
                  onSelected: (val) {
                    if (val) _onPaymentModeChanged(PaymentMode.cash);
                  },
                ),
                ChoiceChip(
                  avatar: const Icon(Icons.qr_code_2, size: 16),
                  label: Text(l10n?.paymentModeFullUpi ?? 'Full UPI'),
                  selected: _paymentMode == PaymentMode.upi,
                  onSelected: (val) {
                    if (val) _onPaymentModeChanged(PaymentMode.upi);
                  },
                ),
                ChoiceChip(
                  avatar: const Icon(Icons.call_split, size: 16),
                  label: Text(l10n?.paymentModeSplit ?? 'Partial Cash & UPI'),
                  selected: _paymentMode == PaymentMode.split,
                  onSelected: (val) {
                    if (val) _onPaymentModeChanged(PaymentMode.split);
                  },
                ),
                ChoiceChip(
                  avatar: const Icon(Icons.handshake_outlined, size: 16),
                  label: Text(
                    l10n?.paymentModeUdhaar ?? 'Borrow (Credit / Udhaar)',
                  ),
                  selected: _paymentMode == PaymentMode.udhaar,
                  onSelected: (val) {
                    if (val) _onPaymentModeChanged(PaymentMode.udhaar);
                  },
                ),
              ],
            ),
            const SizedBox(height: 14),
            _buildPaymentInputs(l10n),
            const SizedBox(height: 16),
            if (validation.warningMessage != null) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.5)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.red,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        validation.warningMessage!,
                        style: const TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (validation.infoMessage != null) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.withValues(alpha: 0.5)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.account_balance_wallet,
                      color: Colors.blue,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        validation.infoMessage!,
                        style: const TextStyle(
                          color: Colors.blue,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            SizedBox(
              height: 48,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF10263D),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: _saving || !validation.isValid ? null : _finalize,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check_circle_outline, size: 20),
                label: Text(
                  _saving
                      ? (l10n?.saving ?? 'Saving...')
                      : (l10n?.finalizeAndSaveBill ?? 'FINALIZE & SAVE BILL'),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  _PaymentValidationResult _validatePayment() {
    if (_lines.isEmpty) {
      return const _PaymentValidationResult(isValid: false);
    }
    if (total.grandTotalPaise <= 0) {
      return const _PaymentValidationResult(
        isValid: false,
        warningMessage: 'Bill total must be greater than zero.',
      );
    }

    if (_gst &&
        _gstin.text.trim().isNotEmpty &&
        !CustomerValidators.isValidGstin(_gstin.text)) {
      return const _PaymentValidationResult(
        isValid: false,
        warningMessage: 'Enter a valid 15-character GSTIN or leave it blank.',
      );
    }

    if (_gst &&
        _gstin.text.trim().isEmpty &&
        total.taxableTotalPaise >= 5000000) {
      final hasName = _selectedCustomer != null &&
          _selectedCustomer!.name.trim().isNotEmpty &&
          _selectedCustomer!.name != 'Walk-in Customer';
      final hasAddress = _selectedCustomer?.address != null &&
          _selectedCustomer!.address!.trim().isNotEmpty;
      final hasState = _selectedCustomer?.stateCode != null &&
          _selectedCustomer!.stateCode!.trim().isNotEmpty;
      if (!hasName || !hasAddress || !hasState) {
        return const _PaymentValidationResult(
          isValid: false,
          warningMessage:
              'For GST invoices with taxable supply ?50,000 or more to an unregistered customer, recipient name, address, and state code are mandatory under GST Rule 46.',
        );
      }
    }

    switch (_paymentMode) {
      case PaymentMode.cash:
        final cashReceived = _parseMoney(_cash.text);
        if (cashReceived == null) {
          return const _PaymentValidationResult(
            isValid: false,
            warningMessage: 'Please enter a valid cash amount received.',
          );
        }
        if (cashReceived < total.grandTotalPaise) {
          final short = total.grandTotalPaise - cashReceived;
          return _PaymentValidationResult(
            isValid: false,
            warningMessage:
                'Cash received is short by ₹${_rupees(short)}. Total must match Grand Total (₹${_rupees(total.grandTotalPaise)}).',
          );
        }
        if (cashReceived > total.grandTotalPaise) {
          final excess = cashReceived - total.grandTotalPaise;
          if (_selectedCustomer != null) {
            return _PaymentValidationResult(
              isValid: true,
              infoMessage:
                  'Extra payment of ₹${_rupees(excess)} will be saved in ${_selectedCustomer!.name}\'s advance balance.',
              excessPaise: excess,
            );
          } else {
            return _PaymentValidationResult(
              isValid: true,
              infoMessage: 'Change to return to customer: ₹${_rupees(excess)}',
            );
          }
        }
        return const _PaymentValidationResult(isValid: true);

      case PaymentMode.upi:
        return const _PaymentValidationResult(isValid: true);

      case PaymentMode.split:
        final c = _parseMoney(_cash.text);
        final u = _parseMoney(_upi.text);
        if (c == null || u == null) {
          return const _PaymentValidationResult(
            isValid: false,
            warningMessage: 'Please enter valid Cash and UPI amounts.',
          );
        }
        if (c < 0 || u < 0) {
          return const _PaymentValidationResult(
            isValid: false,
            warningMessage: 'Payment amounts cannot be negative.',
          );
        }
        final sum = c + u;
        if (sum < total.grandTotalPaise) {
          final short = total.grandTotalPaise - sum;
          return _PaymentValidationResult(
            isValid: false,
            warningMessage:
                'Payment mismatch: Short by ₹${_rupees(short)}. Cash (₹${_rupees(c)}) + UPI (₹${_rupees(u)}) must equal Grand Total (₹${_rupees(total.grandTotalPaise)}).',
          );
        }
        if (sum > total.grandTotalPaise) {
          final excess = sum - total.grandTotalPaise;
          if (_selectedCustomer != null) {
            return _PaymentValidationResult(
              isValid: true,
              infoMessage:
                  'Extra payment of ₹${_rupees(excess)} will be stored in ${_selectedCustomer!.name}\'s advance balance.',
              excessPaise: excess,
            );
          } else {
            return _PaymentValidationResult(
              isValid: false,
              warningMessage:
                  'Total payment exceeds bill by ₹${_rupees(excess)}. Select a customer to credit advance or adjust amounts to match.',
            );
          }
        }
        return const _PaymentValidationResult(isValid: true);

      case PaymentMode.udhaar:
        if (_selectedCustomer == null) {
          return const _PaymentValidationResult(
            isValid: false,
            warningMessage:
                'Customer must be selected for Udhaar (Credit / Borrow) bill.',
          );
        }
        final c = _parseMoney(_cash.text) ?? 0;
        final u = _parseMoney(_upi.text) ?? 0;
        if (c < 0 || u < 0) {
          return const _PaymentValidationResult(
            isValid: false,
            warningMessage: 'Down payment amounts cannot be negative.',
          );
        }
        final downPayment = c + u;
        if (downPayment >= total.grandTotalPaise) {
          return const _PaymentValidationResult(
            isValid: false,
            warningMessage: 'Full amount is covered by down payment. Please switch to Cash, UPI, or Partial payment mode.',
          );
        }
        final due = total.grandTotalPaise - downPayment;
        final limit = _selectedCustomer!.creditLimitPaise;
        if (limit != null && (_selectedCustomer!.duePaise + due > limit)) {
          return _PaymentValidationResult(
            isValid: false,
            warningMessage:
                'Bill exceeds customer credit limit of ₹${_rupees(limit)} (Current due: ₹${_rupees(_selectedCustomer!.duePaise)}, New due: ₹${_rupees(due)}).',
          );
        }
        return const _PaymentValidationResult(isValid: true);
    }
  }

  String _paymentModeLabel(PaymentMode mode) {
    switch (mode) {
      case PaymentMode.cash:
        return 'Full Cash';
      case PaymentMode.upi:
        return 'Full UPI';
      case PaymentMode.split:
        return 'Partial Cash & UPI';
      case PaymentMode.udhaar:
        return 'Borrow (Credit / Udhaar)';
    }
  }

  Widget _buildPaymentInputs([AppLocalizations? l10n]) {
    switch (_paymentMode) {
      case PaymentMode.cash:
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.payments_outlined,
                    color: Colors.green,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${l10n?.collectFullCash ?? "Collect Full Cash"}: ₹${_rupees(total.grandTotalPaise)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _cash,
                readOnly: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText:
                      l10n?.cashReceived ?? 'Cash received from customer (₹)',
                  prefixText: '₹ ',
                  suffixIcon: const Tooltip(
                    message: 'Full cash payment (locked to Grand Total)',
                    child: Icon(
                      Icons.lock_outline,
                      size: 18,
                      color: Colors.grey,
                    ),
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
              Builder(
                builder: (_) {
                  final given =
                      _parseMoney(_cash.text) ?? total.grandTotalPaise;
                  final change = given - total.grandTotalPaise;
                  if (change > 0) {
                    if (_selectedCustomer != null) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Extra ₹${_rupees(change)} will be credited to ${_selectedCustomer!.name}\'s advance',
                          style: const TextStyle(
                            color: Colors.blue,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      );
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.check_circle,
                              size: 16,
                              color: Colors.green,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${l10n?.changeToReturn ?? "Change to return"}: ₹${_rupees(change)}',
                              style: const TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  } else if (change < 0) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '${l10n?.shortBy ?? "Short by"}: ₹${_rupees(-change)}',
                        style: const TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ],
          ),
        );

      case PaymentMode.upi:
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.qr_code_2, color: Colors.blue, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n?.collectFullUpi ?? 'Collect Full Amount via UPI',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '₹${_rupees(total.grandTotalPaise)}',
                          style: const TextStyle(
                            color: Colors.blue,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1B5E20),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: total.grandTotalPaise <= 0
                    ? null
                    : () => showUpiPaymentDialog(
                        context,
                        amount: total.grandTotalPaise / 100.0,
                        customerName: _selectedCustomer?.name,
                        note: 'POS Bill Payment',
                      ),
                icon: const Icon(Icons.qr_code_scanner, size: 18),
                label: Text(
                  '${l10n?.showDynamicUpiQr ?? "Show Dynamic UPI QR"} (₹${_rupees(total.grandTotalPaise)})',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        );

      case PaymentMode.split:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _cash,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: l10n?.cashAmount ?? 'Cash Amount (₹)',
                prefixText: '₹ ',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                suffixIcon: IconButton(
                  tooltip: l10n?.setRemainderToCash ?? 'Set remainder to Cash',
                  icon: const Icon(Icons.auto_fix_high, size: 18),
                  onPressed: () {
                    final upi = _parseMoney(_upi.text) ?? 0;
                    final remainder = (total.grandTotalPaise - upi).clamp(
                      0,
                      total.grandTotalPaise,
                    );
                    setState(() {
                      _cash.text = (remainder / 100).toStringAsFixed(2);
                    });
                  },
                ),
              ),
              onChanged: _onSplitCashChanged,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _upi,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: l10n?.upiAmount ?? 'UPI Amount (₹)',
                prefixText: '₹ ',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                suffixIcon: IconButton(
                  tooltip: l10n?.setRemainderToUpi ?? 'Set remainder to UPI',
                  icon: const Icon(Icons.auto_fix_high, size: 18),
                  onPressed: () {
                    final cash = _parseMoney(_cash.text) ?? 0;
                    final remainder = (total.grandTotalPaise - cash).clamp(
                      0,
                      total.grandTotalPaise,
                    );
                    setState(() {
                      _upi.text = (remainder / 100).toStringAsFixed(2);
                    });
                  },
                ),
              ),
              onChanged: _onSplitUpiChanged,
            ),
            Builder(
              builder: (context) {
                final u = _parseMoney(_upi.text) ?? 0;
                if (u <= 0) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () => showUpiPaymentDialog(
                      context,
                      amount: u / 100.0,
                      customerName: _selectedCustomer?.name,
                      note: 'Split UPI payment',
                    ),
                    icon: const Icon(Icons.qr_code_2, size: 18),
                    label: Text(
                      '${l10n?.showUpiQrFor ?? "Show UPI QR for"} ₹${_rupees(u)}',
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            Builder(
              builder: (_) {
                final c = _parseMoney(_cash.text) ?? 0;
                final u = _parseMoney(_upi.text) ?? 0;
                final sum = c + u;
                final diff = total.grandTotalPaise - sum;
                if (diff == 0) {
                  return Row(
                    children: [
                      const Icon(
                        Icons.check_circle,
                        color: Colors.green,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        l10n?.fullAmountAllocated ??
                            'Full amount allocated (Cash + UPI)',
                        style: const TextStyle(
                          color: Colors.green,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  );
                } else if (diff > 0) {
                  return Text(
                    '${l10n?.remainingToAllocate ?? "Remaining to allocate"}: ₹${_rupees(diff)}',
                    style: const TextStyle(
                      color: Colors.red,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  );
                } else {
                  return Text(
                    _selectedCustomer != null
                        ? 'Extra payment of ₹${_rupees(-diff)} will be stored in advance'
                        : 'Over allocated by: ₹${_rupees(-diff)} (select customer to credit advance)',
                    style: TextStyle(
                      color: _selectedCustomer != null
                          ? Colors.blue
                          : Colors.orange,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  );
                }
              },
            ),
          ],
        );

      case PaymentMode.udhaar:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_selectedCustomer == null) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.orange.withValues(alpha: 0.4),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.orange,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            l10n?.borrowRequiresCustomer ??
                                'Borrow requires customer selection',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _showCustomerPicker,
                        icon: const Icon(Icons.person_add_alt, size: 16),
                        label: Text(
                          l10n?.selectAddCustomer ?? 'Select / Add Customer',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ] else ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.person, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Customer: ${_selectedCustomer!.name} (${_selectedCustomer!.phone})',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
            TextField(
              controller: _cash,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText:
                    l10n?.cashDownPayment ?? 'Cash Down Payment (Optional)',
                prefixText: '₹ ',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _upi,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText:
                    l10n?.upiDownPayment ?? 'UPI Down Payment (Optional)',
                prefixText: '₹ ',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
            Builder(
              builder: (context) {
                final u = _parseMoney(_upi.text) ?? 0;
                if (u <= 0) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () => showUpiPaymentDialog(
                      context,
                      amount: u / 100.0,
                      customerName: _selectedCustomer?.name,
                      note: 'Udhaar down payment UPI',
                    ),
                    icon: const Icon(Icons.qr_code_2, size: 18),
                    label: Text(
                      'Show UPI QR for Down Payment (₹${_rupees(u)})',
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 10),
            Builder(
              builder: (context) {
                final c = _parseMoney(_cash.text) ?? 0;
                final u = _parseMoney(_upi.text) ?? 0;
                final paid = c + u;
                final due = (total.grandTotalPaise - paid).clamp(
                  0,
                  total.grandTotalPaise,
                );
                final hasDue = due > 0;
                return OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: hasDue
                      ? () async {
                          final now = DateTime.now();
                          final picked = await showDatePicker(
                            context: context,
                            initialDate:
                                _dueDate ?? now.add(const Duration(days: 30)),
                            firstDate: now,
                            lastDate: now.add(const Duration(days: 365)),
                          );
                          if (picked != null) {
                            setState(() => _dueDate = picked);
                          }
                        }
                      : null,
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: Text(
                    !hasDue
                        ? 'No Due Date (Fully Paid in Cash)'
                        : (_dueDate == null
                            ? (l10n?.setRepaymentDueDate ??
                                'Set Repayment Due Date (Optional)')
                            : '${l10n?.dueDate ?? "Due Date"}: ${_dueDate!.day}/${_dueDate!.month}/${_dueDate!.year}'),
                  ),
                );
              },
            ),
            const SizedBox(height: 10),
            Builder(
              builder: (_) {
                final c = _parseMoney(_cash.text) ?? 0;
                final u = _parseMoney(_upi.text) ?? 0;
                final paid = c + u;
                final due = (total.grandTotalPaise - paid).clamp(
                  0,
                  total.grandTotalPaise,
                );
                return Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.red.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${l10n?.amountBorrowedDue ?? "Amount Borrowed (Due)"}:',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                        ),
                      ),
                      Text(
                        '₹${_rupees(due)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.red,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        );
    }
  }

  Widget _customerCard([AppLocalizations? l10n]) => Card(
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: Colors.blueGrey.withValues(alpha: 0.18)),
    ),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF10263D).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.person_outline,
                  size: 20,
                  color: Color(0xFF10263D),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _selectedCustomer == null
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n?.walkInCustomer ?? 'Walk-in Customer',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            'General retail billing',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  _selectedCustomer!.name.isEmpty
                                      ? 'Customer'
                                      : _selectedCustomer!.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              if (_selectedCustomer!.customerType == CustomerModel.typeBusiness)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: Colors.purple.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'Business',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.purple.shade700,
                                    ),
                                  ),
                                )
                              else if (_selectedCustomer!.customerType == CustomerModel.typeIndividual)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: Colors.teal.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'Individual',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.teal.shade700,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          Text(
                            _selectedCustomer!.phone,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: _showCustomerPicker,
                icon: const Icon(Icons.person_search_outlined, size: 16),
                label: Text(
                  _selectedCustomer == null
                      ? (l10n?.selectCustomer ?? 'Select Customer')
                      : (l10n?.change ?? 'Change'),
                ),
              ),
              if (_selectedCustomer != null)
                IconButton(
                  tooltip: 'Use walk-in customer',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() {
                    _selectedCustomer = null;
                    _gstin.clear();
                  }),
                  icon: const Icon(Icons.clear, size: 18),
                ),
            ],
          ),
          if (_selectedCustomer != null) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (_selectedCustomer!.duePaise > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${l10n?.due ?? "Due"}: ₹${_rupees(_selectedCustomer!.duePaise)}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.red,
                      ),
                    ),
                  ),
                if (_selectedCustomer!.advancePaise > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${l10n?.advance ?? "Advance"}: ₹${_rupees(_selectedCustomer!.advancePaise)}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.green.shade800,
                      ),
                    ),
                  ),
                if (_selectedCustomer!.creditLimitPaise != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${l10n?.limit ?? "Limit"}: ₹${_rupees(_selectedCustomer!.creditLimitPaise!)}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.blue.shade800,
                      ),
                    ),
                  ),
                if (_selectedCustomer!.isGstRegistered &&
                    _selectedCustomer!.gstin != null &&
                    _selectedCustomer!.gstin!.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'GSTIN: ${_selectedCustomer!.gstin}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.blue.shade800,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    ),
  );

  Widget _gstinField([AppLocalizations? l10n]) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: _gstin,
      textCapitalization: TextCapitalization.characters,
      decoration: InputDecoration(
        labelText: l10n?.customerGstin ?? 'Customer GSTIN (optional)',
        hintText: l10n?.customerGstinHint ?? 'Enter GSTIN for this GST bill',
        prefixIcon: const Icon(Icons.receipt_long_outlined, size: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
      ),
      onChanged: (value) {
        final normalized = value.trim().toUpperCase();
        if (normalized != value) {
          _gstin.value = _gstin.value.copyWith(
            text: normalized,
            selection: TextSelection.collapsed(offset: normalized.length),
          );
        }
      },
    ),
  );

  Future<void> _showCustomerPicker() async {
    final appContext = controller.appContext;
    final token = controller.idToken;
    final repository = controller.customerRepository;
    if (appContext?.businessId == null || token == null || repository == null) {
      _message('Sign in and select a business before choosing a customer.');
      return;
    }
    try {
      _customers = await repository.search(
        tenantId: appContext!.ownerUid,
        businessId: appContext.businessId!,
        token: token,
      );
    } catch (error) {
      _message('Could not load customers: $error');
      return;
    } finally {}
    if (!mounted) return;
    final selected = await showDialog<CustomerModel>(
      context: context,
      builder: (dialogContext) {
        var query = '';
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final filtered = _customers.where((customer) {
              final value = query.toLowerCase();
              return value.isEmpty ||
                  customer.nameLower.contains(value) ||
                  customer.phone.contains(value) ||
                  (customer.gstin ?? '').toLowerCase().contains(value);
            }).toList();
            return AlertDialog(
              title: const Text('Select customer'),
              content: SizedBox(
                width: 520,
                height: 420,
                child: Column(
                  children: [
                    TextField(
                      autofocus: true,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        labelText: 'Search name, phone or GSTIN',
                      ),
                      onChanged: (value) =>
                          setDialogState(() => query = value.trim()),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(child: Text('No customers found.'))
                          : ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (_, index) {
                                final customer = filtered[index];
                                return ListTile(
                                  leading: const CircleAvatar(
                                    child: Icon(Icons.person_outline),
                                  ),
                                  title: Text(
                                    customer.name.isEmpty
                                        ? 'Customer'
                                        : customer.name,
                                  ),
                                  subtitle: Text(
                                    '${customer.phone}'
                                    '${customer.creditLimitPaise != null ? ' • Limit: ₹${_rupees(customer.creditLimitPaise!)}' : ''}',
                                  ),
                                  trailing: customer.duePaise > 0
                                      ? Text(
                                          'Due ₹${_rupees(customer.duePaise)}',
                                          style: const TextStyle(
                                            color: Colors.red,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        )
                                      : customer.advancePaise > 0
                                      ? Text(
                                          'Advance ₹${_rupees(customer.advancePaise)}',
                                          style: const TextStyle(
                                            color: Colors.green,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        )
                                      : const Text(
                                          'Settled ₹0.00',
                                          style: TextStyle(color: Colors.grey),
                                        ),
                                  onTap: () =>
                                      Navigator.pop(dialogContext, customer),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    final created = await _showAddCustomer();
                    if (created != null && context.mounted) {
                      Navigator.pop(dialogContext, created);
                    }
                  },
                  child: const Text('Add new customer'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
              ],
            );
          },
        );
      },
    );
    if (selected != null && mounted) {
      setState(() {
        _selectedCustomer = selected;
        if (selected.isGstRegistered &&
            selected.gstin != null &&
            selected.gstin!.trim().isNotEmpty &&
            CustomerValidators.isValidGstin(selected.gstin)) {
          _gstin.text = CustomerValidators.normalizeGstin(selected.gstin);
        } else {
          _gstin.clear();
        }
      });
    }
  }

  Future<CustomerModel?> _showAddCustomer() async {
    final appContext = controller.appContext;
    final token = controller.idToken;
    final repository = controller.customerRepository;
    if (appContext?.businessId == null || token == null || repository == null) {
      _message('Customer service is unavailable. Please sign in again.');
      return null;
    }
    return showDialog<CustomerModel>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add new customer'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: CustomerForm(
              repository: repository,
              tenantId: appContext!.ownerUid,
              businessId: appContext.businessId!,
              token: token,
              onSaved: (customer) => Navigator.pop(context, customer),
            ),
          ),
        ),
      ),
    );
  }

  void _addLine() {
    final variant = _selected;
    if (variant == null) return;
    final quantity = int.tryParse(_quantity.text) ?? 0;
    final discount = _parseMoney(_discount.text) ?? 0;
    final gstRate = _gst ? (double.tryParse(_gstRate.text.trim()) ?? 0.0) : 0.0;
    if (quantity <= 0) return;

    if (variant.trackStock) {
      final available = _availableStockUnits(variant);
      final inCart = _currentCartQuantity(variant.variantId);
      if (available <= 0) {
        _showStockAlert(
          title: 'Out of Stock Alert',
          message:
              'Quantity cannot be billed because "${variant.displayName}" has 0 available stock in store.',
          productName: variant.displayName,
          availableStock: 0,
          requestedQty: quantity,
        );
        _message(
          'Out of Stock: "${variant.displayName}" has 0 available stock and cannot be added to the bill.',
          isError: true,
        );
        return;
      }
      if (inCart + quantity > available) {
        _showStockAlert(
          title: 'Insufficient Stock Alert',
          message:
              'Quantity cannot be greater than stock quantity! You requested $quantity units of "${variant.displayName}", but only $available units are available in store${inCart > 0 ? " ($inCart already in cart)" : ""}.',
          productName: variant.displayName,
          availableStock: available,
          requestedQty: inCart + quantity,
          onAdjustToMax: () {
            final maxCanAdd = available - inCart;
            if (maxCanAdd > 0) {
              setState(() => _quantity.text = maxCanAdd.toString());
            }
          },
        );
        _message(
          'Insufficient Stock: Cannot add $quantity units of "${variant.displayName}". Only $available available in stock${inCart > 0 ? ' (Cart already has $inCart)' : ''}.',
          isError: true,
        );
        return;
      }
    }
    if (_gst && (gstRate < 0 || gstRate > 100)) {
      _message('Enter a valid GST rate between 0 and 100%.');
      return;
    }

    final enteredSelling = _parseMoney(_sellingPrice.text);
    final enteredMrp = _parseMoney(_mrp.text);
    final effectiveSelling = (enteredSelling != null && enteredSelling > 0)
        ? enteredSelling
        : _effectiveSellingPrice(variant);
    final effectiveMrp = (enteredMrp != null && enteredMrp > 0)
        ? enteredMrp
        : _effectiveMrp(variant);

    if (effectiveSelling <= 0) {
      _message('Enter a selling price greater than ₹0.00 before adding to cart.');
      return;
    }

    if (effectiveMrp > 0 && effectiveSelling > effectiveMrp) {
      _message('Selling price cannot exceed MRP.');
      return;
    }

    final lineGstRateBps = _gst ? (gstRate * 100).round() : 0;
    final existingIndex = _lines.indexWhere(
      (line) => line.variantId == variant.variantId,
    );

    if (enteredSelling != null && enteredSelling > 0) {
      if (variant.sellingPrice <= 0 ||
          (enteredMrp != null && enteredMrp > 0 && variant.mrp <= 0)) {
        _autoPersistPricing(
          variant: variant,
          sellingPrice: enteredSelling,
          mrp: (enteredMrp != null && enteredMrp > 0) ? enteredMrp : effectiveMrp,
          gstRateBps: lineGstRateBps > 0 ? lineGstRateBps : variant.defaultGstRateBps,
        );
      }
    }

    setState(() {
      if (existingIndex >= 0) {
        final existing = _lines[existingIndex];
        _lines[existingIndex] = BillLineInput(
          variantId: existing.variantId,
          sku: existing.sku,
          name: existing.name,
          hsn: existing.hsn,
          quantity: existing.quantity + quantity,
          unitPricePaise: effectiveSelling,
          gstRateBps: lineGstRateBps,
          discountPaise: existing.discountPaise + discount,
          unit: existing.unit,
          conversionFactor: existing.conversionFactor,
          trackStock: existing.trackStock,
          priceIncludesTax: existing.priceIncludesTax,
          batchId: existing.batchId ?? _selectedBatch?.batchId,
        );
      } else {
        _lines.add(
          BillLineInput(
            variantId: variant.variantId,
            sku: variant.sku ?? variant.variantId,
            name: variant.displayName,
            hsn: variant.hsnCode ?? '',
            quantity: quantity,
            unitPricePaise: effectiveSelling,
            gstRateBps: lineGstRateBps,
            discountPaise: discount,
            unit: variant.commercialUnitName ?? variant.baseUnitId,
            conversionFactor: variant.baseQuantityPerCommercialUnit.toInt(),
            trackStock: variant.trackStock,
            priceIncludesTax: variant.priceIncludesTax,
            batchId: _selectedBatch?.batchId,
          ),
        );
      }
      _clearProductSelection();
      final totalDiscount =
          _lines.fold<int>(0, (sum, l) => sum + l.discountPaise);
      _billDiscount.text = (totalDiscount / 100).toStringAsFixed(2);
      _syncPaymentInputsForCurrentTotal();
    });
  }

  Future<void> _autoPersistPricing({
    required ProductVariantModel variant,
    required int sellingPrice,
    required int mrp,
    required int gstRateBps,
  }) async {
    try {
      final appContext = controller.appContext;
      final token = controller.idToken;
      final prodId = variant.productId ??
          controller.products
              .where((p) => p.variants.any((v) => v.variantId == variant.variantId))
              .firstOrNull
              ?.productId ??
          variant.variantId;
      if (appContext?.businessId == null || token == null) return;

      await controller.productRepository.updateVariantPricing(
        tenantId: appContext!.ownerUid,
        businessId: appContext.businessId!,
        productId: prodId,
        variantId: variant.variantId,
        sellingPrice: sellingPrice,
        mrp: mrp > 0 ? mrp : sellingPrice,
        gstRateBps: gstRateBps,
        actorUid: appContext.uid,
        token: token,
        makeDefaultForProduct: false,
      );
      await controller.loadProducts();
      await _loadPricing();
    } catch (e) {
      debugPrint('Failed to auto-persist variant pricing: $e');
    }
  }

  Future<bool> _addOrIncrementVariant(
    ProductVariantModel variant, [
    int quantity = 1,
    VariantBatchPriceOption? selectedBatch,
  ]) async {
    if (quantity <= 0) quantity = 1;

    if (variant.trackStock) {
      final available = _availableStockUnits(variant);
      final inCart = _currentCartQuantity(variant.variantId);
      if (available <= 0) {
        _showStockAlert(
          title: 'Out of Stock Alert',
          message:
              'Quantity cannot be billed because "${variant.displayName}" has 0 available stock in store.',
          productName: variant.displayName,
          availableStock: 0,
          requestedQty: quantity,
        );
        _message(
          'Out of Stock: "${variant.displayName}" has 0 available stock and cannot be added to the bill.',
          isError: true,
        );
        return false;
      }
      if (inCart + quantity > available) {
        _showStockAlert(
          title: 'Insufficient Stock Alert',
          message:
              'Quantity cannot be greater than stock quantity! Requested ${inCart + quantity} units of "${variant.displayName}", but only $available units are available in store${inCart > 0 ? " ($inCart already in cart)" : ""}.',
          productName: variant.displayName,
          availableStock: available,
          requestedQty: inCart + quantity,
        );
        _message(
          'Insufficient Stock: Cannot add $quantity units of "${variant.displayName}". Only $available available in stock${inCart > 0 ? ' (Cart already has $inCart)' : ''}.',
          isError: true,
        );
        return false;
      }
    }

    VariantBatchPriceOption? batch = selectedBatch;
    if (batch == null) {
      final batches = await _getVariantBatches(variant.variantId);
      final activeBatches = batches.where((b) => b.availableQty > 0).toList();
      final distinctPrices = activeBatches
          .map((b) => b.sellingPricePaise)
          .where((p) => p > 0)
          .toSet();

      if (distinctPrices.length > 1) {
        if (!mounted) return false;
        final chosen = await showDialog<VariantBatchPriceOption>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => _LotPriceSelectionDialog(
            variant: variant,
            batches: activeBatches,
          ),
        );
        if (chosen == null) {
          return false;
        }
        batch = chosen;
      } else if (activeBatches.isNotEmpty) {
        batch = activeBatches.first;
      }
    }

    final price = (batch != null && batch.sellingPricePaise > 0)
        ? batch.sellingPricePaise
        : _effectiveSellingPrice(variant);

    final existingIndex = _lines.indexWhere(
      (line) =>
          line.variantId == variant.variantId &&
          line.unitPricePaise == price,
    );
    final targetGstBps = _gst
        ? (_billGstRateBps ?? variant.defaultGstRateBps)
        : 0;

    if (price <= 0 && (existingIndex < 0 || _lines[existingIndex].unitPricePaise <= 0)) {
      setState(() {
        _selected = variant;
        _sellingPrice.text = '';
        final effMrp = (batch != null && batch.mrpPaise > 0)
            ? batch.mrpPaise
            : _effectiveMrp(variant);
        _mrp.text = effMrp > 0 ? _formatMoney(effMrp) : '';
        final effectiveRate = _gst ? (_billGstRateBps ?? variant.defaultGstRateBps) : 0;
        _gstRate.text = (effectiveRate / 100).toStringAsFixed(2);
      });
      _message('Please set selling price for ${variant.displayName} before adding to bill.');
      return false;
    }

    setState(() {
      if (existingIndex >= 0) {
        final existing = _lines[existingIndex];
        _lines[existingIndex] = BillLineInput(
          variantId: existing.variantId,
          sku: existing.sku,
          name: existing.name,
          hsn: existing.hsn,
          quantity: existing.quantity + quantity,
          unitPricePaise: existing.unitPricePaise > 0
              ? existing.unitPricePaise
              : price,
          gstRateBps: _gst ? existing.gstRateBps : 0,
          discountPaise: existing.discountPaise,
          unit: existing.unit,
          conversionFactor: existing.conversionFactor,
          trackStock: existing.trackStock,
          priceIncludesTax: existing.priceIncludesTax,
          batchId: existing.batchId ?? batch?.batchId,
        );
      } else {
        _lines.add(
          BillLineInput(
            variantId: variant.variantId,
            sku: variant.sku ?? variant.variantId,
            name: variant.displayName,
            hsn: variant.hsnCode ?? '',
            quantity: quantity,
            unitPricePaise: price,
            gstRateBps: targetGstBps,
            discountPaise: 0,
            unit: variant.commercialUnitName ?? variant.baseUnitId,
            conversionFactor: variant.baseQuantityPerCommercialUnit.toInt(),
            trackStock: variant.trackStock,
            priceIncludesTax: variant.priceIncludesTax,
            batchId: batch?.batchId,
          ),
        );
      }
      _syncPaymentInputsForCurrentTotal();
    });

    final totalQty = existingIndex >= 0
        ? _lines[existingIndex].quantity
        : quantity;
    _message('Added ${variant.displayName} (Qty: $totalQty)');
    return true;
  }

  void _updateLineQuantity(int index, int newQty) {
    if (index < 0 || index >= _lines.length) return;
    if (newQty <= 0) {
      setState(() {
        _lines.removeAt(index);
        final totalDiscount =
            _lines.fold<int>(0, (sum, l) => sum + l.discountPaise);
        _billDiscount.text = (totalDiscount / 100).toStringAsFixed(2);
        _syncPaymentInputsForCurrentTotal();
      });
      return;
    }
    final line = _lines[index];
    if (line.trackStock && newQty > line.quantity) {
      final variant =
          variants.where((v) => v.variantId == line.variantId).firstOrNull;
      final rawStock = controller.productStock[line.variantId] ?? 0;
      final available = variant != null
          ? _availableStockUnits(variant)
          : (rawStock >= 1000 ? (rawStock / 1000).floor() : rawStock);
      if (newQty > available) {
        _showStockAlert(
          title: 'Stock Limit Reached',
          message:
              'Quantity cannot be greater than stock quantity! Cannot increase quantity to $newQty for "${line.name}" because only $available units are available in store.',
          productName: line.name,
          availableStock: available,
          requestedQty: newQty,
        );
        _message(
          'Insufficient Stock: Cannot set quantity to $newQty for "${line.name}". Only $available available in stock.',
          isError: true,
        );
        return;
      }
    }
    setState(() {
      _lines[index] = BillLineInput(
        variantId: line.variantId,
        sku: line.sku,
        name: line.name,
        hsn: line.hsn,
        quantity: newQty,
        unitPricePaise: line.unitPricePaise,
        gstRateBps: line.gstRateBps,
        priceIncludesTax: line.priceIncludesTax,
        discountPaise: line.discountPaise,
        unit: line.unit,
        conversionFactor: line.conversionFactor,
        trackStock: line.trackStock,
        batchId: line.batchId,
      );
      _syncPaymentInputsForCurrentTotal();
    });
  }

  Future<void> _promptQuantityEdit(BuildContext context, int index) async {
    final currentQty = _lines[index].quantity;
    final qtyController = TextEditingController(text: currentQty.toString());
    final result = await showDialog<int>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('Adjust Quantity for ${_lines[index].name}'),
        content: TextField(
          controller: qtyController,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'Quantity',
            prefixIcon: Icon(Icons.numbers),
          ),
          onSubmitted: (val) {
            final parsed = int.tryParse(val.trim());
            Navigator.pop(dialogCtx, parsed);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final parsed = int.tryParse(qtyController.text.trim());
              Navigator.pop(dialogCtx, parsed);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != null && result > 0) {
      final line = _lines[index];
      if (line.trackStock) {
        final variant =
            variants.where((v) => v.variantId == line.variantId).firstOrNull;
        final rawStock = controller.productStock[line.variantId] ?? 0;
        final available = variant != null
            ? _availableStockUnits(variant)
            : (rawStock >= 1000 ? (rawStock / 1000).floor() : rawStock);
        if (result > available) {
          _showStockAlert(
            title: 'Insufficient Stock Alert',
            message:
                'Quantity cannot be greater than stock quantity! Cannot set quantity to $result for "${line.name}" because only $available units are available in store.',
            productName: line.name,
            availableStock: available,
            requestedQty: result,
            onAdjustToMax: () => _updateLineQuantity(index, available),
          );
          _message(
            'Insufficient Stock: Cannot set quantity to $result for "${line.name}". Only $available available in stock.',
            isError: true,
          );
          return;
        }
      }
      _updateLineQuantity(index, result);
    }
  }

  void _onBillDiscountChanged(String value) {
    final discountRupees = double.tryParse(value.trim()) ?? 0.0;
    final totalDiscountPaise = (discountRupees * 100).round();
    _distributeBillDiscount(totalDiscountPaise);
  }

  void _distributeBillDiscount(int totalDiscountPaise) {
    if (_lines.isEmpty) return;
    final grossTotal = _lines.fold<int>(
      0,
      (sum, l) => sum + (l.quantity * l.unitPricePaise),
    );
    if (grossTotal <= 0) return;

    final effectiveDiscount = totalDiscountPaise.clamp(0, grossTotal);
    var allocated = 0;
    setState(() {
      for (var i = 0; i < _lines.length; i++) {
        final l = _lines[i];
        final lineGross = l.quantity * l.unitPricePaise;
        int lineDiscount;
        if (i == _lines.length - 1) {
          lineDiscount = effectiveDiscount - allocated;
        } else {
          lineDiscount = (effectiveDiscount * lineGross / grossTotal).round();
          allocated += lineDiscount;
        }
        _lines[i] = BillLineInput(
          variantId: l.variantId,
          sku: l.sku,
          name: l.name,
          hsn: l.hsn,
          quantity: l.quantity,
          unit: l.unit,
          conversionFactor: l.conversionFactor,
          trackStock: l.trackStock,
          unitPricePaise: l.unitPricePaise,
          discountPaise: lineDiscount.clamp(0, lineGross),
          gstRateBps: l.gstRateBps,
          priceIncludesTax: l.priceIncludesTax,
        );
      }
      _syncPaymentInputsForCurrentTotal();
    });
  }

  Future<void> _promptDiscountEdit(BuildContext context, int index) async {
    final line = _lines[index];
    final lineGross = line.quantity * line.unitPricePaise;
    final currentDiscountRupees =
        (line.discountPaise / 100).toStringAsFixed(2);
    final discountController =
        TextEditingController(text: currentDiscountRupees);
    final result = await showDialog<double>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('Edit Discount for ${line.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Item Gross Total: ${_rupees(lineGross)}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: discountController,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Discount (₹)',
                prefixText: '₹ ',
                prefixIcon: Icon(Icons.discount_outlined),
              ),
              onSubmitted: (val) {
                final parsed = double.tryParse(val.trim());
                Navigator.pop(dialogCtx, parsed);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final parsed = double.tryParse(discountController.text.trim());
              Navigator.pop(dialogCtx, parsed);
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    if (result != null && result >= 0) {
      final newDiscountPaise = (result * 100).round().clamp(0, lineGross);
      setState(() {
        _lines[index] = BillLineInput(
          variantId: line.variantId,
          sku: line.sku,
          name: line.name,
          hsn: line.hsn,
          quantity: line.quantity,
          unit: line.unit,
          conversionFactor: line.conversionFactor,
          trackStock: line.trackStock,
          unitPricePaise: line.unitPricePaise,
          discountPaise: newDiscountPaise,
          gstRateBps: line.gstRateBps,
          priceIncludesTax: line.priceIncludesTax,
        );
        final totalDiscount =
            _lines.fold<int>(0, (sum, l) => sum + l.discountPaise);
        _billDiscount.text = (totalDiscount / 100).toStringAsFixed(2);
        _syncPaymentInputsForCurrentTotal();
      });
    }
  }

  String _findBarcodeForVariant(String variantId) {
    for (final product in controller.products) {
      for (final variant in product.variants) {
        if (variant.variantId == variantId &&
            variant.barcode != null &&
            variant.barcode!.trim().isNotEmpty) {
          return variant.barcode!.trim();
        }
      }
    }
    return '';
  }

  ProductVariantModel? _findVariantById(String variantId) {
    for (final product in controller.products) {
      for (final variant in product.variants) {
        if (variant.variantId == variantId) {
          return variant;
        }
      }
    }
    return null;
  }

  void _onTaxModeChanged(bool isGst) {
    setState(() {
      _gst = isGst;
      if (!_gst) {
        // Non-GST: turn off GST, set GST to zero for all items, do not add GST
        for (var i = 0; i < _lines.length; i++) {
          final l = _lines[i];
          _lines[i] = BillLineInput(
            variantId: l.variantId,
            sku: l.sku,
            name: l.name,
            hsn: l.hsn,
            quantity: l.quantity,
            unitPricePaise: l.unitPricePaise,
            gstRateBps: 0,
            priceIncludesTax: l.priceIncludesTax,
            discountPaise: l.discountPaise,
            unit: l.unit,
            conversionFactor: l.conversionFactor,
            trackStock: l.trackStock,
          );
        }
        _gstRate.text = '0.00';
      } else {
        // GST: restore default GST rates or applied bill rate
        for (var i = 0; i < _lines.length; i++) {
          final l = _lines[i];
          final v = _findVariantById(l.variantId);
          final rate =
              _billGstRateBps ??
              ((v != null && v.defaultGstRateBps > 0)
                  ? v.defaultGstRateBps
                  : 1800);
          _lines[i] = BillLineInput(
            variantId: l.variantId,
            sku: l.sku,
            name: l.name,
            hsn: l.hsn,
            quantity: l.quantity,
            unitPricePaise: l.unitPricePaise,
            gstRateBps: rate,
            priceIncludesTax: l.priceIncludesTax,
            discountPaise: l.discountPaise,
            unit: l.unit,
            conversionFactor: l.conversionFactor,
            trackStock: l.trackStock,
          );
        }
        if (_selected != null) {
          final rate = _billGstRateBps != null
              ? (_billGstRateBps! / 100).toStringAsFixed(2)
              : (_selected!.defaultGstRateBps / 100).toStringAsFixed(2);
          _gstRate.text = rate;
        }
      }
      _syncPaymentInputsForCurrentTotal();
    });
  }

  void _applyGstRateToAll(int rateBps) {
    if (!_gst) return;
    setState(() {
      _billGstRateBps = rateBps;
      for (var i = 0; i < _lines.length; i++) {
        final l = _lines[i];
        _lines[i] = BillLineInput(
          variantId: l.variantId,
          sku: l.sku,
          name: l.name,
          hsn: l.hsn,
          quantity: l.quantity,
          unitPricePaise: l.unitPricePaise,
          gstRateBps: rateBps,
          priceIncludesTax: l.priceIncludesTax,
          discountPaise: l.discountPaise,
          unit: l.unit,
          conversionFactor: l.conversionFactor,
          trackStock: l.trackStock,
        );
      }
      if (_selected != null) {
        _gstRate.text = (rateBps / 100).toStringAsFixed(2);
      }
      _syncPaymentInputsForCurrentTotal();
    });
  }

  void _updateLineGstRate(int index, int newGstRateBps) {
    if (index < 0 || index >= _lines.length) return;
    setState(() {
      final line = _lines[index];
      _lines[index] = BillLineInput(
        variantId: line.variantId,
        sku: line.sku,
        name: line.name,
        hsn: line.hsn,
        quantity: line.quantity,
        unitPricePaise: line.unitPricePaise,
        gstRateBps: newGstRateBps,
        priceIncludesTax: line.priceIncludesTax,
        discountPaise: line.discountPaise,
        unit: line.unit,
        conversionFactor: line.conversionFactor,
        trackStock: line.trackStock,
        batchId: line.batchId,
      );
      _syncPaymentInputsForCurrentTotal();
    });
  }

  Future<void> _promptGstRateEdit(BuildContext context, int index) async {
    if (index < 0 || index >= _lines.length || !_gst) return;
    final currentLine = _lines[index];
    final currentGstPercent = (currentLine.gstRateBps / 100).toStringAsFixed(
      currentLine.gstRateBps % 100 == 0 ? 0 : 2,
    );
    final textController = TextEditingController(text: currentGstPercent);
    final standardRates = [0, 5, 12, 18, 28];

    final result = await showDialog<double>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Edit GST Rate'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              currentLine.name,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            const Text(
              'Select standard rate:',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: standardRates.map((rate) {
                return ActionChip(
                  label: Text('$rate%'),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => Navigator.pop(dialogCtx, rate.toDouble()),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: textController,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Custom GST Rate (%)',
                suffixText: '%',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (val) {
                final parsed = double.tryParse(val.trim());
                if (parsed != null && parsed >= 0 && parsed <= 100) {
                  Navigator.pop(dialogCtx, parsed);
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final parsed = double.tryParse(textController.text.trim());
              if (parsed != null && parsed >= 0 && parsed <= 100) {
                Navigator.pop(dialogCtx, parsed);
              }
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );

    if (result != null) {
      _updateLineGstRate(index, (result * 100).round());
    }
  }

  Future<void> _showSetAllGstDialog(BuildContext context) async {
    if (!_gst) return;
    final textController = TextEditingController();
    final result = await showDialog<double>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Set Bill GST Rate'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter the GST percentage to calculate on the total amount and apply to all items in this bill:',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: textController,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'GST Rate (%)',
                suffixText: '%',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (val) {
                final parsed = double.tryParse(val.trim());
                if (parsed != null && parsed >= 0 && parsed <= 100) {
                  Navigator.pop(dialogCtx, parsed);
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final parsed = double.tryParse(textController.text.trim());
              if (parsed != null && parsed >= 0 && parsed <= 100) {
                Navigator.pop(dialogCtx, parsed);
              }
            },
            child: const Text('Apply to All'),
          ),
        ],
      ),
    );

    if (result != null) {
      _applyGstRateToAll((result * 100).round());
    }
  }

  void _clearProductSelection() {
    setState(() {
      _selected = null;
      _selectedBatch = null;
      _productPickerVersion++;
      _quantity.text = '1';
      _discount.text = '0.00';
      _sellingPrice.clear();
      _mrp.clear();
      _gstRate.clear();
    });
  }

  Future<void> _savePricing() async {
    final variant = _selected;
    final appContext = controller.appContext;
    final token = controller.idToken;
    final prodId = variant?.productId ??
        controller.products
            .where((p) => p.variants.any((v) => v.variantId == variant?.variantId))
            .firstOrNull
            ?.productId ??
        variant?.variantId;
    if (variant == null ||
        prodId == null ||
        appContext?.businessId == null ||
        token == null) {
      return;
    }
    final sellingPrice = _parseMoney(_sellingPrice.text);
    final mrp = _parseMoney(_mrp.text);
    final gstRate = _gst
        ? double.tryParse(_gstRate.text.trim())
        : (variant.defaultGstRateBps / 100);
    if (sellingPrice == null ||
        mrp == null ||
        gstRate == null ||
        gstRate < 0 ||
        gstRate > 100) {
      _message('Enter valid selling price, MRP, and GST rate.');
      return;
    }
    if (mrp > 0 && sellingPrice > mrp) {
      _message('Selling price cannot exceed MRP.');
      return;
    }
    setState(() => _saving = true);
    try {
      await controller.productRepository.updateVariantPricing(
        tenantId: appContext!.ownerUid,
        businessId: appContext.businessId!,
        productId: prodId,
        variantId: variant.variantId,
        sellingPrice: sellingPrice,
        mrp: mrp,
        gstRateBps: (gstRate * 100).round(),
        actorUid: appContext.uid,
        token: token,
        makeDefaultForProduct: _makeDefaultPrice,
      );
      await controller.loadProducts();
      await _loadPricing();
      final updated = variants.where(
        (item) => item.variantId == variant.variantId,
      );
      if (mounted) {
        setState(() {
          if (updated.isNotEmpty) _selected = updated.first;
        });
        _message(
          _makeDefaultPrice
              ? 'Prices saved and made default for this product.'
              : 'Prices saved for this variant.',
        );
      }
    } catch (error) {
      if (mounted) _message('$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _formatMoney(int paise) =>
      '${paise ~/ 100}.${(paise % 100).toString().padLeft(2, '0')}';

  int? _parseMoney(String value) {
    final normalized = value.trim().replaceAll(',', '');
    if (!RegExp(r'^\d+(?:\.\d{1,2})?$').hasMatch(normalized)) {
      return null;
    }
    final parts = normalized.split('.');
    final rupees = int.tryParse(parts.first);
    if (rupees == null) return null;
    final paise = parts.length == 1 ? 0 : int.parse(parts[1].padRight(2, '0'));
    return rupees * 100 + paise;
  }

  Future<void> _finalize() async {
    final token = controller.idToken;
    final context = controller.appContext;
    final outlet = controller.currentOutlet;
    if (token == null || context?.businessId == null || outlet == null) return;
    final appContext = context!;
    final validation = _validatePayment();
    if (!validation.isValid) {
      if (validation.warningMessage != null) {
        _message(validation.warningMessage!);
      }
      return;
    }

    int cash = 0;
    int upi = 0;
    int due = 0;
    DateTime? dueDate = _dueDate;

    switch (_paymentMode) {
      case PaymentMode.cash:
        final cashReceived = _parseMoney(_cash.text) ?? total.grandTotalPaise;
        if (_selectedCustomer != null && cashReceived > total.grandTotalPaise) {
          cash = cashReceived;
        } else {
          cash = total.grandTotalPaise;
        }
        upi = 0;
        due = 0;
        dueDate = null;
        break;

      case PaymentMode.upi:
        cash = 0;
        upi = total.grandTotalPaise;
        due = 0;
        dueDate = null;
        break;

      case PaymentMode.split:
        cash = _parseMoney(_cash.text) ?? 0;
        upi = _parseMoney(_upi.text) ?? 0;
        due = 0;
        dueDate = null;
        break;

      case PaymentMode.udhaar:
        cash = _parseMoney(_cash.text) ?? 0;
        upi = _parseMoney(_upi.text) ?? 0;
        due = total.grandTotalPaise - (cash + upi);
        break;
    }

    if (_gst &&
        _gstin.text.trim().isNotEmpty &&
        !CustomerValidators.isValidGstin(_gstin.text)) {
      _message('Enter a valid 15-character GSTIN or leave it blank.');
      return;
    }

    setState(() => _saving = true);
    try {
      final business = controller.businesses.where(
        (item) => item.businessId == appContext.businessId,
      );
      final currentBusiness = business.isNotEmpty ? business.first : null;
      final name = currentBusiness?.businessName ?? outlet.outletName;
      final normalizedCode = name
          .replaceAll(RegExp(r'[^A-Za-z0-9]'), '')
          .toUpperCase();
      final shortCode = normalizedCode.substring(
        0,
        normalizedCode.length < 6 ? normalizedCode.length : 6,
      );
      final result = await controller.billingRepository!.finalize(
        FinalizeBillRequest(
          requestId: DateTime.now().microsecondsSinceEpoch.toString(),
          tenantId: appContext.ownerUid,
          businessId: appContext.businessId!,
          outletId: outlet.outletId,
          businessShortCode: shortCode,
          cashierUid: appContext.uid,
          createdAt: DateTime.now(),
          lines: _lines,
          taxMode: _gst ? BillingTaxMode.gst : BillingTaxMode.nonGst,
          taxStructure: TaxStructure.intraState,
          customerId: _selectedCustomer?.customerId,
          customerName: _selectedCustomer?.name,
          customerPhone: _selectedCustomer?.phone,
          customerStateCode: _selectedCustomer?.stateCode,
          customerAddress: _selectedCustomer?.address,
          customerType: _selectedCustomer?.customerType,
          customerGstin: _gstin.text.trim().isEmpty
              ? null
              : CustomerValidators.normalizeGstin(_gstin.text),
          cashPaise: cash,
          upiPaise: upi,
          advancePaise: 0,
          duePaise: due,
          dueDate: dueDate,
          paymentMode: _paymentMode,
        ),
        token: token,
      );
      if (controller.canManageProducts()) {
        await controller.loadProducts();
      }
      if (mounted) {
        final currentBusiness = business.isNotEmpty ? business.first : null;
        final businessGstin = currentBusiness?.gstin?.trim().isNotEmpty == true
            ? currentBusiness!.gstin!.trim()
            : (outlet.gstin?.trim().isNotEmpty == true
                ? outlet.gstin!.trim()
                : null);

        final resolvedGstState = (currentBusiness?.gstState?.trim().isNotEmpty == true)
            ? currentBusiness!.gstState!.trim()
            : (outlet.gstState?.trim().isNotEmpty == true)
                ? outlet.gstState!.trim()
                : CustomerValidators.stateNameFromCode(
                    CustomerValidators.stateCodeFromGstin(businessGstin),
                  );

        final resolvedGstStateCode = CustomerValidators.stateCodeFromGstin(businessGstin) ??
            (resolvedGstState != null
                ? CustomerValidators.gstStateCodes.entries
                    .firstWhere(
                      (e) => e.value.toLowerCase() == resolvedGstState.toLowerCase(),
                      orElse: () => const MapEntry('', ''),
                    )
                    .key
                : null);

        final printLines = <InvoicePrintLine>[
          for (var i = 0; i < _lines.length; i++)
            InvoicePrintLine(
              name: total.lines[i].input.name,
              hsn: _lines[i].hsn,
              quantity: _lines[i].quantity.toDouble(),
              unit: total.lines[i].input.unit,
              unitPricePaise: total.lines[i].input.unitPricePaise,
              discountPaise: total.lines[i].input.discountPaise,
              taxablePaise: total.lines[i].taxablePaise,
              gstRateBps: total.lines[i].input.gstRateBps,
              cgstPaise: total.lines[i].cgstPaise,
              sgstPaise: total.lines[i].sgstPaise,
              igstPaise: total.lines[i].igstPaise,
              lineTotalPaise: total.lines[i].lineTotalPaise,
            ),
        ];

        final printData = InvoicePrintData(
          invoiceNumber: result.invoiceNumber,
          invoiceDate: DateTime.now(),
          businessName: currentBusiness?.businessName ?? name,
          businessTradeName:
              currentBusiness?.gstTradeName ?? outlet.gstTradeName,
          businessAddress: currentBusiness?.address ?? outlet.address,
          businessGstin: businessGstin,
          businessPan:
              businessGstin != null && businessGstin.length >= 12
                  ? businessGstin.substring(2, 12)
                  : null,
          businessPhone: currentBusiness?.phone ?? outlet.contactNumber,
          businessEmail: currentBusiness?.email,
          businessState: resolvedGstState,
          businessStateCode: (resolvedGstStateCode != null &&
                  resolvedGstStateCode.isNotEmpty)
              ? resolvedGstStateCode
              : null,
          customerName: _selectedCustomer?.name.trim().isNotEmpty == true
              ? _selectedCustomer!.name
              : 'Walk-in customer',
          customerPhone: _selectedCustomer?.phone,
          customerAddress: _selectedCustomer?.address,
          customerStateCode: _selectedCustomer?.stateCode,
          customerGstin: _gstin.text.trim().isNotEmpty
              ? CustomerValidators.normalizeGstin(_gstin.text)
              : null,
          lines: printLines,
          subtotalPaise: total.subtotalPaise,
          discountPaise: total.totalDiscountPaise,
          taxablePaise: total.taxableTotalPaise,
          cgstPaise: total.cgstPaise,
          sgstPaise: total.sgstPaise,
          igstPaise: total.igstPaise,
          roundOffPaise: total.roundOffPaise,
          grandTotalPaise: total.grandTotalPaise,
          paidPaise: cash + upi,
          duePaise: due,
          dueDate: _dueDate,
          paymentMode: _paymentModeLabel(_paymentMode),
          upiId: _businessSettings?.upiId,
          bankName: _businessSettings?.bankName,
          bankAccountNumber: _businessSettings?.bankAccountNumber,
          bankIfsc: _businessSettings?.bankIfsc,
          bankAccountName: _businessSettings?.bankAccountName,
          terms: _businessSettings?.invoiceTerms,
          cashierName:
              controller.user?.email.split('@').first ?? appContext.uid,
          status: due > 0 ? 'PARTIAL' : 'PAID',
        );

        await _showSavedBillActions(printData: printData);

        if (_selectedCustomer != null &&
            controller.customerRepository != null) {
          try {
            final refreshed = await controller.customerRepository!.search(
              tenantId: appContext.ownerUid,
              businessId: appContext.businessId!,
              token: token,
            );
            if (mounted) {
              setState(() {
                _customers = refreshed;
                _selectedCustomer = refreshed.firstWhere(
                  (c) => c.customerId == _selectedCustomer!.customerId,
                  orElse: () => _selectedCustomer!,
                );
              });
            }
          } catch (_) {}
        }

        setState(() {
          _lines.clear();
          _billDiscount.text = '0.00';
          _cash.text = '0.00';
          _upi.text = '0.00';
          _dueDate = null;
          _paymentMode = PaymentMode.cash;
        });
        widget.onBillSaved?.call();
      }
    } catch (error) {
      if (mounted) _message('$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _summary(String label, int paise, {bool strong = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: strong ? const TextStyle(fontWeight: FontWeight.bold) : null,
          ),
        ),
        Text(
          _rupees(paise),
          style: strong ? const TextStyle(fontWeight: FontWeight.bold) : null,
        ),
      ],
    ),
  );

  String _rupees(int paise) =>
      '₹${paise ~/ 100}.${(paise % 100).toString().padLeft(2, '0')}';

  Future<void> _showSavedBillActions({
    required InvoicePrintData printData,
  }) async {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.green),
            const SizedBox(width: 8),
            Text(l10n?.billSaved ?? 'Bill saved'),
          ],
        ),
        content: Text(
          'Invoice ${printData.invoiceNumber} was saved successfully.',
        ),
        actions: [
          FilledButton.icon(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await PrintFormatDialog.show(
                context: context,
                data: printData,
                defaultFormatString: _businessSettings?.printFormat,
                defaultCustomWidthMm:
                    _businessSettings?.customPrintWidthMm ?? 80.0,
                onSaveDefaultFormat: (format, customWidth) async {
                  final repo = widget.controller.settingsRepository;
                  final token = widget.controller.idToken;
                  if (repo != null &&
                      _businessSettings != null &&
                      token != null) {
                    final updated = _businessSettings!.copyWith(
                      printFormat: PrintFormatDialog.formatToString(format),
                      customPrintWidthMm: customWidth,
                    );
                    _businessSettings = updated;
                    await repo.saveSettings(settings: updated, token: token);
                  }
                },
              );
            },
            icon: const Icon(Icons.print_outlined),
            label: Text(l10n?.printBill ?? 'Print Bill'),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await PrintFormatDialog.show(
                context: context,
                data: printData,
                defaultFormatString: _businessSettings?.printFormat,
                defaultCustomWidthMm:
                    _businessSettings?.customPrintWidthMm ?? 80.0,
              );
            },
            icon: const Icon(Icons.share_outlined),
            label: Text(l10n?.sharePdf ?? 'Share PDF'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n?.done ?? 'Done'),
          ),
        ],
      ),
    );
  }

  void _message(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              if (isError) ...[
                const Icon(Icons.error_outline, color: Colors.white, size: 20),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          backgroundColor: isError ? Colors.red.shade800 : null,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: isError ? 4 : 2),
        ),
      );
  }

  Future<void> _showStockAlert({
    required String title,
    required String message,
    String? productName,
    int? availableStock,
    int? requestedQty,
    VoidCallback? onAdjustToMax,
  }) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.warning_amber_rounded,
                color: Colors.red.shade800,
                size: 28,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: Colors.red.shade900,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message,
              style: const TextStyle(fontSize: 14, height: 1.4),
            ),
            if (availableStock != null && requestedQty != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Available in Stock:',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '$availableStock units',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: availableStock > 0
                                ? Colors.green.shade800
                                : Colors.red.shade800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Requested Quantity:',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '$requestedQty units',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.red.shade900,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (onAdjustToMax != null &&
              availableStock != null &&
              availableStock > 0)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF10263D),
                side: const BorderSide(color: Color(0xFF10263D)),
              ),
              onPressed: () {
                Navigator.of(dialogCtx).pop();
                onAdjustToMax();
              },
              icon: const Icon(Icons.check, size: 16),
              label: Text('Set Qty to $availableStock'),
            ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade800,
            ),
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('OK, Understood'),
          ),
        ],
      ),
    );
  }
}

class _BarcodeScannerDialog extends StatefulWidget {
  const _BarcodeScannerDialog({required this.onBarcode});

  final ValueChanged<String> onBarcode;

  @override
  State<_BarcodeScannerDialog> createState() => _BarcodeScannerDialogState();
}

class _BarcodeScannerDialogState extends State<_BarcodeScannerDialog>
    with WidgetsBindingObserver {
  late final MobileScannerController _scanner = MobileScannerController(
    autoStart: false,
    facing: CameraFacing.back,
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.all],
  );

  bool _starting = false;
  bool _hasScanned = false;
  String? _startupError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _startScanner());
  }

  Future<void> _startScanner() async {
    if (_starting || !mounted) return;
    setState(() => _starting = true);
    try {
      // Explicitly starting the controller requests Android camera permission.
      await _scanner.start();
      if (mounted) setState(() => _startupError = null);
    } on MissingPluginException {
      if (mounted) {
        setState(() {
          _startupError =
              'This installed app build does not include the barcode scanner. '
              'Stop the app and install a fresh build, then try again.';
        });
      }
    } on MobileScannerException catch (_) {
      // The scanner's errorBuilder below gives the user a retry path and
      // explains that camera access may need to be enabled in system settings.
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_scanner.value.isRunning) {
      _startScanner();
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _scanner.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scanner.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Scan product barcode'),
      content: SizedBox(
        width: 360,
        height: 360,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: _startupError != null
              ? _scannerError(_startupError!, canRetry: false)
              : MobileScanner(
                  controller: _scanner,
                  errorBuilder: (context, error) => _scannerError(
                    error.errorCode == MobileScannerErrorCode.permissionDenied
                        ? 'Camera access is required to scan barcodes. Allow camera access in app settings, then retry.'
                        : 'Unable to start the camera (${error.errorCode.name}). Check camera access and retry.',
                    canRetry: true,
                  ),
                  onDetect: (capture) {
                    if (_hasScanned) return;
                    for (final barcode in capture.barcodes) {
                      final value = barcode.rawValue?.trim();
                      if (value == null || value.isEmpty) continue;
                      _hasScanned = true;
                      widget.onBarcode(value);
                      break;
                    }
                  },
                ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  Widget _scannerError(String message, {required bool canRetry}) {
    return ColoredBox(
      color: Colors.black87,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.no_photography_outlined,
                color: Colors.white,
                size: 36,
              ),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
              if (canRetry) ...[
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _starting ? null : _startScanner,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry camera'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductDetailsCard extends StatelessWidget {
  const _ProductDetailsCard({
    this.l10n,
    required this.variant,
    required this.stock,
    required this.sellingPrice,
    required this.mrp,
    required this.gstRate,
    required this.makeDefault,
    required this.saving,
    required this.isGst,
    required this.onMakeDefaultChanged,
    required this.onSavePricing,
  });

  final AppLocalizations? l10n;
  final ProductVariantModel variant;
  final Map<String, int> stock;
  final TextEditingController sellingPrice;
  final TextEditingController mrp;
  final TextEditingController gstRate;
  final bool makeDefault;
  final bool saving;
  final bool isGst;
  final ValueChanged<bool> onMakeDefaultChanged;
  final VoidCallback onSavePricing;

  @override
  Widget build(BuildContext context) {
    final rawStock = stock[variant.variantId] ?? 0;
    final isStockTracked = variant.trackStock;
    final stockUnits = rawStock >= 1000 ? (rawStock / 1000).floor() : rawStock;
    final isOutOfStock = isStockTracked && stockUnits <= 0;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isOutOfStock
              ? Colors.red.shade300
              : Colors.blueGrey.withValues(alpha: 0.2),
        ),
      ),
      color: isOutOfStock
          ? Colors.red.shade50.withValues(alpha: 0.25)
          : Theme.of(context)
              .colorScheme
              .surfaceContainerHighest
              .withValues(alpha: 0.4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isOutOfStock) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  border: Border.all(color: Colors.red.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.red.shade800,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Out of Stock: "${variant.displayName}" has 0 available inventory and cannot be billed.',
                        style: TextStyle(
                          color: Colors.red.shade900,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            Wrap(
              spacing: 24,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _detail(
                  l10n?.name ?? 'Product',
                  variant.productName ?? variant.name,
                ),
                _detail('Variant', variant.name),
                _detail(l10n?.sku ?? 'SKU', variant.sku ?? '—'),
                _detail('Barcode', variant.barcode ?? '—'),
                _detail(
                  l10n?.unit ?? 'Unit',
                  variant.commercialUnitName ?? variant.baseUnitId,
                ),
                SizedBox(
                  width: 160,
                  child: TextField(
                    controller: sellingPrice,
                    enabled: !saving,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: l10n?.sellingPrice ?? 'Selling price (₹)',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 160,
                  child: TextField(
                    controller: mrp,
                    enabled: !saving,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: l10n?.mrp ?? 'MRP (₹)',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 130,
                  child: TextField(
                    controller: gstRate,
                    enabled: isGst && !saving,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: '${l10n?.gst ?? "GST"} (%)',
                      helperText: isGst ? null : 'Turned off (0%)',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                    ),
                  ),
                ),
                _detail(l10n?.hsn ?? 'HSN', variant.hsnCode ?? '—'),
                _detail(
                  l10n?.availableStock ?? 'Available stock',
                  !isStockTracked
                      ? 'Untracked'
                      : (isOutOfStock
                          ? '0 (Out of stock)'
                          : _formatAvailableStock(rawStock)),
                  isWarning: isOutOfStock,
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Checkbox(
                      value: makeDefault,
                      onChanged: saving
                          ? null
                          : (value) => onMakeDefaultChanged(value ?? false),
                    ),
                    Text(
                      l10n?.makeDefaultPrice ?? 'Make default for this product',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF10263D),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: saving ? null : onSavePricing,
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: Text(
                    saving
                        ? (l10n?.saving ?? 'Saving...')
                        : (l10n?.savePrices ?? 'Save prices'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _detail(String label, String value, {bool isWarning = false}) => SizedBox(
    width: 160,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: isWarning ? Colors.red.shade800 : null,
          ),
        ),
      ],
    ),
  );
}

String _formatAvailableStock(int thousandths) {
  if (thousandths >= 1000) {
    final value = thousandths / 1000;
    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toString();
  }
  return thousandths.toString();
}

class _LotPriceSelectionDialog extends StatelessWidget {
  const _LotPriceSelectionDialog({
    required this.variant,
    required this.batches,
  });

  final ProductVariantModel variant;
  final List<VariantBatchPriceOption> batches;

  String _formatMoney(int paise) => (paise / 100).toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.sell_outlined,
              color: Color(0xFF2563EB),
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Select Selling Price / Lot',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  variant.displayName,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w500,
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
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Multiple purchase lots found with different prices. Tap the price matching the physical product:',
              style: TextStyle(fontSize: 13, color: Color(0xFF475569)),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (var i = 0; i < batches.length; i++) ...[
                      if (i > 0) const SizedBox(height: 8),
                      _batchCard(context, batches[i]),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  Widget _batchCard(BuildContext context, VariantBatchPriceOption batch) {
    final sellStr = _formatMoney(batch.sellingPricePaise);
    final mrpStr = batch.mrpPaise > 0 ? _formatMoney(batch.mrpPaise) : null;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Color(0xFFCBD5E1)),
      ),
      color: const Color(0xFFF8FAFC),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => Navigator.of(context).pop(batch),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '₹$sellStr',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        if (mrpStr != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            'MRP: ₹$mrpStr',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      children: [
                        if (batch.internalBatchNo.isNotEmpty)
                          Text(
                            'Lot: ${batch.internalBatchNo}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF475569),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        if (batch.purchaseId != null &&
                            batch.purchaseId!.isNotEmpty)
                          Text(
                            '• ${batch.purchaseId}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF64748B),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${_formatAvailableStock(batch.availableQty)} in stock',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF166534),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.arrow_forward_ios,
                size: 14,
                color: Color(0xFF94A3B8),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
