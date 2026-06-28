// lib/screens/clubs/member/club_sanction_request_apply_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/clubs/club_summary.dart';
import '../../../services/clubs/club_service.dart';

class ClubSanctionRequestApplyScreen extends StatefulWidget {
  const ClubSanctionRequestApplyScreen({
    super.key,
    required this.club,
  });

  final ClubSummary club;

  @override
  State<ClubSanctionRequestApplyScreen> createState() =>
      _ClubSanctionRequestApplyScreenState();
}

class _ClubSanctionRequestApplyScreenState
    extends State<ClubSanctionRequestApplyScreen> {
  final _formKey = GlobalKey<FormState>();
  final _supabase = Supabase.instance.client;
  final _clubService = ClubService();

  final _requestingClubController = TextEditingController();
  final _secretaryFirstNameController = TextEditingController();
  final _secretaryLastNameController = TextEditingController();
  final _contactEmailController = TextEditingController();
  final _contactPhoneController = TextEditingController();
  final _youthSecretaryFirstNameController = TextEditingController();
  final _youthSecretaryLastNameController = TextEditingController();
  final _youthSecretaryEmailController = TextEditingController();
  final _youthSecretaryPhoneController = TextEditingController();
  final _showLocationNameController = TextEditingController();
  final _showAddressLine1Controller = TextEditingController();
  final _showAddressLine2Controller = TextEditingController();
  final _showCityController = TextEditingController();
  final _showStateController = TextEditingController();
  final _showZipController = TextEditingController();
  final _showDateController = TextEditingController();
  final _applicantNotesController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');
  String _paymentMethod = 'online';
  final List<TextEditingController> _youthSanctionNumberControllers =
      List.generate(6, (_) => TextEditingController());
  final List<TextEditingController> _openSanctionNumberControllers =
      List.generate(6, (_) => TextEditingController());

  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _acceptsOnlinePayments = false;
  bool _allowCheckPayments = false;
  bool _sanctionRequestsAddonEnabled = false;
  bool _useOpenSecretaryForYouth = true;
  String? _errorMessage;
  String? _successMessage;
  String? _treasurerName;
  String? _treasurerAddressLine1;
  String? _treasurerAddressLine2;
  String? _treasurerCity;
  String? _treasurerState;
  String? _treasurerZip;
  List<_SanctionTypeOption> _sanctionTypes = const [];
  _SanctionTypeOption? _selectedSanctionType;
  final String _sanctionCategory = 'rabbit';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadFormData());
  }

  @override
  void dispose() {
    _requestingClubController.dispose();
    _secretaryFirstNameController.dispose();
    _secretaryLastNameController.dispose();
    _contactEmailController.dispose();
    _contactPhoneController.dispose();
    _youthSecretaryFirstNameController.dispose();
    _youthSecretaryLastNameController.dispose();
    _youthSecretaryEmailController.dispose();
    _youthSecretaryPhoneController.dispose();
    _showLocationNameController.dispose();
    _showAddressLine1Controller.dispose();
    _showAddressLine2Controller.dispose();
    _showCityController.dispose();
    _showStateController.dispose();
    _showZipController.dispose();
    _showDateController.dispose();
    _applicantNotesController.dispose();
    _quantityController.dispose();
    for (final controller in _youthSanctionNumberControllers) {
      controller.dispose();
    }
    for (final controller in _openSanctionNumberControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadFormData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final clubRow = await _supabase
          .from('clubs')
          .select(
            'sanction_requests_addon_enabled,accepts_member_online_payments,'
            'allow_sanction_check_payments,treasurer_name,'
            'treasurer_address_line1,treasurer_address_line2,'
            'treasurer_city,treasurer_state,treasurer_zip',
          )
          .eq('id', widget.club.clubId)
          .single();

      final addonEnabled = clubRow['sanction_requests_addon_enabled'] == true;
      final acceptsOnlinePayments =
          clubRow['accepts_member_online_payments'] == true;
      final allowCheckPayments =
          clubRow['allow_sanction_check_payments'] == true;

      if (!addonEnabled) {
        if (!mounted) return;
        setState(() {
          _sanctionRequestsAddonEnabled = false;
          _acceptsOnlinePayments = acceptsOnlinePayments;
          _allowCheckPayments = allowCheckPayments;
          _sanctionTypes = const [];
          _selectedSanctionType = null;
          _isLoading = false;
        });
        return;
      }

      final rows = await _supabase
          .from('club_sanction_types')
          .select(
            'id,name,description,sanction_scope,base_price,currency,'
            'is_bundle,included_open_count,included_youth_count,is_active,'
            'sort_order',
          )
          .eq('club_id', widget.club.clubId)
          .eq('is_active', true)
          .order('sort_order', ascending: true)
          .order('name', ascending: true);

      final types = (rows as List)
          .whereType<Map>()
          .map(
            (row) => _SanctionTypeOption.fromJson(
              Map<String, dynamic>.from(row),
            ),
          )
          .toList();

      if (!mounted) return;
      setState(() {
        _sanctionRequestsAddonEnabled = true;
        _acceptsOnlinePayments = acceptsOnlinePayments;
        _allowCheckPayments = allowCheckPayments;
        _paymentMethod = acceptsOnlinePayments
            ? 'online'
            : allowCheckPayments
                ? 'check'
                : 'offline';
        _treasurerName = _emptyToNull(clubRow['treasurer_name']?.toString() ?? '');
        _treasurerAddressLine1 =
            _emptyToNull(clubRow['treasurer_address_line1']?.toString() ?? '');
        _treasurerAddressLine2 =
            _emptyToNull(clubRow['treasurer_address_line2']?.toString() ?? '');
        _treasurerCity = _emptyToNull(clubRow['treasurer_city']?.toString() ?? '');
        _treasurerState = _emptyToNull(clubRow['treasurer_state']?.toString() ?? '');
        _treasurerZip = _emptyToNull(clubRow['treasurer_zip']?.toString() ?? '');
        _sanctionTypes = types;
        _selectedSanctionType = types.isEmpty ? null : types.first;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Unable to load sanction request form: $error';
      });
    }
  }

  Future<void> _pickDate(TextEditingController controller) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _parseDate(controller.text) ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (selected != null) {
      controller.text = _dateText(selected);
    }
  }

  int get _selectedQuantity {
    final value = int.tryParse(_quantityController.text.trim());
    if (value == null || value < 1) return 1;
    return value;
  }

  int get _checkoutAmountCents {
    final selectedType = _selectedSanctionType;
    if (selectedType == null) return 0;
    return selectedType.amountCents * _selectedQuantity;
  }

  double get _checkoutAmount => _checkoutAmountCents / 100;


  bool get _isCheckPaymentSelected {
    return _checkoutAmountCents > 0 && _paymentMethod == 'check';
  }

  bool get _isOnlinePaymentSelected {
    return _checkoutAmountCents > 0 &&
        _acceptsOnlinePayments &&
        _paymentMethod == 'online';
  }

  String get _treasurerMailingLabel {
    final lines = <String>[];
    final name = _treasurerName?.trim();
    if (name != null && name.isNotEmpty) lines.add(name);
    final line1 = _treasurerAddressLine1?.trim();
    if (line1 != null && line1.isNotEmpty) lines.add(line1);
    final line2 = _treasurerAddressLine2?.trim();
    if (line2 != null && line2.isNotEmpty) lines.add(line2);
    final cityStateZip = [
      _treasurerCity?.trim() ?? '',
      _treasurerState?.trim() ?? '',
      _treasurerZip?.trim() ?? '',
    ].where((part) => part.isNotEmpty).join(', ');
    if (cityStateZip.isNotEmpty) lines.add(cityStateZip);
    return lines.join('\n');
  }

  int get _visibleSanctionBoxCount {
    final quantity = _selectedQuantity;
    final count = quantity < 1 ? 1 : quantity;
    _ensureSanctionNumberControllerCapacity(count);
    return count;
  }

  void _ensureSanctionNumberControllerCapacity(int count) {
    while (_youthSanctionNumberControllers.length < count) {
      _youthSanctionNumberControllers.add(TextEditingController());
    }
    while (_openSanctionNumberControllers.length < count) {
      _openSanctionNumberControllers.add(TextEditingController());
    }
  }

  bool get _showOpenSanctionNumbers {
    final selectedType = _selectedSanctionType;
    if (selectedType == null) return true;
    return selectedType.includesOpen;
  }

  bool get _showYouthSanctionNumbers {
    final selectedType = _selectedSanctionType;
    if (selectedType == null) return true;
    return selectedType.includesYouth;
  }

  Future<void> _submitRequest() async {
    final selectedType = _selectedSanctionType;
    if (selectedType == null) {
      setState(() {
        _errorMessage = 'Choose a sanction type to continue.';
      });
      return;
    }

    if (!(_formKey.currentState?.validate() ?? false)) return;

    final quantity = _selectedQuantity;

    final missingSanctionNumbers = _missingVisibleSanctionNumbers();
    if (missingSanctionNumbers.isNotEmpty) {
      setState(() {
        _errorMessage =
            'Enter ARBA sanction numbers for: ${missingSanctionNumbers.join(', ')}.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final inserted = await _supabase
          .from('club_sanction_requests')
          .insert({
            'club_id': widget.club.clubId,
            'sanction_type_id': selectedType.id,
            'quantity': quantity,
            'requesting_club_name': _requestingClubController.text.trim(),
            'contact_name': _openSecretaryName,
            'contact_email': _emptyToNull(_contactEmailController.text),
            'contact_phone': _emptyToNull(_contactPhoneController.text),
            'show_name': _requestingClubController.text.trim(),
            'show_date': _dateValue(_showDateController.text),
            'show_end_date': _dateValue(_showDateController.text),
            'location_name': _emptyToNull(_showLocationNameController.text),
            'location_address': _showFullAddress,
            'show_type': _derivedShowType,
            'sanction_category': _sanctionCategory,
            'status': 'pending',
            'fee_due': _checkoutAmount,
            'amount_paid': 0,
            'currency': selectedType.currency.toLowerCase(),
            'payment_status': _checkoutAmountCents > 0 ? 'unpaid' : 'waived',
            'applicant_notes': _combinedApplicantNotes(),
            'request_details': _requestDetailsJson(),
            'submitted_at': DateTime.now().toIso8601String(),
          })
          .select('id')
          .single();

      final requestId = inserted['id']?.toString();
      if (requestId == null || requestId.isEmpty) {
        throw Exception('Sanction request was created without an ID.');
      }

      if (_isOnlinePaymentSelected) {
        await _clubService.startMemberCheckout(
          clubId: widget.club.clubId,
          sourceType: 'sanction_request',
          sourceId: requestId,
          amountCents: _checkoutAmountCents,
          description: '${selectedType.name} sanction request',
        );

        if (!mounted) return;
        setState(() {
          _successMessage =
              'Your sanction request was submitted. Complete Stripe Checkout to finish payment.';
        });
      } else if (_isCheckPaymentSelected) {
        if (!mounted) return;
        setState(() {
          _successMessage =
              'Your sanction request was submitted. Mail your check to the club treasurer.';
        });
        await _showCheckPaymentDialog();
      } else if (_checkoutAmountCents > 0) {
        if (!mounted) return;
        setState(() {
          _successMessage =
              'Your sanction request was submitted. Payment will be handled by the club.';
        });
      } else {
        if (!mounted) return;
        setState(() {
          _successMessage =
              'Your sanction request was submitted to ${widget.club.clubName} for review.';
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Unable to submit sanction request: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  String get _openSecretaryName {
    return [
      _secretaryFirstNameController.text.trim(),
      _secretaryLastNameController.text.trim(),
    ].where((part) => part.isNotEmpty).join(' ');
  }

  String get _youthSecretaryName {
    if (_useOpenSecretaryForYouth) return _openSecretaryName;

    return [
      _youthSecretaryFirstNameController.text.trim(),
      _youthSecretaryLastNameController.text.trim(),
    ].where((part) => part.isNotEmpty).join(' ');
  }

  String get _showFullAddress {
    final addressLines = [
      _showAddressLine1Controller.text.trim(),
      _showAddressLine2Controller.text.trim(),
    ].where((part) => part.isNotEmpty).join('\n');

    final cityStateZip = [
      _showCityController.text.trim(),
      _showStateController.text.trim(),
      _showZipController.text.trim(),
    ].where((part) => part.isNotEmpty).join(', ');

    return [addressLines, cityStateZip]
        .where((part) => part.trim().isNotEmpty)
        .join('\n');
  }

  String get _derivedShowType {
    if (_showYouthSanctionNumbers && _showOpenSanctionNumbers) {
      return 'combined';
    }
    if (_showYouthSanctionNumbers || _showOpenSanctionNumbers) {
      return 'all_breed';
    }
    return 'other';
  }

  String get _requestScopeLabel {
    if (_showYouthSanctionNumbers && _showOpenSanctionNumbers) {
      return 'Open & Youth';
    }
    if (_showYouthSanctionNumbers) return 'Youth';
    if (_showOpenSanctionNumbers) return 'Open';
    return 'Other';
  }

  String? _combinedApplicantNotes() {
    final buffer = StringBuffer();
    final notes = _applicantNotesController.text.trim();

    buffer.writeln('Show counts derived from selected sanction type and quantity:');
    buffer.writeln('Youth: ${_showYouthSanctionNumbers ? _visibleSanctionBoxCount : 0}');
    buffer.writeln('Open: ${_showOpenSanctionNumbers ? _visibleSanctionBoxCount : 0}');
    buffer.writeln();
    buffer.writeln('ARBA sanction numbers:');
    if (_showYouthSanctionNumbers) {
      buffer.writeln(
        'Youth: ${_sanctionNumbersSummary(_youthSanctionNumberControllers)}',
      );
    }
    if (_showOpenSanctionNumbers) {
      buffer.writeln(
        'Open: ${_sanctionNumbersSummary(_openSanctionNumberControllers)}',
      );
    }
    buffer.writeln();
    buffer.writeln('Open show secretary: $_openSecretaryName');
    buffer.writeln('Youth show secretary: $_youthSecretaryName');
    buffer.writeln();
    buffer.writeln('Show location:');
    buffer.writeln(_showLocationNameController.text.trim());
    buffer.writeln(_showFullAddress);

    if (notes.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('Applicant notes:');
      buffer.write(notes);
    }

    return buffer.toString().trim();
  }

  Map<String, dynamic> _requestDetailsJson() {
    return {
      'open_secretary': {
        'first_name': _secretaryFirstNameController.text.trim(),
        'last_name': _secretaryLastNameController.text.trim(),
        'name': _openSecretaryName,
        'email': _contactEmailController.text.trim(),
        'phone': _contactPhoneController.text.trim(),
      },
      'youth_secretary': {
        'same_as_open': _useOpenSecretaryForYouth,
        'first_name': _useOpenSecretaryForYouth
            ? _secretaryFirstNameController.text.trim()
            : _youthSecretaryFirstNameController.text.trim(),
        'last_name': _useOpenSecretaryForYouth
            ? _secretaryLastNameController.text.trim()
            : _youthSecretaryLastNameController.text.trim(),
        'name': _youthSecretaryName,
        'email': _useOpenSecretaryForYouth
            ? _contactEmailController.text.trim()
            : _youthSecretaryEmailController.text.trim(),
        'phone': _useOpenSecretaryForYouth
            ? _contactPhoneController.text.trim()
            : _youthSecretaryPhoneController.text.trim(),
      },
      'show_location': {
        'name': _showLocationNameController.text.trim(),
        'address_line1': _showAddressLine1Controller.text.trim(),
        'address_line2': _showAddressLine2Controller.text.trim(),
        'city': _showCityController.text.trim(),
        'state': _showStateController.text.trim(),
        'zip': _showZipController.text.trim(),
        'full_address': _showFullAddress,
      },
      'show_counts': {
        'youth': _showYouthSanctionNumbers ? _visibleSanctionBoxCount : 0,
        'open': _showOpenSanctionNumbers ? _visibleSanctionBoxCount : 0,
      },
      'arba_sanction_numbers': {
        'youth': _showYouthSanctionNumbers
            ? _sanctionNumbersList(_youthSanctionNumberControllers)
            : <String>[],
        'open': _showOpenSanctionNumbers
            ? _sanctionNumbersList(_openSanctionNumberControllers)
            : <String>[],
      },
      'requested_show_scope': {
        'includes_youth': _showYouthSanctionNumbers,
        'includes_open': _showOpenSanctionNumbers,
        'label': _requestScopeLabel,
      },
      'payment_method': _checkoutAmountCents <= 0 ? 'waived' : _paymentMethod,
      'check_payment': {
        'selected': _isCheckPaymentSelected,
        'status': _isCheckPaymentSelected ? 'pending_check' : null,
        'payable_to': _treasurerName,
        'mailing_address': _treasurerMailingLabel,
      },
    };
  }

  List<String> _sanctionNumbersList(List<TextEditingController> controllers) {
    return controllers
        .take(_visibleSanctionBoxCount)
        .map((controller) => controller.text.trim())
        .toList();
  }

  List<String> _missingVisibleSanctionNumbers() {
    final missing = <String>[];

    if (_showYouthSanctionNumbers) {
      for (var index = 0; index < _visibleSanctionBoxCount; index++) {
        if (_youthSanctionNumberControllers[index].text.trim().isEmpty) {
          missing.add('Youth Show ${index + 1}');
        }
      }
    }

    if (_showOpenSanctionNumbers) {
      for (var index = 0; index < _visibleSanctionBoxCount; index++) {
        if (_openSanctionNumberControllers[index].text.trim().isEmpty) {
          missing.add('Open Show ${index + 1}');
        }
      }
    }

    return missing;
  }

  String _sanctionNumbersSummary(List<TextEditingController> controllers) {
    final values = <String>[];
    for (var index = 0; index < _visibleSanctionBoxCount; index++) {
      final value = controllers[index].text.trim();
      if (value.isNotEmpty) {
        values.add('Show ${index + 1}: $value');
      }
    }
    return values.isEmpty ? 'Not provided' : values.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Request Sanction')),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_sanctionRequestsAddonEnabled) {
      return _MessageState(
        icon: Icons.lock_outline,
        title: 'Sanction requests are not enabled',
        message:
            '${widget.club.clubName} is not currently accepting online sanction requests.',
        actionLabel: 'Refresh',
        onAction: _loadFormData,
      );
    }

    if (_sanctionTypes.isEmpty) {
      return _MessageState(
        icon: Icons.verified_outlined,
        title: 'No sanction types available',
        message:
            '${widget.club.clubName} does not currently have any active sanction request types available.',
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
              'Submit a sanction request for review by this club.',
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
            const _SectionTitle(title: 'Sanction Type'),
            const SizedBox(height: 8),
            ..._sanctionTypes.map(_sanctionTypeTile),
            const SizedBox(height: 22),
            TextFormField(
              controller: _quantityController,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Quantity',
                helperText:
                    'Use this when requesting more than one sanction of the selected type.',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                final quantity = int.tryParse(value?.trim() ?? '');
                if (quantity == null || quantity < 1) {
                  return 'Enter a quantity of 1 or more.';
                }
                return null;
              },
              onChanged: (value) {
                final quantity = int.tryParse(value.trim());
                if (quantity != null && quantity > 0) {
                  _ensureSanctionNumberControllerCapacity(quantity);
                }
                setState(() {});
              },
            ),
            const SizedBox(height: 8),
            _InlineMessage(
              icon: Icons.calculate_outlined,
              message:
                  'Current total: ${_moneyLabel(_checkoutAmountCents, _selectedSanctionType?.currency ?? 'USD')}',
              isError: false,
            ),
            const SizedBox(height: 22),
            const _SectionTitle(title: 'Requesting Club / Open Show Secretary'),
            const SizedBox(height: 12),
            _ResponsiveFields(
              children: [
                TextFormField(
                  controller: _requestingClubController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Requesting club',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => _required(value, 'Requesting club'),
                ),
                TextFormField(
                  controller: _secretaryFirstNameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Open show secretary first name',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) =>
                      _required(value, 'Open show secretary first name'),
                ),
                TextFormField(
                  controller: _secretaryLastNameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Open show secretary last name',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) =>
                      _required(value, 'Open show secretary last name'),
                ),
                TextFormField(
                  controller: _contactEmailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Open show secretary email',
                    border: OutlineInputBorder(),
                  ),
                  validator: _optionalEmail,
                ),
                TextFormField(
                  controller: _contactPhoneController,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Open show secretary phone',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            const _SectionTitle(title: 'Youth Show Secretary'),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Same as open show secretary'),
              value: _useOpenSecretaryForYouth,
              onChanged: _isSubmitting
                  ? null
                  : (value) {
                      setState(() {
                        _useOpenSecretaryForYouth = value;
                      });
                    },
            ),
            if (!_useOpenSecretaryForYouth) ...[
              const SizedBox(height: 8),
              _ResponsiveFields(
                children: [
                  TextFormField(
                    controller: _youthSecretaryFirstNameController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Youth show secretary first name',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => _useOpenSecretaryForYouth
                        ? null
                        : _required(value, 'Youth show secretary first name'),
                  ),
                  TextFormField(
                    controller: _youthSecretaryLastNameController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Youth show secretary last name',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => _useOpenSecretaryForYouth
                        ? null
                        : _required(value, 'Youth show secretary last name'),
                  ),
                  TextFormField(
                    controller: _youthSecretaryEmailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Youth show secretary email',
                      border: OutlineInputBorder(),
                    ),
                    validator: _optionalEmail,
                  ),
                  TextFormField(
                    controller: _youthSecretaryPhoneController,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Youth show secretary phone',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 22),
            const _SectionTitle(title: 'Show Details'),
            const SizedBox(height: 12),
            _ResponsiveFields(
              children: [
                _DateField(
                  controller: _showDateController,
                  label: 'Show date',
                  onPick: () => _pickDate(_showDateController),
                ),
                TextFormField(
                  controller: _showLocationNameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Show location name',
                    border: OutlineInputBorder(),
                  ),
                ),
                TextFormField(
                  controller: _showAddressLine1Controller,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Address line 1',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => _required(value, 'Address line 1'),
                ),
                TextFormField(
                  controller: _showAddressLine2Controller,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Address line 2',
                    hintText: 'Optional',
                    border: OutlineInputBorder(),
                  ),
                ),
                TextFormField(
                  controller: _showCityController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'City',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => _required(value, 'City'),
                ),
                TextFormField(
                  controller: _showStateController,
                  textInputAction: TextInputAction.next,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'State',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => _required(value, 'State'),
                ),
                TextFormField(
                  controller: _showZipController,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'ZIP',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => _required(value, 'ZIP'),
                ),
              ],
            ),
            const SizedBox(height: 22),
            const _SectionTitle(title: 'ARBA Sanction Numbers'),
            const SizedBox(height: 8),
            _SanctionNumbersTable(
              youthControllers: _youthSanctionNumberControllers,
              openControllers: _openSanctionNumberControllers,
              showYouth: _showYouthSanctionNumbers,
              showOpen: _showOpenSanctionNumbers,
              visibleCount: _visibleSanctionBoxCount,
            ),
            if (_checkoutAmountCents > 0 &&
                (_acceptsOnlinePayments || _allowCheckPayments)) ...[
              const SizedBox(height: 22),
              const _SectionTitle(title: 'Payment Method'),
              const SizedBox(height: 8),
              _PaymentMethodCard(
                selectedMethod: _paymentMethod,
                acceptsOnlinePayments: _acceptsOnlinePayments,
                allowCheckPayments: _allowCheckPayments,
                checkMailingLabel: _treasurerMailingLabel,
                onChanged: _isSubmitting
                    ? null
                    : (value) {
                        setState(() {
                          _paymentMethod = value;
                        });
                      },
              ),
            ],
            const SizedBox(height: 22),
            TextFormField(
              controller: _applicantNotesController,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Notes for the club',
                hintText: 'Optional',
                border: OutlineInputBorder(),
              ),
            ),
            if (_selectedSanctionType != null && _isOnlinePaymentSelected) ...[
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
              onPressed: _isSubmitting ? null : _submitRequest,
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_outlined),
              label: Text(_submitButtonLabel),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sanctionTypeTile(_SanctionTypeOption type) {
    final isSelected = type.id == _selectedSanctionType?.id;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _isSubmitting
            ? null
            : () {
                setState(() {
                  _selectedSanctionType = type;
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
                color: isSelected ? scheme.primary : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      type.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    if (type.description.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(type.description),
                    ],
                    const SizedBox(height: 6),
                    Text(type.priceLabel),
                    Text(_titleCase(type.sanctionScope)),
                  ],
                ),
              ),
              if (isSelected) ...[
                const SizedBox(width: 12),
                Icon(Icons.check_circle, color: scheme.primary),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String get _submitButtonLabel {
    final selectedType = _selectedSanctionType;
    if (selectedType == null) return 'Submit Request';

    if (_isOnlinePaymentSelected) {
      return 'Submit and Pay ${_moneyLabel(_checkoutAmountCents, selectedType.currency)}';
    }

    if (_isCheckPaymentSelected) {
      return 'Submit and Mail Check';
    }

    return 'Submit Request';
  }

  Future<void> _showCheckPaymentDialog() async {
    final mailingLabel = _treasurerMailingLabel.trim();

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Mail Check Payment'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Please mail your check for ${_moneyLabel(_checkoutAmountCents, _selectedSanctionType?.currency ?? 'USD')} to:',
              ),
              const SizedBox(height: 12),
              if (mailingLabel.isNotEmpty)
                SelectableText(
                  mailingLabel,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                )
              else
                const Text(
                  'The club treasurer. Mailing details have not been added yet, so the club will follow up with payment instructions.',
                ),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Got It'),
            ),
          ],
        );
      },
    );
  }

  String _moneyLabel(int cents, String currency) {
    if (cents <= 0) return 'Free';

    final amount = cents / 100;
    final symbol = currency.toUpperCase() == 'USD' ? r'$' : '';
    return '$symbol${amount.toStringAsFixed(2)} ${currency.toUpperCase()}'.trim();
  }

  String? _required(String? value, String label) {
    if (value == null || value.trim().isEmpty) {
      return '$label is required.';
    }
    return null;
  }

  static String? _optionalEmail(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;

    final pattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!pattern.hasMatch(text)) {
      return 'Enter a valid email address.';
    }
    return null;
  }

  static String? _emptyToNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static DateTime? _parseDate(String value) {
    final text = value.trim();
    if (text.isEmpty) return null;
    return DateTime.tryParse(text);
  }

  static String? _dateValue(String value) {
    final date = _parseDate(value);
    return date == null ? null : _dateText(date);
  }

  static String _dateText(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  static String _titleCase(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return trimmed;
    return trimmed
        .split(RegExp(r'[_\s-]+'))
        .where((part) => part.isNotEmpty)
        .map((part) => part[0].toUpperCase() + part.substring(1).toLowerCase())
        .join(' ');
  }
}

class _SanctionTypeOption {
  const _SanctionTypeOption({
    required this.id,
    required this.name,
    required this.description,
    required this.sanctionScope,
    required this.isBundle,
    required this.includedOpenCount,
    required this.includedYouthCount,
    required this.amountCents,
    required this.currency,
  });

  factory _SanctionTypeOption.fromJson(Map<String, dynamic> json) {
    return _SanctionTypeOption(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Sanction',
      description: json['description']?.toString() ?? '',
      sanctionScope: json['sanction_scope']?.toString() ?? 'open',
      isBundle: json['is_bundle'] == true,
      includedOpenCount: _intValue(json['included_open_count']),
      includedYouthCount: _intValue(json['included_youth_count']),
      amountCents: _priceToCents(json['base_price']),
      currency: json['currency']?.toString().toUpperCase() ?? 'USD',
    );
  }

  final String id;
  final String name;
  final String description;
  final String sanctionScope;
  final bool isBundle;
  final int includedOpenCount;
  final int includedYouthCount;
  final int amountCents;
  final String currency;

  double get basePrice => amountCents / 100;

  bool get includesOpen {
    final scope = sanctionScope.toLowerCase();
    return isBundle ||
        includedOpenCount > 0 ||
        scope.contains('open') ||
        scope.contains('both') ||
        scope.contains('bundle');
  }

  bool get includesYouth {
    final scope = sanctionScope.toLowerCase();
    return isBundle ||
        includedYouthCount > 0 ||
        scope.contains('youth') ||
        scope.contains('both') ||
        scope.contains('bundle');
  }

  String get priceLabel {
    if (amountCents <= 0) return 'Free';

    final amount = amountCents / 100;
    final symbol = currency.toUpperCase() == 'USD' ? r'$' : '';
    return '$symbol${amount.toStringAsFixed(2)} ${currency.toUpperCase()}'.trim();
  }

  static int _intValue(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value.toString()) ?? 0;
  }

  static int _priceToCents(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value * 100;
    if (value is num) return (value * 100).round();

    final parsed = num.tryParse(value.toString());
    return parsed == null ? 0 : (parsed * 100).round();
  }
}

class _ResponsiveFields extends StatelessWidget {
  const _ResponsiveFields({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        final width = wide ? (constraints.maxWidth - 12) / 2 : constraints.maxWidth;

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: children
              .map(
                (child) => SizedBox(
                  width: width,
                  child: child,
                ),
              )
              .toList(),
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
        hintText: 'YYYY-MM-DD',
        border: const OutlineInputBorder(),
        suffixIcon: const Icon(Icons.calendar_month_outlined),
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return '$label is required.';
        }
        return null;
      },
      onTap: onPick,
    );
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
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: isError ? scheme.errorContainer : scheme.primaryContainer,
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



class _SanctionNumbersTable extends StatelessWidget {
  const _SanctionNumbersTable({
    required this.youthControllers,
    required this.openControllers,
    required this.showYouth,
    required this.showOpen,
    required this.visibleCount,
  });

  final List<TextEditingController> youthControllers;
  final List<TextEditingController> openControllers;
  final bool showYouth;
  final bool showOpen;
  final int visibleCount;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: 120.0 + (visibleCount * 140.0)),
        child: Table(
          columnWidths: _columnWidths,
          border: TableBorder.all(color: Theme.of(context).dividerColor),
          children: [
            TableRow(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
              children: [
                const SizedBox.shrink(),
                for (var index = 0; index < visibleCount; index++)
                  _TableHeader('Show ${index + 1}'),
              ],
            ),
            if (showYouth) _numberRow('Youth', youthControllers),
            if (showOpen) _numberRow('Open', openControllers),
          ],
        ),
      ),
    );
  }

  Map<int, TableColumnWidth> get _columnWidths {
    return {
      0: const FixedColumnWidth(90),
      for (var index = 1; index <= visibleCount; index++)
        index: const FlexColumnWidth(),
    };
  }

  TableRow _numberRow(String label, List<TextEditingController> controllers) {
    return TableRow(
      children: [
        _TableHeader(label),
        ...controllers.take(visibleCount).map(
          (controller) => Padding(
            padding: const EdgeInsets.all(6),
            child: TextFormField(
              controller: controller,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TableHeader extends StatelessWidget {
  const _TableHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}


class _PaymentMethodCard extends StatelessWidget {
  const _PaymentMethodCard({
    required this.selectedMethod,
    required this.acceptsOnlinePayments,
    required this.allowCheckPayments,
    required this.checkMailingLabel,
    required this.onChanged,
  });

  final String selectedMethod;
  final bool acceptsOnlinePayments;
  final bool allowCheckPayments;
  final String checkMailingLabel;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            if (acceptsOnlinePayments)
              _PaymentMethodOption(
                value: 'online',
                selectedMethod: selectedMethod,
                onChanged: onChanged,
                title: 'Pay online',
                subtitle: 'Pay securely with Stripe Checkout.',
              ),
            if (acceptsOnlinePayments && allowCheckPayments)
              const Divider(height: 1),
            if (allowCheckPayments)
              _PaymentMethodOption(
                value: 'check',
                selectedMethod: selectedMethod,
                onChanged: onChanged,
                title: 'Mail a check',
                subtitle: checkMailingLabel.trim().isEmpty
                    ? 'The club will provide mailing instructions after submission.'
                    : 'Mail payment to the club treasurer after submission.',
              ),
          ],
        ),
      ),
    );
  }
}

class _PaymentMethodOption extends StatelessWidget {
  const _PaymentMethodOption({
    required this.value,
    required this.selectedMethod,
    required this.onChanged,
    required this.title,
    required this.subtitle,
  });

  final String value;
  final String selectedMethod;
  final ValueChanged<String>? onChanged;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final selected = value == selectedMethod;
    final scheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onChanged == null ? null : () => onChanged!(value),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: selected ? scheme.primary : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}