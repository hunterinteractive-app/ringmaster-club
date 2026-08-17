import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/clubs/club_summary.dart';

/// Read-only dues and receipt history for the signed-in member.
class ClubMemberPaymentsScreen extends StatefulWidget {
  const ClubMemberPaymentsScreen({super.key, required this.club});

  final ClubSummary club;

  @override
  State<ClubMemberPaymentsScreen> createState() =>
      _ClubMemberPaymentsScreenState();
}

class _ClubMemberPaymentsScreenState extends State<ClubMemberPaymentsScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  bool _paymentsEnabled = false;
  String? _errorMessage;
  List<_MemberPayment> _payments = const [];

  @override
  void initState() {
    super.initState();
    _loadPayments();
  }

  Future<void> _loadPayments() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        throw StateError('Please sign in again to view payments.');
      }

      final clubRow = await _supabase
          .from('clubs')
          .select('membership_management_addon_enabled')
          .eq('id', widget.club.clubId)
          .single();
      final enabled = clubRow['membership_management_addon_enabled'] == true;
      Map<String, dynamic>? membership;
      final summaryMembershipId = widget.club.membershipId?.trim();
      if (summaryMembershipId != null && summaryMembershipId.isNotEmpty) {
        membership = await _supabase
            .from('club_memberships')
            .select('id')
            .eq('club_id', widget.club.clubId)
            .eq('id', summaryMembershipId)
            .maybeSingle();
      }
      membership ??= await _supabase
          .from('club_memberships')
          .select('id')
          .eq('club_id', widget.club.clubId)
          .eq('user_id', user.id)
          .maybeSingle();
      final email = user.email?.trim();
      if (membership == null && email != null && email.isNotEmpty) {
        membership = await _supabase
            .from('club_memberships')
            .select('id')
            .eq('club_id', widget.club.clubId)
            .eq('email', email)
            .limit(1)
            .maybeSingle();
      }
      if (!enabled || membership == null) {
        if (!mounted) return;
        setState(() {
          _paymentsEnabled = enabled;
          _payments = const [];
          _isLoading = false;
        });
        return;
      }

      final rows = await _supabase
          .from('club_membership_payments')
          .select(
            'id,amount_due,amount_paid,currency,status,payment_method,'
            'payment_date,reference_number,term_start,term_end,notes,'
            'receipt_sent_at,created_at',
          )
          .eq('club_id', widget.club.clubId)
          .eq('club_membership_id', membership['id'])
          .order('payment_date', ascending: false)
          .order('created_at', ascending: false);
      final payments = (rows as List)
          .whereType<Map>()
          .map((row) => _MemberPayment.fromJson(Map<String, dynamic>.from(row)))
          .toList();
      if (!mounted) return;
      setState(() {
        _paymentsEnabled = true;
        _payments = payments;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Unable to load payment history: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payments & Receipts'),
        actions: [
          IconButton(
            tooltip: 'Refresh payments',
            onPressed: _isLoading ? null : _loadPayments,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(child: _buildBody(context)),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_errorMessage != null) {
      return _PaymentsMessageState(
        icon: Icons.error_outline,
        title: 'We could not load payment history',
        message: _errorMessage!,
        actionLabel: 'Try again',
        onAction: _loadPayments,
      );
    }
    if (!_paymentsEnabled) {
      return _PaymentsMessageState(
        icon: Icons.receipt_long_outlined,
        title: 'Payments are not enabled yet',
        message:
            '${widget.club.displayName} has not enabled online dues and receipt tracking.',
        actionLabel: 'Refresh',
        onAction: _loadPayments,
      );
    }
    if (_payments.isEmpty) {
      return _PaymentsMessageState(
        icon: Icons.payment_outlined,
        title: 'No payment history yet',
        message:
            'When ${widget.club.displayName} records a membership due or payment, it will appear here.',
        actionLabel: 'Refresh',
        onAction: _loadPayments,
      );
    }
    final outstanding = _payments.fold<num>(
      0,
      (total, payment) => total + payment.outstanding,
    );
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Payments & receipts',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          'Your membership dues and payment history with ${widget.club.displayName}.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 18),
        Card(
          child: ListTile(
            leading: const Icon(
              Icons.account_balance_wallet_outlined,
              size: 30,
            ),
            title: const Text(
              'Outstanding balance',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            trailing: Text(
              _money(outstanding, _payments.first.currency),
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
        ),
        const SizedBox(height: 16),
        ..._payments.map((payment) => _PaymentCard(payment: payment)),
      ],
    );
  }
}

class _MemberPayment {
  const _MemberPayment({
    required this.amountDue,
    required this.amountPaid,
    required this.currency,
    required this.status,
    required this.paymentMethod,
    required this.paymentDate,
    required this.referenceNumber,
    required this.termStart,
    required this.termEnd,
    required this.notes,
    required this.receiptSentAt,
    required this.createdAt,
  });

  final num amountDue;
  final num amountPaid;
  final String currency;
  final String status;
  final String? paymentMethod;
  final DateTime? paymentDate;
  final String? referenceNumber;
  final DateTime? termStart;
  final DateTime? termEnd;
  final String? notes;
  final DateTime? receiptSentAt;
  final DateTime createdAt;

  num get outstanding => (amountDue - amountPaid).clamp(0, double.infinity);
  DateTime get sortDate => paymentDate ?? createdAt;

  factory _MemberPayment.fromJson(Map<String, dynamic> json) => _MemberPayment(
    amountDue: _numOrZero(json['amount_due']),
    amountPaid: _numOrZero(json['amount_paid']),
    currency: _textOrNull(json['currency']) ?? 'USD',
    status: _textOrNull(json['status']) ?? 'unpaid',
    paymentMethod: _textOrNull(json['payment_method']),
    paymentDate: _dateOrNull(json['payment_date']),
    referenceNumber: _textOrNull(json['reference_number']),
    termStart: _dateOrNull(json['term_start']),
    termEnd: _dateOrNull(json['term_end']),
    notes: _textOrNull(json['notes']),
    receiptSentAt: _dateOrNull(json['receipt_sent_at']),
    createdAt: _dateOrNull(json['created_at']) ?? DateTime.now(),
  );
}

class _PaymentCard extends StatelessWidget {
  const _PaymentCard({required this.payment});
  final _MemberPayment payment;

  @override
  Widget build(BuildContext context) {
    final isPaid =
        payment.status.toLowerCase() == 'paid' || payment.outstanding == 0;
    final detail = [
      _termLabel(payment.termStart, payment.termEnd),
      if (payment.paymentMethod != null) _titleCase(payment.paymentMethod!),
      if (payment.referenceNumber != null) 'Ref. ${payment.referenceNumber}',
    ].whereType<String>().where((item) => item.isNotEmpty).join(' • ');
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: Icon(
          isPaid ? Icons.check_circle_outline : Icons.pending_outlined,
        ),
        title: Text(
          isPaid ? 'Membership payment' : 'Membership balance',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(detail.isEmpty ? _formatDate(payment.sortDate) : detail),
        trailing: Text(
          _money(
            isPaid ? payment.amountPaid : payment.outstanding,
            payment.currency,
          ),
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
        children: [
          _PaymentDetail(label: 'Status', value: _titleCase(payment.status)),
          _PaymentDetail(
            label: 'Amount due',
            value: _money(payment.amountDue, payment.currency),
          ),
          _PaymentDetail(
            label: 'Amount paid',
            value: _money(payment.amountPaid, payment.currency),
          ),
          if (payment.paymentDate != null)
            _PaymentDetail(
              label: 'Payment date',
              value: _formatDate(payment.paymentDate!),
            ),
          _PaymentDetail(
            label: 'Receipt',
            value: payment.receiptSentAt == null
                ? 'Not sent yet'
                : 'Sent ${_formatDate(payment.receiptSentAt!)}',
          ),
          if (payment.notes != null)
            _PaymentDetail(label: 'Notes', value: payment.notes!),
        ],
      ),
    );
  }
}

class _PaymentDetail extends StatelessWidget {
  const _PaymentDetail({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 112, child: Text(label)),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

class _PaymentsMessageState extends StatelessWidget {
  const _PaymentsMessageState({
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
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 46),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: onAction,
            icon: const Icon(Icons.refresh),
            label: Text(actionLabel),
          ),
        ],
      ),
    ),
  );
}

String? _textOrNull(dynamic value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

DateTime? _dateOrNull(dynamic value) {
  final text = _textOrNull(value);
  return text == null ? null : DateTime.tryParse(text)?.toLocal();
}

num _numOrZero(dynamic value) =>
    value is num ? value : num.tryParse('$value') ?? 0;
String _money(num value, String currency) =>
    '${currency.toUpperCase() == 'USD' ? '\$' : '${currency.toUpperCase()} '}${value.toStringAsFixed(2)}';
String _formatDate(DateTime value) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[value.month - 1]} ${value.day}, ${value.year}';
}

String _termLabel(DateTime? start, DateTime? end) {
  if (start != null && end != null) {
    return '${_formatDate(start)} – ${_formatDate(end)}';
  }
  if (end != null) return 'Term ends ${_formatDate(end)}';
  return '';
}

String _titleCase(String value) => value
    .split(RegExp(r'[_\s-]+'))
    .where((part) => part.isNotEmpty)
    .map((part) => '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}')
    .join(' ');
