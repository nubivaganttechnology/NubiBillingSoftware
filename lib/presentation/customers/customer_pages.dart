import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models/customer_model.dart';
import '../../l10n/app_localizations.dart';
import '../app_controller.dart';
import '../billing/widgets/upi_qr_widget.dart';
import 'customer_form.dart';

enum _CustomerFilter { all, hasDue, hasAdvance, settled }

enum _CustomerSort { nameAsc, dueDesc, advanceDesc }

class CustomerManagementPage extends StatefulWidget {
  const CustomerManagementPage({super.key, required this.controller});
  final AppController controller;

  @override
  State<CustomerManagementPage> createState() => _CustomerManagementPageState();
}

class _CustomerManagementPageState extends State<CustomerManagementPage> {
  List<CustomerModel> _customers = const [];
  bool _loading = false;
  String? _error;
  final _search = TextEditingController();
  _CustomerFilter _activeFilter = _CustomerFilter.all;
  _CustomerSort _activeSort = _CustomerSort.dueDesc;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  AppController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  @override
  void didUpdateWidget(covariant CustomerManagementPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller.appContext?.businessId !=
        widget.controller.appContext?.businessId) {
      _loadCustomers();
    }
  }

  Future<void> _loadCustomers() async {
    final appContext = controller.appContext;
    final token = controller.idToken;
    if (appContext?.businessId == null ||
        token == null ||
        controller.customerRepository == null) {
      if (mounted) {
        setState(() {
          _customers = const [];
          _error = 'Sign in and select a business first.';
        });
      }
      return;
    }
    final selectedContext = appContext!;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final customers = await controller.customerRepository!.search(
        tenantId: selectedContext.ownerUid,
        businessId: selectedContext.businessId!,
        token: token,
      );
      if (mounted) setState(() => _customers = customers);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final appContext = controller.appContext;
    final token = controller.idToken;

    if (appContext?.businessId == null || token == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.business_center_outlined,
                size: 64,
                color: Colors.grey.shade400,
              ),
              const SizedBox(height: 16),
              Text(
                'Sign in and select a business first.',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: Colors.grey.shade700,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Metrics calculations
    final totalCount = _customers.length;
    var totalDuePaise = 0;
    var totalAdvancePaise = 0;
    var totalCreditLimitPaise = 0;
    var owingCount = 0;
    var advanceCount = 0;
    var settledCount = 0;

    for (final c in _customers) {
      if (c.duePaise > 0) {
        totalDuePaise += c.duePaise;
        owingCount++;
      } else if (c.advancePaise > 0) {
        totalAdvancePaise += c.advancePaise;
        advanceCount++;
      } else {
        settledCount++;
      }
      if (c.creditLimitPaise != null) {
        totalCreditLimitPaise += c.creditLimitPaise!;
      }
    }

    // Filter and search
    final query = _search.text.trim().toLowerCase();
    var filtered = _customers.where((customer) {
      final matchesQuery =
          query.isEmpty ||
          customer.nameLower.contains(query) ||
          customer.phone.contains(query) ||
          (customer.gstin?.toLowerCase().contains(query) ?? false) ||
          (customer.address?.toLowerCase().contains(query) ?? false) ||
          (customer.stateCode?.toLowerCase().contains(query) ?? false);

      if (!matchesQuery) return false;

      switch (_activeFilter) {
        case _CustomerFilter.all:
          return true;
        case _CustomerFilter.hasDue:
          return customer.duePaise > 0;
        case _CustomerFilter.hasAdvance:
          return customer.advancePaise > 0;
        case _CustomerFilter.settled:
          return customer.duePaise == 0 && customer.advancePaise == 0;
      }
    }).toList();

    // Sort
    filtered.sort((a, b) {
      switch (_activeSort) {
        case _CustomerSort.nameAsc:
          return a.nameLower.compareTo(b.nameLower);
        case _CustomerSort.dueDesc:
          return b.duePaise.compareTo(a.duePaise);
        case _CustomerSort.advanceDesc:
          return b.advancePaise.compareTo(a.advancePaise);
      }
    });

    return RefreshIndicator(
      onRefresh: _loadCustomers,
      child: ListView(
        padding: EdgeInsets.symmetric(
          horizontal: MediaQuery.sizeOf(context).width < 600 ? 16 : 24,
          vertical: MediaQuery.sizeOf(context).width < 600 ? 16 : 24,
        ),
        children: [
          // Header
          _buildHeader(context, l10n, totalCount),
          const SizedBox(height: 20),

          // KPI Cards
          _buildKpiSection(
            context,
            l10n,
            totalCount: totalCount,
            totalDuePaise: totalDuePaise,
            totalAdvancePaise: totalAdvancePaise,
            totalCreditLimitPaise: totalCreditLimitPaise,
            owingCount: owingCount,
            advanceCount: advanceCount,
          ),
          const SizedBox(height: 24),

          // Search and Filters
          _buildSearchAndFilters(
            context,
            l10n,
            totalCount: totalCount,
            owingCount: owingCount,
            advanceCount: advanceCount,
            settledCount: settledCount,
          ),
          const SizedBox(height: 20),

          // Status & List view
          if (_loading) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            ),
          ] else if (_error != null) ...[
            _buildErrorState(context, _error!),
          ] else if (_customers.isEmpty) ...[
            _buildNoCustomersState(context, l10n),
          ] else if (filtered.isEmpty) ...[
            _buildNoMatchesState(context, l10n),
          ] else ...[
            for (final customer in filtered) ...[
              _buildCustomerCard(context, l10n, customer),
              const SizedBox(height: 12),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, AppLocalizations? l10n, int count) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 900;
        final heading = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF2563EB).withValues(alpha: 0.25),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.people_alt_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        l10n?.customerDashboard ?? 'Customer Hub',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.5,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.1,
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '$count ${l10n?.allCustomers ?? 'Customers'}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n?.customerDashboardSubtitle ?? 'Manage customer profiles, credit limits, outstanding receivables, and instant UPI collection.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );

        final actions = Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: compact ? WrapAlignment.end : WrapAlignment.start,
          children: [
            PopupMenuButton<String>(
              tooltip: l10n?.languageSelector ?? 'Language',
              onSelected: (code) => controller.setLocale(Locale(code)),
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'en', child: Text('🇬🇧 English')),
                PopupMenuItem(value: 'hi', child: Text('🇮🇳 हिंदी')),
                PopupMenuItem(value: 'bn', child: Text('🇮🇳 বাংলা')),
              ],
              icon: const Icon(Icons.translate_rounded),
            ),
            IconButton.outlined(
              tooltip: l10n?.refresh ?? 'Refresh',
              onPressed: _loading ? null : _loadCustomers,
              icon: const Icon(Icons.refresh_rounded),
            ),
            FilledButton.icon(
              onPressed: () => _openCustomerDialog(),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.person_add_rounded, size: 18),
              label: Text(
                l10n?.addCustomer ?? 'Add Customer',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );

        return Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.white, Color(0xFFF6F9FF)],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1D4ED8).withValues(alpha: 0.07),
                blurRadius: 22,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [heading, const SizedBox(height: 14), actions],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: heading),
                    const SizedBox(width: 12),
                    actions,
                  ],
                ),
        );
      },
    );
  }

  Widget _buildKpiSection(
    BuildContext context,
    AppLocalizations? l10n, {
    required int totalCount,
    required int totalDuePaise,
    required int totalAdvancePaise,
    required int totalCreditLimitPaise,
    required int owingCount,
    required int advanceCount,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 840;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            SizedBox(
              width: wide
                  ? (constraints.maxWidth - 48) / 4
                  : (constraints.maxWidth - 16) / 2,
              child: _buildMetricCard(
                context,
                title: l10n?.totalCustomers ?? 'Total Customers',
                value: '$totalCount',
                subtitle: l10n?.registeredAccounts ?? 'Registered accounts',
                icon: Icons.groups_outlined,
                accentColor: const Color(0xFF2563EB),
              ),
            ),
            SizedBox(
              width: wide
                  ? (constraints.maxWidth - 48) / 4
                  : (constraints.maxWidth - 16) / 2,
              child: _buildMetricCard(
                context,
                title: l10n?.totalDueReceivable ?? 'Total Due Receivable',
                value: '₹${_money(totalDuePaise)}',
                subtitle: l10n?.accountsWithDue ?? 'Accounts with due',
                icon: Icons.pending_actions_outlined,
                accentColor: const Color(0xFFDC2626),
              ),
            ),
            SizedBox(
              width: wide
                  ? (constraints.maxWidth - 48) / 4
                  : (constraints.maxWidth - 16) / 2,
              child: _buildMetricCard(
                context,
                title: l10n?.totalAdvanceReceived ?? 'Total Advance Received',
                value: '₹${_money(totalAdvancePaise)}',
                subtitle: l10n?.accountsWithAdvance ?? 'Accounts with advance',
                icon: Icons.account_balance_wallet_outlined,
                accentColor: const Color(0xFF059669),
              ),
            ),
            SizedBox(
              width: wide
                  ? (constraints.maxWidth - 48) / 4
                  : (constraints.maxWidth - 16) / 2,
              child: _buildMetricCard(
                context,
                title: l10n?.creditExtended ?? 'Credit Extended',
                value: '₹${_money(totalCreditLimitPaise)}',
                subtitle: l10n?.activeCreditLines ?? 'Active credit lines',
                icon: Icons.speed_outlined,
                accentColor: const Color(0xFF7C3AED),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMetricCard(
    BuildContext context, {
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: accentColor, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
              color: accentColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilters(
    BuildContext context,
    AppLocalizations? l10n, {
    required int totalCount,
    required int owingCount,
    required int advanceCount,
    required int settledCount,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_rounded),
                    hintText:
                        l10n?.searchCustomersPlaceholder ??
                        'Search by customer name, phone, GSTIN, or city...',
                    isDense: true,
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.3),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    suffixIcon: _search.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: () {
                              _search.clear();
                              setState(() {});
                            },
                          )
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              PopupMenuButton<_CustomerSort>(
                tooltip: l10n?.sortCustomers ?? 'Sort customers',
                initialValue: _activeSort,
                onSelected: (sort) => setState(() => _activeSort = sort),
                icon: const Icon(Icons.sort_rounded),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: _CustomerSort.dueDesc,
                    child: Text(l10n?.dueHighToLow ?? 'Due: High to low'),
                  ),
                  PopupMenuItem(
                    value: _CustomerSort.advanceDesc,
                    child: Text(
                      l10n?.advanceHighToLow ?? 'Advance: High to low',
                    ),
                  ),
                  PopupMenuItem(
                    value: _CustomerSort.nameAsc,
                    child: Text(l10n?.nameAToZ ?? 'Name: A to Z'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip(
                  label: '${l10n?.allCustomers ?? 'All'} ($totalCount)',
                  selected: _activeFilter == _CustomerFilter.all,
                  onSelected: () =>
                      setState(() => _activeFilter = _CustomerFilter.all),
                ),
                const SizedBox(width: 8),
                _buildFilterChip(
                  label: '${l10n?.hasDue ?? 'Has Due'} ($owingCount)',
                  selected: _activeFilter == _CustomerFilter.hasDue,
                  badgeColor: Colors.red,
                  onSelected: () =>
                      setState(() => _activeFilter = _CustomerFilter.hasDue),
                ),
                const SizedBox(width: 8),
                _buildFilterChip(
                  label: '${l10n?.hasAdvance ?? 'Has Advance'} ($advanceCount)',
                  selected: _activeFilter == _CustomerFilter.hasAdvance,
                  badgeColor: Colors.green,
                  onSelected: () => setState(
                    () => _activeFilter = _CustomerFilter.hasAdvance,
                  ),
                ),
                const SizedBox(width: 8),
                _buildFilterChip(
                  label: '${l10n?.settled ?? 'Settled'} ($settledCount)',
                  selected: _activeFilter == _CustomerFilter.settled,
                  onSelected: () =>
                      setState(() => _activeFilter = _CustomerFilter.settled),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool selected,
    required VoidCallback onSelected,
    Color? badgeColor,
  }) {
    final theme = Theme.of(context);
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      labelStyle: TextStyle(
        fontWeight: selected ? FontWeight.bold : FontWeight.w500,
        color: selected
            ? theme.colorScheme.onPrimaryContainer
            : (badgeColor ?? theme.colorScheme.onSurface),
      ),
      backgroundColor: theme.colorScheme.surface,
      selectedColor: theme.colorScheme.primaryContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      showCheckmark: false,
    );
  }

  Widget _buildCustomerCard(
    BuildContext context,
    AppLocalizations? l10n,
    CustomerModel customer,
  ) {
    final theme = Theme.of(context);
    final compact = MediaQuery.sizeOf(context).width < 600;
    final name = customer.name.trim().isEmpty
        ? (l10n?.walkInCustomer ?? 'Walk-in customer')
        : customer.name;
    final initials = _getInitials(name);
    final avatarColor = _getColorForName(name);

    final hasDue = customer.duePaise > 0;
    final hasAdvance = customer.advancePaise > 0;
    final hasCreditLimit =
        customer.creditLimitPaise != null && customer.creditLimitPaise! > 0;

    double? creditRatio;
    if (hasCreditLimit) {
      creditRatio = (customer.duePaise / customer.creditLimitPaise!).clamp(
        0.0,
        1.0,
      );
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar
                CircleAvatar(
                  radius: 22,
                  backgroundColor: avatarColor.withValues(alpha: 0.15),
                  child: Text(
                    initials,
                    style: TextStyle(
                      color: avatarColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
                const SizedBox(width: 14),

                // Name and details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              name,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (customer.gstin != null &&
                              customer.gstin!.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blue.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'GSTIN',
                                style: TextStyle(
                                  color: Colors.blue.shade700,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.phone_outlined,
                            size: 14,
                            color: Colors.grey.shade600,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            customer.phone,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy_rounded, size: 13),
                            tooltip: 'Copy phone',
                            padding: const EdgeInsets.all(4),
                            constraints: const BoxConstraints(),
                            onPressed: () {
                              Clipboard.setData(
                                ClipboardData(text: customer.phone),
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Phone number copied to clipboard.',
                                  ),
                                  duration: Duration(seconds: 1),
                                ),
                              );
                            },
                          ),
                          if (customer.stateCode != null) ...[
                            const SizedBox(width: 8),
                            Text(
                              '• ${customer.stateCode}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (customer.address != null &&
                          customer.address!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(
                              Icons.location_on_outlined,
                              size: 13,
                              color: Colors.grey.shade500,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                customer.address!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: Colors.grey.shade600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),

                // Financial Badge & Actions
                if (!compact)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (hasDue)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEE2E2),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFFCA5A5)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.arrow_upward_rounded,
                                size: 14,
                                color: Color(0xFFDC2626),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Due: ₹${_money(customer.duePaise)}',
                                style: const TextStyle(
                                  color: Color(0xFFB91C1C),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        )
                      else if (hasAdvance)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFD1FAE5),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFF6EE7B7)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.arrow_downward_rounded,
                                size: 14,
                                color: Color(0xFF059669),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Advance: ₹${_money(customer.advancePaise)}',
                                style: const TextStyle(
                                  color: Color(0xFF047857),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Text(
                            'Settled ₹0.00',
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (hasDue) ...[
                            FilledButton.tonalIcon(
                              onPressed: () => showUpiPaymentDialog(
                                context,
                                amount: customer.duePaise / 100.0,
                                customerName: customer.name,
                                note: 'Customer Due Payment',
                              ),
                              style: FilledButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                              ),
                              icon: const Icon(
                                Icons.qr_code_2_rounded,
                                size: 16,
                              ),
                              label: Text(l10n?.upiCollect ?? 'UPI Collect'),
                            ),
                            const SizedBox(width: 6),
                          ],
                          IconButton.outlined(
                            tooltip: l10n?.editCustomer ?? 'Edit customer',
                            onPressed: () =>
                                _openCustomerDialog(customer: customer),
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.edit_outlined, size: 16),
                          ),
                        ],
                      ),
                    ],
                  ),
              ],
            ),

            if (compact) ...[
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(
                      hasDue
                          ? 'Due: ₹${_money(customer.duePaise)}'
                          : hasAdvance
                          ? 'Advance: ₹${_money(customer.advancePaise)}'
                          : 'Settled ₹0.00',
                    ),
                    backgroundColor: hasDue
                        ? const Color(0xFFFEE2E2)
                        : hasAdvance
                        ? const Color(0xFFD1FAE5)
                        : Colors.grey.shade100,
                  ),
                  if (hasDue)
                    FilledButton.tonalIcon(
                      onPressed: () => showUpiPaymentDialog(
                        context,
                        amount: customer.duePaise / 100.0,
                        customerName: customer.name,
                        note: 'Customer Due Payment',
                      ),
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                      ),
                      icon: const Icon(Icons.qr_code_2_rounded, size: 16),
                      label: Text(l10n?.upiCollect ?? 'UPI Collect'),
                    ),
                  IconButton.outlined(
                    tooltip: l10n?.editCustomer ?? 'Edit customer',
                    onPressed: () => _openCustomerDialog(customer: customer),
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.edit_outlined, size: 16),
                  ),
                ],
              ),
            ],

            // Credit Limit Progress Bar (if credit limit configured)
            if (hasCreditLimit) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    Icons.credit_card_outlined,
                    size: 14,
                    color: Colors.grey.shade600,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${l10n?.creditLimit ?? 'Credit Limit'}: ₹${_money(customer.creditLimitPaise!)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${((creditRatio ?? 0) * 100).toInt()}% Used',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: (creditRatio ?? 0) > 0.85
                          ? Colors.red
                          : (creditRatio ?? 0) > 0.5
                          ? Colors.amber.shade800
                          : Colors.green,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: creditRatio ?? 0,
                  minHeight: 6,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    (creditRatio ?? 0) > 0.85
                        ? Colors.red
                        : (creditRatio ?? 0) > 0.5
                        ? Colors.amber.shade700
                        : Colors.green,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildNoCustomersState(BuildContext context, AppLocalizations? l10n) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.person_add_alt_1_rounded,
                size: 48,
                color: Color(0xFF2563EB),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              l10n?.noCustomersYet ?? 'No customers saved yet',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              l10n?.noCustomersYetSubtitle ?? 'Add your first customer to track sales, ledger dues, and contact details.',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () => _openCustomerDialog(),
              icon: const Icon(Icons.add),
              label: Text(l10n?.addCustomer ?? 'Add Customer'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoMatchesState(BuildContext context, AppLocalizations? l10n) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 48,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              l10n?.noCustomersFound ?? 'No customers found',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              l10n?.noCustomersFoundSubtitle ?? 'No customer profiles match your active search or filter criteria.',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () {
                _search.clear();
                setState(() => _activeFilter = _CustomerFilter.all);
              },
              child: const Text('Clear Filters'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, String error) {
    return Card(
      color: Colors.red.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.red.shade200),
      ),
      child: ListTile(
        leading: const Icon(Icons.error_outline_rounded, color: Colors.red),
        title: const Text(
          'Could not load customers',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(error),
        trailing: FilledButton(
          onPressed: _loadCustomers,
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          child: const Text('Retry'),
        ),
      ),
    );
  }

  Future<void> _openCustomerDialog({CustomerModel? customer}) async {
    final appContext = controller.appContext;
    final token = controller.idToken;
    final repository = controller.customerRepository;
    final l10n = AppLocalizations.of(context);
    if (appContext?.businessId == null || token == null || repository == null) {
      return;
    }

    final isEditing = customer != null;
    final result = await showDialog<CustomerModel>(
      context: context,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 580),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: CustomerForm(
                key: ValueKey(customer?.customerId ?? 'new_customer'),
                repository: repository,
                tenantId: appContext!.ownerUid,
                businessId: appContext.businessId!,
                token: token,
                initialCustomer: customer,
                onCancel: () => Navigator.pop(dialogContext),
                onSaved: (savedCustomer) =>
                    Navigator.pop(dialogContext, savedCustomer),
              ),
            ),
          ),
        ),
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _customers = [
          result,
          ..._customers.where((item) => item.customerId != result.customerId),
        ];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isEditing
                ? (l10n?.customerUpdated ?? 'Customer details updated.')
                : (l10n?.customerSaved ??
                      'Customer saved locally and queued for background sync.'),
          ),
        ),
      );
    }
  }

  String _money(int paise) =>
      '${paise ~/ 100}.${(paise % 100).toString().padLeft(2, '0')}';

  String _getInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return 'C';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  Color _getColorForName(String name) {
    const colors = [
      Color(0xFF2563EB),
      Color(0xFF7C3AED),
      Color(0xFF059669),
      Color(0xFFD97706),
      Color(0xFFDC2626),
      Color(0xFF0891B2),
      Color(0xFF4F46E5),
    ];
    final hash = name.codeUnits.fold(0, (prev, elem) => prev + elem);
    return colors[hash % colors.length];
  }
}
