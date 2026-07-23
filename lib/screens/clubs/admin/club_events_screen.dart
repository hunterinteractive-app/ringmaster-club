// lib/screens/clubs/admin/club_events_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/clubs/club_summary.dart';
import '../../../services/clubs/club_communications_service.dart';
import 'club_documents_screen.dart';

class ClubEventsScreen extends StatefulWidget {
  const ClubEventsScreen({super.key, required this.club});

  final ClubSummary club;

  @override
  State<ClubEventsScreen> createState() => _ClubEventsScreenState();
}

class _ClubEventsScreenState extends State<ClubEventsScreen> {
  final _supabase = Supabase.instance.client;
  final _communicationsService = ClubCommunicationsService();
  final _searchController = TextEditingController();

  bool _isLoading = true;
  String? _errorMessage;
  bool _eventsAddonEnabled = false;
  String _statusFilter = 'published';
  String _typeFilter = 'all';
  List<_ClubEvent> _events = const [];
  List<_RelatedDocument> _documents = const [];

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

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final clubRow = await _supabase
          .from('clubs')
          .select('events_meetings_addon_enabled')
          .eq('id', widget.club.clubId)
          .single();

      final eventsAddonEnabled =
          clubRow['events_meetings_addon_enabled'] == true;

      if (!eventsAddonEnabled) {
        if (!mounted) return;
        setState(() {
          _eventsAddonEnabled = false;
          _events = const [];
          _documents = const [];
          _isLoading = false;
        });
        return;
      }

      final responses = await Future.wait([
        _supabase
            .from('club_events')
            .select(
              'id,club_id,related_document_id,title,description,event_type,'
              'status,visibility,start_at,end_at,timezone,location_name,'
              'location_address,virtual_url,agenda,notes,requires_rsvp,'
              'rsvp_deadline,created_at,updated_at,'
              'club_event_documents(document_id)',
            )
            .eq('club_id', widget.club.clubId)
            .order('start_at', ascending: true),
        _supabase
            .from('club_documents')
            .select('id,title,status,visibility')
            .eq('club_id', widget.club.clubId)
            .order('title', ascending: true),
      ]);

      final documentRows = responses[1] as List;
      final documents = documentRows
          .whereType<Map>()
          .map(
            (row) => _RelatedDocument.fromJson(Map<String, dynamic>.from(row)),
          )
          .toList();

      final documentMap = <String, _RelatedDocument>{
        for (final document in documents) document.id: document,
      };

      final eventRows = responses[0] as List;
      final events = eventRows.whereType<Map>().map((row) {
        final json = Map<String, dynamic>.from(row);
        final documentId = json['related_document_id']?.toString();
        final relatedDocuments = <String, _RelatedDocument>{};

        final relationshipRows = json['club_event_documents'];
        if (relationshipRows is List) {
          for (final relationshipRow in relationshipRows.whereType<Map>()) {
            final relatedId = relationshipRow['document_id']?.toString();
            final document = relatedId == null ? null : documentMap[relatedId];
            if (document != null) relatedDocuments[document.id] = document;
          }
        }

        // Preserve events that only have the legacy relationship populated.
        final legacyDocument = documentId == null
            ? null
            : documentMap[documentId];
        if (legacyDocument != null) {
          relatedDocuments.putIfAbsent(legacyDocument.id, () => legacyDocument);
        }

        return _ClubEvent.fromJson(
          json,
          relatedDocuments: relatedDocuments.values.toList(),
        );
      }).toList();

      if (!mounted) return;
      setState(() {
        _eventsAddonEnabled = true;
        _events = events;
        _documents = documents;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Unable to load club events: $error';
      });
    }
  }

  List<_ClubEvent> get _filteredEvents {
    final query = _searchController.text.trim().toLowerCase();

    return _events.where((event) {
      final matchesStatus =
          _statusFilter == 'all' || event.status == _statusFilter;
      final matchesType =
          _typeFilter == 'all' || event.eventType == _typeFilter;
      if (!matchesStatus || !matchesType) return false;
      if (query.isEmpty) return true;

      final searchable = [
        event.title,
        event.description,
        event.locationName,
        event.locationAddress,
        event.agenda,
        event.notes,
        ...event.relatedDocuments.map((document) => document.title),
      ].whereType<String>().join(' ').toLowerCase();

      return searchable.contains(query);
    }).toList();
  }

  int _countForStatus(String status) {
    if (status == 'all') return _events.length;
    return _events.where((event) => event.status == status).length;
  }

  void _showLockedFeature() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Meetings & Events Requires an Add-on'),
        content: const Text(
          'Meetings, agendas, and event notices are available with the Events & Meetings Add-on. The club owner can enable this when the club is ready to use it.',
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

  Future<void> _openEditor({_ClubEvent? existing}) async {
    if (!_eventsAddonEnabled) {
      _showLockedFeature();
      return;
    }
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _EventEditorDialog(
        club: widget.club,
        documents: _documents,
        existing: existing,
      ),
    );

    if (changed == true) await _loadData();
  }

  Future<void> _setStatus(_ClubEvent event, String status) async {
    if (!_eventsAddonEnabled) {
      _showLockedFeature();
      return;
    }
    try {
      await _supabase.rpc(
        'set_club_event_status',
        params: {'p_event_id': event.id, 'p_status': status},
      );
      if (status == 'published' && event.status != 'published') {
        await _notifyMembersAboutEvent(event, notificationType: 'published');
      }
      await _loadData();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to update event: $error')));
    }
  }

  Future<void> _notifyMembersAboutEvent(
    _ClubEvent event, {
    required String notificationType,
  }) async {
    await _notifyClubMembersAboutEvent(
      supabase: _supabase,
      communicationsService: _communicationsService,
      club: widget.club,
      event: event,
      notificationType: notificationType,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Meetings & Events'),
        actions: [
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
            : _eventsAddonEnabled
            ? () => _openEditor()
            : _showLockedFeature,
        icon: Icon(_eventsAddonEnabled ? Icons.add : Icons.lock_outline),
        label: Text(_eventsAddonEnabled ? 'Add Event' : 'Add-on Required'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_eventsAddonEnabled) {
      return _LockedAddOnState(
        clubName: widget.club.clubName,
        onRefresh: _loadData,
      );
    }

    if (_errorMessage != null && _events.isEmpty) {
      return _MessageState(
        icon: Icons.error_outline,
        title: 'Unable to load events',
        message: _errorMessage!,
        actionLabel: 'Try Again',
        onAction: _loadData,
      );
    }

    final filtered = _filteredEvents;

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
            'Manage club meetings, events, deadlines, agendas, and visibility.',
            style: Theme.of(context).textTheme.bodyMedium,
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
                      icon: Icons.event_available_outlined,
                      label: 'Published',
                      value: _countForStatus('published').toString(),
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _SummaryCard(
                      icon: Icons.edit_calendar_outlined,
                      label: 'Drafts',
                      value: _countForStatus('draft').toString(),
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _SummaryCard(
                      icon: Icons.event_busy_outlined,
                      label: 'Cancelled',
                      value: _countForStatus('cancelled').toString(),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              labelText: 'Search events',
              hintText: 'Title, description, agenda, location, or document',
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
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 520,
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'all', label: Text('All')),
                    ButtonSegment(value: 'published', label: Text('Published')),
                    ButtonSegment(value: 'draft', label: Text('Drafts')),
                    ButtonSegment(value: 'cancelled', label: Text('Cancelled')),
                    ButtonSegment(value: 'completed', label: Text('Completed')),
                  ],
                  selected: {_statusFilter},
                  onSelectionChanged: (values) {
                    setState(() => _statusFilter = values.first);
                  },
                ),
              ),
              SizedBox(
                width: 260,
                child: DropdownButtonFormField<String>(
                  initialValue: _typeFilter,
                  decoration: const InputDecoration(
                    labelText: 'Event type',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All')),
                    DropdownMenuItem(value: 'meeting', child: Text('Meeting')),
                    DropdownMenuItem(value: 'show', child: Text('Show')),
                    DropdownMenuItem(
                      value: 'deadline',
                      child: Text('Deadline'),
                    ),
                    DropdownMenuItem(value: 'social', child: Text('Social')),
                    DropdownMenuItem(value: 'other', child: Text('Other')),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _typeFilter = value);
                  },
                ),
              ),
            ],
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
          Text(
            '${filtered.length} ${filtered.length == 1 ? 'event' : 'events'}',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          if (_events.isEmpty)
            _InlineEmptyState(
              title: 'No meetings or events yet',
              message:
                  'Add meetings, deadlines, specialty events, or member activities.',
              actionLabel: 'Add Event',
              onAction: () => _openEditor(),
            )
          else if (filtered.isEmpty)
            const _InlineEmptyState(
              title: 'No matching events',
              message: 'Try another search, status, or event type filter.',
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final useTwoColumns = constraints.maxWidth >= 900;
                final width = useTwoColumns
                    ? (constraints.maxWidth - 12) / 2
                    : constraints.maxWidth;

                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final event in filtered)
                      SizedBox(
                        width: width,
                        child: _EventCard(
                          event: event,
                          onEdit: () => _openEditor(existing: event),
                          onPublish: event.status == 'published'
                              ? null
                              : () => _setStatus(event, 'published'),
                          onCancel: event.status == 'cancelled'
                              ? null
                              : () => _setStatus(event, 'cancelled'),
                          onComplete: event.status == 'completed'
                              ? null
                              : () => _setStatus(event, 'completed'),
                        ),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );
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
                    'Events & Meetings Add-on Required',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '$clubName does not currently have the Events & Meetings Add-on enabled.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'This add-on enables meetings, agendas, event notices, and deadlines.',
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

class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.event,
    required this.onEdit,
    this.onPublish,
    this.onCancel,
    this.onComplete,
  });

  final _ClubEvent event;
  final VoidCallback onEdit;
  final VoidCallback? onPublish;
  final VoidCallback? onCancel;
  final VoidCallback? onComplete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final statusColor = _statusColor(event.status, scheme);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(child: Icon(_iconForType(event.eventType))),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          event.title,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        Text(event.dateLabel),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'edit') onEdit();
                      if (value == 'publish') onPublish?.call();
                      if (value == 'cancel') onCancel?.call();
                      if (value == 'complete') onComplete?.call();
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'edit', child: Text('Edit')),
                      if (onPublish != null)
                        const PopupMenuItem(
                          value: 'publish',
                          child: Text('Publish'),
                        ),
                      if (onComplete != null)
                        const PopupMenuItem(
                          value: 'complete',
                          child: Text('Mark Complete'),
                        ),
                      if (onCancel != null)
                        const PopupMenuItem(
                          value: 'cancel',
                          child: Text('Cancel Event'),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(
                    label: Text(_titleCase(event.status)),
                    backgroundColor: statusColor.withAlpha(40),
                    side: BorderSide(color: statusColor),
                  ),
                  Chip(label: Text(_titleCase(event.eventType))),
                  Chip(label: Text(_titleCase(event.visibility))),
                ],
              ),
              if (event.description != null) ...[
                const SizedBox(height: 12),
                Text(
                  event.description!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 12),
              _DetailRow(icon: Icons.schedule_outlined, text: event.timeLabel),
              if (event.locationName != null)
                _DetailRow(
                  icon: Icons.location_on_outlined,
                  text: event.locationName!,
                ),
              if (event.virtualUrl != null)
                _DetailRow(
                  icon: Icons.video_call_outlined,
                  text: event.virtualUrl!,
                ),
              for (final document in event.relatedDocuments)
                _DetailRow(
                  icon: Icons.description_outlined,
                  text: document.title,
                ),
            ],
          ),
        ),
      ),
    );
  }

  static Color _statusColor(String status, ColorScheme scheme) {
    switch (status) {
      case 'published':
        return scheme.primary;
      case 'cancelled':
        return scheme.error;
      case 'completed':
        return scheme.outline;
      default:
        return scheme.tertiary;
    }
  }
}

class _EventEditorDialog extends StatefulWidget {
  const _EventEditorDialog({
    required this.club,
    required this.documents,
    this.existing,
  });

  final ClubSummary club;
  final List<_RelatedDocument> documents;
  final _ClubEvent? existing;

  @override
  State<_EventEditorDialog> createState() => _EventEditorDialogState();
}

class _EventEditorDialogState extends State<_EventEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  final _supabase = Supabase.instance.client;

  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _startAtController;
  late final TextEditingController _endAtController;
  late final TextEditingController _locationNameController;
  late final TextEditingController _locationAddressController;
  late final TextEditingController _virtualUrlController;
  late final TextEditingController _agendaController;
  late final TextEditingController _notesController;
  late List<_RelatedDocument> _documents;
  late final Set<String> _relatedDocumentIds;
  late String _eventType;
  late String _status;
  late String _visibility;
  late String _timezone;
  bool _isSaving = false;
  bool _isLoadingDocuments = false;
  bool _notifyMembers = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;

    _titleController = TextEditingController(text: existing?.title ?? '');
    _descriptionController = TextEditingController(
      text: existing?.description ?? '',
    );
    _startAtController = TextEditingController(
      text: existing == null ? '' : _dateTimeText(existing.startAt),
    );
    _endAtController = TextEditingController(
      text: existing?.endAt == null ? '' : _dateTimeText(existing!.endAt!),
    );
    _timezone = existing?.timezone ?? _deviceTimezone();
    _locationNameController = TextEditingController(
      text: existing?.locationName ?? '',
    );
    _locationAddressController = TextEditingController(
      text: existing?.locationAddress ?? '',
    );
    _virtualUrlController = TextEditingController(
      text: existing?.virtualUrl ?? '',
    );
    _agendaController = TextEditingController(text: existing?.agenda ?? '');
    _notesController = TextEditingController(text: existing?.notes ?? '');
    _documents = List<_RelatedDocument>.of(widget.documents);
    _relatedDocumentIds = {
      ...?existing?.relatedDocuments.map((document) => document.id),
      if (existing?.relatedDocumentId != null) existing!.relatedDocumentId!,
    };
    _eventType = existing?.eventType ?? 'meeting';
    _status = existing?.status ?? 'draft';
    _visibility = existing?.visibility ?? 'members';
    _notifyMembers = existing == null && _status == 'published';
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _startAtController.dispose();
    _endAtController.dispose();
    _locationNameController.dispose();
    _locationAddressController.dispose();
    _virtualUrlController.dispose();
    _agendaController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSaving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final startAt = _parseDateTime(_startAtController.text);
    final endAt = _parseDateTime(_endAtController.text);

    if (startAt == null) {
      setState(() => _errorMessage = 'Start date and time are required.');
      return;
    }

    if (endAt != null && endAt.isBefore(startAt)) {
      setState(() {
        _errorMessage = 'End date and time cannot be before the start.';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final savedEvent = await _supabase.rpc(
        'save_club_event',
        params: {
          'p_event_id': widget.existing?.id,
          'p_club_id': widget.club.clubId,
          // Keep the first selection in the legacy field until all consumers
          // have moved to club_event_documents.
          'p_related_document_id': _relatedDocumentIds.firstOrNull,
          'p_related_document_ids': _relatedDocumentIds.toList(),
          'p_title': _titleController.text.trim(),
          'p_description': _nullIfBlank(_descriptionController.text),
          'p_event_type': _eventType,
          'p_status': _status,
          'p_visibility': _visibility,
          'p_start_at': startAt.toIso8601String(),
          'p_end_at': endAt?.toIso8601String(),
          'p_timezone': _timezone,
          'p_location_name': _nullIfBlank(_locationNameController.text),
          'p_location_address': _nullIfBlank(_locationAddressController.text),
          'p_virtual_url': _nullIfBlank(_virtualUrlController.text),
          'p_agenda': _nullIfBlank(_agendaController.text),
          'p_notes': _nullIfBlank(_notesController.text),
          'p_requires_rsvp': false,
          'p_rsvp_deadline': null,
        },
      );

      if (_notifyMembers && _status == 'published') {
        final eventId =
            widget.existing?.id ??
            _eventIdFromSaveResponse(savedEvent) ??
            await _findSavedEventId(
              title: _titleController.text.trim(),
              startAt: startAt,
            );
        if (eventId != null) {
          await _notifyClubMembersAboutEvent(
            supabase: _supabase,
            communicationsService: ClubCommunicationsService(),
            club: widget.club,
            event: _eventForNotification(eventId, startAt, endAt),
            notificationType: widget.existing?.status == 'published'
                ? 'updated'
                : 'published',
          );
        }
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorMessage = 'Unable to save event: $error';
      });
    }
  }

  Future<String?> _findSavedEventId({
    required String title,
    required DateTime startAt,
  }) async {
    final rows = await _supabase
        .from('club_events')
        .select('id')
        .eq('club_id', widget.club.clubId)
        .eq('title', title)
        .eq('start_at', startAt.toIso8601String())
        .order('created_at', ascending: false)
        .limit(1);
    if (rows.isEmpty) return null;
    return _nullableString(rows.first['id']);
  }

  _ClubEvent _eventForNotification(
    String eventId,
    DateTime startAt,
    DateTime? endAt,
  ) {
    return _ClubEvent(
      id: eventId,
      title: _titleController.text.trim(),
      description: _nullIfBlank(_descriptionController.text),
      eventType: _eventType,
      status: _status,
      visibility: _visibility,
      startAt: startAt,
      endAt: endAt,
      timezone: _timezone,
      locationName: _nullIfBlank(_locationNameController.text),
      locationAddress: _nullIfBlank(_locationAddressController.text),
      virtualUrl: _nullIfBlank(_virtualUrlController.text),
      agenda: _nullIfBlank(_agendaController.text),
      notes: _nullIfBlank(_notesController.text),
      relatedDocuments: _documents
          .where((document) => _relatedDocumentIds.contains(document.id))
          .toList(),
      requiresRsvp: false,
      createdAt: widget.existing?.createdAt ?? DateTime.now(),
    );
  }

  Future<void> _pickDateTime(TextEditingController controller) async {
    final initial =
        _parseDateTime(controller.text) ??
        DateTime.now().add(const Duration(hours: 1));

    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: DateTime(2200),
    );

    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );

    if (time == null) return;

    controller.text = _dateTimeText(
      DateTime(date.year, date.month, date.day, time.hour, time.minute),
    );
    setState(() {});
  }

  Future<void> _chooseRelatedDocuments() async {
    final selected = Set<String>.of(_relatedDocumentIds);
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Select Related Documents'),
          content: SizedBox(
            width: 520,
            child: _documents.isEmpty
                ? const Text(
                    'No documents are available yet. Use Add Document to upload '
                    'or save one to the club account.',
                  )
                : ListView(
                    shrinkWrap: true,
                    children: [
                      for (final document in _documents)
                        CheckboxListTile(
                          value: selected.contains(document.id),
                          title: Text(document.title),
                          subtitle: Text(
                            '${_titleCase(document.status)} · '
                            '${_titleCase(document.visibility)}',
                          ),
                          onChanged: (checked) {
                            setDialogState(() {
                              if (checked == true) {
                                selected.add(document.id);
                              } else {
                                selected.remove(document.id);
                              }
                            });
                          },
                        ),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(selected),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _relatedDocumentIds
          ..clear()
          ..addAll(result);
      });
    }
  }

  Future<void> _openDocuments() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          Dialog.fullscreen(child: ClubDocumentsScreen(club: widget.club)),
    );
    if (!mounted) return;

    setState(() => _isLoadingDocuments = true);
    try {
      final rows = await _supabase
          .from('club_documents')
          .select('id,title,status,visibility')
          .eq('club_id', widget.club.clubId)
          .order('title', ascending: true);
      final documents = rows
          .whereType<Map>()
          .map(
            (row) => _RelatedDocument.fromJson(Map<String, dynamic>.from(row)),
          )
          .toList();
      if (!mounted) return;
      setState(() => _documents = documents);
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Unable to refresh documents: $error');
    } finally {
      if (mounted) setState(() => _isLoadingDocuments = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Add Event' : 'Edit Event'),
      content: SizedBox(
        width: 780,
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
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: 'Event title',
                    border: OutlineInputBorder(),
                  ),
                  validator: _required,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _descriptionController,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                _ResponsiveFields(
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: _eventType,
                      decoration: const InputDecoration(
                        labelText: 'Event type',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'meeting',
                          child: Text('Meeting'),
                        ),
                        DropdownMenuItem(value: 'show', child: Text('Show')),
                        DropdownMenuItem(
                          value: 'deadline',
                          child: Text('Deadline'),
                        ),
                        DropdownMenuItem(
                          value: 'social',
                          child: Text('Social'),
                        ),
                        DropdownMenuItem(value: 'other', child: Text('Other')),
                      ],
                      onChanged: _isSaving
                          ? null
                          : (value) {
                              if (value != null) {
                                setState(() => _eventType = value);
                              }
                            },
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: _status,
                      decoration: const InputDecoration(
                        labelText: 'Status',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'draft', child: Text('Draft')),
                        DropdownMenuItem(
                          value: 'published',
                          child: Text('Published'),
                        ),
                        DropdownMenuItem(
                          value: 'cancelled',
                          child: Text('Cancelled'),
                        ),
                        DropdownMenuItem(
                          value: 'completed',
                          child: Text('Completed'),
                        ),
                      ],
                      onChanged: _isSaving
                          ? null
                          : (value) {
                              if (value != null) {
                                setState(() {
                                  _status = value;
                                  if (value == 'published' &&
                                      widget.existing?.status != 'published') {
                                    _notifyMembers = true;
                                  }
                                });
                              }
                            },
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: _visibility,
                      decoration: const InputDecoration(
                        labelText: 'Visibility',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'public',
                          child: Text('Public'),
                        ),
                        DropdownMenuItem(
                          value: 'members',
                          child: Text('Members Only'),
                        ),
                        DropdownMenuItem(
                          value: 'staff',
                          child: Text('Staff Only'),
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
                if (_status == 'published') ...[
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _notifyMembers,
                    onChanged: _isSaving
                        ? null
                        : (value) =>
                              setState(() => _notifyMembers = value ?? false),
                    title: const Text('Notify active members'),
                    subtitle: Text(
                      widget.existing?.status == 'published'
                          ? 'Send an event-update notification and email, when enabled.'
                          : 'Send a new-event notification and email, when enabled.',
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Related documents (optional)',
                    border: OutlineInputBorder(),
                  ),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (_relatedDocumentIds.isEmpty)
                        const Text('No related documents selected'),
                      for (final document in _documents.where(
                        (document) => _relatedDocumentIds.contains(document.id),
                      ))
                        InputChip(
                          label: Text(document.title),
                          onDeleted: _isSaving
                              ? null
                              : () => setState(
                                  () => _relatedDocumentIds.remove(document.id),
                                ),
                        ),
                      OutlinedButton.icon(
                        onPressed: _isSaving ? null : _chooseRelatedDocuments,
                        icon: const Icon(Icons.attach_file),
                        label: const Text('Select Documents'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _isSaving || _isLoadingDocuments
                        ? null
                        : _openDocuments,
                    icon: _isLoadingDocuments
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.note_add_outlined),
                    label: Text(
                      _isLoadingDocuments
                          ? 'Refreshing Documents...'
                          : 'Add Document',
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                _SectionTitle('Date & Location'),
                _ResponsiveFields(
                  children: [
                    _DateTimeField(
                      controller: _startAtController,
                      label: 'Start date/time',
                      onPick: () => _pickDateTime(_startAtController),
                    ),
                    _DateTimeField(
                      controller: _endAtController,
                      label: 'End date/time (optional)',
                      onPick: () => _pickDateTime(_endAtController),
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: _timezone,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Timezone',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final timezone in _timezoneChoices(_timezone))
                          DropdownMenuItem(
                            value: timezone,
                            child: Text(
                              timezone.replaceAll('_', ' '),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: _isSaving
                          ? null
                          : (value) {
                              if (value != null) {
                                setState(() => _timezone = value);
                              }
                            },
                    ),
                    TextFormField(
                      controller: _locationNameController,
                      decoration: const InputDecoration(
                        labelText: 'Location name (optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _locationAddressController,
                  decoration: const InputDecoration(
                    labelText: 'Location address (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _virtualUrlController,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Virtual meeting link (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 18),
                _SectionTitle('Agenda & Notes'),
                TextFormField(
                  controller: _agendaController,
                  minLines: 3,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    labelText: 'Agenda (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _notesController,
                  minLines: 3,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    labelText: 'Event notes (optional)',
                    helperText:
                        'These notes may be included in event communications.',
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

class _ClubEvent {
  const _ClubEvent({
    required this.id,
    required this.title,
    required this.eventType,
    required this.status,
    required this.visibility,
    required this.startAt,
    required this.timezone,
    required this.requiresRsvp,
    required this.createdAt,
    this.relatedDocuments = const [],
    this.relatedDocumentId,
    this.description,
    this.endAt,
    this.locationName,
    this.locationAddress,
    this.virtualUrl,
    this.agenda,
    this.notes,
    this.rsvpDeadline,
  });

  final String id;
  final String? relatedDocumentId;
  final List<_RelatedDocument> relatedDocuments;
  final String title;
  final String? description;
  final String eventType;
  final String status;
  final String visibility;
  final DateTime startAt;
  final DateTime? endAt;
  final String timezone;
  final String? locationName;
  final String? locationAddress;
  final String? virtualUrl;
  final String? agenda;
  final String? notes;
  final bool requiresRsvp;
  final DateTime? rsvpDeadline;
  final DateTime createdAt;

  String get dateLabel {
    if (endAt == null || _sameDay(startAt, endAt!)) {
      return _formatDate(startAt);
    }
    return '${_formatDate(startAt)} – ${_formatDate(endAt!)}';
  }

  String get timeLabel {
    if (endAt == null) {
      return _formatDateTime(startAt);
    }
    return '${_formatDateTime(startAt)} – ${_formatDateTime(endAt!)}';
  }

  factory _ClubEvent.fromJson(
    Map<String, dynamic> json, {
    List<_RelatedDocument> relatedDocuments = const [],
  }) {
    return _ClubEvent(
      id: json['id'].toString(),
      relatedDocumentId: _nullableString(json['related_document_id']),
      relatedDocuments: relatedDocuments,
      title: _nullableString(json['title']) ?? 'Untitled Event',
      description: _nullableString(json['description']),
      eventType: _nullableString(json['event_type']) ?? 'meeting',
      status: _nullableString(json['status']) ?? 'draft',
      visibility: _nullableString(json['visibility']) ?? 'members',
      startAt: _nullableDate(json['start_at']) ?? DateTime.now(),
      endAt: _nullableDate(json['end_at']),
      timezone: _nullableString(json['timezone']) ?? 'America/New_York',
      locationName: _nullableString(json['location_name']),
      locationAddress: _nullableString(json['location_address']),
      virtualUrl: _nullableString(json['virtual_url']),
      agenda: _nullableString(json['agenda']),
      notes: _nullableString(json['notes']),
      requiresRsvp: json['requires_rsvp'] == true,
      rsvpDeadline: _nullableDate(json['rsvp_deadline']),
      createdAt: _nullableDate(json['created_at']) ?? DateTime.now(),
    );
  }
}

class _RelatedDocument {
  const _RelatedDocument({
    required this.id,
    required this.title,
    required this.status,
    required this.visibility,
  });

  final String id;
  final String title;
  final String status;
  final String visibility;

  factory _RelatedDocument.fromJson(Map<String, dynamic> json) {
    return _RelatedDocument(
      id: json['id'].toString(),
      title: _nullableString(json['title']) ?? 'Untitled Document',
      status: _nullableString(json['status']) ?? 'draft',
      visibility: _nullableString(json['visibility']) ?? 'members',
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

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
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

class _DateTimeField extends StatelessWidget {
  const _DateTimeField({
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
              tooltip: 'Choose date and time',
              onPressed: onPick,
              icon: const Icon(Icons.schedule_outlined),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
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
            const Icon(Icons.event_note_outlined, size: 52),
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

IconData _iconForType(String type) {
  switch (type) {
    case 'meeting':
      return Icons.groups_outlined;
    case 'show':
      return Icons.emoji_events_outlined;
    case 'deadline':
      return Icons.alarm_outlined;
    case 'social':
      return Icons.celebration_outlined;
    default:
      return Icons.event_note_outlined;
  }
}

String? _nullableString(dynamic value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

Future<void> _notifyClubMembersAboutEvent({
  required SupabaseClient supabase,
  required ClubCommunicationsService communicationsService,
  required ClubSummary club,
  required _ClubEvent event,
  required String notificationType,
}) async {
  try {
    final memberRows = await supabase
        .from('club_memberships')
        .select('user_id,first_name,last_name,showing_name,email')
        .eq('club_id', club.clubId)
        .eq('status', 'active');

    final recipients = memberRows.whereType<Map>().map((row) {
      final member = Map<String, dynamic>.from(row);
      return ClubCommunicationRecipient(
        userId: _nullableString(member['user_id']),
        email: _nullableString(member['email']),
        name: _eventRecipientName(member),
      );
    }).toList();

    await communicationsService.createWorkflowCommunications(
      clubId: club.clubId,
      clubName: club.clubName,
      templateKey: notificationType == 'updated'
          ? 'event_updated'
          : 'event_published',
      relatedType: 'club_event',
      relatedId: event.id,
      recipients: recipients,
      audienceType: 'active_members',
      messageKind: 'event_notice',
      variables: _eventCommunicationVariables(event),
      preferEmailWhenAvailable: true,
      createdBy: supabase.auth.currentUser?.id,
    );
  } catch (error) {
    debugPrint('Unable to create event communication: $error');
  }
}

String _eventRecipientName(Map<String, dynamic> member) {
  final showingName = _nullableString(member['showing_name']);
  if (showingName != null) return showingName;
  final name = [
    _nullableString(member['first_name']),
    _nullableString(member['last_name']),
  ].whereType<String>().join(' ');
  return name.isEmpty ? 'Member' : name;
}

Map<String, String> _eventCommunicationVariables(_ClubEvent event) {
  return {
    'event_title': event.title,
    'event_type': _titleCase(event.eventType),
    'event_date': event.dateLabel,
    'event_time': event.timeLabel,
    'event_timezone': event.timezone,
    'event_location': event.locationName ?? event.locationAddress ?? '',
    'event_address': event.locationAddress ?? '',
    'event_virtual_url': event.virtualUrl ?? '',
    'event_description': event.description ?? '',
    'event_agenda': event.agenda ?? '',
    'event_notes': event.notes ?? '',
  };
}

String? _eventIdFromSaveResponse(dynamic response) {
  if (response is String) return _nullableString(response);
  if (response is Map) return _nullableString(response['id']);
  if (response is List && response.isNotEmpty && response.first is Map) {
    return _nullableString((response.first as Map)['id']);
  }
  return null;
}

DateTime? _nullableDate(dynamic value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) return null;
  return DateTime.tryParse(text);
}

DateTime? _parseDateTime(String value) {
  final text = value.trim();
  if (text.isEmpty) return null;
  return DateTime.tryParse(text);
}

String _dateTimeText(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '${value.year}-$month-$day $hour:$minute';
}

String _formatDate(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '$month/$day/${value.year}';
}

String _formatDateTime(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  final hour = value.hour == 0
      ? 12
      : value.hour > 12
      ? value.hour - 12
      : value.hour;
  final minute = value.minute.toString().padLeft(2, '0');
  final meridiem = value.hour >= 12 ? 'PM' : 'AM';
  return '$month/$day/${value.year} $hour:$minute $meridiem';
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

bool _sameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

const _timezones = <String>[
  'UTC',
  'Pacific/Honolulu',
  'America/Anchorage',
  'America/Los_Angeles',
  'America/Phoenix',
  'America/Denver',
  'America/Chicago',
  'America/New_York',
  'America/Halifax',
  'America/St_Johns',
  'America/Puerto_Rico',
  'America/Mexico_City',
  'America/Bogota',
  'America/Lima',
  'America/Caracas',
  'America/Santiago',
  'America/Sao_Paulo',
  'America/Argentina/Buenos_Aires',
  'Atlantic/Azores',
  'Europe/London',
  'Europe/Paris',
  'Europe/Berlin',
  'Europe/Athens',
  'Europe/Helsinki',
  'Europe/Moscow',
  'Africa/Cairo',
  'Africa/Johannesburg',
  'Asia/Dubai',
  'Asia/Karachi',
  'Asia/Kolkata',
  'Asia/Dhaka',
  'Asia/Bangkok',
  'Asia/Singapore',
  'Asia/Hong_Kong',
  'Asia/Shanghai',
  'Asia/Tokyo',
  'Asia/Seoul',
  'Australia/Perth',
  'Australia/Adelaide',
  'Australia/Darwin',
  'Australia/Brisbane',
  'Australia/Sydney',
  'Pacific/Auckland',
];

List<String> _timezoneChoices(String selected) {
  if (_timezones.contains(selected)) return _timezones;
  return [selected, ..._timezones];
}

String _deviceTimezone() {
  final now = DateTime.now();
  final reportedName = now.timeZoneName.trim();

  // Some platforms report an IANA identifier directly. Others, including many
  // browsers, expose only an abbreviation, so use its current UTC offset.
  if (reportedName.contains('/')) return reportedName;

  const names = <String, String>{
    'UTC': 'UTC',
    'GMT': 'UTC',
    'HST': 'Pacific/Honolulu',
    'AKST': 'America/Anchorage',
    'AKDT': 'America/Anchorage',
    'PST': 'America/Los_Angeles',
    'PDT': 'America/Los_Angeles',
    'MST': 'America/Denver',
    'MDT': 'America/Denver',
    'CST': 'America/Chicago',
    'CDT': 'America/Chicago',
    'EST': 'America/New_York',
    'EDT': 'America/New_York',
    'EASTERN STANDARD TIME': 'America/New_York',
    'EASTERN DAYLIGHT TIME': 'America/New_York',
    'CENTRAL STANDARD TIME': 'America/Chicago',
    'CENTRAL DAYLIGHT TIME': 'America/Chicago',
    'MOUNTAIN STANDARD TIME': 'America/Denver',
    'MOUNTAIN DAYLIGHT TIME': 'America/Denver',
    'PACIFIC STANDARD TIME': 'America/Los_Angeles',
    'PACIFIC DAYLIGHT TIME': 'America/Los_Angeles',
  };
  final namedTimezone = names[reportedName.toUpperCase()];
  if (namedTimezone != null) return namedTimezone;

  final offsetMinutes = now.timeZoneOffset.inMinutes;
  const offsets = <int, String>{
    -600: 'Pacific/Honolulu',
    -540: 'America/Anchorage',
    -480: 'America/Los_Angeles',
    -420: 'America/Denver',
    -360: 'America/Chicago',
    -300: 'America/New_York',
    -240: 'America/Halifax',
    -210: 'America/St_Johns',
    -180: 'America/Sao_Paulo',
    -60: 'Atlantic/Azores',
    0: 'UTC',
    60: 'Europe/Paris',
    120: 'Europe/Athens',
    180: 'Europe/Moscow',
    240: 'Asia/Dubai',
    300: 'Asia/Karachi',
    330: 'Asia/Kolkata',
    360: 'Asia/Dhaka',
    420: 'Asia/Bangkok',
    480: 'Asia/Singapore',
    540: 'Asia/Tokyo',
    570: 'Australia/Adelaide',
    600: 'Australia/Sydney',
    720: 'Pacific/Auckland',
  };
  return offsets[offsetMinutes] ?? 'UTC';
}
