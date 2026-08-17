import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/clubs/club_summary.dart';

/// Personal announcement inbox: only messages addressed to the signed-in user.
class ClubMemberAnnouncementsScreen extends StatefulWidget {
  const ClubMemberAnnouncementsScreen({super.key, required this.club});

  final ClubSummary club;

  @override
  State<ClubMemberAnnouncementsScreen> createState() =>
      _ClubMemberAnnouncementsScreenState();
}

class _ClubMemberAnnouncementsScreenState
    extends State<ClubMemberAnnouncementsScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  String? _errorMessage;
  List<_Announcement> _announcements = const [];

  @override
  void initState() {
    super.initState();
    _loadAnnouncements();
  }

  Future<void> _loadAnnouncements() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        throw StateError('Please sign in again to view announcements.');
      }
      final rows = await _supabase
          .from('club_communications')
          .select(
            'id,message_kind,channel,subject,body,message,status,sent_at,'
            'read_at,created_at',
          )
          .eq('club_id', widget.club.clubId)
          .eq('recipient_user_id', user.id)
          .inFilter('message_kind', [
            'custom_individual',
            'custom_audience',
            'newsletter',
          ])
          .order('created_at', ascending: false);
      final announcements = (rows as List)
          .whereType<Map>()
          .map((row) => _Announcement.fromJson(Map<String, dynamic>.from(row)))
          .where((message) => message.isDelivered)
          .toList();
      if (!mounted) return;
      setState(() {
        _announcements = announcements;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Unable to load announcements: $error';
      });
    }
  }

  Future<void> _openAnnouncement(_Announcement announcement) async {
    if (announcement.readAt == null) {
      try {
        await _supabase
            .from('club_communications')
            .update({'read_at': DateTime.now().toUtc().toIso8601String()})
            .eq('id', announcement.id)
            .eq('recipient_user_id', _supabase.auth.currentUser?.id ?? '');
        if (mounted) {
          setState(() {
            _announcements = _announcements
                .map(
                  (item) => item.id == announcement.id
                      ? item.copyWith(readAt: DateTime.now())
                      : item,
                )
                .toList();
          });
        }
      } catch (_) {
        // The message can still be read even if the notification status cannot
        // be saved by an older RLS policy.
      }
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  announcement.subject,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _formatDateTime(
                    announcement.sentAt ?? announcement.createdAt,
                  ),
                ),
                const SizedBox(height: 20),
                SelectableText(announcement.body),
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Club Announcements'),
        actions: [
          IconButton(
            tooltip: 'Refresh announcements',
            onPressed: _isLoading ? null : _loadAnnouncements,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(child: _buildBody(context)),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_errorMessage != null) {
      return _AnnouncementsMessageState(
        icon: Icons.error_outline,
        title: 'We could not load announcements',
        message: _errorMessage!,
        actionLabel: 'Try again',
        onAction: _loadAnnouncements,
      );
    }
    if (_announcements.isEmpty) {
      return _AnnouncementsMessageState(
        icon: Icons.campaign_outlined,
        title: 'No announcements yet',
        message:
            '${widget.club.displayName} has not sent you any announcements yet.',
        actionLabel: 'Refresh',
        onAction: _loadAnnouncements,
      );
    }
    final unread = _announcements
        .where((announcement) => announcement.readAt == null)
        .length;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Club announcements',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          unread == 0
              ? 'You are all caught up with ${widget.club.displayName}.'
              : '$unread unread announcement${unread == 1 ? '' : 's'} from ${widget.club.displayName}.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 18),
        ..._announcements.map(
          (announcement) => _AnnouncementCard(
            announcement: announcement,
            onTap: () => _openAnnouncement(announcement),
          ),
        ),
      ],
    );
  }
}

class _Announcement {
  const _Announcement({
    required this.id,
    required this.subject,
    required this.body,
    required this.channel,
    required this.status,
    required this.sentAt,
    required this.readAt,
    required this.createdAt,
  });
  final String id;
  final String subject;
  final String body;
  final String channel;
  final String status;
  final DateTime? sentAt;
  final DateTime? readAt;
  final DateTime createdAt;

  bool get isDelivered {
    final value = status.toLowerCase();
    return value == 'sent' || value == 'delivered' || value == 'read';
  }

  _Announcement copyWith({DateTime? readAt}) => _Announcement(
    id: id,
    subject: subject,
    body: body,
    channel: channel,
    status: status,
    sentAt: sentAt,
    readAt: readAt ?? this.readAt,
    createdAt: createdAt,
  );

  factory _Announcement.fromJson(Map<String, dynamic> json) => _Announcement(
    id: json['id'].toString(),
    subject: _textOrNull(json['subject']) ?? 'Club announcement',
    body: _textOrNull(json['body']) ?? _textOrNull(json['message']) ?? '',
    channel: _textOrNull(json['channel']) ?? 'notification',
    status: _textOrNull(json['status']) ?? 'queued',
    sentAt: _dateOrNull(json['sent_at']),
    readAt: _dateOrNull(json['read_at']),
    createdAt: _dateOrNull(json['created_at']) ?? DateTime.now(),
  );
}

class _AnnouncementCard extends StatelessWidget {
  const _AnnouncementCard({required this.announcement, required this.onTap});
  final _Announcement announcement;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      leading: Icon(
        announcement.readAt == null
            ? Icons.mark_email_unread_outlined
            : Icons.drafts_outlined,
        size: 30,
      ),
      title: Text(
        announcement.subject,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 5),
        child: Text(
          '${_formatDateTime(announcement.sentAt ?? announcement.createdAt)}\n${_preview(announcement.body)}',
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    ),
  );
}

class _AnnouncementsMessageState extends StatelessWidget {
  const _AnnouncementsMessageState({
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
            label: Text(actionLabel),
          ),
        ],
      ),
    ),
  );
}

String? _textOrNull(dynamic value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

DateTime? _dateOrNull(dynamic value) {
  final text = _textOrNull(value);
  return text == null ? null : DateTime.tryParse(text)?.toLocal();
}

String _preview(String value) => value.replaceAll(RegExp(r'\s+'), ' ').trim();
String _formatDateTime(DateTime value) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
  final minute = value.minute.toString().padLeft(2, '0');
  return '${months[value.month - 1]} ${value.day}, ${value.year} • $hour:$minute ${value.hour >= 12 ? 'PM' : 'AM'}';
}
