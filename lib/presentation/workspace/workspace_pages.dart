import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/utils/validators.dart';
import '../../data/models/business_model.dart';
import '../../data/models/business_sub_type_model.dart';
import '../../data/models/business_type_model.dart';
import '../../data/models/outlet_model.dart';
import '../../l10n/app_localizations.dart';
import '../app_controller.dart';
import '../widgets/logout_dialog.dart';

class BusinessSelectorPage extends StatelessWidget {
  const BusinessSelectorPage({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final owner = controller.user?.accountType == 'owner';
    final compact = MediaQuery.sizeOf(context).width < 600;
    return _WorkspaceScaffold(
      controller: controller,
      icon: Icons.business_rounded,
      title:
          l10n?.businessDashboardTitle ?? 'Business & Organization Workspace',
      subtitle: owner
          ? (l10n?.businessDashboardSubtitle ??
                'Choose a business to continue. Your businesses stay separate.')
          : (l10n?.businessDashboardSubtitle ??
                'Choose an authorized business to continue.'),
      actions: [
        if (owner)
          compact
              ? IconButton(
                  tooltip: l10n?.addBusiness ?? 'Add business',
                  onPressed: controller.openCreateBusiness,
                  icon: const Icon(Icons.add_business_outlined),
                )
              : FilledButton.icon(
                  onPressed: controller.openCreateBusiness,
                  icon: const Icon(Icons.add_business_outlined),
                  label: Text(l10n?.addBusiness ?? 'Add business'),
                ),
        compact
            ? IconButton(
                tooltip: l10n?.logout ?? 'Log out',
                onPressed: () =>
                    showLogoutConfirmationDialog(context, controller),
                icon: const Icon(Icons.logout),
              )
            : TextButton.icon(
                onPressed: () =>
                    showLogoutConfirmationDialog(context, controller),
                icon: const Icon(Icons.logout),
                label: Text(l10n?.logout ?? 'Log out'),
              ),
      ],
      child: controller.businesses.isEmpty
          ? _EmptyState(
              icon: Icons.business_outlined,
              title: l10n?.noBusinessesFound ?? 'No businesses found',
              message:
                  l10n?.noBusinessesFoundSubtitle ??
                  'There are no active businesses available for this account.',
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth > 940
                    ? 3
                    : constraints.maxWidth > 600
                    ? 2
                    : 1;
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    mainAxisExtent: 174,
                  ),
                  itemCount: controller.businesses.length,
                  itemBuilder: (context, index) => _BusinessCard(
                    business: controller.businesses[index],
                    onTap: () => controller.selectBusiness(
                      controller.businesses[index].businessId,
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class OutletSelectorPage extends StatelessWidget {
  const OutletSelectorPage({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final canCreateOutlet = controller.canCreateOutlet();
    final compact = MediaQuery.sizeOf(context).width < 600;
    return _WorkspaceScaffold(
      controller: controller,
      icon: Icons.storefront_rounded,
      title: l10n?.outletDashboardTitle ?? 'Outlet & Store Workspace',
      subtitle: l10n?.outletDashboardSubtitle ?? 'Choose an outlet to continue store billing, stock & inventory operations.',
      actions: [
        compact
            ? IconButton(
                tooltip: l10n?.switchBusiness ?? 'Switch business',
                onPressed: controller.openBusinessSelector,
                icon: const Icon(Icons.swap_horiz),
              )
            : TextButton.icon(
                onPressed: controller.openBusinessSelector,
                icon: const Icon(Icons.swap_horiz),
                label: Text(l10n?.switchBusiness ?? 'Switch business'),
              ),
        if (canCreateOutlet)
          compact
              ? IconButton(
                  tooltip: l10n?.addOutlet ?? 'Add outlet',
                  onPressed: controller.openCreateOutlet,
                  icon: const Icon(Icons.add_business_outlined),
                )
              : FilledButton.icon(
                  onPressed: controller.openCreateOutlet,
                  icon: const Icon(Icons.add_business_outlined),
                  label: Text(l10n?.addOutlet ?? 'Add outlet'),
                ),
        compact
            ? IconButton(
                tooltip: l10n?.logout ?? 'Log out',
                onPressed: () =>
                    showLogoutConfirmationDialog(context, controller),
                icon: const Icon(Icons.logout),
              )
            : TextButton.icon(
                onPressed: () =>
                    showLogoutConfirmationDialog(context, controller),
                icon: const Icon(Icons.logout),
                label: Text(l10n?.logout ?? 'Log out'),
              ),
      ],
      child: controller.outlets.isEmpty
          ? _EmptyState(
              icon: Icons.store_outlined,
              title: l10n?.noOutletsFound ?? 'No Outlet Available',
              message: l10n?.noOutletsFoundSubtitle ?? 'This Business has no active Outlets yet. Add an Outlet to continue.',
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth > 940
                    ? 3
                    : constraints.maxWidth > 600
                    ? 2
                    : 1;
                final textScale =
                    MediaQuery.textScalerOf(context).scale(16) / 16;
                final cardExtent = (200 + ((textScale - 1).clamp(0, 2) * 72))
                    .toDouble();
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    mainAxisExtent: cardExtent,
                  ),
                  itemCount: controller.outlets.length,
                  itemBuilder: (context, index) => _OutletCard(
                    outlet: controller.outlets[index],
                    onTap: () => controller.selectOutlet(
                      controller.outlets[index].outletId,
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class CreateBusinessPage extends StatefulWidget {
  const CreateBusinessPage({super.key, required this.controller});
  final AppController controller;
  @override
  State<CreateBusinessPage> createState() => _CreateBusinessPageState();
}

class _CreateBusinessPageState extends State<CreateBusinessPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(), _email = TextEditingController();
  final _phone = TextEditingController(), _gstin = TextEditingController();
  final _address = TextEditingController();
  String? _typeId;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    if (widget.controller.businessTypes.isEmpty &&
        !widget.controller.businessTypesLoading) {
      widget.controller.loadBusinessTypes();
    }
    for (final field in [_name, _email, _phone, _gstin, _address]) {
      field.addListener(() => _dirty = true);
    }
  }

  @override
  void dispose() {
    for (final field in [_name, _email, _phone, _gstin, _address]) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> _exit() async {
    if (widget.controller.businessSaving) return;
    if (_dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Discard Changes?'),
          content: const Text('Your entered information will be lost.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Discard'),
            ),
          ],
        ),
      );
      if (discard != true) return;
    }
    widget.controller.cancelCreation();
  }

  Future<void> _pasteGstin() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted || data?.text == null) return;
    _gstin.text = AppValidators.normalizeGstin(data!.text!);
    setState(() => _dirty = true);
  }

  void _submit() {
    if (_form.currentState?.validate() != true || _typeId == null) return;
    widget.controller.createBusiness(
      businessName: _name.text,
      businessTypeId: _typeId!,
      email: _email.text,
      phone: _phone.text,
      address: _address.text,
      gstin: _gstin.text,
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _exit();
    },
    child: _CreationScaffold(
      title: 'Create your business',
      subtitle:
          'Add the business profile. You can create more businesses later.',
      error: widget.controller.error,
      busy: widget.controller.businessSaving,
      onBack: _exit,
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _name,
              enableInteractiveSelection: true,
              decoration: const InputDecoration(labelText: 'Business Name *'),
              validator: AppValidators.businessName,
            ),
            const SizedBox(height: 14),
            _BusinessTypeDropdown(
              types: widget.controller.businessTypes,
              value: _typeId,
              loading: widget.controller.businessTypesLoading,
              error: widget.controller.businessTypesError,
              retry: widget.controller.loadBusinessTypes,
              onChanged: (value) => setState(() {
                _dirty = true;
                _typeId = value;
              }),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _email,
              enableInteractiveSelection: true,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Business Email *'),
              validator: AppValidators.email,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _phone,
              enableInteractiveSelection: true,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Business Contact Number *',
              ),
              validator: AppValidators.indianPhone,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _gstin,
              enableInteractiveSelection: true,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: 'GSTIN (optional)',
                suffixIcon: IconButton(
                  tooltip: 'Paste GSTIN',
                  onPressed: _pasteGstin,
                  icon: const Icon(Icons.content_paste),
                ),
              ),
              validator: AppValidators.gstin,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _address,
              enableInteractiveSelection: true,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Business Address *',
              ),
              validator: (value) =>
                  AppValidators.required(value, 'business address'),
            ),
            const SizedBox(height: 22),
            FilledButton(
              onPressed:
                  widget.controller.businessSaving ||
                      widget.controller.businessTypesLoading ||
                      widget.controller.businessTypesError != null
                  ? null
                  : _submit,
              child: widget.controller.businessSaving
                  ? const CircularProgressIndicator()
                  : const Text('Create Business'),
            ),
          ],
        ),
      ),
    ),
  );
}

class CreateOutletPage extends StatefulWidget {
  const CreateOutletPage({super.key, required this.controller});
  final AppController controller;
  @override
  State<CreateOutletPage> createState() => _CreateOutletPageState();
}

class _CreateOutletPageState extends State<CreateOutletPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(), _phone = TextEditingController();
  final _gstin = TextEditingController(), _address = TextEditingController();
  String? _typeId;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    if (widget.controller.businessSubTypes.isEmpty &&
        !widget.controller.businessSubTypesLoading) {
      widget.controller.loadBusinessSubTypes();
    }
    for (final field in [_name, _phone, _gstin, _address]) {
      field.addListener(() => _dirty = true);
    }
  }

  @override
  void dispose() {
    for (final field in [_name, _phone, _gstin, _address]) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> _exit() async {
    if (widget.controller.outletSaving) return;
    if (_dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Discard Changes?'),
          content: const Text('Your entered information will be lost.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Discard'),
            ),
          ],
        ),
      );
      if (discard != true) return;
    }
    widget.controller.cancelCreation();
  }

  Future<void> _pasteGstin() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted || data?.text == null) return;
    _gstin.text = AppValidators.normalizeGstin(data!.text!);
    setState(() => _dirty = true);
  }

  void _submit() {
    if (_form.currentState?.validate() != true || _typeId == null) return;
    widget.controller.createOutlet(
      outletName: _name.text,
      outletTypeId: _typeId!,
      address: _address.text,
      contactNumber: _phone.text,
      gstin: _gstin.text,
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _exit();
    },
    child: _CreationScaffold(
      title: 'Add Outlet',
      subtitle: 'This outlet belongs to the selected business.',
      error: widget.controller.error,
      busy: widget.controller.outletSaving,
      onBack: _exit,
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _name,
              enableInteractiveSelection: true,
              decoration: const InputDecoration(labelText: 'Outlet Name *'),
              validator: (value) =>
                  AppValidators.required(value, 'outlet name'),
            ),
            const SizedBox(height: 14),
            const Text('Outlet Code: Auto-generated when saved'),
            const SizedBox(height: 14),
            _OutletTypeDropdown(
              types: widget.controller.businessSubTypes,
              value: _typeId,
              loading: widget.controller.businessSubTypesLoading,
              error: widget.controller.businessSubTypesError,
              retry: widget.controller.loadBusinessSubTypes,
              onChanged: (value) => setState(() {
                _dirty = true;
                _typeId = value;
              }),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _phone,
              enableInteractiveSelection: true,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Contact Number *'),
              validator: AppValidators.indianPhone,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _gstin,
              enableInteractiveSelection: true,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: 'GSTIN (optional)',
                suffixIcon: IconButton(
                  tooltip: 'Paste GSTIN',
                  onPressed: _pasteGstin,
                  icon: const Icon(Icons.content_paste),
                ),
              ),
              validator: AppValidators.gstin,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _address,
              enableInteractiveSelection: true,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Outlet Address *'),
              validator: (value) =>
                  AppValidators.required(value, 'outlet address'),
            ),
            const SizedBox(height: 22),
            FilledButton(
              onPressed:
                  widget.controller.outletSaving ||
                      widget.controller.businessSubTypesLoading ||
                      widget.controller.businessSubTypesError != null
                  ? null
                  : _submit,
              child: widget.controller.outletSaving
                  ? const CircularProgressIndicator()
                  : const Text('Save Outlet'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _BusinessTypeDropdown extends StatelessWidget {
  const _BusinessTypeDropdown({
    required this.types,
    required this.value,
    required this.loading,
    required this.error,
    required this.retry,
    required this.onChanged,
  });
  final List<BusinessTypeModel> types;
  final String? value;
  final bool loading;
  final String? error;
  final Future<void> Function() retry;
  final ValueChanged<String?> onChanged;
  @override
  Widget build(BuildContext context) {
    if (loading) return const LinearProgressIndicator();
    if (error != null) {
      return Row(
        children: [
          Expanded(child: Text(error!)),
          TextButton(onPressed: retry, child: const Text('Retry')),
        ],
      );
    }
    if (types.isEmpty) {
      return const Text('No active business types are available.');
    }
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: const InputDecoration(labelText: 'Business Type *'),
      items: [
        for (final type in types)
          DropdownMenuItem(value: type.id, child: Text(type.name)),
      ],
      validator: (value) => value == null ? 'Select a business type.' : null,
      onChanged: onChanged,
    );
  }
}

class _OutletTypeDropdown extends StatelessWidget {
  const _OutletTypeDropdown({
    required this.types,
    required this.value,
    required this.loading,
    required this.error,
    required this.retry,
    required this.onChanged,
  });
  final List<BusinessSubTypeModel> types;
  final String? value;
  final bool loading;
  final String? error;
  final Future<void> Function() retry;
  final ValueChanged<String?> onChanged;
  @override
  Widget build(BuildContext context) {
    if (loading) return const LinearProgressIndicator();
    if (error != null) {
      return Row(
        children: [
          Expanded(child: Text(error!)),
          TextButton(onPressed: retry, child: const Text('Retry')),
        ],
      );
    }
    if (types.isEmpty) {
      return const Text(
        'No active outlet types are configured for this business type.',
      );
    }
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: const InputDecoration(
        labelText: 'Outlet Type / Business Sub-Type *',
      ),
      items: [
        for (final type in types)
          DropdownMenuItem(value: type.id, child: Text(type.name)),
      ],
      validator: (value) => value == null ? 'Select an outlet type.' : null,
      onChanged: onChanged,
    );
  }
}

class _CreationScaffold extends StatelessWidget {
  const _CreationScaffold({
    required this.title,
    required this.subtitle,
    required this.child,
    required this.error,
    required this.busy,
    required this.onBack,
  });
  final String title, subtitle;
  final Widget child;
  final String error;
  final bool busy;
  final VoidCallback onBack;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('NubiBill Business ERP'),
      leading: IconButton(
        onPressed: busy ? null : onBack,
        icon: const Icon(Icons.arrow_back),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : onBack,
          child: const Text('Cancel'),
        ),
      ],
    ),
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(title, style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(subtitle),
                  const SizedBox(height: 24),
                  child,
                  if (error.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(
                      error,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _WorkspaceScaffold extends StatelessWidget {
  const _WorkspaceScaffold({
    required this.controller,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
    this.actions = const [],
  });
  final AppController controller;
  final IconData icon;
  final String title, subtitle;
  final Widget child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 600;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      appBar: AppBar(
        title: Text(controller.currentBusiness?.businessName ?? 'Suman Enterprise'),
        actions: [
          _WorkspaceLanguagePicker(controller: controller, compact: compact),
          ...actions,
        ],
        actionsPadding: const EdgeInsets.symmetric(horizontal: 12),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: ListView(
            padding: EdgeInsets.all(compact ? 16 : 28),
            children: [
              Container(
                padding: EdgeInsets.all(compact ? 20 : 28),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF101D3A),
                      Color(0xFF1E3A8A),
                      Color(0xFF3157A5),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF1E3A8A).withValues(alpha: 0.18),
                      blurRadius: 28,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: compact ? 48 : 58,
                      height: compact ? 48 : 58,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.13),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Icon(
                        icon,
                        color: Colors.white,
                        size: compact ? 25 : 30,
                      ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.4,
                                ),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            subtitle,
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.78),
                                  height: 1.45,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkspaceLanguagePicker extends StatelessWidget {
  const _WorkspaceLanguagePicker({
    required this.controller,
    required this.compact,
  });
  final AppController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: PopupMenuButton<String>(
        tooltip: l10n?.languageSelector ?? 'Language',
        initialValue: controller.currentLocale.languageCode,
        onSelected: (code) => controller.setLocale(Locale(code)),
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'en', child: Text('🇬🇧 English')),
          PopupMenuItem(value: 'hi', child: Text('🇮🇳 हिंदी')),
          PopupMenuItem(value: 'bn', child: Text('🇮🇳 বাংলা')),
        ],
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 12,
            vertical: 9,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.translate_rounded, size: 17),
              if (!compact) ...[
                const SizedBox(width: 7),
                Text(
                  l10n?.languageSelector ?? 'Language',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
              const SizedBox(width: 4),
              const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _BusinessCard extends StatelessWidget {
  const _BusinessCard({required this.business, required this.onTap});
  final BusinessModel business;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    elevation: 1,
    shadowColor: const Color(0xFF1E3A8A).withValues(alpha: 0.08),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: const BorderSide(color: Color(0xFFE2E8F0)),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Theme.of(context)
                      .colorScheme
                      .primaryContainer,
                  child: business.logoUrl == null
                      ? const Icon(Icons.business_outlined)
                      : ClipOval(
                          child: Image.network(
                            business.logoUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) =>
                                const Icon(Icons.business_outlined),
                          ),
                        ),
                ),
                const Spacer(),
                const Icon(Icons.arrow_forward),
              ],
            ),
            const Spacer(),
            Text(
              business.businessName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              business.businessType,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Text(
              business.status,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
    ),
  );
}

class _OutletCard extends StatelessWidget {
  const _OutletCard({required this.outlet, required this.onTap});
  final OutletModel outlet;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    elevation: 1,
    shadowColor: const Color(0xFF1E3A8A).withValues(alpha: 0.08),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: const BorderSide(color: Color(0xFFE2E8F0)),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Theme.of(context)
                      .colorScheme
                      .secondaryContainer,
                  child: const Icon(Icons.store_outlined),
                ),
                const Spacer(),
                const Icon(Icons.arrow_forward),
              ],
            ),
            const Spacer(),
            Text(
              outlet.outletName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              outlet.address?.isNotEmpty == true
                  ? outlet.address!
                  : outlet.outletType,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  outlet.status,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });
  final IconData icon;
  final String title, message;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Icon(icon, size: 42),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}
