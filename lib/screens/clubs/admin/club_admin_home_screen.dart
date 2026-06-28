//lib/screens/clubs/admin/club_admin_home_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
import 'club_billing_screen.dart';
import 'membership_types_screen.dart';
import 'sanction_requests_screen.dart';
import 'sanction_types_screen.dart';

class ClubAdminHomeScreen extends StatefulWidget {
  const ClubAdminHomeScreen({
    super.key,
    required this.club,
  });

  final ClubSummary club;

  @override
  State<ClubAdminHomeScreen> createState() => _ClubAdminHomeScreenState();
}

class _ClubAdminHomeScreenState extends State<ClubAdminHomeScreen> {
  final _supabase = Supabase.instance.client;

  bool _isLoadingFeatures = true;
  String? _featureError;
  _ClubFeatureAccess _features = const _ClubFeatureAccess.base();

  ClubSummary get club => widget.club;

  @override
  void initState() {
    super.initState();
    _loadFeatureAccess();
  }

  Future<void> _loadFeatureAccess() async {
    setState(() {
      _isLoadingFeatures = true;
      _featureError = null;
    });

    try {
      final row = await _supabase
          .from('clubs')
          .select(
            'membership_management_addon_enabled,'
            'sanction_requests_addon_enabled,'
            'events_meetings_addon_enabled,'
            'email_addon_enabled,'
            'sweepstakes_addon_enabled',
          )
          .eq('id', club.clubId)
          .single();

      if (!mounted) return;
      setState(() {
        _features = _ClubFeatureAccess.fromJson(
          Map<String, dynamic>.from(row),
        );
        _isLoadingFeatures = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _features = const _ClubFeatureAccess.base();
        _isLoadingFeatures = false;
        _featureError = 'Unable to load add-on settings: $error';
      });
    }
  }

  void _showLockedFeature({
    required String featureName,
    required String addOnName,
  }) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$featureName Requires an Add-on'),
        content: Text(
          '$featureName is available with the $addOnName. The club owner can enable this when the club is ready to use it.',
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

  VoidCallback _lockedTap(String featureName, String addOnName) {
    return () => _showLockedFeature(
          featureName: featureName,
          addOnName: addOnName,
        );
  }

  @override
  Widget build(BuildContext context) {
    Widget section(
      String title,
      List<Widget> Function(double cardWidth) cards,
    ) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final useTwoColumns = constraints.maxWidth >= 760;
              final cardWidth = useTwoColumns
                  ? (constraints.maxWidth - 12) / 2
                  : constraints.maxWidth;

              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: cards(cardWidth),
              );
            },
          ),
        ],
      );
    }


    return Scaffold(
      appBar: AppBar(
        title: Text('${club.displayName} Management'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _AdminHeaderCard(club: club),
            const SizedBox(height: 12),
            _FeatureAccessSummaryCard(
              isLoading: _isLoadingFeatures,
              errorMessage: _featureError,
              features: _features,
              onRefresh: _loadFeatureAccess,
            ),
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
            section(
              'Membership & Dues',
              (cardWidth) => [
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
                  addOnName: 'Membership Management Add-on',
                  isEnabled: _features.membershipManagement,
                  onLockedTap: _lockedTap(
                    'Payments & Dues',
                    'Membership Management Add-on',
                  ),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ClubPaymentsScreen(club: club),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 24),
            section(
              'Club Operations',
              (cardWidth) => [
                _AdminFeatureCard(
                  width: cardWidth,
                  icon: Icons.approval_outlined,
                  title: 'Sanction Requests',
                  description:
                      'Review, approve, return, or deny sanction requests and issue responses.',
                  addOnName: 'Sanction Requests Add-on',
                  isEnabled: _features.sanctionRequests,
                  onLockedTap: _lockedTap(
                    'Sanction Requests',
                    'Sanction Requests Add-on',
                  ),
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
                  icon: Icons.fact_check_outlined,
                  title: 'Sanction Types',
                  description:
                      'Configure sanction options, bundles, pricing, and availability for this club.',
                  addOnName: 'Sanction Requests Add-on',
                  isEnabled: _features.sanctionRequests,
                  onLockedTap: _lockedTap(
                    'Sanction Types',
                    'Sanction Requests Add-on',
                  ),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => SanctionTypesScreen(club: club),
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
                  addOnName: 'Events & Meetings Add-on',
                  isEnabled: _features.eventsMeetings,
                  onLockedTap: _lockedTap(
                    'Meetings & Events',
                    'Events & Meetings Add-on',
                  ),
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
                  description: _features.email
                      ? 'Create notices, send email announcements, and track delivery.'
                      : 'Create in-app notices and communication records. Email sending is an add-on.',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ClubCommunicationsScreen(club: club),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 24),
            section(
              'Reporting & Awards',
              (cardWidth) => [
                _AdminFeatureCard(
                  width: cardWidth,
                  icon: Icons.emoji_events_outlined,
                  title: 'Sweepstakes',
                  description:
                      'Manage seasons, reports, point rules, imports, approvals, and standings.',
                  addOnName: 'Sweepstakes Add-on',
                  isEnabled: _features.sweepstakes,
                  onLockedTap: _lockedTap(
                    'Sweepstakes',
                    'Sweepstakes Add-on',
                  ),
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
              ],
            ),
            const SizedBox(height: 24),
            section(
              'Administration',
              (cardWidth) => [
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
                  icon: Icons.receipt_long_outlined,
                  title: 'Billing & Add-ons',
                  description:
                      'Manage RingMaster Club plan, add-ons, member payment settings, Stripe setup, and Show token discounts.',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ClubBillingScreen(club: club),
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

class _FeatureAccessSummaryCard extends StatelessWidget {
  const _FeatureAccessSummaryCard({
    required this.isLoading,
    required this.features,
    required this.onRefresh,
    this.errorMessage,
  });

  final bool isLoading;
  final String? errorMessage;
  final _ClubFeatureAccess features;
  final VoidCallback onRefresh;

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
                  child: isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.extension_outlined),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Enabled Club Tools',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        errorMessage == null
                            ? 'Base tools are always available. Add-on tiles stay visible and show what can be enabled later.'
                            : errorMessage!,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh add-ons',
                  onPressed: isLoading ? null : onRefresh,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                const _FeatureChip(label: 'Base Club Tools', enabled: true),
                _FeatureChip(
                  label: 'Membership Management',
                  enabled: features.membershipManagement,
                ),
                _FeatureChip(
                  label: 'Sanction Requests',
                  enabled: features.sanctionRequests,
                ),
                _FeatureChip(
                  label: 'Events & Meetings',
                  enabled: features.eventsMeetings,
                ),
                _FeatureChip(
                  label: 'Email',
                  enabled: features.email,
                ),
                _FeatureChip(
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

class _FeatureChip extends StatelessWidget {
  const _FeatureChip({required this.label, required this.enabled});

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

class _ClubFeatureAccess {
  const _ClubFeatureAccess({
    required this.membershipManagement,
    required this.sanctionRequests,
    required this.eventsMeetings,
    required this.email,
    required this.sweepstakes,
  });

  const _ClubFeatureAccess.base()
      : membershipManagement = false,
        sanctionRequests = false,
        eventsMeetings = false,
        email = false,
        sweepstakes = false;

  final bool membershipManagement;
  final bool sanctionRequests;
  final bool eventsMeetings;
  final bool email;
  final bool sweepstakes;

  factory _ClubFeatureAccess.fromJson(Map<String, dynamic> json) {
    return _ClubFeatureAccess(
      membershipManagement:
          json['membership_management_addon_enabled'] == true,
      sanctionRequests: json['sanction_requests_addon_enabled'] == true,
      eventsMeetings: json['events_meetings_addon_enabled'] == true,
      email: json['email_addon_enabled'] == true,
      sweepstakes: json['sweepstakes_addon_enabled'] == true,
    );
  }
}

class _AdminFeatureCard extends StatelessWidget {
  const _AdminFeatureCard({
    required this.width,
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
    this.addOnName,
    this.isEnabled = true,
    this.onLockedTap,
  });

  final double width;
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;
  final String? addOnName;
  final bool isEnabled;
  final VoidCallback? onLockedTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: isEnabled ? onTap : onLockedTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      icon,
                      size: 30,
                      color: isEnabled
                          ? null
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    if (!isEnabled)
                      Positioned(
                        right: -7,
                        bottom: -7,
                        child: Icon(
                          Icons.lock_outline,
                          size: 16,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                  ],
                ),
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
                      if (!isEnabled && addOnName != null) ...[
                        const SizedBox(height: 4),
                        Chip(
                          avatar: const Icon(Icons.lock_outline, size: 16),
                          label: Text(addOnName!),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                      const SizedBox(height: 6),
                      Text(description),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(isEnabled ? Icons.chevron_right : Icons.lock_outline),
              ],
            ),
          ),
        ),
      ),
    );
  }
}