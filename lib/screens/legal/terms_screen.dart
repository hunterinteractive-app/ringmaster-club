// lib/screens/legal/terms_screen.dart

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/rm_widgets.dart';

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.titleLarge;
    final sectionStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
        );
    final bodyStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          height: 1.6,
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Terms of Service')),
      body: Container(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: RMCard(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'RingMaster Club – Terms of Service',
                          style: titleStyle,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Effective Date: May 2026 (v2026-05)',
                          style: bodyStyle?.copyWith(color: AppColors.muted),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Text(
                          'By creating an account or using RingMaster Club, you agree to the following:',
                          style: bodyStyle,
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        _section(
                          '1. Use of Platform',
                          'RingMaster Club provides tools for club administration, membership management, dues and payment tracking, events, meetings, communications, documents, reports, and related club operations.\n\n'
                              'You agree to use the platform only for lawful and intended club-management purposes.',
                          sectionStyle,
                          bodyStyle,
                        ),
                        _section(
                          '2. Eligibility',
                          'You must be at least 13 years old to create or independently use a RingMaster Club account. A parent, guardian, club officer, or authorized adult may manage information for a minor when permitted by the club and applicable law.',
                          sectionStyle,
                          bodyStyle,
                        ),
                        _section(
                          '3. User Accounts & Security',
                          'You are responsible for maintaining the confidentiality of your account and login access.\n\n'
                              'You agree not to share your account access with unauthorized individuals and to notify RingMaster Club support if you believe your account has been accessed without authorization.\n\n'
                              'You are responsible for activity performed through your account unless prohibited by law.',
                          sectionStyle,
                          bodyStyle,
                        ),
                        _section(
                          '4. Club Roles & Permissions',
                          'Club Officers, treasurers, secretaries, committee members, and other authorized users may receive different levels of access.\n\n'
                              'Clubs are responsible for assigning appropriate permissions, removing access when a person no longer serves in a role, and reviewing access periodically.\n\n'
                              'RingMaster Club is not responsible for actions taken by users who were granted access by a club.',
                          sectionStyle,
                          bodyStyle,
                        ),
                        _section(
                          '5. Data Accuracy & User Responsibility',
                          'Users are responsible for the accuracy and completeness of information entered, submitted, imported, reviewed, or managed within the system.\n\n'
                              'This may include:\n'
                              '• Member and household information\n'
                              '• Membership status and renewal dates\n'
                              '• Club officer and committee assignments\n'
                              '• Dues, fees, payments, credits, and balances\n'
                              '• Sweepstakes points, standings, awards, and sanction-tracking requests\n'
                              '• Classifieds, sale listings, breeder listings, and service listings\n'
                              '• Meetings, events, attendance, and volunteer records\n'
                              '• Announcements, messages, documents, and reports\n\n'
                              'RingMaster Club does not independently verify the accuracy, completeness, or legal sufficiency of information entered by users.',
                          sectionStyle,
                          bodyStyle,
                        ),
                        _section(
                          '6. Memberships, Dues & Payments',
                          'Clubs are responsible for establishing their own membership requirements, dues, renewal periods, refund rules, and payment policies.\n\n'
                              'RingMaster Club may provide tools to collect, record, or report payments, but the club remains responsible for determining whether a member is in good standing and whether a payment, credit, refund, or adjustment is valid.\n\n'
                              'Unless otherwise stated, fees paid directly to RingMaster Club are non-refundable. A club may maintain separate refund policies for amounts collected on its behalf.',
                          sectionStyle,
                          bodyStyle,
                        ),
                        _section(
                          '7. Club Communications',
                          'RingMaster Club may allow authorized users to send email, notices, announcements, reminders, or other communications.\n\n'
                              'Users agree not to send unlawful, deceptive, harassing, abusive, unsolicited, or otherwise inappropriate communications. Clubs are responsible for the content they send and for honoring applicable communication preferences and legal requirements.',
                          sectionStyle,
                          bodyStyle,
                        ),
                        _section(
                          '8. Events, Meetings & Documents',
                          'Event, meeting, attendance, document, and scheduling tools are provided for organizational convenience.\n\n'
                              'Clubs are responsible for confirming dates, locations, eligibility requirements, meeting notices, document accuracy, and any official approval or recordkeeping requirements.',
                          sectionStyle,
                          bodyStyle,
                        ),
                        _section(
                          '9. Uploaded Content',
                          'You retain responsibility for content you upload or submit, including text, images, documents, logos, meeting materials, and member records.\n\n'
                              'You represent that you have the right to use and share that content and that it does not violate the rights of another person or organization.\n\n'
                              'You grant RingMaster Club a limited license to store, process, display, and transmit submitted content as necessary to provide the service.',
                          sectionStyle,
                          bodyStyle,
                        ),
                        _section(
                          '10. Sweepstakes, Points & Awards',
                          'RingMaster Club may provide tools to record, calculate, display, verify, or report sweepstakes points, standings, awards, and related results.\n\n'
                              'Clubs, hosting organizations, and authorized officials remain responsible for establishing rules, determining eligibility, submitting accurate information, reviewing calculations, resolving ties or disputes, approving corrections, and declaring final standings or awards.\n\n'
                              'RingMaster Club does not independently certify that points, standings, rankings, or awards are complete, accurate, or official.',
                          sectionStyle,
                          bodyStyle,
                        ),
                        _section(
                          '11. Sanction and Event Tracking Requests',
                          'RingMaster Club may allow a hosting club or authorized organization to request that points, eligibility, attendance, results, or related information be tracked for an upcoming or completed sanctioned event.\n\n'
                              'The requesting organization is responsible for having authority to submit the request, identifying the correct event and participants, supplying accurate rules and data, and reviewing the resulting records or reports.\n\n'
                              'RingMaster Club acts only as a recordkeeping and reporting platform and does not grant, approve, deny, or enforce sanctions.',
                          sectionStyle,
                          bodyStyle,
                        ),
                        _section(
                          '12. Classifieds, Sales & Listings',
                          'RingMaster Club may allow clubs or users to publish classifieds, animal sale listings, breeder listings, service listings, or similar content.\n\n'
                              'RingMaster Club is not the buyer, seller, broker, auctioneer, escrow provider, shipper, inspector, veterinarian, or guarantor for any listing or transaction. Users are solely responsible for verifying identity, ownership, condition, health, pedigree, registration, legality, price, payment, delivery, transportation, refunds, and any warranties or representations.\n\n'
                              'Listings must be accurate, lawful, and appropriate for the platform. RingMaster Club may remove or restrict listings that appear fraudulent, misleading, unsafe, prohibited, or inconsistent with platform rules.\n\n'
                              'Any dispute arising from a listing or transaction is between the participating users or organizations unless applicable law requires otherwise.',
                          sectionStyle,
                          bodyStyle,
                        ),
                        _section(
                          '13. Acceptable Use',
                          'You agree not to:\n'
                              '• Disrupt or interfere with the platform or other users\n'
                              '• Attempt unauthorized access to accounts, records, systems, or restricted areas\n'
                              '• Intentionally submit false, misleading, abusive, discriminatory, or unlawful information\n'
                              '• Upload malicious software or interfere with platform security\n'
                              '• Use the platform to harass, threaten, exploit, or impersonate another person\n'
                              '• Use RingMaster Club for purposes unrelated to legitimate club or membership administration',
                          sectionStyle,
                          bodyStyle,
                        ),
                        _section(
                          '14. Club Independence',
                          'RingMaster Club is a software platform and is not the governing body, parent organization, legal representative, fiduciary, or decision-maker for any club using the service.\n\n'
                              'Each club remains solely responsible for its bylaws, rules, elections, finances, tax obligations, legal compliance, membership decisions, disputes, disciplinary actions, and internal governance.',
                          sectionStyle,
                          bodyStyle,
                        ),
                        _section(
                          '15. Data Storage & Retention',
                          'Account, club, membership, payment, event, communication, document, audit, and related data may be stored for operational, historical, reporting, security, backup, audit, and legal purposes.\n\n'
                              'Some records may remain available after a membership ends or a club stops using the service when reasonably necessary to preserve transaction history, audit trails, account security, or legal compliance.\n\n'
                              'Data retention periods may vary based on record type, service plan, legal requirements, and operational needs.',
                          sectionStyle,
                          bodyStyle,
                        ),
                        _section(
                          '16. Service Availability',
                          'We aim to provide reliable service, but RingMaster Club does not guarantee uninterrupted, error-free, or continuously available operation.\n\n'
                              'We may modify, suspend, restrict, or discontinue portions of the platform as needed for maintenance, security, improvements, legal compliance, or business reasons.',
                          sectionStyle,
                          bodyStyle,
                        ),
                        _section(
                          '17. Intellectual Property',
                          'RingMaster Club, including its name, design, software, features, workflows, reports, branding, and related materials, is owned by Hunter Interactive, RingMaster One, or their licensors.\n\n'
                              'You may not copy, reproduce, modify, distribute, reverse engineer, or create derivative works from the platform except as expressly permitted by law or written authorization.',
                          sectionStyle,
                          bodyStyle,
                        ),
                        _section(
                          '18. Third-Party Services',
                          'RingMaster Club may rely on third-party providers for hosting, authentication, payments, email, storage, analytics, document delivery, or other operational services.\n\n'
                              'Use of third-party services may also be subject to their own terms and policies. RingMaster Club is not responsible for third-party outages, actions, websites, terms, or policies outside our control.',
                          sectionStyle,
                          bodyStyle,
                        ),
                        _section(
                          '19. Suspension or Termination',
                          'We may restrict, suspend, or terminate access when reasonably necessary to address nonpayment, misuse, security concerns, unlawful activity, repeated violations, or risk to the platform or its users.\n\n'
                              'A club may also remove a user from its organization or change that user’s role or permissions according to its own rules and authority.',
                          sectionStyle,
                          bodyStyle,
                        ),
                        _section(
                          '20. Disclaimer of Warranties',
                          'RingMaster Club is provided “as is” and “as available,” without warranties of any kind, express or implied.\n\n'
                              'We do not warrant that the platform will be accurate, reliable, uninterrupted, error-free, secure, or suitable for every club’s legal, financial, tax, governance, or recordkeeping requirements.',
                          sectionStyle,
                          bodyStyle,
                        ),
                        _section(
                          '21. Limitation of Liability',
                          'To the fullest extent permitted by law, RingMaster Club and Hunter Interactive are not liable for:\n'
                              '• Incorrect, incomplete, or lost member records\n'
                              '• Missed renewals, dues, notices, meetings, elections, or deadlines\n'
                              '• Unauthorized actions taken by club users\n'
                              '• Club governance, membership, financial, or disciplinary decisions\n'
                              '• Incorrect sweepstakes points, standings, sanctions, eligibility determinations, or awards\n'
                              '• Classified listings, sales, payments, delivery, health claims, ownership disputes, or transaction losses\n'
                              '• Loss of data, revenue, business, goodwill, or opportunity\n'
                              '• Indirect, incidental, special, consequential, exemplary, or punitive damages',
                          sectionStyle,
                          bodyStyle,
                        ),
                        _section(
                          '22. Indemnification',
                          'To the extent permitted by law, you agree to defend, indemnify, and hold harmless RingMaster Club, Hunter Interactive, and their owners, employees, contractors, and service providers from claims, losses, liabilities, damages, and expenses arising from your misuse of the platform, your submitted content, your violation of these Terms, or your violation of another person’s rights.',
                          sectionStyle,
                          bodyStyle,
                        ),
                        _section(
                          '23. Governing Law',
                          'These Terms are governed by the laws of the State of Indiana, without regard to conflict-of-law principles.',
                          sectionStyle,
                          bodyStyle,
                        ),
                        _section(
                          '24. Changes to Terms',
                          'These Terms may be updated as the platform evolves. When material changes are made, users may be required to review and accept the updated Terms before continuing to use RingMaster Club.\n\n'
                              'Continued use of RingMaster Club after an updated version becomes effective constitutes acceptance of the current Terms.',
                          sectionStyle,
                          bodyStyle,
                        ),
                        _section(
                          '25. Contact',
                          'For questions, concerns, support requests, or notices regarding these Terms, please contact RingMaster Club support through the application or official RingMaster support channels.',
                          sectionStyle,
                          bodyStyle,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _section(
    String title,
    String body,
    TextStyle? titleStyle,
    TextStyle? bodyStyle,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: titleStyle),
          const SizedBox(height: AppSpacing.xs),
          Text(body, style: bodyStyle),
        ],
      ),
    );
  }
}