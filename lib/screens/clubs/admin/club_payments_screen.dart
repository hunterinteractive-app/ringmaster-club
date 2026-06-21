// lib/screens/clubs/admin/club_payments_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/clubs/club_summary.dart';

class ClubPaymentsScreen extends StatefulWidget {
  const ClubPaymentsScreen({
    super.key,
    required this.club,
  });

  final ClubSummary club;

  @override
  State<ClubPaymentsScreen> createState() => _ClubPaymentsScreenState();
}

class _ClubPaymentsScreenState extends State<ClubPaymentsScreen> {
  final _supabase = Supabase.instance.client;
  final _searchController = TextEditingController();

  bool _isLoading = true;
  String? _errorMessage;
  String _statusFilter = 'all';
  List<_PaymentRecord> _payments = const [];
  List<_MemberOption> _members = const [];

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
            .from('club_membership_payments')
            .select(
              'id,club_id,club_membership_id,amount_due,amount_paid,currency,'
              'status,payment_method,payment_date,reference_number,'
              'term_start,term_end,notes,receipt_sent_at,created_at',
            )
            .eq('club_id', widget.club.clubId)
            .order('payment_date', ascending: false)
            .order('created_at', ascending: false),
        _supabase
            .from('club_memberships')
            .select('id,first_name,last_name,showing_name,membership_number,email')
            .eq('club_id', widget.club.clubId)
            .order('last_name', ascending: true)
            .order('first_name', ascending: true),
      ]);

      final paymentRows = responses[0] as List;
      final memberRows = responses[1] as List;

      final members = memberRows
          .whereType<Map>()
          .map(
            (row) => _MemberOption.fromJson(
              Map<String, dynamic>.from(row),
            ),
          )
          .toList();

      final memberMap = <String, _MemberOption>{
        for (final member in members) member.id: member,
      };

      final payments = paymentRows
          .whereType<Map>()
          .map(
            (row) {
              final json = Map<String, dynamic>.from(row);
              final memberId = json['club_membership_id']?.toString();
              return _PaymentRecord.fromJson(
                json,
                member: memberId == null ? null : memberMap[memberId],
              );
            },
          )
          .toList();

      if (!mounted) return;

      setState(() {
        _members = members;
        _payments = payments;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _errorMessage = 'Unable to load payments and dues: $error';
      });
    }
  }

  List<_PaymentRecord> get _filteredPayments {
    final query = _searchController.text.trim().toLowerCase();

    return _payments.where((payment) {
      final matchesStatus =
          _statusFilter == 'all' || payment.status == _statusFilter;
      if (!matchesStatus) return false;
      if (query.isEmpty) return true;

      final searchable = [
        payment.member?.displayName,
        payment.member?.membershipNumber,
        payment.member?.email,
        payment.referenceNumber,
        payment.paymentMethod,
      ].whereType<String>().join(' ').toLowerCase();

      return searchable.contains(query);
    }).toList();
  }

  double get _totalDue =>
      _payments.fold(0, (total, payment) => total + payment.amountDue);

  double get _totalPaid =>
      _payments.fold(0, (total, payment) => total + payment.amountPaid);

  double get _totalOutstanding => _payments.fold(
        0,
        (total, payment) => total + payment.outstandingAmount,
      );

  Future<void> _openEditor({_PaymentRecord? existing}) async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PaymentEditorDialog(
        clubId: widget.club.clubId,
        members: _members,
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
        title: const Text('Payments & Dues'),
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
        icon: const Icon(Icons.add_card),
        label: const Text('Record Payment'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null && _payments.isEmpty) {
      return _MessageState(
        icon: Icons.error_outline,
        title: 'Unable to load payments',
        message: _errorMessage!,
        actionLabel: 'Try Again',
        onAction: _loadData,
      );
    }

    final filtered = _filteredPayments;

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
            'Track membership dues, manual payments, balances, refunds, and waivers.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth >= 780
                  ? (constraints.maxWidth - 24) / 3
                  : constraints.maxWidth;

              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: width,
                    child: _SummaryCard(
                      icon: Icons.request_quote_outlined,
                      label: 'Total Due',
                      value: _money(_totalDue),
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _SummaryCard(
                      icon: Icons.payments_outlined,
                      label: 'Total Paid',
                      value: _money(_totalPaid),
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _SummaryCard(
                      icon: Icons.warning_amber_outlined,
                      label: 'Outstanding',
                      value: _money(_totalOutstanding),
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
              labelText: 'Search payments',
              hintText: 'Member, membership number, email, or reference',
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
                ButtonSegment(value: 'unpaid', label: Text('Unpaid')),
                ButtonSegment(value: 'partial', label: Text('Partial')),
                ButtonSegment(value: 'paid', label: Text('Paid')),
                ButtonSegment(value: 'refunded', label: Text('Refunded')),
                ButtonSegment(value: 'waived', label: Text('Waived')),
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
            '${filtered.length} ${filtered.length == 1 ? 'record' : 'records'}',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 12),
          if (_payments.isEmpty)
            _InlineEmptyState(
              title: 'No payments recorded',
              message:
                  'Record a member’s dues or payment to begin tracking balances.',
              actionLabel: 'Record Payment',
              onAction: () => _openEditor(),
            )
          else if (filtered.isEmpty)
            const _InlineEmptyState(
              title: 'No matching payments',
              message: 'Try a different search or payment status filter.',
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
                    for (final payment in filtered)
                      SizedBox(
                        width: width,
                        child: _PaymentCard(
                          payment: payment,
                          onEdit: () => _openEditor(existing: payment),
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

class _PaymentCard extends StatelessWidget {
  const _PaymentCard({
    required this.payment,
    required this.onEdit,
  });

  final _PaymentRecord payment;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final statusColor = _statusColor(payment.status, scheme);

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
                    child: Icon(
                      payment.status == 'paid'
                          ? Icons.check_circle_outline
                          : Icons.payments_outlined,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          payment.member?.displayName ?? 'Unknown Member',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        if (payment.member?.membershipNumber != null)
                          Text(
                            'Member #${payment.member!.membershipNumber}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Edit payment',
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
                    label: Text(_titleCase(payment.status)),
                    backgroundColor: statusColor.withAlpha(40),
                    side: BorderSide(color: statusColor),
                  ),
                  Chip(label: Text(_titleCase(payment.paymentMethod))),
                  if (payment.receiptSentAt != null)
                    const Chip(
                      avatar: Icon(Icons.receipt_long_outlined, size: 18),
                      label: Text('Receipt Sent'),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              _PaymentDetail(
                icon: Icons.request_quote_outlined,
                text: 'Due: ${_money(payment.amountDue)}',
              ),
              _PaymentDetail(
                icon: Icons.payments_outlined,
                text: 'Paid: ${_money(payment.amountPaid)}',
              ),
              if (payment.outstandingAmount > 0)
                _PaymentDetail(
                  icon: Icons.warning_amber_outlined,
                  text: 'Outstanding: ${_money(payment.outstandingAmount)}',
                ),
              if (payment.paymentDate != null)
                _PaymentDetail(
                  icon: Icons.event_outlined,
                  text: 'Payment date: ${_formatDate(payment.paymentDate!)}',
                ),
              if (payment.referenceNumber != null)
                _PaymentDetail(
                  icon: Icons.tag,
                  text: 'Reference: ${payment.referenceNumber}',
                ),
              if (payment.termStart != null || payment.termEnd != null)
                _PaymentDetail(
                  icon: Icons.date_range_outlined,
                  text: payment.termLabel,
                ),
            ],
          ),
        ),
      ),
    );
  }

  static Color _statusColor(String status, ColorScheme scheme) {
    switch (status) {
      case 'paid':
        return scheme.primary;
      case 'partial':
        return scheme.tertiary;
      case 'unpaid':
      case 'refunded':
        return scheme.error;
      case 'waived':
        return scheme.secondary;
      default:
        return scheme.outline;
    }
  }
}

class _PaymentEditorDialog extends StatefulWidget {
  const _PaymentEditorDialog({
    required this.clubId,
    required this.members,
    this.existing,
  });

  final String clubId;
  final List<_MemberOption> members;
  final _PaymentRecord? existing;

  @override
  State<_PaymentEditorDialog> createState() =>
      _PaymentEditorDialogState();
}

class _PaymentEditorDialogState extends State<_PaymentEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  final _supabase = Supabase.instance.client;

  late final TextEditingController _amountDueController;
  late final TextEditingController _amountPaidController;
  late final TextEditingController _currencyController;
  late final TextEditingController _paymentDateController;
  late final TextEditingController _referenceController;
  late final TextEditingController _termStartController;
  late final TextEditingController _termEndController;
  late final TextEditingController _notesController;

  String? _memberId;
  late String _status;
  late String _paymentMethod;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;

    _memberId = existing?.clubMembershipId;
    _status = existing?.status ?? 'unpaid';
    _paymentMethod = existing?.paymentMethod ?? 'other';
    _amountDueController = TextEditingController(
      text: existing?.amountDue.toStringAsFixed(2) ?? '0.00',
    );
    _amountPaidController = TextEditingController(
      text: existing?.amountPaid.toStringAsFixed(2) ?? '0.00',
    );
    _currencyController = TextEditingController(
      text: existing?.currency.toUpperCase() ?? 'USD',
    );
    _paymentDateController = TextEditingController(
      text: _dateText(existing?.paymentDate),
    );
    _referenceController = TextEditingController(
      text: existing?.referenceNumber ?? '',
    );
    _termStartController = TextEditingController(
      text: _dateText(existing?.termStart),
    );
    _termEndController = TextEditingController(
      text: _dateText(existing?.termEnd),
    );
    _notesController = TextEditingController(text: existing?.notes ?? '');
  }

  @override
  void dispose() {
    _amountDueController.dispose();
    _amountPaidController.dispose();
    _currencyController.dispose();
    _paymentDateController.dispose();
    _referenceController.dispose();
    _termStartController.dispose();
    _termEndController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSaving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (_memberId == null) {
      setState(() {
        _errorMessage = 'Select a member.';
      });
      return;
    }

    final termStart = _parseDate(_termStartController.text);
    final termEnd = _parseDate(_termEndController.text);

    if (termStart != null && termEnd != null && termEnd.isBefore(termStart)) {
      setState(() {
        _errorMessage = 'The term end date cannot be before the start date.';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final payload = <String, dynamic>{
      'club_id': widget.clubId,
      'club_membership_id': _memberId,
      'amount_due': double.tryParse(_amountDueController.text.trim()) ?? 0,
      'amount_paid': double.tryParse(_amountPaidController.text.trim()) ?? 0,
      'currency': _currencyController.text.trim().isEmpty
          ? 'usd'
          : _currencyController.text.trim().toLowerCase(),
      'status': _status,
      'payment_method': _paymentMethod,
      'payment_date': _dateValue(_paymentDateController.text),
      'reference_number': _nullIfBlank(_referenceController.text),
      'term_start': _dateValue(_termStartController.text),
      'term_end': _dateValue(_termEndController.text),
      'notes': _nullIfBlank(_notesController.text),
    };

    try {
      final existing = widget.existing;

      if (existing == null) {
        await _supabase.from('club_membership_payments').insert(payload);
      } else {
        await _supabase
            .from('club_membership_payments')
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
        _errorMessage = 'Unable to save payment: $error';
      });
    }
  }

  Future<void> _pickDate(TextEditingController controller) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _parseDate(controller.text) ?? DateTime.now(),
      firstDate: DateTime(1900),
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
        widget.existing == null ? 'Record Payment' : 'Edit Payment',
      ),
      content: SizedBox(
        width: 700,
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
                DropdownButtonFormField<String>(
                  initialValue: _memberId,
                  decoration: const InputDecoration(
                    labelText: 'Member',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final member in widget.members)
                      DropdownMenuItem(
                        value: member.id,
                        child: Text(member.dropdownLabel),
                      ),
                  ],
                  onChanged: _isSaving
                      ? null
                      : (value) => setState(() => _memberId = value),
                  validator: (value) =>
                      value == null ? 'Select a member.' : null,
                ),
                const SizedBox(height: 14),
                _ResponsiveFields(
                  children: [
                    TextFormField(
                      controller: _amountDueController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Amount due',
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
                      initialValue: _status,
                      decoration: const InputDecoration(
                        labelText: 'Status',
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
                          value: 'refunded',
                          child: Text('Refunded'),
                        ),
                        DropdownMenuItem(
                          value: 'waived',
                          child: Text('Waived'),
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
                    DropdownButtonFormField<String>(
                      initialValue: _paymentMethod,
                      decoration: const InputDecoration(
                        labelText: 'Payment method',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'online',
                          child: Text('Online'),
                        ),
                        DropdownMenuItem(
                          value: 'cash',
                          child: Text('Cash'),
                        ),
                        DropdownMenuItem(
                          value: 'check',
                          child: Text('Check'),
                        ),
                        DropdownMenuItem(
                          value: 'card',
                          child: Text('Card'),
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
                                setState(() => _paymentMethod = value);
                              }
                            },
                    ),
                    _DateField(
                      controller: _paymentDateController,
                      label: 'Payment date',
                      onPick: () => _pickDate(_paymentDateController),
                    ),
                    TextFormField(
                      controller: _referenceController,
                      decoration: const InputDecoration(
                        labelText: 'Reference number',
                        hintText: 'Check number, transaction ID, or note',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    _DateField(
                      controller: _termStartController,
                      label: 'Term start',
                      onPick: () => _pickDate(_termStartController),
                    ),
                    _DateField(
                      controller: _termEndController,
                      label: 'Term end',
                      onPick: () => _pickDate(_termEndController),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
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

class _PaymentRecord {
  const _PaymentRecord({
    required this.id,
    required this.clubMembershipId,
    required this.amountDue,
    required this.amountPaid,
    required this.currency,
    required this.status,
    required this.paymentMethod,
    this.member,
    this.paymentDate,
    this.referenceNumber,
    this.termStart,
    this.termEnd,
    this.notes,
    this.receiptSentAt,
  });

  final String id;
  final String clubMembershipId;
  final _MemberOption? member;
  final double amountDue;
  final double amountPaid;
  final String currency;
  final String status;
  final String paymentMethod;
  final DateTime? paymentDate;
  final String? referenceNumber;
  final DateTime? termStart;
  final DateTime? termEnd;
  final String? notes;
  final DateTime? receiptSentAt;

  double get outstandingAmount {
    final amount = amountDue - amountPaid;
    return amount > 0 ? amount : 0;
  }

  String get termLabel {
    if (termStart != null && termEnd != null) {
      return 'Term: ${_formatDate(termStart!)} – ${_formatDate(termEnd!)}';
    }
    if (termStart != null) return 'Term starts ${_formatDate(termStart!)}';
    if (termEnd != null) return 'Term ends ${_formatDate(termEnd!)}';
    return 'No term dates';
  }

  factory _PaymentRecord.fromJson(
    Map<String, dynamic> json, {
    _MemberOption? member,
  }) {
    return _PaymentRecord(
      id: json['id'].toString(),
      clubMembershipId: json['club_membership_id'].toString(),
      member: member,
      amountDue: _doubleValue(json['amount_due']),
      amountPaid: _doubleValue(json['amount_paid']),
      currency: _nullableString(json['currency']) ?? 'usd',
      status: _nullableString(json['status']) ?? 'unpaid',
      paymentMethod: _nullableString(json['payment_method']) ?? 'other',
      paymentDate: _nullableDate(json['payment_date']),
      referenceNumber: _nullableString(json['reference_number']),
      termStart: _nullableDate(json['term_start']),
      termEnd: _nullableDate(json['term_end']),
      notes: _nullableString(json['notes']),
      receiptSentAt: _nullableDate(json['receipt_sent_at']),
    );
  }
}

class _MemberOption {
  const _MemberOption({
    required this.id,
    required this.firstName,
    required this.lastName,
    this.showingName,
    this.membershipNumber,
    this.email,
  });

  final String id;
  final String firstName;
  final String lastName;
  final String? showingName;
  final String? membershipNumber;
  final String? email;

  String get displayName {
    final fullName = '$firstName $lastName'.trim();
    if (showingName != null && showingName!.trim().isNotEmpty) {
      return showingName!;
    }
    return fullName.isEmpty ? 'Unnamed Member' : fullName;
  }

  String get dropdownLabel {
    if (membershipNumber != null) {
      return '$displayName • #$membershipNumber';
    }
    return displayName;
  }

  factory _MemberOption.fromJson(Map<String, dynamic> json) {
    return _MemberOption(
      id: json['id'].toString(),
      firstName: _nullableString(json['first_name']) ?? '',
      lastName: _nullableString(json['last_name']) ?? '',
      showingName: _nullableString(json['showing_name']),
      membershipNumber: _nullableString(json['membership_number']),
      email: _nullableString(json['email']),
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

class _PaymentDetail extends StatelessWidget {
  const _PaymentDetail({
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
        final wide = constraints.maxWidth >= 560;
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
            const Icon(Icons.payments_outlined, size: 52),
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
                icon: const Icon(Icons.add_card),
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