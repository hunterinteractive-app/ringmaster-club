// lib/screens/login_screen.dart

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_theme.dart';
import 'legal/privacy_policy_screen.dart';
import 'legal/terms_screen.dart';
import '../widgets/rm_widgets.dart';
import 'home_screen.dart';

final supabase = Supabase.instance.client;

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  StreamSubscription<AuthState>? _authSubscription;
  Timer? _resendTimer;

  late final AnimationController _animationController;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;
  late final Animation<double> _cardFade;
  late final Animation<Offset> _cardSlide;

  String? _pendingEmail;
  String? _message;
  bool _busy = false;
  bool _showLogin = false;
  bool _awaitingCode = false;
  bool _handlingAuthCallback = false;
  int _resendSeconds = 0;

  int _logoTapCount = 0;
  DateTime? _lastLogoTapAt;

  static const String _devLoginEmail = 'test@ringmaster.dev';
  static const String _devLoginPassword = 'Smile!987';
  bool _navigatingHome = false;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _logoScale = Tween<double>(begin: 0.9, end: 1).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOutCubic,
      ),
    );

    _logoFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0, 0.5, curve: Curves.easeOut),
      ),
    );

    _cardFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.35, 1, curve: Curves.easeOut),
      ),
    );

    _cardSlide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.35, 1, curve: Curves.easeOutCubic),
      ),
    );

    _animationController.forward();

    Future<void>.delayed(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      setState(() => _showLogin = true);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleAuthCallbackIfPresent();
    });

    _authSubscription = supabase.auth.onAuthStateChange.listen((data) {
      if (!mounted || data.session == null) return;
      _goHome();
    });
  }
  void _goHome() {
    if (!mounted || _navigatingHome) return;

    _navigatingHome = true;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => const HomeScreen(),
      ),
      (_) => false,
    );
  }


  @override
  void dispose() {
    _authSubscription?.cancel();
    _resendTimer?.cancel();
    _animationController.dispose();
    _emailController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _handleLogoTap() async {
    if (kReleaseMode || _busy) return;

    final now = DateTime.now();

    if (_lastLogoTapAt == null ||
        now.difference(_lastLogoTapAt!) > const Duration(seconds: 4)) {
      _logoTapCount = 0;
    }

    _lastLogoTapAt = now;
    _logoTapCount++;

    await HapticFeedback.selectionClick();

    if (_logoTapCount >= 7) {
      _logoTapCount = 0;
      await _devLogin();
    }
  }

  Future<void> _devLogin() async {
    if (_devLoginEmail.isEmpty || _devLoginPassword.isEmpty) {
      if (!mounted) return;
      setState(() {
        _message =
            'Error: Dev login is not configured. Provide DEV_LOGIN_EMAIL and DEV_LOGIN_PASSWORD with --dart-define.';
      });
      return;
    }

    setState(() {
      _busy = true;
      _message = 'Dev login triggered...';
    });

    try {
      await supabase.auth.signInWithPassword(
        email: _devLoginEmail,
        password: _devLoginPassword,
      );

      if (!mounted) return;
      _goHome();
    } on AuthException catch (error) {
      if (!mounted) return;
      setState(() => _message = 'Error: Dev login failed: ${error.message}');
    } catch (_) {
      if (!mounted) return;
      setState(() => _message = 'Error: Dev login failed.');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _handleAuthCallbackIfPresent() async {
    if (_handlingAuthCallback) return;

    final uri = Uri.base;
    final code = uri.queryParameters['code']?.trim();
    final tokenHash = uri.queryParameters['token_hash']?.trim();

    final hasCode = code != null && code.isNotEmpty;
    final hasTokenHash = tokenHash != null && tokenHash.isNotEmpty;

    if (!hasCode && !hasTokenHash) return;

    _handlingAuthCallback = true;

    if (mounted) {
      setState(() {
        _busy = true;
        _message = 'Finishing login...';
      });
    }

    try {
      if (hasTokenHash) {
        final type = switch (uri.queryParameters['type']?.trim()) {
          'signup' => OtpType.signup,
          'recovery' => OtpType.recovery,
          'invite' => OtpType.invite,
          'email_change' => OtpType.emailChange,
          _ => OtpType.magiclink,
        };

        await supabase.auth.verifyOTP(
          tokenHash: tokenHash,
          type: type,
        );
      } else if (hasCode) {
        await supabase.auth.exchangeCodeForSession(code);
      }

      if (!mounted) return;
      _goHome();
    } on AuthException catch (error) {
      if (!mounted) return;
      setState(() => _message = 'Error: ${error.message}');
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _message = 'Error: Unable to finish login. Please request a new code.';
      });
    } finally {
      _handlingAuthCallback = false;
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _startResendCountdown() {
    _resendTimer?.cancel();
    setState(() => _resendSeconds = 60);

    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_resendSeconds <= 1) {
        timer.cancel();
        setState(() => _resendSeconds = 0);
        return;
      }

      setState(() => _resendSeconds--);
    });
  }

  Future<void> _sendCode({bool isResend = false}) async {
    FocusScope.of(context).unfocus();

    if (!isResend && !_formKey.currentState!.validate()) return;

    final email = isResend
        ? (_pendingEmail ?? '').trim().toLowerCase()
        : _emailController.text.trim().toLowerCase();

    if (email.isEmpty) {
      setState(() => _message = 'Error: Enter your email address first.');
      return;
    }

    setState(() {
      _busy = true;
      _message = null;
    });

    try {
      await supabase.auth.signInWithOtp(
        email: email,
        shouldCreateUser: true,
      );

      if (!mounted) return;

      _otpController.clear();
      setState(() {
        _pendingEmail = email;
        _awaitingCode = true;
        _message = isResend
            ? 'A new login code was sent to $email.'
            : 'Enter the 6-digit login code sent to $email.';
      });
      _startResendCountdown();
    } on AuthException catch (error) {
      if (!mounted) return;
      setState(() => _message = 'Error: ${error.message}');
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _message = 'Error: Unable to send the login code. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _verifyCode() async {
    FocusScope.of(context).unfocus();

    final email = (_pendingEmail ?? '').trim().toLowerCase();
    final code = _otpController.text.replaceAll(RegExp(r'\D'), '');

    if (email.isEmpty) {
      setState(() {
        _awaitingCode = false;
        _message = 'Error: Enter your email and request a new code.';
      });
      return;
    }

    if (code.length != 6) {
      setState(() {
        _message = 'Error: Enter the complete 6-digit login code.';
      });
      return;
    }

    setState(() {
      _busy = true;
      _message = 'Verifying your login code...';
    });

    try {
      final response = await supabase.auth.verifyOTP(
        email: email,
        token: code,
        type: OtpType.email,
      );

      if (response.session == null) {
        throw const AuthException('The login code could not be verified.');
      }

      if (!mounted) return;
      _goHome();
    } on AuthException catch (error) {
      if (!mounted) return;

      final lowerMessage = error.message.toLowerCase();
      setState(() {
        _message = lowerMessage.contains('expired')
            ? 'Error: This code has expired. Request a new code and try again.'
            : 'Error: The code is invalid or has already been used.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _message = 'Error: Unable to verify the login code. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _changeEmail() {
    FocusScope.of(context).unfocus();
    _resendTimer?.cancel();
    _otpController.clear();

    setState(() {
      _pendingEmail = null;
      _awaitingCode = false;
      _resendSeconds = 0;
      _message = null;
    });
  }

  String? _validateEmail(String? value) {
    final email = (value ?? '').trim();

    if (email.isEmpty) return 'Email is required.';
    if (!email.contains('@') || !email.contains('.')) {
      return 'Enter a valid email.';
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.navyDark,
              AppColors.navy,
              AppColors.clubGreenLight,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FadeTransition(
                      opacity: _logoFade,
                      child: ScaleTransition(
                        scale: _logoScale,
                        child: _ClubBranding(
                          onLogoTap: _handleLogoTap,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    if (_showLogin)
                      FadeTransition(
                        opacity: _cardFade,
                        child: SlideTransition(
                          position: _cardSlide,
                          child: RMCard(
                            padding: const EdgeInsets.all(AppSpacing.xl),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    _awaitingCode
                                        ? 'Enter your login code'
                                        : 'Log in or create your RingMaster Club account',
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                  const SizedBox(height: AppSpacing.sm),
                                  Text(
                                    _awaitingCode
                                        ? 'We sent a 6-digit code to ${_pendingEmail ?? ''}.'
                                        : 'Enter your email to receive a secure 6-digit code for membership, club tools, and account access.',
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                  const SizedBox(height: AppSpacing.xl),
                                  if (!_awaitingCode) ...[
                                    TextFormField(
                                      controller: _emailController,
                                      enabled: !_busy,
                                      keyboardType: TextInputType.emailAddress,
                                      autofillHints: const [AutofillHints.email],
                                      textInputAction: TextInputAction.done,
                                      validator: _validateEmail,
                                      onFieldSubmitted: (_) {
                                        if (!_busy) _sendCode();
                                      },
                                      decoration: const InputDecoration(
                                        labelText: 'Email address',
                                        prefixIcon: Icon(Icons.email_outlined),
                                      ),
                                    ),
                                    const SizedBox(height: AppSpacing.lg),
                                    SizedBox(
                                      height: 52,
                                      child: FilledButton.icon(
                                        onPressed:
                                            _busy ? null : () => _sendCode(),
                                        icon: _busy
                                            ? const SizedBox(
                                                width: 18,
                                                height: 18,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: Colors.white,
                                                ),
                                              )
                                            : const Icon(Icons.send_outlined),
                                        label: Text(
                                          _busy ? 'Sending...' : 'Send login code',
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: AppSpacing.md),
                                    Text(
                                      'The code can only be used once and will expire after 20 minutes.',
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                    const SizedBox(height: AppSpacing.md),
                                    Text(
                                      'By continuing, you agree to the RingMaster Club Terms of Service and Privacy Policy.',
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                    const SizedBox(height: AppSpacing.xs),
                                    Wrap(
                                      alignment: WrapAlignment.center,
                                      spacing: AppSpacing.sm,
                                      children: [
                                        TextButton(
                                          onPressed: () {
                                            Navigator.of(context).push(
                                              MaterialPageRoute<void>(
                                                builder: (_) => const TermsScreen(),
                                              ),
                                            );
                                          },
                                          child: const Text('Terms of Service'),
                                        ),
                                        TextButton(
                                          onPressed: () {
                                            Navigator.of(context).push(
                                              MaterialPageRoute<void>(
                                                builder: (_) => const PrivacyPolicyScreen(),
                                              ),
                                            );
                                          },
                                          child: const Text('Privacy Policy'),
                                        ),
                                      ],
                                    ),
                                  ] else ...[
                                    TextField(
                                      controller: _otpController,
                                      enabled: !_busy,
                                      keyboardType: TextInputType.number,
                                      textInputAction: TextInputAction.done,
                                      maxLength: 6,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 26,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 8,
                                      ),
                                      onChanged: (value) {
                                        final digits = value.replaceAll(
                                          RegExp(r'\D'),
                                          '',
                                        );
                                        if (digits.length == 6 && !_busy) {
                                          _verifyCode();
                                        }
                                      },
                                      onSubmitted: (_) {
                                        if (!_busy) _verifyCode();
                                      },
                                      decoration: const InputDecoration(
                                        labelText: '6-digit code',
                                        counterText: '',
                                      ),
                                    ),
                                    const SizedBox(height: AppSpacing.lg),
                                    SizedBox(
                                      height: 52,
                                      child: FilledButton.icon(
                                        onPressed: _busy ? null : _verifyCode,
                                        icon: _busy
                                            ? const SizedBox(
                                                width: 18,
                                                height: 18,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: Colors.white,
                                                ),
                                              )
                                            : const Icon(Icons.login),
                                        label: Text(
                                          _busy ? 'Verifying...' : 'Sign In',
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: AppSpacing.md),
                                    Wrap(
                                      alignment: WrapAlignment.center,
                                      spacing: AppSpacing.sm,
                                      runSpacing: AppSpacing.sm,
                                      children: [
                                        TextButton(
                                          onPressed:
                                              _busy ? null : _changeEmail,
                                          child: const Text('Change Email'),
                                        ),
                                        TextButton(
                                          onPressed: _busy ||
                                                  _resendSeconds > 0
                                              ? null
                                              : () =>
                                                  _sendCode(isResend: true),
                                          child: Text(
                                            _resendSeconds > 0
                                                ? 'Resend in $_resendSeconds s'
                                                : 'Resend Code',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                  if (_message != null) ...[
                                    const SizedBox(height: AppSpacing.lg),
                                    Container(
                                      padding: const EdgeInsets.all(AppSpacing.md),
                                      decoration: BoxDecoration(
                                        color: _message!.startsWith('Error:')
                                            ? AppColors.dangerBg
                                            : AppColors.successBg,
                                        borderRadius: BorderRadius.circular(
                                          AppRadius.sm,
                                        ),
                                      ),
                                      child: Text(
                                        _message!,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: _message!.startsWith('Error:')
                                              ? AppColors.danger
                                              : AppColors.success,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ClubBranding extends StatelessWidget {
  const _ClubBranding({
    required this.onLogoTap,
  });

  final VoidCallback onLogoTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onLogoTap,
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12),
              ),
            ),
            child: Image.asset(
              'assets/images/ringmaster_club_logo.png',
              height: 145,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
              errorBuilder: (context, error, stackTrace) {
                return const SizedBox(
                  width: 145,
                  height: 145,
                  child: Icon(
                    Icons.groups_2_outlined,
                    size: 72,
                    color: Colors.white,
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        const Text(
          'RingMaster Club',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Modern membership, communication, and club management in one place.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.84),
            fontSize: 14,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}