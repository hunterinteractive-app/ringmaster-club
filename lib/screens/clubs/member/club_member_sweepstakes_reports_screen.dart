import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/clubs/club_summary.dart';

enum MemberSweepstakesReportView { applied, outstanding }

class ClubMemberSweepstakesReportsScreen extends StatefulWidget {
  const ClubMemberSweepstakesReportsScreen({
    super.key,
    required this.club,
    required this.view,
  });

  final ClubSummary club;
  final MemberSweepstakesReportView view;

  @override
  State<ClubMemberSweepstakesReportsScreen> createState() =>
      _ClubMemberSweepstakesReportsScreenState();
}

class _ClubMemberSweepstakesReportsScreenState
    extends State<ClubMemberSweepstakesReportsScreen> {
  final _supabase = Supabase.instance.client;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = const [];

  bool get _isApplied => widget.view == MemberSweepstakesReportView.applied;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await _supabase.rpc(
        _isApplied
            ? 'get_member_club_sweepstakes_applied_reports'
            : 'get_member_club_sweepstakes_outstanding_reports',
        params: {'p_club_id': widget.club.clubId},
      );
      if (!mounted) return;
      setState(() {
        _rows = (response as List)
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList();
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_isApplied ? 'Verified Show Reports' : 'Outstanding Reports'),
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: SafeArea(child: _body(context)),
  );

  Widget _body(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return _MemberReportMessage(
        icon: Icons.error_outline,
        title: 'We could not load these reports',
        message: _error!,
        onRefresh: _load,
      );
    }
    if (_rows.isEmpty) {
      return _MemberReportMessage(
        icon: _isApplied ? Icons.fact_check_outlined : Icons.inbox_outlined,
        title: _isApplied
            ? 'No verified show reports yet'
            : 'No outstanding reports',
        message: _isApplied
            ? 'Verified show reports will appear here after their points are applied.'
            : 'All expected show reports have either been processed or waived.',
        onRefresh: _load,
      );
    }
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          _isApplied
              ? 'Reports reflected in standings'
              : 'Reports awaiting completion',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          _isApplied
              ? 'These verified show reports are included in the points shown on the award boards.'
              : 'Received reports are waiting for staff verification. Other reports have not been received yet.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 18),
        ..._rows.map(_isApplied ? _appliedCard : _outstandingCard),
      ],
    );
  }

  Widget _appliedCard(Map<String, dynamic> row) {
    final calculated = _number(row['calculated_total_points']);
    final source = _numberOrNull(row['source_total_points']);
    final details = [
      _textOrNull(row['season_name']),
      _friendlySource(_textOrNull(row['source_type'])),
      'Applied ${_dateTime(row['applied_at']) ?? 'recently'}',
    ].whereType<String>().join(' • ');
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: const Icon(Icons.verified_outlined),
        title: Text(
          _textOrNull(row['show_name']) ?? 'Unnamed show',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          '${_date(row['show_date']) ?? 'Show date not recorded'}\n$details',
        ),
        isThreeLine: true,
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              _points(calculated),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            Text(source == null ? 'verified points' : 'verified points'),
          ],
        ),
      ),
    );
  }

  Widget _outstandingCard(Map<String, dynamic> row) {
    final status = _reportStatus(row);
    final received = _dateTime(row['received_at']);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Icon(
          status.received
              ? Icons.mark_email_read_outlined
              : Icons.mark_email_unread_outlined,
        ),
        title: Text(
          _textOrNull(row['show_name']) ?? 'Unnamed show',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          '${_date(row['show_date']) ?? 'Show date not recorded'} • Due ${_date(row['due_date']) ?? 'not recorded'}\n${status.detail}${received == null ? '' : ' • Received $received'}',
        ),
        isThreeLine: true,
        trailing: Chip(label: Text(status.label)),
      ),
    );
  }
}

class _ReportStatus {
  const _ReportStatus(this.label, this.detail, this.received);
  final String label;
  final String detail;
  final bool received;
}

_ReportStatus _reportStatus(Map<String, dynamic> row) {
  final expected = _textOrNull(row['status'])?.toLowerCase();
  final package = _textOrNull(row['package_status'])?.toLowerCase();
  final received = _textOrNull(row['received_at']) != null || package != null;
  if (package == 'needs_review' ||
      package == 'pending' ||
      package == 'reconciled' ||
      expected == 'needs_review') {
    return const _ReportStatus(
      'Received',
      'Received — waiting for verification',
      true,
    );
  }
  if (package == 'rejected') {
    return const _ReportStatus(
      'Needs action',
      'Received — needs staff follow-up',
      true,
    );
  }
  if (expected == 'partial') {
    return _ReportStatus(
      received ? 'Partial' : 'Not received',
      received
          ? 'Partial report received — waiting for completion'
          : 'Report has not been received',
      received,
    );
  }
  if (expected == 'overdue') {
    return const _ReportStatus(
      'Overdue',
      'Report has not been received',
      false,
    );
  }
  return const _ReportStatus(
    'Not received',
    'Report has not been received',
    false,
  );
}

class _MemberReportMessage extends StatelessWidget {
  const _MemberReportMessage({
    required this.icon,
    required this.title,
    required this.message,
    required this.onRefresh,
  });
  final IconData icon;
  final String title;
  final String message;
  final VoidCallback onRefresh;
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
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh'),
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

num _number(dynamic value) =>
    value is num ? value : num.tryParse('$value') ?? 0;
num? _numberOrNull(dynamic value) => value == null ? null : _number(value);
String _points(num value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(1);
String? _date(dynamic value) {
  final parsed = value == null ? null : DateTime.tryParse(value.toString());
  if (parsed == null) return null;
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
  return '${months[parsed.month - 1]} ${parsed.day}, ${parsed.year}';
}

String? _dateTime(dynamic value) => _date(value);
String? _friendlySource(String? value) => switch (value) {
  'easy2show' => 'Easy2Show',
  'ringmaster_show_breed' || 'ringmaster_show_state' => 'RingMaster Show',
  null => null,
  _ => 'Show report',
};
