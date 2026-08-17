import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/clubs/club_summary.dart';

/// Displays the member's digital card for this club.
///
/// Cards from other organizations will be supported once there is a member
/// wallet data model. This screen only presents verified club membership data.
class ClubMembershipCardsScreen extends StatefulWidget {
  const ClubMembershipCardsScreen({super.key, required this.club});

  final ClubSummary club;

  @override
  State<ClubMembershipCardsScreen> createState() =>
      _ClubMembershipCardsScreenState();
}

class _ClubMembershipCardsScreenState extends State<ClubMembershipCardsScreen> {
  final _supabase = Supabase.instance.client;

  bool _isLoading = true;
  String? _errorMessage;
  _DigitalMembershipCard? _card;
  String? _logoUrl;

  @override
  void initState() {
    super.initState();
    _loadCard();
  }

  Future<void> _loadCard() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        throw StateError('Please sign in again to view your membership card.');
      }

      const membershipFields =
          'id,membership_type_id,membership_number,first_name,last_name,'
          'showing_name,status,current_term_end';
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
          _card = null;
          _isLoading = false;
        });
        return;
      }

      final membership = Map<String, dynamic>.from(membershipRow);
      var currentLogoUrl = widget.club.logoUrl;
      try {
        final clubRow = await _supabase
            .from('clubs')
            .select('logo_url')
            .eq('id', widget.club.clubId)
            .maybeSingle();
        currentLogoUrl = _textOrNull(clubRow?['logo_url']);
      } catch (_) {
        // The membership card remains usable if club branding is not readable
        // under an older club policy; use the portal's existing summary then.
      }
      String? typeName;
      final typeId = _textOrNull(membership['membership_type_id']);
      if (typeId != null) {
        final typeRow = await _supabase
            .from('club_membership_types')
            .select('name')
            .eq('id', typeId)
            .maybeSingle();
        typeName = _textOrNull(typeRow?['name']);
      }

      if (!mounted) return;
      setState(() {
        _card = _DigitalMembershipCard.fromJson(membership, typeName: typeName);
        _logoUrl = currentLogoUrl;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Unable to load your membership card: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.club.displayName} Membership Card'),
        actions: [
          IconButton(
            tooltip: 'Refresh membership card',
            onPressed: _isLoading ? null : _loadCard,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(child: _body(context)),
    );
  }

  Widget _body(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    if (_errorMessage != null) {
      return _CardMessageState(
        icon: Icons.error_outline,
        title: 'We could not load your card',
        message: _errorMessage!,
        actionLabel: 'Try again',
        onAction: _loadCard,
      );
    }

    if (_card == null) {
      return _CardMessageState(
        icon: Icons.credit_card_off_outlined,
        title: 'No membership card yet',
        message:
            'A digital card will appear here after a membership for ${widget.club.displayName} is linked to your RingMaster Club account.',
        actionLabel: 'Refresh',
        onAction: _loadCard,
      );
    }

    final card = _card!;
    final isActive = card.status.toLowerCase() == 'active' && !card.isExpired;
    final logoUrl = (_logoUrl ?? widget.club.logoUrl)?.trim();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Your digital membership card',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          'Present this card to verify your ${widget.club.displayName} membership.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 20),
        AspectRatio(
          aspectRatio: 1.6,
          child: Card(
            clipBehavior: Clip.antiAlias,
            color: isActive
                ? Theme.of(context).colorScheme.primaryContainer
                : Theme.of(context).colorScheme.errorContainer,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (logoUrl != null && logoUrl.isNotEmpty)
                  IgnorePointer(
                    child: Opacity(
                      opacity: 0.18,
                      child: Padding(
                        padding: const EdgeInsets.all(22),
                        child: Image.network(
                          logoUrl,
                          fit: BoxFit.contain,
                          excludeFromSemantics: true,
                          errorBuilder: (_, _, _) => const SizedBox.shrink(),
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.verified_user_outlined,
                            size: 30,
                            color: isActive
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.error,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              widget.club.displayName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Text(
                        card.memberName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 5),
                      Text(card.typeName ?? 'Club Member'),
                      const Spacer(),
                      Row(
                        children: [
                          Expanded(
                            child: _CardDetail(
                              label: 'MEMBER NO.',
                              value: card.membershipNumber ?? 'Pending',
                            ),
                          ),
                          Expanded(
                            child: _CardDetail(
                              label: isActive ? 'VALID THROUGH' : 'STATUS',
                              value: isActive
                                  ? _formatDate(card.currentTermEnd) ?? 'Active'
                                  : card.isExpired
                                  ? 'Expired'
                                  : _titleCase(card.status),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DigitalMembershipCard {
  const _DigitalMembershipCard({
    required this.membershipNumber,
    required this.memberName,
    required this.typeName,
    required this.status,
    required this.currentTermEnd,
  });

  final String? membershipNumber;
  final String memberName;
  final String? typeName;
  final String status;
  final DateTime? currentTermEnd;

  bool get isExpired {
    final end = currentTermEnd;
    if (end == null) return false;
    final today = DateTime.now();
    return DateTime(
      end.year,
      end.month,
      end.day,
    ).isBefore(DateTime(today.year, today.month, today.day));
  }

  factory _DigitalMembershipCard.fromJson(
    Map<String, dynamic> json, {
    required String? typeName,
  }) {
    final showingName = _textOrNull(json['showing_name']);
    final fullName = [
      _textOrNull(json['first_name']),
      _textOrNull(json['last_name']),
    ].whereType<String>().join(' ').trim();
    return _DigitalMembershipCard(
      membershipNumber: _textOrNull(json['membership_number']),
      memberName: showingName ?? (fullName.isEmpty ? 'Club Member' : fullName),
      typeName: typeName,
      status: _textOrNull(json['status']) ?? 'unknown',
      currentTermEnd: _dateOrNull(json['current_term_end']),
    );
  }
}

class _CardDetail extends StatelessWidget {
  const _CardDetail({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 3),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _CardMessageState extends StatelessWidget {
  const _CardMessageState({
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
