import 'package:flutter/material.dart';

enum ClubMemberDestination {
  home('Member home', Icons.home_outlined),
  memberships('Memberships & cards', Icons.badge_outlined),
  calendar('My calendar', Icons.event_outlined),
  announcements('Announcements', Icons.campaign_outlined),
  resources('Club resources', Icons.folder_outlined),
  clubs('My clubs', Icons.groups_outlined),
  membership('Membership details', Icons.badge_outlined),
  card('Membership card', Icons.credit_card_outlined),
  renew('Request renewal', Icons.autorenew),
  club('Member portal', Icons.groups_outlined),
  clubAnnouncements('Club announcements', Icons.campaign_outlined),
  apply('Apply for membership', Icons.person_add_outlined),
  sanction('Request sanction', Icons.verified_outlined);

  const ClubMemberDestination(this.label, this.icon);
  final String label;
  final IconData icon;
  bool get isTopLevel => index <= clubs.index;
}
