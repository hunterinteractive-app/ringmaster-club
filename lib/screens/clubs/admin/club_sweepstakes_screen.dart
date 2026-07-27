// lib/screens/clubs/admin/club_sweepstakes_screen.dart

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../models/clubs/club_summary.dart';

class ClubSweepstakesScreen extends StatefulWidget {
  const ClubSweepstakesScreen({super.key, required this.club});

  final ClubSummary club;

  @override
  State<ClubSweepstakesScreen> createState() => _ClubSweepstakesScreenState();
}

class _ClubSweepstakesScreenState extends State<ClubSweepstakesScreen> {
  final _supabase = Supabase.instance.client;
  final _searchController = TextEditingController();
  final _reportInboxController = ScrollController();

  bool _isLoading = true;
  String? _errorMessage;
  bool _sweepstakesAddonEnabled = false;
  bool _breedPaybackEnabled = false;
  String? _selectedSeasonId;
  String _standingFilter = 'all';

  List<_SweepstakesSeason> _seasons = const [];
  List<_SweepstakesDivision> _divisions = const [];
  List<_SweepstakesStanding> _standings = const [];
  List<_SweepstakesAwardBoard> _awardBoards = const [];
  Map<String, List<_SweepstakesAwardBoardEntry>> _awardBoardEntries = const {};
  List<_SweepstakesAdjustment> _adjustments = const [];
  List<_ExpectedSweepstakesReport> _expectedReports = const [];
  List<_SweepstakesReportPackage> _reportPackages = const [];
  String? _documentStorageBucket;

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
    _reportInboxController.dispose();
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
    }).toList()..sort((a, b) {
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
    return _divisions
        .where((division) => division.seasonId == season.id)
        .toList()
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
      final clubRow = await _supabase
          .from('clubs')
          .select('sweepstakes_addon_enabled,document_storage_bucket')
          .eq('id', widget.club.clubId)
          .single();

      final paybackSettingResponse = await _supabase
          .from('club_sweepstakes_breed_payback_settings')
          .select('is_enabled')
          .eq('club_id', widget.club.clubId)
          .maybeSingle();
      final breedPaybackEnabled = paybackSettingResponse?['is_enabled'] == true;

      final sweepstakesAddonEnabled =
          clubRow['sweepstakes_addon_enabled'] == true;

      if (!sweepstakesAddonEnabled) {
        if (!mounted) return;
        setState(() {
          _sweepstakesAddonEnabled = false;
          _breedPaybackEnabled = false;
          _seasons = const [];
          _divisions = const [];
          _standings = const [];
          _awardBoards = const [];
          _awardBoardEntries = const {};
          _adjustments = const [];
          _expectedReports = const [];
          _reportPackages = const [];
          _documentStorageBucket = null;
          _selectedSeasonId = null;
          _isLoading = false;
        });
        return;
      }

      final seasonsResponse = await _supabase
          .from('club_sweepstakes_seasons')
          .select(
            'id,club_id,name,status,start_date,end_date,description,'
            'points_notes,publication_mode,visibility,public_display_format,'
            'published_at,created_at,updated_at',
          )
          .eq('club_id', widget.club.clubId)
          .order('start_date', ascending: false);

      final divisionsResponse = await _supabase
          .from('club_sweepstakes_divisions')
          .select(
            'id,club_id,season_id,name,code,description,species,'
            'is_active,sort_order,created_at',
          )
          .eq('club_id', widget.club.clubId)
          .order('sort_order', ascending: true);

      final standingsResponse = await _supabase
          .from('club_sweepstakes_standings')
          .select(
            'id,club_id,season_id,division_id,exhibitor_name,'
            'membership_number,species,breed,variety,points_from_results,'
            'points_adjusted,total_points,show_count,last_points_at,'
            'created_at,updated_at',
          )
          .eq('club_id', widget.club.clubId);

      final adjustmentsResponse = await _supabase
          .from('club_sweepstakes_adjustments')
          .select(
            'id,club_id,season_id,division_id,standing_id,exhibitor_name,'
            'points_delta,reason,notes,created_at',
          )
          .eq('club_id', widget.club.clubId)
          .order('created_at', ascending: false);

      final expectedReportsResponse = await _supabase
          .from('club_sweepstakes_expected_reports')
          .select(
            'id,season_id,club_sanction_number,arba_sanction_number,'
            'show_name,show_date,show_end_date,show_location,'
            'show_secretary_name,show_secretary_email,due_date,status,'
            'reminder_count,last_reminder_sent_at,created_at',
          )
          .eq('club_id', widget.club.clubId)
          .order('show_date', ascending: false);

      final reportPackagesResponse = await _supabase
          .from('club_sweepstakes_report_packages')
          .select(
            'id,expected_report_id,season_id,source_type,source_subject,'
            'source_sender_email,source_received_at,storage_path,'
            'attachment_manifest,extracted_summary,review_notes,status,'
            'point_mismatch,created_at',
          )
          .eq('club_id', widget.club.clubId)
          .order('source_received_at', ascending: false);

      final awardBoardsResponse = await _supabase
          .from('club_sweepstakes_award_boards')
          .select(
            'id,club_id,season_id,name,grouping,membership_type_ids,'
            'eligibility_state,residency_requirement,top_n,is_active,sort_order',
          )
          .eq('club_id', widget.club.clubId)
          .eq('is_active', true)
          .order('sort_order', ascending: true);

      final seasons = (seasonsResponse as List)
          .whereType<Map>()
          .map(
            (row) =>
                _SweepstakesSeason.fromJson(Map<String, dynamic>.from(row)),
          )
          .toList();

      final divisions = (divisionsResponse as List)
          .whereType<Map>()
          .map(
            (row) =>
                _SweepstakesDivision.fromJson(Map<String, dynamic>.from(row)),
          )
          .toList();

      final divisionMap = <String, _SweepstakesDivision>{
        for (final division in divisions) division.id: division,
      };

      final standings = (standingsResponse as List).whereType<Map>().map((row) {
        final json = Map<String, dynamic>.from(row);
        final divisionId = json['division_id']?.toString();
        return _SweepstakesStanding.fromJson(
          json,
          division: divisionId == null ? null : divisionMap[divisionId],
        );
      }).toList();

      final adjustments = (adjustmentsResponse as List)
          .whereType<Map>()
          .map(
            (row) => _SweepstakesAdjustment.fromJson(
              Map<String, dynamic>.from(row),
              divisionMap: divisionMap,
            ),
          )
          .toList();
      final expectedReports = (expectedReportsResponse as List)
          .whereType<Map>()
          .map(
            (row) => _ExpectedSweepstakesReport.fromJson(
              Map<String, dynamic>.from(row),
            ),
          )
          .toList();
      final reportPackages = (reportPackagesResponse as List)
          .whereType<Map>()
          .map(
            (row) => _SweepstakesReportPackage.fromJson(
              Map<String, dynamic>.from(row),
            ),
          )
          .toList();
      final awardBoards = (awardBoardsResponse as List)
          .whereType<Map>()
          .map(
            (row) =>
                _SweepstakesAwardBoard.fromJson(Map<String, dynamic>.from(row)),
          )
          .toList();
      final awardBoardResponses = await Future.wait(
        awardBoards.map(
          (board) => _supabase.rpc(
            'get_club_sweepstakes_award_board_entries',
            params: {'p_award_board_id': board.id},
          ),
        ),
      );
      final awardBoardEntries = <String, List<_SweepstakesAwardBoardEntry>>{
        for (var index = 0; index < awardBoards.length; index++)
          awardBoards[index].id: (awardBoardResponses[index] as List)
              .whereType<Map>()
              .map(
                (row) => _SweepstakesAwardBoardEntry.fromJson(
                  Map<String, dynamic>.from(row),
                ),
              )
              .toList(),
      };

      if (!mounted) return;
      setState(() {
        _sweepstakesAddonEnabled = true;
        _breedPaybackEnabled = breedPaybackEnabled;
        _seasons = seasons;
        _divisions = divisions;
        _standings = standings;
        _awardBoards = awardBoards;
        _awardBoardEntries = awardBoardEntries;
        _adjustments = adjustments;
        _expectedReports = expectedReports;
        _reportPackages = reportPackages;
        _documentStorageBucket = _nullableString(
          clubRow['document_storage_bucket'],
        );
        _selectedSeasonId ??= seasons.isEmpty ? null : seasons.first.id;
        if (_selectedSeasonId != null &&
            !seasons.any((season) => season.id == _selectedSeasonId)) {
          _selectedSeasonId = seasons.isEmpty ? null : seasons.first.id;
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

  void _showLockedFeature() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sweepstakes Requires an Add-on'),
        content: const Text(
          'Sweepstakes seasons, divisions, standings, manual adjustments, and show result imports are available with the Sweepstakes Add-on. The club owner can enable this when the club is ready to use it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _openSeasonEditor({_SweepstakesSeason? existing}) async {
    if (!_sweepstakesAddonEnabled) {
      _showLockedFeature();
      return;
    }
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _SeasonEditorDialog(clubId: widget.club.clubId, existing: existing),
    );

    if (changed == true) await _loadData();
  }

  Future<void> _openDivisionEditor({_SweepstakesDivision? existing}) async {
    if (!_sweepstakesAddonEnabled) {
      _showLockedFeature();
      return;
    }
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

  Future<void> _openExpectedReportEditor() async {
    final season = _selectedSeason;
    if (season == null) return;
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ExpectedReportEditorDialog(
        clubId: widget.club.clubId,
        season: season,
      ),
    );
    if (changed == true) await _loadData();
  }

  Future<void> _openAdjustmentEditor({_SweepstakesStanding? standing}) async {
    if (!_sweepstakesAddonEnabled) {
      _showLockedFeature();
      return;
    }
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

  Future<void> _setSeasonStatus(
    _SweepstakesSeason season,
    String status,
  ) async {
    if (!_sweepstakesAddonEnabled) {
      _showLockedFeature();
      return;
    }
    try {
      await _supabase.rpc(
        'set_club_sweepstakes_season_status',
        params: {'p_season_id': season.id, 'p_status': status},
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
            tooltip: 'Upload report package',
            onPressed: _isLoading ? null : _openManualReportUpload,
            icon: const Icon(Icons.upload_file_outlined),
          ),
          IconButton(
            tooltip: 'Sweepstakes Rules & Report Intake',
            onPressed: _isLoading ? null : _openParserRules,
            icon: const Icon(Icons.rule_outlined),
          ),
          if (_breedPaybackEnabled)
            IconButton(
              tooltip: 'Breed Payback Fund',
              onPressed: _isLoading ? null : _openBreedPaybackFund,
              icon: const Icon(Icons.account_balance_wallet_outlined),
            ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _loadData,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isLoading
            ? null
            : _sweepstakesAddonEnabled
            ? () => _openSeasonEditor()
            : _showLockedFeature,
        icon: Icon(_sweepstakesAddonEnabled ? Icons.add : Icons.lock_outline),
        label: Text(
          _sweepstakesAddonEnabled ? 'New Season' : 'Add-on Required',
        ),
      ),
      body: _buildBody(),
    );
  }

  Future<void> _openParserRules() async {
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SweepstakesParserRulesDialog(clubId: widget.club.clubId),
    );
  }

  Future<void> _openBreedPaybackFund() async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _BreedPaybackFundDialog(
        clubId: widget.club.clubId,
        seasons: _seasons,
        expectedReports: _expectedReports,
        selectedSeasonId: _selectedSeasonId,
      ),
    );
    if (changed == true) await _loadData();
  }

  Future<void> _openManualReportUpload() async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ManualSweepstakesReportUploadDialog(
        clubId: widget.club.clubId,
        expectedReports: _expectedReports,
        documentStorageBucket: _documentStorageBucket,
      ),
    );
    if (changed == true) await _loadData();
  }

  Future<void> _openReportReview(_SweepstakesReportPackage report) async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SweepstakesReportReviewDialog(
        clubId: widget.club.clubId,
        report: report,
        expectedReports: _expectedReports,
        divisions: _divisions,
        documentStorageBucket: _documentStorageBucket,
      ),
    );
    if (changed == true) await _loadData();
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_sweepstakesAddonEnabled) {
      return _LockedAddOnState(
        clubName: widget.club.clubName,
        onRefresh: _loadData,
      );
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
    final expectedReports = _expectedReports
        .where(
          (report) => report.seasonId == null || report.seasonId == season?.id,
        )
        .toList();
    final reportPackages = _reportPackages
        .where(
          (report) => report.seasonId == null || report.seasonId == season?.id,
        )
        .toList();
    final packagesNeedingReview = reportPackages
        .where((report) => report.needsReview)
        .length;

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          Text(
            widget.club.clubName,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
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
              title: 'Report Review Inbox',
              actionLabel: packagesNeedingReview == 0
                  ? 'No Pending Reports'
                  : '$packagesNeedingReview Need Review',
              onAction: _loadData,
            ),
            const SizedBox(height: 8),
            if (reportPackages.isEmpty)
              const _InlineEmptyState(
                title: 'No report packages yet',
                message:
                    'Forwarded emails and uploaded reports will arrive here for staff review. Nothing affects standings until it is reviewed and processed.',
              )
            else
              SizedBox(
                height: reportPackages.length > 10
                    ? 960
                    : reportPackages.length * 96.0,
                child: Scrollbar(
                  controller: _reportInboxController,
                  thumbVisibility: reportPackages.length > 10,
                  child: ListView.builder(
                    controller: _reportInboxController,
                    primary: false,
                    itemCount: reportPackages.length,
                    itemBuilder: (context, index) {
                      final report = reportPackages[index];
                      return _SweepstakesReportPackageCard(
                        report: report,
                        onOpen: () => _openReportReview(report),
                      );
                    },
                  ),
                ),
              ),
            const SizedBox(height: 20),
            if (_awardBoards.any((board) => board.seasonId == season.id)) ...[
              Text(
                'Award Standings',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              for (final board in _awardBoards.where(
                (board) => board.seasonId == season.id,
              )) ...[
                _AwardBoardCard(
                  board: board,
                  entries: _awardBoardEntries[board.id] ?? const [],
                ),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 8),
            ],
            _SectionHeader(
              title: 'Report Reconciliation',
              actionLabel: 'Add Expected Report',
              onAction: _openExpectedReportEditor,
            ),
            const SizedBox(height: 8),
            if (expectedReports.isEmpty)
              const _InlineEmptyState(
                title: 'No expected reports yet',
                message:
                    'Approved sanctions will appear here automatically so staff can track missing, partial, and processed reports.',
              )
            else
              for (final report in expectedReports.take(10))
                _ExpectedReportCard(report: report),
            const SizedBox(height: 20),
            if (_breedPaybackEnabled) ...[
              _SectionHeader(
                title: 'ISRBA Breed Payback Fund',
                actionLabel: 'Open Fund Ledger',
                onAction: _openBreedPaybackFund,
              ),
              const SizedBox(height: 8),
              _InlineEmptyState(
                title: 'Track sanctioned-show breed fees',
                message:
                    'Record rabbits shown by breed, then match cash, check, or online payments. Each 10¢ fee is split into 8¢ for the breed fund and 2¢ for ISRBA.',
                actionLabel: 'Open Fund Ledger',
                onAction: _openBreedPaybackFund,
              ),
              const SizedBox(height: 20),
            ],
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
                  const DropdownMenuItem(
                    value: 'all',
                    child: Text('All divisions'),
                  ),
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
                onAdjust: (standing) =>
                    _openAdjustmentEditor(standing: standing),
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

class _BreedPaybackFundDialog extends StatefulWidget {
  const _BreedPaybackFundDialog({
    required this.clubId,
    required this.seasons,
    required this.expectedReports,
    this.selectedSeasonId,
  });

  final String clubId;
  final List<_SweepstakesSeason> seasons;
  final List<_ExpectedSweepstakesReport> expectedReports;
  final String? selectedSeasonId;

  @override
  State<_BreedPaybackFundDialog> createState() =>
      _BreedPaybackFundDialogState();
}

class _BreedPaybackFundDialogState extends State<_BreedPaybackFundDialog> {
  final _supabase = Supabase.instance.client;
  bool _loading = true;
  String? _error;
  List<_BreedPaybackObligation> _obligations = const [];
  List<_BreedPaybackPayment> _payments = const [];
  List<_BreedPaybackAllocation> _allocations = const [];
  List<_BreedPaybackConventionAllocation> _conventionAllocations = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final responses = await Future.wait([
        _supabase
            .from('club_sweepstakes_breed_payback_obligations')
            .select(
              'id,season_id,expected_report_id,breed,rabbits_shown,count_source,collection_cents_per_rabbit,breed_fund_cents_per_rabbit,isrba_allocation_cents_per_rabbit,expected_collection_cents,expected_breed_fund_cents,expected_isrba_allocation_cents,notes,created_at',
            )
            .eq('club_id', widget.clubId)
            .order('created_at', ascending: false),
        _supabase
            .from('club_sweepstakes_breed_payback_payments')
            .select(
              'id,received_date,amount_cents,payment_method,payer_name,payer_email,reference,notes,created_at',
            )
            .eq('club_id', widget.clubId)
            .order('received_date', ascending: false),
        _supabase
            .from('club_sweepstakes_breed_payback_payment_allocations')
            .select('id,payment_id,obligation_id,amount_cents,created_at'),
        _supabase
            .from('club_sweepstakes_breed_payback_convention_allocations')
            .select(
              'id,season_id,breed,award_type,award_detail,amount_cents,notes,created_at',
            )
            .eq('club_id', widget.clubId)
            .order('created_at', ascending: false),
      ]);
      if (!mounted) return;
      setState(() {
        _obligations = (responses[0] as List)
            .whereType<Map>()
            .map(
              (row) => _BreedPaybackObligation.fromJson(
                Map<String, dynamic>.from(row),
              ),
            )
            .toList();
        _payments = (responses[1] as List)
            .whereType<Map>()
            .map(
              (row) =>
                  _BreedPaybackPayment.fromJson(Map<String, dynamic>.from(row)),
            )
            .toList();
        _allocations = (responses[2] as List)
            .whereType<Map>()
            .map(
              (row) => _BreedPaybackAllocation.fromJson(
                Map<String, dynamic>.from(row),
              ),
            )
            .toList();
        _conventionAllocations = (responses[3] as List)
            .whereType<Map>()
            .map(
              (row) => _BreedPaybackConventionAllocation.fromJson(
                Map<String, dynamic>.from(row),
              ),
            )
            .toList();
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load the breed payback fund: $error';
        _loading = false;
      });
    }
  }

  int _receivedFor(String obligationId) => _allocations
      .where((allocation) => allocation.obligationId == obligationId)
      .fold(0, (sum, allocation) => sum + allocation.amountCents);

  int get _expectedCollection =>
      _obligations.fold(0, (sum, item) => sum + item.expectedCollectionCents);
  int get _receivedCollection =>
      _allocations.fold(0, (sum, item) => sum + item.amountCents);
  int get _expectedFund =>
      _obligations.fold(0, (sum, item) => sum + item.expectedBreedFundCents);
  int get _receivedFund => _obligations.fold(0, (sum, item) {
    final received = _receivedFor(item.id);
    return sum +
        (received *
                item.breedFundCentsPerRabbit /
                item.collectionCentsPerRabbit)
            .round();
  });
  int get _expectedIsrba => _obligations.fold(
    0,
    (sum, item) => sum + item.expectedIsrbaAllocationCents,
  );
  int get _receivedIsrba => _receivedCollection - _receivedFund;

  String _breedKey(String breed) => breed.trim().toLowerCase();
  int _receivedFundForBreed(String breed) => _obligations
      .where((item) => _breedKey(item.breed) == _breedKey(breed))
      .fold(0, (sum, item) {
        final received = _receivedFor(item.id);
        return sum +
            (received *
                    item.breedFundCentsPerRabbit /
                    item.collectionCentsPerRabbit)
                .round();
      });
  int _plannedFundForBreed(String breed) => _conventionAllocations
      .where((item) => _breedKey(item.breed) == _breedKey(breed))
      .fold(0, (sum, item) => sum + item.amountCents);
  int _availableFundForBreed(String breed) =>
      _receivedFundForBreed(breed) - _plannedFundForBreed(breed);
  Map<String, int> get _availableFundByBreed {
    final breeds = <String>{
      ..._obligations.map((item) => item.breed),
      ..._conventionAllocations.map((item) => item.breed),
    };
    return {for (final breed in breeds) breed: _availableFundForBreed(breed)};
  }

  String _money(int cents) => '\$${(cents / 100).toStringAsFixed(2)}';
  _ExpectedSweepstakesReport? _reportFor(String id) {
    for (final report in widget.expectedReports) {
      if (report.id == id) return report;
    }
    return null;
  }

  String _countSummary(List<_BreedPaybackObligation> obligations) {
    if (obligations.isEmpty) return 'Awaiting counts';
    return obligations
        .map(
          (obligation) =>
              '${obligation.breed}: ${obligation.rabbitsShown}'
              '${obligation.countSource == 'manual' ? ' (confirmed)' : ''}',
        )
        .join('\n');
  }

  Future<void> _addObligation() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _BreedPaybackObligationDialog(
        clubId: widget.clubId,
        seasons: widget.seasons,
        expectedReports: widget.expectedReports,
        defaultSeasonId: widget.selectedSeasonId,
      ),
    );
    if (saved == true) await _load();
  }

  Future<void> _recordPayment() async {
    if (_obligations.isEmpty) {
      setState(
        () => _error =
            'Add the show and breed fee obligation before recording a payment.',
      );
      return;
    }
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _BreedPaybackPaymentDialog(
        clubId: widget.clubId,
        obligations: _obligations,
        receivedFor: _receivedFor,
        reportFor: _reportFor,
      ),
    );
    if (saved == true) await _load();
  }

  Future<void> _planConventionAwards() async {
    if (_availableFundByBreed.values.every((amount) => amount <= 0) &&
        _conventionAllocations.isEmpty) {
      setState(
        () => _error =
            'Record and match collected show fees before planning convention awards.',
      );
      return;
    }
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _BreedPaybackConventionAllocationDialog(
        clubId: widget.clubId,
        seasonId: widget.selectedSeasonId,
        availableFundByBreed: _availableFundByBreed,
        existingAllocations: _conventionAllocations,
      ),
    );
    if (saved == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final reports =
        widget.expectedReports
            .where(
              (report) =>
                  widget.selectedSeasonId == null ||
                  report.seasonId == null ||
                  report.seasonId == widget.selectedSeasonId,
            )
            .toList()
          ..sort((a, b) => b.showDate.compareTo(a.showDate));

    return AlertDialog(
      title: const Text('ISRBA Breed Payback Fund'),
      content: SizedBox(
        width: 1120,
        height: 680,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Track every ISRBA sanctioned show here. Once rabbit counts are confirmed, each 10¢ fee is split into 8¢ for the breed fund and 2¢ retained by ISRBA.',
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _PaybackMetric(
                        label: 'Expected fees',
                        value: _money(_expectedCollection),
                      ),
                      _PaybackMetric(
                        label: 'Received',
                        value: _money(_receivedCollection),
                      ),
                      _PaybackMetric(
                        label: 'Breed fund: received / expected',
                        value:
                            '${_money(_receivedFund)} / ${_money(_expectedFund)}',
                      ),
                      _PaybackMetric(
                        label: 'ISRBA allocation: received / expected',
                        value:
                            '${_money(_receivedIsrba)} / ${_money(_expectedIsrba)}',
                      ),
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text(
                        'Convention award plan',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const Spacer(),
                      Text(
                        '${_conventionAllocations.length} planned • ${_money(_conventionAllocations.fold(0, (sum, item) => sum + item.amountCents))}',
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (_conventionAllocations.isEmpty)
                    Text(
                      'When funds are collected, plan how each breed’s available fund will be divided at convention.',
                      style: Theme.of(context).textTheme.bodySmall,
                    )
                  else
                    SizedBox(
                      height: 142,
                      child: Scrollbar(
                        child: SingleChildScrollView(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              columnSpacing: 24,
                              headingRowHeight: 36,
                              dataRowMinHeight: 42,
                              dataRowMaxHeight: 58,
                              columns: const [
                                DataColumn(label: Text('Breed')),
                                DataColumn(label: Text('Award')),
                                DataColumn(label: Text('Detail')),
                                DataColumn(
                                  numeric: true,
                                  label: Text('Planned'),
                                ),
                                DataColumn(
                                  numeric: true,
                                  label: Text('Fund left'),
                                ),
                              ],
                              rows: _conventionAllocations.map((item) {
                                final detail = item.awardDetail?.trim();
                                return DataRow(
                                  cells: [
                                    DataCell(Text(item.breed)),
                                    DataCell(Text(item.awardName)),
                                    DataCell(
                                      SizedBox(
                                        width: 180,
                                        child: Text(
                                          detail == null || detail.isEmpty
                                              ? '—'
                                              : detail,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                    DataCell(Text(_money(item.amountCents))),
                                    DataCell(
                                      Text(
                                        _money(
                                          _availableFundForBreed(item.breed),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Text(
                        'Show obligations',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const Spacer(),
                      Text('${reports.length} sanctions'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: reports.isEmpty
                        ? const _InlineEmptyState(
                            title: 'No sanctioned shows yet',
                            message:
                                'Approved ISRBA sanctions will appear here so their show fees can be tracked from expected through collected.',
                          )
                        : Scrollbar(
                            child: SingleChildScrollView(
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: DataTable(
                                  columnSpacing: 22,
                                  headingRowHeight: 36,
                                  dataRowMinHeight: 50,
                                  dataRowMaxHeight: 78,
                                  columns: const [
                                    DataColumn(label: Text('Show')),
                                    DataColumn(label: Text('Date')),
                                    DataColumn(label: Text('Sanction')),
                                    DataColumn(label: Text('Breeds / counts')),
                                    DataColumn(
                                      numeric: true,
                                      label: Text('Due'),
                                    ),
                                    DataColumn(
                                      numeric: true,
                                      label: Text('Received'),
                                    ),
                                    DataColumn(
                                      numeric: true,
                                      label: Text('Remaining'),
                                    ),
                                    DataColumn(label: Text('Status')),
                                  ],
                                  rows: reports.map((report) {
                                    final obligations = _obligations
                                        .where(
                                          (obligation) =>
                                              obligation.expectedReportId ==
                                              report.id,
                                        )
                                        .toList();
                                    final expected = obligations.fold(
                                      0,
                                      (sum, obligation) =>
                                          sum +
                                          obligation.expectedCollectionCents,
                                    );
                                    final received = obligations.fold(
                                      0,
                                      (sum, obligation) =>
                                          sum + _receivedFor(obligation.id),
                                    );
                                    final outstanding = expected - received;
                                    final status = obligations.isEmpty
                                        ? 'Awaiting counts'
                                        : received == 0
                                        ? 'Unpaid'
                                        : outstanding > 0
                                        ? 'Partial'
                                        : outstanding == 0
                                        ? 'Paid'
                                        : 'Overpaid';
                                    return DataRow(
                                      cells: [
                                        DataCell(
                                          SizedBox(
                                            width: 220,
                                            child: Text(
                                              report.showName,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ),
                                        DataCell(
                                          Text(
                                            '${report.showDate.month}/${report.showDate.day}/${report.showDate.year}',
                                          ),
                                        ),
                                        DataCell(
                                          Text(
                                            report.clubSanctionNumber ??
                                                report.arbaSanctionNumber ??
                                                '—',
                                          ),
                                        ),
                                        DataCell(
                                          SizedBox(
                                            width: 170,
                                            child: Text(
                                              _countSummary(obligations),
                                              maxLines: 3,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ),
                                        DataCell(Text(_money(expected))),
                                        DataCell(Text(_money(received))),
                                        DataCell(Text(_money(outstanding))),
                                        DataCell(Chip(label: Text(status))),
                                      ],
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Payment history: ${_payments.length} payment${_payments.length == 1 ? '' : 's'} recorded. ${_money(_expectedCollection - _receivedCollection)} remains uncollected.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        OutlinedButton.icon(
          onPressed: _addObligation,
          icon: const Icon(Icons.add),
          label: const Text('Add show fees'),
        ),
        OutlinedButton.icon(
          onPressed: _planConventionAwards,
          icon: const Icon(Icons.emoji_events_outlined),
          label: const Text('Plan convention awards'),
        ),
        FilledButton.icon(
          onPressed: _recordPayment,
          icon: const Icon(Icons.payments_outlined),
          label: const Text('Record payment'),
        ),
      ],
    );
  }
}

class _PaybackMetric extends StatelessWidget {
  const _PaybackMetric({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 190,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 4),
            Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    ),
  );
}

class _BreedPaybackObligationDialog extends StatefulWidget {
  const _BreedPaybackObligationDialog({
    required this.clubId,
    required this.seasons,
    required this.expectedReports,
    this.defaultSeasonId,
  });
  final String clubId;
  final List<_SweepstakesSeason> seasons;
  final List<_ExpectedSweepstakesReport> expectedReports;
  final String? defaultSeasonId;
  @override
  State<_BreedPaybackObligationDialog> createState() =>
      _BreedPaybackObligationDialogState();
}

class _BreedPaybackObligationDialogState
    extends State<_BreedPaybackObligationDialog> {
  final _supabase = Supabase.instance.client;
  final _breed = TextEditingController();
  final _shown = TextEditingController();
  final _notes = TextEditingController();
  String? _reportId;
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    _breed.dispose();
    _shown.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final shown = int.tryParse(_shown.text.trim());
    if (_reportId == null ||
        _breed.text.trim().isEmpty ||
        shown == null ||
        shown < 0) {
      setState(
        () => _error =
            'Choose the sanctioned show and enter a breed plus the number of rabbits shown.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final report = widget.expectedReports.firstWhere(
      (item) => item.id == _reportId,
    );
    try {
      await _supabase
          .from('club_sweepstakes_breed_payback_obligations')
          .upsert({
            'club_id': widget.clubId,
            'season_id': report.seasonId ?? widget.defaultSeasonId,
            'expected_report_id': _reportId,
            'breed': _breed.text.trim(),
            'rabbits_shown': shown,
            'collection_cents_per_rabbit': 10,
            'breed_fund_cents_per_rabbit': 8,
            'isrba_allocation_cents_per_rabbit': 2,
            'expected_collection_cents': shown * 10,
            'expected_breed_fund_cents': shown * 8,
            'expected_isrba_allocation_cents': shown * 2,
            'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
            'created_by': _supabase.auth.currentUser?.id,
          }, onConflict: 'expected_report_id,breed');
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted)
        setState(() {
          _saving = false;
          _error = 'Unable to save show fees: $error';
        });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add sanctioned-show breed fees'),
    content: SizedBox(
      width: 560,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _reportId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Sanctioned show',
              border: OutlineInputBorder(),
            ),
            items: widget.expectedReports
                .map(
                  (report) => DropdownMenuItem(
                    value: report.id,
                    child: Text(
                      '${report.showName} • ${report.showDate.month}/${report.showDate.day}/${report.showDate.year}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: _saving
                ? null
                : (value) => setState(() => _reportId = value),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _breed,
            enabled: !_saving,
            decoration: const InputDecoration(
              labelText: 'Breed',
              hintText: 'Example: Mini Rex',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _shown,
            enabled: !_saving,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Rabbits shown',
              helperText: '10¢ each: 8¢ to the breed fund and 2¢ to ISRBA.',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            enabled: !_saving,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Notes (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: Text(_saving ? 'Saving…' : 'Save fees'),
      ),
    ],
  );
}

class _BreedPaybackPaymentDialog extends StatefulWidget {
  const _BreedPaybackPaymentDialog({
    required this.clubId,
    required this.obligations,
    required this.receivedFor,
    required this.reportFor,
  });
  final String clubId;
  final List<_BreedPaybackObligation> obligations;
  final int Function(String obligationId) receivedFor;
  final _ExpectedSweepstakesReport? Function(String reportId) reportFor;
  @override
  State<_BreedPaybackPaymentDialog> createState() =>
      _BreedPaybackPaymentDialogState();
}

class _BreedPaybackPaymentDialogState
    extends State<_BreedPaybackPaymentDialog> {
  final _supabase = Supabase.instance.client;
  final _amount = TextEditingController();
  final _payer = TextEditingController();
  final _reference = TextEditingController();
  final _notes = TextEditingController();
  String _method = 'check';
  final List<String?> _obligationIds = [null];
  final List<TextEditingController> _allocationAmounts = [
    TextEditingController(),
  ];
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    _amount.dispose();
    _payer.dispose();
    _reference.dispose();
    _notes.dispose();
    for (final controller in _allocationAmounts) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final amount = (double.tryParse(_amount.text.trim()) ?? 0) * 100;
    if (amount <= 0 || _obligationIds.any((id) => id == null)) {
      setState(
        () => _error =
            'Enter the amount received and choose the show/breed it pays.',
      );
      return;
    }
    final cents = amount.round();
    final allocationCents = _allocationAmounts
        .map(
          (controller) =>
              ((double.tryParse(controller.text.trim()) ?? 0) * 100).round(),
        )
        .toList();
    if (allocationCents.any((value) => value <= 0) ||
        allocationCents.fold(0, (sum, value) => sum + value) != cents) {
      setState(
        () => _error =
            'The payment amount must equal the total you assign to the selected show and breed fees.',
      );
      return;
    }
    for (var index = 0; index < allocationCents.length; index++) {
      final obligation = widget.obligations.firstWhere(
        (item) => item.id == _obligationIds[index],
      );
      if (allocationCents[index] >
          obligation.expectedCollectionCents -
              widget.receivedFor(obligation.id)) {
        setState(
          () => _error =
              'One allocation is more than the remaining balance for that show and breed.',
        );
        return;
      }
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final payment = await _supabase
          .from('club_sweepstakes_breed_payback_payments')
          .insert({
            'club_id': widget.clubId,
            'amount_cents': cents,
            'payment_method': _method,
            'payer_name': _payer.text.trim().isEmpty
                ? null
                : _payer.text.trim(),
            'reference': _reference.text.trim().isEmpty
                ? null
                : _reference.text.trim(),
            'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
            'received_by': _supabase.auth.currentUser?.id,
          })
          .select('id')
          .single();
      await _supabase
          .from('club_sweepstakes_breed_payback_payment_allocations')
          .insert([
            for (var index = 0; index < allocationCents.length; index++)
              {
                'payment_id': payment['id'],
                'obligation_id': _obligationIds[index],
                'amount_cents': allocationCents[index],
              },
          ]);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted)
        setState(() {
          _saving = false;
          _error = 'Unable to record payment: $error';
        });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Record payback payment'),
    content: SizedBox(
      width: 560,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _amount,
            enabled: !_saving,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Amount received',
              prefixText: '\$',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text(
                'Apply this payment',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _saving
                    ? null
                    : () => setState(() {
                        _obligationIds.add(null);
                        _allocationAmounts.add(TextEditingController());
                      }),
                icon: const Icon(Icons.add),
                label: const Text('Add another'),
              ),
            ],
          ),
          for (var index = 0; index < _obligationIds.length; index++) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _obligationIds[index],
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Show and breed fee ${index + 1}',
                      border: const OutlineInputBorder(),
                    ),
                    items: widget.obligations.map((item) {
                      final report = widget.reportFor(item.expectedReportId);
                      final remaining =
                          item.expectedCollectionCents -
                          widget.receivedFor(item.id);
                      return DropdownMenuItem(
                        value: item.id,
                        child: Text(
                          '${report?.showName ?? 'Sanctioned show'} • ${item.breed} • \$${(remaining / 100).toStringAsFixed(2)} remaining',
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: _saving
                        ? null
                        : (value) =>
                              setState(() => _obligationIds[index] = value),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 130,
                  child: TextField(
                    controller: _allocationAmounts[index],
                    enabled: !_saving,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Apply',
                      prefixText: '\$',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                if (_obligationIds.length > 1)
                  IconButton(
                    tooltip: 'Remove allocation',
                    onPressed: _saving
                        ? null
                        : () => setState(() {
                            _allocationAmounts.removeAt(index).dispose();
                            _obligationIds.removeAt(index);
                          }),
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _method,
            decoration: const InputDecoration(
              labelText: 'Payment method',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'cash', child: Text('Cash')),
              DropdownMenuItem(value: 'check', child: Text('Check')),
              DropdownMenuItem(value: 'online', child: Text('Online payment')),
              DropdownMenuItem(value: 'other', child: Text('Other')),
            ],
            onChanged: _saving
                ? null
                : (value) => setState(() => _method = value ?? 'check'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _payer,
            enabled: !_saving,
            decoration: const InputDecoration(
              labelText: 'Secretary or treasurer (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reference,
            enabled: !_saving,
            decoration: const InputDecoration(
              labelText: 'Check number or reference (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            enabled: !_saving,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Notes (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: Text(_saving ? 'Saving…' : 'Record payment'),
      ),
    ],
  );
}

class _BreedPaybackConventionAllocationDialog extends StatefulWidget {
  const _BreedPaybackConventionAllocationDialog({
    required this.clubId,
    required this.availableFundByBreed,
    required this.existingAllocations,
    this.seasonId,
  });

  final String clubId;
  final String? seasonId;
  final Map<String, int> availableFundByBreed;
  final List<_BreedPaybackConventionAllocation> existingAllocations;

  @override
  State<_BreedPaybackConventionAllocationDialog> createState() =>
      _BreedPaybackConventionAllocationDialogState();
}

class _BreedPaybackConventionAllocationDialogState
    extends State<_BreedPaybackConventionAllocationDialog> {
  final _supabase = Supabase.instance.client;
  String? _breed;
  List<_ConventionAwardPlanRow> _rows = [];
  bool _saving = false;
  String? _error;

  static const _awardLabels = {
    'best_of_breed': 'Best of Breed (BOB)',
    'best_opposite_sex_breed': 'Best Opposite Sex of Breed (BOSB)',
    'best_of_variety': 'Best of Variety (BOV)',
    'best_opposite_sex_variety': 'Best Opposite Sex of Variety (BOSV)',
    'best_of_group': 'Best of Group (BOG)',
    'best_opposite_sex_group': 'Best Opposite Sex of Group (BOSG)',
    'custom': 'Custom convention award',
  };

  @override
  void initState() {
    super.initState();
    final breeds = _breeds;
    _breed = breeds.isEmpty ? null : breeds.first;
    _loadRowsForBreed();
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  String _key(String value) => value.trim().toLowerCase();

  bool _isCurrentSeason(_BreedPaybackConventionAllocation item) =>
      item.seasonId == widget.seasonId;

  List<_BreedPaybackConventionAllocation> _existingForBreed(String breed) =>
      widget.existingAllocations
          .where(
            (item) => _isCurrentSeason(item) && _key(item.breed) == _key(breed),
          )
          .toList();

  int _unplannedCentsForBreed(String breed) {
    for (final entry in widget.availableFundByBreed.entries) {
      if (_key(entry.key) == _key(breed)) return entry.value;
    }
    return 0;
  }

  int _usableCentsForBreed(String breed) =>
      _unplannedCentsForBreed(breed) +
      _existingForBreed(
        breed,
      ).fold<int>(0, (total, item) => total + item.amountCents);

  List<String> get _breeds {
    final values =
        <String>{
            ...widget.availableFundByBreed.keys,
            ...widget.existingAllocations
                .where(_isCurrentSeason)
                .map((item) => item.breed),
          }.where((breed) {
            return _unplannedCentsForBreed(breed) > 0 ||
                _existingForBreed(breed).isNotEmpty;
          }).toList()
          ..sort();
    return values;
  }

  void _loadRowsForBreed() {
    for (final row in _rows) {
      row.dispose();
    }
    final existing = _breed == null
        ? const <_BreedPaybackConventionAllocation>[]
        : _existingForBreed(_breed!);
    _rows = existing.map(_ConventionAwardPlanRow.fromAllocation).toList();
    if (_rows.isEmpty) _rows.add(_ConventionAwardPlanRow());
  }

  void _changeBreed(String? value) {
    if (value == null || value == _breed) return;
    setState(() {
      _breed = value;
      _error = null;
      _loadRowsForBreed();
    });
  }

  bool _isBlank(_ConventionAwardPlanRow row) =>
      row.amount.text.trim().isEmpty &&
      row.detail.text.trim().isEmpty &&
      row.notes.text.trim().isEmpty &&
      row.awardType == 'best_of_breed';

  int _cents(_ConventionAwardPlanRow row) =>
      ((double.tryParse(row.amount.text.trim()) ?? 0) * 100).round();

  Future<void> _save() async {
    if (_breed == null) {
      setState(() => _error = 'Choose a breed fund before saving the plan.');
      return;
    }
    final populated = _rows.where((row) => !_isBlank(row)).toList();
    for (final row in populated) {
      if (_cents(row) <= 0) {
        setState(
          () => _error = 'Every award row needs an amount greater than zero.',
        );
        return;
      }
      if (row.awardType == 'custom' && row.detail.text.trim().isEmpty) {
        setState(() => _error = 'Add a detail for every custom award row.');
        return;
      }
    }
    final planned = populated.fold<int>(0, (total, row) => total + _cents(row));
    final available = _usableCentsForBreed(_breed!);
    if (planned > available) {
      setState(
        () => _error =
            'The plan is more than this breed’s available fund of '
            '\$${(available / 100).toStringAsFixed(2)}.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final table = _supabase.from(
        'club_sweepstakes_breed_payback_convention_allocations',
      );
      final retainedIds = populated
          .map((row) => row.id)
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet();
      for (final old in _existingForBreed(_breed!)) {
        if (old.id.isNotEmpty && !retainedIds.contains(old.id)) {
          await table.delete().eq('id', old.id);
        }
      }
      for (final row in populated) {
        final values = <String, dynamic>{
          'award_type': row.awardType,
          'award_detail': row.detail.text.trim().isEmpty
              ? null
              : row.detail.text.trim(),
          'amount_cents': _cents(row),
          'notes': row.notes.text.trim().isEmpty ? null : row.notes.text.trim(),
        };
        if (row.id != null && row.id!.isNotEmpty) {
          await table.update(values).eq('id', row.id!);
        } else {
          await table.insert({
            ...values,
            'club_id': widget.clubId,
            'season_id': widget.seasonId,
            'breed': _breed,
            'created_by': _supabase.auth.currentUser?.id,
          });
        }
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Unable to save the convention award plan: $error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final breeds = _breeds;
    final available = _breed == null ? 0 : _usableCentsForBreed(_breed!);
    return AlertDialog(
      title: const Text('Plan convention awards'),
      content: SizedBox(
        width: 1060,
        height: 610,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Plan the collected breed fund in rows. You can edit or remove earlier rows here; this does not send a payment or change sweepstakes standings.',
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _breed,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Breed fund',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final breed in breeds)
                  DropdownMenuItem(
                    value: breed,
                    child: Text(
                      '$breed • \$${(_usableCentsForBreed(breed) / 100).toStringAsFixed(2)} available',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: _saving ? null : _changeBreed,
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 12),
              child: Text(
                '\$${(available / 100).toStringAsFixed(2)} available for this breed, including any rows already planned below.',
              ),
            ),
            const Divider(),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  SizedBox(width: 255, child: Text('Convention award')),
                  SizedBox(width: 12),
                  SizedBox(width: 185, child: Text('Detail (optional)')),
                  SizedBox(width: 12),
                  SizedBox(width: 135, child: Text('Amount')),
                  SizedBox(width: 12),
                  Expanded(child: Text('Notes (optional)')),
                  SizedBox(width: 48),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                itemCount: _rows.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final row = _rows[index];
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 255,
                        child: DropdownButtonFormField<String>(
                          value: row.awardType,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: [
                            for (final entry in _awardLabels.entries)
                              DropdownMenuItem(
                                value: entry.key,
                                child: Text(
                                  entry.value,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: _saving
                              ? null
                              : (value) => setState(
                                  () =>
                                      row.awardType = value ?? 'best_of_breed',
                                ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 185,
                        child: TextField(
                          controller: row.detail,
                          enabled: !_saving,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 135,
                        child: TextField(
                          controller: row.amount,
                          enabled: !_saving,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            prefixText: '\$',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: row.notes,
                          enabled: !_saving,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 48,
                        child: IconButton(
                          tooltip: 'Remove award row',
                          onPressed: _saving
                              ? null
                              : () => setState(() {
                                  final removed = _rows.removeAt(index);
                                  removed.dispose();
                                  if (_rows.isEmpty) {
                                    _rows.add(_ConventionAwardPlanRow());
                                  }
                                }),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _saving
                    ? null
                    : () =>
                          setState(() => _rows.add(_ConventionAwardPlanRow())),
                icon: const Icon(Icons.add),
                label: const Text('Add award row'),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Save award plan'),
        ),
      ],
    );
  }
}

class _ConventionAwardPlanRow {
  _ConventionAwardPlanRow({
    this.id,
    this.awardType = 'best_of_breed',
    String detail = '',
    String amount = '',
    String notes = '',
  }) : detail = TextEditingController(text: detail),
       amount = TextEditingController(text: amount),
       notes = TextEditingController(text: notes);

  factory _ConventionAwardPlanRow.fromAllocation(
    _BreedPaybackConventionAllocation allocation,
  ) => _ConventionAwardPlanRow(
    id: allocation.id,
    awardType: allocation.awardType,
    detail: allocation.awardDetail ?? '',
    amount: (allocation.amountCents / 100).toStringAsFixed(2),
    notes: allocation.notes ?? '',
  );

  final String? id;
  String awardType;
  final TextEditingController detail;
  final TextEditingController amount;
  final TextEditingController notes;

  void dispose() {
    detail.dispose();
    amount.dispose();
    notes.dispose();
  }
}

class _LockedAddOnState extends StatelessWidget {
  const _LockedAddOnState({required this.clubName, required this.onRefresh});

  final String clubName;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 34,
                    backgroundColor: scheme.primaryContainer,
                    foregroundColor: scheme.onPrimaryContainer,
                    child: const Icon(Icons.lock_outline, size: 34),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Sweepstakes Add-on Required',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '$clubName does not currently have the Sweepstakes Add-on enabled.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'This add-on enables seasons, divisions, standings, manual adjustments, and RingMaster Show result imports.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: onRefresh,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh Add-on Status'),
                  ),
                ],
              ),
            ),
          ),
        ),
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
                    const PopupMenuItem(
                      value: 'edit',
                      child: Text('Edit Season'),
                    ),
                    if (onActivate != null)
                      const PopupMenuItem(
                        value: 'active',
                        child: Text('Activate'),
                      ),
                    if (onFinalize != null)
                      const PopupMenuItem(
                        value: 'finalized',
                        child: Text('Finalize'),
                      ),
                    if (onArchive != null)
                      const PopupMenuItem(
                        value: 'archived',
                        child: Text('Archive'),
                      ),
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
  const _StandingsTable({required this.standings, required this.onAdjust});

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
                  DataCell(
                    Text(_numberText(standings[index].pointsFromResults)),
                  ),
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

class _AwardBoardCard extends StatelessWidget {
  const _AwardBoardCard({required this.board, required this.entries});

  final _SweepstakesAwardBoard board;
  final List<_SweepstakesAwardBoardEntry> entries;

  @override
  Widget build(BuildContext context) {
    final groupByBreed = board.grouping == 'breed';
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              board.name,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 2),
            Text(
              'Active members only${board.residencyLabel} • Top ${board.topN}',
            ),
            const SizedBox(height: 10),
            if (entries.isEmpty)
              const Text(
                'No active members with applied points are eligible for this award board yet.',
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: [
                    const DataColumn(label: Text('Rank')),
                    if (groupByBreed) const DataColumn(label: Text('Breed')),
                    const DataColumn(label: Text('Exhibitor')),
                    const DataColumn(label: Text('Membership')),
                    const DataColumn(label: Text('Points')),
                  ],
                  rows: [
                    for (final entry in entries)
                      DataRow(
                        cells: [
                          DataCell(Text('${entry.rank}')),
                          if (groupByBreed) DataCell(Text(entry.breed ?? '—')),
                          DataCell(Text(entry.exhibitorName)),
                          DataCell(Text(entry.membershipTypeName ?? '—')),
                          DataCell(Text(_numberText(entry.points))),
                        ],
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
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _ExpectedReportCard extends StatelessWidget {
  const _ExpectedReportCard({required this.report});

  final _ExpectedSweepstakesReport report;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final attention = report.needsAttention;
    final color = attention ? scheme.error : scheme.primary;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withAlpha(32),
          child: Icon(
            attention
                ? Icons.assignment_late_outlined
                : Icons.assignment_turned_in_outlined,
            color: color,
          ),
        ),
        title: Text(report.showName),
        subtitle: Text(
          '${_formatDate(report.showDate)} • Club ${report.clubSanctionNumber ?? '—'} • '
          'ARBA ${report.arbaSanctionNumber ?? '—'}\n'
          'Due ${_formatDate(report.dueDate)} • ${_titleCase(report.effectiveStatus)}'
          '${report.reminderCount == 0 ? '' : ' • ${report.reminderCount} reminder(s)'}',
        ),
        isThreeLine: true,
        trailing: Chip(label: Text(_titleCase(report.effectiveStatus))),
      ),
    );
  }
}

class _SweepstakesReportPackageCard extends StatelessWidget {
  const _SweepstakesReportPackageCard({
    required this.report,
    required this.onOpen,
  });

  final _SweepstakesReportPackage report;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = report.needsReview ? scheme.tertiary : scheme.primary;
    return Card(
      child: ListTile(
        onTap: onOpen,
        leading: CircleAvatar(
          backgroundColor: color.withAlpha(32),
          child: Icon(Icons.mark_email_unread_outlined, color: color),
        ),
        title: Text(report.subject ?? 'Untitled report package'),
        subtitle: Text(
          '${report.sender ?? 'Unknown sender'} • ${_formatDate(report.receivedAt)}\n'
          '${report.attachmentCount} attachment${report.attachmentCount == 1 ? '' : 's'} • ${_titleCase(report.status)}',
        ),
        isThreeLine: true,
        trailing: Chip(label: Text(_titleCase(report.status))),
      ),
    );
  }
}

class _ManualSweepstakesReportUploadDialog extends StatefulWidget {
  const _ManualSweepstakesReportUploadDialog({
    required this.clubId,
    required this.expectedReports,
    required this.documentStorageBucket,
  });

  final String clubId;
  final List<_ExpectedSweepstakesReport> expectedReports;
  final String? documentStorageBucket;

  @override
  State<_ManualSweepstakesReportUploadDialog> createState() =>
      _ManualSweepstakesReportUploadDialogState();
}

class _ManualSweepstakesReportUploadDialogState
    extends State<_ManualSweepstakesReportUploadDialog> {
  final _supabase = Supabase.instance.client;
  final _subjectController = TextEditingController();
  final _notesController = TextEditingController();
  List<PlatformFile> _files = const [];
  String? _expectedReportId;
  bool _archiveMode = false;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void dispose() {
    _subjectController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: true,
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'xlsx', 'xls', 'csv'],
      );
      if (result == null || !mounted) return;
      setState(
        () =>
            _files = result.files.where((file) => file.bytes != null).toList(),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Unable to select report files: $error');
    }
  }

  Future<String> _bucket() async {
    final existing = widget.documentStorageBucket;
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final response = await _supabase.functions.invoke(
      'provision-club-storage',
      body: {'club_id': widget.clubId},
    );
    final data = response.data;
    if (data is! Map) {
      throw Exception('Storage provisioning did not return a valid response.');
    }
    final bucket = data['document_storage_bucket']?.toString().trim();
    if (bucket == null || bucket.isEmpty) {
      throw Exception('A private club storage bucket is required.');
    }
    return bucket;
  }

  Future<void> _save() async {
    if (_isSaving) return;
    if (_files.isEmpty) {
      setState(() => _errorMessage = 'Choose at least one report file.');
      return;
    }
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    try {
      final bucket = await _bucket();
      if (_archiveMode) {
        var created = 0;
        for (final entry in _archiveGroups.entries) {
          await _savePackage(bucket, entry.value, entry.key, null);
          created++;
        }
        if (!mounted) return;
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$created report packages are ready for review.'),
          ),
        );
        return;
      }
      await _savePackage(
        bucket,
        _files,
        _nullIfBlank(_subjectController.text) ?? 'Manual report upload',
        _expectedReportId,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorMessage = 'Unable to upload the report package: $error';
      });
    }
  }

  Map<String, List<PlatformFile>> get _archiveGroups {
    final groups = <String, List<PlatformFile>>{};
    for (final file in _files) {
      final match = RegExp(
        r'_(OPEN|YOUTH)_([A-F])(?:\\.pdf)?$',
        caseSensitive: false,
      ).firstMatch(file.name);
      final key = match == null
          ? 'Unsorted reports'
          : '${match.group(1)!.toUpperCase()} ${match.group(2)!.toUpperCase()}';
      (groups[key] ??= []).add(file);
    }
    return groups;
  }

  Future<void> _savePackage(
    String bucket,
    List<PlatformFile> files,
    String subject,
    String? expectedReportId,
  ) async {
    final freeDraft = await _buildFreeDraft(files);
    final rows = await _supabase
        .from('club_sweepstakes_report_packages')
        .insert({
          'club_id': widget.clubId,
          'expected_report_id': expectedReportId,
          'source_type': 'manual',
          'source_subject': subject,
          'source_received_at': DateTime.now().toIso8601String(),
          'review_notes': _nullIfBlank(_notesController.text),
          'status': expectedReportId == null ? 'unmatched' : 'needs_review',
          'extracted_summary': freeDraft,
        })
        .select('id');
    final packageId = rows.first['id'].toString();
    final manifest = <Map<String, dynamic>>[];
    for (final file in files) {
      final bytes = file.bytes;
      if (bytes == null) {
        continue;
      }
      final name = _safeFileName(file.name);
      final storagePath = 'sweepstakes-reports/$packageId/attachments/$name';
      await _supabase.storage
          .from(bucket)
          .uploadBinary(
            storagePath,
            bytes,
            fileOptions: FileOptions(
              contentType: _contentType(file.name),
              upsert: false,
            ),
          );
      manifest.add({
        'file_name': file.name,
        'content_type': _contentType(file.name),
        'size': bytes.length,
        'storage_path': storagePath,
      });
    }
    if (manifest.isEmpty) {
      throw Exception('None of the selected files could be uploaded.');
    }
    await _supabase
        .from('club_sweepstakes_report_packages')
        .update({
          'attachment_manifest': manifest,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', packageId);
    if (expectedReportId != null) {
      await _supabase
          .from('club_sweepstakes_expected_reports')
          .update({
            'status': 'needs_review',
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', expectedReportId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Upload Report Package'),
      content: SizedBox(
        width: 680,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_errorMessage != null) ...[
                Text(
                  _errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                const SizedBox(height: 12),
              ],
              OutlinedButton.icon(
                onPressed: _isSaving ? null : _pickFiles,
                icon: const Icon(Icons.upload_file_outlined),
                label: Text(
                  _files.isEmpty
                      ? 'Choose report files'
                      : 'Change report files',
                ),
              ),
              if (_files.isNotEmpty) ...[
                const SizedBox(height: 8),
                if (_archiveMode)
                  for (final entry in _archiveGroups.entries)
                    Text('• ${entry.key}: ${entry.value.length} files')
                else
                  for (final file in _files) Text('• ${file.name}'),
              ],
              CheckboxListTile(
                value: _archiveMode,
                onChanged: _isSaving
                    ? null
                    : (value) => setState(() => _archiveMode = value ?? false),
                title: const Text('Sort selected files into report packages'),
                subtitle: const Text(
                  'Groups RingMaster filenames by OPEN/YOUTH and show letter. Every package remains in review.',
                ),
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _subjectController,
                decoration: const InputDecoration(
                  labelText: 'Package title',
                  hintText:
                      'For example: Indiana State Mini Rex — October 18, 2025',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String?>(
                initialValue: _expectedReportId,
                decoration: const InputDecoration(
                  labelText: 'Match to expected sanction report',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Leave unmatched for now'),
                  ),
                  for (final expected in widget.expectedReports)
                    DropdownMenuItem<String?>(
                      value: expected.id,
                      child: Text(
                        '${expected.showName} — ${_formatDate(expected.showDate)}',
                      ),
                    ),
                ],
                onChanged: _isSaving
                    ? null
                    : (value) => setState(() => _expectedReportId = value),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _notesController,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Staff notes (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Uploads are private and always enter review. They cannot update standings automatically.',
              ),
            ],
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
          icon: const Icon(Icons.upload_outlined),
          label: Text(_isSaving ? 'Uploading...' : 'Upload for review'),
        ),
      ],
    );
  }

  String? _nullIfBlank(String value) =>
      value.trim().isEmpty ? null : value.trim();
  String _safeFileName(String value) =>
      value.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  String _contentType(String value) {
    final name = value.toLowerCase();
    if (name.endsWith('.pdf')) return 'application/pdf';
    if (name.endsWith('.csv')) return 'text/csv';
    return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
  }

  Future<Map<String, dynamic>> _buildFreeDraft(List<PlatformFile> files) async {
    final parsedFiles = <Map<String, dynamic>>[];
    final allText = StringBuffer();
    for (final file in files) {
      if (!file.name.toLowerCase().endsWith('.pdf') || file.bytes == null) {
        continue;
      }
      try {
        final text = await _FreeSweepstakesParser.extractPdfText(
          file.bytes!,
          file.name,
        );
        if (text.trim().isNotEmpty) {
          allText.writeln(text);
          parsedFiles.add({
            'file_name': file.name,
            'text_found': true,
            'characters': text.length,
          });
        } else {
          parsedFiles.add({'file_name': file.name, 'text_found': false});
        }
      } catch (_) {
        parsedFiles.add({'file_name': file.name, 'text_found': false});
      }
    }
    return _FreeSweepstakesParser.buildDraft(
      allText.toString(),
      parsedFiles: parsedFiles,
    );
  }
}

class _FreeSweepstakesParser {
  static const _standardAddressCutoffWords = <String>{
    'st',
    'street',
    'rd',
    'road',
    'dr',
    'drive',
    'ave',
    'avenue',
    'blvd',
    'ln',
    'hwy',
    'highway',
    'trail',
    'trl',
    'ct',
    'court',
    'way',
    'pkwy',
    'parkway',
    'cir',
    'circle',
    'po',
    'box',
    'county',
    'lot',
    'apt',
    'unit',
    'us',
    'state',
    'township',
  };

  static Future<String> extractPdfText(
    Uint8List bytes,
    String sourceName,
  ) async {
    final document = await PdfDocument.openData(bytes, sourceName: sourceName);
    try {
      final pages = <String>[];
      for (final page in document.pages) {
        final text = await page.loadText();
        if (text != null && text.fullText.trim().isNotEmpty) {
          pages.add(text.fullText);
        }
      }
      return pages.join('\n');
    } finally {
      await document.dispose();
    }
  }

  static Map<String, dynamic> buildDraft(
    String rawText, {
    required List<Map<String, dynamic>> parsedFiles,
  }) {
    final normalized = rawText.replaceAll(RegExp(r'\s+'), ' ').trim();
    final lower = normalized.toLowerCase();
    final source = lower.contains('easy2show')
        ? 'easy2show'
        : lower.contains('ringmaster show') ||
              lower.contains('generated by ringmaster show')
        ? 'ringmaster_show'
        : lower.contains('grandchampionsoftware.com') ||
              lower.contains('grand champion software') ||
              lower.contains('specialty club points report')
        ? 'grand_champion'
        : lower.contains('details by breed')
        ? 'likely_show_results'
        : 'unknown';
    final reportType = lower.contains('details by breed')
        ? 'details_by_breed'
        : lower.contains('exhibitor by breed') ||
              lower.contains('exhibitors by breed')
        ? 'exhibitor_by_breed'
        : lower.contains('ringmaster show sweepstakes report')
        ? 'sweepstakes_report'
        : lower.contains('breed results detail report')
        ? 'breed_results_detail'
        : lower.contains('specialty club points report')
        ? 'specialty_club_points'
        : lower.contains('sweepstakes report')
        ? 'sweepstakes_report'
        : lower.contains('breed results')
        ? 'breed_results_detail'
        : 'unknown';
    final dateMatch = RegExp(
      r'(?:show\s+date|date)\s*[:#-]?\s*(\d{1,2}[/-]\d{1,2}[/-]\d{2,4})',
      caseSensitive: false,
    ).firstMatch(normalized);
    final sanctionMatch = RegExp(
      r'(?:arba\s+)?sanction(?:\s+(?:number|no\.?))?\s*[:#-]?\s*([A-Z0-9-]{3,})',
      caseSensitive: false,
    ).firstMatch(normalized);
    final flags = <String>[];
    if (rawText.trim().isEmpty) {
      flags.add('No selectable PDF text found. Staff review is required.');
    }
    if (source == 'unknown') {
      flags.add('Unknown report source or layout. Staff review is required.');
    }
    if (reportType == 'unknown') {
      flags.add('Report type could not be identified confidently.');
    }
    final confidence = source == 'unknown' || reportType == 'unknown'
        ? 'low'
        : sanctionMatch == null && dateMatch == null
        ? 'medium'
        : 'high';
    return {
      'parser': 'rule_based_v1',
      'source_guess': source,
      'report_type_guess': reportType,
      'confidence': confidence,
      'show_date_guess': dateMatch?.group(1),
      'sanction_number_guess': sanctionMatch?.group(1),
      'parsed_files': parsedFiles,
      'flags': flags,
      'raw_text_excerpt': normalized.length > 2000
          ? normalized.substring(0, 2000)
          : normalized,
    };
  }

  static List<_Easy2ShowTotal> parseEasy2ShowExhibitorTotals(
    String text, {
    List<_SweepstakesRule> rules = const [],
  }) {
    final lines = text
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final heading = lines.indexWhere(
      (line) => RegExp(
        r'exhibitor\s*/?\s*address',
        caseSensitive: false,
      ).hasMatch(line),
    );
    if (heading < 0) return const [];
    final breed = heading > 0 ? lines[heading - 1] : null;
    final ignored = RegExp(
      r'^(animals|total|# class|# variety|# group|# bob|# b4c|# bis|fur|wool|show report|report date|show date|event |sponsoring |classification|show:|type:|specialty:|arba sanction|add.t sanction)',
      caseSensitive: false,
    );
    final totalRows = <_Easy2ShowTotal>[];
    var index = heading + 1;
    while (index < lines.length) {
      final candidate = lines[index];
      final separateTotal = RegExp(
        r'^(\d+)\s+(\d+|-)\s+(\d+|-)(?:\s+[-\d]+)*$',
      ).firstMatch(candidate);
      if (separateTotal != null && index > heading + 1) {
        final previousLine = lines[index - 1];
        final previousLineLooksLikeName =
            previousLine.contains(RegExp(r'[A-Za-z]')) &&
            !previousLine.contains(',') &&
            !ignored.hasMatch(previousLine) &&
            previousLine.length < 70;
        final sourcePoints = num.tryParse(separateTotal.group(2)!);
        if (previousLineLooksLikeName &&
            sourcePoints != null &&
            sourcePoints > 0) {
          totalRows.add(
            _Easy2ShowTotal(
              name: _applyExhibitorRules(previousLine, rules),
              breed: breed,
              sourcePoints: sourcePoints,
            ),
          );
        }
        index++;
        continue;
      }
      final inlineTotal = RegExp(
        r'^([A-Za-z].+?)\s+(\d+)\s+(\d+|-)\s+(\d+|-)(?:\s+[-\d]+)*$',
      ).firstMatch(candidate);
      if (inlineTotal != null) {
        final sourcePoints = num.tryParse(inlineTotal.group(3)!);
        if (sourcePoints != null && sourcePoints > 0) {
          totalRows.add(
            _Easy2ShowTotal(
              name: _applyExhibitorRules(inlineTotal.group(1)!, rules),
              breed: breed,
              sourcePoints: sourcePoints,
            ),
          );
        }
        index++;
        continue;
      }
      final isName =
          candidate.contains(RegExp(r'[A-Za-z]')) &&
          !candidate.contains(',') &&
          !ignored.hasMatch(candidate) &&
          candidate.length < 70;
      if (!isName) {
        index++;
        continue;
      }
      final numbers = <num>[];
      var cursor = index + 1;
      while (cursor < lines.length && cursor <= index + 12) {
        final value = num.tryParse(lines[cursor].replaceAll(',', ''));
        if (value != null) numbers.add(value);
        if (numbers.length >= 3) break;
        cursor++;
      }
      if (numbers.length >= 3) {
        totalRows.add(
          _Easy2ShowTotal(
            name: _applyExhibitorRules(candidate, rules),
            breed: breed,
            sourcePoints: numbers[1],
          ),
        );
        index = cursor + 1;
      } else {
        index++;
      }
    }
    final seen = <String>{};
    return totalRows
        .where(
          (row) => row.sourcePoints > 0 && seen.add(row.name.toLowerCase()),
        )
        .toList();
  }

  static String _applyExhibitorRules(
    String originalName,
    List<_SweepstakesRule> rules,
  ) {
    var cleanedName = originalName.replaceAll(RegExp(r'\s+'), ' ').trim();
    final addressWords = {
      ..._standardAddressCutoffWords,
      ...rules
          .where((rule) => rule.type == 'address_stop_word')
          .map((rule) => rule.matchValue.toLowerCase()),
    };
    if (addressWords.isNotEmpty) {
      final keptWords = <String>[];
      for (final word in cleanedName.split(' ')) {
        final comparison = word.toLowerCase().replaceAll(
          RegExp(r'[^a-z0-9]'),
          '',
        );
        if (addressWords.contains(comparison)) break;
        if (RegExp(r'^\d').hasMatch(word)) break;
        keptWords.add(word);
      }
      cleanedName = keptWords.join(' ').trim();
    }

    final comparable = cleanedName
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();
    final words = comparable
        .split(' ')
        .where((word) => word.isNotEmpty)
        .toSet();
    final nameRules =
        rules
            .where(
              (rule) =>
                  rule.replacementValue != null &&
                  (rule.type == 'name_alias' || rule.type == 'name_pattern'),
            )
            .toList()
          ..sort(
            (a, b) => b.matchValue
                .split(' ')
                .length
                .compareTo(a.matchValue.split(' ').length),
          );
    for (final rule in nameRules) {
      final ruleWords = rule.matchValue
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
          .split(' ')
          .where((word) => word.isNotEmpty)
          .toList();
      final exact = rule.config['match_mode'] == 'exact';
      final matches = exact
          ? comparable == ruleWords.join(' ')
          : ruleWords.every(words.contains);
      if (matches) return rule.replacementValue!;
    }
    return cleanedName.isEmpty ? originalName : cleanedName;
  }
}

class _SweepstakesRule {
  const _SweepstakesRule({
    required this.type,
    required this.matchValue,
    required this.replacementValue,
    required this.config,
  });

  final String type;
  final String matchValue;
  final String? replacementValue;
  final Map<String, dynamic> config;

  factory _SweepstakesRule.fromJson(Map<String, dynamic> json) =>
      _SweepstakesRule(
        type: json['rule_type']?.toString() ?? '',
        matchValue: json['match_value']?.toString() ?? '',
        replacementValue: json['replacement_value']?.toString(),
        config: Map<String, dynamic>.from(json['rule_config'] ?? const {}),
      );
}

class _Easy2ShowTotal {
  const _Easy2ShowTotal({
    required this.name,
    required this.sourcePoints,
    this.breed,
  });

  final String name;
  final String? breed;
  final num sourcePoints;
}

class _SweepstakesReportReviewDialog extends StatefulWidget {
  const _SweepstakesReportReviewDialog({
    required this.clubId,
    required this.report,
    required this.expectedReports,
    required this.divisions,
    required this.documentStorageBucket,
  });

  final String clubId;
  final _SweepstakesReportPackage report;
  final List<_ExpectedSweepstakesReport> expectedReports;
  final List<_SweepstakesDivision> divisions;
  final String? documentStorageBucket;

  @override
  State<_SweepstakesReportReviewDialog> createState() =>
      _SweepstakesReportReviewDialogState();
}

class _SweepstakesReportReviewDialogState
    extends State<_SweepstakesReportReviewDialog> {
  final _supabase = Supabase.instance.client;
  late final TextEditingController _notesController;
  late String? _expectedReportId;
  late String _status;
  bool _isSaving = false;
  bool _isCreatingDraft = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _notesController = TextEditingController(
      text: widget.report.reviewNotes ?? '',
    );
    _expectedReportId = widget.report.expectedReportId;
    _status = widget.report.status;
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _openPrivateFile(String path) async {
    final bucket = widget.documentStorageBucket;
    if (bucket == null || bucket.isEmpty) {
      setState(
        () => _errorMessage =
            'This club does not have private file storage configured.',
      );
      return;
    }
    try {
      final url = await _supabase.storage
          .from(bucket)
          .createSignedUrl(path, 600);
      final opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) throw Exception('The file could not be opened.');
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _errorMessage = 'Unable to open the private report file: $error',
      );
    }
  }

  Future<void> _save() async {
    if (_isSaving) return;
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    try {
      await _supabase
          .from('club_sweepstakes_report_packages')
          .update({
            'expected_report_id': _expectedReportId,
            'status': _status,
            'review_notes': _nullIfBlank(_notesController.text),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', widget.report.id);
      if (_expectedReportId != null && _status != 'rejected') {
        await _supabase
            .from('club_sweepstakes_expected_reports')
            .update({
              'status': 'needs_review',
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', _expectedReportId!);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorMessage = 'Unable to save the report review: $error';
      });
    }
  }

  _ExpectedSweepstakesReport? get _matchedExpectedReport {
    for (final report in widget.expectedReports) {
      if (report.id == _expectedReportId) return report;
    }
    return null;
  }

  Future<void> _createOrOpenResultDraft() async {
    if (_isCreatingDraft || _isSaving) return;
    final expected = _matchedExpectedReport;
    final seasonId = widget.report.seasonId ?? expected?.seasonId;
    if (seasonId == null) {
      setState(
        () => _errorMessage =
            'Match this package to an expected report (with a season) before creating a results draft.',
      );
      return;
    }
    setState(() {
      _isCreatingDraft = true;
      _errorMessage = null;
    });
    try {
      await _supabase
          .from('club_sweepstakes_report_packages')
          .update({
            'expected_report_id': _expectedReportId,
            'status': 'needs_review',
            'review_notes': _nullIfBlank(_notesController.text),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', widget.report.id);
      final result = await _supabase
          .from('club_sweepstakes_result_imports')
          .upsert({
            'club_id': widget.clubId,
            'report_package_id': widget.report.id,
            'expected_report_id': _expectedReportId,
            'season_id': seasonId,
            'source_report_type': widget.report.freeDraft?['report_type_guess']
                ?.toString(),
            'status': 'draft',
          }, onConflict: 'report_package_id')
          .select()
          .single();
      if (!mounted) return;
      final resultsApplied = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _SweepstakesResultDraftDialog(
          clubId: widget.clubId,
          import: _SweepstakesResultImport.fromJson(result),
          report: widget.report,
          documentStorageBucket: widget.documentStorageBucket,
          divisions: widget.divisions
              .where((division) => division.seasonId == seasonId)
              .toList(),
        ),
      );
      if (resultsApplied == true && mounted) {
        Navigator.of(context).pop(true);
        return;
      }
      if (mounted) setState(() => _isCreatingDraft = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isCreatingDraft = false;
        _errorMessage = 'Unable to create the results draft: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    return AlertDialog(
      title: const Text('Review Report Package'),
      content: SizedBox(
        width: 720,
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
              Text(
                report.subject ?? 'Untitled report package',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                '${report.sender ?? 'Unknown sender'} • ${_formatDate(report.receivedAt)}',
              ),
              const SizedBox(height: 16),
              const Text(
                'Original files',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              if (report.storagePath != null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.email_outlined),
                  title: const Text('Original forwarded email'),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => _openPrivateFile(report.storagePath!),
                ),
              for (final file in report.attachments)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.picture_as_pdf_outlined),
                  title: Text(file.fileName),
                  subtitle: file.contentType == null
                      ? null
                      : Text(file.contentType!),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: file.storagePath == null
                      ? null
                      : () => _openPrivateFile(file.storagePath!),
                ),
              if (report.storagePath == null && report.attachments.isEmpty)
                const Text('No stored files are attached to this package.'),
              if (report.freeDraft != null) ...[
                const Divider(height: 28),
                const Text(
                  'Report reading summary',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  '${_titleCase(report.freeDraft!['source_guess']?.toString() ?? 'unknown')} • '
                  '${_titleCase(report.freeDraft!['report_type_guess']?.toString() ?? 'unknown')} • '
                  '${_titleCase(report.freeDraft!['confidence']?.toString() ?? 'low')} confidence',
                ),
                if (report.freeDraft!['show_date_guess'] != null)
                  Text(
                    'Show date found: ${report.freeDraft!['show_date_guess']}',
                  ),
                if (report.freeDraft!['sanction_number_guess'] != null)
                  Text(
                    'Sanction found: ${report.freeDraft!['sanction_number_guess']}',
                  ),
                for (final flag in _stringList(report.freeDraft!['flags']))
                  Text('• $flag'),
              ],
              const Divider(height: 28),
              DropdownButtonFormField<String?>(
                initialValue: _expectedReportId,
                decoration: const InputDecoration(
                  labelText: 'Match to expected sanction report',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Leave unmatched for now'),
                  ),
                  for (final expected in widget.expectedReports)
                    DropdownMenuItem<String?>(
                      value: expected.id,
                      child: Text(
                        '${expected.showName} — ${_formatDate(expected.showDate)}',
                      ),
                    ),
                ],
                onChanged: _isSaving
                    ? null
                    : (value) => setState(() => _expectedReportId = value),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _status,
                decoration: const InputDecoration(
                  labelText: 'Review status',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'pending',
                    child: Text('Pending review'),
                  ),
                  DropdownMenuItem(
                    value: 'unmatched',
                    child: Text('Unmatched'),
                  ),
                  DropdownMenuItem(
                    value: 'needs_review',
                    child: Text('Needs review'),
                  ),
                  DropdownMenuItem(
                    value: 'reconciled',
                    child: Text('Matched — ready for extraction'),
                  ),
                  DropdownMenuItem(
                    value: 'processed',
                    child: Text('Processed — standings updated'),
                  ),
                  DropdownMenuItem(
                    value: 'rejected',
                    child: Text('Not a sweepstakes report'),
                  ),
                ],
                onChanged: _isSaving
                    ? null
                    : (value) => value == null
                          ? null
                          : setState(() => _status = value),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _notesController,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'Staff review notes',
                  hintText:
                      'Why it matches, what is missing, or why it should be rejected',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Saving this review does not change any standings or points. Extraction and final processing are separate approval steps.',
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        OutlinedButton.icon(
          onPressed: _isSaving || _isCreatingDraft
              ? null
              : _createOrOpenResultDraft,
          icon: const Icon(Icons.fact_check_outlined),
          label: Text(_isCreatingDraft ? 'Opening...' : 'Create results draft'),
        ),
        FilledButton.icon(
          onPressed: _isSaving ? null : _save,
          icon: const Icon(Icons.save_outlined),
          label: Text(_isSaving ? 'Saving...' : 'Save review'),
        ),
      ],
    );
  }

  String? _nullIfBlank(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  List<String> _stringList(Object? value) {
    return value is List ? value.whereType<String>().toList() : const [];
  }
}

class _SweepstakesResultDraftDialog extends StatefulWidget {
  const _SweepstakesResultDraftDialog({
    required this.clubId,
    required this.import,
    required this.report,
    required this.documentStorageBucket,
    required this.divisions,
  });

  final String clubId;
  final _SweepstakesResultImport import;
  final _SweepstakesReportPackage report;
  final String? documentStorageBucket;
  final List<_SweepstakesDivision> divisions;

  @override
  State<_SweepstakesResultDraftDialog> createState() =>
      _SweepstakesResultDraftDialogState();
}

class _SweepstakesResultDraftDialogState
    extends State<_SweepstakesResultDraftDialog> {
  final _supabase = Supabase.instance.client;
  List<_SweepstakesResultImportRow> _rows = const [];
  List<_SweepstakesRule> _activeRules = const [];
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final response = await _supabase
          .from('club_sweepstakes_result_import_rows')
          .select()
          .eq('import_id', widget.import.id)
          .order('created_at');
      final rulesResponse = await _supabase
          .from('club_sweepstakes_parser_rules')
          .select('rule_type, match_value, replacement_value, rule_config')
          .eq('club_id', widget.clubId)
          .eq('is_active', true)
          .order('sort_order');
      if (!mounted) return;
      setState(() {
        _rows = (response as List)
            .map(
              (row) => _SweepstakesResultImportRow.fromJson(
                Map<String, dynamic>.from(row as Map),
              ),
            )
            .toList();
        _activeRules = (rulesResponse as List)
            .map(
              (rule) => _SweepstakesRule.fromJson(
                Map<String, dynamic>.from(rule as Map),
              ),
            )
            .toList();
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Unable to load result rows: $error';
        _isLoading = false;
      });
    }
  }

  Future<void> _addRow() async {
    final row = await showDialog<_SweepstakesResultImportRowDraft>(
      context: context,
      builder: (_) =>
          _SweepstakesResultRowEditorDialog(divisions: widget.divisions),
    );
    if (row == null || !mounted) return;
    setState(() => _isSaving = true);
    try {
      await _supabase.from('club_sweepstakes_result_import_rows').insert({
        'import_id': widget.import.id,
        'club_id': widget.clubId,
        'division_id': row.divisionId,
        'exhibitor_name': row.exhibitorName,
        'species': row.species,
        'breed': row.breed,
        'placement': row.placement,
        'source_points': row.sourcePoints,
        'calculated_points': row.calculatedPoints,
      });
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Unable to add result row: $error');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _readReportDraft() async {
    if (_isSaving) return;
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    try {
      final response = await _supabase.functions.invoke(
        'read-sweepstakes-report',
        body: {'import_id': widget.import.id},
      );
      final data = Map<String, dynamic>.from(response.data as Map? ?? const {});
      final added = data['rows_added'];
      if (added is! num || added <= 0) {
        throw Exception(
          'No rule-supported results could be safely identified.',
        );
      }
      await _load();
      if (!mounted) return;
      final breedCountsAdded = data['breed_counts_added'] as num? ?? 0;
      final breedCountsNote = data['breed_counts_note'] as String?;
      final sourceLabel = data['source_label'] as String? ?? 'Report';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            breedCountsAdded > 0
                ? '$sourceLabel: $breedCountsAdded breed ${breedCountsAdded == 1 ? 'count was' : 'counts were'} added to Show obligations.'
                : breedCountsNote ??
                      '$sourceLabel results draft is ready for review.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Unable to read the report draft: $error');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _setRowStatus(
    _SweepstakesResultImportRow row,
    String status,
  ) async {
    setState(() => _isSaving = true);
    try {
      await _supabase
          .from('club_sweepstakes_result_import_rows')
          .update({
            'status': status,
            'reviewed_at': DateTime.now().toIso8601String(),
          })
          .eq('id', row.id);
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Unable to update the row: $error');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _approveAllPendingRows() async {
    if (_isSaving) return;
    final pendingCount = _rows.where((row) => row.status == 'pending').length;
    if (pendingCount == 0) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Approve all pending results?'),
        content: Text(
          'This will approve all $pendingCount pending ${pendingCount == 1 ? 'result' : 'results'} in this draft. You can still reject or return an individual result to pending before applying the approved results.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.done_all),
            label: const Text('Approve all'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isSaving = true);
    try {
      await _supabase
          .from('club_sweepstakes_result_import_rows')
          .update({
            'status': 'approved',
            'reviewed_at': DateTime.now().toIso8601String(),
          })
          .eq('import_id', widget.import.id)
          .eq('status', 'pending');
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _errorMessage = 'Unable to approve all pending results: $error',
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _applyApprovedResults() async {
    if (_isSaving) return;
    final approvedCount = _rows.where((row) => row.status == 'approved').length;
    final unsettledCount = _rows
        .where((row) => row.status != 'approved' && row.status != 'rejected')
        .length;
    if (_rows.isEmpty || approvedCount == 0 || unsettledCount > 0) {
      setState(
        () => _errorMessage =
            'Approve or reject every result before applying this report.',
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Apply approved results?'),
        content: Text(
          'This will add $approvedCount approved ${approvedCount == 1 ? 'result' : 'results'} to the season standings using the calculated points shown here. This report cannot be applied twice.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Apply results'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    try {
      final response = await _supabase.rpc(
        'apply_club_sweepstakes_result_import',
        params: {'p_import_id': widget.import.id},
      );
      if (!mounted) return;
      final data = Map<String, dynamic>.from(response as Map? ?? const {});
      final applied = data['applied_rows'] as num? ?? approvedCount;
      final publishedLive = data['published_live'] == true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$applied ${applied == 1 ? 'result was' : 'results were'} added to standings.${publishedLive ? ' The live season standings were updated.' : ''}',
          ),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(
          () => _errorMessage = 'Unable to apply approved results: $error',
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _showCalculationBreakdown(
    _SweepstakesResultImportRow row,
  ) async {
    try {
      final response = await _supabase
          .from('club_sweepstakes_result_awards')
          .select()
          .eq('result_row_id', row.id)
          .order('created_at');
      if (!mounted) return;
      final awards = (response as List)
          .map(
            (award) => _SweepstakesResultAward.fromJson(
              Map<String, dynamic>.from(award as Map),
            ),
          )
          .toList();
      final sourcePoints = row.sourcePoints;
      final difference = sourcePoints == null
          ? null
          : sourcePoints - row.calculatedPoints;
      final hasDifference = difference != null && difference != 0;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('${row.exhibitorName}: point review'),
          content: SizedBox(
            width: 660,
            height: 560,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: hasDifference
                        ? Theme.of(dialogContext).colorScheme.errorContainer
                        : Theme.of(
                            dialogContext,
                          ).colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sourcePoints == null
                            ? 'No source total was supplied for this exhibitor.'
                            : 'Source total: ${_formatPoints(sourcePoints)} points',
                        style: Theme.of(dialogContext).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Your current rules calculate: ${_formatPoints(row.calculatedPoints)} points',
                      ),
                      if (difference != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          difference == 0
                              ? 'This matches the source total exactly.'
                              : difference > 0
                              ? '${_formatPoints(difference)} source points are not explained by the current rules.'
                              : '${_formatPoints(difference.abs())} more points are calculated than the source total.',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                      if (hasDifference) ...[
                        const SizedBox(height: 8),
                        const Text(
                          'The source report provides a total per exhibitor, not necessarily a point value for every individual award. Review the counted awards below to find a missing or incorrect rule.',
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Awards counted by your current rules',
                  style: Theme.of(dialogContext).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: awards.isEmpty
                      ? const Center(
                          child: Text(
                            'No detailed calculation is available for this row. Reread the report to create a detailed review.',
                            textAlign: TextAlign.center,
                          ),
                        )
                      : ListView.separated(
                          itemCount: awards.length,
                          separatorBuilder: (_, _) => const Divider(),
                          itemBuilder: (_, index) {
                            final award = awards[index];
                            final formula = award.shownCount == null
                                ? '${_formatPoints(award.pointsPerAward)} points'
                                : '${_formatPoints(award.pointsPerAward)} points × ${_formatPoints(award.shownCount)} shown = ${_formatPoints(award.calculatedPoints)} points';
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              isThreeLine: true,
                              title: Text(award.awardLabel),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(award.ruleLabel),
                                  Text(
                                    '$formula${award.breed == null ? '' : ' • ${award.breed}'}',
                                  ),
                                ],
                              ),
                              trailing: Text(
                                _formatPoints(award.calculatedPoints),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Unable to load the calculation: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final approved = _rows.where((row) => row.status == 'approved').length;
    final mismatches = _rows.where((row) => row.pointMismatch).length;
    final unsettled = _rows
        .where((row) => row.status != 'approved' && row.status != 'rejected')
        .length;
    final pending = _rows.where((row) => row.status == 'pending').length;
    final canApply = _rows.isNotEmpty && approved > 0 && unsettled == 0;
    return AlertDialog(
      title: const Text('Review Results Draft'),
      content: SizedBox(
        width: 860,
        height: 560,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${_rows.length} rows • $approved approved • $mismatches point mismatches',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Enter or correct the calculated points for each result. A difference from the source points is always flagged. Nothing here changes published standings.',
                  ),
                  if (_activeRules.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${_activeRules.length} active Sweepstakes Rules will be used when importing report totals.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _errorMessage!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Expanded(
                    child: _rows.isEmpty
                        ? const _InlineEmptyState(
                            title: 'No results added yet',
                            message:
                                'Use Add result to enter the verified results from the source report. Automated extraction can be added later without changing this approval flow.',
                          )
                        : ListView.separated(
                            itemCount: _rows.length,
                            separatorBuilder: (_, _) => const Divider(),
                            itemBuilder: (context, index) {
                              final row = _rows[index];
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(
                                  row.pointMismatch
                                      ? Icons.warning_amber_rounded
                                      : Icons.verified_outlined,
                                  color: row.pointMismatch
                                      ? Theme.of(context).colorScheme.error
                                      : null,
                                ),
                                title: Text(
                                  '${row.exhibitorName} — ${row.breed ?? 'Unspecified breed'}',
                                ),
                                subtitle: Text(
                                  'Placement ${row.placement ?? '—'} • Source ${_formatPoints(row.sourcePoints)} • Calculated ${_formatPoints(row.calculatedPoints)}${row.pointMismatch ? ' • MISMATCH' : ''}',
                                ),
                                onTap: () => _showCalculationBreakdown(row),
                                trailing: PopupMenuButton<String>(
                                  enabled: !_isSaving,
                                  onSelected: (value) =>
                                      _setRowStatus(row, value),
                                  itemBuilder: (_) => const [
                                    PopupMenuItem(
                                      value: 'approved',
                                      child: Text('Approve row'),
                                    ),
                                    PopupMenuItem(
                                      value: 'rejected',
                                      child: Text('Reject row'),
                                    ),
                                    PopupMenuItem(
                                      value: 'pending',
                                      child: Text('Return to pending'),
                                    ),
                                  ],
                                  child: Chip(
                                    label: Text(_titleCase(row.status)),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Close'),
        ),
        OutlinedButton.icon(
          onPressed: _isSaving ? null : _addRow,
          icon: const Icon(Icons.add),
          label: const Text('Add result'),
        ),
        OutlinedButton.icon(
          onPressed: _isSaving ? null : _readReportDraft,
          icon: const Icon(Icons.auto_awesome_outlined),
          label: const Text('Read report draft'),
        ),
        OutlinedButton.icon(
          onPressed: _isSaving || pending == 0 ? null : _approveAllPendingRows,
          icon: const Icon(Icons.done_all),
          label: Text('Approve all $pending pending'),
        ),
        FilledButton.icon(
          onPressed: _isSaving || !canApply ? null : _applyApprovedResults,
          icon: const Icon(Icons.check_circle_outline),
          label: Text(
            'Apply $approved approved ${approved == 1 ? 'result' : 'results'}',
          ),
        ),
      ],
    );
  }

  String _formatPoints(num? value) => value == null ? '—' : value.toString();
}

class _SweepstakesResultRowEditorDialog extends StatefulWidget {
  const _SweepstakesResultRowEditorDialog({required this.divisions});

  final List<_SweepstakesDivision> divisions;

  @override
  State<_SweepstakesResultRowEditorDialog> createState() =>
      _SweepstakesResultRowEditorDialogState();
}

class _SweepstakesResultRowEditorDialogState
    extends State<_SweepstakesResultRowEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  final _exhibitor = TextEditingController();
  final _species = TextEditingController();
  final _breed = TextEditingController();
  final _placement = TextEditingController();
  final _sourcePoints = TextEditingController();
  final _calculatedPoints = TextEditingController();
  String? _divisionId;

  @override
  void dispose() {
    _exhibitor.dispose();
    _species.dispose();
    _breed.dispose();
    _placement.dispose();
    _sourcePoints.dispose();
    _calculatedPoints.dispose();
    super.dispose();
  }

  String? _nullIfBlank(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add Verified Result'),
    content: SizedBox(
      width: 520,
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _exhibitor,
                decoration: const InputDecoration(labelText: 'Exhibitor name'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Exhibitor name is required.'
                    : null,
              ),
              DropdownButtonFormField<String?>(
                value: _divisionId,
                decoration: const InputDecoration(
                  labelText: 'Division (optional)',
                ),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('Not assigned'),
                  ),
                  for (final division in widget.divisions)
                    DropdownMenuItem(
                      value: division.id,
                      child: Text(division.name),
                    ),
                ],
                onChanged: (value) => setState(() => _divisionId = value),
              ),
              TextFormField(
                controller: _species,
                decoration: const InputDecoration(labelText: 'Species'),
              ),
              TextFormField(
                controller: _breed,
                decoration: const InputDecoration(labelText: 'Breed'),
              ),
              TextFormField(
                controller: _placement,
                decoration: const InputDecoration(labelText: 'Placement'),
              ),
              TextFormField(
                controller: _sourcePoints,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Points shown on report (optional)',
                ),
              ),
              TextFormField(
                controller: _calculatedPoints,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Verified calculated points',
                ),
                validator: (value) => num.tryParse(value ?? '') == null
                    ? 'Enter verified calculated points.'
                    : null,
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (!_formKey.currentState!.validate()) return;
          Navigator.pop(
            context,
            _SweepstakesResultImportRowDraft(
              divisionId: _divisionId,
              exhibitorName: _exhibitor.text.trim(),
              species: _nullIfBlank(_species.text),
              breed: _nullIfBlank(_breed.text),
              placement: _nullIfBlank(_placement.text),
              sourcePoints: num.tryParse(_sourcePoints.text),
              calculatedPoints: num.parse(_calculatedPoints.text),
            ),
          );
        },
        child: const Text('Add to draft'),
      ),
    ],
  );
}

class _SweepstakesParserRulesDialog extends StatefulWidget {
  const _SweepstakesParserRulesDialog({required this.clubId});
  final String clubId;
  @override
  State<_SweepstakesParserRulesDialog> createState() =>
      _SweepstakesParserRulesDialogState();
}

class _SweepstakesParserRulesDialogState
    extends State<_SweepstakesParserRulesDialog> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _rules = const [];
  bool _loading = true;
  bool _savingIntake = false;
  bool _intakeEnabled = false;
  bool _remindersEnabled = false;
  bool _approvalRequired = false;
  int _dueDays = 30;
  int _retentionDays = 365;
  String? _forwardingAddress;
  String? _errorMessage;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final responses = await Future.wait([
        _supabase
            .from('club_sweepstakes_parser_rules')
            .select()
            .eq('club_id', widget.clubId)
            .order('rule_type')
            .order('sort_order'),
        _supabase
            .from('club_sweepstakes_settings')
            .select(
              'report_intake_enabled,automatic_report_reminders_enabled,'
              'reminder_approval_required,report_due_days,report_retention_days',
            )
            .eq('club_id', widget.clubId)
            .maybeSingle(),
        _supabase
            .from('clubs')
            .select('slug')
            .eq('id', widget.clubId)
            .maybeSingle(),
      ]);
      final settings = responses[1] as Map<String, dynamic>?;
      final club = responses[2] as Map<String, dynamic>?;
      final slug = club?['slug']?.toString().trim();
      if (!mounted) return;
      setState(() {
        _rules = (responses[0] as List)
            .map((row) => Map<String, dynamic>.from(row as Map))
            .toList();
        _intakeEnabled = settings?['report_intake_enabled'] == true;
        _remindersEnabled =
            settings?['automatic_report_reminders_enabled'] == true;
        _approvalRequired = settings?['reminder_approval_required'] == true;
        _dueDays = _nullableInt(settings?['report_due_days']) ?? 30;
        _retentionDays =
            _nullableInt(settings?['report_retention_days']) ?? 365;
        _forwardingAddress = slug == null || slug.isEmpty
            ? null
            : '$slug@reports.ringmasterone.com';
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Unable to load Sweepstakes Rules: $error';
        _loading = false;
      });
    }
  }

  Future<void> _addCurrentRule() async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => const _ParserRuleEditorDialog(),
    );
    if (result == null) return;
    await _supabase.from('club_sweepstakes_parser_rules').insert({
      'club_id': widget.clubId,
      'rule_type': result['type'],
      'match_value': result['match'],
      'replacement_value': result['replacement'],
    });
    await _load();
  }

  Future<void> _editCurrentRule(Map<String, dynamic> rule) async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => _ParserRuleEditorDialog(initialRule: rule),
    );
    if (result == null) return;
    await _supabase
        .from('club_sweepstakes_parser_rules')
        .update({
          'rule_type': result['type'],
          'match_value': result['match'],
          'replacement_value': result['replacement'],
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', rule['id']);
    await _load();
  }

  Future<void> _addScoringRule() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _ScoringRuleEditorDialog(),
    );
    if (result == null) return;
    await _supabase.from('club_sweepstakes_parser_rules').insert({
      'club_id': widget.clubId,
      'rule_type': 'points_rule',
      'match_value': result['match_value'],
      'replacement_value': result['replacement_value'],
      'rule_config': result['rule_config'],
      'description': result['description'],
    });
    await _load();
  }

  Future<void> _editScoringRule(Map<String, dynamic> rule) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _ScoringRuleEditorDialog(initialRule: rule),
    );
    if (result == null) return;
    await _supabase
        .from('club_sweepstakes_parser_rules')
        .update({
          'match_value': result['match_value'],
          'replacement_value': result['replacement_value'],
          'rule_config': result['rule_config'],
          'description': result['description'],
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', rule['id']);
    await _load();
  }

  Future<void> _deleteInactiveRule(Map<String, dynamic> rule) async {
    if (rule['is_active'] == true) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete inactive rule?'),
        content: const Text(
          'This rule is not currently used. Deleting it removes it from this club’s Sweepstakes Rules permanently.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete rule'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _supabase
        .from('club_sweepstakes_parser_rules')
        .delete()
        .eq('id', rule['id']);
    await _load();
  }

  Future<void> _saveIntakeSettings() async {
    if (_savingIntake) return;
    setState(() => _savingIntake = true);
    try {
      await _supabase.from('club_sweepstakes_settings').upsert({
        'club_id': widget.clubId,
        'report_intake_enabled': _intakeEnabled,
        'automatic_report_reminders_enabled': _remindersEnabled,
        'reminder_approval_required': _approvalRequired,
        'report_due_days': _dueDays,
        'report_retention_days': _retentionDays,
        'updated_by': _supabase.auth.currentUser?.id,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'club_id');
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted)
        setState(
          () => _errorMessage = 'Unable to save intake settings: $error',
        );
    } finally {
      if (mounted) setState(() => _savingIntake = false);
    }
  }

  Future<void> _setRuleActive(Map<String, dynamic> rule, bool value) async {
    await _supabase
        .from('club_sweepstakes_parser_rules')
        .update({
          'is_active': value,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', rule['id']);
    await _load();
  }

  List<Map<String, dynamic>> get _currentRules => _rules
      .where(
        (rule) =>
            rule['rule_type'] != 'points_rule' &&
            rule['rule_type'] != 'address_stop_word',
      )
      .toList();

  List<Map<String, dynamic>> get _scoringRules =>
      _rules.where((rule) => rule['rule_type'] == 'points_rule').toList();

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    child: AlertDialog(
      title: const Text('Sweepstakes Rules & Report Intake'),
      content: SizedBox(
        width: 900,
        height: 580,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  const TabBar(
                    tabs: [
                      Tab(text: 'Current rules'),
                      Tab(text: 'Report intake'),
                      Tab(text: 'Scoring rules'),
                    ],
                  ),
                  if (_errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _RulesTable(
                          rules: _currentRules,
                          emptyMessage:
                              'Name corrections, breed aliases, and division assignments will appear here. Address cleanup is built in for every club.',
                          columns: const [
                            'Rule type',
                            'Match',
                            'Outcome',
                            'Active',
                          ],
                          onChanged: _setRuleActive,
                          onEdit: _editCurrentRule,
                          onDelete: _deleteInactiveRule,
                        ),
                        _buildIntakeTab(context),
                        _RulesTable(
                          rules: _scoringRules,
                          emptyMessage:
                              'Add the point methods this club uses. Each rule is stored separately, so it can be changed without changing code.',
                          columns: const [
                            'Calculation option',
                            'Points / multiplier',
                            'Notes',
                            'Active',
                          ],
                          onChanged: _setRuleActive,
                          onEdit: _editScoringRule,
                          onDelete: _deleteInactiveRule,
                          scoring: true,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Close'),
        ),
        FilledButton.icon(
          onPressed: _addCurrentRule,
          icon: const Icon(Icons.add),
          label: const Text('Add current rule'),
        ),
        FilledButton.icon(
          onPressed: _addScoringRule,
          icon: const Icon(Icons.calculate_outlined),
          label: const Text('Add scoring rule'),
        ),
      ],
    ),
  );

  Widget _buildIntakeTab(BuildContext context) => ListView(
    padding: const EdgeInsets.only(top: 12),
    children: [
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        value: _intakeEnabled,
        onChanged: _savingIntake
            ? null
            : (value) => setState(() => _intakeEnabled = value),
        title: const Text('Enable forwarded report intake'),
        subtitle: const Text(
          'Allow emailed reports and attachments into this club’s restricted review inbox.',
        ),
      ),
      if (_intakeEnabled && _forwardingAddress != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: SelectableText(
            'Forward reports to\n$_forwardingAddress',
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
      const Divider(),
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        value: _remindersEnabled,
        onChanged: _savingIntake
            ? null
            : (value) => setState(() => _remindersEnabled = value),
        title: const Text('Send missing-report reminders'),
        subtitle: const Text(
          'Email the show secretary when an expected sanction report is still missing.',
        ),
      ),
      if (_remindersEnabled)
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: _approvalRequired,
          onChanged: _savingIntake
              ? null
              : (value) => setState(() => _approvalRequired = value),
          title: const Text('Require staff approval before sending'),
        ),
      const SizedBox(height: 12),
      _ResponsiveFields(
        children: [
          DropdownButtonFormField<int>(
            value: _dueDays,
            decoration: const InputDecoration(
              labelText: 'Reminder due after',
              border: OutlineInputBorder(),
            ),
            items: const [15, 30, 45, 60]
                .map(
                  (days) => DropdownMenuItem(
                    value: days,
                    child: Text('$days days after show end'),
                  ),
                )
                .toList(),
            onChanged: _savingIntake
                ? null
                : (value) {
                    if (value != null) setState(() => _dueDays = value);
                  },
          ),
          DropdownButtonFormField<int>(
            value: _retentionDays,
            decoration: const InputDecoration(
              labelText: 'Original report retention',
              border: OutlineInputBorder(),
            ),
            items: const [365, 730, 1095]
                .map(
                  (days) => DropdownMenuItem(
                    value: days,
                    child: Text('${days ~/ 365} year${days == 365 ? '' : 's'}'),
                  ),
                )
                .toList(),
            onChanged: _savingIntake
                ? null
                : (value) {
                    if (value != null) setState(() => _retentionDays = value);
                  },
          ),
        ],
      ),
      const SizedBox(height: 16),
      Align(
        alignment: Alignment.centerRight,
        child: FilledButton.icon(
          onPressed: _savingIntake ? null : _saveIntakeSettings,
          icon: const Icon(Icons.save_outlined),
          label: Text(_savingIntake ? 'Saving...' : 'Save intake settings'),
        ),
      ),
      const SizedBox(height: 12),
      const Text(
        'Every report remains in staff review. A received email or PDF never changes standings automatically.',
      ),
    ],
  );
}

class _ParserRuleEditorDialog extends StatefulWidget {
  const _ParserRuleEditorDialog({this.initialRule});

  final Map<String, dynamic>? initialRule;
  @override
  State<_ParserRuleEditorDialog> createState() =>
      _ParserRuleEditorDialogState();
}

class _ParserRuleEditorDialogState extends State<_ParserRuleEditorDialog> {
  late final TextEditingController _match;
  late final TextEditingController _replacement;
  late String _type;

  @override
  void initState() {
    super.initState();
    final rule = widget.initialRule;
    _match = TextEditingController(text: rule?['match_value']?.toString());
    _replacement = TextEditingController(
      text: rule?['replacement_value']?.toString(),
    );
    _type = rule?['rule_type']?.toString() ?? 'name_alias';
  }

  @override
  void dispose() {
    _match.dispose();
    _replacement.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.initialRule == null
          ? 'Add Sweepstakes Rule'
          : 'Edit Sweepstakes Rule',
    ),
    content: SizedBox(
      width: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _type,
            decoration: const InputDecoration(labelText: 'Rule type'),
            items: const [
              DropdownMenuItem(
                value: 'name_alias',
                child: Text('Exhibitor name correction'),
              ),
              DropdownMenuItem(
                value: 'name_pattern',
                child: Text('Exhibitor name pattern'),
              ),
              DropdownMenuItem(
                value: 'breed_alias',
                child: Text('Breed alias'),
              ),
              DropdownMenuItem(
                value: 'division_assignment',
                child: Text('Division assignment'),
              ),
            ],
            onChanged: (value) => setState(() => _type = value!),
          ),
          TextField(
            controller: _match,
            decoration: const InputDecoration(labelText: 'Match value'),
          ),
          TextField(
            controller: _replacement,
            decoration: const InputDecoration(
              labelText: 'Replacement / outcome',
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (_match.text.trim().isEmpty) return;
          Navigator.pop(context, {
            'type': _type,
            'match': _match.text.trim(),
            'replacement': _replacement.text.trim(),
          });
        },
        child: const Text('Save rule'),
      ),
    ],
  );
}

class _RulesTable extends StatelessWidget {
  const _RulesTable({
    required this.rules,
    required this.emptyMessage,
    required this.columns,
    required this.onChanged,
    required this.onEdit,
    required this.onDelete,
    this.scoring = false,
  });

  final List<Map<String, dynamic>> rules;
  final String emptyMessage;
  final List<String> columns;
  final Future<void> Function(Map<String, dynamic>, bool) onChanged;
  final Future<void> Function(Map<String, dynamic>) onEdit;
  final Future<void> Function(Map<String, dynamic>) onDelete;
  final bool scoring;

  @override
  Widget build(BuildContext context) {
    if (rules.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(emptyMessage, textAlign: TextAlign.center),
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 16),
      child: DataTable(
        columns: [
          for (final label in columns) DataColumn(label: Text(label)),
          const DataColumn(label: Text('Actions')),
        ],
        rows: rules.map((rule) {
          final config = Map<String, dynamic>.from(
            rule['rule_config'] ?? const {},
          );
          final title = scoring
              ? '${config['award_label']?.toString() ?? 'Award'} — ${config['label']?.toString() ?? rule['match_value']?.toString() ?? 'Scoring rule'}'
              : _titleCase(rule['rule_type']?.toString() ?? '');
          final value = rule['replacement_value']?.toString() ?? '—';
          final note = scoring
              ? (rule['description']?.toString().trim().isNotEmpty == true
                    ? rule['description'].toString()
                    : config['calculation_type']?.toString() ?? '—')
              : value;
          return DataRow(
            cells: [
              DataCell(SizedBox(width: 190, child: Text(title))),
              DataCell(
                SizedBox(
                  width: 200,
                  child: Text(
                    scoring ? value : rule['match_value']?.toString() ?? '—',
                  ),
                ),
              ),
              DataCell(
                SizedBox(
                  width: 230,
                  child: Text(
                    note,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              DataCell(
                Switch(
                  value: rule['is_active'] == true,
                  onChanged: (value) => onChanged(rule, value),
                ),
              ),
              DataCell(
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Edit rule',
                      onPressed: () => onEdit(rule),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    if (rule['is_active'] != true)
                      IconButton(
                        tooltip: 'Delete inactive rule',
                        onPressed: () => onDelete(rule),
                        icon: const Icon(Icons.delete_outline),
                      ),
                  ],
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}

class _ScoringRuleEditorDialog extends StatefulWidget {
  const _ScoringRuleEditorDialog({this.initialRule});

  final Map<String, dynamic>? initialRule;

  @override
  State<_ScoringRuleEditorDialog> createState() =>
      _ScoringRuleEditorDialogState();
}

class _ScoringRuleEditorDialogState extends State<_ScoringRuleEditorDialog> {
  late final TextEditingController _points;
  late String _option;
  late String _award;

  @override
  void initState() {
    super.initState();
    final rule = widget.initialRule;
    final match = rule?['match_value']?.toString() ?? '';
    final savedOption = match.split(':').first;
    final option = _scoringOptions.any((item) => item.code == savedOption)
        ? _scoringOptions.firstWhere((item) => item.code == savedOption)
        : _scoringOptions.first;
    final config = Map<String, dynamic>.from(rule?['rule_config'] ?? const {});
    _option = option.code;
    _award =
        config['award_label']?.toString() ??
        (match.contains(':') ? match.split(':').last : option.awards.first);
    if (!option.awards.contains(_award)) _award = option.awards.first;
    _points = TextEditingController(
      text: rule?['replacement_value']?.toString(),
    );
  }

  @override
  void dispose() {
    _points.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = _scoringOptions.firstWhere(
      (option) => option.code == _option,
    );
    final pointsLabel = selected.usesShownCount
        ? 'Points for $_award'
        : selected.valueLabel;
    return AlertDialog(
      title: Text(
        widget.initialRule == null ? 'Add scoring rule' : 'Edit scoring rule',
      ),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              value: _option,
              decoration: const InputDecoration(labelText: 'Scoring category'),
              items: _scoringOptions
                  .map(
                    (option) => DropdownMenuItem(
                      value: option.code,
                      child: Text(option.label),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  final option = _scoringOptions.firstWhere(
                    (item) => item.code == value,
                  );
                  setState(() {
                    _option = value;
                    _award = option.awards.first;
                  });
                }
              },
            ),
            const SizedBox(height: 8),
            Text(
              selected.helpText,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _award,
              decoration: const InputDecoration(
                labelText: 'Award or placement',
              ),
              items: selected.awards
                  .map(
                    (award) =>
                        DropdownMenuItem(value: award, child: Text(award)),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => _award = value);
              },
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _points,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(labelText: pointsLabel),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final points = num.tryParse(_points.text.trim());
            if (points == null) return;
            Navigator.pop(context, {
              'match_value': '${selected.code}:$_award',
              'replacement_value': points.toString(),
              'description': '${selected.label} for $_award',
              'rule_config': {
                'label': selected.label,
                'award_label': _award,
                'calculation_type': selected.calculationType,
              },
            });
          },
          child: const Text('Save scoring rule'),
        ),
      ],
    );
  }
}

class _ScoringOption {
  const _ScoringOption(
    this.code,
    this.label,
    this.valueLabel,
    this.helpText,
    this.calculationType,
    this.awards, {
    this.usesShownCount = false,
  });

  final String code;
  final String label;
  final String valueLabel;
  final String helpText;
  final String calculationType;
  final List<String> awards;
  final bool usesShownCount;
}

const _scoringOptions = [
  _ScoringOption(
    'class_placement_flat',
    'Class placement — flat points',
    'Points for this placement',
    'Award a fixed number of points for a class placement, regardless of class size.',
    'flat_points',
    [
      '1st place',
      '2nd place',
      '3rd place',
      '4th place',
      '5th place',
      '6th place',
      '7th place',
      '8th place',
      '9th place',
      '10th place',
    ],
  ),
  _ScoringOption(
    'class_placement_multiplier',
    'Class placement — multiplier × number shown',
    'Points for placement',
    'Enter the points for the placement. RingMaster multiplies those points by the number of animals in the class.',
    'class_size_multiplier',
    [
      '1st place',
      '2nd place',
      '3rd place',
      '4th place',
      '5th place',
      '6th place',
      '7th place',
      '8th place',
      '9th place',
      '10th place',
    ],
    usesShownCount: true,
  ),
  _ScoringOption(
    'variety_award_flat',
    'Variety award — flat points',
    'Award points',
    'Use for BOV, BOSV, or another variety-level award with fixed points.',
    'flat_points',
    ['BOV', 'BOSV'],
  ),
  _ScoringOption(
    'variety_award_multiplier',
    'Variety award — multiplier × variety shown',
    'Points for award',
    'Enter the points for the award. RingMaster multiplies those points by the animals shown in that variety.',
    'variety_count_multiplier',
    ['BOV', 'BOSV'],
    usesShownCount: true,
  ),
  _ScoringOption(
    'breed_award_flat',
    'Breed award — flat points',
    'Award points',
    'Use for BOB, BOS, or another breed-level award with fixed points.',
    'flat_points',
    ['BOB', 'BOS'],
  ),
  _ScoringOption(
    'breed_award_multiplier',
    'Breed award — multiplier × breed shown',
    'Points for award',
    'Enter the points for the award. RingMaster multiplies those points by the animals shown in the breed.',
    'breed_count_multiplier',
    ['BOB', 'BOS'],
    usesShownCount: true,
  ),
  _ScoringOption(
    'group_award_flat',
    'Group award — flat points',
    'Award points',
    'Use for a group award with a fixed point value.',
    'flat_points',
    ['BOG', 'BOSG'],
  ),
  _ScoringOption(
    'group_award_multiplier',
    'Group award — multiplier × group shown',
    'Points for award',
    'Enter the points for the group award. RingMaster multiplies those points by the number of animals shown in the group.',
    'group_count_multiplier',
    ['BOG', 'BOSG'],
    usesShownCount: true,
  ),
  _ScoringOption(
    'same_sex_award_multiplier',
    'Breed award — multiplier × same-sex shown',
    'Points for award',
    'Enter the points for the award. RingMaster multiplies those points by the number shown of the applicable sex.',
    'same_sex_count_multiplier',
    ['BOS'],
    usesShownCount: true,
  ),
  _ScoringOption(
    'show_award_flat',
    'Show award — flat points',
    'Award points',
    'Use for BIS, RIS, B4C, B6C, or another show award with fixed points.',
    'flat_points',
    ['B4C', 'B6C', 'BIS', 'RIS'],
  ),
  _ScoringOption(
    'show_award_multiplier',
    'Show award — multiplier × total show entries',
    'Points for award',
    'Enter the points for the award. RingMaster multiplies those points by total eligible show entries.',
    'show_count_multiplier',
    ['B4C', 'B6C', 'BIS', 'RIS'],
    usesShownCount: true,
  ),
  _ScoringOption(
    'event_multiplier',
    'Special event multiplier',
    'Multiplier',
    'Use for a national, convention, specialty, or other event that multiplies qualifying points.',
    'event_multiplier',
    ['National Show', 'ARBA Convention', 'Specialty Show'],
  ),
  _ScoringOption(
    'fur_wool_flat',
    'Fur or wool award — flat points',
    'Award points',
    'Use for Best Fur, Best Wool, or a fur/wool class placement with a fixed value.',
    'flat_points',
    [
      'Best Fur',
      'Best Wool',
      '1st Fur/Wool',
      '2nd Fur/Wool',
      '3rd Fur/Wool',
      '4th Fur/Wool',
      '5th Fur/Wool',
    ],
  ),
  _ScoringOption(
    'quality_points_flat',
    'Quality points — flat points',
    'Award points',
    'Use when a club tracks quality points separately from regular sweepstakes points.',
    'flat_points',
    ['Quality points'],
  ),
];

class _ReportIntakeSettingsDialog extends StatefulWidget {
  const _ReportIntakeSettingsDialog({required this.clubId});

  final String clubId;

  @override
  State<_ReportIntakeSettingsDialog> createState() =>
      _ReportIntakeSettingsDialogState();
}

class _ReportIntakeSettingsDialogState
    extends State<_ReportIntakeSettingsDialog> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _intakeEnabled = false;
  bool _remindersEnabled = false;
  bool _approvalRequired = false;
  int _dueDays = 30;
  int _retentionDays = 365;
  String? _forwardingAddress;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final responses = await Future.wait([
        _supabase
            .from('club_sweepstakes_settings')
            .select(
              'report_intake_enabled,automatic_report_reminders_enabled,'
              'reminder_approval_required,report_due_days,report_retention_days',
            )
            .eq('club_id', widget.clubId)
            .maybeSingle(),
        _supabase
            .from('clubs')
            .select('slug')
            .eq('id', widget.clubId)
            .maybeSingle(),
      ]);
      final row = responses[0];
      final club = responses[1];
      final slug = club?['slug']?.toString().trim();
      if (!mounted) return;
      setState(() {
        _intakeEnabled = row?['report_intake_enabled'] == true;
        _remindersEnabled = row?['automatic_report_reminders_enabled'] == true;
        _approvalRequired = row?['reminder_approval_required'] == true;
        _dueDays = _nullableInt(row?['report_due_days']) ?? 30;
        _retentionDays = _nullableInt(row?['report_retention_days']) ?? 365;
        _forwardingAddress = slug == null || slug.isEmpty
            ? null
            : '$slug@reports.ringmasterone.com';
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Unable to load report intake settings: $error';
        _isLoading = false;
      });
    }
  }

  Future<void> _save() async {
    if (_isSaving) return;
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    try {
      await _supabase.from('club_sweepstakes_settings').upsert({
        'club_id': widget.clubId,
        'report_intake_enabled': _intakeEnabled,
        'automatic_report_reminders_enabled': _remindersEnabled,
        'reminder_approval_required': _approvalRequired,
        'report_due_days': _dueDays,
        'report_retention_days': _retentionDays,
        'updated_by': _supabase.auth.currentUser?.id,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'club_id');
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Unable to save report intake settings: $error';
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Report Intake & Reminders'),
      content: SizedBox(
        width: 620,
        child: _isLoading
            ? const SizedBox(
                height: 160,
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_errorMessage != null) ...[
                      Text(
                        _errorMessage!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: _intakeEnabled,
                      onChanged: _isSaving
                          ? null
                          : (value) => setState(() => _intakeEnabled = value),
                      title: const Text('Enable forwarded report intake'),
                      subtitle: const Text(
                        'Allow report packages to enter the club’s restricted review inbox.',
                      ),
                    ),
                    if (_intakeEnabled && _forwardingAddress != null) ...[
                      const SizedBox(height: 8),
                      SelectableText(
                        'Forward reports to\n$_forwardingAddress',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'This address accepts forwarded emails and attachments. Every package stays in staff review until someone approves it.',
                      ),
                    ],
                    const Divider(),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: _remindersEnabled,
                      onChanged: _isSaving
                          ? null
                          : (value) =>
                                setState(() => _remindersEnabled = value),
                      title: const Text('Send missing-report reminders'),
                      subtitle: const Text(
                        'Email the show secretary when an expected sanction report is still missing.',
                      ),
                    ),
                    if (_remindersEnabled)
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        value: _approvalRequired,
                        onChanged: _isSaving
                            ? null
                            : (value) =>
                                  setState(() => _approvalRequired = value),
                        title: const Text(
                          'Require staff approval before sending',
                        ),
                      ),
                    const SizedBox(height: 12),
                    _ResponsiveFields(
                      children: [
                        DropdownButtonFormField<int>(
                          initialValue: _dueDays,
                          decoration: const InputDecoration(
                            labelText: 'Reminder due after',
                            border: OutlineInputBorder(),
                          ),
                          items: const [15, 30, 45, 60]
                              .map(
                                (days) => DropdownMenuItem(
                                  value: days,
                                  child: Text('$days days after show end'),
                                ),
                              )
                              .toList(),
                          onChanged: _isSaving
                              ? null
                              : (value) {
                                  if (value != null) {
                                    setState(() => _dueDays = value);
                                  }
                                },
                        ),
                        DropdownButtonFormField<int>(
                          initialValue: _retentionDays,
                          decoration: const InputDecoration(
                            labelText: 'Original report retention',
                            border: OutlineInputBorder(),
                          ),
                          items: const [365, 730, 1095]
                              .map(
                                (days) => DropdownMenuItem(
                                  value: days,
                                  child: Text(
                                    '${days ~/ 365} year${days == 365 ? '' : 's'}',
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: _isSaving
                              ? null
                              : (value) {
                                  if (value != null) {
                                    setState(() => _retentionDays = value);
                                  }
                                },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Reports are always held for staff review. No email or PDF can change standings automatically.',
                    ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isLoading || _isSaving ? null : _save,
          child: Text(_isSaving ? 'Saving...' : 'Save settings'),
        ),
      ],
    );
  }
}

class _SeasonEditorDialog extends StatefulWidget {
  const _SeasonEditorDialog({required this.clubId, this.existing});

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
  late String _publicationMode;
  late String _visibility;
  late String _publicDisplayFormat;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameController = TextEditingController(text: existing?.name ?? '');
    _descriptionController = TextEditingController(
      text: existing?.description ?? '',
    );
    _startDateController = TextEditingController(
      text: _dateText(existing?.startDate),
    );
    _endDateController = TextEditingController(
      text: _dateText(existing?.endDate),
    );
    _pointsNotesController = TextEditingController(
      text: existing?.pointsNotes ?? '',
    );
    _status = existing?.status ?? 'draft';
    _publicationMode = existing?.publicationMode ?? 'manual';
    _visibility = existing?.visibility ?? 'members';
    _publicDisplayFormat = existing?.publicDisplayFormat ?? 'name_state';
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
          'p_publication_mode': _publicationMode,
          'p_visibility': _visibility,
          'p_public_display_format': _publicDisplayFormat,
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
                    DropdownMenuItem(
                      value: 'finalized',
                      child: Text('Finalized'),
                    ),
                    DropdownMenuItem(
                      value: 'archived',
                      child: Text('Archived'),
                    ),
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
                _ResponsiveFields(
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: _publicationMode,
                      decoration: const InputDecoration(
                        labelText: 'Standings updates',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'manual',
                          child: Text('Publish on update click'),
                        ),
                        DropdownMenuItem(
                          value: 'live',
                          child: Text('Live 24/7'),
                        ),
                      ],
                      onChanged: _isSaving
                          ? null
                          : (value) {
                              if (value != null) {
                                setState(() => _publicationMode = value);
                              }
                            },
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: _visibility,
                      decoration: const InputDecoration(
                        labelText: 'Standings visibility',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'members',
                          child: Text('Club members only'),
                        ),
                        DropdownMenuItem(
                          value: 'public',
                          child: Text('Public'),
                        ),
                      ],
                      onChanged: _isSaving
                          ? null
                          : (value) {
                              if (value != null) {
                                setState(() => _visibility = value);
                              }
                            },
                    ),
                  ],
                ),
                if (_visibility == 'public') ...[
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: _publicDisplayFormat,
                    decoration: const InputDecoration(
                      labelText: 'Public exhibitor display',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'name_only',
                        child: Text('Name only'),
                      ),
                      DropdownMenuItem(
                        value: 'name_state',
                        child: Text('Name and state'),
                      ),
                      DropdownMenuItem(
                        value: 'name_city_state',
                        child: Text('Name, city and state'),
                      ),
                    ],
                    onChanged: _isSaving
                        ? null
                        : (value) {
                            if (value != null) {
                              setState(() => _publicDisplayFormat = value);
                            }
                          },
                  ),
                ],
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

class _ExpectedReportEditorDialog extends StatefulWidget {
  const _ExpectedReportEditorDialog({
    required this.clubId,
    required this.season,
  });

  final String clubId;
  final _SweepstakesSeason season;

  @override
  State<_ExpectedReportEditorDialog> createState() =>
      _ExpectedReportEditorDialogState();
}

class _ExpectedReportEditorDialogState
    extends State<_ExpectedReportEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  final _supabase = Supabase.instance.client;
  late final TextEditingController _showName;
  late final TextEditingController _showDate;
  late final TextEditingController _showEndDate;
  late final TextEditingController _clubNumber;
  late final TextEditingController _arbaNumber;
  late final TextEditingController _secretaryName;
  late final TextEditingController _secretaryEmail;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _showName = TextEditingController();
    _showDate = TextEditingController();
    _showEndDate = TextEditingController();
    _clubNumber = TextEditingController();
    _arbaNumber = TextEditingController();
    _secretaryName = TextEditingController();
    _secretaryEmail = TextEditingController();
  }

  @override
  void dispose() {
    _showName.dispose();
    _showDate.dispose();
    _showEndDate.dispose();
    _clubNumber.dispose();
    _arbaNumber.dispose();
    _secretaryName.dispose();
    _secretaryEmail.dispose();
    super.dispose();
  }

  DateTime? _parseDate(String value) => DateTime.tryParse(value.trim());
  String? _optional(String value) => value.trim().isEmpty ? null : value.trim();

  Future<void> _save() async {
    if (_isSaving || !_formKey.currentState!.validate()) return;
    final showDate = _parseDate(_showDate.text);
    final endDate = _showEndDate.text.trim().isEmpty
        ? null
        : _parseDate(_showEndDate.text);
    if (showDate == null || (endDate != null && endDate.isBefore(showDate))) {
      setState(() => _errorMessage = 'Enter valid show dates.');
      return;
    }
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    try {
      await _supabase.from('club_sweepstakes_expected_reports').insert({
        'club_id': widget.clubId,
        'season_id': widget.season.id,
        'show_name': _showName.text.trim(),
        'show_date': showDate.toIso8601String().substring(0, 10),
        'show_end_date': endDate?.toIso8601String().substring(0, 10),
        'club_sanction_number': _optional(_clubNumber.text),
        'arba_sanction_number': _optional(_arbaNumber.text),
        'show_secretary_name': _optional(_secretaryName.text),
        'show_secretary_email': _optional(_secretaryEmail.text),
        'due_date': (endDate ?? showDate)
            .add(const Duration(days: 30))
            .toIso8601String()
            .substring(0, 10),
        'status': 'expected',
      });
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorMessage = 'Unable to add the expected report: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add Expected Report'),
    content: SizedBox(
      width: 600,
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'For ${widget.season.name}. Use this for an outside or historic sanction; approved Club sanctions are added automatically.',
              ),
              const SizedBox(height: 14),
              if (_errorMessage != null)
                Text(
                  _errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              TextFormField(
                controller: _showName,
                decoration: const InputDecoration(labelText: 'Show name'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Show name is required.'
                    : null,
              ),
              _ResponsiveFields(
                children: [
                  TextFormField(
                    controller: _showDate,
                    decoration: const InputDecoration(
                      labelText: 'Show date (YYYY-MM-DD)',
                    ),
                    validator: (value) => _parseDate(value ?? '') == null
                        ? 'Use YYYY-MM-DD.'
                        : null,
                  ),
                  TextFormField(
                    controller: _showEndDate,
                    decoration: const InputDecoration(
                      labelText: 'End date (optional)',
                    ),
                  ),
                ],
              ),
              _ResponsiveFields(
                children: [
                  TextFormField(
                    controller: _clubNumber,
                    decoration: const InputDecoration(
                      labelText: 'Club sanction number',
                    ),
                  ),
                  TextFormField(
                    controller: _arbaNumber,
                    decoration: const InputDecoration(
                      labelText: 'ARBA sanction number',
                    ),
                  ),
                ],
              ),
              _ResponsiveFields(
                children: [
                  TextFormField(
                    controller: _secretaryName,
                    decoration: const InputDecoration(
                      labelText: 'Show secretary name',
                    ),
                  ),
                  TextFormField(
                    controller: _secretaryEmail,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Show secretary email',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _isSaving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton.icon(
        onPressed: _isSaving ? null : _save,
        icon: const Icon(Icons.add_task_outlined),
        label: Text(_isSaving ? 'Saving...' : 'Add expected report'),
      ),
    ],
  );
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
    _descriptionController = TextEditingController(
      text: existing?.description ?? '',
    );
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
  State<_AdjustmentEditorDialog> createState() =>
      _AdjustmentEditorDialogState();
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
    _divisionId =
        standing?.divisionId ??
        (widget.divisions.isEmpty ? null : widget.divisions.first.id);
    _exhibitorController = TextEditingController(
      text: standing?.exhibitorName ?? '',
    );
    _membershipController = TextEditingController(
      text: standing?.membershipNumber ?? '',
    );
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

class _SweepstakesResultImport {
  const _SweepstakesResultImport({required this.id});

  final String id;

  factory _SweepstakesResultImport.fromJson(Map<String, dynamic> json) =>
      _SweepstakesResultImport(id: json['id'].toString());
}

class _SweepstakesResultImportRow {
  const _SweepstakesResultImportRow({
    required this.id,
    required this.exhibitorName,
    required this.calculatedPoints,
    required this.status,
    required this.pointMismatch,
    this.breed,
    this.placement,
    this.sourcePoints,
  });

  final String id;
  final String exhibitorName;
  final String? breed;
  final String? placement;
  final num? sourcePoints;
  final num calculatedPoints;
  final String status;
  final bool pointMismatch;

  factory _SweepstakesResultImportRow.fromJson(Map<String, dynamic> json) =>
      _SweepstakesResultImportRow(
        id: json['id'].toString(),
        exhibitorName:
            _nullableString(json['exhibitor_name']) ?? 'Unnamed exhibitor',
        breed: _nullableString(json['breed']),
        placement: _nullableString(json['placement']),
        sourcePoints: json['source_points'] as num?,
        calculatedPoints: (json['calculated_points'] as num?) ?? 0,
        status: _nullableString(json['status']) ?? 'pending',
        pointMismatch: json['point_mismatch'] == true,
      );
}

class _SweepstakesResultImportRowDraft {
  const _SweepstakesResultImportRowDraft({
    required this.exhibitorName,
    required this.calculatedPoints,
    this.divisionId,
    this.species,
    this.breed,
    this.placement,
    this.sourcePoints,
  });

  final String? divisionId;
  final String exhibitorName;
  final String? species;
  final String? breed;
  final String? placement;
  final num? sourcePoints;
  final num calculatedPoints;
}

class _SweepstakesResultAward {
  const _SweepstakesResultAward({
    required this.awardLabel,
    required this.ruleLabel,
    required this.pointsPerAward,
    required this.calculatedPoints,
    this.shownCount,
    this.breed,
  });

  final String awardLabel;
  final String ruleLabel;
  final num pointsPerAward;
  final num calculatedPoints;
  final num? shownCount;
  final String? breed;

  factory _SweepstakesResultAward.fromJson(Map<String, dynamic> json) =>
      _SweepstakesResultAward(
        awardLabel: _nullableString(json['award_label']) ?? 'Award',
        ruleLabel: _nullableString(json['rule_label']) ?? 'Sweepstakes rule',
        pointsPerAward: (json['points_per_award'] as num?) ?? 0,
        calculatedPoints: (json['calculated_points'] as num?) ?? 0,
        shownCount: json['shown_count'] as num?,
        breed: _nullableString(json['breed']),
      );
}

class _BreedPaybackObligation {
  const _BreedPaybackObligation({
    required this.id,
    required this.expectedReportId,
    required this.breed,
    required this.rabbitsShown,
    required this.countSource,
    required this.collectionCentsPerRabbit,
    required this.breedFundCentsPerRabbit,
    required this.expectedCollectionCents,
    required this.expectedBreedFundCents,
    required this.expectedIsrbaAllocationCents,
  });

  final String id;
  final String expectedReportId;
  final String breed;
  final int rabbitsShown;
  final String countSource;
  final int collectionCentsPerRabbit;
  final int breedFundCentsPerRabbit;
  final int expectedCollectionCents;
  final int expectedBreedFundCents;
  final int expectedIsrbaAllocationCents;

  factory _BreedPaybackObligation.fromJson(Map<String, dynamic> json) =>
      _BreedPaybackObligation(
        id: json['id'].toString(),
        expectedReportId: json['expected_report_id'].toString(),
        breed: _nullableString(json['breed']) ?? 'Unknown breed',
        rabbitsShown: _nullableInt(json['rabbits_shown']) ?? 0,
        countSource: _nullableString(json['count_source']) ?? 'manual',
        collectionCentsPerRabbit:
            _nullableInt(json['collection_cents_per_rabbit']) ?? 10,
        breedFundCentsPerRabbit:
            _nullableInt(json['breed_fund_cents_per_rabbit']) ?? 8,
        expectedCollectionCents:
            _nullableInt(json['expected_collection_cents']) ?? 0,
        expectedBreedFundCents:
            _nullableInt(json['expected_breed_fund_cents']) ?? 0,
        expectedIsrbaAllocationCents:
            _nullableInt(json['expected_isrba_allocation_cents']) ?? 0,
      );
}

class _BreedPaybackPayment {
  const _BreedPaybackPayment({required this.id});
  final String id;
  factory _BreedPaybackPayment.fromJson(Map<String, dynamic> json) =>
      _BreedPaybackPayment(id: json['id'].toString());
}

class _BreedPaybackAllocation {
  const _BreedPaybackAllocation({
    required this.obligationId,
    required this.amountCents,
  });
  final String obligationId;
  final int amountCents;
  factory _BreedPaybackAllocation.fromJson(Map<String, dynamic> json) =>
      _BreedPaybackAllocation(
        obligationId: json['obligation_id'].toString(),
        amountCents: _nullableInt(json['amount_cents']) ?? 0,
      );
}

class _BreedPaybackConventionAllocation {
  const _BreedPaybackConventionAllocation({
    required this.id,
    required this.breed,
    required this.awardType,
    required this.amountCents,
    this.seasonId,
    this.awardDetail,
    this.notes,
  });

  final String id;
  final String? seasonId;
  final String breed;
  final String awardType;
  final String? awardDetail;
  final String? notes;
  final int amountCents;

  String get awardName {
    const labels = {
      'best_of_breed': 'BOB',
      'best_opposite_sex_breed': 'BOSB',
      'best_of_variety': 'BOV',
      'best_opposite_sex_variety': 'BOSV',
      'best_of_group': 'BOG',
      'best_opposite_sex_group': 'BOSG',
      'custom': 'Custom award',
    };
    return labels[awardType] ?? 'Convention award';
  }

  String get awardLabel {
    final label = awardName;
    return awardDetail == null || awardDetail!.trim().isEmpty
        ? label
        : '$label: ${awardDetail!.trim()}';
  }

  factory _BreedPaybackConventionAllocation.fromJson(
    Map<String, dynamic> json,
  ) => _BreedPaybackConventionAllocation(
    id: _nullableString(json['id']) ?? '',
    seasonId: _nullableString(json['season_id']),
    breed: _nullableString(json['breed']) ?? 'Unknown breed',
    awardType: _nullableString(json['award_type']) ?? 'custom',
    awardDetail: _nullableString(json['award_detail']),
    notes: _nullableString(json['notes']),
    amountCents: _nullableInt(json['amount_cents']) ?? 0,
  );
}

class _ExpectedSweepstakesReport {
  const _ExpectedSweepstakesReport({
    required this.id,
    required this.showName,
    required this.showDate,
    required this.dueDate,
    required this.status,
    required this.reminderCount,
    this.seasonId,
    this.clubSanctionNumber,
    this.arbaSanctionNumber,
  });

  final String id;
  final String? seasonId;
  final String? clubSanctionNumber;
  final String? arbaSanctionNumber;
  final String showName;
  final DateTime showDate;
  final DateTime dueDate;
  final String status;
  final int reminderCount;

  String get effectiveStatus {
    if ((status == 'expected' || status == 'partial') &&
        dueDate.isBefore(DateTime.now())) {
      return 'overdue';
    }
    return status;
  }

  bool get needsAttention =>
      effectiveStatus == 'expected' ||
      effectiveStatus == 'partial' ||
      effectiveStatus == 'overdue' ||
      effectiveStatus == 'needs_review';

  factory _ExpectedSweepstakesReport.fromJson(Map<String, dynamic> json) {
    return _ExpectedSweepstakesReport(
      id: json['id'].toString(),
      seasonId: _nullableString(json['season_id']),
      clubSanctionNumber: _nullableString(json['club_sanction_number']),
      arbaSanctionNumber: _nullableString(json['arba_sanction_number']),
      showName: _nullableString(json['show_name']) ?? 'Unnamed show',
      showDate: _nullableDate(json['show_date']) ?? DateTime.now(),
      dueDate: _nullableDate(json['due_date']) ?? DateTime.now(),
      status: _nullableString(json['status']) ?? 'expected',
      reminderCount: _nullableInt(json['reminder_count']) ?? 0,
    );
  }
}

class _SweepstakesReportAttachment {
  const _SweepstakesReportAttachment({
    required this.fileName,
    this.storagePath,
    this.contentType,
  });

  final String fileName;
  final String? storagePath;
  final String? contentType;

  factory _SweepstakesReportAttachment.fromJson(Map<String, dynamic> json) {
    return _SweepstakesReportAttachment(
      fileName: _nullableString(json['file_name']) ?? 'Unnamed attachment',
      storagePath: _nullableString(json['storage_path']),
      contentType: _nullableString(json['content_type']),
    );
  }
}

class _SweepstakesReportPackage {
  const _SweepstakesReportPackage({
    required this.id,
    required this.status,
    required this.receivedAt,
    required this.attachments,
    this.expectedReportId,
    this.seasonId,
    this.subject,
    this.sender,
    this.storagePath,
    this.reviewNotes,
    this.freeDraft,
  });

  final String id;
  final String? expectedReportId;
  final String? seasonId;
  final String? subject;
  final String? sender;
  final DateTime receivedAt;
  final String? storagePath;
  final List<_SweepstakesReportAttachment> attachments;
  final String? reviewNotes;
  final Map<String, dynamic>? freeDraft;
  final String status;

  int get attachmentCount => attachments.length;
  bool get needsReview =>
      status == 'pending' || status == 'unmatched' || status == 'needs_review';

  factory _SweepstakesReportPackage.fromJson(Map<String, dynamic> json) {
    final rawAttachments = json['attachment_manifest'];
    final attachments = rawAttachments is List
        ? rawAttachments
              .whereType<Map>()
              .map(
                (item) => _SweepstakesReportAttachment.fromJson(
                  Map<String, dynamic>.from(item),
                ),
              )
              .toList()
        : const <_SweepstakesReportAttachment>[];
    return _SweepstakesReportPackage(
      id: json['id'].toString(),
      expectedReportId: _nullableString(json['expected_report_id']),
      seasonId: _nullableString(json['season_id']),
      subject: _nullableString(json['source_subject']),
      sender: _nullableString(json['source_sender_email']),
      receivedAt:
          _nullableDate(json['source_received_at']) ??
          _nullableDate(json['created_at']) ??
          DateTime.now(),
      storagePath: _nullableString(json['storage_path']),
      attachments: attachments,
      reviewNotes: _nullableString(json['review_notes']),
      freeDraft: json['extracted_summary'] is Map
          ? Map<String, dynamic>.from(json['extracted_summary'] as Map)
          : null,
      status: _nullableString(json['status']) ?? 'pending',
    );
  }
}

class _SweepstakesSeason {
  const _SweepstakesSeason({
    required this.id,
    required this.name,
    required this.status,
    required this.startDate,
    required this.endDate,
    required this.publicationMode,
    required this.visibility,
    required this.publicDisplayFormat,
    this.description,
    this.pointsNotes,
  });

  final String id;
  final String name;
  final String status;
  final DateTime startDate;
  final DateTime endDate;
  final String publicationMode;
  final String visibility;
  final String publicDisplayFormat;
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
      publicationMode: _nullableString(json['publication_mode']) ?? 'manual',
      visibility: _nullableString(json['visibility']) ?? 'members',
      publicDisplayFormat:
          _nullableString(json['public_display_format']) ?? 'name_state',
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

class _SweepstakesAwardBoard {
  const _SweepstakesAwardBoard({
    required this.id,
    required this.seasonId,
    required this.name,
    required this.grouping,
    required this.topN,
    required this.residencyRequirement,
    this.eligibilityState,
  });

  final String id;
  final String seasonId;
  final String name;
  final String grouping;
  final int topN;
  final String residencyRequirement;
  final String? eligibilityState;

  String get residencyLabel {
    if (eligibilityState == null || residencyRequirement == 'any') return '';
    final wording = residencyRequirement == 'out_of_state'
        ? 'outside $eligibilityState'
        : '$eligibilityState residents';
    return ' • $wording';
  }

  factory _SweepstakesAwardBoard.fromJson(Map<String, dynamic> json) {
    return _SweepstakesAwardBoard(
      id: json['id'].toString(),
      seasonId: json['season_id'].toString(),
      name: _nullableString(json['name']) ?? 'Award standings',
      grouping: _nullableString(json['grouping']) ?? 'overall',
      topN: _nullableInt(json['top_n']) ?? 10,
      residencyRequirement:
          _nullableString(json['residency_requirement']) ?? 'any',
      eligibilityState: _nullableString(json['eligibility_state']),
    );
  }
}

class _SweepstakesAwardBoardEntry {
  const _SweepstakesAwardBoardEntry({
    required this.rank,
    required this.exhibitorName,
    required this.points,
    this.membershipTypeName,
    this.breed,
  });

  final int rank;
  final String exhibitorName;
  final String? membershipTypeName;
  final String? breed;
  final double points;

  factory _SweepstakesAwardBoardEntry.fromJson(Map<String, dynamic> json) {
    return _SweepstakesAwardBoardEntry(
      rank: _nullableInt(json['rank']) ?? 0,
      exhibitorName:
          _nullableString(json['exhibitor_name']) ?? 'Unnamed exhibitor',
      membershipTypeName: _nullableString(json['membership_type_name']),
      breed: _nullableString(json['breed']),
      points: _nullableDouble(json['points']) ?? 0,
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
      exhibitorName:
          _nullableString(json['exhibitor_name']) ?? 'Unknown Exhibitor',
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
      exhibitorName:
          _nullableString(json['exhibitor_name']) ?? 'Unknown Exhibitor',
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
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
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
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
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
