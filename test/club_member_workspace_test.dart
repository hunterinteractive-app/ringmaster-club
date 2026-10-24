import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_club/models/clubs/club_member_overview.dart';
import 'package:ringmaster_club/models/clubs/club_summary.dart';
import 'package:ringmaster_club/screens/clubs/admin/club_admin_home_screen.dart';
import 'package:ringmaster_club/screens/clubs/member/club_member_destination.dart';
import 'package:ringmaster_club/screens/clubs/member/club_member_workspace.dart';
import 'package:ringmaster_club/theme/app_theme.dart';

const memberClub = ClubSummary(
  clubId: 'member-club',
  clubName: 'Member Club',
  clubSlug: 'member',
  clubType: 'local',
  relationshipType: 'member',
  membershipId: 'my-membership',
  membershipStatus: 'active',
);
const staffClub = ClubSummary(
  clubId: 'staff-club',
  clubName: 'Staff Club',
  clubSlug: 'staff',
  clubType: 'local',
  relationshipType: 'staff',
  roleName: 'Secretary',
);
const secondStaffClub = ClubSummary(
  clubId: 'second-staff-club',
  clubName: 'Second Staff Club',
  clubSlug: 'second',
  clubType: 'local',
  relationshipType: 'staff',
);

ClubMemberOverview memberOverview({List<ClubSummary> managed = const []}) =>
    ClubMemberOverview(
      clubs: [memberClub, ...managed],
      memberships: [
        MemberMembershipSummary(
          club: memberClub,
          memberName: 'Sample Member',
          status: 'active',
          number: 'M123',
          expiresAt: DateTime.now().add(const Duration(days: 30)),
        ),
      ],
      events: [
        MemberClubUpdate(
          club: memberClub,
          title: 'Fall club meeting',
          date: DateTime.now().add(const Duration(days: 7)),
        ),
      ],
      announcements: const [
        MemberClubUpdate(club: memberClub, title: 'Club newsletter'),
      ],
      personalCardCount: 2,
    );

Future<void> mountMember(
  WidgetTester tester, {
  ClubMemberOverview? overview,
  Future<ClubMemberOverview> Function()? loader,
  Future<void> Function(ClubSummary)? onManage,
  void Function(ClubMemberDestination, ClubSummary?)? onPage,
  Size size = const Size(1440, 1100),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: ClubMemberWorkspace(
        displayName: 'Sample Member',
        overviewLoader:
            loader ?? () async => overview ?? const ClubMemberOverview(),
        onOpenManagement: onManage ?? (_) async {},
        destinationBuilder: (context, destination, club) {
          onPage?.call(destination, club);
          return Scaffold(
            appBar: AppBar(title: Text('Member tool: ${destination.name}')),
            body: const Text('Member tool content'),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'people with no clubs still have a member home and card wallet, with no management entry',
    (tester) async {
      await mountMember(tester);
      expect(find.text('No linked clubs yet'), findsOneWidget);
      expect(find.text('Club management'), findsNothing);
      expect(find.text('Club overview'), findsNothing);
      await tester.tap(find.text('Open my card wallet'));
      await tester.pumpAndSettle();
      expect(find.text('Member tool: memberships'), findsOneWidget);
      expect(find.byKey(const ValueKey('member-nav-home')), findsOneWidget);
    },
  );

  testWidgets(
    'members see their own status, card, renewal, events and announcements without staff controls',
    (tester) async {
      ClubMemberDestination? page;
      ClubSummary? selectedClub;
      await mountMember(
        tester,
        overview: memberOverview(),
        onPage: (destination, club) {
          page = destination;
          selectedClub = club;
        },
      );
      expect(find.text('Sample Member'), findsWidgets);
      expect(find.textContaining('Member #M123'), findsOneWidget);
      expect(find.text('Fall club meeting'), findsOneWidget);
      expect(find.text('Club newsletter'), findsOneWidget);
      expect(find.text('Club management'), findsNothing);
      await tester.tap(find.text('Request renewal'));
      await tester.pumpAndSettle();
      expect(page, ClubMemberDestination.renew);
      expect(selectedClub?.membershipId, 'my-membership');
      expect(find.byKey(const ValueKey('member-nav-home')), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('My memberships'), findsOneWidget);
    },
  );

  testWidgets(
    'staff can enter management only for clubs they manage, while their personal membership stays separate',
    (tester) async {
      final managed = <String>[];
      await mountMember(
        tester,
        overview: memberOverview(managed: [staffClub]),
        onManage: (club) async {
          managed.add(club.clubId);
        },
      );
      expect(find.text('Member Club'), findsWidgets);
      await tester.tap(find.text('Club management').first);
      await tester.pumpAndSettle();
      expect(managed, ['staff-club']);
      expect(find.text('My memberships'), findsOneWidget);
      expect(find.text('Staff Club'), findsNothing);
    },
  );

  testWidgets(
    'multi-club management chooser excludes clubs with only membership access',
    (tester) async {
      final managed = <String>[];
      await mountMember(
        tester,
        overview: memberOverview(managed: [staffClub, secondStaffClub]),
        onManage: (club) async {
          managed.add(club.clubId);
        },
      );
      await tester.tap(find.text('Club management').first);
      await tester.pumpAndSettle();
      expect(find.text('Second Staff Club'), findsOneWidget);
      await tester.tap(find.text('Second Staff Club'));
      await tester.pumpAndSettle();
      expect(managed, ['second-staff-club']);
    },
  );

  testWidgets('staff access alone does not fabricate a personal membership', (
    tester,
  ) async {
    await mountMember(
      tester,
      overview: const ClubMemberOverview(clubs: [staffClub]),
    );
    expect(find.text('No personal memberships linked yet'), findsOneWidget);
    expect(find.text('View membership'), findsNothing);
    expect(find.text('Club management'), findsWidgets);
  });

  testWidgets(
    'My clubs stays inside the workspace and opens the correct membership',
    (tester) async {
      ClubSummary? selectedClub;
      ClubMemberDestination? page;
      await mountMember(
        tester,
        overview: memberOverview(managed: [staffClub]),
        onPage: (destination, club) {
          page = destination;
          selectedClub = club;
        },
      );
      await tester.tap(find.byKey(const ValueKey('member-nav-clubs')));
      await tester.pumpAndSettle();
      expect(find.text('Your clubs, together'), findsOneWidget);
      expect(find.textContaining('Member #M123'), findsOneWidget);
      expect(find.byKey(const ValueKey('member-nav-home')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('member-club-staff-club')),
        findsOneWidget,
      );
      expect(
        find.text('No personal membership linked to this club.'),
        findsOneWidget,
      );
      await tester.tap(find.text('View membership'));
      await tester.pumpAndSettle();
      expect(page, ClubMemberDestination.membership);
      expect(selectedClub?.membershipId, 'my-membership');
      expect(find.byKey(const ValueKey('member-nav-clubs')), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Your clubs, together'), findsOneWidget);
    },
  );

  testWidgets(
    'My clubs retains staff management, applications and enabled sanction requests',
    (tester) async {
      final club = staffClub.copyWith(sanctionRequestsEnabled: true);
      final managed = <String>[];
      ClubMemberDestination? page;
      ClubSummary? selectedClub;
      await mountMember(
        tester,
        overview: ClubMemberOverview(clubs: [club]),
        onManage: (club) async => managed.add(club.clubId),
        onPage: (destination, club) {
          page = destination;
          selectedClub = club;
        },
      );
      await tester.tap(find.byKey(const ValueKey('member-nav-clubs')));
      await tester.pumpAndSettle();
      expect(find.text('View membership'), findsNothing);
      await tester.tap(find.text('Apply for membership'));
      await tester.pumpAndSettle();
      expect(page, ClubMemberDestination.apply);
      expect(selectedClub?.clubId, staffClub.clubId);
      await tester.tap(find.byKey(const ValueKey('member-nav-clubs')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Request sanction'));
      await tester.pumpAndSettle();
      expect(page, ClubMemberDestination.sanction);
      expect(selectedClub?.clubId, staffClub.clubId);
      await tester.tap(find.byKey(const ValueKey('member-nav-clubs')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('member-club-manage-staff-club')),
      );
      await tester.pumpAndSettle();
      expect(managed, [staffClub.clubId]);
      expect(find.text('Your clubs, together'), findsOneWidget);
    },
  );

  testWidgets('My clubs handles phones, large text and member-only access', (
    tester,
  ) async {
    await mountMember(
      tester,
      overview: memberOverview(),
      size: const Size(390, 844),
      textScale: 1.5,
    );
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('member-nav-clubs')));
    await tester.tap(find.byKey(const ValueKey('member-nav-clubs')));
    await tester.pumpAndSettle();
    expect(find.text('Your clubs, together'), findsOneWidget);
    expect(find.text('Club management'), findsNothing);
    expect(find.text('Request sanction'), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'My clubs distinguishes failed loads from no clubs and can recover',
    (tester) async {
      var calls = 0;
      await mountMember(
        tester,
        loader: () async {
          if (++calls == 1) throw StateError('Unavailable');
          return memberOverview();
        },
      );
      await tester.tap(find.byKey(const ValueKey('member-nav-clubs')));
      await tester.pumpAndSettle();
      expect(find.text('Clubs not loaded'), findsOneWidget);
      expect(find.text('No linked clubs yet'), findsNothing);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Member Club'), findsOneWidget);
      expect(find.text('Clubs not loaded'), findsNothing);
    },
  );

  testWidgets(
    'refresh removes management entry when the account no longer has staff clubs',
    (tester) async {
      var calls = 0;
      await mountMember(
        tester,
        loader: () async => ++calls == 1
            ? memberOverview(managed: [staffClub])
            : memberOverview(),
      );
      expect(find.text('Club management'), findsWidgets);
      await tester.tap(find.byTooltip('Refresh member home'));
      await tester.pumpAndSettle();
      expect(find.text('Club management'), findsNothing);
    },
  );

  testWidgets(
    'failed membership reads remain distinct from an account with no clubs',
    (tester) async {
      await mountMember(
        tester,
        overview: const ClubMemberOverview(
          clubs: [memberClub],
          unavailableSections: {'memberships', 'events'},
        ),
      );
      expect(find.text('Memberships could not be loaded'), findsOneWidget);
      expect(find.text('No linked clubs yet'), findsNothing);
      expect(find.text('No upcoming club events'), findsNothing);
      expect(find.text('Club management'), findsNothing);
    },
  );

  testWidgets('member navigation works on phones with large text', (
    tester,
  ) async {
    await mountMember(
      tester,
      overview: memberOverview(),
      size: const Size(390, 844),
      textScale: 1.5,
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('member-nav-resources')));
    await tester.pumpAndSettle();
    expect(find.text('Member tool: resources'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'the management route does not load administrative data for a member',
    (tester) async {
      var requested = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: ClubAdminHomeScreen(
            club: memberClub,
            overviewLoader: () async {
              requested = true;
              throw StateError('must not load');
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(requested, isFalse);
      expect(
        find.text('Club management is available to staff of this club.'),
        findsOneWidget,
      );
      expect(find.text('Enabled Club Tools'), findsNothing);
    },
  );

  test('membership renewal timing uses personal term and status', () {
    final now = DateTime(2026, 10, 24);
    MemberMembershipSummary membership(String status, DateTime end) =>
        MemberMembershipSummary(
          club: memberClub,
          memberName: 'Member',
          status: status,
          expiresAt: end,
        );
    expect(
      membership('active', DateTime(2026, 11, 20)).needsRenewal(now),
      isTrue,
    );
    expect(
      membership('active', DateTime(2027, 5, 1)).needsRenewal(now),
      isFalse,
    );
    expect(
      membership('pending', DateTime(2026, 11, 1)).needsRenewal(now),
      isFalse,
    );
    expect(
      membership('expired', DateTime(2026, 9, 1)).needsRenewal(now),
      isTrue,
    );
  });
}
