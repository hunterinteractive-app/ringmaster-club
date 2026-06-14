// lib/widgets/exhibitor_builder_dialog.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ExhibitorBuilderDialog extends StatefulWidget {
  final String? exhibitorId;

  const ExhibitorBuilderDialog({
    super.key,
    this.exhibitorId,
  });

  @override
  State<ExhibitorBuilderDialog> createState() =>
      _ExhibitorBuilderDialogState();
}

class _ExhibitorBuilderDialogState extends State<ExhibitorBuilderDialog> {
  final _formKey = GlobalKey<FormState>();
  final _supabase = Supabase.instance.client;

  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _showingName = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _address1 = TextEditingController();
  final _address2 = TextEditingController();
  final _city = TextEditingController();
  final _state = TextEditingController();
  final _zip = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _showingNameWasManuallyEdited = false;
  String? _error;

  bool get _isEditing => widget.exhibitorId != null;

  @override
  void initState() {
    super.initState();
    _firstName.addListener(_updateShowingName);
    _lastName.addListener(_updateShowingName);
    _showingName.addListener(_trackShowingNameEdit);
    _load();
  }

  @override
  void dispose() {
    _firstName.removeListener(_updateShowingName);
    _lastName.removeListener(_updateShowingName);
    _showingName.removeListener(_trackShowingNameEdit);
    _firstName.dispose();
    _lastName.dispose();
    _showingName.dispose();
    _email.dispose();
    _phone.dispose();
    _address1.dispose();
    _address2.dispose();
    _city.dispose();
    _state.dispose();
    _zip.dispose();
    super.dispose();
  }

  void _trackShowingNameEdit() {
    if (!_loading && _showingName.text.trim() != _generatedShowingName()) {
      _showingNameWasManuallyEdited = true;
    }
  }

  void _updateShowingName() {
    if (_loading || _showingNameWasManuallyEdited) return;

    final generated = _generatedShowingName();
    if (_showingName.text != generated) {
      _showingName.value = TextEditingValue(
        text: generated,
        selection: TextSelection.collapsed(offset: generated.length),
      );
    }
  }

  String _generatedShowingName() {
    final first = _firstName.text.trim();
    final last = _lastName.text.trim();

    if (first.isEmpty) return last;
    if (last.isEmpty) return first;
    return '$first $last';
  }

  Future<void> _load() async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'You must be signed in to complete account setup.';
      });
      return;
    }

    try {
      _email.text = user.email ?? '';

      if (_isEditing) {
        final row = await _supabase
            .from('exhibitors')
            .select(
              'id, first_name, last_name, showing_name, email, phone, '
              'address_line1, address_line2, city, state, zip',
            )
            .eq('id', widget.exhibitorId!)
            .single();

        _firstName.text = _text(row['first_name']);
        _lastName.text = _text(row['last_name']);
        _showingName.text = _text(row['showing_name']);
        _email.text = _text(row['email']).isEmpty
            ? (user.email ?? '')
            : _text(row['email']);
        _phone.text = _text(row['phone']);
        _address1.text = _text(row['address_line1']);
        _address2.text = _text(row['address_line2']);
        _city.text = _text(row['city']);
        _state.text = _text(row['state']);
        _zip.text = _text(row['zip']);
        _showingNameWasManuallyEdited =
            _showingName.text.trim().isNotEmpty &&
                _showingName.text.trim() != _generatedShowingName();
      } else {
        final metadata = user.userMetadata ?? const <String, dynamic>{};
        _firstName.text = _text(metadata['first_name']);
        _lastName.text = _text(metadata['last_name']);
        _showingName.text = _generatedShowingName();
      }

      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Unable to load account information: $error';
      });
    }
  }

  String _text(dynamic value) => (value ?? '').toString().trim();

  String? _required(String? value, String label) {
    if ((value ?? '').trim().isEmpty) {
      return '$label is required.';
    }
    return null;
  }

  String? _validateEmail(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return 'Email is required.';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(text)) {
      return 'Enter a valid email address.';
    }
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _saving) return;

    final user = _supabase.auth.currentUser;
    if (user == null) {
      setState(() {
        _error = 'Your session has expired. Please sign in again.';
      });
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final values = <String, dynamic>{
        'owner_user_id': user.id,
        'first_name': _firstName.text.trim(),
        'last_name': _lastName.text.trim(),
        'showing_name': _showingName.text.trim(),
        'email': _email.text.trim(),
        'phone': _phone.text.trim(),
        'address_line1': _address1.text.trim(),
        'address_line2': _address2.text.trim().isEmpty
            ? null
            : _address2.text.trim(),
        'city': _city.text.trim(),
        'state': _state.text.trim().toUpperCase(),
        'zip': _zip.text.trim(),
        'is_active': true,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

      Map<String, dynamic> saved;

      if (_isEditing) {
        saved = await _supabase
            .from('exhibitors')
            .update(values)
            .eq('id', widget.exhibitorId!)
            .select()
            .single();
      } else {
        values['created_at'] = DateTime.now().toUtc().toIso8601String();
        saved = await _supabase
            .from('exhibitors')
            .insert(values)
            .select()
            .single();
      }

      await _supabase.from('profiles').upsert(
        {
          'user_id': user.id,
          'email': _email.text.trim(),
          'display_name': _showingName.text.trim(),
        },
        onConflict: 'user_id',
      );

      if (!mounted) return;
      Navigator.of(context).pop(saved);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Unable to save account information: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: Text(_isEditing ? 'Edit Account Information' : 'Set Up Account'),
        content: SizedBox(
          width: 680,
          child: _loading
              ? const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                )
              : Form(
                  key: _formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Please provide the account information RingMaster Club '
                          'will use for your memberships and club activity.',
                        ),
                        const SizedBox(height: 20),
                        if (_error != null) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .errorContainer,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              _error!,
                              style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onErrorContainer,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final stacked = constraints.maxWidth < 520;
                            final first = TextFormField(
                              controller: _firstName,
                              textCapitalization: TextCapitalization.words,
                              decoration: const InputDecoration(
                                labelText: 'First name',
                                border: OutlineInputBorder(),
                              ),
                              validator: (value) =>
                                  _required(value, 'First name'),
                            );
                            final last = TextFormField(
                              controller: _lastName,
                              textCapitalization: TextCapitalization.words,
                              decoration: const InputDecoration(
                                labelText: 'Last name',
                                border: OutlineInputBorder(),
                              ),
                              validator: (value) =>
                                  _required(value, 'Last name'),
                            );

                            if (stacked) {
                              return Column(
                                children: [
                                  first,
                                  const SizedBox(height: 12),
                                  last,
                                ],
                              );
                            }

                            return Row(
                              children: [
                                Expanded(child: first),
                                const SizedBox(width: 12),
                                Expanded(child: last),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _showingName,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Display / showing name',
                            helperText:
                                'This is how your name will appear in RingMaster.',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) =>
                              _required(value, 'Display / showing name'),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            border: OutlineInputBorder(),
                          ),
                          validator: _validateEmail,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _phone,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'Phone',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) => _required(value, 'Phone'),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _address1,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Address',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) => _required(value, 'Address'),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _address2,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Address line 2',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _city,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'City',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) => _required(value, 'City'),
                        ),
                        const SizedBox(height: 12),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final stacked = constraints.maxWidth < 420;
                            final state = TextFormField(
                              controller: _state,
                              textCapitalization:
                                  TextCapitalization.characters,
                              maxLength: 2,
                              decoration: const InputDecoration(
                                labelText: 'State',
                                counterText: '',
                                border: OutlineInputBorder(),
                              ),
                              validator: (value) {
                                final required = _required(value, 'State');
                                if (required != null) return required;
                                if (value!.trim().length != 2) {
                                  return 'Use the 2-letter abbreviation.';
                                }
                                return null;
                              },
                            );
                            final zip = TextFormField(
                              controller: _zip,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'ZIP code',
                                border: OutlineInputBorder(),
                              ),
                              validator: (value) =>
                                  _required(value, 'ZIP code'),
                            );

                            if (stacked) {
                              return Column(
                                children: [
                                  state,
                                  const SizedBox(height: 12),
                                  zip,
                                ],
                              );
                            }

                            return Row(
                              children: [
                                Expanded(child: state),
                                const SizedBox(width: 12),
                                Expanded(flex: 2, child: zip),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: _saving
                ? null
                : () => Navigator.of(context).pop(null),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: _loading || _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(_saving ? 'Saving...' : 'Save and Continue'),
          ),
        ],
      ),
    );
  }
}