-- A club may choose whether an active Youth member's unassigned Open-show
-- results are credited to Youth Sweepstakes or remain in Open Sweepstakes.
alter table public.club_sweepstakes_settings
  add column if not exists youth_open_show_points_enabled boolean not null default true;
