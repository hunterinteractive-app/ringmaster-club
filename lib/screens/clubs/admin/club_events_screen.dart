// lib/screens/clubs/admin/club_events_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/clubs/club_summary.dart';

class ClubEventsScreen extends StatefulWidget {
  const ClubEventsScreen({
    super.key,
    required this.club,
  });

  final ClubSummary club;

  @override
  State<ClubEventsScreen> createState() => _ClubEventsScreenState();
}

class _ClubEventsScreenState extends State<ClubEventsScreen> {
  final _supabase = Supabase.instance.client;
  final _searchController = TextEditingController();

  bool _isLoading = true;
  String? _errorMessage;
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
      final responses = await Future.wait([
        _supabase
            .from('club_events')
            .select(
              'id,club_id,related_document_id,title,description,event_type,'
              'status,visibility,start_at,end_at,timezone,location_name,'
              'location_address,virtual_url,agenda,notes,requires_rsvp,'
              'rsvp_deadline,created_at,updated_at',
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
            (row) => _RelatedDocument.fromJson(
              Map<String, dynamic>.from(row),
            ),
          )
          .toList();

      final documentMap = <String, _RelatedDocument>{
        for (final document in documents) document.id: document,
      };

      final eventRows = responses[0] as List;
      final events = eventRows
          .whereType<Map>()
          .map((row) {
            final json = Map<String, dynamic>.from(row);
            final documentId = json['related_document_id']?.toString();
            return _ClubEvent.fromJson(
              json,
              relatedDocument:
                  documentId == null ? null : documentMap[documentId],
            );
          })
          .toList();

      if (!mounted) return;
      setState(() {
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
      final matchesType = _typeFilter == 'all' || event.eventType == _typeFilter;
      if (!matchesStatus || !matchesType) return false;
      if (query.isEmpty) return true;

      final searchable = [
        event.title,
        event.description,
        event.locationName,
        event.locationAddress,
        event.agenda,
        event.notes,
        event.relatedDocument?.title,
      ].whereType<String>().join(' ').toLowerCase();

      return searchable.contains(query);
    }).toList();
  }

  int _countForStatus(String status) {
    if (status == 'all') return _events.length;
    return _events.where((event) => event.status == status).length;
  }

  Future<void> _openEditor({_ClubEvent? existing}) async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _EventEditorDialog(
        clubId: widget.club.clubId,
        documents: _documents,
        existing: existing,
      ),
    );

    if (changed == true) await _loadData();
  }

  Future<void> _setStatus(_ClubEvent event, String status) async {
    try {
      await _supabase.rpc(
        'set_club_event_status',
        params: {
          'p_event_id': event.id,
          'p_status': status,
        },
      );
      await _loadData();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to update event: $error')),
      );
    }
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
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('Add Event'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
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
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
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
                    DropdownMenuItem(value: 'deadline', child: Text('Deadline')),
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
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
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
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
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
                  if (event.requiresRsvp)
                    const Chip(
                      avatar: Icon(Icons.how_to_reg_outlined, size: 18),
                      label: Text('RSVP'),
                    ),
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
              if (event.relatedDocument != null)
                _DetailRow(
                  icon: Icons.description_outlined,
                  text: event.relatedDocument!.title,
                ),
              if (event.rsvpDeadline != null)
                _DetailRow(
                  icon: Icons.event_busy_outlined,
                  text: 'RSVP by ${_formatDateTime(event.rsvpDeadline!)}',
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
    required this.clubId,
    required this.documents,
    this.existing,
  });

  final String clubId;
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
  late final TextEditingController _timezoneController;
  late final TextEditingController _locationNameController;
  late final TextEditingController _locationAddressController;
  late final TextEditingController _virtualUrlController;
  late final TextEditingController _agendaController;
  late final TextEditingController _notesController;
  late final TextEditingController _rsvpDeadlineController;

  String? _relatedDocumentId;
  late String _eventType;
  late String _status;
  late String _visibility;
  bool _requiresRsvp = false;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;

    _titleController = TextEditingController(text: existing?.title ?? '');
    _descriptionController =
        TextEditingController(text: existing?.description ?? '');
    _startAtController = TextEditingController(
      text: existing == null ? '' : _dateTimeText(existing.startAt),
    );
    _endAtController = TextEditingController(
      text: existing?.endAt == null ? '' : _dateTimeText(existing!.endAt!),
    );
    _timezoneController =
        TextEditingController(text: existing?.timezone ?? 'America/New_York');
    _locationNameController =
        TextEditingController(text: existing?.locationName ?? '');
    _locationAddressController =
        TextEditingController(text: existing?.locationAddress ?? '');
    _virtualUrlController =
        TextEditingController(text: existing?.virtualUrl ?? '');
    _agendaController = TextEditingController(text: existing?.agenda ?? '');
    _notesController = TextEditingController(text: existing?.notes ?? '');
    _rsvpDeadlineController = TextEditingController(
      text: existing?.rsvpDeadline == null
          ? ''
          : _dateTimeText(existing!.rsvpDeadline!),
    );

    _relatedDocumentId = existing?.relatedDocumentId;
    _eventType = existing?.eventType ?? 'meeting';
    _status = existing?.status ?? 'draft';
    _visibility = existing?.visibility ?? 'members';
    _requiresRsvp = existing?.requiresRsvp ?? false;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _startAtController.dispose();
    _endAtController.dispose();
    _timezoneController.dispose();
    _locationNameController.dispose();
    _locationAddressController.dispose();
    _virtualUrlController.dispose();
    _agendaController.dispose();
    _notesController.dispose();
    _rsvpDeadlineController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSaving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final startAt = _parseDateTime(_startAtController.text);
    final endAt = _parseDateTime(_endAtController.text);
    final rsvpDeadline = _parseDateTime(_rsvpDeadlineController.text);

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

    if (_requiresRsvp &&
        rsvpDeadline != null &&
        rsvpDeadline.isAfter(startAt)) {
      setState(() {
        _errorMessage = 'RSVP deadline cannot be after the event starts.';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      await _supabase.rpc(
        'save_club_event',
        params: {
          'p_event_id': widget.existing?.id,
          'p_club_id': widget.clubId,
          'p_related_document_id': _relatedDocumentId,
          'p_title': _titleController.text.trim(),
          'p_description': _nullIfBlank(_descriptionController.text),
          'p_event_type': _eventType,
          'p_status': _status,
          'p_visibility': _visibility,
          'p_start_at': startAt.toIso8601String(),
          'p_end_at': endAt?.toIso8601String(),
          'p_timezone': _nullIfBlank(_timezoneController.text) ?? 'America/New_York',
          'p_location_name': _nullIfBlank(_locationNameController.text),
          'p_location_address': _nullIfBlank(_locationAddressController.text),
          'p_virtual_url': _nullIfBlank(_virtualUrlController.text),
          'p_agenda': _nullIfBlank(_agendaController.text),
          'p_notes': _nullIfBlank(_notesController.text),
          'p_requires_rsvp': _requiresRsvp,
          'p_rsvp_deadline': _requiresRsvp
              ? rsvpDeadline?.toIso8601String()
              : null,
        },
      );

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

  Future<void> _pickDateTime(TextEditingController controller) async {
    final initial = _parseDateTime(controller.text) ??
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
                    labelText: 'Description',
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
                        DropdownMenuItem(value: 'meeting', child: Text('Meeting')),
                        DropdownMenuItem(value: 'show', child: Text('Show')),
                        DropdownMenuItem(value: 'deadline', child: Text('Deadline')),
                        DropdownMenuItem(value: 'social', child: Text('Social')),
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
                              if (value != null) setState(() => _status = value);
                            },
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: _visibility,
                      decoration: const InputDecoration(
                        labelText: 'Visibility',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'public', child: Text('Public')),
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
                    DropdownButtonFormField<String>(
                      initialValue: _relatedDocumentId,
                      decoration: const InputDecoration(
                        labelText: 'Related document',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem<String>(
                          value: null,
                          child: Text('No related document'),
                        ),
                        for (final document in widget.documents)
                          DropdownMenuItem(
                            value: document.id,
                            child: Text(document.title),
                          ),
                      ],
                      onChanged: _isSaving
                          ? null
                          : (value) => setState(() => _relatedDocumentId = value),
                    ),
                  ],
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
                      label: 'End date/time',
                      onPick: () => _pickDateTime(_endAtController),
                    ),
                    TextFormField(
                      controller: _timezoneController,
                      decoration: const InputDecoration(
                        labelText: 'Timezone',
                        hintText: 'America/New_York',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    TextFormField(
                      controller: _locationNameController,
                      decoration: const InputDecoration(
                        labelText: 'Location name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _locationAddressController,
                  decoration: const InputDecoration(
                    labelText: 'Location address',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _virtualUrlController,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Virtual meeting link',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 18),
                _SectionTitle('Agenda & RSVP'),
                TextFormField(
                  controller: _agendaController,
                  minLines: 3,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    labelText: 'Agenda',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _notesController,
                  minLines: 3,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    labelText: 'Internal notes',
                    border: OutlineInputBorder(),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Track RSVP later'),
                  subtitle: const Text(
                    'This stores RSVP settings now. RSVP response tracking can be added later.',
                  ),
                  value: _requiresRsvp,
                  onChanged: _isSaving
                      ? null
                      : (value) => setState(() => _requiresRsvp = value),
                ),
                if (_requiresRsvp)
                  _DateTimeField(
                    controller: _rsvpDeadlineController,
                    label: 'RSVP deadline',
                    onPick: () => _pickDateTime(_rsvpDeadlineController),
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
    this.relatedDocumentId,
    this.relatedDocument,
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
  final _RelatedDocument? relatedDocument;
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
    _RelatedDocument? relatedDocument,
  }) {
    return _ClubEvent(
      id: json['id'].toString(),
      relatedDocumentId: _nullableString(json['related_document_id']),
      relatedDocument: relatedDocument,
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
  const _DetailRow({
    required this.icon,
    required this.text,
  });

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
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
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
            const Icon(Icons.event_note_outlined, size: 52),
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
