import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';

import '../../../models/clubs/club_member_overview.dart';
import '../../../models/clubs/club_summary.dart';
import 'club_member_destination.dart';

const _muted = AppColors.offWhite;
const _accent = AppColors.gold;

class ClubMemberDashboard extends StatelessWidget {
  const ClubMemberDashboard({
    super.key,
    required this.displayName,
    required this.overview,
    required this.loading,
    required this.onRefresh,
    required this.onOpen,
    this.error,
    this.management,
  });
  final String displayName;
  final ClubMemberOverview? overview;
  final bool loading;
  final String? error;
  final Future<void> Function() onRefresh;
  final void Function(ClubMemberDestination, [ClubSummary?]) onOpen;
  final Widget? management;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.clubCardNavy,
    appBar: AppBar(
      backgroundColor: AppColors.clubCardNavy,
      title: const Text('Member home'),
      actions: [
        IconButton(
          tooltip: 'Refresh member home',
          onPressed: loading ? null : onRefresh,
          icon: const Icon(Icons.refresh),
        ),
        const SizedBox(width: 12),
      ],
    ),
    body: RefreshIndicator(
      onRefresh: onRefresh,
      child: SingleChildScrollView(
        key: const PageStorageKey('member-home-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 48),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1280),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Welcome, $displayName',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: AppColors.clubLightText,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Your memberships, cards, and club updates in one place.',
                  style: TextStyle(color: _muted),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () =>
                          onOpen(ClubMemberDestination.memberships),
                      icon: const Icon(Icons.credit_card_outlined, size: 18),
                      label: const Text('My membership cards'),
                    ),
                    ?management,
                  ],
                ),
                if ((overview?.personalCardCount ?? 0) > 0) ...[
                  const SizedBox(height: 10),
                  Text(
                    '${overview!.personalCardCount} personal membership cards saved in your wallet',
                    style: const TextStyle(fontSize: 12, color: _muted),
                  ),
                ],
                const SizedBox(height: 24),
                if (loading) ...[
                  const LinearProgressIndicator(minHeight: 2, color: _accent),
                  const SizedBox(height: 20),
                ],
                if (error != null) ...[
                  _Message(
                    title: 'Member information unavailable',
                    detail: error!,
                    action: 'Try again',
                    onAction: loading ? null : onRefresh,
                  ),
                  const SizedBox(height: 20),
                ],
                _Heading(
                  title: 'My memberships',
                  action: 'All cards',
                  onAction: () => onOpen(ClubMemberDestination.memberships),
                ),
                const SizedBox(height: 12),
                if (overview == null)
                  _Message(
                    title: loading
                        ? 'Loading your memberships'
                        : 'Memberships not loaded',
                    detail:
                        'Your linked club memberships will appear here when your account information is available.',
                  )
                else if (overview!.unavailableSections.contains('memberships'))
                  _Message(
                    title: 'Memberships could not be loaded',
                    detail:
                        'Try refreshing to check your membership status and renewal dates.',
                    action: 'Retry',
                    onAction: loading ? null : onRefresh,
                  )
                else if (overview!.memberships.isEmpty)
                  _Message(
                    title: overview!.clubs.isEmpty
                        ? 'No linked clubs yet'
                        : 'No personal memberships linked yet',
                    detail:
                        'A club membership will appear here when the club links it to your account. You can also keep personal membership cards from other organizations in your card wallet.',
                    action: 'Open my card wallet',
                    onAction: () => onOpen(ClubMemberDestination.memberships),
                  )
                else
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final twoColumns = constraints.maxWidth >= 740;
                      final width = twoColumns
                          ? (constraints.maxWidth - 16) / 2
                          : constraints.maxWidth;
                      return Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        children: overview!.memberships
                            .map(
                              (member) => SizedBox(
                                width: width,
                                child: _membership(member),
                              ),
                            )
                            .toList(),
                      );
                    },
                  ),
                const SizedBox(height: 24),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final panels = [
                      _updates(
                        title: 'Coming up',
                        destination: ClubMemberDestination.calendar,
                        section: 'events',
                        items: overview?.events ?? [],
                        emptyTitle: 'No upcoming club events',
                        emptyDetail:
                            'Published meetings and events from clubs you belong to will appear here.',
                        icon: Icons.event_outlined,
                      ),
                      _updates(
                        title: 'Club announcements',
                        destination: ClubMemberDestination.announcements,
                        section: 'announcements',
                        items: overview?.announcements ?? [],
                        emptyTitle: 'No announcements yet',
                        emptyDetail:
                            'Updates sent to your account by your clubs will appear here.',
                        icon: Icons.campaign_outlined,
                      ),
                    ];
                    if (constraints.maxWidth < 850) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          panels[0],
                          const SizedBox(height: 20),
                          panels[1],
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: panels[0]),
                        const SizedBox(width: 20),
                        Expanded(child: panels[1]),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _membership(MemberMembershipSummary member) {
    final renew = member.needsRenewal(DateTime.now());
    final statusColor = member.status == 'active'
        ? AppColors.clubLightText
        : AppColors.gold;
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.badge_outlined, color: _accent, size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  member.club.displayName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: member.status == 'active'
                      ? AppColors.clubPrimary
                      : AppColors.gold.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _titleCase(member.status),
                  style: TextStyle(color: statusColor, fontSize: 12),
                ),
              ),
              if (renew)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 5),
                  child: Text(
                    'Renewal available',
                    style: TextStyle(fontSize: 12, color: AppColors.gold),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (member.memberName.isNotEmpty)
            Text(
              member.memberName,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          const SizedBox(height: 5),
          Text(
            [
              if (member.number?.isNotEmpty == true) 'Member #${member.number}',
              if (member.expiresAt != null)
                'Term ends ${_date(member.expiresAt!)}',
            ].join(' · '),
            style: const TextStyle(color: _muted, fontSize: 12),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: () =>
                    onOpen(ClubMemberDestination.membership, member.club),
                child: const Text('View membership'),
              ),
              OutlinedButton.icon(
                onPressed: () =>
                    onOpen(ClubMemberDestination.card, member.club),
                icon: const Icon(Icons.credit_card_outlined, size: 18),
                label: const Text('Card'),
              ),
              if (renew)
                TextButton(
                  onPressed: () =>
                      onOpen(ClubMemberDestination.renew, member.club),
                  child: const Text('Request renewal'),
                ),
              TextButton(
                onPressed: () =>
                    onOpen(ClubMemberDestination.club, member.club),
                child: const Text('Club tools'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _updates({
    required String title,
    required ClubMemberDestination destination,
    required String section,
    required List<MemberClubUpdate> items,
    required String emptyTitle,
    required String emptyDetail,
    required IconData icon,
  }) => _Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Heading(
          title: title,
          action: 'View all',
          onAction: () => onOpen(destination),
        ),
        const SizedBox(height: 12),
        if (overview == null)
          const Text(
            'Club updates have not loaded yet.',
            style: TextStyle(color: _muted),
          )
        else if (overview!.unavailableSections.contains(section))
          _Message(
            title: 'This section could not be loaded',
            detail: 'Refresh to check for club updates.',
            action: 'Retry',
            onAction: loading ? null : onRefresh,
          )
        else if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: _muted, size: 26),
                const SizedBox(height: 12),
                Text(
                  emptyTitle,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text(
                  emptyDetail,
                  style: const TextStyle(fontSize: 12, color: _muted),
                ),
              ],
            ),
          )
        else
          for (final item in items.take(4))
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(icon, size: 22, color: _accent),
              title: Text(
                item.title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                [
                  item.club.displayName,
                  if (item.date != null) _date(item.date!),
                  if (item.detail?.isNotEmpty == true) item.detail!,
                ].join(' · '),
                style: const TextStyle(fontSize: 12, color: _muted),
              ),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap: () {
                if (destination == ClubMemberDestination.announcements &&
                    overview!.memberships.any(
                      (member) => member.club.clubId == item.club.clubId,
                    )) {
                  final memberClub = overview!.memberships
                      .firstWhere(
                        (member) => member.club.clubId == item.club.clubId,
                      )
                      .club;
                  onOpen(ClubMemberDestination.clubAnnouncements, memberClub);
                } else {
                  onOpen(destination);
                }
              },
            ),
      ],
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
      border: Border.all(color: AppColors.clubDivider),
    ),
    child: child,
  );
}

class _Heading extends StatelessWidget {
  const _Heading({required this.title, this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
      if (action != null)
        TextButton(
          onPressed: onAction,
          child: Text(
            action!,
            style: const TextStyle(color: _accent, fontSize: 12),
          ),
        ),
    ],
  );
}

class _Message extends StatelessWidget {
  const _Message({
    required this.title,
    required this.detail,
    this.action,
    this.onAction,
  });
  final String title;
  final String detail;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => _Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
        Text(detail, style: const TextStyle(color: _muted, fontSize: 13)),
        if (action != null) ...[
          const SizedBox(height: 16),
          OutlinedButton(onPressed: onAction, child: Text(action!)),
        ],
      ],
    ),
  );
}

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
String _titleCase(String value) => value
    .split(RegExp(r'[_\s-]+'))
    .where((part) => part.isNotEmpty)
    .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
    .join(' ');
