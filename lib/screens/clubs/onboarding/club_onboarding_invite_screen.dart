import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  final _stripe = TextEditingController();
  final _square = TextEditingController();
  final _officers = <_OfficerDraft>[];

  bool _loading = true;
  bool _saving = false;
  String? _error;
  String _email = '';
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
      _stripe,
      _square,
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
    _membership = setup['membership_management'] != false;
    _sanctions = setup['sanctions'] == true;
    _events = setup['events'] == true;
    _sweepstakes = setup['sweepstakes'] == true;
    _onlinePayments = setup['online_payments'] == true;
    _mailedChecks = setup['mailed_checks'] != false;
    _paymentProvider = setup['payment_provider']?.toString() ?? 'not_ready';
    _stripe.text = setup['stripe_contact']?.toString() ?? '';
    _square.text = setup['square_contact']?.toString() ?? '';
    _memberImport = imports['membership_roster'] == true;
    _sweepstakesImport = imports['sweepstakes_archive'] == true;
    final savedOfficers = answers['officers'] as List? ?? const [];
    for (final item in savedOfficers.whereType<Map>()) {
      _officers.add(_OfficerDraft.fromJson(Map<String, dynamic>.from(item)));
    }
  }

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
    'officers': _officers.map((officer) => officer.toJson()).toList(),
    'setup': {
      'membership_management': _membership,
      'sanctions': _sanctions,
      'events': _events,
      'sweepstakes': _sweepstakes,
      'online_payments': _onlinePayments,
      'mailed_checks': _mailedChecks,
      'payment_provider': _paymentProvider,
      'stripe_contact': _stripe.text.trim(),
      'square_contact': _square.text.trim(),
      'paypal_requested': _paymentProvider == 'paypal_soon',
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
        decoration: const InputDecoration(labelText: 'Legal club name *'),
      ),
      TextField(
        controller: _shortName,
        decoration: const InputDecoration(
          labelText: 'Short name / abbreviation',
        ),
      ),
      TextField(
        controller: _website,
        decoration: const InputDecoration(labelText: 'Website URL'),
      ),
      TextField(
        controller: _contactName,
        decoration: const InputDecoration(labelText: 'Primary contact name'),
      ),
      TextField(
        controller: _contactPhone,
        decoration: const InputDecoration(labelText: 'Contact phone'),
      ),
      TextField(
        controller: _address,
        decoration: const InputDecoration(labelText: 'Mailing address'),
      ),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _city,
              decoration: const InputDecoration(labelText: 'City'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _state,
              decoration: const InputDecoration(labelText: 'State'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _postalCode,
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
        'Titles are what members see. The access template controls what each person can do and can be customized later.',
    children: [
      TextField(
        controller: _treasurerName,
        decoration: const InputDecoration(labelText: 'Treasurer name'),
      ),
      TextField(
        controller: _treasurerEmail,
        decoration: const InputDecoration(labelText: 'Treasurer email'),
      ),
      TextField(
        controller: _treasurerAddress,
        decoration: const InputDecoration(
          labelText: 'Treasurer / check-payment address',
        ),
      ),
      const SizedBox(height: 12),
      for (final officer in _officers)
        _OfficerCard(
          officer: officer,
          onRemove: () => setState(() {
            officer.dispose();
            _officers.remove(officer);
          }),
        ),
      OutlinedButton.icon(
        onPressed: () => setState(() => _officers.add(_OfficerDraft())),
        icon: const Icon(Icons.person_add_alt_1_outlined),
        label: const Text('Add President, Secretary, VP, or Director'),
      ),
    ],
  );

  Widget _setupStep() => _StepContent(
    title: 'Choose services and payment setup',
    description:
        'Online payments make renewal and dues processing easier. Stripe and Square are available now; PayPal is being prepared.',
    children: [
      SwitchListTile(
        value: _membership,
        onChanged: (value) => setState(() => _membership = value),
        title: const Text('Membership management'),
      ),
      SwitchListTile(
        value: _sanctions,
        onChanged: (value) => setState(() => _sanctions = value),
        title: const Text('Sanction requests'),
      ),
      SwitchListTile(
        value: _events,
        onChanged: (value) => setState(() => _events = value),
        title: const Text('Events & meetings'),
      ),
      SwitchListTile(
        value: _sweepstakes,
        onChanged: (value) => setState(() => _sweepstakes = value),
        title: const Text('Sweepstakes'),
      ),
      const Divider(),
      SwitchListTile(
        value: _onlinePayments,
        onChanged: (value) => setState(() => _onlinePayments = value),
        title: const Text('Accept online membership payments'),
      ),
      SwitchListTile(
        value: _mailedChecks,
        onChanged: (value) => setState(() => _mailedChecks = value),
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
            value: 'paypal_soon',
            child: Text('PayPal — coming soon'),
          ),
        ],
        onChanged: (value) {
          if (value != null) setState(() => _paymentProvider = value);
        },
      ),
      if (_paymentProvider == 'stripe')
        TextField(
          controller: _stripe,
          decoration: const InputDecoration(
            labelText: 'Stripe setup contact / notes',
          ),
        ),
      if (_paymentProvider == 'square')
        TextField(
          controller: _square,
          decoration: const InputDecoration(
            labelText: 'Square setup contact / notes',
          ),
        ),
      const Card(
        child: Padding(
          padding: EdgeInsets.all(14),
          child: Text(
            'Default membership plan: Individual \$10, Family \$15, and Youth \$5. You will review and adjust all plans before activation.',
          ),
        ),
      ),
    ],
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
        _officers.isEmpty ? 'None added yet' : '${_officers.length} added',
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
  const _OfficerCard({required this.officer, required this.onRemove});
  final _OfficerDraft officer;
  final VoidCallback onRemove;
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
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: officer.email,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
              ),
              IconButton(
                onPressed: onRemove,
                tooltip: 'Remove officer',
                icon: const Icon(Icons.remove_circle_outline),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: officer.title,
                  decoration: const InputDecoration(labelText: 'Office title'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: officer.access,
                  decoration: const InputDecoration(
                    labelText: 'Access template',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'club_admin',
                      child: Text('Club Administrator'),
                    ),
                    DropdownMenuItem(
                      value: 'treasurer',
                      child: Text('Treasurer'),
                    ),
                    DropdownMenuItem(
                      value: 'sanctions_sweepstakes_secretary',
                      child: Text('Sanction & Sweepstakes Secretary'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) officer.access = value;
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
