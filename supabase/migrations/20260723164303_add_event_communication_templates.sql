-- Default member-facing notices for a newly published event and a later
-- announced update. Clubs can override either template in Communications.

insert into public.club_communication_templates (
  club_id,
  template_key,
  name,
  description,
  subject,
  body,
  message,
  channel_default,
  is_system_default,
  is_enabled,
  is_active
)
select
  null,
  'event_published',
  'Event Published',
  'Sent to active members when a club publishes an event.',
  'New event: {{event_title}}',
  E'Hello {{recipient_name}},\n\n{{club_name}} has published a new {{event_type}}.\n\n{{event_title}}\n{{event_date}}\n{{event_time}} {{event_timezone}}\n\nLocation: {{event_location}}\n{{event_description}}\n\n{{club_name}}',
  E'Hello {{recipient_name}},\n\n{{club_name}} has published a new {{event_type}}.\n\n{{event_title}}\n{{event_date}}\n{{event_time}} {{event_timezone}}\n\nLocation: {{event_location}}\n{{event_description}}\n\n{{club_name}}',
  'notification',
  true,
  true,
  true
where not exists (
  select 1
  from public.club_communication_templates
  where club_id is null and template_key = 'event_published'
);

insert into public.club_communication_templates (
  club_id,
  template_key,
  name,
  description,
  subject,
  body,
  message,
  channel_default,
  is_system_default,
  is_enabled,
  is_active
)
select
  null,
  'event_updated',
  'Event Updated',
  'Sent to active members when staff choose to announce an update to a published event.',
  'Event update: {{event_title}}',
  E'Hello {{recipient_name}},\n\n{{club_name}} has updated an event.\n\n{{event_title}}\n{{event_date}}\n{{event_time}} {{event_timezone}}\n\nLocation: {{event_location}}\n{{event_description}}\n\n{{event_notes}}\n\n{{club_name}}',
  E'Hello {{recipient_name}},\n\n{{club_name}} has updated an event.\n\n{{event_title}}\n{{event_date}}\n{{event_time}} {{event_timezone}}\n\nLocation: {{event_location}}\n{{event_description}}\n\n{{event_notes}}\n\n{{club_name}}',
  'notification',
  true,
  true,
  true
where not exists (
  select 1
  from public.club_communication_templates
  where club_id is null and template_key = 'event_updated'
);
