import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/clubs/club_member_overview.dart';
import '../../models/clubs/club_summary.dart';
import 'club_service.dart';

class ClubMemberOverviewService {
  const ClubMemberOverviewService(this.client);
  final SupabaseClient client;

  Future<ClubMemberOverview> load() async {
    final user = client.auth.currentUser;
    if (user == null) throw StateError('Please sign in again.');
    final clubs = await ClubService(client: client).getMyClubs();
    final byId = <String, ClubSummary>{
      for (final club in clubs) club.clubId: club,
    };
    final unavailable = <String>{};
    Future<dynamic> optional(
      String section,
      Future<dynamic> Function() read,
    ) async {
      try {
        return await read();
      } catch (_) {
        unavailable.add(section);
        return null;
      }
    }

    final responses = await Future.wait<dynamic>([
      optional(
        'cards',
        () => client
            .from('personal_membership_cards')
            .count(CountOption.exact)
            .eq('user_id', user.id),
      ),
      if (byId.isNotEmpty)
        optional(
          'memberships',
          () => client
              .from('club_memberships')
              .select(
                'id,club_id,first_name,last_name,showing_name,membership_number,status,current_term_end',
              )
              .eq('user_id', user.id)
              .inFilter('club_id', byId.keys.toList())
              .neq('status', 'denied')
              .neq('status', 'cancelled')
              .order('current_term_end'),
        ),
    ]);
    final memberships = responses.length < 2
        ? <MemberMembershipSummary>[]
        : _rows(responses[1])
              .where((row) => byId.containsKey(row['club_id']))
              .map(
                (row) => MemberMembershipSummary.fromJson(
                  byId[row['club_id']]!,
                  row,
                ),
              )
              .toList();
    final memberIds = memberships
        .map((member) => member.club.clubId)
        .toSet()
        .toList();
    final updates = await Future.wait<dynamic>([
      if (memberIds.isNotEmpty)
        optional(
          'events',
          () => client
              .from('club_events')
              .select('club_id,title,start_at,location_name')
              .inFilter('club_id', memberIds)
              .eq('status', 'published')
              .inFilter('visibility', ['public', 'members'])
              .gte('start_at', DateTime.now().toUtc().toIso8601String())
              .order('start_at')
              .limit(6),
        )
      else
        Future.value(const []),
      if (byId.isNotEmpty)
        optional(
          'announcements',
          () => client
              .from('club_communications')
              .select('club_id,subject,sent_at,created_at')
              .eq('recipient_user_id', user.id)
              .inFilter('club_id', byId.keys.toList())
              .inFilter('message_kind', [
                'custom_individual',
                'custom_audience',
                'newsletter',
              ])
              .inFilter('status', ['sent', 'delivered'])
              .order('created_at', ascending: false)
              .limit(4),
        )
      else
        Future.value(const []),
    ]);
    if (unavailable.contains('memberships')) unavailable.add('events');
    List<MemberClubUpdate> updateList(dynamic rows, bool events) => _rows(rows)
        .where((row) => byId.containsKey(row['club_id']))
        .map(
          (row) => MemberClubUpdate(
            club: byId[row['club_id']]!,
            title:
                row[events ? 'title' : 'subject']?.toString() ?? 'Club update',
            date: DateTime.tryParse(
              (events ? row['start_at'] : row['sent_at'] ?? row['created_at'])
                      ?.toString() ??
                  '',
            )?.toLocal(),
            detail: events ? row['location_name']?.toString() : null,
          ),
        )
        .toList();
    return ClubMemberOverview(
      clubs: byId.values.toList(),
      memberships: memberships,
      events: updateList(updates[0], true),
      announcements: updateList(updates[1], false),
      personalCardCount: responses[0] as int?,
      unavailableSections: unavailable,
    );
  }
}

Iterable<Map<String, dynamic>> _rows(dynamic value) => value is List
    ? value.whereType<Map>().map((row) => Map<String, dynamic>.from(row))
    : const [];
