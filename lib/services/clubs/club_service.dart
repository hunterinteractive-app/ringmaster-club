// lib/services/clubs/club_service.dart

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

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

  Future<ClubCheckoutResult> startMemberCheckout({
    required String clubId,
    required String sourceType,
    required String sourceId,
    required int amountCents,
    required String description,
    String? returnUrl,
    bool openCheckout = true,
  }) async {
    final normalizedClubId = clubId.trim();
    final normalizedSourceType = sourceType.trim();
    final normalizedSourceId = sourceId.trim();
    final normalizedDescription = description.trim();

    if (normalizedClubId.isEmpty) {
      throw ArgumentError('clubId is required.');
    }

    if (normalizedSourceType.isEmpty) {
      throw ArgumentError('sourceType is required.');
    }

    if (normalizedSourceId.isEmpty) {
      throw ArgumentError('sourceId is required.');
    }

    if (amountCents <= 0) {
      throw ArgumentError('amountCents must be greater than zero.');
    }

    final response = await _client.functions.invoke(
      'stripe-club-member-create-checkout',
      body: {
        'club_id': normalizedClubId,
        'source_type': normalizedSourceType,
        'source_id': normalizedSourceId,
        'amount_cents': amountCents,
        'description': normalizedDescription.isEmpty
            ? 'RingMaster Club payment'
            : normalizedDescription,
        'return_url': returnUrl ?? Uri.base.toString(),
      },
    );

    final data = _normalizeMapResponse(
      response.data,
      'stripe-club-member-create-checkout returned an unexpected response format.',
    );

    final errorMessage = data['error']?.toString().trim();
    if (errorMessage != null && errorMessage.isNotEmpty) {
      throw Exception(errorMessage);
    }

    final result = ClubCheckoutResult.fromJson(data);

    if (openCheckout) {
      final url = result.url;
      if (url == null || url.isEmpty) {
        throw Exception('Stripe Checkout did not return a checkout URL.');
      }

      final uri = Uri.tryParse(url);
      if (uri == null) {
        throw Exception('Stripe Checkout returned an invalid checkout URL.');
      }

      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!launched) {
        throw Exception('Unable to open Stripe Checkout.');
      }
    }

    return result;
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
  
  Map<String, dynamic> _normalizeMapResponse(
    dynamic response,
    String formatErrorMessage,
  ) {
    if (response is Map<String, dynamic>) {
      return response;
    }

    if (response is Map) {
      return Map<String, dynamic>.from(response);
    }

    throw FormatException(formatErrorMessage);
  }
}


class ClubCheckoutResult {
  const ClubCheckoutResult({
    required this.checkoutSessionId,
    required this.amountSubtotal,
    required this.stripeProcessingFeeAmount,
    required this.platformFeeAmount,
    required this.amountTotal,
    required this.feeMode,
    this.url,
  });

  factory ClubCheckoutResult.fromJson(Map<String, dynamic> json) {
    return ClubCheckoutResult(
      url: json['url']?.toString(),
      checkoutSessionId: json['checkout_session_id']?.toString() ?? '',
      amountSubtotal: _intValue(json['amount_subtotal']),
      stripeProcessingFeeAmount: _intValue(
        json['stripe_processing_fee_amount'],
      ),
      platformFeeAmount: _intValue(json['platform_fee_amount']),
      amountTotal: _intValue(json['amount_total']),
      feeMode: json['fee_mode']?.toString() ?? '',
    );
  }

  final String? url;
  final String checkoutSessionId;
  final int amountSubtotal;
  final int stripeProcessingFeeAmount;
  final int platformFeeAmount;
  final int amountTotal;
  final String feeMode;

  static int _intValue(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}