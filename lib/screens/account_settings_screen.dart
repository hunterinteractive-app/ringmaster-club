// lib/screens/account_settings_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'legal/privacy_policy_screen.dart';
import 'legal/terms_screen.dart';
import 'login_screen.dart';
import '../widgets/exhibitor_builder_dialog.dart';
import '../widgets/account_settings_view.dart';

final supabase = Supabase.instance.client;

class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({super.key, this.onAccountChanged});

  final Future<void> Function()? onAccountChanged;

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  bool _loading = true;
  bool _signingOut = false;
  bool _hasLoaded = false;
  String? _message;
  String? _profileDisplayName;
  String? _profileEmail;
  List<Map<String, dynamic>> _exhibitors = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = supabase.auth.currentUser;

    if (user == null) {
      if (!mounted) return;
      _returnToLogin();
      return;
    }

    setState(() {
      _loading = true;
      _message = null;
    });

    try {
      final profile = await supabase
          .from('profiles')
          .select('display_name,email')
          .eq('user_id', user.id)
          .maybeSingle();

      final rows = await supabase
          .from('exhibitors')
          .select(
            'id,account_type,display_name,first_name,last_name,showing_name,'
            'email,phone,address_line1,address_line2,city,state,zip,birth_date,'
            'arba_number,source_exhibitor_number,is_public_entry,'
            'print_phone_on_reports,group_members,is_primary,is_active,imported_from,'
            'imported_source_id,imported_at,created_at,updated_at',
          )
          .eq('owner_user_id', user.id)
          .order('created_at', ascending: true);

      if (!mounted) return;

      setState(() {
        _profileDisplayName = _clean(profile?['display_name']);
        _profileEmail = _clean(profile?['email']) ?? user.email;
        _exhibitors = (rows as List).cast<Map<String, dynamic>>();
        _hasLoaded = true;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _message = 'Unable to load account settings: $error';
      });
    }
  }

  Future<void> _setPrimaryAccount(Map<String, dynamic> exhibitor) async {
    final user = supabase.auth.currentUser;
    final exhibitorId = exhibitor['id']?.toString();

    if (user == null || exhibitorId == null || exhibitorId.isEmpty) {
      return;
    }

    try {
      final now = DateTime.now().toUtc().toIso8601String();

      await supabase
          .from('exhibitors')
          .update({'is_primary': false, 'updated_at': now})
          .eq('owner_user_id', user.id)
          .eq('is_primary', true);

      await supabase
          .from('exhibitors')
          .update({'is_primary': true, 'is_active': true, 'updated_at': now})
          .eq('id', exhibitorId)
          .eq('owner_user_id', user.id);

      final displayName = _displayNameFor(exhibitor);

      await supabase.from('profiles').upsert({
        'user_id': user.id,
        'email': user.email,
        'display_name': displayName,
        'updated_at': now,
      }, onConflict: 'user_id');

      await _reloadAfterChange();

      if (!mounted) return;

      setState(() {
        _message = '$displayName is now the primary account.';
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _message = 'Unable to update the primary account: $error';
      });
    }
  }

  String? _clean(dynamic value) {
    final text = (value ?? '').toString().trim();
    return text.isEmpty ? null : text;
  }

  String _displayNameFor(Map<String, dynamic> exhibitor) {
    return accountDisplayName(exhibitor);
  }

  Future<void> _reloadAfterChange() async {
    if (!mounted) return;
    await widget.onAccountChanged?.call();
    if (mounted) await _load();
  }

  Future<void> _openExhibitorEditor({Map<String, dynamic>? existing}) async {
    final saved = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          ExhibitorBuilderDialog(exhibitorId: existing?['id']?.toString()),
    );

    if (saved != null) {
      await _reloadAfterChange();
      if (!mounted) return;
      setState(() {
        _message = existing == null
            ? 'Account added.'
            : 'Account information updated.';
      });
    }
  }

  Future<void> _toggleActive(
    Map<String, dynamic> exhibitor,
    bool newValue,
  ) async {
    final id = exhibitor['id']?.toString();
    if (id == null || id.isEmpty) return;

    try {
      await supabase
          .from('exhibitors')
          .update({
            'is_active': newValue,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', id);

      await _reloadAfterChange();

      if (!mounted) return;
      setState(() {
        _message = newValue ? 'Account activated.' : 'Account deactivated.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _message = 'Unable to update account status: $error';
      });
    }
  }

  Future<void> _confirmToggleActive(
    Map<String, dynamic> exhibitor,
    bool newValue,
  ) async {
    final name = _displayNameFor(exhibitor);

    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(newValue ? 'Activate account?' : 'Deactivate account?'),
            content: Text(
              newValue
                  ? '$name will become available for RingMaster Club activity.'
                  : '$name will remain saved but will no longer be active.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(newValue ? 'Activate' : 'Deactivate'),
              ),
            ],
          ),
        ) ??
        false;

    if (confirmed) {
      await _toggleActive(exhibitor, newValue);
    }
  }

  Future<void> _signOut() async {
    if (_signingOut) return;

    setState(() {
      _signingOut = true;
    });

    await supabase.auth.signOut();

    if (!mounted) return;
    _returnToLogin();
  }

  void _returnToLogin() {
    if (!mounted) return;

    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  Future<void> _openTerms() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const TermsScreen()));
  }

  Future<void> _openPrivacy() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen()));
  }

  @override
  Widget build(BuildContext context) => AccountSettingsView(
    loading: _loading,
    hasLoaded: _hasLoaded,
    signingOut: _signingOut,
    displayName: _profileDisplayName,
    email: _profileEmail,
    accounts: _exhibitors,
    message: _message,
    onRefresh: _load,
    onAdd: () => _openExhibitorEditor(),
    onEdit: (account) => _openExhibitorEditor(existing: account),
    onMakePrimary: _setPrimaryAccount,
    onToggleActive: _confirmToggleActive,
    onTerms: _openTerms,
    onPrivacy: _openPrivacy,
    onSignOut: _signOut,
  );
}
