// lib/screens/clubs/admin/sanction_types_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/clubs/club_summary.dart';

final supabase = Supabase.instance.client;

class SanctionTypesScreen extends StatefulWidget {
  const SanctionTypesScreen({
    super.key,
    required this.club,
  });

  final ClubSummary club;

  @override
  State<SanctionTypesScreen> createState() => _SanctionTypesScreenState();
}

class _SanctionTypesScreenState extends State<SanctionTypesScreen> {
  bool _isLoading = true;
  bool _showArchived = false;
  String? _errorMessage;
  bool _sanctionRequestsAddonEnabled = false;
  List<_SanctionType> _types = const [];

  List<_SanctionType> get _visibleTypes {
    if (_showArchived) return _types;
    return _types.where((type) => type.isActive).toList();
  }

  @override
  void initState() {
    super.initState();
    _loadTypes();
  }

  Future<void> _loadTypes() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final clubRow = await supabase
          .from('clubs')
          .select('sanction_requests_addon_enabled')
          .eq('id', widget.club.clubId)
          .single();

      final sanctionRequestsAddonEnabled =
          clubRow['sanction_requests_addon_enabled'] == true;

      if (!sanctionRequestsAddonEnabled) {
        if (!mounted) return;
        setState(() {
          _sanctionRequestsAddonEnabled = false;
          _types = const [];
          _isLoading = false;
        });
        return;
      }

      final rows = await supabase
          .from('club_sanction_types')
          .select(
            'id,club_id,name,description,sanction_scope,base_price,currency,'
            'is_bundle,included_open_count,included_youth_count,is_active,'
            'sort_order,created_at,updated_at',
          )
          .eq('club_id', widget.club.clubId)
          .order('is_active', ascending: false)
          .order('sort_order', ascending: true)
          .order('name', ascending: true);

      final parsed = (rows as List)
          .whereType<Map>()
          .map((row) => _SanctionType.fromJson(Map<String, dynamic>.from(row)))
          .toList();

      if (!mounted) return;
      setState(() {
        _sanctionRequestsAddonEnabled = true;
        _types = parsed;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Unable to load sanction types: $error';
      });
    }
  }

  void _showLockedFeature() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sanction Types Requires an Add-on'),
        content: const Text(
          'Sanction types, sanction pricing, bundles, and online sanction request options are available with the Sanction Requests Add-on. The club owner can enable this when the club is ready to use it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _openEditor({_SanctionType? existing}) async {
    if (!_sanctionRequestsAddonEnabled) {
      _showLockedFeature();
      return;
    }

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _SanctionTypeDialog(
        clubId: widget.club.clubId,
        existing: existing,
        existingTypes: _types,
      ),
    );

    if (saved == true) {
      await _loadTypes();
    }
  }

  Future<void> _archiveOrRestore(_SanctionType type) async {
    if (!_sanctionRequestsAddonEnabled) {
      _showLockedFeature();
      return;
    }
    try {
      await supabase
          .from('club_sanction_types')
          .update({'is_active': !type.isActive})
          .eq('id', type.id)
          .eq('club_id', widget.club.clubId);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            type.isActive
                ? '${type.name} was archived.'
                : '${type.name} was restored.',
          ),
        ),
      );

      await _loadTypes();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to update sanction type: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sanction Types'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _loadTypes,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isLoading
            ? null
            : _sanctionRequestsAddonEnabled
                ? () => _openEditor()
                : _showLockedFeature,
        icon: Icon(
          _sanctionRequestsAddonEnabled ? Icons.add : Icons.lock_outline,
        ),
        label: Text(
          _sanctionRequestsAddonEnabled ? 'Add Type' : 'Add-on Required',
        ),
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_sanctionRequestsAddonEnabled) {
      return _LockedAddOnState(
        clubName: widget.club.clubName,
        onRefresh: _loadTypes,
      );
    }

    final visibleTypes = _visibleTypes;
    final archivedCount = _types.where((type) => !type.isActive).length;

    if (_errorMessage != null && _types.isEmpty) {
      return _MessageState(
        icon: Icons.error_outline,
        title: 'Unable to load sanction types',
        message: _errorMessage!,
        actionLabel: 'Try Again',
        onAction: _loadTypes,
      );
    }

    if (_types.isEmpty) {
      return _MessageState(
        icon: Icons.fact_check_outlined,
        title: 'No sanction types yet',
        message:
            'Create the sanction options, bundles, and pricing this club will offer.',
        actionLabel: 'Add Sanction Type',
        onAction: () => _openEditor(),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadTypes,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          if (_errorMessage != null) ...[
            Material(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(_errorMessage!),
              ),
            ),
            const SizedBox(height: 16),
          ],
          Text(
            widget.club.clubName,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'Configure sanction options, bundle rules, pricing, and availability for this club.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (archivedCount > 0) ...[
            const SizedBox(height: 14),
            Card(
              child: SwitchListTile.adaptive(
                value: _showArchived,
                onChanged: (value) => setState(() => _showArchived = value),
                secondary: const Icon(Icons.inventory_2_outlined),
                title: const Text('Show archived sanction types'),
                subtitle: Text(
                  _showArchived
                      ? 'Archived sanction types are visible below.'
                      : '$archivedCount archived sanction type${archivedCount == 1 ? '' : 's'} hidden.',
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (visibleTypes.isEmpty)
            _MessageCard(
              icon: Icons.inventory_2_outlined,
              title: 'No active sanction types',
              message:
                  'All sanction types are archived. Turn on Show archived sanction types to restore one, or add a new sanction type.',
              actionLabel: 'Add Sanction Type',
              onAction: () => _openEditor(),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final useTwoColumns = constraints.maxWidth >= 850;
                final cardWidth = useTwoColumns
                    ? (constraints.maxWidth - 12) / 2
                    : constraints.maxWidth;

                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final type in visibleTypes)
                      SizedBox(
                        width: cardWidth,
                        child: _SanctionTypeCard(
                          type: type,
                          onEdit: () => _openEditor(existing: type),
                          onArchiveOrRestore: () => _archiveOrRestore(type),
                        ),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }


}

class _LockedAddOnState extends StatelessWidget {
  const _LockedAddOnState({
    required this.clubName,
    required this.onRefresh,
  });

  final String clubName;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 34,
                    backgroundColor: scheme.primaryContainer,
                    foregroundColor: scheme.onPrimaryContainer,
                    child: const Icon(Icons.lock_outline, size: 34),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Sanction Requests Add-on Required',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '$clubName does not currently have the Sanction Requests Add-on enabled.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'This add-on enables sanction types, sanction pricing, bundles, and online sanction request options.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: onRefresh,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh Add-on Status'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SanctionTypeCard extends StatelessWidget {
  const _SanctionTypeCard({
    required this.type,
    required this.onEdit,
    required this.onArchiveOrRestore,
  });

  final _SanctionType type;
  final VoidCallback onEdit;
  final VoidCallback onArchiveOrRestore;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final inactiveBackground = scheme.surfaceContainerHighest.withAlpha(150);
    final inactiveBorder = scheme.outlineVariant;

    return Card(
      clipBehavior: Clip.antiAlias,
      color: type.isActive ? null : inactiveBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: type.isActive ? Colors.transparent : inactiveBorder,
          width: type.isActive ? 0 : 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!type.isActive) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: scheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: scheme.error.withAlpha((0.5 * 255).round()),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.inventory_2_outlined, color: scheme.onErrorContainer),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'ARCHIVED — hidden from new sanction requests',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: scheme.onErrorContainer,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(child: Icon(_iconForScope(type.sanctionScope))),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        type.name,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(type.scopeLabel),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'edit') onEdit();
                    if (value == 'archive') onArchiveOrRestore();
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.edit_outlined),
                        title: Text('Edit'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'archive',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          type.isActive
                              ? Icons.inventory_2_outlined
                              : Icons.restore_outlined,
                        ),
                        title: Text(type.isActive ? 'Archive' : 'Restore'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (type.description != null) ...[
              const SizedBox(height: 12),
              Text(type.description!),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InfoChip(
                  icon: Icons.payments_outlined,
                  label: type.priceLabel,
                ),
                if (type.isBundle)
                  const _InfoChip(
                    icon: Icons.all_inclusive,
                    label: 'Bundle',
                  ),
                if (type.includedOpenCount > 0)
                  _InfoChip(
                    icon: Icons.check_circle_outline,
                    label: '${type.includedOpenCount} Open',
                  ),
                if (type.includedYouthCount > 0)
                  _InfoChip(
                    icon: Icons.child_care_outlined,
                    label: '${type.includedYouthCount} Youth',
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}

class _SanctionTypeDialog extends StatefulWidget {
  const _SanctionTypeDialog({
    required this.clubId,
    required this.existingTypes,
    this.existing,
  });

  final String clubId;
  final List<_SanctionType> existingTypes;
  final _SanctionType? existing;

  @override
  State<_SanctionTypeDialog> createState() => _SanctionTypeDialogState();
}

class _SanctionTypeDialogState extends State<_SanctionTypeDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _priceController;
  late final TextEditingController _currencyController;
  late final TextEditingController _includedOpenController;
  late final TextEditingController _includedYouthController;

  String _sanctionScope = 'open_youth_bundle';
  bool _isBundle = true;
  bool _isActive = true;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;

    _nameController = TextEditingController(text: existing?.name ?? '');
    _descriptionController = TextEditingController(
      text: existing?.description ?? '',
    );
    _priceController = TextEditingController(
      text: existing == null ? '0.00' : existing.basePrice.toStringAsFixed(2),
    );
    _currencyController = TextEditingController(text: existing?.currency ?? 'USD');
    _includedOpenController = TextEditingController(
      text: (existing?.includedOpenCount ?? 0).toString(),
    );
    _includedYouthController = TextEditingController(
      text: (existing?.includedYouthCount ?? 0).toString(),
    );

    _sanctionScope = existing?.sanctionScope ?? 'open_youth_bundle';
    _isBundle = existing?.isBundle ?? true;
    _isActive = existing?.isActive ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _currencyController.dispose();
    _includedOpenController.dispose();
    _includedYouthController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSaving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final generatedSortOrder = _generatedSortOrderForScope(_sanctionScope);
      final payload = {
        'club_id': widget.clubId,
        'name': _nameController.text.trim(),
        'description': _nullIfBlank(_descriptionController.text),
        'sanction_scope': _sanctionScope,
        'base_price': double.tryParse(_priceController.text.trim()) ?? 0,
        'currency': _currencyController.text.trim().isEmpty
            ? 'USD'
            : _currencyController.text.trim().toUpperCase(),
        'is_bundle': _isBundle,
        'included_open_count': int.tryParse(_includedOpenController.text.trim()) ?? 0,
        'included_youth_count': int.tryParse(_includedYouthController.text.trim()) ?? 0,
        'is_active': _isActive,
        'sort_order': generatedSortOrder,
      };

      final existing = widget.existing;
      if (existing == null) {
        await supabase.from('club_sanction_types').insert(payload);
      } else {
        await supabase
            .from('club_sanction_types')
            .update(payload)
            .eq('id', existing.id)
            .eq('club_id', widget.clubId);
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorMessage = 'Unable to save sanction type: $error';
      });
    }
  }

  int _generatedSortOrderForScope(String scope) {
    final existing = widget.existing;
    if (existing != null && existing.sanctionScope == scope) {
      return existing.sortOrder;
    }

    final base = _baseSortOrderForScope(scope);
    final usedSortOrders = widget.existingTypes
        .where((type) => type.id != existing?.id)
        .map((type) => type.sortOrder)
        .toSet();

    for (var offset = 0; offset < 20; offset++) {
      final candidate = base + offset;
      if (!usedSortOrders.contains(candidate)) {
        return candidate;
      }
    }

    return base + 19;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Add Sanction Type' : 'Edit Sanction Type'),
      content: SizedBox(
        width: 720,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_errorMessage != null) ...[
                  Material(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(_errorMessage!),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Sanction type name',
                    hintText: 'Open & Youth Bundle',
                    border: OutlineInputBorder(),
                  ),
                  validator: _required,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _descriptionController,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _sanctionScope,
                  decoration: const InputDecoration(
                    labelText: 'Sanction scope',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'open', child: Text('Open')),
                    DropdownMenuItem(value: 'youth', child: Text('Youth')),
                    DropdownMenuItem(
                      value: 'open_youth_bundle',
                      child: Text('Open & Youth Bundle'),
                    ),
                    DropdownMenuItem(value: 'other', child: Text('Other')),
                  ],
                  onChanged: _isSaving
                      ? null
                      : (value) {
                          if (value == null) return;
                          setState(() {
                            _sanctionScope = value;
                            if (value == 'open_youth_bundle') {
                              _isBundle = true;
                              if (_includedOpenController.text.trim() == '0') {
                                _includedOpenController.text = '1';
                              }
                              if (_includedYouthController.text.trim() == '0') {
                                _includedYouthController.text = '1';
                              }
                            }
                          });
                        },
                ),
                const SizedBox(height: 14),
                _ResponsiveFields(
                  children: [
                    TextFormField(
                      controller: _priceController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Base price',
                        prefixText: r'$ ',
                        border: OutlineInputBorder(),
                      ),
                      validator: _money,
                    ),
                    TextFormField(
                      controller: _currencyController,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Currency',
                        hintText: 'USD',
                        border: OutlineInputBorder(),
                      ),
                      validator: _required,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Bundle'),
                  subtitle: const Text(
                    'Use this for options that include multiple sanction items.',
                  ),
                  value: _isBundle,
                  onChanged: _isSaving
                      ? null
                      : (value) => setState(() => _isBundle = value),
                ),
                const SizedBox(height: 8),
                _ResponsiveFields(
                  children: [
                    TextFormField(
                      controller: _includedOpenController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Included Open sanctions',
                        border: OutlineInputBorder(),
                      ),
                      validator: _wholeNumber,
                    ),
                    TextFormField(
                      controller: _includedYouthController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Included Youth sanctions',
                        border: OutlineInputBorder(),
                      ),
                      validator: _wholeNumber,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Archived'),
                  subtitle: const Text(
                    'Archived sanction types are hidden from new sanction request options.',
                  ),
                  value: !_isActive,
                  onChanged: _isSaving
                      ? null
                      : (value) => setState(() => _isActive = !value),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _isSaving ? null : _save,
          icon: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: Text(_isSaving ? 'Saving...' : 'Save'),
        ),
      ],
    );
  }

  String? _required(String? value) {
    return value == null || value.trim().isEmpty ? 'Required.' : null;
  }

  String? _money(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Required.';
    final parsed = double.tryParse(text);
    if (parsed == null || parsed < 0) return 'Enter a valid amount.';
    return null;
  }

  String? _wholeNumber(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Required.';
    final parsed = int.tryParse(text);
    if (parsed == null || parsed < 0) return 'Enter 0 or greater.';
    return null;
  }
}

class _ResponsiveFields extends StatelessWidget {
  const _ResponsiveFields({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useWide = constraints.maxWidth >= 680;
        final width = useWide
            ? (constraints.maxWidth - ((children.length - 1) * 12)) /
                children.length
            : constraints.maxWidth;

        return Wrap(
          spacing: 12,
          runSpacing: 14,
          children: [
            for (final child in children)
              SizedBox(
                width: width,
                child: child,
              ),
          ],
        );
      },
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56),
            const SizedBox(height: 14),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.add),
              label: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            Icon(icon, size: 52),
            const SizedBox(height: 12),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.add),
              label: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _SanctionType {
  const _SanctionType({
    required this.id,
    required this.name,
    required this.sanctionScope,
    required this.basePrice,
    required this.currency,
    required this.isBundle,
    required this.includedOpenCount,
    required this.includedYouthCount,
    required this.isActive,
    required this.sortOrder,
    this.description,
  });

  final String id;
  final String name;
  final String? description;
  final String sanctionScope;
  final double basePrice;
  final String currency;
  final bool isBundle;
  final int includedOpenCount;
  final int includedYouthCount;
  final bool isActive;
  final int sortOrder;

  String get scopeLabel {
    switch (sanctionScope) {
      case 'open_youth_bundle':
        return 'Open & Youth Bundle';
      case 'open':
        return 'Open';
      case 'youth':
        return 'Youth';
      case 'other':
        return 'Other';
      default:
        return sanctionScope;
    }
  }

  String get priceLabel {
    final symbol = currency.toUpperCase() == 'USD' ? r'$' : '$currency ';
    return '$symbol${basePrice.toStringAsFixed(2)}';
  }

  factory _SanctionType.fromJson(Map<String, dynamic> json) {
    return _SanctionType(
      id: json['id'].toString(),
      name: _text(json['name'], fallback: 'Sanction Type'),
      description: _nullableText(json['description']),
      sanctionScope: _text(
        json['sanction_scope'],
        fallback: 'open_youth_bundle',
      ),
      basePrice: _doubleFromValue(json['base_price']),
      currency: _text(json['currency'], fallback: 'USD').toUpperCase(),
      isBundle: json['is_bundle'] == true,
      includedOpenCount: _intFromValue(json['included_open_count']),
      includedYouthCount: _intFromValue(json['included_youth_count']),
      isActive: json['is_active'] != false,
      sortOrder: _intFromValue(json['sort_order'], fallback: 100),
    );
  }
}

IconData _iconForScope(String scope) {
  switch (scope) {
    case 'open_youth_bundle':
      return Icons.all_inclusive;
    case 'open':
      return Icons.workspace_premium_outlined;
    case 'youth':
      return Icons.child_care_outlined;
    case 'other':
      return Icons.fact_check_outlined;
    default:
      return Icons.fact_check_outlined;
  }
}

int _baseSortOrderForScope(String scope) {
  switch (scope) {
    case 'open':
      return 10;
    case 'youth':
      return 30;
    case 'open_youth_bundle':
      return 50;
    case 'other':
      return 70;
    default:
      return 70;
  }
}

String _text(dynamic value, {String fallback = ''}) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? fallback : text;
}

String? _nullableText(dynamic value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

String? _nullIfBlank(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

int _intFromValue(dynamic value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

double _doubleFromValue(dynamic value) {
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}
