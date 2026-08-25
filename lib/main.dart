// lib/main.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/app_versions.dart';
import 'config/supabase_config.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'theme/app_theme.dart';

final supabase = Supabase.instance.client;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await pdfrxFlutterInitialize();

  SupabaseConfig.validate();

  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.anonKey,
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
      builder: (context, child) {
        return DecoratedBox(
          decoration: const BoxDecoration(
            gradient: AppColors.clubBackgroundGradient,
          ),
          child: Stack(
            children: [
              child ?? const SizedBox.shrink(),
              const _VersionBanner(),
            ],
          ),
        );
      },
      home: const Root(),
    );
  }
}

class _VersionBanner extends StatelessWidget {
  const _VersionBanner();

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          width: double.infinity,
          color: const Color(0xFFE7ECE9),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Text(
              'Version $kRingMasterClubAppVersion',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF66706B),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    ),
  );
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

    _claimPendingStaffInvitations();
    _authSubscription = supabase.auth.onAuthStateChange.listen((_) {
      _claimPendingStaffInvitations();
      if (mounted) {
        setState(() {});
      }
    });
  }

  Future<void> _claimPendingStaffInvitations() async {
    if (supabase.auth.currentSession == null) return;
    try {
      await supabase.rpc('claim_pending_club_staff_invitations');
    } catch (_) {
      // An invitation must never prevent a user from signing in. The next
      // authenticated session retries the claim if a migration is pending.
    }
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

    return const HomeScreen();
  }
}
