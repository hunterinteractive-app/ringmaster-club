import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/clubs/club_summary.dart';
import 'club_membership_apply_screen.dart';

/// The member-facing view of a single club membership.
///
/// This deliberately does not edit membership records. Club staff remain the
/// source of truth for approval, membership type, term dates, and dues.
class ClubMemberMembershipScreen extends StatefulWidget {
  const ClubMemberMembershipScreen({super.key, required this.club});

  final ClubSummary club;

  @override
  State<ClubMemberMembershipScreen> createState() =>
      _ClubMemberMembershipScreenState();
}

class _ClubMemberMembershipScreenState
    extends State<ClubMemberMembershipScreen> {
  final _supabase = Supabase.instance.client;

  bool _isLoading = true;
  String? _errorMessage;
  _MembershipDetails? _membership;
  String? _membershipTypeName;
  _LinkedExhibitor? _linkedExhibitor;

  @override
  void initState() {
    super.initState();
    _loadMembership();
  }

  Future<void> _loadMembership() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        throw StateError('Please sign in again to view your membership.');
      }

      const membershipFields =
          'id,membership_type_id,membership_number,first_name,last_name,'
          'showing_name,email,status,joined_at,current_term_start,'
          'current_term_end,auto_renew,exhibitor_id';

      // Imported club rosters often predate RingMaster accounts. Prefer the
      // membership relationship supplied by the authorized club summary, then
      // the direct account link, and finally the verified sign-in email.
      Map<String, dynamic>? membershipRow;
      final summaryMembershipId = widget.club.membershipId?.trim();
      if (summaryMembershipId != null && summaryMembershipId.isNotEmpty) {
        membershipRow = await _supabase
            .from('club_memberships')
            .select(membershipFields)
            .eq('club_id', widget.club.clubId)
            .eq('id', summaryMembershipId)
            .maybeSingle();
      }
      membershipRow ??= await _supabase
          .from('club_memberships')
          .select(membershipFields)
          .eq('club_id', widget.club.clubId)
          .eq('user_id', user.id)
          .maybeSingle();
      final email = user.email?.trim();
      if (membershipRow == null && email != null && email.isNotEmpty) {
        membershipRow = await _supabase
            .from('club_memberships')
            .select(membershipFields)
            .eq('club_id', widget.club.clubId)
            .eq('email', email)
            .limit(1)
            .maybeSingle();
      }

      if (membershipRow == null) {
        if (!mounted) return;
        setState(() {
          _membership = null;
          _membershipTypeName = null;
          _linkedExhibitor = null;
          _isLoading = false;
        });
        return;
      }

      final membership = _MembershipDetails.fromJson(
        Map<String, dynamic>.from(membershipRow),
      );

      String? typeName;
      if (membership.membershipTypeId != null) {
        final typeRow = await _supabase
            .from('club_membership_types')
            .select('name')
            .eq('id', membership.membershipTypeId!)
            .maybeSingle();
        typeName = _textOrNull(typeRow?['name']);
      }

      _LinkedExhibitor? exhibitor;
      if (membership.exhibitorId != null) {
        final exhibitorRow = await _supabase
            .from('exhibitors')
            .select(
              'id,display_name,showing_name,first_name,last_name,arba_number',
            )
            .eq('id', membership.exhibitorId!)
            .maybeSingle();
        if (exhibitorRow != null) {
          exhibitor = _LinkedExhibitor.fromJson(
            Map<String, dynamic>.from(exhibitorRow),
          );
        }
      }

      if (!mounted) return;
      setState(() {
        _membership = membership;
        _membershipTypeName = typeName;
        _linkedExhibitor = exhibitor;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Unable to load your membership: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Membership'),
        actions: [
          IconButton(
            tooltip: 'Refresh membership',
            onPressed: _isLoading ? null : _loadMembership,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(child: _buildBody(context)),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return _MessageState(
        icon: Icons.error_outline,
        title: 'We could not load your membership',
        message: _errorMessage!,
        actionLabel: 'Try again',
        onAction: _loadMembership,
      );
    }

    if (_membership == null) {
      return _MessageState(
        icon: Icons.badge_outlined,
        title: 'No membership record found',
        message:
            'There is not yet a membership linked to this RingMaster Club account for ${widget.club.displayName}.',
        actionLabel: 'Refresh',
        onAction: _loadMembership,
      );
    }

    final membership = _membership!;
    final status =
        membership.status ?? widget.club.membershipStatus ?? 'unknown';
    final termEnd = membership.currentTermEnd;
    final isExpired = termEnd != null && termEnd.isBefore(_today());

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          widget.club.clubName,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          'Your membership details are managed by the club.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.verified_user_outlined, size: 30),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _membershipTypeName ?? 'Club Membership',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    _StatusBadge(status: status, expired: isExpired),
                  ],
                ),
                const SizedBox(height: 20),
                _DetailRow(
                  label: 'Membership number',
                  value: membership.membershipNumber ?? 'Not assigned',
                ),
                _DetailRow(label: 'Member name', value: membership.memberName),
                _DetailRow(
                  label: 'Joined',
                  value: _formatDate(membership.joinedAt) ?? 'Not available',
                ),
                _DetailRow(
                  label: 'Current term',
                  value: _termLabel(
                    membership.currentTermStart,
                    membership.currentTermEnd,
                  ),
                ),
                _DetailRow(
                  label: 'Auto-renew',
                  value: membership.autoRenew == true
                      ? 'Enabled'
                      : 'Not enabled',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            contentPadding: const EdgeInsets.all(18),
            leading: const Icon(Icons.pets_outlined, size: 30),
            title: const Text(
              'Linked exhibitor',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_linkedExhibitor?.label ?? 'No exhibitor linked yet'),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Renew membership',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  termEnd == null
                      ? 'Send a renewal request to ${widget.club.displayName}. Club staff will review it before any membership dates change.'
                      : 'Your current term ends ${_formatDate(termEnd)}. Send a renewal request to ${widget.club.displayName}; staff will review it before any membership dates change.',
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: () async {
                    final submitted = await Navigator.of(context).push<bool>(
                      MaterialPageRoute<bool>(
                        builder: (_) => ClubMembershipApplyScreen(
                          club: widget.club,
                          isRenewal: true,
                        ),
                      ),
                    );
                    if (submitted == true) await _loadMembership();
                  },
                  icon: const Icon(Icons.autorenew_outlined),
                  label: const Text('Request renewal'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Need a change?',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          'Contact ${widget.club.displayName} to update your membership type, term, or membership number.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}

class _MembershipDetails {
  const _MembershipDetails({
    required this.membershipTypeId,
    required this.membershipNumber,
    required this.firstName,
    required this.lastName,
    required this.showingName,
    required this.status,
    required this.joinedAt,
    required this.currentTermStart,
    required this.currentTermEnd,
    required this.autoRenew,
    required this.exhibitorId,
  });

  final String? membershipTypeId;
  final String? membershipNumber;
  final String? firstName;
  final String? lastName;
  final String? showingName;
  final String? status;
  final DateTime? joinedAt;
  final DateTime? currentTermStart;
  final DateTime? currentTermEnd;
  final bool? autoRenew;
  final String? exhibitorId;

  String get memberName {
    final showing = showingName?.trim();
    if (showing != null && showing.isNotEmpty) return showing;
    return [firstName, lastName]
            .whereType<String>()
            .where((part) => part.trim().isNotEmpty)
            .join(' ')
            .trim()
            .isEmpty
        ? 'Not available'
        : [firstName, lastName]
              .whereType<String>()
              .where((part) => part.trim().isNotEmpty)
              .join(' ')
              .trim();
  }

  factory _MembershipDetails.fromJson(Map<String, dynamic> json) {
    return _MembershipDetails(
      membershipTypeId: _textOrNull(json['membership_type_id']),
      membershipNumber: _textOrNull(json['membership_number']),
      firstName: _textOrNull(json['first_name']),
      lastName: _textOrNull(json['last_name']),
      showingName: _textOrNull(json['showing_name']),
      status: _textOrNull(json['status']),
      joinedAt: _dateOrNull(json['joined_at']),
      currentTermStart: _dateOrNull(json['current_term_start']),
      currentTermEnd: _dateOrNull(json['current_term_end']),
      autoRenew: json['auto_renew'] as bool?,
      exhibitorId: _textOrNull(json['exhibitor_id']),
    );
  }
}

class _LinkedExhibitor {
  const _LinkedExhibitor({required this.name, required this.arbaNumber});

  final String name;
  final String? arbaNumber;

  String get label {
    final arba = arbaNumber?.trim();
    return arba == null || arba.isEmpty ? name : '$name • ARBA #$arba';
  }

  factory _LinkedExhibitor.fromJson(Map<String, dynamic> json) {
    final candidates = <String>[
      _textOrNull(json['display_name']) ?? '',
      _textOrNull(json['showing_name']) ?? '',
      [
        _textOrNull(json['first_name']),
        _textOrNull(json['last_name']),
      ].whereType<String>().join(' ').trim(),
    ];
    final name = candidates.firstWhere(
      (value) => value.trim().isNotEmpty,
      orElse: () => 'Unnamed exhibitor',
    );
    return _LinkedExhibitor(
      name: name,
      arbaNumber: _textOrNull(json['arba_number']),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 132,
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
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
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status, required this.expired});

  final String status;
  final bool expired;

  @override
  Widget build(BuildContext context) {
    final text = expired ? 'Expired' : _titleCase(status);
    final color = expired
        ? Theme.of(context).colorScheme.error
        : status.toLowerCase() == 'active'
        ? Colors.green
        : Theme.of(context).colorScheme.secondary;
    return Chip(
      label: Text(text),
      labelStyle: TextStyle(color: color, fontWeight: FontWeight.w700),
      side: BorderSide(color: color.withValues(alpha: 0.65)),
      visualDensity: VisualDensity.compact,
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
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 46),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
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
}

String? _textOrNull(dynamic value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

DateTime? _dateOrNull(dynamic value) {
  final text = _textOrNull(value);
  return text == null ? null : DateTime.tryParse(text)?.toLocal();
}

DateTime _today() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

String _termLabel(DateTime? start, DateTime? end) {
  final startText = _formatDate(start);
  final endText = _formatDate(end);
  if (startText != null && endText != null) return '$startText – $endText';
  if (endText != null) return 'Renews by $endText';
  if (startText != null) return 'Started $startText';
  return 'Not available';
}

String? _formatDate(DateTime? value) {
  if (value == null) return null;
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

String _titleCase(String value) {
  return value
      .split(RegExp(r'[_\s-]+'))
      .where((part) => part.isNotEmpty)
      .map(
        (part) => '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
      )
      .join(' ');
}
