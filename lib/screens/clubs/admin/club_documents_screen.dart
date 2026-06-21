// lib/screens/clubs/admin/club_documents_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/clubs/club_summary.dart';

class ClubDocumentsScreen extends StatefulWidget {
  const ClubDocumentsScreen({
    super.key,
    required this.club,
  });

  final ClubSummary club;

  @override
  State<ClubDocumentsScreen> createState() => _ClubDocumentsScreenState();
}

class _ClubDocumentsScreenState extends State<ClubDocumentsScreen> {
  final _supabase = Supabase.instance.client;
  final _searchController = TextEditingController();

  bool _isLoading = true;
  String? _errorMessage;
  String _statusFilter = 'active';
  String _visibilityFilter = 'all';
  List<_ClubDocument> _documents = const [];
  List<_DocumentCategory> _categories = const [];

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
            .from('club_documents')
            .select(
              'id,club_id,category_id,title,description,file_name,storage_bucket,'
              'storage_path,external_url,visibility,status,effective_date,'
              'expires_at,version_label,version_notes,published_at,created_at,'
              'updated_at',
            )
            .eq('club_id', widget.club.clubId)
            .order('created_at', ascending: false),
        _supabase
            .from('club_document_categories')
            .select('id,club_id,name,description,is_active,sort_order')
            .eq('club_id', widget.club.clubId)
            .order('sort_order', ascending: true)
            .order('name', ascending: true),
      ]);

      final categoryRows = responses[1] as List;
      final categories = categoryRows
          .whereType<Map>()
          .map(
            (row) => _DocumentCategory.fromJson(
              Map<String, dynamic>.from(row),
            ),
          )
          .toList();

      final categoryMap = <String, _DocumentCategory>{
        for (final category in categories) category.id: category,
      };

      final documentRows = responses[0] as List;
      final documents = documentRows
          .whereType<Map>()
          .map((row) {
            final json = Map<String, dynamic>.from(row);
            final categoryId = json['category_id']?.toString();
            return _ClubDocument.fromJson(
              json,
              category: categoryId == null ? null : categoryMap[categoryId],
            );
          })
          .toList();

      if (!mounted) return;
      setState(() {
        _documents = documents;
        _categories = categories;
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

  List<_ClubDocument> get _filteredDocuments {
    final query = _searchController.text.trim().toLowerCase();

    return _documents.where((document) {
      final matchesStatus =
          _statusFilter == 'all' || document.status == _statusFilter;
      final matchesVisibility = _visibilityFilter == 'all' ||
          document.visibility == _visibilityFilter;

      if (!matchesStatus || !matchesVisibility) return false;
      if (query.isEmpty) return true;

      final searchable = [
        document.title,
        document.description,
        document.fileName,
        document.category?.name,
        document.versionLabel,
      ].whereType<String>().join(' ').toLowerCase();

      return searchable.contains(query);
    }).toList();
  }

  int _countForStatus(String status) {
    if (status == 'all') return _documents.length;
    return _documents.where((document) => document.status == status).length;
  }

  Future<void> _openEditor({_ClubDocument? existing}) async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DocumentEditorDialog(
        clubId: widget.club.clubId,
        categories: _categories,
        existing: existing,
      ),
    );

    if (changed == true) await _loadData();
  }

  Future<void> _openCategories() async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CategoryManagerDialog(
        clubId: widget.club.clubId,
        categories: _categories,
      ),
    );

    if (changed == true) await _loadData();
  }

  Future<void> _archive(_ClubDocument document) async {
    try {
      await _supabase.rpc(
        'set_club_document_status',
        params: {
          'p_document_id': document.id,
          'p_status': 'archived',
        },
      );
      await _loadData();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to archive document: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Documents'),
        actions: [
          IconButton(
            tooltip: 'Manage Categories',
            onPressed: _isLoading ? null : _openCategories,
            icon: const Icon(Icons.category_outlined),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _loadData,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.upload_file_outlined),
        label: const Text('Add Document'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null && _documents.isEmpty) {
      return _MessageState(
        icon: Icons.error_outline,
        title: 'Unable to load documents',
        message: _errorMessage!,
        actionLabel: 'Try Again',
        onAction: _loadData,
      );
    }

    final filtered = _filteredDocuments;

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
            'Manage bylaws, forms, meeting minutes, newsletters, policies, and other club files.',
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
                      icon: Icons.description_outlined,
                      label: 'Active',
                      value: _countForStatus('active').toString(),
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _SummaryCard(
                      icon: Icons.edit_note_outlined,
                      label: 'Drafts',
                      value: _countForStatus('draft').toString(),
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _SummaryCard(
                      icon: Icons.archive_outlined,
                      label: 'Archived',
                      value: _countForStatus('archived').toString(),
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
              labelText: 'Search documents',
              hintText: 'Title, description, file name, category, or version',
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
                width: 420,
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'all', label: Text('All')),
                    ButtonSegment(value: 'active', label: Text('Active')),
                    ButtonSegment(value: 'draft', label: Text('Drafts')),
                    ButtonSegment(value: 'archived', label: Text('Archived')),
                  ],
                  selected: {_statusFilter},
                  onSelectionChanged: (values) {
                    setState(() => _statusFilter = values.first);
                  },
                ),
              ),
              SizedBox(
                width: 280,
                child: DropdownButtonFormField<String>(
                  initialValue: _visibilityFilter,
                  decoration: const InputDecoration(
                    labelText: 'Visibility',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All')),
                    DropdownMenuItem(value: 'public', child: Text('Public')),
                    DropdownMenuItem(value: 'members', child: Text('Members')),
                    DropdownMenuItem(value: 'staff', child: Text('Staff Only')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _visibilityFilter = value);
                    }
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
            '${filtered.length} ${filtered.length == 1 ? 'document' : 'documents'}',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 12),
          if (_documents.isEmpty)
            _InlineEmptyState(
              title: 'No documents yet',
              message:
                  'Add bylaws, forms, minutes, newsletters, policies, or other club documents.',
              actionLabel: 'Add Document',
              onAction: () => _openEditor(),
            )
          else if (filtered.isEmpty)
            const _InlineEmptyState(
              title: 'No matching documents',
              message: 'Try another search or filter.',
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
                    for (final document in filtered)
                      SizedBox(
                        width: width,
                        child: _DocumentCard(
                          document: document,
                          onEdit: () => _openEditor(existing: document),
                          onArchive: document.status == 'archived'
                              ? null
                              : () => _archive(document),
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

class _DocumentCard extends StatelessWidget {
  const _DocumentCard({
    required this.document,
    required this.onEdit,
    this.onArchive,
  });

  final _ClubDocument document;
  final VoidCallback onEdit;
  final VoidCallback? onArchive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

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
                  CircleAvatar(child: Icon(_iconForFile(document.fileName))),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          document.title,
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        if (document.category != null)
                          Text(document.category!.name),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'edit') onEdit();
                      if (value == 'archive') onArchive?.call();
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Text('Edit'),
                      ),
                      if (onArchive != null)
                        const PopupMenuItem(
                          value: 'archive',
                          child: Text('Archive'),
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
                  Chip(label: Text(_titleCase(document.status))),
                  Chip(label: Text(_titleCase(document.visibility))),
                  if (document.versionLabel != null)
                    Chip(label: Text('Version ${document.versionLabel}')),
                ],
              ),
              if (document.description != null) ...[
                const SizedBox(height: 12),
                Text(
                  document.description!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 12),
              _DetailRow(
                icon: Icons.attach_file,
                text: document.fileName ?? 'External document',
              ),
              if (document.effectiveDate != null)
                _DetailRow(
                  icon: Icons.event_available_outlined,
                  text: 'Effective ${_formatDate(document.effectiveDate!)}',
                ),
              if (document.expiresAt != null)
                _DetailRow(
                  icon: Icons.event_busy_outlined,
                  text: 'Expires ${_formatDate(document.expiresAt!)}',
                ),
              if (document.status == 'archived')
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Material(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                    child: const Padding(
                      padding: EdgeInsets.all(10),
                      child: Row(
                        children: [
                          Icon(Icons.archive_outlined, size: 18),
                          SizedBox(width: 8),
                          Expanded(child: Text('Archived document')),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DocumentEditorDialog extends StatefulWidget {
  const _DocumentEditorDialog({
    required this.clubId,
    required this.categories,
    this.existing,
  });

  final String clubId;
  final List<_DocumentCategory> categories;
  final _ClubDocument? existing;

  @override
  State<_DocumentEditorDialog> createState() => _DocumentEditorDialogState();
}

class _DocumentEditorDialogState extends State<_DocumentEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  final _supabase = Supabase.instance.client;

  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _fileNameController;
  late final TextEditingController _bucketController;
  late final TextEditingController _pathController;
  late final TextEditingController _externalUrlController;
  late final TextEditingController _effectiveDateController;
  late final TextEditingController _expiresAtController;
  late final TextEditingController _versionLabelController;
  late final TextEditingController _versionNotesController;

  String? _categoryId;
  late String _visibility;
  late String _status;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;

    _titleController = TextEditingController(text: existing?.title ?? '');
    _descriptionController =
        TextEditingController(text: existing?.description ?? '');
    _fileNameController = TextEditingController(text: existing?.fileName ?? '');
    _bucketController =
        TextEditingController(text: existing?.storageBucket ?? 'club-documents');
    _pathController =
        TextEditingController(text: existing?.storagePath ?? '');
    _externalUrlController =
        TextEditingController(text: existing?.externalUrl ?? '');
    _effectiveDateController =
        TextEditingController(text: _dateText(existing?.effectiveDate));
    _expiresAtController =
        TextEditingController(text: _dateText(existing?.expiresAt));
    _versionLabelController =
        TextEditingController(text: existing?.versionLabel ?? '');
    _versionNotesController =
        TextEditingController(text: existing?.versionNotes ?? '');

    _categoryId = existing?.categoryId;
    _visibility = existing?.visibility ?? 'members';
    _status = existing?.status ?? 'draft';
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _fileNameController.dispose();
    _bucketController.dispose();
    _pathController.dispose();
    _externalUrlController.dispose();
    _effectiveDateController.dispose();
    _expiresAtController.dispose();
    _versionLabelController.dispose();
    _versionNotesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSaving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final effectiveDate = _parseDate(_effectiveDateController.text);
    final expiresAt = _parseDate(_expiresAtController.text);

    if (effectiveDate != null &&
        expiresAt != null &&
        expiresAt.isBefore(effectiveDate)) {
      setState(() {
        _errorMessage = 'The expiration date cannot be before the effective date.';
      });
      return;
    }

    final hasStoragePath = _pathController.text.trim().isNotEmpty;
    final hasExternalUrl = _externalUrlController.text.trim().isNotEmpty;

    if (!hasStoragePath && !hasExternalUrl) {
      setState(() {
        _errorMessage =
            'Enter either a Supabase Storage path or an external URL.';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      await _supabase.rpc(
        'save_club_document',
        params: {
          'p_document_id': widget.existing?.id,
          'p_club_id': widget.clubId,
          'p_category_id': _categoryId,
          'p_title': _titleController.text.trim(),
          'p_description': _nullIfBlank(_descriptionController.text),
          'p_file_name': _nullIfBlank(_fileNameController.text),
          'p_storage_bucket': hasStoragePath
              ? (_nullIfBlank(_bucketController.text) ?? 'club-documents')
              : null,
          'p_storage_path': hasStoragePath
              ? _nullIfBlank(_pathController.text)
              : null,
          'p_external_url': hasExternalUrl
              ? _nullIfBlank(_externalUrlController.text)
              : null,
          'p_visibility': _visibility,
          'p_status': _status,
          'p_effective_date': _dateValue(_effectiveDateController.text),
          'p_expires_at': _dateValue(_expiresAtController.text),
          'p_version_label': _nullIfBlank(_versionLabelController.text),
          'p_version_notes': _nullIfBlank(_versionNotesController.text),
        },
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorMessage = 'Unable to save document: $error';
      });
    }
  }

  Future<void> _pickDate(TextEditingController controller) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _parseDate(controller.text) ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime(2200),
    );

    if (selected != null) controller.text = _dateText(selected);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Add Document' : 'Edit Document'),
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
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: 'Document title',
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
                      initialValue: _categoryId,
                      decoration: const InputDecoration(
                        labelText: 'Category',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem<String>(
                          value: null,
                          child: Text('Uncategorized'),
                        ),
                        for (final category in widget.categories
                            .where((category) => category.isActive))
                          DropdownMenuItem(
                            value: category.id,
                            child: Text(category.name),
                          ),
                      ],
                      onChanged: _isSaving
                          ? null
                          : (value) => setState(() => _categoryId = value),
                    ),
                    TextFormField(
                      controller: _fileNameController,
                      decoration: const InputDecoration(
                        labelText: 'File name',
                        border: OutlineInputBorder(),
                      ),
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
                      initialValue: _status,
                      decoration: const InputDecoration(
                        labelText: 'Status',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'draft', child: Text('Draft')),
                        DropdownMenuItem(value: 'active', child: Text('Active')),
                        DropdownMenuItem(
                          value: 'archived',
                          child: Text('Archived'),
                        ),
                      ],
                      onChanged: _isSaving
                          ? null
                          : (value) {
                              if (value != null) setState(() => _status = value);
                            },
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _SectionTitle('File Location'),
                TextFormField(
                  controller: _bucketController,
                  decoration: const InputDecoration(
                    labelText: 'Storage bucket',
                    hintText: 'club-documents',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _pathController,
                  decoration: const InputDecoration(
                    labelText: 'Supabase Storage path',
                    hintText: 'club-id/category/file.pdf',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                const Center(child: Text('OR')),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _externalUrlController,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'External URL',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 18),
                _SectionTitle('Version & Dates'),
                _ResponsiveFields(
                  children: [
                    TextFormField(
                      controller: _versionLabelController,
                      decoration: const InputDecoration(
                        labelText: 'Version label',
                        hintText: '2026.1 or Revised June 2026',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    _DateField(
                      controller: _effectiveDateController,
                      label: 'Effective date',
                      onPick: () => _pickDate(_effectiveDateController),
                    ),
                    _DateField(
                      controller: _expiresAtController,
                      label: 'Expiration date',
                      onPick: () => _pickDate(_expiresAtController),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _versionNotesController,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'Version notes',
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

  DateTime? _parseDate(String value) {
    final text = value.trim();
    return text.isEmpty ? null : DateTime.tryParse(text);
  }

  String? _dateValue(String value) {
    final date = _parseDate(value);
    return date == null ? null : _dateText(date);
  }
}

class _CategoryManagerDialog extends StatelessWidget {
  const _CategoryManagerDialog({
    required this.clubId,
    required this.categories,
  });

  final String clubId;
  final List<_DocumentCategory> categories;

  Future<void> _openEditor(
    BuildContext context, {
    _DocumentCategory? existing,
  }) async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CategoryEditorDialog(
        clubId: clubId,
        existing: existing,
      ),
    );

    if (changed == true && context.mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Document Categories'),
      content: SizedBox(
        width: 640,
        child: categories.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No document categories have been created yet.',
                  textAlign: TextAlign.center,
                ),
              )
            : ListView.separated(
                shrinkWrap: true,
                itemCount: categories.length,
                separatorBuilder: (context, index) =>
                    const Divider(height: 1),
                itemBuilder: (context, index) {
                  final category = categories[index];
                  return ListTile(
                    leading: Icon(
                      category.isActive
                          ? Icons.folder_outlined
                          : Icons.folder_off_outlined,
                    ),
                    title: Text(category.name),
                    subtitle: category.description == null
                        ? null
                        : Text(category.description!),
                    trailing: Text('#${category.sortOrder}'),
                    onTap: () => _openEditor(context, existing: category),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Close'),
        ),
        FilledButton.icon(
          onPressed: () => _openEditor(context),
          icon: const Icon(Icons.add),
          label: const Text('New Category'),
        ),
      ],
    );
  }
}

class _CategoryEditorDialog extends StatefulWidget {
  const _CategoryEditorDialog({
    required this.clubId,
    this.existing,
  });

  final String clubId;
  final _DocumentCategory? existing;

  @override
  State<_CategoryEditorDialog> createState() => _CategoryEditorDialogState();
}

class _CategoryEditorDialogState extends State<_CategoryEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  final _supabase = Supabase.instance.client;

  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _sortOrderController;
  bool _isActive = true;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existing?.name ?? '');
    _descriptionController =
        TextEditingController(text: widget.existing?.description ?? '');
    _sortOrderController = TextEditingController(
      text: (widget.existing?.sortOrder ?? 0).toString(),
    );
    _isActive = widget.existing?.isActive ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _sortOrderController.dispose();
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
      'name': _nullIfBlank(_nameController.text) ?? '',
      'description': _nullIfBlank(_descriptionController.text),
      'sort_order': int.tryParse(_sortOrderController.text.trim()) ?? 0,
      'is_active': _isActive,
    };

    try {
      if (widget.existing == null) {
        await _supabase.from('club_document_categories').insert(payload);
      } else {
        await _supabase
            .from('club_document_categories')
            .update(payload)
            .eq('id', widget.existing!.id)
            .eq('club_id', widget.clubId);
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorMessage = 'Unable to save category: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'New Category' : 'Edit Category'),
      content: SizedBox(
        width: 560,
        child: Form(
          key: _formKey,
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
                  labelText: 'Category name',
                  border: OutlineInputBorder(),
                ),
                validator: (value) =>
                    value == null || value.trim().isEmpty ? 'Required.' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _descriptionController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _sortOrderController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Sort order',
                  border: OutlineInputBorder(),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Active category'),
                value: _isActive,
                onChanged: _isSaving
                    ? null
                    : (value) => setState(() => _isActive = value),
              ),
            ],
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

  String? _nullIfBlank(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

class _ClubDocument {
  const _ClubDocument({
    required this.id,
    required this.title,
    required this.visibility,
    required this.status,
    required this.createdAt,
    this.categoryId,
    this.category,
    this.description,
    this.fileName,
    this.storageBucket,
    this.storagePath,
    this.externalUrl,
    this.effectiveDate,
    this.expiresAt,
    this.versionLabel,
    this.versionNotes,
    this.publishedAt,
  });

  final String id;
  final String? categoryId;
  final _DocumentCategory? category;
  final String title;
  final String? description;
  final String? fileName;
  final String? storageBucket;
  final String? storagePath;
  final String? externalUrl;
  final String visibility;
  final String status;
  final DateTime? effectiveDate;
  final DateTime? expiresAt;
  final String? versionLabel;
  final String? versionNotes;
  final DateTime? publishedAt;
  final DateTime createdAt;

  factory _ClubDocument.fromJson(
    Map<String, dynamic> json, {
    _DocumentCategory? category,
  }) {
    return _ClubDocument(
      id: json['id'].toString(),
      categoryId: _nullableString(json['category_id']),
      category: category,
      title: _nullableString(json['title']) ?? 'Untitled Document',
      description: _nullableString(json['description']),
      fileName: _nullableString(json['file_name']),
      storageBucket: _nullableString(json['storage_bucket']),
      storagePath: _nullableString(json['storage_path']),
      externalUrl: _nullableString(json['external_url']),
      visibility: _nullableString(json['visibility']) ?? 'members',
      status: _nullableString(json['status']) ?? 'draft',
      effectiveDate: _nullableDate(json['effective_date']),
      expiresAt: _nullableDate(json['expires_at']),
      versionLabel: _nullableString(json['version_label']),
      versionNotes: _nullableString(json['version_notes']),
      publishedAt: _nullableDate(json['published_at']),
      createdAt: _nullableDate(json['created_at']) ?? DateTime.now(),
    );
  }
}

class _DocumentCategory {
  const _DocumentCategory({
    required this.id,
    required this.name,
    required this.isActive,
    required this.sortOrder,
    this.description,
  });

  final String id;
  final String name;
  final String? description;
  final bool isActive;
  final int sortOrder;

  factory _DocumentCategory.fromJson(Map<String, dynamic> json) {
    return _DocumentCategory(
      id: json['id'].toString(),
      name: _nullableString(json['name']) ?? 'Unnamed Category',
      description: _nullableString(json['description']),
      isActive: json['is_active'] == true,
      sortOrder: _nullableInt(json['sort_order']) ?? 0,
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
            for (final child in children)
              SizedBox(width: width, child: child),
          ],
        );
      },
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
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
              tooltip: 'Choose date',
              onPressed: onPick,
              icon: const Icon(Icons.calendar_today_outlined),
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
            const Icon(Icons.folder_open_outlined, size: 52),
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
                icon: const Icon(Icons.upload_file_outlined),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

IconData _iconForFile(String? fileName) {
  final value = fileName?.toLowerCase() ?? '';
  if (value.endsWith('.pdf')) return Icons.picture_as_pdf_outlined;
  if (value.endsWith('.doc') || value.endsWith('.docx')) {
    return Icons.article_outlined;
  }
  if (value.endsWith('.xls') || value.endsWith('.xlsx')) {
    return Icons.table_chart_outlined;
  }
  if (value.endsWith('.jpg') ||
      value.endsWith('.jpeg') ||
      value.endsWith('.png')) {
    return Icons.image_outlined;
  }
  return Icons.insert_drive_file_outlined;
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

String _dateText(DateTime? value) {
  if (value == null) return '';
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '${value.year}-$month-$day';
}

String _formatDate(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '$month/$day/${value.year}';
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
