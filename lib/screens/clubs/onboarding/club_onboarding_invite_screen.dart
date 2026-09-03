import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class ClubOnboardingInviteScreen extends StatefulWidget {
  const ClubOnboardingInviteScreen({super.key, required this.token});

  final String token;

  @override
  State<ClubOnboardingInviteScreen> createState() =>
      _ClubOnboardingInviteScreenState();
}

class _ClubOnboardingInviteScreenState
    extends State<ClubOnboardingInviteScreen> {
  final _supabase = Supabase.instance.client;
  final _clubName = TextEditingController();
  final _shortName = TextEditingController();
  final _website = TextEditingController();
  final _contactName = TextEditingController();
  final _contactEmail = TextEditingController();
  final _contactPhone = TextEditingController();
  final _addressLine1 = TextEditingController();
  final _addressLine2 = TextEditingController();
  final _city = TextEditingController();
  final _state = TextEditingController();
  final _postalCode = TextEditingController();
  final _treasurerName = TextEditingController();
  final _treasurerEmail = TextEditingController();
  final _treasurerAddressLine1 = TextEditingController();
  final _treasurerAddressLine2 = TextEditingController();
  final _treasurerCity = TextEditingController();
  final _treasurerState = TextEditingController();
  final _treasurerPostalCode = TextEditingController();
  final _description = TextEditingController();
  final _logoUrl = TextEditingController();
  final _brandPrimaryColor = TextEditingController();
  final _brandSecondaryColor = TextEditingController();
  final _communicationSenderName = TextEditingController();
  final _communicationReplyToEmail = TextEditingController();
  final _officers = <_OfficerDraft>[];

  bool _loading = true;
  bool _saving = false;
  String? _error;
  String _email = '';
  String? _draftId;
  String _onboardingStatus = 'in_progress';
  String? _provisionedClubId;
  Map<String, dynamic> _purchasedEntitlements = const {};
  int _step = 0;
  bool _membership = true;
  bool _sanctions = false;
  bool _events = false;
  bool _sweepstakes = false;
  bool _onlinePayments = false;
  bool _mailedChecks = true;
  bool _memberImport = false;
  bool _sweepstakesImport = false;
  String _paymentProvider = 'not_ready';
  String _clubType = 'local';
  String _speciesScope = 'both';
  bool _publicProfile = true;
  bool _publicEvents = false;
  bool _publicDocuments = false;
  bool _publicSweepstakes = false;
  bool _requireArbaNumber = true;
  bool _requireMembershipApproval = false;
  bool _allowAutoRenew = false;
  int _adultMinimumAge = 19;
  int _youthMaximumAge = 18;
  int _familyIncludedAdults = 2;
  int _familyIncludedYouth = 3;
  double _additionalYouthPrice = 0;
  String _senderChoice = 'club_name';
  String _replyToChoice = 'club_email';
  Map<String, dynamic>? _rosterPreview;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final controller in [
      _clubName,
      _shortName,
      _website,
      _contactName,
      _contactEmail,
      _contactPhone,
      _addressLine1,
      _addressLine2,
      _city,
      _state,
      _postalCode,
      _treasurerName,
      _treasurerEmail,
      _treasurerAddressLine1,
      _treasurerAddressLine2,
      _treasurerCity,
      _treasurerState,
      _treasurerPostalCode,
      _description,
      _logoUrl,
      _brandPrimaryColor,
      _brandSecondaryColor,
      _communicationSenderName,
      _communicationReplyToEmail,
    ]) {
      controller.dispose();
    }
    for (final officer in _officers) {
      officer.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final response = await _supabase.rpc(
        'get_club_onboarding_invitation',
        params: {'p_token': widget.token},
      );
      final data = Map<String, dynamic>.from(response as Map);
      final answers = Map<String, dynamic>.from(data['answers'] as Map? ?? {});
      _email = data['email']?.toString() ?? '';
      _draftId = data['draft_id']?.toString();
      _onboardingStatus = data['status']?.toString() ?? 'in_progress';
      _provisionedClubId = data['provisioned_club_id']?.toString();
      _purchasedEntitlements = Map<String, dynamic>.from(
        data['purchased_entitlements'] as Map? ?? const {},
      );
      _restore(answers);
      _rosterPreview = Map<String, dynamic>.from(
        await _supabase.rpc(
              'get_club_onboarding_roster_preview',
              params: {'p_token': widget.token},
            )
            as Map,
      );
      _step = _stepFor(data['current_step']?.toString());
      if (mounted) setState(() => _loading = false);
    } catch (error) {
      if (mounted)
        setState(() {
          _error = '$error';
          _loading = false;
        });
    }
  }

  int _stepFor(String? value) => switch (value) {
    'club' => 0,
    'officers' => 1,
    'setup' => 2,
    'imports' => 3,
    'review' => 4,
    _ => 0,
  };

  void _restore(Map<String, dynamic> answers) {
    final club = Map<String, dynamic>.from(answers['club'] as Map? ?? {});
    final treasurer = Map<String, dynamic>.from(
      answers['treasurer'] as Map? ?? {},
    );
    final setup = Map<String, dynamic>.from(answers['setup'] as Map? ?? {});
    final imports = Map<String, dynamic>.from(answers['imports'] as Map? ?? {});
    _clubName.text = club['name']?.toString() ?? '';
    _shortName.text = club['short_name']?.toString() ?? '';
    _website.text = club['website_url']?.toString() ?? '';
    _contactName.text = club['contact_name']?.toString() ?? '';
    _contactEmail.text = club['contact_email']?.toString() ?? _email;
    _contactPhone.text = club['contact_phone']?.toString() ?? '';
    _addressLine1.text =
        club['address_line1']?.toString() ?? club['address']?.toString() ?? '';
    _addressLine2.text = club['address_line2']?.toString() ?? '';
    _city.text = club['city']?.toString() ?? '';
    _state.text = club['state']?.toString() ?? '';
    _postalCode.text = club['postal_code']?.toString() ?? '';
    _treasurerName.text = treasurer['name']?.toString() ?? '';
    _treasurerEmail.text = treasurer['email']?.toString() ?? '';
    _treasurerAddressLine1.text =
        treasurer['address_line1']?.toString() ??
        treasurer['address']?.toString() ??
        '';
    _treasurerAddressLine2.text = treasurer['address_line2']?.toString() ?? '';
    _treasurerCity.text = treasurer['city']?.toString() ?? '';
    _treasurerState.text = treasurer['state']?.toString() ?? '';
    _treasurerPostalCode.text = treasurer['postal_code']?.toString() ?? '';
    _description.text = club['description']?.toString() ?? '';
    _logoUrl.text = club['logo_url']?.toString() ?? '';
    final branding = Map<String, dynamic>.from(club['branding'] as Map? ?? {});
    _brandPrimaryColor.text = branding['primary_color']?.toString() ?? '';
    _brandSecondaryColor.text = branding['secondary_color']?.toString() ?? '';
    _clubType = club['type']?.toString() ?? 'local';
    _speciesScope = club['species_scope']?.toString() ?? 'both';
    _publicProfile = club['public_profile'] != false;
    _publicEvents = club['public_events'] == true;
    _publicDocuments = club['public_documents'] == true;
    _publicSweepstakes = club['public_sweepstakes'] == true;
    _membership = _hasPurchasedAddOn('membership_management');
    _sanctions = _hasPurchasedAddOn('sanction_requests');
    _events = _hasPurchasedAddOn('events_meetings');
    _sweepstakes = _hasPurchasedAddOn('sweepstakes');
    _onlinePayments = setup['online_payments'] == true;
    _mailedChecks = setup['mailed_checks'] != false;
    _paymentProvider = setup['payment_provider']?.toString() ?? 'not_ready';
    final rules = Map<String, dynamic>.from(
      setup['membership_rules'] as Map? ?? const {},
    );
    _requireArbaNumber = rules['require_arba_number'] != false;
    _requireMembershipApproval = rules['requires_approval'] == true;
    _allowAutoRenew = rules['allow_auto_renew'] == true;
    _adultMinimumAge = _asInt(rules['adult_minimum_age'], 19);
    _youthMaximumAge = _asInt(rules['youth_maximum_age'], 18);
    _familyIncludedAdults = _asInt(rules['family_included_adults'], 2);
    _familyIncludedYouth = _asInt(rules['family_included_youth'], 3);
    _additionalYouthPrice = _asDouble(rules['additional_youth_price'], 0);
    _senderChoice =
        setup['communication_sender_choice']?.toString() ?? 'club_name';
    _replyToChoice =
        setup['communication_reply_to_choice']?.toString() ?? 'club_email';
    _communicationSenderName.text =
        setup['communication_sender_name']?.toString() ?? '';
    _communicationReplyToEmail.text =
        setup['communication_reply_to_email']?.toString() ?? '';
    _memberImport = imports['membership_roster'] == true;
    _sweepstakesImport = imports['sweepstakes_archive'] == true;
    final savedOfficers = answers['officers'] as List? ?? const [];
    for (final item in savedOfficers.whereType<Map>()) {
      _officers.add(_OfficerDraft.fromJson(Map<String, dynamic>.from(item)));
    }
    final seenEmptyTitles = <String>{};
    _officers.removeWhere((officer) {
      final isEmpty =
          officer.name.text.trim().isEmpty && officer.email.text.trim().isEmpty;
      if (!isEmpty || !seenEmptyTitles.contains(officer.title.text)) {
        if (isEmpty) seenEmptyTitles.add(officer.title.text);
        return false;
      }
      officer.dispose();
      return true;
    });
    _ensureStandardOfficers();
  }

  int _asInt(dynamic value, int fallback) => value is num
      ? value.toInt()
      : int.tryParse(value?.toString() ?? '') ?? fallback;

  double _asDouble(dynamic value, double fallback) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? fallback;

  bool _hasPurchasedAddOn(String addOnKey) {
    final values = _purchasedEntitlements['addons'] as List? ?? const [];
    return values.map((value) => value.toString()).contains(addOnKey);
  }

  String get _purchasedPlanKey =>
      _purchasedEntitlements['plan_key']?.toString() ?? 'small_club_base';

  String get _purchasedPlanLabel => switch (_purchasedPlanKey) {
    'standard_club_complete' => 'Standard Club Complete',
    'standard_club_base' => 'Standard Club Base',
    _ => 'Small Club Base',
  };

  void _ensureStandardOfficers() {
    const titles = ['President', 'Vice President', 'Secretary', 'Newsletter'];
    for (final title in titles) {
      final matching = _officers
          .where((officer) => officer.title.text == title)
          .toList();
      if (matching.isEmpty) {
        _officers.add(
          _OfficerDraft(title: title, access: _defaultAccessForTitle(title)),
        );
      } else if (matching.first.name.text.trim().isEmpty &&
          matching.first.email.text.trim().isEmpty) {
        matching.first.access = _defaultAccessForTitle(title);
      }
    }
  }

  String _defaultAccessForTitle(String title) => switch (title) {
    'President' || 'Secretary' => 'club_admin',
    'Vice President' || 'Newsletter' => 'membership_read_newsletter',
    'Director' => 'read_only',
    _ => 'read_only',
  };

  List<_OfficerDraft> get _enteredOfficers => _officers
      .where(
        (officer) =>
            officer.name.text.trim().isNotEmpty ||
            officer.email.text.trim().isNotEmpty,
      )
      .toList();

  _OfficerDraft _officerFor(String title) =>
      _officers.firstWhere((officer) => officer.title.text == title);

  void _addDirector() => setState(
    () => _officers.add(
      _OfficerDraft(
        title: 'Director',
        access: _defaultAccessForTitle('Director'),
      ),
    ),
  );

  Map<String, dynamic> get _answers => {
    'club': {
      'name': _clubName.text.trim(),
      'short_name': _shortName.text.trim(),
      'type': _clubType,
      'species_scope': _speciesScope,
      'description': _description.text.trim(),
      'logo_url': _logoUrl.text.trim(),
      'branding': {
        'primary_color': _brandPrimaryColor.text.trim(),
        'secondary_color': _brandSecondaryColor.text.trim(),
      },
      'website_url': _website.text.trim(),
      'contact_name': _contactName.text.trim(),
      'contact_email': _contactEmail.text.trim(),
      'contact_phone': _contactPhone.text.trim(),
      'address_line1': _addressLine1.text.trim(),
      'address_line2': _addressLine2.text.trim(),
      'city': _city.text.trim(),
      'state': _state.text.trim(),
      'postal_code': _postalCode.text.trim(),
      'country': 'US',
      'public_profile': _publicProfile,
      'public_events': _publicEvents,
      'public_documents': _publicDocuments,
      'public_sweepstakes': _publicSweepstakes,
    },
    'treasurer': {
      'name': _treasurerName.text.trim(),
      'email': _treasurerEmail.text.trim(),
      'address_line1': _treasurerAddressLine1.text.trim(),
      'address_line2': _treasurerAddressLine2.text.trim(),
      'city': _treasurerCity.text.trim(),
      'state': _treasurerState.text.trim(),
      'postal_code': _treasurerPostalCode.text.trim(),
    },
    'officers': _enteredOfficers.map((officer) => officer.toJson()).toList(),
    'setup': {
      'membership_management': _membership,
      'sanctions': _sanctions,
      'events': _events,
      'sweepstakes': _sweepstakes,
      'online_payments': _onlinePayments,
      'mailed_checks': _mailedChecks,
      'payment_provider': _paymentProvider,
      'paypal_requested': _paymentProvider == 'paypal',
      'communication_sender_choice': _senderChoice,
      'communication_sender_name': _senderChoice == 'custom'
          ? _communicationSenderName.text.trim()
          : _senderChoice == 'contact_name'
          ? _contactName.text.trim()
          : _shortName.text.trim().isEmpty
          ? _clubName.text.trim()
          : _shortName.text.trim(),
      'communication_reply_to_choice': _replyToChoice,
      'communication_reply_to_email': _replyToChoice == 'custom'
          ? _communicationReplyToEmail.text.trim()
          : _replyToChoice == 'contact_email'
          ? (_contactEmail.text.trim().isEmpty
                ? _email
                : _contactEmail.text.trim())
          : _email,
      'membership_rules': {
        'require_arba_number': _requireArbaNumber,
        'requires_approval': _requireMembershipApproval,
        'allow_auto_renew': _allowAutoRenew,
        'adult_minimum_age': _adultMinimumAge,
        'youth_maximum_age': _youthMaximumAge,
        'family_included_adults': _familyIncludedAdults,
        'family_included_youth': _familyIncludedYouth,
        'additional_youth_price': _additionalYouthPrice,
      },
      'membership_types': const [
        {'name': 'Individual', 'price': 10},
        {'name': 'Family', 'price': 15},
        {'name': 'Youth', 'price': 5},
      ],
    },
    'imports': {
      'membership_roster': _memberImport,
      'sweepstakes_archive': _sweepstakesImport,
      'review_before_import': true,
    },
  };

  Future<void> _save({required int nextStep}) async {
    if (_saving) return;
    if (_step == 0 && _clubName.text.trim().isEmpty) {
      setState(() => _error = 'Enter the club name before continuing.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _supabase.rpc(
        'save_club_onboarding_draft',
        params: {
          'p_token': widget.token,
          'p_current_step': _stepName(nextStep),
          'p_answers': _answers,
        },
      );
      _onboardingStatus = 'ready_for_review';
      if (mounted) setState(() => _step = nextStep);
    } catch (error) {
      if (mounted) setState(() => _error = 'Unable to save progress: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _stepName(int step) =>
      ['club', 'officers', 'setup', 'imports', 'review'][step];

  String get _importsSummary {
    final items = <String>[
      if (_memberImport) 'Membership roster',
      if (_sweepstakesImport) 'Sweepstakes reports',
    ];
    return items.isEmpty ? 'None planned' : items.join(', ');
  }

  Future<void> _pickRoster() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv'],
      withData: true,
    );
    if (picked == null || picked.files.single.bytes == null) return;
    final file = picked.files.single;
    final draftId = _draftId;
    if (draftId == null || draftId.isEmpty) {
      throw StateError(
        'Unable to identify this onboarding draft. Refresh and try again.',
      );
    }
    try {
      setState(() {
        _saving = true;
        _error = null;
      });
      final parsed = _parseCsv(String.fromCharCodes(file.bytes!));
      if (parsed.length < 2) {
        throw Exception('The CSV needs a header row and at least one member.');
      }
      final headers = parsed.first.map((cell) => cell.trim()).toList();
      final rows = <Map<String, dynamic>>[];
      for (var index = 1; index < parsed.length; index++) {
        final source = <String, String>{};
        for (var column = 0; column < headers.length; column++) {
          source[headers[column]] = column < parsed[index].length
              ? parsed[index][column].trim()
              : '';
        }
        rows.add(_normalizeRosterRow(source, index + 1));
      }
      final safeFileName = file.name.replaceAll(
        RegExp(r'[^A-Za-z0-9._-]'),
        '_',
      );
      final storageBucket = 'club-onboarding-rosters';
      final storagePath =
          '$draftId/rosters/${DateTime.now().microsecondsSinceEpoch}_$safeFileName';
      await _supabase.storage
          .from(storageBucket)
          .uploadBinary(
            storagePath,
            file.bytes!,
            fileOptions: const FileOptions(
              contentType: 'text/csv',
              upsert: false,
            ),
          );
      final result = await _supabase.rpc(
        'save_club_onboarding_roster_preview',
        params: {
          'p_token': widget.token,
          'p_file_name': file.name,
          'p_headers': headers,
          'p_rows': rows,
          'p_storage_bucket': storageBucket,
          'p_storage_path': storagePath,
        },
      );
      if (mounted) {
        setState(() {
          _memberImport = true;
          _rosterPreview = Map<String, dynamic>.from(result as Map);
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Unable to prepare roster preview: $error');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  List<List<String>> _parseCsv(String content) {
    final rows = <List<String>>[];
    var row = <String>[];
    var cell = StringBuffer();
    var quoted = false;
    for (var i = 0; i < content.length; i++) {
      final char = content[i];
      if (char == '"') {
        if (quoted && i + 1 < content.length && content[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          quoted = !quoted;
        }
      } else if (char == ',' && !quoted) {
        row.add(cell.toString());
        cell = StringBuffer();
      } else if ((char == '\n' || char == '\r') && !quoted) {
        if (char == '\r' && i + 1 < content.length && content[i + 1] == '\n')
          i++;
        row.add(cell.toString());
        cell = StringBuffer();
        if (row.any((value) => value.trim().isNotEmpty)) rows.add(row);
        row = <String>[];
      } else {
        cell.write(char);
      }
    }
    row.add(cell.toString());
    if (row.any((value) => value.trim().isNotEmpty)) rows.add(row);
    return rows;
  }

  Map<String, dynamic> _normalizeRosterRow(
    Map<String, String> source,
    int rowNumber,
  ) {
    String find(List<String> names) {
      for (final name in names) {
        final match = source.entries
            .where(
              (entry) =>
                  entry.key.toLowerCase().replaceAll(
                    RegExp(r'[^a-z0-9]'),
                    '',
                  ) ==
                  name,
            )
            .toList();
        if (match.isNotEmpty && match.first.value.isNotEmpty)
          return match.first.value;
      }
      return '';
    }

    final fullName = find(['name', 'fullname', 'membername']);
    var first = find(['firstname', 'first']);
    var last = find(['lastname', 'last', 'surname']);
    if (first.isEmpty && last.isEmpty && fullName.isNotEmpty) {
      final bits = fullName.split(RegExp(r'\s+'));
      first = bits.first;
      last = bits.skip(1).join(' ');
    }
    final email = find(['email', 'emailaddress']);
    final type = find(['membershiptype', 'membertype', 'type', 'membership']);
    final errors = <String>[];
    if (first.isEmpty && last.isEmpty) errors.add('Missing member name');
    if (email.isNotEmpty && !email.contains('@'))
      errors.add('Email address looks incomplete');
    return {
      'row_number': rowNumber,
      'source_row': source,
      'proposed_member': {
        'first_name': first,
        'last_name': last,
        'email': email,
        'phone': find(['phone', 'phonenumber', 'mobile']),
        'address_line1': find(['address', 'address1', 'street']),
        'city': find(['city']),
        'state': find(['state', 'province']),
        'postal_code': find(['zip', 'zipcode', 'postalcode']),
        'membership_type': type.isEmpty ? 'Needs review' : type,
        'household': find(['household', 'family', 'familyname']),
      },
      'errors': errors,
    };
  }

  Future<void> _submit() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _supabase.rpc(
        'submit_club_onboarding_draft',
        params: {'p_token': widget.token},
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          icon: const Icon(Icons.mark_email_read_outlined),
          title: const Text('Ready for Review'),
          content: const Text(
            'Your setup choices are saved. RingMaster will review the draft with you before the club, staff access, payments, and imports are activated.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = 'Unable to submit: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_error != null && _email.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Club Onboarding')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_error!),
          ),
        ),
      );
    }
    if (_onboardingStatus == 'approved' && _provisionedClubId != null) {
      return _activationScreen();
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Set Up Your Club')),
      body: Stepper(
        currentStep: _step,
        type: StepperType.horizontal,
        onStepTapped: (step) => setState(() => _step = step),
        controlsBuilder: (context, details) => Padding(
          padding: const EdgeInsets.only(top: 20),
          child: Wrap(
            spacing: 12,
            children: [
              if (_step > 0)
                OutlinedButton(
                  onPressed: _saving ? null : () => _save(nextStep: _step - 1),
                  child: const Text('Back'),
                ),
              if (_step < 4)
                FilledButton(
                  onPressed: _saving ? null : () => _save(nextStep: _step + 1),
                  child: Text(_saving ? 'Saving…' : 'Save & Continue'),
                )
              else
                FilledButton.icon(
                  onPressed: _saving ? null : _submit,
                  icon: const Icon(Icons.fact_check_outlined),
                  label: Text(_saving ? 'Submitting…' : 'Submit for Review'),
                ),
            ],
          ),
        ),
        steps: [
          Step(
            title: const Text('Club'),
            content: _clubStep(),
            isActive: _step >= 0,
          ),
          Step(
            title: const Text('Officers'),
            content: _officersStep(),
            isActive: _step >= 1,
          ),
          Step(
            title: const Text('Setup'),
            content: _setupStep(),
            isActive: _step >= 2,
          ),
          Step(
            title: const Text('Imports'),
            content: _importsStep(),
            isActive: _step >= 3,
          ),
          Step(
            title: const Text('Review'),
            content: _reviewStep(),
            isActive: _step >= 4,
          ),
        ],
      ),
    );
  }

  Widget _clubStep() => _StepContent(
    title: 'Start with your club details',
    description:
        'This invitation is tied to $_email. That shared club email will become the Club Account Owner.',
    children: [
      TextField(
        controller: _clubName,
        autofillHints: const [AutofillHints.organizationName],
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.next,
        onEditingComplete: () => FocusScope.of(context).nextFocus(),
        decoration: const InputDecoration(labelText: 'Legal club name *'),
      ),
      TextField(
        controller: _shortName,
        textCapitalization: TextCapitalization.characters,
        textInputAction: TextInputAction.next,
        onEditingComplete: () => FocusScope.of(context).nextFocus(),
        decoration: const InputDecoration(
          labelText: 'Short name / abbreviation',
        ),
      ),
      DropdownButtonFormField<String>(
        initialValue: _clubType,
        decoration: const InputDecoration(labelText: 'Club type *'),
        items: const [
          DropdownMenuItem(value: 'local', child: Text('Local club')),
          DropdownMenuItem(value: 'state', child: Text('State club')),
          DropdownMenuItem(value: 'national', child: Text('National club')),
          DropdownMenuItem(value: 'specialty', child: Text('Specialty club')),
        ],
        onChanged: (value) => setState(() => _clubType = value ?? 'local'),
      ),
      DropdownButtonFormField<String>(
        initialValue: _speciesScope,
        decoration: const InputDecoration(labelText: 'Species scope *'),
        items: const [
          DropdownMenuItem(value: 'rabbit', child: Text('Rabbit')),
          DropdownMenuItem(value: 'cavy', child: Text('Cavy')),
          DropdownMenuItem(value: 'both', child: Text('Rabbit & Cavy')),
        ],
        onChanged: (value) => setState(() => _speciesScope = value ?? 'both'),
      ),
      TextField(
        controller: _description,
        minLines: 2,
        maxLines: 4,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(labelText: 'Club description'),
      ),
      TextField(
        controller: _website,
        autofillHints: const [AutofillHints.url],
        keyboardType: TextInputType.url,
        textInputAction: TextInputAction.next,
        onEditingComplete: () => FocusScope.of(context).nextFocus(),
        decoration: const InputDecoration(labelText: 'Website URL'),
      ),
      TextField(
        controller: _logoUrl,
        autofillHints: const [AutofillHints.url],
        keyboardType: TextInputType.url,
        decoration: const InputDecoration(
          labelText: 'Logo URL (optional)',
          helperText:
              'You can also replace this with an uploaded logo after activation.',
        ),
      ),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _brandPrimaryColor,
              decoration: const InputDecoration(
                labelText: 'Primary brand color',
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _brandSecondaryColor,
              decoration: const InputDecoration(
                labelText: 'Secondary brand color',
              ),
            ),
          ),
        ],
      ),
      TextField(
        controller: _contactName,
        autofillHints: const [AutofillHints.name],
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.next,
        onEditingComplete: () => FocusScope.of(context).nextFocus(),
        decoration: const InputDecoration(labelText: 'Primary contact name'),
      ),
      TextField(
        controller: _contactEmail,
        autofillHints: const [AutofillHints.email],
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.next,
        onEditingComplete: () => FocusScope.of(context).nextFocus(),
        decoration: const InputDecoration(
          labelText: 'Primary contact email',
          helperText:
              'This may be different from the shared club account email.',
        ),
      ),
      TextField(
        controller: _contactPhone,
        autofillHints: const [AutofillHints.telephoneNumber],
        keyboardType: TextInputType.phone,
        textInputAction: TextInputAction.next,
        onEditingComplete: () => FocusScope.of(context).nextFocus(),
        decoration: const InputDecoration(labelText: 'Contact phone'),
      ),
      TextField(
        controller: _addressLine1,
        autofillHints: const [AutofillHints.streetAddressLine1],
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.next,
        onEditingComplete: () => FocusScope.of(context).nextFocus(),
        decoration: const InputDecoration(
          labelText: 'Mailing address line 1 *',
        ),
      ),
      TextField(
        controller: _addressLine2,
        autofillHints: const [AutofillHints.streetAddressLine2],
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.next,
        onEditingComplete: () => FocusScope.of(context).nextFocus(),
        decoration: const InputDecoration(labelText: 'Mailing address line 2'),
      ),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _city,
              autofillHints: const [AutofillHints.addressCity],
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              onEditingComplete: () => FocusScope.of(context).nextFocus(),
              decoration: const InputDecoration(labelText: 'City'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: _usStates.any((item) => item.code == _state.text)
                  ? _state.text
                  : null,
              decoration: const InputDecoration(labelText: 'State'),
              isExpanded: true,
              items: [
                for (final state in _usStates)
                  DropdownMenuItem(
                    value: state.code,
                    child: Text('${state.code} — ${state.name}'),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _state.text = value);
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _postalCode,
              autofillHints: const [AutofillHints.postalCode],
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.next,
              onEditingComplete: () => FocusScope.of(context).nextFocus(),
              decoration: const InputDecoration(labelText: 'ZIP / postal code'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 4),
      const Text(
        'Public visibility',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: _publicProfile,
        onChanged: (value) => setState(() => _publicProfile = value),
        title: const Text('Show a public club profile'),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: _publicEvents,
        onChanged: (value) => setState(() => _publicEvents = value),
        title: const Text('Show public events'),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: _publicDocuments,
        onChanged: (value) => setState(() => _publicDocuments = value),
        title: const Text('Allow public documents'),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: _publicSweepstakes,
        onChanged: (value) => setState(() => _publicSweepstakes = value),
        title: const Text('Show public sweepstakes results'),
      ),
    ],
  );

  Widget _officersStep() => _StepContent(
    title: 'Add your officers',
    description:
        'Enter each office separately. RingMaster assigns the appropriate starting access for each office; it can be adjusted later in Staff & Permissions.',
    children: [
      TextField(
        controller: _treasurerName,
        autofillHints: const [AutofillHints.name],
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.next,
        onEditingComplete: () => FocusScope.of(context).nextFocus(),
        decoration: const InputDecoration(labelText: 'Treasurer name'),
      ),
      TextField(
        controller: _treasurerEmail,
        autofillHints: const [AutofillHints.email],
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.next,
        onEditingComplete: () => FocusScope.of(context).nextFocus(),
        decoration: const InputDecoration(labelText: 'Treasurer email'),
      ),
      TextField(
        controller: _treasurerAddressLine1,
        autofillHints: const [AutofillHints.streetAddressLine1],
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.next,
        onEditingComplete: () => FocusScope.of(context).nextFocus(),
        decoration: const InputDecoration(
          labelText: 'Treasurer / check-payment address line 1',
        ),
      ),
      TextField(
        controller: _treasurerAddressLine2,
        autofillHints: const [AutofillHints.streetAddressLine2],
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.next,
        onEditingComplete: () => FocusScope.of(context).nextFocus(),
        decoration: const InputDecoration(labelText: 'Address line 2'),
      ),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _treasurerCity,
              autofillHints: const [AutofillHints.addressCity],
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'City'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue:
                  _usStates.any((item) => item.code == _treasurerState.text)
                  ? _treasurerState.text
                  : null,
              decoration: const InputDecoration(labelText: 'State'),
              isExpanded: true,
              items: [
                for (final state in _usStates)
                  DropdownMenuItem(
                    value: state.code,
                    child: Text('${state.code} — ${state.name}'),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _treasurerState.text = value);
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _treasurerPostalCode,
              autofillHints: const [AutofillHints.postalCode],
              decoration: const InputDecoration(labelText: 'ZIP / postal code'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      const Text(
        'Club Officers',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 8),
      _OfficerCard(officer: _officerFor('President')),
      _OfficerCard(officer: _officerFor('Vice President')),
      _OfficerCard(officer: _officerFor('Secretary')),
      _OfficerCard(officer: _officerFor('Newsletter')),
      for (final officer in _officers.where(
        (officer) => officer.title.text == 'Director',
      ))
        _OfficerCard(
          officer: officer,
          onRemove: () => setState(() {
            officer.dispose();
            _officers.remove(officer);
          }),
        ),
      OutlinedButton.icon(
        onPressed: _addDirector,
        icon: const Icon(Icons.person_add_alt_1_outlined),
        label: const Text('Add Director'),
      ),
    ],
  );

  Widget _setupStep() => _StepContent(
    title: 'Purchased services and payment setup',
    description:
        'Your plan and included services are set from your purchase. Choose a payment provider only if you want to accept payments online.',
    children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Included with your purchase',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              _PurchasedServiceRow(label: 'Plan', value: _purchasedPlanLabel),
              _PurchasedServiceRow(
                label: 'Membership management',
                included: _membership,
              ),
              _PurchasedServiceRow(
                label: 'Sanction requests',
                included: _sanctions,
              ),
              _PurchasedServiceRow(
                label: 'Events & meetings',
                included: _events,
              ),
              _PurchasedServiceRow(
                label: 'Sweepstakes',
                included: _sweepstakes,
              ),
              _PurchasedServiceRow(
                label: 'Email communications',
                included: _hasPurchasedAddOn('email'),
              ),
              const SizedBox(height: 6),
              const Text(
                'Need to change your plan or included services? Contact RingMaster before activation.',
              ),
            ],
          ),
        ),
      ),
      const Divider(),
      if (_membership) ...[
        Text(
          'Membership rules',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const Text(
          'These default rules will be applied to your Individual, Family, and Youth plans before activation.',
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _requireArbaNumber,
          onChanged: (value) => setState(() => _requireArbaNumber = value),
          title: const Text('Require ARBA number'),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _requireMembershipApproval,
          onChanged: (value) =>
              setState(() => _requireMembershipApproval = value),
          title: const Text('Require membership approval'),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _allowAutoRenew,
          onChanged: (value) => setState(() => _allowAutoRenew = value),
          title: const Text('Allow automatic renewal'),
        ),
        Row(
          children: [
            Expanded(
              child: _NumberField(
                label: 'Individual minimum age',
                value: _adultMinimumAge,
                onChanged: (value) => setState(() => _adultMinimumAge = value),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _NumberField(
                label: 'Youth maximum age',
                value: _youthMaximumAge,
                onChanged: (value) => setState(() => _youthMaximumAge = value),
              ),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: _NumberField(
                label: 'Family included adults',
                value: _familyIncludedAdults,
                onChanged: (value) =>
                    setState(() => _familyIncludedAdults = value),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _NumberField(
                label: 'Family included youth',
                value: _familyIncludedYouth,
                onChanged: (value) =>
                    setState(() => _familyIncludedYouth = value),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                initialValue: _additionalYouthPrice.toStringAsFixed(2),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Extra youth fee (USD)',
                ),
                onChanged: (value) =>
                    setState(() => _additionalYouthPrice = _asDouble(value, 0)),
              ),
            ),
          ],
        ),
        const Divider(),
      ],
      SwitchListTile(
        value: _onlinePayments,
        onChanged: _membership
            ? (value) => setState(() {
                _onlinePayments = value;
                if (!value) _paymentProvider = 'not_ready';
              })
            : null,
        title: const Text('Accept online membership payments'),
        subtitle: Text(
          _membership
              ? 'Choose a provider below. Stripe launches after your club is activated.'
              : 'Membership Management is not included with this purchase.',
        ),
      ),
      SwitchListTile(
        value: _mailedChecks,
        onChanged: _membership
            ? (value) => setState(() => _mailedChecks = value)
            : null,
        title: const Text('Accept mailed checks'),
      ),
      DropdownButtonFormField<String>(
        initialValue: _paymentProvider,
        decoration: const InputDecoration(labelText: 'Online payment provider'),
        items: const [
          DropdownMenuItem(value: 'not_ready', child: Text('Not ready yet')),
          DropdownMenuItem(
            value: 'stripe',
            child: Text('Stripe — recommended'),
          ),
          DropdownMenuItem(value: 'square', child: Text('Square')),
          DropdownMenuItem(
            value: 'paypal',
            child: Text('PayPal — coming soon'),
          ),
        ],
        onChanged: _onlinePayments
            ? (value) {
                if (value != null) setState(() => _paymentProvider = value);
              }
            : null,
      ),
      const Card(
        child: Padding(
          padding: EdgeInsets.all(14),
          child: Text(
            'Stripe Connect or Square will open immediately after RingMaster activates your club. PayPal is recorded for follow-up while its Club connection flow is prepared.',
          ),
        ),
      ),
      if (_hasPurchasedAddOn('email')) ...[
        const Divider(),
        Text(
          'Communication defaults',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        DropdownButtonFormField<String>(
          initialValue: _senderChoice,
          decoration: const InputDecoration(labelText: 'Email sender name'),
          items: const [
            DropdownMenuItem(
              value: 'club_name',
              child: Text('Club short name'),
            ),
            DropdownMenuItem(
              value: 'contact_name',
              child: Text('Primary contact name'),
            ),
            DropdownMenuItem(
              value: 'custom',
              child: Text('Custom sender name'),
            ),
          ],
          onChanged: (value) =>
              setState(() => _senderChoice = value ?? 'club_name'),
        ),
        if (_senderChoice == 'custom')
          TextField(
            controller: _communicationSenderName,
            decoration: const InputDecoration(labelText: 'Custom sender name'),
          ),
        DropdownButtonFormField<String>(
          initialValue: _replyToChoice,
          decoration: const InputDecoration(labelText: 'Reply-to email'),
          items: const [
            DropdownMenuItem(
              value: 'club_email',
              child: Text('Shared club email'),
            ),
            DropdownMenuItem(
              value: 'contact_email',
              child: Text('Primary contact email'),
            ),
            DropdownMenuItem(
              value: 'custom',
              child: Text('Custom reply-to email'),
            ),
          ],
          onChanged: (value) =>
              setState(() => _replyToChoice = value ?? 'club_email'),
        ),
        if (_replyToChoice == 'custom')
          TextField(
            controller: _communicationReplyToEmail,
            autofillHints: const [AutofillHints.email],
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Custom reply-to email',
            ),
          ),
      ],
    ],
  );

  Future<void> _startStripeConnectOnboarding() async {
    final clubId = _provisionedClubId;
    if (clubId == null || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final response = await _supabase.functions.invoke(
        'stripe-club-connect-start-onboarding',
        body: {'club_id': clubId, 'return_url': Uri.base.toString()},
      );
      final data = response.data;
      final url = data is Map ? data['url']?.toString() : null;
      if (url == null || url.isEmpty) {
        throw Exception('Stripe did not return a connection link.');
      }
      final launched = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!launched) throw Exception('Unable to open Stripe Connect.');
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Unable to start Stripe Connect: $error');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _startSquareConnectOnboarding() async {
    final clubId = _provisionedClubId;
    if (clubId == null || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final response = await _supabase.functions.invoke(
        'square-club-connect-start',
        body: {'club_id': clubId},
      );
      final data = response.data;
      final url = data is Map ? data['authorization_url']?.toString() : null;
      if (url == null || url.isEmpty) {
        throw Exception('Square did not return a connection link.');
      }
      final launched = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!launched) throw Exception('Unable to open Square.');
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Unable to start Square connection: $error');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _activationScreen() => Scaffold(
    appBar: AppBar(title: const Text('Your Club Is Ready')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Icon(Icons.celebration_outlined, size: 56),
        const SizedBox(height: 16),
        Text(
          _clubName.text.trim().isEmpty
              ? 'Your club is activated'
              : _clubName.text.trim(),
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const Text(
          'RingMaster has activated your club and applied the plan and services in your purchase.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        if (_paymentProvider == 'stripe')
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Connect Stripe',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Complete Stripe Connect now to accept online membership payments.',
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: _saving ? null : _startStripeConnectOnboarding,
                    icon: const Icon(Icons.account_balance_wallet_outlined),
                    label: Text(_saving ? 'Opening Stripe…' : 'Connect Stripe'),
                  ),
                ],
              ),
            ),
          )
        else if (_paymentProvider == 'square')
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Connect Square',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Authorize Square now to accept online membership payments.',
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: _saving ? null : _startSquareConnectOnboarding,
                    icon: const Icon(Icons.account_balance_wallet_outlined),
                    label: Text(_saving ? 'Opening Square…' : 'Connect Square'),
                  ),
                ],
              ),
            ),
          )
        else if (_paymentProvider == 'paypal')
          const _ConnectionQueuedCard(
            provider: 'PayPal',
            message:
                'Your PayPal preference is recorded. PayPal connection for RingMaster Club is coming soon.',
          )
        else
          const _ConnectionQueuedCard(
            provider: 'Online payments',
            message:
                'You can connect a payment provider later from Billing & Add-ons.',
          ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    ),
  );

  Widget _importsStep() => _StepContent(
    title: 'Plan your reviewed imports',
    description:
        'Nothing is imported automatically. You will map each file, preview the resulting records, and approve it before it is applied.',
    children: [
      CheckboxListTile(
        value: _memberImport,
        onChanged: (value) => setState(() => _memberImport = value ?? false),
        title: const Text('I have a membership roster to import'),
        subtitle: const Text(
          'CSV or Excel; you will map fields, membership types, and duplicates.',
        ),
      ),
      if (_sweepstakes)
        CheckboxListTile(
          value: _sweepstakesImport,
          onChanged: (value) =>
              setState(() => _sweepstakesImport = value ?? false),
          title: const Text('I have historical sweepstakes reports'),
          subtitle: const Text(
            'Each report package remains in review until your show rules and parsed results are confirmed.',
          ),
        ),
      if (_memberImport)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: _rosterPreview?['has_preview'] == true
                ? _RosterPreviewSummary(
                    preview: _rosterPreview!,
                    showRows: true,
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Upload your membership roster to create the review preview.',
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: _saving ? null : _pickRoster,
                        icon: const Icon(Icons.upload_file_outlined),
                        label: const Text('Upload CSV roster'),
                      ),
                    ],
                  ),
          ),
        ),
      const Card(
        child: Padding(
          padding: EdgeInsets.all(14),
          child: Text(
            'Roster uploads are staged only for review. Nothing is imported until RingMaster and your club confirm the resulting records.',
          ),
        ),
      ),
    ],
  );

  Widget _reviewStep() => _StepContent(
    title: 'Review before activation',
    description:
        'Submitting sends this draft to RingMaster for a final accuracy review. Nothing becomes public or billable until that review is approved.',
    children: [
      _ReviewLine(
        'Club',
        _clubName.text.trim().isEmpty
            ? 'Missing club name'
            : _clubName.text.trim(),
      ),
      _ReviewLine('Club account email', _email),
      _ReviewLine('Club type', _clubType),
      _ReviewLine('Species scope', _speciesScope),
      _ReviewLine(
        'Public profile',
        _publicProfile ? 'Enabled' : 'Private until enabled later',
      ),
      _ReviewLine(
        'Officers',
        _enteredOfficers.isEmpty
            ? 'None added yet'
            : '${_enteredOfficers.length} added',
      ),
      _ReviewLine(
        'Treasurer',
        _treasurerName.text.trim().isEmpty
            ? 'Not provided'
            : _treasurerName.text.trim(),
      ),
      _ReviewLine(
        'Payments',
        _paymentProvider == 'not_ready'
            ? 'Online payments not enabled yet'
            : _paymentProvider,
      ),
      if (_membership)
        _ReviewLine(
          'Membership rules',
          '${_requireArbaNumber ? 'ARBA number required' : 'ARBA number optional'} · ${_requireMembershipApproval ? 'approval required' : 'automatic approval'} · ${_allowAutoRenew ? 'auto-renew enabled' : 'manual renewal'}',
        ),
      _ReviewLine('Imports', _importsSummary),
    ],
  );
}

class _RosterPreviewSummary extends StatelessWidget {
  const _RosterPreviewSummary({required this.preview, required this.showRows});
  final Map<String, dynamic> preview;
  final bool showRows;

  @override
  Widget build(BuildContext context) {
    final rows = (preview['rows'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Roster preview: ${preview['file_name']}',
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          '${preview['total_rows'] ?? 0} rows · ${preview['valid_rows'] ?? 0} ready · ${preview['error_rows'] ?? 0} need attention',
        ),
        if (showRows && rows.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text(
            'First 10 proposed members',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          ...rows.take(10).map((row) {
            final member = Map<String, dynamic>.from(
              row['proposed_member'] as Map? ?? const {},
            );
            final errors = (row['errors'] as List? ?? const []).join(' · ');
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Row ${row['row_number']}: ${[member['first_name'], member['last_name']].whereType<String>().where((value) => value.isNotEmpty).join(' ')}${member['email']?.toString().isEmpty == false ? ' · ${member['email']}' : ''}${errors.isNotEmpty ? ' — $errors' : ''}',
              ),
            );
          }),
        ],
      ],
    );
  }
}

class _StepContent extends StatelessWidget {
  const _StepContent({
    required this.title,
    required this.description,
    required this.children,
  });
  final String title;
  final String description;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 820),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        Text(description),
        const SizedBox(height: 16),
        ...children.map(
          (child) =>
              Padding(padding: const EdgeInsets.only(bottom: 12), child: child),
        ),
      ],
    ),
  );
}

class _PurchasedServiceRow extends StatelessWidget {
  const _PurchasedServiceRow({required this.label, this.value, this.included});

  final String label;
  final String? value;
  final bool? included;

  @override
  Widget build(BuildContext context) {
    final isIncluded = included ?? true;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(
            isIncluded
                ? Icons.check_circle_outline
                : Icons.remove_circle_outline,
            size: 18,
            color: isIncluded
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
          Text(value ?? (isIncluded ? 'Included' : 'Not included')),
        ],
      ),
    );
  }
}

class _ConnectionQueuedCard extends StatelessWidget {
  const _ConnectionQueuedCard({required this.provider, required this.message});

  final String provider;
  final String message;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            provider,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(message),
        ],
      ),
    ),
  );
}

class _ReviewLine extends StatelessWidget {
  const _ReviewLine(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(label),
    subtitle: Text(value),
    leading: const Icon(Icons.check_circle_outline),
  );
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => TextFormField(
    initialValue: '$value',
    keyboardType: TextInputType.number,
    decoration: InputDecoration(labelText: label),
    onChanged: (text) {
      final parsed = int.tryParse(text);
      if (parsed != null && parsed >= 0) onChanged(parsed);
    },
  );
}

class _UsState {
  const _UsState(this.code, this.name);
  final String code;
  final String name;
}

const _usStates = <_UsState>[
  _UsState('AL', 'Alabama'),
  _UsState('AK', 'Alaska'),
  _UsState('AZ', 'Arizona'),
  _UsState('AR', 'Arkansas'),
  _UsState('CA', 'California'),
  _UsState('CO', 'Colorado'),
  _UsState('CT', 'Connecticut'),
  _UsState('DE', 'Delaware'),
  _UsState('FL', 'Florida'),
  _UsState('GA', 'Georgia'),
  _UsState('HI', 'Hawaii'),
  _UsState('ID', 'Idaho'),
  _UsState('IL', 'Illinois'),
  _UsState('IN', 'Indiana'),
  _UsState('IA', 'Iowa'),
  _UsState('KS', 'Kansas'),
  _UsState('KY', 'Kentucky'),
  _UsState('LA', 'Louisiana'),
  _UsState('ME', 'Maine'),
  _UsState('MD', 'Maryland'),
  _UsState('MA', 'Massachusetts'),
  _UsState('MI', 'Michigan'),
  _UsState('MN', 'Minnesota'),
  _UsState('MS', 'Mississippi'),
  _UsState('MO', 'Missouri'),
  _UsState('MT', 'Montana'),
  _UsState('NE', 'Nebraska'),
  _UsState('NV', 'Nevada'),
  _UsState('NH', 'New Hampshire'),
  _UsState('NJ', 'New Jersey'),
  _UsState('NM', 'New Mexico'),
  _UsState('NY', 'New York'),
  _UsState('NC', 'North Carolina'),
  _UsState('ND', 'North Dakota'),
  _UsState('OH', 'Ohio'),
  _UsState('OK', 'Oklahoma'),
  _UsState('OR', 'Oregon'),
  _UsState('PA', 'Pennsylvania'),
  _UsState('RI', 'Rhode Island'),
  _UsState('SC', 'South Carolina'),
  _UsState('SD', 'South Dakota'),
  _UsState('TN', 'Tennessee'),
  _UsState('TX', 'Texas'),
  _UsState('UT', 'Utah'),
  _UsState('VT', 'Vermont'),
  _UsState('VA', 'Virginia'),
  _UsState('WA', 'Washington'),
  _UsState('WV', 'West Virginia'),
  _UsState('WI', 'Wisconsin'),
  _UsState('WY', 'Wyoming'),
  _UsState('DC', 'District of Columbia'),
];

class _OfficerDraft {
  _OfficerDraft({
    String name = '',
    String email = '',
    String title = 'President',
    String access = 'club_admin',
  }) : name = TextEditingController(text: name),
       email = TextEditingController(text: email),
       title = TextEditingController(text: title),
       access = access;
  final TextEditingController name;
  final TextEditingController email;
  final TextEditingController title;
  String access;
  factory _OfficerDraft.fromJson(Map<String, dynamic> json) => _OfficerDraft(
    name: json['name']?.toString() ?? '',
    email: json['email']?.toString() ?? '',
    title: json['title']?.toString() ?? 'President',
    access: json['access_template']?.toString() ?? 'club_admin',
  );
  Map<String, dynamic> toJson() => {
    'name': name.text.trim(),
    'email': email.text.trim(),
    'title': title.text.trim(),
    'access_template': access,
  };
  void dispose() {
    name.dispose();
    email.dispose();
    title.dispose();
  }
}

class _OfficerCard extends StatelessWidget {
  const _OfficerCard({required this.officer, this.onRemove});
  final _OfficerDraft officer;
  final VoidCallback? onRemove;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: officer.name,
                  autofillHints: const [AutofillHints.name],
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: officer.email,
                  autofillHints: const [AutofillHints.email],
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
              ),
              if (onRemove != null)
                IconButton(
                  onPressed: onRemove,
                  tooltip: 'Remove director',
                  icon: const Icon(Icons.remove_circle_outline),
                ),
            ],
          ),
          const SizedBox(height: 12),
          InputDecorator(
            decoration: const InputDecoration(labelText: 'Office title'),
            child: Text(officer.title.text),
          ),
        ],
      ),
    ),
  );
}
