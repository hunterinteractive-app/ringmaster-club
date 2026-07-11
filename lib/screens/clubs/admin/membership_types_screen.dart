// lib/screens/clubs/admin/membership_types_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/clubs/club_summary.dart';

class MembershipTypesScreen extends StatefulWidget {
  const MembershipTypesScreen({super.key, required this.club});

  final ClubSummary club;

  @override
  State<MembershipTypesScreen> createState() => _MembershipTypesScreenState();
}

class _MembershipTypesScreenState extends State<MembershipTypesScreen> {
  final _supabase = Supabase.instance.client;

  bool _isLoading = true;
  bool _showArchived = false;
  bool _membershipManagementAddonEnabled = false;
  bool _allowMembershipCheckPayments = false;
  bool _isSavingPaymentSettings = false;
  String? _errorMessage;
  List<_MembershipType> _types = const [];

  List<_MembershipType> get _visibleTypes {
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
      final clubRow = await _supabase
          .from('clubs')
          .select(
            'membership_management_addon_enabled,allow_membership_check_payments',
          )
          .eq('id', widget.club.clubId)
          .single();

      final rows = await _supabase
          .from('club_membership_types')
          .select(
            'id,club_id,name,code,description,membership_scope,billing_type,'
            'term_type,term_months,price,currency,minimum_age,maximum_age,'
            'requires_approval,require_arba_number,allow_auto_renew,is_public,is_active,settings',
          )
          .eq('club_id', widget.club.clubId)
          .order('is_active', ascending: false)
          .order('name', ascending: true);

      final parsed = (rows as List)
          .whereType<Map>()
          .map(
            (row) => _MembershipType.fromJson(Map<String, dynamic>.from(row)),
          )
          .toList();

      if (!mounted) return;

      setState(() {
        _membershipManagementAddonEnabled =
            clubRow['membership_management_addon_enabled'] == true;
        _allowMembershipCheckPayments =
            clubRow['allow_membership_check_payments'] == true;
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
        membershipManagementAddonEnabled: _membershipManagementAddonEnabled,
        existing: existing,
      ),
    );

    if (changed == true) {
      await _loadTypes();
    }
  }

  Future<void> _archiveOrRestoreType(_MembershipType type) async {
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
                ? '${type.name} was archived and hidden from active membership options.'
                : '${type.name} was restored.',
          ),
        ),
      );

      await _loadTypes();
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to update membership type: $error')),
      );
    }
  }

  Future<void> _setAllowMembershipCheckPayments(bool value) async {
    if (_isSavingPaymentSettings) return;

    final previousValue = _allowMembershipCheckPayments;

    setState(() {
      _allowMembershipCheckPayments = value;
      _isSavingPaymentSettings = true;
      _errorMessage = null;
    });

    try {
      await _supabase
          .from('clubs')
          .update({'allow_membership_check_payments': value})
          .eq('id', widget.club.clubId);
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _allowMembershipCheckPayments = previousValue;
        _errorMessage = 'Unable to update membership payment settings: $error';
      });
    } finally {
      if (mounted) {
        setState(() => _isSavingPaymentSettings = false);
      }
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

    final visibleTypes = _visibleTypes;
    final archivedCount = _types.where((type) => !type.isActive).length;

    if (_errorMessage != null && _types.isEmpty) {
      return _MessageState(
        icon: Icons.error_outline,
        title: 'Unable to load membership types',
        message: _errorMessage!,
        actionLabel: 'Try Again',
        onAction: _loadTypes,
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
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Configure the membership levels, fees, terms, and approval rules available for this club.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          _BaseMembershipTypesAccessCard(
            membershipManagementAddonEnabled: _membershipManagementAddonEnabled,
          ),
          const SizedBox(height: 14),
          _MembershipPaymentSettingsCard(
            allowCheckPayments: _allowMembershipCheckPayments,
            isSaving: _isSavingPaymentSettings,
            onAllowCheckPaymentsChanged: _setAllowMembershipCheckPayments,
          ),
          if (archivedCount > 0) ...[
            const SizedBox(height: 14),
            Card(
              child: SwitchListTile.adaptive(
                value: _showArchived,
                onChanged: (value) => setState(() => _showArchived = value),
                secondary: const Icon(Icons.inventory_2_outlined),
                title: const Text('Show archived membership types'),
                subtitle: Text(
                  _showArchived
                      ? 'Archived membership types are visible below.'
                      : '$archivedCount archived membership type${archivedCount == 1 ? '' : 's'} hidden.',
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (visibleTypes.isEmpty)
            _MessageCard(
              icon: Icons.inventory_2_outlined,
              title: _types.isEmpty
                  ? 'No membership types yet'
                  : 'No active membership types',
              message: _types.isEmpty
                  ? 'Create the membership options this club will offer to members.'
                  : 'All membership types are archived. Turn on Show archived membership types to restore one, or add a new membership type.',
              actionLabel: 'Add Membership Type',
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
                        child: _MembershipTypeCard(
                          type: type,
                          onEdit: () => _openEditor(existing: type),
                          onArchiveOrRestore: () => _archiveOrRestoreType(type),
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

class _BaseMembershipTypesAccessCard extends StatelessWidget {
  const _BaseMembershipTypesAccessCard({
    required this.membershipManagementAddonEnabled,
  });

  final bool membershipManagementAddonEnabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: scheme.primaryContainer,
              foregroundColor: scheme.onPrimaryContainer,
              child: const Icon(Icons.check_circle_outline),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Included with Base Club Tools',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Membership types are always available for clubs. Clubs can define levels, fees, terms, approval rules, and public availability.',
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      const _MembershipFeatureChip(
                        label: 'Membership Types',
                        enabled: true,
                      ),
                      _MembershipFeatureChip(
                        label: 'Auto-renew',
                        enabled: membershipManagementAddonEnabled,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MembershipFeatureChip extends StatelessWidget {
  const _MembershipFeatureChip({required this.label, required this.enabled});

  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Chip(
      avatar: Icon(
        enabled ? Icons.check_circle_outline : Icons.lock_outline,
        size: 18,
      ),
      label: Text(label),
      backgroundColor: enabled
          ? scheme.primaryContainer
          : scheme.surfaceContainerHighest,
      side: BorderSide(color: enabled ? scheme.primary : scheme.outlineVariant),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _MembershipPaymentSettingsCard extends StatelessWidget {
  const _MembershipPaymentSettingsCard({
    required this.allowCheckPayments,
    required this.isSaving,
    required this.onAllowCheckPaymentsChanged,
  });

  final bool allowCheckPayments;
  final bool isSaving;
  final ValueChanged<bool> onAllowCheckPaymentsChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: scheme.primaryContainer,
                  foregroundColor: scheme.onPrimaryContainer,
                  child: const Icon(Icons.payments_outlined),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Membership Payment Options',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Control whether applicants can choose to mail a check instead of paying online for these membership types.',
                      ),
                    ],
                  ),
                ),
                if (isSaving)
                  const Padding(
                    padding: EdgeInsets.only(left: 12, top: 4),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Allow mailed checks'),
              subtitle: const Text(
                'When enabled, applicants can submit their membership request and mail payment to the treasurer address saved in Club Settings.',
              ),
              value: allowCheckPayments,
              onChanged: isSaving ? null : onAllowCheckPaymentsChanged,
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
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
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

class _MembershipTypeCard extends StatelessWidget {
  const _MembershipTypeCard({
    required this.type,
    required this.onEdit,
    required this.onArchiveOrRestore,
  });

  final _MembershipType type;
  final VoidCallback onEdit;
  final VoidCallback onArchiveOrRestore;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final inactiveBackground = colorScheme.errorContainer.withAlpha(
      (0.45 * 255).round(),
    );
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
                            'ARCHIVED',
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  color: colorScheme.onErrorContainer,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.8,
                                ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'This membership type is hidden from active membership options.',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: colorScheme.onErrorContainer),
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
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
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
                      case 'archive':
                        onArchiveOrRestore();
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
                  icon: Icons.confirmation_number_outlined,
                  text: type.requireArbaNumber
                      ? 'ARBA # required'
                      : 'ARBA # optional',
                ),
                _DetailText(
                  icon: Icons.autorenew,
                  text: type.allowAutoRenew
                      ? 'Auto-renew available'
                      : 'No auto-renew',
                ),
                if (type.minimumAge != null || type.maximumAge != null)
                  _DetailText(icon: Icons.cake_outlined, text: type.ageLabel),
                if (type.membershipScope == 'family')
                  _DetailText(
                    icon: Icons.family_restroom_outlined,
                    text: type.familySettingsLabel,
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
          (part) =>
              '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
        )
        .join(' ');
  }
}

class _MembershipTypeDialog extends StatefulWidget {
  const _MembershipTypeDialog({
    required this.clubId,
    required this.membershipManagementAddonEnabled,
    this.existing,
  });

  final String clubId;
  final bool membershipManagementAddonEnabled;
  final _MembershipType? existing;

  @override
  State<_MembershipTypeDialog> createState() => _MembershipTypeDialogState();
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
  late final TextEditingController _includedAdultsController;
  late final TextEditingController _includedYouthController;
  late final TextEditingController _additionalYouthPriceController;

  late String _membershipScope;
  late String _billingType;
  late String _termType;
  late bool _requiresApproval;
  late bool _requireArbaNumber;
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
    _descriptionController = TextEditingController(
      text: existing?.description ?? '',
    );
    _priceController = TextEditingController(
      text: existing == null ? '0.00' : existing.price.toStringAsFixed(2),
    );
    _currencyController = TextEditingController(
      text: existing?.currency.toUpperCase() ?? 'USD',
    );
    _termMonthsController = TextEditingController(
      text: existing?.termMonths?.toString() ?? '',
    );
    _minimumAgeController = TextEditingController(
      text: existing?.minimumAge?.toString() ?? '',
    );
    _maximumAgeController = TextEditingController(
      text: existing?.maximumAge?.toString() ?? '',
    );
    _includedAdultsController = TextEditingController(
      text: existing?.familyIncludedAdults?.toString() ?? '2',
    );
    _includedYouthController = TextEditingController(
      text: existing?.familyIncludedYouth?.toString() ?? '0',
    );
    _additionalYouthPriceController = TextEditingController(
      text: existing?.familyAdditionalYouthPrice == null
          ? '5.00'
          : existing!.familyAdditionalYouthPrice!.toStringAsFixed(2),
    );

    _membershipScope = _normalizedMembershipScope(
      existing?.membershipScope ?? 'individual',
    );
    _billingType = existing?.billingType ?? 'one_time';
    _termType = existing?.termType ?? 'rolling_year';
    _requiresApproval = existing?.requiresApproval ?? true;
    _requireArbaNumber = existing?.requireArbaNumber ?? false;
    _allowAutoRenew =
        widget.membershipManagementAddonEnabled &&
        (existing?.allowAutoRenew ?? false);
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
    _includedAdultsController.dispose();
    _includedYouthController.dispose();
    _additionalYouthPriceController.dispose();
    super.dispose();
  }

  void _setBillingType(String value) {
    setState(() {
      _billingType = value;

      if (value != 'recurring') {
        _allowAutoRenew = false;
      } else if (widget.membershipManagementAddonEnabled) {
        _allowAutoRenew = true;
      }

      if (value == 'lifetime') {
        _termType = 'lifetime';
        _termMonthsController.clear();
      }
    });
  }

  void _setTermType(String value) {
    setState(() {
      _termType = value;
    });
  }

  void _setMembershipScope(String value) {
    setState(() {
      _membershipScope = value;

      if (value == 'family') {
        if (_includedAdultsController.text.trim().isEmpty) {
          _includedAdultsController.text = '2';
        }
        if (_includedYouthController.text.trim().isEmpty) {
          _includedYouthController.text = '0';
        }
        if (_additionalYouthPriceController.text.trim().isEmpty) {
          _additionalYouthPriceController.text = '5.00';
        }
      }
    });
  }

  bool get _canAllowAutoRenew {
    return widget.membershipManagementAddonEnabled &&
        _billingType == 'recurring' &&
        _termType != 'lifetime';
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
      'require_arba_number': _requireArbaNumber,
      'allow_auto_renew': _canAllowAutoRenew && _allowAutoRenew,
      'is_public': _isPublic,
      'is_active': _isActive,
      'settings': _buildSettingsPayload(),
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
                        'Suggested abbreviations: ADT = Adult, CPL = Couple, '
                        'YTH = Youth, FAM = Family, ASC = Associate, LIFE = Lifetime',
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
                      child: Text('Individual / Single Adult'),
                    ),
                    DropdownMenuItem(
                      value: 'couple',
                      child: Text('Couple / Married Couple'),
                    ),
                    DropdownMenuItem(value: 'youth', child: Text('Youth')),
                    DropdownMenuItem(value: 'family', child: Text('Family')),
                    DropdownMenuItem(
                      value: 'associate',
                      child: Text('Associate'),
                    ),
                    DropdownMenuItem(
                      value: 'lifetime',
                      child: Text('Lifetime'),
                    ),
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
                            _setMembershipScope(value);
                          }
                        },
                ),
                const SizedBox(height: 8),
                _ScopeHelpCard(scope: _membershipScope),
                const SizedBox(height: 14),
                if (_membershipScope == 'family') ...[
                  _FamilySettingsCard(
                    includedAdultsController: _includedAdultsController,
                    includedYouthController: _includedYouthController,
                    additionalYouthPriceController:
                        _additionalYouthPriceController,
                    validator: _optionalNonNegativeInt,
                  ),
                  const SizedBox(height: 14),
                ],
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
                            _setBillingType(value);
                          }
                        },
                ),
                const SizedBox(height: 8),
                _BillingHelpCard(billingType: _billingType),
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
                            _setTermType(value);
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
                              final price = double.tryParse(
                                value?.trim() ?? '',
                              );
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
                      : (value) => setState(() => _requiresApproval = value),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Require ARBA number'),
                  subtitle: const Text(
                    'Applicants must enter an ARBA number for this membership type.',
                  ),
                  value: _requireArbaNumber,
                  onChanged: _isSaving
                      ? null
                      : (value) => setState(() => _requireArbaNumber = value),
                ),
                if (_billingType == 'recurring')
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Allow auto-renew'),
                    subtitle: Text(
                      widget.membershipManagementAddonEnabled
                          ? 'Members may choose recurring automatic renewal for this membership type.'
                          : 'Auto-renew requires the Membership Management Add-on.',
                    ),
                    value: _canAllowAutoRenew && _allowAutoRenew,
                    onChanged: _isSaving || !_canAllowAutoRenew
                        ? null
                        : (value) => setState(() => _allowAutoRenew = value),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: _MutedInfoRow(
                      icon: Icons.autorenew,
                      text:
                          'Auto-renew is only available when Billing type is Recurring.',
                    ),
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
                  title: const Text('Archived'),
                  subtitle: const Text(
                    'Archived membership types are hidden from active membership options but kept for historical records.',
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

  Map<String, dynamic>? _buildSettingsPayload() {
    if (_membershipScope != 'family') return null;

    return {
      'included_adults': _nullableInt(_includedAdultsController.text) ?? 2,
      'included_youth': _nullableInt(_includedYouthController.text) ?? 0,
      'additional_youth_price':
          double.tryParse(_additionalYouthPriceController.text.trim()) ?? 0,
    };
  }

  String _normalizedMembershipScope(String value) {
    switch (value.trim().toLowerCase()) {
      case 'adult':
      case 'single_adult':
      case 'single adult':
        return 'individual';
      case 'married_couple':
      case 'married couple':
      case 'couples':
        return 'couple';
      case 'life':
      case 'lifetime_member':
      case 'lifetime member':
        return 'lifetime';
      default:
        return value.trim().isEmpty ? 'individual' : value.trim().toLowerCase();
    }
  }
}

class _ScopeHelpCard extends StatelessWidget {
  const _ScopeHelpCard({required this.scope});

  final String scope;

  @override
  Widget build(BuildContext context) {
    final text = switch (scope) {
      'individual' =>
        'Use for a single adult membership, such as ISRBA Single Adult.',
      'couple' =>
        'Use for two adults on one membership, such as ISRBA Married Couple.',
      'youth' =>
        'Use for a youth membership. Minimum and maximum age can be set below.',
      'family' =>
        'Use for household memberships. The application form can include additional saved people for this type.',
      'associate' =>
        'Use for non-voting, associate, or supporting memberships.',
      'lifetime' =>
        'Use for lifetime memberships. Consider setting Billing type and Term type to Lifetime.',
      'organization' =>
        'Use for clubs, businesses, or organizations instead of individuals.',
      _ =>
        'Use for any membership structure that does not fit the standard scopes.',
    };

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}

class _BillingHelpCard extends StatelessWidget {
  const _BillingHelpCard({required this.billingType});

  final String billingType;

  @override
  Widget build(BuildContext context) {
    final text = switch (billingType) {
      'one_time' =>
        'Use for annual dues paid once per term. Members will need to renew manually.',
      'recurring' =>
        'Use when members can opt into automatic renewal through the Membership Management Add-on.',
      'lifetime' =>
        'Use for lifetime memberships. Term type will be set to Lifetime and auto-renew is disabled.',
      'manual' =>
        'Use when the club records payment manually instead of collecting online dues.',
      _ => 'Choose how this membership type should be billed.',
    };

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.payments_outlined, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}

class _MutedInfoRow extends StatelessWidget {
  const _MutedInfoRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: scheme.onSurfaceVariant),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

class _FamilySettingsCard extends StatelessWidget {
  const _FamilySettingsCard({
    required this.includedAdultsController,
    required this.includedYouthController,
    required this.additionalYouthPriceController,
    required this.validator,
  });

  final TextEditingController includedAdultsController;
  final TextEditingController includedYouthController;
  final TextEditingController additionalYouthPriceController;
  final String? Function(String?) validator;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.family_restroom_outlined, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Family membership settings',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'The base price covers the included adults and youth. Additional youth can be charged separately during application.',
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 560;
                final width = wide
                    ? (constraints.maxWidth - 24) / 3
                    : constraints.maxWidth;

                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: width,
                      child: TextFormField(
                        controller: includedAdultsController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Included adults',
                          border: OutlineInputBorder(),
                        ),
                        validator: validator,
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: TextFormField(
                        controller: includedYouthController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Included youth',
                          border: OutlineInputBorder(),
                        ),
                        validator: validator,
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: TextFormField(
                        controller: additionalYouthPriceController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Additional youth price',
                          prefixText: r'$ ',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          final price = double.tryParse(value?.trim() ?? '');
                          if (price == null || price < 0) {
                            return 'Enter a valid price.';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
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
    required this.requireArbaNumber,
    required this.allowAutoRenew,
    required this.isPublic,
    required this.isActive,
    required this.settings,
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
  final bool requireArbaNumber;
  final bool allowAutoRenew;
  final bool isPublic;
  final bool isActive;
  final Map<String, dynamic> settings;

  String get priceLabel {
    final symbol = currency.toLowerCase() == 'usd' ? r'$' : '';
    return '$symbol${price.toStringAsFixed(2)} ${currency.toUpperCase()}'
        .trim();
  }

  String get ageLabel {
    if (minimumAge != null && maximumAge != null) {
      return 'Ages $minimumAge–$maximumAge';
    }
    if (minimumAge != null) return 'Age $minimumAge+';
    if (maximumAge != null) return 'Up to age $maximumAge';
    return 'No age limit';
  }

  int? get familyIncludedAdults => _settingsInt('included_adults');
  int? get familyIncludedYouth => _settingsInt('included_youth');

  double? get familyAdditionalYouthPrice {
    final value = settings['additional_youth_price'];
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  String get familySettingsLabel {
    final adults = familyIncludedAdults ?? 2;
    final youth = familyIncludedYouth ?? 0;
    final additionalYouth = familyAdditionalYouthPrice ?? 0;

    return '$adults adult${adults == 1 ? '' : 's'}, '
        '$youth youth included, '
        '\$${additionalYouth.toStringAsFixed(2)} per extra youth';
  }

  int? _settingsInt(String key) {
    final value = settings[key];
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '');
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
      requireArbaNumber: json['require_arba_number'] == true,
      allowAutoRenew: json['allow_auto_renew'] == true,
      isPublic: json['is_public'] == true,
      isActive: json['is_active'] == true,
      settings: _settingsMap(json['settings']),
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

  static Map<String, dynamic> _settingsMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return const <String, dynamic>{};
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(label: Text(label), visualDensity: VisualDensity.compact);
  }
}

class _DetailText extends StatelessWidget {
  const _DetailText({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [Icon(icon, size: 18), const SizedBox(width: 6), Text(text)],
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
