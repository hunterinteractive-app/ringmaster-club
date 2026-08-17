import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../models/clubs/club_summary.dart';

class ClubMemberDocumentsScreen extends StatefulWidget {
  const ClubMemberDocumentsScreen({super.key, required this.club});

  final ClubSummary club;

  @override
  State<ClubMemberDocumentsScreen> createState() =>
      _ClubMemberDocumentsScreenState();
}

class _ClubMemberDocumentsScreenState extends State<ClubMemberDocumentsScreen> {
  final _supabase = Supabase.instance.client;
  final _searchController = TextEditingController();
  bool _isLoading = true;
  String? _errorMessage;
  String _categoryFilter = 'all';
  List<_MemberDocument> _documents = const [];
  Map<String, String> _categoryNames = const {};

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_refreshView);
    _loadDocuments();
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_refreshView)
      ..dispose();
    super.dispose();
  }

  void _refreshView() {
    if (mounted) setState(() {});
  }

  Future<void> _loadDocuments() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final responses = await Future.wait([
        _supabase
            .from('club_documents')
            .select(
              'id,category_id,title,description,file_name,storage_bucket,'
              'storage_path,external_url,visibility,status,effective_date,'
              'expires_at,version_label,published_at,file_size_bytes,content_type',
            )
            .eq('club_id', widget.club.clubId)
            .eq('status', 'active')
            .order('published_at', ascending: false),
        _supabase
            .from('club_document_categories')
            .select('id,name,is_active,sort_order')
            .eq('club_id', widget.club.clubId)
            .eq('is_active', true)
            .order('sort_order', ascending: true)
            .order('name', ascending: true),
      ]);
      final categoryNames = <String, String>{};
      for (final row in (responses[1] as List).whereType<Map>()) {
        final id = _textOrNull(row['id']);
        if (id != null) {
          categoryNames[id] = _textOrNull(row['name']) ?? 'Uncategorized';
        }
      }
      final documents = (responses[0] as List)
          .whereType<Map>()
          .map(
            (row) => _MemberDocument.fromJson(Map<String, dynamic>.from(row)),
          )
          .where(
            (document) => document.isVisibleToMembers && !document.isExpired,
          )
          .toList();
      if (!mounted) return;
      setState(() {
        _documents = documents;
        _categoryNames = categoryNames;
        if (_categoryFilter != 'all' &&
            !_categoryNames.containsKey(_categoryFilter)) {
          _categoryFilter = 'all';
        }
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Unable to load club documents: $error';
      });
    }
  }

  List<_MemberDocument> get _visibleDocuments {
    final query = _searchController.text.trim().toLowerCase();
    return _documents.where((document) {
      if (_categoryFilter != 'all' && document.categoryId != _categoryFilter) {
        return false;
      }
      if (query.isEmpty) return true;
      return [
        document.title,
        document.description,
        document.fileName,
        _categoryNames[document.categoryId],
        document.versionLabel,
      ].whereType<String>().join(' ').toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _openDocument(_MemberDocument document) async {
    try {
      var url = document.externalUrl;
      if (url == null &&
          document.storageBucket != null &&
          document.storagePath != null) {
        url = await _supabase.storage
            .from(document.storageBucket!)
            .createSignedUrl(document.storagePath!, 600);
      }
      final uri = url == null ? null : Uri.tryParse(url);
      if (uri == null ||
          !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw StateError('The document could not be opened.');
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to open document: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Club Documents'),
        actions: [
          IconButton(
            tooltip: 'Refresh documents',
            onPressed: _isLoading ? null : _loadDocuments,
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
      return _DocumentsMessageState(
        icon: Icons.error_outline,
        title: 'We could not load documents',
        message: _errorMessage!,
        actionLabel: 'Try again',
        onAction: _loadDocuments,
      );
    }
    final documents = _visibleDocuments;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Club documents',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          'Published forms, rules, minutes, and shared files from ${widget.club.displayName}.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _searchController,
          decoration: const InputDecoration(
            labelText: 'Search documents',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: ValueKey('document-category-$_categoryFilter'),
          initialValue: _categoryFilter,
          decoration: const InputDecoration(labelText: 'Category'),
          items: [
            const DropdownMenuItem(value: 'all', child: Text('All categories')),
            ..._categoryNames.entries.map(
              (entry) =>
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
            ),
          ],
          onChanged: (value) =>
              setState(() => _categoryFilter = value ?? 'all'),
        ),
        const SizedBox(height: 18),
        if (documents.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                _documents.isEmpty
                    ? 'No documents have been published for members yet.'
                    : 'No documents match your search.',
              ),
            ),
          )
        else
          ...documents.map(
            (document) => _DocumentCard(
              document: document,
              categoryName: _categoryNames[document.categoryId],
              onTap: () => _openDocument(document),
            ),
          ),
      ],
    );
  }
}

class _MemberDocument {
  const _MemberDocument({
    required this.categoryId,
    required this.title,
    required this.description,
    required this.fileName,
    required this.storageBucket,
    required this.storagePath,
    required this.externalUrl,
    required this.visibility,
    required this.expiresAt,
    required this.versionLabel,
    required this.fileSizeBytes,
  });

  final String? categoryId;
  final String title;
  final String? description;
  final String? fileName;
  final String? storageBucket;
  final String? storagePath;
  final String? externalUrl;
  final String visibility;
  final DateTime? expiresAt;
  final String? versionLabel;
  final int? fileSizeBytes;

  bool get isVisibleToMembers =>
      visibility.toLowerCase() == 'members' ||
      visibility.toLowerCase() == 'public';
  bool get isExpired => expiresAt != null && expiresAt!.isBefore(_today());

  factory _MemberDocument.fromJson(Map<String, dynamic> json) {
    return _MemberDocument(
      categoryId: _textOrNull(json['category_id']),
      title: _textOrNull(json['title']) ?? 'Untitled document',
      description: _textOrNull(json['description']),
      fileName: _textOrNull(json['file_name']),
      storageBucket: _textOrNull(json['storage_bucket']),
      storagePath: _textOrNull(json['storage_path']),
      externalUrl: _textOrNull(json['external_url']),
      visibility: _textOrNull(json['visibility']) ?? 'members',
      expiresAt: _dateOrNull(json['expires_at']),
      versionLabel: _textOrNull(json['version_label']),
      fileSizeBytes: _intOrNull(json['file_size_bytes']),
    );
  }
}

class _DocumentCard extends StatelessWidget {
  const _DocumentCard({
    required this.document,
    required this.categoryName,
    required this.onTap,
  });
  final _MemberDocument document;
  final String? categoryName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final details = [
      categoryName,
      document.versionLabel,
      _formatFileSize(document.fileSizeBytes),
    ].whereType<String>().where((value) => value.isNotEmpty).join(' • ');
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 10,
        ),
        leading: const Icon(Icons.description_outlined, size: 30),
        title: Text(
          document.title,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (document.description != null) Text(document.description!),
              if (details.isNotEmpty) Text(details),
            ],
          ),
        ),
        trailing: const Icon(Icons.open_in_new),
        onTap: onTap,
      ),
    );
  }
}

class _DocumentsMessageState extends StatelessWidget {
  const _DocumentsMessageState({
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

int? _intOrNull(dynamic value) => value is int ? value : int.tryParse('$value');

DateTime _today() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

String? _formatFileSize(int? bytes) {
  if (bytes == null || bytes <= 0) return null;
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
