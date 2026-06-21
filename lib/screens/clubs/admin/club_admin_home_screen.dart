//lib/screens/clubs/admin/club_admin_home_screen.dart


import 'package:flutter/material.dart';

import '../../../models/clubs/club_summary.dart';
import 'club_communications_screen.dart';
import 'club_documents_screen.dart';
import 'club_events_screen.dart';
import 'club_members_screen.dart';
import 'club_payments_screen.dart';
import 'club_reports_screen.dart';
import 'club_staff_permissions_screen.dart';
import 'club_sweepstakes_screen.dart';
import 'membership_applications_screen.dart';
import 'club_settings_screen.dart';
import 'membership_types_screen.dart';
import 'sanction_requests_screen.dart';

class ClubAdminHomeScreen extends StatelessWidget {
  const ClubAdminHomeScreen({
    super.key,
    required this.club,
  });

  final ClubSummary club;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${club.displayName} Management'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _AdminHeaderCard(club: club),
            const SizedBox(height: 20),
            Text(
              'Club Management',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'Manage your club operations, membership, communications, and reporting.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 20),
            LayoutBuilder(
              builder: (context, constraints) {
                final useTwoColumns = constraints.maxWidth >= 760;
                final cardWidth = useTwoColumns
                    ? (constraints.maxWidth - 12) / 2
                    : constraints.maxWidth;

                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _AdminFeatureCard(
                      width: cardWidth,
                      icon: Icons.people_alt_outlined,
                      title: 'Members',
                      description:
                          'View, add, approve, renew, suspend, and manage club memberships.',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => ClubMembersScreen(club: club),
                          ),
                        );
                      },
                    ),
                    _AdminFeatureCard(
                      width: cardWidth,
                      icon: Icons.workspace_premium_outlined,
                      title: 'Membership Types',
                      description:
                          'Configure membership levels, pricing, terms, and approval requirements.',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => MembershipTypesScreen(club: club),
                          ),
                        );
                      },
                    ),
                    _AdminFeatureCard(
                      width: cardWidth,
                      icon: Icons.assignment_outlined,
                      title: 'Applications & Renewals',
                      description:
                          'Review new membership applications, renewals, payment status, and approval decisions.',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => MembershipApplicationsScreen(club: club),
                          ),
                        );
                      },
                    ),
                    _AdminFeatureCard(
                      width: cardWidth,
                      icon: Icons.payments_outlined,
                      title: 'Payments & Dues',
                      description:
                          'Track dues, recurring payments, offline payments, refunds, and receipts.',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => ClubPaymentsScreen(club: club),
                          ),
                        );
                      },
                    ),
                    _AdminFeatureCard(
                      width: cardWidth,
                      icon: Icons.approval_outlined,
                      title: 'Sanction Requests',
                      description:
                          'Review, approve, return, or deny sanction requests and issue responses.',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => SanctionRequestsScreen(club: club),
                          ),
                        );
                      },
                    ),
                    _AdminFeatureCard(
                      width: cardWidth,
                      icon: Icons.emoji_events_outlined,
                      title: 'Sweepstakes',
                      description:
                          'Manage seasons, reports, point rules, imports, approvals, and standings.',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => ClubSweepstakesScreen(club: club),
                          ),
                        );
                      },
                    ),
                    _AdminFeatureCard(
                      width: cardWidth,
                      icon: Icons.event_note_outlined,
                      title: 'Meetings & Events',
                      description:
                          'Manage club meetings, deadlines, calendars, agendas, and event notices.',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => ClubEventsScreen(club: club),
                          ),
                        );
                      },
                    ),
                    _AdminFeatureCard(
                      width: cardWidth,
                      icon: Icons.folder_outlined,
                      title: 'Documents',
                      description:
                          'Manage bylaws, rules, forms, minutes, newsletters, and shared files.',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => ClubDocumentsScreen(club: club),
                          ),
                        );
                      },
                    ),
                    _AdminFeatureCard(
                      width: cardWidth,
                      icon: Icons.mark_email_read_outlined,
                      title: 'Communications',
                      description:
                          'Send announcements and customize automated club email responses.',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => ClubCommunicationsScreen(club: club),
                          ),
                        );
                      },
                    ),
                    _AdminFeatureCard(
                      width: cardWidth,
                      icon: Icons.analytics_outlined,
                      title: 'Reports',
                      description:
                          'View membership, financial, sanction, and sweepstakes reports.',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => ClubReportsScreen(club: club),
                          ),
                        );
                      },
                    ),
                    _AdminFeatureCard(
                      width: cardWidth,
                      icon: Icons.manage_accounts_outlined,
                      title: 'Staff & Permissions',
                      description:
                          'Assign club roles and control access to administrative features.',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => ClubStaffPermissionsScreen(club: club),
                          ),
                        );
                      },
                    ),
                    _AdminFeatureCard(
                      width: cardWidth,
                      icon: Icons.settings_outlined,
                      title: 'Club Settings',
                      description:
                          'Update club profile, branding, public visibility, and preferences.',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => ClubSettingsScreen(club: club),
                          ),
                        );
                      },
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

}

class _AdminHeaderCard extends StatelessWidget {
  const _AdminHeaderCard({required this.club});

  final ClubSummary club;

  @override
  Widget build(BuildContext context) {
    final roleName = club.roleName?.trim();

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ClubAvatar(club: club),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    club.clubName,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Chip(
                        avatar: const Icon(
                          Icons.admin_panel_settings_outlined,
                          size: 18,
                        ),
                        label: Text(
                          roleName != null && roleName.isNotEmpty
                              ? roleName
                              : 'Club Staff',
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                      Chip(
                        avatar: const Icon(Icons.apartment_outlined, size: 18),
                        label: Text(_titleCase(club.clubType)),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
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
}

class _ClubAvatar extends StatelessWidget {
  const _ClubAvatar({required this.club});

  final ClubSummary club;

  @override
  Widget build(BuildContext context) {
    final logoUrl = club.logoUrl?.trim();

    return CircleAvatar(
      radius: 32,
      foregroundImage:
          logoUrl != null && logoUrl.isNotEmpty ? NetworkImage(logoUrl) : null,
      child: Text(
        _initials(club.displayName),
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  String _initials(String value) {
    final words = value
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();

    if (words.isEmpty) return 'C';

    if (words.length == 1) {
      final word = words.first;
      return word.substring(0, word.length >= 2 ? 2 : 1).toUpperCase();
    }

    return '${words.first[0]}${words.last[0]}'.toUpperCase();
  }
}

class _AdminFeatureCard extends StatelessWidget {
  const _AdminFeatureCard({
    required this.width,
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final double width;
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 30),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text(description),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }
}