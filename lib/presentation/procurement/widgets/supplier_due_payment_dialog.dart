import 'package:flutter/material.dart';

import '../../../data/models/purchase_bill_model.dart';
import '../../app_controller.dart';
import 'supplier_ledger_localizations.dart';

/// Modal dialog for recording a FIFO multi-bill supplier due settlement.
/// Shows live preview of how the entered amount will be allocated across outstanding bills.
class SupplierDuePaymentDialog extends StatefulWidget {
  final String supplierId;
  final String supplierName;
  final int currentPayablePaise;
  final AppController controller;
  final VoidCallback? onSuccess;

  const SupplierDuePaymentDialog({
    super.key,
    required this.supplierId,
    required this.supplierName,
    required this.currentPayablePaise,
    required this.controller,
    this.onSuccess,
  });

  @override
  State<SupplierDuePaymentDialog> createState() => _SupplierDuePaymentDialogState();
}

class _SupplierDuePaymentDialogState extends State<SupplierDuePaymentDialog> {
  final _amountController = TextEditingController();
  final _refController = TextEditingController();
  String _paymentMode = 'CASH';
  DateTime _paymentDate = DateTime.now();
  bool _loadingBills = true;
  bool _submitting = false;
  String? _errorMessage;
  List<PurchaseBillModel> _outstandingBills = [];

  @override
  void initState() {
    super.initState();
    final defaultAmount = widget.currentPayablePaise > 0
        ? (widget.currentPayablePaise / 100).toStringAsFixed(2)
        : '';
    _amountController.text = defaultAmount;
    _amountController.addListener(() => setState(() {}));
    _loadBills();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _refController.dispose();
    super.dispose();
  }

  Future<void> _loadBills() async {
    setState(() {
      _loadingBills = true;
      _errorMessage = null;
    });
    try {
      final bills = await widget.controller.getSupplierOutstandingBills(widget.supplierId);
      if (mounted) {
        setState(() {
          _outstandingBills = bills;
          _loadingBills = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load outstanding bills: $e';
          _loadingBills = false;
        });
      }
    }
  }

  int get _enteredAmountPaise {
    final text = _amountController.text.trim();
    if (text.isEmpty) return 0;
    final cleaned = text.replaceAll('₹', '').replaceAll(',', '').trim();
    final val = double.tryParse(cleaned);
    if (val == null || val <= 0) return 0;
    return (val * 100).round();
  }

  Future<void> _submit() async {
    final s = SupplierLedgerStrings.of(context, widget.controller);
    final amountPaise = _enteredAmountPaise;
    if (amountPaise <= 0) {
      setState(() => _errorMessage = s.enterValidAmount);
      return;
    }

    setState(() {
      _submitting = true;
      _errorMessage = null;
    });

    try {
      final receipt = await widget.controller.settleSupplierDues(
        supplierId: widget.supplierId,
        amountPaise: amountPaise,
        paymentMode: _paymentMode,
        referenceNo: _refController.text.trim(),
        paymentDate: _paymentDate,
      );

      if (!mounted) return;

      if (receipt != null) {
        widget.onSuccess?.call();
        Navigator.of(context).pop(receipt);
      } else {
        setState(() {
          _submitting = false;
          _errorMessage = widget.controller.error.isNotEmpty
              ? widget.controller.error
              : s.enterValidAmount;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = SupplierLedgerStrings.of(context, widget.controller);
    final enteredPaise = _enteredAmountPaise;

    // Calculate real-time FIFO allocation preview
    var remToAlloc = enteredPaise;
    final previewList = <Map<String, dynamic>>[];
    for (final bill in _outstandingBills) {
      final effDue = bill.outstandingAmount > 0
          ? bill.outstandingAmount
          : (bill.grandTotal - bill.paidAmount);
      if (effDue <= 0) continue;

      final alloc = remToAlloc > effDue ? effDue : (remToAlloc > 0 ? remToAlloc : 0);
      remToAlloc = (remToAlloc - alloc).clamp(0, double.infinity).toInt();
      final newDue = effDue - alloc;
      previewList.add({
        'bill': bill,
        'effectiveDue': effDue,
        'allocated': alloc,
        'newDue': newDue,
        'isFullyPaid': newDue == 0,
        'isTouched': alloc > 0,
      });
    }

    final totalPayablePaise = widget.currentPayablePaise > 0
        ? widget.currentPayablePaise
        : _outstandingBills.fold<int>(
            0,
            (sum, b) =>
                sum +
                (b.outstandingAmount > 0
                    ? b.outstandingAmount
                    : (b.grandTotal - b.paidAmount)),
          );
    final remainingNetDuePaise = (totalPayablePaise - enteredPaise).clamp(0, double.infinity).toInt();
    final advancePaise = enteredPaise > totalPayablePaise ? (enteredPaise - totalPayablePaise) : 0;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540, maxHeight: 720),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Dialog Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.payment_rounded, color: Colors.blue.shade700, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.paySupplierDueTitle,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          widget.supplierName,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: s.cancel,
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Total Due Card
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        '${s.totalPayable}:',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.red.shade900,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '₹${(totalPayablePaise / 100).toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.red.shade900,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(color: Colors.red.shade900, fontSize: 12),
                  ),
                ),
                const SizedBox(height: 10),
              ],

              // Amount Input
              TextField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: '${s.paymentAmount} *',
                  hintText: 'e.g. 6000',
                  prefixText: '₹ ',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),

              // Mode and Date in Row
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _paymentMode,
                      decoration: InputDecoration(
                        labelText: s.paymentMode,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        isDense: true,
                      ),
                      items: const [
                        'CASH',
                        'UPI',
                        'BANK_TRANSFER',
                        'CHEQUE',
                        'CARD',
                      ].map((m) {
                        return DropdownMenuItem(
                          value: m,
                          child: Text(s.localizedPaymentMode(m)),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _paymentMode = val);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _paymentDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now().add(const Duration(days: 30)),
                        );
                        if (picked != null) {
                          setState(() => _paymentDate = picked);
                        }
                      },
                      icon: const Icon(Icons.calendar_today_rounded, size: 16),
                      label: Text(
                        '${_paymentDate.day}/${_paymentDate.month}/${_paymentDate.year}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Reference / UTR
              TextField(
                controller: _refController,
                decoration: InputDecoration(
                  labelText: s.referenceOptional,
                  hintText: 'e.g. UPI Ref / Cheque #',
                  prefixIcon: const Icon(Icons.tag_rounded),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 14),

              // Live Real-Time FIFO Allocation Preview
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.auto_mode_rounded, size: 16, color: Colors.blueGrey.shade800),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${s.fifoPreviewTitle}:',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.blueGrey.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_loadingBills)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(8),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    else if (previewList.isEmpty)
                      Text(
                        s.noOutstandingBills,
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      )
                    else ...[
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: previewList.length,
                        separatorBuilder: (_, _) => const Divider(height: 8),
                        itemBuilder: (context, idx) {
                          final item = previewList[idx];
                          final bill = item['bill'] as PurchaseBillModel;
                          final effDue = (item['effectiveDue'] as int) / 100.0;
                          final alloc = (item['allocated'] as int) / 100.0;
                          final newDue = (item['newDue'] as int) / 100.0;
                          final isFullyPaid = item['isFullyPaid'] as bool;
                          final isTouched = item['isTouched'] as bool;

                          return Row(
                            children: [
                              Expanded(
                                flex: 4,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '#${bill.supplierInvoiceNumber.isNotEmpty ? bill.supplierInvoiceNumber : (bill.purchaseNumber ?? bill.purchaseBillId)}',
                                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                                    ),
                                    Text(
                                      '${s.remainingLabel}: ₹${effDue.toStringAsFixed(2)}',
                                      style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                flex: 3,
                                child: Text(
                                  isTouched ? '${s.paidLabel}: ₹${alloc.toStringAsFixed(2)}' : s.unchanged,
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: isTouched ? Colors.green.shade700 : Colors.grey.shade500,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: !isTouched
                                      ? Colors.grey.shade100
                                      : isFullyPaid
                                          ? Colors.green.shade50
                                          : Colors.orange.shade50,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  !isTouched
                                      ? '${s.remainingLabel} ₹${newDue.toStringAsFixed(0)}'
                                      : isFullyPaid
                                          ? (s.isBn ? 'পরিশোধিত' : s.isHi ? 'चुकाया गया' : 'PAID')
                                          : '${s.remainingLabel} ₹${newDue.toStringAsFixed(0)}',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: !isTouched
                                        ? Colors.grey.shade700
                                        : isFullyPaid
                                            ? Colors.green.shade800
                                            : Colors.orange.shade800,
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      const Divider(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            s.remainingDueAfterPayment,
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
                          ),
                          Text(
                            '₹${(remainingNetDuePaise / 100).toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: remainingNetDuePaise > 0
                                  ? Colors.red.shade700
                                  : Colors.green.shade700,
                            ),
                          ),
                        ],
                      ),
                      if (advancePaise > 0)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              s.advanceCredit,
                              style: TextStyle(fontSize: 12, color: Colors.indigo.shade800),
                            ),
                            Text(
                              '₹${(advancePaise / 100).toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.indigo.shade800,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Action Buttons
              Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton(
                    onPressed: _submitting ? null : () => Navigator.of(context).pop(),
                    child: Text(s.cancel),
                  ),
                  FilledButton.icon(
                    onPressed: _submitting ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                    icon: _submitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.check_rounded, size: 18),
                    label: Text(_submitting ? s.saving : s.confirmPayment),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
