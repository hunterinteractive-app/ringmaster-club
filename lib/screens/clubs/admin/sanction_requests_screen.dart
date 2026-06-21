// lib/screens/clubs/admin/sanction_requests_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/clubs/club_summary.dart';

class SanctionRequestsScreen extends StatefulWidget {
  const SanctionRequestsScreen({
    super.key,
    required this.club,
  });

  final ClubSummary club;

  @override
  State<SanctionRequestsScreen> createState() =>
      _SanctionRequestsScreenState();
}

class _SanctionRequestsScreenState extends State<SanctionRequestsScreen> {
  final _supabase = Supabase.instance.client;
  final _searchController = TextEditingController();

  bool _isLoading = true;
  String? _errorMessage;
  String _statusFilter = 'pending';
  List<_SanctionRequest> _requests = const [];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleSearchChanged);
    _loadRequests();
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

  Future<void> _loadRequests() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final rows = await _supabase
          .from('club_sanction_requests')
          .select(
            'id,club_id,requesting_club_name,contact_name,contact_email,'
            'contact_phone,show_name,show_date,show_end_date,location_name,'
            'location_address,show_type,sanction_category,status,fee_due,'
            'amount_paid,currency,payment_status,sanction_number,'
            'applicant_notes,staff_notes,submitted_at,reviewed_at,created_at',
          )
          .eq('club_id', widget.club.clubId)
          .order('show_date', ascending: true)
          .order('submitted_at', ascending: false);

      final requests = (rows as List)
          .whereType<Map>()
          .map(
            (row) => _SanctionRequest.fromJson(
              Map<String, dynamic>.from(row),
            ),
          )
          .toList();

      if (!mounted) return;

      setState(() {
        _requests = requests;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _errorMessage = 'Unable to load sanction requests: $error';
      });
    }
  }

  List<_SanctionRequest> get _filteredRequests {
    final query = _searchController.text.trim().toLowerCase();

    return _requests.where((request) {
      final matchesStatus =
          _statusFilter == 'all' || request.status == _statusFilter;
      if (!matchesStatus) return false;
      if (query.isEmpty) return true;

      final searchable = [
        request.requestingClubName,
        request.contactName,
        request.contactEmail,
        request.showName,
        request.locationName,
        request.sanctionCategory,
        request.sanctionNumber,
      ].whereType<String>().join(' ').toLowerCase();

      return searchable.contains(query);
    }).toList();
  }

  int _countForStatus(String status) {
    if (status == 'all') return _requests.length;
    return _requests.where((request) => request.status == status).length;
  }

  Future<void> _openEditor({_SanctionRequest? existing}) async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SanctionRequestDialog(
        clubId: widget.club.clubId,
        existing: existing,
      ),
    );

    if (changed == true) {
      await _loadRequests();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sanction Requests'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _loadRequests,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('New Request'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null && _requests.isEmpty) {
      return _MessageState(
        icon: Icons.error_outline,
        title: 'Unable to load sanction requests',
        message: _errorMessage!,
        actionLabel: 'Try Again',
        onAction: _loadRequests,
      );
    }

    final filtered = _filteredRequests;

    return RefreshIndicator(
      onRefresh: _loadRequests,
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
            'Review and manage show sanction requests, fees, and approval numbers.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
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
                      label: 'Pending',
                      value: _countForStatus('pending').toString(),
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _SummaryCard(
                      icon: Icons.assignment_return_outlined,
                      label: 'Returned',
                      value: _countForStatus('returned').toString(),
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
              labelText: 'Search sanction requests',
              hintText: 'Club, show, contact, location, or sanction number',
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
                ButtonSegment(value: 'returned', label: Text('Returned')),
                ButtonSegment(value: 'approved', label: Text('Approved')),
                ButtonSegment(value: 'denied', label: Text('Denied')),
                ButtonSegment(value: 'cancelled', label: Text('Cancelled')),
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
            '${filtered.length} ${filtered.length == 1 ? 'request' : 'requests'}',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 12),
          if (_requests.isEmpty)
            _InlineEmptyState(
              title: 'No sanction requests yet',
              message:
                  'Create the first sanction request or wait for one to be submitted.',
              actionLabel: 'New Request',
              onAction: () => _openEditor(),
            )
          else if (filtered.isEmpty)
            const _InlineEmptyState(
              title: 'No matching sanction requests',
              message: 'Try another search or status filter.',
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
                    for (final request in filtered)
                      SizedBox(
                        width: width,
                        child: _SanctionRequestCard(
                          request: request,
                          onEdit: () => _openEditor(existing: request),
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

class _SanctionRequestCard extends StatelessWidget {
  const _SanctionRequestCard({
    required this.request,
    required this.onEdit,
  });

  final _SanctionRequest request;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final statusColor = _statusColor(request.status, scheme);

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
                  const CircleAvatar(
                    child: Icon(Icons.verified_outlined),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          request.showName,
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        Text(request.requestingClubName),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Edit sanction request',
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
                    label: Text(_titleCase(request.status)),
                    backgroundColor: statusColor.withAlpha(40),
                    side: BorderSide(color: statusColor),
                  ),
                  Chip(label: Text(_titleCase(request.showType))),
                  Chip(label: Text(_titleCase(request.sanctionCategory))),
                  Chip(
                    avatar: const Icon(Icons.payments_outlined, size: 18),
                    label: Text(_titleCase(request.paymentStatus)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _DetailRow(
                icon: Icons.event_outlined,
                text: request.dateLabel,
              ),
              if (request.locationName != null)
                _DetailRow(
                  icon: Icons.location_on_outlined,
                  text: request.locationName!,
                ),
              _DetailRow(
                icon: Icons.person_outline,
                text: request.contactName,
              ),
              if (request.contactEmail != null)
                _DetailRow(
                  icon: Icons.email_outlined,
                  text: request.contactEmail!,
                ),
              _DetailRow(
                icon: Icons.request_quote_outlined,
                text:
                    'Fee: ${_money(request.feeDue)} • Paid: ${_money(request.amountPaid)}',
              ),
              if (request.sanctionNumber != null)
                _DetailRow(
                  icon: Icons.confirmation_number_outlined,
                  text: 'Sanction #${request.sanctionNumber}',
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
      case 'returned':
        return scheme.tertiary;
      case 'denied':
      case 'cancelled':
        return scheme.error;
      default:
        return scheme.outline;
    }
  }
}

class _SanctionRequestDialog extends StatefulWidget {
  const _SanctionRequestDialog({
    required this.clubId,
    this.existing,
  });

  final String clubId;
  final _SanctionRequest? existing;

  @override
  State<_SanctionRequestDialog> createState() =>
      _SanctionRequestDialogState();
}

class _SanctionRequestDialogState extends State<_SanctionRequestDialog> {
  final _formKey = GlobalKey<FormState>();
  final _supabase = Supabase.instance.client;

  late final TextEditingController _requestingClubController;
  late final TextEditingController _contactNameController;
  late final TextEditingController _contactEmailController;
  late final TextEditingController _contactPhoneController;
  late final TextEditingController _showNameController;
  late final TextEditingController _showDateController;
  late final TextEditingController _showEndDateController;
  late final TextEditingController _locationNameController;
  late final TextEditingController _locationAddressController;
  late final TextEditingController _feeDueController;
  late final TextEditingController _amountPaidController;
  late final TextEditingController _currencyController;
  late final TextEditingController _sanctionNumberController;
  late final TextEditingController _applicantNotesController;
  late final TextEditingController _staffNotesController;

  late String _showType;
  late String _sanctionCategory;
  late String _status;
  late String _paymentStatus;

  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;

    _requestingClubController =
        TextEditingController(text: existing?.requestingClubName ?? '');
    _contactNameController =
        TextEditingController(text: existing?.contactName ?? '');
    _contactEmailController =
        TextEditingController(text: existing?.contactEmail ?? '');
    _contactPhoneController =
        TextEditingController(text: existing?.contactPhone ?? '');
    _showNameController =
        TextEditingController(text: existing?.showName ?? '');
    _showDateController =
        TextEditingController(text: _dateText(existing?.showDate));
    _showEndDateController =
        TextEditingController(text: _dateText(existing?.showEndDate));
    _locationNameController =
        TextEditingController(text: existing?.locationName ?? '');
    _locationAddressController =
        TextEditingController(text: existing?.locationAddress ?? '');
    _feeDueController = TextEditingController(
      text: existing?.feeDue.toStringAsFixed(2) ?? '0.00',
    );
    _amountPaidController = TextEditingController(
      text: existing?.amountPaid.toStringAsFixed(2) ?? '0.00',
    );
    _currencyController =
        TextEditingController(text: existing?.currency.toUpperCase() ?? 'USD');
    _sanctionNumberController =
        TextEditingController(text: existing?.sanctionNumber ?? '');
    _applicantNotesController =
        TextEditingController(text: existing?.applicantNotes ?? '');
    _staffNotesController =
        TextEditingController(text: existing?.staffNotes ?? '');

    _showType = existing?.showType ?? 'all_breed';
    _sanctionCategory = existing?.sanctionCategory ?? 'rabbit';
    _status = existing?.status ?? 'pending';
    _paymentStatus = existing?.paymentStatus ?? 'unpaid';
  }

  @override
  void dispose() {
    _requestingClubController.dispose();
    _contactNameController.dispose();
    _contactEmailController.dispose();
    _contactPhoneController.dispose();
    _showNameController.dispose();
    _showDateController.dispose();
    _showEndDateController.dispose();
    _locationNameController.dispose();
    _locationAddressController.dispose();
    _feeDueController.dispose();
    _amountPaidController.dispose();
    _currencyController.dispose();
    _sanctionNumberController.dispose();
    _applicantNotesController.dispose();
    _staffNotesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSaving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final showDate = _parseDate(_showDateController.text);
    final showEndDate = _parseDate(_showEndDateController.text);

    if (showDate != null &&
        showEndDate != null &&
        showEndDate.isBefore(showDate)) {
      setState(() {
        _errorMessage = 'The show end date cannot be before the start date.';
      });
      return;
    }

    if (_status == 'approved' &&
        _sanctionNumberController.text.trim().isEmpty) {
      setState(() {
        _errorMessage = 'Enter a sanction number before approving.';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final payload = <String, dynamic>{
      'club_id': widget.clubId,
      'requesting_club_name': _requestingClubController.text.trim(),
      'contact_name': _contactNameController.text.trim(),
      'contact_email': _nullIfBlank(_contactEmailController.text),
      'contact_phone': _nullIfBlank(_contactPhoneController.text),
      'show_name': _showNameController.text.trim(),
      'show_date': _dateValue(_showDateController.text),
      'show_end_date': _dateValue(_showEndDateController.text),
      'location_name': _nullIfBlank(_locationNameController.text),
      'location_address': _nullIfBlank(_locationAddressController.text),
      'show_type': _showType,
      'sanction_category': _sanctionCategory,
      'status': _status,
      'fee_due': double.tryParse(_feeDueController.text.trim()) ?? 0,
      'amount_paid': double.tryParse(_amountPaidController.text.trim()) ?? 0,
      'currency': _currencyController.text.trim().isEmpty
          ? 'usd'
          : _currencyController.text.trim().toLowerCase(),
      'payment_status': _paymentStatus,
      'sanction_number': _nullIfBlank(_sanctionNumberController.text),
      'applicant_notes': _nullIfBlank(_applicantNotesController.text),
      'staff_notes': _nullIfBlank(_staffNotesController.text),
      'reviewed_at': _status == 'pending' ? null : DateTime.now().toIso8601String(),
    };

    try {
      final existing = widget.existing;

      if (existing == null) {
        await _supabase.from('club_sanction_requests').insert(payload);
      } else {
        await _supabase
            .from('club_sanction_requests')
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
        _errorMessage = 'Unable to save sanction request: $error';
      });
    }
  }

  Future<void> _pickDate(TextEditingController controller) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _parseDate(controller.text) ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (selected != null) {
      controller.text = _dateText(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.existing == null
            ? 'New Sanction Request'
            : 'Edit Sanction Request',
      ),
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
                _SectionTitle('Requesting Club'),
                _ResponsiveFields(
                  children: [
                    TextFormField(
                      controller: _requestingClubController,
                      decoration: const InputDecoration(
                        labelText: 'Requesting club',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) => _required(value, 'Requesting club'),
                    ),
                    TextFormField(
                      controller: _contactNameController,
                      decoration: const InputDecoration(
                        labelText: 'Contact name',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) => _required(value, 'Contact name'),
                    ),
                    TextFormField(
                      controller: _contactEmailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Contact email',
                        border: OutlineInputBorder(),
                      ),
                      validator: _optionalEmail,
                    ),
                    TextFormField(
                      controller: _contactPhoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Contact phone',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _SectionTitle('Show Details'),
                TextFormField(
                  controller: _showNameController,
                  decoration: const InputDecoration(
                    labelText: 'Show name',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => _required(value, 'Show name'),
                ),
                const SizedBox(height: 14),
                _ResponsiveFields(
                  children: [
                    _DateField(
                      controller: _showDateController,
                      label: 'Show date',
                      onPick: () => _pickDate(_showDateController),
                    ),
                    _DateField(
                      controller: _showEndDateController,
                      label: 'Show end date',
                      onPick: () => _pickDate(_showEndDateController),
                    ),
                    TextFormField(
                      controller: _locationNameController,
                      decoration: const InputDecoration(
                        labelText: 'Location name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    TextFormField(
                      controller: _locationAddressController,
                      decoration: const InputDecoration(
                        labelText: 'Location address',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: _showType,
                      decoration: const InputDecoration(
                        labelText: 'Show type',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'all_breed',
                          child: Text('All-Breed'),
                        ),
                        DropdownMenuItem(
                          value: 'specialty',
                          child: Text('Specialty'),
                        ),
                        DropdownMenuItem(
                          value: 'combined',
                          child: Text('Combined'),
                        ),
                        DropdownMenuItem(
                          value: 'other',
                          child: Text('Other'),
                        ),
                      ],
                      onChanged: _isSaving
                          ? null
                          : (value) {
                              if (value != null) {
                                setState(() => _showType = value);
                              }
                            },
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: _sanctionCategory,
                      decoration: const InputDecoration(
                        labelText: 'Sanction category',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'rabbit',
                          child: Text('Rabbit'),
                        ),
                        DropdownMenuItem(
                          value: 'cavy',
                          child: Text('Cavy'),
                        ),
                        DropdownMenuItem(
                          value: 'rabbit_and_cavy',
                          child: Text('Rabbit & Cavy'),
                        ),
                        DropdownMenuItem(
                          value: 'other',
                          child: Text('Other'),
                        ),
                      ],
                      onChanged: _isSaving
                          ? null
                          : (value) {
                              if (value != null) {
                                setState(() => _sanctionCategory = value);
                              }
                            },
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _SectionTitle('Fees & Review'),
                _ResponsiveFields(
                  children: [
                    TextFormField(
                      controller: _feeDueController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Fee due',
                        prefixText: r'$ ',
                        border: OutlineInputBorder(),
                      ),
                      validator: _nonNegativeMoney,
                    ),
                    TextFormField(
                      controller: _amountPaidController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Amount paid',
                        prefixText: r'$ ',
                        border: OutlineInputBorder(),
                      ),
                      validator: _nonNegativeMoney,
                    ),
                    TextFormField(
                      controller: _currencyController,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Currency',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: _paymentStatus,
                      decoration: const InputDecoration(
                        labelText: 'Payment status',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'unpaid',
                          child: Text('Unpaid'),
                        ),
                        DropdownMenuItem(
                          value: 'partial',
                          child: Text('Partial'),
                        ),
                        DropdownMenuItem(
                          value: 'paid',
                          child: Text('Paid'),
                        ),
                        DropdownMenuItem(
                          value: 'waived',
                          child: Text('Waived'),
                        ),
                        DropdownMenuItem(
                          value: 'refunded',
                          child: Text('Refunded'),
                        ),
                      ],
                      onChanged: _isSaving
                          ? null
                          : (value) {
                              if (value != null) {
                                setState(() => _paymentStatus = value);
                              }
                            },
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: _status,
                      decoration: const InputDecoration(
                        labelText: 'Request status',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'pending',
                          child: Text('Pending'),
                        ),
                        DropdownMenuItem(
                          value: 'returned',
                          child: Text('Returned for Corrections'),
                        ),
                        DropdownMenuItem(
                          value: 'approved',
                          child: Text('Approved'),
                        ),
                        DropdownMenuItem(
                          value: 'denied',
                          child: Text('Denied'),
                        ),
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
                    TextFormField(
                      controller: _sanctionNumberController,
                      decoration: const InputDecoration(
                        labelText: 'Sanction number',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _applicantNotesController,
                  minLines: 3,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Applicant notes',
                    border: OutlineInputBorder(),
                  ),
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

  String? _nonNegativeMoney(String? value) {
    final amount = double.tryParse(value?.trim() ?? '');
    if (amount == null || amount < 0) {
      return 'Enter a valid amount.';
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

class _SanctionRequest {
  const _SanctionRequest({
    required this.id,
    required this.requestingClubName,
    required this.contactName,
    required this.showName,
    required this.showDate,
    required this.showType,
    required this.sanctionCategory,
    required this.status,
    required this.feeDue,
    required this.amountPaid,
    required this.currency,
    required this.paymentStatus,
    this.contactEmail,
    this.contactPhone,
    this.showEndDate,
    this.locationName,
    this.locationAddress,
    this.sanctionNumber,
    this.applicantNotes,
    this.staffNotes,
    this.submittedAt,
    this.reviewedAt,
  });

  final String id;
  final String requestingClubName;
  final String contactName;
  final String? contactEmail;
  final String? contactPhone;
  final String showName;
  final DateTime showDate;
  final DateTime? showEndDate;
  final String? locationName;
  final String? locationAddress;
  final String showType;
  final String sanctionCategory;
  final String status;
  final double feeDue;
  final double amountPaid;
  final String currency;
  final String paymentStatus;
  final String? sanctionNumber;
  final String? applicantNotes;
  final String? staffNotes;
  final DateTime? submittedAt;
  final DateTime? reviewedAt;

  String get dateLabel {
    if (showEndDate == null || _sameDay(showDate, showEndDate!)) {
      return _formatDate(showDate);
    }
    return '${_formatDate(showDate)} – ${_formatDate(showEndDate!)}';
  }

  factory _SanctionRequest.fromJson(Map<String, dynamic> json) {
    return _SanctionRequest(
      id: json['id'].toString(),
      requestingClubName:
          _nullableString(json['requesting_club_name']) ?? 'Unknown Club',
      contactName: _nullableString(json['contact_name']) ?? 'Unknown Contact',
      contactEmail: _nullableString(json['contact_email']),
      contactPhone: _nullableString(json['contact_phone']),
      showName: _nullableString(json['show_name']) ?? 'Unnamed Show',
      showDate: _nullableDate(json['show_date']) ?? DateTime.now(),
      showEndDate: _nullableDate(json['show_end_date']),
      locationName: _nullableString(json['location_name']),
      locationAddress: _nullableString(json['location_address']),
      showType: _nullableString(json['show_type']) ?? 'all_breed',
      sanctionCategory:
          _nullableString(json['sanction_category']) ?? 'rabbit',
      status: _nullableString(json['status']) ?? 'pending',
      feeDue: _doubleValue(json['fee_due']),
      amountPaid: _doubleValue(json['amount_paid']),
      currency: _nullableString(json['currency']) ?? 'usd',
      paymentStatus: _nullableString(json['payment_status']) ?? 'unpaid',
      sanctionNumber: _nullableString(json['sanction_number']),
      applicantNotes: _nullableString(json['applicant_notes']),
      staffNotes: _nullableString(json['staff_notes']),
      submittedAt: _nullableDate(json['submitted_at']),
      reviewedAt: _nullableDate(json['reviewed_at']),
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

class _ResponsiveFields extends StatelessWidget {
  const _ResponsiveFields({required this.children});

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
            const Icon(Icons.verified_outlined, size: 52),
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
                icon: const Icon(Icons.add),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _money(double value) => '\$${value.toStringAsFixed(2)}';

String? _nullableString(dynamic value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

DateTime? _nullableDate(dynamic value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) return null;
  return DateTime.tryParse(text);
}

double _doubleValue(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
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

bool _sameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}
