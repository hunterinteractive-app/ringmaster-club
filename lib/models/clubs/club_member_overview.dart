import 'club_summary.dart';

class ClubMemberOverview {
  const ClubMemberOverview({
    this.clubs = const [],
    this.memberships = const [],
    this.events = const [],
    this.announcements = const [],
    this.personalCardCount,
    this.unavailableSections = const {},
  });

  final List<ClubSummary> clubs;
  final List<MemberMembershipSummary> memberships;
  final List<MemberClubUpdate> events;
  final List<MemberClubUpdate> announcements;
  final int? personalCardCount;
  final Set<String> unavailableSections;

  /// Staff access and personal membership are independent relationships.
  List<ClubSummary> get manageableClubs => {
    for (final club in clubs.where((club) => club.canManageClub))
      club.clubId: club,
  }.values.toList();
}

class MemberMembershipSummary {
  const MemberMembershipSummary({
    required this.club,
    required this.memberName,
    required this.status,
    this.number,
    this.expiresAt,
  });

  final ClubSummary club;
  final String memberName;
  final String status;
  final String? number;
  final DateTime? expiresAt;

  bool needsRenewal(DateTime now) {
    if (status == 'expired' || status == 'expiring') return true;
    if (status != 'active' || expiresAt == null) return false;
    final today = DateTime(now.year, now.month, now.day);
    final expiration = DateTime(
      expiresAt!.year,
      expiresAt!.month,
      expiresAt!.day,
    );
    return !expiration.isAfter(today.add(const Duration(days: 60)));
  }

  factory MemberMembershipSummary.fromJson(
    ClubSummary club,
    Map<String, dynamic> row,
  ) => MemberMembershipSummary(
    club: club.copyWith(
      membershipId: row['id']?.toString(),
      membershipStatus: row['status']?.toString(),
    ),
    memberName: row['showing_name']?.toString().trim().isNotEmpty == true
        ? row['showing_name'].toString()
        : [row['first_name'], row['last_name']]
              .whereType<String>()
              .where((part) => part.trim().isNotEmpty)
              .join(' '),
    status: row['status']?.toString() ?? 'unknown',
    number: row['membership_number']?.toString(),
    expiresAt: DateTime.tryParse(row['current_term_end']?.toString() ?? ''),
  );
}

class MemberClubUpdate {
  const MemberClubUpdate({
    required this.club,
    required this.title,
    this.date,
    this.detail,
  });
  final ClubSummary club;
  final String title;
  final DateTime? date;
  final String? detail;
}
