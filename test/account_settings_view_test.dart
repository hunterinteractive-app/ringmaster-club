import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_club/theme/app_theme.dart';
import 'package:ringmaster_club/widgets/account_settings_view.dart';

const primary = <String, dynamic>{
  'id': 'adult',
  'display_name': 'Sample Adult',
  'email': 'adult@example.invalid',
  'phone': '202-555-0100',
  'city': 'Meadowbrook',
  'state': 'IN',
  'account_type': 'adult',
  'is_active': true,
  'is_primary': true,
  'imported_from': 'ringmaster_show',
};
const youth = <String, dynamic>{
  'id': 'youth',
  'first_name': 'Sample',
  'last_name': 'Youth',
  'account_type': 'youth',
  'is_active': false,
  'is_primary': false,
};

Future<void> mountSettings(
  WidgetTester tester, {
  Size size = const Size(1440, 1100),
  double textScale = 1,
  bool loading = false,
  bool hasLoaded = true,
  bool signingOut = false,
  String? message,
  List<Map<String, dynamic>> accounts = const [primary, youth],
  List<String>? actions,
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
      home: AccountSettingsView(
        loading: loading,
        hasLoaded: hasLoaded,
        signingOut: signingOut,
        displayName: 'Sample Adult',
        email: 'login@example.invalid',
        accounts: accounts,
        message: message,
        onRefresh: () async => actions?.add('refresh'),
        onAdd: () => actions?.add('add'),
        onEdit: (account) => actions?.add('edit:${account['id']}'),
        onMakePrimary: (account) => actions?.add('primary:${account['id']}'),
        onToggleActive: (account, active) =>
            actions?.add('active:${account['id']}:$active'),
        onTerms: () => actions?.add('terms'),
        onPrivacy: () => actions?.add('privacy'),
        onSignOut: () => actions?.add('signOut'),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets(
    'account overview distinguishes login, linked accounts and primary identity',
    (tester) async {
      await mountSettings(tester);
      expect(find.text('login@example.invalid'), findsOneWidget);
      expect(find.text('adult@example.invalid'), findsOneWidget);
      expect(find.text('1 active · 2 linked accounts'), findsOneWidget);
      expect(find.text('Primary'), findsOneWidget);
      expect(find.text('Inactive'), findsOneWidget);
      expect(find.text('Linked from RingMaster Show'), findsOneWidget);
      expect(find.byKey(const ValueKey('primary-account-adult')), findsNothing);
      expect(
        find.byKey(const ValueKey('primary-account-youth')),
        findsOneWidget,
      );
    },
  );

  testWidgets('add, edit and primary actions target the selected account', (
    tester,
  ) async {
    final actions = <String>[];
    await mountSettings(tester, actions: actions);
    await tester.tap(find.text('Add account'));
    await tester.tap(find.byKey(const ValueKey('edit-account-adult')));
    await tester.ensureVisible(
      find.byKey(const ValueKey('primary-account-youth')),
    );
    await tester.tap(find.byKey(const ValueKey('primary-account-youth')));
    expect(actions, ['add', 'edit:adult', 'primary:youth']);
  });

  testWidgets(
    'status menus retain activate and deactivate actions for the selected account',
    (tester) async {
      final actions = <String>[];
      await mountSettings(tester, actions: actions);
      await tester.tap(find.byTooltip('Status actions for Sample Youth'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Activate account'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Status actions for Sample Adult'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Deactivate account'));
      await tester.pumpAndSettle();
      expect(actions, ['active:youth:true', 'active:adult:false']);
    },
  );

  testWidgets('policy and sign-out controls retain their actions', (
    tester,
  ) async {
    final actions = <String>[];
    await mountSettings(tester, actions: actions);
    await tester.tap(find.text('Terms of Service'));
    await tester.tap(find.text('Privacy Policy'));
    await tester.tap(find.text('Sign out'));
    expect(actions, ['terms', 'privacy', 'signOut']);
  });

  testWidgets('phone layout wraps long names and badges with large text', (
    tester,
  ) async {
    await mountSettings(
      tester,
      size: const Size(390, 844),
      textScale: 1.5,
      accounts: [
        {
          ...primary,
          'display_name': 'A very long family account name with several people',
          'email': 'long-account-name@example.invalid',
          'account_type': 'family',
        },
        youth,
      ],
    );
    await tester.ensureVisible(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a failed initial read offers retry without claiming there are no accounts',
    (tester) async {
      final actions = <String>[];
      await mountSettings(
        tester,
        hasLoaded: false,
        accounts: [],
        message: 'Unable to load account settings.',
        actions: actions,
      );
      expect(find.text('Linked accounts could not be loaded.'), findsOneWidget);
      expect(find.text('No linked accounts'), findsNothing);
      await tester.tap(find.text('Try again'));
      expect(actions, ['refresh']);
    },
  );

  testWidgets('loading and sign-out in progress disable account changes', (
    tester,
  ) async {
    await mountSettings(tester, loading: true, hasLoaded: false, accounts: []);
    expect(find.text('Loading linked accounts…'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('add-account')))
          .onPressed,
      isNull,
    );
    await mountSettings(tester, signingOut: true);
    expect(find.text('Signing out…'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('account-sign-out')),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('edit-account-adult')),
          )
          .onPressed,
      isNull,
    );
  });
}
