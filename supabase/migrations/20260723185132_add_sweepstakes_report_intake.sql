-- Sweepstakes report intake, sanction reconciliation, publishing, and reminder
-- settings. The original report package is always retained as restricted staff
-- evidence; only reviewed/processed data may affect standings.

alter table public.club_sweepstakes_seasons
  add column if not exists publication_mode text not null default 'manual'
    check (publication_mode in ('live', 'manual')),
  add column if not exists visibility text not null default 'members'
    check (visibility in ('public', 'members')),
  add column if not exists public_display_format text not null default 'name_state'
    check (public_display_format in ('name_only', 'name_state', 'name_city_state')),
  add column if not exists published_at timestamptz,
  add column if not exists published_by uuid references auth.users(id);

create table if not exists public.club_sweepstakes_settings (
  club_id uuid primary key references public.clubs(id) on delete cascade,
  report_intake_enabled boolean not null default false,
  report_intake_token uuid not null default gen_random_uuid(),
  automatic_report_reminders_enabled boolean not null default false,
  report_due_days integer not null default 30 check (report_due_days between 1 and 365),
  report_retention_days integer not null default 365 check (report_retention_days between 30 and 3650),
  reminder_approval_required boolean not null default false,
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.club_sweepstakes_expected_reports (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  season_id uuid references public.club_sweepstakes_seasons(id) on delete set null,
  sanction_request_id uuid unique references public.club_sanction_requests(id) on delete set null,
  club_sanction_number text,
  arba_sanction_number text,
  show_name text not null,
  show_date date not null,
  show_end_date date,
  show_location text,
  show_secretary_name text,
  show_secretary_email text,
  expected_sections jsonb not null default '[]'::jsonb,
  expected_report_types jsonb not null default '[]'::jsonb,
  due_date date not null,
  status text not null default 'expected'
    check (status in ('expected', 'partial', 'received', 'needs_review', 'processed', 'overdue', 'waived')),
  last_reminder_sent_at timestamptz,
  reminder_count integer not null default 0,
  notes text,
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists club_sweepstakes_expected_reports_club_status_idx
  on public.club_sweepstakes_expected_reports (club_id, status, due_date);

create table if not exists public.club_sweepstakes_report_packages (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  expected_report_id uuid references public.club_sweepstakes_expected_reports(id) on delete set null,
  season_id uuid references public.club_sweepstakes_seasons(id) on delete set null,
  source_type text not null default 'manual'
    check (source_type in ('manual', 'forwarded_email', 'easy2show', 'ringmaster_show_breed', 'ringmaster_show_state', 'unknown')),
  source_subject text,
  source_sender_email text,
  source_received_at timestamptz,
  storage_path text,
  attachment_manifest jsonb not null default '[]'::jsonb,
  extracted_summary jsonb not null default '{}'::jsonb,
  review_notes text,
  status text not null default 'pending'
    check (status in ('pending', 'unmatched', 'needs_review', 'reconciled', 'processed', 'rejected')),
  point_mismatch boolean not null default false,
  processed_by uuid references auth.users(id),
  processed_at timestamptz,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists club_sweepstakes_report_packages_club_status_idx
  on public.club_sweepstakes_report_packages (club_id, status, created_at desc);

alter table public.club_sweepstakes_settings enable row level security;
alter table public.club_sweepstakes_expected_reports enable row level security;
alter table public.club_sweepstakes_report_packages enable row level security;

create policy "Club staff can manage sweepstakes settings"
  on public.club_sweepstakes_settings for all to authenticated
  using (is_club_staff(club_id, auth.uid()))
  with check (is_club_staff(club_id, auth.uid()));

create policy "Club staff can manage expected sweepstakes reports"
  on public.club_sweepstakes_expected_reports for all to authenticated
  using (is_club_staff(club_id, auth.uid()))
  with check (is_club_staff(club_id, auth.uid()));

create policy "Club staff can manage sweepstakes report packages"
  on public.club_sweepstakes_report_packages for all to authenticated
  using (is_club_staff(club_id, auth.uid()))
  with check (is_club_staff(club_id, auth.uid()));

create or replace function public.sync_expected_sweepstakes_report_from_sanction()
returns trigger
language plpgsql
as $$
declare
  report_due_days integer;
begin
  if new.status <> 'approved' then
    return new;
  end if;

  select coalesce(settings.report_due_days, 30)
  into report_due_days
  from public.club_sweepstakes_settings settings
  where settings.club_id = new.club_id;

  insert into public.club_sweepstakes_expected_reports (
    club_id,
    sanction_request_id,
    club_sanction_number,
    arba_sanction_number,
    show_name,
    show_date,
    show_end_date,
    show_location,
    show_secretary_name,
    show_secretary_email,
    due_date,
    expected_sections,
    expected_report_types
  ) values (
    new.club_id,
    new.id,
    new.sanction_number,
    coalesce(new.request_details ->> 'arba_sanction_number', new.sanction_number),
    new.show_name,
    new.show_date,
    new.show_end_date,
    new.location_name,
    new.contact_name,
    new.contact_email,
    coalesce(new.show_end_date, new.show_date) + coalesce(report_due_days, 30),
    coalesce(new.request_details -> 'expected_sections', '[]'::jsonb),
    coalesce(new.request_details -> 'expected_report_types', '[]'::jsonb)
  ) on conflict (sanction_request_id) do update
    set club_sanction_number = excluded.club_sanction_number,
        arba_sanction_number = excluded.arba_sanction_number,
        show_name = excluded.show_name,
        show_date = excluded.show_date,
        show_end_date = excluded.show_end_date,
        show_location = excluded.show_location,
        show_secretary_name = excluded.show_secretary_name,
        show_secretary_email = excluded.show_secretary_email,
        expected_sections = excluded.expected_sections,
        expected_report_types = excluded.expected_report_types,
        due_date = excluded.due_date,
        updated_at = now();
  return new;
end;
$$;

drop trigger if exists sync_expected_sweepstakes_report_from_sanction
  on public.club_sanction_requests;
create trigger sync_expected_sweepstakes_report_from_sanction
after insert or update of status, sanction_number, show_name, show_date, show_end_date,
  location_name, contact_name, contact_email, request_details
on public.club_sanction_requests
for each row execute function public.sync_expected_sweepstakes_report_from_sanction();

-- Backfill approved sanctions into the expected-report queue.
insert into public.club_sweepstakes_expected_reports (
  club_id, sanction_request_id, club_sanction_number, arba_sanction_number,
  show_name, show_date, show_end_date, show_location, show_secretary_name,
  show_secretary_email, due_date, expected_sections, expected_report_types
)
select
  sanction.club_id,
  sanction.id,
  sanction.sanction_number,
  coalesce(sanction.request_details ->> 'arba_sanction_number', sanction.sanction_number),
  sanction.show_name,
  sanction.show_date,
  sanction.show_end_date,
  sanction.location_name,
  sanction.contact_name,
  sanction.contact_email,
  coalesce(sanction.show_end_date, sanction.show_date) + coalesce(settings.report_due_days, 30),
  coalesce(sanction.request_details -> 'expected_sections', '[]'::jsonb),
  coalesce(sanction.request_details -> 'expected_report_types', '[]'::jsonb)
from public.club_sanction_requests sanction
left join public.club_sweepstakes_settings settings on settings.club_id = sanction.club_id
where sanction.status = 'approved'
on conflict (sanction_request_id) do nothing;
