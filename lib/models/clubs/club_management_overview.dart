/// Read-only data for the management workspace. A missing summary means that
/// reporting could not be loaded; it must not be presented as an empty club.
class ClubManagementOverview {
  const ClubManagementOverview({
    required this.features,
    this.summary,
    this.reportsNeedingReview,
    this.overdueReports,
  });

  final ClubManagementFeatures features;
  final ClubManagementSummary? summary;
  final int? reportsNeedingReview;
  final int? overdueReports;
}

class ClubManagementFeatures {
  const ClubManagementFeatures({
    this.membership = false,
    this.sanctions = false,
    this.events = false,
    this.email = false,
    this.sweepstakes = false,
  });

  final bool membership;
  final bool sanctions;
  final bool events;
  final bool email;
  final bool sweepstakes;

  factory ClubManagementFeatures.fromJson(Map<String, dynamic> json) =>
      ClubManagementFeatures(
        membership: json['membership_management_addon_enabled'] == true,
        sanctions: json['sanction_requests_addon_enabled'] == true,
        events: json['events_meetings_addon_enabled'] == true,
        email: json['email_addon_enabled'] == true,
        sweepstakes: json['sweepstakes_addon_enabled'] == true,
      );
}

class ClubManagementSummary {
  const ClubManagementSummary({
    required this.totalMembers,
    required this.activeMembers,
    required this.expiringMembers,
    required this.pendingApplications,
    required this.pendingSanctions,
    required this.outstandingDues,
    required this.unpaidCount,
    required this.upcomingEvents,
    this.renewals = const [],
    this.activity = const [],
  });

  final int totalMembers;
  final int activeMembers;
  final int expiringMembers;
  final int pendingApplications;
  final int pendingSanctions;
  final double outstandingDues;
  final int unpaidCount;
  final int upcomingEvents;
  final List<ClubManagementRenewal> renewals;
  final List<ClubManagementActivity> activity;

  factory ClubManagementSummary.fromJson(Map<String, dynamic> json) {
    final membership = _map(json['membership']);
    final operations = _map(json['operations']);
    final payments = _map(json['payments']);
    return ClubManagementSummary(
      totalMembers: _number(membership['total_members']).toInt(),
      activeMembers: _number(membership['active_members']).toInt(),
      expiringMembers: _number(membership['expiring_soon']).toInt(),
      pendingApplications: _number(operations['pending_applications']).toInt(),
      pendingSanctions: _number(operations['pending_sanctions']).toInt(),
      outstandingDues: _number(payments['outstanding']).toDouble(),
      unpaidCount: _number(payments['unpaid_count']).toInt(),
      upcomingEvents: _number(operations['upcoming_events']).toInt(),
      renewals: _rows(
        json['upcoming_expirations'],
      ).map(ClubManagementRenewal.fromJson).toList(),
      activity: _rows(
        json['recent_activity'],
      ).map(ClubManagementActivity.fromJson).toList(),
    );
  }
}

class ClubManagementRenewal {
  const ClubManagementRenewal({required this.name, this.type, this.expiresAt});

  final String name;
  final String? type;
  final DateTime? expiresAt;

  factory ClubManagementRenewal.fromJson(Map<String, dynamic> json) =>
      ClubManagementRenewal(
        name: json['name']?.toString() ?? 'Member',
        type: json['type_name']?.toString(),
        expiresAt: DateTime.tryParse(json['expires_at']?.toString() ?? ''),
      );
}

class ClubManagementActivity {
  const ClubManagementActivity({
    required this.type,
    required this.title,
    this.status,
    this.createdAt,
  });

  final String type;
  final String title;
  final String? status;
  final DateTime? createdAt;

  factory ClubManagementActivity.fromJson(Map<String, dynamic> json) =>
      ClubManagementActivity(
        type: json['type']?.toString() ?? 'activity',
        title: json['title']?.toString() ?? 'Club activity',
        status: json['subtitle']?.toString(),
        createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
      );
}

Map<String, dynamic> _map(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : const {};

Iterable<Map<String, dynamic>> _rows(dynamic value) => value is List
    ? value.whereType<Map>().map((row) => Map<String, dynamic>.from(row))
    : const [];

num _number(dynamic value) =>
    value is num ? value : num.tryParse(value?.toString() ?? '') ?? 0;
