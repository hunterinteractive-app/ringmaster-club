-- One forwarded email can contain documents for several distinct shows.
-- Track the attachment group as part of provider-message idempotency so each
-- show receives an independent report package and results draft.
alter table public.club_sweepstakes_report_packages
  add column if not exists source_provider_group_key text;

update public.club_sweepstakes_report_packages
set source_provider_group_key = 'email'
where source_provider_group_key is null;

alter table public.club_sweepstakes_report_packages
  alter column source_provider_group_key set default 'email',
  alter column source_provider_group_key set not null;

drop index if exists public.club_sweepstakes_report_packages_provider_message_id_idx;

create unique index if not exists club_sweepstakes_report_packages_provider_message_group_idx
  on public.club_sweepstakes_report_packages (source_provider_message_id, source_provider_group_key)
  where source_provider_message_id is not null;
