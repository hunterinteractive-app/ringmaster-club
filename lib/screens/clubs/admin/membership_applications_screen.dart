

// lib/screens/clubs/admin/membership_applications_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/clubs/club_summary.dart';

class MembershipApplicationsScreen extends StatefulWidget {
  const MembershipApplicationsScreen({
    super.key,
    required this.club,
  });

  final ClubSummary club;

  @override
  State<MembershipApplicationsScreen> createState() =>
      _MembershipApplicationsScreenState();
}

class _MembershipApplicationsScreenState
    extends State<MembershipApplicationsScreen> {
  final _supabase = Supabase.instance.client;
  final _searchController = TextEditingController();

  bool _isLoading = true;
  String? _errorMessage;
  String _statusFilter = 'pending';
  List<_MembershipApplication> _applications = const [];
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
    if (mounted) setState(() {});
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final responses = await Future.wait([
        _supabase
            .from('club_membership_applications')
            .select(
              'id,club_id,user_id,membership_type_id,application_type,status,'
              'first_name,last_name,showing_name,email,phone,address_line1,'
              'address_line2,city,state,postal_code,country,date_of_birth,arba_number,'
              'submitted_at,payment_status,staff_notes,applicant_message,'
              'reviewed_at,reviewed_by,created_at',
            )
            .eq('club_id', widget.club.clubId)
            .order('submitted_at', ascending: false)
            .order('created_at', ascending: false),
        _supabase
            .from('club_membership_types')
            .select('id,name,is_active')
            .eq('club_id', widget.club.clubId)
            .order('name', ascending: true),
      ]);

      final applicationRows = responses[0] as List;
      final typeRows = responses[1] as List;

      final types = typeRows
          .whereType<Map>()
          .map(
            (row) => _MembershipTypeOption.fromJson(
              Map<String, dynamic>.from(row),
            ),
          )
          .toList();

      final typeMap = <String, _MembershipTypeOption>{
        for (final type in types) type.id: type,
      };

      final applications = applicationRows
          .whereType<Map>()
          .map((row) {
            final json = Map<String, dynamic>.from(row);
            final typeId = json['membership_type_id']?.toString();

            return _MembershipApplication.fromJson(
              json,
              membershipType: typeId == null ? null : typeMap[typeId],
            );
          })
          .toList();

      if (!mounted) return;

      setState(() {
        _applications = applications;
        _membershipTypes = types;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _errorMessage = 'Unable to load membership applications: $error';
      });
    }
  }

  List<_MembershipApplication> get _filteredApplications {
    final query = _searchController.text.trim().toLowerCase();

    return _applications.where((application) {
      final matchesStatus =
          _statusFilter == 'all' || application.status == _statusFilter;
      if (!matchesStatus) return false;
      if (query.isEmpty) return true;

      final searchable = [
        application.fullName,
        application.showingName,
        application.email,
        application.phone,
        application.membershipType?.name,
        application.applicationType,
        application.paymentStatus,
      ].whereType<String>().join(' ').toLowerCase();

      return searchable.contains(query);
    }).toList();
  }

  int _countForStatus(String status) {
    if (status == 'all') return _applications.length;
    return _applications.where((item) => item.status == status).length;
  }

  Future<void> _openReview(_MembershipApplication application) async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ApplicationReviewDialog(
        clubId: widget.club.clubId,
        application: application,
        membershipTypes: _membershipTypes,
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
        title: const Text('Applications & Renewals'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _loadData,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null && _applications.isEmpty) {
      return _MessageState(
        icon: Icons.error_outline,
        title: 'Unable to load applications',
        message: _errorMessage!,
        actionLabel: 'Try Again',
        onAction: _loadData,
      );
    }

    final filtered = _filteredApplications;

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          Text(
            widget.club.clubName,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'Review new membership applications and renewal requests.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          const _BaseApplicationsAccessCard(),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth >= 760
                  ? (constraints.maxWidth - 24) / 3
                  : constraints.maxWidth;

              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: width,
                    child: _SummaryCard(
                      icon: Icons.pending_actions_outlined,
                      label: 'Pending Review',
                      value: _countForStatus('pending').toString(),
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _SummaryCard(
                      icon: Icons.mark_email_unread_outlined,
                      label: 'Needs Information',
                      value: _countForStatus('needs_information').toString(),
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _SummaryCard(
                      icon: Icons.check_circle_outline,
                      label: 'Approved',
                      value: _countForStatus('approved').toString(),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              labelText: 'Search applications',
              hintText: 'Name, email, phone, or membership type',
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
                ButtonSegment(
                  value: 'needs_information',
                  label: Text('Needs Info'),
                ),
                ButtonSegment(value: 'approved', label: Text('Approved')),
                ButtonSegment(value: 'denied', label: Text('Denied')),
                ButtonSegment(value: 'withdrawn', label: Text('Withdrawn')),
              ],
              selected: {_statusFilter},
              onSelectionChanged: (values) {
                setState(() => _statusFilter = values.first);
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
          Text(
            '${filtered.length} ${filtered.length == 1 ? 'application' : 'applications'}',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 12),
          if (_applications.isEmpty)
            const _InlineEmptyState(
              title: 'No applications yet',
              message:
                  'New membership applications and renewal requests will appear here.',
            )
          else if (filtered.isEmpty)
            const _InlineEmptyState(
              title: 'No matching applications',
              message: 'Try a different search or application status filter.',
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
                    for (final application in filtered)
                      SizedBox(
                        width: width,
                        child: _ApplicationCard(
                          application: application,
                          onReview: () => _openReview(application),
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

class _ApplicationCard extends StatelessWidget {
  const _ApplicationCard({
    required this.application,
    required this.onReview,
  });

  final _MembershipApplication application;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final statusColor = _statusColor(application.status, scheme);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onReview,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(child: Text(application.initials)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          application.fullName,
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        if (application.showingName != null &&
                            application.showingName != application.fullName)
                          Text(application.showingName!),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Review application',
                    onPressed: onReview,
                    icon: const Icon(Icons.open_in_new),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(
                    label: Text(_titleCase(application.status)),
                    backgroundColor: statusColor.withAlpha(40),
                    side: BorderSide(color: statusColor),
                  ),
                  Chip(label: Text(_titleCase(application.applicationType))),
                  if (application.membershipType != null)
                    Chip(label: Text(application.membershipType!.name)),
                  Chip(
                    avatar: const Icon(Icons.payments_outlined, size: 18),
                    label: Text(_titleCase(application.paymentStatus)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (application.email != null)
                _DetailRow(
                  icon: Icons.email_outlined,
                  text: application.email!,
                ),
              if (application.phone != null)
                _DetailRow(
                  icon: Icons.phone_outlined,
                  text: application.phone!,
                ),
              if (application.arbaNumber != null)
                _DetailRow(
                  icon: Icons.confirmation_number_outlined,
                  text: 'ARBA # ${application.arbaNumber!}',
                ),
              _DetailRow(
                icon: Icons.event_outlined,
                text: 'Submitted ${_formatDate(application.submittedAt)}',
              ),
              if (application.membershipType != null &&
                  !application.membershipType!.isActive)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Material(
                    color: scheme.errorContainer,
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        children: [
                          Icon(
                            Icons.warning_amber_outlined,
                            color: scheme.onErrorContainer,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'The requested membership type is inactive.',
                              style: TextStyle(
                                color: scheme.onErrorContainer,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static Color _statusColor(String status, ColorScheme scheme) {
    switch (status) {
      case 'approved':
        return scheme.primary;
      case 'pending':
      case 'needs_information':
        return scheme.tertiary;
      case 'denied':
      case 'withdrawn':
        return scheme.error;
      default:
        return scheme.outline;
    }
  }
}

class _ApplicationReviewDialog extends StatefulWidget {
  const _ApplicationReviewDialog({
    required this.clubId,
    required this.application,
    required this.membershipTypes,
  });

  final String clubId;
  final _MembershipApplication application;
  final List<_MembershipTypeOption> membershipTypes;

  @override
  State<_ApplicationReviewDialog> createState() =>
      _ApplicationReviewDialogState();
}

class _ApplicationReviewDialogState
    extends State<_ApplicationReviewDialog> {
  final _supabase = Supabase.instance.client;
  late final TextEditingController _staffNotesController;

  late String _status;
  late String _paymentStatus;
  String? _membershipTypeId;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _status = widget.application.status;
    _paymentStatus = widget.application.paymentStatus;
    _membershipTypeId = widget.application.membershipTypeId;
    _staffNotesController = TextEditingController(
      text: widget.application.staffNotes ?? '',
    );
  }

  @override
  void dispose() {
    _staffNotesController.dispose();
    super.dispose();
  }

  Future<void> _saveReview(String action) async {
    if (_isSaving) return;

    if (action == 'approved') {
      if (_membershipTypeId == null) {
        setState(() {
          _errorMessage = 'Select a membership type before approving.';
        });
        return;
      }

      final selectedType = widget.membershipTypes
          .where((type) => type.id == _membershipTypeId)
          .firstOrNull;

      if (selectedType == null || !selectedType.isActive) {
        setState(() {
          _errorMessage =
              'This application cannot be approved with an inactive membership type.';
        });
        return;
      }
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      await _supabase.rpc(
        'review_club_membership_application',
        params: {
          'p_application_id': widget.application.id,
          'p_status': action,
          'p_membership_type_id': _membershipTypeId,
          'p_payment_status': _paymentStatus,
          'p_staff_notes': _nullIfBlank(_staffNotesController.text),
        },
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _isSaving = false;
        _errorMessage = 'Unable to update application: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final application = widget.application;
    final selectableTypes = widget.membershipTypes
        .where(
          (type) => type.isActive || type.id == _membershipTypeId,
        )
        .toList();

    return AlertDialog(
      title: const Text('Review Application'),
      content: SizedBox(
        width: 760,
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
              _SectionTitle('Applicant'),
              _ReadOnlyGrid(
                children: [
                  _ReadOnlyField(label: 'Name', value: application.fullName),
                  _ReadOnlyField(
                    label: 'Showing name',
                    value: application.showingName ?? '—',
                  ),
                  _ReadOnlyField(
                    label: 'Email',
                    value: application.email ?? '—',
                  ),
                  _ReadOnlyField(
                    label: 'Phone',
                    value: application.phone ?? '—',
                  ),
                  _ReadOnlyField(
                    label: 'ARBA number',
                    value: application.arbaNumber ?? '—',
                  ),
                  _ReadOnlyField(
                    label: 'Application type',
                    value: _titleCase(application.applicationType),
                  ),
                  _ReadOnlyField(
                    label: 'Submitted',
                    value: _formatDate(application.submittedAt),
                  ),
                ],
              ),
              if (application.addressLabel != null) ...[
                const SizedBox(height: 14),
                _ReadOnlyField(
                  label: 'Address',
                  value: application.addressLabel!,
                ),
              ],
              if (application.applicantMessage != null) ...[
                const SizedBox(height: 18),
                _SectionTitle('Applicant Message'),
                Material(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(application.applicantMessage!),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              _SectionTitle('Review'),
              DropdownButtonFormField<String>(
                initialValue: _membershipTypeId,
                decoration: const InputDecoration(
                  labelText: 'Membership type',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final type in selectableTypes)
                    DropdownMenuItem(
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
              DropdownButtonFormField<String>(
                initialValue: _paymentStatus,
                decoration: const InputDecoration(
                  labelText: 'Payment status',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'unpaid', child: Text('Unpaid')),
                  DropdownMenuItem(value: 'pending', child: Text('Pending')),
                  DropdownMenuItem(value: 'paid', child: Text('Paid')),
                  DropdownMenuItem(value: 'waived', child: Text('Waived')),
                  DropdownMenuItem(value: 'refunded', child: Text('Refunded')),
                ],
                onChanged: _isSaving
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() => _paymentStatus = value);
                        }
                      },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _staffNotesController,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'Staff notes',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _status,
                decoration: const InputDecoration(
                  labelText: 'Current status',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'pending', child: Text('Pending')),
                  DropdownMenuItem(
                    value: 'needs_information',
                    child: Text('Needs Information'),
                  ),
                  DropdownMenuItem(value: 'approved', child: Text('Approved')),
                  DropdownMenuItem(value: 'denied', child: Text('Denied')),
                  DropdownMenuItem(
                    value: 'withdrawn',
                    child: Text('Withdrawn'),
                  ),
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
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Close'),
        ),
        OutlinedButton.icon(
          onPressed: _isSaving
              ? null
              : () => _saveReview('needs_information'),
          icon: const Icon(Icons.mark_email_unread_outlined),
          label: const Text('Request Information'),
        ),
        OutlinedButton.icon(
          onPressed: _isSaving ? null : () => _saveReview('denied'),
          icon: const Icon(Icons.block_outlined),
          label: const Text('Deny'),
        ),
        FilledButton.icon(
          onPressed: _isSaving ? null : () => _saveReview('approved'),
          icon: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check_circle_outline),
          label: Text(_isSaving ? 'Saving...' : 'Approve'),
        ),
      ],
    );
  }

  String? _nullIfBlank(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

class _MembershipApplication {
  const _MembershipApplication({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.applicationType,
    required this.status,
    required this.submittedAt,
    required this.paymentStatus,
    this.userId,
    this.membershipTypeId,
    this.membershipType,
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
    this.arbaNumber,
    this.staffNotes,
    this.applicantMessage,
    this.reviewedAt,
    this.reviewedBy,
  });

  final String id;
  final String? userId;
  final String? membershipTypeId;
  final _MembershipTypeOption? membershipType;
  final String applicationType;
  final String status;
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
  final String? arbaNumber;
  final DateTime submittedAt;
  final String paymentStatus;
  final String? staffNotes;
  final String? applicantMessage;
  final DateTime? reviewedAt;
  final String? reviewedBy;

  String get fullName => '$firstName $lastName'.trim();

  String get initials {
    final first = firstName.isEmpty ? '' : firstName[0];
    final last = lastName.isEmpty ? '' : lastName[0];
    final value = '$first$last'.trim();
    return value.isEmpty ? 'A' : value.toUpperCase();
  }

  String? get addressLabel {
    final lines = <String>[
      ?addressLine1,
      ?addressLine2,
      [city, state, postalCode]
          .whereType<String>()
          .where((part) => part.trim().isNotEmpty)
          .join(', '),
      ?country,
    ].where((line) => line.trim().isNotEmpty).toList();

    return lines.isEmpty ? null : lines.join('\n');
  }

  factory _MembershipApplication.fromJson(
    Map<String, dynamic> json, {
    _MembershipTypeOption? membershipType,
  }) {
    return _MembershipApplication(
      id: json['id'].toString(),
      userId: _nullableString(json['user_id']),
      membershipTypeId: _nullableString(json['membership_type_id']),
      membershipType: membershipType,
      applicationType:
          _nullableString(json['application_type']) ?? 'new_membership',
      status: _nullableString(json['status']) ?? 'pending',
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
      arbaNumber: _nullableString(json['arba_number']),
      submittedAt:
          _nullableDate(json['submitted_at']) ?? DateTime.now(),
      paymentStatus: _nullableString(json['payment_status']) ?? 'unpaid',
      staffNotes: _nullableString(json['staff_notes']),
      applicantMessage: _nullableString(json['applicant_message']),
      reviewedAt: _nullableDate(json['reviewed_at']),
      reviewedBy: _nullableString(json['reviewed_by']),
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

class _BaseApplicationsAccessCard extends StatelessWidget {
  const _BaseApplicationsAccessCard();

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
                    'Applications and renewals are always available for clubs. Clubs can review applicants, request more information, approve, deny, or mark applications withdrawn. Payment integration and dues tracking are handled by the Membership Management Add-on.',
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

class _DetailRow extends StatelessWidget {
  const _DetailRow({
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

class _ReadOnlyGrid extends StatelessWidget {
  const _ReadOnlyGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth >= 560
            ? (constraints.maxWidth - 12) / 2
            : constraints.maxWidth;

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final child in children)
              SizedBox(width: width, child: child),
          ],
        );
      },
    );
  }
}

class _ReadOnlyField extends StatelessWidget {
  const _ReadOnlyField({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
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
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            const Icon(Icons.assignment_outlined, size: 52),
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

extension _FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}