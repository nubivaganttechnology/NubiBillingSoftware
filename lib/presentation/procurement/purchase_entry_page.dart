import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models/product_variant_model.dart';
import '../../data/models/purchase_bill_model.dart';
import '../../data/models/storage_location_model.dart';
import '../../data/models/supplier_model.dart';
import '../app_controller.dart';
import '../../l10n/app_localizations.dart';
import 'supplier_pages.dart' show showSupplierFormFromPurchase;

class PurchaseEntryPage extends StatefulWidget {
  const PurchaseEntryPage({
    super.key,
    required this.controller,
    required this.onClose,
    this.draftToEdit,
  });
  final AppController controller;
  final VoidCallback onClose;
  final PurchaseBillModel? draftToEdit;

  @override
  State<PurchaseEntryPage> createState() => _PurchaseEntryPageState();
}

class _PurchaseEntryPageState extends State<PurchaseEntryPage> {
  static const _directStorageValue = '__DIRECT_STORAGE__';
  final _form = GlobalKey<FormState>();
  final _invoice = TextEditingController();
  final _discount = TextEditingController(text: '0');
  final _roundOff = TextEditingController(text: '0');
  final _paidNow = TextEditingController(text: '0');
  final _paymentReference = TextEditingController();
  final _paymentNotes = TextEditingController();
  final _rows = List.generate(5, (_) => _PurchaseEntryRow());
  final _gridHorizontalScroll = ScrollController();
  final _charges = <_ChargeRow>[];
  List<SupplierModel> _suppliers = [];
  String? _supplierId;
  DateTime _invoiceDate = DateTime.now();
  DateTime _purchaseDate = DateTime.now();
  String _discountType = 'FIXED_AMOUNT';
  String _paymentStatus = 'UNPAID';
  String _paymentMethod = 'CASH';
  DateTime? _dueDate;
  bool _dirty = false;
  bool _saving = false;
  bool _review = false;
  bool _preview = false;
  int _activeGridRow = 0;
  int _activeGridColumn = 0;

  @override
  void initState() {
    super.initState();
    final outletId = widget.controller.currentOutlet?.outletId;
    for (final row in _rows) {
      row.locationType = 'OUTLET';
      row.locationId = outletId;
      row.locationKey = outletId == null ? null : 'OUTLET:$outletId';
    }
    final draft = widget.draftToEdit;
    if (draft != null && draft.status == 'DRAFT') {
      _invoice.text = draft.supplierInvoiceNumber;
      _supplierId = draft.supplierId;
      _invoiceDate = draft.invoiceDate;
      _purchaseDate = draft.purchaseDate ?? draft.invoiceDate;
      _discount.text = _rupees(draft.discountAmount);
      _roundOff.text = _rupees(draft.roundOff);
      if (draft.chargesAmount != 0) {
        _charges.add(_ChargeRow()..amount.text = _rupees(draft.chargesAmount));
      }
      for (var i = 0; i < draft.items.length; i++) {
        if (i >= _rows.length) _rows.add(_PurchaseEntryRow());
        final item = draft.items[i];
        final row = _rows[i];
        row.goodsReceiptItemId = item.goodsReceiptItemId;
        row.variant = widget.controller.purchaseProducts
            .where((v) => v.variantId == item.variantId)
            .firstOrNull;
        row.initialVariantId = item.variantId;
        row.product.text = item.productName;
        row.variantName.text = item.variantName ?? item.productName;
        row.hsn.text = item.hsnCode ?? '';
        row.qty.text = _formatQuantity(item.quantity);
        row.unit.text =
            row.variant?.commercialUnitName ??
            item.commercialUnitId ??
            item.unitId;
        row.rate.text = _rupees(item.rate);
        row.gst.text = (item.gstRateBps / 100)
            .toStringAsFixed(2)
            .replaceFirst(RegExp(r'\.00$'), '');
        row.mrp.text = _rupees(item.mrp ?? 0);
        row.selling.text = _rupees(item.sellingPrice ?? 0);
        row.supplierLot.text = item.supplierLotNo ?? '';
        row.manufacturingDate.text =
            item.manufacturingDate?.toIso8601String().split('T').first ?? '';
        row.expiryDate.text =
            item.expiryDate?.toIso8601String().split('T').first ?? '';
        row.internalBatchNo = item.internalBatchNo ?? '';
        row.locationType = item.storageType ?? 'OUTLET';
        row.locationId = item.storageLocationId ?? outletId;
        row.locationKey = row.locationId == null
            ? null
            : '${row.locationType}:${row.locationId}';
        row.rackId = item.rackId;
        row.editRevision++;
      }
    }
    _suppliers = List.of(widget.controller.suppliers);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await widget.controller.loadStorageLocations();
      if (mounted) {
        setState(() => _suppliers = List.of(widget.controller.suppliers));
      }
    });
  }

  @override
  void dispose() {
    _gridHorizontalScroll.dispose();
    _invoice.dispose();
    _discount.dispose();
    _roundOff.dispose();
    _paidNow.dispose();
    _paymentReference.dispose();
    _paymentNotes.dispose();
    for (final row in _rows) {
      row.dispose();
    }
    for (final charge in _charges) {
      charge.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope<Object?>(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _confirmLeave();
    },
    child: Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          _entryToolbar(),
          Expanded(
            child: _review
                ? _reviewPanel()
                : _preview
                ? _previewPanel()
                : _entryBody(),
          ),
          _entryFooter(),
        ],
      ),
    ),
  );

  Widget _entryToolbar() => LayoutBuilder(
    builder: (context, constraints) {
      final l10n = AppLocalizations.of(context);
      final title = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Back to Purchases',
            onPressed: _confirmLeave,
            icon: const Icon(Icons.arrow_back),
          ),
          const SizedBox(width: 4),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.draftToEdit == null
                    ? (l10n?.newPurchase ?? 'New Purchase')
                    : (l10n?.editDraftPurchase ?? 'Edit Draft Purchase'),
                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
              ),
              const Text(
                'Enterprise Procurement · Invoice inwarding & item entry',
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
            ],
          ),
        ],
      );
      final actions = Wrap(
        spacing: 8,
        children: [
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => setState(() {
              _preview = true;
              _review = false;
            }),
            icon: const Icon(Icons.preview_outlined, size: 16),
            label: const Text('Preview'),
          ),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: _saving ? null : _saveDraft,
            icon: const Icon(Icons.save_outlined, size: 16),
            label: Text(l10n?.saveDraft ?? 'Save Draft'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF132B45),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: _saving ? null : _reviewAndPost,
            icon: const Icon(Icons.fact_check_outlined, size: 16),
            label: Text(l10n?.reviewAndPost ?? 'Review & Post'),
          ),
        ],
      );
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 8),
        child: constraints.maxWidth >= 900
            ? Row(children: [title, const Spacer(), actions])
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [title, const SizedBox(height: 10), actions],
              ),
      );
    },
  );

  Widget _entryFooter() => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
    decoration: BoxDecoration(
      color: Theme.of(context).cardColor,
      border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
    ),
    child: Wrap(
      alignment: WrapAlignment.end,
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: _confirmLeave,
          icon: const Icon(Icons.close),
          label: const Text('Cancel'),
        ),
        OutlinedButton.icon(
          onPressed: () => setState(() {
            _preview = true;
            _review = false;
          }),
          icon: const Icon(Icons.preview_outlined),
          label: const Text('Preview'),
        ),
        OutlinedButton(
          onPressed: _saving ? null : _saveDraft,
          child: const Text('Save Draft'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _reviewAndPost,
          icon: const Icon(Icons.fact_check_outlined),
          label: const Text('Review & Post'),
        ),
      ],
    ),
  );

  Widget _entryBody() {
    final l10n = AppLocalizations.of(context);
    final c = widget.controller;
    final variants = c.purchaseProducts;
    final outlets = c.outlets.where((o) => o.isActive).toList();
    final godowns = c.storageLocations
        .where((l) => l.type == StorageLocationType.godown && l.isActive)
        .toList();
    final locations = <_StockLocation>[
      ...outlets.map((o) => _StockLocation('OUTLET', o.outletId, o.outletName)),
      ...godowns.map(
        (g) => _StockLocation('GODOWN', g.storageLocationId, g.name),
      ),
    ];
    final lineCount = _rows.where((r) => r.hasContent).length;
    final subtotal = _rows.fold<int>(0, (sum, row) => sum + row.taxablePaise);
    final chargeTotal = _charges.fold<int>(
      0,
      (sum, charge) => sum + (_moneyToPaise(charge.amount.text) ?? 0),
    );
    final discountRaw = _moneyToPaise(_discount.text) ?? 0;
    final discount = _discountType == 'PERCENTAGE'
        ? (subtotal * discountRaw ~/ 10000)
        : discountRaw;
    final totalTax = _taxAfterDiscount(discount);
    final sameState =
        _supplierStateCode() != null &&
        _businessStateCode() != null &&
        _supplierStateCode() == _businessStateCode();
    final cgst = sameState ? totalTax ~/ 2 : 0;
    final sgst = sameState ? totalTax - cgst : 0;
    final igst = sameState ? 0 : totalTax;
    final grand =
        (subtotal - discount).clamp(0, 1 << 62) +
        totalTax +
        chargeTotal +
        (_signedMoney(_roundOff.text) ?? 0);
    return Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
        children: [
          _supplierHeader(l10n),
          const SizedBox(height: 14),
          _excelToolbar(l10n, lineCount),
          _purchaseGrid(variants, locations, subtotal, grand),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final summary = _summary(
                lineCount,
                subtotal,
                discount,
                cgst,
                sgst,
                igst,
                chargeTotal,
                grand,
              );
              return constraints.maxWidth >= 1000
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 3, child: _chargesPanel()),
                        const SizedBox(width: 12),
                        SizedBox(width: 360, child: summary),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _chargesPanel(),
                        const SizedBox(height: 10),
                        summary,
                      ],
                    );
            },
          ),
          const SizedBox(height: 12),
          _paymentPanel(grand),
          if (c.error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                c.error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (c.productsError?.isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                c.productsError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    );
  }

  Widget _excelToolbar(AppLocalizations? l10n, int lineCount) => LayoutBuilder(
    builder: (context, constraints) {
      final info = Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: const Color(0xFF107C41).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(Icons.grid_on_rounded, size: 18, color: Color(0xFF107C41)),
          ),
          Text(
            l10n?.purchaseItems ?? 'Purchase Items',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0F172A),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$lineCount item(s)',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFA5D6A7)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check, size: 12, color: Color(0xFF2E7D32)),
                SizedBox(width: 4),
                Text(
                  'Excel Grid Mode',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF2E7D32)),
                ),
              ],
            ),
          ),
        ],
      );

      final actions = Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              side: const BorderSide(color: Color(0xFFCBD5E1)),
              backgroundColor: Colors.white,
            ),
            onPressed: _copyActiveRow,
            icon: const Icon(Icons.content_copy, size: 14, color: Color(0xFF334155)),
            label: Text(
              l10n?.copyRow ?? 'Copy Row',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
            ),
          ),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              side: const BorderSide(color: Color(0xFFCBD5E1)),
              backgroundColor: Colors.white,
            ),
            onPressed: _pasteGrid,
            icon: const Icon(Icons.content_paste, size: 14, color: Color(0xFF107C41)),
            label: Text(
              l10n?.pasteFromExcel ?? 'Paste from Excel',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF107C41)),
            ),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF107C41),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            onPressed: _addRow,
            icon: const Icon(Icons.add, size: 14),
            label: Text(
              l10n?.addRow ?? 'Add Row',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      );

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: const BoxDecoration(
          color: Color(0xFFF8FAFC),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(8),
            topRight: Radius.circular(8),
          ),
          border: Border(
            top: BorderSide(color: Color(0xFFCBD5E1)),
            left: BorderSide(color: Color(0xFFCBD5E1)),
            right: BorderSide(color: Color(0xFFCBD5E1)),
          ),
        ),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 10,
          children: [
            info,
            actions,
          ],
        ),
      );
    },
  );


  Widget _supplierHeader(AppLocalizations? l10n) => Container(
    padding: const EdgeInsets.all(16),
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
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF132B45).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.store_rounded, size: 16, color: Color(0xFF132B45)),
            ),
            const SizedBox(width: 8),
            Text(
              l10n?.supplierBill ?? 'Supplier & Invoice Details',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F172A),
              ),
            ),
            if (_supplierId != null) ...[
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.location_on_outlined, size: 13, color: Color(0xFF64748B)),
                    const SizedBox(width: 4),
                    Text(
                      _placeDisplay(),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF475569),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 14),

        // Fields Row: Supplier, Add Supplier, Invoice No, Invoice Date, Purchase Date
        Wrap(
          spacing: 12,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // Supplier Autocomplete
            SizedBox(
              width: 320,
              child: Autocomplete<SupplierModel>(
                key: ValueKey(_supplierId),
                initialValue: TextEditingValue(text: _selectedSupplierCaption()),
                displayStringForOption: (s) => _supplierCaption(s),
                optionsBuilder: (value) {
                  final q = value.text.toLowerCase();
                  return _suppliers.where(
                    (s) =>
                        s.isActive &&
                        (q.isEmpty ||
                            [
                              s.name,
                              s.mobile ?? '',
                              s.gstin ?? '',
                            ].any((v) => v.toLowerCase().contains(q))),
                  );
                },
                onSelected: (s) {
                  setState(() {
                    _supplierId = s.supplierId;
                    _dirty = true;
                  });
                },
                fieldViewBuilder: (context, text, focus, submit) => TextFormField(
                  controller: text,
                  focusNode: focus,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    labelText: l10n?.suppliers ?? 'Supplier',
                    hintText: 'Search supplier name, mobile, GSTIN...',
                    isDense: true,
                    prefixIcon: const Icon(Icons.business_outlined, size: 18),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF132B45), width: 1.5),
                    ),
                  ),
                  onChanged: (value) {
                    final match = _suppliers.where(
                      (s) => _supplierCaption(s) == value,
                    );
                    if (match.isEmpty && _supplierId != null) {
                      setState(() {
                        _supplierId = null;
                        _dirty = true;
                      });
                    } else {
                      _markDirty();
                    }
                  },
                ),
              ),
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                side: const BorderSide(color: Color(0xFFCBD5E1)),
              ),
              onPressed: widget.controller.canCreateSuppliers()
                  ? _addSupplier
                  : null,
              icon: const Icon(Icons.person_add_alt_1, size: 16),
              label: const Text('Add Supplier', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            SizedBox(
              width: 200,
              child: TextFormField(
                controller: _invoice,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  labelText: l10n?.supplierInvoiceNo ?? 'Supplier Invoice #',
                  hintText: 'e.g. INV-2026-001',
                  isDense: true,
                  prefixIcon: const Icon(Icons.receipt_long_outlined, size: 18),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFF132B45), width: 1.5),
                  ),
                ),
                onChanged: (_) => _markDirty(),
              ),
            ),
            _dateField(l10n?.invoiceDate ?? 'Invoice Date', _invoiceDate, (d) {
              setState(() {
                _invoiceDate = d;
                _dirty = true;
              });
            }),
            _dateField(l10n?.purchaseDate ?? 'Purchase Date', _purchaseDate, (d) {
              setState(() {
                _purchaseDate = d;
                _dirty = true;
              });
            }),
          ],
        ),
        const SizedBox(height: 12),

        // Sub-row: Document Inwarding OCR Tools
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Wrap(
            spacing: 10,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.document_scanner_outlined, size: 16, color: Color(0xFF64748B)),
                  SizedBox(width: 6),
                  Text(
                    'Smart Bill Inward:',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF475569),
                    ),
                  ),
                ],
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  side: const BorderSide(color: Color(0xFFCBD5E1)),
                  backgroundColor: Colors.white,
                ),
                onPressed: _importUnavailable,
                icon: const Icon(Icons.document_scanner, size: 14),
                label: const Text('Scan Bill', style: TextStyle(fontSize: 12)),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  side: const BorderSide(color: Color(0xFFCBD5E1)),
                  backgroundColor: Colors.white,
                ),
                onPressed: _importUnavailable,
                icon: const Icon(Icons.image_outlined, size: 14),
                label: const Text('Upload Image', style: TextStyle(fontSize: 12)),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  side: const BorderSide(color: Color(0xFFCBD5E1)),
                  backgroundColor: Colors.white,
                ),
                onPressed: _importUnavailable,
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 14),
                label: const Text('Upload PDF', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _dateField(
    String label,
    DateTime date,
    ValueChanged<DateTime> onChanged,
  ) => OutlinedButton.icon(
    style: OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      side: const BorderSide(color: Color(0xFFCBD5E1)),
      backgroundColor: Colors.white,
    ),
    onPressed: () async {
      final value = await showDatePicker(
        context: context,
        initialDate: date,
        firstDate: DateTime(2000),
        lastDate: DateTime.now().add(const Duration(days: 365)),
      );
      if (value != null) onChanged(value);
    },
    icon: const Icon(Icons.calendar_month_outlined, size: 16, color: Color(0xFF132B45)),
    label: Text(
      '$label: ${_date(date)}',
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Color(0xFF1E293B),
      ),
    ),
  );

  String _placeDisplay() {
    final supplier = _suppliers
        .where((s) => s.supplierId == _supplierId)
        .firstOrNull;
    final code =
        supplier?.stateCode ??
        (supplier?.gstin != null && supplier!.gstin!.length >= 2
            ? supplier.gstin!.substring(0, 2)
            : null);
    if (code == null || code.isEmpty) return 'State: not provided';
    return '${_stateName(code)} ($code)';
  }

  String _supplierCaption(SupplierModel supplier) => [
    supplier.name,
    supplier.mobile,
    supplier.gstin,
  ].whereType<String>().where((v) => v.trim().isNotEmpty).join(' · ');
  String _selectedSupplierCaption() {
    final selected = _suppliers
        .where((s) => s.supplierId == _supplierId)
        .firstOrNull;
    return selected == null ? '' : _supplierCaption(selected);
  }

  Widget _purchaseGrid(
    List<ProductVariantModel> variants,
    List<_StockLocation> locations,
    int subtotal,
    int grand,
  ) {
    final height = (38 + _rows.length * 42 + 38).clamp(280, 520).toDouble();
    return Container(
      height: height,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          left: BorderSide(color: Color(0xFFCBD5E1)),
          right: BorderSide(color: Color(0xFFCBD5E1)),
          bottom: BorderSide(color: Color(0xFFCBD5E1)),
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(8),
          bottomRight: Radius.circular(8),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Scrollbar(
        controller: _gridHorizontalScroll,
        thumbVisibility: true,
        notificationPredicate: (notification) =>
            notification.metrics.axis == Axis.horizontal,
        child: SingleChildScrollView(
          key: const ValueKey('purchase-items-horizontal-scroll'),
          controller: _gridHorizontalScroll,
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: _gridWidth,
            child: Column(
              children: [
                _gridHeader(),
                Expanded(
                  child: ListView.builder(
                    physics: const ClampingScrollPhysics(),
                    itemCount: _rows.length,
                    itemBuilder: (context, i) =>
                        _gridRow(i, variants, locations),
                  ),
                ),
                _gridTotalRow(subtotal, grand),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _gridTotalRow(int subtotal, int grand) {
    double totalQty = 0;
    for (final row in _rows) {
      final q = _quantity(row.qty.text);
      if (q != null) totalQty += q / 1000.0;
    }

    final lineItemsTotal = _rows.fold<int>(0, (sum, row) => sum + row.totalPaise);

    return Container(
      height: 38,
      decoration: const BoxDecoration(
        color: Color(0xFFF1F5F9),
        border: Border(
          top: BorderSide(color: Color(0xFF94A3B8), width: 1.5),
          bottom: BorderSide(color: Color(0xFF334155), width: 2),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48 + 210 + 230 + 90 + 120 + 160 + 130 + 120 + 120,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: const BoxDecoration(
              border: Border(right: BorderSide(color: Color(0xFFCBD5E1))),
            ),
            child: Text(
              'Total (${_rows.where((r) => r.hasContent).length} items):',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF334155),
              ),
            ),
          ),
          Container(
            width: 80,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: const BoxDecoration(
              border: Border(right: BorderSide(color: Color(0xFFCBD5E1))),
            ),
            child: Text(
              totalQty > 0
                  ? totalQty.toStringAsFixed(totalQty.truncateToDouble() == totalQty ? 0 : 2)
                  : '—',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
              ),
            ),
          ),
          const SizedBox(width: 90),
          const SizedBox(width: 130),
          const SizedBox(width: 85),
          Container(
            width: 110,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: const BoxDecoration(
              border: Border(right: BorderSide(color: Color(0xFFCBD5E1))),
            ),
            child: Text(
              '₹${_rupees(subtotal)}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
              ),
            ),
          ),
          const SizedBox(width: 100),
          const SizedBox(width: 120),
          const SizedBox(width: 150),
          const SizedBox(width: 120),
          const SizedBox(width: 180),
          const SizedBox(width: 140),
          Container(
            width: 110,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: const BoxDecoration(
              border: Border(right: BorderSide(color: Color(0xFFCBD5E1))),
            ),
            child: Text(
              '₹${_rupees(lineItemsTotal)}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Color(0xFF107C41),
              ),
            ),
          ),
          const SizedBox(width: 60),
        ],
      ),
    );
  }

  static const _gridColumns = <(String, double)>[
    ('#', 48),
    ('Product', 210),
    ('Variant / Specification', 230),
    ('HSN', 90),
    ('Barcode', 120),
    ('Internal Batch No', 160),
    ('Supplier Lot', 130),
    ('Mfg Date', 130),
    ('Expiry Date', 130),
    ('Qty', 80),
    ('Unit', 90),
    ('Purchase Price', 130),
    ('GST %', 85),
    ('Taxable', 110),
    ('MRP', 100),
    ('Selling Price', 120),
    ('Receiving', 150),
    ('Store At', 120),
    ('Location', 180),
    ('Rack', 140),
    ('Total', 110),
    ('Delete', 60),
  ];

  double get _gridWidth =>
      _gridColumns.fold<double>(0, (total, column) => total + column.$2);

  Widget _gridHeader() => Row(
    children: [
      for (final (title, width) in _gridColumns) _gridHeaderCell(title, width),
    ],
  );

  Widget _gridHeaderCell(String title, double width) {
    final isRight = [
      'Qty',
      'Purchase Price',
      'GST %',
      'Taxable',
      'MRP',
      'Selling Price',
      'Total',
    ].contains(title);
    final isCenter = ['#', 'Delete'].contains(title);

    return Container(
      width: width,
      height: 38,
      alignment: isRight
          ? Alignment.centerRight
          : (isCenter ? Alignment.center : Alignment.centerLeft),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: const BoxDecoration(
        color: Color(0xFFF1F5F9),
        border: Border(
          right: BorderSide(color: Color(0xFFCBD5E1)),
          bottom: BorderSide(color: Color(0xFF94A3B8), width: 1.5),
        ),
      ),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Color(0xFF334155),
        ),
        softWrap: false,
      ),
    );
  }

  Widget _gridRow(
    int index,
    List<ProductVariantModel> variants,
    List<_StockLocation> locations,
  ) {
    final row = _rows[index];
    final isRowActive = _activeGridRow == index;
    final rowBg = isRowActive
        ? const Color(0xFFF0FDF4)
        : (index.isEven ? Colors.white : const Color(0xFFF8FAFC));
    final rackOptions = widget.controller.storageLocations
        .where(
          (l) =>
              l.type == StorageLocationType.rack &&
              l.isActive &&
              l.parentLocationId == row.locationId &&
              ((l.parentLocationType ?? '').toUpperCase() == row.locationType),
        )
        .toList();
    return Container(
      height: 42,
      color: rowBg,
      child: Row(
        children: [
          _cell(
            Text(
              '${index + 1}',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF64748B),
              ),
            ),
            48,
            rowIndex: index,
            colIndex: -1,
            alignment: Alignment.center,
            backgroundColor: const Color(0xFFF8FAFC),
          ),
          _cell(_productCell(row, variants, index), 210, rowIndex: index, colIndex: 0),
          _cell(_variantCell(row, variants, index), 230, rowIndex: index, colIndex: 1),
          _cell(
            _input(
              row.hsn,
              rowIndex: index,
              gridColumn: 2,
              onChanged: (_) => _markDirty(),
            ),
            90,
            rowIndex: index,
            colIndex: 2,
          ),
          _cell(
            Text(
              _previewBarcode(row),
              style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
            ),
            120,
            rowIndex: index,
            colIndex: -1,
          ),
          _cell(
            Tooltip(
              message: row.internalBatchNo.isEmpty
                  ? 'Generated by the app when this purchase is saved'
                  : row.internalBatchNo,
              child: Text(
                row.internalBatchNo.isEmpty
                    ? 'Generated on save'
                    : row.internalBatchNo,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: row.internalBatchNo.isEmpty ? FontStyle.italic : FontStyle.normal,
                  color: row.internalBatchNo.isEmpty ? const Color(0xFF94A3B8) : const Color(0xFF334155),
                ),
              ),
            ),
            160,
            rowIndex: index,
            colIndex: -1,
          ),
          _cell(
            _input(
              row.supplierLot,
              rowIndex: index,
              gridColumn: 3,
              onChanged: (_) => _markDirty(),
            ),
            130,
            rowIndex: index,
            colIndex: 3,
          ),
          _cell(
            _dateInput(
              row.manufacturingDate,
              rowIndex: index,
              gridColumn: 4,
              label: 'Mfg Date',
              isExpiry: false,
              onChanged: (_) => _markDirty(),
            ),
            130,
            rowIndex: index,
            colIndex: 4,
          ),
          _cell(
            _dateInput(
              row.expiryDate,
              rowIndex: index,
              gridColumn: 5,
              label: 'Expiry Date',
              isExpiry: true,
              mfgDate: DateTime.tryParse(row.manufacturingDate.text.trim()),
              onChanged: (_) => _markDirty(),
            ),
            130,
            rowIndex: index,
            colIndex: 5,
          ),
          _cell(
            _input(
              row.qty,
              number: true,
              rowIndex: index,
              gridColumn: 6,
              onChanged: (v) {
                _defaultReceived(row, v);
                _markDirty();
              },
            ),
            80,
            rowIndex: index,
            colIndex: 6,
          ),
          _cell(
            _input(
              row.unit,
              rowIndex: index,
              gridColumn: 7,
              onChanged: (_) => _markDirty(),
            ),
            90,
            rowIndex: index,
            colIndex: 7,
          ),
          _cell(
            _input(
              row.rate,
              number: true,
              rowIndex: index,
              gridColumn: 8,
              onChanged: (_) {
                setState(() {
                  _markDirty();
                });
              },
            ),
            130,
            rowIndex: index,
            colIndex: 8,
          ),
          _cell(
            _input(
              row.gst,
              number: true,
              rowIndex: index,
              gridColumn: 9,
              onChanged: (_) => _markDirty(),
            ),
            85,
            rowIndex: index,
            colIndex: 9,
          ),
          _cell(
            Text(
              '₹${_rupees(row.taxablePaise)}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F172A),
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            110,
            alignment: Alignment.centerRight,
            rowIndex: index,
            colIndex: -1,
          ),
          _cell(
            _input(
              row.mrp,
              number: true,
              rowIndex: index,
              gridColumn: 10,
              onChanged: (_) => _markDirty(),
            ),
            100,
            rowIndex: index,
            colIndex: 10,
          ),
          _cell(
            _input(
              row.selling,
              number: true,
              rowIndex: index,
              gridColumn: 11,
              onChanged: (_) => _markDirty(),
            ),
            120,
            rowIndex: index,
            colIndex: 11,
          ),
          _cell(_receivingCell(row), 150, rowIndex: index, colIndex: -1),
          _cell(_storeAtSelector(row, index), 120, rowIndex: index, colIndex: 12),
          _cell(_locationSelector(row, locations, index), 180, rowIndex: index, colIndex: 13),
          _cell(_rackSelector(row, rackOptions, index), 140, rowIndex: index, colIndex: 14),
          _cell(
            Text(
              '₹${_rupees(row.totalPaise)}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF107C41),
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            110,
            alignment: Alignment.centerRight,
            rowIndex: index,
            colIndex: -1,
          ),
          _cell(
            IconButton(
              tooltip: 'Delete row',
              onPressed: () {
                setState(() {
                  if (_rows.length > 1) {
                    row.dispose();
                    _rows.removeAt(index);
                  }
                  _dirty = true;
                });
              },
              icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFEF4444)),
            ),
            60,
            alignment: Alignment.center,
            rowIndex: index,
            colIndex: -1,
          ),
        ],
      ),
    );
  }

  Widget _storeAtSelector(_PurchaseEntryRow row, int rowIndex) =>
      DropdownButton<String>(
        key: ValueKey('purchase-store-at-$rowIndex'),
        value: row.locationType,
        isExpanded: true,
        underline: const SizedBox.shrink(),
        items: const [
          DropdownMenuItem(value: 'OUTLET', child: Text('Outlet')),
          DropdownMenuItem(value: 'GODOWN', child: Text('Godown')),
        ],
        onChanged: (type) {
          if (type == null) return;
          setState(() {
            _setActiveGridCell(rowIndex, 12);
            row.locationType = type;
            final outletId = widget.controller.currentOutlet?.outletId;
            if (type == 'OUTLET') {
              row.locationId = outletId;
              row.locationKey = outletId == null ? null : 'OUTLET:$outletId';
            } else {
              row.locationId = null;
              row.locationKey = null;
            }
            row.rackId = null;
            _dirty = true;
          });
        },
      );

  Widget _locationSelector(
    _PurchaseEntryRow row,
    List<_StockLocation> locations,
    int rowIndex,
  ) {
    final matchingLocations = locations
        .where((location) => location.type == row.locationType)
        .toList();
    final selected = locations
        .where((l) => '${l.type}:${l.id}' == row.locationKey)
        .firstOrNull;
    return Tooltip(
      message: selected == null
          ? 'Choose a stock location'
          : '${selected.type == 'OUTLET' ? 'Outlet' : 'Godown'} • ${selected.name}',
      child: DropdownButton<String>(
        key: ValueKey('purchase-location-$rowIndex'),
        value:
            matchingLocations.any(
              (location) =>
                  '${location.type}:${location.id}' == row.locationKey,
            )
            ? row.locationKey
            : null,
        isExpanded: true,
        hint: Text(
          row.locationType == 'GODOWN' ? 'Select godown' : 'Select outlet',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        disabledHint: const Text('No location available'),
        menuWidth: 280,
        underline: const SizedBox.shrink(),
        selectedItemBuilder: (context) => matchingLocations
            .map(
              (l) => Align(
                alignment: Alignment.centerLeft,
                child: Tooltip(
                  message:
                      '${l.type == 'OUTLET' ? 'Outlet' : 'Godown'} • ${l.name}',
                  child: Text(
                    '${l.type == 'OUTLET' ? 'Outlet' : 'Godown'} • ${l.name}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            )
            .toList(),
        items: matchingLocations
            .map(
              (l) => DropdownMenuItem(
                value: '${l.type}:${l.id}',
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      l.type == 'OUTLET' ? 'Outlet' : 'Godown',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
            )
            .toList(),
        onChanged: matchingLocations.isEmpty
            ? null
            : (value) => setState(() {
                _setActiveGridCell(rowIndex, 13);
                row.locationKey = value;
                final parts = value?.split(':');
                row.locationType = parts?.first;
                row.locationId = parts?.last;
                row.rackId = null;
                _dirty = true;
              }),
      ),
    );
  }

  Widget _rackSelector(
    _PurchaseEntryRow row,
    List<StorageLocationModel> racks,
    int rowIndex,
  ) {
    final selected = racks
        .where((rack) => rack.storageLocationId == row.rackId)
        .firstOrNull;
    final hasLocation = row.locationId != null;
    return Tooltip(
      message: selected == null ? 'No Rack / Direct Storage' : selected.name,
      child: DropdownButton<String>(
        key: ValueKey('purchase-rack-$rowIndex'),
        value: hasLocation ? (row.rackId ?? _directStorageValue) : null,
        isExpanded: true,
        menuWidth: 180,
        underline: const SizedBox.shrink(),
        hint: Text(
          hasLocation ? 'No Rack / Direct Storage' : 'Select location',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        selectedItemBuilder: (context) => [
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'No Rack',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          ...racks.map(
            (rack) => Align(
              alignment: Alignment.centerLeft,
              child: Tooltip(
                message: rack.name,
                child: Text(
                  rack.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        ],
        items: [
          const DropdownMenuItem<String>(
            value: _directStorageValue,
            child: Text('No Rack / Direct Storage'),
          ),
          ...racks.map(
            (rack) => DropdownMenuItem(
              value: rack.storageLocationId,
              child: Text(
                rack.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
        onChanged: !hasLocation
            ? null
            : (value) => setState(() {
                _setActiveGridCell(rowIndex, 14);
                row.rackId = value == _directStorageValue ? null : value;
                _dirty = true;
              }),
      ),
    );
  }

  Widget _receivingCell(_PurchaseEntryRow row) {
    final received = row.received.text.isEmpty
        ? row.qty.text
        : row.received.text;
    final receivedMilli = _quantity(received) ?? 0;
    final rejected = row.rejected.text.isEmpty ? '0' : row.rejected.text;
    final rejectedMilli = _quantity(rejected) ?? 0;
    final accepted = _formatQuantity(
      (receivedMilli - rejectedMilli).clamp(0, receivedMilli),
    );
    final purchaseMilli = _quantity(row.qty.text) ?? 0;
    final normal = receivedMilli == purchaseMilli && rejectedMilli == 0;
    final short = receivedMilli < purchaseMilli && rejectedMilli == 0;
    final display = purchaseMilli == 0
        ? '—'
        : normal
        ? '$accepted accepted'
        : short
        ? '$received received'
        : '$accepted accepted • $rejected rejected';
    return Tooltip(
      message: purchaseMilli == 0
          ? 'Enter Purchase Qty to edit receiving.'
          : 'Received $received · Accepted $accepted · Rejected $rejected',
      child: TextButton.icon(
        onPressed: () => _editReceiving(row),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          minimumSize: const Size(0, 32),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        icon: const Icon(Icons.inventory_2_outlined, size: 15),
        label: Text(display, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }

  Future<void> _editReceiving(_PurchaseEntryRow row) async {
    final qty = _quantity(row.qty.text) ?? 0;
    if (qty <= 0) {
      _message('Enter a Purchase Qty before editing receiving details.');
      return;
    }
    final receivedController = TextEditingController(
      text: row.received.text.isEmpty ? row.qty.text : row.received.text,
    );
    final rejectedController = TextEditingController(
      text: row.rejected.text.isEmpty ? '0' : row.rejected.text,
    );
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) {
            final receivedRaw = receivedController.text.trim();
            final rejectedRaw = rejectedController.text.trim();
            final received = _quantity(receivedRaw);
            final rejected = _quantity(rejectedRaw);
            final receivedError = received == null
                ? 'Enter a valid quantity of 0 or more.'
                : received > qty
                ? 'Received quantity cannot exceed Purchase Qty.'
                : null;
            final rejectedError = rejected == null
                ? 'Enter a valid quantity of 0 or more.'
                : received != null && rejected > received
                ? 'Rejected quantity cannot exceed Received Qty.'
                : null;
            final accepted = received != null && rejected != null
                ? (received - rejected).clamp(0, received)
                : 0;
            final hasError = receivedError != null || rejectedError != null;
            return AlertDialog(
              title: const Text('Receiving Details'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Purchase Qty',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            row.qty.text,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    _receivingInput(
                      'Received Qty',
                      receivedController,
                      helperText: 'Total quantity physically received from the supplier.',
                      errorText: receivedError,
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    _receivingInput(
                      'Rejected / Damaged Qty',
                      rejectedController,
                      helperText:
                          'Damaged, defective or otherwise rejected goods.',
                      errorText: rejectedError,
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 4),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Accepted into Stock',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: const Text(
                        'Calculated automatically: Received − Rejected',
                      ),
                      trailing: Text(
                        _formatQuantity(accepted),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    Text(
                      '${_formatQuantity(accepted)} units will be added to usable stock.',
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
                  onPressed: hasError
                      ? null
                      : () {
                          row.received.text = receivedController.text;
                          row.rejected.text = rejectedController.text;
                          row.accepted.text = _formatQuantity(accepted);
                          _markDirty();
                          Navigator.pop(dialogContext);
                        },
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        ),
      );
    } finally {
      receivedController.dispose();
      rejectedController.dispose();
    }
  }

  Widget _receivingInput(
    String label,
    TextEditingController controller, {
    required String helperText,
    required String? errorText,
    required ValueChanged<String> onChanged,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        helperText: helperText,
        errorText: errorText,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
    ),
  );

  Widget _productCell(
    _PurchaseEntryRow row,
    List<ProductVariantModel> variants,
    int rowIndex,
  ) => Autocomplete<ProductVariantModel>(
    key: ValueKey('product_${row.hashCode}_${row.editRevision}'),
    initialValue: TextEditingValue(text: row.product.text),
    displayStringForOption: (v) => v.productName ?? v.name,
    optionsBuilder: (value) {
      final q = value.text.toLowerCase().trim();
      if (q.isEmpty) return const Iterable<ProductVariantModel>.empty();
      return variants.where(
        (v) => [
          v.productName ?? '',
          v.brand ?? '',
          v.sku ?? '',
          v.barcode ?? '',
          v.name,
        ].any((x) => x.toLowerCase().contains(q)),
      );
    },
    onSelected: (variant) {
      setState(() {
        if (row.variant?.variantId != variant.variantId) {
          if (row.initialVariantId != null &&
              row.initialVariantId != variant.variantId) {
            row.goodsReceiptItemId = null;
          }
          row.internalBatchNo = '';
        }
        row.variant = variant;
        row.product.text = variant.productName ?? variant.name;
        row.variantName.text = variant.name;
        row.unit.text =
            variant.commercialUnitName ??
            variant.commercialUnitId ??
            variant.baseUnitId;
        row.gst.text = (variant.defaultGstRateBps / 100).toStringAsFixed(2);
        row.hsn.text = variant.hsnCode ?? '';
        row.editRevision++;
        _dirty = true;
      });
    },
    fieldViewBuilder: (_, controller, focus, submit) => TextField(
      controller: controller,
      focusNode: focus,
      style: const TextStyle(fontSize: 13, color: Color(0xFF0F172A)),
      onTap: () => _setActiveGridCell(rowIndex, 0),
      onChanged: (v) {
        row.product.text = v;
        if (v.isNotEmpty && indexOfLast(row)) _ensureBlankRow();
        _markDirty();
      },
      cursorColor: const Color(0xFF107C41),
      decoration: InputDecoration(
        isDense: true,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        errorBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        filled: false,
        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        hintText: 'Search / type product',
        hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
        suffixIcon: row.variant == null && row.product.text.isNotEmpty
            ? const Icon(Icons.new_releases_outlined, size: 14, color: Color(0xFFD97706))
            : null,
      ),
    ),
  );

  String _previewBarcode(_PurchaseEntryRow target) {
    final selected = target.variant;
    if (selected == null) return '';
    return selected.barcode?.trim() ?? '';
  }

  Widget _variantCell(
    _PurchaseEntryRow row,
    List<ProductVariantModel> variants,
    int rowIndex,
  ) => Autocomplete<ProductVariantModel>(
    key: ValueKey('variant_${row.hashCode}_${row.editRevision}'),
    initialValue: TextEditingValue(text: row.variantName.text),
    displayStringForOption: (v) => v.name,
    optionsBuilder: (value) {
      final q = value.text.toLowerCase().trim();
      final product = row.variant?.productName;
      return variants.where(
        (v) =>
            (product == null || v.productName == product) &&
            (q.isEmpty ||
                v.name.toLowerCase().contains(q) ||
                (v.barcode?.toLowerCase().contains(q) ?? false)),
      );
    },
    onSelected: (v) {
      setState(() {
        if (row.variant?.variantId != v.variantId) {
          if (row.initialVariantId != null &&
              row.initialVariantId != v.variantId) {
            row.goodsReceiptItemId = null;
          }
          row.internalBatchNo = '';
        }
        row.variant = v;
        row.variantName.text = v.name;
        row.unit.text =
            v.commercialUnitName ?? v.commercialUnitId ?? v.baseUnitId;
        row.gst.text = (v.defaultGstRateBps / 100).toStringAsFixed(2);
        row.hsn.text = v.hsnCode ?? '';
        row.editRevision++;
        _dirty = true;
      });
    },
    fieldViewBuilder: (_, controller, focus, submit) => TextField(
      controller: controller,
      focusNode: focus,
      style: const TextStyle(fontSize: 13, color: Color(0xFF0F172A)),
      onTap: () => _setActiveGridCell(rowIndex, 1),
      onChanged: (v) {
        row.variantName.text = v;
        if (v.isNotEmpty && indexOfLast(row)) _ensureBlankRow();
        _markDirty();
      },
      cursorColor: const Color(0xFF107C41),
      decoration: const InputDecoration(
        isDense: true,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        errorBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        filled: false,
        contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        hintText: 'Type variant',
        hintStyle: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
      ),
    ),
  );

  _PurchaseEntryRow _newEntryRow() {
    final row = _PurchaseEntryRow();
    final outletId = widget.controller.currentOutlet?.outletId;
    row.locationType = 'OUTLET';
    row.locationId = outletId;
    row.locationKey = outletId == null ? null : 'OUTLET:$outletId';
    return row;
  }

  bool indexOfLast(_PurchaseEntryRow row) => identical(row, _rows.last);
  void _ensureBlankRow() {
    if (_rows.length < 500) setState(() => _rows.add(_newEntryRow()));
  }

  void _addRow() => setState(() {
    _rows.add(_newEntryRow());
    _dirty = true;
  });

  void _setActiveGridCell(int row, int column) {
    _activeGridRow = row.clamp(0, _rows.length - 1);
    _activeGridColumn = column.clamp(0, 14);
  }

  Future<void> _copyActiveRow() async {
    if (_rows.isEmpty) return;
    final row = _rows[_activeGridRow.clamp(0, _rows.length - 1)];
    final location =
        widget.controller.storageLocations
            .where((value) => value.storageLocationId == row.locationId)
            .map((value) => value.name)
            .firstOrNull ??
        widget.controller.outlets
            .where((value) => value.outletId == row.locationId)
            .map((value) => value.outletName)
            .firstOrNull ??
        '';
    final rack =
        widget.controller.storageLocations
            .where((value) => value.storageLocationId == row.rackId)
            .map((value) => value.name)
            .firstOrNull ??
        '';
    final received = row.received.text.isEmpty
        ? row.qty.text
        : row.received.text;
    final rejected = row.rejected.text.isEmpty ? '0' : row.rejected.text;
    final accepted = _formatQuantity(
      ((_quantity(received) ?? 0) - (_quantity(rejected) ?? 0)).clamp(
        0,
        _quantity(received) ?? 0,
      ),
    );
    final values = [
      row.product.text,
      row.variantName.text,
      row.hsn.text,
      _previewBarcode(row),
      row.internalBatchNo,
      row.supplierLot.text,
      row.manufacturingDate.text,
      row.expiryDate.text,
      row.qty.text,
      row.unit.text,
      row.rate.text,
      row.gst.text,
      '₹${_rupees(row.taxablePaise)}',
      row.mrp.text,
      row.selling.text,
      '$accepted accepted${(_quantity(rejected) ?? 0) > 0 ? ' • $rejected rejected' : ''}',
      row.locationType ?? '',
      location,
      rack,
      '₹${_rupees(row.totalPaise)}',
    ];
    await Clipboard.setData(ClipboardData(text: values.join('\t')));
    if (mounted) _message('Purchase row copied to clipboard.');
  }

  Future<void> _pasteGrid() async {
    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    final raw = clipboard?.text;
    if (raw == null || raw.trim().isEmpty) {
      _message('Clipboard is empty. Copy spreadsheet cells, then paste again.');
      return;
    }
    final lines = raw
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n');
    while (lines.isNotEmpty && lines.last.trim().isEmpty) {
      lines.removeLast();
    }
    final matrix = lines.map((line) => line.split('\t').toList()).toList();
    if (matrix.isEmpty) return;

    final variants = widget.controller.purchaseProducts;
    final locations = <_StockLocation>[
      ...widget.controller.outlets
          .where((o) => o.isActive)
          .map((o) => _StockLocation('OUTLET', o.outletId, o.outletName)),
      ...widget.controller.storageLocations
          .where((g) => g.type == StorageLocationType.godown && g.isActive)
          .map((g) => _StockLocation('GODOWN', g.storageLocationId, g.name)),
    ];
    final startRow = _activeGridRow.clamp(0, _rows.length - 1);
    final startColumn = _activeGridColumn.clamp(0, 14);
    final isFullGridExport = matrix.any((row) => row.length >= 16);

    setState(() {
      for (var r = 0; r < matrix.length; r++) {
        final rowIndex = startRow + r;
        while (rowIndex >= _rows.length && _rows.length < 500) {
          _rows.add(_newEntryRow());
        }
        if (rowIndex >= _rows.length) break;
        final row = _rows[rowIndex];
        final cells = matrix[r];

        if (isFullGridExport) {
          // Map full 20-column clipboard from _copyActiveRow
          if (cells.isNotEmpty) row.product.text = cells[0].trim();
          if (cells.length > 1) row.variantName.text = cells[1].trim();
          if (cells.length > 2) row.hsn.text = cells[2].trim();
          if (cells.length > 5) row.supplierLot.text = cells[5].trim();
          if (cells.length > 6) row.manufacturingDate.text = cells[6].trim();
          if (cells.length > 7) row.expiryDate.text = cells[7].trim();
          if (cells.length > 8) row.qty.text = cells[8].trim();
          if (cells.length > 9) row.unit.text = cells[9].trim();
          if (cells.length > 10) {
            row.rate.text = cells[10].trim().replaceAll(',', '').replaceFirst(RegExp(r'^₹\s*'), '');
          }
          if (cells.length > 11) {
            row.gst.text = cells[11].trim().replaceAll('%', '').trim();
          }
          if (cells.length > 13) {
            row.mrp.text = cells[13].trim().replaceAll(',', '').replaceFirst(RegExp(r'^₹\s*'), '');
          }
          if (cells.length > 14) {
            row.selling.text = cells[14].trim().replaceAll(',', '').replaceFirst(RegExp(r'^₹\s*'), '');
          }
          if (cells.length > 16) {
            final type = cells[16].trim().toUpperCase();
            if (type == 'OUTLET' || type == 'GODOWN') {
              row.locationType = type;
              final outletId = widget.controller.currentOutlet?.outletId;
              row.locationId = type == 'OUTLET' ? outletId : null;
              row.locationKey = row.locationId == null ? null : '$type:$outletId';
              row.rackId = null;
            }
          }
          if (cells.length > 17) {
            final locVal = cells[17].trim();
            final location = locations.where((candidate) {
              final normalized = locVal.toLowerCase().replaceFirst(RegExp(r'^(outlet|godown)\s*[•·-]\s*'), '');
              return candidate.name.toLowerCase() == normalized ||
                  '${candidate.type}:${candidate.id}'.toLowerCase() == locVal.toLowerCase();
            }).firstOrNull;
            if (location != null) {
              row.locationKey = '${location.type}:${location.id}';
              row.locationType = location.type;
              row.locationId = location.id;
              row.rackId = null;
            }
          }
          if (cells.length > 18 && row.locationId != null) {
            final rackVal = cells[18].trim();
            final rack = widget.controller.storageLocations
                .where(
                  (candidate) =>
                      candidate.type == StorageLocationType.rack &&
                      candidate.isActive &&
                      candidate.parentLocationId == row.locationId &&
                      ((candidate.parentLocationType ?? '').toUpperCase() == row.locationType),
                )
                .where(
                  (candidate) =>
                      candidate.name.toLowerCase() == rackVal.toLowerCase() ||
                      candidate.code.toLowerCase() == rackVal.toLowerCase(),
                )
                .firstOrNull;
            row.rackId = rack?.storageLocationId;
          }
        } else {
          // Standard editable columns mapping based on startColumn
          final columns = <int, TextEditingController Function(_PurchaseEntryRow)>{
            0: (r) => r.product,
            1: (r) => r.variantName,
            2: (r) => r.hsn,
            3: (r) => r.supplierLot,
            4: (r) => r.manufacturingDate,
            5: (r) => r.expiryDate,
            6: (r) => r.qty,
            7: (r) => r.unit,
            8: (r) => r.rate,
            9: (r) => r.gst,
            10: (r) => r.mrp,
            11: (r) => r.selling,
          };

          for (var c = 0; c < cells.length; c++) {
            final targetColumn = startColumn + c;
            final value = cells[c].trim();
            final setter = columns[targetColumn];
            if (setter != null) {
              final controller = setter(row);
              controller.text = targetColumn == 8 || targetColumn == 10 || targetColumn == 11
                  ? value.replaceAll(',', '').replaceFirst(RegExp(r'^₹\s*'), '')
                  : targetColumn == 9
                  ? value.replaceAll('%', '').trim()
                  : value;
            } else if (targetColumn == 12) {
              final type = value.toUpperCase();
              if (type == 'OUTLET' || type == 'GODOWN') {
                row.locationType = type;
                final outletId = widget.controller.currentOutlet?.outletId;
                row.locationId = type == 'OUTLET' ? outletId : null;
                row.locationKey = row.locationId == null ? null : '$type:$outletId';
                row.rackId = null;
              }
            } else if (targetColumn == 13) {
              final location = locations.where((candidate) {
                final normalized = value.toLowerCase().replaceFirst(RegExp(r'^(outlet|godown)\s*[•·-]\s*'), '');
                return candidate.name.toLowerCase() == normalized ||
                    '${candidate.type}:${candidate.id}'.toLowerCase() == value.toLowerCase();
              }).firstOrNull;
              if (location != null) {
                row.locationKey = '${location.type}:${location.id}';
                row.locationType = location.type;
                row.locationId = location.id;
                row.rackId = null;
              }
            } else if (targetColumn == 14 && row.locationId != null) {
              final rack = widget.controller.storageLocations
                  .where(
                    (candidate) =>
                        candidate.type == StorageLocationType.rack &&
                        candidate.isActive &&
                        candidate.parentLocationId == row.locationId &&
                        ((candidate.parentLocationType ?? '').toUpperCase() == row.locationType),
                  )
                  .where(
                    (candidate) =>
                        candidate.name.toLowerCase() == value.toLowerCase() ||
                        candidate.code.toLowerCase() == value.toLowerCase(),
                  )
                  .firstOrNull;
              row.rackId = rack?.storageLocationId;
            }
          }
        }

        final qty = _quantity(row.qty.text);
        if (qty != null) _defaultReceived(row, row.qty.text);
        final productText = row.product.text.trim().toLowerCase();
        final variantText = row.variantName.text.trim().toLowerCase();
        row.variant = variants.where((candidate) {
          final productMatches =
              (candidate.productName ?? candidate.name).trim().toLowerCase() == productText;
          final variantMatches = candidate.name.trim().toLowerCase() == variantText;
          return productMatches && (variantText.isEmpty || variantMatches);
        }).firstOrNull;
        if (row.variant != null && row.unit.text.isEmpty) {
          row.unit.text =
              row.variant!.commercialUnitName ??
              row.variant!.commercialUnitId ??
              row.variant!.baseUnitId;
        }
        row.editRevision++;
      }
      _activeGridRow = startRow;
      _activeGridColumn = startColumn;
      _dirty = true;
    });
    _message(
      'Pasted ${matrix.length} spreadsheet row(s). Review unmatched products and locations.',
    );
  }

  Future<void> _pickGridDate({
    required TextEditingController controller,
    required int rowIndex,
    required int gridColumn,
    required bool isExpiry,
    DateTime? mfgDate,
  }) async {
    _setActiveGridCell(rowIndex, gridColumn);

    final now = DateTime.now();
    final DateTime firstDate;
    final DateTime lastDate;

    if (isExpiry) {
      firstDate = mfgDate ?? DateTime(2000);
      lastDate = DateTime(2100, 12, 31);
    } else {
      firstDate = DateTime(1990);
      lastDate = now.add(const Duration(days: 365));
    }

    final parsed = DateTime.tryParse(controller.text.trim());
    DateTime initial =
        parsed ?? (isExpiry && mfgDate != null && mfgDate.isAfter(now) ? mfgDate : now);

    if (initial.isBefore(firstDate)) initial = firstDate;
    if (initial.isAfter(lastDate)) initial = lastDate;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: firstDate,
      lastDate: lastDate,
    );

    if (picked != null) {
      final formatted =
          '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      controller.text = formatted;
      _markDirty();
    }
  }

  Widget _dateInput(
    TextEditingController controller, {
    required int rowIndex,
    required int gridColumn,
    required String label,
    required bool isExpiry,
    DateTime? mfgDate,
    ValueChanged<String>? onChanged,
  }) =>
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              textAlign: TextAlign.start,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF0F172A),
              ),
              onTap: () => _setActiveGridCell(rowIndex, gridColumn),
              keyboardType: TextInputType.datetime,
              onChanged: onChanged,
              cursorColor: const Color(0xFF107C41),
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'YYYY-MM-DD',
                hintStyle: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              ),
            ),
          ),
          Tooltip(
            message: 'Choose $label',
            child: InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: () => _pickGridDate(
                controller: controller,
                rowIndex: rowIndex,
                gridColumn: gridColumn,
                isExpiry: isExpiry,
                mfgDate: mfgDate,
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Icon(
                  Icons.calendar_month_outlined,
                  size: 16,
                  color: Color(0xFF64748B),
                ),
              ),
            ),
          ),
        ],
      );

  Widget _input(
    TextEditingController c, {
    bool number = false,
    int? rowIndex,
    int? gridColumn,
    ValueChanged<String>? onChanged,
    TextAlign textAlign = TextAlign.start,
    String? hintText,
  }) => TextField(
    controller: c,
    textAlign: number ? TextAlign.right : textAlign,
    style: TextStyle(
      fontSize: 13,
      color: const Color(0xFF0F172A),
      fontFeatures: number ? const [FontFeature.tabularFigures()] : null,
    ),
    onTap: rowIndex == null || gridColumn == null
        ? null
        : () => _setActiveGridCell(rowIndex, gridColumn),
    keyboardType: number
        ? const TextInputType.numberWithOptions(decimal: true)
        : TextInputType.text,
    onChanged: onChanged,
    cursorColor: const Color(0xFF107C41),
    decoration: InputDecoration(
      isDense: true,
      hintText: hintText,
      hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      errorBorder: InputBorder.none,
      disabledBorder: InputBorder.none,
      filled: false,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
    ),
  );

  Widget _cell(
    Widget child,
    double width, {
    int? rowIndex,
    int? colIndex,
    Alignment alignment = Alignment.centerLeft,
    Color? backgroundColor,
  }) {
    final isFocused = rowIndex != null &&
        colIndex != null &&
        colIndex >= 0 &&
        _activeGridRow == rowIndex &&
        _activeGridColumn == colIndex;

    return Container(
      width: width,
      height: 42,
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: isFocused ? const Color(0xFFF0FDF4) : backgroundColor,
        border: isFocused
            ? Border.all(color: const Color(0xFF107C41), width: 2)
            : const Border(
                right: BorderSide(color: Color(0xFFE2E8F0)),
                bottom: BorderSide(color: Color(0xFFE2E8F0)),
              ),
      ),
      child: child,
    );
  }
  void _defaultReceived(_PurchaseEntryRow row, String value) {
    final qty = _quantity(value);
    if (qty == null) return;
    if (row.received.text.isEmpty || row.received.text == row.previousQty) {
      row.received.text = value;
    }
    if (row.rejected.text.isEmpty) {
      row.rejected.text = '0';
    }
    final received = _quantity(row.received.text) ?? qty;
    final rejected = _quantity(row.rejected.text) ?? 0;
    row.accepted.text = _formatQuantity(
      (received - rejected).clamp(0, received),
    );
    row.previousQty = value;
    row.previousReceived = value;
  }

  void _markDirty() {
    if (!mounted) return;
    setState(() {
      _dirty = true;
      if (_paymentStatus == 'PAID') _paidNow.text = _rupees(_liveGrandTotal());
    });
  }

  int _liveGrandTotal() {
    final subtotal = _rows.fold<int>(0, (sum, row) => sum + row.taxablePaise);
    final rawDiscount = _moneyToPaise(_discount.text) ?? 0;
    final discount = _discountType == 'PERCENTAGE'
        ? subtotal * rawDiscount ~/ 10000
        : rawDiscount;
    final charges = _charges.fold<int>(
      0,
      (sum, row) => sum + (_moneyToPaise(row.amount.text) ?? 0),
    );
    return (subtotal - discount).clamp(0, 1 << 62) +
        _taxAfterDiscount(discount) +
        charges +
        (_signedMoney(_roundOff.text) ?? 0);
  }

  Widget _chargesPanel() => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Purchase Discount & Charges',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              TextButton.icon(
                onPressed: () => setState(() {
                  _charges.add(_ChargeRow());
                  _dirty = true;
                }),
                icon: const Icon(Icons.add),
                label: const Text('Add Charge'),
              ),
            ],
          ),
          Row(
            children: [
              DropdownButton<String>(
                value: _discountType,
                items: const [
                  DropdownMenuItem(
                    value: 'FIXED_AMOUNT',
                    child: Text('Fixed amount'),
                  ),
                  DropdownMenuItem(
                    value: 'PERCENTAGE',
                    child: Text('Percentage'),
                  ),
                ],
                onChanged: (v) => setState(() {
                  _discountType = v ?? 'FIXED_AMOUNT';
                  _dirty = true;
                }),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 145,
                child: TextField(
                  controller: _discount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                    hintText: '0.00',
                  ),
                  onChanged: (_) => _markDirty(),
                ),
              ),
              const SizedBox(width: 6),
              Text(_discountType == 'PERCENTAGE' ? '%' : '₹', style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
          for (var i = 0; i < _charges.length; i++)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      key: ValueKey('charge_${i}_${_charges[i].type}'),
                      initialValue: _charges[i].type,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        isDense: true,
                        labelText: 'Charge',
                      ),
                      items:
                          const [
                                'Freight',
                                'Transport',
                                'Loading',
                                'Unloading',
                                'Insurance',
                                'Packing',
                                'Other',
                              ]
                              .map(
                                (x) => DropdownMenuItem(value: x, child: Text(x)),
                              )
                              .toList(),
                      onChanged: (v) => setState(() {
                        _charges[i].type = v ?? 'Other';
                        _dirty = true;
                      }),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 130,
                    child: TextField(
                      controller: _charges[i].amount,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                        labelText: 'Amount ₹',
                        hintText: '0.00',
                      ),
                      onChanged: (_) => _markDirty(),
                    ),
                  ),
                  IconButton(
                    onPressed: () => setState(() {
                      _charges[i].dispose();
                      _charges.removeAt(i);
                      _dirty = true;
                    }),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );

  Widget _summary(
    int lines,
    int subtotal,
    int discount,
    int cgst,
    int sgst,
    int igst,
    int charges,
    int grand,
  ) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Purchase Summary',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const Divider(),
          _sumLine('Items', '$lines'),
          _sumLine('Subtotal', '₹${_rupees(subtotal)}'),
          _sumLine('Discount', '− ₹${_rupees(discount)}'),
          _sumLine(
            'Taxable Amount',
            '₹${_rupees((subtotal - discount).clamp(0, 1 << 62))}',
          ),
          _sumLine('CGST', '₹${_rupees(cgst)}'),
          _sumLine('SGST', '₹${_rupees(sgst)}'),
          _sumLine('IGST', '₹${_rupees(igst)}'),
          _sumLine('Additional Charges', '₹${_rupees(charges)}'),
          Row(
            children: [
              const Expanded(child: Text('Round Off')),
              SizedBox(
                width: 100,
                child: TextField(
                  controller: _roundOff,
                  textAlign: TextAlign.end,
                  keyboardType: const TextInputType.numberWithOptions(
                    signed: true,
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                      borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                    ),
                    hintText: '0.00',
                  ),
                  onChanged: (_) => _markDirty(),
                ),
              ),
            ],
          ),
          const Divider(),
          _sumLine('Grand Total', '₹${_rupees(grand)}', bold: true),
          _sumLine(
            'Paid Now',
            '₹${_rupees(_moneyToPaise(_paidNow.text) ?? 0)}',
          ),
          _sumLine(
            'Balance Due',
            '₹${_rupees((grand - (_moneyToPaise(_paidNow.text) ?? 0)).clamp(0, 1 << 62))}',
            bold: true,
          ),
        ],
      ),
    ),
  );
  Widget _sumLine(String label, String value, {bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: bold ? const TextStyle(fontWeight: FontWeight.bold) : null,
          ),
        ),
        Text(
          value,
          style: bold ? const TextStyle(fontWeight: FontWeight.bold) : null,
        ),
      ],
    ),
  );

  Widget _paymentPanel(int grand) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            'Payment Information',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          SizedBox(
            width: 160,
            child: DropdownButtonFormField<String>(
              key: ValueKey('payment_status_$_paymentStatus'),
              initialValue: _paymentStatus,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Payment Status',
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(
                  value: 'UNPAID',
                  child: Text(
                    'Unpaid',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                DropdownMenuItem(
                  value: 'PARTIALLY_PAID',
                  child: Text(
                    'Partially Paid',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                DropdownMenuItem(
                  value: 'PAID',
                  child: Text(
                    'Paid',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              onChanged: (v) {
                setState(() {
                  _paymentStatus = v ?? 'UNPAID';
                  if (_paymentStatus == 'UNPAID') _paidNow.text = '0';
                  if (_paymentStatus == 'PAID') _paidNow.text = _rupees(grand);
                  _dirty = true;
                });
              },
            ),
          ),
          SizedBox(
            width: 130,
            child: TextField(
              controller: _paidNow,
              enabled: _paymentStatus != 'UNPAID',
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Paid Now ₹',
                isDense: true,
              ),
              onChanged: (_) => setState(() => _dirty = true),
            ),
          ),
          SizedBox(
            width: 155,
            child: DropdownButtonFormField<String>(
              key: ValueKey('payment_method_$_paymentMethod'),
              initialValue: _paymentMethod,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Payment Method',
                isDense: true,
              ),
              items:
                  const [
                        'CASH',
                        'UPI',
                        'BANK_TRANSFER',
                        'CHEQUE',
                        'CARD',
                        'OTHER',
                      ]
                      .map(
                        (m) => DropdownMenuItem(
                          value: m,
                          child: Text(
                            m.replaceAll('_', ' '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
              onChanged: (v) => setState(() {
                _paymentMethod = v ?? 'CASH';
                _dirty = true;
              }),
            ),
          ),
          SizedBox(
            width: 165,
            child: TextField(
              controller: _paymentReference,
              decoration: const InputDecoration(
                labelText: 'Reference No.',
                isDense: true,
              ),
              onChanged: (_) => _markDirty(),
            ),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: _dueDate ?? DateTime.now(),
                firstDate: DateTime(2000),
                lastDate: DateTime.now().add(const Duration(days: 3650)),
              );
              if (date != null) {
                setState(() {
                  _dueDate = date;
                  _dirty = true;
                });
              }
            },
            icon: const Icon(Icons.event, size: 16),
            label: Text(_dueDate == null ? 'Due Date' : _date(_dueDate!)),
          ),
          SizedBox(
            width: 180,
            child: TextField(
              controller: _paymentNotes,
              decoration: const InputDecoration(
                labelText: 'Payment Notes',
                isDense: true,
              ),
              onChanged: (_) => _markDirty(),
            ),
          ),
          Text(
            'Due ₹${_rupees((grand - (_moneyToPaise(_paidNow.text) ?? 0)).clamp(0, 1 << 62))}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    ),
  );

  int _taxAfterDiscount(int discount) {
    final active = _rows
        .where((row) => row.hasContent && row.taxablePaise > 0)
        .toList();
    final subtotal = active.fold<int>(0, (sum, row) => sum + row.taxablePaise);
    if (subtotal == 0) return 0;
    var allocated = 0;
    var tax = 0;
    for (var i = 0; i < active.length; i++) {
      final row = active[i];
      final share = i == active.length - 1
          ? discount - allocated
          : subtotal == 0
          ? 0
          : (discount * row.taxablePaise + subtotal ~/ 2) ~/ subtotal;
      allocated += share;
      final taxable = (row.taxablePaise - share).clamp(0, 1 << 62);
      tax +=
          (taxable * ((double.tryParse(row.gst.text) ?? 0) * 100).round() +
              5000) ~/
          10000;
    }
    return tax;
  }

  String? _businessStateCode() {
    final business = widget.controller.businesses
        .where((b) => b.businessId == widget.controller.appContext?.businessId)
        .firstOrNull;
    final gstin = business?.gstin;
    if (gstin != null && gstin.length >= 2) return gstin.substring(0, 2);
    return business?.gstState;
  }

  Future<void> _addSupplier() async {
    final created = await showSupplierFormFromPurchase(
      context,
      widget.controller,
    );
    if (!created || !mounted) return;
    setState(() {
      _suppliers = List.of(widget.controller.suppliers);
      _supplierId = _suppliers.lastOrNull?.supplierId;
      _dirty = true;
    });
  }

  Future<void> _saveDraft() async => _persistDraft(closeAfterSave: true);

  Future<bool> _persistDraft({required bool closeAfterSave}) async {
    for (final row in _rows) {
      for (final value in [row.manufacturingDate.text, row.expiryDate.text]) {
        if (value.trim().isNotEmpty &&
            DateTime.tryParse(value.trim()) == null) {
          _message('Enter manufacturing and expiry dates as YYYY-MM-DD.');
          return false;
        }
      }
      final manufactured = DateTime.tryParse(row.manufacturingDate.text.trim());
      final expires = DateTime.tryParse(row.expiryDate.text.trim());
      if (manufactured != null &&
          expires != null &&
          expires.isBefore(manufactured)) {
        _message('Expiry date cannot be earlier than manufacturing date.');
        return false;
      }
    }
    final validRows = _resolvedRows();
    if (widget.draftToEdit != null &&
        validRows.length < widget.draftToEdit!.items.length) {
      _message(
        'One or more saved variants are unavailable in this outlet. Restore them before saving the draft.',
      );
      return false;
    }
    if (validRows.isEmpty) {
      _message('Add at least one row and select a known Product/Variant.');
      return false;
    }
    if (_supplierId == null) {
      _message(
        'Add or select a Supplier before saving with the current purchase service.',
      );
      return false;
    }
    final placeCode = _supplierStateCode();
    if (placeCode == null) {
      _message(
        'Supplier state information is missing. Update the Supplier GSTIN or address before saving.',
      );
      return false;
    }
    if (_hasInvalidStorageDestination()) {
      _message(
        'Choose a valid Outlet or Godown, and ensure any selected rack belongs to that location.',
      );
      return false;
    }
    if (_hasUnsupportedReceivingQuantities()) {
      _message(
        'Current Purchase posting receives the full invoiced quantity. Partial acceptance and rejected goods are not yet supported by this posting service.',
      );
      return false;
    }
    final discount = _moneyToPaise(_discount.text) ?? 0;
    final actualDiscount = _discountType == 'PERCENTAGE'
        ? validRows.fold<int>(0, (s, i) => s + i.taxableAmount) *
              discount ~/
              10000
        : discount;
    setState(() => _saving = true);
    final draftToEdit = widget.draftToEdit;
    final saved = draftToEdit == null
        ? await widget.controller.createPurchaseDraft(
            supplierId: _supplierId!,
            supplierInvoiceNumber: _invoice.text.trim(),
            invoiceDate: _invoiceDate,
            purchaseDate: _purchaseDate,
            placeOfSupplyStateCode: placeCode,
            discountAmount: actualDiscount,
            chargesAmount: _charges.fold<int>(
              0,
              (s, c) => s + (_moneyToPaise(c.amount.text) ?? 0),
            ),
            roundOff: _signedMoney(_roundOff.text) ?? 0,
            items: validRows,
          )
        : await widget.controller.updatePurchaseDraft(
            bill: draftToEdit,
            supplierId: _supplierId!,
            supplierInvoiceNumber: _invoice.text.trim(),
            invoiceDate: _invoiceDate,
            purchaseDate: _purchaseDate,
            placeOfSupplyStateCode: placeCode,
            discountAmount: actualDiscount,
            chargesAmount: _charges.fold<int>(
              0,
              (s, c) => s + (_moneyToPaise(c.amount.text) ?? 0),
            ),
            roundOff: _signedMoney(_roundOff.text) ?? 0,
            items: validRows,
          );
    if (saved && mounted) {
      final savedBill = widget.controller.purchaseBills
          .where(
            (bill) => draftToEdit != null
                ? bill.purchaseBillId == draftToEdit.purchaseBillId
                : bill.supplierInvoiceNumber == _invoice.text.trim() &&
                      bill.supplierId == _supplierId,
          )
          .firstOrNull;
      if (savedBill != null) {
        final lineRows = _rows
            .where(
              (row) =>
                  row.variant != null &&
                  (_quantity(row.qty.text) ?? 0) > 0 &&
                  (_moneyToPaise(row.rate.text) ?? -1) >= 0,
            )
            .toList();
        for (
          var i = 0;
          i < lineRows.length && i < savedBill.items.length;
          i++
        ) {
          lineRows[i].goodsReceiptItemId =
              savedBill.items[i].goodsReceiptItemId;
          lineRows[i].internalBatchNo =
              savedBill.items[i].internalBatchNo ?? '';
        }
      }
    }
    if (mounted) setState(() => _saving = false);
    if (saved && mounted && closeAfterSave) {
      _dirty = false;
      widget.onClose();
    }
    return saved;
  }

  Future<void> _reviewAndPost() async {
    if (_supplierId == null || _invoice.text.trim().isEmpty) {
      _message(
        'Select a Supplier and enter the Supplier Invoice Number before posting.',
      );
      return;
    }
    final rows = _resolvedRows();
    if (rows.isEmpty) {
      _message('At least one valid existing Product/Variant is required.');
      return;
    }
    final hasQuantityIssue = _rows.where((r) => r.hasContent).any((r) {
      final received = _quantity(r.received.text) ?? 0;
      final accepted = _quantity(r.accepted.text) ?? 0;
      final rejected = _quantity(r.rejected.text) ?? 0;
      return accepted + rejected > received;
    });
    if (hasQuantityIssue) {
      _message(
        'Accepted plus Rejected quantity cannot exceed Received quantity.',
      );
      return;
    }
    if (_hasInvalidStorageDestination()) {
      _message(
        'Choose a valid Outlet or Godown, and ensure any selected rack belongs to that location.',
      );
      return;
    }
    if (_hasUnsupportedReceivingQuantities()) {
      _message(
        'Partial acceptance and rejected goods are not supported by the current posting service.',
      );
      return;
    }
    final subtotal = rows.fold<int>(0, (sum, item) => sum + item.taxableAmount);
    final discountRaw = _moneyToPaise(_discount.text) ?? 0;
    final discount = _discountType == 'PERCENTAGE'
        ? subtotal * discountRaw ~/ 10000
        : discountRaw;
    final total =
        subtotal -
        discount +
        _taxAfterDiscount(discount) +
        _charges.fold<int>(
          0,
          (sum, row) => sum + (_moneyToPaise(row.amount.text) ?? 0),
        ) +
        (_signedMoney(_roundOff.text) ?? 0);
    final paid = _moneyToPaise(_paidNow.text) ?? 0;
    if (_paymentStatus == 'PARTIALLY_PAID' && (paid <= 0 || paid >= total)) {
      _message(
        'For a partially paid Purchase, Paid Now must be above zero and below the Grand Total.',
      );
      return;
    }
    if (_paymentStatus == 'PAID' && paid != total) {
      _message(
        'Paid Now must equal the Grand Total for a fully paid Purchase.',
      );
      return;
    }
    setState(() {
      _preview = false;
      _review = true;
    });
  }

  bool _hasInvalidStorageDestination() {
    final controller = widget.controller;
    return _rows.any((row) {
      if (!row.hasContent) return false;
      final locationExists = row.locationType == 'OUTLET'
          ? controller.outlets.any(
              (outlet) => outlet.isActive && outlet.outletId == row.locationId,
            )
          : row.locationType == 'GODOWN' &&
                controller.storageLocations.any(
                  (location) =>
                      location.type == StorageLocationType.godown &&
                      location.isActive &&
                      location.storageLocationId == row.locationId,
                );
      if (!locationExists || row.locationId == null) return true;
      if (row.rackId == null) return false;
      return !controller.storageLocations.any(
        (rack) =>
            rack.type == StorageLocationType.rack &&
            rack.isActive &&
            rack.storageLocationId == row.rackId &&
            rack.parentLocationId == row.locationId &&
            (rack.parentLocationType ?? '').toUpperCase() == row.locationType,
      );
    });
  }

  bool _hasUnsupportedReceivingQuantities() => _rows.any((row) {
    if (!row.hasContent) return false;
    final qty = _quantity(row.qty.text) ?? 0;
    final received = _quantity(row.received.text) ?? qty;
    final accepted = _quantity(row.accepted.text) ?? received;
    final rejected = _quantity(row.rejected.text) ?? 0;
    return received != qty || accepted != qty || rejected != 0;
  });

  Widget _reviewPanel() => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Text('Review Purchase', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 12),
      Card(
        child: Column(
          children: [
            ListTile(
              title: const Text('Supplier'),
              subtitle: Text(
                _suppliers
                        .where((s) => s.supplierId == _supplierId)
                        .firstOrNull
                        ?.name ??
                    'Missing',
              ),
            ),
            ListTile(
              title: const Text('Invoice'),
              subtitle: Text(_invoice.text),
            ),
            ListTile(
              title: const Text('Lines'),
              subtitle: Text('${_resolvedRows().length} matched Product lines'),
            ),
            const ListTile(
              title: Text('Inventory destination'),
              subtitle: Text(
                'Physical destination is saved per purchase line.',
              ),
            ),
            for (final row in _rows.where((row) => row.hasContent))
              ListTile(
                title: Text(
                  '${row.product.text} ${row.variantName.text}'.trim(),
                ),
                subtitle: Text(
                  'Internal Batch No: ${row.internalBatchNo.isEmpty ? 'Generated on save' : row.internalBatchNo} · '
                  'Store At: ${row.locationType ?? '—'} · '
                  'Location: ${row.locationId ?? '—'} · '
                  'Rack: ${row.rackId ?? 'No Rack'}',
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        children: [
          OutlinedButton(
            onPressed: () => setState(() => _review = false),
            child: const Text('Back to Edit'),
          ),
          FilledButton(
            onPressed: _saving ? null : _postExistingWorkflow,
            child: const Text('Confirm & Post'),
          ),
        ],
      ),
    ],
  );

  Widget _previewPanel() {
    final rows = _rows.where((row) => row.hasContent).toList();
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Purchase Preview',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              ListTile(
                title: const Text('Supplier'),
                subtitle: Text(
                  _selectedSupplierCaption().isEmpty
                      ? 'Not selected'
                      : _selectedSupplierCaption(),
                ),
              ),
              ListTile(
                title: const Text('Supplier Invoice Number'),
                subtitle: Text(_invoice.text.isEmpty ? '—' : _invoice.text),
              ),
              for (var index = 0; index < rows.length; index++)
                ListTile(
                  title: Text(
                    '${index + 1}. ${rows[index].product.text} ${rows[index].variantName.text}'
                        .trim(),
                  ),
                  subtitle: Text(
                    'Barcode: ${_previewBarcode(rows[index])} · '
                    'Internal Batch No: ${rows[index].internalBatchNo.isEmpty ? 'Generated on save' : rows[index].internalBatchNo} · '
                    'Supplier Lot: ${rows[index].supplierLot.text.isEmpty ? '—' : rows[index].supplierLot.text} · '
                    'Store At: ${rows[index].locationType ?? '—'} · '
                    'Location: ${rows[index].locationId ?? '—'} · '
                    'Rack: ${rows[index].rackId ?? 'No Rack'}',
                  ),
                ),
            ],
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => setState(() => _preview = false),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Back to Edit'),
          ),
        ),
      ],
    );
  }

  Future<void> _postExistingWorkflow() async {
    final saved = await _persistDraft(closeAfterSave: false);
    if (!saved || !mounted) return;
    final bill = widget.controller.purchaseBills
        .where((b) => b.supplierInvoiceNumber == _invoice.text.trim())
        .firstOrNull;
    if (bill == null) {
      _message(
        'Draft was not saved; check the Supplier, invoice and Purchase rows.',
      );
      return;
    }
    final ok = await widget.controller.approvePurchase(bill.purchaseBillId);
    if (ok && mounted && (_moneyToPaise(_paidNow.text) ?? 0) > 0) {
      final postedBill = widget.controller.purchaseBills
          .where((candidate) => candidate.purchaseBillId == bill.purchaseBillId)
          .firstOrNull;
      if (postedBill != null) {
        final paid = await widget.controller.recordSupplierPayment(
          bill: postedBill,
          amount: _moneyToPaise(_paidNow.text)!,
          paymentMode: _paymentMethod,
          reference: _paymentReference.text.trim(),
        );
        if (!paid && mounted) {
          _message(
            'Purchase posted, but immediate payment was not recorded. Record it from the Purchase list.',
          );
        }
      }
    }
    if (ok && mounted) {
      _dirty = false;
      widget.onClose();
    }
  }

  List<PurchaseBillItemModel> _resolvedRows() => [
    for (final row in _rows)
      if (row.variant != null &&
          (_quantity(row.qty.text) ?? 0) > 0 &&
          (_moneyToPaise(row.rate.text) ?? -1) >= 0)
        PurchaseBillItemModel(
          goodsReceiptItemId:
              row.goodsReceiptItemId ??
              'LINE_${DateTime.now().microsecondsSinceEpoch}_${_rows.indexOf(row)}',
          variantId: row.variant!.variantId,
          productName: row.product.text.trim().isEmpty
              ? row.variant!.name
              : row.product.text.trim(),
          unitId: row.variant!.baseUnitId,
          commercialUnitId: row.variant!.commercialUnitId,
          conversionFactor: (row.variant!.baseQuantityPerCommercialUnit * 1000)
              .round(),
          quantity: _quantity(row.qty.text)!,
          rate: _moneyToPaise(row.rate.text)!,
          gstRateBps: ((double.tryParse(row.gst.text) ?? 0) * 100).round(),
          taxableAmount: row.taxablePaise,
          taxAmount: row.taxPaise,
          hsnCode: row.hsn.text.trim(),
          mrp: _moneyToPaise(row.mrp.text),
          sellingPrice: _moneyToPaise(row.selling.text),
          productId: row.variant!.productId,
          variantName: row.variant!.name,
          barcodeSnapshot: row.variant!.barcode,
          internalBatchNo: row.internalBatchNo.isEmpty
              ? null
              : row.internalBatchNo,
          supplierLotNo: row.supplierLot.text.trim().isEmpty
              ? null
              : row.supplierLot.text.trim(),
          manufacturingDate: DateTime.tryParse(
            row.manufacturingDate.text.trim(),
          ),
          expiryDate: DateTime.tryParse(row.expiryDate.text.trim()),
          storageType: row.locationType,
          storageLocationId: row.locationId,
          rackId: row.rackId,
        ),
  ];

  String? _supplierStateCode() {
    final s = _suppliers.where((s) => s.supplierId == _supplierId).firstOrNull;
    final supplierCode =
        s?.stateCode ??
        (s?.gstin != null && s!.gstin!.length >= 2
            ? s.gstin!.substring(0, 2)
            : null);
    if (supplierCode != null && supplierCode.isNotEmpty) return supplierCode;
    final business = widget.controller.businesses
        .where((b) => b.businessId == widget.controller.appContext?.businessId)
        .firstOrNull;
    final gstin = business?.gstin;
    return gstin != null && gstin.length >= 2 ? gstin.substring(0, 2) : null;
  }

  Future<void> _confirmLeave() async {
    if (!_dirty) {
      widget.onClose();
      return;
    }
    final leave = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Discard unsaved Purchase?'),
        content: const Text(
          'Your current spreadsheet edits have not been saved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Stay'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (leave == true && mounted) {
      _dirty = false;
      widget.onClose();
    }
  }

  void _importUnavailable() => _message(
    'Bill import review/storage is not connected to the current Firestore REST workflow yet.',
  );
  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

class _PurchaseEntryRow {
  final product = TextEditingController(),
      variantName = TextEditingController(),
      hsn = TextEditingController(),
      qty = TextEditingController(),
      unit = TextEditingController(),
      rate = TextEditingController(),
      gst = TextEditingController(),
      mrp = TextEditingController(),
      selling = TextEditingController(),
      received = TextEditingController(),
      accepted = TextEditingController(),
      rejected = TextEditingController(),
      supplierLot = TextEditingController(),
      manufacturingDate = TextEditingController(),
      expiryDate = TextEditingController();
  ProductVariantModel? variant;
  String? goodsReceiptItemId;
  String? initialVariantId;
  String internalBatchNo = '';
  String? locationKey, locationType, locationId, rackId;
  String previousQty = '', previousReceived = '';
  int editRevision = 0;
  bool get hasContent =>
      product.text.isNotEmpty ||
      variantName.text.isNotEmpty ||
      qty.text.isNotEmpty;
  int get taxablePaise =>
      ((_quantity(qty.text) ?? 0) * (_moneyToPaise(rate.text) ?? 0) ~/ 1000);
  int get taxPaise =>
      taxablePaise * ((double.tryParse(gst.text) ?? 0) * 100).round() ~/ 10000;
  int get totalPaise => taxablePaise + taxPaise;
  void dispose() {
    for (final c in [
      product,
      variantName,
      hsn,
      qty,
      unit,
      rate,
      gst,
      mrp,
      selling,
      received,
      accepted,
      rejected,
      supplierLot,
      manufacturingDate,
      expiryDate,
    ]) {
      c.dispose();
    }
  }
}

class _ChargeRow {
  String type = 'Freight';
  final amount = TextEditingController();
  void dispose() => amount.dispose();
}

class _StockLocation {
  const _StockLocation(this.type, this.id, this.name);
  final String type, id, name;
}

int? _quantity(String raw) {
  final value = raw.trim();
  if (!RegExp(r'^\d+(\.\d{1,3})?$').hasMatch(value)) return null;
  final p = value.split('.');
  return int.parse(p[0]) * 1000 +
      int.parse((p.length > 1 ? p[1] : '').padRight(3, '0'));
}

String _formatQuantity(int milli) {
  final whole = milli ~/ 1000;
  final fraction = (milli % 1000)
      .toString()
      .padLeft(3, '0')
      .replaceFirst(RegExp(r'0+$'), '');
  return fraction.isEmpty ? '$whole' : '$whole.$fraction';
}

int? _moneyToPaise(String raw) {
  final value = raw.trim().replaceAll(',', '');
  if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(value)) return null;
  final p = value.split('.');
  return int.parse(p[0]) * 100 +
      int.parse((p.length > 1 ? p[1] : '').padRight(2, '0'));
}

int? _signedMoney(String raw) {
  final negative = raw.trim().startsWith('-');
  final value = _moneyToPaise(negative ? raw.trim().substring(1) : raw);
  return value == null
      ? null
      : negative
      ? -value
      : value;
}

String _rupees(int paise) => (paise / 100).toStringAsFixed(2);
String _date(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
String _stateName(String code) =>
    const {
      '01': 'Jammu and Kashmir',
      '02': 'Himachal Pradesh',
      '03': 'Punjab',
      '04': 'Chandigarh',
      '05': 'Uttarakhand',
      '06': 'Haryana',
      '07': 'Delhi',
      '08': 'Rajasthan',
      '09': 'Uttar Pradesh',
      '10': 'Bihar',
      '11': 'Sikkim',
      '12': 'Arunachal Pradesh',
      '13': 'Nagaland',
      '14': 'Manipur',
      '15': 'Mizoram',
      '16': 'Tripura',
      '17': 'Meghalaya',
      '18': 'Assam',
      '19': 'West Bengal',
      '20': 'Jharkhand',
      '21': 'Odisha',
      '22': 'Chhattisgarh',
      '23': 'Madhya Pradesh',
      '24': 'Gujarat',
      '27': 'Maharashtra',
      '29': 'Karnataka',
      '32': 'Kerala',
      '33': 'Tamil Nadu',
      '36': 'Telangana',
    }[code] ??
    'State';
