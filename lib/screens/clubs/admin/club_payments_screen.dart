// lib/screens/clubs/admin/club_payments_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/clubs/club_summary.dart';
import '../../../services/clubs/club_communications_service.dart';

class ClubPaymentsScreen extends StatefulWidget {
  const ClubPaymentsScreen({super.key, required this.club});

  final ClubSummary club;

  @override
  State<ClubPaymentsScreen> createState() => _ClubPaymentsScreenState();
}

class _ClubPaymentsScreenState extends State<ClubPaymentsScreen> {
  final _supabase = Supabase.instance.client;
  final _communicationsService = ClubCommunicationsService();
  final _searchController = TextEditingController();

  bool _isLoading = true;
  String? _errorMessage;
  bool _membershipManagementAddonEnabled = false;
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
      final clubRow = await _supabase
          .from('clubs')
          .select('membership_management_addon_enabled')
          .eq('id', widget.club.clubId)
          .single();

      final membershipManagementAddonEnabled =
          clubRow['membership_management_addon_enabled'] == true;

      if (!membershipManagementAddonEnabled) {
        if (!mounted) return;
        setState(() {
          _membershipManagementAddonEnabled = false;
          _members = const [];
          _payments = const [];
          _isLoading = false;
        });
        return;
      }

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
            .select(
              'id,first_name,last_name,showing_name,membership_number,email',
            )
            .eq('club_id', widget.club.clubId)
            .order('last_name', ascending: true)
            .order('first_name', ascending: true),
        _supabase
            .from('club_membership_applications')
            .select(
              'id,club_id,membership_type_id,status,payment_status,first_name,last_name,'
              'showing_name,email,applicant_message,application_details,submitted_at,created_at',
            )
            .eq('club_id', widget.club.clubId)
            .order('submitted_at', ascending: false)
            .order('created_at', ascending: false),
        _supabase
            .from('club_payments')
            .select(
              'id,club_id,source_type,source_id,payment_method,status,'
              'amount_subtotal,amount_total,amount_paid,currency,fee_mode,'
              'stripe_checkout_session_id,stripe_payment_intent_id,reference_number,'
              'notes,recorded_at,created_at,updated_at',
            )
            .eq('club_id', widget.club.clubId)
            .order('recorded_at', ascending: false)
            .order('created_at', ascending: false),
      ]);

      final paymentRows = responses[0] as List;
      final memberRows = responses[1] as List;
      final applicationRows = responses[2] as List;
      final clubPaymentRows = responses[3] as List;

      final members = memberRows
          .whereType<Map>()
          .map((row) => _MemberOption.fromJson(Map<String, dynamic>.from(row)))
          .toList();

      final memberMap = <String, _MemberOption>{
        for (final member in members) member.id: member,
      };

      final clubPaymentBySource = <String, Map<String, dynamic>>{};
      for (final row in clubPaymentRows.whereType<Map>()) {
        final json = Map<String, dynamic>.from(row);
        final sourceType = json['source_type']?.toString();
        final sourceId = json['source_id']?.toString();
        if (sourceType == null || sourceId == null) continue;
        clubPaymentBySource['$sourceType:$sourceId'] = json;
      }

      final payments = <_PaymentRecord>[];

      for (final row in paymentRows.whereType<Map>()) {
        payments.add(
          _PaymentRecord.fromMembershipPaymentJson(
            Map<String, dynamic>.from(row),
            member: memberMap[row['club_membership_id']?.toString()],
          ),
        );
      }

      for (final row in applicationRows.whereType<Map>()) {
        final json = Map<String, dynamic>.from(row);
        final applicationId = json['id']?.toString();
        payments.add(
          _PaymentRecord.fromMembershipApplicationJson(
            json,
            clubPayment: applicationId == null
                ? null
                : clubPaymentBySource['membership_due:$applicationId'],
          ),
        );
      }

      for (final row in clubPaymentRows.whereType<Map>()) {
        if ((row['source_type']?.toString() ?? '') == 'membership_due') {
          continue;
        }
        payments.add(
          _PaymentRecord.fromClubPaymentJson(Map<String, dynamic>.from(row)),
        );
      }

      payments.sort((a, b) => b.sortDate.compareTo(a.sortDate));

      if (!mounted) return;

      setState(() {
        _membershipManagementAddonEnabled = true;
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
          _statusFilter == 'all' ||
          payment.status == _statusFilter ||
          payment.bucket == _statusFilter;
      if (!matchesStatus) return false;
      if (query.isEmpty) return true;

      final searchable = [
        payment.displayName,
        payment.subtitle,
        payment.member?.displayName,
        payment.member?.membershipNumber,
        payment.member?.email,
        payment.referenceNumber,
        payment.paymentMethod,
        payment.sourceType,
      ].whereType<String>().join(' ').toLowerCase();

      return searchable.contains(query);
    }).toList();
  }

  Future<void> _markPaymentRecordPaid(_PaymentRecord payment) async {
    if (payment.sourceType == null || payment.sourceId == null) return;

    setState(() => _errorMessage = null);

    try {
      final now = DateTime.now().toIso8601String();

      if (payment.sourceType == 'membership_due') {
        await _supabase
            .from('club_membership_applications')
            .update({'payment_status': 'paid'})
            .eq('id', payment.sourceId!);

        final existingPayment = await _supabase
            .from('club_payments')
            .select('id')
            .eq('club_id', widget.club.clubId)
            .eq('source_type', payment.sourceType!)
            .eq('source_id', payment.sourceId!)
            .maybeSingle();

        final payload = {
          'club_id': widget.club.clubId,
          'source_type': payment.sourceType,
          'source_id': payment.sourceId,
          'payment_method': 'check',
          'status': 'paid',
          'amount_subtotal': (payment.amountDue * 100).round(),
          'amount_total': (payment.amountDue * 100).round(),
          'amount_paid': (payment.amountDue * 100).round(),
          'currency': payment.currency.toLowerCase(),
          'fee_mode': 'club_handled',
          'notes': 'Marked paid from Payments & Dues.',
          'recorded_at': now,
          'updated_at': now,
        };

        if (existingPayment == null) {
          await _supabase.from('club_payments').insert(payload);
        } else {
          await _supabase
              .from('club_payments')
              .update(payload)
              .eq('id', existingPayment['id']);
        }
      } else if (payment.sourceType == 'sanction_request') {
        await _supabase
            .from('club_sanction_requests')
            .update({
              'payment_status': 'paid',
              'amount_paid': payment.amountDue,
            })
            .eq('id', payment.sourceId!);
      }

      await _createPaymentCommunication(
        payment,
        templateKey: 'payment_received',
        staffMessage: '',
      );

      await _loadData();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Unable to mark payment paid: $error';
      });
    }
  }

  Future<void> _sendPendingCheckReminder(_PaymentRecord payment) async {
    if (payment.sourceType == null || payment.sourceId == null) return;

    setState(() => _errorMessage = null);

    try {
      await _createPaymentCommunication(
        payment,
        templateKey: 'pending_check_reminder',
        staffMessage:
            'Please mail your check so the club can complete this payment.',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pending check reminder created.')),
      );
      await _loadData();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Unable to create pending check reminder: $error';
      });
    }
  }

  Future<void> _createPaymentCommunication(
    _PaymentRecord payment, {
    required String templateKey,
    required String staffMessage,
  }) async {
    final recipient = await _loadPaymentRecipient(payment);
    if (recipient == null) return;

    await _communicationsService.createWorkflowCommunication(
      clubId: widget.club.clubId,
      clubName: widget.club.clubName,
      templateKey: templateKey,
      relatedType: payment.sourceType!,
      relatedId: payment.sourceId!,
      recipientUserId: recipient.userId,
      recipientEmail: recipient.email,
      recipientName: recipient.name,
      audienceType: payment.sourceType!,
      variables: {
        'amount_due': _money(payment.amountDue),
        'amount_paid': _money(
          templateKey == 'payment_received'
              ? payment.amountDue
              : payment.amountPaid,
        ),
        'payment_method': _titleCase(payment.paymentMethod),
        'treasurer_mailing_address': recipient.treasurerMailingAddress ?? '',
        'staff_message': staffMessage,
      },
      preferEmailWhenAvailable: true,
      createdBy: _supabase.auth.currentUser?.id,
    );
  }

  Future<_PaymentRecipient?> _loadPaymentRecipient(
    _PaymentRecord payment,
  ) async {
    if (payment.sourceType == 'membership_due') {
      final row = await _supabase
          .from('club_membership_applications')
          .select('user_id,first_name,last_name,email,application_details')
          .eq('id', payment.sourceId!)
          .maybeSingle();
      if (row == null) return null;

      final firstName = _nullableString(row['first_name']) ?? '';
      final lastName = _nullableString(row['last_name']) ?? '';
      final details = _nullableJsonMap(row['application_details']);
      final checkPayment = details?['check_payment'];
      return _PaymentRecipient(
        userId: _nullableString(row['user_id']),
        email: _nullableString(row['email']),
        name: '$firstName $lastName'.trim().isEmpty
            ? payment.displayName
            : '$firstName $lastName'.trim(),
        treasurerMailingAddress: checkPayment is Map
            ? _nullableString(checkPayment['mailing_address'])
            : null,
      );
    }

    if (payment.sourceType == 'sanction_request') {
      final row = await _supabase
          .from('club_sanction_requests')
          .select('contact_name,contact_email,request_details')
          .eq('id', payment.sourceId!)
          .maybeSingle();
      if (row == null) return null;

      final details = _nullableJsonMap(row['request_details']);
      final checkPayment = details?['check_payment'];
      return _PaymentRecipient(
        email: _nullableString(row['contact_email']),
        name: _nullableString(row['contact_name']) ?? payment.displayName,
        treasurerMailingAddress: checkPayment is Map
            ? _nullableString(checkPayment['mailing_address'])
            : null,
      );
    }

    return null;
  }

  double get _totalDue =>
      _payments.fold(0, (total, payment) => total + payment.amountDue);

  double get _totalPaid =>
      _payments.fold(0, (total, payment) => total + payment.amountPaid);

  double get _totalOutstanding =>
      _payments.fold(0, (total, payment) => total + payment.outstandingAmount);

  void _showLockedFeature() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Payments & Dues Requires an Add-on'),
        content: const Text(
          'Payment integration, dues tracking, offline payment records, balances, and receipt tracking are available with the Membership Management Add-on. The club owner can enable this when the club is ready to use it.',
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

  Future<void> _openEditor({_PaymentRecord? existing}) async {
    if (!_membershipManagementAddonEnabled) {
      _showLockedFeature();
      return;
    }

    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PaymentEditorDialog(
        clubId: widget.club.clubId,
        clubName: widget.club.clubName,
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
        onPressed: _isLoading
            ? null
            : _membershipManagementAddonEnabled
            ? () => _openEditor()
            : _showLockedFeature,
        icon: Icon(
          _membershipManagementAddonEnabled
              ? Icons.add_card
              : Icons.lock_outline,
        ),
        label: Text(
          _membershipManagementAddonEnabled
              ? 'Record Payment'
              : 'Add-on Required',
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_membershipManagementAddonEnabled) {
      return _LockedAddOnState(
        clubName: widget.club.clubName,
        onRefresh: _loadData,
      );
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
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
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
                ButtonSegment(value: 'online', label: Text('Online')),
                ButtonSegment(
                  value: 'pending_check',
                  label: Text('Pending Checks'),
                ),
                ButtonSegment(value: 'manual', label: Text('Manual')),
                ButtonSegment(value: 'unpaid', label: Text('Unpaid')),
                ButtonSegment(value: 'paid', label: Text('Paid')),
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
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
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
                          onEdit: payment.canEditAsMembershipPayment
                              ? () => _openEditor(existing: payment)
                              : null,
                          onMarkPaid: payment.canMarkPaid
                              ? () => _markPaymentRecordPaid(payment)
                              : null,
                          onSendReminder: payment.canSendPendingCheckReminder
                              ? () => _sendPendingCheckReminder(payment)
                              : null,
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
    this.onEdit,
    this.onMarkPaid,
    this.onSendReminder,
  });

  final _PaymentRecord payment;
  final VoidCallback? onEdit;
  final VoidCallback? onMarkPaid;
  final VoidCallback? onSendReminder;

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
                          payment.displayName,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        if (payment.subtitle != null)
                          Text(
                            payment.subtitle!,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                  if (onEdit != null)
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
              if (payment.notes != null)
                _PaymentDetail(
                  icon: Icons.notes_outlined,
                  text: payment.notes!,
                ),
              if (onMarkPaid != null || onSendReminder != null) ...[
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerRight,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (onSendReminder != null)
                        OutlinedButton.icon(
                          onPressed: onSendReminder,
                          icon: const Icon(Icons.mark_email_unread_outlined),
                          label: const Text('Remind'),
                        ),
                      if (onMarkPaid != null)
                        FilledButton.icon(
                          onPressed: onMarkPaid,
                          icon: const Icon(Icons.check_circle_outline),
                          label: const Text('Mark Paid'),
                        ),
                    ],
                  ),
                ),
              ],
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
    required this.clubName,
    required this.members,
    this.existing,
  });

  final String clubId;
  final String clubName;
  final List<_MemberOption> members;
  final _PaymentRecord? existing;

  @override
  State<_PaymentEditorDialog> createState() => _PaymentEditorDialogState();
}

class _PaymentEditorDialogState extends State<_PaymentEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  final _supabase = Supabase.instance.client;
  final _communicationsService = ClubCommunicationsService();

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
      late final String paymentId;

      if (existing == null) {
        final inserted = await _supabase
            .from('club_membership_payments')
            .insert(payload)
            .select('id')
            .single();
        paymentId = inserted['id'].toString();
      } else {
        await _supabase
            .from('club_membership_payments')
            .update(payload)
            .eq('id', existing.id)
            .eq('club_id', widget.clubId);
        paymentId = existing.id;
      }

      final shouldSendReceipt = _status == 'paid' && existing?.status != 'paid';
      if (shouldSendReceipt) {
        await _createManualPaymentReceivedCommunication(paymentId);
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

  Future<void> _createManualPaymentReceivedCommunication(String paymentId) async {
    final memberId = _memberId;
    if (memberId == null) return;

    final member = widget.members.where((item) => item.id == memberId).firstOrNull;
    if (member == null) return;

    await _communicationsService.createWorkflowCommunication(
      clubId: widget.clubId,
      clubName: widget.clubName,
      templateKey: 'payment_received',
      relatedType: 'membership_due',
      relatedId: paymentId,
      recipientEmail: member.email,
      recipientName: member.displayName,
      audienceType: 'membership_due',
      variables: {
        'amount_due': _money(
          double.tryParse(_amountDueController.text.trim()) ?? 0,
        ),
        'amount_paid': _money(
          double.tryParse(_amountPaidController.text.trim()) ?? 0,
        ),
        'payment_method': _titleCase(_paymentMethod),
        'treasurer_mailing_address': '',
        'staff_message': '',
      },
      preferEmailWhenAvailable: true,
      createdBy: _supabase.auth.currentUser?.id,
    );
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
      title: Text(widget.existing == null ? 'Record Payment' : 'Edit Payment'),
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
                        DropdownMenuItem(value: 'paid', child: Text('Paid')),
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
                        DropdownMenuItem(value: 'cash', child: Text('Cash')),
                        DropdownMenuItem(value: 'check', child: Text('Check')),
                        DropdownMenuItem(value: 'card', child: Text('Card')),
                        DropdownMenuItem(value: 'other', child: Text('Other')),
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
    required this.amountDue,
    required this.amountPaid,
    required this.currency,
    required this.status,
    required this.paymentMethod,
    required this.displayName,
    required this.sortDate,
    required this.bucket,
    this.clubMembershipId,
    this.member,
    this.subtitle,
    this.sourceType,
    this.sourceId,
    this.paymentDate,
    this.referenceNumber,
    this.termStart,
    this.termEnd,
    this.notes,
    this.receiptSentAt,
  });

  final String id;
  final String? clubMembershipId;
  final _MemberOption? member;
  final double amountDue;
  final double amountPaid;
  final String currency;
  final String status;
  final String paymentMethod;
  final String displayName;
  final String? subtitle;
  final String? sourceType;
  final String? sourceId;
  final DateTime sortDate;
  final String bucket;
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

  bool get canEditAsMembershipPayment =>
      sourceType == null && clubMembershipId != null;

  bool get canMarkPaid {
    if (status == 'paid' || status == 'waived') return false;
    return sourceType == 'membership_due' || sourceType == 'sanction_request';
  }

  bool get canSendPendingCheckReminder {
    if (sourceType != 'membership_due' && sourceType != 'sanction_request') {
      return false;
    }
    if (status == 'paid' || status == 'waived') return false;
    return bucket == 'pending_check' ||
        paymentMethod.toLowerCase().contains('check');
  }

  String get termLabel {
    if (termStart != null && termEnd != null) {
      return 'Term: ${_formatDate(termStart!)} – ${_formatDate(termEnd!)}';
    }
    if (termStart != null) return 'Term starts ${_formatDate(termStart!)}';
    if (termEnd != null) return 'Term ends ${_formatDate(termEnd!)}';
    return 'No term dates';
  }

  factory _PaymentRecord.fromMembershipPaymentJson(
    Map<String, dynamic> json, {
    _MemberOption? member,
  }) {
    final createdAt = _nullableDate(json['created_at']) ?? DateTime.now();
    final paymentDate = _nullableDate(json['payment_date']);
    final memberName = member?.displayName ?? 'Unknown Member';
    return _PaymentRecord(
      id: json['id'].toString(),
      clubMembershipId: json['club_membership_id']?.toString(),
      member: member,
      amountDue: _doubleValue(json['amount_due']),
      amountPaid: _doubleValue(json['amount_paid']),
      currency: _nullableString(json['currency']) ?? 'usd',
      status: _nullableString(json['status']) ?? 'unpaid',
      paymentMethod: _nullableString(json['payment_method']) ?? 'other',
      displayName: memberName,
      subtitle: member?.membershipNumber == null
          ? 'Manual dues record'
          : 'Manual dues record • Member #${member!.membershipNumber}',
      sortDate: paymentDate ?? createdAt,
      bucket: 'manual',
      paymentDate: paymentDate,
      referenceNumber: _nullableString(json['reference_number']),
      termStart: _nullableDate(json['term_start']),
      termEnd: _nullableDate(json['term_end']),
      notes: _nullableString(json['notes']),
      receiptSentAt: _nullableDate(json['receipt_sent_at']),
    );
  }

  factory _PaymentRecord.fromMembershipApplicationJson(
    Map<String, dynamic> json, {
    Map<String, dynamic>? clubPayment,
  }) {
    final details = _nullableJsonMap(json['application_details']);
    final membershipType = details?['membership_type'];
    final checkPayment = details?['check_payment'];
    final amountCents = membershipType is Map
        ? _intValue(membershipType['checkout_amount_cents'])
        : 0;
    final currency = membershipType is Map
        ? (_nullableString(membershipType['currency']) ?? 'usd')
        : 'usd';
    final paidCents = clubPayment == null
        ? 0
        : _intValue(clubPayment['amount_paid']);
    final paymentStatus = _nullableString(json['payment_status']) ?? 'unpaid';
    final checkSelected =
        checkPayment is Map && checkPayment['selected'] == true;
    final status = clubPayment == null
        ? paymentStatus
        : (_nullableString(clubPayment['status']) ?? paymentStatus);
    final method = checkSelected
        ? 'check'
        : (_nullableString(clubPayment?['payment_method']) ??
              _nullableString(details?['payment_method']) ??
              'membership_due');
    final submittedAt =
        _nullableDate(json['submitted_at']) ??
        _nullableDate(json['created_at']) ??
        DateTime.now();
    final firstName = _nullableString(json['first_name']) ?? '';
    final lastName = _nullableString(json['last_name']) ?? '';
    final showingName = _nullableString(json['showing_name']);
    final fullName = '$firstName $lastName'.trim();
    final displayName = showingName == null || showingName.isEmpty
        ? (fullName.isEmpty ? 'Membership Application' : fullName)
        : showingName;

    return _PaymentRecord(
      id: json['id'].toString(),
      amountDue: amountCents / 100,
      amountPaid: paidCents / 100,
      currency: currency,
      status: status,
      paymentMethod: method,
      displayName: displayName,
      subtitle:
          'Membership application • ${_titleCase(_nullableString(json['status']) ?? 'pending')}',
      sourceType: 'membership_due',
      sourceId: json['id'].toString(),
      sortDate: submittedAt,
      bucket: checkSelected && status != 'paid' ? 'pending_check' : 'online',
      paymentDate: _nullableDate(clubPayment?['recorded_at']),
      referenceNumber:
          _nullableString(clubPayment?['reference_number']) ??
          _nullableString(clubPayment?['stripe_payment_intent_id']),
      notes: _nullableString(json['applicant_message']),
    );
  }

  factory _PaymentRecord.fromClubPaymentJson(Map<String, dynamic> json) {
    final sourceType = _nullableString(json['source_type']);
    final sourceId = _nullableString(json['source_id']);
    final amountTotal = _intValue(json['amount_total']);
    final amountPaid = _intValue(json['amount_paid']);
    final status = _nullableString(json['status']) ?? 'pending';
    final method = _nullableString(json['payment_method']) ?? 'online_card';
    final createdAt =
        _nullableDate(json['recorded_at']) ??
        _nullableDate(json['created_at']) ??
        DateTime.now();

    return _PaymentRecord(
      id: json['id'].toString(),
      amountDue: amountTotal / 100,
      amountPaid: amountPaid / 100,
      currency: _nullableString(json['currency']) ?? 'usd',
      status: status,
      paymentMethod: method,
      displayName: _titleCase(sourceType ?? 'Club Payment'),
      subtitle: sourceId == null ? null : 'Source ID: $sourceId',
      sourceType: sourceType,
      sourceId: sourceId,
      sortDate: createdAt,
      bucket: method.contains('check') ? 'pending_check' : 'online',
      paymentDate: _nullableDate(json['recorded_at']),
      referenceNumber:
          _nullableString(json['reference_number']) ??
          _nullableString(json['stripe_payment_intent_id']),
      notes: _nullableString(json['notes']),
    );
  }
}

class _PaymentRecipient {
  const _PaymentRecipient({
    required this.name,
    this.userId,
    this.email,
    this.treasurerMailingAddress,
  });

  final String name;
  final String? userId;
  final String? email;
  final String? treasurerMailingAddress;
}

Map<String, dynamic>? _nullableJsonMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return null;
}

int _intValue(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '') ?? 0;
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
  const _PaymentDetail({required this.icon, required this.text});

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

class _LockedAddOnState extends StatelessWidget {
  const _LockedAddOnState({required this.clubName, required this.onRefresh});

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
                    'Membership Management Add-on Required',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '$clubName does not currently have the Membership Management Add-on enabled.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'This add-on enables payment integration, dues tracking, offline payment records, balances, and receipt tracking.',
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
