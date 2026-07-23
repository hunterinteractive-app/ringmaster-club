-- Make Resend webhook retries idempotent. The original email and attachments
-- are placed in the existing private club documents bucket by the edge function.
alter table public.club_sweepstakes_report_packages
  add column if not exists source_provider_message_id text;

create unique index if not exists club_sweepstakes_report_packages_provider_message_id_idx
  on public.club_sweepstakes_report_packages (source_provider_message_id)
  where source_provider_message_id is not null;
