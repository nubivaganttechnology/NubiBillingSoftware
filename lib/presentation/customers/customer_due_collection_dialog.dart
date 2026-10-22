import 'package:flutter/material.dart';

import '../../core/errors/app_exception.dart';
import '../../data/models/customer_model.dart';
import '../../data/models/customer_payment_model.dart';
import '../../l10n/app_localizations.dart';
import '../app_controller.dart';

class CustomerDueCollectionDialog extends StatefulWidget {
  const CustomerDueCollectionDialog({
    super.key,
    required this.controller,
    required this.customer,
    required this.onPaymentCompleted,
  });

  final AppController controller;
  final CustomerModel customer;
  final VoidCallback onPaymentCompleted;

  @override
  State<CustomerDueCollectionDialog> createState() =>
      _CustomerDueCollectionDialogState();
}

class _CustomerDueCollectionDialogState
    extends State<CustomerDueCollectionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();

  bool _loading = true;
  bool _submitting = false;
  String? _error;
  List<Map<String, dynamic>> _invoices = const [];

  String _paymentMode = 'CASH';
  bool _isManualAllocation = false;
  final Set<String> _selectedInvoiceIds = {};
  final Map<String, TextEditingController> _manualAllocControllers = {};
  bool _allowAdvance = false;

  @override
  void initState() {
    super.initState();
    final initialRupees = widget.customer.duePaise / 100.0;
    _amountController.text = initialRupees > 0
        ? (initialRupees % 1 == 0
            ? initialRupees.toInt().toString()
            : initialRupees.toStringAsFixed(2))
        : '';
    _loadOutstandingInvoices();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    for (final c in _manualAllocControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadOutstandingInvoices() async {
    final appContext = widget.controller.appContext;
    final token = widget.controller.idToken;
    final repo = widget.controller.customerRepository;
    if (appContext?.businessId == null || token == null || repo == null) {
      setState(() {
        _loading = false;
        _error = 'Session unavailable. Please sign in again.';
      });
      return;
    }

    try {
      final invoices = await repo.getOutstandingInvoices(
        tenantId: appContext!.ownerUid,
        businessId: appContext.businessId!,
        customerId: widget.customer.customerId,
        token: token,
        employeePermissions: appContext.permissions,
        employeeOutletId: appContext.outletId,
        isOwner: widget.controller.user?.accountType == 'owner' ||
            widget.controller.user?.uid == appContext.ownerUid,
      );
      if (mounted) {
        setState(() {
          _invoices = invoices;
          _loading = false;
          for (final inv in invoices) {
            final invId = inv['invoiceId']?.toString() ?? '';
            final duePaise = (inv['dueAmount'] as num?)?.toInt() ?? 0;
            _manualAllocControllers[invId] = TextEditingController(
              text: (duePaise / 100.0).toStringAsFixed(2),
            );
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$e';
        });
      }
    }
  }

  int get _enteredAmountPaise {
    final parsed = double.tryParse(_amountController.text.trim());
    return parsed != null ? (parsed * 100).round() : 0;
  }

  int get _totalOutstandingPaise => _invoices.fold<int>(
        0,
        (sum, inv) => sum + ((inv['dueAmount'] as num?)?.toInt() ?? 0),
      );

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final amountPaise = _enteredAmountPaise;
    if (amountPaise <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid payment amount.')),
      );
      return;
    }

    final appContext = widget.controller.appContext;
    final token = widget.controller.idToken;
    final repo = widget.controller.customerRepository;
    final actorUid = widget.controller.user?.uid ?? 'SYSTEM';

    if (appContext?.businessId == null || token == null || repo == null) {
      return;
    }

    List<PaymentAllocationRequest>? manualAllocations;
    if (_isManualAllocation) {
      manualAllocations = [];
      var totalAlloc = 0;
      for (final invId in _selectedInvoiceIds) {
        final inv = _invoices.firstWhere(
          (item) => item['invoiceId'] == invId,
          orElse: () => const {},
        );
        final outletId = inv['outletId']?.toString() ?? '';
        final allocRupees =
            double.tryParse(_manualAllocControllers[invId]?.text.trim() ?? '');
        final allocPaise = allocRupees != null ? (allocRupees * 100).round() : 0;
        if (allocPaise <= 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Allocation for invoice ${inv['invoiceNumber'] ?? invId} must be positive.',
              ),
            ),
          );
          return;
        }
        totalAlloc += allocPaise;
        manualAllocations.add(
          PaymentAllocationRequest(
            invoiceId: invId,
            originalOutletId: outletId,
            allocatedPaise: allocPaise,
          ),
        );
      }
      if (totalAlloc > amountPaise) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Sum of allocations (₹${_money(totalAlloc)}) cannot exceed payment amount (₹${_money(amountPaise)}).',
            ),
          ),
        );
        return;
      }
    }

    setState(() {
      _submitting = true;
    });

    try {
      final paymentRecord = await repo.collectPayment(
        tenantId: appContext!.ownerUid,
        businessId: appContext.businessId!,
        customerId: widget.customer.customerId,
        collectedAtOutletId: appContext.outletId ?? '',
        amountPaise: amountPaise,
        paymentMethod: _paymentMode,
        actorUid: actorUid,
        token: token,
        employeePermissions: appContext.permissions,
        manualAllocations: manualAllocations,
        allowAdvance: _allowAdvance,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        isOwner: widget.controller.user?.accountType == 'owner' ||
            widget.controller.user?.uid == appContext.ownerUid,
      );

      if (mounted) {
        Navigator.pop(context);
        widget.onPaymentCompleted();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF059669),
            content: Text(
              'Payment of ₹${_money(paymentRecord.amountPaise)} posted successfully. ${paymentRecord.allocations.length} invoice(s) settled.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade700,
            content: Text(e is AppException ? e.message : '$e'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final amountPaise = _enteredAmountPaise;
    final totalOutstanding = _totalOutstandingPaise;
    final excessPaise = amountPaise > totalOutstanding
        ? amountPaise - totalOutstanding
        : 0;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 780),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _loading
              ? const SizedBox(
                  height: 200,
                  child: Center(child: CircularProgressIndicator()),
                )
              : _error != null
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 48, color: Colors.red),
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                  ],
                )
              : Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF059669).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.payments_rounded,
                              color: Color(0xFF059669),
                              size: 26,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Collect Due Payment',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  '${widget.customer.name} (${widget.customer.phone})',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Balance Overview Card
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Consolidated Due',
                                    style: theme.textTheme.labelSmall
                                        ?.copyWith(color: Colors.grey.shade600),
                                  ),
                                  Text(
                                    '₹${_money(widget.customer.duePaise)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: Color(0xFFB91C1C),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (widget.customer.advancePaise > 0)
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Current Advance',
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(color: Colors.grey.shade600),
                                    ),
                                    Text(
                                      '₹${_money(widget.customer.advancePaise)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                        color: Color(0xFF047857),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Collecting Outlet',
                                    style: theme.textTheme.labelSmall
                                        ?.copyWith(color: Colors.grey.shade600),
                                  ),
                                  Text(
                                    widget.controller.appContext?.outletId ?? 'Current',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Scrollable form fields
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: TextFormField(
                                      controller: _amountController,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                      decoration: InputDecoration(
                                        labelText: 'Payment Amount (₹) *',
                                        prefixText: '₹ ',
                                        filled: true,
                                        fillColor: theme
                                            .colorScheme.surfaceContainerHighest
                                            .withValues(alpha: 0.3),
                                      ),
                                      onChanged: (_) => setState(() {}),
                                      validator: (value) {
                                        final numVal = double.tryParse(value ?? '');
                                        if (numVal == null || numVal <= 0) {
                                          return 'Enter a positive amount.';
                                        }
                                        return null;
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    flex: 2,
                                    child: DropdownButtonFormField<String>(
                                      initialValue: _paymentMode,
                                      decoration: InputDecoration(
                                        labelText: 'Payment Mode',
                                        filled: true,
                                        fillColor: theme
                                            .colorScheme.surfaceContainerHighest
                                            .withValues(alpha: 0.3),
                                      ),
                                      items: const [
                                        DropdownMenuItem(
                                          value: 'CASH',
                                          child: Text('Cash'),
                                        ),
                                        DropdownMenuItem(
                                          value: 'UPI',
                                          child: Text('UPI'),
                                        ),
                                        DropdownMenuItem(
                                          value: 'CARD',
                                          child: Text('Card'),
                                        ),
                                        DropdownMenuItem(
                                          value: 'BANK_TRANSFER',
                                          child: Text('Bank Transfer'),
                                        ),
                                      ],
                                      onChanged: (val) {
                                        if (val != null) {
                                          setState(() => _paymentMode = val);
                                        }
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),

                              // Allocation Strategy Switch
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text(
                                  'Manual Invoice Allocation',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                                subtitle: Text(
                                  _isManualAllocation
                                      ? 'Choose specific invoices and amounts'
                                      : 'FIFO Default: Settles oldest eligible invoices first across outlets',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                                value: _isManualAllocation,
                                onChanged: (val) {
                                  setState(() {
                                    _isManualAllocation = val;
                                    if (val && _selectedInvoiceIds.isEmpty) {
                                      _selectedInvoiceIds.addAll(
                                        _invoices.map(
                                          (i) => i['invoiceId'].toString(),
                                        ),
                                      );
                                    }
                                  });
                                },
                              ),
                              const SizedBox(height: 8),

                              // Outstanding Invoices Breakdown
                              Text(
                                'Eligible Invoices (${_invoices.length})',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 6),
                              if (_invoices.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 8),
                                  child: Text(
                                    'No outstanding invoices found for this customer.',
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                )
                              else
                                ..._invoices.map((inv) {
                                  final invId = inv['invoiceId']?.toString() ?? '';
                                  final invNum =
                                      inv['invoiceNumber']?.toString() ?? invId;
                                  final outletId =
                                      inv['outletId']?.toString() ?? '';
                                  final due =
                                      (inv['dueAmount'] as num?)?.toInt() ?? 0;
                                  final isCurrentOutlet =
                                      outletId == widget.controller.appContext?.outletId;

                                  return Card(
                                    elevation: 0,
                                    color: isCurrentOutlet
                                        ? const Color(0xFFF9FAFB)
                                        : const Color(0xFFEFF6FF),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      side: BorderSide(
                                        color: isCurrentOutlet
                                            ? Colors.grey.shade300
                                            : const Color(0xFFBFDBFE),
                                      ),
                                    ),
                                    margin: const EdgeInsets.only(bottom: 8),
                                    child: Padding(
                                      padding: const EdgeInsets.all(10),
                                      child: Row(
                                        children: [
                                          if (_isManualAllocation) ...[
                                            Checkbox(
                                              value: _selectedInvoiceIds.contains(invId),
                                              onChanged: (checked) {
                                                setState(() {
                                                  if (checked == true) {
                                                    _selectedInvoiceIds.add(invId);
                                                  } else {
                                                    _selectedInvoiceIds.remove(invId);
                                                  }
                                                });
                                              },
                                            ),
                                          ],
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Text(
                                                      invNum,
                                                      style: const TextStyle(
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 13,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 2,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color: isCurrentOutlet
                                                            ? Colors.grey.shade200
                                                            : const Color(0xFFDBEAFE),
                                                        borderRadius:
                                                            BorderRadius.circular(6),
                                                      ),
                                                      child: Text(
                                                        isCurrentOutlet
                                                            ? 'This Outlet ($outletId)'
                                                            : 'Outlet: $outletId',
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          color: isCurrentOutlet
                                                              ? Colors.grey.shade700
                                                              : const Color(0xFF1D4ED8),
                                                          fontWeight: FontWeight.w600,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                Text(
                                                  'Due: ₹${_money(due)}',
                                                  style: const TextStyle(
                                                    color: Color(0xFFB91C1C),
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (_isManualAllocation &&
                                              _selectedInvoiceIds.contains(invId))
                                            SizedBox(
                                              width: 110,
                                              child: TextFormField(
                                                controller:
                                                    _manualAllocControllers[invId],
                                                keyboardType:
                                                    const TextInputType
                                                        .numberWithOptions(
                                                  decimal: true,
                                                ),
                                                decoration: const InputDecoration(
                                                  isDense: true,
                                                  prefixText: '₹ ',
                                                  labelText: 'Allocate',
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  );
                                }),

                              // Excess Advance warning / confirmation
                              if (excessPaise > 0) ...[
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFEF3C7),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: const Color(0xFFFCD34D),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.info_outline,
                                            size: 18,
                                            color: Color(0xFFD97706),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              'Payment exceeds eligible dues by ₹${_money(excessPaise)}.',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFF92400E),
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      CheckboxListTile(
                                        contentPadding: EdgeInsets.zero,
                                        visualDensity: VisualDensity.compact,
                                        title: const Text(
                                          'Confirm storing unallocated excess as customer advance credit.',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Color(0xFF78350F),
                                          ),
                                        ),
                                        value: _allowAdvance,
                                        onChanged: (val) {
                                          setState(() => _allowAdvance = val ?? false);
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 12),

                              // Optional Notes
                              TextFormField(
                                controller: _notesController,
                                decoration: const InputDecoration(
                                  labelText: 'Notes / Remarks (Optional)',
                                  hintText: 'e.g. Cleared dues via GPay at main counter',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Actions
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: _submitting ? null : () => Navigator.pop(context),
                            child: Text(l10n?.cancel ?? 'Cancel'),
                          ),
                          const SizedBox(width: 12),
                          FilledButton.icon(
                            onPressed: _submitting ? null : _submit,
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF059669),
                            ),
                            icon: _submitting
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.check_circle_outline, size: 18),
                            label: Text(
                              _submitting
                                  ? 'Posting Payment...'
                                  : 'Collect ₹${_money(amountPaise)}',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  String _money(int paise) =>
      '${paise ~/ 100}.${(paise % 100).toString().padLeft(2, '0')}';
}
