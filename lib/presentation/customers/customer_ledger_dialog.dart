import 'package:flutter/material.dart';

import '../../data/models/customer_ledger_entry_model.dart';
import '../../data/models/customer_model.dart';
import '../app_controller.dart';

class CustomerLedgerDialog extends StatefulWidget {
  const CustomerLedgerDialog({
    super.key,
    required this.controller,
    required this.customer,
  });

  final AppController controller;
  final CustomerModel customer;

  @override
  State<CustomerLedgerDialog> createState() => _CustomerLedgerDialogState();
}

class _CustomerLedgerDialogState extends State<CustomerLedgerDialog> {
  bool _loading = true;
  String? _error;
  List<CustomerLedgerEntryModel> _entries = const [];

  @override
  void initState() {
    super.initState();
    _loadLedger();
  }

  Future<void> _loadLedger() async {
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
      final entries = await repo.getCustomerLedger(
        tenantId: appContext!.ownerUid,
        businessId: appContext.businessId!,
        customerId: widget.customer.customerId,
        token: token,
        employeePermissions: appContext.permissions,
        isOwner: widget.controller.user?.accountType == 'owner' ||
            widget.controller.user?.uid == appContext.ownerUid,
      );
      if (mounted) {
        setState(() {
          _entries = entries;
          _loading = false;
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2563EB).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.receipt_long_rounded,
                      color: Color(0xFF2563EB),
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Unified Customer Ledger',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${widget.customer.name} • Phone: ${widget.customer.phone}',
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

              // KPI Balance Summary
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9FAFB),
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
                            'Outstanding Due',
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
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Advance Credit',
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
                            'Total Ledger Entries',
                            style: theme.textTheme.labelSmall
                                ?.copyWith(color: Colors.grey.shade600),
                          ),
                          Text(
                            '${_entries.length} posted events',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Table Content
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                    ? Center(
                        child: Text(_error!,
                            style: const TextStyle(color: Colors.red)),
                      )
                    : _entries.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.history_outlined,
                              size: 48,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No ledger transactions recorded yet.',
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        itemCount: _entries.length,
                        separatorBuilder: (_, _) =>
                            const Divider(height: 1, thickness: 0.5),
                        itemBuilder: (context, index) {
                          final entry = _entries[index];
                          final isCreditSale = entry.transactionType ==
                              CustomerLedgerEntryModel.typeCreditSale;
                          final isPayment = entry.transactionType ==
                              CustomerLedgerEntryModel.typePayment;
                          final isOpening = entry.transactionType ==
                              CustomerLedgerEntryModel.typeOpeningBalance;

                          final dateStr =
                              '${entry.createdAt.year}-${entry.createdAt.month.toString().padLeft(2, '0')}-${entry.createdAt.day.toString().padLeft(2, '0')}';

                          return Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 10,
                              horizontal: 6,
                            ),
                            child: Row(
                              children: [
                                // Date & Outlet
                                SizedBox(
                                  width: 90,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        dateStr,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 12,
                                        ),
                                      ),
                                      if (entry.outletId.isNotEmpty)
                                        Text(
                                          entry.outletId,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey.shade600,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),

                                // Transaction Type Badge
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isCreditSale
                                        ? const Color(0xFFEFF6FF)
                                        : isPayment
                                        ? const Color(0xFFD1FAE5)
                                        : isOpening
                                        ? const Color(0xFFF3E8FF)
                                        : const Color(0xFFFEF3C7),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    entry.transactionType.replaceAll('_', ' '),
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                      color: isCreditSale
                                          ? const Color(0xFF1D4ED8)
                                          : isPayment
                                          ? const Color(0xFF047857)
                                          : isOpening
                                          ? const Color(0xFF7E22CE)
                                          : const Color(0xFFB45309),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),

                                // Reference & Details
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (entry.invoiceId != null &&
                                          entry.invoiceId!.isNotEmpty)
                                        Text(
                                          'Invoice: ${entry.invoiceId}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 12,
                                          ),
                                        ),
                                      if (entry.notes != null &&
                                          entry.notes!.isNotEmpty)
                                        Text(
                                          entry.notes!,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey.shade600,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                    ],
                                  ),
                                ),

                                // Debit / Credit Amounts
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    if (entry.debitPaise > 0)
                                      Text(
                                        '+₹${_money(entry.debitPaise)} Dr',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: Color(0xFFDC2626),
                                        ),
                                      ),
                                    if (entry.creditPaise > 0)
                                      Text(
                                        '-₹${_money(entry.creditPaise)} Cr',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: Color(0xFF059669),
                                        ),
                                      ),
                                    if (entry.advanceCreditPaise > 0)
                                      Text(
                                        'Adv: ₹${_money(entry.advanceCreditPaise)}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 11,
                                          color: Color(0xFF047857),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 16),

              // Actions
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _money(int paise) =>
      '${paise ~/ 100}.${(paise % 100).toString().padLeft(2, '0')}';
}
