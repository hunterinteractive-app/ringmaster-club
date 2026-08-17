import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/clubs/club_summary.dart';
import 'club_member_sweepstakes_reports_screen.dart';

/// Read-only view of the award boards that this club has made visible to members.
class ClubMemberSweepstakesStandingsScreen extends StatefulWidget {
  const ClubMemberSweepstakesStandingsScreen({super.key, required this.club});

  final ClubSummary club;

  @override
  State<ClubMemberSweepstakesStandingsScreen> createState() =>
      _ClubMemberSweepstakesStandingsScreenState();
}

class _ClubMemberSweepstakesStandingsScreenState
    extends State<ClubMemberSweepstakesStandingsScreen> {
  final _supabase = Supabase.instance.client;

  bool _isLoading = true;
  String? _errorMessage;
  List<_AwardBoard> _boards = const [];
  Map<String, List<_BoardEntry>> _entriesByBoard = const {};
  String? _selectedSeasonId;

  @override
  void initState() {
    super.initState();
    _loadBoards();
  }

  Future<void> _loadBoards() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final response = await _supabase.rpc(
        'get_member_club_sweepstakes_award_boards',
        params: {'p_club_id': widget.club.clubId},
      );
      final boards = (response as List)
          .whereType<Map>()
          .map((row) => _AwardBoard.fromJson(Map<String, dynamic>.from(row)))
          .toList();
      final results = await Future.wait(
        boards.map(
          (board) async => MapEntry(
            board.id,
            ((await _supabase.rpc(
                      'get_member_club_sweepstakes_award_board_entries',
                      params: {'p_award_board_id': board.id},
                    ))
                    as List)
                .whereType<Map>()
                .map(
                  (row) => _BoardEntry.fromJson(Map<String, dynamic>.from(row)),
                )
                .toList(),
          ),
        ),
      );
      if (!mounted) return;
      setState(() {
        _boards = boards;
        _entriesByBoard = Map.fromEntries(results);
        _selectedSeasonId =
            boards.any((board) => board.seasonId == _selectedSeasonId)
            ? _selectedSeasonId
            : boards.firstOrNull?.seasonId;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Unable to load the club award boards: $error';
      });
    }
  }

  List<_AwardBoard> get _visibleBoards =>
      _boards.where((board) => board.seasonId == _selectedSeasonId).toList();

  List<_SeasonChoice> get _seasonChoices {
    final byId = <String, _SeasonChoice>{};
    for (final board in _boards) {
      byId.putIfAbsent(
        board.seasonId,
        () => _SeasonChoice(
          id: board.seasonId,
          name: board.seasonName,
          startsOn: board.seasonStartsOn,
          endsOn: board.seasonEndsOn,
        ),
      );
    }
    return byId.values.toList();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Sweepstakes Standings'),
      actions: [
        IconButton(
          tooltip: 'Verified show reports',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ClubMemberSweepstakesReportsScreen(
                club: widget.club,
                view: MemberSweepstakesReportView.applied,
              ),
            ),
          ),
          icon: const Icon(Icons.description_outlined),
        ),
        IconButton(
          tooltip: 'Outstanding reports',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ClubMemberSweepstakesReportsScreen(
                club: widget.club,
                view: MemberSweepstakesReportView.outstanding,
              ),
            ),
          ),
          icon: const Icon(Icons.pending_actions_outlined),
        ),
        IconButton(
          tooltip: 'Refresh standings',
          onPressed: _isLoading ? null : _loadBoards,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: SafeArea(child: _buildBody(context)),
  );

  Widget _buildBody(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_errorMessage != null) {
      return _MessageState(
        icon: Icons.error_outline,
        title: 'We could not load the standings',
        message: _errorMessage!,
        onAction: _loadBoards,
      );
    }
    if (_boards.isEmpty) {
      return _MessageState(
        icon: Icons.emoji_events_outlined,
        title: 'No award boards available yet',
        message:
            '${widget.club.displayName} has not made any sweepstakes award boards visible to members.',
        onAction: _loadBoards,
      );
    }

    final seasons = _seasonChoices;
    final boards = _visibleBoards;
    final season = seasons.firstWhere((item) => item.id == _selectedSeasonId);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Sweepstakes award boards',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          'These boards are configured by ${widget.club.displayName} and are read-only here.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 18),
        DropdownButtonFormField<String>(
          key: ValueKey('season-$_selectedSeasonId'),
          initialValue: _selectedSeasonId,
          decoration: const InputDecoration(labelText: 'Season'),
          items: seasons
              .map(
                (item) =>
                    DropdownMenuItem(value: item.id, child: Text(item.name)),
              )
              .toList(),
          onChanged: (value) => setState(() => _selectedSeasonId = value),
        ),
        const SizedBox(height: 16),
        _SeasonCard(season: season, boardCount: boards.length),
        const SizedBox(height: 16),
        ...boards.map(
          (board) => _AwardBoardCard(
            board: board,
            entries: _entriesByBoard[board.id] ?? const [],
          ),
        ),
      ],
    );
  }
}

class _AwardBoard {
  const _AwardBoard({
    required this.id,
    required this.seasonId,
    required this.seasonName,
    required this.seasonStartsOn,
    required this.seasonEndsOn,
    required this.name,
    required this.grouping,
    required this.topN,
  });

  final String id;
  final String seasonId;
  final String seasonName;
  final DateTime? seasonStartsOn;
  final DateTime? seasonEndsOn;
  final String name;
  final String grouping;
  final int topN;

  bool get isBreedBoard => grouping == 'breed';

  factory _AwardBoard.fromJson(Map<String, dynamic> json) => _AwardBoard(
    id: json['id'].toString(),
    seasonId: json['season_id'].toString(),
    seasonName: _text(json['season_name'], fallback: 'Unnamed season'),
    seasonStartsOn: _date(json['season_starts_on']),
    seasonEndsOn: _date(json['season_ends_on']),
    name: _text(json['name'], fallback: 'Unnamed award board'),
    grouping: _text(json['board_grouping'], fallback: 'overall'),
    topN: _integer(json['top_n']),
  );
}

class _BoardEntry {
  const _BoardEntry({
    required this.rank,
    required this.exhibitorName,
    required this.membershipTypeName,
    required this.breed,
    required this.points,
  });

  final int rank;
  final String exhibitorName;
  final String? membershipTypeName;
  final String? breed;
  final num points;

  factory _BoardEntry.fromJson(Map<String, dynamic> json) => _BoardEntry(
    rank: _integer(json['rank']),
    exhibitorName: _text(json['exhibitor_name'], fallback: 'Unknown exhibitor'),
    membershipTypeName: _nullableText(json['membership_type_name']),
    breed: _nullableText(json['breed']),
    points: _number(json['points']),
  );
}

class _SeasonChoice {
  const _SeasonChoice({
    required this.id,
    required this.name,
    required this.startsOn,
    required this.endsOn,
  });

  final String id;
  final String name;
  final DateTime? startsOn;
  final DateTime? endsOn;
}

class _SeasonCard extends StatelessWidget {
  const _SeasonCard({required this.season, required this.boardCount});

  final _SeasonChoice season;
  final int boardCount;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: const Icon(Icons.emoji_events_outlined, size: 30),
      title: Text(
        season.name,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        '${_dateRange(season.startsOn, season.endsOn)} • $boardCount award boards',
      ),
    ),
  );
}

class _AwardBoardCard extends StatelessWidget {
  const _AwardBoardCard({required this.board, required this.entries});

  final _AwardBoard board;
  final List<_BoardEntry> entries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entriesByBreed = <String, List<_BoardEntry>>{};
    if (board.isBreedBoard) {
      for (final entry in entries) {
        entriesByBreed
            .putIfAbsent(entry.breed ?? 'Unspecified breed', () => [])
            .add(entry);
      }
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  board.isBreedBoard
                      ? Icons.pets_outlined
                      : Icons.emoji_events_outlined,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    board.name,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Top ${board.topN} • ${board.isBreedBoard ? 'ranked within each breed' : 'overall standings'}',
            ),
            const Divider(height: 26),
            if (entries.isEmpty)
              const Text(
                'No eligible results have been posted to this award board yet.',
              )
            else if (board.isBreedBoard)
              ...entriesByBreed.entries.expand(
                (group) => [
                  Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 6),
                    child: Text(
                      group.key,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  ...group.value.map((entry) => _EntryRow(entry: entry)),
                ],
              )
            else
              ...entries.map((entry) => _EntryRow(entry: entry)),
          ],
        ),
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry});

  final _BoardEntry entry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        CircleAvatar(radius: 16, child: Text('${entry.rank}')),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.exhibitorName,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              if (entry.membershipTypeName != null)
                Text(entry.membershipTypeName!),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              _points(entry.points),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const Text('points'),
          ],
        ),
      ],
    ),
  );
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.title,
    required this.message,
    required this.onAction,
  });
  final IconData icon;
  final String title;
  final String message;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 46),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: onAction,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh'),
          ),
        ],
      ),
    ),
  );
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

String? _nullableText(dynamic value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

String _text(dynamic value, {required String fallback}) =>
    _nullableText(value) ?? fallback;
DateTime? _date(dynamic value) => _nullableText(value) == null
    ? null
    : DateTime.tryParse(value.toString())?.toLocal();
int _integer(dynamic value) =>
    value is int ? value : int.tryParse('$value') ?? 0;
num _number(dynamic value) =>
    value is num ? value : num.tryParse('$value') ?? 0;
String _points(num value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(1);
String _dateRange(DateTime? start, DateTime? end) {
  String format(DateTime value) =>
      '${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][value.month - 1]} ${value.day}, ${value.year}';
  if (start != null && end != null) return '${format(start)} – ${format(end)}';
  return start != null
      ? format(start)
      : end != null
      ? format(end)
      : 'Dates not published';
}
