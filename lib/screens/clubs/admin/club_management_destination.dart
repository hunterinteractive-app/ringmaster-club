import 'package:flutter/material.dart';

import '../../../models/clubs/club_management_overview.dart';

enum ClubManagementDestination {
  dashboard('Overview', Icons.space_dashboard_outlined),
  members('Members', Icons.people_outline),
  applications('Applications & renewals', Icons.inbox_outlined),
  payments('Payments & dues', Icons.payments_outlined),
  sanctions('Sanction requests', Icons.verified_outlined),
  sweepstakes('Sweepstakes', Icons.emoji_events_outlined),
  events('Meetings & events', Icons.event_outlined),
  communications('Communications', Icons.campaign_outlined),
  documents('Documents', Icons.folder_outlined),
  reports('Reports', Icons.bar_chart_outlined),
  membershipTypes('Membership types', Icons.badge_outlined),
  sanctionTypes('Sanction types', Icons.fact_check_outlined),
  staff('Staff & permissions', Icons.manage_accounts_outlined),
  billing('Billing & plan', Icons.receipt_long_outlined),
  settings('Club settings', Icons.settings_outlined);

  const ClubManagementDestination(this.label, this.icon);
  final String label;
  final IconData icon;

  bool get isSetup => index >= membershipTypes.index;
  bool get requiresFeature => switch (this) {
    payments || sanctions || sanctionTypes || sweepstakes || events => true,
    _ => false,
  };

  bool available(ClubManagementFeatures features) => switch (this) {
    payments => features.membership,
    sanctions || sanctionTypes => features.sanctions,
    sweepstakes => features.sweepstakes,
    events => features.events,
    _ => true,
  };

  static ClubManagementDestination? forActivity(String type) => switch (type) {
    'application' => applications,
    'payment' => payments,
    'sanction' => sanctions,
    'communication' => communications,
    'document' => documents,
    'event' => events,
    'sweepstakes' => sweepstakes,
    _ => null,
  };
}
