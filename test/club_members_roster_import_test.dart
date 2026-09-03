import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_club/screens/clubs/admin/club_members_screen.dart';

void main() {
  test(
    'normalizes title rows, aliases, malformed addresses, and roster rules',
    () {
      final rows = parseMembershipRosterForTesting(
        extension: 'csv',
        bytes: Uint8List.fromList(
          utf8.encode('''ASCRBA Membership List,,,,,,,,,

Name,E-mail,Expiration,Youth,Address,City,State,Zip Code,Phone Number,Active/Inactive
,,Date,,,,,,,
Roxanna Dabney,rox@example.com,5/7/2028,,1004 S. 22nd Street,Rogers,AR,72758,479-282-7184,Active
Kenneth & Shirley Wilson,,2/1/2020,,100 Main St,Albany,NY,12207,,Expired
Kathy Mannweiler,,5/7/2028,,Box 41 (Errington, BC VOR 1VO),Canada,,,250-240-7145,Active
Jamie Jones,,5/7/2028,YOUTH,200 Oak St,Salem,IN,47167,,Active
'''),
        ),
      );

      expect(rows, hasLength(4));
      expect(rows[0]['category'], 'Individual');
      expect(rows[0]['status'], 'active');
      expect(rows[1]['category'], 'Family');
      expect(rows[1]['status'], 'inactive');
      expect(rows[1]['linkedPeople'], {
        'additional_manual_people': [
          {
            'first_name': 'Shirley',
            'last_name': 'Wilson',
            'classification': 'adult',
          },
        ],
        'additional_exhibitor_ids': <String>[],
        'additional_people_summary': '1 additional family member',
      });
      expect(rows[2]['address'], 'Box 41 (Errington, BC VOR 1VO)');
      expect(rows[3]['category'], 'Youth');
    },
  );
}
