// lib/main.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/supabase_config.dart';
import 'screens/login_screen.dart';
import 'theme/app_theme.dart';

final supabase = Supabase.instance.client;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SupabaseConfig.validate();

  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
  );

  runApp(const RingMasterClubApp());
}

class RingMasterClubApp extends StatelessWidget {
  const RingMasterClubApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RingMaster Club',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const Root(),
    );
  }
}

class Root extends StatefulWidget {
  const Root({super.key});

  @override
  State<Root> createState() => _RootState();
}

class _RootState extends State<Root> {
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();

    _authSubscription = supabase.auth.onAuthStateChange.listen((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = supabase.auth.currentSession;

    if (session == null) {
      return const LoginScreen();
    }

    return const _ClubHomePlaceholder();
  }
}

class _ClubHomePlaceholder extends StatelessWidget {
  const _ClubHomePlaceholder();

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('RingMaster Club'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            onPressed: () async {
              await Supabase.instance.client.auth.signOut();
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.groups_2_outlined,
                size: 72,
              ),
              const SizedBox(height: 16),
              Text(
                'RingMaster Club is ready to build.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                user?.email ?? 'Signed in',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}