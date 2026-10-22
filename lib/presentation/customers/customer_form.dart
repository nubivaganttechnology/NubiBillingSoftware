import 'package:flutter/material.dart';

import '../../data/models/customer_model.dart';
import '../../data/repositories/customer_repository.dart';
import '../../domain/customers/customer_validators.dart';
import '../../l10n/app_localizations.dart';

class CustomerForm extends StatefulWidget {
  const CustomerForm({
    super.key,
    required this.repository,
    required this.tenantId,
    required this.businessId,
    required this.token,
    this.initialCustomer,
    this.onSaved,
    this.onCancel,
  });

  final CustomerRepository repository;
  final String tenantId;
  final String businessId;
  final String token;
  final CustomerModel? initialCustomer;
  final ValueChanged<CustomerModel>? onSaved;
  final VoidCallback? onCancel;

  @override
  State<CustomerForm> createState() => _CustomerFormState();
}

class _CustomerFormState extends State<CustomerForm> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _gstin = TextEditingController();
  final _state = TextEditingController();
  final _address = TextEditingController();
  final _creditLimit = TextEditingController();
  final _opening = TextEditingController(text: '0');

  String _customerType = CustomerModel.typeIndividual;
  bool _isGstRegistered = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final customer = widget.initialCustomer;
    if (customer != null) {
      _name.text = customer.name;
      _phone.text = customer.phone;
      _gstin.text = customer.gstin ?? '';
      _state.text = customer.stateCode ?? '';
      _address.text = customer.address ?? '';
      if (customer.creditLimitPaise != null) {
        final rupees = customer.creditLimitPaise! / 100.0;
        _creditLimit.text = rupees % 1 == 0
            ? rupees.toInt().toString()
            : rupees.toStringAsFixed(2);
      }
      if (customer.customerType == CustomerModel.typeBusiness) {
        _customerType = CustomerModel.typeBusiness;
      } else if (customer.customerType == CustomerModel.typeIndividual) {
        _customerType = CustomerModel.typeIndividual;
      } else {
        _customerType = (customer.gstin != null && customer.gstin!.trim().isNotEmpty)
            ? CustomerModel.typeBusiness
            : CustomerModel.typeIndividual;
      }
      _isGstRegistered = customer.isGstRegistered;
    } else {
      _customerType = CustomerModel.typeIndividual;
      _isGstRegistered = false;
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _phone,
      _gstin,
      _state,
      _address,
      _creditLimit,
      _opening,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _handleGstRegistrationChange(bool isRegistered) async {
    if (isRegistered == _isGstRegistered) return;
    if (!isRegistered && _gstin.text.trim().isNotEmpty) {
      final shouldClear = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Clear Saved GSTIN?'),
          content: Text(
            'This customer currently has GSTIN "${_gstin.text.trim()}". Switching to Unregistered requires confirmation before clearing it.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton.tonal(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Clear & Set Unregistered'),
            ),
          ],
        ),
      );
      if (shouldClear == true) {
        setState(() {
          _isGstRegistered = false;
          _gstin.clear();
        });
      }
      return;
    }
    setState(() {
      _isGstRegistered = isRegistered;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final isEditing = widget.initialCustomer != null;
    final isBusiness = _customerType == CustomerModel.typeBusiness;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Section 1: Basic Information & Classification
          _buildSectionHeader(
            context,
            icon: Icons.person_outline_rounded,
            title: isEditing
                ? (l10n?.editCustomer ?? 'Edit Customer')
                : (l10n?.addCustomer ?? 'New Customer Profile'),
            subtitle: 'Contact and basic identity details',
          ),
          const SizedBox(height: 12),

          // Customer Classification Selector
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Customer Classification',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment<String>(
                    value: CustomerModel.typeIndividual,
                    label: Text('Individual'),
                    icon: Icon(Icons.person_outline, size: 18),
                  ),
                  ButtonSegment<String>(
                    value: CustomerModel.typeBusiness,
                    label: Text('Business'),
                    icon: Icon(Icons.business_outlined, size: 18),
                  ),
                ],
                selected: {_customerType},
                onSelectionChanged: (selected) {
                  setState(() {
                    _customerType = selected.first;
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 12),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: TextFormField(
                  controller: _name,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: isBusiness
                        ? 'Business Name *'
                        : '${l10n?.customerName ?? 'Customer name'} *',
                    hintText: isBusiness
                        ? 'e.g. Sharma Traders / Acme Corp'
                        : 'e.g. John Doe',
                    prefixIcon: Icon(
                      isBusiness ? Icons.business_outlined : Icons.badge_outlined,
                    ),
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.3),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? (isBusiness
                          ? 'Enter business name.'
                          : 'Enter customer name.')
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: '${l10n?.phone ?? 'Phone'} *',
                    hintText: '10-digit mobile',
                    prefixIcon: const Icon(Icons.phone_outlined),
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.3),
                  ),
                  validator: (value) => CustomerValidators.isValidPhone(value ?? '')
                      ? null
                      : 'Enter a valid 10-digit phone number.',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Section 2: GST & Location Details
          _buildSectionHeader(
            context,
            icon: Icons.receipt_long_outlined,
            title: 'Tax & Address',
            subtitle: 'GST compliance and location for state tax calculations',
          ),
          const SizedBox(height: 12),

          // GST Registration Status Selector
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'GST Registration Status',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment<bool>(
                    value: false,
                    label: Text('Unregistered'),
                    icon: Icon(Icons.person_off_outlined, size: 18),
                  ),
                  ButtonSegment<bool>(
                    value: true,
                    label: Text('GST Registered'),
                    icon: Icon(Icons.verified_outlined, size: 18),
                  ),
                ],
                selected: {_isGstRegistered},
                onSelectionChanged: (selected) {
                  _handleGstRegistrationChange(selected.first);
                },
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (_isGstRegistered) ...[
            TextFormField(
              controller: _gstin,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'Recipient GSTIN *',
                hintText: '15-character GSTIN (e.g. 27AAPFU0939F1ZV)',
                prefixIcon: const Icon(Icons.verified_user_outlined),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.3),
              ),
              onChanged: (value) {
                final normalized = CustomerValidators.normalizeGstin(value);
                if (normalized != value) {
                  _gstin.value = _gstin.value.copyWith(
                    text: normalized,
                    selection:
                        TextSelection.collapsed(offset: normalized.length),
                  );
                }
                final stateCode =
                    CustomerValidators.stateCodeFromGstin(normalized);
                // Autofill state code ONLY if empty - do not overwrite customer's actual state!
                if (stateCode != null && _state.text.trim().isEmpty) {
                  _state.text = stateCode;
                }
              },
              validator: (value) {
                if (_isGstRegistered) {
                  return CustomerValidators.validateGstinForRegistration(value);
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
          ],

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: _state,
                  textCapitalization: TextCapitalization.characters,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: l10n?.stateCode ?? 'State code',
                    hintText: 'e.g. 19 or 27',
                    prefixIcon: const Icon(Icons.map_outlined),
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.3),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: TextFormField(
                  controller: _address,
                  maxLines: 2,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: l10n?.billingAddress ?? 'Billing Address',
                    hintText: 'Street, area, city, pin code...',
                    prefixIcon: const Icon(Icons.location_on_outlined),
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.3),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Section 3: Financial & Credit Limits
          _buildSectionHeader(
            context,
            icon: Icons.account_balance_wallet_outlined,
            title: 'Credit & Ledger',
            subtitle: 'Credit limit caps and opening balances for financial ledger',
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  controller: _creditLimit,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: '${l10n?.creditLimit ?? 'Credit limit'} (₹)',
                    prefixText: '₹ ',
                    hintText: 'e.g. 25000',
                    prefixIcon: const Icon(Icons.credit_score_outlined),
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.3),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              if (!isEditing)
                Expanded(
                  child: TextFormField(
                    controller: _opening,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: InputDecoration(
                      labelText:
                          '${l10n?.openingBalance ?? 'Opening balance'} (₹)',
                      prefixText: '₹ ',
                      hintText: '0.00',
                      prefixIcon: const Icon(Icons.account_balance_outlined),
                      filled: true,
                      fillColor: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.3),
                    ),
                  ),
                )
              else
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: (widget.initialCustomer!.duePaise > 0
                              ? Colors.red
                              : widget.initialCustomer!.advancePaise > 0
                              ? Colors.green
                              : Colors.grey)
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: (widget.initialCustomer!.duePaise > 0
                                ? Colors.red
                                : widget.initialCustomer!.advancePaise > 0
                                ? Colors.green
                                : Colors.grey)
                            .withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          l10n?.currentBalance ?? 'Current Balance',
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: Colors.grey.shade700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.initialCustomer!.duePaise > 0
                              ? 'Due: ₹${(widget.initialCustomer!.duePaise / 100).toStringAsFixed(2)}'
                              : widget.initialCustomer!.advancePaise > 0
                              ? 'Advance: ₹${(widget.initialCustomer!.advancePaise / 100).toStringAsFixed(2)}'
                              : '₹0.00 (Settled)',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: widget.initialCustomer!.duePaise > 0
                                ? Colors.red.shade700
                                : widget.initialCustomer!.advancePaise > 0
                                ? Colors.green.shade700
                                : Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          if (!isEditing) ...[
            const SizedBox(height: 6),
            Text(
              l10n?.openingBalanceHelper ??
                  'Positive (+) = customer owes you (Due). Negative (-) = advance customer already paid.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: Colors.grey.shade600),
            ),
          ],
          const SizedBox(height: 24),

          // Actions
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (widget.onCancel != null)
                TextButton(
                  onPressed: _saving ? null : widget.onCancel,
                  child: Text(l10n?.cancel ?? 'Cancel'),
                ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(
                        isEditing
                            ? Icons.save_outlined
                            : Icons.person_add_alt_1_outlined,
                      ),
                label: Text(
                  _saving
                      ? 'Saving...'
                      : isEditing
                      ? (l10n?.editCustomer ?? 'Update Customer')
                      : (l10n?.addCustomer ?? 'Save Customer'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '• $subtitle',
            style: theme.textTheme.labelSmall
                ?.copyWith(color: Colors.grey.shade600),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      int? creditLimitPaise;
      final limitStr = _creditLimit.text.trim();
      if (limitStr.isNotEmpty) {
        final limitRupees = double.tryParse(limitStr);
        if (limitRupees != null) {
          creditLimitPaise = (limitRupees * 100).round();
        }
      }

      int openingBalancePaise = 0;
      final openStr = _opening.text.trim();
      if (openStr.isNotEmpty) {
        final openRupees = double.tryParse(openStr);
        if (openRupees != null) {
          openingBalancePaise = (openRupees * 100).round();
        }
      }

      final trimmedGstin = _gstin.text.trim();
      final effectiveGstin = trimmedGstin.isNotEmpty
          ? CustomerValidators.normalizeGstin(trimmedGstin)
          : null;

      final customer = widget.initialCustomer == null
          ? await widget.repository.create(
              tenantId: widget.tenantId,
              businessId: widget.businessId,
              token: widget.token,
              name: _name.text,
              phone: _phone.text,
              customerType: _customerType,
              isGstRegistered: _isGstRegistered,
              gstin: effectiveGstin,
              stateCode: _state.text.trim().isEmpty
                  ? null
                  : _state.text.trim().toUpperCase(),
              address:
                  _address.text.trim().isEmpty ? null : _address.text.trim(),
              creditLimitPaise: creditLimitPaise,
              openingBalancePaise: openingBalancePaise,
            )
          : await widget.repository.update(
              tenantId: widget.tenantId,
              businessId: widget.businessId,
              token: widget.token,
              customer: widget.initialCustomer!,
              name: _name.text,
              phone: _phone.text,
              customerType: _customerType,
              isGstRegistered: _isGstRegistered,
              gstin: effectiveGstin,
              stateCode: _state.text.trim().isEmpty
                  ? null
                  : _state.text.trim().toUpperCase(),
              address:
                  _address.text.trim().isEmpty ? null : _address.text.trim(),
              creditLimitPaise: creditLimitPaise,
            );
      if (mounted) widget.onSaved?.call(customer);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
