

// lib/screens/clubs/admin/club_communications_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/clubs/club_summary.dart';

class ClubCommunicationsScreen extends StatefulWidget {
  const ClubCommunicationsScreen({
    super.key,
    required this.club,
  });

  final ClubSummary club;

  @override
  State<ClubCommunicationsScreen> createState() =>
      _ClubCommunicationsScreenState();
}

class _ClubCommunicationsScreenState extends State<ClubCommunicationsScreen> {
  final _supabase = Supabase.instance.client;
  final _searchController = TextEditingController();

  bool _isLoading = true;
  String? _errorMessage;
  String _statusFilter = 'all';
  bool _emailAddonEnabled = false;
  List<_CommunicationRecord> _communications = const [];
  List<_CommunicationTemplate> _templates = const [];

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
            .from('club_communications')
            .select(
              'id,club_id,subject,message,recipient_group,channel,status,'
              'email_status,scheduled_at,published_at,sent_at,last_error,'
              'recipient_count,failed_count,created_at,updated_at',
            )
            .eq('club_id', widget.club.clubId)
            .order('created_at', ascending: false),
        _supabase
            .from('club_communication_templates')
            .select(
              'id,club_id,name,template_key,subject,message,is_active,created_at',
            )
            .eq('club_id', widget.club.clubId)
            .order('name', ascending: true),
        _supabase
            .from('clubs')
            .select('email_addon_enabled')
            .eq('id', widget.club.clubId)
            .single(),
      ]);

      final communicationRows = responses[0] as List;
      final templateRows = responses[1] as List;
      final clubRow = Map<String, dynamic>.from(responses[2] as Map);
      final emailAddonEnabled = clubRow['email_addon_enabled'] == true;

      if (!mounted) return;

      setState(() {
        _emailAddonEnabled = emailAddonEnabled;
        _communications = communicationRows
            .whereType<Map>()
            .map(
              (row) => _CommunicationRecord.fromJson(
                Map<String, dynamic>.from(row),
              ),
            )
            .toList();
        _templates = templateRows
            .whereType<Map>()
            .map(
              (row) => _CommunicationTemplate.fromJson(
                Map<String, dynamic>.from(row),
              ),
            )
            .toList();
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _errorMessage = 'Unable to load communications: $error';
      });
    }
  }

  List<_CommunicationRecord> get _filteredCommunications {
    final query = _searchController.text.trim().toLowerCase();

    return _communications.where((record) {
      final matchesStatus = _statusFilter == 'all' ||
          record.status == _statusFilter ||
          record.emailStatus == _statusFilter;
      if (!matchesStatus) return false;
      if (query.isEmpty) return true;

      final searchable = [
        record.subject,
        record.message,
        record.recipientGroup,
        record.channel,
        record.emailStatus,
      ].join(' ').toLowerCase();

      return searchable.contains(query);
    }).toList();
  }

  int _countForStatus(String status) {
    if (status == 'all') return _communications.length;
    return _communications.where((record) => record.status == status).length;
  }

  Future<void> _openComposer({_CommunicationRecord? existing}) async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CommunicationComposerDialog(
        clubId: widget.club.clubId,
        templates: _templates,
        emailAddonEnabled: _emailAddonEnabled,
        existing: existing,
      ),
    );

    if (changed == true) {
      await _loadData();
    }
  }

  Future<void> _openTemplates() async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _TemplateManagerDialog(
        clubId: widget.club.clubId,
        templates: _templates,
      ),
    );

    if (changed == true) {
      await _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Communications'),
        actions: [
          IconButton(
            tooltip: 'Manage Templates',
            onPressed: _isLoading ? null : _openTemplates,
            icon: const Icon(Icons.description_outlined),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _loadData,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openComposer(),
        icon: const Icon(Icons.edit_outlined),
        label: const Text('New Message'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null && _communications.isEmpty) {
      return _MessageState(
        icon: Icons.error_outline,
        title: 'Unable to load communications',
        message: _errorMessage!,
        actionLabel: 'Try Again',
        onAction: _loadData,
      );
    }

    final filtered = _filteredCommunications;

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
            'Create member notices, communication records, and reusable templates. Email delivery is available as an add-on.',
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
                      icon: Icons.drafts_outlined,
                      label: 'Drafts',
                      value: _countForStatus('draft').toString(),
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _SummaryCard(
                      icon: Icons.campaign_outlined,
                      label: 'Published',
                      value: _countForStatus('published').toString(),
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _SummaryCard(
                      icon: Icons.outbox_outlined,
                      label: 'Queued Email',
                      value: _communications
                          .where((record) => record.emailStatus == 'queued')
                          .length
                          .toString(),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          _EmailAddonNotice(enabled: _emailAddonEnabled),
          const SizedBox(height: 16),
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              labelText: 'Search communications',
              hintText: 'Subject, message, or recipient group',
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
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'all', label: Text('All')),
                ButtonSegment(value: 'draft', label: Text('Drafts')),
                ButtonSegment(value: 'published', label: Text('Published')),
                ButtonSegment(value: 'queued', label: Text('Queued')),
                ButtonSegment(value: 'failed', label: Text('Failed')),
              ],
              selected: {_statusFilter},
              onSelectionChanged: (values) {
                setState(() => _statusFilter = values.first);
              },
            ),
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
            '${filtered.length} ${filtered.length == 1 ? 'message' : 'messages'}',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 12),
          if (_communications.isEmpty)
            _InlineEmptyState(
              title: 'No communications yet',
              message:
                  'Create an in-app member notice or communication record. Email delivery can be added later with the Email Add-on.',
              actionLabel: 'Create Message',
              onAction: () => _openComposer(),
            )
          else if (filtered.isEmpty)
            const _InlineEmptyState(
              title: 'No matching communications',
              message: 'Try another search or status filter.',
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
                    for (final record in filtered)
                      SizedBox(
                        width: width,
                        child: _CommunicationCard(
                          record: record,
                          onEdit: () => _openComposer(existing: record),
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

class _CommunicationCard extends StatelessWidget {
  const _CommunicationCard({
    required this.record,
    required this.onEdit,
  });

  final _CommunicationRecord record;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final statusColor = _statusColor(record.status, scheme);

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
                  CircleAvatar(
                    child: Icon(
                      record.usesEmail
                          ? Icons.mark_email_read_outlined
                          : Icons.campaign_outlined,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          record.subject,
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        Text(
                          '${_titleCase(record.recipientGroup)} • ${record.channelLabel}',
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Open message',
                    onPressed: onEdit,
                    icon: const Icon(Icons.open_in_new),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(
                    label: Text(_titleCase(record.status)),
                    backgroundColor: statusColor.withAlpha(40),
                    side: BorderSide(color: statusColor),
                  ),
                  Chip(
                    avatar: Icon(
                      record.usesEmail
                          ? Icons.email_outlined
                          : Icons.campaign_outlined,
                      size: 18,
                    ),
                    label: Text(record.channelLabel),
                  ),
                  if (record.usesEmail)
                    Chip(
                      avatar: const Icon(Icons.outbox_outlined, size: 18),
                      label: Text('Email ${_titleCase(record.emailStatus)}'),
                    ),
                  if (record.recipientCount != null)
                    Chip(
                      avatar: const Icon(Icons.people_outline, size: 18),
                      label: Text('${record.recipientCount} recipients'),
                    ),
                  if (record.failedCount > 0)
                    Chip(
                      avatar: const Icon(Icons.error_outline, size: 18),
                      label: Text('${record.failedCount} failed'),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                record.messagePreview,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              if (record.scheduledAt != null)
                _DetailRow(
                  icon: Icons.schedule_outlined,
                  text: 'Scheduled ${_formatDateTime(record.scheduledAt!)}',
                ),
              if (record.publishedAt != null)
                _DetailRow(
                  icon: Icons.campaign_outlined,
                  text: 'Published ${_formatDateTime(record.publishedAt!)}',
                ),
              if (record.sentAt != null)
                _DetailRow(
                  icon: Icons.send_outlined,
                  text: 'Sent ${_formatDateTime(record.sentAt!)}',
                ),
              if (record.lastError != null)
                _DetailRow(
                  icon: Icons.error_outline,
                  text: 'Last error: ${record.lastError}',
                ),
              if (record.scheduledAt == null &&
                  record.publishedAt == null &&
                  record.sentAt == null)
                _DetailRow(
                  icon: Icons.edit_calendar_outlined,
                  text: 'Created ${_formatDateTime(record.createdAt)}',
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
      case 'sent':
        return scheme.primary;
      case 'queued':
      case 'scheduled':
        return scheme.tertiary;
      case 'failed':
        return scheme.error;
      default:
        return scheme.outline;
    }
  }
}

class _CommunicationComposerDialog extends StatefulWidget {
  const _CommunicationComposerDialog({
    required this.clubId,
    required this.templates,
    required this.emailAddonEnabled,
    this.existing,
  });

  final String clubId;
  final List<_CommunicationTemplate> templates;
  final bool emailAddonEnabled;
  final _CommunicationRecord? existing;

  @override
  State<_CommunicationComposerDialog> createState() =>
      _CommunicationComposerDialogState();
}

class _CommunicationComposerDialogState
    extends State<_CommunicationComposerDialog> {
  final _formKey = GlobalKey<FormState>();
  final _supabase = Supabase.instance.client;

  late final TextEditingController _subjectController;
  late final TextEditingController _messageController;
  late final TextEditingController _scheduledAtController;

  late String _recipientGroup;
  late String _channel;
  String? _templateId;
  bool _isSaving = false;
  String? _errorMessage;

  bool get _editingEmailCommunicationWithoutAddon {
    final existing = widget.existing;
    if (existing == null || widget.emailAddonEnabled) return false;
    return existing.usesEmail;
  }

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;

    _subjectController = TextEditingController(text: existing?.subject ?? '');
    _messageController = TextEditingController(text: existing?.message ?? '');
    _scheduledAtController = TextEditingController(
      text: existing?.scheduledAt == null
          ? ''
          : _dateTimeText(existing!.scheduledAt!),
    );

    _recipientGroup = existing?.recipientGroup ?? 'active_members';
    _channel = existing?.channel ?? 'in_app';
    if (!widget.emailAddonEnabled &&
        _channel != 'in_app' &&
        existing == null) {
      _channel = 'in_app';
    }
  }

  @override
  void dispose() {
    _subjectController.dispose();
    _messageController.dispose();
    _scheduledAtController.dispose();
    super.dispose();
  }

  void _applyTemplate(String? templateId) {
    setState(() => _templateId = templateId);
    if (templateId == null) return;

    final template = widget.templates
        .where((item) => item.id == templateId)
        .firstOrNull;

    if (template == null) return;

    _subjectController.text = template.subject;
    _messageController.text = template.message;
  }

  Future<void> _save({required bool publishNow}) async {
    if (_isSaving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final scheduledAt = _parseDateTime(_scheduledAtController.text);
    final usesEmail = _channel == 'email' || _channel == 'both';

    if (usesEmail && !widget.emailAddonEnabled) {
      setState(() {
        _errorMessage = _editingEmailCommunicationWithoutAddon
            ? 'This message used email delivery, but the Email Add-on is no longer enabled. Change the delivery method to In-app before saving.'
            : 'Email delivery requires the Email Add-on.';
      });
      return;
    }

    final nextStatus = publishNow
        ? usesEmail
            ? 'queued'
            : 'published'
        : scheduledAt != null
            ? 'scheduled'
            : 'draft';
    final emailStatus = usesEmail
        ? publishNow
            ? 'queued'
            : 'not_applicable'
        : 'not_applicable';

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final payload = <String, dynamic>{
      'club_id': widget.clubId,
      'subject': _subjectController.text.trim(),
      'message': _messageController.text.trim(),
      'recipient_group': _recipientGroup,
      'channel': _channel,
      'status': nextStatus,
      'email_status': emailStatus,
      'scheduled_at': scheduledAt?.toIso8601String(),
      'published_at': publishNow ? DateTime.now().toIso8601String() : null,
      'sent_at': null,
    };

    try {
      final existing = widget.existing;
      late final String communicationId;

      if (existing == null) {
        final inserted = await _supabase
            .from('club_communications')
            .insert(payload)
            .select('id')
            .single();

        communicationId = inserted['id'].toString();
      } else {
        await _supabase
            .from('club_communications')
            .update(payload)
            .eq('id', existing.id)
            .eq('club_id', widget.clubId);

        communicationId = existing.id;
      }

      if (publishNow && usesEmail) {
        final deliveryError = await _sendQueuedEmailNow(communicationId);

        if (!mounted) return;

        if (deliveryError != null) {
          await _showDeliveryError(deliveryError);

          if (!mounted) return;
          Navigator.of(context).pop(true);
          return;
        }
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _isSaving = false;
        _errorMessage = 'Unable to save communication: $error';
      });
    }
  }

  Future<String?> _sendQueuedEmailNow(String communicationId) async {
    try {
      final response = await _supabase.functions.invoke(
        'send-club-communications',
        body: {
          'communication_id': communicationId,
          'limit': 1,
        },
      );

      final data = response.data;
      if (data is Map) {
        final topLevelError = data['error']?.toString().trim();
        if (topLevelError != null && topLevelError.isNotEmpty) {
          return topLevelError;
        }

        final results = data['results'];
        if (results is List && results.isNotEmpty) {
          final first = results.first;
          if (first is Map) {
            final status = first['status']?.toString();
            final error = first['error']?.toString().trim();
            final failedCount = int.tryParse(
                  first['failed_count']?.toString() ?? '0',
                ) ??
                0;

            if (status == 'failed' || failedCount > 0) {
              if (error != null && error.isNotEmpty) return error;
              return 'Email delivery failed for $failedCount recipient(s).';
            }
          }
        }
      }

      return null;
    } catch (error) {
      return error.toString();
    }
  }

  Future<void> _showDeliveryError(String error) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Email Delivery Failed'),
        content: Text(error),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickScheduledDateTime() async {
    final initial = _parseDateTime(_scheduledAtController.text) ??
        DateTime.now().add(const Duration(hours: 1));

    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );

    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );

    if (time == null) return;

    final selected = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );

    _scheduledAtController.text = _dateTimeText(selected);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.existing == null ? 'New Communication' : 'Edit Communication',
      ),
      content: SizedBox(
        width: 760,
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
                if (_editingEmailCommunicationWithoutAddon) ...[
                  Material(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'This communication was created with email delivery, but the Email Add-on is no longer enabled. You can view it here, but you must change the delivery method to In-app before saving changes.',
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                DropdownButtonFormField<String>(
                  initialValue: _templateId,
                  decoration: const InputDecoration(
                    labelText: 'Use a template',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('Start from scratch'),
                    ),
                    for (final template
                        in widget.templates.where((item) => item.isActive))
                      DropdownMenuItem(
                        value: template.id,
                        child: Text(template.name),
                      ),
                  ],
                  onChanged: _isSaving ? null : _applyTemplate,
                ),
                const SizedBox(height: 14),
                _SectionTitle('Delivery Method'),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'in_app',
                      icon: Icon(Icons.campaign_outlined),
                      label: Text('In-app'),
                    ),
                    ButtonSegment(
                      value: 'email',
                      icon: Icon(Icons.email_outlined),
                      label: Text('Email'),
                    ),
                    ButtonSegment(
                      value: 'both',
                      icon: Icon(Icons.all_inbox_outlined),
                      label: Text('Both'),
                    ),
                  ],
                  selected: {_channel},
                  onSelectionChanged: _isSaving
                      ? null
                      : (values) {
                          final selected = values.first;
                          if (selected != 'in_app' &&
                              !widget.emailAddonEnabled) {
                            setState(() {
                              _errorMessage =
                                  'Email delivery requires the Email Add-on.';
                              _channel = 'in_app';
                            });
                            return;
                          }
                          setState(() {
                            _errorMessage = null;
                            _channel = selected;
                          });
                        },
                ),
                const SizedBox(height: 8),
                Text(
                  widget.emailAddonEnabled
                      ? 'Email selections will be queued and sent through the email delivery function.'
                      : 'In-app notices are included. Email delivery is available with the Email Add-on.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _recipientGroup,
                  decoration: const InputDecoration(
                    labelText: 'Recipient group',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'all_members',
                      child: Text('All Members'),
                    ),
                    DropdownMenuItem(
                      value: 'active_members',
                      child: Text('Active Members'),
                    ),
                    DropdownMenuItem(
                      value: 'expired_members',
                      child: Text('Expired Members'),
                    ),
                    DropdownMenuItem(
                      value: 'pending_applicants',
                      child: Text('Pending Applicants'),
                    ),
                    DropdownMenuItem(
                      value: 'unpaid_members',
                      child: Text('Members with Unpaid Dues'),
                    ),
                    DropdownMenuItem(
                      value: 'sanction_contacts',
                      child: Text('Sanction Request Contacts'),
                    ),
                    DropdownMenuItem(
                      value: 'staff',
                      child: Text('Club Staff'),
                    ),
                  ],
                  onChanged: _isSaving
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() => _recipientGroup = value);
                          }
                        },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _subjectController,
                  decoration: const InputDecoration(
                    labelText: 'Subject',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Subject is required.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _messageController,
                  minLines: 8,
                  maxLines: 16,
                  decoration: const InputDecoration(
                    labelText: 'Message',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Message is required.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _scheduledAtController,
                  readOnly: true,
                  decoration: InputDecoration(
                    labelText: 'Schedule for later',
                    hintText: 'Leave blank to save as a draft',
                    border: const OutlineInputBorder(),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_scheduledAtController.text.isNotEmpty)
                          IconButton(
                            tooltip: 'Clear schedule',
                            onPressed: _isSaving
                                ? null
                                : () {
                                    setState(_scheduledAtController.clear);
                                  },
                            icon: const Icon(Icons.clear),
                          ),
                        IconButton(
                          tooltip: 'Choose date and time',
                          onPressed:
                              _isSaving ? null : _pickScheduledDateTime,
                          icon: const Icon(Icons.schedule_outlined),
                        ),
                      ],
                    ),
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
        OutlinedButton.icon(
          onPressed: _isSaving ? null : () => _save(publishNow: false),
          icon: const Icon(Icons.save_outlined),
          label: Text(
            _scheduledAtController.text.isEmpty ? 'Save Draft' : 'Schedule',
          ),
        ),
        FilledButton.icon(
          onPressed: _isSaving ? null : () => _save(publishNow: true),
          icon: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  _channel == 'in_app'
                      ? Icons.campaign_outlined
                      : Icons.outbox_outlined,
                ),
          label: Text(
            _isSaving
                ? 'Saving...'
                : _channel == 'in_app'
                    ? 'Publish Notice'
                    : 'Queue Email',
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}

class _TemplateManagerDialog extends StatefulWidget {
  const _TemplateManagerDialog({
    required this.clubId,
    required this.templates,
  });

  final String clubId;
  final List<_CommunicationTemplate> templates;

  @override
  State<_TemplateManagerDialog> createState() =>
      _TemplateManagerDialogState();
}

class _TemplateManagerDialogState extends State<_TemplateManagerDialog> {
  final _supabase = Supabase.instance.client;
  bool _changed = false;

  Future<void> _editTemplate({_CommunicationTemplate? existing}) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _TemplateEditorDialog(
        clubId: widget.clubId,
        existing: existing,
      ),
    );

    if (result == true) {
      _changed = true;
      if (mounted) Navigator.of(context).pop(true);
    }
  }

  Future<void> _toggleTemplate(_CommunicationTemplate template) async {
    await _supabase
        .from('club_communication_templates')
        .update({'is_active': !template.isActive})
        .eq('id', template.id)
        .eq('club_id', widget.clubId);

    _changed = true;
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Communication Templates'),
      content: SizedBox(
        width: 680,
        child: widget.templates.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No templates have been created yet.',
                  textAlign: TextAlign.center,
                ),
              )
            : ListView.separated(
                shrinkWrap: true,
                itemCount: widget.templates.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final template = widget.templates[index];
                  return ListTile(
                    leading: Icon(
                      template.isActive
                          ? Icons.description_outlined
                          : Icons.block_outlined,
                    ),
                    title: Text(template.name),
                    subtitle: Text(template.subject),
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'edit') {
                          _editTemplate(existing: template);
                        } else if (value == 'toggle') {
                          _toggleTemplate(template);
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: Text('Edit'),
                        ),
                        PopupMenuItem(
                          value: 'toggle',
                          child: Text(
                            template.isActive ? 'Deactivate' : 'Activate',
                          ),
                        ),
                      ],
                    ),
                    onTap: () => _editTemplate(existing: template),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(_changed),
          child: const Text('Close'),
        ),
        FilledButton.icon(
          onPressed: () => _editTemplate(),
          icon: const Icon(Icons.add),
          label: const Text('New Template'),
        ),
      ],
    );
  }
}

class _TemplateEditorDialog extends StatefulWidget {
  const _TemplateEditorDialog({
    required this.clubId,
    this.existing,
  });

  final String clubId;
  final _CommunicationTemplate? existing;

  @override
  State<_TemplateEditorDialog> createState() =>
      _TemplateEditorDialogState();
}

class _TemplateEditorDialogState extends State<_TemplateEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  final _supabase = Supabase.instance.client;

  late final TextEditingController _nameController;
  late final TextEditingController _subjectController;
  late final TextEditingController _messageController;
  bool _isActive = true;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existing?.name ?? '');
    _subjectController =
        TextEditingController(text: widget.existing?.subject ?? '');
    _messageController =
        TextEditingController(text: widget.existing?.message ?? '');
    _isActive = widget.existing?.isActive ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _subjectController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSaving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final payload = <String, dynamic>{
      'club_id': widget.clubId,
      'name': _nameController.text.trim(),
      'subject': _subjectController.text.trim(),
      'message': _messageController.text.trim(),
      'is_active': _isActive,
    };

    try {
      final existing = widget.existing;

      if (existing == null) {
        await _supabase.from('club_communication_templates').insert(payload);
      } else {
        await _supabase
            .from('club_communication_templates')
            .update(payload)
            .eq('id', existing.id)
            .eq('club_id', widget.clubId);
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorMessage = 'Unable to save template: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'New Template' : 'Edit Template'),
      content: SizedBox(
        width: 640,
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
                    labelText: 'Template name',
                    border: OutlineInputBorder(),
                  ),
                  validator: _required,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _subjectController,
                  decoration: const InputDecoration(
                    labelText: 'Subject',
                    border: OutlineInputBorder(),
                  ),
                  validator: _required,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _messageController,
                  minLines: 8,
                  maxLines: 16,
                  decoration: const InputDecoration(
                    labelText: 'Message',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                  validator: _required,
                ),
                const SizedBox(height: 10),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active template'),
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
}

class _CommunicationRecord {
  const _CommunicationRecord({
    required this.id,
    required this.subject,
    required this.message,
    required this.recipientGroup,
    required this.channel,
    required this.status,
    required this.emailStatus,
    required this.createdAt,
    required this.failedCount,
    this.lastError,
    this.scheduledAt,
    this.publishedAt,
    this.sentAt,
    this.recipientCount,
  });

  final String id;
  final String subject;
  final String message;
  final String recipientGroup;
  final String channel;
  final String status;
  final String emailStatus;
  final DateTime? scheduledAt;
  final DateTime? publishedAt;
  final DateTime? sentAt;
  final int? recipientCount;
  final int failedCount;
  final String? lastError;
  final DateTime createdAt;

  String get messagePreview => message.replaceAll(RegExp(r'\s+'), ' ').trim();

  bool get usesEmail => channel == 'email' || channel == 'both';

  String get channelLabel {
    switch (channel) {
      case 'email':
        return 'Email';
      case 'both':
        return 'In-app + Email';
      case 'in_app':
      default:
        return 'In-app Notice';
    }
  }

  factory _CommunicationRecord.fromJson(Map<String, dynamic> json) {
    return _CommunicationRecord(
      id: json['id'].toString(),
      subject: _nullableString(json['subject']) ?? 'Untitled Message',
      message: _nullableString(json['message']) ?? '',
      recipientGroup:
          _nullableString(json['recipient_group']) ?? 'active_members',
      channel: _nullableString(json['channel']) ?? 'in_app',
      status: _nullableString(json['status']) ?? 'draft',
      emailStatus: _nullableString(json['email_status']) ?? 'not_applicable',
      scheduledAt: _nullableDate(json['scheduled_at']),
      publishedAt: _nullableDate(json['published_at']),
      sentAt: _nullableDate(json['sent_at']),
      recipientCount: _nullableInt(json['recipient_count']),
      failedCount: _nullableInt(json['failed_count']) ?? 0,
      lastError: _nullableString(json['last_error']),
      createdAt: _nullableDate(json['created_at']) ?? DateTime.now(),
    );
  }
}

class _CommunicationTemplate {
  const _CommunicationTemplate({
    required this.id,
    required this.name,
    required this.subject,
    required this.message,
    required this.isActive,
    this.templateKey,
  });

  final String id;
  final String name;
  final String? templateKey;
  final String subject;
  final String message;
  final bool isActive;

  factory _CommunicationTemplate.fromJson(Map<String, dynamic> json) {
    return _CommunicationTemplate(
      id: json['id'].toString(),
      name: _nullableString(json['name']) ?? 'Untitled Template',
      templateKey: _nullableString(json['template_key']),
      subject: _nullableString(json['subject']) ?? '',
      message: _nullableString(json['message']) ?? '',
      isActive: json['is_active'] == true,
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
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
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
            const Icon(Icons.campaign_outlined, size: 52),
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
                icon: const Icon(Icons.edit_outlined),
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

extension _FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class _EmailAddonNotice extends StatelessWidget {
  const _EmailAddonNotice({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: enabled
                  ? scheme.primaryContainer
                  : scheme.surfaceContainerHighest,
              foregroundColor: enabled
                  ? scheme.onPrimaryContainer
                  : scheme.onSurfaceVariant,
              child: Icon(enabled ? Icons.email_outlined : Icons.lock_outline),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                enabled
                    ? 'Email Add-on enabled. Email messages can be queued and sent through the delivery function.'
                    : 'Base communications create in-app notices and records. Email delivery is available as an add-on.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}