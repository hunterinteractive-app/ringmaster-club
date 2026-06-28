

// lib/screens/clubs/admin/club_staff_permissions_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/clubs/club_summary.dart';

class ClubStaffPermissionsScreen extends StatefulWidget {
  const ClubStaffPermissionsScreen({
    super.key,
    required this.club,
  });

  final ClubSummary club;

  @override
  State<ClubStaffPermissionsScreen> createState() =>
      _ClubStaffPermissionsScreenState();
}

class _ClubStaffPermissionsScreenState
    extends State<ClubStaffPermissionsScreen> {
  final _supabase = Supabase.instance.client;
  final _searchController = TextEditingController();

  bool _isLoading = true;
  String? _errorMessage;
  _StaffPermissionsDashboard? _dashboard;

  String? get _currentUserId => _supabase.auth.currentUser?.id;

  _ClubStaffAssignment? get _currentUserStaffAssignment {
    final userId = _currentUserId;
    final dashboard = _dashboard;
    if (userId == null || dashboard == null) return null;

    return dashboard.staff
        .where((staff) => staff.userId == userId && staff.status == 'active')
        .firstOrNull;
  }

  _ClubRole? get _currentUserRole {
    final assignment = _currentUserStaffAssignment;
    final dashboard = _dashboard;
    if (assignment == null || dashboard == null) return null;
    return dashboard.roleById(assignment.roleId);
  }

  bool get _canManageStaff {
    final role = _currentUserRole;
    if (role == null) return false;
    return _isOwnerRole(role.code) || _isAdminRole(role.code);
  }

  bool get _isCurrentUserOwner {
    final role = _currentUserRole;
    if (role == null) return false;
    return _isOwnerRole(role.code);
  }

  bool _canModifyStaffAssignment(_ClubStaffAssignment staff) {
    if (!_canManageStaff) return false;
    if (staff.userId != null && staff.userId == _currentUserId) return false;

    final role = _dashboard?.roleById(staff.roleId);
    if (role != null && _isOwnerRole(role.code) && !_isCurrentUserOwner) {
      return false;
    }

    return true;
  }

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleSearchChanged);
    _loadDashboard();
  }

  @override
  void dispose() {
    _searchController.removeListener(_handleSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _handleSearchChanged() {
    if (mounted) setState(() {});
  }

  List<_ClubStaffAssignment> get _filteredStaff {
    final dashboard = _dashboard;
    if (dashboard == null) return const [];

    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return dashboard.staff;

    return dashboard.staff.where((staff) {
      final searchable = [
        staff.displayName,
        staff.email,
        staff.roleName,
        staff.status,
      ].whereType<String>().join(' ').toLowerCase();

      return searchable.contains(query);
    }).toList();
  }

  Future<void> _loadDashboard() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await _supabase.rpc(
        'get_club_staff_permissions_dashboard',
        params: {'p_club_id': widget.club.clubId},
      );

      if (!mounted) return;
      setState(() {
        _dashboard = _StaffPermissionsDashboard.fromJson(
          Map<String, dynamic>.from(response as Map),
        );
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Unable to load staff permissions: $error';
      });
    }
  }

  Future<void> _openStaffEditor({_ClubStaffAssignment? existing}) async {
    final dashboard = _dashboard;
    if (dashboard == null) return;

    if (!_canManageStaff) {
      _showPermissionSnackBar();
      return;
    }

    if (existing != null && !_canModifyStaffAssignment(existing)) {
      _showPermissionSnackBar(
        'You do not have permission to change this staff assignment.',
      );
      return;
    }

    final editableRoles = _isCurrentUserOwner
        ? dashboard.roles
        : dashboard.roles
            .where((role) => !_isOwnerRole(role.code))
            .toList();

    if (editableRoles.isEmpty) {
      _showPermissionSnackBar(
        'There are no roles you are allowed to assign.',
      );
      return;
    }

    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _StaffEditorDialog(
        clubId: widget.club.clubId,
        roles: editableRoles,
        existing: existing,
      ),
    );

    if (changed == true) await _loadDashboard();
  }

  void _showPermissionSnackBar([
    String message = 'You do not have permission to manage staff assignments.',
  ]) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _removeStaff(_ClubStaffAssignment staff) async {
    if (!_canModifyStaffAssignment(staff)) {
      _showPermissionSnackBar(
        'You do not have permission to remove this staff assignment.',
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Staff Access?'),
        content: Text(
          'This will remove staff access for ${staff.displayName}. This does not delete their user account or membership.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.remove_circle_outline),
            label: const Text('Remove Access'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _supabase.rpc(
        'remove_club_staff_assignment',
        params: {
          'p_assignment_id': staff.id,
          'p_club_id': widget.club.clubId,
        },
      );
      await _loadDashboard();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to remove staff access: $error')),
      );
    }
  }

  Future<void> _toggleStatus(_ClubStaffAssignment staff) async {
    if (!_canModifyStaffAssignment(staff)) {
      _showPermissionSnackBar(
        'You do not have permission to update this staff assignment.',
      );
      return;
    }

    final nextStatus = staff.status == 'active' ? 'inactive' : 'active';

    try {
      await _supabase.rpc(
        'set_club_staff_assignment_status',
        params: {
          'p_assignment_id': staff.id,
          'p_club_id': widget.club.clubId,
          'p_status': nextStatus,
        },
      );
      await _loadDashboard();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to update staff status: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Staff & Permissions'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _loadDashboard,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _dashboard == null
            ? null
            : _canManageStaff
                ? () => _openStaffEditor()
                : _showPermissionSnackBar,
        icon: const Icon(Icons.person_add_alt_1_outlined),
        label: const Text('Add Staff'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null && _dashboard == null) {
      return _MessageState(
        icon: Icons.error_outline,
        title: 'Unable to load staff permissions',
        message: _errorMessage!,
        actionLabel: 'Try Again',
        onAction: _loadDashboard,
      );
    }

    final dashboard = _dashboard;
    if (dashboard == null) {
      return _MessageState(
        icon: Icons.admin_panel_settings_outlined,
        title: 'No staff data',
        message: 'No staff permissions data was returned for this club.',
        actionLabel: 'Refresh',
        onAction: _loadDashboard,
      );
    }

    final filteredStaff = _filteredStaff;

    return RefreshIndicator(
      onRefresh: _loadDashboard,
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
            'Manage staff access, role assignments, and permission visibility for this club.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          _CurrentAccessCard(
            roleName: _currentUserRole?.name ?? 'No active staff role',
            canManageStaff: _canManageStaff,
            canManageBilling: _isCurrentUserOwner,
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
          _ResponsiveCards(
            children: [
              _SummaryCard(
                icon: Icons.people_alt_outlined,
                label: 'Staff Members',
                value: dashboard.staff.length.toString(),
              ),
              _SummaryCard(
                icon: Icons.admin_panel_settings_outlined,
                label: 'Roles',
                value: dashboard.roles.length.toString(),
              ),
              _SummaryCard(
                icon: Icons.key_outlined,
                label: 'Permissions',
                value: dashboard.permissions.length.toString(),
              ),
              _SummaryCard(
                icon: Icons.verified_user_outlined,
                label: 'Active Staff',
                value: dashboard.staff
                    .where((staff) => staff.status == 'active')
                    .length
                    .toString(),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const _SectionTitle('Staff'),
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              labelText: 'Search staff',
              hintText: 'Name, email, role, or status',
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
          if (filteredStaff.isEmpty)
            _InlineEmptyState(
              title: dashboard.staff.isEmpty
                  ? 'No staff assignments yet'
                  : 'No matching staff',
              message: dashboard.staff.isEmpty
                  ? 'Add officers, secretaries, treasurers, or other club staff to manage club operations.'
                  : 'Try another name, email, role, or status.',
              actionLabel:
                  dashboard.staff.isEmpty && _canManageStaff ? 'Add Staff' : null,
              onAction: dashboard.staff.isEmpty && _canManageStaff
                  ? () => _openStaffEditor()
                  : null,
            )
          else
            _StaffTable(
              staff: filteredStaff,
              canModify: _canModifyStaffAssignment,
              onEdit: (staff) => _openStaffEditor(existing: staff),
              onToggleStatus: _toggleStatus,
              onRemove: _removeStaff,
            ),
          const SizedBox(height: 20),
          const _SectionTitle('Roles & Permissions'),
          if (dashboard.roles.isEmpty)
            const _InlineEmptyState(
              title: 'No roles configured',
              message:
                  'Club roles will appear here once the database role setup has been created.',
            )
          else
            for (final role in dashboard.roles)
              _RolePermissionsCard(
                role: role,
                permissions: dashboard.permissionsForRole(role.id),
              ),
        ],
      ),
    );
  }
}

class _StaffTable extends StatelessWidget {
  const _StaffTable({
    required this.staff,
    required this.canModify,
    required this.onEdit,
    required this.onToggleStatus,
    required this.onRemove,
  });

  final List<_ClubStaffAssignment> staff;
  final bool Function(_ClubStaffAssignment staff) canModify;
  final ValueChanged<_ClubStaffAssignment> onEdit;
  final ValueChanged<_ClubStaffAssignment> onToggleStatus;
  final ValueChanged<_ClubStaffAssignment> onRemove;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Name')),
            DataColumn(label: Text('Email')),
            DataColumn(label: Text('Role')),
            DataColumn(label: Text('Status')),
            DataColumn(label: Text('Assigned')),
            DataColumn(label: Text('Actions')),
          ],
          rows: [
            for (final item in staff)
              DataRow(
                cells: [
                  DataCell(Text(item.displayName)),
                  DataCell(Text(item.email ?? '—')),
                  DataCell(
                    Text(
                      item.roleName ?? '—',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                  DataCell(_StatusChip(status: item.status)),
                  DataCell(Text(_formatDate(item.createdAt))),
                  DataCell(
                    canModify(item)
                        ? PopupMenuButton<String>(
                            onSelected: (value) {
                              if (value == 'edit') onEdit(item);
                              if (value == 'status') onToggleStatus(item);
                              if (value == 'remove') onRemove(item);
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(
                                value: 'edit',
                                child: Text('Edit Role'),
                              ),
                              PopupMenuItem(
                                value: 'status',
                                child: Text(
                                  item.status == 'active'
                                      ? 'Deactivate'
                                      : 'Reactivate',
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'remove',
                                child: Text('Remove Access'),
                              ),
                            ],
                          )
                        : const Text('View only'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _StaffEditorDialog extends StatefulWidget {
  const _StaffEditorDialog({
    required this.clubId,
    required this.roles,
    this.existing,
  });

  final String clubId;
  final List<_ClubRole> roles;
  final _ClubStaffAssignment? existing;

  @override
  State<_StaffEditorDialog> createState() => _StaffEditorDialogState();
}

class _StaffEditorDialogState extends State<_StaffEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  final _supabase = Supabase.instance.client;

  late final TextEditingController _emailController;
  late String? _roleId;
  late String _status;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _emailController = TextEditingController(text: existing?.email ?? '');
    final existingRoleIsAvailable = existing == null
        ? false
        : widget.roles.any((role) => role.id == existing.roleId);
    _roleId = existingRoleIsAvailable
        ? existing.roleId
        : (widget.roles.isEmpty ? null : widget.roles.first.id);
    _status = existing?.status ?? 'active';
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSaving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (_roleId == null) {
      setState(() => _errorMessage = 'Select a role.');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      await _supabase.rpc(
        'save_club_staff_assignment',
        params: {
          'p_assignment_id': widget.existing?.id,
          'p_club_id': widget.clubId,
          'p_email': _emailController.text.trim(),
          'p_role_id': _roleId,
          'p_status': _status,
        },
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorMessage = 'Unable to save staff assignment: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;

    return AlertDialog(
      title: Text(editing ? 'Edit Staff Access' : 'Add Staff Access'),
      content: SizedBox(
        width: 620,
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
                  controller: _emailController,
                  readOnly: editing,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Staff user email',
                    helperText:
                        'The user must already have a RingMaster Club account.',
                    border: OutlineInputBorder(),
                  ),
                  validator: _emailRequired,
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _roleId,
                  decoration: const InputDecoration(
                    labelText: 'Role',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final role in widget.roles)
                      DropdownMenuItem(
                        value: role.id,
                        child: Text(role.name),
                      ),
                  ],
                  onChanged: _isSaving
                      ? null
                      : (value) => setState(() => _roleId = value),
                  validator: (value) => value == null ? 'Required.' : null,
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _status,
                  decoration: const InputDecoration(
                    labelText: 'Status',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'active', child: Text('Active')),
                    DropdownMenuItem(value: 'inactive', child: Text('Inactive')),
                  ],
                  onChanged: _isSaving
                      ? null
                      : (value) {
                          if (value != null) setState(() => _status = value);
                        },
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

  String? _emailRequired(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Required.';
    if (!text.contains('@')) return 'Enter a valid email.';
    return null;
  }
}

class _RolePermissionsCard extends StatelessWidget {
  const _RolePermissionsCard({
    required this.role,
    required this.permissions,
  });

  final _ClubRole role;
  final List<_ClubPermission> permissions;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.admin_panel_settings_outlined),
        title: Text(role.name),
        subtitle: Text(
          role.description ??
              '${role.normalizedCode} • ${permissions.length} ${permissions.length == 1 ? 'permission' : 'permissions'}',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          if (permissions.isEmpty)
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('No permissions assigned to this role.'),
            )
          else
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final permission in permissions)
                    Chip(
                      avatar: const Icon(Icons.key_outlined, size: 18),
                      label: Text(permission.label),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _CurrentAccessCard extends StatelessWidget {
  const _CurrentAccessCard({
    required this.roleName,
    required this.canManageStaff,
    required this.canManageBilling,
  });

  final String roleName;
  final bool canManageStaff;
  final bool canManageBilling;

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
              backgroundColor: canManageStaff
                  ? scheme.primaryContainer
                  : scheme.surfaceContainerHighest,
              foregroundColor: canManageStaff
                  ? scheme.onPrimaryContainer
                  : scheme.onSurfaceVariant,
              child: Icon(
                canManageStaff
                    ? Icons.admin_panel_settings_outlined
                    : Icons.visibility_outlined,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your access: $roleName',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    canManageStaff
                        ? canManageBilling
                            ? 'You can manage staff, permissions, billing, and add-ons for this club.'
                            : 'You can manage staff and permissions for this club. Billing and add-ons remain owner-only.'
                        : 'You can view staff and permissions, but you cannot change assignments.',
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

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = status == 'active' ? scheme.primary : scheme.outline;

    return Chip(
      label: Text(_titleCase(status)),
      backgroundColor: color.withAlpha(35),
      side: BorderSide(color: color),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            CircleAvatar(child: Icon(icon)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
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

class _ResponsiveCards extends StatelessWidget {
  const _ResponsiveCards({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth >= 1100
            ? (constraints.maxWidth - 36) / 4
            : constraints.maxWidth >= 760
                ? (constraints.maxWidth - 24) / 3
                : constraints.maxWidth >= 520
                    ? (constraints.maxWidth - 12) / 2
                    : constraints.maxWidth;

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final child in children) SizedBox(width: width, child: child),
          ],
        );
      },
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
              fontWeight: FontWeight.w800,
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
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
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
            const Icon(Icons.admin_panel_settings_outlined, size: 52),
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
                icon: const Icon(Icons.person_add_alt_1_outlined),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StaffPermissionsDashboard {
  const _StaffPermissionsDashboard({
    required this.staff,
    required this.roles,
    required this.permissions,
    required this.rolePermissions,
  });

  final List<_ClubStaffAssignment> staff;
  final List<_ClubRole> roles;
  final List<_ClubPermission> permissions;
  final List<_ClubRolePermission> rolePermissions;

  List<_ClubPermission> permissionsForRole(String roleId) {
    final permissionIds = rolePermissions
        .where((item) => item.roleId == roleId)
        .map((item) => item.permissionId)
        .toSet();

    return permissions
        .where((permission) => permissionIds.contains(permission.id))
        .toList()
      ..sort((a, b) => a.label.compareTo(b.label));
  }

  _ClubRole? roleById(String roleId) {
    for (final role in roles) {
      if (role.id == roleId) return role;
    }
    return null;
  }

  factory _StaffPermissionsDashboard.fromJson(Map<String, dynamic> json) {
    return _StaffPermissionsDashboard(
      staff: _list(json['staff']).map(_ClubStaffAssignment.fromJson).toList(),
      roles: _list(json['roles']).map(_ClubRole.fromJson).toList(),
      permissions:
          _list(json['permissions']).map(_ClubPermission.fromJson).toList(),
      rolePermissions: _list(json['role_permissions'])
          .map(_ClubRolePermission.fromJson)
          .toList(),
    );
  }
}

class _ClubStaffAssignment {
  const _ClubStaffAssignment({
    required this.id,
    required this.roleId,
    required this.status,
    required this.displayName,
    required this.createdAt,
    this.userId,
    this.email,
    this.roleName,
  });

  final String id;
  final String? userId;
  final String roleId;
  final String? email;
  final String? roleName;
  final String status;
  final String displayName;
  final DateTime createdAt;

  factory _ClubStaffAssignment.fromJson(Map<String, dynamic> json) {
    return _ClubStaffAssignment(
      id: json['id'].toString(),
      userId: _nullableString(json['user_id']),
      roleId: _stringValue(json['role_id'], fallback: ''),
      email: _nullableString(json['email']),
      roleName: _nullableString(json['role_name']),
      status: _stringValue(json['status'], fallback: 'active'),
      displayName: _stringValue(
        json['display_name'],
        fallback: _nullableString(json['email']) ?? 'Unknown Staff',
      ),
      createdAt: _dateValue(json['created_at']) ?? DateTime.now(),
    );
  }
}

class _ClubRole {
  const _ClubRole({
    required this.id,
    required this.name,
    required this.code,
    required this.isSystem,
    this.description,
  });

  final String id;
  final String name;
  final String code;
  final String? description;
  final bool isSystem;

  String get normalizedCode => _normalizeRoleCode(code);

  factory _ClubRole.fromJson(Map<String, dynamic> json) {
    return _ClubRole(
      id: json['id'].toString(),
      name: _stringValue(json['name'], fallback: 'Role'),
      code: _stringValue(json['code'], fallback: ''),
      description: _nullableString(json['description']),
      isSystem: json['is_system'] == true,
    );
  }
}

class _ClubPermission {
  const _ClubPermission({
    required this.id,
    required this.code,
    required this.label,
    this.description,
    this.category,
  });

  final String id;
  final String code;
  final String label;
  final String? description;
  final String? category;

  factory _ClubPermission.fromJson(Map<String, dynamic> json) {
    final code = _stringValue(json['code'], fallback: 'permission');
    return _ClubPermission(
      id: json['id'].toString(),
      code: code,
      label: _stringValue(json['label'], fallback: _titleCase(code)),
      description: _nullableString(json['description']),
      category: _nullableString(json['category']),
    );
  }
}

class _ClubRolePermission {
  const _ClubRolePermission({
    required this.roleId,
    required this.permissionId,
  });

  final String roleId;
  final String permissionId;

  factory _ClubRolePermission.fromJson(Map<String, dynamic> json) {
    return _ClubRolePermission(
      roleId: _stringValue(json['role_id'], fallback: ''),
      permissionId: _stringValue(json['permission_id'], fallback: ''),
    );
  }
}

List<Map<String, dynamic>> _list(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
}

String? _nullableString(dynamic value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

String _stringValue(dynamic value, {required String fallback}) {
  return _nullableString(value) ?? fallback;
}

DateTime? _dateValue(dynamic value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) return null;
  return DateTime.tryParse(text);
}

String _formatDate(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '$month/$day/${value.year}';
}

String _titleCase(String value) {
  return value
      .split(RegExp(r'[_\s.-]+'))
      .where((part) => part.isNotEmpty)
      .map(
        (part) => '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
      )
      .join(' ');
}

String _normalizeRoleCode(String value) {
  return value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
}

bool _isOwnerRole(String value) {
  final code = _normalizeRoleCode(value);
  return code == 'owner' || code == 'club_owner';
}

bool _isAdminRole(String value) {
  final code = _normalizeRoleCode(value);
  return code == 'admin' || code == 'club_admin';
}

extension _FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}