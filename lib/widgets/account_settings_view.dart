import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

String? _text(dynamic value) {
  final text = (value ?? '').toString().trim();
  return text.isEmpty ? null : text;
}

String accountDisplayName(Map<String, dynamic> account) =>
    _text(account['display_name']) ??
    _text(account['showing_name']) ??
    _text(
      [
        _text(account['first_name']),
        _text(account['last_name']),
      ].whereType<String>().join(' '),
    ) ??
    'Unnamed account';

class AccountSettingsView extends StatelessWidget {
  const AccountSettingsView({
    super.key,
    required this.loading,
    required this.hasLoaded,
    required this.signingOut,
    required this.displayName,
    required this.email,
    required this.accounts,
    required this.onRefresh,
    required this.onAdd,
    required this.onEdit,
    required this.onMakePrimary,
    required this.onToggleActive,
    required this.onTerms,
    required this.onPrivacy,
    required this.onSignOut,
    this.message,
  });

  final bool loading;
  final bool hasLoaded;
  final bool signingOut;
  final String? displayName;
  final String? email;
  final List<Map<String, dynamic>> accounts;
  final String? message;
  final Future<void> Function() onRefresh;
  final VoidCallback onAdd;
  final ValueChanged<Map<String, dynamic>> onEdit;
  final ValueChanged<Map<String, dynamic>> onMakePrimary;
  final void Function(Map<String, dynamic>, bool) onToggleActive;
  final VoidCallback onTerms;
  final VoidCallback onPrivacy;
  final VoidCallback onSignOut;

  bool get _busy => loading || signingOut;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.clubCardNavy,
    appBar: AppBar(
      backgroundColor: AppColors.clubCardNavy,
      title: const Text('Account settings'),
      actions: [
        IconButton(
          tooltip: 'Refresh account settings',
          onPressed: _busy ? null : onRefresh,
          icon: const Icon(Icons.refresh),
        ),
        const SizedBox(width: 12),
      ],
    ),
    body: RefreshIndicator(
      onRefresh: onRefresh,
      child: SingleChildScrollView(
        key: const PageStorageKey('account-settings-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 48),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1280),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Your account, organized',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Manage the people and groups you use for club activity.',
                  style: TextStyle(color: AppColors.offWhite),
                ),
                const SizedBox(height: 24),
                if (loading) ...[
                  const LinearProgressIndicator(
                    minHeight: 2,
                    color: AppColors.gold,
                  ),
                  const SizedBox(height: 20),
                ],
                if (message != null) ...[
                  _panel(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          message!,
                          style: const TextStyle(color: AppColors.gold),
                        ),
                        if (!hasLoaded) ...[
                          const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed: _busy ? null : onRefresh,
                            child: const Text('Try again'),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
                LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth >= 900) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _accounts()),
                          const SizedBox(width: 24),
                          SizedBox(
                            width: 300,
                            child: Column(
                              children: [
                                _profile(),
                                const SizedBox(height: 20),
                                _policies(),
                              ],
                            ),
                          ),
                        ],
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _profile(),
                        const SizedBox(height: 24),
                        _accounts(),
                        const SizedBox(height: 24),
                        _policies(),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _profile() => _panel(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.person_outline, color: AppColors.gold, size: 28),
        const SizedBox(height: 14),
        const Text(
          'SIGNED-IN ACCOUNT',
          style: TextStyle(
            fontSize: 10,
            letterSpacing: 1.4,
            color: AppColors.offWhite,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          hasLoaded
              ? displayName ?? 'RingMaster Club account'
              : 'Account information',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          hasLoaded
              ? email ?? 'No email available'
              : 'Your sign-in details will appear here.',
          style: const TextStyle(color: AppColors.offWhite),
        ),
        if (hasLoaded) ...[
          const SizedBox(height: 18),
          Text(
            '${accounts.where((account) => account['is_active'] == true).length} active · ${accounts.length} linked accounts',
            style: const TextStyle(fontSize: 12, color: AppColors.offWhite),
          ),
        ],
      ],
    ),
  );

  Widget _accounts() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          const Expanded(
            child: Text(
              'Linked accounts',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            key: const ValueKey('add-account'),
            onPressed: _busy ? null : onAdd,
            icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
            label: const Text('Add account'),
          ),
        ],
      ),
      const SizedBox(height: 8),
      const Text(
        'Your primary account supplies the name shown in your workspace.',
        style: TextStyle(color: AppColors.offWhite),
      ),
      const SizedBox(height: 16),
      if (!hasLoaded)
        _panel(
          Text(
            loading
                ? 'Loading linked accounts…'
                : 'Linked accounts could not be loaded.',
            style: const TextStyle(color: AppColors.offWhite),
          ),
        )
      else if (accounts.isEmpty)
        _panel(
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.person_add_alt_1_outlined,
                color: AppColors.gold,
                size: 28,
              ),
              SizedBox(height: 12),
              Text(
                'No linked accounts',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 8),
              Text(
                'Add a personal, youth, family, or group account to get started.',
                style: TextStyle(color: AppColors.offWhite),
              ),
            ],
          ),
        )
      else
        for (final account in accounts) ...[
          _account(account),
          const SizedBox(height: 16),
        ],
    ],
  );

  Widget _account(Map<String, dynamic> account) {
    final active = account['is_active'] == true;
    final primary = account['is_primary'] == true;
    final type = _text(account['account_type']);
    final location = [
      _text(account['city']),
      _text(account['state']),
    ].whereType<String>().join(', ');
    return _panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                type == 'group' || type == 'family'
                    ? Icons.groups_outlined
                    : Icons.person_outline,
                color: AppColors.gold,
                size: 26,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  accountDisplayName(account),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              PopupMenuButton<bool>(
                tooltip: 'Status actions for ${accountDisplayName(account)}',
                enabled: !_busy,
                onSelected: (value) => onToggleActive(account, value),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: !active,
                    child: Text(
                      active ? 'Deactivate account' : 'Activate account',
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _badge(
                active ? 'Active' : 'Inactive',
                active
                    ? Icons.check_circle_outline
                    : Icons.pause_circle_outline,
              ),
              if (primary) _badge('Primary', Icons.star_outline),
              if (type != null)
                _badge(type.replaceAll('_', ' '), Icons.badge_outlined),
            ],
          ),
          const SizedBox(height: 16),
          if (_text(account['email']) case final String email)
            _detail(Icons.email_outlined, email),
          if (_text(account['phone']) case final String phone)
            _detail(Icons.phone_outlined, phone),
          if (location.isNotEmpty)
            _detail(Icons.location_on_outlined, location),
          if (_text(account['arba_number']) case final String number)
            _detail(Icons.badge_outlined, 'ARBA number: $number'),
          if (account['imported_from'] == 'ringmaster_show')
            _detail(Icons.link, 'Linked from RingMaster Show'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                key: ValueKey('edit-account-${account['id']}'),
                onPressed: _busy ? null : () => onEdit(account),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Edit account'),
              ),
              if (!primary)
                TextButton.icon(
                  key: ValueKey('primary-account-${account['id']}'),
                  onPressed: _busy ? null : () => onMakePrimary(account),
                  icon: const Icon(Icons.star_outline, size: 18),
                  label: const Text('Make primary'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _policies() => _panel(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Policies & session',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(
            Icons.description_outlined,
            color: AppColors.gold,
          ),
          title: const Text('Terms of Service'),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTerms,
        ),
        const Divider(color: AppColors.clubDivider, height: 1),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(
            Icons.privacy_tip_outlined,
            color: AppColors.gold,
          ),
          title: const Text('Privacy Policy'),
          trailing: const Icon(Icons.chevron_right),
          onTap: onPrivacy,
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          key: const ValueKey('account-sign-out'),
          onPressed: _busy ? null : onSignOut,
          icon: signingOut
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.logout, size: 18),
          label: Text(signingOut ? 'Signing out…' : 'Sign out'),
        ),
      ],
    ),
  );

  Widget _panel(Widget child) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: AppColors.clubCardNavyLight,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.clubDivider),
    ),
    child: child,
  );

  Widget _badge(String label, IconData icon) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: AppColors.clubCardNavy,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: AppColors.gold),
        const SizedBox(width: 6),
        Flexible(child: Text(label, style: const TextStyle(fontSize: 12))),
      ],
    ),
  );

  Widget _detail(IconData icon, String label) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 17, color: AppColors.offWhite),
        const SizedBox(width: 8),
        Expanded(
          child: Text(label, style: const TextStyle(color: AppColors.offWhite)),
        ),
      ],
    ),
  );
}
