import 'package:flutter/material.dart';
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
  final _contactPhone = TextEditingController();
  final _address = TextEditingController();
  final _city = TextEditingController();
  final _state = TextEditingController();
  final _postalCode = TextEditingController();
  final _treasurerName = TextEditingController();
  final _treasurerEmail = TextEditingController();
  final _treasurerAddress = TextEditingController();
  final _officers = <_OfficerDraft>[];

  bool _loading = true;
  bool _saving = false;
  String? _error;
  String _email = '';
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
      _contactPhone,
      _address,
      _city,
      _state,
      _postalCode,
      _treasurerName,
      _treasurerEmail,
      _treasurerAddress,
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
      _onboardingStatus = data['status']?.toString() ?? 'in_progress';
      _provisionedClubId = data['provisioned_club_id']?.toString();
      _purchasedEntitlements = Map<String, dynamic>.from(
        data['purchased_entitlements'] as Map? ?? const {},
      );
      _restore(answers);
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
    _contactPhone.text = club['contact_phone']?.toString() ?? '';
    _address.text = club['address']?.toString() ?? '';
    _city.text = club['city']?.toString() ?? '';
    _state.text = club['state']?.toString() ?? '';
    _postalCode.text = club['postal_code']?.toString() ?? '';
    _treasurerName.text = treasurer['name']?.toString() ?? '';
    _treasurerEmail.text = treasurer['email']?.toString() ?? '';
    _treasurerAddress.text = treasurer['address']?.toString() ?? '';
    _membership = _hasPurchasedAddOn('membership_management');
    _sanctions = _hasPurchasedAddOn('sanction_requests');
    _events = _hasPurchasedAddOn('events_meetings');
    _sweepstakes = _hasPurchasedAddOn('sweepstakes');
    _onlinePayments = setup['online_payments'] == true;
    _mailedChecks = setup['mailed_checks'] != false;
    _paymentProvider = setup['payment_provider']?.toString() ?? 'not_ready';
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
      'website_url': _website.text.trim(),
      'contact_name': _contactName.text.trim(),
      'contact_email': _email,
      'contact_phone': _contactPhone.text.trim(),
      'address': _address.text.trim(),
      'city': _city.text.trim(),
      'state': _state.text.trim(),
      'postal_code': _postalCode.text.trim(),
      'country': 'US',
    },
    'treasurer': {
      'name': _treasurerName.text.trim(),
      'email': _treasurerEmail.text.trim(),
      'address': _treasurerAddress.text.trim(),
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
      TextField(
        controller: _website,
        autofillHints: const [AutofillHints.url],
        keyboardType: TextInputType.url,
        textInputAction: TextInputAction.next,
        onEditingComplete: () => FocusScope.of(context).nextFocus(),
        decoration: const InputDecoration(labelText: 'Website URL'),
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
        controller: _contactPhone,
        autofillHints: const [AutofillHints.telephoneNumber],
        keyboardType: TextInputType.phone,
        textInputAction: TextInputAction.next,
        onEditingComplete: () => FocusScope.of(context).nextFocus(),
        decoration: const InputDecoration(labelText: 'Contact phone'),
      ),
      TextField(
        controller: _address,
        autofillHints: const [AutofillHints.streetAddressLine1],
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.next,
        onEditingComplete: () => FocusScope.of(context).nextFocus(),
        decoration: const InputDecoration(labelText: 'Mailing address'),
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
        controller: _treasurerAddress,
        autofillHints: const [AutofillHints.fullStreetAddress],
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.next,
        onEditingComplete: () => FocusScope.of(context).nextFocus(),
        decoration: const InputDecoration(
          labelText: 'Treasurer / check-payment address',
        ),
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
            'Stripe Connect will open immediately after RingMaster activates your club. Square and PayPal are recorded for follow-up until their Club connection flows are available.',
          ),
        ),
      ),
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
          const _ConnectionQueuedCard(
            provider: 'Square',
            message:
                'Your Square preference is recorded. RingMaster will contact you when the Club Square connection is ready.',
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
      const Card(
        child: Padding(
          padding: EdgeInsets.all(14),
          child: Text(
            'Uploads are enabled after your club draft is approved so every file can be attached to the correct club workspace and reviewed safely.',
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
      _ReviewLine('Imports', _importsSummary),
    ],
  );
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
