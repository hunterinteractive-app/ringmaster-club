import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/clubs/club_summary.dart';

/// Read-only calendar for club events that have been published to members.
class ClubMemberEventsScreen extends StatefulWidget {
  const ClubMemberEventsScreen({super.key, required this.club});

  final ClubSummary club;

  @override
  State<ClubMemberEventsScreen> createState() => _ClubMemberEventsScreenState();
}

class _ClubMemberEventsScreenState extends State<ClubMemberEventsScreen> {
  final _supabase = Supabase.instance.client;

  bool _isLoading = true;
  bool _eventsEnabled = false;
  String? _errorMessage;
  List<_MemberEvent> _events = const [];

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  Future<void> _loadEvents() async {
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
      final eventsEnabled = clubRow['events_meetings_addon_enabled'] == true;

      if (!eventsEnabled) {
        if (!mounted) return;
        setState(() {
          _eventsEnabled = false;
          _events = const [];
          _isLoading = false;
        });
        return;
      }

      final rows = await _supabase
          .from('club_events')
          .select(
            'id,title,description,event_type,status,visibility,start_at,end_at,'
            'timezone,location_name,location_address,virtual_url,agenda,'
            'requires_rsvp,rsvp_deadline',
          )
          .eq('club_id', widget.club.clubId)
          .eq('status', 'published')
          .order('start_at', ascending: true);

      final events = (rows as List)
          .whereType<Map>()
          .map((row) => _MemberEvent.fromJson(Map<String, dynamic>.from(row)))
          .where((event) => event.isVisibleToMembers && !event.hasEnded)
          .toList();

      if (!mounted) return;
      setState(() {
        _eventsEnabled = true;
        _events = events;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Meetings & Events'),
        actions: [
          IconButton(
            tooltip: 'Refresh events',
            onPressed: _isLoading ? null : _loadEvents,
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
      return _EventsMessageState(
        icon: Icons.error_outline,
        title: 'We could not load events',
        message: _errorMessage!,
        actionLabel: 'Try again',
        onAction: _loadEvents,
      );
    }
    if (!_eventsEnabled) {
      return _EventsMessageState(
        icon: Icons.event_busy_outlined,
        title: 'Events are not enabled yet',
        message:
            '${widget.club.displayName} has not enabled Meetings & Events. Club leadership can turn it on whenever they are ready.',
        actionLabel: 'Refresh',
        onAction: _loadEvents,
      );
    }
    if (_events.isEmpty) {
      return _EventsMessageState(
        icon: Icons.event_available_outlined,
        title: 'No upcoming events',
        message:
            '${widget.club.displayName} has not published any upcoming meetings, shows, or deadlines.',
        actionLabel: 'Refresh',
        onAction: _loadEvents,
      );
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Upcoming events',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          'Meetings, shows, deadlines, and club activities published by ${widget.club.displayName}.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 20),
        ..._events.map(
          (event) =>
              _EventCard(event: event, onTap: () => _showEventDetails(event)),
        ),
      ],
    );
  }

  Future<void> _showEventDetails(_MemberEvent event) {
    return showModalBottomSheet<void>(
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
                  event.title,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                _EventDetail(
                  icon: Icons.schedule_outlined,
                  text: event.dateTimeLabel,
                ),
                if (event.locationLabel != null)
                  _EventDetail(
                    icon: Icons.location_on_outlined,
                    text: event.locationLabel!,
                  ),
                if (event.virtualUrl != null)
                  const _EventDetail(
                    icon: Icons.videocam_outlined,
                    text:
                        'Virtual attendance link is available from club leadership.',
                  ),
                if (event.requiresRsvp)
                  _EventDetail(
                    icon: Icons.how_to_reg_outlined,
                    text: event.rsvpDeadline == null
                        ? 'RSVP required'
                        : 'RSVP required by ${_formatDate(event.rsvpDeadline!)}',
                  ),
                if (event.description != null) ...[
                  const SizedBox(height: 16),
                  Text(event.description!),
                ],
                if (event.agenda != null) ...[
                  const SizedBox(height: 20),
                  Text(
                    'Agenda',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(event.agenda!),
                ],
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
}

class _MemberEvent {
  const _MemberEvent({
    required this.title,
    required this.description,
    required this.eventType,
    required this.visibility,
    required this.startAt,
    required this.endAt,
    required this.locationName,
    required this.locationAddress,
    required this.virtualUrl,
    required this.agenda,
    required this.requiresRsvp,
    required this.rsvpDeadline,
  });

  final String title;
  final String? description;
  final String eventType;
  final String visibility;
  final DateTime startAt;
  final DateTime? endAt;
  final String? locationName;
  final String? locationAddress;
  final String? virtualUrl;
  final String? agenda;
  final bool requiresRsvp;
  final DateTime? rsvpDeadline;

  bool get isVisibleToMembers =>
      visibility.toLowerCase() == 'members' ||
      visibility.toLowerCase() == 'public';

  bool get hasEnded => (endAt ?? startAt).isBefore(DateTime.now());

  String get typeLabel => _titleCase(eventType);

  String get dateTimeLabel {
    final date = _formatDate(startAt);
    final startTime = _formatTime(startAt);
    final end = endAt;
    if (end == null) {
      return '$date • $startTime';
    }
    if (_sameDay(startAt, end)) {
      return '$date • $startTime – ${_formatTime(end)}';
    }
    return '$date • $startTime – ${_formatDate(end)} ${_formatTime(end)}';
  }

  String? get locationLabel {
    return [locationName, locationAddress]
            .whereType<String>()
            .where((value) => value.isNotEmpty)
            .join('\n')
            .trim()
            .isEmpty
        ? null
        : [locationName, locationAddress]
              .whereType<String>()
              .where((value) => value.isNotEmpty)
              .join('\n')
              .trim();
  }

  factory _MemberEvent.fromJson(Map<String, dynamic> json) {
    return _MemberEvent(
      title: _textOrNull(json['title']) ?? 'Untitled event',
      description: _textOrNull(json['description']),
      eventType: _textOrNull(json['event_type']) ?? 'event',
      visibility: _textOrNull(json['visibility']) ?? 'members',
      startAt: _dateOrNull(json['start_at']) ?? DateTime.now(),
      endAt: _dateOrNull(json['end_at']),
      locationName: _textOrNull(json['location_name']),
      locationAddress: _textOrNull(json['location_address']),
      virtualUrl: _textOrNull(json['virtual_url']),
      agenda: _textOrNull(json['agenda']),
      requiresRsvp: json['requires_rsvp'] == true,
      rsvpDeadline: _dateOrNull(json['rsvp_deadline']),
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event, required this.onTap});

  final _MemberEvent event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 10,
        ),
        leading: CircleAvatar(child: Icon(_iconForEventType(event.eventType))),
        title: Text(
          event.title,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Text('${event.typeLabel} • ${event.dateTimeLabel}'),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _EventDetail extends StatelessWidget {
  const _EventDetail({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _EventsMessageState extends StatelessWidget {
  const _EventsMessageState({
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
}

IconData _iconForEventType(String type) {
  switch (type.toLowerCase()) {
    case 'meeting':
      return Icons.groups_outlined;
    case 'show':
      return Icons.emoji_events_outlined;
    case 'deadline':
      return Icons.timer_outlined;
    default:
      return Icons.event_outlined;
  }
}

String? _textOrNull(dynamic value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

DateTime? _dateOrNull(dynamic value) {
  final text = _textOrNull(value);
  return text == null ? null : DateTime.tryParse(text)?.toLocal();
}

bool _sameDay(DateTime first, DateTime second) =>
    first.year == second.year &&
    first.month == second.month &&
    first.day == second.day;

String _formatDate(DateTime value) {
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
  return '${months[value.month - 1]} ${value.day}, ${value.year}';
}

String _formatTime(DateTime value) {
  final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
  final minute = value.minute.toString().padLeft(2, '0');
  final period = value.hour >= 12 ? 'PM' : 'AM';
  return '$hour:$minute $period';
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
