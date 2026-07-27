-- Preserve when an individual imported result was reviewed or approved.
alter table public.club_sweepstakes_result_import_rows
  add column if not exists reviewed_at timestamptz;
