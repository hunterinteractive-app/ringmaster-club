import 'package:flutter/material.dart';

import '../../../models/clubs/club_member_overview.dart';
import '../../../models/clubs/club_summary.dart';
import '../../../theme/app_theme.dart';
import 'club_member_destination.dart';

class ClubMemberClubsPage extends StatelessWidget {
  const ClubMemberClubsPage({
    super.key,
    required this.overview,
    required this.loading,
    required this.onRefresh,
    required this.onOpen,
    required this.onManage,
    this.error,
  });

  final ClubMemberOverview? overview;
  final bool loading;
  final String? error;
  final Future<void> Function() onRefresh;
  final void Function(ClubMemberDestination, [ClubSummary?]) onOpen;
  final void Function(ClubSummary) onManage;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.clubCardNavy,
    appBar: AppBar(
      backgroundColor: AppColors.clubCardNavy,
      title: const Text('My clubs'),
      actions: [
        IconButton(
          tooltip: 'Refresh clubs',
          onPressed: loading ? null : onRefresh,
          icon: const Icon(Icons.refresh),
        ),
        const SizedBox(width: 12),
      ],
    ),
    body: RefreshIndicator(
      onRefresh: onRefresh,
      child: SingleChildScrollView(
        key: const PageStorageKey('member-clubs-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 48),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1280),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Your clubs, together',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Memberships, club tools, and management for the clubs you help run.',
                  style: TextStyle(color: AppColors.offWhite),
                ),
                const SizedBox(height: 24),
                if (loading) ...[
                  const LinearProgressIndicator(
                    minHeight: 2,
                    color: AppColors.gold,
                  ),
                  const SizedBox(height: 20),
                ],
                if (error != null) ...[
                  Text(error!, style: const TextStyle(color: AppColors.gold)),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton(
                      onPressed: loading ? null : onRefresh,
                      child: const Text('Try again'),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
                if (overview == null)
                  Text(
                    loading ? 'Loading your clubs…' : 'Clubs not loaded',
                    style: const TextStyle(color: AppColors.offWhite),
                  )
                else if (overview!.clubs.isEmpty) ...[
                  const Text(
                    'No linked clubs yet',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Clubs appear here when they link a membership or staff role to your account. Your personal card wallet is always available.',
                    style: TextStyle(color: AppColors.offWhite),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          onOpen(ClubMemberDestination.memberships),
                      icon: const Icon(Icons.credit_card_outlined),
                      label: const Text('Open my card wallet'),
                    ),
                  ),
                ] else
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.maxWidth >= 840
                          ? (constraints.maxWidth - 16) / 2
                          : constraints.maxWidth;
                      return Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        children: [
                          for (final club in overview!.clubs)
                            SizedBox(width: width, child: _club(club)),
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

  Widget _club(ClubSummary club) {
    final memberships = overview!.memberships
        .where((member) => member.club.clubId == club.clubId)
        .toList();
    final membershipUnavailable = overview!.unavailableSections.contains(
      'memberships',
    );
    return Container(
      key: ValueKey('member-club-${club.clubId}'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.clubCardNavyLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.clubDivider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.groups_outlined,
                color: AppColors.gold,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  club.clubName,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (club.canManageClub) ...[
            const SizedBox(height: 12),
            Text(
              'Staff access · ${club.roleName ?? 'Club staff'}',
              style: const TextStyle(color: AppColors.offWhite),
            ),
          ],
          const SizedBox(height: 16),
          if (membershipUnavailable)
            const Text(
              'Membership details could not be loaded. Refresh to check your membership.',
              style: TextStyle(color: AppColors.gold),
            )
          else if (memberships.isEmpty)
            const Text(
              'No personal membership linked to this club.',
              style: TextStyle(color: AppColors.offWhite),
            )
          else
            for (final member in memberships) ...[
              Text(
                member.memberName,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                [
                  member.status.isEmpty
                      ? 'Status unavailable'
                      : '${member.status[0].toUpperCase()}${member.status.substring(1).replaceAll('_', ' ')}',
                  if (member.number?.isNotEmpty ?? false)
                    'Member #${member.number}',
                ].join(' · '),
                style: const TextStyle(color: AppColors.offWhite),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton(
                    onPressed: () =>
                        onOpen(ClubMemberDestination.membership, member.club),
                    child: const Text('View membership'),
                  ),
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
              const SizedBox(height: 12),
            ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (club.canManageClub)
                FilledButton.icon(
                  key: ValueKey('member-club-manage-${club.clubId}'),
                  onPressed: () => onManage(club),
                  icon: const Icon(
                    Icons.admin_panel_settings_outlined,
                    size: 18,
                  ),
                  label: const Text('Club management'),
                ),
              if (!membershipUnavailable && memberships.isEmpty)
                OutlinedButton(
                  onPressed: () => onOpen(ClubMemberDestination.apply, club),
                  child: const Text('Apply for membership'),
                ),
              if (club.canRequestSanction)
                OutlinedButton.icon(
                  onPressed: () => onOpen(ClubMemberDestination.sanction, club),
                  icon: const Icon(Icons.verified_outlined, size: 18),
                  label: const Text('Request sanction'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
