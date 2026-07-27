create table public.club_sweepstakes_result_awards (
  id uuid primary key default gen_random_uuid(),
  result_row_id uuid not null references public.club_sweepstakes_result_import_rows(id) on delete cascade,
  club_id uuid not null references public.clubs(id) on delete cascade,
  rule_key text not null,
  rule_label text not null,
  award_label text not null,
  calculation_type text not null,
  points_per_award numeric not null,
  shown_count numeric,
  calculated_points numeric not null,
  placement text,
  breed text,
  created_at timestamptz not null default now()
);

create index club_sweepstakes_result_awards_row_idx
  on public.club_sweepstakes_result_awards (result_row_id, created_at);

alter table public.club_sweepstakes_result_awards enable row level security;

create policy "Club staff can manage sweepstakes result award breakdowns"
  on public.club_sweepstakes_result_awards for all to authenticated
  using (is_club_staff(club_id, auth.uid()))
  with check (is_club_staff(club_id, auth.uid()));
