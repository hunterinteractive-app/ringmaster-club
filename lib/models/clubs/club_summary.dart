// lib/models/clubs/club_summary.dart

class ClubSummary {
  const ClubSummary({
    required this.clubId,
    required this.clubName,
    required this.clubSlug,
    required this.clubType,
    required this.relationshipType,
    this.clubShortName,
    this.logoUrl,
    this.roleKey,
    this.roleName,
    this.membershipId,
    this.membershipStatus,
    this.sanctionRequestsEnabled,
  });

  final String clubId;
  final String clubName;
  final String? clubShortName;
  final String clubSlug;
  final String clubType;
  final String? logoUrl;
  final String relationshipType;
  final String? roleKey;
  final String? roleName;
  final String? membershipId;
  final String? membershipStatus;
  final bool? sanctionRequestsEnabled;

  bool get isStaff => relationshipType == 'staff';

  bool get isMember => relationshipType == 'member';

  bool get isOwner => roleKey == 'owner';

  bool get canManageClub => isStaff;

  bool get hasMembership => membershipId != null;

  bool get canRequestSanction => sanctionRequestsEnabled ?? true;

  String get displayName {
    final shortName = clubShortName?.trim();
    if (shortName != null && shortName.isNotEmpty) {
      return shortName;
    }
    return clubName;
  }

  factory ClubSummary.fromJson(Map<String, dynamic> json) {
    return ClubSummary(
      clubId: _requiredString(json, 'club_id'),
      clubName: _requiredString(json, 'club_name'),
      clubShortName: _nullableString(json['club_short_name']),
      clubSlug: _requiredString(json, 'club_slug'),
      clubType: _requiredString(json, 'club_type'),
      logoUrl: _nullableString(json['logo_url']),
      relationshipType: _requiredString(json, 'relationship_type'),
      roleKey: _nullableString(json['role_key']),
      roleName: _nullableString(json['role_name']),
      membershipId: _nullableString(json['membership_id']),
      membershipStatus: _nullableString(json['membership_status']),
      sanctionRequestsEnabled: _nullableBool(
        json['sanction_requests_addon_enabled'],
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'club_id': clubId,
      'club_name': clubName,
      'club_short_name': clubShortName,
      'club_slug': clubSlug,
      'club_type': clubType,
      'logo_url': logoUrl,
      'relationship_type': relationshipType,
      'role_key': roleKey,
      'role_name': roleName,
      'membership_id': membershipId,
      'membership_status': membershipStatus,
      'sanction_requests_addon_enabled': sanctionRequestsEnabled,
    };
  }

  ClubSummary copyWith({
    String? clubId,
    String? clubName,
    String? clubShortName,
    bool clearClubShortName = false,
    String? clubSlug,
    String? clubType,
    String? logoUrl,
    bool clearLogoUrl = false,
    String? relationshipType,
    String? roleKey,
    bool clearRoleKey = false,
    String? roleName,
    bool clearRoleName = false,
    String? membershipId,
    bool clearMembershipId = false,
    String? membershipStatus,
    bool clearMembershipStatus = false,
    bool? sanctionRequestsEnabled,
    bool clearSanctionRequestsEnabled = false,
  }) {
    return ClubSummary(
      clubId: clubId ?? this.clubId,
      clubName: clubName ?? this.clubName,
      clubShortName: clearClubShortName
          ? null
          : clubShortName ?? this.clubShortName,
      clubSlug: clubSlug ?? this.clubSlug,
      clubType: clubType ?? this.clubType,
      logoUrl: clearLogoUrl ? null : logoUrl ?? this.logoUrl,
      relationshipType: relationshipType ?? this.relationshipType,
      roleKey: clearRoleKey ? null : roleKey ?? this.roleKey,
      roleName: clearRoleName ? null : roleName ?? this.roleName,
      membershipId: clearMembershipId
          ? null
          : membershipId ?? this.membershipId,
      membershipStatus: clearMembershipStatus
          ? null
          : membershipStatus ?? this.membershipStatus,
      sanctionRequestsEnabled: clearSanctionRequestsEnabled
          ? null
          : sanctionRequestsEnabled ?? this.sanctionRequestsEnabled,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ClubSummary &&
            runtimeType == other.runtimeType &&
            clubId == other.clubId &&
            relationshipType == other.relationshipType;
  }

  @override
  int get hashCode => Object.hash(clubId, relationshipType);

  @override
  String toString() {
    return 'ClubSummary('
        'clubId: $clubId, '
        'clubName: $clubName, '
        'relationshipType: $relationshipType, '
        'roleKey: $roleKey, '
        'membershipStatus: $membershipStatus'
        ')';
  }

  static String _requiredString(Map<String, dynamic> json, String key) {
    final value = _nullableString(json[key]);
    if (value == null) {
      throw FormatException('Missing or empty required field: $key');
    }
    return value;
  }

  static String? _nullableString(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static bool? _nullableBool(dynamic value) {
    if (value == null) return null;
    if (value is bool) return value;

    final text = value.toString().trim().toLowerCase();
    if (text.isEmpty) return null;
    if (text == 'true' || text == 't' || text == '1' || text == 'yes') {
      return true;
    }
    if (text == 'false' || text == 'f' || text == '0' || text == 'no') {
      return false;
    }

    return null;
  }
}
