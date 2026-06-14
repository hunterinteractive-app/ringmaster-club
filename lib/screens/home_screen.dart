// lib/screens/home_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/legal_config.dart';
import 'account_profile_setup_screen.dart';
import 'legal/privacy_policy_screen.dart';
import 'legal/terms_screen.dart';
import 'login_screen.dart';
import 'account_settings_screen.dart';

final supabase = Supabase.instance.client;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _checkingLegal = true;
  String? _displayName;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeHome();
    });
  }

  Future<void> _initializeHome() async {
    final user = supabase.auth.currentUser;

    if (user == null) {
      _returnToLogin();
      return;
    }

    try {
      final profile = await supabase
          .from('profiles')
          .select(
            'display_name, accepted_terms_version, accepted_privacy_version',
          )
          .eq('user_id', user.id)
          .maybeSingle();

      final termsAccepted =
          profile?['accepted_terms_version'] == LegalConfig.currentTermsVersion;
      final privacyAccepted = profile?['accepted_privacy_version'] ==
          LegalConfig.currentPrivacyVersion;

      if (!termsAccepted || !privacyAccepted) {
        if (!mounted) return;

        final agreed = await _showLegalAgreementDialog();

        if (!agreed) {
          await supabase.auth.signOut();
          _returnToLogin();
          return;
        }

        final now = DateTime.now().toUtc().toIso8601String();
        final fallbackName = _nameFromUser(user);

        await supabase.from('profiles').upsert(
          {
            'user_id': user.id,
            'email': user.email,
            'display_name':
                _cleanText(profile?['display_name']) ?? fallbackName,
            'accepted_terms_version': LegalConfig.currentTermsVersion,
            'accepted_terms_at': now,
            'accepted_privacy_version': LegalConfig.currentPrivacyVersion,
            'accepted_privacy_at': now,
          },
          onConflict: 'user_id',
        );
      }

      final accountReady = await _ensureRequiredAccountSetup(user.id);
      if (!accountReady || !mounted) return;

      final primaryDisplayName =
          await _ensureAndLoadPrimaryDisplayName(user.id);

      if (!mounted) return;

      final refreshedProfile = await supabase
          .from('profiles')
          .select('display_name')
          .eq('user_id', user.id)
          .maybeSingle();

      if (!mounted) return;

      setState(() {
        _displayName =
            primaryDisplayName ??
            _cleanText(refreshedProfile?['display_name']) ??
            _cleanText(profile?['display_name']) ??
            _nameFromUser(user);
        _checkingLegal = false;
      });
    } catch (error) {
      if (!mounted) return;

      final retry = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Unable to Verify Account'),
              content: Text(
                'RingMaster Club could not finish verifying your legal agreement or account information.\n\n$error',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Sign Out'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Try Again'),
                ),
              ],
            ),
          ) ??
          false;

      if (!mounted) return;

      if (retry) {
        await _initializeHome();
      } else {
        await supabase.auth.signOut();
        _returnToLogin();
      }
    }
  }

  Future<bool> _ensureRequiredAccountSetup(String userId) async {
    final existingRows = await supabase
        .from('exhibitors')
        .select('id')
        .eq('owner_user_id', userId)
        .eq('is_active', true)
        .limit(1);

    if ((existingRows as List).isNotEmpty) {
      return true;
    }

    final lookupResponse = await supabase.functions.invoke(
      'import-ringmaster-show-account',
      method: HttpMethod.post,
      body: const {
        'action': 'lookup',
      },
    );

    final lookupData = lookupResponse.data is Map
        ? Map<String, dynamic>.from(lookupResponse.data as Map)
        : <String, dynamic>{};

    final status = (lookupData['status'] ?? '').toString();

    if (status == 'already_exists' || status == 'imported') {
      return true;
    }

    if (status == 'link_confirmation_required') {
      final rawMatches = lookupData['matches'];
      final matches = rawMatches is List
          ? rawMatches
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList()
          : <Map<String, dynamic>>[];

      if (matches.isEmpty) {
        return await _openManualAccountSetup();
      }

      final exhibitorIds = await _showShowAccountLinkDialog(matches);

      if (exhibitorIds == null || exhibitorIds.isEmpty) {
        return await _openManualAccountSetup();
      }

      final importResponse = await supabase.functions.invoke(
        'import-ringmaster-show-account',
        method: HttpMethod.post,
        body: {
          'action': 'import',
          'exhibitor_ids': exhibitorIds,
        },
      );

      final importData = importResponse.data is Map
          ? Map<String, dynamic>.from(importResponse.data as Map)
          : <String, dynamic>{};

      final importStatus = (importData['status'] ?? '').toString();

      if (importStatus == 'imported' || importStatus == 'already_exists') {
        return true;
      }

      if (importStatus == 'incomplete_match') {
        final rawRecords = importData['records'];
        final records = rawRecords is List
            ? rawRecords
                .whereType<Map>()
                .map((row) => Map<String, dynamic>.from(row))
                .toList()
            : <Map<String, dynamic>>[];

        final details = records.map((record) {
          final name =
              (record['display_name'] ?? record['exhibitor_id'] ?? 'Account')
                  .toString();
          final rawMissing = record['missing_fields'];
          final missing = rawMissing is List
              ? rawMissing.map((value) => value.toString()).join(', ')
              : 'required account information';
          return '$name: $missing';
        }).join('\n');

        throw Exception(
          details.isEmpty
              ? 'One or more selected RingMaster Show accounts are missing required information.'
              : 'The following information is missing:\n$details',
        );
      }

      throw Exception(
        (importData['message'] ??
                'Unable to link your RingMaster Show account. Status: $importStatus')
            .toString(),
      );
    }

    if (status == 'not_found' ||
        status == 'multiple_matches' ||
        status == 'incomplete_match') {
      if (mounted) {
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: const Text('RingMaster Show Account Not Linked'),
            content: Text(
              status == 'not_found'
                  ? 'No eligible RingMaster Show account was found using your signed-in email address.'
                  : status == 'multiple_matches'
                      ? 'More than one RingMaster Show account was found, but the import service did not return enough information to confirm them.'
                      : 'A RingMaster Show account was found, but required information is missing. Please complete the setup form.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Continue'),
              ),
            ],
          ),
        );
      }

      return await _openManualAccountSetup();
    }

    throw Exception(
      (lookupData['message'] ??
              'Unable to check your RingMaster Show account. Status: $status')
          .toString(),
    );
  }

  Future<bool> _openManualAccountSetup() async {
    if (!mounted) return false;

    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const AccountProfileSetupScreen(),
      ),
    );

    return saved == true;
  }

  Future<List<String>?> _showShowAccountLinkDialog(
    List<Map<String, dynamic>> matches,
  ) async {
    final selectedIds = <String>{
      for (final match in matches)
        if ((match['id'] ?? '').toString().isNotEmpty)
          (match['id'] ?? '').toString(),
    };

    return showDialog<List<String>>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('RingMaster Show Account Found'),
              content: SizedBox(
                width: 560,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Select the RingMaster Show account records you want to link to RingMaster Club:',
                      ),
                      const SizedBox(height: 16),
                      ...matches.map((match) {
                        final id = (match['id'] ?? '').toString();
                        final name =
                            (match['display_name'] ?? 'Unnamed account')
                                .toString();
                        final city = (match['city'] ?? '').toString().trim();
                        final state = (match['state'] ?? '').toString().trim();
                        final phone =
                            (match['phone_last_four'] ?? '').toString().trim();
                        final accountType =
                            (match['account_type'] ?? '').toString().trim();
                        final location = [city, state]
                            .where((value) => value.isNotEmpty)
                            .join(', ');

                        final details = <String>[
                          if (accountType.isNotEmpty)
                            accountType.replaceAll('_', ' '),
                          if (location.isNotEmpty) location,
                          if (phone.isNotEmpty) 'Phone ending in $phone',
                        ].join(' • ');

                        return CheckboxListTile(
                          value: selectedIds.contains(id),
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text(
                            name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          subtitle: details.isEmpty ? null : Text(details),
                          onChanged: id.isEmpty
                              ? null
                              : (selected) {
                                  setDialogState(() {
                                    if (selected == true) {
                                      selectedIds.add(id);
                                    } else {
                                      selectedIds.remove(id);
                                    }
                                  });
                                },
                        );
                      }),
                      const SizedBox(height: 8),
                      const Text(
                        'Only the selected records will be copied. Existing RingMaster Show records will not be changed.',
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(null),
                  child: const Text('Create New Instead'),
                ),
                FilledButton.icon(
                  onPressed: selectedIds.isEmpty
                      ? null
                      : () => Navigator.of(dialogContext).pop(
                            selectedIds.toList(),
                          ),
                  icon: const Icon(Icons.link),
                  label: Text(
                    selectedIds.length == 1
                        ? 'Link 1 Account'
                        : 'Link ${selectedIds.length} Accounts',
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<String?> _ensureAndLoadPrimaryDisplayName(
    String userId,
  ) async {
    final rows = await supabase
        .from('exhibitors')
        .select(
          'id,account_type,display_name,showing_name,first_name,last_name,'
          'birth_date,is_primary,is_active,created_at',
        )
        .eq('owner_user_id', userId)
        .eq('is_active', true)
        .order('created_at', ascending: true);

    final exhibitors = (rows as List)
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();

    if (exhibitors.isEmpty) return null;

    Map<String, dynamic>? primary;

    for (final exhibitor in exhibitors) {
      if (exhibitor['is_primary'] == true) {
        primary = exhibitor;
        break;
      }
    }

    primary ??= _preferredPrimaryExhibitor(exhibitors);

    final primaryId = primary['id']?.toString();
    if (primaryId == null || primaryId.isEmpty) return null;

    final displayName = _exhibitorDisplayName(primary);
    final now = DateTime.now().toUtc().toIso8601String();

    if (primary['is_primary'] != true) {
      await supabase
          .from('exhibitors')
          .update({
            'is_primary': false,
            'updated_at': now,
          })
          .eq('owner_user_id', userId)
          .eq('is_primary', true);

      await supabase
          .from('exhibitors')
          .update({
            'is_primary': true,
            'updated_at': now,
          })
          .eq('id', primaryId)
          .eq('owner_user_id', userId);
    }

    final user = supabase.auth.currentUser;

    if (displayName != null && user != null) {
      await supabase.from('profiles').upsert(
        {
          'user_id': user.id,
          'email': user.email,
          'display_name': displayName,
          'updated_at': now,
        },
        onConflict: 'user_id',
      );
    }

    return displayName;
  }

  Map<String, dynamic> _preferredPrimaryExhibitor(
    List<Map<String, dynamic>> exhibitors,
  ) {
    final sorted = [...exhibitors];

    sorted.sort((a, b) {
      final aYouth = _isYouthExhibitor(a);
      final bYouth = _isYouthExhibitor(b);

      if (aYouth != bYouth) {
        return aYouth ? 1 : -1;
      }

      final aBirthDate = DateTime.tryParse(
        (a['birth_date'] ?? '').toString(),
      );
      final bBirthDate = DateTime.tryParse(
        (b['birth_date'] ?? '').toString(),
      );

      if (aBirthDate != null && bBirthDate != null) {
        return aBirthDate.compareTo(bBirthDate);
      }

      if (aBirthDate != null) return -1;
      if (bBirthDate != null) return 1;

      return (a['created_at'] ?? '')
          .toString()
          .compareTo((b['created_at'] ?? '').toString());
    });

    return sorted.first;
  }

  bool _isYouthExhibitor(
    Map<String, dynamic> exhibitor,
  ) {
    final accountType = (exhibitor['account_type'] ?? '')
        .toString()
        .trim()
        .toLowerCase();

    if (accountType.contains('youth') ||
        accountType.contains('child')) {
      return true;
    }

    final birthDate = DateTime.tryParse(
      (exhibitor['birth_date'] ?? '').toString(),
    );

    if (birthDate == null) return false;

    final now = DateTime.now();
    var age = now.year - birthDate.year;

    final birthdayOccurred =
        now.month > birthDate.month ||
        (now.month == birthDate.month && now.day >= birthDate.day);

    if (!birthdayOccurred) {
      age--;
    }

    return age < 18;
  }

  String? _exhibitorDisplayName(
    Map<String, dynamic> exhibitor,
  ) {
    final directName =
        _cleanText(exhibitor['display_name']) ??
        _cleanText(exhibitor['showing_name']);

    if (directName != null) return directName;

    final firstName = _cleanText(exhibitor['first_name']);
    final lastName = _cleanText(exhibitor['last_name']);

    final generated = [firstName, lastName]
        .whereType<String>()
        .join(' ')
        .trim();

    return generated.isEmpty ? null : generated;
  }

  Future<void> _openAccountSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const AccountSettingsScreen(),
      ),
    );

    if (!mounted) return;

    final user = supabase.auth.currentUser;
    if (user == null) return;

    final primaryDisplayName =
        await _ensureAndLoadPrimaryDisplayName(user.id);

    if (!mounted || primaryDisplayName == null) return;

    setState(() {
      _displayName = primaryDisplayName;
    });
  }

  String? _cleanText(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  String _nameFromUser(User user) {
    final metadataName = _cleanText(user.userMetadata?['display_name']) ??
        _cleanText(user.userMetadata?['full_name']) ??
        _cleanText(user.userMetadata?['name']);

    if (metadataName != null) return metadataName;

    final email = user.email?.trim();
    if (email != null && email.contains('@')) {
      return email.split('@').first;
    }

    return 'Member';
  }

  void _returnToLogin() {
    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  Future<bool> _showLegalAgreementDialog() async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) {
            var agreed = false;

            return StatefulBuilder(
              builder: (context, setDialogState) {
                return AlertDialog(
                  title: const Text('Terms & Privacy Agreement'),
                  content: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Before continuing, please review and accept the '
                            'current RingMaster Club Terms of Service and '
                            'Privacy Policy.',
                          ),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton.icon(
                                icon: const Icon(Icons.description_outlined),
                                label: const Text('Terms of Service'),
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => const TermsScreen(),
                                    ),
                                  );
                                },
                              ),
                              OutlinedButton.icon(
                                icon: const Icon(Icons.privacy_tip_outlined),
                                label: const Text('Privacy Policy'),
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const PrivacyPolicyScreen(),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          CheckboxListTile(
                            value: agreed,
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: const Text(
                              'I have reviewed and agree to the current Terms '
                              'of Service and Privacy Policy.',
                            ),
                            onChanged: (value) {
                              setDialogState(() {
                                agreed = value ?? false;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () {
                        Navigator.of(dialogContext).pop(false);
                      },
                      child: const Text('Sign Out'),
                    ),
                    FilledButton(
                      onPressed: agreed
                          ? () {
                              Navigator.of(dialogContext).pop(true);
                            }
                          : null,
                      child: const Text('Agree & Continue'),
                    ),
                  ],
                );
              },
            );
          },
        ) ??
        false;
  }

  Future<void> _signOut() async {
    await supabase.auth.signOut();
    _returnToLogin();
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingLegal) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('RingMaster Club'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Account menu',
            onSelected: (value) {
            switch (value) {
              case 'account':
                _openAccountSettings();
                break;
                case 'terms':
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const TermsScreen()),
                  );
                  break;
                case 'privacy':
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const PrivacyPolicyScreen(),
                    ),
                  );
                  break;
                case 'logout':
                  _signOut();
                  break;
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'account',
                child: ListTile(
                  leading: Icon(Icons.manage_accounts_outlined),
                  title: Text('Account Settings'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: 'terms',
                child: ListTile(
                  leading: Icon(Icons.description_outlined),
                  title: Text('Terms of Service'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'privacy',
                child: ListTile(
                  leading: Icon(Icons.privacy_tip_outlined),
                  title: Text('Privacy Policy'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: 'logout',
                child: ListTile(
                  leading: Icon(Icons.logout),
                  title: Text('Sign Out'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: CircleAvatar(
                child: Icon(Icons.person_outline),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          colorScheme.primaryContainer,
                          colorScheme.secondaryContainer,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Welcome, ${_displayName ?? 'Member'}!',
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Your central home for RingMaster Club tools, '
                          'resources, and membership information.',
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth >= 900
                          ? 3
                          : constraints.maxWidth >= 600
                              ? 2
                              : 1;
                      const spacing = 16.0;
                      final width =
                          (constraints.maxWidth - spacing * (columns - 1)) /
                              columns;

                      return Wrap(
                        spacing: spacing,
                        runSpacing: spacing,
                        children: [
                          _HomeActionCard(
                            width: width,
                            icon: Icons.groups_outlined,
                            title: 'My Clubs',
                            description:
                                'View and manage your club memberships.',
                            onTap: () => _comingSoon('My Clubs'),
                          ),
                          _HomeActionCard(
                            width: width,
                            icon: Icons.event_outlined,
                            title: 'Events',
                            description:
                                'Review upcoming club meetings and events.',
                            onTap: () => _comingSoon('Events'),
                          ),
                          _HomeActionCard(
                            width: width,
                            icon: Icons.folder_outlined,
                            title: 'Resources',
                            description:
                                'Access club documents, forms, and resources.',
                            onTap: () => _comingSoon('Resources'),
                          ),
                          _HomeActionCard(
                            width: width,
                            icon: Icons.campaign_outlined,
                            title: 'Announcements',
                            description:
                                'See the latest news from your organizations.',
                            onTap: () => _comingSoon('Announcements'),
                          ),
                          _HomeActionCard(
                            width: width,
                            icon: Icons.badge_outlined,
                            title: 'Membership',
                            description:
                                'Review your membership details and status.',
                            onTap: () => _comingSoon('Membership'),
                          ),
                          _HomeActionCard(
                            width: width,
                            icon: Icons.settings_outlined,
                            title: 'Account Settings',
                            description:
                                'Update your profile and account preferences.',
                          onTap: _openAccountSettings,
                          ),
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
  }

  void _comingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature is coming soon.')),
    );
  }
}

class _HomeActionCard extends StatelessWidget {
  const _HomeActionCard({
    required this.width,
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final double width;
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  icon,
                  size: 36,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      'Open',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_forward, size: 18),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
