// lib/screens/clubs/admin/club_members_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/clubs/club_summary.dart';

class ClubMembersScreen extends StatefulWidget {
  const ClubMembersScreen({
    super.key,
    required this.club,
  });

  final ClubSummary club;

  @override
  State<ClubMembersScreen> createState() => _ClubMembersScreenState();
}

class _ClubMembersScreenState extends State<ClubMembersScreen> {
  final _supabase = Supabase.instance.client;
  final _searchController = TextEditingController();

  bool _isLoading = true;
  String? _errorMessage;
  String _statusFilter = 'all';
  List<_ClubMember> _members = const [];
  List<_MembershipTypeOption> _membershipTypes = const [];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleSearchChanged);
    _loadData();
  }

  @override
  void dispose() {
    _searchController.removeListener(_handleSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _handleSearchChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final responses = await Future.wait([
        _supabase
            .from('club_memberships')
            .select(
              'id,club_id,user_id,exhibitor_id,membership_type_id,'
              'membership_number,first_name,last_name,showing_name,email,phone,'
              'address_line1,address_line2,city,state,postal_code,country,'
              'date_of_birth,status,joined_at,current_term_start,'
              'current_term_end,auto_renew,source,notes,created_at',
            )
            .eq('club_id', widget.club.clubId)
            .order('last_name', ascending: true)
            .order('first_name', ascending: true),
        _supabase
            .from('club_membership_types')
            .select('id,name,is_active')
            .eq('club_id', widget.club.clubId)
            .order('name', ascending: true),
      ]);

      final memberRows = responses[0] as List;
      final typeRows = responses[1] as List;

      final types = typeRows
          .whereType<Map>()
          .map(
            (row) => _MembershipTypeOption.fromJson(
              Map<String, dynamic>.from(row),
            ),
          )
          .toList();

      final typeNames = <String, String>{
        for (final type in types) type.id: type.name,
      };

      final members = memberRows
          .whereType<Map>()
          .map(
            (row) => _ClubMember.fromJson(
              Map<String, dynamic>.from(row),
              membershipTypeName:
                  typeNames[row['membership_type_id']?.toString()],
            ),
          )
          .toList();

      if (!mounted) return;

      setState(() {
        _membershipTypes = types;
        _members = members;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _errorMessage = 'Unable to load members: $error';
      });
    }
  }

  List<_ClubMember> get _filteredMembers {
    final query = _searchController.text.trim().toLowerCase();

    return _members.where((member) {
      final matchesStatus =
          _statusFilter == 'all' || member.status == _statusFilter;

      if (!matchesStatus) return false;
      if (query.isEmpty) return true;

      final searchable = [
        member.fullName,
        member.showingName,
        member.email,
        member.membershipNumber,
        member.membershipTypeName,
      ].whereType<String>().join(' ').toLowerCase();

      return searchable.contains(query);
    }).toList();
  }

  Future<void> _openEditor({_ClubMember? existing}) async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ClubMemberDialog(
        clubId: widget.club.clubId,
        membershipTypes: _membershipTypes,
        existing: existing,
      ),
    );

    if (changed == true) {
      await _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Members'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _loadData,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Add Member'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null && _members.isEmpty) {
      return _MessageState(
        icon: Icons.error_outline,
        title: 'Unable to load members',
        message: _errorMessage!,
        actionLabel: 'Try Again',
        onAction: _loadData,
      );
    }

    final filtered = _filteredMembers;

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          Text(
            widget.club.clubName,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'Search, review, and manage this club’s membership records.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              labelText: 'Search members',
              hintText: 'Name, email, showing name, or membership number',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: _searchController.clear,
                      icon: const Icon(Icons.clear),
                    ),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'all', label: Text('All')),
                ButtonSegment(value: 'pending', label: Text('Pending')),
                ButtonSegment(value: 'active', label: Text('Active')),
                ButtonSegment(value: 'expiring', label: Text('Expiring')),
                ButtonSegment(value: 'expired', label: Text('Expired')),
                ButtonSegment(value: 'suspended', label: Text('Suspended')),
              ],
              selected: {_statusFilter},
              onSelectionChanged: (values) {
                setState(() {
                  _statusFilter = values.first;
                });
              },
            ),
          ),
          const SizedBox(height: 16),
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
          Row(
            children: [
              Text(
                '${filtered.length} ${filtered.length == 1 ? 'member' : 'members'}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_members.isEmpty)
            _InlineEmptyState(
              title: 'No members yet',
              message:
                  'Add the club’s first member to begin building the membership roster.',
              actionLabel: 'Add Member',
              onAction: () => _openEditor(),
            )
          else if (filtered.isEmpty)
            const _InlineEmptyState(
              title: 'No matching members',
              message: 'Try a different search or status filter.',
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final useTwoColumns = constraints.maxWidth >= 900;
                final width = useTwoColumns
                    ? (constraints.maxWidth - 12) / 2
                    : constraints.maxWidth;

                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final member in filtered)
                      SizedBox(
                        width: width,
                        child: _MemberCard(
                          member: member,
                          onEdit: () => _openEditor(existing: member),
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

class _MemberCard extends StatelessWidget {
  const _MemberCard({
    required this.member,
    required this.onEdit,
  });

  final _ClubMember member;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = _statusColor(member.status, colorScheme);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    child: Text(member.initials),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          member.fullName,
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        if (member.showingName != null &&
                            member.showingName != member.fullName) ...[
                          const SizedBox(height: 2),
                          Text(member.showingName!),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Edit member',
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(
                    label: Text(_titleCase(member.status)),
                    backgroundColor: statusColor.withAlpha(40),
                    side: BorderSide(color: statusColor),
                  ),
                  if (member.membershipTypeName != null)
                    Chip(label: Text(member.membershipTypeName!)),
                  if (member.autoRenew)
                    const Chip(
                      avatar: Icon(Icons.autorenew, size: 18),
                      label: Text('Auto-renew'),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (member.membershipNumber != null)
                _MemberDetail(
                  icon: Icons.badge_outlined,
                  text: 'Member #${member.membershipNumber}',
                ),
              if (member.email != null)
                _MemberDetail(
                  icon: Icons.email_outlined,
                  text: member.email!,
                ),
              if (member.phone != null)
                _MemberDetail(
                  icon: Icons.phone_outlined,
                  text: member.phone!,
                ),
              if (member.currentTermEnd != null)
                _MemberDetail(
                  icon: Icons.event_outlined,
                  text: 'Expires ${_formatDate(member.currentTermEnd!)}',
                ),
              _MemberDetail(
                icon: Icons.source_outlined,
                text: 'Source: ${_titleCase(member.source)}',
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Color _statusColor(String status, ColorScheme scheme) {
    switch (status) {
      case 'active':
        return scheme.primary;
      case 'pending':
      case 'expiring':
        return scheme.tertiary;
      case 'expired':
      case 'suspended':
      case 'cancelled':
      case 'denied':
        return scheme.error;
      default:
        return scheme.outline;
    }
  }
}

class _ClubMemberDialog extends StatefulWidget {
  const _ClubMemberDialog({
    required this.clubId,
    required this.membershipTypes,
    this.existing,
  });

  final String clubId;
  final List<_MembershipTypeOption> membershipTypes;
  final _ClubMember? existing;

  @override
  State<_ClubMemberDialog> createState() => _ClubMemberDialogState();
}

class _ClubMemberDialogState extends State<_ClubMemberDialog> {
  final _formKey = GlobalKey<FormState>();
  final _supabase = Supabase.instance.client;

  late final TextEditingController _membershipNumberController;
  late final TextEditingController _firstNameController;
  late final TextEditingController _lastNameController;
  late final TextEditingController _showingNameController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  late final TextEditingController _addressLine1Controller;
  late final TextEditingController _addressLine2Controller;
  late final TextEditingController _cityController;
  late final TextEditingController _stateController;
  late final TextEditingController _postalCodeController;
  late final TextEditingController _countryController;
  late final TextEditingController _dateOfBirthController;
  late final TextEditingController _joinedAtController;
  late final TextEditingController _termStartController;
  late final TextEditingController _termEndController;
  late final TextEditingController _notesController;

  String? _membershipTypeId;
  late String _status;
  late bool _autoRenew;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;

    _membershipNumberController =
        TextEditingController(text: existing?.membershipNumber ?? '');
    _firstNameController =
        TextEditingController(text: existing?.firstName ?? '');
    _lastNameController =
        TextEditingController(text: existing?.lastName ?? '');
    _showingNameController =
        TextEditingController(text: existing?.showingName ?? '');
    _emailController = TextEditingController(text: existing?.email ?? '');
    _phoneController = TextEditingController(text: existing?.phone ?? '');
    _addressLine1Controller =
        TextEditingController(text: existing?.addressLine1 ?? '');
    _addressLine2Controller =
        TextEditingController(text: existing?.addressLine2 ?? '');
    _cityController = TextEditingController(text: existing?.city ?? '');
    _stateController = TextEditingController(text: existing?.state ?? '');
    _postalCodeController =
        TextEditingController(text: existing?.postalCode ?? '');
    _countryController =
        TextEditingController(text: existing?.country ?? 'US');
    _dateOfBirthController = TextEditingController(
      text: _dateText(existing?.dateOfBirth),
    );
    _joinedAtController = TextEditingController(
      text: _dateText(existing?.joinedAt),
    );
    _termStartController = TextEditingController(
      text: _dateText(existing?.currentTermStart),
    );
    _termEndController = TextEditingController(
      text: _dateText(existing?.currentTermEnd),
    );
    _notesController = TextEditingController(text: existing?.notes ?? '');

    _membershipTypeId = existing?.membershipTypeId;
    _status = existing?.status ?? 'pending';
    _autoRenew = existing?.autoRenew ?? false;
  }

  @override
  void dispose() {
    _membershipNumberController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _showingNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressLine1Controller.dispose();
    _addressLine2Controller.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _postalCodeController.dispose();
    _countryController.dispose();
    _dateOfBirthController.dispose();
    _joinedAtController.dispose();
    _termStartController.dispose();
    _termEndController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSaving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final termStart = _parseDate(_termStartController.text);
    final termEnd = _parseDate(_termEndController.text);

    if (termStart != null && termEnd != null && termEnd.isBefore(termStart)) {
      setState(() {
        _errorMessage = 'The expiration date cannot be before the start date.';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final payload = <String, dynamic>{
      'club_id': widget.clubId,
      'membership_type_id': _membershipTypeId,
      'membership_number': _nullIfBlank(_membershipNumberController.text),
      'first_name': _firstNameController.text.trim(),
      'last_name': _lastNameController.text.trim(),
      'showing_name': _nullIfBlank(_showingNameController.text),
      'email': _nullIfBlank(_emailController.text),
      'phone': _nullIfBlank(_phoneController.text),
      'address_line1': _nullIfBlank(_addressLine1Controller.text),
      'address_line2': _nullIfBlank(_addressLine2Controller.text),
      'city': _nullIfBlank(_cityController.text),
      'state': _nullIfBlank(_stateController.text),
      'postal_code': _nullIfBlank(_postalCodeController.text),
      'country': _countryController.text.trim().isEmpty
          ? 'US'
          : _countryController.text.trim().toUpperCase(),
      'date_of_birth': _dateValue(_dateOfBirthController.text),
      'status': _status,
      'joined_at': _dateValue(_joinedAtController.text),
      'current_term_start': _dateValue(_termStartController.text),
      'current_term_end': _dateValue(_termEndController.text),
      'auto_renew': _autoRenew,
      'source': widget.existing?.source ?? 'admin',
      'notes': _nullIfBlank(_notesController.text),
    };

    try {
      final existing = widget.existing;

      if (existing == null) {
        await _supabase.from('club_memberships').insert(payload);
      } else {
        await _supabase
            .from('club_memberships')
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
        _errorMessage = 'Unable to save member: $error';
      });
    }
  }

  Future<void> _pickDate(TextEditingController controller) async {
    final initial = _parseDate(controller.text) ?? DateTime.now();

    final selected = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );

    if (selected != null) {
      controller.text = _dateText(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeTypes = widget.membershipTypes
        .where((type) => type.isActive || type.id == _membershipTypeId)
        .toList();

    return AlertDialog(
      title: Text(widget.existing == null ? 'Add Member' : 'Edit Member'),
      content: SizedBox(
        width: 760,
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
                _SectionTitle('Membership'),
                DropdownButtonFormField<String?>(
                  initialValue: _membershipTypeId,
                  decoration: const InputDecoration(
                    labelText: 'Membership type',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('No membership type selected'),
                    ),
                    for (final type in activeTypes)
                      DropdownMenuItem<String?>(
                        value: type.id,
                        child: Text(
                          type.isActive ? type.name : '${type.name} (Inactive)',
                        ),
                      ),
                  ],
                  onChanged: _isSaving
                      ? null
                      : (value) => setState(() => _membershipTypeId = value),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _membershipNumberController,
                  decoration: const InputDecoration(
                    labelText: 'Membership number',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _status,
                  decoration: const InputDecoration(
                    labelText: 'Status',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'pending', child: Text('Pending')),
                    DropdownMenuItem(value: 'active', child: Text('Active')),
                    DropdownMenuItem(
                      value: 'expiring',
                      child: Text('Expiring'),
                    ),
                    DropdownMenuItem(value: 'expired', child: Text('Expired')),
                    DropdownMenuItem(
                      value: 'suspended',
                      child: Text('Suspended'),
                    ),
                    DropdownMenuItem(value: 'denied', child: Text('Denied')),
                    DropdownMenuItem(
                      value: 'cancelled',
                      child: Text('Cancelled'),
                    ),
                  ],
                  onChanged: _isSaving
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() => _status = value);
                          }
                        },
                ),
                const SizedBox(height: 18),
                _SectionTitle('Member Details'),
                _ResponsiveFields(
                  children: [
                    TextFormField(
                      controller: _firstNameController,
                      decoration: const InputDecoration(
                        labelText: 'First name',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) => _required(value, 'First name'),
                    ),
                    TextFormField(
                      controller: _lastNameController,
                      decoration: const InputDecoration(
                        labelText: 'Last name',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) => _required(value, 'Last name'),
                    ),
                    TextFormField(
                      controller: _showingNameController,
                      decoration: const InputDecoration(
                        labelText: 'Showing name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    TextFormField(
                      controller: _dateOfBirthController,
                      readOnly: true,
                      decoration: InputDecoration(
                        labelText: 'Date of birth',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          onPressed: () => _pickDate(_dateOfBirthController),
                          icon: const Icon(Icons.calendar_today_outlined),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _SectionTitle('Contact Information'),
                _ResponsiveFields(
                  children: [
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                      ),
                      validator: _optionalEmail,
                    ),
                    TextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Phone',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _SectionTitle('Address'),
                TextFormField(
                  controller: _addressLine1Controller,
                  decoration: const InputDecoration(
                    labelText: 'Address line 1',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _addressLine2Controller,
                  decoration: const InputDecoration(
                    labelText: 'Address line 2',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                _ResponsiveFields(
                  children: [
                    TextFormField(
                      controller: _cityController,
                      decoration: const InputDecoration(
                        labelText: 'City',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    TextFormField(
                      controller: _stateController,
                      decoration: const InputDecoration(
                        labelText: 'State / Province',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    TextFormField(
                      controller: _postalCodeController,
                      decoration: const InputDecoration(
                        labelText: 'Postal code',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    TextFormField(
                      controller: _countryController,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Country code',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _SectionTitle('Membership Term'),
                _ResponsiveFields(
                  children: [
                    _DateField(
                      controller: _joinedAtController,
                      label: 'Joined date',
                      onPick: () => _pickDate(_joinedAtController),
                    ),
                    _DateField(
                      controller: _termStartController,
                      label: 'Current term start',
                      onPick: () => _pickDate(_termStartController),
                    ),
                    _DateField(
                      controller: _termEndController,
                      label: 'Current term end',
                      onPick: () => _pickDate(_termEndController),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Auto-renew'),
                  subtitle: const Text(
                    'Mark that this membership is set to renew automatically.',
                  ),
                  value: _autoRenew,
                  onChanged: _isSaving
                      ? null
                      : (value) => setState(() => _autoRenew = value),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _notesController,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'Internal notes',
                    border: OutlineInputBorder(),
                  ),
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

  String? _required(String? value, String label) {
    if (value == null || value.trim().isEmpty) {
      return '$label is required.';
    }
    return null;
  }

  String? _optionalEmail(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;

    final pattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!pattern.hasMatch(text)) {
      return 'Enter a valid email address.';
    }
    return null;
  }

  String? _nullIfBlank(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  DateTime? _parseDate(String value) {
    final text = value.trim();
    return text.isEmpty ? null : DateTime.tryParse(text);
  }

  String? _dateValue(String value) {
    final date = _parseDate(value);
    return date == null ? null : _dateText(date);
  }
}

class _ClubMember {
  const _ClubMember({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.status,
    required this.autoRenew,
    required this.source,
    this.userId,
    this.exhibitorId,
    this.membershipTypeId,
    this.membershipTypeName,
    this.membershipNumber,
    this.showingName,
    this.email,
    this.phone,
    this.addressLine1,
    this.addressLine2,
    this.city,
    this.state,
    this.postalCode,
    this.country,
    this.dateOfBirth,
    this.joinedAt,
    this.currentTermStart,
    this.currentTermEnd,
    this.notes,
  });

  final String id;
  final String? userId;
  final String? exhibitorId;
  final String? membershipTypeId;
  final String? membershipTypeName;
  final String? membershipNumber;
  final String firstName;
  final String lastName;
  final String? showingName;
  final String? email;
  final String? phone;
  final String? addressLine1;
  final String? addressLine2;
  final String? city;
  final String? state;
  final String? postalCode;
  final String? country;
  final DateTime? dateOfBirth;
  final String status;
  final DateTime? joinedAt;
  final DateTime? currentTermStart;
  final DateTime? currentTermEnd;
  final bool autoRenew;
  final String source;
  final String? notes;

  String get fullName => '$firstName $lastName'.trim();

  String get initials {
    final first = firstName.isEmpty ? '' : firstName[0];
    final last = lastName.isEmpty ? '' : lastName[0];
    final result = '$first$last'.trim();
    return result.isEmpty ? 'M' : result.toUpperCase();
  }

  factory _ClubMember.fromJson(
    Map<String, dynamic> json, {
    String? membershipTypeName,
  }) {
    return _ClubMember(
      id: json['id'].toString(),
      userId: _nullableString(json['user_id']),
      exhibitorId: _nullableString(json['exhibitor_id']),
      membershipTypeId: _nullableString(json['membership_type_id']),
      membershipTypeName: membershipTypeName,
      membershipNumber: _nullableString(json['membership_number']),
      firstName: _nullableString(json['first_name']) ?? '',
      lastName: _nullableString(json['last_name']) ?? '',
      showingName: _nullableString(json['showing_name']),
      email: _nullableString(json['email']),
      phone: _nullableString(json['phone']),
      addressLine1: _nullableString(json['address_line1']),
      addressLine2: _nullableString(json['address_line2']),
      city: _nullableString(json['city']),
      state: _nullableString(json['state']),
      postalCode: _nullableString(json['postal_code']),
      country: _nullableString(json['country']),
      dateOfBirth: _nullableDate(json['date_of_birth']),
      status: _nullableString(json['status']) ?? 'pending',
      joinedAt: _nullableDate(json['joined_at']),
      currentTermStart: _nullableDate(json['current_term_start']),
      currentTermEnd: _nullableDate(json['current_term_end']),
      autoRenew: json['auto_renew'] == true,
      source: _nullableString(json['source']) ?? 'admin',
      notes: _nullableString(json['notes']),
    );
  }
}

class _MembershipTypeOption {
  const _MembershipTypeOption({
    required this.id,
    required this.name,
    required this.isActive,
  });

  final String id;
  final String name;
  final bool isActive;

  factory _MembershipTypeOption.fromJson(Map<String, dynamic> json) {
    return _MembershipTypeOption(
      id: json['id'].toString(),
      name: json['name'].toString(),
      isActive: json['is_active'] == true,
    );
  }
}

class _MemberDetail extends StatelessWidget {
  const _MemberDetail({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _ResponsiveFields extends StatelessWidget {
  const _ResponsiveFields({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 580;
        final width = wide
            ? (constraints.maxWidth - 12) / 2
            : constraints.maxWidth;

        return Wrap(
          spacing: 12,
          runSpacing: 14,
          children: [
            for (final child in children)
              SizedBox(width: width, child: child),
          ],
        );
      },
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.controller,
    required this.label,
    required this.onPick,
  });

  final TextEditingController controller;
  final String label;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      readOnly: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          onPressed: onPick,
          icon: const Icon(Icons.calendar_today_outlined),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
      ),
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
                icon: const Icon(Icons.refresh),
                label: Text(actionLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineEmptyState extends StatelessWidget {
  const _InlineEmptyState({
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            const Icon(Icons.people_outline, size: 52),
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
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.person_add_alt_1),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String? _nullableString(dynamic value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

DateTime? _nullableDate(dynamic value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) return null;
  return DateTime.tryParse(text);
}

String _dateText(DateTime? value) {
  if (value == null) return '';
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '${value.year}-$month-$day';
}

String _formatDate(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '$month/$day/${value.year}';
}

String _titleCase(String value) {
  return value
      .split(RegExp(r'[_\s-]+'))
      .where((part) => part.isNotEmpty)
      .map(
        (part) => '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
      )
      .join(' ');
}
