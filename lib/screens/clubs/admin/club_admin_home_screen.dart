import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/clubs/club_management_overview.dart';
import '../../../models/clubs/club_summary.dart';
import '../../../services/clubs/club_management_service.dart';
import 'club_billing_screen.dart';
import 'club_communications_screen.dart';
import 'club_documents_screen.dart';
import 'club_events_screen.dart';
import 'club_management_dashboard.dart';
import 'club_management_destination.dart';
import 'club_members_screen.dart';
import 'club_payments_screen.dart';
import 'club_reports_screen.dart';
import 'club_settings_screen.dart';
import 'club_staff_permissions_screen.dart';
import 'club_sweepstakes_screen.dart';
import 'membership_applications_screen.dart';
import 'membership_types_screen.dart';
import 'sanction_requests_screen.dart';
import 'sanction_types_screen.dart';

class ClubAdminHomeScreen extends StatefulWidget {
  const ClubAdminHomeScreen({
    super.key,
    required this.club,
    this.backLabel = 'Back to my clubs',
    this.overviewLoader,
    this.destinationBuilder,
  });

  final ClubSummary club;
  final String backLabel;
  final Future<ClubManagementOverview> Function()? overviewLoader;
  final Widget Function(BuildContext, ClubManagementDestination)?
  destinationBuilder;

  @override
  State<ClubAdminHomeScreen> createState() => _ClubAdminHomeScreenState();
}

class _ClubAdminHomeScreenState extends State<ClubAdminHomeScreen> {
  final _navigator = GlobalKey<NavigatorState>();
  final _scaffold = GlobalKey<ScaffoldState>();
  final _updates = ValueNotifier(0);
  late final NavigatorObserver _observer = _WorkspaceObserver(
    _navigationChanged,
  );
  ClubManagementDestination _selected = ClubManagementDestination.dashboard;
  ClubManagementOverview? _overview;
  bool _loading = true;
  bool _requestInFlight = false;
  bool _contentCanPop = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.club.canManageClub) _loadOverview();
  }

  Future<void> _loadOverview() async {
    if (!widget.club.canManageClub) return;
    if (_requestInFlight) return;
    _requestInFlight = true;
    if (!_loading) {
      setState(() => _loading = true);
      _updates.value++;
    }
    try {
      final overview =
          await (widget.overviewLoader?.call() ??
              ClubManagementService(
                Supabase.instance.client,
              ).load(widget.club.clubId));
      if (!mounted) return;
      setState(() {
        _overview = overview;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _overview == null
            ? 'The club overview could not be loaded. Your tools are still available.'
            : 'The refresh failed. The figures below are from the last successful update.';
      });
    }
    _requestInFlight = false;
    _updates.value++;
  }

  void _navigationChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final canPop = _navigator.currentState?.canPop() ?? false;
      if (canPop != _contentCanPop) setState(() => _contentCanPop = canPop);
    });
  }

  void _leaveWorkspace() {
    final workspaceRoute = ModalRoute.of(context);
    if (workspaceRoute == null || workspaceRoute.isFirst) {
      _scaffold.currentState?.closeDrawer();
      return;
    }
    // A drawer adds local history to this route. Pop through that entry as
    // well as the workspace, so the return action works with one tap.
    Navigator.of(context).popUntil((route) => route != workspaceRoute);
  }

  void _open(
    ClubManagementDestination destination, {
    String memberFilter = 'all',
    bool importRoster = false,
  }) {
    _scaffold.currentState?.closeDrawer();
    if (destination == _selected && memberFilter == 'all' && !importRoster) {
      _navigator.currentState?.popUntil((route) => route.isFirst);
      return;
    }
    setState(() => _selected = destination);
    _navigator.currentState!.pushAndRemoveUntil<void>(
      PageRouteBuilder<void>(
        settings: RouteSettings(name: '/club-management/${destination.name}'),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (context, _, _) =>
            destination == ClubManagementDestination.dashboard
            ? _OverviewHost(owner: this)
            : _ToolHost(
                owner: this,
                destination: destination,
                memberFilter: memberFilter,
                importRoster: importRoster,
              ),
      ),
      (_) => false,
    );
    if (destination == ClubManagementDestination.dashboard && !_loading) {
      _loadOverview();
    }
  }

  Widget _tool(
    BuildContext context,
    ClubManagementDestination destination,
    String memberFilter,
    bool importRoster,
  ) {
    final features = _overview?.features;
    if (destination.requiresFeature &&
        (features == null || !destination.available(features))) {
      return Scaffold(
        appBar: AppBar(title: Text(destination.label)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    features == null
                        ? Icons.cloud_off_outlined
                        : Icons.lock_outline,
                    size: 36,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    features == null
                        ? 'Club tools are unavailable'
                        : '${destination.label} is not enabled',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    features == null
                        ? 'Refresh to check which tools are available for this club.'
                        : 'The club owner can manage available tools in Billing & plan.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: features == null
                        ? (_loading ? null : _loadOverview)
                        : () => _open(ClubManagementDestination.billing),
                    child: Text(
                      features == null ? 'Try again' : 'View billing & plan',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    final override = widget.destinationBuilder;
    if (override != null) return override(context, destination);
    final club = widget.club;
    return switch (destination) {
      ClubManagementDestination.dashboard => const SizedBox.shrink(),
      ClubManagementDestination.members => ClubMembersScreen(
        club: club,
        initialStatusFilter: memberFilter,
        openMembershipListUpload: importRoster,
      ),
      ClubManagementDestination.applications => MembershipApplicationsScreen(
        club: club,
        initialStatusFilter: 'review',
      ),
      ClubManagementDestination.payments => ClubPaymentsScreen(club: club),
      ClubManagementDestination.sanctions => SanctionRequestsScreen(club: club),
      ClubManagementDestination.sweepstakes => ClubSweepstakesScreen(
        club: club,
      ),
      ClubManagementDestination.events => ClubEventsScreen(club: club),
      ClubManagementDestination.communications => ClubCommunicationsScreen(
        club: club,
      ),
      ClubManagementDestination.documents => ClubDocumentsScreen(club: club),
      ClubManagementDestination.reports => ClubReportsScreen(club: club),
      ClubManagementDestination.membershipTypes => MembershipTypesScreen(
        club: club,
      ),
      ClubManagementDestination.sanctionTypes => SanctionTypesScreen(
        club: club,
      ),
      ClubManagementDestination.staff => ClubStaffPermissionsScreen(club: club),
      ClubManagementDestination.billing => ClubBillingScreen(club: club),
      ClubManagementDestination.settings => ClubSettingsScreen(club: club),
    };
  }

  @override
  void dispose() {
    _updates.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => !widget.club.canManageClub
      ? Scaffold(
          appBar: AppBar(title: const Text('Club management')),
          body: const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Club management is available to staff of this club.',
              ),
            ),
          ),
        )
      : PopScope(
          canPop:
              _selected == ClubManagementDestination.dashboard &&
              !_contentCanPop,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            if (_navigator.currentState?.canPop() ?? false) {
              _navigator.currentState!.pop();
            } else {
              _open(ClubManagementDestination.dashboard);
            }
          },
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 1000;
              return Scaffold(
                key: _scaffold,
                backgroundColor: AppColors.clubCardNavy,
                drawer: wide ? null : Drawer(child: _navigation()),
                body: SafeArea(
                  child: Row(
                    children: [
                      if (wide) SizedBox(width: 250, child: _navigation()),
                      Expanded(
                        key: const ValueKey('management-content'),
                        child: Navigator(
                          key: _navigator,
                          observers: [_observer],
                          onGenerateRoute: (_) => MaterialPageRoute<void>(
                            builder: (_) => _OverviewHost(owner: this),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                bottomNavigationBar: wide
                    ? null
                    : Padding(
                        padding: const EdgeInsets.only(bottom: 24),
                        child: NavigationBar(
                          selectedIndex: switch (_selected) {
                            ClubManagementDestination.dashboard => 0,
                            ClubManagementDestination.members => 1,
                            ClubManagementDestination.applications => 2,
                            _ => 3,
                          },
                          onDestinationSelected: (index) {
                            if (index == 3) {
                              _scaffold.currentState!.openDrawer();
                            } else {
                              _open(
                                [
                                  ClubManagementDestination.dashboard,
                                  ClubManagementDestination.members,
                                  ClubManagementDestination.applications,
                                ][index],
                              );
                            }
                          },
                          destinations: const [
                            NavigationDestination(
                              icon: Icon(Icons.space_dashboard_outlined),
                              label: 'Overview',
                            ),
                            NavigationDestination(
                              icon: Icon(Icons.people_outline),
                              label: 'Members',
                            ),
                            NavigationDestination(
                              icon: Icon(Icons.inbox_outlined),
                              label: 'Applications',
                            ),
                            NavigationDestination(
                              icon: Icon(Icons.menu),
                              label: 'More',
                            ),
                          ],
                        ),
                      ),
              );
            },
          ),
        );

  Widget _navigation() {
    final features = _overview?.features;
    final work = ClubManagementDestination.values.where((d) => !d.isSetup);
    final available = work.where(
      (d) => !d.requiresFeature || (features != null && d.available(features)),
    );
    final other = work.where(
      (d) => d.requiresFeature && (features == null || !d.available(features)),
    );
    Widget tile(ClubManagementDestination destination) => ListTile(
      key: ValueKey('nav-${destination.name}'),
      dense: true,
      selected: _selected == destination,
      selectedColor: AppColors.clubLightText,
      selectedTileColor: AppColors.clubPrimary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      leading: Icon(destination.icon, size: 21),
      title: Text(destination.label, style: const TextStyle(fontSize: 13)),
      trailing: features != null && !destination.available(features)
          ? const Icon(Icons.lock_outline, size: 15)
          : destination == ClubManagementDestination.applications &&
                (_overview?.summary?.pendingApplications ?? 0) > 0
          ? Text('${_overview!.summary!.pendingApplications}')
          : null,
      onTap: () => _open(destination),
    );
    return Material(
      color: AppColors.coreNavy,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 16, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'RINGMASTER CLUB',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.8,
                    color: AppColors.offWhite,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  widget.club.displayName,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  widget.club.roleName ?? 'Club management',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.offWhite,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.clubDivider),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
              children: [
                ...available.map(tile),
                const SizedBox(height: 12),
                ExpansionTile(
                  key: ValueKey('setup-${_selected.isSetup}'),
                  initiallyExpanded: _selected.isSetup,
                  tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                  title: const Text(
                    'Setup & settings',
                    style: TextStyle(fontSize: 12),
                  ),
                  children: ClubManagementDestination.values
                      .where((d) => d.isSetup)
                      .map(tile)
                      .toList(),
                ),
                if (other.isNotEmpty)
                  ExpansionTile(
                    title: const Text(
                      'Other tools',
                      style: TextStyle(fontSize: 12),
                    ),
                    tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                    children: other.map(tile).toList(),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.clubDivider),
          ListTile(
            leading: const Icon(Icons.arrow_back, size: 19),
            title: Text(widget.backLabel, style: const TextStyle(fontSize: 12)),
            onTap: _leaveWorkspace,
          ),
          const SizedBox(height: 28),
        ],
      ),
    );
  }
}

class _OverviewHost extends StatelessWidget {
  const _OverviewHost({required this.owner});
  final _ClubAdminHomeScreenState owner;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: owner._updates,
    builder: (context, _) => ClubManagementDashboard(
      club: owner.widget.club,
      overview: owner._overview,
      loading: owner._loading,
      error: owner._error,
      onRefresh: owner._loadOverview,
      onOpen: owner._open,
      onRenewals: () => owner._open(
        ClubManagementDestination.members,
        memberFilter: 'expiring',
      ),
      onImport: () =>
          owner._open(ClubManagementDestination.members, importRoster: true),
    ),
  );
}

class _ToolHost extends StatelessWidget {
  const _ToolHost({
    required this.owner,
    required this.destination,
    required this.memberFilter,
    required this.importRoster,
  });
  final _ClubAdminHomeScreenState owner;
  final ClubManagementDestination destination;
  final String memberFilter;
  final bool importRoster;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: owner._updates,
    builder: (context, _) =>
        owner._tool(context, destination, memberFilter, importRoster),
  );
}

class _WorkspaceObserver extends NavigatorObserver {
  _WorkspaceObserver(this.onChanged);
  final VoidCallback onChanged;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      onChanged();
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      onChanged();
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      onChanged();
}
