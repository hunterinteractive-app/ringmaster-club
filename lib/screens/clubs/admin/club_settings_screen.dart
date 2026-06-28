// lib/screens/clubs/admin/club_settings_screen.dart

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

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
  final _treasurerNameController = TextEditingController();
  final _treasurerEmailController = TextEditingController();
  final _treasurerPhoneController = TextEditingController();
  final _treasurerAddressLine1Controller = TextEditingController();
  final _treasurerAddressLine2Controller = TextEditingController();
  final _treasurerCityController = TextEditingController();
  final _treasurerStateController = TextEditingController();
  final _treasurerZipController = TextEditingController();
  final _addressLine1Controller = TextEditingController();
  final _addressLine2Controller = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _postalCodeController = TextEditingController();
  final _countryController = TextEditingController(text: 'US');

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isUploadingLogo = false;
  String? _errorMessage;
  String? _logoStorageBucket;
  _ClubSettingsFeatureAccess _features = const _ClubSettingsFeatureAccess.base();

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
    _treasurerNameController.dispose();
    _treasurerEmailController.dispose();
    _treasurerPhoneController.dispose();
    _treasurerAddressLine1Controller.dispose();
    _treasurerAddressLine2Controller.dispose();
    _treasurerCityController.dispose();
    _treasurerStateController.dispose();
    _treasurerZipController.dispose();
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
            'contact_name,contact_email,contact_phone,treasurer_name,'
            'treasurer_email,treasurer_phone,treasurer_address_line1,'
            'treasurer_address_line2,treasurer_city,treasurer_state,'
            'treasurer_zip,status,'
            'allow_public_profile,allow_public_events,'
            'allow_public_documents,allow_public_sweepstakes,'
            'events_meetings_addon_enabled,sweepstakes_addon_enabled,'
            'logo_storage_bucket,document_storage_bucket',
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
      _treasurerNameController.text = _text(row['treasurer_name']);
      _treasurerEmailController.text = _text(row['treasurer_email']);
      _treasurerPhoneController.text = _text(row['treasurer_phone']);
      _treasurerAddressLine1Controller.text =
          _text(row['treasurer_address_line1']);
      _treasurerAddressLine2Controller.text =
          _text(row['treasurer_address_line2']);
      _treasurerCityController.text = _text(row['treasurer_city']);
      _treasurerStateController.text = _text(row['treasurer_state']);
      _treasurerZipController.text = _text(row['treasurer_zip']);
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
        _features = _ClubSettingsFeatureAccess.fromJson(
          Map<String, dynamic>.from(row),
        );
        if (!_features.eventsMeetings) {
          _allowPublicEvents = false;
        }
        if (!_features.sweepstakes) {
          _allowPublicSweepstakes = false;
        }
        _logoStorageBucket = _text(row['logo_storage_bucket']);
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

  Future<void> _uploadLogo() async {
    if (_isUploadingLogo || _isSaving) return;

    setState(() {
      _isUploadingLogo = true;
      _errorMessage = null;
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) {
        if (mounted) setState(() => _isUploadingLogo = false);
        return;
      }

      final file = result.files.single;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        throw Exception('No logo file data was selected.');
      }

      final maxLogoBytes = 1024 * 1024;
      if (bytes.length > maxLogoBytes) {
        throw Exception('Logo files must be 1 MB or smaller.');
      }

      final extension = _fileExtension(file.name);
      final bucketName = await _provisionLogoStorageBucket();
      final storagePath = 'logo-${DateTime.now().millisecondsSinceEpoch}$extension';
      final contentType = _imageContentType(extension);

      await _supabase.storage.from(bucketName).uploadBinary(
            storagePath,
            Uint8List.fromList(bytes),
            fileOptions: FileOptions(
              contentType: contentType,
              upsert: true,
            ),
          );

      final publicUrl = _supabase.storage.from(bucketName).getPublicUrl(
            storagePath,
          );

      if (!mounted) return;
      setState(() {
        _logoUrlController.text = publicUrl;
        _isUploadingLogo = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Logo uploaded. Save changes to keep it on the club profile.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isUploadingLogo = false;
        _errorMessage = 'Unable to upload logo: $error';
      });
    }
  }

  Future<String> _provisionLogoStorageBucket() async {
    final existingBucket = _logoStorageBucket?.trim();
    if (existingBucket != null && existingBucket.isNotEmpty) {
      return existingBucket;
    }

    final response = await _supabase.functions.invoke(
      'provision-club-storage',
      body: {'club_id': widget.club.clubId},
    );

    final data = response.data;
    if (data is! Map) {
      throw Exception('Storage provisioning did not return a valid response.');
    }

    final json = Map<String, dynamic>.from(data);
    final logoBucket = json['logo_storage_bucket']?.toString().trim();

    if (logoBucket == null || logoBucket.isEmpty) {
      final error = json['error']?.toString();
      throw Exception(
        error ?? 'Storage provisioning did not return a logo bucket.',
      );
    }

    _logoStorageBucket = logoBucket;

    return logoBucket;
  }



  String _fileExtension(String name) {
    final dotIndex = name.lastIndexOf('.');
    if (dotIndex < 0 || dotIndex == name.length - 1) return '.png';
    final extension = name.substring(dotIndex).toLowerCase();
    if (extension == '.jpg' ||
        extension == '.jpeg' ||
        extension == '.png' ||
        extension == '.webp') {
      return extension;
    }
    return '.png';
  }

  String _imageContentType(String extension) {
    switch (extension) {
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.webp':
        return 'image/webp';
      case '.png':
      default:
        return 'image/png';
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
            'treasurer_name': _nullIfBlank(_treasurerNameController.text),
            'treasurer_email': _nullIfBlank(_treasurerEmailController.text),
            'treasurer_phone': _nullIfBlank(_treasurerPhoneController.text),
            'treasurer_address_line1':
                _nullIfBlank(_treasurerAddressLine1Controller.text),
            'treasurer_address_line2':
                _nullIfBlank(_treasurerAddressLine2Controller.text),
            'treasurer_city': _nullIfBlank(_treasurerCityController.text),
            'treasurer_state': _nullIfBlank(_treasurerStateController.text),
            'treasurer_zip': _nullIfBlank(_treasurerZipController.text),
            'status': _status,
            'allow_public_profile': _allowPublicProfile,
            'allow_public_events':
                _features.eventsMeetings && _allowPublicEvents,
            'allow_public_documents': _allowPublicDocuments,
            'allow_public_sweepstakes':
                _features.sweepstakes && _allowPublicSweepstakes,
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
                onPressed: _isSaving || _isUploadingLogo ? null : _save,
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
          _BaseSettingsAccessCard(features: _features),
          const SizedBox(height: 16),
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
              _LogoUploadField(
                logoUrlController: _logoUrlController,
                isUploading: _isUploadingLogo,
                onUpload: _uploadLogo,
                onClear: _isUploadingLogo
                    ? null
                    : () => setState(() => _logoUrlController.clear()),
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
            title: 'Treasurer / Check Payments',
            children: [
              Text(
                'These details are used when a club allows mailed checks for sanction requests. The requester will see where to mail payment after submitting.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _treasurerNameController,
                decoration: const InputDecoration(
                  labelText: 'Treasurer name / Payable to',
                  helperText: 'Example: ISRBA Treasurer or Jane Smith',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _treasurerEmailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Treasurer email',
                  border: OutlineInputBorder(),
                ),
                validator: _optionalEmail,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _treasurerPhoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Treasurer phone',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _treasurerAddressLine1Controller,
                decoration: const InputDecoration(
                  labelText: 'Payment mailing address line 1',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _treasurerAddressLine2Controller,
                decoration: const InputDecoration(
                  labelText: 'Payment mailing address line 2',
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
                          controller: _treasurerCityController,
                          decoration: const InputDecoration(
                            labelText: 'Payment city',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: fieldWidth,
                        child: TextFormField(
                          controller: _treasurerStateController,
                          decoration: const InputDecoration(
                            labelText: 'Payment state / province',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: fieldWidth,
                        child: TextFormField(
                          controller: _treasurerZipController,
                          decoration: const InputDecoration(
                            labelText: 'Payment ZIP / postal code',
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
                subtitle: Text(
                  _features.eventsMeetings
                      ? 'Allow visitors to view shared meetings and events.'
                      : 'Public events require the Events & Meetings Add-on.',
                ),
                value: _features.eventsMeetings && _allowPublicEvents,
                onChanged: _isSaving || !_features.eventsMeetings
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
                subtitle: Text(
                  _features.sweepstakes
                      ? 'Allow visitors to view published sweepstakes standings.'
                      : 'Public sweepstakes standings require the Sweepstakes Add-on.',
                ),
                value: _features.sweepstakes && _allowPublicSweepstakes,
                onChanged: _isSaving || !_features.sweepstakes
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

class _LogoUploadField extends StatelessWidget {
  const _LogoUploadField({
    required this.logoUrlController,
    required this.isUploading,
    required this.onUpload,
    required this.onClear,
  });

  final TextEditingController logoUrlController;
  final bool isUploading;
  final VoidCallback onUpload;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final logoUrl = logoUrlController.text.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Club Logo',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 8),
        Material(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: logoUrl.isEmpty
                      ? const Icon(Icons.image_outlined, size: 38)
                      : Image.network(
                          logoUrl,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) =>
                              const Icon(
                            Icons.broken_image_outlined,
                            size: 38,
                          ),
                        ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        logoUrl.isEmpty ? 'No logo uploaded' : 'Logo selected',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Upload a PNG, JPG, or WebP logo. Logo files are limited to 1 MB on the base club plan.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (logoUrl.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        SelectableText(
                          logoUrl,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            onPressed: isUploading ? null : onUpload,
                            icon: isUploading
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.upload_file_outlined),
                            label: Text(
                              isUploading ? 'Uploading...' : 'Upload Logo',
                            ),
                          ),
                          if (logoUrl.isNotEmpty)
                            OutlinedButton.icon(
                              onPressed: onClear,
                              icon: const Icon(Icons.clear),
                              label: const Text('Remove'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ClubSettingsFeatureAccess {
  const _ClubSettingsFeatureAccess({
    required this.eventsMeetings,
    required this.sweepstakes,
  });

  const _ClubSettingsFeatureAccess.base()
      : eventsMeetings = false,
        sweepstakes = false;

  final bool eventsMeetings;
  final bool sweepstakes;

  factory _ClubSettingsFeatureAccess.fromJson(Map<String, dynamic> json) {
    return _ClubSettingsFeatureAccess(
      eventsMeetings: json['events_meetings_addon_enabled'] == true,
      sweepstakes: json['sweepstakes_addon_enabled'] == true,
    );
  }
}

class _BaseSettingsAccessCard extends StatelessWidget {
  const _BaseSettingsAccessCard({required this.features});

  final _ClubSettingsFeatureAccess features;

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
              backgroundColor: scheme.primaryContainer,
              foregroundColor: scheme.onPrimaryContainer,
              child: const Icon(Icons.settings_outlined),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Included with Base Club Tools',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Club profile, branding, contact details, documents visibility, and core settings are always available. Public event and sweepstakes visibility depend on those add-ons being enabled.',
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      const _SettingsFeatureChip(
                        label: 'Base Settings',
                        enabled: true,
                      ),
                      _SettingsFeatureChip(
                        label: 'Public Events',
                        enabled: features.eventsMeetings,
                      ),
                      _SettingsFeatureChip(
                        label: 'Public Sweepstakes',
                        enabled: features.sweepstakes,
                      ),
                    ],
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

class _SettingsFeatureChip extends StatelessWidget {
  const _SettingsFeatureChip({required this.label, required this.enabled});

  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Chip(
      avatar: Icon(
        enabled ? Icons.check_circle_outline : Icons.lock_outline,
        size: 18,
      ),
      label: Text(label),
      backgroundColor:
          enabled ? scheme.primaryContainer : scheme.surfaceContainerHighest,
      side: BorderSide(
        color: enabled ? scheme.primary : scheme.outlineVariant,
      ),
      visualDensity: VisualDensity.compact,
    );
  }
}