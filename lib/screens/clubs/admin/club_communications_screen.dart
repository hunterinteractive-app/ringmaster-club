// lib/screens/clubs/admin/club_communications_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/clubs/club_summary.dart';
import '../../../theme/app_theme.dart';

class ClubCommunicationsScreen extends StatefulWidget {
  const ClubCommunicationsScreen({super.key, required this.club});

  final ClubSummary club;

  @override
  State<ClubCommunicationsScreen> createState() =>
      _ClubCommunicationsScreenState();
}

class _ClubCommunicationsScreenState extends State<ClubCommunicationsScreen> {
  final _supabase = Supabase.instance.client;

  bool _isLoading = true;
  bool _emailAddonEnabled = false;
  String? _replyToEmail;
  String? _senderName;
  String? _errorMessage;

  List<_CommunicationTemplate> _templates = const [];
  List<_CommunicationBatch> _batches = const [];
  List<_CommunicationRecord> _communications = const [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final responses = await Future.wait([
        _supabase
            .from('clubs')
            .select(
              'email_addon_enabled,communication_reply_to_email,'
              'communication_sender_name',
            )
            .eq('id', widget.club.clubId)
            .single(),
        _supabase
            .from('club_communication_templates')
            .select(
              'id,club_id,template_key,name,description,subject,body,message,'
              'channel_default,is_system_default,is_enabled,updated_at',
            )
            .or('club_id.is.null,club_id.eq.${widget.club.clubId}')
            .order('is_system_default', ascending: false)
            .order('name', ascending: true),
        _supabase
            .from('club_communication_batches')
            .select(
              'id,club_id,message_kind,template_key,subject,body,audience_type,'
              'recipient_count,notification_count,email_count,status,created_by,'
              'sent_at,created_at,updated_at',
            )
            .eq('club_id', widget.club.clubId)
            .order('created_at', ascending: false),
        _supabase
            .from('club_communications')
            .select(
              'id,club_id,batch_id,template_key,message_kind,related_type,'
              'related_id,recipient_user_id,recipient_email,recipient_name,'
              'channel,subject,body,message,status,sent_at,read_at,failed_at,'
              'error_message,created_by,created_at,updated_at',
            )
            .eq('club_id', widget.club.clubId)
            .order('created_at', ascending: false),
      ]);

      final clubRow = Map<String, dynamic>.from(responses[0] as Map);
      final templateRows = responses[1] as List;
      final batchRows = responses[2] as List;
      final communicationRows = responses[3] as List;

      if (!mounted) return;
      setState(() {
        _emailAddonEnabled = clubRow['email_addon_enabled'] == true;
        _replyToEmail = _nullableString(
          clubRow['communication_reply_to_email'],
        );
        _senderName = _nullableString(clubRow['communication_sender_name']);
        _templates = _mergeTemplateDefaultsAndOverrides(templateRows);
        _batches = batchRows
            .whereType<Map>()
            .map(
              (row) =>
                  _CommunicationBatch.fromJson(Map<String, dynamic>.from(row)),
            )
            .toList();
        _communications = communicationRows
            .whereType<Map>()
            .map(
              (row) =>
                  _CommunicationRecord.fromJson(Map<String, dynamic>.from(row)),
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

  List<_CommunicationTemplate> _mergeTemplateDefaultsAndOverrides(List rows) {
    final byKey = <String, _CommunicationTemplate>{};
    final customTemplates = <_CommunicationTemplate>[];

    for (final row in rows.whereType<Map>()) {
      final template = _CommunicationTemplate.fromJson(
        Map<String, dynamic>.from(row),
      );
      final key = template.templateKey;

      if (key == null || key.isEmpty) {
        customTemplates.add(template);
        continue;
      }

      final existing = byKey[key];
      if (existing == null ||
          (existing.isSystemDefault && !template.isSystemDefault)) {
        byKey[key] = template;
      }
    }

    final templates = [...byKey.values, ...customTemplates]
      ..sort((a, b) => a.name.compareTo(b.name));
    return templates;
  }

  Future<void> _openTemplateEditor({_CommunicationTemplate? template}) async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _TemplateEditorDialog(clubId: widget.club.clubId, template: template),
    );

    if (changed == true) await _loadData();
  }

  Future<void> _openComposer({
    _CommunicationTemplate? template,
    String? messageKind,
  }) async {
    final composeTemplate = template?.canUseForManualCompose == true
        ? template
        : null;
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ComposerDialog(
        clubId: widget.club.clubId,
        clubName: widget.club.clubName,
        emailAddonEnabled: _emailAddonEnabled,
        templates: _templates,
        initialTemplate: composeTemplate,
        initialMessageKind: messageKind,
      ),
    );

    if (changed == true) await _loadData();
  }

  Future<void> _openSettings() async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CommunicationSettingsDialog(
        clubId: widget.club.clubId,
        emailAddonEnabled: _emailAddonEnabled,
        senderName: _senderName,
        replyToEmail: _replyToEmail,
      ),
    );

    if (changed == true) await _loadData();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Communications'),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: _isLoading ? null : _loadData,
              icon: const Icon(Icons.refresh),
            ),
          ],
          bottom: const TabBar(
            isScrollable: false,
            labelColor: AppColors.offWhite,
            unselectedLabelColor: AppColors.clubLightText,
            indicatorColor: AppColors.gold,
            indicatorWeight: 3,
            tabs: [
              Tab(icon: Icon(Icons.edit_outlined), text: 'Compose'),
              Tab(icon: Icon(Icons.description_outlined), text: 'Templates'),
              Tab(icon: Icon(Icons.history_outlined), text: 'History'),
              Tab(icon: Icon(Icons.settings_outlined), text: 'Settings'),
            ],
          ),
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return _MessageState(
        icon: Icons.error_outline,
        title: 'Unable to load communications',
        message: _errorMessage!,
        actionLabel: 'Try Again',
        onAction: _loadData,
      );
    }

    return TabBarView(
      children: [
        _ComposeTab(
          clubName: widget.club.clubName,
          emailAddonEnabled: _emailAddonEnabled,
          templates: _templates,
          onCompose: (template, messageKind) =>
              _openComposer(template: template, messageKind: messageKind),
        ),
        _TemplatesTab(
          clubName: widget.club.clubName,
          templates: _templates,
          onEdit: (template) => _openTemplateEditor(template: template),
          onCreate: () => _openTemplateEditor(),
          onUse: (template) => _openComposer(
            template: template,
            messageKind: template.templateKey == 'newsletter'
                ? 'newsletter'
                : 'custom_audience',
          ),
        ),
        _HistoryTab(batches: _batches, communications: _communications),
        _SettingsTab(
          emailAddonEnabled: _emailAddonEnabled,
          senderName: _senderName,
          replyToEmail: _replyToEmail,
          onEdit: _openSettings,
        ),
      ],
    );
  }
}

class _ComposeTab extends StatelessWidget {
  const _ComposeTab({
    required this.clubName,
    required this.emailAddonEnabled,
    required this.templates,
    required this.onCompose,
  });

  final String clubName;
  final bool emailAddonEnabled;
  final List<_CommunicationTemplate> templates;
  final Future<void> Function(
    _CommunicationTemplate? template,
    String? messageKind,
  )
  onCompose;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
      children: [
        Text(
          'Compose',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          'Send an individual message, club announcement, newsletter, or save a communication record for $clubName.',
        ),
        const SizedBox(height: 16),
        _EmailAddonNotice(enabled: emailAddonEnabled),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _ComposeActionCard(
              icon: Icons.person_outline,
              title: 'Individual Message',
              description:
                  'Message one member, applicant, sanction contact, officer, or custom address.',
              onTap: () => onCompose(null, 'custom_individual'),
            ),
            _ComposeActionCard(
              icon: Icons.groups_outlined,
              title: 'Group Message',
              description:
                  'Send a notice to active members, pending applicants, staff, or another saved audience.',
              onTap: () => onCompose(null, 'custom_audience'),
            ),
            _ComposeActionCard(
              icon: Icons.newspaper_outlined,
              title: 'Newsletter',
              description:
                  'Start from the newsletter template and send a longer club update.',
              onTap: () => onCompose(
                templates
                    .where(
                      (item) =>
                          item.templateKey == 'newsletter' &&
                          item.canUseForManualCompose,
                    )
                    .firstOrNull,
                'newsletter',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ComposeActionCard extends StatelessWidget {
  const _ComposeActionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 840;
    return SizedBox(
      width: wide ? 260 : double.infinity,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(child: Icon(icon)),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(description),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TemplatesTab extends StatelessWidget {
  const _TemplatesTab({
    required this.clubName,
    required this.templates,
    required this.onEdit,
    required this.onCreate,
    required this.onUse,
  });

  final String clubName;
  final List<_CommunicationTemplate> templates;
  final ValueChanged<_CommunicationTemplate> onEdit;
  final VoidCallback onCreate;
  final ValueChanged<_CommunicationTemplate> onUse;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Templates',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Edit club-specific message templates. System defaults stay available and can be customized per club.',
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: const Text('New'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (templates.isEmpty)
          _InlineEmptyState(
            title: 'No templates',
            message:
                'Run the communication template seed to load the default system templates.',
            actionLabel: 'Create Template',
            onAction: onCreate,
          )
        else ...[
          _TemplateSection(
            clubName: clubName,
            title: 'Membership',
            templates: templates
                .where(
                  (template) =>
                      template.templateKey?.startsWith('membership_') == true,
                )
                .toList(),
            onEdit: onEdit,
            onUse: onUse,
          ),
          _TemplateSection(
            clubName: clubName,
            title: 'Sanction Requests',
            templates: templates
                .where(
                  (template) =>
                      template.templateKey?.startsWith('sanction_') == true,
                )
                .toList(),
            onEdit: onEdit,
            onUse: onUse,
          ),
          _TemplateSection(
            clubName: clubName,
            title: 'Payments & Reminders',
            templates: templates
                .where(
                  (template) =>
                      template.templateKey == 'payment_received' ||
                      template.templateKey == 'pending_check_reminder',
                )
                .toList(),
            onEdit: onEdit,
            onUse: onUse,
          ),
          _TemplateSection(
            clubName: clubName,
            title: 'General Club Communications',
            templates: templates
                .where(
                  (template) =>
                      template.templateKey == 'club_announcement' ||
                      template.templateKey == 'newsletter' ||
                      template.templateKey == null ||
                      template.templateKey!.isEmpty,
                )
                .toList(),
            onEdit: onEdit,
            onUse: onUse,
          ),
        ],
      ],
    );
  }
}

class _TemplateSection extends StatelessWidget {
  const _TemplateSection({
    required this.clubName,
    required this.title,
    required this.templates,
    required this.onEdit,
    required this.onUse,
  });

  final String clubName;
  final String title;
  final List<_CommunicationTemplate> templates;
  final ValueChanged<_CommunicationTemplate> onEdit;
  final ValueChanged<_CommunicationTemplate> onUse;

  @override
  Widget build(BuildContext context) {
    if (templates.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          for (final template in templates)
            _TemplateCard(
              clubName: clubName,
              template: template,
              onEdit: () => onEdit(template),
              onUse: () => onUse(template),
            ),
        ],
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.clubName,
    required this.template,
    required this.onEdit,
    required this.onUse,
  });

  final String clubName;
  final _CommunicationTemplate template;
  final VoidCallback onEdit;
  final VoidCallback onUse;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  child: Icon(
                    template.channelDefault == 'email'
                        ? Icons.email_outlined
                        : Icons.campaign_outlined,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        template.name,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      Text(_renderPreviewText(template.subject, clubName)),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'edit') onEdit();
                    if (value == 'use') onUse();
                  },
                  itemBuilder: (_) => [
                    if (template.canUseForManualCompose)
                      const PopupMenuItem(
                        value: 'use',
                        child: Text('Use Template'),
                      ),
                    const PopupMenuItem(
                      value: 'edit',
                      child: Text('Customize'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  avatar: Icon(
                    template.isSystemDefault
                        ? Icons.public_outlined
                        : Icons.edit_outlined,
                    size: 18,
                  ),
                  label: Text(
                    template.isSystemDefault
                        ? 'RingMaster Default'
                        : 'Club Custom',
                  ),
                ),
                Chip(label: Text(_titleCase(template.channelDefault))),
                if (!template.isEnabled)
                  const Chip(
                    avatar: Icon(Icons.block_outlined, size: 18),
                    label: Text('Disabled'),
                  ),
              ],
            ),
            if (template.description != null) ...[
              const SizedBox(height: 10),
              Text(template.description!),
            ],
            const SizedBox(height: 10),
            Text(
              _renderPreviewText(template.bodyPreview, clubName),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryTab extends StatefulWidget {
  const _HistoryTab({required this.batches, required this.communications});

  final List<_CommunicationBatch> batches;
  final List<_CommunicationRecord> communications;

  @override
  State<_HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<_HistoryTab> {
  final _searchController = TextEditingController();
  String _statusFilter = 'all';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  List<_CommunicationBatch> get _filteredBatches {
    final query = _searchController.text.trim().toLowerCase();

    return widget.batches.where((batch) {
      final matchesStatus =
          _statusFilter == 'all' || batch.status == _statusFilter;
      if (!matchesStatus) return false;
      if (query.isEmpty) return true;

      return [
        batch.subject,
        batch.body,
        batch.messageKind,
        batch.audienceType,
      ].join(' ').toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredBatches;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
      children: [
        Text(
          'History',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        const Text(
          'Review communication batches and individual delivery records.',
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            labelText: 'Search history',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _searchController.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear',
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
            selected: {_statusFilter},
            segments: const [
              ButtonSegment(value: 'all', label: Text('All')),
              ButtonSegment(value: 'draft', label: Text('Draft')),
              ButtonSegment(value: 'queued', label: Text('Queued')),
              ButtonSegment(value: 'sent', label: Text('Sent')),
              ButtonSegment(value: 'partial', label: Text('Partial')),
              ButtonSegment(value: 'failed', label: Text('Failed')),
            ],
            onSelectionChanged: (values) {
              setState(() => _statusFilter = values.first);
            },
          ),
        ),
        const SizedBox(height: 16),
        Text(
          '${filtered.length} ${filtered.length == 1 ? 'batch' : 'batches'}',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        if (widget.batches.isEmpty && widget.communications.isEmpty)
          const _InlineEmptyState(
            title: 'No communication history yet',
            message:
                'Messages, notifications, email attempts, and system notices will appear here.',
          )
        else if (filtered.isEmpty)
          const _InlineEmptyState(
            title: 'No matching history',
            message: 'Try another search or status filter.',
          )
        else
          for (final batch in filtered) _HistoryBatchCard(batch: batch),
        if (widget.communications.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            'Individual Records',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          for (final record in widget.communications.take(25))
            _CommunicationRecordTile(record: record),
        ],
      ],
    );
  }
}

class _HistoryBatchCard extends StatelessWidget {
  const _HistoryBatchCard({required this.batch});

  final _CommunicationBatch batch;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(child: Icon(_kindIcon(batch.messageKind))),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        batch.subject,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_titleCase(batch.messageKind)} • ${_titleCase(batch.audienceType ?? 'audience')}',
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text(_titleCase(batch.status))),
                Chip(label: Text('${batch.recipientCount} recipients')),
                Chip(label: Text('${batch.notificationCount} notifications')),
                Chip(label: Text('${batch.emailCount} emails')),
              ],
            ),
            const SizedBox(height: 10),
            Text(batch.preview, maxLines: 3, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 10),
            _DetailRow(
              icon: Icons.schedule_outlined,
              text: batch.sentAt == null
                  ? 'Created ${_formatDateTime(batch.createdAt)}'
                  : 'Sent ${_formatDateTime(batch.sentAt!)}',
            ),
          ],
        ),
      ),
    );
  }

  IconData _kindIcon(String kind) {
    switch (kind) {
      case 'newsletter':
        return Icons.newspaper_outlined;
      case 'custom_individual':
        return Icons.person_outline;
      case 'custom_audience':
        return Icons.groups_outlined;
      default:
        return Icons.campaign_outlined;
    }
  }
}

class _CommunicationRecordTile extends StatelessWidget {
  const _CommunicationRecordTile({required this.record});

  final _CommunicationRecord record;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(
          record.channel == 'email'
              ? Icons.email_outlined
              : Icons.notifications_outlined,
        ),
        title: Text(record.subject),
        subtitle: Text(
          [
            record.recipientName,
            record.recipientEmail,
            _titleCase(record.status),
          ].whereType<String>().join(' • '),
        ),
        trailing: record.sentAt == null
            ? null
            : Text(_formatDateTime(record.sentAt!)),
      ),
    );
  }
}

class _SettingsTab extends StatelessWidget {
  const _SettingsTab({
    required this.emailAddonEnabled,
    required this.senderName,
    required this.replyToEmail,
    required this.onEdit,
  });

  final bool emailAddonEnabled;
  final String? senderName;
  final String? replyToEmail;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Settings',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Configure sender details and review email add-on availability.',
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _EmailAddonNotice(enabled: emailAddonEnabled),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DetailRow(
                  icon: Icons.badge_outlined,
                  text: 'Sender name: ${senderName ?? 'Club default'}',
                ),
                _DetailRow(
                  icon: Icons.reply_outlined,
                  text: 'Reply-to email: ${replyToEmail ?? 'Not set'}',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ComposerDialog extends StatefulWidget {
  const _ComposerDialog({
    required this.clubId,
    required this.clubName,
    required this.emailAddonEnabled,
    required this.templates,
    this.initialTemplate,
    this.initialMessageKind,
  });

  final String clubId;
  final String clubName;
  final bool emailAddonEnabled;
  final List<_CommunicationTemplate> templates;
  final _CommunicationTemplate? initialTemplate;
  final String? initialMessageKind;

  @override
  State<_ComposerDialog> createState() => _ComposerDialogState();
}

class _ComposerDialogState extends State<_ComposerDialog> {
  final _formKey = GlobalKey<FormState>();
  final _supabase = Supabase.instance.client;
  final _subjectController = TextEditingController();
  final _bodyController = TextEditingController();
  final _recipientNameController = TextEditingController();
  final _recipientEmailController = TextEditingController();
  final _recipientSearchController = TextEditingController();

  List<_MemberRecipientOption> _recipientOptions = const [];
  bool _isLoadingRecipients = false;
  String? _recipientLoadError;
  String? _selectedRecipientMembershipId;
  String? _selectedRecipientUserId;

  String _messageKind = 'custom_audience';
  String _audienceType = 'active_members';
  String _channel = 'notification';
  String? _templateKey;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _messageKind = widget.initialMessageKind ?? _messageKind;
    _applyTemplate(widget.initialTemplate);
    _loadActiveMemberRecipients();
  }

  @override
  void dispose() {
    _subjectController.dispose();
    _bodyController.dispose();
    _recipientNameController.dispose();
    _recipientEmailController.dispose();
    _recipientSearchController.dispose();
    super.dispose();
  }

  void _applyTemplate(_CommunicationTemplate? template) {
    if (template == null) return;
    _templateKey = template.templateKey;
    _subjectController.text = _renderComposerTemplate(template.subject);
    _bodyController.text = _renderComposerTemplate(template.body);
    _channel = template.channelDefault;
    if (_channel != 'notification' && !widget.emailAddonEnabled) {
      _channel = 'notification';
    }
    if (template.templateKey == 'newsletter') {
      _messageKind = 'newsletter';
      _audienceType = 'active_members';
    }
  }

  String _renderComposerTemplate(String value) {
    final recipientLabel = _messageKind == 'custom_individual'
        ? _nullIfBlank(_recipientNameController.text) ?? 'Recipient Name'
        : '{{recipient_name}}';

    return value
        .replaceAll('{{club_name}}', widget.clubName)
        .replaceAll('{{recipient_name}}', recipientLabel)
        .replaceAll('{{membership_type}}', 'Membership Type')
        .replaceAll('{{amount_due}}', 'Amount Due')
        .replaceAll('{{amount_paid}}', 'Amount Paid')
        .replaceAll('{{payment_method}}', 'Payment Method')
        .replaceAll('{{staff_message}}', 'Write the staff message here.')
        .replaceAll('{{requesting_club_name}}', 'Requesting Club')
        .replaceAll('{{show_date}}', 'Show Date')
        .replaceAll('{{contact_name}}', 'Contact Name')
        .replaceAll('{{request_scope}}', 'Request Scope')
        .replaceAll(
          '{{treasurer_mailing_address}}',
          'Treasurer Mailing Address',
        )
        .replaceAll('{{message_body}}', 'Write your message here.');
  }

  String _audienceLabel(String value) {
    switch (value) {
      case 'expired_members':
        return 'Expired Membership';
      case 'pending_applicants':
        return 'Pending Applicants';
      case 'unpaid_members':
        return 'Members With Unpaid Dues';
      case 'staff':
        return 'Club Board';
      case 'active_members':
      default:
        return 'Active Members';
    }
  }

  Future<void> _loadActiveMemberRecipients() async {
    setState(() {
      _isLoadingRecipients = true;
      _recipientLoadError = null;
    });

    try {
      final rows = await _supabase
          .from('club_memberships')
          .select('id,user_id,first_name,last_name,email,status')
          .eq('club_id', widget.clubId)
          .order('last_name', ascending: true)
          .order('first_name', ascending: true);

      final recipients = rows
          .whereType<Map>()
          .map(
            (row) =>
                _MemberRecipientOption.fromJson(Map<String, dynamic>.from(row)),
          )
          .where((member) => member.isActive)
          .toList();

      if (!mounted) return;
      setState(() {
        _recipientOptions = recipients;
        _isLoadingRecipients = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoadingRecipients = false;
        _recipientLoadError = 'Unable to load active members: $error';
      });
    }
  }

  void _selectRecipient(_MemberRecipientOption option) {
    setState(() {
      _selectedRecipientMembershipId = option.id;
      _selectedRecipientUserId = option.userId;
    });
    _recipientSearchController.text = option.displayLabel;
    _recipientNameController.text = option.fullName;
    _recipientEmailController.text = option.email ?? '';
  }

  Future<List<_MemberRecipientOption>> _loadRecipientsForAudience(
    String audienceType,
  ) async {
    if (audienceType == 'pending_applicants') {
      return _loadPendingApplicantRecipients();
    }
    if (audienceType == 'staff') {
      return _loadStaffRecipients();
    }
    if (audienceType == 'unpaid_members') {
      return _loadUnpaidRecipients();
    }

    final rows = await _supabase
        .from('club_memberships')
        .select('id,user_id,first_name,last_name,email,status')
        .eq('club_id', widget.clubId)
        .order('last_name', ascending: true)
        .order('first_name', ascending: true);

    final members = rows
        .whereType<Map>()
        .map(
          (row) =>
              _MemberRecipientOption.fromJson(Map<String, dynamic>.from(row)),
        )
        .toList();

    switch (audienceType) {
      case 'expired_members':
        return members.where((member) => member.isExpired).toList();
      case 'active_members':
      default:
        return members.where((member) => member.isActive).toList();
    }
  }

  Future<List<_MemberRecipientOption>> _loadPendingApplicantRecipients() async {
    final rows = await _supabase
        .from('club_membership_applications')
        .select('id,user_id,first_name,last_name,email,status')
        .eq('club_id', widget.clubId)
        .inFilter('status', ['pending', 'needs_information'])
        .order('created_at', ascending: false);

    return rows
        .whereType<Map>()
        .map(
          (row) => _MemberRecipientOption.fromJson(
            Map<String, dynamic>.from(row),
            relatedType: 'membership_application',
          ),
        )
        .toList();
  }

  Future<List<_MemberRecipientOption>> _loadUnpaidRecipients() async {
    final responses = await Future.wait([
      _supabase
          .from('club_memberships')
          .select('id,user_id,first_name,last_name,email,status')
          .eq('club_id', widget.clubId)
          .order('last_name', ascending: true)
          .order('first_name', ascending: true),
      _supabase
          .from('club_membership_applications')
          .select('id,user_id,first_name,last_name,email,status,payment_status')
          .eq('club_id', widget.clubId)
          .inFilter('payment_status', ['unpaid', 'pending', 'pending_check'])
          .order('created_at', ascending: false),
    ]);

    final members = (responses[0] as List)
        .whereType<Map>()
        .map(
          (row) =>
              _MemberRecipientOption.fromJson(Map<String, dynamic>.from(row)),
        )
        .where((member) => member.isUnpaid)
        .toList();

    final applications = (responses[1] as List)
        .whereType<Map>()
        .map(
          (row) => _MemberRecipientOption.fromJson(
            Map<String, dynamic>.from(row),
            relatedType: 'membership_application',
          ),
        )
        .toList();

    return [...members, ...applications];
  }

  Future<List<_MemberRecipientOption>> _loadStaffRecipients() async {
    final response = await _supabase.rpc(
      'get_club_staff_permissions_dashboard',
      params: {'p_club_id': widget.clubId},
    );
    if (response is! Map) return const [];
    final staffRows = response['staff'];
    if (staffRows is! List) return const [];

    return staffRows
        .whereType<Map>()
        .map(
          (row) => _MemberRecipientOption.fromStaffJson(
            Map<String, dynamic>.from(row),
          ),
        )
        .where((recipient) => recipient.isStaffActive)
        .toList();
  }

  String _renderForRecipient(String value, String recipientName) {
    return value
        .replaceAll('{{club_name}}', widget.clubName)
        .replaceAll('{{recipient_name}}', recipientName)
        .replaceAll('[Recipient Name]', recipientName)
        .replaceAll('(Name)', recipientName);
  }

  Future<void> _save({required bool sendNow}) async {
    if (_isSaving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final usesEmail = _channel == 'email' || _channel == 'both';
    if (usesEmail && !widget.emailAddonEnabled) {
      setState(() {
        _errorMessage = 'Email delivery requires the Email Add-on.';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final now = DateTime.now();
    final subjectTemplate = _subjectController.text.trim();
    final bodyTemplate = _bodyController.text.trim();
    final status = sendNow
        ? usesEmail
              ? 'queued'
              : 'sent'
        : 'draft';

    try {
      final recipients = _messageKind == 'custom_individual'
          ? [
              _MemberRecipientOption(
                id: _selectedRecipientMembershipId ?? 'custom',
                userId: _selectedRecipientUserId,
                fullName:
                    _nullIfBlank(_recipientNameController.text) ?? 'Recipient',
                email: _nullIfBlank(_recipientEmailController.text),
                status: 'active',
              ),
            ]
          : await _loadRecipientsForAudience(_audienceType);

      if (recipients.isEmpty) {
        if (!mounted) return;
        setState(() {
          _isSaving = false;
          _errorMessage =
              'No recipients were found for ${_audienceLabel(_audienceType)}.';
        });
        return;
      }

      final batch = await _supabase
          .from('club_communication_batches')
          .insert({
            'club_id': widget.clubId,
            'message_kind': _messageKind,
            'template_key': _templateKey,
            'subject': subjectTemplate,
            'body': bodyTemplate,
            'audience_type': _messageKind == 'custom_individual'
                ? 'individual'
                : _audienceType,
            'recipient_count': recipients.length,
            'notification_count':
                sendNow && (_channel == 'notification' || _channel == 'both')
                ? recipients.length
                : 0,
            'email_count':
                sendNow && (_channel == 'email' || _channel == 'both')
                ? recipients
                      .where((recipient) => recipient.email != null)
                      .length
                : 0,
            'status': status,
            'sent_at': sendNow ? now.toIso8601String() : null,
          })
          .select('id')
          .single();

      final communicationRows = recipients.map((recipient) {
        final personalizedSubject = _renderForRecipient(
          subjectTemplate,
          recipient.fullName,
        );
        final personalizedBody = _renderForRecipient(
          bodyTemplate,
          recipient.fullName,
        );
        final isCustomRecipient = recipient.id == 'custom';

        return {
          'club_id': widget.clubId,
          'batch_id': batch['id'],
          'template_key': _templateKey,
          'message_kind': _messageKind,
          'related_type': isCustomRecipient ? null : recipient.relatedType,
          'related_id': isCustomRecipient ? null : recipient.id,
          'recipient_user_id': recipient.userId,
          'recipient_name': recipient.fullName,
          'recipient_email': recipient.email,
          'channel': _channel,
          'subject': personalizedSubject,
          'body': personalizedBody,
          'message': personalizedBody,
          'status': sendNow
              ? usesEmail
                    ? 'queued'
                    : 'notification_created'
              : 'draft',
          'sent_at': sendNow && !usesEmail ? now.toIso8601String() : null,
        };
      }).toList();

      await _supabase.from('club_communications').insert(communicationRows);

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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Compose Communication'),
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
                  _InlineError(message: _errorMessage!),
                  const SizedBox(height: 14),
                ],
                DropdownButtonFormField<String>(
                  initialValue: _messageKind,
                  decoration: const InputDecoration(
                    labelText: 'Message type',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'custom_individual',
                      child: Text('Individual Message'),
                    ),
                    DropdownMenuItem(
                      value: 'custom_audience',
                      child: Text('Group Message'),
                    ),
                    DropdownMenuItem(
                      value: 'newsletter',
                      child: Text('Newsletter'),
                    ),
                  ],
                  onChanged: _isSaving
                      ? null
                      : (value) {
                          if (value == null) return;
                          setState(() => _messageKind = value);
                          final template = widget.templates
                              .where((item) => item.templateKey == _templateKey)
                              .firstOrNull;
                          if (template != null) {
                            _subjectController.text = _renderComposerTemplate(
                              template.subject,
                            );
                            _bodyController.text = _renderComposerTemplate(
                              template.body,
                            );
                          }
                        },
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _templateKey,
                  decoration: const InputDecoration(
                    labelText: 'Template',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('No template'),
                    ),
                    for (final template in widget.templates.where(
                      (item) => item.isEnabled && item.isManualComposeTemplate,
                    ))
                      DropdownMenuItem(
                        value: template.templateKey,
                        child: Text(template.name),
                      ),
                  ],
                  onChanged: _isSaving
                      ? null
                      : (value) {
                          final template = widget.templates
                              .where((item) => item.templateKey == value)
                              .firstOrNull;
                          setState(() => _templateKey = value);
                          _applyTemplate(template);
                        },
                ),
                const SizedBox(height: 14),
                SegmentedButton<String>(
                  selected: {_channel},
                  segments: const [
                    ButtonSegment(
                      value: 'notification',
                      icon: Icon(Icons.notifications_outlined),
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
                  onSelectionChanged: _isSaving
                      ? null
                      : (values) {
                          final selected = values.first;
                          if (selected != 'notification' &&
                              !widget.emailAddonEnabled) {
                            setState(() {
                              _channel = 'notification';
                              _errorMessage =
                                  'Email delivery requires the Email Add-on.';
                            });
                            return;
                          }
                          setState(() {
                            _channel = selected;
                            _errorMessage = null;
                          });
                        },
                ),
                const SizedBox(height: 14),
                if (_messageKind == 'custom_individual') ...[
                  if (_isLoadingRecipients) ...[
                    const LinearProgressIndicator(),
                    const SizedBox(height: 10),
                  ] else if (_recipientLoadError != null) ...[
                    _InlineError(message: _recipientLoadError!),
                    const SizedBox(height: 10),
                  ],
                  Autocomplete<_MemberRecipientOption>(
                    displayStringForOption: (option) => option.displayLabel,
                    optionsBuilder: (textEditingValue) {
                      final query = textEditingValue.text.trim().toLowerCase();
                      if (query.isEmpty) {
                        return _recipientOptions.take(25);
                      }

                      return _recipientOptions
                          .where((option) {
                            return option.searchText.contains(query);
                          })
                          .take(25);
                    },
                    onSelected: _selectRecipient,
                    fieldViewBuilder:
                        (
                          context,
                          textEditingController,
                          focusNode,
                          onFieldSubmitted,
                        ) {
                          if (_recipientSearchController.text.isNotEmpty &&
                              textEditingController.text.isEmpty) {
                            textEditingController.text =
                                _recipientSearchController.text;
                          }

                          return TextFormField(
                            controller: textEditingController,
                            focusNode: focusNode,
                            decoration: InputDecoration(
                              labelText: 'Search active members',
                              hintText: 'Start typing a member name or email',
                              border: const OutlineInputBorder(),
                              suffixIcon: textEditingController.text.isEmpty
                                  ? const Icon(Icons.search)
                                  : IconButton(
                                      tooltip: 'Clear selected member',
                                      onPressed: () {
                                        textEditingController.clear();
                                        _recipientSearchController.clear();
                                        setState(() {
                                          _selectedRecipientMembershipId = null;
                                          _selectedRecipientUserId = null;
                                        });
                                      },
                                      icon: const Icon(Icons.clear),
                                    ),
                            ),
                            onChanged: (value) {
                              _recipientSearchController.text = value;
                              if (_selectedRecipientMembershipId != null) {
                                setState(() {
                                  _selectedRecipientMembershipId = null;
                                  _selectedRecipientUserId = null;
                                });
                              }
                            },
                          );
                        },
                    optionsViewBuilder: (context, onSelected, options) {
                      return Align(
                        alignment: Alignment.topLeft,
                        child: Material(
                          elevation: 4,
                          borderRadius: BorderRadius.circular(12),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxWidth: 560,
                              maxHeight: 280,
                            ),
                            child: ListView.builder(
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              itemCount: options.length,
                              itemBuilder: (context, index) {
                                final option = options.elementAt(index);
                                return ListTile(
                                  leading: const Icon(Icons.person_outline),
                                  title: Text(option.fullName),
                                  subtitle: Text(
                                    option.email ?? 'No email on file',
                                  ),
                                  onTap: () => onSelected(option),
                                );
                              },
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _recipientNameController,
                    decoration: const InputDecoration(
                      labelText: 'Recipient name',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      final text = value?.trim() ?? '';
                      if (text.isEmpty) return 'Recipient name is required.';
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _recipientEmailController,
                    decoration: const InputDecoration(
                      labelText: 'Recipient email',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (_channel == 'notification') return null;
                      final text = value?.trim() ?? '';
                      if (text.isEmpty) return 'Email is required.';
                      if (!text.contains('@')) return 'Enter a valid email.';
                      return null;
                    },
                  ),
                ] else
                  DropdownButtonFormField<String>(
                    initialValue: _audienceType,
                    decoration: const InputDecoration(
                      labelText: 'Audience',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'active_members',
                        child: Text('Active Members'),
                      ),
                      DropdownMenuItem(
                        value: 'expired_members',
                        child: Text('Expired Membership'),
                      ),
                      DropdownMenuItem(
                        value: 'pending_applicants',
                        child: Text('Pending Applicants'),
                      ),
                      DropdownMenuItem(
                        value: 'unpaid_members',
                        child: Text('Members With Unpaid Dues'),
                      ),
                      DropdownMenuItem(
                        value: 'staff',
                        child: Text('Club Board'),
                      ),
                    ],
                    onChanged: _isSaving
                        ? null
                        : (value) {
                            if (value != null) {
                              setState(() => _audienceType = value);
                              final template = widget.templates
                                  .where(
                                    (item) => item.templateKey == _templateKey,
                                  )
                                  .firstOrNull;
                              if (template != null) {
                                _subjectController.text =
                                    _renderComposerTemplate(template.subject);
                                _bodyController.text = _renderComposerTemplate(
                                  template.body,
                                );
                              }
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
                  validator: _required,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _bodyController,
                  minLines: 10,
                  maxLines: 18,
                  decoration: const InputDecoration(
                    labelText: 'Message',
                    hintText:
                        'Write the message exactly how you want it to appear.',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                  validator: _required,
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
          onPressed: _isSaving ? null : () => _save(sendNow: false),
          icon: const Icon(Icons.save_outlined),
          label: const Text('Save Draft'),
        ),
        FilledButton.icon(
          onPressed: _isSaving ? null : () => _save(sendNow: true),
          icon: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.send_outlined),
          label: Text(_isSaving ? 'Saving...' : 'Send / Queue'),
        ),
      ],
    );
  }
}

class _TemplateEditorDialog extends StatefulWidget {
  const _TemplateEditorDialog({required this.clubId, this.template});

  final String clubId;
  final _CommunicationTemplate? template;

  @override
  State<_TemplateEditorDialog> createState() => _TemplateEditorDialogState();
}

class _TemplateEditorDialogState extends State<_TemplateEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  final _supabase = Supabase.instance.client;

  late final TextEditingController _nameController;
  late final TextEditingController _subjectController;
  late final TextEditingController _bodyController;
  late String _channelDefault;
  late bool _isEnabled;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final template = widget.template;
    _nameController = TextEditingController(text: template?.name ?? '');
    _subjectController = TextEditingController(text: template?.subject ?? '');
    _bodyController = TextEditingController(text: template?.body ?? '');
    _channelDefault = template?.channelDefault ?? 'notification';
    _isEnabled = template?.isEnabled ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _subjectController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSaving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final body = _bodyController.text.trim();
    final template = widget.template;
    final templateKey =
        template?.templateKey ?? _slugFromName(_nameController.text.trim());
    final payload = {
      'club_id': widget.clubId,
      'template_key': templateKey,
      'name': _nameController.text.trim(),
      'subject': _subjectController.text.trim(),
      'body': body,
      'message': body,
      'channel_default': _channelDefault,
      'is_system_default': false,
      'is_enabled': _isEnabled,
    };

    try {
      if (template == null || template.isSystemDefault) {
        await _supabase
            .from('club_communication_templates')
            .upsert(payload, onConflict: 'club_id,template_key');
      } else {
        await _supabase
            .from('club_communication_templates')
            .update(payload)
            .eq('id', template.id)
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
    final template = widget.template;

    return AlertDialog(
      title: Text(
        template == null
            ? 'New Template'
            : template.isSystemDefault
            ? 'Customize Template'
            : 'Edit Template',
      ),
      content: SizedBox(
        width: 700,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_errorMessage != null) ...[
                  _InlineError(message: _errorMessage!),
                  const SizedBox(height: 14),
                ],
                if (template?.isSystemDefault == true) ...[
                  Material(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'You are editing a RingMaster default. Saving creates a club-specific override and leaves the default intact.',
                      ),
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
                SegmentedButton<String>(
                  selected: {_channelDefault},
                  segments: const [
                    ButtonSegment(
                      value: 'notification',
                      label: Text('In-app'),
                      icon: Icon(Icons.notifications_outlined),
                    ),
                    ButtonSegment(
                      value: 'email',
                      label: Text('Email'),
                      icon: Icon(Icons.email_outlined),
                    ),
                    ButtonSegment(
                      value: 'both',
                      label: Text('Both'),
                      icon: Icon(Icons.all_inbox_outlined),
                    ),
                  ],
                  onSelectionChanged: _isSaving
                      ? null
                      : (values) {
                          setState(() => _channelDefault = values.first);
                        },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _bodyController,
                  minLines: 10,
                  maxLines: 18,
                  decoration: const InputDecoration(
                    labelText: 'Message body',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                  validator: _required,
                ),
                const SizedBox(height: 10),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Enabled'),
                  value: _isEnabled,
                  onChanged: _isSaving
                      ? null
                      : (value) => setState(() => _isEnabled = value),
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
}

class _CommunicationSettingsDialog extends StatefulWidget {
  const _CommunicationSettingsDialog({
    required this.clubId,
    required this.emailAddonEnabled,
    required this.senderName,
    required this.replyToEmail,
  });

  final String clubId;
  final bool emailAddonEnabled;
  final String? senderName;
  final String? replyToEmail;

  @override
  State<_CommunicationSettingsDialog> createState() =>
      _CommunicationSettingsDialogState();
}

class _CommunicationSettingsDialogState
    extends State<_CommunicationSettingsDialog> {
  final _supabase = Supabase.instance.client;
  late final TextEditingController _senderNameController;
  late final TextEditingController _replyToEmailController;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _senderNameController = TextEditingController(
      text: widget.senderName ?? '',
    );
    _replyToEmailController = TextEditingController(
      text: widget.replyToEmail ?? '',
    );
  }

  @override
  void dispose() {
    _senderNameController.dispose();
    _replyToEmailController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSaving) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      await _supabase
          .from('clubs')
          .update({
            'communication_sender_name': _nullIfBlank(
              _senderNameController.text,
            ),
            'communication_reply_to_email': _nullIfBlank(
              _replyToEmailController.text,
            ),
          })
          .eq('id', widget.clubId);

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorMessage = 'Unable to save communication settings: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Communication Settings'),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_errorMessage != null) ...[
              _InlineError(message: _errorMessage!),
              const SizedBox(height: 14),
            ],
            _EmailAddonNotice(enabled: widget.emailAddonEnabled),
            const SizedBox(height: 14),
            TextField(
              controller: _senderNameController,
              decoration: const InputDecoration(
                labelText: 'Sender name',
                hintText: 'Example: ISRBA Secretary',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _replyToEmailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Reply-to email',
                hintText: 'secretary@example.com',
                border: OutlineInputBorder(),
              ),
            ),
          ],
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
}

class _CommunicationTemplate {
  const _CommunicationTemplate({
    required this.id,
    required this.name,
    required this.subject,
    required this.body,
    required this.channelDefault,
    required this.isSystemDefault,
    required this.isEnabled,
    this.clubId,
    this.templateKey,
    this.description,
  });

  final String id;
  final String? clubId;
  final String? templateKey;
  final String name;
  final String? description;
  final String subject;
  final String body;
  final String channelDefault;
  final bool isSystemDefault;
  final bool isEnabled;

  String get bodyPreview => body.replaceAll(RegExp(r'\s+'), ' ').trim();

  bool get isWorkflowEventTemplate {
    final key = templateKey?.trim().toLowerCase();
    if (key == null || key.isEmpty) return false;

    return key.startsWith('membership_') ||
        key.startsWith('sanction_') ||
        key == 'payment_received' ||
        key == 'pending_check_reminder';
  }

  bool get isManualComposeTemplate => !isWorkflowEventTemplate;

  bool get canUseForManualCompose => isEnabled && isManualComposeTemplate;

  factory _CommunicationTemplate.fromJson(Map<String, dynamic> json) {
    return _CommunicationTemplate(
      id: json['id'].toString(),
      clubId: _nullableString(json['club_id']),
      templateKey: _nullableString(json['template_key']),
      name: _nullableString(json['name']) ?? 'Untitled Template',
      description: _nullableString(json['description']),
      subject: _nullableString(json['subject']) ?? '',
      body:
          _nullableString(json['body']) ??
          _nullableString(json['message']) ??
          '',
      channelDefault:
          _nullableString(json['channel_default']) ?? 'notification',
      isSystemDefault: json['is_system_default'] == true,
      isEnabled: json['is_enabled'] != false,
    );
  }
}

class _CommunicationBatch {
  const _CommunicationBatch({
    required this.id,
    required this.messageKind,
    required this.subject,
    required this.body,
    required this.status,
    required this.recipientCount,
    required this.notificationCount,
    required this.emailCount,
    required this.createdAt,
    this.templateKey,
    this.audienceType,
    this.sentAt,
  });

  final String id;
  final String messageKind;
  final String? templateKey;
  final String subject;
  final String body;
  final String? audienceType;
  final int recipientCount;
  final int notificationCount;
  final int emailCount;
  final String status;
  final DateTime? sentAt;
  final DateTime createdAt;

  String get preview => body.replaceAll(RegExp(r'\s+'), ' ').trim();

  factory _CommunicationBatch.fromJson(Map<String, dynamic> json) {
    return _CommunicationBatch(
      id: json['id'].toString(),
      messageKind: _nullableString(json['message_kind']) ?? 'template',
      templateKey: _nullableString(json['template_key']),
      subject: _nullableString(json['subject']) ?? 'Untitled Message',
      body: _nullableString(json['body']) ?? '',
      audienceType: _nullableString(json['audience_type']),
      recipientCount: _intValue(json['recipient_count']),
      notificationCount: _intValue(json['notification_count']),
      emailCount: _intValue(json['email_count']),
      status: _nullableString(json['status']) ?? 'draft',
      sentAt: _nullableDate(json['sent_at']),
      createdAt: _nullableDate(json['created_at']) ?? DateTime.now(),
    );
  }
}

class _CommunicationRecord {
  const _CommunicationRecord({
    required this.id,
    required this.subject,
    required this.body,
    required this.channel,
    required this.status,
    required this.createdAt,
    this.recipientName,
    this.recipientEmail,
    this.sentAt,
    this.errorMessage,
  });

  final String id;
  final String subject;
  final String body;
  final String? recipientName;
  final String? recipientEmail;
  final String channel;
  final String status;
  final DateTime? sentAt;
  final String? errorMessage;
  final DateTime createdAt;

  factory _CommunicationRecord.fromJson(Map<String, dynamic> json) {
    return _CommunicationRecord(
      id: json['id'].toString(),
      subject: _nullableString(json['subject']) ?? 'Untitled Message',
      body:
          _nullableString(json['body']) ??
          _nullableString(json['message']) ??
          '',
      recipientName: _nullableString(json['recipient_name']),
      recipientEmail: _nullableString(json['recipient_email']),
      channel: _nullableString(json['channel']) ?? 'notification',
      status: _nullableString(json['status']) ?? 'queued',
      sentAt: _nullableDate(json['sent_at']),
      errorMessage: _nullableString(json['error_message']),
      createdAt: _nullableDate(json['created_at']) ?? DateTime.now(),
    );
  }
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
          crossAxisAlignment: CrossAxisAlignment.start,
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
                    ? 'Email Add-on enabled. Messages can create notifications and queue email delivery.'
                    : 'Base communications create in-app notifications and history records. Email delivery is available with the Email Add-on.',
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

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(12),
      child: Padding(padding: const EdgeInsets.all(12), child: Text(message)),
    );
  }
}

String? _required(String? value) {
  return value == null || value.trim().isEmpty ? 'Required.' : null;
}

String? _nullableString(dynamic value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

String? _nullIfBlank(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

DateTime? _nullableDate(dynamic value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) return null;
  return DateTime.tryParse(text);
}

int _intValue(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '') ?? 0;
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

String _renderPreviewText(String value, String clubName) {
  return value
      .replaceAll('{{club_name}}', clubName)
      .replaceAll('{{recipient_name}}', 'Recipient')
      .replaceAll('{{membership_type}}', 'Membership Type')
      .replaceAll('{{amount_due}}', 'Amount Due')
      .replaceAll('{{amount_paid}}', 'Amount Paid')
      .replaceAll('{{payment_method}}', 'Payment Method')
      .replaceAll('{{staff_message}}', 'Staff message')
      .replaceAll('{{requesting_club_name}}', 'Requesting Club')
      .replaceAll('{{show_date}}', 'Show Date')
      .replaceAll('{{contact_name}}', 'Contact Name')
      .replaceAll('{{request_scope}}', 'Request Scope')
      .replaceAll('{{treasurer_mailing_address}}', 'Treasurer Mailing Address')
      .replaceAll('{{message_body}}', 'Message preview');
}

String _slugFromName(String value) {
  final slug = value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');

  return slug.isEmpty
      ? 'custom_template_${DateTime.now().millisecondsSinceEpoch}'
      : slug;
}

extension _FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class _MemberRecipientOption {
  const _MemberRecipientOption({
    required this.id,
    required this.fullName,
    required this.status,
    this.relatedType = 'club_membership',
    this.userId,
    this.email,
  });

  final String id;
  final String relatedType;
  final String? userId;
  final String fullName;
  final String? email;
  final String status;

  bool get isActive {
    final normalized = status.trim().toLowerCase();
    return normalized.isEmpty ||
        normalized == 'active' ||
        normalized == 'current' ||
        normalized == 'approved' ||
        normalized == 'paid';
  }

  bool get isExpired {
    final normalized = status.trim().toLowerCase();
    return normalized == 'expired' ||
        normalized == 'inactive' ||
        normalized == 'lapsed';
  }

  bool get isUnpaid {
    final normalized = status.trim().toLowerCase();
    return normalized == 'unpaid' ||
        normalized == 'payment_due' ||
        normalized == 'pending_payment';
  }

  bool get isBoardOrStaff {
    final normalized = status.trim().toLowerCase();
    return normalized == 'board' ||
        normalized == 'officer' ||
        normalized == 'staff' ||
        normalized == 'admin';
  }

  bool get isStaffActive => status.trim().toLowerCase() == 'active';

  String get displayLabel {
    final parts = [fullName, ?email];
    return parts.join(' • ');
  }

  String get searchText => displayLabel.toLowerCase();

  factory _MemberRecipientOption.fromJson(
    Map<String, dynamic> json, {
    String relatedType = 'club_membership',
  }) {
    final firstName = _nullableString(json['first_name']);
    final lastName = _nullableString(json['last_name']);
    final fullName = [firstName, lastName]
        .whereType<String>()
        .where((part) => part.trim().isNotEmpty)
        .join(' ')
        .trim();

    return _MemberRecipientOption(
      id: json['id'].toString(),
      relatedType: relatedType,
      userId: _nullableString(json['user_id']),
      fullName: fullName.isEmpty ? 'Unnamed Member' : fullName,
      email: _nullableString(json['email']),
      status:
          _nullableString(json['payment_status']) ??
          _nullableString(json['status']) ??
          '',
    );
  }

  factory _MemberRecipientOption.fromStaffJson(Map<String, dynamic> json) {
    return _MemberRecipientOption(
      id:
          json['id']?.toString() ??
          json['assignment_id']?.toString() ??
          json['user_id']?.toString() ??
          'staff',
      relatedType: 'club_staff',
      userId: _nullableString(json['user_id']),
      fullName:
          _nullableString(json['display_name']) ??
          _nullableString(json['name']) ??
          _nullableString(json['email']) ??
          'Club Staff',
      email: _nullableString(json['email']),
      status: _nullableString(json['status']) ?? '',
    );
  }
}
