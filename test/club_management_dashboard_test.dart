import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_club/models/clubs/club_management_overview.dart';
import 'package:ringmaster_club/models/clubs/club_summary.dart';
import 'package:ringmaster_club/screens/clubs/admin/club_admin_home_screen.dart';
import 'package:ringmaster_club/theme/app_theme.dart';

const club = ClubSummary(
  clubId: 'club-1',
  clubName: 'Garden State Rabbit & Cavy Breeders Association',
  clubShortName: 'Garden State RCBA',
  clubSlug: 'garden-state',
  clubType: 'local',
  relationshipType: 'staff',
  roleName: 'Club Administrator',
);

ClubManagementOverview overview({
  int members = 124,
  int applications = 6,
  bool sweepstakes = true,
  bool summaryAvailable = true,
  int? reviewCount = 3,
}) => ClubManagementOverview(
  features: ClubManagementFeatures(
    membership: true,
    sanctions: true,
    events: true,
    sweepstakes: sweepstakes,
  ),
  reportsNeedingReview: reviewCount,
  overdueReports: 2,
  summary: !summaryAvailable
      ? null
      : ClubManagementSummary.fromJson({
          'membership': {
            'total_members': members,
            'active_members': members,
            'expiring_soon': members == 0 ? 0 : 8,
          },
          'operations': {
            'pending_applications': applications,
            'pending_sanctions': 2,
            'upcoming_events': 3,
          },
          'payments': {'outstanding': 175.5, 'unpaid_count': 4},
          'upcoming_expirations': members == 0
              ? []
              : [
                  {
                    'name': 'Taylor Rabbitry',
                    'type_name': 'Family',
                    'expires_at': '2026-11-12',
                  },
                ],
          'recent_activity': [
            {
              'type': 'application',
              'title': 'Jamie Lee',
              'subtitle': 'pending',
              'created_at': '2026-10-24T12:00:00Z',
            },
          ],
        }),
);

Future<void> mountWorkspace(
  WidgetTester tester, {
  Future<ClubManagementOverview> Function()? loader,
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
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ClubAdminHomeScreen(
                  club: club,
                  overviewLoader: loader ?? () async => overview(),
                  destinationBuilder: (context, destination) => Scaffold(
                    appBar: AppBar(title: Text('Tool: ${destination.name}')),
                    body: Column(
                      children: [
                        const TextField(
                          decoration: InputDecoration(
                            labelText: 'Unsaved note',
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => Scaffold(
                                appBar: AppBar(title: const Text('Detail')),
                                body: const Text('Nested detail'),
                              ),
                            ),
                          ),
                          child: const Text('Open detail'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            child: const Text('Open workspace'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open workspace'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'mobile workspace return closes the drawer and exits in one tap',
    (tester) async {
      await mountWorkspace(tester, size: const Size(390, 844));
      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Back to my clubs'));
      await tester.pumpAndSettle();
      expect(find.text('Open workspace'), findsOneWidget);
      expect(find.text('Club overview'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'desktop dashboard links work queues and keeps navigation on nested details',
    (tester) async {
      var loads = 0;
      await mountWorkspace(
        tester,
        loader: () async {
          loads++;
          return overview(applications: loads == 1 ? 6 : 7);
        },
      );
      expect(find.text('124'), findsOneWidget);
      expect(find.text('Review membership applications'), findsOneWidget);
      expect(find.text('Review show reports'), findsOneWidget);
      expect(find.text('Taylor Rabbitry'), findsOneWidget);
      await tester.tap(find.text('Review membership applications'));
      await tester.pumpAndSettle();
      expect(find.text('Tool: applications'), findsOneWidget);
      expect(find.byKey(const ValueKey('nav-members')), findsOneWidget);
      await tester.tap(find.text('Open detail'));
      await tester.pumpAndSettle();
      expect(find.text('Nested detail'), findsOneWidget);
      expect(find.byKey(const ValueKey('nav-dashboard')), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Tool: applications'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Club overview'), findsOneWidget);
      expect(loads, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'navigation and in-progress tool state survive a desktop to phone resize',
    (tester) async {
      await mountWorkspace(tester);
      await tester.tap(find.byKey(const ValueKey('nav-members')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Keep this draft');
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      expect(find.text('Keep this draft'), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);
      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nav-documents')));
      await tester.pumpAndSettle();
      expect(find.text('Tool: documents'), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('phone layout supports large text and the empty-club next step', (
    tester,
  ) async {
    await mountWorkspace(
      tester,
      size: const Size(390, 844),
      textScale: 1.5,
      loader: () async => overview(members: 0),
    );
    await tester.scrollUntilVisible(
      find.text('Bring your members into view'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Bring your members into view'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a failed initial load offers recovery without inventing zero counts',
    (tester) async {
      var loads = 0;
      await mountWorkspace(
        tester,
        loader: () async {
          if (++loads == 1) throw StateError('offline');
          return overview();
        },
      );
      expect(
        find.textContaining('overview could not be loaded'),
        findsOneWidget,
      );
      expect(find.text('No pending items in this overview'), findsNothing);
      expect(find.text('124'), findsNothing);
      await tester.tap(find.text('Retry').first);
      await tester.pumpAndSettle();
      expect(find.text('124'), findsOneWidget);
      expect(find.textContaining('overview could not be loaded'), findsNothing);
    },
  );

  testWidgets('missing optional data is not mistaken for an all-clear', (
    tester,
  ) async {
    await mountWorkspace(
      tester,
      loader: () async => overview(summaryAvailable: false),
    );
    expect(find.text('Overview unavailable'), findsOneWidget);
    expect(find.text('No pending items in this overview'), findsNothing);
    expect(find.byKey(const ValueKey('nav-members')), findsOneWidget);
  });

  testWidgets(
    'disabled tools are tucked away and cannot open their feature screen',
    (tester) async {
      await mountWorkspace(
        tester,
        loader: () async => overview(sweepstakes: false),
      );
      expect(find.text('Review show reports'), findsNothing);
      expect(find.byKey(const ValueKey('nav-sweepstakes')), findsNothing);
      await tester.tap(find.text('Other tools'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nav-sweepstakes')));
      await tester.pumpAndSettle();
      expect(find.text('Sweepstakes is not enabled'), findsOneWidget);
      expect(find.text('Tool: sweepstakes'), findsNothing);
      expect(find.byKey(const ValueKey('nav-dashboard')), findsOneWidget);
    },
  );

  testWidgets(
    'a failed refresh preserves previous data and clearly marks it stale',
    (tester) async {
      var loads = 0;
      await mountWorkspace(
        tester,
        loader: () async {
          if (++loads > 1) throw StateError('offline');
          return overview();
        },
      );
      await tester.tap(find.byTooltip('Refresh overview'));
      await tester.pumpAndSettle();
      expect(find.text('124'), findsOneWidget);
      expect(find.textContaining('last successful update'), findsOneWidget);
    },
  );
}
