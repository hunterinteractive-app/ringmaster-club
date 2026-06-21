// lib/screens/clubs/admin/membership_types_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/clubs/club_summary.dart';

class MembershipTypesScreen extends StatefulWidget {
  const MembershipTypesScreen({
    super.key,
    required this.club,
  });

  final ClubSummary club;

  @override
  State<MembershipTypesScreen> createState() =>
      _MembershipTypesScreenState();
}

class _MembershipTypesScreenState extends State<MembershipTypesScreen> {
  final _supabase = Supabase.instance.client;

  bool _isLoading = true;
  String? _errorMessage;
  List<_MembershipType> _types = const [];

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
      final rows = await _supabase
          .from('club_membership_types')
          .select(
            'id,club_id,name,code,description,membership_scope,billing_type,'
            'term_type,term_months,price,currency,minimum_age,maximum_age,'
            'requires_approval,allow_auto_renew,is_public,is_active',
          )
          .eq('club_id', widget.club.clubId)
          .order('name', ascending: true);

      final parsed = (rows as List)
          .whereType<Map>()
          .map((row) => _MembershipType.fromJson(
                Map<String, dynamic>.from(row),
              ))
          .toList();

      if (!mounted) return;

      setState(() {
        _types = parsed;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _errorMessage = 'Unable to load membership types: $error';
      });
    }
  }

  Future<void> _openEditor({_MembershipType? existing}) async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _MembershipTypeDialog(
        clubId: widget.club.clubId,
        existing: existing,
      ),
    );

    if (changed == true) {
      await _loadTypes();
    }
  }

  Future<void> _toggleActive(_MembershipType type) async {
    try {
      await _supabase
          .from('club_membership_types')
          .update({'is_active': !type.isActive})
          .eq('id', type.id)
          .eq('club_id', widget.club.clubId);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            type.isActive
                ? '${type.name} was deactivated.'
                : '${type.name} was activated.',
          ),
        ),
      );

      await _loadTypes();
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to update membership type: $error'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Membership Types'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _loadTypes,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('Add Type'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null && _types.isEmpty) {
      return _MessageState(
        icon: Icons.error_outline,
        title: 'Unable to load membership types',
        message: _errorMessage!,
        actionLabel: 'Try Again',
        onAction: _loadTypes,
      );
    }

    if (_types.isEmpty) {
      return _MessageState(
        icon: Icons.workspace_premium_outlined,
        title: 'No membership types yet',
        message:
            'Create the membership options this club will offer to members.',
        actionLabel: 'Add Membership Type',
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
            'Configure the membership levels, fees, terms, and approval rules available for this club.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
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
                  for (final type in _types)
                    SizedBox(
                      width: cardWidth,
                      child: _MembershipTypeCard(
                        type: type,
                        onEdit: () => _openEditor(existing: type),
                        onToggleActive: () => _toggleActive(type),
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

class _MembershipTypeCard extends StatelessWidget {
  const _MembershipTypeCard({
    required this.type,
    required this.onEdit,
    required this.onToggleActive,
  });

  final _MembershipType type;
  final VoidCallback onEdit;
  final VoidCallback onToggleActive;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final inactiveBackground = colorScheme.errorContainer.withAlpha((0.45 * 255).round());
    final inactiveBorder = colorScheme.error.withAlpha((0.55 * 255).round());

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
                  color: colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: colorScheme.error.withAlpha((0.5 * 255).round()),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.pause_circle_filled,
                      color: colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'DEACTIVATED',
                            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                  color: colorScheme.onErrorContainer,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.8,
                                ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'This membership type is not available for new memberships.',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onErrorContainer,
                                ),
                          ),
                        ],
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
                CircleAvatar(
                  child: Icon(
                    type.isActive
                        ? Icons.workspace_premium_outlined
                        : Icons.pause_circle_outline,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        type.name,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      if (type.code != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          type.code!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    switch (value) {
                      case 'edit':
                        onEdit();
                        break;
                      case 'toggle':
                        onToggleActive();
                        break;
                    }
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
                      value: 'toggle',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          type.isActive
                              ? Icons.pause_circle_outline
                              : Icons.play_circle_outline,
                        ),
                        title: Text(
                          type.isActive ? 'Deactivate' : 'Activate',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InfoChip(label: _titleCase(type.membershipScope)),
                _InfoChip(label: _titleCase(type.billingType)),
                _InfoChip(label: _termLabel(type)),
                _InfoChip(label: type.priceLabel),
                // Removed the "Inactive" chip in favor of the banner above.
                if (!type.isPublic) const _InfoChip(label: 'Hidden'),
              ],
            ),
            if (type.description != null) ...[
              const SizedBox(height: 12),
              Text(type.description!),
            ],
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _DetailText(
                  icon: Icons.how_to_reg_outlined,
                  text: type.requiresApproval
                      ? 'Approval required'
                      : 'Automatic approval',
                ),
                _DetailText(
                  icon: Icons.autorenew,
                  text: type.allowAutoRenew
                      ? 'Auto-renew available'
                      : 'No auto-renew',
                ),
                if (type.minimumAge != null || type.maximumAge != null)
                  _DetailText(
                    icon: Icons.cake_outlined,
                    text: type.ageLabel,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _termLabel(_MembershipType type) {
    if (type.termType == 'multi_year' && type.termMonths != null) {
      final years = type.termMonths! / 12;
      return years == years.roundToDouble()
          ? '${years.toInt()} year term'
          : '${type.termMonths} month term';
    }

    if (type.termType == 'rolling_year') return 'Rolling year';
    if (type.termType == 'calendar_year') return 'Calendar year';
    if (type.termType == 'monthly') return 'Monthly';
    if (type.termType == 'lifetime') return 'Lifetime';
    return _titleCase(type.termType);
  }

  static String _titleCase(String value) {
    return value
        .split(RegExp(r'[_\s-]+'))
        .where((part) => part.isNotEmpty)
        .map(
          (part) => '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
        )
        .join(' ');
  }
}

class _MembershipTypeDialog extends StatefulWidget {
  const _MembershipTypeDialog({
    required this.clubId,
    this.existing,
  });

  final String clubId;
  final _MembershipType? existing;

  @override
  State<_MembershipTypeDialog> createState() =>
      _MembershipTypeDialogState();
}

class _MembershipTypeDialogState extends State<_MembershipTypeDialog> {
  final _formKey = GlobalKey<FormState>();
  final _supabase = Supabase.instance.client;

  late final TextEditingController _nameController;
  late final TextEditingController _codeController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _priceController;
  late final TextEditingController _currencyController;
  late final TextEditingController _termMonthsController;
  late final TextEditingController _minimumAgeController;
  late final TextEditingController _maximumAgeController;

  late String _membershipScope;
  late String _billingType;
  late String _termType;
  late bool _requiresApproval;
  late bool _allowAutoRenew;
  late bool _isPublic;
  late bool _isActive;

  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();

    final existing = widget.existing;

    _nameController = TextEditingController(text: existing?.name ?? '');
    _codeController = TextEditingController(text: existing?.code ?? '');
    _descriptionController =
        TextEditingController(text: existing?.description ?? '');
    _priceController = TextEditingController(
      text: existing == null ? '0.00' : existing.price.toStringAsFixed(2),
    );
    _currencyController =
        TextEditingController(text: existing?.currency.toUpperCase() ?? 'USD');
    _termMonthsController = TextEditingController(
      text: existing?.termMonths?.toString() ?? '',
    );
    _minimumAgeController = TextEditingController(
      text: existing?.minimumAge?.toString() ?? '',
    );
    _maximumAgeController = TextEditingController(
      text: existing?.maximumAge?.toString() ?? '',
    );

    _membershipScope = existing?.membershipScope ?? 'individual';
    _billingType = existing?.billingType ?? 'one_time';
    _termType = existing?.termType ?? 'rolling_year';
    _requiresApproval = existing?.requiresApproval ?? true;
    _allowAutoRenew = existing?.allowAutoRenew ?? false;
    _isPublic = existing?.isPublic ?? true;
    _isActive = existing?.isActive ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _currencyController.dispose();
    _termMonthsController.dispose();
    _minimumAgeController.dispose();
    _maximumAgeController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSaving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final payload = <String, dynamic>{
      'club_id': widget.clubId,
      'name': _nameController.text.trim(),
      'code': _nullIfBlank(_codeController.text),
      'description': _nullIfBlank(_descriptionController.text),
      'membership_scope': _membershipScope,
      'billing_type': _billingType,
      'term_type': _termType,
      'term_months': _termType == 'multi_year'
          ? _nullableInt(_termMonthsController.text)
          : null,
      'price': double.tryParse(_priceController.text.trim()) ?? 0,
      'currency': _currencyController.text.trim().isEmpty
          ? 'usd'
          : _currencyController.text.trim().toLowerCase(),
      'minimum_age': _nullableInt(_minimumAgeController.text),
      'maximum_age': _nullableInt(_maximumAgeController.text),
      'requires_approval': _requiresApproval,
      'allow_auto_renew': _allowAutoRenew,
      'is_public': _isPublic,
      'is_active': _isActive,
    };

    try {
      final existing = widget.existing;

      if (existing == null) {
        await _supabase.from('club_membership_types').insert(payload);
      } else {
        await _supabase
            .from('club_membership_types')
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
        _errorMessage = 'Unable to save membership type: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.existing == null
            ? 'Add Membership Type'
            : 'Edit Membership Type',
      ),
      content: SizedBox(
        width: 680,
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
                    labelText: 'Name',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Name is required.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _codeController,
                  decoration: const InputDecoration(
                    labelText: 'Code (optional)',
                    hintText: 'Example: IND',
                    helperText:
                        'Suggested abbreviations: IND = Individual, YTH = Youth, '
                        'FAM = Family, ASC = Associate, LIFE = Lifetime',
                    helperMaxLines: 3,
                    border: OutlineInputBorder(),
                  ),
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
                  initialValue: _membershipScope,
                  decoration: const InputDecoration(
                    labelText: 'Membership scope',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'individual',
                      child: Text('Individual'),
                    ),
                    DropdownMenuItem(value: 'youth', child: Text('Youth')),
                    DropdownMenuItem(value: 'family', child: Text('Family')),
                    DropdownMenuItem(
                      value: 'associate',
                      child: Text('Associate'),
                    ),
                    DropdownMenuItem(value: 'life', child: Text('Life')),
                    DropdownMenuItem(
                      value: 'organization',
                      child: Text('Organization'),
                    ),
                    DropdownMenuItem(value: 'other', child: Text('Other')),
                  ],
                  onChanged: _isSaving
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() => _membershipScope = value);
                          }
                        },
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _billingType,
                  decoration: const InputDecoration(
                    labelText: 'Billing type',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'one_time',
                      child: Text('One-time'),
                    ),
                    DropdownMenuItem(
                      value: 'recurring',
                      child: Text('Recurring'),
                    ),
                    DropdownMenuItem(
                      value: 'lifetime',
                      child: Text('Lifetime'),
                    ),
                    DropdownMenuItem(value: 'manual', child: Text('Manual')),
                  ],
                  onChanged: _isSaving
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() => _billingType = value);
                          }
                        },
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _termType,
                  decoration: const InputDecoration(
                    labelText: 'Term type',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'calendar_year',
                      child: Text('Calendar year'),
                    ),
                    DropdownMenuItem(
                      value: 'rolling_year',
                      child: Text('Rolling year'),
                    ),
                    DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                    DropdownMenuItem(
                      value: 'multi_year',
                      child: Text('Multi-year'),
                    ),
                    DropdownMenuItem(
                      value: 'lifetime',
                      child: Text('Lifetime'),
                    ),
                    DropdownMenuItem(value: 'custom', child: Text('Custom')),
                  ],
                  onChanged: _isSaving
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() => _termType = value);
                          }
                        },
                ),
                if (_termType == 'multi_year') ...[
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _termMonthsController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Term length in months',
                      hintText: 'Example: 24',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      final months = int.tryParse(value?.trim() ?? '');
                      if (months == null || months <= 0) {
                        return 'Enter a valid number of months.';
                      }
                      return null;
                    },
                  ),
                ],
                const SizedBox(height: 14),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 540;
                    final width = wide
                        ? (constraints.maxWidth - 12) / 2
                        : constraints.maxWidth;

                    return Wrap(
                      spacing: 12,
                      runSpacing: 14,
                      children: [
                        SizedBox(
                          width: width,
                          child: TextFormField(
                            controller: _priceController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Price',
                              prefixText: r'$ ',
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) {
                              final price =
                                  double.tryParse(value?.trim() ?? '');
                              if (price == null || price < 0) {
                                return 'Enter a valid price.';
                              }
                              return null;
                            },
                          ),
                        ),
                        SizedBox(
                          width: width,
                          child: TextFormField(
                            controller: _currencyController,
                            textCapitalization: TextCapitalization.characters,
                            decoration: const InputDecoration(
                              labelText: 'Currency',
                              hintText: 'USD',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: width,
                          child: TextFormField(
                            controller: _minimumAgeController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Minimum age',
                              border: OutlineInputBorder(),
                            ),
                            validator: _optionalNonNegativeInt,
                          ),
                        ),
                        SizedBox(
                          width: width,
                          child: TextFormField(
                            controller: _maximumAgeController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Maximum age',
                              border: OutlineInputBorder(),
                            ),
                            validator: _optionalNonNegativeInt,
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 10),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Require approval'),
                  subtitle: const Text(
                    'A club administrator must approve applications for this type.',
                  ),
                  value: _requiresApproval,
                  onChanged: _isSaving
                      ? null
                      : (value) =>
                          setState(() => _requiresApproval = value),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Allow auto-renew'),
                  subtitle: const Text(
                    'Members may choose recurring automatic renewal.',
                  ),
                  value: _allowAutoRenew,
                  onChanged: _isSaving
                      ? null
                      : (value) =>
                          setState(() => _allowAutoRenew = value),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Publicly available'),
                  subtitle: const Text(
                    'Show this membership type to prospective members.',
                  ),
                  value: _isPublic,
                  onChanged: _isSaving
                      ? null
                      : (value) => setState(() => _isPublic = value),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active'),
                  subtitle: const Text(
                    'Allow this membership type to be used for new memberships.',
                  ),
                  value: _isActive,
                  onChanged: _isSaving
                      ? null
                      : (value) => setState(() => _isActive = value),
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

  String? _nullIfBlank(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  int? _nullableInt(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : int.tryParse(trimmed);
  }

  String? _optionalNonNegativeInt(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;

    final parsed = int.tryParse(text);
    if (parsed == null || parsed < 0) {
      return 'Enter zero or a positive whole number.';
    }
    return null;
  }

}

class _MembershipType {
  const _MembershipType({
    required this.id,
    required this.name,
    required this.membershipScope,
    required this.billingType,
    required this.termType,
    required this.price,
    required this.currency,
    required this.requiresApproval,
    required this.allowAutoRenew,
    required this.isPublic,
    required this.isActive,
    this.code,
    this.description,
    this.termMonths,
    this.minimumAge,
    this.maximumAge,
  });

  final String id;
  final String name;
  final String? code;
  final String? description;
  final String membershipScope;
  final String billingType;
  final String termType;
  final int? termMonths;
  final double price;
  final String currency;
  final int? minimumAge;
  final int? maximumAge;
  final bool requiresApproval;
  final bool allowAutoRenew;
  final bool isPublic;
  final bool isActive;

  String get priceLabel {
    final symbol = currency.toLowerCase() == 'usd' ? r'$' : '';
    return '$symbol${price.toStringAsFixed(2)} ${currency.toUpperCase()}'.trim();
  }

  String get ageLabel {
    if (minimumAge != null && maximumAge != null) {
      return 'Ages $minimumAge–$maximumAge';
    }
    if (minimumAge != null) return 'Age $minimumAge+';
    if (maximumAge != null) return 'Up to age $maximumAge';
    return 'No age limit';
  }

  factory _MembershipType.fromJson(Map<String, dynamic> json) {
    return _MembershipType(
      id: json['id'].toString(),
      name: json['name'].toString(),
      code: _nullableString(json['code']),
      description: _nullableString(json['description']),
      membershipScope:
          _nullableString(json['membership_scope']) ?? 'individual',
      billingType: _nullableString(json['billing_type']) ?? 'one_time',
      termType: _nullableString(json['term_type']) ?? 'rolling_year',
      termMonths: _nullableIntValue(json['term_months']),
      price: _doubleValue(json['price']),
      currency: _nullableString(json['currency']) ?? 'usd',
      minimumAge: _nullableIntValue(json['minimum_age']),
      maximumAge: _nullableIntValue(json['maximum_age']),
      requiresApproval: json['requires_approval'] == true,
      allowAutoRenew: json['allow_auto_renew'] == true,
      isPublic: json['is_public'] == true,
      isActive: json['is_active'] == true,
    );
  }

  static String? _nullableString(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static int? _nullableIntValue(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    return int.tryParse(value.toString());
  }

  static double _doubleValue(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _DetailText extends StatelessWidget {
  const _DetailText({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 6),
        Text(text),
      ],
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
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 64),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 10),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.add),
                label: Text(actionLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}