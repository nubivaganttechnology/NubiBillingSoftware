import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/utils/id_generator.dart';
import '../../core/utils/validators.dart';
import '../../data/models/supplier_model.dart';
import '../../data/models/supplier_refund_model.dart';
import '../../l10n/app_localizations.dart';
import '../app_controller.dart';

enum _SupplierFilter { all, active, inactive }

enum _SupplierSort { nameAsc, nameDesc }

class SupplierManagementPage extends StatefulWidget {
  const SupplierManagementPage({super.key, required this.controller});
  final AppController controller;

  @override
  State<SupplierManagementPage> createState() => _SupplierManagementPageState();
}

/// Shared standalone refund entry used by Supplier Advance and the purchase
/// correction handoff. It always reloads the local scoped advance before entry.
Future<bool> showSupplierRefundEntry(
  BuildContext context,
  AppController controller,
  String supplierId,
) async {
  final snapshot = await controller.loadSupplierFinancialSnapshot(supplierId);
  if (!context.mounted) return false;
  if (snapshot == null) {
    final message = controller.error.isEmpty
        ? 'Supplier advance is unavailable.'
        : controller.error;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
    return false;
  }
  final available = (snapshot['unallocatedAdvance'] as int?) ?? 0;
  if (available <= 0) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('There is no supplier advance to refund.')),
    );
    return false;
  }
  final requestId = IdGenerator.create('SREQ');
  final input = await showDialog<_RefundInput>(
    context: context,
    builder: (_) => SupplierRefundDialog(availableAdvance: available),
  );
  if (input == null || !context.mounted) return false;
  final saved = await controller.recordSupplierRefund(
    supplierId: supplierId,
    amount: input.amount,
    refundDate: input.refundDate,
    paymentMode: input.paymentMode,
    referenceNo: input.referenceNo,
    reason: input.reason,
    notes: input.notes,
    requestId: requestId,
  );
  if (!context.mounted) return saved;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        saved
            ? 'Supplier refund recorded and queued for sync.'
            : controller.error.isEmpty
            ? 'Refund was not recorded.'
            : controller.error,
      ),
    ),
  );
  return saved;
}

class _SupplierManagementPageState extends State<SupplierManagementPage> {
  final _search = TextEditingController();
  _SupplierFilter _activeFilter = _SupplierFilter.all;
  _SupplierSort _activeSort = _SupplierSort.nameAsc;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.controller.loadSuppliers();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        if (!controller.canManageSuppliers()) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.lock_outline_rounded,
                    size: 64,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'You do not have supplier access.',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final linkedIds = controller.suppliers
            .map((item) => item.supplierId)
            .toSet();
        final unlinked = controller.tenantSuppliers
            .where((item) => !linkedIds.contains(item.supplierId))
            .toList();

        final totalCount = controller.suppliers.length;
        final activeCount = controller.suppliers
            .where((s) => s.isActive)
            .length;
        final inactiveCount = totalCount - activeCount;

        // Search & Filter
        final query = _search.text.trim().toLowerCase();
        var visibleSuppliers = controller.suppliers.where((supplier) {
          final matchesQuery =
              query.isEmpty ||
              supplier.name.toLowerCase().contains(query) ||
              (supplier.mobile?.toLowerCase().contains(query) ?? false) ||
              (supplier.contactPerson?.toLowerCase().contains(query) ??
                  false) ||
              (supplier.email?.toLowerCase().contains(query) ?? false) ||
              (supplier.gstin?.toLowerCase().contains(query) ?? false) ||
              (supplier.pan?.toLowerCase().contains(query) ?? false) ||
              (supplier.address?.toLowerCase().contains(query) ?? false);

          if (!matchesQuery) return false;

          switch (_activeFilter) {
            case _SupplierFilter.all:
              return true;
            case _SupplierFilter.active:
              return supplier.isActive;
            case _SupplierFilter.inactive:
              return !supplier.isActive;
          }
        }).toList();

        // Sort
        visibleSuppliers.sort((a, b) {
          switch (_activeSort) {
            case _SupplierSort.nameAsc:
              return a.name.toLowerCase().compareTo(b.name.toLowerCase());
            case _SupplierSort.nameDesc:
              return b.name.toLowerCase().compareTo(a.name.toLowerCase());
          }
        });

        return RefreshIndicator(
          onRefresh: controller.loadSuppliers,
          child: ListView(
            padding: EdgeInsets.symmetric(
              horizontal: MediaQuery.sizeOf(context).width < 600 ? 16 : 24,
              vertical: MediaQuery.sizeOf(context).width < 600 ? 16 : 24,
            ),
            children: [
              // Header
              _buildHeader(
                context,
                l10n,
                totalCount: totalCount,
                unlinked: unlinked,
              ),
              const SizedBox(height: 20),

              // KPI Cards
              _buildKpiSection(
                context,
                l10n,
                totalCount: totalCount,
                activeCount: activeCount,
                inactiveCount: inactiveCount,
                unlinkedCount: unlinked.length,
              ),
              const SizedBox(height: 24),

              // Search & Filter Bar
              _buildSearchAndFilters(
                context,
                l10n,
                totalCount: totalCount,
                activeCount: activeCount,
                inactiveCount: inactiveCount,
              ),
              const SizedBox(height: 20),

              // Main List / States
              if (controller.suppliersLoading) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ] else if (controller.suppliersError != null) ...[
                _buildErrorCard(context, controller.suppliersError!),
              ] else if (controller.suppliers.isEmpty) ...[
                _buildEmptySuppliersCard(context, l10n, unlinked),
              ] else if (visibleSuppliers.isEmpty) ...[
                _buildEmptySearchResultsCard(context, l10n),
              ] else ...[
                for (final supplier in visibleSuppliers) ...[
                  _SupplierCard(
                    supplier: supplier,
                    onEdit: () => _editSupplier(context, supplier),
                    onToggleStatus: () =>
                        _toggleSupplierStatus(context, supplier),
                    onAdvance: () => _showSupplierAdvance(context, supplier),
                    busy: controller.supplierSaving,
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(
    BuildContext context,
    AppLocalizations? l10n, {
    required int totalCount,
    required List<SupplierModel> unlinked,
  }) {
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
                  colors: [Color(0xFF7C3AED), Color(0xFF6D28D9)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF7C3AED).withValues(alpha: 0.25),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.local_shipping_rounded,
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
                        l10n?.supplierDashboard ?? 'Supplier & Vendor Hub',
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
                          color: const Color(0xFF7C3AED).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '$totalCount ${l10n?.allSuppliers ?? 'Suppliers'}',
                          style: const TextStyle(
                            color: Color(0xFF7C3AED),
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n?.supplierDashboardSubtitle ?? 'Oversee procurement partners, trade credit terms, advance balances, and refunds.',
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
          alignment: compact ? WrapAlignment.end : WrapAlignment.start,
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            PopupMenuButton<String>(
              tooltip: l10n?.languageSelector ?? 'Language',
              onSelected: (code) => widget.controller.setLocale(Locale(code)),
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'en', child: Text('🇬🇧 English')),
                PopupMenuItem(value: 'hi', child: Text('🇮🇳 हिंदी')),
                PopupMenuItem(value: 'bn', child: Text('🇮🇳 বাংলা')),
              ],
              icon: const Icon(Icons.translate_rounded),
            ),
            IconButton.outlined(
              tooltip: l10n?.refresh ?? 'Refresh',
              onPressed: widget.controller.suppliersLoading
                  ? null
                  : widget.controller.loadSuppliers,
              icon: const Icon(Icons.refresh_rounded),
            ),
            if (unlinked.isNotEmpty)
              OutlinedButton.icon(
                onPressed: () => _linkSupplier(context, unlinked),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.link_rounded, size: 18),
                label: Text(
                  '${l10n?.linkExistingSupplier ?? 'Link existing'} (${unlinked.length})',
                ),
              ),
            FilledButton.icon(
              onPressed: () => _createSupplier(context),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF7C3AED),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(
                l10n?.addSupplier ?? 'Add Supplier',
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
              colors: [Colors.white, Color(0xFFFBF8FF)],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF6D28D9).withValues(alpha: 0.07),
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
    required int activeCount,
    required int inactiveCount,
    required int unlinkedCount,
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
                title: l10n?.totalSuppliers ?? 'Total Suppliers',
                value: '$totalCount',
                subtitle: l10n?.linkedToBusiness ?? 'Linked to business',
                icon: Icons.inventory_2_outlined,
                accentColor: const Color(0xFF7C3AED),
              ),
            ),
            SizedBox(
              width: wide
                  ? (constraints.maxWidth - 48) / 4
                  : (constraints.maxWidth - 16) / 2,
              child: _buildMetricCard(
                context,
                title: l10n?.activeSuppliers ?? 'Active Suppliers',
                value: '$activeCount',
                subtitle: l10n?.readyForPurchases ?? 'Ready for purchases',
                icon: Icons.check_circle_outline_rounded,
                accentColor: const Color(0xFF059669),
              ),
            ),
            SizedBox(
              width: wide
                  ? (constraints.maxWidth - 48) / 4
                  : (constraints.maxWidth - 16) / 2,
              child: _buildMetricCard(
                context,
                title: l10n?.inactiveSuppliers ?? 'Inactive Suppliers',
                value: '$inactiveCount',
                subtitle: l10n?.deactivatedAccounts ?? 'Deactivated accounts',
                icon: Icons.pause_circle_outline_rounded,
                accentColor: const Color(0xFFDC2626),
              ),
            ),
            SizedBox(
              width: wide
                  ? (constraints.maxWidth - 48) / 4
                  : (constraints.maxWidth - 16) / 2,
              child: _buildMetricCard(
                context,
                title: l10n?.availableToLink ?? 'Available to link',
                value: '$unlinkedCount',
                subtitle: l10n?.fromOtherBusinesses ?? 'From other businesses',
                icon: Icons.alt_route_rounded,
                accentColor: const Color(0xFF2563EB),
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
    required int activeCount,
    required int inactiveCount,
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
                    hintText: l10n?.searchSuppliersPlaceholder ?? 'Search by supplier name, contact person, mobile, or GSTIN...',
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
              PopupMenuButton<_SupplierSort>(
                tooltip: l10n?.sortSuppliers ?? 'Sort suppliers',
                initialValue: _activeSort,
                onSelected: (sort) => setState(() => _activeSort = sort),
                icon: const Icon(Icons.sort_rounded),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: _SupplierSort.nameAsc,
                    child: Text(l10n?.nameAToZ ?? 'Name: A to Z'),
                  ),
                  PopupMenuItem(
                    value: _SupplierSort.nameDesc,
                    child: Text(l10n?.nameZToA ?? 'Name: Z to A'),
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
                  label: '${l10n?.allSuppliers ?? 'All'} ($totalCount)',
                  selected: _activeFilter == _SupplierFilter.all,
                  onSelected: () =>
                      setState(() => _activeFilter = _SupplierFilter.all),
                ),
                const SizedBox(width: 8),
                _buildFilterChip(
                  label: '${l10n?.activeSuppliers ?? 'Active'} ($activeCount)',
                  selected: _activeFilter == _SupplierFilter.active,
                  badgeColor: Colors.green,
                  onSelected: () =>
                      setState(() => _activeFilter = _SupplierFilter.active),
                ),
                const SizedBox(width: 8),
                _buildFilterChip(
                  label:
                      '${l10n?.inactiveSuppliers ?? 'Inactive'} ($inactiveCount)',
                  selected: _activeFilter == _SupplierFilter.inactive,
                  badgeColor: Colors.red,
                  onSelected: () =>
                      setState(() => _activeFilter = _SupplierFilter.inactive),
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

  Widget _buildEmptySuppliersCard(
    BuildContext context,
    AppLocalizations? l10n,
    List<SupplierModel> unlinked,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF7C3AED).withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.local_shipping_outlined,
                size: 48,
                color: Color(0xFF7C3AED),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              l10n?.noSuppliersYet ?? 'No suppliers linked yet',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                l10n?.noSuppliersYetSubtitle ?? 'No suppliers are linked to this business. Add a supplier or link one from another business.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (unlinked.isNotEmpty) ...[
                  OutlinedButton.icon(
                    onPressed: () => _linkSupplier(context, unlinked),
                    icon: const Icon(Icons.link_rounded),
                    label: Text(l10n?.linkExistingSupplier ?? 'Link existing'),
                  ),
                  const SizedBox(width: 12),
                ],
                FilledButton.icon(
                  onPressed: () => _createSupplier(context),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF7C3AED),
                  ),
                  icon: const Icon(Icons.add),
                  label: Text(l10n?.addSupplier ?? 'Add Supplier'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptySearchResultsCard(
    BuildContext context,
    AppLocalizations? l10n,
  ) {
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
              l10n?.noSuppliersFound ?? 'No suppliers found',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              l10n?.noSuppliersFoundSubtitle ?? 'No supplier profiles match your active search or filter criteria.',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () {
                _search.clear();
                setState(() => _activeFilter = _SupplierFilter.all);
              },
              child: const Text('Clear Filters'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard(BuildContext context, String error) {
    return Card(
      color: Colors.red.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.red.shade200),
      ),
      child: ListTile(
        leading: const Icon(Icons.cloud_off_outlined, color: Colors.red),
        title: const Text(
          'Could not load suppliers',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(error),
        trailing: FilledButton(
          onPressed: widget.controller.loadSuppliers,
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          child: const Text('Retry'),
        ),
      ),
    );
  }

  Future<void> _createSupplier(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _SupplierFormDialog(controller: widget.controller),
    );
  }

  Future<void> _editSupplier(
    BuildContext context,
    SupplierModel supplier,
  ) async {
    final terms = await widget.controller.getSupplierBusinessTerms(
      supplier.supplierId,
    );
    if (terms == null || !context.mounted) {
      if (context.mounted && widget.controller.error.isNotEmpty) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(widget.controller.error)));
      }
      return;
    }
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _SupplierFormDialog(
        controller: widget.controller,
        supplier: supplier,
        businessTerms: terms,
      ),
    );
    if (saved == true && context.mounted) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n?.supplierUpdated ?? '${supplier.name} updated.'),
        ),
      );
    }
  }

  Future<void> _toggleSupplierStatus(
    BuildContext context,
    SupplierModel supplier,
  ) async {
    final activate = !supplier.isActive;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${activate ? 'Activate' : 'Deactivate'} supplier?'),
        content: Text(
          activate
              ? '${supplier.name} will become available for purchasing in this tenant.'
              : '${supplier.name} will be deactivated across all businesses and unavailable for new purchases.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: activate
                  ? const Color(0xFF059669)
                  : const Color(0xFFDC2626),
            ),
            child: Text(activate ? 'Activate' : 'Deactivate'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final saved = await widget.controller.setSupplierActive(
      supplier.supplierId,
      activate,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            saved
                ? '${supplier.name} ${activate ? 'activated' : 'deactivated'}.'
                : widget.controller.error,
          ),
        ),
      );
    }
  }

  Future<void> _showSupplierAdvance(
    BuildContext context,
    SupplierModel supplier,
  ) async {
    var snapshot = await widget.controller.loadSupplierFinancialSnapshot(
      supplier.supplierId,
    );
    if (!context.mounted) return;
    if (snapshot == null) {
      final message = widget.controller.error.isEmpty
          ? 'Supplier advance is unavailable.'
          : widget.controller.error;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final advance = (snapshot!['unallocatedAdvance'] as int?) ?? 0;
          final refunds = snapshot!['refunds'] as List<SupplierRefundModel>;
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF059669).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.account_balance_wallet_rounded,
                    color: Color(0xFF059669),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        supplier.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Supplier Advance & Refunds',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 540,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFECFDF5), Color(0xFFD1FAE5)],
                        ),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFA7F3D0)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Available Advance',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF065F46),
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Money available for future purchases',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: const Color(0xFF047857),
                                ),
                              ),
                            ],
                          ),
                          Text(
                            '₹${_formatPaise(advance)}',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF065F46),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Refund History',
                            style: Theme.of(dialogContext).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: advance <= 0
                              ? null
                              : () async {
                                  final requestId = IdGenerator.create('SREQ');
                                  final input = await showDialog<_RefundInput>(
                                    context: dialogContext,
                                    builder: (_) => SupplierRefundDialog(
                                      availableAdvance: advance,
                                    ),
                                  );
                                  if (input == null || !dialogContext.mounted) {
                                    return;
                                  }
                                  final saved = await widget.controller
                                      .recordSupplierRefund(
                                        supplierId: supplier.supplierId,
                                        amount: input.amount,
                                        refundDate: input.refundDate,
                                        paymentMode: input.paymentMode,
                                        referenceNo: input.referenceNo,
                                        reason: input.reason,
                                        notes: input.notes,
                                        requestId: requestId,
                                      );
                                  if (!dialogContext.mounted) return;
                                  if (!saved) {
                                    ScaffoldMessenger.of(dialogContext)
                                        .showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              widget.controller.error.isEmpty
                                                  ? 'Refund was not recorded.'
                                                  : widget.controller.error,
                                            ),
                                          ),
                                        );
                                    return;
                                  }
                                  final refreshed = await widget.controller
                                      .loadSupplierFinancialSnapshot(
                                        supplier.supplierId,
                                      );
                                  if (refreshed != null &&
                                      dialogContext.mounted) {
                                    setDialogState(() => snapshot = refreshed);
                                  }
                                },
                          icon: const Icon(
                            Icons.call_received_rounded,
                            size: 16,
                          ),
                          label: const Text('Record Refund'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (refunds.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(20),
                        alignment: Alignment.center,
                        child: Text(
                          'No supplier refunds recorded.',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      )
                    else
                      for (final refund in refunds.take(8)) ...[
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.south_west_rounded,
                                  size: 16,
                                  color: Colors.blue,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Money received · ₹${_formatPaise(refund.amount)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${_dateLabel(refund.refundDate)} • ${refund.paymentMode.replaceAll('_', ' ')} • ${refund.reason}'
                                      '${refund.referenceNo == null ? '' : ' • Ref: ${refund.referenceNo}'}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade600,
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
                                  color: Colors.green.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  refund.status,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Close'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _linkSupplier(
    BuildContext context,
    List<SupplierModel> suppliers,
  ) async {
    final selected = await showDialog<SupplierModel>(
      context: context,
      builder: (context) => SimpleDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Link existing supplier',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        children: [
          for (final supplier in suppliers)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, supplier),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(
                  child: Icon(Icons.local_shipping_outlined),
                ),
                title: Text(
                  supplier.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(supplier.mobile ?? supplier.email ?? ''),
              ),
            ),
        ],
      ),
    );
    if (selected == null || !context.mounted) return;
    final terms = await showDialog<_SupplierTerms>(
      context: context,
      builder: (_) => const _SupplierTermsDialog(),
    );
    if (terms == null || !context.mounted) return;
    final linked = await widget.controller.linkSupplier(
      supplierId: selected.supplierId,
      creditLimit: terms.creditLimit,
      paymentTermsDays: terms.paymentTerms,
      openingBalance: terms.openingBalance,
      preferred: terms.preferred,
    );
    if (linked && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${selected.name} linked to this business.')),
      );
    }
  }
}

class _SupplierTerms {
  const _SupplierTerms(
    this.creditLimit,
    this.paymentTerms,
    this.openingBalance,
    this.preferred,
  );
  final int creditLimit, paymentTerms, openingBalance;
  final bool preferred;
}

class _SupplierTermsDialog extends StatefulWidget {
  const _SupplierTermsDialog();
  @override
  State<_SupplierTermsDialog> createState() => _SupplierTermsDialogState();
}

class _SupplierTermsDialogState extends State<_SupplierTermsDialog> {
  final _credit = TextEditingController(text: '0');
  final _terms = TextEditingController(text: '0');
  final _opening = TextEditingController(text: '0');
  bool _preferred = false;

  @override
  void dispose() {
    _credit.dispose();
    _terms.dispose();
    _opening.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    title: const Text(
      'Business Terms',
      style: TextStyle(fontWeight: FontWeight.bold),
    ),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _credit,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Credit Limit (₹)',
              prefixText: '₹ ',
              filled: true,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _terms,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Payment Terms (days)',
              hintText: 'e.g. 30',
              filled: true,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _opening,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Opening Payable (₹)',
              prefixText: '₹ ',
              filled: true,
            ),
          ),
          const SizedBox(height: 12),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Preferred Supplier'),
            subtitle: const Text('Used as a priority vendor indicator'),
            value: _preferred,
            onChanged: (value) => setState(() => _preferred = value),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          final credit = _parseRupees(_credit.text),
              opening = _parseRupees(_opening.text),
              days = int.tryParse(_terms.text.trim());
          if (credit != null &&
              opening != null &&
              credit >= 0 &&
              opening >= 0 &&
              days != null &&
              days >= 0) {
            Navigator.pop(
              context,
              _SupplierTerms(credit, days, opening, _preferred),
            );
          }
        },
        child: const Text('Link Supplier'),
      ),
    ],
  );
}

int? _parseRupees(String raw) {
  final value = raw.trim().replaceAll(',', '');
  if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(value)) return null;
  final parts = value.split('.');
  return int.parse(parts.first) * 100 +
      int.parse((parts.length > 1 ? parts[1] : '').padRight(2, '0'));
}

String _formatRupees(int paise) => (paise / 100).toStringAsFixed(2);

class _SupplierCard extends StatelessWidget {
  const _SupplierCard({
    required this.supplier,
    required this.onEdit,
    required this.onToggleStatus,
    required this.onAdvance,
    required this.busy,
  });
  final SupplierModel supplier;
  final VoidCallback onEdit, onToggleStatus, onAdvance;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compact = MediaQuery.sizeOf(context).width < 600;
    final initials = _getInitials(supplier.name);
    final avatarColor = _getColorForName(supplier.name);

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

                // Name & details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            supplier.name,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(width: 8),
                          // Status chip
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: supplier.isActive
                                  ? const Color(0xFFD1FAE5)
                                  : const Color(0xFFFEE2E2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              supplier.isActive ? 'Active' : 'Inactive',
                              style: TextStyle(
                                color: supplier.isActive
                                    ? const Color(0xFF047857)
                                    : const Color(0xFFB91C1C),
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (supplier.gstin != null &&
                              supplier.gstin!.isNotEmpty) ...[
                            const SizedBox(width: 6),
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
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        children: [
                          if (supplier.contactPerson?.isNotEmpty == true)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.person_outline_rounded,
                                  size: 14,
                                  color: Colors.grey.shade600,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  supplier.contactPerson!,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: Colors.grey.shade700,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          if (supplier.mobile?.isNotEmpty == true)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.phone_outlined,
                                  size: 14,
                                  color: Colors.grey.shade600,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  supplier.mobile!,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: Colors.grey.shade700,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.copy_rounded,
                                    size: 12,
                                  ),
                                  tooltip: 'Copy mobile',
                                  padding: const EdgeInsets.all(4),
                                  constraints: const BoxConstraints(),
                                  onPressed: () {
                                    Clipboard.setData(
                                      ClipboardData(text: supplier.mobile!),
                                    );
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Mobile copied to clipboard.',
                                        ),
                                        duration: Duration(seconds: 1),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          if (supplier.gstin?.isNotEmpty == true)
                            Text(
                              'GSTIN: ${supplier.gstin!}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.grey.shade600,
                              ),
                            ),
                          if (supplier.supplierType?.isNotEmpty == true)
                            Text(
                              'Type: ${supplier.supplierType!}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.grey.shade600,
                              ),
                            ),
                        ],
                      ),
                      if (supplier.address?.isNotEmpty == true) ...[
                        const SizedBox(height: 4),
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
                                supplier.address!,
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

                // Actions
                if (compact)
                  PopupMenuButton<String>(
                    tooltip: 'Supplier actions',
                    onSelected: (action) {
                      switch (action) {
                        case 'advance':
                          onAdvance();
                          break;
                        case 'edit':
                          onEdit();
                          break;
                        case 'status':
                          if (!busy) onToggleStatus();
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'advance',
                        child: Text('Supplier advance'),
                      ),
                      const PopupMenuItem(
                        value: 'edit',
                        child: Text('Edit supplier'),
                      ),
                      PopupMenuItem(
                        value: 'status',
                        enabled: !busy,
                        child: Text(
                          supplier.isActive
                              ? 'Deactivate supplier'
                              : 'Activate supplier',
                        ),
                      ),
                    ],
                  )
                else
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: onAdvance,
                        style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                        ),
                        icon: const Icon(
                          Icons.account_balance_wallet_outlined,
                          size: 16,
                        ),
                        label: const Text('Advance'),
                      ),
                      const SizedBox(width: 6),
                      IconButton.outlined(
                        tooltip: 'Edit supplier',
                        onPressed: onEdit,
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.edit_outlined, size: 16),
                      ),
                      const SizedBox(width: 6),
                      IconButton.outlined(
                        tooltip: supplier.isActive
                            ? 'Deactivate supplier'
                            : 'Activate supplier',
                        onPressed: busy ? null : onToggleStatus,
                        visualDensity: VisualDensity.compact,
                        color: supplier.isActive
                            ? Colors.green.shade700
                            : Colors.red.shade700,
                        icon: Icon(
                          supplier.isActive
                              ? Icons.toggle_on_rounded
                              : Icons.toggle_off_rounded,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _getInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return 'S';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  Color _getColorForName(String name) {
    const colors = [
      Color(0xFF7C3AED),
      Color(0xFF2563EB),
      Color(0xFF059669),
      Color(0xFFD97706),
      Color(0xFF0891B2),
      Color(0xFF4F46E5),
      Color(0xFFBE185D),
    ];
    final hash = name.codeUnits.fold(0, (prev, elem) => prev + elem);
    return colors[hash % colors.length];
  }
}

class _RefundInput {
  const _RefundInput({
    required this.amount,
    required this.refundDate,
    required this.paymentMode,
    required this.referenceNo,
    required this.reason,
    required this.notes,
  });
  final int amount;
  final DateTime refundDate;
  final String paymentMode, referenceNo, reason, notes;
}

class SupplierRefundDialog extends StatefulWidget {
  const SupplierRefundDialog({super.key, required this.availableAdvance});
  final int availableAdvance;

  @override
  State<SupplierRefundDialog> createState() => _SupplierRefundDialogState();
}

class _SupplierRefundDialogState extends State<SupplierRefundDialog> {
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  final _reason = TextEditingController();
  final _notes = TextEditingController();
  DateTime? _date = DateTime.now();
  String _mode = 'CASH';
  String? _error;

  @override
  void initState() {
    super.initState();
    _amount.text = (widget.availableAdvance / 100).toStringAsFixed(2);
  }

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    _reason.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Record Supplier Refund'),
    content: SizedBox(
      width: 430,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Available advance: ₹${_formatPaise(widget.availableAdvance)}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Refund Amount (₹)'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Refund Date *'),
              subtitle: Text(
                _date == null ? 'Select date' : _dateLabel(_date!),
              ),
              trailing: const Icon(Icons.calendar_month_outlined),
              onTap: () async {
                final selected = await showDatePicker(
                  context: context,
                  initialDate: _date ?? DateTime.now(),
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (selected != null) setState(() => _date = selected);
              },
            ),
            DropdownButtonFormField<String>(
              initialValue: _mode,
              decoration: const InputDecoration(labelText: 'Payment Mode *'),
              items: const ['CASH', 'UPI', 'BANK_TRANSFER', 'CHEQUE', 'CARD']
                  .map(
                    (mode) => DropdownMenuItem(
                      value: mode,
                      child: Text(mode.replaceAll('_', ' ')),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _mode = value ?? 'CASH'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _reference,
              decoration: const InputDecoration(labelText: 'Reference Number'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _reason,
              decoration: const InputDecoration(labelText: 'Reason *'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _notes,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Notes'),
            ),
            if (_amount.text.isNotEmpty) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Advance after refund: ₹${_formatPaise(widget.availableAdvance - (_parsePaise(_amount.text) ?? 0))}',
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          final amount = _parsePaise(_amount.text);
          if (amount == null || amount <= 0) {
            setState(() => _error = 'Refund amount must be greater than zero.');
            return;
          }
          if (amount > widget.availableAdvance) {
            setState(() => _error = 'Refund cannot exceed available advance.');
            return;
          }
          if (_date == null) {
            setState(() => _error = 'Refund date is required.');
            return;
          }
          if (_mode.isEmpty) {
            setState(() => _error = 'Payment mode is required.');
            return;
          }
          if (_reason.text.trim().isEmpty) {
            setState(() => _error = 'Reason is required.');
            return;
          }
          Navigator.pop(
            context,
            _RefundInput(
              amount: amount,
              refundDate: _date!,
              paymentMode: _mode,
              referenceNo: _reference.text.trim(),
              reason: _reason.text.trim(),
              notes: _notes.text.trim(),
            ),
          );
        },
        child: const Text('Record Refund'),
      ),
    ],
  );
}

int? _parsePaise(String value) {
  final raw = value.trim().replaceAll(',', '');
  if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(raw)) return null;
  final parts = raw.split('.');
  return int.parse(parts[0]) * 100 +
      int.parse((parts.length > 1 ? parts[1] : '').padRight(2, '0'));
}

String _formatPaise(int value) => (value / 100).toStringAsFixed(2);
String _dateLabel(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

class _SupplierFormDialog extends StatefulWidget {
  const _SupplierFormDialog({
    required this.controller,
    this.supplier,
    this.businessTerms,
  });
  final AppController controller;
  final SupplierModel? supplier;
  final SupplierBusinessModel? businessTerms;

  @override
  State<_SupplierFormDialog> createState() => _SupplierFormDialogState();
}

class _SupplierFormDialogState extends State<_SupplierFormDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _mobile = TextEditingController();
  final _contact = TextEditingController();
  final _email = TextEditingController();
  final _whatsapp = TextEditingController();
  final _gstin = TextEditingController();
  final _pan = TextEditingController();
  final _state = TextEditingController();
  final _type = TextEditingController();
  final _address = TextEditingController();
  final _creditLimit = TextEditingController(text: '0');
  final _terms = TextEditingController(text: '0');
  final _openingBalance = TextEditingController(text: '0');
  bool _preferred = false;
  bool get _isEditing => widget.supplier != null;
  bool get _hasBusiness {
    final context = widget.controller.appContext;
    return context?.businessId != null &&
        widget.controller.businesses.any(
          (business) =>
              business.businessId == context!.businessId &&
              business.ownerUid == context.ownerUid &&
              business.isActive,
        );
  }

  @override
  void initState() {
    super.initState();
    final supplier = widget.supplier;
    final terms = widget.businessTerms;
    if (supplier == null) return;
    _name.text = supplier.name;
    _mobile.text = supplier.mobile ?? '';
    _contact.text = supplier.contactPerson ?? '';
    _email.text = supplier.email ?? '';
    _whatsapp.text = supplier.whatsapp ?? '';
    _gstin.text = supplier.gstin ?? '';
    _pan.text = supplier.pan ?? '';
    _state.text = supplier.stateCode ?? '';
    _type.text = supplier.supplierType ?? '';
    _address.text = supplier.address ?? '';
    _creditLimit.text = _formatRupees(terms?.creditLimit ?? 0);
    _terms.text = '${terms?.paymentTermsDays ?? 0}';
    _openingBalance.text = _formatRupees(terms?.openingBalance ?? 0);
    _preferred = terms?.preferred ?? false;
  }

  @override
  void dispose() {
    for (final field in [
      _name,
      _mobile,
      _contact,
      _email,
      _whatsapp,
      _gstin,
      _pan,
      _state,
      _type,
      _address,
      _creditLimit,
      _terms,
      _openingBalance,
    ]) {
      field.dispose();
    }
    super.dispose();
  }

  int? _paise(String input) {
    final value = input.trim().replaceAll(',', '');
    if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(value)) return null;
    final parts = value.split('.');
    final rupees = int.tryParse(parts[0]);
    if (rupees == null) return null;
    final fraction = parts.length == 1 ? '' : parts[1].padRight(2, '0');
    return rupees * 100 + (fraction.isEmpty ? 0 : int.parse(fraction));
  }

  Future<void> _save() async {
    if (_form.currentState?.validate() != true) return;
    final saved = _isEditing
        ? await widget.controller.updateSupplier(
            supplierId: widget.supplier!.supplierId,
            name: _name.text,
            mobile: _mobile.text,
            contactPerson: _contact.text,
            email: _email.text,
            whatsapp: _whatsapp.text,
            gstin: _gstin.text,
            pan: _pan.text,
            stateCode: _state.text,
            supplierType: _type.text,
            address: _address.text,
            creditLimit: _paise(_creditLimit.text)!,
            paymentTermsDays: int.parse(_terms.text),
            preferred: _preferred,
          )
        : await widget.controller.createSupplier(
            name: _name.text,
            mobile: _mobile.text,
            contactPerson: _contact.text,
            email: _email.text,
            whatsapp: _whatsapp.text,
            gstin: _gstin.text,
            pan: _pan.text,
            stateCode: _state.text,
            supplierType: _type.text,
            address: _address.text,
            creditLimit: _paise(_creditLimit.text)!,
            paymentTermsDays: int.parse(_terms.text),
            openingBalance: _paise(_openingBalance.text)!,
            preferred: _preferred,
          );
    if (saved && mounted) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _isEditing
                ? (l10n?.editSupplier ?? 'Edit Supplier')
                : (l10n?.addSupplier ?? 'Add Supplier'),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          leading: IconButton(
            onPressed: widget.controller.supplierSaving
                ? null
                : () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: FilledButton.icon(
                onPressed: widget.controller.supplierSaving || !_hasBusiness
                    ? null
                    : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                ),
                icon: widget.controller.supplierSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check_rounded),
                label: Text(
                  widget.controller.supplierSaving
                      ? 'Saving...'
                      : _isEditing
                      ? (l10n?.editSupplier ?? 'Update')
                      : (l10n?.addSupplier ?? 'Save'),
                ),
              ),
            ),
          ],
        ),
        body: AnimatedBuilder(
          animation: widget.controller,
          builder: (context, _) => Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              children: [
                // Section 1: Basic Information
                _buildSectionCard(
                  context,
                  icon: Icons.business_outlined,
                  title: 'Supplier Profile & Contact',
                  subtitle: 'Business identity and representative details',
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextFormField(
                            controller: _name,
                            decoration: const InputDecoration(
                              labelText: 'Supplier Name *',
                              hintText: 'e.g. Apex Traders Ltd.',
                              prefixIcon: Icon(
                                Icons.store_mall_directory_outlined,
                              ),
                              filled: true,
                            ),
                            validator: (v) =>
                                AppValidators.required(v, 'supplier name'),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: _contact,
                            decoration: InputDecoration(
                              labelText:
                                  l10n?.contactPerson ?? 'Contact Person',
                              hintText: 'Manager / Representative',
                              prefixIcon: const Icon(
                                Icons.person_outline_rounded,
                              ),
                              filled: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _mobile,
                            keyboardType: TextInputType.phone,
                            decoration: InputDecoration(
                              labelText:
                                  l10n?.supplierMobile ?? 'Mobile Number',
                              prefixIcon: const Icon(Icons.phone_outlined),
                              filled: true,
                            ),
                            validator: (v) => (v?.trim().isEmpty ?? true)
                                ? null
                                : AppValidators.indianPhone(v),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: _whatsapp,
                            keyboardType: TextInputType.phone,
                            decoration: InputDecoration(
                              labelText:
                                  l10n?.whatsappNumber ?? 'WhatsApp Number',
                              prefixIcon: const Icon(
                                Icons.chat_bubble_outline_rounded,
                              ),
                              filled: true,
                            ),
                            validator: (v) => (v?.trim().isEmpty ?? true)
                                ? null
                                : AppValidators.indianPhone(v),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            decoration: InputDecoration(
                              labelText: l10n?.supplierEmail ?? 'Email Address',
                              prefixIcon: const Icon(
                                Icons.mail_outline_rounded,
                              ),
                              filled: true,
                            ),
                            validator: (v) => (v?.trim().isEmpty ?? true)
                                ? null
                                : AppValidators.email(v),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Section 2: Taxation and Regulatory
                _buildSectionCard(
                  context,
                  icon: Icons.verified_user_outlined,
                  title: 'Taxation & Regulatory',
                  subtitle: 'GST, PAN, state code and registered category',
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextFormField(
                            controller: _gstin,
                            textCapitalization: TextCapitalization.characters,
                            decoration: const InputDecoration(
                              labelText: 'GSTIN',
                              hintText: '22AAAAA0000A1Z5',
                              prefixIcon: Icon(Icons.receipt_long_outlined),
                              filled: true,
                            ),
                            validator: AppValidators.gstin,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: _pan,
                            textCapitalization: TextCapitalization.characters,
                            decoration: InputDecoration(
                              labelText: l10n?.panNumber ?? 'PAN',
                              hintText: 'ABCDE1234F',
                              prefixIcon: const Icon(
                                Icons.credit_card_outlined,
                              ),
                              filled: true,
                            ),
                            validator: (value) =>
                                value == null ||
                                    value.trim().isEmpty ||
                                    RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$')
                                        .hasMatch(value.trim().toUpperCase())
                                ? null
                                : 'Enter a valid PAN.',
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 1,
                          child: TextFormField(
                            controller: _state,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: l10n?.stateCode ?? 'State code',
                              hintText: 'e.g. 19',
                              prefixIcon: const Icon(Icons.map_outlined),
                              filled: true,
                            ),
                            validator: (value) =>
                                value == null ||
                                    value.trim().isEmpty ||
                                    RegExp(r'^\d{2}$').hasMatch(value.trim())
                                ? null
                                : 'Enter 2-digit code.',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: _type,
                            decoration: InputDecoration(
                              labelText:
                                  l10n?.supplierType ??
                                  'Supplier type / Category',
                              hintText: 'Wholesaler / Manufacturer',
                              prefixIcon: const Icon(Icons.category_outlined),
                              filled: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 4,
                          child: TextFormField(
                            controller: _address,
                            maxLines: 2,
                            decoration: InputDecoration(
                              labelText: l10n?.billingAddress ?? 'Address',
                              hintText: 'Warehouse address, town, pincode...',
                              prefixIcon: const Icon(
                                Icons.location_on_outlined,
                              ),
                              filled: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Section 3: Commercial Business Terms
                _buildSectionCard(
                  context,
                  icon: Icons.handshake_outlined,
                  title: l10n?.businessTerms ?? 'Commercial Business Terms',
                  subtitle: l10n?.optionalBusinessTermsSubtitle ?? 'Configure credit limits, payment schedules, and partner priority',
                  children: [
                    Builder(
                      builder: (context) {
                        final businessId =
                            widget.controller.appContext?.businessId;
                        final selectedBusiness = widget.controller.businesses
                            .where(
                              (business) =>
                                  business.businessId == businessId &&
                                  business.isActive,
                            );
                        if (selectedBusiness.isEmpty) {
                          return const ListTile(
                            leading: Icon(Icons.business_outlined),
                            title: Text(
                              'Select an active business before adding a supplier.',
                            ),
                          );
                        }
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withValues(
                              alpha: 0.05,
                            ),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: theme.colorScheme.primary.withValues(
                                alpha: 0.2,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.business_rounded,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Linked Business: ${selectedBusiness.first.businessName}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ),
                              const Text(
                                'Active Workspace',
                                style: TextStyle(
                                  color: Colors.black54,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _creditLimit,
                            enabled: _hasBusiness,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText:
                                  '${l10n?.creditLimit ?? 'Credit Limit'} (₹)',
                              prefixText: '₹ ',
                              filled: true,
                            ),
                            validator: (v) => _paise(v ?? '') == null
                                ? 'Enter valid amount.'
                                : null,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: _terms,
                            enabled: _hasBusiness,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText:
                                  l10n?.paymentTermsDays ??
                                  'Payment Terms (days)',
                              hintText: 'e.g. 30',
                              filled: true,
                            ),
                            validator: (v) =>
                                int.tryParse(v ?? '') == null ||
                                    int.parse(v!) < 0
                                ? 'Enter days >= 0.'
                                : null,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: _openingBalance,
                            enabled: _hasBusiness,
                            readOnly: _isEditing,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText:
                                  '${l10n?.openingPayable ?? 'Opening Payable'} (₹)',
                              prefixText: '₹ ',
                              helperText: _isEditing
                                  ? 'Recorded in ledger (read-only)'
                                  : null,
                              filled: true,
                            ),
                            validator: (v) => _paise(v ?? '') == null
                                ? 'Enter valid amount.'
                                : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        l10n?.preferredSupplier ??
                            'Preferred Supplier for this Business',
                      ),
                      subtitle: Text(
                        l10n?.preferredSupplierSubtitle ??
                            'Used as a primary vendor indicator.',
                      ),
                      value: _preferred,
                      onChanged: !_hasBusiness
                          ? null
                          : (value) => setState(() => _preferred = value),
                    ),
                  ],
                ),
                if (widget.controller.error.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Text(
                      widget.controller.error,
                      style: TextStyle(color: Colors.red.shade700),
                    ),
                  ),
                ],
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: const Color(0xFF7C3AED)),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '• $subtitle',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// Opens the existing full Supplier master form for use from Purchase Entry.
Future<bool> showSupplierFormFromPurchase(
  BuildContext context,
  AppController controller,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => _SupplierFormDialog(controller: controller),
    ) ==
    true;
