// lib/screens/clubs/admin/club_reports_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/clubs/club_summary.dart';

class ClubReportsScreen extends StatefulWidget {
  const ClubReportsScreen({
    super.key,
    required this.club,
  });

  final ClubSummary club;

  @override
  State<ClubReportsScreen> createState() => _ClubReportsScreenState();
}

class _ClubReportsScreenState extends State<ClubReportsScreen> {
  final _supabase = Supabase.instance.client;

  bool _isLoading = true;
  String? _errorMessage;
  _ClubReportsDashboard? _dashboard;
  _ClubReportFeatureAccess _features = const _ClubReportFeatureAccess.base();

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final clubResponse = await _supabase
          .from('clubs')
          .select(
            'membership_management_addon_enabled,'
            'sanction_requests_addon_enabled,'
            'events_meetings_addon_enabled,'
            'sweepstakes_addon_enabled',
          )
          .eq('id', widget.club.clubId)
          .single();

      final dashboardResponse = await _supabase.rpc(
        'get_club_reports_dashboard',
        params: {'p_club_id': widget.club.clubId},
      );

      final clubRow = Map<String, dynamic>.from(clubResponse);
      final dashboardRow = Map<String, dynamic>.from(dashboardResponse as Map);

      if (!mounted) return;
      setState(() {
        _features = _ClubReportFeatureAccess.fromJson(clubRow);
        _dashboard = _ClubReportsDashboard.fromJson(dashboardRow);
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Unable to load reports dashboard: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _loadDashboard,
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

    if (_errorMessage != null && _dashboard == null) {
      return _MessageState(
        icon: Icons.error_outline,
        title: 'Unable to load reports',
        message: _errorMessage!,
        actionLabel: 'Try Again',
        onAction: _loadDashboard,
      );
    }

    final dashboard = _dashboard;
    if (dashboard == null) {
      return _MessageState(
        icon: Icons.bar_chart_outlined,
        title: 'No report data',
        message: 'No dashboard data was returned for this club.',
        actionLabel: 'Refresh',
        onAction: _loadDashboard,
      );
    }

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
            'Dashboard overview of memberships, applications, communications, documents, and enabled add-on reports.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          _ReportsAccessSummaryCard(features: _features),
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
          const _SectionTitle('Membership'),
          _ResponsiveCards(
            children: [
              _ReportMetricCard(
                icon: Icons.people_outline,
                label: 'Total Members',
                value: dashboard.membership.totalMembers.toString(),
              ),
              _ReportMetricCard(
                icon: Icons.verified_user_outlined,
                label: 'Active',
                value: dashboard.membership.activeMembers.toString(),
              ),
              _ReportMetricCard(
                icon: Icons.pending_actions_outlined,
                label: 'Pending',
                value: dashboard.membership.pendingMembers.toString(),
              ),
              _ReportMetricCard(
                icon: Icons.event_busy_outlined,
                label: 'Expired',
                value: dashboard.membership.expiredMembers.toString(),
              ),
              _ReportMetricCard(
                icon: Icons.warning_amber_outlined,
                label: 'Expiring Soon',
                value: dashboard.membership.expiringSoon.toString(),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const _SectionTitle('Payments & Dues'),
          if (_features.membershipManagement)
            _ResponsiveCards(
              children: [
                _ReportMetricCard(
                  icon: Icons.payments_outlined,
                  label: 'Total Due',
                  value: _money(dashboard.payments.totalDue),
                ),
                _ReportMetricCard(
                  icon: Icons.check_circle_outline,
                  label: 'Collected',
                  value: _money(dashboard.payments.totalPaid),
                ),
                _ReportMetricCard(
                  icon: Icons.account_balance_wallet_outlined,
                  label: 'Outstanding',
                  value: _money(dashboard.payments.outstanding),
                ),
                _ReportMetricCard(
                  icon: Icons.receipt_long_outlined,
                  label: 'Unpaid Records',
                  value: dashboard.payments.unpaidCount.toString(),
                ),
              ],
            )
          else
            const _LockedReportSection(
              title: 'Membership Management Add-on Required',
              message:
                  'Payment totals, collected dues, outstanding balances, and unpaid records are available when the Membership Management Add-on is enabled.',
            ),
          const SizedBox(height: 20),
          const _SectionTitle('Operations'),
          _ResponsiveCards(
            children: [
              _ReportMetricCard(
                icon: Icons.assignment_outlined,
                label: 'Applications',
                value: dashboard.operations.totalApplications.toString(),
                helper: '${dashboard.operations.pendingApplications} pending',
              ),
              _ReportMetricCard(
                icon: _features.sanctionRequests
                    ? Icons.approval_outlined
                    : Icons.lock_outline,
                label: 'Sanctions',
                value: _features.sanctionRequests
                    ? dashboard.operations.totalSanctions.toString()
                    : 'Locked',
                helper: _features.sanctionRequests
                    ? '${dashboard.operations.pendingSanctions} pending'
                    : 'Sanction Requests Add-on',
              ),
              _ReportMetricCard(
                icon: Icons.campaign_outlined,
                label: 'Communications',
                value: dashboard.operations.totalCommunications.toString(),
                helper:
                    '${dashboard.operations.scheduledCommunications} scheduled',
              ),
              _ReportMetricCard(
                icon: Icons.folder_outlined,
                label: 'Documents',
                value: dashboard.operations.totalDocuments.toString(),
                helper: '${dashboard.operations.activeDocuments} active',
              ),
              _ReportMetricCard(
                icon: _features.eventsMeetings
                    ? Icons.event_note_outlined
                    : Icons.lock_outline,
                label: 'Events',
                value: _features.eventsMeetings
                    ? dashboard.operations.totalEvents.toString()
                    : 'Locked',
                helper: _features.eventsMeetings
                    ? '${dashboard.operations.upcomingEvents} upcoming'
                    : 'Events & Meetings Add-on',
              ),
              _ReportMetricCard(
                icon: _features.sweepstakes
                    ? Icons.emoji_events_outlined
                    : Icons.lock_outline,
                label: 'Sweepstakes Seasons',
                value: _features.sweepstakes
                    ? dashboard.operations.sweepstakesSeasons.toString()
                    : 'Locked',
                helper: _features.sweepstakes
                    ? '${dashboard.operations.activeSweepstakesSeasons} active'
                    : 'Sweepstakes Add-on',
              ),
            ],
          ),
          const SizedBox(height: 20),
          const _SectionTitle('Upcoming Membership Expirations'),
          if (dashboard.upcomingExpirations.isEmpty)
            const _InlineEmptyState(
              title: 'No upcoming expirations',
              message: 'No active memberships are expiring in the next 60 days.',
            )
          else
            _SimpleReportTable(
              columns: const ['Member', 'Type', 'Expires'],
              rows: [
                for (final item in dashboard.upcomingExpirations)
                  [
                    item.name,
                    item.typeName ?? '—',
                    _formatDate(item.expiresAt),
                  ],
              ],
            ),
          const SizedBox(height: 20),
          const _SectionTitle('Outstanding Dues'),
          if (!_features.membershipManagement)
            const _LockedReportSection(
              title: 'Membership Management Add-on Required',
              message:
                  'Outstanding dues reports are available when the Membership Management Add-on is enabled.',
            )
          else if (dashboard.outstandingDues.isEmpty)
            const _InlineEmptyState(
              title: 'No outstanding dues',
              message: 'No unpaid or partially paid membership dues were found.',
            )
          else
            _SimpleReportTable(
              columns: const ['Member', 'Status', 'Outstanding'],
              rows: [
                for (final item in dashboard.outstandingDues)
                  [
                    item.name,
                    _titleCase(item.status),
                    _money(item.outstanding),
                  ],
              ],
            ),
          const SizedBox(height: 20),
          const _SectionTitle('Recent Activity'),
          _RecentActivityList(items: dashboard.recentActivity),
        ],
      ),
    );
  }
}

class _ReportMetricCard extends StatelessWidget {
  const _ReportMetricCard({
    required this.icon,
    required this.label,
    required this.value,
    this.helper,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(child: Icon(icon)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  if (helper != null) ...[
                    const SizedBox(height: 4),
                    Text(helper!),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportsAccessSummaryCard extends StatelessWidget {
  const _ReportsAccessSummaryCard({required this.features});

  final _ClubReportFeatureAccess features;

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
                  child: const Icon(Icons.bar_chart_outlined),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Included and Add-on Reports',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Basic membership, application, communication, and document reports are included. Add-on report areas unlock when those tools are enabled.',
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                const _ReportFeatureChip(label: 'Basic Reports', enabled: true),
                _ReportFeatureChip(
                  label: 'Payments & Dues',
                  enabled: features.membershipManagement,
                ),
                _ReportFeatureChip(
                  label: 'Sanctions',
                  enabled: features.sanctionRequests,
                ),
                _ReportFeatureChip(
                  label: 'Events',
                  enabled: features.eventsMeetings,
                ),
                _ReportFeatureChip(
                  label: 'Sweepstakes',
                  enabled: features.sweepstakes,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportFeatureChip extends StatelessWidget {
  const _ReportFeatureChip({required this.label, required this.enabled});

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
      backgroundColor:
          enabled ? scheme.primaryContainer : scheme.surfaceContainerHighest,
      side: BorderSide(
        color: enabled ? scheme.primary : scheme.outlineVariant,
      ),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _LockedReportSection extends StatelessWidget {
  const _LockedReportSection({
    required this.title,
    required this.message,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: scheme.surfaceContainerHighest,
              foregroundColor: scheme.onSurfaceVariant,
              child: const Icon(Icons.lock_outline),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(message),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
class _ClubReportFeatureAccess {
  const _ClubReportFeatureAccess({
    required this.membershipManagement,
    required this.sanctionRequests,
    required this.eventsMeetings,
    required this.sweepstakes,
  });

  const _ClubReportFeatureAccess.base()
      : membershipManagement = false,
        sanctionRequests = false,
        eventsMeetings = false,
        sweepstakes = false;

  final bool membershipManagement;
  final bool sanctionRequests;
  final bool eventsMeetings;
  final bool sweepstakes;

  factory _ClubReportFeatureAccess.fromJson(Map<String, dynamic> json) {
    return _ClubReportFeatureAccess(
      membershipManagement:
          json['membership_management_addon_enabled'] == true,
      sanctionRequests: json['sanction_requests_addon_enabled'] == true,
      eventsMeetings: json['events_meetings_addon_enabled'] == true,
      sweepstakes: json['sweepstakes_addon_enabled'] == true,
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

class _SimpleReportTable extends StatelessWidget {
  const _SimpleReportTable({
    required this.columns,
    required this.rows,
  });

  final List<String> columns;
  final List<List<String>> rows;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: [
            for (final column in columns) DataColumn(label: Text(column)),
          ],
          rows: [
            for (final row in rows)
              DataRow(
                cells: [
                  for (final cell in row) DataCell(Text(cell)),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _RecentActivityList extends StatelessWidget {
  const _RecentActivityList({required this.items});

  final List<_ReportActivity> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const _InlineEmptyState(
        title: 'No recent activity',
        message: 'Recent admin activity will appear here as features are used.',
      );
    }

    return Column(
      children: [
        for (final item in items)
          Card(
            child: ListTile(
              leading: CircleAvatar(child: Icon(_activityIcon(item.type))),
              title: Text(item.title),
              subtitle: Text(item.subtitle ?? _titleCase(item.type)),
              trailing: Text(_formatDate(item.createdAt)),
            ),
          ),
      ],
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
            const Icon(Icons.bar_chart_outlined, size: 52),
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

class _ClubReportsDashboard {
  const _ClubReportsDashboard({
    required this.membership,
    required this.payments,
    required this.operations,
    required this.upcomingExpirations,
    required this.outstandingDues,
    required this.recentActivity,
  });

  final _MembershipReport membership;
  final _PaymentsReport payments;
  final _OperationsReport operations;
  final List<_UpcomingExpiration> upcomingExpirations;
  final List<_OutstandingDue> outstandingDues;
  final List<_ReportActivity> recentActivity;

  factory _ClubReportsDashboard.fromJson(Map<String, dynamic> json) {
    return _ClubReportsDashboard(
      membership: _MembershipReport.fromJson(_map(json['membership'])),
      payments: _PaymentsReport.fromJson(_map(json['payments'])),
      operations: _OperationsReport.fromJson(_map(json['operations'])),
      upcomingExpirations: _list(json['upcoming_expirations'])
          .map(_UpcomingExpiration.fromJson)
          .toList(),
      outstandingDues:
          _list(json['outstanding_dues']).map(_OutstandingDue.fromJson).toList(),
      recentActivity:
          _list(json['recent_activity']).map(_ReportActivity.fromJson).toList(),
    );
  }
}

class _MembershipReport {
  const _MembershipReport({
    required this.totalMembers,
    required this.activeMembers,
    required this.pendingMembers,
    required this.expiredMembers,
    required this.expiringSoon,
  });

  final int totalMembers;
  final int activeMembers;
  final int pendingMembers;
  final int expiredMembers;
  final int expiringSoon;

  factory _MembershipReport.fromJson(Map<String, dynamic> json) {
    return _MembershipReport(
      totalMembers: _intValue(json['total_members']),
      activeMembers: _intValue(json['active_members']),
      pendingMembers: _intValue(json['pending_members']),
      expiredMembers: _intValue(json['expired_members']),
      expiringSoon: _intValue(json['expiring_soon']),
    );
  }
}

class _PaymentsReport {
  const _PaymentsReport({
    required this.totalDue,
    required this.totalPaid,
    required this.outstanding,
    required this.unpaidCount,
  });

  final double totalDue;
  final double totalPaid;
  final double outstanding;
  final int unpaidCount;

  factory _PaymentsReport.fromJson(Map<String, dynamic> json) {
    return _PaymentsReport(
      totalDue: _doubleValue(json['total_due']),
      totalPaid: _doubleValue(json['total_paid']),
      outstanding: _doubleValue(json['outstanding']),
      unpaidCount: _intValue(json['unpaid_count']),
    );
  }
}

class _OperationsReport {
  const _OperationsReport({
    required this.totalApplications,
    required this.pendingApplications,
    required this.totalSanctions,
    required this.pendingSanctions,
    required this.totalCommunications,
    required this.scheduledCommunications,
    required this.totalDocuments,
    required this.activeDocuments,
    required this.totalEvents,
    required this.upcomingEvents,
    required this.sweepstakesSeasons,
    required this.activeSweepstakesSeasons,
  });

  final int totalApplications;
  final int pendingApplications;
  final int totalSanctions;
  final int pendingSanctions;
  final int totalCommunications;
  final int scheduledCommunications;
  final int totalDocuments;
  final int activeDocuments;
  final int totalEvents;
  final int upcomingEvents;
  final int sweepstakesSeasons;
  final int activeSweepstakesSeasons;

  factory _OperationsReport.fromJson(Map<String, dynamic> json) {
    return _OperationsReport(
      totalApplications: _intValue(json['total_applications']),
      pendingApplications: _intValue(json['pending_applications']),
      totalSanctions: _intValue(json['total_sanctions']),
      pendingSanctions: _intValue(json['pending_sanctions']),
      totalCommunications: _intValue(json['total_communications']),
      scheduledCommunications: _intValue(json['scheduled_communications']),
      totalDocuments: _intValue(json['total_documents']),
      activeDocuments: _intValue(json['active_documents']),
      totalEvents: _intValue(json['total_events']),
      upcomingEvents: _intValue(json['upcoming_events']),
      sweepstakesSeasons: _intValue(json['sweepstakes_seasons']),
      activeSweepstakesSeasons: _intValue(json['active_sweepstakes_seasons']),
    );
  }
}

class _UpcomingExpiration {
  const _UpcomingExpiration({
    required this.name,
    required this.expiresAt,
    this.typeName,
  });

  final String name;
  final String? typeName;
  final DateTime expiresAt;

  factory _UpcomingExpiration.fromJson(Map<String, dynamic> json) {
    return _UpcomingExpiration(
      name: _stringValue(json['name'], fallback: 'Unknown Member'),
      typeName: _nullableString(json['type_name']),
      expiresAt: _dateValue(json['expires_at']) ?? DateTime.now(),
    );
  }
}

class _OutstandingDue {
  const _OutstandingDue({
    required this.name,
    required this.status,
    required this.outstanding,
  });

  final String name;
  final String status;
  final double outstanding;

  factory _OutstandingDue.fromJson(Map<String, dynamic> json) {
    return _OutstandingDue(
      name: _stringValue(json['name'], fallback: 'Unknown Member'),
      status: _stringValue(json['status'], fallback: 'unpaid'),
      outstanding: _doubleValue(json['outstanding']),
    );
  }
}

class _ReportActivity {
  const _ReportActivity({
    required this.type,
    required this.title,
    required this.createdAt,
    this.subtitle,
  });

  final String type;
  final String title;
  final String? subtitle;
  final DateTime createdAt;

  factory _ReportActivity.fromJson(Map<String, dynamic> json) {
    return _ReportActivity(
      type: _stringValue(json['type'], fallback: 'activity'),
      title: _stringValue(json['title'], fallback: 'Activity'),
      subtitle: _nullableString(json['subtitle']),
      createdAt: _dateValue(json['created_at']) ?? DateTime.now(),
    );
  }
}

IconData _activityIcon(String type) {
  switch (type) {
    case 'application':
      return Icons.assignment_outlined;
    case 'payment':
      return Icons.payments_outlined;
    case 'sanction':
      return Icons.approval_outlined;
    case 'communication':
      return Icons.campaign_outlined;
    case 'document':
      return Icons.folder_outlined;
    case 'event':
      return Icons.event_note_outlined;
    case 'sweepstakes':
      return Icons.emoji_events_outlined;
    default:
      return Icons.history_outlined;
  }
}

Map<String, dynamic> _map(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return <String, dynamic>{};
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

int _intValue(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

double _doubleValue(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
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

String _money(double value) {
  return '\$${value.toStringAsFixed(2)}';
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