// lib/screens/clubs/member/club_membership_apply_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/clubs/club_summary.dart';
import '../../../services/clubs/club_service.dart';

class ClubMembershipApplyScreen extends StatefulWidget {
  const ClubMembershipApplyScreen({super.key, required this.club});

  final ClubSummary club;

  @override
  State<ClubMembershipApplyScreen> createState() =>
      _ClubMembershipApplyScreenState();
}

class _ClubMembershipApplyScreenState extends State<ClubMembershipApplyScreen> {
  final _formKey = GlobalKey<FormState>();
  final _clubService = ClubService();
  final _supabase = Supabase.instance.client;

  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _showingNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressLine1Controller = TextEditingController();
  final _addressLine2Controller = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _postalCodeController = TextEditingController();
  final _dateOfBirthController = TextEditingController();
  final _arbaNumberController = TextEditingController();
  final _countryController = TextEditingController(text: 'US');
  final _notesController = TextEditingController();

  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _acceptsOnlinePayments = false;
  String? _errorMessage;
  String? _successMessage;
  _MembershipTypeOption? _selectedType;
  List<_MembershipTypeOption> _membershipTypes = const [];
  List<Map<String, dynamic>> _linkedExhibitors = const [];
  Map<String, dynamic>? _selectedLinkedExhibitor;
  final Set<String> _selectedAdditionalExhibitorIds = <String>{};
  bool _autoRenewEnabled = false;
  bool _showingNameTouched = false;
  bool _isWiringShowingName = false;
  bool _prefilledFromSavedAccount = false;
  String? _prefillSourceLabel;

  @override
  void initState() {
    super.initState();
    _emailController.text = _supabase.auth.currentUser?.email ?? '';
    _wireAutofillShowingName();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadFormData());
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _showingNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressLine1Controller.dispose();
    _addressLine2Controller.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _postalCodeController.dispose();
    _dateOfBirthController.dispose();
    _arbaNumberController.dispose();
    _countryController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _wireAutofillShowingName() {
    void recompute() {
      if (_showingNameTouched) return;
      _recomputeShowingName();
    }

    _firstNameController.addListener(recompute);
    _lastNameController.addListener(recompute);

    _showingNameController.addListener(() {
      if (_isWiringShowingName) return;
      final expected = _buildAutoShowingName();
      if (_showingNameController.text.trim() != expected.trim()) {
        _showingNameTouched = true;
      }
    });
  }

  void _recomputeShowingName() {
    if (_showingNameTouched) return;

    final value = _buildAutoShowingName();

    _isWiringShowingName = true;
    _showingNameController.text = value;
    _showingNameController.selection = TextSelection.fromPosition(
      TextPosition(offset: _showingNameController.text.length),
    );
    _isWiringShowingName = false;
  }

  String _buildAutoShowingName() {
    return _joinNameParts(
      _firstNameController.text,
      _lastNameController.text,
    );
  }

  Future<void> _prefillFromSavedAccount() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    List<Map<String, dynamic>> exhibitors = const [];
    try {
      final rows = await _supabase
          .from('exhibitors')
          .select(
            'id,account_type,display_name,showing_name,first_name,last_name,email,phone,address_line1,address_line2,city,state,zip,birth_date,arba_number,is_primary,is_active,imported_from,created_at',
          )
          .eq('owner_user_id', user.id)
          .eq('is_active', true)
          .order('created_at', ascending: true);

      exhibitors = rows
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      _linkedExhibitors = exhibitors;
    } catch (_) {
      exhibitors = const [];
    }

    final primaryExhibitor = _pickBestExhibitorForPrefill(exhibitors);

    if (primaryExhibitor == null) {
      _prefillFromAuthUser(user);
      return;
    }

    _selectedLinkedExhibitor = primaryExhibitor;

    _setTextIfEmpty(
      _firstNameController,
      primaryExhibitor['first_name']?.toString() ?? '',
    );
    _setTextIfEmpty(
      _lastNameController,
      primaryExhibitor['last_name']?.toString() ?? '',
    );

    final savedShowingName = _bestShowingNameForExhibitor(primaryExhibitor);
    if (_showingNameController.text.trim().isEmpty &&
        savedShowingName.isNotEmpty) {
      _setShowingNameProgrammatically(savedShowingName);
      _showingNameTouched = savedShowingName != _buildAutoShowingName();
    }

    _setTextIfEmpty(
      _emailController,
      primaryExhibitor['email']?.toString() ?? user.email ?? '',
    );
    _setTextIfEmpty(
      _phoneController,
      primaryExhibitor['phone']?.toString() ?? '',
    );
    _setTextIfEmpty(
      _addressLine1Controller,
      primaryExhibitor['address_line1']?.toString() ?? '',
    );
    _setTextIfEmpty(
      _addressLine2Controller,
      primaryExhibitor['address_line2']?.toString() ?? '',
    );
    _setTextIfEmpty(
      _cityController,
      primaryExhibitor['city']?.toString() ?? '',
    );
    _setTextIfEmpty(
      _stateController,
      primaryExhibitor['state']?.toString() ?? '',
    );
    _setTextIfEmpty(
      _postalCodeController,
      primaryExhibitor['zip']?.toString() ?? '',
    );
    _setTextIfEmpty(
      _dateOfBirthController,
      _formatDateForInput(primaryExhibitor['birth_date']),
    );
    _setTextIfEmpty(
      _arbaNumberController,
      primaryExhibitor['arba_number']?.toString() ?? '',
    );

    _prefilledFromSavedAccount = true;
    _prefillSourceLabel = _bestShowingNameForExhibitor(primaryExhibitor);
  }

  void _prefillFromAuthUser(User user) {
    final metadata = user.userMetadata ?? const <String, dynamic>{};
    final fullName = _firstNonEmpty([
      metadata['full_name']?.toString(),
      metadata['name']?.toString(),
      metadata['display_name']?.toString(),
    ]);

    if (fullName != null) {
      final parts = _splitFullName(fullName);
      _setTextIfEmpty(_firstNameController, parts.$1);
      _setTextIfEmpty(_lastNameController, parts.$2);
    }

    _setTextIfEmpty(_emailController, user.email ?? '');

    if (!_showingNameTouched && _showingNameController.text.trim().isEmpty) {
      _setShowingNameProgrammatically(_buildAutoShowingName());
    }
  }

  Map<String, dynamic>? _pickBestExhibitorForPrefill(
    List<Map<String, dynamic>> exhibitors,
  ) {
    if (exhibitors.isEmpty) return null;

    for (final exhibitor in exhibitors) {
      if (exhibitor['is_primary'] == true) return exhibitor;
    }

    for (final exhibitor in exhibitors) {
      final type = _accountTypeFor(exhibitor);
      if (type == 'adult') return exhibitor;
    }

    for (final exhibitor in exhibitors) {
      final type = _accountTypeFor(exhibitor);
      if (type != 'group') return exhibitor;
    }

    return exhibitors.first;
  }

  String _bestShowingNameForExhibitor(Map<String, dynamic> exhibitor) {
    final savedShowingName = _firstNonEmpty([
      exhibitor['showing_name']?.toString(),
      exhibitor['display_name']?.toString(),
    ]);

    if (savedShowingName != null) return savedShowingName;

    return _joinNameParts(
      exhibitor['first_name']?.toString(),
      exhibitor['last_name']?.toString(),
    );
  }

  String _accountTypeFor(Map<String, dynamic> exhibitor) {
    return exhibitor['account_type']?.toString().toLowerCase().trim() ?? '';
  }

  void _applyLinkedExhibitor(Map<String, dynamic> exhibitor) {
    setState(() {
      _selectedLinkedExhibitor = exhibitor;
      _selectedAdditionalExhibitorIds.remove(exhibitor['id']?.toString());
      _prefilledFromSavedAccount = true;
      _prefillSourceLabel = _bestShowingNameForExhibitor(exhibitor);
      _showingNameTouched = false;

      _firstNameController.text = exhibitor['first_name']?.toString() ?? '';
      _lastNameController.text = exhibitor['last_name']?.toString() ?? '';

      final showingName = _bestShowingNameForExhibitor(exhibitor);
      if (showingName.isNotEmpty) {
        _setShowingNameProgrammatically(showingName);
        _showingNameTouched = showingName != _buildAutoShowingName();
      } else {
        _setShowingNameProgrammatically(_buildAutoShowingName());
      }

      _emailController.text = exhibitor['email']?.toString() ??
          _supabase.auth.currentUser?.email ??
          '';
      _phoneController.text = exhibitor['phone']?.toString() ?? '';
      _addressLine1Controller.text =
          exhibitor['address_line1']?.toString() ?? '';
      _addressLine2Controller.text =
          exhibitor['address_line2']?.toString() ?? '';
      _cityController.text = exhibitor['city']?.toString() ?? '';
      _stateController.text = exhibitor['state']?.toString() ?? '';
      _postalCodeController.text = exhibitor['zip']?.toString() ?? '';
      _dateOfBirthController.text = _formatDateForInput(
        exhibitor['birth_date'],
      );
      _arbaNumberController.text = exhibitor['arba_number']?.toString() ?? '';
    });
  }

  void _startAdditionalName() {
    setState(() {
      _selectedLinkedExhibitor = null;
      _selectedAdditionalExhibitorIds.clear();
      _prefilledFromSavedAccount = false;
      _prefillSourceLabel = null;
      _showingNameTouched = false;

      _firstNameController.clear();
      _lastNameController.clear();
      _setShowingNameProgrammatically('');
      _showingNameController.clear();
      _phoneController.clear();
      _dateOfBirthController.clear();
      _arbaNumberController.clear();
      _notesController.clear();

      // Keep shared contact/address defaults from the signed-in account.
      final selected = _pickBestExhibitorForPrefill(_linkedExhibitors);
      if (selected != null) {
        _emailController.text = selected['email']?.toString() ??
            _supabase.auth.currentUser?.email ??
            '';
        _addressLine1Controller.text =
            selected['address_line1']?.toString() ?? '';
        _addressLine2Controller.text =
            selected['address_line2']?.toString() ?? '';
        _cityController.text = selected['city']?.toString() ?? '';
        _stateController.text = selected['state']?.toString() ?? '';
        _postalCodeController.text = selected['zip']?.toString() ?? '';
      } else {
        _emailController.text = _supabase.auth.currentUser?.email ?? '';
        _addressLine1Controller.clear();
        _addressLine2Controller.clear();
        _cityController.clear();
        _stateController.clear();
        _postalCodeController.clear();
      }
    });
  }

  void _toggleAdditionalLinkedExhibitor(
    Map<String, dynamic> exhibitor,
    bool selected,
  ) {
    final id = exhibitor['id']?.toString();
    if (id == null || id.isEmpty) return;

    setState(() {
      if (selected) {
        if (_selectedLinkedExhibitor?['id']?.toString() != id) {
          _selectedAdditionalExhibitorIds.add(id);
        }
      } else {
        _selectedAdditionalExhibitorIds.remove(id);
      }
    });
  }

  List<Map<String, dynamic>> get _additionalLinkedExhibitors {
    return _linkedExhibitors
        .where(
          (exhibitor) => _selectedAdditionalExhibitorIds.contains(
            exhibitor['id']?.toString(),
          ),
        )
        .toList();
  }

  List<Map<String, dynamic>> get _availableAdditionalLinkedExhibitors {
    final selectedPrimaryId = _selectedLinkedExhibitor?['id']?.toString();
    return _linkedExhibitors
        .where((exhibitor) => exhibitor['id']?.toString() != selectedPrimaryId)
        .toList();
  }

  String _additionalLinkedPeopleSummary() {
    final selected = _additionalLinkedExhibitors;
    if (selected.isEmpty) return '';

    return selected
        .map((exhibitor) {
          final name = _bestShowingNameForExhibitor(exhibitor);
          final type = _accountTypeFor(exhibitor);
          final dob = _formatDateForInput(exhibitor['birth_date']);
          final parts = <String>[];
          if (name.isNotEmpty) parts.add(name);
          if (type.isNotEmpty) parts.add(_titleCase(type));
          if (dob.isNotEmpty) parts.add('DOB $dob');
          return parts.isEmpty ? 'Linked account' : parts.join(' • ');
        })
        .join('\n');
  }

  String? _combinedNotesForSubmission() {
    final notes = _notesController.text.trim();
    final additionalPeople = _additionalLinkedPeopleSummary();

    if (additionalPeople.isEmpty) return _emptyToNull(notes);

    final buffer = StringBuffer();
    if (notes.isNotEmpty) {
      buffer.writeln(notes);
      buffer.writeln();
    }
    buffer.writeln('Additional linked people included on this application:');
    buffer.write(additionalPeople);

    return buffer.toString().trim();
  }

  void _setShowingNameProgrammatically(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;

    _isWiringShowingName = true;
    _showingNameController.text = trimmed;
    _showingNameController.selection = TextSelection.fromPosition(
      TextPosition(offset: _showingNameController.text.length),
    );
    _isWiringShowingName = false;
  }

  String? _firstNonEmpty(List<String?> values) {
    for (final value in values) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    }
    return null;
  }

  (String, String) _splitFullName(String value) {
    final parts = value
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.trim().isNotEmpty)
        .toList();

    if (parts.isEmpty) return ('', '');
    if (parts.length == 1) return (parts.first, '');

    return (parts.first, parts.sublist(1).join(' '));
  }

  String _joinNameParts(String? firstName, String? lastName) {
    return [firstName, lastName]
        .map((part) => part?.trim() ?? '')
        .where((part) => part.isNotEmpty)
        .join(' ')
        .trim();
  }

  String _linkedExhibitorLabel(Map<String, dynamic> exhibitor) {
    final name = _bestShowingNameForExhibitor(exhibitor);
    final type = _accountTypeFor(exhibitor);

    final parts = <String>[];
    if (type.isNotEmpty) parts.add(_titleCase(type));
    if (exhibitor['is_primary'] == true) parts.add('Primary');

    if (parts.isEmpty) return name.isEmpty ? 'Linked account' : name;
    return '${name.isEmpty ? 'Linked account' : name} • ${parts.join(' • ')}';
  }

  String _titleCase(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return trimmed;
    return trimmed
        .split(RegExp(r'[_\s-]+'))
        .where((part) => part.isNotEmpty)
        .map((part) => part[0].toUpperCase() + part.substring(1).toLowerCase())
        .join(' ');
  }

  Future<void> _pickDateOfBirth() async {
    final now = DateTime.now();
    final current = DateTime.tryParse(_dateOfBirthController.text);
    final initialDate = current ?? DateTime(now.year - 18, now.month, now.day);

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate.isAfter(now) ? now : initialDate,
      firstDate: DateTime(1900),
      lastDate: now,
    );

    if (picked == null) return;

    setState(() {
      _dateOfBirthController.text = _formatDateForInput(picked);
    });
  }

  String _formatDateForInput(dynamic value) {
    if (value == null) return '';
    final text = value.toString().trim();
    if (text.isEmpty) return '';

    final parsed = value is DateTime ? value : DateTime.tryParse(text);
    if (parsed == null) return text.length >= 10 ? text.substring(0, 10) : text;

    final month = parsed.month.toString().padLeft(2, '0');
    final day = parsed.day.toString().padLeft(2, '0');
    return '${parsed.year}-$month-$day';
  }

  void _setTextIfEmpty(TextEditingController controller, String value) {
    if (controller.text.trim().isNotEmpty) return;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    controller.text = trimmed;
  }

  Future<void> _loadFormData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final clubResponse = await _supabase
          .from('clubs')
          .select('accepts_member_online_payments')
          .eq('id', widget.club.clubId)
          .single();

      final typeResponse = await _supabase
          .from('club_membership_types')
          .select(
            'id,name,description,price,currency,allow_auto_renew,is_public,is_active,sort_order,requires_approval,require_arba_number,term_months,term_type,minimum_age,maximum_age,membership_scope,settings',
          )
          .eq('club_id', widget.club.clubId)
          .eq('is_active', true)
          .eq('is_public', true)
          .order('sort_order', ascending: true)
          .order('name', ascending: true);

      final types = (typeResponse as List)
          .whereType<Map>()
          .map((row) => _MembershipTypeOption.fromJson(row))
          .toList();

      await _prefillFromSavedAccount();

      if (!mounted) return;

      setState(() {
        _acceptsOnlinePayments =
            clubResponse['accepts_member_online_payments'] == true;
        _membershipTypes = types;
        _selectedType = types.isEmpty ? null : types.first;
        _autoRenewEnabled = _selectedType?.allowAutoRenew == true;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _submitApplication() async {
    final selectedType = _selectedType;
    if (selectedType == null) {
      setState(() {
        _errorMessage = 'Choose a membership type to continue.';
      });
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    final ageError = _selectedTypeAgeError(selectedType);
    if (ageError != null) {
      setState(() {
        _errorMessage = ageError;
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final user = _supabase.auth.currentUser;
      final autoRenew = _autoRenewEnabled && selectedType.allowAutoRenew;
      final now = DateTime.now().toIso8601String();
      final checkoutAmountCents = _checkoutAmountCents;

      final membershipResponse = await _supabase
          .from('club_memberships')
          .insert({
            'club_id': widget.club.clubId,
            'user_id': user?.id,
            'membership_type_id': selectedType.id,
            'first_name': _firstNameController.text.trim(),
            'last_name': _lastNameController.text.trim(),
            'showing_name': _emptyToNull(_showingNameController.text),
            'email': _emptyToNull(_emailController.text),
            'phone': _emptyToNull(_phoneController.text),
            'address_line1': _emptyToNull(_addressLine1Controller.text),
            'address_line2': _emptyToNull(_addressLine2Controller.text),
            'city': _emptyToNull(_cityController.text),
            'state': _emptyToNull(_stateController.text),
            'postal_code': _emptyToNull(_postalCodeController.text),
            'date_of_birth': _emptyToNull(_dateOfBirthController.text),
            'arba_number': _emptyToNull(_arbaNumberController.text),
            'country': _countryController.text.trim().isEmpty
                ? 'US'
                : _countryController.text.trim(),
            'status': 'pending',
            'source': 'ringmaster',
            'notes': _combinedNotesForSubmission(),
            'auto_renew': autoRenew,
            'auto_renew_enabled': autoRenew,
            'auto_renew_opted_in_at': autoRenew ? now : null,
          })
          .select('id')
          .single();

      final membershipId = membershipResponse['id']?.toString();
      if (membershipId == null || membershipId.isEmpty) {
        throw Exception('Membership application was created without an ID.');
      }

      if (checkoutAmountCents > 0 && _acceptsOnlinePayments) {
        await _clubService.startMemberCheckout(
          clubId: widget.club.clubId,
          sourceType: 'membership_due',
          sourceId: membershipId,
          amountCents: checkoutAmountCents,
          description: '${selectedType.name} membership application',
        );

        if (!mounted) return;
        setState(() {
          _successMessage =
              'Your application was started. Complete Stripe Checkout to finish payment.';
        });
      } else if (checkoutAmountCents > 0) {
        if (!mounted) return;
        setState(() {
          _successMessage =
              'Your application was submitted. This club is not currently accepting online membership payments, so payment will be handled by the club.';
        });
      } else {
        if (!mounted) return;
        setState(() {
          _successMessage = 'Your membership application was submitted.';
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  String? _selectedTypeAgeError(_MembershipTypeOption selectedType) {
    if (!selectedType.hasAgeLimit) return null;

    final birthDate = DateTime.tryParse(_dateOfBirthController.text.trim());
    if (birthDate == null) {
      return 'Date of birth is required for ${selectedType.name} membership.';
    }

    final age = _ageOnDate(birthDate, DateTime.now());

    if (selectedType.minimumAge != null && age < selectedType.minimumAge!) {
      return '${selectedType.name} membership requires the applicant to be at least ${selectedType.minimumAge} years old.';
    }

    if (selectedType.maximumAge != null && age > selectedType.maximumAge!) {
      return '${selectedType.name} membership is limited to applicants age ${selectedType.maximumAge} or younger.';
    }

    return null;
  }

  int _ageOnDate(DateTime birthDate, DateTime onDate) {
    var age = onDate.year - birthDate.year;
    final hasHadBirthdayThisYear = onDate.month > birthDate.month ||
        (onDate.month == birthDate.month && onDate.day >= birthDate.day);

    if (!hasHadBirthdayThisYear) age--;
    return age;
  }

  int get _checkoutAmountCents {
    final selectedType = _selectedType;
    if (selectedType == null) return 0;
    return selectedType.amountCents + _familyAdditionalYouthTotalCents;
  }

  int get _familyAdditionalYouthTotalCents {
    final selectedType = _selectedType;
    if (selectedType == null || selectedType.membershipScope != 'family') {
      return 0;
    }

    final extraYouthCount = _familyExtraYouthCount;
    if (extraYouthCount <= 0) return 0;

    return extraYouthCount * selectedType.familyAdditionalYouthPriceCents;
  }

  int get _familyExtraYouthCount {
    final selectedType = _selectedType;
    if (selectedType == null || selectedType.membershipScope != 'family') {
      return 0;
    }

    final includedYouth = selectedType.familyIncludedYouth;
    final youthCount = _selectedFamilyYouthCount;
    return youthCount > includedYouth ? youthCount - includedYouth : 0;
  }

  int get _selectedFamilyYouthCount {
    final people = <Map<String, dynamic>>[
      ?_selectedLinkedExhibitor,
      ..._additionalLinkedExhibitors,
    ];

    return people.where(_isYouthExhibitor).length;
  }

  bool _isYouthExhibitor(Map<String, dynamic> exhibitor) {
    final type = _accountTypeFor(exhibitor);
    if (type == 'youth') return true;

    final birthDate = DateTime.tryParse(
      _formatDateForInput(exhibitor['birth_date']),
    );
    final maximumAge = _selectedType?.maximumAge;

    if (birthDate == null || maximumAge == null) return false;
    return _ageOnDate(birthDate, DateTime.now()) <= maximumAge;
  }

  String _moneyLabel(int cents, String currency) {
    if (cents <= 0) return 'Free';

    final amount = cents / 100;
    final symbol = currency.toUpperCase() == 'USD' ? r'$' : '';
    return '$symbol${amount.toStringAsFixed(2)} ${currency.toUpperCase()}'.trim();
  }

  String? get _familyPriceMessage {
    final selectedType = _selectedType;
    if (selectedType == null || selectedType.membershipScope != 'family') {
      return null;
    }

    final extraYouthCount = _familyExtraYouthCount;
    if (extraYouthCount <= 0) {
      return 'Family base price includes ${selectedType.familyIncludedAdults} adult(s) and ${selectedType.familyIncludedYouth} youth.';
    }

    final extraYouthTotal = _familyAdditionalYouthTotalCents;
    return 'Family total includes $extraYouthCount additional youth at ${_moneyLabel(selectedType.familyAdditionalYouthPriceCents, selectedType.currency)} each (${_moneyLabel(extraYouthTotal, selectedType.currency)} added).';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Apply for Membership'),
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null && _membershipTypes.isEmpty) {
      return _MessageState(
        icon: Icons.error_outline,
        title: 'Unable to load membership form',
        message: _errorMessage!,
        actionLabel: 'Try again',
        onAction: _loadFormData,
      );
    }

    if (_membershipTypes.isEmpty) {
      return _MessageState(
        icon: Icons.card_membership_outlined,
        title: 'No public memberships available',
        message:
            'This club does not currently have any public membership types available.',
        actionLabel: 'Refresh',
        onAction: _loadFormData,
      );
    }

    return SafeArea(
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              widget.club.clubName,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'Choose a membership type and submit your information. Applications may require club approval.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            if (_errorMessage != null) ...[
              _InlineMessage(
                icon: Icons.error_outline,
                message: _errorMessage!,
                isError: true,
              ),
              const SizedBox(height: 14),
            ],
            if (_successMessage != null) ...[
              _InlineMessage(
                icon: Icons.check_circle_outline,
                message: _successMessage!,
                isError: false,
              ),
              const SizedBox(height: 14),
            ],
            if (_prefilledFromSavedAccount) ...[
              _InlineMessage(
                icon: Icons.person_search_outlined,
                message: _prefillSourceLabel == null ||
                        _prefillSourceLabel!.trim().isEmpty
                    ? 'We prefilled this form from your saved RingMaster account information.'
                    : 'We prefilled this form from your saved RingMaster account information for $_prefillSourceLabel.',
                isError: false,
              ),
              const SizedBox(height: 14),
            ],
            const _SectionTitle(title: 'Membership Type'),
            const SizedBox(height: 8),
            ..._membershipTypes.map(_membershipTypeTile),
            const SizedBox(height: 20),
            const _SectionTitle(title: 'Applicant Information'),
            const SizedBox(height: 12),
            if (_linkedExhibitors.isNotEmpty) ...[
              DropdownButtonFormField<String>(
                initialValue: _selectedLinkedExhibitor?['id']?.toString(),
                decoration: const InputDecoration(
                  labelText: 'Use linked account',
                  helperText:
                      'Choose a saved RingMaster account or enter another person.',
                ),
                items: [
                  ..._linkedExhibitors.map(
                    (exhibitor) => DropdownMenuItem<String>(
                      value: exhibitor['id']?.toString(),
                      child: Text(_linkedExhibitorLabel(exhibitor)),
                    ),
                  ),
                  const DropdownMenuItem<String>(
                    value: '__additional_name__',
                    child: Text('Add another person / name'),
                  ),
                ],
                onChanged: (value) {
                  if (value == null) return;

                  if (value == '__additional_name__') {
                    _startAdditionalName();
                    return;
                  }

                  final exhibitor = _linkedExhibitors.firstWhere(
                    (row) => row['id']?.toString() == value,
                    orElse: () =>
                        _selectedLinkedExhibitor ?? _linkedExhibitors.first,
                  );
                  _applyLinkedExhibitor(exhibitor);
                },
              ),
              const SizedBox(height: 12),
              if (_availableAdditionalLinkedExhibitors.isNotEmpty) ...[
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: ExpansionTile(
                    initiallyExpanded: true,
                    leading: const Icon(Icons.group_add_outlined),
                    title: const Text('Additional saved people'),
                    subtitle: Text(
                      _selectedAdditionalExhibitorIds.isEmpty
                          ? 'Optional: include more linked names for couple or family memberships.'
                          : '${_selectedAdditionalExhibitorIds.length} additional saved name(s) selected.',
                    ),
                    children: _availableAdditionalLinkedExhibitors.map(
                      (exhibitor) {
                        final id = exhibitor['id']?.toString();
                        final selected = id != null &&
                            _selectedAdditionalExhibitorIds.contains(id);

                        return CheckboxListTile(
                          value: selected,
                          onChanged: (value) => _toggleAdditionalLinkedExhibitor(
                            exhibitor,
                            value == true,
                          ),
                          title: Text(_linkedExhibitorLabel(exhibitor)),
                          subtitle: Text(
                            _bestShowingNameForExhibitor(exhibitor),
                          ),
                        );
                      },
                    ).toList(),
                  ),
                ),
                const SizedBox(height: 36),
              ],
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _firstNameController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'First name'),
                    validator: _requiredValidator,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _lastNameController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'Last name'),
                    validator: _requiredValidator,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _showingNameController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Rabbitry / showing name',
                hintText: 'Optional',
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Phone'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _dateOfBirthController,
              readOnly: true,
              decoration: InputDecoration(
                labelText: _selectedType?.hasAgeLimit == true
                    ? 'Date of birth *'
                    : 'Date of birth',
                hintText: 'YYYY-MM-DD',
                helperText: _selectedType?.ageLimitLabel,
                suffixIcon: const Icon(Icons.calendar_month_outlined),
              ),
              validator: (_) {
                final selectedType = _selectedType;
                if (selectedType == null) return null;
                return _selectedTypeAgeError(selectedType);
              },
              onTap: _pickDateOfBirth,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _arbaNumberController,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: _selectedType?.requireArbaNumber == true
                    ? 'ARBA number *'
                    : 'ARBA number',
                hintText: 'Optional unless required by this membership type',
              ),
              validator: (_) {
                if (_selectedType?.requireArbaNumber == true &&
                    _arbaNumberController.text.trim().isEmpty) {
                  return 'ARBA number is required for ${_selectedType?.name ?? 'this membership type'}.';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),
            const _SectionTitle(title: 'Address'),
            const SizedBox(height: 12),
            TextFormField(
              controller: _addressLine1Controller,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Address line 1'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _addressLine2Controller,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Address line 2'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _cityController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'City'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _stateController,
                    textCapitalization: TextCapitalization.characters,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'State'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _postalCodeController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'Postal code'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _countryController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(labelText: 'Country'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _notesController,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Notes for the club',
                hintText: 'Optional',
              ),
            ),
            if (_selectedAdditionalExhibitorIds.isNotEmpty) ...[
              const SizedBox(height: 12),
              _InlineMessage(
                icon: Icons.group_outlined,
                message:
                    'Additional saved people selected: ${_additionalLinkedExhibitors.map(_bestShowingNameForExhibitor).where((name) => name.isNotEmpty).join(', ')}',
                isError: false,
              ),
            ],
            if (_familyPriceMessage != null) ...[
              const SizedBox(height: 12),
              _InlineMessage(
                icon: Icons.family_restroom_outlined,
                message: _familyPriceMessage!,
                isError: false,
              ),
            ],
            if (_selectedType?.allowAutoRenew == true) ...[
              const SizedBox(height: 12),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _autoRenewEnabled,
                onChanged: (value) {
                  setState(() {
                    _autoRenewEnabled = value;
                  });
                },
                title: const Text('Enable automatic renewal'),
                subtitle: const Text(
                  'You can change this later from your membership settings.',
                ),
              ),
            ],
            if (_selectedType != null &&
                _checkoutAmountCents > 0 &&
                _acceptsOnlinePayments) ...[
              const SizedBox(height: 16),
              const _InlineMessage(
                icon: Icons.lock_outline,
                message:
                    'You will be redirected to Stripe Checkout to complete payment securely.',
                isError: false,
              ),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _isSubmitting ? null : _submitApplication,
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.arrow_forward),
              label: Text(_submitButtonLabel),
            ),
          ],
        ),
      ),
    );
  }

  Widget _membershipTypeTile(_MembershipTypeOption option) {
    final isSelected = option.id == _selectedType?.id;
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedType = option;
            _autoRenewEnabled = option.allowAutoRenew;
          });
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                isSelected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: isSelected ? colorScheme.primary : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    if (option.description.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(option.description),
                    ],
                    const SizedBox(height: 6),
                    Text(option.priceLabel),
                    if (isSelected && option.membershipScope == 'family')
                      Text(
                        'Current total: ${_moneyLabel(_checkoutAmountCents, option.currency)}',
                      ),
                    if (option.ageLimitLabel != null)
                      Text(option.ageLimitLabel!),
                    if (option.requiresApproval)
                      const Text('Requires club approval'),
                    if (option.requireArbaNumber)
                      const Text('ARBA number required'),
                    if (!_acceptsOnlinePayments && option.amountCents > 0)
                      const Text('Online payment is not currently enabled.'),
                  ],
                ),
              ),
              if (isSelected) ...[
                const SizedBox(width: 12),
                Icon(Icons.check_circle, color: colorScheme.primary),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String get _submitButtonLabel {
    final selectedType = _selectedType;
    if (selectedType == null) return 'Submit Application';

    if (_checkoutAmountCents > 0 && _acceptsOnlinePayments) {
      return 'Submit and Pay ${_moneyLabel(_checkoutAmountCents, selectedType.currency)}';
    }

    return 'Submit Application';
  }

  static String? _requiredValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Required';
    }

    return null;
  }

  static String? _emptyToNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

class _MembershipTypeOption {
  const _MembershipTypeOption({
    required this.id,
    required this.name,
    required this.description,
    required this.amountCents,
    required this.currency,
    required this.allowAutoRenew,
    required this.requiresApproval,
    required this.requireArbaNumber,
    required this.minimumAge,
    required this.maximumAge,
    required this.membershipScope,
    required this.settings,
  });

  factory _MembershipTypeOption.fromJson(Map<dynamic, dynamic> json) {
    return _MembershipTypeOption(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Membership',
      description: json['description']?.toString() ?? '',
      amountCents: _priceToCents(json['price']),
      currency: json['currency']?.toString().toUpperCase() ?? 'USD',
      allowAutoRenew: json['allow_auto_renew'] == true,
      requiresApproval: json['requires_approval'] != false,
      requireArbaNumber: json['require_arba_number'] == true,
      minimumAge: _intOrNull(json['minimum_age']),
      maximumAge: _intOrNull(json['maximum_age']),
      membershipScope: json['membership_scope']?.toString() ?? 'individual',
      settings: _settingsMap(json['settings']),
    );
  }

  final String id;
  final String name;
  final String description;
  final int amountCents;
  final String currency;
  final bool allowAutoRenew;
  final bool requiresApproval;
  final bool requireArbaNumber;
  final int? minimumAge;
  final int? maximumAge;
  final String membershipScope;
  final Map<String, dynamic> settings;

  int get familyIncludedAdults => _settingsInt('included_adults') ?? 2;
  int get familyIncludedYouth => _settingsInt('included_youth') ?? 0;

  int get familyAdditionalYouthPriceCents {
    final value = settings['additional_youth_price'];
    if (value == null) return 0;
    if (value is int) return value * 100;
    if (value is num) return (value * 100).round();

    final parsed = num.tryParse(value.toString());
    return parsed == null ? 0 : (parsed * 100).round();
  }

  int? _settingsInt(String key) {
    final value = settings[key];
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '');
  }

  bool get hasAgeLimit => minimumAge != null || maximumAge != null;

  String? get ageLimitLabel {
    if (minimumAge != null && maximumAge != null) {
      return 'Ages $minimumAge–$maximumAge';
    }
    if (minimumAge != null) return 'Minimum age: $minimumAge';
    if (maximumAge != null) return 'Maximum age: $maximumAge';
    return null;
  }

  String get priceLabel {
    if (amountCents <= 0) return 'Free';

    final amount = amountCents / 100;
    return '\$${amount.toStringAsFixed(2)} ${currency.toUpperCase()}';
  }

  static int _priceToCents(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value * 100;
    if (value is num) return (value * 100).round();

    final parsed = num.tryParse(value.toString());
    return parsed == null ? 0 : (parsed * 100).round();
  }

  static int? _intOrNull(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value.toString());
  }

  static Map<String, dynamic> _settingsMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return const <String, dynamic>{};
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
    );
  }
}

class _InlineMessage extends StatelessWidget {
  const _InlineMessage({
    required this.icon,
    required this.message,
    required this.isError,
  });

  final IconData icon;
  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: isError ? colorScheme.errorContainer : colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
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
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 64),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 10),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 22),
              FilledButton(onPressed: onAction, child: Text(actionLabel)),
            ],
          ),
        ),
      ),
    );
  }
}