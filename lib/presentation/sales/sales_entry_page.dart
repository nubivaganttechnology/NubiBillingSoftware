import 'package:flutter/material.dart';

import '../../core/errors/app_exception.dart';
import '../../core/utils/id_generator.dart';
import '../../data/models/product_variant_model.dart';
import '../../data/models/employee_model.dart';
import '../../data/models/sales_invoice_model.dart';
import '../../data/repositories/sales_repository.dart';
import '../../l10n/app_localizations.dart';
import '../app_controller.dart';
import '../billing/bill_search_page.dart';

class SalesManagementPage extends StatefulWidget {
  const SalesManagementPage({
    super.key,
    required this.controller,
    required this.onOpenModule,
    this.initialShowHistory = true,
  });
  final AppController controller;
  final ValueChanged<String> onOpenModule;
  final bool initialShowHistory;

  @override
  State<SalesManagementPage> createState() => _SalesManagementPageState();
}

class _SalesManagementPageState extends State<SalesManagementPage> {
  late bool _showHistory;

  @override
  void initState() {
    super.initState();
    _showHistory = widget.initialShowHistory;
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(SalesManagementPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Column(
        children: [
          // Executive Sub-Navigation Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(
                bottom: BorderSide(
                  color: theme.dividerColor.withValues(alpha: 0.15),
                ),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isCompact = constraints.maxWidth < 780;
                final headerInfo = Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF132B45).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.point_of_sale_rounded,
                        color: Color(0xFF132B45),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            l10n?.salesManagement ??
                                'Sales Management & Invoicing',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            _showHistory
                                ? (l10n?.salesHistoryAndSearch ??
                                      'Sales Invoices & History')
                                : (l10n?.createInvoice ?? 'Create New Invoice'),
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.textTheme.bodySmall?.color
                                  ?.withValues(alpha: 0.7),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                );

                final switcher = FittedBox(
                  fit: BoxFit.scaleDown,
                  child: SegmentedButton<bool>(
                    style: SegmentedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      selectedForegroundColor: Colors.white,
                      selectedBackgroundColor: const Color(0xFF132B45),
                    ),
                    segments: [
                      ButtonSegment<bool>(
                        value: true,
                        icon: const Icon(Icons.receipt_long_rounded, size: 16),
                        label: Text(l10n?.salesInvoices ?? 'Sales Invoices'),
                      ),
                      ButtonSegment<bool>(
                        value: false,
                        icon: const Icon(
                          Icons.add_shopping_cart_rounded,
                          size: 16,
                        ),
                        label: Text(l10n?.newSale ?? 'New Sale'),
                      ),
                    ],
                    selected: {_showHistory},
                    onSelectionChanged: (set) {
                      setState(() => _showHistory = set.first);
                    },
                  ),
                );

                if (isCompact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      headerInfo,
                      const SizedBox(height: 10),
                      Align(alignment: Alignment.centerLeft, child: switcher),
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: headerInfo),
                    const SizedBox(width: 16),
                    switcher,
                  ],
                );
              },
            ),
          ),
          Expanded(
            child: _showHistory
                ? BillSearchPage(
                    key: ValueKey(
                      'bill_search_${widget.controller.appContext?.businessId}_${widget.controller.appContext?.outletId}',
                    ),
                    controller: widget.controller,
                    onNewBill: () => setState(() => _showHistory = false),
                    embeddedInHub: true,
                  )
                : SalesEntryPage(
                    key: ValueKey(
                      'sales_entry_${widget.controller.appContext?.businessId}_${widget.controller.appContext?.outletId}',
                    ),
                    controller: widget.controller,
                    onOpenHistory: () => setState(() => _showHistory = true),
                    embeddedInHub: true,
                  ),
          ),
        ],
      ),
    );
  }
}

class SalesEntryPage extends StatefulWidget {
  const SalesEntryPage({
    super.key,
    required this.controller,
    this.onOpenHistory,
    this.embeddedInHub = false,
  });
  final AppController controller;
  final VoidCallback? onOpenHistory;
  final bool embeddedInHub;

  @override
  State<SalesEntryPage> createState() => _SalesEntryPageState();
}

class _SalesEntryPageState extends State<SalesEntryPage> {
  List<ProductVariantModel> _variants = const [];
  List<Map<String, dynamic>> _customers = const [];
  List<EmployeeModel> _staffEmployees = const [];
  final List<SalesInvoiceLine> _lines = [];
  DateTime _invoiceDate = DateTime.now();
  String? _customerId;
  String? _chargeToEmployeeId;
  String _invoiceId = IdGenerator.create('INV');
  bool _loading = true;
  bool _saving = false;
  String? _error;

  bool get _canChargeStaffKhata {
    try {
      return widget.controller.canChargeStaffKhata();
    } catch (_) {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final values = await Future.wait([
        widget.controller.loadSalesVariants(),
        widget.controller.loadSalesCustomers(),
      ]);
      final staffEmployees = _canChargeStaffKhata
          ? await widget.controller.loadStaffKhataEmployees()
          : const <EmployeeModel>[];
      if (!mounted) return;
      setState(() {
        _variants = values[0] as List<ProductVariantModel>;
        _customers = values[1] as List<Map<String, dynamic>>;
        _staffEmployees = staffEmployees;
      });
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final subtotal = _lines.fold<int>(
      0,
      (sum, line) => sum + line.quantity * line.unitPrice,
    );
    final tax = _lines.fold<int>(
      0,
      (sum, line) => sum + line.lineTotal - line.taxableAmount,
    );
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 760;
            final title = Wrap(
              spacing: 12,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  l10n?.newSale ?? 'New Sale',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFC18B35).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFFC18B35).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    '#$_invoiceId',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFB47B25),
                    ),
                  ),
                ),
              ],
            );
            final actions = Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: compact ? WrapAlignment.end : WrapAlignment.start,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (widget.onOpenHistory != null && !widget.embeddedInHub)
                  OutlinedButton.icon(
                    onPressed: widget.onOpenHistory,
                    icon: const Icon(Icons.receipt_long_outlined, size: 18),
                    label: Text(
                      l10n?.salesHistoryAndSearch ?? 'Sales History & Search',
                    ),
                  ),
                IconButton.filledTonal(
                  tooltip: l10n?.refreshLocalData ?? 'Refresh local data',
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh, size: 18),
                ),
              ],
            );
            return compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [title, const SizedBox(height: 8), actions],
                  )
                : Row(
                    children: [
                      Expanded(child: title),
                      const SizedBox(width: 12),
                      actions,
                    ],
                  );
          },
        ),
        const SizedBox(height: 16),
        if (_error != null) _errorBanner(_error!),
        if (_loading) const LinearProgressIndicator(),
        _card(context, l10n?.customerAndInvoice ?? 'Customer and invoice', [
          Wrap(
            spacing: 16,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 320,
                child: DropdownButtonFormField<String?>(
                  initialValue: _customerId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: l10n?.customerAndInvoice ?? 'Customer',
                    prefixIcon: const Icon(Icons.person_outline, size: 20),
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Walk-in Customer'),
                    ),
                    for (final customer in _customers)
                      DropdownMenuItem<String?>(
                        value: customer['customerId'] as String,
                        child: Text(
                          customer['name'] as String,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => setState(() {
                          _customerId = value;
                          if (value != null) _chargeToEmployeeId = null;
                        }),
                ),
              ),
              if (_canChargeStaffKhata)
                SizedBox(
                  width: 320,
                  child: DropdownButtonFormField<String?>(
                    initialValue: _chargeToEmployeeId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Charge to Staff Khata',
                      prefixIcon: Icon(Icons.badge_outlined, size: 20),
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Regular customer sale'),
                      ),
                      for (final employee in _staffEmployees)
                        DropdownMenuItem<String?>(
                          value: employee.employeeId,
                          child: Text(
                            employee.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _saving
                        ? null
                        : (value) => setState(() {
                            _chargeToEmployeeId = value;
                            if (value != null) _customerId = null;
                          }),
                  ),
                ),
              OutlinedButton.icon(
                onPressed: _saving
                    ? null
                    : () async {
                        final selected = await showDatePicker(
                          context: context,
                          initialDate: _invoiceDate,
                          firstDate: DateTime(2000),
                          lastDate: DateTime.now().add(
                            const Duration(days: 365),
                          ),
                        );
                        if (selected != null) {
                          setState(() => _invoiceDate = selected);
                        }
                      },
                icon: const Icon(Icons.calendar_today_outlined, size: 18),
                label: Text(
                  '${l10n?.invoiceDate ?? 'Invoice date'} · ${_date(_invoiceDate)}',
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF64748B).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  '₹ Minor-unit convention · Auto-converted',
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ]),
        const SizedBox(height: 16),
        _card(context, l10n?.saleItems ?? 'Sale items', [
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF132B45),
                foregroundColor: Colors.white,
              ),
              onPressed: _loading || _saving || _variants.isEmpty
                  ? null
                  : _addLine,
              icon: const Icon(Icons.add_shopping_cart, size: 18),
              label: Text(l10n?.addProductVariant ?? 'Add Product / Variant'),
            ),
          ),
          const SizedBox(height: 12),
          if (_lines.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.inventory_2_outlined,
                      size: 44,
                      color: Theme.of(context).dividerColor,
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Add a product and allocate its quantity to verified batches.',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          for (var i = 0; i < _lines.length; i++)
            _lineCard(context, _lines[i], i, l10n),
        ]),
        const SizedBox(height: 16),
        _card(context, l10n?.invoiceSummary ?? 'Invoice summary', [
          _summaryRow('Subtotal', subtotal),
          _summaryRow('GST', tax),
          const Divider(height: 20),
          _summaryRow(
            l10n?.totalUnpaid ?? 'Total · Unpaid',
            subtotal + tax,
            strong: true,
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF3B82F6).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: const Color(0xFF3B82F6).withValues(alpha: 0.2),
              ),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, size: 18, color: Color(0xFF2563EB)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'This first Sales workflow posts unpaid invoices. Customer payments and payment allocations can be settled at any time from Sales History.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF1E40AF)),
                  ),
                ),
              ],
            ),
          ),
        ]),
        const SizedBox(height: 20),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF059669),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            ),
            onPressed: _saving || _lines.isEmpty ? null : _post,
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
                  ? (l10n?.postingLocally ?? 'Posting locally…')
                  : (l10n?.postSale ?? 'Post Sale'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }

  Widget _lineCard(
    BuildContext context,
    SalesInvoiceLine line,
    int index,
    AppLocalizations? l10n,
  ) => Card(
    elevation: 0,
    margin: const EdgeInsets.only(top: 8),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: BorderSide(
        color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
      ),
    ),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: const Color(0xFF132B45),
            foregroundColor: Colors.white,
            radius: 16,
            child: Text(
              '${index + 1}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${line.productName} · ${line.variantName}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF64748B).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Qty: ${line.quantity} ${line.commercialUnitId}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF059669).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${line.batchAllocations.length} ${l10n?.batchAllocations ?? 'batches'} (${line.batchAllocations.fold<int>(0, (s, a) => s + a.baseQuantity)} units)',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF059669),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '₹${_money(line.lineTotal)}',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: l10n?.removeLine ?? 'Remove line',
            onPressed: _saving
                ? null
                : () => setState(() => _lines.removeAt(index)),
            icon: const Icon(Icons.delete_outline, color: Color(0xFFDC2626)),
          ),
        ],
      ),
    ),
  );

  Future<void> _addLine() async {
    final line = await showDialog<SalesInvoiceLine>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ManualSaleLineDialog(
        variants: _variants,
        loadBatches: widget.controller.loadSalesBatches,
      ),
    );
    if (line != null && mounted) setState(() => _lines.add(line));
  }

  Future<void> _post() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final customer = _customers
          .where((row) => row['customerId'] == _customerId)
          .firstOrNull;
      final invoiceId = await widget.controller.postSalesInvoice(
        invoiceId: _invoiceId,
        invoiceDate: _invoiceDate,
        customerId: _customerId,
        customerName: customer?['name'] as String?,
        chargeToEmployeeId: _chargeToEmployeeId,
        lines: List.unmodifiable(_lines),
      );
      if (!mounted) return;
      setState(() {
        _lines.clear();
        _invoiceId = IdGenerator.create('INV');
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sale $invoiceId saved locally and queued for sync.'),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _summaryRow(String label, int amount, {bool strong = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: strong
                    ? const TextStyle(fontWeight: FontWeight.w700)
                    : null,
              ),
            ),
            Text(
              '₹${_money(amount)}',
              style: strong
                  ? const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)
                  : null,
            ),
          ],
        ),
      );

  Widget _card(BuildContext context, String title, List<Widget> children) =>
      Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.15),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 14),
              ...children,
            ],
          ),
        ),
      );

  Widget _errorBanner(String message) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(message),
  );
}

class _ManualSaleLineDialog extends StatefulWidget {
  const _ManualSaleLineDialog({
    required this.variants,
    required this.loadBatches,
  });
  final List<ProductVariantModel> variants;
  final Future<List<SalesBatchOption>> Function(
    String productId,
    String variantId,
  )
  loadBatches;

  @override
  State<_ManualSaleLineDialog> createState() => _ManualSaleLineDialogState();
}

class _ManualSaleLineDialogState extends State<_ManualSaleLineDialog> {
  final _quantity = TextEditingController(text: '1');
  final _price = TextEditingController();
  ProductVariantModel? _variant;
  List<SalesBatchOption> _batches = const [];
  final Map<String, TextEditingController> _allocations = {};
  bool _loadingBatches = false;
  String? _error;

  @override
  void dispose() {
    _quantity.dispose();
    _price.dispose();
    for (final controller in _allocations.values) {
      controller.dispose();
    }
    super.dispose();
  }

  int get _qty => int.tryParse(_quantity.text.trim()) ?? 0;
  int get _factor => _variant == null
      ? 0
      : (_variant!.baseQuantityPerCommercialUnit * 1000).round();
  int get _requiredBase =>
      _qty > 0 && _factor > 0 ? (_qty * _factor + 500) ~/ 1000 : 0;
  int get _allocated => _allocations.values.fold<int>(
    0,
    (sum, controller) => sum + (int.tryParse(controller.text.trim()) ?? 0),
  );
  int get _priceMinor => _toMinor(_price.text);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.add_shopping_cart, color: Color(0xFF132B45)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n?.addProductVariant ??
                  'Add sale item · manual batch allocation',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 720,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Autocomplete<ProductVariantModel>(
                displayStringForOption: (variant) =>
                    '${variant.productName ?? 'Product'} · ${variant.name}',
                optionsBuilder: (value) {
                  final q = value.text.toLowerCase();
                  return widget.variants.where(
                    (variant) =>
                        '${variant.productName} ${variant.name} ${variant.barcode ?? ''}'
                            .toLowerCase()
                            .contains(q),
                  );
                },
                onSelected: (variant) {
                  setState(() {
                    _variant = variant;
                    _batches = const [];
                    for (final controller in _allocations.values) {
                      controller.dispose();
                    }
                    _allocations.clear();
                    _price.text = _fromMinor(variant.sellingPrice);
                    _error = null;
                  });
                },
                fieldViewBuilder: (context, controller, focusNode, onSubmit) =>
                    TextField(
                      controller: controller,
                      focusNode: focusNode,
                      decoration: InputDecoration(
                        labelText:
                            '${l10n?.search ?? 'Search'} · Product / variant',
                        prefixIcon: const Icon(Icons.search),
                      ),
                    ),
              ),
              if (_variant != null) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    SizedBox(
                      width: 130,
                      child: TextField(
                        controller: _quantity,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Quantity',
                          isDense: true,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    SizedBox(
                      width: 160,
                      child: TextField(
                        controller: _price,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Selling Price ₹',
                          isDense: true,
                        ),
                      ),
                    ),
                    InputChip(
                      label: Text('GST ${_variant!.defaultGstRateBps / 100}%'),
                    ),
                    InputChip(
                      label: Text(
                        '${l10n?.required ?? 'Required base quantity'}: $_requiredBase',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: _loadingBatches || _requiredBase <= 0
                      ? null
                      : _loadBatches,
                  icon: const Icon(Icons.inventory_2_outlined),
                  label: Text(
                    _loadingBatches
                        ? (l10n?.loadingBatches ?? 'Loading local batches…')
                        : (l10n?.loadVerifiedBatches ??
                              'Load verified batches'),
                  ),
                ),
                const SizedBox(height: 8),
                if (_batches.isEmpty && !_loadingBatches)
                  const Text(
                    'Load local batches to allocate this line. Legacy batches without verified receipt-ledger coverage cannot be selected.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                for (final batch in _batches) _batchRow(batch, l10n),
                if (_batches.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '${l10n?.allocated ?? 'Allocated'} $_allocated / ${l10n?.required ?? 'Required'} $_requiredBase · ${l10n?.remaining ?? 'Remaining'} ${_requiredBase - _allocated}',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: _allocated == _requiredBase
                            ? Colors.green
                            : Colors.deepOrange,
                      ),
                    ),
                  ),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n?.cancel ?? 'Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF132B45),
            foregroundColor: Colors.white,
          ),
          onPressed: _variant == null ? null : _save,
          child: Text(l10n?.addLine ?? 'Add line'),
        ),
      ],
    );
  }

  Widget _batchRow(SalesBatchOption batch, AppLocalizations? l10n) {
    _allocations.putIfAbsent(
      batch.batchId,
      () => TextEditingController(text: '0'),
    );
    final allocation = _allocations[batch.batchId]!;
    final location =
        '${batch.storageType} · ${batch.storageLocationId}${batch.rackId == null ? '' : ' · Rack ${batch.rackId}'}';
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(top: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: batch.trusted
              ? const Color(0xFFE2E8F0)
              : Colors.deepOrange.withValues(alpha: 0.3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        batch.internalBatchNo,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(width: 8),
                      if (batch.trusted)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF059669)
                                .withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'Verified',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF059669),
                            ),
                          ),
                        ),
                    ],
                  ),
                  Text(
                    'Supplier lot: ${batch.supplierLotNo ?? '—'} · Expiry: ${_dateText(batch.expiryDate)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  Text(
                    '$location · Available ${batch.availableBaseQuantity} base units',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  if (!batch.trusted)
                    const Text(
                      'This batch does not have verified movement-ledger coverage and cannot be used for strict allocation yet.',
                      style: TextStyle(color: Colors.deepOrange, fontSize: 11),
                    ),
                ],
              ),
            ),
            SizedBox(
              width: 130,
              child: TextField(
                controller: allocation,
                enabled: batch.trusted,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: l10n?.allocateBaseQty ?? 'Allocate base qty',
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadBatches() async {
    final variant = _variant!;
    setState(() {
      _loadingBatches = true;
      _error = null;
    });
    try {
      final batches = await widget.loadBatches(
        variant.productId ?? '',
        variant.variantId,
      );
      if (!mounted) return;
      for (final controller in _allocations.values) {
        controller.dispose();
      }
      _allocations.clear();
      setState(() => _batches = batches);
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _loadingBatches = false);
    }
  }

  void _save() {
    final variant = _variant!;
    final quantity = _qty;
    final baseQuantity = _requiredBase;
    final allocations = <SalesBatchAllocation>[];
    for (final batch in _batches) {
      final entered =
          int.tryParse(_allocations[batch.batchId]?.text.trim() ?? '') ?? 0;
      if (entered < 0 || entered > batch.availableBaseQuantity) {
        setState(
          () => _error =
              'Allocation for ${batch.internalBatchNo} must be between 0 and ${batch.availableBaseQuantity}.',
        );
        return;
      }
      if (entered > 0) {
        if (!batch.trusted) {
          setState(() => _error = 'Unverified batches cannot be allocated.');
          return;
        }
        allocations.add(
          SalesBatchAllocation(batchId: batch.batchId, baseQuantity: entered),
        );
      }
    }
    if (quantity <= 0 ||
        baseQuantity <= 0 ||
        _priceMinor < 0 ||
        allocations.isEmpty ||
        _allocated != baseQuantity) {
      setState(
        () => _error =
            'Enter a positive quantity and price, then allocate exactly $_requiredBase base units across verified batches.',
      );
      return;
    }
    final taxable = quantity * _priceMinor;
    final tax = (taxable * variant.defaultGstRateBps + 5000) ~/ 10000;
    final line = SalesInvoiceLine(
      invoiceLineId: 'LINE-${DateTime.now().microsecondsSinceEpoch}',
      productId: variant.productId ?? '',
      variantId: variant.variantId,
      productName: variant.productName ?? 'Product',
      variantName: variant.name,
      quantity: quantity,
      commercialUnitId: variant.commercialUnitId ?? variant.baseUnitId,
      baseUnitId: variant.baseUnitId,
      conversionFactor: _factor,
      baseQuantity: baseQuantity,
      unitPrice: _priceMinor,
      mrp: variant.mrp,
      gstPercent: variant.defaultGstRateBps / 100,
      taxableAmount: taxable,
      lineTotal: taxable + tax,
      batchAllocations: allocations,
    );
    Navigator.pop(context, line);
  }
}

String _message(Object error) =>
    error is AppException ? error.message : error.toString();
int _toMinor(String value) {
  final parsed = double.tryParse(value.trim().replaceAll(',', ''));
  return parsed == null || !parsed.isFinite ? -1 : (parsed * 100).round();
}

String _fromMinor(int value) => (value / 100).toStringAsFixed(2);
String _money(int value) => (value / 100).toStringAsFixed(2);
String _date(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
String _dateText(String? value) => value == null ? '—' : value.split('T').first;
