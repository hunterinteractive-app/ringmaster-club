// lib/screens/legal/privacy_policy_screen.dart

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/rm_widgets.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

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
      appBar: AppBar(title: const Text('Privacy Policy')),
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
                          'RingMaster Club – Privacy Policy',
                          style: titleStyle,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Effective Date: May 2026 (v2026-05)',
                          style: bodyStyle?.copyWith(color: AppColors.muted),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Text(
                          'RingMaster Club respects your privacy and is committed to protecting the information used to provide club and membership-management services.',
                          style: bodyStyle,
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        _section(
                          '1. Information We Collect',
                          'We may collect:\n'
                              '• Name, email address, phone number, mailing address, and other contact information\n'
                              '• Account credentials, authentication records, and account identifiers\n'
                              '• Display name, profile details, and communication preferences\n'
                              '• Club, officer, committee, and role information\n'
                              '• Member, household, dependent, and emergency-contact information\n'
                              '• Membership status, renewal dates, dues, credits, balances, and payment records\n'
                              '• Sweepstakes points, standings, award history, and sanctioned-event tracking requests\n'
                              '• Classified, sale, breeder, or service listing details, including descriptions, prices, images, and contact preferences\n'
                              '• Meeting, event, attendance, volunteer, election, and activity records\n'
                              '• Messages, announcements, support requests, documents, images, and other uploaded content\n'
                              '• Device, browser, IP address, diagnostic, and usage information\n'
                              '• Transaction-related information when paid features or payment services are used',
                          sectionStyle,
                          bodyStyle,
                        ),
                        _section(
                          '2. How We Use Information',
                          'We may use information to:\n'
                              '• Create, authenticate, and maintain user accounts\n'
                              '• Operate club, membership, dues, communication, event, meeting, document, and reporting features\n'
                              '• Allow authorized club users to manage records and permissions\n'
                              '• Process or record payments, renewals, credits, and balances\n'
                              '• Calculate, display, verify, or report sweepstakes points, standings, awards, and sanctioned-event eligibility\n'
                              '• Publish and manage classifieds, sale listings, breeder listings, and related member content\n'
                              '• Send account, membership, event, payment, security, and service-related communications\n'
                              '• Provide support and investigate reported problems\n'
                              '• Improve performance, reliability, accessibility, and user experience\n'
                              '• Maintain security, prevent fraud or misuse, and enforce platform rules\n'
                              '• Meet legal, tax, audit, dispute-resolution, and recordkeeping obligations',
                          sectionStyle,
                          bodyStyle,
                        ),
                        _section(
                          '3. Club and User Responsibility',
                          'Clubs and authorized users are responsible for determining what information they enter, collect, upload, maintain, share, or communicate through RingMaster Club.\n\n'
                              'Each club is responsible for having the authority to collect and use member information, assigning appropriate access, maintaining accurate records, and complying with laws and organizational policies that apply to its activities.',
                          sectionStyle,
                          bodyStyle,
                        ),
                        _section(
                          '4. How Information Is Shared',
                          'We do not sell personal information.\n\n'
                              'Information may be shared:\n'
                              '• With authorized club owners, officers, administrators, treasurers, secretaries, committee members, or other users based on their assigned permissions\n'
                              '• With members or households when needed to provide directories, communications, events, membership tools, or other club services\n'
                              '• With hosting clubs, sanctioning organizations, or authorized officials when needed to track points, standings, eligibility, or awards for an upcoming or completed event\n'
                              '• With users who can view a classified, sale, breeder, or service listing, according to the visibility and contact options selected by the listing owner or club\n'
                              '• With service providers that support hosting, authentication, payments, email, storage, analytics, security, support, or document delivery\n'
                              '• With another organization or service when a user or club directs or authorizes the transfer\n'
                              '• When required by law, court order, legal process, or governmental request\n'
                              '• When reasonably necessary to protect the rights, safety, security, or integrity of RingMaster Club, Hunter Interactive, clubs, users, or the public\n'
                              '• In connection with a merger, acquisition, financing, reorganization, sale, or transfer of some or all of the business, subject to appropriate safeguards',
                          sectionStyle,
                          bodyStyle,
                        ),
                        _section(
                          '5. Member Directories and Club Visibility',
                          'Some clubs may enable member directories, officer listings, contact lists, event rosters, or similar features. The club determines which information is displayed and who may access it.\n\n'
                              'Users should review their club’s settings and policies and should contact the club if they believe information is displayed incorrectly or too broadly.',
                          sectionStyle,
                          bodyStyle,
                        ),
                        _section(
                          '6. Payments and Financial Information',
                          'Payment transactions may be processed by third-party payment providers. RingMaster Club may receive transaction identifiers, status, amount, payer details, fees, and related records, but may not directly store full payment-card numbers.\n\n'
                              'Payment providers process information under their own privacy policies and security practices.',
                          sectionStyle,
                          bodyStyle,
                        ),
                        _section(
                          '7. Sweepstakes, Sanctioned Events, and Classifieds',
                          'RingMaster Club may process sweepstakes points, standings, award history, and sanctioned-event requests submitted by hosting clubs or authorized organizations. This information may be used to calculate or verify eligibility, prepare reports, and support future or completed events.\n\n'
                              'RingMaster Club may also allow clubs or members to publish classifieds, sale listings, breeder listings, or service listings. Information placed in a listing may be visible to other users according to the selected visibility settings. Users should avoid including information they do not want displayed publicly or shared with prospective buyers, sellers, or other members.\n\n'
                              'RingMaster Club does not independently verify the accuracy of points, standings, sanction requests, listing descriptions, prices, ownership claims, health statements, or other user-submitted information.',
                          sectionStyle,
                          bodyStyle,
                        ),
                        _section(
                          '8. Data Storage and Retention',
                          'Information may be stored for operational, historical, reporting, security, backup, audit, tax, legal, and dispute-resolution purposes.\n\n'
                              'Retention periods may vary based on record type, club settings, service plan, legal requirements, payment history, account status, and operational needs.\n\n'
                              'Certain records, including transaction history, membership history, audit logs, communications, support records, and security events, may be retained after a membership ends, a user leaves a club, or an account-deletion request is made when reasonably necessary or legally required.',
                          sectionStyle,
                          bodyStyle,
                        ),
                        _section(
                          '9. Security',
                          'We use reasonable administrative, technical, and organizational safeguards, including secured hosting, authentication controls, access restrictions, and service monitoring.\n\n'
                              'No method of internet transmission or electronic storage is completely secure, and we cannot guarantee absolute security. Users and clubs should protect login access, assign permissions carefully, and report suspected unauthorized access promptly.',
                          sectionStyle,
                          bodyStyle,
                        ),
                        _section(
                          '10. Your Choices and Rights',
                          'Depending on your location and applicable law, you may have rights to request access to, correction of, deletion of, or a copy of certain personal information.\n\n'
                              'You may also be able to update profile details, communication preferences, or directory visibility through the platform or by contacting your club.\n\n'
                              'Some requests may need to be handled by the club that collected or controls the information. Certain information may be retained when required for legal compliance, security, transaction records, audit history, dispute resolution, or legitimate operational needs.',
                          sectionStyle,
                          bodyStyle,
                        ),
                        _section(
                          '11. Children’s Privacy',
                          'RingMaster Club is not intended for children under 13 to create or independently manage accounts.\n\n'
                              'Clubs, parents, guardians, or authorized adults may maintain information about minors when appropriate for membership or club activities. They are responsible for having any required authority or consent.\n\n'
                              'If we learn that a child under 13 created an account or provided personal information without appropriate authorization, we will take reasonable steps to review and remove or restrict that information as appropriate.',
                          sectionStyle,
                          bodyStyle,
                        ),
                        _section(
                          '12. Cookies, Local Storage, and Similar Technologies',
                          'RingMaster Club may use cookies, browser storage, authentication tokens, and similar technologies to keep users signed in, preserve preferences, support security, improve performance, and understand platform usage.\n\n'
                              'Disabling these technologies may prevent some features from functioning correctly.',
                          sectionStyle,
                          bodyStyle,
                        ),
                        _section(
                          '13. Third-Party Services',
                          'RingMaster Club may use third-party providers for hosting, authentication, payments, email delivery, analytics, storage, security, support, and other operational needs.\n\n'
                              'These providers may process limited information as needed to perform their services and are governed by their own terms, privacy policies, and security practices.',
                          sectionStyle,
                          bodyStyle,
                        ),
                        _section(
                          '14. Data Transfers',
                          'Information may be processed or stored in the United States or other locations where RingMaster Club or its service providers operate.\n\n'
                              'Where required, we use reasonable safeguards for transfers of personal information across jurisdictions.',
                          sectionStyle,
                          bodyStyle,
                        ),
                        _section(
                          '15. Changes to This Policy',
                          'This Privacy Policy may be updated as the platform, legal requirements, or business practices evolve.\n\n'
                              'When material changes are made, users may be notified or required to review and accept the updated policy before continuing to use RingMaster Club.',
                          sectionStyle,
                          bodyStyle,
                        ),
                        _section(
                          '16. Contact',
                          'For privacy-related questions, requests, or concerns, please contact RingMaster Club support through the application or official RingMaster support channels.\n\n'
                              'For information controlled by a particular club, you may also need to contact that club directly.',
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