// lib/services/clubs/club_service.dart

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/clubs/club_summary.dart';

class ClubService {
  ClubService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<List<ClubSummary>> getMyClubs() async {
    final response = await _client.rpc('get_my_clubs');

    final rows = _normalizeRows(response);
    final clubs = rows.map(ClubSummary.fromJson).toList();

    clubs.sort((a, b) {
      final nameComparison = a.clubName.toLowerCase().compareTo(
            b.clubName.toLowerCase(),
          );

      if (nameComparison != 0) {
        return nameComparison;
      }

      if (a.isStaff != b.isStaff) {
        return a.isStaff ? -1 : 1;
      }

      return a.relationshipType.compareTo(b.relationshipType);
    });

    return clubs;
  }

  Future<ClubSummary?> getClubById(String clubId) async {
    final normalizedClubId = clubId.trim();
    if (normalizedClubId.isEmpty) {
      return null;
    }

    final clubs = await getMyClubs();

    for (final club in clubs) {
      if (club.clubId == normalizedClubId) {
        return club;
      }
    }

    return null;
  }

  Future<bool> hasPermission({
    required String clubId,
    required String permissionKey,
  }) async {
    final normalizedClubId = clubId.trim();
    final normalizedPermissionKey = permissionKey.trim();

    if (normalizedClubId.isEmpty || normalizedPermissionKey.isEmpty) {
      return false;
    }

    final response = await _client.rpc(
      'has_club_permission',
      params: {
        'p_club_id': normalizedClubId,
        'p_permission_key': normalizedPermissionKey,
      },
    );

    return response == true;
  }

  Future<bool> isClubStaff(String clubId) async {
    final normalizedClubId = clubId.trim();
    if (normalizedClubId.isEmpty) {
      return false;
    }

    final response = await _client.rpc(
      'is_club_staff',
      params: {
        'p_club_id': normalizedClubId,
      },
    );

    return response == true;
  }

  Future<bool> isClubMember(String clubId) async {
    final normalizedClubId = clubId.trim();
    if (normalizedClubId.isEmpty) {
      return false;
    }

    final response = await _client.rpc(
      'is_club_member',
      params: {
        'p_club_id': normalizedClubId,
      },
    );

    return response == true;
  }

  List<Map<String, dynamic>> _normalizeRows(dynamic response) {
    if (response == null) {
      return const [];
    }

    if (response is! List) {
      throw const FormatException(
        'get_my_clubs returned an unexpected response format.',
      );
    }

    return response.map<Map<String, dynamic>>((row) {
      if (row is Map<String, dynamic>) {
        return row;
      }

      if (row is Map) {
        return Map<String, dynamic>.from(row);
      }

      throw const FormatException(
        'get_my_clubs returned an invalid club row.',
      );
    }).toList();
  }
}