// lib/screens/clubs/club_portal_screen.dart

import 'package:flutter/material.dart';

import '../../models/clubs/club_summary.dart';
import '../../services/clubs/club_session.dart';

typedef ClubPageBuilder =
    Widget Function(BuildContext context, ClubSummary club);

class ClubPortalScreen extends StatefulWidget {
  const ClubPortalScreen({
    super.key,
    required this.clubSession,
    required this.memberPageBuilder,
    required this.adminPageBuilder,
  });

  final ClubSession clubSession;
  final ClubPageBuilder memberPageBuilder;
  final ClubPageBuilder adminPageBuilder;

  @override
  State<ClubPortalScreen> createState() => _ClubPortalScreenState();
}

class _ClubPortalScreenState extends State<ClubPortalScreen> {
  bool _loadedOnce = false;

  @override
  void initState() {
    super.initState();
    widget.clubSession.addListener(_handleSessionChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _loadedOnce) return;
      _loadedOnce = true;
      widget.clubSession.loadClubs();
    });
  }

  @override
  void didUpdateWidget(covariant ClubPortalScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.clubSession != widget.clubSession) {
      oldWidget.clubSession.removeListener(_handleSessionChanged);
      widget.clubSession.addListener(_handleSessionChanged);
      _loadedOnce = false;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _loadedOnce) return;
        _loadedOnce = true;
        widget.clubSession.loadClubs();
      });
    }
  }

  @override
  void dispose() {
    widget.clubSession.removeListener(_handleSessionChanged);
    super.dispose();
  }

  void _handleSessionChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _showClubSelector() async {
    final selectedClub = await showModalBottomSheet<ClubSummary>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 560),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(24, 4, 24, 12),
                  child: Text(
                    'Select a club',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: widget.clubSession.clubs.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final club = widget.clubSession.clubs[index];
                      final isSelected =
                          club.clubId == widget.clubSession.activeClub?.clubId;

                      return ListTile(
                        leading: _ClubAvatar(club: club),
                        title: Text(club.clubName),
                        subtitle: Text(_relationshipLabel(club)),
                        trailing: isSelected
                            ? const Icon(Icons.check_circle)
                            : const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).pop(club),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (selectedClub != null) {
      widget.clubSession.setActiveClub(selectedClub);
    }
  }

  void _openMemberPortal(ClubSummary club) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => widget.memberPageBuilder(context, club),
      ),
    );
  }

  void _openAdminPortal(ClubSummary club) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => widget.adminPageBuilder(context, club),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.clubSession;

    return Scaffold(
      appBar: AppBar(
        title: const Text('RingMaster Club'),
        actions: [
          if (session.hasMultipleClubs)
            IconButton(
              tooltip: 'Switch club',
              onPressed: _showClubSelector,
              icon: const Icon(Icons.swap_horiz),
            ),
          IconButton(
            tooltip: 'Refresh clubs',
            onPressed: session.isLoading ? null : session.refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _buildBody(session),
    );
  }

  Widget _buildBody(ClubSession session) {
    if (session.isLoading && !session.hasClubs) {
      return const Center(child: CircularProgressIndicator());
    }

    final errorMessage = session.errorMessage;
    if (errorMessage != null && !session.hasClubs) {
      return _MessageState(
        icon: Icons.cloud_off_outlined,
        title: 'Unable to load clubs',
        message: errorMessage,
        actionLabel: 'Try again',
        onAction: session.refresh,
      );
    }

    if (!session.hasClubs) {
      return _MessageState(
        icon: Icons.groups_outlined,
        title: 'No clubs yet',
        message:
            'You are not currently connected to a RingMaster Club organization.',
        actionLabel: 'Refresh',
        onAction: session.refresh,
      );
    }

    final club = session.activeClub;
    if (club == null) {
      return _MessageState(
        icon: Icons.warning_amber_rounded,
        title: 'Select a club',
        message: 'Choose a club to continue.',
        actionLabel: 'Select club',
        onAction: _showClubSelector,
      );
    }

    return RefreshIndicator(
      onRefresh: session.refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          _ClubHeaderCard(
            club: club,
            showSwitcher: session.hasMultipleClubs,
            onSwitchClub: _showClubSelector,
          ),
          const SizedBox(height: 20),
          Text(
            'Choose how you want to continue',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          _PortalChoiceCard(
            icon: Icons.badge_outlined,
            title: 'Member Portal',
            description:
                'View memberships, digital cards, sweepstakes, events, and club documents.',
            buttonLabel: 'Open Member Portal',
            onPressed: () => _openMemberPortal(club),
          ),
          if (club.canManageClub) ...[
            const SizedBox(height: 12),
            _PortalChoiceCard(
              icon: Icons.admin_panel_settings_outlined,
              title: 'Manage Club',
              description:
                  'Manage members, dues, sanctions, sweepstakes, documents, events, and communications.',
              buttonLabel: 'Open Club Management',
              onPressed: () => _openAdminPortal(club),
            ),
          ],
          if (session.errorMessage != null) ...[
            const SizedBox(height: 16),
            Material(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_rounded),
                    const SizedBox(width: 10),
                    Expanded(child: Text(session.errorMessage!)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _relationshipLabel(ClubSummary club) {
    if (club.isStaff) {
      return club.roleName?.trim().isNotEmpty == true
          ? club.roleName!
          : 'Club staff';
    }

    final membershipStatus = club.membershipStatus?.trim();
    if (membershipStatus != null && membershipStatus.isNotEmpty) {
      return 'Member • ${_titleCase(membershipStatus)}';
    }

    return 'Member';
  }

  static String _titleCase(String value) {
    return value
        .split(RegExp(r'[_\s-]+'))
        .where((part) => part.isNotEmpty)
        .map(
          (part) =>
              '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
        )
        .join(' ');
  }
}

class _ClubHeaderCard extends StatelessWidget {
  const _ClubHeaderCard({
    required this.club,
    required this.showSwitcher,
    required this.onSwitchClub,
  });

  final ClubSummary club;
  final bool showSwitcher;
  final VoidCallback onSwitchClub;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ClubAvatar(club: club, radius: 32),
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
                  const SizedBox(height: 6),
                  Text(
                    ClubPortalScreenStateHelpers.relationshipLabel(club),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    ClubPortalScreenStateHelpers.titleCase(club.clubType),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (showSwitcher)
              TextButton.icon(
                onPressed: onSwitchClub,
                icon: const Icon(Icons.swap_horiz),
                label: const Text('Switch'),
              ),
          ],
        ),
      ),
    );
  }
}

class _ClubAvatar extends StatelessWidget {
  const _ClubAvatar({required this.club, this.radius = 24});

  final ClubSummary club;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final logoUrl = club.logoUrl?.trim();

    return CircleAvatar(
      radius: radius,
      foregroundImage: logoUrl != null && logoUrl.isNotEmpty
          ? NetworkImage(logoUrl)
          : null,
      child: Text(
        _initials(club.displayName),
        style: TextStyle(fontWeight: FontWeight.w700, fontSize: radius * 0.65),
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
      return words.first
          .substring(0, words.first.length >= 2 ? 2 : 1)
          .toUpperCase();
    }

    return '${words.first[0]}${words.last[0]}'.toUpperCase();
  }
}

class _PortalChoiceCard extends StatelessWidget {
  const _PortalChoiceCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.buttonLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String description;
  final String buttonLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
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
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Text(description),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onPressed,
              icon: const Icon(Icons.arrow_forward),
              label: Text(buttonLabel),
            ),
          ],
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
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 64),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 22),
              FilledButton(onPressed: onAction, child: Text(actionLabel)),
            ],
          ),
        ),
      ),
    );
  }
}

abstract final class ClubPortalScreenStateHelpers {
  static String relationshipLabel(ClubSummary club) {
    if (club.isStaff) {
      return club.roleName?.trim().isNotEmpty == true
          ? club.roleName!
          : 'Club staff';
    }

    final membershipStatus = club.membershipStatus?.trim();
    if (membershipStatus != null && membershipStatus.isNotEmpty) {
      return 'Member • ${titleCase(membershipStatus)}';
    }

    return 'Member';
  }

  static String titleCase(String value) {
    return value
        .split(RegExp(r'[_\s-]+'))
        .where((part) => part.isNotEmpty)
        .map(
          (part) =>
              '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
        )
        .join(' ');
  }
}
