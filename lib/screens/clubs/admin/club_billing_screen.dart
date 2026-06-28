

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../models/clubs/club_summary.dart';

final supabase = Supabase.instance.client;

class ClubBillingScreen extends StatefulWidget {
  const ClubBillingScreen({
    super.key,
    required this.club,
  });

  final ClubSummary club;

  @override
  State<ClubBillingScreen> createState() => _ClubBillingScreenState();
}

class _ClubBillingScreenState extends State<ClubBillingScreen> {
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;

  _ClubBillingSnapshot? _snapshot;

  @override
  void initState() {
    super.initState();
    _loadBilling();
  }

  Future<void> _loadBilling() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      Map<String, dynamic>? refreshedPaymentAccount;

      try {
        final connectStatusResponse = await supabase.functions.invoke(
          'stripe-club-connect-account-status',
          body: {
            'club_id': widget.club.clubId,
          },
        );

        if (connectStatusResponse.data is Map) {
          refreshedPaymentAccount = Map<String, dynamic>.from(
            connectStatusResponse.data as Map,
          );
        }
      } catch (_) {
        // Ignore Stripe Connect refresh errors so billing can still load.
      }

      final clubResponse = await supabase
          .from('clubs')
          .select(
            'id,name,billing_plan_key,billing_status,billing_member_limit,'
            'billing_current_period_end,accepts_member_online_payments,'
            'member_online_fee_mode,member_platform_fee_percent,'
            'membership_management_addon_enabled,'
            'sanction_requests_addon_enabled,'
            'events_meetings_addon_enabled,email_addon_enabled,'
            'sweepstakes_addon_enabled,storage_limit_bytes,'
            'show_token_discount_enabled,show_token_discount_percent,'
            'show_token_pack_discount_percent,show_unlimited_discount_percent',
          )
          .eq('id', widget.club.clubId)
          .single();

      final billingAccountResponse = await supabase
          .from('club_billing_accounts')
          .select('stripe_customer_id,billing_email')
          .eq('club_id', widget.club.clubId)
          .maybeSingle();

      final planResponse = await supabase
          .from('club_plan_subscriptions')
          .select(
            'plan_key,status,current_period_start,current_period_end,'
            'cancel_at_period_end,stripe_subscription_id',
          )
          .eq('club_id', widget.club.clubId)
          .maybeSingle();

      final addonResponse = await supabase
          .from('club_addon_subscriptions')
          .select(
            'add_on_key,status,current_period_start,current_period_end,'
            'cancel_at_period_end,stripe_subscription_id',
          )
          .eq('club_id', widget.club.clubId);

      final paymentAccountResponse = await supabase
          .from('club_payment_accounts')
          .select(
            'provider,stripe_account_id,charges_enabled,payouts_enabled,'
            'details_submitted,account_status',
          )
          .eq('club_id', widget.club.clubId)
          .eq('provider', 'stripe')
          .maybeSingle();

      if (!mounted) return;

      final paymentAccountRow = paymentAccountResponse == null
          ? refreshedPaymentAccount
          : Map<String, dynamic>.from(paymentAccountResponse);

      setState(() {
        _snapshot = _ClubBillingSnapshot.fromRows(
          club: Map<String, dynamic>.from(clubResponse),
          billingAccount: billingAccountResponse == null
              ? null
              : Map<String, dynamic>.from(billingAccountResponse),
          plan: planResponse == null
              ? null
              : Map<String, dynamic>.from(planResponse),
          addons: (addonResponse as List)
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList(),
          paymentAccount: paymentAccountRow,
        );
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Unable to load billing settings: $error';
      });
    }
  }

  Future<void> _updateMemberPaymentSettings({
    bool? acceptsOnlinePayments,
    String? feeMode,
  }) async {
    final snapshot = _snapshot;
    if (snapshot == null) return;

    setState(() => _isSaving = true);

    try {
      await supabase
          .from('clubs')
          .update({
            'accepts_member_online_payments':
                acceptsOnlinePayments ?? snapshot.acceptsMemberOnlinePayments,
            'member_online_fee_mode': feeMode ?? snapshot.memberOnlineFeeMode,
          })
          .eq('id', widget.club.clubId);

      await _loadBilling();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Billing settings updated.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to update billing settings: $error')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _openStripeFunctionUrl({
    required String functionName,
    required String actionLabel,
    Map<String, dynamic>? body,
  }) async {
    setState(() => _isSaving = true);

    try {
      final response = await supabase.functions.invoke(
        functionName,
        body: {
          'club_id': widget.club.clubId,
          'return_url': Uri.base.toString(),
          ...?body,
        },
      );

      final data = response.data;
      final url = data is Map ? data['url']?.toString() : null;
      final updated = data is Map && data['updated'] == true;

      if (url != null && url.isNotEmpty) {
        final uri = Uri.parse(url);
        final launched = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );

        if (!launched) {
          throw Exception('Unable to open $url');
        }
        return;
      }

      if (updated) {
        await _loadBilling();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_titleCase(actionLabel)} completed.')),
        );
        return;
      }

      throw Exception('No redirect URL or update confirmation was returned.');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to start $actionLabel: $error')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _startPlanCheckout() async {
    final selectedPlanKey = await showDialog<String>(
      context: context,
      builder: (context) => const _PlanPickerDialog(),
    );

    if (selectedPlanKey == null) return;

    return _openStripeFunctionUrl(
      functionName: 'stripe-club-billing-create-checkout',
      actionLabel: 'plan checkout',
      body: {
        'checkout_type': 'plan',
        'plan_key': selectedPlanKey,
      },
    );
  }

  Future<void> _startAddOnCheckout() async {
    final snapshot = _snapshot;
    if (snapshot == null) return;

    if (!snapshot.hasActiveBilling) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Choose a RingMaster Club plan before managing add-ons.'),
        ),
      );
      return;
    }

    final selection = await showDialog<_AddOnSelection>(
      context: context,
      builder: (context) => _AddOnPickerDialog(snapshot: snapshot),
    );

    if (selection == null || !mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _AddOnConfirmationDialog(selection: selection),
    );

    if (confirmed != true) return;

    return _openStripeFunctionUrl(
      functionName: 'stripe-club-billing-update-addons',
      actionLabel: 'add-on update',
      body: {
        'add_on_key': selection.addOnKey,
        'enabled': selection.enabled,
      },
    );
  }

  Future<void> _openBillingPortal() {
    return _openStripeFunctionUrl(
      functionName: 'stripe-club-billing-create-portal-link',
      actionLabel: 'billing portal',
    );
  }

  Future<void> _startStripeConnectOnboarding() {
    return _openStripeFunctionUrl(
      functionName: 'stripe-club-connect-start-onboarding',
      actionLabel: 'Stripe Connect onboarding',
    );
  }

  Future<void> _openStripeDashboard() {
    return _openStripeFunctionUrl(
      functionName: 'stripe-club-connect-create-login-link',
      actionLabel: 'Stripe Dashboard',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Billing & Add-ons'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _loadBilling,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final snapshot = _snapshot;
    if (_errorMessage != null && snapshot == null) {
      return _MessageState(
        icon: Icons.error_outline,
        title: 'Unable to load billing',
        message: _errorMessage!,
        actionLabel: 'Try Again',
        onAction: _loadBilling,
      );
    }

    if (snapshot == null) {
      return _MessageState(
        icon: Icons.receipt_long_outlined,
        title: 'No billing data',
        message: 'No billing settings were returned for this club.',
        actionLabel: 'Refresh',
        onAction: _loadBilling,
      );
    }

    return RefreshIndicator(
      onRefresh: _loadBilling,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          Text(
            widget.club.clubName,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'Manage RingMaster Club billing, add-ons, member payment settings, and Stripe setup.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          if (_errorMessage != null) ...[
            Material(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(_errorMessage!),
              ),
            ),
            const SizedBox(height: 16),
          ],
          _BillingOverviewCard(snapshot: snapshot),
          const SizedBox(height: 16),
          _PlanCard(
            snapshot: snapshot,
            isSaving: _isSaving,
            onManageBilling: _openBillingPortal,
            onChoosePlan: _startPlanCheckout,
          ),
          const SizedBox(height: 16),
          _AddOnsCard(
            snapshot: snapshot,
            isSaving: _isSaving,
            onManageAddOns: _startAddOnCheckout,
          ),
          const SizedBox(height: 16),
          _ShowDiscountCard(snapshot: snapshot),
          const SizedBox(height: 16),
          _MemberPaymentsCard(
            snapshot: snapshot,
            isSaving: _isSaving,
            onAcceptsOnlineChanged: (value) => _updateMemberPaymentSettings(
              acceptsOnlinePayments: value,
            ),
            onFeeModeChanged: (value) => _updateMemberPaymentSettings(
              feeMode: value,
            ),
            onConnectStripe: _startStripeConnectOnboarding,
            onOpenStripeDashboard: _openStripeDashboard,
          ),
          const SizedBox(height: 16),
          const _ManualPaymentsCard(),
        ],
      ),
    );
  }
}

class _PlanPickerDialog extends StatelessWidget {
  const _PlanPickerDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Choose a RingMaster Club plan'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            _PlanPickerTile(
              planKey: 'small_club_base',
              title: 'Small Club Base',
              price: r'$15/year',
              description:
                  'For clubs under 20 members. Includes Base Club Tools.',
            ),
            SizedBox(height: 10),
            _PlanPickerTile(
              planKey: 'standard_club_base',
              title: 'Standard Club Base',
              price: r'$99/year introductory',
              description:
                  'For clubs with 20 or more members. Includes Base Club Tools and RingMaster Show token discounts.',
            ),
            SizedBox(height: 10),
            _PlanPickerTile(
              planKey: 'standard_club_complete',
              title: 'Standard Club Complete',
              price: r'$300/year',
              description:
                  'Includes Base Club Tools, all current add-ons, 20GB storage, and the highest RingMaster Show token discounts.',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _PlanPickerTile extends StatelessWidget {
  const _PlanPickerTile({
    required this.planKey,
    required this.title,
    required this.price,
    required this.description,
  });

  final String planKey;
  final String title;
  final String price;
  final String description;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context).pop(planKey),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: scheme.primaryContainer,
                foregroundColor: scheme.onPrimaryContainer,
                child: const Icon(Icons.workspace_premium_outlined),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      price,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(description),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _BillingOverviewCard extends StatelessWidget {
  const _BillingOverviewCard({required this.snapshot});

  final _ClubBillingSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth >= 850
                ? (constraints.maxWidth - 24) / 3
                : constraints.maxWidth >= 560
                    ? (constraints.maxWidth - 12) / 2
                    : constraints.maxWidth;

            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: width,
                  child: _MiniMetric(
                    icon: Icons.workspace_premium_outlined,
                    label: 'Current Plan',
                    value: snapshot.planLabel,
                    helper: _titleCase(snapshot.billingStatus),
                  ),
                ),
                SizedBox(
                  width: width,
                  child: _MiniMetric(
                    icon: Icons.extension_outlined,
                    label: 'Enabled Add-ons',
                    value: snapshot.enabledAddOnCount.toString(),
                    helper: 'of ${_AddonDefinition.all.length}',
                  ),
                ),
                SizedBox(
                  width: width,
                  child: _MiniMetric(
                    icon: Icons.payments_outlined,
                    label: 'Member Fee Mode',
                    value: snapshot.memberOnlineFeeMode == 'member_pays'
                        ? 'Member Pays'
                        : 'Club Absorbs',
                    helper: 'Payment processing costs & RingMaster fees ${snapshot.memberPlatformFeePercent.toStringAsFixed(0)}%',
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.snapshot,
    required this.isSaving,
    required this.onManageBilling,
    required this.onChoosePlan,
  });

  final _ClubBillingSnapshot snapshot;
  final bool isSaving;
  final VoidCallback onManageBilling;
  final VoidCallback onChoosePlan;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      icon: Icons.workspace_premium_outlined,
      title: 'RingMaster Club Plan',
      subtitle: 'Yearly billing for this club\'s RingMaster Club access.',
      trailing: _StatusChip(label: _titleCase(snapshot.billingStatus)),
      children: [
        _DetailRow(label: 'Plan', value: snapshot.planLabel),
        _DetailRow(label: 'Billing status', value: _titleCase(snapshot.billingStatus)),
        _DetailRow(
          label: 'Renews on',
          value: snapshot.renewalDate == null
              ? '—'
              : _formatDate(snapshot.renewalDate!),
        ),
        _DetailRow(
          label: 'Member limit',
          value: snapshot.billingMemberLimit == null
              ? '—'
              : snapshot.billingMemberLimit.toString(),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: isSaving
                  ? null
                  : snapshot.hasActiveBilling
                      ? onManageBilling
                      : onChoosePlan,
              icon: Icon(
                snapshot.hasActiveBilling
                    ? Icons.open_in_new
                    : Icons.shopping_cart_checkout,
              ),
              label: Text(snapshot.hasActiveBilling ? 'Manage Plan' : 'Choose Plan'),
            ),
            OutlinedButton.icon(
              onPressed: isSaving || !snapshot.hasActiveBilling
                  ? null
                  : onManageBilling,
              icon: const Icon(Icons.open_in_new),
              label: const Text('Manage Billing'),
            ),
          ],
        ),
      ],
    );
  }
}

class _AddOnsCard extends StatelessWidget {
  const _AddOnsCard({
    required this.snapshot,
    required this.isSaving,
    required this.onManageAddOns,
  });

  final _ClubBillingSnapshot snapshot;
  final bool isSaving;
  final VoidCallback onManageAddOns;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      icon: Icons.extension_outlined,
      title: 'Add-ons',
      subtitle: 'Add-on status is controlled by active billing subscriptions.',
      trailing: _StatusChip(label: '${snapshot.enabledAddOnCount} enabled'),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final addon in _AddonDefinition.all)
              _FeatureChip(
                label: addon.label,
                enabled: snapshot.addOnEnabled(addon.key),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: isSaving || !snapshot.hasActiveBilling
                ? null
                : onManageAddOns,
            icon: const Icon(Icons.tune_outlined),
            label: const Text('Manage Add-ons'),
          ),
        ),
      ],
    );
  }
}

class _AddOnSelection {
  const _AddOnSelection({
    required this.addOnKey,
    required this.enabled,
  });

  final String addOnKey;
  final bool enabled;
}

class _AddOnPickerDialog extends StatelessWidget {
  const _AddOnPickerDialog({required this.snapshot});

  final _ClubBillingSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Manage add-ons'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'For test mode, only Storage 20GB is enabled. Other add-ons will be enabled when live Stripe prices are used.',
            ),
            const SizedBox(height: 14),
            for (final addon in _AddonDefinition.all) ...[
              _AddOnPickerTile(
                addon: addon,
                enabled: snapshot.addOnEnabled(addon.key),
                selectable: addon.key == 'storage_20gb',
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _AddOnPickerTile extends StatelessWidget {
  const _AddOnPickerTile({
    required this.addon,
    required this.enabled,
    required this.selectable,
  });

  final _AddonDefinition addon;
  final bool enabled;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final actionText = enabled ? 'Remove' : 'Add';

    return Material(
      color: selectable
          ? scheme.surfaceContainerHighest
          : scheme.surfaceContainerHighest.withAlpha((0.55 * 255).toInt()),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: selectable
            ? () => Navigator.of(context).pop(
                  _AddOnSelection(
                    addOnKey: addon.key,
                    enabled: !enabled,
                  ),
                )
            : null,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: enabled
                    ? scheme.primaryContainer
                    : scheme.surfaceContainerHighest,
                foregroundColor: enabled
                    ? scheme.onPrimaryContainer
                    : scheme.onSurfaceVariant,
                child: Icon(enabled ? Icons.check_circle_outline : Icons.lock_outline),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      addon.label,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      selectable
                          ? '$actionText this add-on with Stripe proration.'
                          : 'Not available in test mode yet.',
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (selectable)
                TextButton(
                  onPressed: () => Navigator.of(context).pop(
                    _AddOnSelection(
                      addOnKey: addon.key,
                      enabled: !enabled,
                    ),
                  ),
                  child: Text(actionText),
                )
              else
                const Icon(Icons.lock_outline),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddOnConfirmationDialog extends StatelessWidget {
  const _AddOnConfirmationDialog({required this.selection});

  final _AddOnSelection selection;

  @override
  Widget build(BuildContext context) {
    final addOn = _AddonDefinition.labelFor(selection.addOnKey);
    final action = selection.enabled ? 'Add' : 'Remove';
    final description = selection.enabled
        ? 'Stripe will add this add-on to the club subscription using proration. If a card is saved on file, Stripe may automatically charge the card for the prorated amount due today. The amount due today may be adjusted based on the time remaining in the current billing period.'
        : 'Stripe will remove this add-on from the club subscription using proration. Any credit will be handled by Stripe according to the billing settings.';

    return AlertDialog(
      title: Text('$action $addOn?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(description),
          const SizedBox(height: 14),
          if (selection.addOnKey == 'storage_20gb')
            const Text(
              'Storage 20GB is \$29/year. The final prorated amount and any automatic card charge will be calculated by Stripe.',
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text('$action Add-on'),
        ),
      ],
    );
  }
}

class _ShowDiscountCard extends StatelessWidget {
  const _ShowDiscountCard({required this.snapshot});

  final _ClubBillingSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      icon: Icons.local_offer_outlined,
      title: 'RingMaster Show Discount',
      subtitle: 'Discounts for RingMaster Show tokens are based on the active club plan.',
      trailing: _StatusChip(
        label: snapshot.showTokenDiscountEnabled ? 'Enabled' : 'Not enabled',
      ),
      children: [
        _DetailRow(
          label: 'Single show tokens',
          value: '${snapshot.showTokenDiscountPercent.toStringAsFixed(0)}% off',
        ),
        _DetailRow(
          label: '4-pack show tokens',
          value: '${snapshot.showTokenPackDiscountPercent.toStringAsFixed(0)}% off',
        ),
        _DetailRow(
          label: 'Unlimited show plan',
          value: '${snapshot.showUnlimitedDiscountPercent.toStringAsFixed(0)}% off',
        ),
      ],
    );
  }
}

class _MemberPaymentsCard extends StatelessWidget {
  const _MemberPaymentsCard({
    required this.snapshot,
    required this.isSaving,
    required this.onAcceptsOnlineChanged,
    required this.onFeeModeChanged,
    required this.onConnectStripe,
    required this.onOpenStripeDashboard,
  });

  final _ClubBillingSnapshot snapshot;
  final bool isSaving;
  final ValueChanged<bool> onAcceptsOnlineChanged;
  final ValueChanged<String> onFeeModeChanged;
  final VoidCallback onConnectStripe;
  final VoidCallback onOpenStripeDashboard;

  @override
  Widget build(BuildContext context) {
    final paymentAccount = snapshot.paymentAccount;
    final stripeReady = paymentAccount?.accountStatus == 'ready';

    return _SectionCard(
      icon: Icons.credit_card_outlined,
      title: 'Member Payment Setup',
      subtitle:
          'Use Stripe Connect for online member dues, renewals, and sanction payments.',
      trailing: _StatusChip(
        label: paymentAccount?.statusLabel ?? 'Not connected',
      ),
      children: [
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: snapshot.acceptsMemberOnlinePayments,
          onChanged: isSaving || !stripeReady ? null : onAcceptsOnlineChanged,
          title: const Text('Accept online member payments'),
          subtitle: Text(
            stripeReady
                ? 'Members can pay online when this setting is enabled for this club.'
                : 'Stripe Connect must be ready before online member payments can be used.',
          ),
        ),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: 'member_pays',
              label: Text('Member pays fees'),
              icon: Icon(Icons.person_outline),
            ),
            ButtonSegment(
              value: 'club_absorbs',
              label: Text('Club absorbs fees'),
              icon: Icon(Icons.account_balance_outlined),
            ),
          ],
          selected: {snapshot.memberOnlineFeeMode},
          onSelectionChanged: isSaving
              ? null
              : (values) => onFeeModeChanged(values.first),
        ),
        const SizedBox(height: 12),
        Text(
          'This controls both Stripe processing fees and the ${snapshot.memberPlatformFeePercent.toStringAsFixed(0)}% RingMaster platform fee for member online payments.',
        ),
        const SizedBox(height: 12),
        _DetailRow(
          label: 'Stripe Connect status',
          value: paymentAccount?.statusLabel ?? 'Not connected',
        ),
        _DetailRow(
          label: 'Charges enabled',
          value: paymentAccount?.chargesEnabled == true ? 'Yes' : 'No',
        ),
        _DetailRow(
          label: 'Payouts enabled',
          value: paymentAccount?.payoutsEnabled == true ? 'Yes' : 'No',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: isSaving ? null : onConnectStripe,
              icon: const Icon(Icons.account_balance_wallet_outlined),
              label: Text(paymentAccount == null ? 'Connect Stripe' : 'Update Stripe Setup'),
            ),
            OutlinedButton.icon(
              onPressed: isSaving || paymentAccount?.stripeAccountId == null
                  ? null
                  : onOpenStripeDashboard,
              icon: const Icon(Icons.open_in_new),
              label: const Text('Stripe Dashboard'),
            ),
          ],
        ),
      ],
    );
  }
}

class _ManualPaymentsCard extends StatelessWidget {
  const _ManualPaymentsCard();

  @override
  Widget build(BuildContext context) {
    return const _SectionCard(
      icon: Icons.payments_outlined,
      title: 'Manual Payment Methods',
      subtitle:
          'Clubs can record payments received outside RingMaster Club with audit details.',
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _FeatureChip(label: 'Cash', enabled: true),
            _FeatureChip(label: 'Check', enabled: true),
            _FeatureChip(label: 'PayPal', enabled: true),
            _FeatureChip(label: 'Venmo', enabled: true),
            _FeatureChip(label: 'Square', enabled: true),
            _FeatureChip(label: 'Zelle', enabled: true),
            _FeatureChip(label: 'Money Order', enabled: true),
            _FeatureChip(label: 'Other', enabled: true),
            _FeatureChip(label: 'Comped/Waived', enabled: true),
          ],
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.children,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: scheme.primaryContainer,
                  foregroundColor: scheme.onPrimaryContainer,
                  child: Icon(icon),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(subtitle),
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 12),
                  trailing!,
                ],
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric({
    required this.icon,
    required this.label,
    required this.value,
    this.helper,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(child: Icon(icon)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label),
              const SizedBox(height: 4),
              Text(
                value,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              if (helper != null) ...[
                const SizedBox(height: 4),
                Text(helper!),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 180,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _FeatureChip extends StatelessWidget {
  const _FeatureChip({required this.label, required this.enabled});

  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Chip(
      avatar: Icon(
        enabled ? Icons.check_circle_outline : Icons.lock_outline,
        size: 18,
      ),
      label: Text(label),
      backgroundColor:
          enabled ? scheme.primaryContainer : scheme.surfaceContainerHighest,
      side: BorderSide(
        color: enabled ? scheme.primary : scheme.outlineVariant,
      ),
      visualDensity: VisualDensity.compact,
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
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            children: [
              Icon(icon, size: 64),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 10),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.refresh),
                label: Text(actionLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClubBillingSnapshot {
  const _ClubBillingSnapshot({
    required this.planKey,
    required this.billingStatus,
    required this.billingMemberLimit,
    required this.billingCurrentPeriodEnd,
    required this.acceptsMemberOnlinePayments,
    required this.memberOnlineFeeMode,
    required this.memberPlatformFeePercent,
    required this.addOnFlags,
    required this.showTokenDiscountEnabled,
    required this.showTokenDiscountPercent,
    required this.showTokenPackDiscountPercent,
    required this.showUnlimitedDiscountPercent,
    required this.stripeCustomerId,
    required this.billingEmail,
    required this.planSubscription,
    required this.addonSubscriptions,
    required this.paymentAccount,
  });

  final String planKey;
  final String billingStatus;
  final int? billingMemberLimit;
  final DateTime? billingCurrentPeriodEnd;
  final bool acceptsMemberOnlinePayments;
  final String memberOnlineFeeMode;
  final double memberPlatformFeePercent;
  final Map<String, bool> addOnFlags;
  final bool showTokenDiscountEnabled;
  final double showTokenDiscountPercent;
  final double showTokenPackDiscountPercent;
  final double showUnlimitedDiscountPercent;
  final String? stripeCustomerId;
  final String? billingEmail;
  final _PlanSubscription? planSubscription;
  final Map<String, _AddonSubscription> addonSubscriptions;
  final _ClubPaymentAccount? paymentAccount;

  bool get hasActiveBilling => billingStatus == 'active' || billingStatus == 'trialing';

  DateTime? get renewalDate =>
      billingCurrentPeriodEnd ?? planSubscription?.currentPeriodEnd;

  String get planLabel => _planLabel(planKey);

  int get enabledAddOnCount =>
      addOnFlags.values.where((enabled) => enabled).length;

  bool addOnEnabled(String key) => addOnFlags[key] == true;

  factory _ClubBillingSnapshot.fromRows({
    required Map<String, dynamic> club,
    required Map<String, dynamic>? billingAccount,
    required Map<String, dynamic>? plan,
    required List<Map<String, dynamic>> addons,
    required Map<String, dynamic>? paymentAccount,
  }) {
    return _ClubBillingSnapshot(
      planKey: _stringValue(club['billing_plan_key'], fallback: 'none'),
      billingStatus: _stringValue(club['billing_status'], fallback: 'inactive'),
      billingMemberLimit: _nullableInt(club['billing_member_limit']),
      billingCurrentPeriodEnd: _dateValue(club['billing_current_period_end']),
      acceptsMemberOnlinePayments:
          club['accepts_member_online_payments'] == true,
      memberOnlineFeeMode:
          _stringValue(club['member_online_fee_mode'], fallback: 'member_pays'),
      memberPlatformFeePercent:
          _doubleValue(club['member_platform_fee_percent'], fallback: 2),
      addOnFlags: {
        'membership_management':
            club['membership_management_addon_enabled'] == true,
        'sanction_requests': club['sanction_requests_addon_enabled'] == true,
        'events_meetings': club['events_meetings_addon_enabled'] == true,
        'email': club['email_addon_enabled'] == true,
        'sweepstakes': club['sweepstakes_addon_enabled'] == true,
        'storage_20gb': _intValue(club['storage_limit_bytes']) >= 21474836480,
      },
      showTokenDiscountEnabled: club['show_token_discount_enabled'] == true,
      showTokenDiscountPercent: _doubleValue(club['show_token_discount_percent']),
      showTokenPackDiscountPercent:
          _doubleValue(club['show_token_pack_discount_percent']),
      showUnlimitedDiscountPercent:
          _doubleValue(club['show_unlimited_discount_percent']),
      stripeCustomerId: _nullableString(billingAccount?['stripe_customer_id']),
      billingEmail: _nullableString(billingAccount?['billing_email']),
      planSubscription:
          plan == null ? null : _PlanSubscription.fromJson(plan),
      addonSubscriptions: {
        for (final addon in addons)
          _stringValue(addon['add_on_key'], fallback: ''):
              _AddonSubscription.fromJson(addon),
      }..remove(''),
      paymentAccount: paymentAccount == null
          ? null
          : _ClubPaymentAccount.fromJson(paymentAccount),
    );
  }
}

class _PlanSubscription {
  const _PlanSubscription({
    required this.planKey,
    required this.status,
    required this.currentPeriodEnd,
    required this.cancelAtPeriodEnd,
    required this.stripeSubscriptionId,
  });

  final String planKey;
  final String status;
  final DateTime? currentPeriodEnd;
  final bool cancelAtPeriodEnd;
  final String? stripeSubscriptionId;

  factory _PlanSubscription.fromJson(Map<String, dynamic> json) {
    return _PlanSubscription(
      planKey: _stringValue(json['plan_key'], fallback: 'none'),
      status: _stringValue(json['status'], fallback: 'inactive'),
      currentPeriodEnd: _dateValue(json['current_period_end']),
      cancelAtPeriodEnd: json['cancel_at_period_end'] == true,
      stripeSubscriptionId: _nullableString(json['stripe_subscription_id']),
    );
  }
}

class _AddonSubscription {
  const _AddonSubscription({
    required this.addOnKey,
    required this.status,
    required this.currentPeriodEnd,
    required this.cancelAtPeriodEnd,
    required this.stripeSubscriptionId,
  });

  final String addOnKey;
  final String status;
  final DateTime? currentPeriodEnd;
  final bool cancelAtPeriodEnd;
  final String? stripeSubscriptionId;

  factory _AddonSubscription.fromJson(Map<String, dynamic> json) {
    return _AddonSubscription(
      addOnKey: _stringValue(json['add_on_key'], fallback: ''),
      status: _stringValue(json['status'], fallback: 'inactive'),
      currentPeriodEnd: _dateValue(json['current_period_end']),
      cancelAtPeriodEnd: json['cancel_at_period_end'] == true,
      stripeSubscriptionId: _nullableString(json['stripe_subscription_id']),
    );
  }
}

class _ClubPaymentAccount {
  const _ClubPaymentAccount({
    required this.provider,
    required this.stripeAccountId,
    required this.chargesEnabled,
    required this.payoutsEnabled,
    required this.detailsSubmitted,
    required this.accountStatus,
  });

  final String provider;
  final String? stripeAccountId;
  final bool chargesEnabled;
  final bool payoutsEnabled;
  final bool detailsSubmitted;
  final String accountStatus;

  String get statusLabel {
    switch (accountStatus) {
      case 'ready':
        return 'Ready';
      case 'restricted':
        return 'Connected - needs attention';
      case 'pending_onboarding':
        return 'Connected - setup incomplete';
      default:
        return 'Not connected';
    }
  }

  factory _ClubPaymentAccount.fromJson(Map<String, dynamic> json) {
    return _ClubPaymentAccount(
      provider: _stringValue(json['provider'], fallback: 'stripe'),
      stripeAccountId: _nullableString(json['stripe_account_id']),
      chargesEnabled: json['charges_enabled'] == true,
      payoutsEnabled: json['payouts_enabled'] == true,
      detailsSubmitted: json['details_submitted'] == true,
      accountStatus: _stringValue(
        json['account_status'],
        fallback: 'not_connected',
      ),
    );
  }
}

class _AddonDefinition {
  const _AddonDefinition({required this.key, required this.label});

  final String key;
  final String label;

  static const all = [
    _AddonDefinition(key: 'membership_management', label: 'Membership Management'),
    _AddonDefinition(key: 'sanction_requests', label: 'Sanction Management'),
    _AddonDefinition(key: 'events_meetings', label: 'Events & Meetings'),
    _AddonDefinition(key: 'email', label: 'Email'),
    _AddonDefinition(key: 'sweepstakes', label: 'Sweepstakes'),
    _AddonDefinition(key: 'storage_20gb', label: 'Storage 20GB'),
  ];

  static String labelFor(String key) {
    for (final addon in all) {
      if (addon.key == key) return addon.label;
    }
    return key;
  }
}

String _planLabel(String key) {
  switch (key) {
    case 'small_club_base':
      return 'Small Club Base';
    case 'standard_club_base':
      return 'Standard Club Base';
    case 'standard_club_complete':
      return 'Standard Club Complete';
    default:
      return 'No Active Plan';
  }
}

String? _nullableString(dynamic value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

String _stringValue(dynamic value, {required String fallback}) {
  return _nullableString(value) ?? fallback;
}

int _intValue(dynamic value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

int? _nullableInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

double _doubleValue(dynamic value, {double fallback = 0}) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? fallback;
}

DateTime? _dateValue(dynamic value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) return null;
  return DateTime.tryParse(text);
}

String _formatDate(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '$month/$day/${value.year}';
}

String _titleCase(String value) {
  return value
      .split(RegExp(r'[_\s-]+'))
      .where((part) => part.isNotEmpty)
      .map(
        (part) => '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
      )
      .join(' ');
}