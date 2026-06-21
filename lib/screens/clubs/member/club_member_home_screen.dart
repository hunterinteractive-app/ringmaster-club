// lib/screens/club_member_home_screen.dart

import 'package:flutter/material.dart';

import '../../../models/clubs/club_summary.dart';

class ClubMemberHomeScreen extends StatelessWidget {
  const ClubMemberHomeScreen({
    super.key,
    required this.club,
  });

  final ClubSummary club;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(club.displayName),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _MemberHeaderCard(club: club),
            const SizedBox(height: 20),
            Text(
              'Member Portal',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'View and manage your club information in one place.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 20),
            _MemberPortalTile(
              icon: Icons.badge_outlined,
              title: 'My Membership',
              subtitle:
                  'View your membership status, number, type, and renewal details.',
              onTap: () => _showComingSoon(context, 'My Membership'),
            ),
            _MemberPortalTile(
              icon: Icons.credit_card_outlined,
              title: 'Membership Cards',
              subtitle:
                  'Access digital club cards and store membership cards from other organizations.',
              onTap: () => _showComingSoon(context, 'Membership Cards'),
            ),
            _MemberPortalTile(
              icon: Icons.emoji_events_outlined,
              title: 'Sweepstakes Standings',
              subtitle:
                  'View published standings, seasons, points, and eligible show results.',
              onTap: () => _showComingSoon(context, 'Sweepstakes Standings'),
            ),
            _MemberPortalTile(
              icon: Icons.event_outlined,
              title: 'Meetings & Events',
              subtitle:
                  'See upcoming meetings, shows, deadlines, and club activities.',
              onTap: () => _showComingSoon(context, 'Meetings & Events'),
            ),
            _MemberPortalTile(
              icon: Icons.folder_outlined,
              title: 'Club Documents',
              subtitle:
                  'Find constitution and bylaws, show rules, forms, minutes, and shared files.',
              onTap: () => _showComingSoon(context, 'Club Documents'),
            ),
            _MemberPortalTile(
              icon: Icons.receipt_long_outlined,
              title: 'Payments & Receipts',
              subtitle:
                  'Review dues payments, renewal charges, receipts, and payment history.',
              onTap: () => _showComingSoon(context, 'Payments & Receipts'),
            ),
            _MemberPortalTile(
              icon: Icons.campaign_outlined,
              title: 'Club Announcements',
              subtitle:
                  'Read updates and notices shared by club leadership.',
              onTap: () => _showComingSoon(context, 'Club Announcements'),
            ),
          ],
        ),
      ),
    );
  }

  void _showComingSoon(BuildContext context, String featureName) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$featureName is coming next.'),
      ),
    );
  }
}

class _MemberHeaderCard extends StatelessWidget {
  const _MemberHeaderCard({required this.club});

  final ClubSummary club;

  @override
  Widget build(BuildContext context) {
    final membershipStatus = club.membershipStatus?.trim();
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
                      _StatusChip(
                        icon: club.isStaff
                            ? Icons.admin_panel_settings_outlined
                            : Icons.person_outline,
                        label: club.isStaff
                            ? (roleName != null && roleName.isNotEmpty
                                ? roleName
                                : 'Club Staff')
                            : 'Member',
                      ),
                      if (membershipStatus != null &&
                          membershipStatus.isNotEmpty)
                        _StatusChip(
                          icon: Icons.verified_outlined,
                          label: _titleCase(membershipStatus),
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

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _MemberPortalTile extends StatelessWidget {
  const _MemberPortalTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 10,
        ),
        leading: Icon(icon, size: 30),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(subtitle),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
