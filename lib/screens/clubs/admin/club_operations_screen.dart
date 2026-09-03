import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class ClubOperationsScreen extends StatefulWidget {
  const ClubOperationsScreen({super.key});

  @override
  State<ClubOperationsScreen> createState() => _ClubOperationsScreenState();
}

class _ClubOperationsScreenState extends State<ClubOperationsScreen> {
  final _supabase = Supabase.instance.client;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _drafts = const [];
  int _readyForReview = 0;
  int _approved = 0;

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
      final data = Map<String, dynamic>.from(
        await _supabase.rpc('get_club_operations_dashboard') as Map,
      );
      final rows = data['drafts'] as List? ?? const [];
      if (!mounted) return;
      setState(() {
        _drafts = rows
            .map((row) => Map<String, dynamic>.from(row as Map))
            .toList();
        _readyForReview =
            (data['ready_for_review_count'] as num?)?.toInt() ?? 0;
        _approved = (data['approved_count'] as num?)?.toInt() ?? 0;
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$error';
        });
      }
    }
  }

  Future<void> _approve(Map<String, dynamic> draft) async {
    final name = draft['club_name']?.toString() ?? 'this club';
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Approve club onboarding?'),
        content: Text(
          'This provisions $name, its purchased services, staff invitations, and payment setup.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Approve & Provision'),
          ),
        ],
      ),
    );
    if (approved != true) return;
    try {
      await _supabase.rpc(
        'approve_club_onboarding_from_operations',
        params: {'p_draft_id': draft['id']},
      );
      if (mounted) _showNotice('$name was approved and provisioned.');
      await _load();
    } catch (error) {
      if (mounted) _showNotice('Unable to approve: $error', isError: true);
    }
  }

  void _showNotice(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(20, 20, 20, 72),
          showCloseIcon: true,
          backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
          duration: const Duration(seconds: 12),
        ),
      );
  }

  Future<void> _showDetails(Map<String, dynamic> draft) async {
    Map<String, dynamic> roster = const {};
    try {
      roster = Map<String, dynamic>.from(
        await _supabase.rpc(
              'get_club_operations_roster_preview',
              params: {'p_draft_id': draft['id']},
            )
            as Map,
      );
    } catch (_) {}
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(draft['club_name']?.toString() ?? 'Onboarding details'),
        content: SizedBox(
          width: 680,
          child: SingleChildScrollView(
            child: _OnboardingDetails(
              answers: Map<String, dynamic>.from(
                draft['answers'] as Map? ?? const {},
              ),
              entitlements: Map<String, dynamic>.from(
                draft['purchased_entitlements'] as Map? ?? const {},
              ),
              roster: roster,
            ),
          ),
        ),
        actions: [
          if ((roster['storage_bucket']?.toString().isNotEmpty ?? false) &&
              (roster['storage_path']?.toString().isNotEmpty ?? false))
            OutlinedButton.icon(
              onPressed: () => _downloadRoster(roster),
              icon: const Icon(Icons.download_outlined),
              label: const Text('Download CSV'),
            ),
          if (roster['has_preview'] == true)
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _openRosterReview(draft, roster);
              },
              icon: const Icon(Icons.edit_note_outlined),
              label: const Text('Review all rows'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _openRosterReview(
    Map<String, dynamic> draft,
    Map<String, dynamic> roster,
  ) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _RosterReviewDialog(draftId: draft['id'].toString(), roster: roster),
    );
    await _load();
  }

  Future<void> _downloadRoster(Map<String, dynamic> roster) async {
    final bucket = roster['storage_bucket']?.toString();
    final path = roster['storage_path']?.toString();
    if (bucket == null || bucket.isEmpty || path == null || path.isEmpty) {
      return;
    }
    try {
      final url = await _supabase.storage
          .from(bucket)
          .createSignedUrl(path, 600);
      if (!await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      )) {
        throw StateError('The browser could not open the roster download.');
      }
    } catch (error) {
      if (mounted) {
        _showNotice('Unable to download roster: $error', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('RingMaster Operations'),
      actions: [
        IconButton(
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(_error!),
            ),
          )
        : ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Club onboarding review',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'Internal RingMaster view — review submitted drafts and activate only the clubs you approve.',
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _Metric(label: 'Ready for review', value: _readyForReview),
                  _Metric(label: 'Approved', value: _approved),
                  _Metric(label: 'All drafts', value: _drafts.length),
                ],
              ),
              const SizedBox(height: 24),
              if (_drafts.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('No club onboarding drafts yet.'),
                  ),
                ),
              ..._drafts.map((draft) {
                final status = draft['status']?.toString() ?? 'unknown';
                final provider =
                    draft['payment_provider']?.toString() ?? 'not_ready';
                final paymentStatus = draft['payment_status']?.toString();
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                draft['club_name']?.toString() ??
                                    'Untitled club',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            _StatusChip(status),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(draft['email']?.toString() ?? ''),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            Chip(
                              label: Text('Plan: ${draft['plan_key'] ?? '—'}'),
                            ),
                            Chip(
                              label: Text(
                                'Payments: $provider${paymentStatus == null ? '' : ' · $paymentStatus'}',
                              ),
                            ),
                            Chip(
                              label: Text(
                                'Step: ${draft['current_step'] ?? 'club'}',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () => _showDetails(draft),
                          icon: const Icon(Icons.visibility_outlined),
                          label: const Text('View entered information'),
                        ),
                        if (status == 'ready_for_review') ...[
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: () => _approve(draft),
                            icon: const Icon(Icons.verified_outlined),
                            label: const Text('Approve & Provision'),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
  );
}

class _OnboardingDetails extends StatelessWidget {
  const _OnboardingDetails({
    required this.answers,
    required this.entitlements,
    required this.roster,
  });

  final Map<String, dynamic> answers;
  final Map<String, dynamic> entitlements;
  final Map<String, dynamic> roster;

  @override
  Widget build(BuildContext context) {
    Map<String, dynamic> map(String key) =>
        Map<String, dynamic>.from(answers[key] as Map? ?? const {});
    final club = map('club');
    final setup = map('setup');
    final treasurer = map('treasurer');
    final imports = map('imports');
    final officers = (answers['officers'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    final membershipTypes = (setup['membership_types'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Section('Purchased services', [
          _Field('Plan', entitlements['plan_key']),
          _Field(
            'Add-ons',
            (entitlements['addons'] as List? ?? const []).join(', '),
          ),
        ]),
        _Section('Club information', [
          _Field('Name', club['name']),
          _Field('Short name', club['short_name']),
          _Field('Website', club['website_url']),
          _Field('Contact', club['contact_name']),
          _Field('Email', club['contact_email']),
          _Field('Phone', club['contact_phone']),
          _Field('Address', _address(club)),
        ]),
        _Section('Setup & payments', [
          _Field(
            'Membership management',
            _yesNo(setup['membership_management']),
          ),
          _Field('Online payments', _yesNo(setup['online_payments'])),
          _Field('Payment provider', setup['payment_provider']),
          _Field('Mailed checks', _yesNo(setup['mailed_checks'])),
          _Field('Events & meetings', _yesNo(setup['events'])),
          _Field('Sanction requests', _yesNo(setup['sanctions'])),
          _Field('Sweepstakes', _yesNo(setup['sweepstakes'])),
        ]),
        if (membershipTypes.isNotEmpty)
          _Section(
            'Membership types',
            membershipTypes
                .map(
                  (type) => _Field(
                    type['name']?.toString() ?? 'Membership',
                    '\$${type['price'] ?? '0'}',
                  ),
                )
                .toList(),
          ),
        if (officers.isNotEmpty)
          _Section(
            'Officers',
            officers
                .map(
                  (officer) => _Field(
                    officer['title']?.toString() ?? 'Officer',
                    [officer['name'], officer['email']]
                        .whereType<String>()
                        .where((v) => v.trim().isNotEmpty)
                        .join(' · '),
                  ),
                )
                .toList(),
          ),
        _Section('Treasurer / check payments', [
          _Field('Name', treasurer['name']),
          _Field('Email', treasurer['email']),
          _Field('Address', treasurer['address']),
        ]),
        _Section('Imports', [
          _Field('Membership roster', _yesNo(imports['membership_roster'])),
          _Field('Sweepstakes archive', _yesNo(imports['sweepstakes_archive'])),
          _Field(
            'Review before import',
            _yesNo(imports['review_before_import']),
          ),
        ]),
        if (roster['has_preview'] == true)
          _RosterPreviewSection(roster: roster),
      ],
    );
  }

  String _yesNo(Object? value) => value == true ? 'Yes' : 'No';
  String _address(Map<String, dynamic> club) => [
    club['address'],
    club['city'],
    club['state'],
    club['postal_code'],
    club['country'],
  ].whereType<String>().where((v) => v.trim().isNotEmpty).join(', ');
}

class _RosterPreviewSection extends StatelessWidget {
  const _RosterPreviewSection({required this.roster});
  final Map<String, dynamic> roster;

  @override
  Widget build(BuildContext context) {
    final rows = (roster['rows'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Membership roster preview',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            '${roster['file_name']} · ${roster['total_rows']} rows · ${roster['valid_rows']} ready · ${roster['error_rows']} need attention',
          ),
          const SizedBox(height: 10),
          if (rows.isEmpty)
            const Text('No parsed rows were saved.')
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Row')),
                  DataColumn(label: Text('Proposed member')),
                  DataColumn(label: Text('Email')),
                  DataColumn(label: Text('Membership')),
                  DataColumn(label: Text('Review')),
                ],
                rows: rows.take(25).map((row) {
                  final member = Map<String, dynamic>.from(
                    row['proposed_member'] as Map? ?? const {},
                  );
                  final name = [member['first_name'], member['last_name']]
                      .whereType<String>()
                      .where((value) => value.trim().isNotEmpty)
                      .join(' ');
                  return DataRow(
                    cells: [
                      DataCell(Text(row['row_number']?.toString() ?? '')),
                      DataCell(Text(name.isEmpty ? 'Missing name' : name)),
                      DataCell(Text(member['email']?.toString() ?? '')),
                      DataCell(
                        Text(
                          member['membership_type']?.toString() ??
                              'Needs review',
                        ),
                      ),
                      DataCell(
                        Text((row['errors'] as List? ?? const []).join(' · ')),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          if (rows.length > 25)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Showing the first 25 rows. The complete staged roster remains available for import review.',
              ),
            ),
        ],
      ),
    );
  }
}

class _RosterReviewDialog extends StatefulWidget {
  const _RosterReviewDialog({required this.draftId, required this.roster});
  final String draftId;
  final Map<String, dynamic> roster;
  @override
  State<_RosterReviewDialog> createState() => _RosterReviewDialogState();
}

class _RosterReviewDialogState extends State<_RosterReviewDialog> {
  final _supabase = Supabase.instance.client;
  late Map<String, dynamic> _roster = widget.roster;
  bool _saving = false;

  List<Map<String, dynamic>> get _rows => (_roster['rows'] as List? ?? const [])
      .whereType<Map>()
      .map((row) => Map<String, dynamic>.from(row))
      .toList();

  Future<void> _edit(Map<String, dynamic> row) async {
    final member = Map<String, dynamic>.from(
      row['proposed_member'] as Map? ?? const {},
    );
    final fields = <String, TextEditingController>{
      for (final key in [
        'first_name',
        'last_name',
        'email',
        'phone',
        'address_line1',
        'city',
        'state',
        'postal_code',
        'membership_type',
        'status',
        'expiration',
      ])
        key: TextEditingController(text: member[key]?.toString() ?? ''),
    };
    final changed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit roster row ${row['row_number']}'),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final entry in fields.entries)
                  SizedBox(
                    width: entry.key == 'address_line1' ? 616 : 302,
                    child: TextField(
                      controller: entry.value,
                      decoration: InputDecoration(
                        labelText: entry.key.replaceAll('_', ' '),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save row'),
          ),
        ],
      ),
    );
    if (changed != true) {
      for (final controller in fields.values) {
        controller.dispose();
      }
      return;
    }
    for (final entry in fields.entries) {
      member[entry.key] = entry.value.text.trim();
      entry.value.dispose();
    }
    final errors = <String>[];
    if ((member['first_name']?.toString().isEmpty ?? true) ||
        (member['last_name']?.toString().isEmpty ?? true)) {
      errors.add('Missing member name');
    }
    setState(() => _saving = true);
    try {
      final result = await _supabase.rpc(
        'update_club_operations_roster_preview_row',
        params: {
          'p_draft_id': widget.draftId,
          'p_row_number': row['row_number'],
          'p_proposed_member': member,
          'p_errors': errors,
        },
      );
      if (mounted) {
        setState(() => _roster = Map<String, dynamic>.from(result as Map));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Roster review — ${_rows.length} rows'),
    content: SizedBox(
      width: 1200,
      height: 650,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: 1500,
          child: ListView.builder(
            itemCount: _rows.length,
            itemBuilder: (context, index) {
              final row = _rows[index];
              final member = Map<String, dynamic>.from(
                row['proposed_member'] as Map? ?? const {},
              );
              final name =
                  '${member['first_name'] ?? ''} ${member['last_name'] ?? ''}'
                      .trim();
              return ListTile(
                leading: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(row['row_number']?.toString() ?? ''),
                    IconButton(
                      tooltip: 'Edit row',
                      onPressed: _saving ? null : () => _edit(row),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                  ],
                ),
                title: Text(
                  '$name  •  ${member['membership_type'] ?? ''}  •  ${member['status'] ?? ''}',
                ),
                subtitle: Text(
                  'Email: ${member['email'] ?? '—'}  |  Phone: ${member['phone'] ?? '—'}  |  Address: ${member['address_line1'] ?? '—'}, ${member['city'] ?? ''}, ${member['state'] ?? ''} ${member['postal_code'] ?? ''}',
                ),
              );
            },
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  );
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.fields);
  final String title;
  final List<_Field> fields;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        ...fields.where((field) => field.value.trim().isNotEmpty),
      ],
    ),
  );
}

class _Field extends StatelessWidget {
  _Field(this.label, Object? value) : value = value?.toString() ?? '';
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 180,
          child: Text(label, style: Theme.of(context).textTheme.labelLarge),
        ),
        Expanded(child: Text(value)),
      ],
    ),
  );
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final int value;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 180,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label),
            const SizedBox(height: 8),
            Text('$value', style: Theme.of(context).textTheme.headlineMedium),
          ],
        ),
      ),
    ),
  );
}

class _StatusChip extends StatelessWidget {
  const _StatusChip(this.status);
  final String status;
  @override
  Widget build(BuildContext context) =>
      Chip(label: Text(status.replaceAll('_', ' ')));
}
