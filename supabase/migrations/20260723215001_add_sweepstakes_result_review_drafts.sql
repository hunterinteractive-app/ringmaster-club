create table public.club_sweepstakes_result_imports (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  report_package_id uuid not null unique references public.club_sweepstakes_report_packages(id) on delete cascade,
  expected_report_id uuid references public.club_sweepstakes_expected_reports(id) on delete set null,
  season_id uuid references public.club_sweepstakes_seasons(id) on delete set null,
  source_report_type text,
  source_total_points numeric,
  calculated_total_points numeric,
  point_mismatch boolean not null default false,
  status text not null default 'draft' check (status in ('draft','under_review','approved','rejected','applied')),
  review_notes text,
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  applied_by uuid references auth.users(id),
  applied_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.club_sweepstakes_result_import_rows (
  id uuid primary key default gen_random_uuid(),
  import_id uuid not null references public.club_sweepstakes_result_imports(id) on delete cascade,
  club_id uuid not null references public.clubs(id) on delete cascade,
  division_id uuid references public.club_sweepstakes_divisions(id) on delete set null,
  exhibitor_name text not null,
  membership_number text,
  species text,
  breed text,
  variety text,
  placement text,
  source_points numeric,
  calculated_points numeric not null default 0,
  point_mismatch boolean not null default false,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  review_notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index club_sweepstakes_result_import_rows_import_idx
  on public.club_sweepstakes_result_import_rows(import_id, status);

alter table public.club_sweepstakes_result_imports enable row level security;
alter table public.club_sweepstakes_result_import_rows enable row level security;

create policy "Club staff can manage sweepstakes result imports"
  on public.club_sweepstakes_result_imports for all to authenticated
  using (is_club_staff(club_id, auth.uid()))
  with check (is_club_staff(club_id, auth.uid()));
create policy "Club staff can manage sweepstakes result import rows"
  on public.club_sweepstakes_result_import_rows for all to authenticated
  using (is_club_staff(club_id, auth.uid()))
  with check (is_club_staff(club_id, auth.uid()));

create or replace function public.refresh_club_sweepstakes_import_totals()
returns trigger language plpgsql set search_path to public as $$
declare v_import_id uuid := coalesce(new.import_id, old.import_id);
begin
  update public.club_sweepstakes_result_imports target
  set calculated_total_points = coalesce((select sum(calculated_points) from public.club_sweepstakes_result_import_rows where import_id = v_import_id and status = 'approved'), 0),
      source_total_points = (select sum(source_points) from public.club_sweepstakes_result_import_rows where import_id = v_import_id and status = 'approved'),
      point_mismatch = exists (select 1 from public.club_sweepstakes_result_import_rows where import_id = v_import_id and status = 'approved' and point_mismatch),
      updated_at = now()
  where id = v_import_id;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create or replace function public.set_club_sweepstakes_import_row_flags()
returns trigger language plpgsql set search_path to public as $$
begin
  new.exhibitor_name := trim(new.exhibitor_name);
  new.point_mismatch := new.source_points is not null and new.source_points <> new.calculated_points;
  new.updated_at := now();
  return new;
end;
$$;

create trigger set_club_sweepstakes_import_row_flags before insert or update on public.club_sweepstakes_result_import_rows
for each row execute function public.set_club_sweepstakes_import_row_flags();
create trigger refresh_club_sweepstakes_import_totals after insert or update or delete on public.club_sweepstakes_result_import_rows
for each row execute function public.refresh_club_sweepstakes_import_totals();
