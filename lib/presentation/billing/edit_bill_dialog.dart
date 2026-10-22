import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants/firebase_constants.dart';
import '../../data/models/product_variant_model.dart';
import '../../data/services/firestore_rest_service.dart';
import '../../domain/billing/bill_calculator.dart';
import '../../domain/billing/billing_models.dart';
import '../../domain/customers/customer_validators.dart';
import '../app_controller.dart';

class EditBillDialog extends StatefulWidget {
  const EditBillDialog({
    super.key,
    required this.controller,
    required this.row,
    required this.fields,
    required this.initialItems,
    required this.onBillUpdated,
  });

  final AppController controller;
  final Map<String, dynamic> row;
  final Map<String, dynamic> fields;
  final List<Map<String, dynamic>> initialItems;
  final VoidCallback onBillUpdated;

  static Future<void> show({
    required BuildContext context,
    required AppController controller,
    required Map<String, dynamic> row,
    required Map<String, dynamic> fields,
    required VoidCallback onBillUpdated,
  }) async {
    final token = controller.idToken;
    final service = controller.offline;
    final invoiceName = row['name'] as String?;
    if (token == null || service == null || invoiceName == null) return;
    final invoiceId = invoiceName.split('/').last;

    List<Map<String, dynamic>> items = const [];
    try {
      items = await service.queryDocuments(
        collection: FirebaseConstants.invoiceItems,
        filters: [FirestoreFilter('invoiceId', 'EQUAL', invoiceId)],
        orderBy: 'name',
        idToken: token,
      );
    } catch (_) {
      // Continue even if items query fails; dialog will report empty or load fallback
    }

    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => EditBillDialog(
        controller: controller,
        row: row,
        fields: fields,
        initialItems: items,
        onBillUpdated: onBillUpdated,
      ),
    );
  }

  @override
  State<EditBillDialog> createState() => _EditBillDialogState();
}

class _EditItemState {
  _EditItemState({
    required this.variantId,
    required this.sku,
    required this.name,
    required this.hsn,
    required this.unit,
    required this.conversionFactor,
    required this.trackStock,
    required this.gstRateBps,
    required this.priceIncludesTax,
    required int initialQuantity,
    required int initialUnitPricePaise,
    required int initialDiscountPaise,
    required VoidCallback onChanged,
  })  : qtyController = TextEditingController(text: initialQuantity.toString()),
        priceController = TextEditingController(
          text: (initialUnitPricePaise / 100).toStringAsFixed(2),
        ),
        discountController = TextEditingController(
          text: (initialDiscountPaise / 100).toStringAsFixed(2),
        ) {
    qtyController.addListener(onChanged);
    priceController.addListener(onChanged);
    discountController.addListener(onChanged);
  }

  final String variantId;
  final String sku;
  final String name;
  final String hsn;
  final String unit;
  final int conversionFactor;
  final bool trackStock;
  int gstRateBps;
  final bool priceIncludesTax;

  final TextEditingController qtyController;
  final TextEditingController priceController;
  final TextEditingController discountController;

  void dispose() {
    qtyController.dispose();
    priceController.dispose();
    discountController.dispose();
  }

  int? get quantity {
    final v = int.tryParse(qtyController.text.trim());
    return (v != null && v > 0) ? v : null;
  }

  int? get unitPricePaise => _parseMoney(priceController.text);
  int? get discountPaise => _parseMoney(discountController.text);

  BillLineInput? toBillLineInput() {
    final q = quantity;
    final p = unitPricePaise;
    final d = discountPaise ?? 0;
    if (q == null || p == null || p < 0 || d < 0) return null;
    return BillLineInput(
      variantId: variantId,
      sku: sku,
      name: name,
      hsn: hsn,
      quantity: q,
      unitPricePaise: p,
      discountPaise: d,
      gstRateBps: gstRateBps,
      priceIncludesTax: priceIncludesTax,
      unit: unit,
      conversionFactor: conversionFactor,
      trackStock: trackStock,
    );
  }

  static int? _parseMoney(String text) {
    final normalized = text.trim().replaceAll(',', '');
    if (normalized.isEmpty) return 0;
    final parts = normalized.split('.');
    if (parts.length > 2 || !RegExp(r'^\d+$').hasMatch(parts.first)) {
      return null;
    }
    if (parts.length == 2 && !RegExp(r'^\d{1,2}$').hasMatch(parts[1])) {
      return null;
    }
    final rupees = int.tryParse(parts.first) ?? 0;
    final paise = parts.length == 1 ? 0 : int.tryParse(parts[1].padRight(2, '0')) ?? 0;
    return rupees * 100 + paise;
  }
}

class _EditBillDialogState extends State<EditBillDialog> {
  late final TextEditingController _customerName;
  late final TextEditingController _customerPhone;
  late final TextEditingController _customerGstin;
  DateTime? _dueDate;
  late BillingTaxMode _taxMode;
  late final TaxStructure _taxStructure;
  final List<_EditItemState> _items = [];
  CalculatedBill? _calculated;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final f = widget.fields;
    _customerName = TextEditingController(text: f['customerName'] as String? ?? 'Walk-in');
    _customerPhone = TextEditingController(text: f['customerPhone'] as String? ?? '');
    _customerGstin = TextEditingController(text: f['customerGstin'] as String? ?? '');
    if (f['dueDate'] != null) {
      _dueDate = DateTime.tryParse(f['dueDate'] as String);
    }

    final taxModeStr = f['taxMode'] as String?;
    _taxMode = taxModeStr == 'nonGst' ? BillingTaxMode.nonGst : BillingTaxMode.gst;
    final igst = (f['igstPaise'] as num?)?.toInt() ?? 0;
    _taxStructure = igst > 0 ? TaxStructure.interState : TaxStructure.intraState;

    for (final raw in widget.initialItems) {
      final itemFields = FirestoreRestService.decodeFields(raw['fields']);
      final variantId = itemFields['variantId'] as String? ?? '';
      final sku = itemFields['sku'] as String? ?? '';
      final name = itemFields['name'] as String? ?? 'Item';
      final hsn = itemFields['hsn'] as String? ?? '';
      final qty = (itemFields['quantity'] as num?)?.toInt() ?? 1;
      final unitPricePaise = (itemFields['unitPricePaise'] as num?)?.toInt() ?? 0;
      final discountPaise = (itemFields['discountPaise'] as num?)?.toInt() ?? 0;
      final gstRateBps = (itemFields['gstRateBps'] as num?)?.toInt() ?? 0;
      final unit = itemFields['unit'] as String? ?? 'UNIT';
      final conversionFactor = (itemFields['conversionFactor'] as num?)?.toInt() ?? 1;
      final trackStock = itemFields['trackStock'] as bool? ?? true;
      final lineTotalPaise = (itemFields['lineTotalPaise'] as num?)?.toInt() ?? 0;
      final taxPaise = (itemFields['taxPaise'] as num?)?.toInt() ?? 0;
      final net = qty * unitPricePaise - discountPaise;
      final priceIncludesTax = (lineTotalPaise == net && taxPaise > 0);

      _items.add(
        _EditItemState(
          variantId: variantId,
          sku: sku,
          name: name,
          hsn: hsn,
          unit: unit,
          conversionFactor: conversionFactor,
          trackStock: trackStock,
          gstRateBps: gstRateBps,
          priceIncludesTax: priceIncludesTax,
          initialQuantity: qty,
          initialUnitPricePaise: unitPricePaise,
          initialDiscountPaise: discountPaise,
          onChanged: _recalculate,
        ),
      );
    }

    _recalculate();
  }

  @override
  void dispose() {
    _customerName.dispose();
    _customerPhone.dispose();
    _customerGstin.dispose();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  void _recalculate() {
    final validLines = <BillLineInput>[];
    for (final item in _items) {
      final line = item.toBillLineInput();
      if (line != null) {
        validLines.add(line);
      }
    }
    if (validLines.isEmpty) {
      setState(() {
        _calculated = null;
      });
      return;
    }
    try {
      final calc = const BillCalculator().calculate(
        lines: validLines,
        taxMode: _taxMode,
        taxStructure: _taxStructure,
      );
      setState(() {
        _calculated = calc;
      });
    } catch (_) {
      setState(() {
        _calculated = null;
      });
    }
  }

  void _removeItem(int index) {
    if (_items.length <= 1) return;
    setState(() {
      final item = _items.removeAt(index);
      item.dispose();
    });
    _recalculate();
  }

  Future<void> _pickDueDate() async {
    final initialDate = _dueDate ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      setState(() => _dueDate = picked);
    }
  }

  Future<void> _addProduct() async {
    final selected = await showDialog<ProductVariantModel>(
      context: context,
      builder: (dialogCtx) => _ProductPickerModal(
        products: widget.controller.products,
      ),
    );
    if (selected != null && mounted) {
      final existingIndex = _items.indexWhere(
        (item) => item.variantId == selected.variantId,
      );
      if (existingIndex >= 0) {
        final currentQty = _items[existingIndex].quantity ?? 1;
        _items[existingIndex].qtyController.text = (currentQty + 1).toString();
      } else {
        setState(() {
          _items.add(
            _EditItemState(
              variantId: selected.variantId,
              sku: selected.sku ?? '',
              name: selected.displayName,
              hsn: selected.hsnCode ?? '',
              unit: selected.commercialUnitName ?? selected.baseUnitId,
              conversionFactor: selected.baseQuantityPerCommercialUnit.toInt(),
              trackStock: selected.trackStock,
              gstRateBps: _taxMode == BillingTaxMode.gst ? selected.defaultGstRateBps : 0,
              priceIncludesTax: selected.priceIncludesTax,
              initialQuantity: 1,
              initialUnitPricePaise: selected.sellingPrice,
              initialDiscountPaise: 0,
              onChanged: _recalculate,
            ),
          );
        });
      }
      _recalculate();
    }
  }

  void _promptGstRateEdit(int index) async {
    if (index < 0 || index >= _items.length || _taxMode != BillingTaxMode.gst) return;
    final item = _items[index];
    final currentGstPercent = (item.gstRateBps / 100).toStringAsFixed(
      item.gstRateBps % 100 == 0 ? 0 : 2,
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
              item.name,
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
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
      setState(() {
        item.gstRateBps = (result * 100).round();
      });
      _recalculate();
    }
  }

  void _applyGstRateToAll(int rateBps) {
    if (_taxMode != BillingTaxMode.gst) return;
    setState(() {
      for (final item in _items) {
        item.gstRateBps = rateBps;
      }
    });
    _recalculate();
  }

  Future<void> _showSetAllGstDialog() async {
    if (_taxMode != BillingTaxMode.gst) return;
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
              'Enter the GST percentage to apply to all items in this bill:',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: textController,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
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

  Future<void> _save() async {
    final token = widget.controller.idToken;
    final repository = widget.controller.billingRepository;
    final invoiceName = widget.row['name'] as String?;
    if (token == null || repository == null || invoiceName == null) return;
    final invoiceId = invoiceName.split('/').last;

    if (_customerGstin.text.trim().isNotEmpty &&
        !CustomerValidators.isValidGstin(_customerGstin.text)) {
      setState(() => _error = 'Enter a valid 15-character GSTIN or leave it blank.');
      return;
    }

    if (_items.isEmpty) {
      setState(() => _error = 'At least one item is required.');
      return;
    }

    final lines = <BillLineInput>[];
    for (var i = 0; i < _items.length; i++) {
      final line = _items[i].toBillLineInput();
      if (line == null) {
        setState(() => _error = 'Please enter valid quantity and price for item #${i + 1}.');
        return;
      }
      lines.add(line);
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await repository.updateBill(
        invoiceId: invoiceId,
        customerName: _customerName.text.trim(),
        customerPhone: _customerPhone.text.trim(),
        customerGstin: _customerGstin.text.trim(),
        dueDate: _dueDate,
        lines: lines,
        taxMode: _taxMode,
        taxStructure: _taxStructure,
        token: token,
      );

      if (mounted) {
        Navigator.pop(context);
        widget.onBillUpdated();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Bill ${widget.fields['invoiceNumber'] ?? invoiceId} updated successfully.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _saving = false;
        });
      }
    }
  }

  String _formatMoney(int paise) =>
      '${paise ~/ 100}.${(paise % 100).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final f = widget.fields;
    final invoiceName = widget.row['name'] as String?;
    final invoiceId = invoiceName?.split('/').last ?? '';
    final invoiceNumber = f['invoiceNumber'] as String? ?? invoiceId;
    final paidPaise = (f['paidPaise'] as num?)?.toInt() ?? 0;
    final grandTotal = _calculated?.grandTotalPaise ?? (f['grandTotalPaise'] as num?)?.toInt() ?? 0;
    final newDue = (grandTotal - paidPaise).clamp(0, grandTotal);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860, maxHeight: 800),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.edit_note,
                    size: 28,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Edit Bill',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        Text(
                          'Invoice: $invoiceNumber',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.grey[700],
                              ),
                        ),
                      ],
                    ),
                  ),
                  SegmentedButton<BillingTaxMode>(
                    segments: const [
                      ButtonSegment(value: BillingTaxMode.gst, label: Text('GST')),
                      ButtonSegment(value: BillingTaxMode.nonGst, label: Text('Non-GST')),
                    ],
                    selected: {_taxMode},
                    onSelectionChanged: (val) {
                      setState(() {
                        _taxMode = val.first;
                        if (_taxMode == BillingTaxMode.nonGst) {
                          for (final it in _items) {
                            it.gstRateBps = 0;
                          }
                        } else {
                          for (final it in _items) {
                            if (it.gstRateBps == 0) {
                              it.gstRateBps = 1800;
                            }
                          }
                        }
                      });
                      _recalculate();
                    },
                  ),
                  const SizedBox(width: 8),
                  Chip(
                    label: Text(
                      f['status'] as String? ?? 'ACTIVE',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Close',
                    onPressed: _saving ? null : () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(height: 24),
              if (_error != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline,
                          color: Theme.of(context).colorScheme.error),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Section 1: Customer Details
                      Text(
                        'Customer & Bill Information',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          SizedBox(
                            width: 240,
                            child: TextField(
                              controller: _customerName,
                              decoration: const InputDecoration(
                                labelText: 'Customer Name',
                                prefixIcon: Icon(Icons.person_outline),
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 200,
                            child: TextField(
                              controller: _customerPhone,
                              keyboardType: TextInputType.phone,
                              decoration: const InputDecoration(
                                labelText: 'Phone Number',
                                prefixIcon: Icon(Icons.phone_outlined),
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 200,
                            child: TextField(
                              controller: _customerGstin,
                              textCapitalization: TextCapitalization.characters,
                              decoration: const InputDecoration(
                                labelText: 'GSTIN',
                                prefixIcon: Icon(Icons.badge_outlined),
                              ),
                            ),
                          ),
                          Container(
                            height: 48,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade400),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.calendar_today,
                                    size: 18, color: Colors.grey[700]),
                                const SizedBox(width: 8),
                                Text(
                                  _dueDate != null
                                      ? 'Due: ${_dueDate!.day}/${_dueDate!.month}/${_dueDate!.year}'
                                      : 'No due date',
                                  style: const TextStyle(fontSize: 13),
                                ),
                                const SizedBox(width: 4),
                                TextButton(
                                  onPressed: _pickDueDate,
                                  child: Text(_dueDate == null ? 'Set' : 'Change'),
                                ),
                                if (_dueDate != null)
                                  IconButton(
                                    icon: const Icon(Icons.clear, size: 16),
                                    tooltip: 'Clear due date',
                                    onPressed: () => setState(() => _dueDate = null),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Section 2: Items
                      Row(
                        children: [
                          Text(
                            'Bill Line Items (${_items.length})',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          const Spacer(),
                          OutlinedButton.icon(
                            onPressed: _addProduct,
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Add Product'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (_items.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Center(
                            child: Text('No items in this bill. Click "Add Product" to add one.'),
                          ),
                        )
                      else
                        Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            side: BorderSide(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Column(
                              children: [
                                // Table Header
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  child: Row(
                                    children: const [
                                      Expanded(
                                        flex: 4,
                                        child: Text(
                                          'Item Description',
                                          style: TextStyle(fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: Text(
                                          'Qty',
                                          style: TextStyle(fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: Text(
                                          'Rate (₹)',
                                          style: TextStyle(fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: Text(
                                          'Disc (₹)',
                                          style: TextStyle(fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: Text(
                                          'GST',
                                          style: TextStyle(fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: Text(
                                          'Total (₹)',
                                          textAlign: TextAlign.end,
                                          style: TextStyle(fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      SizedBox(width: 36),
                                    ],
                                  ),
                                ),
                                const Divider(height: 1),
                                for (var i = 0; i < _items.length; i++) ...[
                                  if (i > 0) const Divider(height: 1),
                                  _buildItemRow(i),
                                ],
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(height: 20),

                      // Section 3: Summary Totals
                      if (_calculated != null) ...[
                        Card(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _summaryLine('Subtotal', _calculated!.subtotalPaise),
                                if (_calculated!.totalDiscountPaise > 0)
                                  _summaryLine('Discount', _calculated!.totalDiscountPaise, isDeduction: true),
                                if (_taxMode == BillingTaxMode.gst) ...[
                                  _summaryLine('Taxable Amount', _calculated!.taxableTotalPaise),
                                  _summaryLine('GST Total', _calculated!.taxTotalPaise),
                                ] else ...[
                                  _summaryLine('GST (Turned off)', 0),
                                ],
                                if (_calculated!.roundOffPaise != 0)
                                  _summaryLine('Round Off', _calculated!.roundOffPaise),
                                if (_taxMode == BillingTaxMode.gst) ...[
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      const Icon(Icons.percent, size: 14),
                                      const SizedBox(width: 4),
                                      const Text(
                                        'Set Bill GST:',
                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                      ),
                                      const SizedBox(width: 6),
                                      ...[0, 5, 12, 18, 28].map((rate) {
                                        return Padding(
                                          padding: const EdgeInsets.only(right: 4),
                                          child: ActionChip(
                                            label: Text('$rate%'),
                                            visualDensity: VisualDensity.compact,
                                            padding: EdgeInsets.zero,
                                            onPressed: () => _applyGstRateToAll(rate * 100),
                                          ),
                                        );
                                      }),
                                      TextButton(
                                        onPressed: _showSetAllGstDialog,
                                        style: TextButton.styleFrom(
                                          visualDensity: VisualDensity.compact,
                                          padding: const EdgeInsets.symmetric(horizontal: 6),
                                        ),
                                        child: const Text('Custom'),
                                      ),
                                    ],
                                  ),
                                ],
                                const Divider(height: 16),
                                Row(
                                  children: [
                                    Text(
                                      'Updated Grand Total',
                                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      '₹${_formatMoney(_calculated!.grandTotalPaise)}',
                                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                            fontWeight: FontWeight.bold,
                                            color: Theme.of(context).colorScheme.primary,
                                          ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Text('Previously Paid: ₹${_formatMoney(paidPaise)}'),
                                    const Spacer(),
                                    Text(
                                      'Remaining Due: ₹${_formatMoney(newDue)}',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: newDue > 0 ? Colors.red.shade700 : Colors.green.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: (_saving || _items.isEmpty || _calculated == null) ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.check),
                    label: Text(_saving ? 'Saving Changes...' : 'Save Bill Changes'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildItemRow(int index) {
    final item = _items[index];
    final lineCalc = (_calculated != null && index < _calculated!.lines.length)
        ? _calculated!.lines[index]
        : null;
    final totalPaise = lineCalc?.lineTotalPaise ?? 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Item Description
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                Text(
                  '${item.unit} • ${item.sku.isNotEmpty ? item.sku : (item.hsn.isNotEmpty ? 'HSN ${item.hsn}' : 'Item')}',
                  style: TextStyle(color: Colors.grey[600], fontSize: 11),
                ),
              ],
            ),
          ),
          // Quantity
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 40,
              child: TextField(
                controller: item.qtyController,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Unit Rate
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 40,
              child: TextField(
                controller: item.priceController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.end,
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  prefixText: '₹',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Discount
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 40,
              child: TextField(
                controller: item.discountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.end,
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  prefixText: '₹',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // GST
          Expanded(
            flex: 2,
            child: _taxMode == BillingTaxMode.gst
                ? InkWell(
                    onTap: () => _promptGstRateEdit(index),
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                        border: Border.all(
                          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '${(item.gstRateBps / 100).toStringAsFixed(item.gstRateBps % 100 == 0 ? 0 : 1)}%',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          const SizedBox(width: 2),
                          Icon(
                            Icons.edit,
                            size: 10,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ],
                      ),
                    ),
                  )
                : Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      '0%',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
          ),
          // Total
          Expanded(
            flex: 2,
            child: Text(
              '₹${_formatMoney(totalPaise)}',
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
          // Delete action
          SizedBox(
            width: 36,
            child: IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
              tooltip: _items.length <= 1 ? 'Bill must have at least one item' : 'Remove item',
              onPressed: _items.length <= 1 ? null : () => _removeItem(index),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryLine(String label, int paise, {bool isDeduction = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
            Text(
              '${isDeduction ? "- " : ""}₹${_formatMoney(paise.abs())}',
              style: const TextStyle(fontSize: 13),
            ),
          ],
        ),
      );
}

class _ProductPickerModal extends StatefulWidget {
  const _ProductPickerModal({required this.products});
  final List<dynamic> products;

  @override
  State<_ProductPickerModal> createState() => _ProductPickerModalState();
}

class _ProductPickerModalState extends State<_ProductPickerModal> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final matchingVariants = <ProductVariantModel>[];
    for (final product in widget.products) {
      if (product.variants != null) {
        for (final variant in product.variants) {
          if (variant is ProductVariantModel) {
            if (_query.isEmpty ||
                variant.displayName.toLowerCase().contains(_query) ||
                (variant.sku?.toLowerCase().contains(_query) ?? false)) {
              matchingVariants.add(variant);
            }
          }
        }
      }
    }

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Select Product to Add',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _search,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Search product name or SKU',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (val) => setState(() => _query = val.trim().toLowerCase()),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: matchingVariants.isEmpty
                    ? const Center(child: Text('No matching products found.'))
                    : ListView.separated(
                        itemCount: matchingVariants.length,
                        separatorBuilder: (context, index) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final variant = matchingVariants[index];
                          final rate = (variant.sellingPrice / 100).toStringAsFixed(2);
                          return ListTile(
                            title: Text(variant.displayName),
                            subtitle: Text(
                              '${variant.sku ?? 'No SKU'} • GST ${(variant.defaultGstRateBps / 100).toStringAsFixed(1)}%',
                            ),
                            trailing: Text(
                              '₹$rate',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            onTap: () => Navigator.pop(context, variant),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
