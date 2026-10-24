import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/config/environment_config.dart';
import '../../data/models/business_settings_model.dart';
import '../../data/services/error_analytics_service.dart';
import '../../data/sync/sync_engine.dart';
import '../../l10n/app_localizations.dart';
import '../about/about_page.dart';
import '../app_controller.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.controller});
  final AppController controller;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  BusinessSettingsModel? _settings;
  bool _loading = false;
  bool _saving = false;
  String? _error;
  String? _successMessage;

  // Form controllers
  final _invoicePrefixCtrl = TextEditingController();
  final _invoiceTermsCtrl = TextEditingController();
  final _bankNameCtrl = TextEditingController();
  final _bankAccountCtrl = TextEditingController();
  final _bankIfscCtrl = TextEditingController();
  final _bankAccountNameCtrl = TextEditingController();
  final _upiIdCtrl = TextEditingController();
  final _lowStockCtrl = TextEditingController();
  final _customWidthCtrl = TextEditingController(text: '80');

  String _printFormat = 'A4_STANDARD';
  bool _alwaysAskPrintFormat = true;
  bool _showUpiQr = true;
  bool _showBankDetails = true;
  String _gstMode = 'REGULAR';
  bool _showHsnSummary = true;
  double _defaultGstRate = 18.0;
  bool _allowNegativeStock = false;
  bool _autoGenerateBarcode = true;
  bool _roundOffPaise = true;

  AppController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    _tabController = TabController(length: 5, vsync: this);
    _loadSettings();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller.appContext?.businessId !=
        widget.controller.appContext?.businessId) {
      _loadSettings();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _tabController.dispose();
    _invoicePrefixCtrl.dispose();
    _invoiceTermsCtrl.dispose();
    _bankNameCtrl.dispose();
    _bankAccountCtrl.dispose();
    _bankIfscCtrl.dispose();
    _bankAccountNameCtrl.dispose();
    _upiIdCtrl.dispose();
    _lowStockCtrl.dispose();
    _customWidthCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final appContext = controller.appContext;
    final token = controller.idToken;
    final repo = controller.settingsRepository;

    if (appContext?.businessId == null || token == null || repo == null) {
      if (mounted) {
        setState(() {
          _error = 'Select an active business to view settings.';
        });
      }
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _successMessage = null;
    });

    try {
      final s = await repo.loadSettings(
        businessId: appContext!.businessId!,
        tenantId: appContext.ownerUid,
        token: token,
      );

      if (mounted) {
        setState(() {
          _settings = s;
          _invoicePrefixCtrl.text = s.invoicePrefix;
          _invoiceTermsCtrl.text = s.invoiceTerms;
          _printFormat = s.printFormat;
          _customWidthCtrl.text = s.customPrintWidthMm.toStringAsFixed(0);
          _alwaysAskPrintFormat = s.alwaysAskPrintFormat;
          _showUpiQr = s.showUpiQr;
          _showBankDetails = s.showBankDetails;
          _bankNameCtrl.text = s.bankName ?? '';
          _bankAccountCtrl.text = s.bankAccountNumber ?? '';
          _bankIfscCtrl.text = s.bankIfsc ?? '';
          _bankAccountNameCtrl.text = s.bankAccountName ?? '';
          _upiIdCtrl.text = s.upiId ?? '';
          _gstMode = s.gstMode;
          _showHsnSummary = s.showHsnSummary;
          _defaultGstRate = s.defaultGstRate;
          _allowNegativeStock = s.allowNegativeStock;
          _lowStockCtrl.text = s.lowStockThreshold.toString();
          _autoGenerateBarcode = s.autoGenerateBarcode;
          _roundOffPaise = s.roundOffPaise;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveSettings() async {
    final appContext = controller.appContext;
    final token = controller.idToken;
    final repo = controller.settingsRepository;

    if (appContext?.businessId == null || token == null || repo == null) {
      return;
    }

    final lowStock = int.tryParse(_lowStockCtrl.text.trim()) ?? 5;
    final customWidth = double.tryParse(_customWidthCtrl.text.trim()) ?? 80.0;

    final updated = (_settings ??
            BusinessSettingsModel.defaultSettings(
              businessId: appContext!.businessId!,
              tenantId: appContext.ownerUid,
            ))
        .copyWith(
      invoicePrefix: _invoicePrefixCtrl.text.trim().isEmpty
          ? 'INV-'
          : _invoicePrefixCtrl.text.trim(),
      invoiceTerms: _invoiceTermsCtrl.text.trim(),
      printFormat: _printFormat,
      customPrintWidthMm: customWidth,
      alwaysAskPrintFormat: _alwaysAskPrintFormat,
      showUpiQr: _showUpiQr,
      showBankDetails: _showBankDetails,
      bankName: _bankNameCtrl.text.trim().isEmpty ? null : _bankNameCtrl.text.trim(),
      bankAccountNumber: _bankAccountCtrl.text.trim().isEmpty
          ? null
          : _bankAccountCtrl.text.trim(),
      bankIfsc: _bankIfscCtrl.text.trim().isEmpty ? null : _bankIfscCtrl.text.trim(),
      bankAccountName: _bankAccountNameCtrl.text.trim().isEmpty
          ? null
          : _bankAccountNameCtrl.text.trim(),
      upiId: _upiIdCtrl.text.trim().isEmpty ? null : _upiIdCtrl.text.trim(),
      gstMode: _gstMode,
      showHsnSummary: _showHsnSummary,
      defaultGstRate: _defaultGstRate,
      allowNegativeStock: _allowNegativeStock,
      lowStockThreshold: lowStock,
      autoGenerateBarcode: _autoGenerateBarcode,
      roundOffPaise: _roundOffPaise,
    );

    setState(() {
      _saving = true;
      _error = null;
      _successMessage = null;
    });

    try {
      await repo.saveSettings(settings: updated, token: token);
      if (mounted) {
        setState(() {
          _settings = updated;
          _successMessage = 'Settings saved and synced successfully!';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settings saved successfully')),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Failed to save settings: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final business = controller.businesses.where(
      (item) => item.businessId == controller.appContext?.businessId,
    );
    final currentBiz = business.isEmpty ? null : business.first;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Header Bar
                Container(
                  color: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFF10263D).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.settings_suggest_rounded,
                          color: Color(0xFF10263D),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n?.settingsAndPreferences ?? 'Settings & Preferences',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFF10263D),
                                  ),
                            ),
                            Text(
                              currentBiz != null
                                  ? 'Configuration for ${currentBiz.businessName}'
                                  : 'Store, billing, tax and sync preferences',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: _saving ? null : _saveSettings,
                        icon: _saving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.check, size: 18),
                        label: Text(_saving ? (l10n?.saving ?? 'Saving...') : (l10n?.saveChanges ?? 'Save Changes')),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF10263D),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Notifications / alerts
                if (_error != null)
                  Container(
                    width: double.infinity,
                    color: Colors.red.shade50,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 8,
                    ),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Colors.red.shade900,
                        fontSize: 13,
                      ),
                    ),
                  ),
                if (_successMessage != null)
                  Container(
                    width: double.infinity,
                    color: Colors.green.shade50,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 8,
                    ),
                    child: Text(
                      _successMessage!,
                      style: TextStyle(
                        color: Colors.green.shade900,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                // Tabs
                Container(
                  color: Colors.white,
                  child: TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    labelColor: const Color(0xFF10263D),
                    unselectedLabelColor: Colors.grey.shade600,
                    indicatorColor: const Color(0xFF10263D),
                    indicatorWeight: 3,
                    labelStyle: const TextStyle(fontWeight: FontWeight.bold),
                    tabs: [
                      Tab(
                        icon: const Icon(Icons.storefront_outlined, size: 20),
                        text: l10n?.storeProfile ?? 'Store Profile',
                      ),
                      Tab(
                        icon: const Icon(Icons.receipt_long_outlined, size: 20),
                        text: l10n?.billingAndInvoice ?? 'Billing & Invoice',
                      ),
                      Tab(
                        icon: const Icon(Icons.account_balance_outlined, size: 20),
                        text: l10n?.gstAndTax ?? 'GST & Tax',
                      ),
                      Tab(
                        icon: const Icon(Icons.inventory_2_outlined, size: 20),
                        text: l10n?.inventoryPolicies ?? 'Inventory Policies',
                      ),
                      Tab(
                        icon: const Icon(Icons.sync_outlined, size: 20),
                        text: l10n?.syncAndDiagnostics ?? 'Sync & Diagnostics',
                      ),
                    ],
                  ),
                ),

                const Divider(height: 1),

                // Tab Views
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildStoreProfileTab(currentBiz),
                      _buildBillingTab(),
                      _buildTaxTab(),
                      _buildInventoryTab(),
                      _buildDiagnosticsTab(),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  // 1. STORE PROFILE TAB
  Widget _buildStoreProfileTab(dynamic currentBiz) {
    final l10n = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _SectionCard(
          title: l10n?.languageAndAppearance ?? 'Language & Regional',
          subtitle: l10n?.selectLanguage ?? 'Select preferred language for bills, reports and interface',
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              ChoiceChip(
                avatar: const Icon(Icons.language_rounded, size: 16),
                label: const Text('🇬🇧 English'),
                selected: controller.currentLocale.languageCode == 'en',
                onSelected: (val) {
                  if (val) controller.setLocale(const Locale('en'));
                },
              ),
              ChoiceChip(
                avatar: const Icon(Icons.language_rounded, size: 16),
                label: const Text('🇮🇳 বাংলা (Bengali)'),
                selected: controller.currentLocale.languageCode == 'bn',
                onSelected: (val) {
                  if (val) controller.setLocale(const Locale('bn'));
                },
              ),
              ChoiceChip(
                avatar: const Icon(Icons.language_rounded, size: 16),
                label: const Text('🇮🇳 हिंदी (Hindi)'),
                selected: controller.currentLocale.languageCode == 'hi',
                onSelected: (val) {
                  if (val) controller.setLocale(const Locale('hi'));
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _SectionCard(
          title: l10n?.businessInformation ?? 'Business Information',
          subtitle: 'Store identity and identification details',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _InfoRow(
                label: 'Business Name',
                value: currentBiz?.businessName ?? '—',
              ),
              const Divider(height: 20),
              _InfoRow(
                label: 'Business ID',
                value: currentBiz?.businessId ?? '—',
              ),
              const Divider(height: 20),
              _InfoRow(
                label: 'Owner Account',
                value: controller.user?.email ?? '—',
              ),
              const Divider(height: 20),
              _InfoRow(
                label: 'Outlets Count',
                value: '${controller.outlets.length} outlet(s) configured',
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _SectionCard(
          title: AppLocalizations.of(context)?.bankAndPaymentDetails ?? 'Bank & Payment Details for Invoices',
          subtitle:
              'These details appear at the bottom of customer bills for direct bank transfer and QR payment',
          child: Column(
            children: [
              TextFormField(
                controller: _bankAccountNameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Account Holder / Beneficiary Name',
                  hintText: 'e.g. Shree Balaji Paints & Hardware',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _bankNameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Bank Name',
                        hintText: 'e.g. State Bank of India, HDFC Bank',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _bankAccountCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Account Number',
                        hintText: 'e.g. 50200012345678',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _bankIfscCtrl,
                      decoration: const InputDecoration(
                        labelText: 'IFSC Code',
                        hintText: 'e.g. SBIN0001234',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _upiIdCtrl,
                      decoration: const InputDecoration(
                        labelText: 'UPI VPA / ID for Payment QR',
                        hintText: 'e.g. shreebalaji@upi',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // 2. BILLING & INVOICE TAB
  Widget _buildBillingTab() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _SectionCard(
          title: AppLocalizations.of(context)?.invoicePrintingLayout ?? 'Invoice Printing Layout',
          subtitle: 'Choose your default receipt and print document geometry',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RadioListTile<String>(
                value: 'A4_STANDARD',
                groupValue: _printFormat,
                title: const Text('A4 Standard Laser/Inkjet Invoice'),
                subtitle: const Text(
                  'Full sheet invoice with complete item table, taxes, and terms (Best for Wholesale/GST bills)',
                ),
                onChanged: (val) => setState(() => _printFormat = val!),
              ),
              RadioListTile<String>(
                value: 'A5_COMPACT',
                groupValue: _printFormat,
                title: const Text('A5 Compact Half-Page Invoice'),
                subtitle: const Text(
                  'Fits 2 bills per A4 page, economical for everyday counter retail',
                ),
                onChanged: (val) => setState(() => _printFormat = val!),
              ),
              RadioListTile<String>(
                value: 'THERMAL_80MM',
                groupValue: _printFormat,
                title: const Text('80mm (3-inch) Thermal POS Slip'),
                subtitle: const Text(
                  'Continuous roll receipt for standard POS counter thermal printers',
                ),
                onChanged: (val) => setState(() => _printFormat = val!),
              ),
              RadioListTile<String>(
                value: 'THERMAL_58MM',
                groupValue: _printFormat,
                title: const Text('58mm (2-inch) Thermal POS Slip'),
                subtitle: const Text(
                  'Compact roll receipt for portable Bluetooth & mini thermal printers',
                ),
                onChanged: (val) => setState(() => _printFormat = val!),
              ),
              RadioListTile<String>(
                value: 'CUSTOM',
                groupValue: _printFormat,
                title: const Text('Custom Size Thermal / Paper'),
                subtitle: const Text(
                  'Set custom roll width in millimeters (e.g. 58mm, 72mm, 80mm, 100mm)',
                ),
                onChanged: (val) => setState(() => _printFormat = val!),
              ),
              if (_printFormat == 'CUSTOM') ...[
                Padding(
                  padding: const EdgeInsets.only(left: 48, right: 16, bottom: 12),
                  child: Row(
                    children: [
                      const Text(
                        'Custom Roll Width: ',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 90,
                        child: TextFormField(
                          controller: _customWidthCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            isDense: true,
                            suffixText: 'mm',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 8,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        '(Range: 40mm - 150mm)',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
              const Divider(height: 24),
              SwitchListTile(
                value: _alwaysAskPrintFormat,
                onChanged: (val) => setState(() => _alwaysAskPrintFormat = val),
                title: const Text('Always ask print size before printing'),
                subtitle: const Text(
                  'When printing from Billing POS or Sales, prompt to choose between A4, A5, Thermal or Custom',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _SectionCard(
          title: AppLocalizations.of(context)?.numberingAndContentOptions ?? 'Numbering & Content Options',
          subtitle: 'Configure invoice identifiers and printed sections',
          child: Column(
            children: [
              TextFormField(
                controller: _invoicePrefixCtrl,
                decoration: const InputDecoration(
                  labelText: 'Invoice Number Prefix',
                  hintText: 'e.g. INV-, BILL-, NUBI/24-25/',
                  helperText:
                      'All generated bills will start with this prefix followed by sequential number',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                value: _showUpiQr,
                title: const Text('Print Dynamic UPI Payment QR Code'),
                subtitle: const Text(
                  'Generates a scan-and-pay Bharat QR with exact invoice amount',
                ),
                onChanged: (val) => setState(() => _showUpiQr = val),
              ),
              SwitchListTile(
                value: _showBankDetails,
                title: const Text('Print Bank Details on Invoices'),
                subtitle: const Text(
                  'Displays bank account & IFSC in invoice footer for NEFT/RTGS payments',
                ),
                onChanged: (val) => setState(() => _showBankDetails = val),
              ),
              SwitchListTile(
                value: _roundOffPaise,
                title: const Text('Round Off Invoice Total to Nearest Rupee'),
                subtitle: const Text(
                  'Rounds fraction amounts (e.g. ₹ 450.40 ➔ ₹ 450.00) automatically',
                ),
                onChanged: (val) => setState(() => _roundOffPaise = val),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _invoiceTermsCtrl,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Default Invoice Terms & Conditions',
                  hintText: 'Enter shop disclaimer, warranty terms, return policy...',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // 3. GST & TAX TAB
  Widget _buildTaxTab() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _SectionCard(
          title: AppLocalizations.of(context)?.gstFilingScheme ?? 'GST Filing Scheme',
          subtitle: 'Configure tax regime applicable to your business',
          child: Column(
            children: [
              RadioListTile<String>(
                value: 'REGULAR',
                groupValue: _gstMode,
                title: const Text('Regular Scheme (Tax Invoice)'),
                subtitle: const Text(
                  'Computes CGST, SGST, IGST with input tax credit (ITC) and HSN codes',
                ),
                onChanged: (val) => setState(() => _gstMode = val!),
              ),
              RadioListTile<String>(
                value: 'COMPOSITION',
                groupValue: _gstMode,
                title: const Text('Composition Scheme (Bill of Supply)'),
                subtitle: const Text(
                  'Flat rate turnover tax without charging GST to customers',
                ),
                onChanged: (val) => setState(() => _gstMode = val!),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _SectionCard(
          title: AppLocalizations.of(context)?.taxSlabsAndReporting ?? 'Tax Slabs & Reporting Options',
          subtitle: 'Default rates applied when creating products or new bills',
          child: Column(
            children: [
              DropdownButtonFormField<double>(
                value: _defaultGstRate,
                decoration: const InputDecoration(
                  labelText: 'Default GST Rate for New Products',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 0.0, child: Text('0% (Exempt)')),
                  DropdownMenuItem(value: 5.0, child: Text('5% (Paints/Solvents basic)')),
                  DropdownMenuItem(value: 12.0, child: Text('12% (Building materials)')),
                  DropdownMenuItem(value: 18.0, child: Text('18% (Standard Paint & Hardware)')),
                  DropdownMenuItem(value: 28.0, child: Text('28% (Luxury & Industrial Coatings)')),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _defaultGstRate = val);
                },
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                value: _showHsnSummary,
                title: const Text('Show HSN/SAC Tax Breakdown on Invoice'),
                subtitle: const Text(
                  'Prints taxable value, CGST, SGST, and IGST grouped by HSN in invoice summary',
                ),
                onChanged: (val) => setState(() => _showHsnSummary = val),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // 4. INVENTORY TAB
  Widget _buildInventoryTab() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _SectionCard(
          title: AppLocalizations.of(context)?.stockAvailabilityRules ?? 'Stock Availability & Safety Rules',
          subtitle: 'Control billing behavior when stock levels are low or zero',
          child: Column(
            children: [
              SwitchListTile(
                value: _allowNegativeStock,
                title: const Text('Allow Negative Stock Billing'),
                subtitle: Text(
                  _allowNegativeStock
                      ? '⚠️ Warning: Cashiers can bill products even when recorded stock is 0'
                      : 'Recommended: Prevents billing when stock balance is insufficient',
                  style: TextStyle(
                    color: _allowNegativeStock ? Colors.orange.shade800 : Colors.grey.shade600,
                  ),
                ),
                onChanged: (val) => setState(() => _allowNegativeStock = val),
              ),
              const Divider(height: 20),
              TextFormField(
                controller: _lowStockCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Low Stock Alert Threshold (Units)',
                  hintText: 'e.g. 5',
                  helperText:
                      'Products with available balance at or below this value appear in Low Stock reports',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _SectionCard(
          title: AppLocalizations.of(context)?.barcodingAndItemIdentification ?? 'Barcoding & Item Identification',
          subtitle: 'Automation preferences when registering new items',
          child: Column(
            children: [
              SwitchListTile(
                value: _autoGenerateBarcode,
                title: const Text('Auto-Generate Barcode / SKU for New Items'),
                subtitle: const Text(
                  'Automatically assigns unique 13-digit EAN-style barcode if left blank during product entry',
                ),
                onChanged: (val) => setState(() => _autoGenerateBarcode = val),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // 5. SYNC & DIAGNOSTICS TAB
  Widget _buildDiagnosticsTab() {
    final sync = controller.sync;
    final state = sync?.state ?? SyncState.offline;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _SectionCard(
          title: AppLocalizations.of(context)?.cloudSyncEngineStatus ?? 'Cloud Synchronization Engine Status',
          subtitle: 'Local SQLite to Google Cloud Firestore sync health',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('Sync Status: ',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: state == SyncState.synced
                          ? Colors.green.shade50
                          : state == SyncState.syncing
                              ? Colors.blue.shade50
                              : Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: state == SyncState.synced
                            ? Colors.green.shade300
                            : state == SyncState.syncing
                                ? Colors.blue.shade300
                                : Colors.orange.shade300,
                      ),
                    ),
                    child: Text(
                      state.name.toUpperCase(),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: state == SyncState.synced
                            ? Colors.green.shade800
                            : state == SyncState.syncing
                                ? Colors.blue.shade800
                                : Colors.orange.shade800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _InfoRow(
                label: 'Pending Outbox Writes',
                value: '${sync?.pendingCount ?? 0} item(s) in queue',
              ),
              if (sync?.error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.shade300),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.shield_outlined, color: Colors.amber.shade900, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Data Safety & Sync Notice',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.amber.shade900,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              sync!.error!,
                              style: TextStyle(
                                color: Colors.brown.shade900,
                                fontSize: 12,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: () async {
                      await controller.sync?.retry();
                      controller.sync?.schedule(
                        pull: true,
                        reason: 'MANUAL_FORCE_SYNC',
                      );
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Triggered remote synchronization retry & sync'),
                          ),
                        );
                        setState(() {});
                      }
                    },
                    icon: const Icon(Icons.sync),
                    label: const Text('Force Remote Sync Now'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF10263D),
                    ),
                  ),
                  if (sync?.error case final err?
                      when err.contains('Remote version changed') ||
                          err.contains('sync-conflict')) ...[
                    OutlinedButton.icon(
                      onPressed: () async {
                        try {
                          await controller.sync?.resolveConflictedOutbox();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Accepted remote data and resolved sync conflict.'),
                              ),
                            );
                            setState(() {});
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Failed to resolve conflict: $e'),
                                backgroundColor: Colors.red.shade700,
                              ),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.check_circle_outline, color: Colors.teal),
                      label: const Text('Accept Remote & Clear Conflict'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.teal.shade800,
                        side: BorderSide(color: Colors.teal.shade600),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        if (sync?.rawDiagnosticError != null || (ErrorAnalyticsService.instance?.recentReports.isNotEmpty ?? false)) ...[
          const SizedBox(height: 20),
          _buildErrorAnalyticsCard(context, sync?.rawDiagnosticError),
        ],
        const SizedBox(height: 20),
        _SectionCard(
          title: AppLocalizations.of(context)?.applicationInformation ?? 'Application Information',
          subtitle: 'NubiBill Business ERP build and architecture details',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _InfoRow(label: 'Software Name', value: 'NubiBill Business ERP'),
              const Divider(height: 20),
              const _InfoRow(label: 'Version', value: 'v${EnvironmentConfig.appVersion}'),
              const Divider(height: 20),
              _InfoRow(label: 'Business Entity', value: widget.controller.currentBusinessName),
              const Divider(height: 20),
              const _InfoRow(label: 'Architecture', value: 'Offline-First SQLite + Firestore REST'),
              const Divider(height: 20),
              const _InfoRow(label: 'Specialization', value: 'Paints, Hardware & Retail Billing'),
              const Divider(height: 20),
              const _InfoRow(label: 'Status', value: 'Active & Verified'),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: () => showAboutNubiBillDialog(context, widget.controller),
                  icon: const Icon(Icons.info_outline, size: 18),
                  label: const Text('About NubiBill ERP & Support'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF10263D),
                    side: const BorderSide(color: Color(0xFF10263D)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildErrorAnalyticsCard(BuildContext context, String? rawDiagnosticError) {
    final recentReport = ErrorAnalyticsService.instance?.recentReports.firstOrNull;
    final raw = rawDiagnosticError ?? recentReport?.rawError ?? '';
    final indexUrl = recentReport?.indexCreationUrl ??
        RegExp(r'https:\/\/console\.firebase\.google\.com[^\s\)]+').firstMatch(raw)?.group(0);

    final problemType = recentReport?.problemType ??
        (raw.toLowerCase().contains('index') ? 'MISSING_COMPOSITE_INDEX' : 'SYNC_EXCEPTION');
    final problemSummary = recentReport?.problemSummary ??
        (problemType == 'MISSING_COMPOSITE_INDEX'
            ? 'Missing Google Cloud Firestore Composite Index'
            : 'Cloud Sync Diagnostic Telemetry');
    final location = recentReport?.location ?? 'Sync Engine background runner';
    final collection = recentReport?.collection ?? (raw.contains('collection=') ? raw.split('collection=').last.split(' ').first : null);

    return _SectionCard(
      title: AppLocalizations.of(context)?.cloudDiagnosticsAndAnalytics ?? 'Cloud Diagnostics & Error Analytics',
      subtitle: 'Technical telemetry automatically recorded to Firestore analytics',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blueGrey.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  problemType,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    color: Colors.blueGrey.shade900,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                'Logged to system_error_analytics',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _InfoRow(label: 'Which Problem', value: problemSummary),
          const Divider(height: 16),
          _InfoRow(
            label: 'Where Problem',
            value: collection != null ? '$location (Collection: $collection)' : location,
          ),
          const Divider(height: 16),
          _InfoRow(
            label: 'What Problem',
            value: indexUrl != null
                ? 'Firestore multi-field query requires an index. The query was safely paused and local data preserved.'
                : (recentReport?.details ?? raw),
          ),
          if (indexUrl != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.link, color: Colors.blue.shade800, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        'Firebase Console Index URL',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade900,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    indexUrl,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: Colors.blue.shade900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: indexUrl));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Firebase index creation link copied to clipboard!'),
                        ),
                      );
                    },
                    icon: const Icon(Icons.copy, size: 14),
                    label: const Text('Copy Index Link'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blue.shade900,
                      side: BorderSide(color: Colors.blue.shade400),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title, subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF10263D),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            const Divider(height: 24),
            child,
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label, value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF10263D),
            ),
          ),
        ),
      ],
    );
  }
}
