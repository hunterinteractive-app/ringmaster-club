-- Keep report-read counts distinct from counts corrected by ISRBA staff.
-- A later report reread may refresh its own counts, but never overwrites a
-- manually entered correction.
alter table public.club_sweepstakes_breed_payback_obligations
  add column count_source text not null default 'manual'
  check (count_source in ('manual', 'report'));

create index club_sweepstakes_breed_payback_obligations_expected_report_source_idx
  on public.club_sweepstakes_breed_payback_obligations (expected_report_id, count_source);
