import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/clubs/club_summary.dart';
import '../../../services/clubs/club_service.dart';
import 'club_member_announcements_screen.dart';
import 'club_member_documents_screen.dart';
import 'club_member_events_screen.dart';
import 'club_membership_cards_screen.dart';

enum MemberNetworkView { events, resources, announcements, memberships }

/// Account-wide member views assembled from every club the user belongs to.
class MemberNetworkScreen extends StatefulWidget {
  const MemberNetworkScreen({super.key, required this.view});

  final MemberNetworkView view;

  @override
  State<MemberNetworkScreen> createState() => _MemberNetworkScreenState();
}

class _MemberNetworkScreenState extends State<MemberNetworkScreen> {
  final _supabase = Supabase.instance.client;
  final _clubService = ClubService();
  bool _loading = true;
  String? _error;
  List<_NetworkItem> _items = const [];
  List<_PersonalMembershipCard> _personalCards = const [];
  DateTime _visibleMonth = _monthFor(DateTime.now());
  DateTime _selectedDay = _dayFor(DateTime.now());

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
      final clubs = (await _clubService.getMyClubs())
          .where((club) => club.isMember || club.isStaff)
          .toList();
      final user = _supabase.auth.currentUser;
      if (user == null) throw StateError('Please sign in again.');
      final itemLists = await Future.wait(
        clubs.map((club) => _loadClubItems(club, user.id, user.email)),
      );
      final personalRows = widget.view == MemberNetworkView.memberships
          ? await _supabase
                .from('personal_membership_cards')
                .select('id,club_name,expires_on,photo_paths')
                .eq('user_id', user.id)
                .order('created_at', ascending: false)
          : const [];
      final personalCards = await Future.wait(
        personalRows.whereType<Map>().map(
          (row) => _PersonalMembershipCard.fromJson(
            Map<String, dynamic>.from(row),
            _supabase,
          ),
        ),
      );
      if (!mounted) return;
      setState(() {
        _items = itemLists.expand((items) => items).toList()
          ..sort(
            (a, b) =>
                (a.date ?? DateTime(3000)).compareTo(b.date ?? DateTime(3000)),
          );
        _personalCards = personalCards;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  Future<List<_NetworkItem>> _loadClubItems(
    ClubSummary club,
    String userId,
    String? userEmail,
  ) async {
    switch (widget.view) {
      case MemberNetworkView.events:
        final rows = await _supabase
            .from('club_events')
            .select('id,title,start_at,event_type,visibility,status')
            .eq('club_id', club.clubId)
            .eq('status', 'published')
            .order('start_at');
        final events = (rows as List)
            .whereType<Map>()
            .where((row) {
              final visibility = row['visibility']?.toString().toLowerCase();
              final start = DateTime.tryParse(
                row['start_at']?.toString() ?? '',
              );
              return (visibility == 'members' || visibility == 'public') &&
                  (start == null || !start.isBefore(DateTime.now()));
            })
            .map(
              (row) => _NetworkItem(
                club: club,
                title: _text(row['title'], 'Untitled event'),
                subtitle: _text(row['event_type'], 'Event'),
                date: DateTime.tryParse(
                  row['start_at']?.toString() ?? '',
                )?.toLocal(),
              ),
            )
            .toList();
        final membership = await _findMembership(club, userId, userEmail);
        final expiration = DateTime.tryParse(
          membership?['current_term_end']?.toString() ?? '',
        )?.toLocal();
        if (expiration != null) {
          events.add(
            _NetworkItem(
              club: club,
              title: 'Membership renewal due',
              subtitle: 'Your ${club.displayName} membership expires',
              date: expiration,
              isMembershipExpiration: true,
            ),
          );
        }
        return events;
      case MemberNetworkView.resources:
        final rows = await _supabase
            .from('club_documents')
            .select('id,title,description,published_at,visibility,status')
            .eq('club_id', club.clubId)
            .eq('status', 'active')
            .order('published_at', ascending: false);
        return (rows as List)
            .whereType<Map>()
            .where((row) {
              final visibility = row['visibility']?.toString().toLowerCase();
              return visibility == 'members' || visibility == 'public';
            })
            .map(
              (row) => _NetworkItem(
                club: club,
                title: _text(row['title'], 'Untitled document'),
                subtitle: _text(row['description'], 'Club resource'),
                date: DateTime.tryParse(
                  row['published_at']?.toString() ?? '',
                )?.toLocal(),
              ),
            )
            .toList();
      case MemberNetworkView.announcements:
        final rows = await _supabase
            .from('club_communications')
            .select(
              'id,message_kind,subject,body,message,sent_at,created_at,status',
            )
            .eq('club_id', club.clubId)
            .eq('recipient_user_id', userId)
            .inFilter('message_kind', [
              'custom_individual',
              'custom_audience',
              'newsletter',
            ])
            .order('created_at', ascending: false);
        return (rows as List)
            .whereType<Map>()
            .where(
              (row) => const [
                'sent',
                'delivered',
              ].contains(row['status']?.toString().toLowerCase()),
            )
            .map(
              (row) => _NetworkItem(
                club: club,
                title: _text(row['subject'], 'Club announcement'),
                subtitle: _text(row['body'] ?? row['message'], 'Announcement'),
                date: DateTime.tryParse(
                  (row['sent_at'] ?? row['created_at'])?.toString() ?? '',
                )?.toLocal(),
              ),
            )
            .toList();
      case MemberNetworkView.memberships:
        final membership = await _findMembership(club, userId, userEmail);
        if (membership == null) return const [];
        String typeName = 'Membership';
        final typeId = membership['membership_type_id']?.toString();
        if (typeId != null) {
          final type = await _supabase
              .from('club_membership_types')
              .select('name')
              .eq('id', typeId)
              .maybeSingle();
          typeName = _text(type?['name'], typeName);
        }
        return [
          _NetworkItem(
            club: club,
            title: typeName,
            subtitle:
                '${_text(membership['status'], 'Unknown')} • ${_text(membership['membership_number'], 'Number not assigned')}',
            date: DateTime.tryParse(
              membership['current_term_end']?.toString() ?? '',
            )?.toLocal(),
          ),
        ];
    }
  }

  Future<Map?> _findMembership(
    ClubSummary club,
    String userId,
    String? userEmail,
  ) async {
    const fields =
        'id,membership_type_id,membership_number,status,current_term_end,first_name,last_name';
    Map? membership;
    final membershipId = club.membershipId;
    if (membershipId != null) {
      membership = await _supabase
          .from('club_memberships')
          .select(fields)
          .eq('id', membershipId)
          .maybeSingle();
    }
    membership ??= await _supabase
        .from('club_memberships')
        .select(fields)
        .eq('club_id', club.clubId)
        .eq('user_id', userId)
        .maybeSingle();
    final email = userEmail?.trim();
    if (membership == null && email != null && email.isNotEmpty) {
      membership = await _supabase
          .from('club_memberships')
          .select(fields)
          .eq('club_id', club.clubId)
          .eq('email', email)
          .limit(1)
          .maybeSingle();
    }
    return membership;
  }

  String get _title => switch (widget.view) {
    MemberNetworkView.events => 'My Events',
    MemberNetworkView.resources => 'My Resources',
    MemberNetworkView.announcements => 'My Announcements',
    MemberNetworkView.memberships => 'My Membership Cards',
  };
  String get _intro => switch (widget.view) {
    MemberNetworkView.events =>
      'Meetings, shows, and membership renewal dates from all of your clubs.',
    MemberNetworkView.resources =>
      'Documents, forms, and resources shared by all of your clubs.',
    MemberNetworkView.announcements =>
      'Announcements delivered to you by all of your clubs.',
    MemberNetworkView.memberships =>
      'Digital membership cards for every club linked to your account.',
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_title),
      actions: [
        if (widget.view == MemberNetworkView.memberships)
          IconButton(
            tooltip: 'Add another membership card',
            onPressed: _loading ? null : _addPersonalCard,
            icon: const Icon(Icons.add_card_outlined),
          ),
        IconButton(
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh),
          tooltip: 'Refresh',
        ),
      ],
    ),
    body: SafeArea(child: _body(context)),
  );

  Widget _body(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return _NetworkMessage(
        title: 'We could not load this view',
        message: _error!,
        onRefresh: _load,
      );
    }
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          _title,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(_intro, style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 18),
        if (widget.view == MemberNetworkView.memberships) ...[
          ..._personalCards.map(_personalCard),
          if (_items.isEmpty && _personalCards.isEmpty)
            _NetworkMessage(
              title: 'No membership cards yet',
              message: 'Add a personal card or join a club to get started.',
              onRefresh: _load,
            )
          else
            ..._items.map(_itemCard),
        ] else if (_items.isEmpty)
          _NetworkMessage(
            title: 'Nothing to show yet',
            message: 'Your clubs have not published anything here yet.',
            onRefresh: _load,
          )
        else if (widget.view == MemberNetworkView.events)
          _eventsCalendar(context)
        else
          ..._items.map(_itemCard),
      ],
    );
  }

  Widget _eventsCalendar(BuildContext context) {
    final selectedItems = _items
        .where(
          (item) => item.date != null && _isSameDay(item.date!, _selectedDay),
        )
        .toList();
    final selectedLabel = _date(_selectedDay);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _EventsMonthCalendar(
          month: _visibleMonth,
          selectedDay: _selectedDay,
          eventDates: _items
              .where((item) => item.date != null)
              .map((item) => item.date!)
              .toList(),
          onPreviousMonth: () => setState(
            () => _visibleMonth = DateTime(
              _visibleMonth.year,
              _visibleMonth.month - 1,
            ),
          ),
          onNextMonth: () => setState(
            () => _visibleMonth = DateTime(
              _visibleMonth.year,
              _visibleMonth.month + 1,
            ),
          ),
          onSelectDay: (day) => setState(() {
            _selectedDay = _dayFor(day);
            _visibleMonth = _monthFor(day);
          }),
        ),
        const SizedBox(height: 24),
        Text(
          selectedItems.isEmpty
              ? 'Nothing scheduled on $selectedLabel'
              : 'Scheduled for $selectedLabel',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        if (selectedItems.isEmpty)
          const Text(
            'Choose another highlighted date to see an event or renewal date.',
          )
        else
          ...selectedItems.map(_itemCard),
      ],
    );
  }

  Widget _itemCard(_NetworkItem item) {
    final isMembership = widget.view == MemberNetworkView.memberships;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: item.isMembershipExpiration
            ? const Icon(Icons.event_repeat_outlined)
            : isMembership && item.club.logoUrl != null
            ? CircleAvatar(backgroundImage: NetworkImage(item.club.logoUrl!))
            : Icon(_icon),
        title: Text(
          item.title,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          '${item.club.displayName} • ${item.subtitle}${item.date == null ? '' : '\n${_date(item.date!)}'}',
        ),
        isThreeLine: item.date != null,
        trailing: item.isMembershipExpiration
            ? const Chip(label: Text('Renewal'))
            : const Icon(Icons.chevron_right),
        onTap: item.isMembershipExpiration
            ? null
            : () => _openClubView(item.club),
      ),
    );
  }

  Widget _personalCard(_PersonalMembershipCard card) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: card.photoUrl == null
          ? const Icon(Icons.credit_card_outlined)
          : ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.network(
                card.photoUrl!,
                width: 52,
                height: 40,
                fit: BoxFit.cover,
              ),
            ),
      title: Text(
        card.clubName,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        card.expiresOn == null
            ? 'Personal membership card'
            : 'Expires ${_date(card.expiresOn!)}',
      ),
      trailing: const Chip(label: Text('Personal')),
    ),
  );

  Future<void> _addPersonalCard() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => const _AddPersonalMembershipCardDialog(),
    );
    if (saved == true) await _load();
  }

  IconData get _icon => switch (widget.view) {
    MemberNetworkView.events => Icons.event_outlined,
    MemberNetworkView.resources => Icons.folder_outlined,
    MemberNetworkView.announcements => Icons.campaign_outlined,
    MemberNetworkView.memberships => Icons.badge_outlined,
  };
  void _openClubView(ClubSummary club) {
    final page = switch (widget.view) {
      MemberNetworkView.events => ClubMemberEventsScreen(club: club),
      MemberNetworkView.resources => ClubMemberDocumentsScreen(club: club),
      MemberNetworkView.announcements => ClubMemberAnnouncementsScreen(
        club: club,
      ),
      MemberNetworkView.memberships => ClubMembershipCardsScreen(club: club),
    };
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }
}

class _EventsMonthCalendar extends StatelessWidget {
  const _EventsMonthCalendar({
    required this.month,
    required this.selectedDay,
    required this.eventDates,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.onSelectDay,
  });

  final DateTime month;
  final DateTime selectedDay;
  final List<DateTime> eventDates;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final ValueChanged<DateTime> onSelectDay;

  @override
  Widget build(BuildContext context) {
    final firstDay = DateTime(month.year, month.month);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    // Convert Sunday (7) to 0 so the grid starts on Sunday.
    final leadingBlanks = firstDay.weekday % 7;
    final cells = List<Widget>.generate(leadingBlanks + daysInMonth, (index) {
      if (index < leadingBlanks) return const SizedBox.shrink();
      final day = DateTime(month.year, month.month, index - leadingBlanks + 1);
      final hasEvents = eventDates.any(
        (eventDate) => _isSameDay(eventDate, day),
      );
      final isSelected = _isSameDay(day, selectedDay);
      final isToday = _isSameDay(day, DateTime.now());
      final foreground = isSelected
          ? Theme.of(context).colorScheme.onPrimary
          : Theme.of(context).colorScheme.onSurface;
      return InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => onSelectDay(day),
        child: Container(
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: isSelected ? Theme.of(context).colorScheme.primary : null,
            border: isToday && !isSelected
                ? Border.all(color: Theme.of(context).colorScheme.primary)
                : null,
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('${day.day}', style: TextStyle(color: foreground)),
                const SizedBox(height: 2),
                SizedBox(
                  height: 5,
                  child: hasEvents
                      ? DecoratedBox(
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Theme.of(context).colorScheme.onPrimary
                                : Theme.of(context).colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                          child: const SizedBox(width: 5, height: 5),
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
      );
    });
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Previous month',
                  onPressed: onPreviousMonth,
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: Text(
                    _monthLabel(month),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Next month',
                  onPressed: onNextMonth,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Row(
              children: [
                _CalendarWeekday('Sun'),
                _CalendarWeekday('Mon'),
                _CalendarWeekday('Tue'),
                _CalendarWeekday('Wed'),
                _CalendarWeekday('Thu'),
                _CalendarWeekday('Fri'),
                _CalendarWeekday('Sat'),
              ],
            ),
            const SizedBox(height: 6),
            GridView.count(
              crossAxisCount: 7,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.1,
              children: cells,
            ),
          ],
        ),
      ),
    );
  }
}

class _CalendarWeekday extends StatelessWidget {
  const _CalendarWeekday(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Text(
      label,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.labelSmall,
    ),
  );
}

class _NetworkItem {
  const _NetworkItem({
    required this.club,
    required this.title,
    required this.subtitle,
    this.date,
    this.isMembershipExpiration = false,
  });
  final ClubSummary club;
  final String title;
  final String subtitle;
  final DateTime? date;
  final bool isMembershipExpiration;
}

class _PersonalMembershipCard {
  const _PersonalMembershipCard({
    required this.clubName,
    this.expiresOn,
    this.photoUrl,
  });

  final String clubName;
  final DateTime? expiresOn;
  final String? photoUrl;

  static Future<_PersonalMembershipCard> fromJson(
    Map<String, dynamic> json,
    SupabaseClient supabase,
  ) async {
    final paths = json['photo_paths'] is List
        ? (json['photo_paths'] as List).map((item) => item.toString()).toList()
        : const <String>[];
    String? photoUrl;
    if (paths.isNotEmpty) {
      try {
        photoUrl = await supabase.storage
            .from('personal-membership-cards')
            .createSignedUrl(paths.first, 600);
      } catch (_) {
        // The card details remain available if a prior photo was removed.
      }
    }
    return _PersonalMembershipCard(
      clubName: _text(json['club_name'], 'Unnamed club'),
      expiresOn: DateTime.tryParse(
        json['expires_on']?.toString() ?? '',
      )?.toLocal(),
      photoUrl: photoUrl,
    );
  }
}

class _AddPersonalMembershipCardDialog extends StatefulWidget {
  const _AddPersonalMembershipCardDialog();

  @override
  State<_AddPersonalMembershipCardDialog> createState() =>
      _AddPersonalMembershipCardDialogState();
}

class _AddPersonalMembershipCardDialogState
    extends State<_AddPersonalMembershipCardDialog> {
  final _clubController = TextEditingController();
  final _supabase = Supabase.instance.client;
  DateTime? _expiresOn;
  List<PlatformFile> _photos = const [];
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _clubController.dispose();
    super.dispose();
  }

  Future<void> _pickPhotos() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: true,
    );
    if (result != null && mounted) {
      setState(() => _photos = result.files.take(2).toList());
    }
  }

  Future<void> _save() async {
    final clubName = _clubController.text.trim();
    final user = _supabase.auth.currentUser;
    if (clubName.isEmpty || user == null) {
      setState(() => _error = 'Enter a club name before saving.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final row = await _supabase
          .from('personal_membership_cards')
          .insert({
            'user_id': user.id,
            'club_name': clubName,
            'expires_on': _expiresOn?.toIso8601String().split('T').first,
          })
          .select('id')
          .single();
      final cardId = row['id'].toString();
      final paths = <String>[];
      for (var index = 0; index < _photos.length; index++) {
        final photo = _photos[index];
        final bytes = photo.bytes;
        if (bytes == null) continue;
        final extension = photo.extension?.toLowerCase() ?? 'jpg';
        final path = '${user.id}/$cardId/$index.$extension';
        await _supabase.storage
            .from('personal-membership-cards')
            .uploadBinary(
              path,
              bytes,
              fileOptions: FileOptions(
                contentType: _imageContentType(extension),
                upsert: false,
              ),
            );
        paths.add(path);
      }
      if (paths.isNotEmpty) {
        await _supabase
            .from('personal_membership_cards')
            .update({'photo_paths': paths})
            .eq('id', cardId);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Unable to save your card: $error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add Membership Card'),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            TextField(
              controller: _clubController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Club Name'),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Membership expiration date'),
              subtitle: Text(
                _expiresOn == null ? 'No expiration date' : _date(_expiresOn!),
              ),
              trailing: const Icon(Icons.calendar_today_outlined),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                  initialDate: _expiresOn ?? DateTime.now(),
                );
                if (picked != null && mounted) {
                  setState(() => _expiresOn = picked);
                }
              },
            ),
            OutlinedButton.icon(
              onPressed: _saving ? null : _pickPhotos,
              icon: const Icon(Icons.add_a_photo_outlined),
              label: Text(
                _photos.isEmpty
                    ? 'Add card photo(s)'
                    : '${_photos.length} photo${_photos.length == 1 ? '' : 's'} selected',
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Add a front image and, if needed, a back image. Photos are private to your account.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: Text(_saving ? 'Saving…' : 'Save Card'),
      ),
    ],
  );
}

class _NetworkMessage extends StatelessWidget {
  const _NetworkMessage({
    required this.title,
    required this.message,
    required this.onRefresh,
  });
  final String title;
  final String message;
  final VoidCallback onRefresh;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.inbox_outlined, size: 46),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh'),
          ),
        ],
      ),
    ),
  );
}

String _text(dynamic value, String fallback) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? fallback : text;
}

String _date(DateTime value) {
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

DateTime _dayFor(DateTime value) =>
    DateTime(value.year, value.month, value.day);

DateTime _monthFor(DateTime value) => DateTime(value.year, value.month);

bool _isSameDay(DateTime first, DateTime second) =>
    first.year == second.year &&
    first.month == second.month &&
    first.day == second.day;

String _monthLabel(DateTime value) {
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${months[value.month - 1]} ${value.year}';
}

String _imageContentType(String extension) => switch (extension) {
  'png' => 'image/png',
  'webp' => 'image/webp',
  _ => 'image/jpeg',
};
