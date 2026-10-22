import 'package:flutter/material.dart';

import '../../core/utils/validators.dart';
import '../../data/models/storage_location_model.dart';
import '../app_controller.dart';

class StorageManagementPage extends StatefulWidget {
  const StorageManagementPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<StorageManagementPage> createState() => _StorageManagementPageState();
}

class _StorageManagementPageState extends State<StorageManagementPage> {
  final _search = TextEditingController();
  String _statusFilter = 'ALL';
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.controller.loadStorageLocations();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      final business = controller.businesses.where(
        (item) => item.businessId == controller.appContext?.businessId,
      );
      if (!controller.canViewStorage()) {
        return const Center(
          child: Text('You do not have permission to view storage locations.'),
        );
      }
      if (business.isEmpty) {
        return _StorageEmptyState(
          title: 'Select a Business',
          message: 'Select a business to manage its optional Godowns.',
        );
      }
      final businessStorageLocations = controller.storageLocations
          .where(
            (item) =>
                item.type != StorageLocationType.rack ||
                item.parentLocationType == 'GODOWN',
          )
          .toList();
      final filtered = _filteredLocations(businessStorageLocations);
      final visibleIds = _visibleIds(filtered, businessStorageLocations);
      final visible = businessStorageLocations
          .where((item) => visibleIds.contains(item.storageLocationId))
          .toList();
      final children = <String?, List<StorageLocationModel>>{};
      for (final location in visible) {
        children.putIfAbsent(location.parentLocationId, () => []).add(location);
      }
      final roots = visible
          .where(
            (item) =>
                item.type == StorageLocationType.godown ||
                (item.type == StorageLocationType.rack &&
                    item.parentLocationType == 'GODOWN'),
          )
          .where(
            (item) =>
                item.parentLocationId == null ||
                !visibleIds.contains(item.parentLocationId),
          )
          .toList();
      final selected = controller.storageLocations.where(
        (item) => item.storageLocationId == _selectedId,
      );

      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 760;
                final heading = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Godown Management',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(business.first.businessName),
                  ],
                );
                final actions = Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: compact ? WrapAlignment.end : WrapAlignment.start,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    IconButton(
                      tooltip: 'Refresh storage locations',
                      onPressed: controller.storageLoading
                          ? null
                          : controller.loadStorageLocations,
                      icon: const Icon(Icons.refresh),
                    ),
                    const SizedBox(width: 8),
                    if (controller.canCreateStorage())
                      FilledButton.icon(
                        onPressed: controller.storageSaving
                            ? null
                            : () => _showCreateDialog(context),
                        icon: const Icon(Icons.add),
                        label: const Text('Add Godown'),
                      ),
                    if (controller.canCreateRacks()) ...[
                      OutlinedButton.icon(
                        onPressed: controller.storageSaving
                            ? null
                            : () => _showAddRackDialog(context),
                        icon: const Icon(Icons.add),
                        label: const Text('Add Rack'),
                      ),
                    ],
                  ],
                );
                return compact
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          heading,
                          const SizedBox(height: 10),
                          actions,
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(child: heading),
                          actions,
                        ],
                      );
              },
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 300,
                  child: TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      labelText: 'Search name or code',
                      isDense: true,
                    ),
                  ),
                ),
                _FilterDropdown(
                  label: 'Status',
                  value: _statusFilter,
                  values: const ['ALL', 'ACTIVE', 'INACTIVE'],
                  onChanged: (value) => setState(() => _statusFilter = value),
                ),
              ],
            ),
            if (controller.storageError != null) ...[
              const SizedBox(height: 12),
              MaterialBanner(
                content: Text(controller.storageError!),
                actions: [
                  TextButton(
                    onPressed: controller.loadStorageLocations,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            Expanded(
              child: controller.storageLoading
                  ? const Center(child: CircularProgressIndicator())
                  : businessStorageLocations.isEmpty
                  ? _StorageEmptyState(
                      title: 'No Godowns',
                      message: 'This business has no Godowns yet. Outlets can operate independently.',
                      actionLabel: controller.canCreateStorage()
                          ? 'Add Godown'
                          : null,
                      onAction: controller.canCreateStorage()
                          ? () => _showCreateDialog(context)
                          : null,
                    )
                  : visible.isEmpty
                  ? const Center(
                      child: Text('No storage locations match these filters.'),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final tree = _buildTree(roots, children, controller);
                        final details = selected.isEmpty
                            ? const _StorageDetailsEmpty()
                            : _StorageDetailsPanel(
                                location: selected.first,
                                controller: controller,
                                onEdit: () =>
                                    _showEditDialog(context, selected.first),
                                onAddChild: () => _showCreateDialog(
                                  context,
                                  parent: selected.first,
                                ),
                                onAddMultiple: () => _showBulkRackDialog(
                                  context,
                                  selected.first,
                                ),
                                onStatus: () =>
                                    _confirmStatus(context, selected.first),
                              );
                        if (constraints.maxWidth >= 820) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(flex: 5, child: tree),
                              const SizedBox(width: 16),
                              Expanded(flex: 4, child: details),
                            ],
                          );
                        }
                        return ListView(
                          children: [tree, const SizedBox(height: 12), details],
                        );
                      },
                    ),
            ),
          ],
        ),
      );
    },
  );

  List<StorageLocationModel> _filteredLocations(
    List<StorageLocationModel> all,
  ) {
    final search = _search.text.trim().toLowerCase();
    return all.where((location) {
      final matchesSearch =
          search.isEmpty ||
          location.name.toLowerCase().contains(search) ||
          location.code.toLowerCase().contains(search);
      final matchesStatus =
          _statusFilter == 'ALL' || location.status.value == _statusFilter;
      return matchesSearch && matchesStatus;
    }).toList();
  }

  Set<String> _visibleIds(
    List<StorageLocationModel> matches,
    List<StorageLocationModel> all,
  ) {
    final byId = {for (final item in all) item.storageLocationId: item};
    final result = <String>{};
    for (final match in matches) {
      StorageLocationModel? cursor = match;
      final visited = <String>{};
      while (cursor != null && visited.add(cursor.storageLocationId)) {
        result.add(cursor.storageLocationId);
        final parentId = cursor.parentLocationId;
        cursor = parentId == null ? null : byId[parentId];
      }
    }
    return result;
  }

  Widget _buildTree(
    List<StorageLocationModel> roots,
    Map<String?, List<StorageLocationModel>> children,
    AppController controller,
  ) {
    final outletNames = {
      for (final outlet in controller.outlets)
        outlet.outletId: outlet.outletName,
    };
    return Card(
      clipBehavior: Clip.antiAlias,
      child: controller.storageLocations.isEmpty
          ? const SizedBox.shrink()
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                for (final root in roots)
                  _StorageTreeNode(
                    location: root,
                    children: children,
                    outletNames: outletNames,
                    selectedId: _selectedId,
                    onSelect: (location) => setState(
                      () => _selectedId = location.storageLocationId,
                    ),
                    onEdit:
                        (controller.canUpdateRacks() ||
                            controller.canEditStorage())
                        ? (location) {
                            if (location.type == StorageLocationType.rack
                                ? controller.canUpdateRacks()
                                : controller.canEditStorage()) {
                              _showEditDialog(context, location);
                            }
                          }
                        : null,
                    onAddChild:
                        (controller.canCreateRacks() ||
                            controller.canCreateStorage())
                        ? (location) {
                            if (location.type == StorageLocationType.rack
                                ? controller.canCreateStorage()
                                : controller.canCreateRacks()) {
                              _showCreateDialog(context, parent: location);
                            }
                          }
                        : null,
                    onStatus:
                        (controller.canDeactivateRacks() ||
                            controller.canDeleteStorage())
                        ? (location) {
                            if (location.type == StorageLocationType.rack
                                ? controller.canDeactivateRacks()
                                : controller.canDeleteStorage()) {
                              _confirmStatus(context, location);
                            }
                          }
                        : null,
                  ),
              ],
            ),
    );
  }

  Future<void> _showCreateDialog(
    BuildContext context, {
    StorageLocationModel? parent,
  }) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) =>
          _StorageFormDialog(controller: widget.controller, parent: parent),
    );
    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Location created.')));
    }
  }

  Future<void> _showAddRackDialog(BuildContext context) async {
    final controller = widget.controller;
    final parents = <Map<String, String>>[
      for (final godown in controller.storageLocations.where(
        (item) => item.type == StorageLocationType.godown && item.isActive,
      ))
        {
          'type': 'GODOWN',
          'id': godown.storageLocationId,
          'label': 'Godown · ${godown.name} (${godown.code})',
        },
      for (final outlet in controller.outlets.where(
        (item) =>
            item.isActive &&
            item.businessId == controller.appContext?.businessId,
      ))
        {
          'type': 'OUTLET',
          'id': outlet.outletId,
          'label':
              'Outlet · ${outlet.outletName} (${outlet.outletCode ?? outlet.outletId})',
        },
    ];
    if (parents.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Create an active Godown or Outlet first.'),
        ),
      );
      return;
    }
    final optionsByKey = {
      for (final parent in parents) '${parent['type']}:${parent['id']}': parent,
    };
    var selected = optionsByKey.keys.first;
    final selectedKey = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Add Rack'),
            content: DropdownButtonFormField<String>(
              initialValue: selected,
              decoration: const InputDecoration(labelText: 'Rack location'),
              items: [
                for (final entry in optionsByKey.entries)
                  DropdownMenuItem(
                    value: entry.key,
                    child: Text(entry.value['label']!),
                  ),
              ],
              onChanged: (value) =>
                  setDialogState(() => selected = value ?? selected),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, selected),
                child: const Text('Continue'),
              ),
            ],
          );
        },
      ),
    );
    if (selectedKey == null || !context.mounted) return;
    final parent = optionsByKey[selectedKey]!;
    await showDialog<bool>(
      context: context,
      builder: (_) => _StorageFormDialog(
        controller: controller,
        parentLocationType: parent['type'],
        parentLocationId: parent['id'],
      ),
    );
  }

  Future<void> _showEditDialog(
    BuildContext context,
    StorageLocationModel location,
  ) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) =>
          _StorageFormDialog(controller: widget.controller, location: location),
    );
    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Location updated.')));
    }
  }

  Future<void> _showBulkRackDialog(
    BuildContext context,
    StorageLocationModel parent,
  ) async {
    final field = TextEditingController();
    final count = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add Multiple Racks · ${parent.name}'),
        content: TextField(
          controller: field,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Number of Racks',
            hintText: '1–100',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final parsed = int.tryParse(field.text.trim());
              if (parsed != null && parsed > 0 && parsed <= 100)
                Navigator.pop(context, parsed);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
    field.dispose();
    if (count == null || !context.mounted) return;
    final saved = await widget.controller.createMultipleRacks(
      parentLocationType: 'GODOWN',
      parentLocationId: parent.storageLocationId,
      count: count,
    );
    if (saved && context.mounted)
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$count Racks created.')));
  }

  Future<void> _confirmStatus(
    BuildContext context,
    StorageLocationModel location,
  ) async {
    final activate = !location.isActive;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          activate
              ? 'Activate ${location.type.label}?'
              : 'Deactivate ${location.type.label}?',
        ),
        content: Text(
          activate
              ? 'This ${location.type.label.toLowerCase()} will become active again.'
              : 'This ${location.type.label.toLowerCase()} will become inactive. Historical information will be preserved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(activate ? 'Activate' : 'Deactivate'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final changed = await widget.controller.setStorageLocationActive(
      location,
      activate,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          changed
              ? 'Storage location ${activate ? 'activated' : 'deactivated'}.'
              : widget.controller.storageError ?? 'Unable to update location.',
        ),
      ),
    );
  }
}

class _StorageTreeNode extends StatelessWidget {
  const _StorageTreeNode({
    required this.location,
    required this.children,
    required this.outletNames,
    required this.selectedId,
    required this.onSelect,
    required this.onEdit,
    required this.onAddChild,
    required this.onStatus,
  });

  final StorageLocationModel location;
  final Map<String?, List<StorageLocationModel>> children;
  final Map<String, String> outletNames;
  final String? selectedId;
  final ValueChanged<StorageLocationModel> onSelect;
  final ValueChanged<StorageLocationModel>? onEdit, onAddChild, onStatus;

  @override
  Widget build(BuildContext context) {
    final nested = children[location.storageLocationId] ?? const [];
    final isSelected = location.storageLocationId == selectedId;
    final subtitle = <String>[
      '${location.code} · ${location.type.label} · ${location.isActive ? 'Active' : 'Inactive'}',
      if (location.type == StorageLocationType.godown)
        'Scope: ${location.godownScope?.name.toUpperCase() ?? 'Needs review'}',
      if (location.type == StorageLocationType.godown &&
          location.godownScope == GodownScope.outlet)
        'Outlet: ${outletNames[location.outletId] ?? location.outletId ?? 'Unassigned'}',
      if (location.type == StorageLocationType.godown)
        'Capacity: ${_capacityLabel(location.capacity)} · Used: Not Available · Available: Not Available · Utilization: Not Available',
      if (location.type == StorageLocationType.godown &&
          (location.address?.isNotEmpty ?? false))
        location.address!,
      if (location.type == StorageLocationType.godown)
        'Created ${_date(location.createdAt)}',
    ].join('\n');
    final content = ListTile(
      dense: true,
      selected: isSelected,
      title: Text(location.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        subtitle,
        style: location.isActive
            ? null
            : TextStyle(color: Theme.of(context).colorScheme.error),
      ),
      trailing: onAddChild == null && onEdit == null && onStatus == null
          ? null
          : MediaQuery.sizeOf(context).width < 600
          ? PopupMenuButton<String>(
              tooltip: 'Location actions',
              onSelected: (action) {
                switch (action) {
                  case 'add':
                    onAddChild?.call(location);
                    break;
                  case 'edit':
                    onEdit?.call(location);
                    break;
                  case 'status':
                    onStatus?.call(location);
                    break;
                }
              },
              itemBuilder: (context) => [
                if (onAddChild != null &&
                    location.type != StorageLocationType.shelf)
                  PopupMenuItem(
                    value: 'add',
                    child: Text(
                      location.type == StorageLocationType.godown
                          ? 'Add Rack'
                          : 'Add Shelf',
                    ),
                  ),
                if (onEdit != null)
                  PopupMenuItem(
                    value: 'edit',
                    child: Text('Edit ${location.type.label}'),
                  ),
                if (onStatus != null)
                  PopupMenuItem(
                    value: 'status',
                    child: Text(location.isActive ? 'Deactivate' : 'Activate'),
                  ),
              ],
            )
          : Wrap(
              spacing: 0,
              children: [
                if (onAddChild != null &&
                    location.type != StorageLocationType.shelf)
                  IconButton(
                    tooltip: location.type == StorageLocationType.godown
                        ? 'Add Rack'
                        : 'Add Shelf',
                    onPressed: () => onAddChild!(location),
                    icon: const Icon(Icons.add, size: 18),
                  ),
                if (onEdit != null)
                  IconButton(
                    tooltip: 'Edit ${location.type.label}',
                    onPressed: () => onEdit!(location),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                  ),
                if (onStatus != null)
                  IconButton(
                    tooltip: location.isActive ? 'Deactivate' : 'Activate',
                    onPressed: () => onStatus!(location),
                    icon: Icon(
                      location.isActive ? Icons.toggle_on : Icons.toggle_off,
                      color: location.isActive ? Colors.green : Colors.red,
                    ),
                  ),
              ],
            ),
      onTap: () => onSelect(location),
    );
    if (nested.isEmpty) {
      return Padding(padding: const EdgeInsets.only(left: 8), child: content);
    }
    return ExpansionTile(
      key: PageStorageKey(location.storageLocationId),
      initiallyExpanded: true,
      title: content,
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(left: 22),
      children: [
        for (final child in nested)
          _StorageTreeNode(
            location: child,
            children: children,
            outletNames: outletNames,
            selectedId: selectedId,
            onSelect: onSelect,
            onEdit: onEdit,
            onAddChild: onAddChild,
            onStatus: onStatus,
          ),
      ],
    );
  }
}

class _StorageDetailsPanel extends StatelessWidget {
  const _StorageDetailsPanel({
    required this.location,
    required this.controller,
    required this.onEdit,
    required this.onAddChild,
    required this.onAddMultiple,
    required this.onStatus,
  });

  final StorageLocationModel location;
  final AppController controller;
  final VoidCallback onEdit, onAddChild, onStatus;
  final VoidCallback onAddMultiple;

  @override
  Widget build(BuildContext context) {
    final parent = controller.storageLocations.where(
      (item) => item.storageLocationId == location.parentLocationId,
    );
    final assignedOutlets = controller.outlets.where(
      (outlet) => outlet.outletId == location.outletId,
    );
    final assignedOutletName = assignedOutlets.isEmpty
        ? location.outletId ?? '—'
        : assignedOutlets.first.outletName;
    return Card(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  location.name,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              _StatusBadge(active: location.isActive),
            ],
          ),
          const Divider(height: 26),
          _DetailRow('${location.type.label} Code', location.code),
          if (location.type == StorageLocationType.godown) ...[
            _DetailRow(
              'Scope',
              location.godownScope?.name.toUpperCase() ?? 'Needs review',
            ),
            if (location.godownScope == GodownScope.outlet)
              _DetailRow('Assigned Outlet', assignedOutletName),
            _DetailRow('Capacity', _capacityLabel(location.capacity)),
            const _DetailRow('Used', 'Not Available'),
            const _DetailRow('Available', 'Not Available'),
            const _DetailRow('Utilization', 'Not Available'),
            _DetailRow('Address', location.address ?? '—'),
            _DetailRow(
              'Contact Person',
              location.contact?['contactPerson'] as String? ?? '—',
            ),
            _DetailRow(
              'Contact Number',
              location.contact?['phone'] as String? ?? '—',
            ),
            _DetailRow('Email', location.contact?['email'] as String? ?? '—'),
          ] else
            _DetailRow(
              'Parent Storage',
              parent.isEmpty ? 'Root location' : parent.first.name,
            ),
          _DetailRow('Description', location.description ?? '—'),
          _DetailRow('Created At', _date(location.createdAt)),
          _DetailRow('Updated At', _date(location.updatedAt)),
          _DetailRow('Version', '${location.version}'),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (location.type == StorageLocationType.rack
                  ? controller.canUpdateRacks()
                  : controller.canEditStorage())
                OutlinedButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit'),
                ),
              if ((location.type == StorageLocationType.godown
                      ? controller.canCreateRacks()
                      : controller.canCreateStorage()) &&
                  location.type != StorageLocationType.shelf)
                OutlinedButton.icon(
                  onPressed: onAddChild,
                  icon: const Icon(Icons.add),
                  label: Text(
                    location.type == StorageLocationType.godown
                        ? 'Add Rack'
                        : 'Add Shelf',
                  ),
                ),
              if (location.type == StorageLocationType.godown &&
                  controller.canCreateRacks())
                OutlinedButton.icon(
                  onPressed: onAddMultiple,
                  icon: const Icon(Icons.playlist_add),
                  label: const Text('Add Multiple Racks'),
                ),
              if (location.type == StorageLocationType.rack
                  ? controller.canDeactivateRacks()
                  : controller.canEditStorage())
                FilledButton.tonal(
                  onPressed: onStatus,
                  child: Text(location.isActive ? 'Deactivate' : 'Activate'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StorageFormDialog extends StatefulWidget {
  const _StorageFormDialog({
    required this.controller,
    this.parent,
    this.parentLocationType,
    this.parentLocationId,
    this.location,
  });

  final AppController controller;
  final StorageLocationModel? parent, location;
  final String? parentLocationType, parentLocationId;

  @override
  State<_StorageFormDialog> createState() => _StorageFormDialogState();
}

class _StorageFormDialogState extends State<_StorageFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _code = TextEditingController();
  final _description = TextEditingController();
  final _addressFields = {
    for (final key in [
      'addressLine1',
      'addressLine2',
      'city',
      'district',
      'stateCode',
      'postalCode',
      'country',
    ])
      key: TextEditingController(),
  };
  final _contactPerson = TextEditingController();
  final _contactPhone = TextEditingController();
  final _contactEmail = TextEditingController();
  final _maximumCapacity = TextEditingController();
  final _warningPercent = TextEditingController(text: '80');
  final _criticalPercent = TextEditingController(text: '95');
  StorageLocationType _type = StorageLocationType.godown;
  GodownScope? _godownScope = GodownScope.central;
  String? _outletId;
  String _capacityType = 'VOLUME';
  String _capacityUnit = 'CUBIC_METER';
  String? _state;
  bool _capacityEnabled = true;
  String? _parentId;

  static const _states = <String, String>{
    'Andhra Pradesh': '37',
    'Arunachal Pradesh': '12',
    'Assam': '18',
    'Bihar': '10',
    'Chhattisgarh': '22',
    'Goa': '30',
    'Gujarat': '24',
    'Haryana': '06',
    'Himachal Pradesh': '02',
    'Jharkhand': '20',
    'Karnataka': '29',
    'Kerala': '32',
    'Madhya Pradesh': '23',
    'Maharashtra': '27',
    'Manipur': '14',
    'Meghalaya': '17',
    'Mizoram': '15',
    'Nagaland': '13',
    'Odisha': '21',
    'Punjab': '03',
    'Rajasthan': '08',
    'Sikkim': '11',
    'Tamil Nadu': '33',
    'Telangana': '36',
    'Tripura': '16',
    'Uttar Pradesh': '09',
    'Uttarakhand': '05',
    'West Bengal': '19',
    'Delhi': '07',
    'Jammu and Kashmir': '01',
    'Ladakh': '38',
    'Puducherry': '34',
  };

  bool get _editing => widget.location != null;

  @override
  void initState() {
    super.initState();
    _addressFields['country']!.text = 'India';
    final location = widget.location;
    if (location != null) {
      _name.text = location.name;
      _code.text = location.code;
      _description.text = location.description ?? '';
      _type = location.type;
      if (_type == StorageLocationType.godown) {
        final address = location.addressDetails ?? const <String, dynamic>{};
        for (final key in _addressFields.keys) {
          _addressFields[key]!.text = '${address[key] ?? ''}';
        }
        if (_addressFields['country']!.text.isEmpty) {
          _addressFields['country']!.text = 'India';
        }
        if (location.addressDetails == null) {
          _addressFields['addressLine1']!.text = location.address ?? '';
        }
        _state = address['state'] as String?;
        _contactPerson.text = '${location.contact?['contactPerson'] ?? ''}';
        _contactPhone.text = '${location.contact?['phone'] ?? ''}';
        _contactEmail.text = '${location.contact?['email'] ?? ''}';
        _godownScope = location.godownScope;
        _outletId = location.outletId;
        final capacity = location.capacity ?? const <String, dynamic>{};
        _capacityEnabled = capacity['enabled'] == true;
        _capacityType = capacity['capacityType'] as String? ?? 'VOLUME';
        _capacityUnit = capacity['capacityUnit'] as String? ?? 'CUBIC_METER';
        _maximumCapacity.text = '${capacity['maximumCapacity'] ?? ''}';
        _warningPercent.text = '${capacity['warningThresholdPercent'] ?? 80}';
        _criticalPercent.text = '${capacity['criticalThresholdPercent'] ?? 95}';
      } else if (_type == StorageLocationType.rack) {
        final capacity = location.capacity ?? const <String, dynamic>{};
        _capacityEnabled = capacity['enabled'] == true;
        _capacityType = capacity['capacityType'] as String? ?? 'UNITS';
        _capacityUnit =
            capacity['capacityUnit'] as String? ??
            _unitsFor(_capacityType).first;
        _maximumCapacity.text = '${capacity['maximumCapacity'] ?? ''}';
      }
    } else if (widget.parent != null) {
      _parentId = widget.parent!.storageLocationId;
      _type = widget.parent!.type == StorageLocationType.godown
          ? StorageLocationType.rack
          : StorageLocationType.shelf;
    } else if (widget.parentLocationId != null) {
      _parentId = widget.parentLocationId;
      _type = StorageLocationType.rack;
      _capacityEnabled = false;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _description.dispose();
    for (final field in _addressFields.values) {
      field.dispose();
    }
    _contactPerson.dispose();
    _contactPhone.dispose();
    _contactEmail.dispose();
    _maximumCapacity.dispose();
    _warningPercent.dispose();
    _criticalPercent.dispose();
    super.dispose();
  }

  List<StorageLocationModel> get _validParents {
    final requiredType = _type == StorageLocationType.rack
        ? StorageLocationType.godown
        : StorageLocationType.rack;
    return widget.controller.storageLocations
        .where((item) => item.isActive && item.type == requiredType)
        .toList();
  }

  List<String> _unitsFor(String type) => switch (type) {
    'VOLUME' => const ['CUBIC_METER', 'CUBIC_FEET'],
    'WEIGHT' => const ['KG', 'TON'],
    _ => const ['UNIT'],
  };

  String _unitLabel(String unit) => switch (unit) {
    'CUBIC_METER' => 'Cubic Meter',
    'CUBIC_FEET' => 'Cubic Feet',
    _ => unit,
  };

  Widget _percentField(
    TextEditingController field,
    String label,
    int minimum,
    int maximum,
  ) => TextFormField(
    controller: field,
    keyboardType: TextInputType.number,
    decoration: InputDecoration(labelText: label),
    validator: (value) {
      final percent = int.tryParse(value?.trim() ?? '');
      if (percent == null || percent < minimum || percent > maximum) {
        return 'Enter $minimum–$maximum.';
      }
      if (label.startsWith('Critical') &&
          percent <= (int.tryParse(_warningPercent.text) ?? 80)) {
        return 'Must exceed warning.';
      }
      if (label.startsWith('Warning') &&
          percent >= (int.tryParse(_criticalPercent.text) ?? 95)) {
        return 'Must be below critical.';
      }
      return null;
    },
  );

  Future<void> _save() async {
    if (_formKey.currentState?.validate() != true) return;
    final controller = widget.controller;
    final isGodown = _type == StorageLocationType.godown;
    final address = isGodown
        ? <String, dynamic>{
            'addressLine1': _addressFields['addressLine1']!.text,
            'addressLine2': _addressFields['addressLine2']!.text,
            'city': _addressFields['city']!.text,
            'district': _addressFields['district']!.text,
            'state': _state ?? '',
            'stateCode': _state == null ? '' : _states[_state]!,
            'postalCode': _addressFields['postalCode']!.text,
            'country': _addressFields['country']!.text,
          }
        : null;
    final capacity = isGodown
        ? _capacityEnabled
              ? <String, dynamic>{
                  'enabled': true,
                  'capacityType': _capacityType,
                  'maximumCapacity': num.parse(_maximumCapacity.text.trim())
                      .toDouble(),
                  'capacityUnit': _capacityUnit,
                  'warningThresholdPercent':
                      int.tryParse(_warningPercent.text.trim()) ?? 80,
                  'criticalThresholdPercent':
                      int.tryParse(_criticalPercent.text.trim()) ?? 95,
                }
              : const <String, dynamic>{'enabled': false}
        : _type == StorageLocationType.rack
        ? _capacityEnabled
              ? <String, dynamic>{
                  'enabled': true,
                  'capacityType': _capacityType,
                  'maximumCapacity': double.parse(_maximumCapacity.text.trim()),
                  'capacityUnit': _capacityUnit,
                }
              : const <String, dynamic>{
                  'enabled': false,
                  'capacityType': null,
                  'maximumCapacity': null,
                  'capacityUnit': null,
                }
        : null;
    final contact = isGodown
        ? <String, dynamic>{
            'contactPerson': _contactPerson.text,
            'phone': _contactPhone.text,
            'email': _contactEmail.text,
          }
        : null;
    final saved = _editing
        ? await controller.updateStorageLocation(
            location: widget.location!,
            name: _name.text,
            code: isGodown || _type == StorageLocationType.rack
                ? null
                : _code.text,
            description: _description.text,
            addressDetails: address,
            capacity: capacity,
            contact: contact,
            godownScope: _godownScope,
            outletId: _godownScope == GodownScope.outlet ? _outletId : null,
          )
        : await controller.createStorageLocation(
            type: _type,
            parentLocationId: _type == StorageLocationType.godown
                ? null
                : widget.parentLocationId ?? _parentId,
            parentLocationType: widget.parentLocationType ?? 'GODOWN',
            name: _name.text,
            code: isGodown || _type == StorageLocationType.rack
                ? null
                : _code.text,
            description: _description.text,
            addressDetails: address,
            capacity: capacity,
            contact: contact,
            godownScope: _godownScope,
            outletId: _godownScope == GodownScope.outlet ? _outletId : null,
          );
    if (saved && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final location = widget.location;
    final business = widget.controller.businesses.where(
      (item) => item.businessId == widget.controller.appContext?.businessId,
    );
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) => AlertDialog(
        title: Text(
          _editing
              ? 'Edit ${location!.type.label}'
              : _type == StorageLocationType.godown
              ? 'Add Godown'
              : 'Add ${_type.label}',
        ),
        content: SizedBox(
          width: 460,
          child: Form(
            key: _formKey,
            child: ListView(
              shrinkWrap: true,
              children: [
                if (_type == StorageLocationType.godown)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Business'),
                    subtitle: Text(
                      business.isEmpty
                          ? 'Selected Business'
                          : business.first.businessName,
                    ),
                  ),
                if (_editing)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Location Type'),
                    subtitle: Text(location!.type.label),
                  ),
                if (!_editing &&
                    _type != StorageLocationType.godown &&
                    widget.parent == null &&
                    widget.parentLocationId == null) ...[
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue:
                        _validParents.any(
                          (item) => item.storageLocationId == _parentId,
                        )
                        ? _parentId
                        : null,
                    decoration: InputDecoration(
                      labelText: _type == StorageLocationType.rack
                          ? 'Parent Godown'
                          : 'Parent Rack',
                    ),
                    items: [
                      for (final parent in _validParents)
                        DropdownMenuItem(
                          value: parent.storageLocationId,
                          child: Text('${parent.name} (${parent.code})'),
                        ),
                    ],
                    validator: (value) => value == null
                        ? 'Select a parent storage location.'
                        : null,
                    onChanged: widget.parent == null
                        ? (value) => setState(() => _parentId = value)
                        : null,
                  ),
                ],
                const SizedBox(height: 10),
                TextFormField(
                  controller: _name,
                  maxLength: 100,
                  decoration: InputDecoration(
                    labelText: _type == StorageLocationType.godown
                        ? 'Godown Name'
                        : '${_type.label} Name',
                  ),
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    return text.length < 2 || text.length > 100
                        ? 'Name is required (2–100 characters).'
                        : null;
                  },
                ),
                if (_type == StorageLocationType.godown)
                  InputDecorator(
                    decoration: const InputDecoration(labelText: 'Godown Code'),
                    child: Text(
                      _editing ? location!.code : 'Auto-generated on save',
                    ),
                  )
                else if (_type == StorageLocationType.shelf)
                  TextFormField(
                    controller: _code,
                    maxLength: 30,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      labelText: '${_type.label} Code',
                    ),
                    validator: (value) {
                      final text = value?.trim() ?? '';
                      return text.length < 2 || text.length > 30
                          ? 'Enter a code between 2 and 30 characters.'
                          : null;
                    },
                  ),
                if (_type == StorageLocationType.rack)
                  InputDecorator(
                    decoration: const InputDecoration(labelText: 'Rack Code'),
                    child: Text(
                      _editing ? location!.code : 'Auto-generated on save',
                    ),
                  ),
                if (_type == StorageLocationType.rack)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Capacity Tracking'),
                    value: _capacityEnabled,
                    onChanged: (value) =>
                        setState(() => _capacityEnabled = value),
                  ),
                if (_type == StorageLocationType.rack && _capacityEnabled) ...[
                  DropdownButtonFormField<String>(
                    initialValue: _capacityType,
                    decoration: const InputDecoration(
                      labelText: 'Capacity Type',
                    ),
                    items: const [
                      DropdownMenuItem(value: 'VOLUME', child: Text('Volume')),
                      DropdownMenuItem(value: 'WEIGHT', child: Text('Weight')),
                      DropdownMenuItem(value: 'UNITS', child: Text('Units')),
                    ],
                    onChanged: (value) => setState(() {
                      _capacityType = value ?? 'UNITS';
                      _capacityUnit = _unitsFor(_capacityType).first;
                    }),
                  ),
                  TextFormField(
                    controller: _maximumCapacity,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Maximum Capacity',
                    ),
                    validator: (value) =>
                        _type == StorageLocationType.rack &&
                            _capacityEnabled &&
                            ((double.tryParse(value ?? '') ?? 0) <= 0)
                        ? 'Enter a capacity greater than zero.'
                        : null,
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: _capacityUnit,
                    decoration: const InputDecoration(
                      labelText: 'Capacity Unit',
                    ),
                    items: [
                      for (final unit in _unitsFor(_capacityType))
                        DropdownMenuItem(
                          value: unit,
                          child: Text(_unitLabel(unit)),
                        ),
                    ],
                    onChanged: (value) =>
                        setState(() => _capacityUnit = value ?? _capacityUnit),
                  ),
                ],
                if (_type == StorageLocationType.godown) ...[
                  const SizedBox(height: 14),
                  DropdownButtonFormField<GodownScope>(
                    initialValue: _godownScope,
                    decoration: const InputDecoration(
                      labelText: 'Godown Scope *',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: GodownScope.central,
                        child: Text('Central Godown'),
                      ),
                      DropdownMenuItem(
                        value: GodownScope.outlet,
                        child: Text('Outlet Godown'),
                      ),
                    ],
                    validator: (value) =>
                        value == null ? 'Select a scope.' : null,
                    onChanged: (value) => setState(() {
                      _godownScope = value;
                      if (value != GodownScope.outlet) _outletId = null;
                    }),
                  ),
                  if (_godownScope == GodownScope.outlet) ...[
                    const SizedBox(height: 12),
                    if (widget.controller.outlets.isEmpty)
                      const Text(
                        'No active Outlets are available in this Business.',
                      ),
                    DropdownButtonFormField<String>(
                      initialValue:
                          widget.controller.outlets.any(
                            (outlet) => outlet.outletId == _outletId,
                          )
                          ? _outletId
                          : null,
                      decoration: const InputDecoration(
                        labelText: 'Assigned Outlet *',
                      ),
                      items: [
                        for (final outlet in widget.controller.outlets)
                          DropdownMenuItem(
                            value: outlet.outletId,
                            child: Text(outlet.outletName),
                          ),
                      ],
                      validator: (value) => value == null
                          ? 'Select an active Outlet from this Business.'
                          : null,
                      onChanged: (value) => setState(() => _outletId = value),
                    ),
                  ],
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Capacity Tracking'),
                    value: _capacityEnabled,
                    onChanged: (value) =>
                        setState(() => _capacityEnabled = value),
                  ),
                  if (_capacityEnabled) ...[
                    DropdownButtonFormField<String>(
                      initialValue: _capacityType,
                      decoration: const InputDecoration(
                        labelText: 'Capacity Type *',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'VOLUME',
                          child: Text('Volume'),
                        ),
                        DropdownMenuItem(
                          value: 'WEIGHT',
                          child: Text('Weight'),
                        ),
                        DropdownMenuItem(value: 'UNITS', child: Text('Units')),
                      ],
                      onChanged: (value) => setState(() {
                        _capacityType = value ?? 'VOLUME';
                        _capacityUnit = _unitsFor(_capacityType).first;
                      }),
                    ),
                    TextFormField(
                      controller: _maximumCapacity,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Maximum Capacity *',
                      ),
                      validator: (value) {
                        final number = double.tryParse(value?.trim() ?? '');
                        return number == null || number <= 0
                            ? 'Enter a capacity greater than zero.'
                            : null;
                      },
                    ),
                    DropdownButtonFormField<String>(
                      initialValue:
                          _unitsFor(_capacityType).contains(_capacityUnit)
                          ? _capacityUnit
                          : _unitsFor(_capacityType).first,
                      decoration: const InputDecoration(
                        labelText: 'Capacity Unit *',
                      ),
                      items: [
                        for (final unit in _unitsFor(_capacityType))
                          DropdownMenuItem(
                            value: unit,
                            child: Text(_unitLabel(unit)),
                          ),
                      ],
                      onChanged: (value) => setState(() {
                        if (value != null) _capacityUnit = value;
                      }),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: _percentField(
                            _warningPercent,
                            'Warning At %',
                            1,
                            100,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _percentField(
                            _criticalPercent,
                            'Critical At %',
                            2,
                            100,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _contactPerson,
                    decoration: const InputDecoration(
                      labelText: 'Contact Person',
                    ),
                  ),
                  TextFormField(
                    controller: _contactPhone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Contact Number',
                    ),
                    validator: (value) => (value?.trim().isEmpty ?? true)
                        ? null
                        : AppValidators.indianPhone(value),
                  ),
                  TextFormField(
                    controller: _contactEmail,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email'),
                    validator: (value) => (value?.trim().isEmpty ?? true)
                        ? null
                        : AppValidators.email(value),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _addressFields['addressLine1'],
                    decoration: const InputDecoration(
                      labelText: 'Address Line 1 *',
                    ),
                    validator: (value) =>
                        AppValidators.required(value, 'address line 1'),
                  ),
                  TextFormField(
                    controller: _addressFields['addressLine2'],
                    decoration: const InputDecoration(
                      labelText: 'Address Line 2',
                    ),
                  ),
                  TextFormField(
                    controller: _addressFields['city'],
                    decoration: const InputDecoration(labelText: 'City *'),
                    validator: (value) => AppValidators.required(value, 'city'),
                  ),
                  TextFormField(
                    controller: _addressFields['district'],
                    decoration: const InputDecoration(labelText: 'District'),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: _state,
                    decoration: const InputDecoration(labelText: 'State *'),
                    items: [
                      for (final state in _states.keys)
                        DropdownMenuItem(value: state, child: Text(state)),
                    ],
                    validator: (value) =>
                        value == null ? 'Select a state.' : null,
                    onChanged: (value) => setState(() => _state = value),
                  ),
                  TextFormField(
                    controller: _addressFields['postalCode'],
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'PIN Code *'),
                    validator: (value) {
                      final pin = value?.trim() ?? '';
                      return RegExp(r'^\d{6}$').hasMatch(pin)
                          ? null
                          : 'Enter a valid 6-digit PIN code.';
                    },
                  ),
                  TextFormField(
                    controller: _addressFields['country'],
                    decoration: const InputDecoration(labelText: 'Country *'),
                    validator: (value) =>
                        AppValidators.required(value, 'country'),
                  ),
                ],
                TextFormField(
                  controller: _description,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Description'),
                ),
                if (widget.controller.storageError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      widget.controller.storageError!,
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
            onPressed: widget.controller.storageSaving
                ? null
                : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: widget.controller.storageSaving ? null : _save,
            child: widget.controller.storageSaving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_editing ? 'Save Changes' : 'Save'),
          ),
        ],
      ),
    );
  }
}

class _FilterDropdown extends StatelessWidget {
  const _FilterDropdown({
    required this.label,
    required this.value,
    required this.values,
    required this.onChanged,
  });

  final String label, value;
  final List<String> values;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 170,
    child: DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(labelText: label, isDense: true),
      items: [
        for (final item in values)
          DropdownMenuItem(
            value: item,
            child: Text(item == 'ALL' ? 'All' : item),
          ),
      ],
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
    ),
  );
}

class _StorageEmptyState extends StatelessWidget {
  const _StorageEmptyState({
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final String title, message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warehouse_outlined, size: 44),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(message, textAlign: TextAlign.center),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    ),
  );
}

class _StorageDetailsEmpty extends StatelessWidget {
  const _StorageDetailsEmpty();

  @override
  Widget build(BuildContext context) => const Card(
    child: Center(child: Text('Select a storage location to view details.')),
  );
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) => Chip(
    label: Text(active ? 'Active' : 'Inactive'),
    backgroundColor: active ? Colors.green.shade100 : Colors.red.shade100,
    labelStyle: TextStyle(
      color: active ? Colors.green.shade900 : Colors.red.shade900,
    ),
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, this.value);
  final String label, value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 118,
          child: Text(label, style: Theme.of(context).textTheme.labelLarge),
        ),
        Expanded(child: Text(value)),
      ],
    ),
  );
}

String _date(DateTime? value) => value == null
    ? '—'
    : '${value.toLocal().year.toString().padLeft(4, '0')}-'
          '${value.toLocal().month.toString().padLeft(2, '0')}-'
          '${value.toLocal().day.toString().padLeft(2, '0')} '
          '${value.toLocal().hour.toString().padLeft(2, '0')}:'
          '${value.toLocal().minute.toString().padLeft(2, '0')}';

String _capacityLabel(Map<String, dynamic>? capacity) {
  if (capacity?['enabled'] != true) return 'Not tracked';
  final maximum = capacity?['maximumCapacity'];
  final unit = capacity?['capacityUnit'] as String? ?? '';
  final label = switch (unit) {
    'CUBIC_METER' => 'm³',
    'CUBIC_FEET' => 'ft³',
    'KG' => 'kg',
    'TON' => 'ton',
    'UNIT' => 'units',
    _ => unit,
  };
  return maximum == null ? 'Not configured' : '$maximum $label';
}

class OutletRackManagementPage extends StatefulWidget {
  const OutletRackManagementPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<OutletRackManagementPage> createState() =>
      _OutletRackManagementPageState();
}

class _OutletRackManagementPageState extends State<OutletRackManagementPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.controller.loadStorageLocations();
    });
  }

  Future<void> _addRack() async {
    final outlet = widget.controller.currentOutlet;
    if (outlet == null) return;
    await showDialog<bool>(
      context: context,
      builder: (_) => _StorageFormDialog(
        controller: widget.controller,
        parentLocationType: 'OUTLET',
        parentLocationId: outlet.outletId,
      ),
    );
  }

  Future<void> _editRack(StorageLocationModel rack) async {
    await showDialog<bool>(
      context: context,
      builder: (_) =>
          _StorageFormDialog(controller: widget.controller, location: rack),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      final outlet = controller.currentOutlet;
      if (outlet == null) {
        return const Center(
          child: Text('Select an Outlet to manage its racks.'),
        );
      }
      final racks =
          controller.storageLocations
              .where(
                (location) =>
                    location.type == StorageLocationType.rack &&
                    location.parentLocationType == 'OUTLET' &&
                    location.parentLocationId == outlet.outletId,
              )
              .toList()
            ..sort((a, b) => (a.rackNumber ?? 0).compareTo(b.rackNumber ?? 0));

      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 760;
                final title = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Racks',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${outlet.outletName} · ${outlet.outletCode ?? outlet.outletId}',
                    ),
                  ],
                );
                final actions = Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: compact ? WrapAlignment.end : WrapAlignment.start,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    IconButton(
                      tooltip: 'Refresh racks',
                      onPressed: controller.storageLoading
                          ? null
                          : controller.loadStorageLocations,
                      icon: const Icon(Icons.refresh),
                    ),
                    if (controller.canCreateRacks())
                      FilledButton.icon(
                        onPressed: controller.storageSaving ? null : _addRack,
                        icon: const Icon(Icons.add),
                        label: const Text('Add Rack'),
                      ),
                  ],
                );
                return compact
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [title, const SizedBox(height: 10), actions],
                      )
                    : Row(
                        children: [
                          Expanded(child: title),
                          actions,
                        ],
                      );
              },
            ),
            if (controller.storageError != null) ...[
              const SizedBox(height: 12),
              MaterialBanner(
                content: Text(controller.storageError!),
                actions: [
                  TextButton(
                    onPressed: controller.loadStorageLocations,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Expanded(
              child: controller.storageLoading
                  ? const Center(child: CircularProgressIndicator())
                  : racks.isEmpty
                  ? _StorageEmptyState(
                      title: 'No Outlet Racks',
                      message:
                          'Add a rack to ${outlet.outletName} to organize its stock.',
                      actionLabel: controller.canCreateRacks()
                          ? 'Add Rack'
                          : null,
                      onAction: controller.canCreateRacks() ? _addRack : null,
                    )
                  : Card(
                      clipBehavior: Clip.antiAlias,
                      child: ListView.separated(
                        itemCount: racks.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final rack = racks[index];
                          return ListTile(
                            leading: const CircleAvatar(
                              child: Icon(Icons.view_list_outlined),
                            ),
                            title: Text('${rack.name} · ${rack.code}'),
                            subtitle: Text(
                              'Outlet: ${rack.parentLocationName ?? outlet.outletName} '
                              '(${rack.parentLocationCode ?? outlet.outletCode ?? outlet.outletId}) · '
                              '${rack.status.value} · Capacity: ${_capacityLabel(rack.capacity)}',
                            ),
                            trailing: Wrap(
                              spacing: 4,
                              children: [
                                if (controller.canUpdateRacks())
                                  IconButton(
                                    tooltip: 'Edit rack',
                                    onPressed: () => _editRack(rack),
                                    icon: const Icon(Icons.edit_outlined),
                                  ),
                                if (controller.canDeactivateRacks())
                                  IconButton(
                                    tooltip: rack.isActive
                                        ? 'Deactivate rack'
                                        : 'Activate rack',
                                    onPressed: () =>
                                        controller.setStorageLocationActive(
                                          rack,
                                          !rack.isActive,
                                        ),
                                    icon: Icon(
                                      rack.isActive
                                          ? Icons.toggle_on
                                          : Icons.toggle_off,
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      );
    },
  );
}

Future<void> showOutletRackManagement(
  BuildContext context,
  AppController controller,
  String outletId,
  String outletName,
) async {
  await controller.loadStorageLocations();
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (_) => _OutletRackDialog(
      controller: controller,
      outletId: outletId,
      outletName: outletName,
    ),
  );
}

class _OutletRackDialog extends StatefulWidget {
  const _OutletRackDialog({
    required this.controller,
    required this.outletId,
    required this.outletName,
  });
  final AppController controller;
  final String outletId, outletName;

  @override
  State<_OutletRackDialog> createState() => _OutletRackDialogState();
}

class _OutletRackDialogState extends State<_OutletRackDialog> {
  List<StorageLocationModel> get _racks =>
      widget.controller.storageLocations
          .where(
            (item) =>
                item.type == StorageLocationType.rack &&
                item.parentLocationType == 'OUTLET' &&
                item.parentLocationId == widget.outletId,
          )
          .toList()
        ..sort((a, b) => (a.rackNumber ?? 0).compareTo(b.rackNumber ?? 0));

  Future<void> _createOne() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _StorageFormDialog(
        controller: widget.controller,
        parentLocationType: 'OUTLET',
        parentLocationId: widget.outletId,
      ),
    );
    if (saved == true && mounted) setState(() {});
  }

  Future<void> _createMany() async {
    final count = TextEditingController();
    final value = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Multiple Racks'),
        content: TextField(
          controller: count,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Number of Racks',
            hintText: '1–100',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final parsed = int.tryParse(count.text.trim());
              if (parsed != null && parsed > 0 && parsed <= 100)
                Navigator.pop(context, parsed);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
    count.dispose();
    if (value == null || !mounted) return;
    final saved = await widget.controller.createMultipleRacks(
      parentLocationType: 'OUTLET',
      parentLocationId: widget.outletId,
      count: value,
    );
    if (saved && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) => AlertDialog(
      title: Text('${widget.outletName} · Racks'),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.controller.storageError != null)
              MaterialBanner(
                content: Text(widget.controller.storageError!),
                actions: [
                  TextButton(
                    onPressed: widget.controller.loadStorageLocations,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            if (widget.controller.storageSaving)
              const LinearProgressIndicator(),
            Row(
              children: [
                Text(
                  'Total: ${_racks.length}  ·  Active: ${_racks.where((rack) => rack.isActive).length}',
                ),
                const Spacer(),
                if (widget.controller.canCreateRacks())
                  IconButton(
                    tooltip: 'Add Rack',
                    onPressed: _createOne,
                    icon: const Icon(Icons.add),
                  ),
                if (widget.controller.canCreateRacks())
                  IconButton(
                    tooltip: 'Add Multiple Racks',
                    onPressed: _createMany,
                    icon: const Icon(Icons.playlist_add),
                  ),
              ],
            ),
            const Divider(),
            if (_racks.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text('No Racks in this Outlet yet.'),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final rack in _racks)
                      ListTile(
                        title: Text('${rack.code} · ${rack.name}'),
                        subtitle: Text(
                          'Capacity: ${_capacityLabel(rack.capacity)} · ${rack.status.value}',
                        ),
                        trailing: Wrap(
                          children: [
                            if (widget.controller.canUpdateRacks())
                              IconButton(
                                tooltip: 'Edit',
                                onPressed: () async {
                                  final saved = await showDialog<bool>(
                                    context: context,
                                    builder: (_) => _StorageFormDialog(
                                      controller: widget.controller,
                                      location: rack,
                                    ),
                                  );
                                  if (saved == true && mounted) setState(() {});
                                },
                                icon: const Icon(Icons.edit_outlined),
                              ),
                            if (widget.controller.canDeactivateRacks())
                              IconButton(
                                tooltip: rack.isActive
                                    ? 'Deactivate'
                                    : 'Activate',
                                onPressed: () async {
                                  final saved = await widget.controller
                                      .setStorageLocationActive(
                                        rack,
                                        !rack.isActive,
                                      );
                                  if (saved && mounted) setState(() {});
                                },
                                icon: Icon(
                                  rack.isActive
                                      ? Icons.toggle_on
                                      : Icons.toggle_off,
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}
