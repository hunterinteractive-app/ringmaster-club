import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';

import '../../../models/clubs/club_management_overview.dart';
import '../../../models/clubs/club_summary.dart';
import 'club_management_destination.dart';

const _muted = AppColors.offWhite;
const _line = AppColors.clubDivider;
const _accent = AppColors.gold;

class ClubManagementDashboard extends StatelessWidget {
  const ClubManagementDashboard({
    super.key,
    required this.club,
    required this.overview,
    required this.loading,
    required this.onRefresh,
    required this.onOpen,
    required this.onRenewals,
    required this.onImport,
    this.error,
  });

  final ClubSummary club;
  final ClubManagementOverview? overview;
  final bool loading;
  final String? error;
  final Future<void> Function() onRefresh;
  final ValueChanged<ClubManagementDestination> onOpen;
  final VoidCallback onRenewals;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final summary = overview?.summary;
    final features = overview?.features;
    return Scaffold(
      backgroundColor: AppColors.clubCardNavy,
      appBar: AppBar(
        backgroundColor: AppColors.clubCardNavy,
        title: Text(club.displayName, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Refresh overview',
            onPressed: loading ? null : onRefresh,
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: onRefresh,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final padding = constraints.maxWidth < 600 ? 16.0 : 28.0;
            return SingleChildScrollView(
              key: const PageStorageKey('club-overview-scroll'),
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(padding, 16, padding, 48),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1280),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _today(),
                        style: const TextStyle(color: _muted, fontSize: 12),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Club overview',
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w700,
                          color: AppColors.clubLightText,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Memberships, decisions, and the next things to do.',
                        style: TextStyle(color: _muted),
                      ),
                      const SizedBox(height: 24),
                      if (loading) ...[
                        const LinearProgressIndicator(
                          minHeight: 2,
                          color: _accent,
                        ),
                        const SizedBox(height: 20),
                      ],
                      if (error != null ||
                          (!loading &&
                              overview != null &&
                              summary == null)) ...[
                        _Notice(
                          message:
                              error ??
                              'Overview figures are unavailable. Open a club tool to continue, or try refreshing.',
                          onRetry: loading ? null : onRefresh,
                        ),
                        const SizedBox(height: 20),
                      ],
                      _Metrics(
                        children: [
                          _Metric(
                            label: 'Active memberships',
                            value: _count(summary?.activeMembers),
                            detail: summary == null
                                ? 'Awaiting club records'
                                : '${summary.totalMembers} total memberships',
                            icon: Icons.people_outline,
                            onTap: () =>
                                onOpen(ClubManagementDestination.members),
                          ),
                          _Metric(
                            label: 'Applications to review',
                            value: _count(summary?.pendingApplications),
                            detail: 'Pending or needing information',
                            icon: Icons.inbox_outlined,
                            highlight: (summary?.pendingApplications ?? 0) > 0,
                            onTap: () =>
                                onOpen(ClubManagementDestination.applications),
                          ),
                          _Metric(
                            label: 'Renewals coming up',
                            value: _count(summary?.expiringMembers),
                            detail: 'Expiring in the next 60 days',
                            icon: Icons.autorenew,
                            onTap: onRenewals,
                          ),
                          if (features?.membership == true)
                            _Metric(
                              label: 'Recorded dues outstanding',
                              value: summary == null
                                  ? '—'
                                  : _money(summary.outstandingDues),
                              detail: summary == null
                                  ? 'Awaiting payment records'
                                  : '${summary.unpaidCount} unpaid or partial records',
                              icon: Icons.payments_outlined,
                              onTap: () =>
                                  onOpen(ClubManagementDestination.payments),
                            )
                          else if (features?.events == true)
                            _Metric(
                              label: 'Upcoming events',
                              value: _count(summary?.upcomingEvents),
                              detail: 'Published club meetings & events',
                              icon: Icons.event_outlined,
                              onTap: () =>
                                  onOpen(ClubManagementDestination.events),
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      if (summary?.totalMembers == 0) ...[
                        _Panel(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Bring your members into view',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Import your existing roster to start tracking memberships and upcoming renewals.',
                                style: TextStyle(color: _muted),
                              ),
                              const SizedBox(height: 16),
                              Wrap(
                                spacing: 12,
                                runSpacing: 10,
                                children: [
                                  FilledButton.icon(
                                    onPressed: onImport,
                                    icon: const Icon(
                                      Icons.upload_file_outlined,
                                    ),
                                    label: const Text('Import roster'),
                                  ),
                                  TextButton(
                                    onPressed: () => onOpen(
                                      ClubManagementDestination.membershipTypes,
                                    ),
                                    child: const Text(
                                      'Set up membership types',
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                      LayoutBuilder(
                        builder: (context, panelConstraints) {
                          final attention = _attention(summary, features);
                          final renewals = _renewals(summary);
                          if (panelConstraints.maxWidth < 850) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                attention,
                                const SizedBox(height: 20),
                                renewals,
                              ],
                            );
                          }
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(flex: 3, child: attention),
                              const SizedBox(width: 20),
                              Expanded(flex: 2, child: renewals),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 20),
                      _Panel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _PanelHeading(title: 'Quick access'),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                _QuickAction(
                                  icon: Icons.people_outline,
                                  label: 'Manage members',
                                  onTap: () =>
                                      onOpen(ClubManagementDestination.members),
                                ),
                                _QuickAction(
                                  icon: Icons.upload_file_outlined,
                                  label: 'Import roster',
                                  onTap: onImport,
                                ),
                                _QuickAction(
                                  icon: Icons.campaign_outlined,
                                  label: 'Communications',
                                  onTap: () => onOpen(
                                    ClubManagementDestination.communications,
                                  ),
                                ),
                                _QuickAction(
                                  icon: Icons.folder_outlined,
                                  label: 'Club documents',
                                  onTap: () => onOpen(
                                    ClubManagementDestination.documents,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      _activity(summary, features),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _attention(
    ClubManagementSummary? summary,
    ClubManagementFeatures? features,
  ) {
    final tasks = <Widget>[];
    void task(
      int? count,
      String title,
      String detail,
      IconData icon,
      VoidCallback open,
    ) {
      if (count != null && count > 0) {
        tasks.add(
          _ActionRow(
            title: title,
            detail: detail,
            icon: icon,
            count: count,
            onTap: open,
          ),
        );
      }
    }

    task(
      summary?.pendingApplications,
      'Review membership applications',
      'Pending applications and requests for information',
      Icons.inbox_outlined,
      () => onOpen(ClubManagementDestination.applications),
    );
    task(
      summary?.expiringMembers,
      'Review upcoming renewals',
      'Memberships ending within 60 days',
      Icons.autorenew,
      onRenewals,
    );
    if (features?.membership == true && (summary?.outstandingDues ?? 0) > 0) {
      tasks.add(
        _ActionRow(
          title: 'Follow up on recorded dues',
          detail: '${_money(summary!.outstandingDues)} outstanding',
          icon: Icons.payments_outlined,
          onTap: () => onOpen(ClubManagementDestination.payments),
        ),
      );
    }
    if (features?.sanctions == true) {
      task(
        summary?.pendingSanctions,
        'Review sanction requests',
        'Pending and returned requests',
        Icons.verified_outlined,
        () => onOpen(ClubManagementDestination.sanctions),
      );
    }
    if (features?.sweepstakes == true) {
      task(
        overview?.reportsNeedingReview,
        'Review show reports',
        'Reports waiting for staff review',
        Icons.description_outlined,
        () => onOpen(ClubManagementDestination.sweepstakes),
      );
      task(
        overview?.overdueReports,
        'Follow up on overdue reports',
        'Expected reports past their due date',
        Icons.event_busy_outlined,
        () => onOpen(ClubManagementDestination.sweepstakes),
      );
    }
    final missingReports =
        features?.sweepstakes == true &&
        (overview?.reportsNeedingReview == null ||
            overview?.overdueReports == null);
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PanelHeading(
            title: 'Needs attention',
            action: 'View reports',
            onAction: () => onOpen(ClubManagementDestination.reports),
          ),
          const SizedBox(height: 12),
          if (summary == null)
            _QuietState(
              icon: Icons.insights_outlined,
              title: loading
                  ? 'Loading your club overview'
                  : 'Overview unavailable',
              detail: loading
                  ? 'Checking memberships and pending work.'
                  : 'Refresh to check pending work. Your club tools remain accessible.',
            )
          else if (tasks.isEmpty && !missingReports)
            const _QuietState(
              icon: Icons.check_circle_outline,
              title: 'No pending items in this overview',
              detail:
                  'Applications, upcoming renewals, and enabled work queues will appear here when they need attention.',
            )
          else
            ...tasks,
          if (missingReports) ...[
            const SizedBox(height: 12),
            _Notice(
              message: 'Show report counts are unavailable.',
              onRetry: loading ? null : onRefresh,
            ),
          ],
        ],
      ),
    );
  }

  Widget _renewals(ClubManagementSummary? summary) => _Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PanelHeading(
          title: 'Upcoming renewals',
          action: 'View all',
          onAction: onRenewals,
        ),
        const SizedBox(height: 4),
        const Text(
          'Next 60 days',
          style: TextStyle(fontSize: 12, color: _muted),
        ),
        const SizedBox(height: 12),
        if (summary == null)
          const _QuietState(
            icon: Icons.event_outlined,
            title: 'Renewals not loaded',
            detail: 'Dates will appear when the overview is available.',
          )
        else if (summary.renewals.isEmpty)
          const _QuietState(
            icon: Icons.event_available_outlined,
            title: 'No renewals coming up',
            detail: 'Active memberships expiring soon will appear here.',
          )
        else
          for (final renewal in summary.renewals.take(5))
            _ActionRow(
              title: renewal.name,
              detail: [
                renewal.type,
                if (renewal.expiresAt != null)
                  'Expires ${_date(renewal.expiresAt!)}',
              ].whereType<String>().join(' · '),
              icon: Icons.person_outline,
              onTap: onRenewals,
            ),
      ],
    ),
  );

  Widget _activity(
    ClubManagementSummary? summary,
    ClubManagementFeatures? features,
  ) {
    // Match enabled tools; activity from a disabled module should not send a
    // person from a useful dashboard into a locked screen.
    final activity =
        summary?.activity
            .where((item) {
              final destination = ClubManagementDestination.forActivity(
                item.type,
              );
              return destination == null ||
                  (features != null && destination.available(features));
            })
            .take(6)
            .toList() ??
        [];
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _PanelHeading(title: 'Recent activity'),
          const SizedBox(height: 12),
          if (summary == null)
            const _QuietState(
              icon: Icons.history,
              title: 'Activity not loaded',
              detail: 'Refresh to load recent changes.',
            )
          else if (activity.isEmpty)
            const _QuietState(
              icon: Icons.history,
              title: 'No recent activity',
              detail:
                  'Membership applications, payments, and club updates will appear here.',
            )
          else
            for (final item in activity)
              Builder(
                builder: (context) {
                  final destination = ClubManagementDestination.forActivity(
                    item.type,
                  );
                  return _ActionRow(
                    title: item.title,
                    detail: [
                      destination?.label ?? 'Club activity',
                      if (item.status?.isNotEmpty == true)
                        _titleCase(item.status!),
                      if (item.createdAt != null)
                        _date(item.createdAt!.toLocal()),
                    ].join(' · '),
                    icon: destination?.icon ?? Icons.history,
                    onTap: destination == null
                        ? null
                        : () => onOpen(destination),
                  );
                },
              ),
        ],
      ),
    );
  }
}

class _Metrics extends StatelessWidget {
  const _Metrics({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final largeText = MediaQuery.textScalerOf(context).scale(14) > 18;
      final columns = constraints.maxWidth >= 900
          ? children.length
          : constraints.maxWidth >= 320 &&
                !(largeText && constraints.maxWidth < 600)
          ? 2
          : 1;
      final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: children
            .map((child) => SizedBox(width: width, child: child))
            .toList(),
      );
    },
  );
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.detail,
    required this.icon,
    required this.onTap,
    this.highlight = false,
  });
  final String label;
  final String value;
  final String detail;
  final IconData icon;
  final VoidCallback onTap;
  final bool highlight;
  @override
  Widget build(BuildContext context) => Material(
    color: highlight ? AppColors.clubPrimary : AppColors.clubCardNavyLight,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(color: highlight ? AppColors.clubLight : _line),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 23, color: _accent),
            const SizedBox(height: 18),
            Text(
              value,
              style: const TextStyle(
                fontSize: 30,
                color: AppColors.clubLightText,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              label,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 7),
            Text(detail, style: const TextStyle(fontSize: 11, color: _muted)),
          ],
        ),
      ),
    ),
  );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: AppColors.clubCardNavyLight,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _line),
    ),
    child: child,
  );
}

class _PanelHeading extends StatelessWidget {
  const _PanelHeading({required this.title, this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppColors.clubLightText,
          ),
        ),
      ),
      if (action != null)
        TextButton(
          onPressed: onAction,
          child: Text(
            action!,
            style: const TextStyle(fontSize: 12, color: _accent),
          ),
        ),
    ],
  );
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.title,
    required this.detail,
    required this.icon,
    this.count,
    this.onTap,
  });
  final String title;
  final String detail;
  final IconData icon;
  final int? count;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 2),
        child: Row(
          children: [
            Icon(icon, color: _accent, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    detail,
                    style: const TextStyle(fontSize: 12, color: _muted),
                  ),
                ],
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: 8),
              Text(
                '$count',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: _accent,
                ),
              ),
            ],
            if (onTap != null) ...[
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, size: 18, color: _muted),
            ],
          ],
        ),
      ),
    ),
  );
}

class _QuietState extends StatelessWidget {
  const _QuietState({
    required this.icon,
    required this.title,
    required this.detail,
  });
  final IconData icon;
  final String title;
  final String detail;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 26, color: _muted),
        const SizedBox(height: 12),
        Text(
          title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Text(detail, style: const TextStyle(fontSize: 12, color: _muted)),
      ],
    ),
  );
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onTap,
    style: OutlinedButton.styleFrom(
      side: const BorderSide(color: _line),
      foregroundColor: AppColors.clubLightText,
    ),
    icon: Icon(icon, size: 18),
    label: Text(label, style: const TextStyle(fontSize: 12)),
  );
}

class _Notice extends StatelessWidget {
  const _Notice({required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
    decoration: BoxDecoration(
      color: AppColors.gold.withValues(alpha: .10),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      children: [
        const Icon(Icons.info_outline, size: 20, color: AppColors.gold),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(fontSize: 12, color: AppColors.gold),
          ),
        ),
        TextButton(
          onPressed: onRetry,
          child: const Text('Retry', style: TextStyle(color: AppColors.gold)),
        ),
      ],
    ),
  );
}

String _count(int? value) => value?.toString() ?? '—';
String _money(double value) => '\$${value.toStringAsFixed(2)}';
const _months = [
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
String _date(DateTime value) =>
    '${_months[value.month - 1]} ${value.day}, ${value.year}';
String _today() => _date(DateTime.now());
String _titleCase(String value) => value
    .split(RegExp(r'[_\s-]+'))
    .where((part) => part.isNotEmpty)
    .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
    .join(' ');
