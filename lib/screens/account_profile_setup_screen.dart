// lib/screens/account_profile_setup_screen.dart

import 'package:flutter/material.dart';

import '../widgets/exhibitor_builder_dialog.dart';

class AccountProfileSetupScreen extends StatefulWidget {
  final String? exhibitorId;

  const AccountProfileSetupScreen({
    super.key,
    this.exhibitorId,
  });

  @override
  State<AccountProfileSetupScreen> createState() =>
      _AccountProfileSetupScreenState();
}

class _AccountProfileSetupScreenState
    extends State<AccountProfileSetupScreen> {
  bool _opening = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openBuilder();
    });
  }

  Future<void> _openBuilder() async {
    if (_opening || !mounted) return;

    setState(() {
      _opening = true;
      _message = null;
    });

    try {
      final saved = await showDialog<Map<String, dynamic>>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ExhibitorBuilderDialog(
          exhibitorId: widget.exhibitorId,
        ),
      );

      if (!mounted) return;

      if (saved != null) {
        Navigator.of(context).pop(true);
        return;
      }

      Navigator.of(context).pop(false);
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _opening = false;
        _message = 'Unable to open account setup: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.exhibitorId != null;

    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('RingMaster Club'),
        ),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 700),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.account_circle_outlined,
                      size: 72,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      isEdit
                          ? 'Opening account information...'
                          : 'Let’s finish setting up your account.',
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      isEdit
                          ? 'Your saved account information will open in a moment.'
                          : 'RingMaster Club requires your account information before you can continue.',
                      style: Theme.of(context).textTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 28),
                    if (_opening) const CircularProgressIndicator(),
                    if (_message != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .errorContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _message!,
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onErrorContainer,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _opening ? null : _openBuilder,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Try Again'),
                      ),
                    ],
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