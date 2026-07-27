import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/clubs/club_summary.dart';
import '../../../utils/archive_file_reader.dart';
import '../../../utils/archive_folder_picker.dart';
import 'club_members_screen.dart';

class ClubOnboardingScreen extends StatelessWidget {
  const ClubOnboardingScreen({super.key, required this.club});

  final ClubSummary club;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Bring Your Club Onboard')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Move your existing club records into RingMaster Club.',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        const Text(
          'Both steps are review-first. Nothing is published or applied automatically.',
        ),
        const SizedBox(height: 24),
        _StepCard(
          number: '1',
          icon: Icons.groups_outlined,
          title: 'Import membership roster',
          description:
              'Upload an Excel or CSV roster, map membership categories, and review duplicate names before import.',
          action: 'Open member import',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  ClubMembersScreen(club: club, openMembershipListUpload: true),
            ),
          ),
        ),
        const SizedBox(height: 16),
        _StepCard(
          number: '2',
          icon: Icons.folder_zip_outlined,
          title: 'Import sweepstakes archive',
          description:
              'Upload each show folder as a report package. Every report stays in review until staff verifies and approves it.',
          action: 'Open report archive',
          onPressed: () => _importArchive(context, club),
        ),
      ],
    ),
  );
}

Future<void> _importArchive(BuildContext context, ClubSummary club) async {
  List<ArchiveFile> files;
  try {
    final root = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choose report archive folder',
    );
    if (root == null || !context.mounted) return;
    files = await readPdfArchive(root);
  } on UnimplementedError {
    final selected = await pickArchiveFolder();
    if (selected == null) return;
    files = selected;
  }
  if (!context.mounted || files.isEmpty) return;
  final groups = <String, List<ArchiveFile>>{};
  for (final file in files) {
    final slash = file.relativePath.lastIndexOf('/');
    final key = slash < 0
        ? _showGroupFromFileName(file.relativePath)
        : file.relativePath.substring(0, slash);
    (groups[key] ??= []).add(file);
  }
  final approved = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Import report archive'),
      content: Text(
        '${files.length} PDFs will become ${groups.length} private review packages. No standings will change.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Upload'),
        ),
      ],
    ),
  );
  if (approved != true || !context.mounted) return;
  final client = Supabase.instance.client;
  final storage = await client.functions.invoke(
    'provision-club-storage',
    body: {'club_id': club.clubId},
  );
  final bucket = (storage.data as Map)['document_storage_bucket']?.toString();
  if (bucket == null || bucket.isEmpty)
    throw Exception('Club storage is unavailable.');
  for (final entry in groups.entries) {
    final package = await client
        .from('club_sweepstakes_report_packages')
        .insert({
          'club_id': club.clubId,
          'source_type': 'manual',
          'source_subject': entry.key,
          'source_received_at': DateTime.now().toIso8601String(),
          'status': 'unmatched',
          'review_notes':
              'Imported from onboarding archive; requires staff review.',
        })
        .select('id')
        .single();
    final id = package['id'].toString();
    final manifest = <Map<String, dynamic>>[];
    for (final item in entry.value.indexed) {
      final index = item.$1;
      final file = item.$2;
      final name = file.relativePath
          .split('/')
          .last
          .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final storageName = '${index.toString().padLeft(4, '0')}_$name';
      final path = 'sweepstakes-reports/$id/attachments/$storageName';
      await client.storage
          .from(bucket)
          .uploadBinary(
            path,
            file.bytes,
            fileOptions: const FileOptions(contentType: 'application/pdf'),
          );
      manifest.add({
        'file_name': name,
        'content_type': 'application/pdf',
        'size': file.bytes.length,
        'storage_path': path,
      });
    }
    await client
        .from('club_sweepstakes_report_packages')
        .update({'attachment_manifest': manifest})
        .eq('id', id);
  }
  if (context.mounted)
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${groups.length} review packages uploaded.')),
    );
}

String _showGroupFromFileName(String value) {
  final name = value.replaceFirst(RegExp(r'\.pdf$', caseSensitive: false), '');
  final ringMaster = RegExp(
    r'^(.*?)(?:_(?:Breed_(?:Totals|Special_Points)|Display_Points|Breed_Results_Detail_Report|Sweepstakes_Report)_Rabbit)_(OPEN|YOUTH)_([A-Z])$',
    caseSensitive: false,
  ).firstMatch(name);
  if (ringMaster != null) {
    return '${ringMaster.group(1)!.replaceAll('_', ' ')} - ${ringMaster.group(2)!.toUpperCase()} ${ringMaster.group(3)!.toUpperCase()}';
  }
  final specialty = RegExp(
    r'^(.*?)(?:_SpecialtyClub(?:Points|Placement))_(.*?)_([A-Z]{2}[A-Z0-9]+)$',
    caseSensitive: false,
  ).firstMatch(name);
  if (specialty != null)
    return '${specialty.group(1)!.replaceAll('_', ' ')} - ${specialty.group(2)!.replaceAll('_', ' ')} ${specialty.group(3)}';
  return name.replaceAll('_', ' ');
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.number,
    required this.icon,
    required this.title,
    required this.description,
    required this.action,
    required this.onPressed,
  });
  final String number, title, description, action;
  final IconData icon;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(child: Text(number)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon),
                const SizedBox(height: 8),
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(description),
                const SizedBox(height: 14),
                FilledButton(onPressed: onPressed, child: Text(action)),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
