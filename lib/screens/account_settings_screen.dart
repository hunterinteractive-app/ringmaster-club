// lib/screens/account_settings_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'legal/privacy_policy_screen.dart';
import 'legal/terms_screen.dart';
import 'login_screen.dart';
import '../widgets/exhibitor_builder_dialog.dart';

final supabase = Supabase.instance.client;

class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({super.key});

  @override
  State<AccountSettingsScreen> createState() =>
      _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  bool _loading = true;
  bool _signingOut = false;
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

  Future<void> _setPrimaryAccount(
    Map<String, dynamic> exhibitor,
  ) async {
    final user = supabase.auth.currentUser;
    final exhibitorId = exhibitor['id']?.toString();

    if (user == null || exhibitorId == null || exhibitorId.isEmpty) {
      return;
    }

    try {
      final now = DateTime.now().toUtc().toIso8601String();

      await supabase
          .from('exhibitors')
          .update({
            'is_primary': false,
            'updated_at': now,
          })
          .eq('owner_user_id', user.id)
          .eq('is_primary', true);

      await supabase
          .from('exhibitors')
          .update({
            'is_primary': true,
            'is_active': true,
            'updated_at': now,
          })
          .eq('id', exhibitorId)
          .eq('owner_user_id', user.id);

      final displayName = _displayNameFor(exhibitor);

      await supabase.from('profiles').upsert(
        {
          'user_id': user.id,
          'email': user.email,
          'display_name': displayName,
          'updated_at': now,
        },
        onConflict: 'user_id',
      );

      await _load();

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
    return _clean(exhibitor['display_name']) ??
        _clean(exhibitor['showing_name']) ??
        [
          _clean(exhibitor['first_name']),
          _clean(exhibitor['last_name']),
        ].whereType<String>().join(' ').trim().ifEmpty('Unnamed account');
  }


  String _initialFor(String value) {
    final text = value.trim();
    if (text.isEmpty) return '?';
    return text.substring(0, 1).toUpperCase();
  }

  Future<void> _openExhibitorEditor({
    Map<String, dynamic>? existing,
  }) async {
    final saved = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ExhibitorBuilderDialog(
        exhibitorId: existing?['id']?.toString(),
      ),
    );

    if (saved != null) {
      await _load();
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

      await _load();

      if (!mounted) return;
      setState(() {
        _message = newValue
            ? 'Account activated.'
            : 'Account deactivated.';
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

    final confirmed = await showDialog<bool>(
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

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const LoginScreen(),
      ),
      (_) => false,
    );
  }

  Future<void> _openTerms() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const TermsScreen(),
      ),
    );
  }

  Future<void> _openPrivacy() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const PrivacyPolicyScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Account Settings'),
        actions: [
          IconButton(
            tooltip: 'Add account',
            onPressed: _loading ? null : () => _openExhibitorEditor(),
            icon: const Icon(Icons.person_add_alt_1),
          ),
          IconButton(
            tooltip: 'Reload',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildProfileCard(theme),
                  const SizedBox(height: 16),
                  if (_message != null) ...[
                    _buildMessage(theme),
                    const SizedBox(height: 16),
                  ],
                  _buildAccountsHeader(theme),
                  const SizedBox(height: 10),
                  if (_exhibitors.isEmpty)
                    _buildEmptyState(theme)
                  else
                    ..._exhibitors.map(
                      (exhibitor) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _buildExhibitorCard(theme, exhibitor),
                      ),
                    ),
                  const SizedBox(height: 8),
                  _buildLegalCard(theme),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _signingOut ? null : _signOut,
                    icon: _signingOut
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.logout),
                    label: Text(_signingOut ? 'Signing out...' : 'Sign Out'),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _buildProfileCard(ThemeData theme) {
    final userEmail = _profileEmail ?? supabase.auth.currentUser?.email ?? '—';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 28,
              child: Text(
                _initialFor(_profileDisplayName ?? userEmail),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _profileDisplayName ?? 'RingMaster Club Account',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    userEmail,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: () => _openExhibitorEditor(),
                    icon: const Icon(Icons.person_add_alt_1),
                    label: const Text('Add Another Account'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessage(ThemeData theme) {
    final isError = _message!.toLowerCase().contains('unable') ||
        _message!.toLowerCase().contains('failed');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isError
            ? theme.colorScheme.errorContainer
            : theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        _message!,
        style: TextStyle(
          color: isError
              ? theme.colorScheme.onErrorContainer
              : theme.colorScheme.onSecondaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildAccountsHeader(ThemeData theme) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Linked Accounts',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Text(
          '${_exhibitors.length}',
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            Icon(
              Icons.person_add_alt_1_outlined,
              size: 46,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 14),
            Text(
              'No linked accounts',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Add an account to use RingMaster Club memberships and club activity.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () => _openExhibitorEditor(),
              icon: const Icon(Icons.add),
              label: const Text('Add Account'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExhibitorCard(
    ThemeData theme,
    Map<String, dynamic> exhibitor,
  ) {
    final name = _displayNameFor(exhibitor);
    final active = exhibitor['is_active'] == true;
    final isPrimary = exhibitor['is_primary'] == true;
    final type = _clean(exhibitor['account_type']);
    final email = _clean(exhibitor['email']);
    final phone = _clean(exhibitor['phone']);
    final city = _clean(exhibitor['city']);
    final state = _clean(exhibitor['state']);
    final arbaNumber = _clean(exhibitor['arba_number']);
    final importedFrom = _clean(exhibitor['imported_from']);

    final location = [city, state].whereType<String>().join(', ');

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: active
                  ? theme.colorScheme.primaryContainer
                  : theme.colorScheme.surfaceContainerHighest,
              child: Icon(
                type == 'group' || type == 'family'
                    ? Icons.groups_outlined
                    : Icons.person_outline,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _StatusChip(active: active),
                      if (isPrimary) ...[
                        const SizedBox(width: 8),
                        const Chip(
                          visualDensity: VisualDensity.compact,
                          avatar: Icon(Icons.star_outline, size: 17),
                          label: Text('Primary'),
                        ),
                      ],
                    ],
                  ),
                  if (type != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      type.replaceAll('_', ' ').toUpperCase(),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  if (email != null) _DetailLine(Icons.email_outlined, email),
                  if (phone != null) _DetailLine(Icons.phone_outlined, phone),
                  if (location.isNotEmpty)
                    _DetailLine(Icons.location_on_outlined, location),
                  if (arbaNumber != null)
                    _DetailLine(
                      Icons.badge_outlined,
                      'ARBA number: $arbaNumber',
                    ),
                  if (importedFrom == 'ringmaster_show')
                    const _DetailLine(
                      Icons.link,
                      'Linked from RingMaster Show',
                    ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Account actions',
              onSelected: (value) async {
                switch (value) {
                  case 'edit':
                    await _openExhibitorEditor(existing: exhibitor);
                    break;
                  case 'primary':
                    await _setPrimaryAccount(exhibitor);
                    break;
                  case 'activate':
                    await _confirmToggleActive(exhibitor, true);
                    break;
                  case 'deactivate':
                    await _confirmToggleActive(exhibitor, false);
                    break;
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: ListTile(
                    leading: Icon(Icons.edit_outlined),
                    title: Text('Edit'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                if (!isPrimary)
                  const PopupMenuItem(
                    value: 'primary',
                    child: ListTile(
                      leading: Icon(Icons.star_outline),
                      title: Text('Make Primary'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                PopupMenuItem(
                  value: active ? 'deactivate' : 'activate',
                  child: ListTile(
                    leading: Icon(
                      active
                          ? Icons.person_off_outlined
                          : Icons.person_outline,
                    ),
                    title: Text(active ? 'Deactivate' : 'Activate'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegalCard(ThemeData theme) {
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('Terms of Service'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _openTerms,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Privacy Policy'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _openPrivacy,
          ),
        ],
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  final IconData icon;
  final String text;

  const _DetailLine(this.icon, this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17),
          const SizedBox(width: 7),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final bool active;

  const _StatusChip({required this.active});

  @override
  Widget build(BuildContext context) {
    return Chip(
      visualDensity: VisualDensity.compact,
      label: Text(active ? 'Active' : 'Inactive'),
      avatar: Icon(
        active ? Icons.check_circle_outline : Icons.pause_circle_outline,
        size: 17,
      ),
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => trim().isEmpty ? fallback : this;
}
