import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../account_settings_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../models/clubs/club_member_overview.dart';
import '../../../models/clubs/club_summary.dart';
import '../../../services/clubs/club_member_overview_service.dart';
import 'club_member_announcements_screen.dart';
import 'club_member_clubs_page.dart';
import 'club_member_dashboard.dart';
import 'club_member_destination.dart';
import 'club_member_home_screen.dart';
import 'club_member_membership_screen.dart';
import 'club_membership_apply_screen.dart';
import 'club_membership_cards_screen.dart';
import 'club_sanction_request_apply_screen.dart';
import 'member_network_screen.dart';

class ClubMemberWorkspace extends StatefulWidget {
  const ClubMemberWorkspace({
    super.key,
    required this.displayName,
    required this.onOpenManagement,
    this.onOpenOperations,
    this.onAccountChanged,
    this.overviewLoader,
    this.destinationBuilder,
  });

  final String displayName;
  final Future<void> Function(ClubSummary) onOpenManagement;
  final Future<void> Function()? onOpenOperations;
  final Future<void> Function()? onAccountChanged;
  final Future<ClubMemberOverview> Function()? overviewLoader;
  final Widget Function(BuildContext, ClubMemberDestination, ClubSummary?)?
  destinationBuilder;

  @override
  State<ClubMemberWorkspace> createState() => ClubMemberWorkspaceState();
}

class ClubMemberWorkspaceState extends State<ClubMemberWorkspace> {
  final _navigator = GlobalKey<NavigatorState>();
  final _scaffold = GlobalKey<ScaffoldState>();
  final _updates = ValueNotifier(0);
  late final _observer = _MemberNavigatorObserver(_navigationChanged);
  ClubMemberDestination _selected = ClubMemberDestination.home;
  ClubMemberOverview? _overview;
  bool _loading = true;
  bool _inFlight = false;
  bool _canPop = false;
  String? _error;

  void openAccountSettings() => _open(ClubMemberDestination.account);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_inFlight) return;
    _inFlight = true;
    if (!_loading) {
      setState(() => _loading = true);
      _updates.value++;
    }
    try {
      final overview =
          await (widget.overviewLoader?.call() ??
              ClubMemberOverviewService(Supabase.instance.client).load());
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
            ? 'Your member home could not be loaded. Try again, or open Memberships & cards to continue.'
            : 'The refresh failed. You are seeing your last loaded member information.';
      });
    }
    _inFlight = false;
    _updates.value++;
  }

  void _navigationChanged() =>
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final canPop = _navigator.currentState?.canPop() ?? false;
        if (_canPop != canPop) setState(() => _canPop = canPop);
      });

  Future<void> _manage(ClubSummary club) async {
    if (!(_overview?.manageableClubs.any(
          (item) => item.clubId == club.clubId,
        ) ??
        false)) {
      return;
    }
    _scaffold.currentState?.closeDrawer();
    await widget.onOpenManagement(club);
    if (mounted) await _load();
  }

  void _open(ClubMemberDestination destination, [ClubSummary? club]) {
    _scaffold.currentState?.closeDrawer();
    if (!destination.isTopLevel) {
      final clubRequest =
          destination == ClubMemberDestination.apply ||
          destination == ClubMemberDestination.sanction;
      // Club requests need a linked club; personal details need an actual
      // membership returned for this account. Staff access alone is not one.
      final allowed =
          club != null &&
          (clubRequest
              ? (_overview?.clubs.any(
                      (item) =>
                          item.clubId == club.clubId &&
                          (destination != ClubMemberDestination.sanction ||
                              item.canRequestSanction),
                    ) ??
                    false)
              : (_overview?.memberships.any(
                      (member) =>
                          member.club.clubId == club.clubId &&
                          member.club.membershipId == club.membershipId,
                    ) ??
                    false));
      if (!allowed) {
        return;
      }
      _navigator.currentState!
          .push<void>(
            MaterialPageRoute(
              builder: (context) => _page(context, destination, club),
            ),
          )
          .then((_) {
            if (mounted) _load();
          });
      return;
    }
    if (_selected == destination) {
      _navigator.currentState?.popUntil((route) => route.isFirst);
      return;
    }
    setState(() => _selected = destination);
    _navigator.currentState!.pushAndRemoveUntil<void>(
      PageRouteBuilder<void>(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (context, _, _) => _page(context, destination, null),
      ),
      (_) => false,
    );
    if (destination == ClubMemberDestination.home) _load();
  }

  Widget _page(
    BuildContext context,
    ClubMemberDestination destination,
    ClubSummary? club,
  ) {
    if (destination == ClubMemberDestination.home) {
      return ListenableBuilder(
        listenable: _updates,
        builder: (context, _) => ClubMemberDashboard(
          displayName: widget.displayName,
          overview: _overview,
          loading: _loading,
          error: _error,
          onRefresh: _load,
          onOpen: _open,
          management: (_overview?.manageableClubs.isNotEmpty ?? false)
              ? _managementButton()
              : null,
        ),
      );
    }
    if (destination == ClubMemberDestination.clubs) {
      return ListenableBuilder(
        listenable: _updates,
        builder: (context, _) => ClubMemberClubsPage(
          overview: _overview,
          loading: _loading,
          error: _error,
          onRefresh: _load,
          onOpen: _open,
          onManage: _manage,
        ),
      );
    }
    if (widget.destinationBuilder != null) {
      return widget.destinationBuilder!(context, destination, club);
    }
    return switch (destination) {
      ClubMemberDestination.home => const SizedBox.shrink(),
      ClubMemberDestination.clubs => const SizedBox.shrink(),
      ClubMemberDestination.account => AccountSettingsScreen(
        onAccountChanged: () async {
          await widget.onAccountChanged?.call();
          if (mounted) await _load();
        },
      ),
      ClubMemberDestination.memberships => const MemberNetworkScreen(
        view: MemberNetworkView.memberships,
      ),
      ClubMemberDestination.calendar => const MemberNetworkScreen(
        view: MemberNetworkView.events,
      ),
      ClubMemberDestination.announcements => const MemberNetworkScreen(
        view: MemberNetworkView.announcements,
      ),
      ClubMemberDestination.resources => const MemberNetworkScreen(
        view: MemberNetworkView.resources,
      ),
      ClubMemberDestination.membership => ClubMemberMembershipScreen(
        club: club!,
      ),
      ClubMemberDestination.card => ClubMembershipCardsScreen(club: club!),
      ClubMemberDestination.renew => ClubMembershipApplyScreen(
        club: club!,
        isRenewal: true,
      ),
      ClubMemberDestination.club => ClubMemberHomeScreen(club: club!),
      ClubMemberDestination.clubAnnouncements => ClubMemberAnnouncementsScreen(
        club: club!,
      ),
      ClubMemberDestination.apply => ClubMembershipApplyScreen(club: club!),
      ClubMemberDestination.sanction => ClubSanctionRequestApplyScreen(
        club: club!,
      ),
    };
  }

  Widget _managementButton() {
    final clubs = _overview!.manageableClubs;
    if (clubs.length == 1) {
      return OutlinedButton.icon(
        onPressed: () => _manage(clubs.single),
        icon: const Icon(Icons.admin_panel_settings_outlined, size: 18),
        label: const Text('Club management'),
      );
    }
    return PopupMenuButton<ClubSummary>(
      tooltip: 'Choose a club to manage',
      onSelected: _manage,
      itemBuilder: (_) => clubs
          .map(
            (club) => PopupMenuItem(value: club, child: Text(club.displayName)),
          )
          .toList(),
      child: const Padding(
        padding: EdgeInsets.all(12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.admin_panel_settings_outlined, size: 18),
            SizedBox(width: 8),
            Flexible(
              child: Text('Club management', style: TextStyle(fontSize: 13)),
            ),
            Icon(Icons.expand_more),
          ],
        ),
      ),
    );
  }

  Widget _navigation() => Material(
    color: AppColors.coreNavy,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'MEMBER WORKSPACE',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.6,
                  color: AppColors.offWhite,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                widget.displayName,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 5),
              const Text(
                'Your memberships and club updates',
                style: TextStyle(fontSize: 12, color: AppColors.offWhite),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              for (final destination in ClubMemberDestination.values.where(
                (item) => item.isTopLevel,
              ))
                ListTile(
                  key: ValueKey('member-nav-${destination.name}'),
                  dense: true,
                  selected: _selected == destination,
                  selectedColor: AppColors.clubLightText,
                  selectedTileColor: AppColors.clubPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  leading: Icon(destination.icon, size: 21),
                  title: Text(
                    destination.label,
                    style: const TextStyle(fontSize: 13),
                  ),
                  onTap: () => _open(destination),
                ),
            ],
          ),
        ),
        if (_overview?.manageableClubs.isNotEmpty ?? false)
          Padding(
            padding: const EdgeInsets.all(16),
            child: _managementButton(),
          ),
        if (widget.onOpenOperations != null)
          ListTile(
            leading: const Icon(Icons.admin_panel_settings_outlined),
            title: const Text(
              'RingMaster operations',
              style: TextStyle(fontSize: 12),
            ),
            onTap: widget.onOpenOperations,
          ),
        const SizedBox(height: 28),
      ],
    ),
  );

  @override
  void dispose() {
    _updates.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _selected == ClubMemberDestination.home && !_canPop,
    onPopInvokedWithResult: (didPop, _) {
      if (didPop) return;
      if (_navigator.currentState?.canPop() ?? false) {
        _navigator.currentState!.pop();
      } else {
        _open(ClubMemberDestination.home);
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
                  key: const ValueKey('member-content'),
                  child: Navigator(
                    key: _navigator,
                    observers: [_observer],
                    onGenerateRoute: (_) => MaterialPageRoute(
                      builder: (context) =>
                          _page(context, ClubMemberDestination.home, null),
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
                      ClubMemberDestination.home => 0,
                      ClubMemberDestination.memberships => 1,
                      ClubMemberDestination.calendar => 2,
                      _ => 3,
                    },
                    onDestinationSelected: (index) => index == 3
                        ? _scaffold.currentState!.openDrawer()
                        : _open(
                            [
                              ClubMemberDestination.home,
                              ClubMemberDestination.memberships,
                              ClubMemberDestination.calendar,
                            ][index],
                          ),
                    destinations: const [
                      NavigationDestination(
                        icon: Icon(Icons.home_outlined),
                        label: 'Home',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.badge_outlined),
                        label: 'Memberships',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.event_outlined),
                        label: 'Calendar',
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
}

class _MemberNavigatorObserver extends NavigatorObserver {
  _MemberNavigatorObserver(this.changed);
  final VoidCallback changed;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      changed();
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => changed();
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      changed();
}
