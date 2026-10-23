import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:barcode_widget/barcode_widget.dart' as barcode_ui;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../core/utils/stock_quantity_formatter.dart';
import '../../data/models/product_model.dart';
import '../../data/models/product_variant_model.dart';
import '../../data/repositories/product_repository.dart';
import '../../data/services/barcode_label_print_service.dart';
import '../../l10n/app_localizations.dart';

enum _BarcodeSearchType { product, variant, barcode, category, brand }

enum _BarcodeTemplate { standard, compact, price, barcodeOnly }

class BarcodePrintingPage extends StatefulWidget {
  const BarcodePrintingPage({
    super.key,
    required this.products,
    required this.businessName,
    required this.loadReceivedVariantIds,
    this.loadReceivedVariantPricing,
    this.loadVariantBatches,
    this.availableQuantities = const {},
    this.initialProductId,
    this.initialVariantId,
    this.initialCopies,
    this.initialMrpOverrides,
    this.initialSellingPriceOverrides,
    this.onClose,
    this.showBackButton = false,
    // Retained for source compatibility with product-row shortcuts.
    this.showBulkTools = true,
  });

  final List<ProductModel> products;
  final String businessName;
  final Future<Set<String>> Function() loadReceivedVariantIds;
  final Future<Map<String, ({int mrp, int sellingPrice})>> Function()?
  loadReceivedVariantPricing;
  final Future<List<VariantBatchPriceOption>> Function(String variantId)?
  loadVariantBatches;
  final Map<String, int> availableQuantities;
  final String? initialProductId;
  final String? initialVariantId;
  final Map<String, int>? initialCopies;
  final Map<String, int>? initialMrpOverrides;
  final Map<String, int>? initialSellingPriceOverrides;
  final VoidCallback? onClose;
  final bool showBackButton;
  final bool showBulkTools;

  @override
  State<BarcodePrintingPage> createState() => _BarcodePrintingPageState();
}

class _BarcodePrintingPageState extends State<BarcodePrintingPage> {
  static const _sizes = <String, (double, double)>{
    '50 x 25 mm': (50, 25),
    '50 x 30 mm': (50, 30),
    '40 x 25 mm': (40, 25),
    'Custom': (0, 0),
  };

  final _search = TextEditingController();
  final _globalCopies = TextEditingController(text: '1');
  final _customWidth = TextEditingController(text: '50');
  final _customHeight = TextEditingController(text: '25');
  final _printService = const BarcodeLabelPrintService();
  final _previewBoundaryKey = GlobalKey();
  final _tableScrollController = ScrollController();
  final Set<String> _selected = {};
  final Map<String, int> _copies = {};
  final Map<String, TextEditingController> _copyControllers = {};
  final Set<String> _invalidCopies = {};
  Set<String> _received = {};
  Map<String, ({int mrp, int sellingPrice})> _receivedPricing = {};
  final Map<String, int> _mrpOverrides = {};
  final Map<String, int> _sellingPriceOverrides = {};
  final Map<String, List<VariantBatchPriceOption>> _variantBatches = {};
  final Set<String> _loadingBatches = {};
  _BarcodeSearchType _searchType = _BarcodeSearchType.product;
  _BarcodeTemplate _template = _BarcodeTemplate.standard;
  String _query = '';
  String _size = '50 x 25 mm';
  String? _focusedVariantId;
  bool _checkingEligibility = true;
  bool _showIneligible = false;
  bool _showBusiness = true;
  bool _showProduct = true;
  bool _showVariant = true;
  bool _showMrp = true;
  bool _showSellingPrice = true;
  bool _previewSelected = false;
  bool _printing = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialCopies != null) {
      _copies.addAll(widget.initialCopies!);
    }
    if (widget.initialMrpOverrides != null) {
      _mrpOverrides.addAll(widget.initialMrpOverrides!);
    }
    if (widget.initialSellingPriceOverrides != null) {
      _sellingPriceOverrides.addAll(widget.initialSellingPriceOverrides!);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadEligibility());
  }

  @override
  void dispose() {
    _search.dispose();
    _globalCopies.dispose();
    _customWidth.dispose();
    _customHeight.dispose();
    _tableScrollController.dispose();
    for (final controller in _copyControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadEligibility() async {
    try {
      final received = await widget.loadReceivedVariantIds();
      final pricing =
          await widget.loadReceivedVariantPricing?.call() ?? const {};
      if (!mounted) return;
      setState(() {
        _received = received;
        _receivedPricing = pricing;
        _checkingEligibility = false;
        if (widget.initialCopies != null && widget.initialCopies!.isNotEmpty) {
          for (final vid in widget.initialCopies!.keys) {
            _selected.add(vid);
            _focusedVariantId ??= vid;
          }
        }
      });
      final initial = _allVariants
          .where(
            (entry) =>
                entry.$1.productId == widget.initialProductId &&
                entry.$2.variantId == widget.initialVariantId,
          )
          .firstOrNull;
      if (initial != null) {
        if (_baseEligible(initial.$1, initial.$2)) {
          setState(() {
            _selected.add(initial.$2.variantId);
            _focusedVariantId = initial.$2.variantId;
          });
        } else {
          setState(() {
            _showIneligible = true;
            _focusedVariantId = initial.$2.variantId;
          });
        }
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _checkingEligibility = false);
      _message(
        'Could not read local receipt history. Barcode output is blocked.',
      );
    }
    if (widget.loadVariantBatches != null) {
      for (final entry in _allVariants) {
        final vid = entry.$2.variantId;
        final stock = widget.availableQuantities[vid];
        if (stock != null && stock > 0) {
          _fetchBatchesForVariant(vid);
        }
      }
    }
  }

  Future<void> _fetchBatchesForVariant(String variantId) async {
    if (widget.loadVariantBatches == null) return;
    if (_variantBatches.containsKey(variantId) ||
        _loadingBatches.contains(variantId)) {
      return;
    }
    _loadingBatches.add(variantId);
    try {
      final batches = await widget.loadVariantBatches!(variantId);
      if (mounted) {
        setState(() {
          _variantBatches[variantId] = batches;
          _loadingBatches.remove(variantId);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingBatches.remove(variantId);
        });
      }
    }
  }

  @override
  void didUpdateWidget(BarcodePrintingPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selected.isEmpty && widget.initialVariantId != null) {
      final initial = _allVariants
          .where(
            (entry) =>
                entry.$1.productId == widget.initialProductId &&
                entry.$2.variantId == widget.initialVariantId,
          )
          .firstOrNull;
      if (initial != null && _baseEligible(initial.$1, initial.$2)) {
        setState(() {
          _selected.add(initial.$2.variantId);
          _focusedVariantId = initial.$2.variantId;
        });
      }
    }
  }

  List<(ProductModel, ProductVariantModel)> get _allVariants => [
    for (final product in widget.products)
      for (final variant in product.variants) (product, variant),
  ];

  String _key(ProductVariantModel variant) => variant.variantId;

  String? _eligibilityIssue(ProductModel product, ProductVariantModel variant) {
    if (!product.isActive) {
      return 'Product is inactive';
    }
    if (!variant.isActive) {
      return 'Variant is inactive';
    }
    if (!_received.contains(_key(variant))) {
      return 'Not received';
    }
    if (variant.barcode?.trim().isNotEmpty != true) {
      return 'Barcode not assigned';
    }
    final qty = widget.availableQuantities[_key(variant)];
    if (qty == null || qty <= 0) {
      return 'No stock available';
    }
    return null;
  }

  bool _baseEligible(ProductModel product, ProductVariantModel variant) =>
      _eligibilityIssue(product, variant) == null;

  int _effectiveMrp(ProductVariantModel variant) {
    final override = _mrpOverrides[_key(variant)];
    if (override != null && override > 0) return override;
    if (variant.mrp > 0) return variant.mrp;
    return _receivedPricing[_key(variant)]?.mrp ?? 0;
  }

  int _effectiveSellingPrice(ProductVariantModel variant) {
    final override = _sellingPriceOverrides[_key(variant)];
    if (override != null && override > 0) return override;
    if (variant.sellingPrice > 0) return variant.sellingPrice;
    return _receivedPricing[_key(variant)]?.sellingPrice ?? 0;
  }

  String? _priceIssue(ProductVariantModel variant) {
    if (_showMrp && _effectiveMrp(variant) <= 0) {
      return 'MRP unavailable';
    }
    if (_showSellingPrice && _effectiveSellingPrice(variant) <= 0) {
      return 'Selling price unavailable';
    }
    return null;
  }

  String _status(ProductModel product, ProductVariantModel variant) {
    if (_checkingEligibility) return 'Checking…';
    final issue = _eligibilityIssue(product, variant);
    if (issue != null) return issue;
    if (_invalidCopies.contains(_key(variant))) {
      return 'Incomplete · Copies must be at least 1';
    }
    final priceIssue = _priceIssue(variant);
    if (priceIssue != null) return 'Incomplete · $priceIssue';
    return 'Ready to print';
  }

  List<(ProductModel, ProductVariantModel)> get _visibleRows {
    final query = _query.trim().toLowerCase();
    return _allVariants.where((entry) {
      final product = entry.$1;
      final variant = entry.$2;
      if (!_showIneligible && !_baseEligible(product, variant)) return false;
      if (query.isEmpty) return true;
      final value = switch (_searchType) {
        _BarcodeSearchType.product => product.name,
        _BarcodeSearchType.variant => variant.name,
        _BarcodeSearchType.barcode => variant.barcode ?? '',
        _BarcodeSearchType.category => product.category ?? '',
        _BarcodeSearchType.brand => product.brand ?? '',
      };
      return value.toLowerCase().contains(query);
    }).toList();
  }

  (ProductModel, ProductVariantModel)? get _focusedEntry {
    final rows = _allVariants.where((e) => _selected.contains(_key(e.$2)));
    if (_focusedVariantId != null) {
      final focused = rows
          .where((e) => _key(e.$2) == _focusedVariantId)
          .firstOrNull;
      if (focused != null) return focused;
    }
    return rows.firstOrNull;
  }

  (double, double)? get _dimensions {
    if (_size != 'Custom') return _sizes[_size];
    final width = double.tryParse(_customWidth.text.trim());
    final height = double.tryParse(_customHeight.text.trim());
    if (width == null ||
        height == null ||
        !width.isFinite ||
        !height.isFinite ||
        width <= 0 ||
        height <= 0 ||
        width > 200 ||
        height > 200) {
      return null;
    }
    return (width, height);
  }

  BarcodeLabelOptions get _options {
    final d = _dimensions ?? (50.0, 25.0);
    return BarcodeLabelOptions(
      widthMm: d.$1,
      heightMm: d.$2,
      businessName: widget.businessName,
      showBusinessName: _showBusiness,
      showProductName: _showProduct,
      showVariant: _showVariant,
      showMrp: _showMrp,
      showSellingPrice: _showSellingPrice,
    );
  }

  BarcodeLabelLine _line(ProductModel product, ProductVariantModel variant) =>
      BarcodeLabelLine(
        productName: product.name,
        variantName: variant.name,
        barcode: variant.barcode ?? '',
        quantity: _copies[_key(variant)] ?? 1,
        mrp: _effectiveMrp(variant),
        sellingPrice: _effectiveSellingPrice(variant),
      );

  List<BarcodeLabelLine> get _selectedLines => [
    for (final entry in _allVariants)
      if (_selected.contains(_key(entry.$2))) _line(entry.$1, entry.$2),
  ];

  void _message(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  void _selectRow(ProductVariantModel variant, bool selected) {
    setState(() {
      if (selected) {
        _selected.add(_key(variant));
        _focusedVariantId = _key(variant);
      } else {
        _selected.remove(_key(variant));
        if (_focusedVariantId == _key(variant)) _focusedVariantId = null;
      }
      _previewSelected = false;
    });
  }

  void _selectAllVisible() {
    setState(() {
      for (final entry in _visibleRows) {
        if (_baseEligible(entry.$1, entry.$2) &&
            _priceIssue(entry.$2) == null) {
          _selected.add(_key(entry.$2));
        }
      }
      _previewSelected = false;
    });
  }

  void _applyCopies() {
    final count = int.tryParse(_globalCopies.text.trim());
    if (count == null || count < 1) {
      _message('Copies must be a positive whole number.');
      return;
    }
    if (_selected.isEmpty) {
      _message('Select at least one eligible variant first.');
      return;
    }
    setState(() {
      for (final id in _selected) {
        _copies[id] = count;
        _invalidCopies.remove(id);
        _copyControllers[id]?.text = '$count';
      }
    });
    _message('Applied $count copies to ${_selected.length} selected variants.');
  }

  void _reset() {
    setState(() {
      _search.clear();
      _query = '';
      _searchType = _BarcodeSearchType.product;
      _showIneligible = false;
      _selected.clear();
      _copies.clear();
      _invalidCopies.clear();
      _mrpOverrides.clear();
      _sellingPriceOverrides.clear();
      for (final controller in _copyControllers.values) {
        controller.text = '1';
      }
      _globalCopies.text = '1';
      _focusedVariantId = null;
      _previewSelected = false;
      _size = '50 x 25 mm';
      _customWidth.text = '50';
      _customHeight.text = '25';
      _setTemplate(_BarcodeTemplate.standard, notify: false);
    });
  }

  void _setTemplate(_BarcodeTemplate template, {bool notify = true}) {
    void apply() {
      _template = template;
      switch (template) {
        case _BarcodeTemplate.standard:
          _showBusiness = true;
          _showProduct = true;
          _showVariant = true;
          _showMrp = true;
          _showSellingPrice = true;
        case _BarcodeTemplate.compact:
          _showBusiness = false;
          _showProduct = true;
          _showVariant = true;
          _showMrp = false;
          _showSellingPrice = true;
        case _BarcodeTemplate.price:
          _showBusiness = true;
          _showProduct = true;
          _showVariant = true;
          _showMrp = true;
          _showSellingPrice = true;
        case _BarcodeTemplate.barcodeOnly:
          _showBusiness = false;
          _showProduct = false;
          _showVariant = false;
          _showMrp = false;
          _showSellingPrice = false;
      }
    }

    if (notify) {
      setState(apply);
    } else {
      apply();
    }
  }

  List<BarcodeLabelLine>? _validatedLines() {
    if (_selected.isEmpty) {
      _message('Select at least one barcode-eligible variant.');
      return null;
    }
    final lines = _selectedLines;
    final blocked = <String>[];
    var blockedRows = 0;
    for (final entry in _allVariants.where(
      (e) => _selected.contains(_key(e.$2)),
    )) {
      final product = entry.$1;
      final variant = entry.$2;
      if (_eligibilityIssue(product, variant) case final issue?) {
        blocked.add('${product.name} · ${variant.name}: $issue');
        blockedRows++;
      } else if (_priceIssue(variant) case final issue?) {
        blocked.add('${product.name} · ${variant.name}: $issue');
        blockedRows++;
      } else if (_invalidCopies.contains(_key(variant)) ||
          (_copies[_key(variant)] ?? 1) < 1) {
        blocked.add('${product.name} · ${variant.name}: invalid copies');
        blockedRows++;
      }
    }
    if (_dimensions == null) blocked.add('Label size is invalid.');
    if (blocked.isNotEmpty) {
      _message(
        '${_selected.length - blockedRows} eligible, $blockedRows blocked. ${blocked.first}',
      );
      return null;
    }
    return lines;
  }

  void _preview() {
    if (_validatedLines() == null) return;
    setState(() => _previewSelected = true);
  }

  Future<void> _downloadPdf() async {
    final lines = _validatedLines();
    if (lines == null) return;
    try {
      final bytes = await _printService.buildPdf(lines, _options);
      final date = DateTime.now().toIso8601String().substring(0, 10);
      await _saveBytes(
        bytes,
        'application/pdf',
        'pdf',
        'Barcode_Labels_$date.pdf',
      );
    } catch (error) {
      if (mounted) _message('Could not create barcode PDF: $error');
    }
  }

  Future<void> _printSelected() async {
    final lines = _validatedLines();
    if (lines == null) return;
    setState(() => _printing = true);
    try {
      await _printService.printLabels(lines, _options);
    } catch (error) {
      if (mounted) _message('Could not print barcode labels: $error');
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  Future<void> _downloadPng() async {
    final entry = _focusedEntry;
    if (entry == null) {
      _message('Select one eligible variant to download a PNG label.');
      return;
    }
    if (_validatedLines() == null) return;
    await WidgetsBinding.instance.endOfFrame;
    final renderObject = _previewBoundaryKey.currentContext?.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) {
      _message('Preview is not ready for PNG export.');
      return;
    }
    ui.Image? image;
    try {
      image = await renderObject.toImage(pixelRatio: 8);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('Could not encode PNG image.');
      final name =
          '${_safeName(entry.$1.name)}_${_safeName(entry.$2.name)}_${_safeName(entry.$2.barcode ?? '')}.png';
      await _saveBytes(data.buffer.asUint8List(), 'image/png', 'png', name);
    } catch (error) {
      if (mounted) _message('Could not download PNG: $error');
    } finally {
      image?.dispose();
    }
  }

  Future<void> _saveBytes(
    List<int> bytes,
    String mime,
    String extension,
    String suggestedName,
  ) async {
    try {
      final location = await getSaveLocation(
        acceptedTypeGroups: [
          XTypeGroup(label: extension.toUpperCase(), extensions: [extension]),
        ],
        suggestedName: suggestedName,
        confirmButtonText: 'Save',
      );
      if (location == null) return;
      final path = location.path.toLowerCase().endsWith('.$extension')
          ? location.path
          : '${location.path}.$extension';
      await XFile.fromData(
        Uint8List.fromList(bytes),
        mimeType: mime,
        name: suggestedName,
      ).saveTo(path);
      if (mounted) _message('Saved ${path.split('/').last}.');
    } catch (error) {
      if (mounted) _message('Could not save barcode file: $error');
    }
  }

  String _safeName(String value) => value
      .trim()
      .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final preview = _previewPanel(context);
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            LayoutBuilder(
              builder: (context, headerConstraints) {
                final compact = headerConstraints.maxWidth < 720;
                final heading = Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (widget.showBackButton && widget.onClose != null)
                      IconButton(
                        onPressed: widget.onClose,
                        icon: const Icon(Icons.arrow_back),
                      ),
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF132B45),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(
                        Icons.qr_code_2_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    Text(
                      l10n?.barcodePrinting ?? 'Barcode Printing',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                        letterSpacing: -0.3,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Text(
                        '${_visibleRows.length} available',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF475569),
                        ),
                      ),
                    ),
                  ],
                );
                final reset = OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                  ),
                  onPressed: _reset,
                  icon: const Icon(Icons.restart_alt, size: 16),
                  label: const Text('Reset'),
                );
                return compact
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          heading,
                          const SizedBox(height: 8),
                          Align(alignment: Alignment.centerRight, child: reset),
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(child: heading),
                          reset,
                        ],
                      );
              },
            ),
            const SizedBox(height: 14),
            _filtersAndControls(context),
            const SizedBox(height: 12),
            if (constraints.maxWidth >= 1180)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 7, child: _productTable(context)),
                  const SizedBox(width: 16),
                  Expanded(flex: 4, child: preview),
                ],
              )
            else ...[
              _productTable(context),
              const SizedBox(height: 12),
              preview,
            ],
          ],
        );
      },
    );
  }

  Widget _filtersAndControls(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Row 1: Search & Filter Scope
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 720;
                final searchType = SizedBox(
                  width: compact ? constraints.maxWidth : 175,
                  child: DropdownButtonFormField<_BarcodeSearchType>(
                    initialValue: _searchType,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Search Field',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: _BarcodeSearchType.product,
                        child: Text('Product Name'),
                      ),
                      DropdownMenuItem(
                        value: _BarcodeSearchType.variant,
                        child: Text('Variant'),
                      ),
                      DropdownMenuItem(
                        value: _BarcodeSearchType.barcode,
                        child: Text('Barcode'),
                      ),
                      DropdownMenuItem(
                        value: _BarcodeSearchType.category,
                        child: Text('Category'),
                      ),
                      DropdownMenuItem(
                        value: _BarcodeSearchType.brand,
                        child: Text('Brand'),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => _searchType = value ?? _searchType),
                  ),
                );
                final searchField = TextField(
                  controller: _search,
                  onChanged: (value) => setState(() => _query = value),
                  decoration: InputDecoration(
                    labelText: 'Search',
                    hintText: 'Filter local variants by SKU, name or code',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    suffixIcon: _query.isNotEmpty
                        ? IconButton(
                            onPressed: () {
                              _search.clear();
                              setState(() => _query = '');
                            },
                            icon: const Icon(Icons.clear, size: 18),
                          )
                        : null,
                  ),
                );
                final eligibilityFilter = FilterChip(
                  label: Text(l10n?.showIneligible ?? 'Show ineligible'),
                  selected: _showIneligible,
                  avatar: Icon(
                    _showIneligible
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  onSelected: (value) =>
                      setState(() => _showIneligible = value),
                );
                return compact
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          searchType,
                          const SizedBox(height: 8),
                          searchField,
                          Align(
                            alignment: Alignment.centerRight,
                            child: eligibilityFilter,
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          searchType,
                          const SizedBox(width: 10),
                          Expanded(child: searchField),
                          const SizedBox(width: 12),
                          eligibilityFilter,
                        ],
                      );
              },
            ),
            const SizedBox(height: 10),
            const Divider(height: 1, color: Color(0xFFF1F5F9)),
            const SizedBox(height: 10),

            // Row 2: Batch Selection Actions & Copies
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              runSpacing: 8,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: _selected.isNotEmpty
                        ? const Color(0xFFEFF6FF)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _selected.isNotEmpty
                          ? const Color(0xFFBFDBFE)
                          : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Text(
                    '${_selected.length} selected',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: _selected.isNotEmpty
                          ? const Color(0xFF1D4ED8)
                          : const Color(0xFF64748B),
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  onPressed: _selectAllVisible,
                  icon: const Icon(Icons.select_all_rounded, size: 16),
                  label: Text(l10n?.selectAllVisible ?? 'Select All Visible'),
                ),
                if (_selected.isNotEmpty)
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFDC2626),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                    ),
                    onPressed: () => setState(() {
                      _selected.clear();
                      _copies.clear();
                      _previewSelected = false;
                      _focusedVariantId = null;
                    }),
                    icon: const Icon(Icons.close_rounded, size: 16),
                    label: Text(l10n?.clearSelection ?? 'Clear Selection'),
                  ),
                Text(
                  l10n?.copiesForSelected ?? 'Copies for selected',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF475569),
                  ),
                ),
                SizedBox(
                  width: 75,
                  child: TextField(
                    controller: _globalCopies,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF132B45),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: _applyCopies,
                  child: const Text('Apply'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _productTable(BuildContext context) {
    final rows = _visibleRows;
    if (_checkingEligibility) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (rows.isEmpty) {
      return Card(
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
                  Icons.inventory_2_outlined,
                  size: 36,
                  color: Color(0xFF94A3B8),
                ),
                const SizedBox(height: 10),
                Text(
                  _showIneligible ? 'No variants match this search.' : 'No active barcode variants with available stock match this search. Turn on Show ineligible to inspect other variants.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Scrollbar(
        controller: _tableScrollController,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _tableScrollController,
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowHeight: 46,
            headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
            dataRowMinHeight: 56,
            dataRowMaxHeight: 84,
            columnSpacing: 18,
            columns: const [
              DataColumn(label: Text('Select')),
              DataColumn(label: SizedBox(width: 210, child: Text('Product'))),
              DataColumn(
                label: SizedBox(
                  width: 220,
                  child: Text('Variant / Specification'),
                ),
              ),
              DataColumn(label: SizedBox(width: 140, child: Text('Barcode'))),
              DataColumn(label: Text('Available Qty')),
              DataColumn(label: SizedBox(width: 90, child: Text('Copies'))),
              DataColumn(label: Text('MRP')),
              DataColumn(label: Text('Selling Price')),
              DataColumn(label: SizedBox(width: 190, child: Text('Status'))),
            ],
            rows: [for (final entry in rows) _tableRow(entry.$1, entry.$2)],
          ),
        ),
      ),
    );
  }

  DataRow _tableRow(ProductModel product, ProductVariantModel variant) {
    final id = _key(variant);
    final base = _baseEligible(product, variant);
    final selected = _selected.contains(id);
    final status = _status(product, variant);
    final priceIssue = _priceIssue(variant);
    final enabled = base && priceIssue == null;
    final effectiveMrp = _effectiveMrp(variant);
    final effectiveSell = _effectiveSellingPrice(variant);
    final stock = widget.availableQuantities[id];
    final hasStock = stock != null && stock > 0;
    final batches = _variantBatches[id] ?? const [];
    final activeBatches = batches.where((b) => b.availableQty > 0).toList();
    return DataRow(
      selected: selected,
      onSelectChanged: base
          ? (value) => _selectRow(variant, value == true)
          : null,
      cells: [
        DataCell(
          Checkbox(
            key: ValueKey('select-$id'),
            value: selected,
            onChanged: base
                ? (value) => _selectRow(variant, value == true)
                : null,
          ),
        ),
        DataCell(
          SizedBox(
            width: 210,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  product.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: Color(0xFF0F172A),
                  ),
                ),
                if (!product.isActive)
                  const Text(
                    'Product Inactive',
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFFDC2626),
                      fontWeight: FontWeight.w600,
                    ),
                  )
                else if (product.category != null || product.brand != null)
                  Text(
                    [
                      if (product.brand?.isNotEmpty == true) product.brand!,
                      if (product.category?.isNotEmpty == true)
                        product.category!,
                    ].join(' · '),
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
          onTap: () => setState(() => _focusedVariantId = id),
        ),
        DataCell(
          SizedBox(
            width: 220,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  variant.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: Color(0xFF334155),
                  ),
                ),
                if (!variant.isActive)
                  const Text(
                    'Variant Inactive',
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFFDC2626),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
          onTap: () => setState(() => _focusedVariantId = id),
        ),
        DataCell(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: SelectableText(
              variant.barcode?.isNotEmpty == true ? variant.barcode! : '—',
              key: ValueKey('barcode-$id'),
              style: const TextStyle(
                fontFamily: 'monospace',
                fontWeight: FontWeight.w700,
                fontSize: 12,
                letterSpacing: 0.5,
                color: Color(0xFF0F172A),
              ),
            ),
          ),
        ),
        DataCell(
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              hasStock
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FDF4),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFBBF7D0)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Color(0xFF16A34A),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            formatStockQuantity(stock),
                            style: const TextStyle(
                              color: Color(0xFF15803D),
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFECACA)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Color(0xFFDC2626),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          const Text(
                            '0',
                            style: TextStyle(
                              color: Color(0xFFDC2626),
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
              if (activeBatches.length > 1) ...[
                const SizedBox(height: 3),
                InkWell(
                  onTap: () => _showLotSelectionDialog(product, variant),
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFFBFDBFE)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.layers_outlined,
                          size: 11,
                          color: Color(0xFF2563EB),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '${activeBatches.length} Lots',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1D4ED8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        DataCell(
          SizedBox(
            width: 80,
            child: TextField(
              key: ValueKey('copies-$id'),
              controller: _copyController(id),
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 6,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                ),
              ),
              onChanged: (value) {
                final parsed = int.tryParse(value);
                setState(() {
                  if (parsed != null && parsed > 0) {
                    _copies[id] = parsed;
                    _invalidCopies.remove(id);
                  } else {
                    _invalidCopies.add(id);
                  }
                });
              },
            ),
          ),
        ),
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                effectiveMrp > 0
                    ? 'INR ${(effectiveMrp / 100).toStringAsFixed(2)}'
                    : 'Unavailable',
                style: TextStyle(
                  color: effectiveMrp > 0
                      ? const Color(0xFF0F172A)
                      : const Color(0xFFDC2626),
                  fontWeight: effectiveMrp > 0 ? FontWeight.w700 : null,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(
                  Icons.edit_outlined,
                  size: 15,
                  color: Color(0xFF64748B),
                ),
                tooltip: 'Edit label prices',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => _editPriceDialog(product, variant),
              ),
            ],
          ),
        ),
        DataCell(
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                effectiveSell > 0
                    ? 'INR ${(effectiveSell / 100).toStringAsFixed(2)}'
                    : 'Unavailable',
                style: TextStyle(
                  color: effectiveSell > 0
                      ? const Color(0xFF0F172A)
                      : const Color(0xFFDC2626),
                  fontWeight: effectiveSell > 0 ? FontWeight.w700 : null,
                  fontSize: 12,
                ),
              ),
              if (activeBatches.length > 1) ...[
                const SizedBox(height: 2),
                InkWell(
                  onTap: () => _showLotSelectionDialog(product, variant),
                  child: const Text(
                    'Choose lot price ▾',
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFF2563EB),
                      decoration: TextDecoration.underline,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        DataCell(_statusPill(status, enabled)),
      ],
    );
  }

  Widget _statusPill(String status, bool enabled) {
    final (
      Color bg,
      Color text,
      Color border,
      IconData icon,
    ) = switch (status) {
      'Ready to print' => (
        const Color(0xFFDCFCE7),
        const Color(0xFF15803D),
        const Color(0xFF86EFAC),
        Icons.check_circle_rounded,
      ),
      'No stock available' => (
        const Color(0xFFFEF3C7),
        const Color(0xFFB45309),
        const Color(0xFFFDE68A),
        Icons.inventory_2_outlined,
      ),
      'Product is inactive' || 'Variant is inactive' => (
        const Color(0xFFFEE2E2),
        const Color(0xFFB91C1C),
        const Color(0xFFFECACA),
        Icons.cancel_outlined,
      ),
      'Not received' => (
        const Color(0xFFEFF6FF),
        const Color(0xFF1D4ED8),
        const Color(0xFFBFDBFE),
        Icons.pending_actions_rounded,
      ),
      _ => (
        const Color(0xFFFEF3C7),
        const Color(0xFFD97706),
        const Color(0xFFFDE68A),
        Icons.info_outline_rounded,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: text),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              status,
              style: TextStyle(
                color: text,
                fontWeight: FontWeight.w600,
                fontSize: 11,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  void _editPriceDialog(ProductModel product, ProductVariantModel variant) {
    final currentMrp = _effectiveMrp(variant);
    final currentSell = _effectiveSellingPrice(variant);
    final mrpController = TextEditingController(
      text: currentMrp > 0 ? (currentMrp / 100).toStringAsFixed(2) : '',
    );
    final sellController = TextEditingController(
      text: currentSell > 0 ? (currentSell / 100).toStringAsFixed(2) : '',
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit Label Prices · ${variant.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: mrpController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'MRP (INR)',
                prefixText: '₹ ',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: sellController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Selling Price (INR)',
                prefixText: '₹ ',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final mrpVal = double.tryParse(mrpController.text.trim());
              final sellVal = double.tryParse(sellController.text.trim());
              if (mrpVal != null && mrpVal >= 0) {
                _mrpOverrides[_key(variant)] = (mrpVal * 100).round();
              }
              if (sellVal != null && sellVal >= 0) {
                _sellingPriceOverrides[_key(variant)] = (sellVal * 100).round();
              }
              Navigator.pop(ctx);
              setState(() {});
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _showLotSelectionDialog(
    ProductModel product,
    ProductVariantModel variant,
  ) async {
    final id = _key(variant);
    var batches = _variantBatches[id];
    if (batches == null && widget.loadVariantBatches != null) {
      try {
        batches = await widget.loadVariantBatches!(id);
        if (mounted) {
          setState(() => _variantBatches[id] = batches!);
        }
      } catch (_) {}
    }
    final activeBatches =
        batches?.where((b) => b.availableQty > 0).toList() ?? [];
    if (!mounted) return;
    if (activeBatches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No active purchase lots found for this variant.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.layers_outlined, color: Color(0xFF2563EB)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Select Purchase Lot · ${variant.name}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This product has multiple active purchase lots with different prices. Choose which lot to print barcode stickers for:',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < activeBatches.length; i++) ...[
                        () {
                          final batch = activeBatches[i];
                          final qtyUnits = batch.availableQty ~/ 1000;
                          final sellPrice =
                              (batch.sellingPricePaise / 100).toStringAsFixed(2);
                          final mrpPrice =
                              (batch.mrpPaise / 100).toStringAsFixed(2);
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              border: Border.all(color: const Color(0xFFCBD5E1)),
                              borderRadius: BorderRadius.circular(8),
                              color: const Color(0xFFF8FAFC),
                            ),
                            child: ListTile(
                              title: Text(
                                'Lot #${i + 1} (${batch.internalBatchNo})',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                              subtitle: Text(
                                'Stock: $qtyUnits units  |  Selling Price: ₹$sellPrice  |  MRP: ₹$mrpPrice',
                                style: const TextStyle(fontSize: 12),
                              ),
                              trailing: FilledButton.tonal(
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  setState(() {
                                    _selected.add(id);
                                    _focusedVariantId = id;
                                    if (qtyUnits > 0) {
                                      _copies[id] = qtyUnits;
                                      _copyControllers[id]?.text = '$qtyUnits';
                                      _invalidCopies.remove(id);
                                    }
                                    _sellingPriceOverrides[id] =
                                        batch.sellingPricePaise;
                                    if (batch.mrpPaise > 0) {
                                      _mrpOverrides[id] = batch.mrpPaise;
                                    }
                                  });
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Applied Lot #${i + 1}: $qtyUnits copies @ ₹$sellPrice',
                                      ),
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                                },
                                child: const Text('Apply Lot'),
                              ),
                            ),
                          );
                        }(),
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
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  TextEditingController _copyController(String variantId) =>
      _copyControllers.putIfAbsent(
        variantId,
        () => TextEditingController(text: '${_copies[variantId] ?? 1}'),
      );

  Widget _previewPanel(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final entry = _focusedEntry;
    final d = _dimensions ?? (50.0, 25.0);

    return Card(
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
            // Studio Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF132B45),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    Icons.style_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n?.labelTemplate ?? 'Label template',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const Text(
                        'Live Thermal Output Simulator',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: _selected.isNotEmpty
                        ? const Color(0xFFEFF6FF)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _selected.isNotEmpty
                          ? const Color(0xFFBFDBFE)
                          : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Text(
                    '${_selected.length} selected',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _selected.isNotEmpty
                          ? const Color(0xFF1D4ED8)
                          : const Color(0xFF64748B),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Template and Size row
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<_BarcodeTemplate>(
                    initialValue: _template,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Template',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: _BarcodeTemplate.standard,
                        child: Text('Standard'),
                      ),
                      DropdownMenuItem(
                        value: _BarcodeTemplate.compact,
                        child: Text('Compact'),
                      ),
                      DropdownMenuItem(
                        value: _BarcodeTemplate.price,
                        child: Text('Price Label'),
                      ),
                      DropdownMenuItem(
                        value: _BarcodeTemplate.barcodeOnly,
                        child: Text('Barcode Only'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) _setTemplate(value);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _size,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: l10n?.labelSize ?? 'Label Size',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    items: [
                      for (final size in _sizes.keys)
                        DropdownMenuItem(value: size, child: Text(size)),
                    ],
                    onChanged: (value) =>
                        setState(() => _size = value ?? _size),
                  ),
                ),
              ],
            ),
            if (_size == 'Custom') ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _customWidth,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: 'Width mm',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _customHeight,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: 'Height mm',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 10),

            // Content Element Toggles
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                _toggle(
                  'Show Business Name',
                  _showBusiness,
                  (v) => setState(() => _showBusiness = v),
                ),
                _toggle(
                  'Show Product Name',
                  _showProduct,
                  (v) => setState(() => _showProduct = v),
                ),
                _toggle(
                  'Show Variant',
                  _showVariant,
                  (v) => setState(() => _showVariant = v),
                ),
                _toggle(
                  'Show MRP',
                  _showMrp,
                  (v) => setState(() => _showMrp = v),
                ),
                _toggle(
                  'Show Selling Price',
                  _showSellingPrice,
                  (v) => setState(() => _showSellingPrice = v),
                ),
              ],
            ),
            if (_dimensions == null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Enter valid label dimensions.',
                  style: TextStyle(
                    color: theme.colorScheme.error,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            const SizedBox(height: 12),

            // Live Sticker Canvas
            if (entry == null)
              Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 32,
                  horizontal: 16,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: const Column(
                  children: [
                    Icon(
                      Icons.touch_app_outlined,
                      size: 28,
                      color: Color(0xFF94A3B8),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Select a row to see its live label preview.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              )
            else if (_eligibilityIssue(entry.$1, entry.$2) case final issue?)
              Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 24,
                  horizontal: 16,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFECACA)),
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      size: 28,
                      color: Color(0xFFDC2626),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Not eligible for printing: $issue',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFB91C1C),
                      ),
                    ),
                  ],
                ),
              )
            else if (_priceIssue(entry.$2) case final issue?)
              Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 24,
                  horizontal: 16,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.price_check_outlined,
                      size: 28,
                      color: Color(0xFFD97706),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Preview unavailable · $issue',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFB45309),
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${entry.$1.name} · ${entry.$2.name} · ${_copies[_key(entry.$2)] ?? 1} copies',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF334155),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 10),

              // Studio Mockup Box
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF1E293B)),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.print_outlined,
                              size: 13,
                              color: Color(0xFF94A3B8),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              '${d.$1.toInt()} × ${d.$2.toInt()} mm Thermal Sticker',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF94A3B8),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            '203 DPI · Code 128',
                            style: TextStyle(
                              fontSize: 9,
                              color: Color(0xFF38BDF8),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Container(
                      decoration: const BoxDecoration(
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black54,
                            blurRadius: 16,
                            offset: Offset(0, 6),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: _labelPreview(
                          _line(entry.$1, entry.$2),
                          key: _previewBoundaryKey,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (_previewSelected && _selected.length > 1)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Previewing focused row. ${_selected.length} variants selected.',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF64748B),
                  ),
                ),
              ),
            const SizedBox(height: 14),

            // Action Buttons
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  onPressed: _printing ? null : _preview,
                  icon: const Icon(Icons.preview_outlined, size: 16),
                  label: Text(l10n?.previewSelected ?? 'Preview Selected'),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  onPressed: _printing ? null : _downloadPdf,
                  icon: const Icon(
                    Icons.picture_as_pdf_outlined,
                    size: 16,
                    color: Color(0xFFDC2626),
                  ),
                  label: Text(l10n?.downloadPdf ?? 'Download PDF'),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  onPressed: _printing ? null : _downloadPng,
                  icon: const Icon(Icons.image_outlined, size: 16),
                  label: const Text('PNG'),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF132B45),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                  onPressed: _printing ? null : _printSelected,
                  icon: const Icon(Icons.print_rounded, size: 16),
                  label: Text(_printing ? 'Printing…' : 'Print'),
                ),
              ],
            ),
            if (_previewSelected && _selected.length > 1) ...[
              const Divider(height: 24),
              Text('Selected label preview', style: theme.textTheme.titleSmall),
              for (final line in _selectedLines) ...[
                const SizedBox(height: 10),
                Text(
                  '${line.productName} · ${line.variantName} · ${line.quantity} copies',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 6),
                Center(child: _labelPreview(line)),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _toggle(String label, bool value, ValueChanged<bool> onChanged) =>
      FilterChip(
        label: Text(label, style: const TextStyle(fontSize: 11)),
        selected: value,
        showCheckmark: true,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        onSelected: onChanged,
      );

  Widget _labelPreview(BarcodeLabelLine line, {Key? key}) {
    final d = _dimensions ?? (50.0, 25.0);
    final layout = BarcodeLabelLayout(
      widthMm: d.$1,
      heightMm: d.$2,
      showBusiness: _showBusiness && widget.businessName.isNotEmpty,
      showProduct: _showProduct,
      productLines: _showProduct
          ? BarcodeLabelLayout.estimateProductLines(
              line.productName,
              d.$1,
              d.$2,
            )
          : 0,
      showVariant: _showVariant,
      showMrp: _showMrp,
      showSellingPrice: _showSellingPrice,
    );
    return RepaintBoundary(
      key: key,
      child: Container(
        width: d.$1 * 3,
        height: d.$2 * 3,
        color: Colors.white,
        padding: EdgeInsets.symmetric(
          horizontal: layout.outerMarginMm * 3,
          vertical: layout.outerMarginMm * 3,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (layout.showBusiness)
              _labelText(
                widget.businessName,
                layout.businessFontPt,
                maxLines: 1,
              ),
            if (layout.showBusiness &&
                (layout.showProduct || layout.showVariant))
              SizedBox(height: layout.sectionGapMm * 3),
            if (layout.showProduct)
              _labelText(
                line.productName,
                layout.productFontPt,
                bold: true,
                maxLines: 2,
              ),
            if (layout.showProduct && layout.showVariant)
              SizedBox(height: layout.sectionGapMm * 3),
            if (layout.showVariant)
              _labelText(line.variantName, layout.variantFontPt, maxLines: 1),
            if (layout.showVariant) SizedBox(height: layout.sectionGapMm * 3),
            SizedBox(
              width: layout.barcodeWidthMm * 3,
              height: layout.barcodeHeightMm * 3,
              child: barcode_ui.BarcodeWidget(
                barcode: barcode_ui.Barcode.code128(),
                data: line.barcode,
                drawText: false,
                errorBuilder: (_, error) => Text('Invalid barcode: $error'),
              ),
            ),
            SizedBox(height: layout.sectionGapMm * 3),
            _labelText(line.barcode, layout.barcodeNumberFontPt, maxLines: 1),
            if (_showMrp || _showSellingPrice) ...[
              SizedBox(height: layout.sectionGapMm * 3),
              Row(
                children: [
                  if (_showMrp)
                    Expanded(
                      child: _labelText(
                        'MRP INR ${(line.mrp / 100).toStringAsFixed(2)}',
                        layout.priceFontPt,
                        maxLines: 1,
                      ),
                    ),
                  if (_showSellingPrice)
                    Expanded(
                      child: _labelText(
                        'Sell INR ${(line.sellingPrice / 100).toStringAsFixed(2)}',
                        layout.priceFontPt,
                        maxLines: 1,
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _labelText(
    String value,
    double points, {
    bool bold = false,
    int maxLines = 1,
  }) => Text(
    BarcodeLabelLayout.fitText(
      value,
      availableWidthMm: _dimensions?.$1 ?? 50,
      fontSizePt: points,
      maxLines: maxLines,
    ),
    textAlign: TextAlign.center,
    maxLines: maxLines,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      fontSize: BarcodeLabelLayout.flutterFontSize(points),
      height: 1.05,
      fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
      color: Colors.black,
    ),
  );
}
