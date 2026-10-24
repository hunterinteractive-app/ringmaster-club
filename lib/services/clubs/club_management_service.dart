import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/clubs/club_management_overview.dart';

class ClubManagementService {
  const ClubManagementService(this.client);

  final SupabaseClient client;

  Future<ClubManagementOverview> load(String clubId) async {
    // Keep the same authenticated RPC and RLS policies used by Reports and
    // Sweepstakes. Optional reporting failures must not block navigation.
    final responses = await Future.wait<dynamic>([
      client
          .from('clubs')
          .select(
            'membership_management_addon_enabled,'
            'sanction_requests_addon_enabled,events_meetings_addon_enabled,'
            'email_addon_enabled,sweepstakes_addon_enabled',
          )
          .eq('id', clubId)
          .single(),
      _optional(
        () => client.rpc(
          'get_club_reports_dashboard',
          params: {'p_club_id': clubId},
        ),
      ),
    ]);
    final features = ClubManagementFeatures.fromJson(
      Map<String, dynamic>.from(responses[0] as Map),
    );
    final summary = responses[1] is Map
        ? ClubManagementSummary.fromJson(
            Map<String, dynamic>.from(responses[1] as Map),
          )
        : null;

    int? reviewCount;
    int? overdueCount;
    if (features.sweepstakes) {
      final today = DateTime.now();
      final date =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-'
          '${today.day.toString().padLeft(2, '0')}';
      final counts = await Future.wait<dynamic>([
        _optional(
          () => client
              .from('club_sweepstakes_report_packages')
              .count(CountOption.exact)
              .eq('club_id', clubId)
              .inFilter('status', ['pending', 'unmatched', 'needs_review']),
        ),
        _optional(
          () => client
              .from('club_sweepstakes_expected_reports')
              .count(CountOption.exact)
              .eq('club_id', clubId)
              .or(
                'status.eq.overdue,and(status.in.(expected,partial),due_date.lt.$date)',
              ),
        ),
      ]);
      reviewCount = counts[0] as int?;
      overdueCount = counts[1] as int?;
    }
    return ClubManagementOverview(
      features: features,
      summary: summary,
      reportsNeedingReview: reviewCount,
      overdueReports: overdueCount,
    );
  }

  Future<dynamic> _optional(Future<dynamic> Function() request) async {
    try {
      return await request();
    } catch (_) {
      return null;
    }
  }
}
