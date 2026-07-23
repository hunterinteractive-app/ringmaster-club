import 'package:supabase_flutter/supabase_flutter.dart';

class ClubCommunicationsService {
  ClubCommunicationsService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<ClubCommunicationTemplate?> loadEnabledCommunicationTemplate({
    required String clubId,
    required String templateKey,
  }) async {
    final rows = await _client
        .from('club_communication_templates')
        .select(
          'id,club_id,template_key,subject,body,message,channel_default,'
          'is_enabled',
        )
        .eq('template_key', templateKey)
        .or('club_id.is.null,club_id.eq.$clubId');

    ClubCommunicationTemplate? globalTemplate;

    for (final row in rows.whereType<Map>()) {
      final template = ClubCommunicationTemplate.fromJson(
        Map<String, dynamic>.from(row),
      );

      if (template.clubId == clubId) {
        return template.isEnabled ? template : null;
      }

      if (template.clubId == null && template.isEnabled) {
        globalTemplate ??= template;
      }
    }

    return globalTemplate;
  }

  Future<String?> createWorkflowCommunication({
    required String clubId,
    required String clubName,
    required String templateKey,
    required String relatedType,
    required String relatedId,
    required String recipientName,
    required Map<String, String> variables,
    String messageKind = 'template',
    String audienceType = 'workflow',
    String? recipientUserId,
    String? recipientEmail,
    String? channelOverride,
    bool allowEmailWithoutAddon = false,
    bool preferEmailWhenAvailable = false,
    String? createdBy,
  }) async {
    final communicationIds = await createWorkflowCommunications(
      clubId: clubId,
      clubName: clubName,
      templateKey: templateKey,
      relatedType: relatedType,
      relatedId: relatedId,
      recipients: [
        ClubCommunicationRecipient(
          name: recipientName,
          userId: recipientUserId,
          email: recipientEmail,
        ),
      ],
      variables: variables,
      messageKind: messageKind,
      audienceType: audienceType,
      channelOverride: channelOverride,
      allowEmailWithoutAddon: allowEmailWithoutAddon,
      preferEmailWhenAvailable: preferEmailWhenAvailable,
      createdBy: createdBy,
    );
    return communicationIds.isEmpty ? null : communicationIds.first;
  }

  Future<List<String>> createWorkflowCommunications({
    required String clubId,
    required String clubName,
    required String templateKey,
    required String relatedType,
    required String relatedId,
    required List<ClubCommunicationRecipient> recipients,
    required Map<String, String> variables,
    String messageKind = 'template',
    String audienceType = 'workflow',
    String? channelOverride,
    bool allowEmailWithoutAddon = false,
    bool preferEmailWhenAvailable = false,
    String? createdBy,
  }) async {
    if (recipients.isEmpty) return const [];

    final template = await loadEnabledCommunicationTemplate(
      clubId: clubId,
      templateKey: templateKey,
    );
    if (template == null) return const [];

    final emailAddonEnabled = allowEmailWithoutAddon
        ? true
        : await _clubEmailAddonEnabled(clubId);
    final now = DateTime.now().toIso8601String();
    final deliveries = recipients.map((recipient) {
      final recipientEmail = _nullableString(recipient.email);
      final canEmail = emailAddonEnabled && recipientEmail != null;
      final channel = preferEmailWhenAvailable && canEmail
          ? 'both'
          : _effectiveChannel(
              requestedChannel: channelOverride ?? template.channelDefault,
              emailAddonEnabled: emailAddonEnabled,
              recipientEmail: recipientEmail,
            );
      final allVariables = <String, String>{
        'club_name': clubName,
        'recipient_name': recipient.name,
        ...variables,
      };
      final subject = renderTemplate(
        template.subject.isEmpty
            ? 'Update from {{club_name}}'
            : template.subject,
        allVariables,
      );
      final body = renderTemplate(
        template.body.isEmpty ? template.message : template.body,
        allVariables,
      );
      final hasEmail = channel == 'email' || channel == 'both';
      return _WorkflowDelivery(
        recipient: recipient,
        recipientEmail: recipientEmail,
        channel: channel,
        subject: subject,
        body: body,
        hasEmail: hasEmail,
      );
    }).toList();

    final notificationCount = deliveries
        .where(
          (delivery) =>
              delivery.channel == 'notification' || delivery.channel == 'both',
        )
        .length;
    final emailCount = deliveries.where((delivery) => delivery.hasEmail).length;
    final hasEmail = emailCount > 0;

    final batch = await _client
        .from('club_communication_batches')
        .insert({
          'club_id': clubId,
          'message_kind': messageKind,
          'template_key': templateKey,
          'subject': template.subject,
          'body': template.body.isEmpty ? template.message : template.body,
          'audience_type': audienceType,
          'recipient_count': deliveries.length,
          'notification_count': notificationCount,
          'email_count': emailCount,
          'status': hasEmail ? 'queued' : 'sent',
          'created_by': createdBy,
          'sent_at': hasEmail ? null : now,
          'updated_at': now,
        })
        .select('id')
        .single();

    final communicationRows = await _client
        .from('club_communications')
        .insert([
          for (final delivery in deliveries)
            {
              'club_id': clubId,
              'batch_id': batch['id'],
              'template_key': templateKey,
              'message_kind': messageKind,
              'related_type': relatedType,
              'related_id': relatedId,
              'recipient_user_id': delivery.recipient.userId,
              'recipient_email': delivery.recipientEmail,
              'recipient_name': delivery.recipient.name,
              'channel': delivery.channel,
              'subject': delivery.subject,
              'body': delivery.body,
              'message': delivery.body,
              'status': delivery.hasEmail ? 'queued' : 'notification_created',
              'sent_at': delivery.hasEmail ? null : now,
              'created_by': createdBy,
              'updated_at': now,
            },
        ])
        .select('id');

    return communicationRows
        .whereType<Map>()
        .map((row) => row['id']?.toString())
        .whereType<String>()
        .toList();
  }

  Future<bool> _clubEmailAddonEnabled(String clubId) async {
    final row = await _client
        .from('clubs')
        .select('email_addon_enabled,email_communications_addon_enabled')
        .eq('id', clubId)
        .maybeSingle();
    return row?['email_communications_addon_enabled'] == true ||
        row?['email_addon_enabled'] == true;
  }

  String _effectiveChannel({
    required String requestedChannel,
    required bool emailAddonEnabled,
    required String? recipientEmail,
  }) {
    final normalized = requestedChannel.trim().toLowerCase();
    final canEmail = emailAddonEnabled && recipientEmail != null;

    if (canEmail && (normalized == 'email' || normalized == 'both')) {
      return 'both';
    }

    return 'notification';
  }

  static String renderTemplate(String template, Map<String, String> variables) {
    var rendered = template;
    for (final entry in variables.entries) {
      rendered = rendered.replaceAll('{{${entry.key}}}', entry.value);
    }

    final recipientName = variables['recipient_name'];
    if (recipientName != null) {
      rendered = rendered
          .replaceAll('[Recipient Name]', recipientName)
          .replaceAll('(Name)', recipientName);
    }

    return rendered;
  }
}

class ClubCommunicationRecipient {
  const ClubCommunicationRecipient({
    required this.name,
    this.userId,
    this.email,
  });

  final String name;
  final String? userId;
  final String? email;
}

class _WorkflowDelivery {
  const _WorkflowDelivery({
    required this.recipient,
    required this.recipientEmail,
    required this.channel,
    required this.subject,
    required this.body,
    required this.hasEmail,
  });

  final ClubCommunicationRecipient recipient;
  final String? recipientEmail;
  final String channel;
  final String subject;
  final String body;
  final bool hasEmail;
}

class ClubCommunicationTemplate {
  const ClubCommunicationTemplate({
    required this.id,
    required this.templateKey,
    required this.subject,
    required this.body,
    required this.message,
    required this.channelDefault,
    required this.isEnabled,
    this.clubId,
  });

  final String id;
  final String? clubId;
  final String templateKey;
  final String subject;
  final String body;
  final String message;
  final String channelDefault;
  final bool isEnabled;

  factory ClubCommunicationTemplate.fromJson(Map<String, dynamic> json) {
    return ClubCommunicationTemplate(
      id: json['id'].toString(),
      clubId: _nullableString(json['club_id']),
      templateKey: _nullableString(json['template_key']) ?? '',
      subject: _nullableString(json['subject']) ?? '',
      body: _nullableString(json['body']) ?? '',
      message: _nullableString(json['message']) ?? '',
      channelDefault:
          _nullableString(json['channel_default']) ?? 'notification',
      isEnabled: json['is_enabled'] != false,
    );
  }
}

String? _nullableString(dynamic value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}
