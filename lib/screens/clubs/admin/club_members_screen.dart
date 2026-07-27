// lib/screens/clubs/admin/club_members_screen.dart

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:xml/xml.dart';

import '../../../models/clubs/club_summary.dart';

class ClubMembersScreen extends StatefulWidget {
  const ClubMembersScreen({
    super.key,
    required this.club,
    this.openMembershipListUpload = false,
  });

  final ClubSummary club;
  final bool openMembershipListUpload;

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
    if (widget.openMembershipListUpload) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openMembershipListUpload();
      });
    }
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
              'arba_number,'
              'address_line1,address_line2,city,state,postal_code,country,'
              'date_of_birth,status,joined_at,current_term_start,'
              'current_term_end,auto_renew,recommendation,source,notes,created_at',
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
            (row) =>
                _MembershipTypeOption.fromJson(Map<String, dynamic>.from(row)),
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

  Future<void> _openMembershipListUpload() async {
    try {
      final selection = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['xlsx', 'csv'],
        withData: true,
      );
      final file = selection?.files.singleOrNull;
      final bytes = file?.bytes;
      if (file == null || bytes == null) return;

      final rows = _readMembershipRows(
        bytes: bytes,
        extension: file.extension ?? '',
      );
      if (rows.isEmpty) {
        throw const FormatException(
          'No membership rows were found in that file.',
        );
      }

      if (!mounted) return;
      final changed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _MembershipListUploadDialog(
          clubId: widget.club.clubId,
          rows: rows,
          membershipTypes: _membershipTypes,
          existingMembers: _members,
        ),
      );
      if (changed == true) await _loadData();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to read membership list: $error')),
      );
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
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
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
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
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
  const _MemberCard({required this.member, required this.onEdit});

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
                  CircleAvatar(child: Text(member.initials)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          member.fullName,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
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
                _MemberDetail(icon: Icons.email_outlined, text: member.email!),
              if (member.phone != null)
                _MemberDetail(icon: Icons.phone_outlined, text: member.phone!),
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
  late final TextEditingController _arbaNumberController;
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
  late final TextEditingController _recommendationController;
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

    _membershipNumberController = TextEditingController(
      text: existing?.membershipNumber ?? '',
    );
    _firstNameController = TextEditingController(
      text: existing?.firstName ?? '',
    );
    _lastNameController = TextEditingController(text: existing?.lastName ?? '');
    _showingNameController = TextEditingController(
      text: existing?.showingName ?? '',
    );
    _arbaNumberController = TextEditingController(
      text: existing?.arbaNumber ?? '',
    );
    _emailController = TextEditingController(text: existing?.email ?? '');
    _phoneController = TextEditingController(text: existing?.phone ?? '');
    _addressLine1Controller = TextEditingController(
      text: existing?.addressLine1 ?? '',
    );
    _addressLine2Controller = TextEditingController(
      text: existing?.addressLine2 ?? '',
    );
    _cityController = TextEditingController(text: existing?.city ?? '');
    _stateController = TextEditingController(text: existing?.state ?? '');
    _postalCodeController = TextEditingController(
      text: existing?.postalCode ?? '',
    );
    _countryController = TextEditingController(text: existing?.country ?? 'US');
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
    _recommendationController = TextEditingController(
      text: existing?.recommendation ?? '',
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
    _arbaNumberController.dispose();
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
    _recommendationController.dispose();
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
      'arba_number': _nullIfBlank(_arbaNumberController.text),
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
      'recommendation': _nullIfBlank(_recommendationController.text),
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
                      controller: _arbaNumberController,
                      decoration: const InputDecoration(
                        labelText: 'ARBA number',
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
                  controller: _recommendationController,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Recommendation (optional)',
                    border: OutlineInputBorder(),
                  ),
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
    this.arbaNumber,
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
    this.recommendation,
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
  final String? arbaNumber;
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
  final String? recommendation;
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
      arbaNumber: _nullableString(json['arba_number']),
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
      recommendation: _nullableString(json['recommendation']),
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

class _MembershipListUploadDialog extends StatefulWidget {
  const _MembershipListUploadDialog({
    required this.clubId,
    required this.rows,
    required this.membershipTypes,
    required this.existingMembers,
  });

  final String clubId;
  final List<_ImportedMembershipRow> rows;
  final List<_MembershipTypeOption> membershipTypes;
  final List<_ClubMember> existingMembers;

  @override
  State<_MembershipListUploadDialog> createState() =>
      _MembershipListUploadDialogState();
}

class _MembershipListUploadDialogState
    extends State<_MembershipListUploadDialog> {
  final _supabase = Supabase.instance.client;
  late final Map<String, String?> _typeMapping;
  int _previewRowLimit = 25;
  bool _isImporting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final categories =
        widget.rows
            .map((row) => row.membershipCategory)
            .whereType<String>()
            .toSet()
            .toList()
          ..sort();
    _typeMapping = {
      for (final category in categories)
        category: _matchingMembershipTypeId(category),
    };
  }

  String? _matchingMembershipTypeId(String category) {
    final normalized = _normalizeLabel(category);
    for (final type in widget.membershipTypes.where((type) => type.isActive)) {
      if (_normalizeLabel(type.name) == normalized) return type.id;
    }
    return null;
  }

  List<_ImportedMembershipRow> get _validRows => widget.rows
      .where(
        (row) =>
            row.firstName != null &&
            row.lastName != null &&
            row.membershipCategory != null &&
            _typeMapping[row.membershipCategory] != null,
      )
      .toList();

  Future<void> _import() async {
    if (_isImporting) return;
    final unmapped = _typeMapping.entries
        .where((entry) => entry.value == null)
        .map((entry) => entry.key)
        .toList();
    if (unmapped.isNotEmpty) {
      setState(() {
        _errorMessage =
            'Choose a Club membership type for: ${unmapped.join(', ')}.';
      });
      return;
    }

    if (_duplicateRows.isNotEmpty) {
      setState(() {
        _errorMessage =
            'The upload has repeated source rows. Review the row numbers below before importing.';
      });
      return;
    }

    setState(() {
      _isImporting = true;
      _errorMessage = null;
    });
    try {
      for (final row in _validRows) {
        final existing = _existingMatchFor(row);
        final typeId = _typeMapping[row.membershipCategory]!;
        final expired =
            row.expireDate != null &&
            row.expireDate!.isBefore(
              DateTime.now().copyWith(
                hour: 0,
                minute: 0,
                second: 0,
                millisecond: 0,
                microsecond: 0,
              ),
            );
        final payload = <String, dynamic>{
          'club_id': widget.clubId,
          'membership_type_id': typeId,
          'membership_number': row.membershipNumber,
          'first_name': row.firstName,
          'last_name': row.lastName,
          'showing_name': row.showingName,
          'arba_number': row.arbaNumber,
          'email': row.email,
          'phone': row.phone,
          'address_line1': row.address,
          'city': row.city,
          'state': row.state,
          'postal_code': row.postalCode,
          'country': 'US',
          'date_of_birth': _dateStorageValue(row.birthDate),
          'joined_at': _dateStorageValue(row.joinedDate),
          'current_term_start': _dateStorageValue(row.joinedDate),
          'current_term_end': _dateStorageValue(row.expireDate),
          'status': expired ? 'expired' : 'active',
          'recommendation': row.recommendation,
          // Keep this aligned with the membership source values enforced by
          // the database. The screen itself supplies the one-time-list context.
          'source': 'import',
        };
        if (existing == null) {
          await _supabase.from('club_memberships').insert(payload);
        } else {
          await _supabase
              .from('club_memberships')
              .update(payload)
              .eq('id', existing.id)
              .eq('club_id', widget.clubId);
        }
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isImporting = false;
        _errorMessage = 'Unable to save the membership list: $error';
      });
    }
  }

  _ClubMember? _existingMatchFor(_ImportedMembershipRow row) {
    List<_ClubMember> matchesFor(bool Function(_ClubMember member) test) =>
        widget.existingMembers.where(test).toList();

    if (row.membershipNumber != null) {
      final matches = matchesFor(
        (member) =>
            member.membershipNumber != null &&
            _normalizeLabel(row.membershipNumber!) ==
                _normalizeLabel(member.membershipNumber!),
      );
      if (matches.length == 1) return matches.single;
    }
    if (row.email != null) {
      final matches = matchesFor(
        (member) =>
            member.email != null &&
            _normalizeLabel(row.email!) == _normalizeLabel(member.email!),
      );
      if (matches.length == 1) return matches.single;
    }
    if (row.showingName != null) {
      final matches = matchesFor(
        (member) =>
            member.showingName != null &&
            _normalizeLabel(row.showingName!) ==
                _normalizeLabel(member.showingName!),
      );
      if (matches.length == 1) return matches.single;
    }
    final matches = matchesFor(
      (member) =>
          _normalizeLabel(row.fullName) == _normalizeLabel(member.fullName),
    );
    return matches.length == 1 ? matches.single : null;
  }

  List<List<_ImportedMembershipRow>> get _duplicateRows {
    final rowsByIdentity = <String, List<_ImportedMembershipRow>>{};
    for (final row in _validRows) {
      final key = row.identityKey;
      if (key != null) {
        (rowsByIdentity[key] ??= <_ImportedMembershipRow>[]).add(row);
      }
    }
    return rowsByIdentity.values.where((rows) => rows.length > 1).toList();
  }

  @override
  Widget build(BuildContext context) {
    final mappedRows = _validRows.length;
    final categories = _typeMapping.keys.toList()..sort();
    final previewRows = _previewRowLimit == 0
        ? widget.rows
        : widget.rows.take(_previewRowLimit).toList();
    return AlertDialog(
      title: const Text('Review Membership List Upload'),
      content: SizedBox(
        width: 840,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Nothing is saved until you confirm this import. A member is updated only when one clear match is found by membership number, email, showing name, or full name; otherwise a new member is created.',
              ),
              const SizedBox(height: 16),
              Text(
                '${widget.rows.length} rows found • $mappedRows ready to import',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 14),
              const _SectionTitle('Map the Member column'),
              const Text(
                'The spreadsheet’s Member value identifies Open or Youth. Choose the matching club membership type for each value.',
              ),
              const SizedBox(height: 12),
              for (final category in categories) ...[
                DropdownButtonFormField<String?>(
                  initialValue: _typeMapping[category],
                  decoration: InputDecoration(
                    labelText: '$category → Club membership type',
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Choose membership type'),
                    ),
                    for (final type in widget.membershipTypes.where(
                      (type) => type.isActive,
                    ))
                      DropdownMenuItem<String?>(
                        value: type.id,
                        child: Text(type.name),
                      ),
                  ],
                  onChanged: _isImporting
                      ? null
                      : (value) =>
                            setState(() => _typeMapping[category] = value),
                ),
                const SizedBox(height: 12),
              ],
              if (_errorMessage != null) ...[
                Material(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(_errorMessage!),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (_duplicateRows.isNotEmpty) ...[
                const _SectionTitle('Possible repeated source rows'),
                const Text(
                  'These have the same name or showing name within the same Open/Youth category. Check the source list before importing.',
                ),
                const SizedBox(height: 8),
                DataTable(
                  columns: const [
                    DataColumn(label: Text('Member')),
                    DataColumn(label: Text('Name')),
                    DataColumn(label: Text('Rows')),
                  ],
                  rows: [
                    for (final matches in _duplicateRows.take(12))
                      DataRow(
                        cells: [
                          DataCell(
                            Text(matches.first.membershipCategory ?? '—'),
                          ),
                          DataCell(Text(matches.first.fullName)),
                          DataCell(
                            Text(
                              matches.map((row) => row.sourceRow).join(', '),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                if (_duplicateRows.length > 12)
                  Text(
                    'Showing 12 of ${_duplicateRows.length} possible repeats.',
                  ),
                const SizedBox(height: 12),
              ],
              const _SectionTitle('Preview'),
              if (widget.rows.length > 25) ...[
                DropdownButtonFormField<int>(
                  initialValue: _previewRowLimit,
                  decoration: const InputDecoration(
                    labelText: 'Rows to show',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 25, child: Text('25 rows')),
                    DropdownMenuItem(value: 50, child: Text('50 rows')),
                    DropdownMenuItem(value: 100, child: Text('100 rows')),
                    DropdownMenuItem(value: 0, child: Text('All rows')),
                  ],
                  onChanged: _isImporting
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() => _previewRowLimit = value);
                          }
                        },
                ),
                const SizedBox(height: 12),
              ],
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Member')),
                    DataColumn(label: Text('Name')),
                    DataColumn(label: Text('Showing name')),
                    DataColumn(label: Text('Expires')),
                    DataColumn(label: Text('Status')),
                  ],
                  rows: [
                    for (final row in previewRows)
                      DataRow(
                        cells: [
                          DataCell(Text(row.membershipCategory ?? 'Missing')),
                          DataCell(Text(row.fullName)),
                          DataCell(Text(row.showingName ?? '—')),
                          DataCell(Text(_dateText(row.expireDate))),
                          DataCell(
                            Text(
                              row.expireDate != null &&
                                      row.expireDate!.isBefore(DateTime.now())
                                  ? 'Expired'
                                  : 'Active',
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              if (previewRows.length < widget.rows.length)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Showing the first ${previewRows.length} of ${widget.rows.length} rows.',
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isImporting
              ? null
              : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _isImporting ? null : _import,
          icon: _isImporting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.upload_outlined),
          label: Text(_isImporting ? 'Importing...' : 'Import members'),
        ),
      ],
    );
  }
}

class _ImportedMembershipRow {
  const _ImportedMembershipRow({
    required this.sourceRow,
    this.membershipCategory,
    this.membershipNumber,
    this.firstName,
    this.lastName,
    this.showingName,
    this.arbaNumber,
    this.birthDate,
    this.address,
    this.city,
    this.state,
    this.postalCode,
    this.phone,
    this.expireDate,
    this.recommendation,
    this.joinedDate,
    this.email,
  });

  final String? membershipCategory;
  final int sourceRow;
  final String? membershipNumber;
  final String? firstName;
  final String? lastName;
  final String? showingName;
  final String? arbaNumber;
  final DateTime? birthDate;
  final String? address;
  final String? city;
  final String? state;
  final String? postalCode;
  final String? phone;
  final DateTime? expireDate;
  final String? recommendation;
  final DateTime? joinedDate;
  final String? email;

  String get fullName => '${firstName ?? ''} ${lastName ?? ''}'.trim();

  String? get identityKey {
    final category = membershipCategory == null
        ? ''
        : '${_normalizeLabel(membershipCategory!)}|';
    if (membershipNumber != null) {
      return '${category}number:${_normalizeLabel(membershipNumber!)}';
    }
    if (showingName != null) {
      return '${category}show:${_normalizeLabel(showingName!)}';
    }
    if (fullName.isNotEmpty) {
      return '${category}name:${_normalizeLabel(fullName)}';
    }
    return email == null ? null : '${category}email:${_normalizeLabel(email!)}';
  }

  factory _ImportedMembershipRow.fromColumns(
    Map<String, String> columns, {
    required int sourceRow,
  }) {
    String? value(String label) {
      final text = columns[_normalizeLabel(label)]?.trim();
      return text == null || text.isEmpty ? null : text;
    }

    return _ImportedMembershipRow(
      sourceRow: sourceRow,
      membershipCategory: value('Member'),
      membershipNumber: value('Member Number'),
      firstName: value('FirstName'),
      lastName: value('LastName'),
      showingName: value('Showing Name'),
      arbaNumber: value('ARBA'),
      birthDate: _importDate(value('Y Birthdate')),
      address: value('Address'),
      city: value('City'),
      state: value('State'),
      postalCode: value('ZIP'),
      phone: value('HomePhone'),
      expireDate: _importDate(value('ExpireDate')),
      recommendation: value('recommend'),
      joinedDate: _importDate(value('JOINED')),
      email: value('email'),
    );
  }
}

class _MemberDetail extends StatelessWidget {
  const _MemberDetail({required this.icon, required this.text});

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
            for (final child in children) SizedBox(width: width, child: child),
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
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
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
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
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

List<_ImportedMembershipRow> _readMembershipRows({
  required Uint8List bytes,
  required String extension,
}) {
  final normalizedExtension = extension.trim().toLowerCase();
  final List<List<String>> table;
  if (normalizedExtension == 'xlsx') {
    table = _readXlsxRows(bytes);
  } else if (normalizedExtension == 'csv') {
    table = _readCsvRows(utf8.decode(bytes, allowMalformed: true));
  } else {
    throw const FormatException('Choose an .xlsx or .csv membership list.');
  }

  if (table.isEmpty) return const [];
  final headers = table.first.map(_normalizeLabel).toList(growable: false);
  if (!headers.contains(_normalizeLabel('Member')) ||
      !headers.contains(_normalizeLabel('FirstName')) ||
      !headers.contains(_normalizeLabel('LastName'))) {
    throw const FormatException(
      'The list needs Member, FirstName, and LastName column headers.',
    );
  }

  final importedRows = <_ImportedMembershipRow>[];
  for (var rowIndex = 1; rowIndex < table.length; rowIndex++) {
    final row = table[rowIndex];
    if (!row.any((cell) => cell.trim().isNotEmpty)) continue;
    final columns = <String, String>{
      for (var index = 0; index < headers.length; index++)
        headers[index]: index < row.length ? row[index].trim() : '',
    };
    importedRows.add(
      _ImportedMembershipRow.fromColumns(columns, sourceRow: rowIndex + 1),
    );
  }
  return importedRows;
}

List<List<String>> _readXlsxRows(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  ArchiveFile? fileNamed(String name) {
    for (final file in archive.files) {
      if (file.name == name) return file;
    }
    return null;
  }

  String fileText(String name) {
    final file = fileNamed(name);
    if (file == null) return '';
    return utf8.decode(file.content, allowMalformed: true);
  }

  final sharedStrings = <String>[];
  final sharedText = fileText('xl/sharedStrings.xml');
  if (sharedText.isNotEmpty) {
    final document = XmlDocument.parse(sharedText);
    for (final node in document.findAllElements('si')) {
      sharedStrings.add(
        node.descendants.whereType<XmlText>().map((text) => text.value).join(),
      );
    }
  }

  ArchiveFile? sheetFile;
  for (final file in archive.files) {
    if (RegExp(r'^xl/worksheets/sheet\d+\.xml$').hasMatch(file.name)) {
      sheetFile = file;
      break;
    }
  }
  if (sheetFile == null) {
    throw const FormatException(
      'The workbook does not contain a readable worksheet.',
    );
  }
  final sheet = XmlDocument.parse(
    utf8.decode(sheetFile.content, allowMalformed: true),
  );
  final rows = <List<String>>[];
  for (final rowNode in sheet.findAllElements('row')) {
    final cells = <int, String>{};
    var nextColumn = 0;
    for (final cell in rowNode.findElements('c')) {
      final reference = cell.getAttribute('r') ?? '';
      final column = _xlsxColumnIndex(reference) ?? nextColumn;
      nextColumn = column + 1;
      final type = cell.getAttribute('t');
      final raw = cell.getElement('v')?.innerText ?? '';
      String value = raw;
      if (type == 's') {
        final index = int.tryParse(raw);
        if (index != null && index >= 0 && index < sharedStrings.length) {
          value = sharedStrings[index];
        }
      } else if (type == 'inlineStr') {
        value = cell.findAllElements('t').map((node) => node.innerText).join();
      }
      cells[column] = value;
    }
    if (cells.isEmpty) continue;
    final lastColumn = cells.keys.reduce((a, b) => a > b ? a : b);
    rows.add(
      List<String>.generate(lastColumn + 1, (index) => cells[index] ?? ''),
    );
  }
  return rows;
}

int? _xlsxColumnIndex(String reference) {
  final letters = RegExp(
    r'^[A-Z]+',
    caseSensitive: false,
  ).firstMatch(reference)?.group(0);
  if (letters == null) return null;
  var value = 0;
  for (final code in letters.toUpperCase().codeUnits) {
    value = value * 26 + (code - 64);
  }
  return value - 1;
}

List<List<String>> _readCsvRows(String source) {
  final rows = <List<String>>[];
  var row = <String>[];
  var field = StringBuffer();
  var quoted = false;
  for (var index = 0; index < source.length; index++) {
    final character = source[index];
    if (character == '"') {
      if (quoted && index + 1 < source.length && source[index + 1] == '"') {
        field.write('"');
        index++;
      } else {
        quoted = !quoted;
      }
    } else if (character == ',' && !quoted) {
      row.add(field.toString());
      field = StringBuffer();
    } else if ((character == '\n' || character == '\r') && !quoted) {
      if (character == '\r' &&
          index + 1 < source.length &&
          source[index + 1] == '\n') {
        index++;
      }
      row.add(field.toString());
      rows.add(row);
      row = <String>[];
      field = StringBuffer();
    } else {
      field.write(character);
    }
  }
  if (field.isNotEmpty || row.isNotEmpty) {
    row.add(field.toString());
    rows.add(row);
  }
  return rows;
}

String _normalizeLabel(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');

DateTime? _importDate(String? value) {
  final text = value?.trim();
  if (text == null || text.isEmpty) return null;

  // Excel commonly stores a date as a serial number (days since 1899-12-30).
  // Support that form as well as the human-readable dates in CSV exports.
  final excelSerial = double.tryParse(text);
  if (excelSerial != null && excelSerial >= 1 && excelSerial <= 100000) {
    return DateTime(1899, 12, 30).add(Duration(days: excelSerial.floor()));
  }

  final isoDate = DateTime.tryParse(text);
  if (isoDate != null) {
    return DateTime(isoDate.year, isoDate.month, isoDate.day);
  }
  final match = RegExp(
    r'^(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})$',
  ).firstMatch(text);
  if (match == null) return null;
  final month = int.parse(match.group(1)!);
  final day = int.parse(match.group(2)!);
  var year = int.parse(match.group(3)!);
  if (year < 100) year += year >= 70 ? 1900 : 2000;
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  return DateTime(year, month, day);
}

String? _dateStorageValue(DateTime? value) =>
    value == null ? null : _dateText(value);
