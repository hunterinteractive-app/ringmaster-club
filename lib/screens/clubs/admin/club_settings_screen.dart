

// lib/screens/clubs/admin/club_settings_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/clubs/club_summary.dart';

class ClubSettingsScreen extends StatefulWidget {
  const ClubSettingsScreen({
    super.key,
    required this.club,
  });

  final ClubSummary club;

  @override
  State<ClubSettingsScreen> createState() => _ClubSettingsScreenState();
}

class _ClubSettingsScreenState extends State<ClubSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _supabase = Supabase.instance.client;

  final _nameController = TextEditingController();
  final _shortNameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _websiteController = TextEditingController();
  final _logoUrlController = TextEditingController();
  final _contactNameController = TextEditingController();
  final _contactEmailController = TextEditingController();
  final _contactPhoneController = TextEditingController();
  final _addressLine1Controller = TextEditingController();
  final _addressLine2Controller = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _postalCodeController = TextEditingController();
  final _countryController = TextEditingController(text: 'US');

  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;

  String _clubType = 'local';
  String _speciesScope = 'both';
  String _status = 'active';

  bool _allowPublicProfile = true;
  bool _allowPublicEvents = true;
  bool _allowPublicDocuments = false;
  bool _allowPublicSweepstakes = false;

  @override
  void initState() {
    super.initState();
    _loadClub();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _shortNameController.dispose();
    _descriptionController.dispose();
    _websiteController.dispose();
    _logoUrlController.dispose();
    _contactNameController.dispose();
    _contactEmailController.dispose();
    _contactPhoneController.dispose();
    _addressLine1Controller.dispose();
    _addressLine2Controller.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _postalCodeController.dispose();
    _countryController.dispose();
    super.dispose();
  }

  Future<void> _loadClub() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final row = await _supabase
          .from('clubs')
          .select(
            'name,short_name,club_type,species_scope,description,logo_url,'
            'website_url,mailing_address_line1,mailing_address_line2,'
            'mailing_city,mailing_state,mailing_postal_code,mailing_country,'
            'contact_name,contact_email,contact_phone,status,'
            'allow_public_profile,allow_public_events,'
            'allow_public_documents,allow_public_sweepstakes',
          )
          .eq('id', widget.club.clubId)
          .single();

      if (!mounted) return;

      _nameController.text = _text(row['name']);
      _shortNameController.text = _text(row['short_name']);
      _descriptionController.text = _text(row['description']);
      _websiteController.text = _text(row['website_url']);
      _logoUrlController.text = _text(row['logo_url']);
      _contactNameController.text = _text(row['contact_name']);
      _contactEmailController.text = _text(row['contact_email']);
      _contactPhoneController.text = _text(row['contact_phone']);
      _addressLine1Controller.text = _text(row['mailing_address_line1']);
      _addressLine2Controller.text = _text(row['mailing_address_line2']);
      _cityController.text = _text(row['mailing_city']);
      _stateController.text = _text(row['mailing_state']);
      _postalCodeController.text = _text(row['mailing_postal_code']);
      _countryController.text = _text(row['mailing_country']).isEmpty
          ? 'US'
          : _text(row['mailing_country']);

      setState(() {
        _clubType = _text(row['club_type']).isEmpty
            ? 'local'
            : _text(row['club_type']);
        _speciesScope = _text(row['species_scope']).isEmpty
            ? 'both'
            : _text(row['species_scope']);
        _status = _text(row['status']).isEmpty
            ? 'active'
            : _text(row['status']);
        _allowPublicProfile = row['allow_public_profile'] == true;
        _allowPublicEvents = row['allow_public_events'] == true;
        _allowPublicDocuments = row['allow_public_documents'] == true;
        _allowPublicSweepstakes = row['allow_public_sweepstakes'] == true;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Unable to load club settings: $error';
      });
    }
  }

  Future<void> _save() async {
    if (_isSaving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      await _supabase
          .from('clubs')
          .update({
            'name': _nameController.text.trim(),
            'short_name': _nullIfBlank(_shortNameController.text),
            'club_type': _clubType,
            'species_scope': _speciesScope,
            'description': _nullIfBlank(_descriptionController.text),
            'logo_url': _nullIfBlank(_logoUrlController.text),
            'website_url': _nullIfBlank(_websiteController.text),
            'mailing_address_line1':
                _nullIfBlank(_addressLine1Controller.text),
            'mailing_address_line2':
                _nullIfBlank(_addressLine2Controller.text),
            'mailing_city': _nullIfBlank(_cityController.text),
            'mailing_state': _nullIfBlank(_stateController.text),
            'mailing_postal_code': _nullIfBlank(_postalCodeController.text),
            'mailing_country': _countryController.text.trim().isEmpty
                ? 'US'
                : _countryController.text.trim().toUpperCase(),
            'contact_name': _nullIfBlank(_contactNameController.text),
            'contact_email': _nullIfBlank(_contactEmailController.text),
            'contact_phone': _nullIfBlank(_contactPhoneController.text),
            'status': _status,
            'allow_public_profile': _allowPublicProfile,
            'allow_public_events': _allowPublicEvents,
            'allow_public_documents': _allowPublicDocuments,
            'allow_public_sweepstakes': _allowPublicSweepstakes,
          })
          .eq('id', widget.club.clubId);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Club settings saved.')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Unable to save club settings: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Club Settings'),
        actions: [
          IconButton(
            tooltip: 'Reload',
            onPressed: _isLoading || _isSaving ? null : _loadClub,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _buildBody(),
      bottomNavigationBar: _isLoading
          ? null
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: FilledButton.icon(
                onPressed: _isSaving ? null : _save,
                icon: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(_isSaving ? 'Saving...' : 'Save Changes'),
              ),
            ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null && _nameController.text.isEmpty) {
      return _ErrorState(
        message: _errorMessage!,
        onRetry: _loadClub,
      );
    }

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
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
          _SectionCard(
            title: 'Club Information',
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Club name',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => _required(value, 'Club name'),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _shortNameController,
                decoration: const InputDecoration(
                  labelText: 'Short name',
                  hintText: 'Example: ISRBA',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _clubType,
                decoration: const InputDecoration(
                  labelText: 'Club type',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'local', child: Text('Local')),
                  DropdownMenuItem(value: 'regional', child: Text('Regional')),
                  DropdownMenuItem(value: 'state', child: Text('State')),
                  DropdownMenuItem(
                    value: 'national_specialty',
                    child: Text('National Specialty'),
                  ),
                  DropdownMenuItem(value: 'national', child: Text('National')),
                  DropdownMenuItem(value: 'other', child: Text('Other')),
                ],
                onChanged: _isSaving
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() => _clubType = value);
                        }
                      },
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _speciesScope,
                decoration: const InputDecoration(
                  labelText: 'Species',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'rabbit', child: Text('Rabbit')),
                  DropdownMenuItem(value: 'cavy', child: Text('Cavy')),
                  DropdownMenuItem(value: 'both', child: Text('Rabbit & Cavy')),
                  DropdownMenuItem(value: 'other', child: Text('Other')),
                ],
                onChanged: _isSaving
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() => _speciesScope = value);
                        }
                      },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _descriptionController,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Branding & Website',
            children: [
              TextFormField(
                controller: _logoUrlController,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Logo URL',
                  border: OutlineInputBorder(),
                ),
                validator: _optionalUrl,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _websiteController,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Website URL',
                  border: OutlineInputBorder(),
                ),
                validator: _optionalUrl,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Contact Information',
            children: [
              TextFormField(
                controller: _contactNameController,
                decoration: const InputDecoration(
                  labelText: 'Contact name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _contactEmailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Contact email',
                  border: OutlineInputBorder(),
                ),
                validator: _optionalEmail,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _contactPhoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Contact phone',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Mailing Address',
            children: [
              TextFormField(
                controller: _addressLine1Controller,
                decoration: const InputDecoration(
                  labelText: 'Address line 1',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _addressLine2Controller,
                decoration: const InputDecoration(
                  labelText: 'Address line 2',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 700;
                  final fieldWidth = wide
                      ? (constraints.maxWidth - 12) / 2
                      : constraints.maxWidth;

                  return Wrap(
                    spacing: 12,
                    runSpacing: 14,
                    children: [
                      SizedBox(
                        width: fieldWidth,
                        child: TextFormField(
                          controller: _cityController,
                          decoration: const InputDecoration(
                            labelText: 'City',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: fieldWidth,
                        child: TextFormField(
                          controller: _stateController,
                          decoration: const InputDecoration(
                            labelText: 'State / Province',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: fieldWidth,
                        child: TextFormField(
                          controller: _postalCodeController,
                          decoration: const InputDecoration(
                            labelText: 'Postal code',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: fieldWidth,
                        child: TextFormField(
                          controller: _countryController,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(
                            labelText: 'Country code',
                            hintText: 'US',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Public Visibility',
            children: [
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Public club profile'),
                subtitle: const Text(
                  'Allow visitors to view basic club information.',
                ),
                value: _allowPublicProfile,
                onChanged: _isSaving
                    ? null
                    : (value) =>
                        setState(() => _allowPublicProfile = value),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Public events'),
                subtitle: const Text(
                  'Allow visitors to view shared meetings and events.',
                ),
                value: _allowPublicEvents,
                onChanged: _isSaving
                    ? null
                    : (value) => setState(() => _allowPublicEvents = value),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Public documents'),
                subtitle: const Text(
                  'Allow visitors to view documents marked for public access.',
                ),
                value: _allowPublicDocuments,
                onChanged: _isSaving
                    ? null
                    : (value) =>
                        setState(() => _allowPublicDocuments = value),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Public sweepstakes'),
                subtitle: const Text(
                  'Allow visitors to view published sweepstakes standings.',
                ),
                value: _allowPublicSweepstakes,
                onChanged: _isSaving
                    ? null
                    : (value) =>
                        setState(() => _allowPublicSweepstakes = value),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Club Status',
            children: [
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
                    value: 'suspended',
                    child: Text('Suspended'),
                  ),
                  DropdownMenuItem(value: 'archived', child: Text('Archived')),
                ],
                onChanged: _isSaving
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() => _status = value);
                        }
                      },
              ),
            ],
          ),
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  String _text(dynamic value) => value?.toString().trim() ?? '';

  String? _nullIfBlank(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String? _required(String? value, String label) {
    if (value == null || value.trim().isEmpty) {
      return '$label is required.';
    }
    return null;
  }

  String? _optionalEmail(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;

    final emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!emailPattern.hasMatch(text)) {
      return 'Enter a valid email address.';
    }

    return null;
  }

  String? _optionalUrl(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;

    final uri = Uri.tryParse(text);
    if (uri == null ||
        !(uri.scheme == 'http' || uri.scheme == 'https') ||
        uri.host.isEmpty) {
      return 'Enter a valid http or https URL.';
    }

    return null;
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64),
              const SizedBox(height: 16),
              Text(
                'Unable to load settings',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}