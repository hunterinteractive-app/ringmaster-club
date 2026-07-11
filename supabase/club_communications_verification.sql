-- Club Communications verification queries.
-- Run these after exercising membership, sanction, payment, and manual flows.

select id, club_id, template_key, message_kind, recipient_name, recipient_email,
       channel, status, subject, sent_at, created_at
from club_communications
order by created_at desc
limit 20;

select id, club_id, template_key, message_kind, audience_type, recipient_count,
       notification_count, email_count, status, created_at
from club_communication_batches
order by created_at desc
limit 20;

-- Disabled workflow template check:
-- 1. Create or update the club override for the workflow template.
-- 2. Run the workflow action.
-- 3. Confirm no newer communication rows exist for that template_key.
--
-- Example:
-- update club_communication_templates
-- set is_enabled = false
-- where club_id = '<club-id>'
--   and template_key = 'membership_approved';
--
-- select id, club_id, template_key, related_type, related_id, created_at
-- from club_communications
-- where club_id = '<club-id>'
--   and template_key = 'membership_approved'
-- order by created_at desc
-- limit 10;

-- RLS/policy checklist for the live database:
-- - Global templates are readable where club_id is null.
-- - Club staff can read/manage templates, batches, and communications for their club.
-- - Club staff inserts/updates are constrained to club_id values they can manage.
-- - Club staff cannot update global templates where club_id is null.
-- - Recipients can read rows where recipient_user_id = auth.uid().
-- - Service-role edge functions can update queued email rows to sent/failed.

-- Constraint/migration checklist for the live database:
-- Ensure club_communications.channel accepts:
--   notification, email, both, in_app
-- Ensure club_communications.status accepts:
--   draft, queued, sent, notification_created, failed, cancelled
-- Ensure club_communication_batches.status accepts:
--   draft, queued, sent, partial, failed, cancelled
-- If club_communications has no error text column, add one such as:
--   alter table public.club_communications
--   add column if not exists error_message text;
