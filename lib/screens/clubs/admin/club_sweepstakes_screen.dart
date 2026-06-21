

// lib/screens/clubs/admin/club_sweepstakes_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/clubs/club_summary.dart';

class ClubSweepstakesScreen extends StatefulWidget {
  const ClubSweepstakesScreen({
    super.key,
    required this.club,
  });

  final ClubSummary club;

  @override
  State<ClubSweepstakesScreen> createState() => _ClubSweepstakesScreenState();
}

class _ClubSweepstakesScreenState extends State<ClubSweepstakesScreen> {
  final _supabase = Supabase.instance.client;
  final _searchController = TextEditingController();

  bool _isLoading = true;
  String? _errorMessage;
  String? _selectedSeasonId;
  String _standingFilter = 'all';

  List<_SweepstakesSeason> _seasons = const [];
  List<_SweepstakesDivision> _divisions = const [];
  List<_SweepstakesStanding> _standings = const [];
  List<_SweepstakesAdjustment> _adjustments = const [];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleSearchChanged);
    _loadData();
  }

  @override
  void dispose() {
    _searchController.removeListener(_handleSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _handleSearchChanged() {
    if (mounted) setState(() {});
  }

  _SweepstakesSeason? get _selectedSeason {
    for (final season in _seasons) {
      if (season.id == _selectedSeasonId) return season;
    }
    return _seasons.isEmpty ? null : _seasons.first;
  }

  List<_SweepstakesStanding> get _filteredStandings {
    final query = _searchController.text.trim().toLowerCase();
    final season = _selectedSeason;

    return _standings.where((standing) {
      if (season != null && standing.seasonId != season.id) return false;
      if (_standingFilter != 'all' && standing.divisionId != _standingFilter) {
        return false;
      }
      if (query.isEmpty) return true;

      final searchable = [
        standing.exhibitorName,
        standing.membershipNumber,
        standing.species,
        standing.breed,
        standing.variety,
        standing.divisionName,
      ].whereType<String>().join(' ').toLowerCase();

      return searchable.contains(query);
    }).toList()
      ..sort((a, b) {
        final divisionCompare = (a.divisionName ?? '').compareTo(
          b.divisionName ?? '',
        );
        if (divisionCompare != 0) return divisionCompare;
        final pointsCompare = b.totalPoints.compareTo(a.totalPoints);
        if (pointsCompare != 0) return pointsCompare;
        return a.exhibitorName.compareTo(b.exhibitorName);
      });
  }

  List<_SweepstakesDivision> get _selectedSeasonDivisions {
    final season = _selectedSeason;
    if (season == null) return const [];
    return _divisions.where((division) => division.seasonId == season.id).toList()
      ..sort((a, b) {
        final sortCompare = a.sortOrder.compareTo(b.sortOrder);
        if (sortCompare != 0) return sortCompare;
        return a.name.compareTo(b.name);
      });
  }

  List<_SweepstakesAdjustment> get _selectedSeasonAdjustments {
    final season = _selectedSeason;
    if (season == null) return const [];
    return _adjustments
        .where((adjustment) => adjustment.seasonId == season.id)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final responses = await Future.wait([
        _supabase
            .from('club_sweepstakes_seasons')
            .select(
              'id,club_id,name,status,start_date,end_date,description,'
              'points_notes,created_at,updated_at',
            )
            .eq('club_id', widget.club.clubId)
            .order('start_date', ascending: false),
        _supabase
            .from('club_sweepstakes_divisions')
            .select(
              'id,club_id,season_id,name,code,description,species,'
              'is_active,sort_order,created_at',
            )
            .eq('club_id', widget.club.clubId)
            .order('sort_order', ascending: true),
        _supabase
            .from('club_sweepstakes_standings')
            .select(
              'id,club_id,season_id,division_id,exhibitor_name,'
              'membership_number,species,breed,variety,points_from_results,'
              'points_adjusted,total_points,show_count,last_points_at,'
              'created_at,updated_at',
            )
            .eq('club_id', widget.club.clubId),
        _supabase
            .from('club_sweepstakes_adjustments')
            .select(
              'id,club_id,season_id,division_id,standing_id,exhibitor_name,'
              'points_delta,reason,notes,created_at',
            )
            .eq('club_id', widget.club.clubId)
            .order('created_at', ascending: false),
      ]);

      final seasons = (responses[0] as List)
          .whereType<Map>()
          .map((row) => _SweepstakesSeason.fromJson(Map<String, dynamic>.from(row)))
          .toList();

      final divisions = (responses[1] as List)
          .whereType<Map>()
          .map(
            (row) => _SweepstakesDivision.fromJson(Map<String, dynamic>.from(row)),
          )
          .toList();

      final divisionMap = <String, _SweepstakesDivision>{
        for (final division in divisions) division.id: division,
      };

      final standings = (responses[2] as List)
          .whereType<Map>()
          .map((row) {
            final json = Map<String, dynamic>.from(row);
            final divisionId = json['division_id']?.toString();
            return _SweepstakesStanding.fromJson(
              json,
              division: divisionId == null ? null : divisionMap[divisionId],
            );
          })
          .toList();

      final adjustments = (responses[3] as List)
          .whereType<Map>()
          .map(
            (row) => _SweepstakesAdjustment.fromJson(
              Map<String, dynamic>.from(row),
              divisionMap: divisionMap,
            ),
          )
          .toList();

      if (!mounted) return;
      setState(() {
        _seasons = seasons;
        _divisions = divisions;
        _standings = standings;
        _adjustments = adjustments;
        _selectedSeasonId ??= seasons.isEmpty ? null : seasons.first.id;
        if (_selectedSeasonId != null &&
            !seasons.any((season) => season.id == _selectedSeasonId)) {
          _selectedSeasonId = seasons.first.id;
        }
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Unable to load sweepstakes: $error';
      });
    }
  }

  Future<void> _openSeasonEditor({_SweepstakesSeason? existing}) async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SeasonEditorDialog(
        clubId: widget.club.clubId,
        existing: existing,
      ),
    );

    if (changed == true) await _loadData();
  }

  Future<void> _openDivisionEditor({_SweepstakesDivision? existing}) async {
    final season = _selectedSeason;
    if (season == null) return;

    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DivisionEditorDialog(
        clubId: widget.club.clubId,
        season: season,
        existing: existing,
      ),
    );

    if (changed == true) await _loadData();
  }

  Future<void> _openAdjustmentEditor({_SweepstakesStanding? standing}) async {
    final season = _selectedSeason;
    if (season == null) return;

    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AdjustmentEditorDialog(
        clubId: widget.club.clubId,
        season: season,
        divisions: _selectedSeasonDivisions,
        standing: standing,
      ),
    );

    if (changed == true) await _loadData();
  }

  Future<void> _setSeasonStatus(_SweepstakesSeason season, String status) async {
    try {
      await _supabase.rpc(
        'set_club_sweepstakes_season_status',
        params: {
          'p_season_id': season.id,
          'p_status': status,
        },
      );
      await _loadData();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to update season: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sweepstakes'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _loadData,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openSeasonEditor(),
        icon: const Icon(Icons.add),
        label: const Text('New Season'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null && _seasons.isEmpty) {
      return _MessageState(
        icon: Icons.error_outline,
        title: 'Unable to load sweepstakes',
        message: _errorMessage!,
        actionLabel: 'Try Again',
        onAction: _loadData,
      );
    }

    final season = _selectedSeason;
    final filteredStandings = _filteredStandings;
    final divisions = _selectedSeasonDivisions;
    final adjustments = _selectedSeasonAdjustments;

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          Text(
            widget.club.clubName,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'Manage sweepstakes seasons, divisions, standings, and manual point adjustments.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          if (_errorMessage != null) ...[
            Material(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(_errorMessage!),
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (_seasons.isEmpty)
            _InlineEmptyState(
              title: 'No sweepstakes seasons yet',
              message:
                  'Create a season before adding divisions, standings, or adjustments.',
              actionLabel: 'New Season',
              onAction: () => _openSeasonEditor(),
            )
          else ...[
            _SeasonHeaderCard(
              season: season!,
              seasons: _seasons,
              selectedSeasonId: _selectedSeasonId,
              onSeasonChanged: (value) {
                if (value == null) return;
                setState(() {
                  _selectedSeasonId = value;
                  _standingFilter = 'all';
                });
              },
              onEdit: () => _openSeasonEditor(existing: season),
              onActivate: season.status == 'active'
                  ? null
                  : () => _setSeasonStatus(season, 'active'),
              onFinalize: season.status == 'finalized'
                  ? null
                  : () => _setSeasonStatus(season, 'finalized'),
              onArchive: season.status == 'archived'
                  ? null
                  : () => _setSeasonStatus(season, 'archived'),
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth >= 760
                    ? (constraints.maxWidth - 24) / 3
                    : constraints.maxWidth;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: width,
                      child: _SummaryCard(
                        icon: Icons.leaderboard_outlined,
                        label: 'Standings',
                        value: filteredStandings.length.toString(),
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: _SummaryCard(
                        icon: Icons.category_outlined,
                        label: 'Divisions',
                        value: divisions.length.toString(),
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: _SummaryCard(
                        icon: Icons.tune_outlined,
                        label: 'Adjustments',
                        value: adjustments.length.toString(),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            _SectionHeader(
              title: 'Divisions',
              actionLabel: 'Add Division',
              onAction: () => _openDivisionEditor(),
            ),
            const SizedBox(height: 8),
            if (divisions.isEmpty)
              const _InlineEmptyState(
                title: 'No divisions yet',
                message:
                    'Add divisions such as Open Rabbit, Youth Rabbit, Open Cavy, or breed-specific groups.',
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final division in divisions)
                    ActionChip(
                      avatar: Icon(
                        division.isActive
                            ? Icons.category_outlined
                            : Icons.category_rounded,
                      ),
                      label: Text(
                        '${division.name}${division.isActive ? '' : ' (Inactive)'}',
                      ),
                      onPressed: () => _openDivisionEditor(existing: division),
                    ),
                ],
              ),
            const SizedBox(height: 20),
            _SectionHeader(
              title: 'Standings',
              actionLabel: 'Manual Adjustment',
              onAction: () => _openAdjustmentEditor(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Search standings',
                hintText: 'Exhibitor, member number, species, breed, variety',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        onPressed: _searchController.clear,
                        icon: const Icon(Icons.clear),
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: 320,
              child: DropdownButtonFormField<String>(
                initialValue: _standingFilter,
                decoration: const InputDecoration(
                  labelText: 'Division filter',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(value: 'all', child: Text('All divisions')),
                  for (final division in divisions)
                    DropdownMenuItem(
                      value: division.id,
                      child: Text(division.name),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _standingFilter = value);
                },
              ),
            ),
            const SizedBox(height: 12),
            if (filteredStandings.isEmpty)
              const _InlineEmptyState(
                title: 'No standings yet',
                message:
                    'Standings will appear after show result imports or manual point adjustments are added.',
              )
            else
              _StandingsTable(
                standings: filteredStandings,
                onAdjust: (standing) => _openAdjustmentEditor(standing: standing),
              ),
            const SizedBox(height: 20),
            _SectionHeader(
              title: 'Recent Adjustments',
              actionLabel: 'Add Adjustment',
              onAction: () => _openAdjustmentEditor(),
            ),
            const SizedBox(height: 8),
            if (adjustments.isEmpty)
              const _InlineEmptyState(
                title: 'No manual adjustments',
                message:
                    'Point corrections and bonus adjustments will be listed here for audit history.',
              )
            else
              for (final adjustment in adjustments.take(10))
                _AdjustmentCard(adjustment: adjustment),
          ],
        ],
      ),
    );
  }
}

class _SeasonHeaderCard extends StatelessWidget {
  const _SeasonHeaderCard({
    required this.season,
    required this.seasons,
    required this.selectedSeasonId,
    required this.onSeasonChanged,
    required this.onEdit,
    this.onActivate,
    this.onFinalize,
    this.onArchive,
  });

  final _SweepstakesSeason season;
  final List<_SweepstakesSeason> seasons;
  final String? selectedSeasonId;
  final ValueChanged<String?> onSeasonChanged;
  final VoidCallback onEdit;
  final VoidCallback? onActivate;
  final VoidCallback? onFinalize;
  final VoidCallback? onArchive;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CircleAvatar(child: Icon(Icons.emoji_events_outlined)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        season.name,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      Text(season.dateLabel),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Chip(label: Text(_titleCase(season.status))),
                          if (season.description != null)
                            Chip(label: Text(season.description!)),
                        ],
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'edit') onEdit();
                    if (value == 'active') onActivate?.call();
                    if (value == 'finalized') onFinalize?.call();
                    if (value == 'archived') onArchive?.call();
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'edit', child: Text('Edit Season')),
                    if (onActivate != null)
                      const PopupMenuItem(value: 'active', child: Text('Activate')),
                    if (onFinalize != null)
                      const PopupMenuItem(value: 'finalized', child: Text('Finalize')),
                    if (onArchive != null)
                      const PopupMenuItem(value: 'archived', child: Text('Archive')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: selectedSeasonId,
              decoration: const InputDecoration(
                labelText: 'Selected season',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final item in seasons)
                  DropdownMenuItem(
                    value: item.id,
                    child: Text('${item.name} — ${_titleCase(item.status)}'),
                  ),
              ],
              onChanged: onSeasonChanged,
            ),
            if (season.pointsNotes != null) ...[
              const SizedBox(height: 12),
              Text(season.pointsNotes!),
            ],
          ],
        ),
      ),
    );
  }
}

class _StandingsTable extends StatelessWidget {
  const _StandingsTable({
    required this.standings,
    required this.onAdjust,
  });

  final List<_SweepstakesStanding> standings;
  final ValueChanged<_SweepstakesStanding> onAdjust;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Rank')),
            DataColumn(label: Text('Exhibitor')),
            DataColumn(label: Text('Division')),
            DataColumn(label: Text('Species')),
            DataColumn(label: Text('Breed')),
            DataColumn(label: Text('Result Pts')),
            DataColumn(label: Text('Adj')),
            DataColumn(label: Text('Total')),
            DataColumn(label: Text('Shows')),
            DataColumn(label: Text('Actions')),
          ],
          rows: [
            for (var index = 0; index < standings.length; index++)
              DataRow(
                cells: [
                  DataCell(Text('${index + 1}')),
                  DataCell(Text(standings[index].exhibitorLabel)),
                  DataCell(Text(standings[index].divisionName ?? '—')),
                  DataCell(Text(_titleCase(standings[index].species ?? '—'))),
                  DataCell(Text(standings[index].breed ?? '—')),
                  DataCell(Text(_numberText(standings[index].pointsFromResults))),
                  DataCell(Text(_numberText(standings[index].pointsAdjusted))),
                  DataCell(Text(_numberText(standings[index].totalPoints))),
                  DataCell(Text('${standings[index].showCount}')),
                  DataCell(
                    TextButton(
                      onPressed: () => onAdjust(standings[index]),
                      child: const Text('Adjust'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _AdjustmentCard extends StatelessWidget {
  const _AdjustmentCard({required this.adjustment});

  final _SweepstakesAdjustment adjustment;

  @override
  Widget build(BuildContext context) {
    final isPositive = adjustment.pointsDelta >= 0;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          child: Icon(isPositive ? Icons.add : Icons.remove),
        ),
        title: Text(adjustment.exhibitorName),
        subtitle: Text(
          '${adjustment.divisionName ?? 'No division'} • ${adjustment.reason}\n${adjustment.notes ?? ''}',
        ),
        isThreeLine: adjustment.notes != null,
        trailing: Text(
          _numberText(adjustment.pointsDelta),
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
      ),
    );
  }
}

class _SeasonEditorDialog extends StatefulWidget {
  const _SeasonEditorDialog({
    required this.clubId,
    this.existing,
  });

  final String clubId;
  final _SweepstakesSeason? existing;

  @override
  State<_SeasonEditorDialog> createState() => _SeasonEditorDialogState();
}

class _SeasonEditorDialogState extends State<_SeasonEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  final _supabase = Supabase.instance.client;

  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _startDateController;
  late final TextEditingController _endDateController;
  late final TextEditingController _pointsNotesController;

  late String _status;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameController = TextEditingController(text: existing?.name ?? '');
    _descriptionController =
        TextEditingController(text: existing?.description ?? '');
    _startDateController = TextEditingController(text: _dateText(existing?.startDate));
    _endDateController = TextEditingController(text: _dateText(existing?.endDate));
    _pointsNotesController = TextEditingController(text: existing?.pointsNotes ?? '');
    _status = existing?.status ?? 'draft';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _startDateController.dispose();
    _endDateController.dispose();
    _pointsNotesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSaving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final startDate = _parseDate(_startDateController.text);
    final endDate = _parseDate(_endDateController.text);

    if (startDate == null || endDate == null) {
      setState(() => _errorMessage = 'Start and end dates are required.');
      return;
    }

    if (endDate.isBefore(startDate)) {
      setState(() => _errorMessage = 'End date cannot be before start date.');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      await _supabase.rpc(
        'save_club_sweepstakes_season',
        params: {
          'p_season_id': widget.existing?.id,
          'p_club_id': widget.clubId,
          'p_name': _nameController.text.trim(),
          'p_status': _status,
          'p_start_date': _dateText(startDate),
          'p_end_date': _dateText(endDate),
          'p_description': _nullIfBlank(_descriptionController.text),
          'p_points_notes': _nullIfBlank(_pointsNotesController.text),
        },
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorMessage = 'Unable to save season: $error';
      });
    }
  }

  Future<void> _pickDate(TextEditingController controller) async {
    final date = await showDatePicker(
      context: context,
      initialDate: _parseDate(controller.text) ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime(2200),
    );
    if (date != null) controller.text = _dateText(date);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'New Season' : 'Edit Season'),
      content: SizedBox(
        width: 680,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_errorMessage != null) ...[
                  Material(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(_errorMessage!),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Season name',
                    border: OutlineInputBorder(),
                  ),
                  validator: _required,
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _status,
                  decoration: const InputDecoration(
                    labelText: 'Status',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'draft', child: Text('Draft')),
                    DropdownMenuItem(value: 'active', child: Text('Active')),
                    DropdownMenuItem(value: 'finalized', child: Text('Finalized')),
                    DropdownMenuItem(value: 'archived', child: Text('Archived')),
                  ],
                  onChanged: _isSaving
                      ? null
                      : (value) {
                          if (value != null) setState(() => _status = value);
                        },
                ),
                const SizedBox(height: 14),
                _ResponsiveFields(
                  children: [
                    _DateField(
                      controller: _startDateController,
                      label: 'Start date',
                      onPick: () => _pickDate(_startDateController),
                    ),
                    _DateField(
                      controller: _endDateController,
                      label: 'End date',
                      onPick: () => _pickDate(_endDateController),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _descriptionController,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _pointsNotesController,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'Point rules / notes',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _isSaving ? null : _save,
          icon: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: Text(_isSaving ? 'Saving...' : 'Save'),
        ),
      ],
    );
  }

  String? _required(String? value) {
    return value == null || value.trim().isEmpty ? 'Required.' : null;
  }

  String? _nullIfBlank(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

class _DivisionEditorDialog extends StatefulWidget {
  const _DivisionEditorDialog({
    required this.clubId,
    required this.season,
    this.existing,
  });

  final String clubId;
  final _SweepstakesSeason season;
  final _SweepstakesDivision? existing;

  @override
  State<_DivisionEditorDialog> createState() => _DivisionEditorDialogState();
}

class _DivisionEditorDialogState extends State<_DivisionEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  final _supabase = Supabase.instance.client;

  late final TextEditingController _nameController;
  late final TextEditingController _codeController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _sortOrderController;
  String _species = 'all';
  bool _isActive = true;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameController = TextEditingController(text: existing?.name ?? '');
    _codeController = TextEditingController(text: existing?.code ?? '');
    _descriptionController = TextEditingController(text: existing?.description ?? '');
    _sortOrderController = TextEditingController(
      text: (existing?.sortOrder ?? 0).toString(),
    );
    _species = existing?.species ?? 'all';
    _isActive = existing?.isActive ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    _descriptionController.dispose();
    _sortOrderController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSaving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      await _supabase.rpc(
        'save_club_sweepstakes_division',
        params: {
          'p_division_id': widget.existing?.id,
          'p_club_id': widget.clubId,
          'p_season_id': widget.season.id,
          'p_name': _nameController.text.trim(),
          'p_code': _nullIfBlank(_codeController.text),
          'p_description': _nullIfBlank(_descriptionController.text),
          'p_species': _species,
          'p_is_active': _isActive,
          'p_sort_order': int.tryParse(_sortOrderController.text.trim()) ?? 0,
        },
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorMessage = 'Unable to save division: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Add Division' : 'Edit Division'),
      content: SizedBox(
        width: 620,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_errorMessage != null) ...[
                  Material(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(_errorMessage!),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Division name',
                    border: OutlineInputBorder(),
                  ),
                  validator: _required,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _codeController,
                  decoration: const InputDecoration(
                    labelText: 'Code',
                    hintText: 'OPEN-RABBIT, YOUTH-CAVY, etc.',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _species,
                  decoration: const InputDecoration(
                    labelText: 'Species',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All')),
                    DropdownMenuItem(value: 'rabbit', child: Text('Rabbit')),
                    DropdownMenuItem(value: 'cavy', child: Text('Cavy')),
                  ],
                  onChanged: _isSaving
                      ? null
                      : (value) {
                          if (value != null) setState(() => _species = value);
                        },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _descriptionController,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _sortOrderController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Sort order',
                    border: OutlineInputBorder(),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active division'),
                  value: _isActive,
                  onChanged: _isSaving
                      ? null
                      : (value) => setState(() => _isActive = value),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _isSaving ? null : _save,
          icon: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: Text(_isSaving ? 'Saving...' : 'Save'),
        ),
      ],
    );
  }

  String? _required(String? value) {
    return value == null || value.trim().isEmpty ? 'Required.' : null;
  }

  String? _nullIfBlank(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

class _AdjustmentEditorDialog extends StatefulWidget {
  const _AdjustmentEditorDialog({
    required this.clubId,
    required this.season,
    required this.divisions,
    this.standing,
  });

  final String clubId;
  final _SweepstakesSeason season;
  final List<_SweepstakesDivision> divisions;
  final _SweepstakesStanding? standing;

  @override
  State<_AdjustmentEditorDialog> createState() => _AdjustmentEditorDialogState();
}

class _AdjustmentEditorDialogState extends State<_AdjustmentEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  final _supabase = Supabase.instance.client;

  late final TextEditingController _exhibitorController;
  late final TextEditingController _membershipController;
  late final TextEditingController _speciesController;
  late final TextEditingController _breedController;
  late final TextEditingController _varietyController;
  late final TextEditingController _pointsController;
  late final TextEditingController _reasonController;
  late final TextEditingController _notesController;

  String? _divisionId;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final standing = widget.standing;
    _divisionId = standing?.divisionId ??
        (widget.divisions.isEmpty ? null : widget.divisions.first.id);
    _exhibitorController =
        TextEditingController(text: standing?.exhibitorName ?? '');
    _membershipController =
        TextEditingController(text: standing?.membershipNumber ?? '');
    _speciesController = TextEditingController(text: standing?.species ?? '');
    _breedController = TextEditingController(text: standing?.breed ?? '');
    _varietyController = TextEditingController(text: standing?.variety ?? '');
    _pointsController = TextEditingController();
    _reasonController = TextEditingController();
    _notesController = TextEditingController();
  }

  @override
  void dispose() {
    _exhibitorController.dispose();
    _membershipController.dispose();
    _speciesController.dispose();
    _breedController.dispose();
    _varietyController.dispose();
    _pointsController.dispose();
    _reasonController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSaving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final points = double.tryParse(_pointsController.text.trim());
    if (points == null || points == 0) {
      setState(() => _errorMessage = 'Enter a non-zero point adjustment.');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      await _supabase.rpc(
        'add_club_sweepstakes_adjustment',
        params: {
          'p_club_id': widget.clubId,
          'p_season_id': widget.season.id,
          'p_division_id': _divisionId,
          'p_standing_id': widget.standing?.id,
          'p_exhibitor_name': _exhibitorController.text.trim(),
          'p_membership_number': _nullIfBlank(_membershipController.text),
          'p_species': _nullIfBlank(_speciesController.text),
          'p_breed': _nullIfBlank(_breedController.text),
          'p_variety': _nullIfBlank(_varietyController.text),
          'p_points_delta': points,
          'p_reason': _reasonController.text.trim(),
          'p_notes': _nullIfBlank(_notesController.text),
        },
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorMessage = 'Unable to save adjustment: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Manual Point Adjustment'),
      content: SizedBox(
        width: 720,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_errorMessage != null) ...[
                  Material(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(_errorMessage!),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                TextFormField(
                  controller: _exhibitorController,
                  decoration: const InputDecoration(
                    labelText: 'Exhibitor name',
                    border: OutlineInputBorder(),
                  ),
                  validator: _required,
                ),
                const SizedBox(height: 14),
                _ResponsiveFields(
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: _divisionId,
                      decoration: const InputDecoration(
                        labelText: 'Division',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem<String>(
                          value: null,
                          child: Text('No division'),
                        ),
                        for (final division in widget.divisions)
                          DropdownMenuItem(
                            value: division.id,
                            child: Text(division.name),
                          ),
                      ],
                      onChanged: _isSaving
                          ? null
                          : (value) => setState(() => _divisionId = value),
                    ),
                    TextFormField(
                      controller: _membershipController,
                      decoration: const InputDecoration(
                        labelText: 'Membership number',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    TextFormField(
                      controller: _speciesController,
                      decoration: const InputDecoration(
                        labelText: 'Species',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    TextFormField(
                      controller: _breedController,
                      decoration: const InputDecoration(
                        labelText: 'Breed',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    TextFormField(
                      controller: _varietyController,
                      decoration: const InputDecoration(
                        labelText: 'Variety',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    TextFormField(
                      controller: _pointsController,
                      keyboardType: const TextInputType.numberWithOptions(
                        signed: true,
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Point adjustment',
                        hintText: 'Use negative numbers to subtract points',
                        border: OutlineInputBorder(),
                      ),
                      validator: _required,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _reasonController,
                  decoration: const InputDecoration(
                    labelText: 'Reason',
                    border: OutlineInputBorder(),
                  ),
                  validator: _required,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _notesController,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'Notes',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _isSaving ? null : _save,
          icon: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: Text(_isSaving ? 'Saving...' : 'Save'),
        ),
      ],
    );
  }

  String? _required(String? value) {
    return value == null || value.trim().isEmpty ? 'Required.' : null;
  }

  String? _nullIfBlank(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

class _SweepstakesSeason {
  const _SweepstakesSeason({
    required this.id,
    required this.name,
    required this.status,
    required this.startDate,
    required this.endDate,
    this.description,
    this.pointsNotes,
  });

  final String id;
  final String name;
  final String status;
  final DateTime startDate;
  final DateTime endDate;
  final String? description;
  final String? pointsNotes;

  String get dateLabel => '${_formatDate(startDate)} – ${_formatDate(endDate)}';

  factory _SweepstakesSeason.fromJson(Map<String, dynamic> json) {
    return _SweepstakesSeason(
      id: json['id'].toString(),
      name: _nullableString(json['name']) ?? 'Unnamed Season',
      status: _nullableString(json['status']) ?? 'draft',
      startDate: _nullableDate(json['start_date']) ?? DateTime.now(),
      endDate: _nullableDate(json['end_date']) ?? DateTime.now(),
      description: _nullableString(json['description']),
      pointsNotes: _nullableString(json['points_notes']),
    );
  }
}

class _SweepstakesDivision {
  const _SweepstakesDivision({
    required this.id,
    required this.seasonId,
    required this.name,
    required this.isActive,
    required this.sortOrder,
    this.code,
    this.description,
    this.species,
  });

  final String id;
  final String seasonId;
  final String name;
  final String? code;
  final String? description;
  final String? species;
  final bool isActive;
  final int sortOrder;

  factory _SweepstakesDivision.fromJson(Map<String, dynamic> json) {
    return _SweepstakesDivision(
      id: json['id'].toString(),
      seasonId: json['season_id'].toString(),
      name: _nullableString(json['name']) ?? 'Unnamed Division',
      code: _nullableString(json['code']),
      description: _nullableString(json['description']),
      species: _nullableString(json['species']),
      isActive: json['is_active'] == true,
      sortOrder: _nullableInt(json['sort_order']) ?? 0,
    );
  }
}

class _SweepstakesStanding {
  const _SweepstakesStanding({
    required this.id,
    required this.seasonId,
    required this.exhibitorName,
    required this.pointsFromResults,
    required this.pointsAdjusted,
    required this.totalPoints,
    required this.showCount,
    this.divisionId,
    this.divisionName,
    this.membershipNumber,
    this.species,
    this.breed,
    this.variety,
  });

  final String id;
  final String seasonId;
  final String? divisionId;
  final String? divisionName;
  final String exhibitorName;
  final String? membershipNumber;
  final String? species;
  final String? breed;
  final String? variety;
  final double pointsFromResults;
  final double pointsAdjusted;
  final double totalPoints;
  final int showCount;

  String get exhibitorLabel {
    if (membershipNumber == null) return exhibitorName;
    return '$exhibitorName #$membershipNumber';
  }

  factory _SweepstakesStanding.fromJson(
    Map<String, dynamic> json, {
    _SweepstakesDivision? division,
  }) {
    return _SweepstakesStanding(
      id: json['id'].toString(),
      seasonId: json['season_id'].toString(),
      divisionId: _nullableString(json['division_id']),
      divisionName: division?.name,
      exhibitorName: _nullableString(json['exhibitor_name']) ?? 'Unknown Exhibitor',
      membershipNumber: _nullableString(json['membership_number']),
      species: _nullableString(json['species']),
      breed: _nullableString(json['breed']),
      variety: _nullableString(json['variety']),
      pointsFromResults: _nullableDouble(json['points_from_results']) ?? 0,
      pointsAdjusted: _nullableDouble(json['points_adjusted']) ?? 0,
      totalPoints: _nullableDouble(json['total_points']) ?? 0,
      showCount: _nullableInt(json['show_count']) ?? 0,
    );
  }
}

class _SweepstakesAdjustment {
  const _SweepstakesAdjustment({
    required this.id,
    required this.seasonId,
    required this.exhibitorName,
    required this.pointsDelta,
    required this.reason,
    required this.createdAt,
    this.divisionName,
    this.notes,
  });

  final String id;
  final String seasonId;
  final String exhibitorName;
  final String? divisionName;
  final double pointsDelta;
  final String reason;
  final String? notes;
  final DateTime createdAt;

  factory _SweepstakesAdjustment.fromJson(
    Map<String, dynamic> json, {
    required Map<String, _SweepstakesDivision> divisionMap,
  }) {
    final divisionId = _nullableString(json['division_id']);
    return _SweepstakesAdjustment(
      id: json['id'].toString(),
      seasonId: json['season_id'].toString(),
      exhibitorName: _nullableString(json['exhibitor_name']) ?? 'Unknown Exhibitor',
      divisionName: divisionId == null ? null : divisionMap[divisionId]?.name,
      pointsDelta: _nullableDouble(json['points_delta']) ?? 0,
      reason: _nullableString(json['reason']) ?? 'Adjustment',
      notes: _nullableString(json['notes']),
      createdAt: _nullableDate(json['created_at']) ?? DateTime.now(),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            CircleAvatar(child: Icon(icon)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
        OutlinedButton.icon(
          onPressed: onAction,
          icon: const Icon(Icons.add),
          label: Text(actionLabel),
        ),
      ],
    );
  }
}

class _ResponsiveFields extends StatelessWidget {
  const _ResponsiveFields({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth >= 560
            ? (constraints.maxWidth - 12) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: 12,
          runSpacing: 14,
          children: [
            for (final child in children) SizedBox(width: width, child: child),
          ],
        );
      },
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.controller,
    required this.label,
    required this.onPick,
  });

  final TextEditingController controller;
  final String label;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      readOnly: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (controller.text.isNotEmpty)
              IconButton(
                tooltip: 'Clear',
                onPressed: controller.clear,
                icon: const Icon(Icons.clear),
              ),
            IconButton(
              tooltip: 'Choose date',
              onPressed: onPick,
              icon: const Icon(Icons.calendar_today_outlined),
            ),
          ],
        ),
      ),
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
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            children: [
              Icon(icon, size: 64),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 10),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.refresh),
                label: Text(actionLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineEmptyState extends StatelessWidget {
  const _InlineEmptyState({
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            const Icon(Icons.emoji_events_outlined, size: 52),
            const SizedBox(height: 12),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.add),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String? _nullableString(dynamic value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

DateTime? _nullableDate(dynamic value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) return null;
  return DateTime.tryParse(text);
}

int? _nullableInt(dynamic value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '');
}

double? _nullableDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

DateTime? _parseDate(String value) {
  final text = value.trim();
  if (text.isEmpty) return null;
  return DateTime.tryParse(text);
}

String _dateText(DateTime? value) {
  if (value == null) return '';
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '${value.year}-$month-$day';
}

String _formatDate(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '$month/$day/${value.year}';
}

String _numberText(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value.toStringAsFixed(2);
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