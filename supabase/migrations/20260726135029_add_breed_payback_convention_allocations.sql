-- Planned convention awards are kept separate from incoming show-fee payments.
-- This makes each breed's available ISRBA fund visible before staff decide how
-- to divide it among Best of Breed, varieties, groups, or custom awards.

create table public.club_sweepstakes_breed_payback_convention_allocations (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  season_id uuid references public.club_sweepstakes_seasons(id) on delete set null,
  breed text not null check (length(trim(breed)) > 0),
  award_type text not null check (
    award_type in (
      'best_of_breed',
      'best_opposite_sex_breed',
      'best_of_variety',
      'best_opposite_sex_variety',
      'best_of_group',
      'best_opposite_sex_group',
      'custom'
    )
  ),
  award_detail text,
  amount_cents integer not null check (amount_cents > 0),
  notes text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index club_sweepstakes_breed_payback_convention_allocations_club_season_idx
  on public.club_sweepstakes_breed_payback_convention_allocations (club_id, season_id);

alter table public.club_sweepstakes_breed_payback_convention_allocations enable row level security;

-- New public-schema tables are not automatically available through the Data API.
-- Access is still restricted to club staff by the RLS policy below.
grant select, insert, update, delete
  on table public.club_sweepstakes_breed_payback_convention_allocations
  to authenticated;

create policy "Club staff can manage breed payback convention allocations"
  on public.club_sweepstakes_breed_payback_convention_allocations for all to authenticated
  using (is_club_staff(club_id, auth.uid()))
  with check (is_club_staff(club_id, auth.uid()));

create trigger touch_club_sweepstakes_breed_payback_convention_allocations_updated_at
before update on public.club_sweepstakes_breed_payback_convention_allocations
for each row execute function public.touch_club_sweepstakes_breed_payback_updated_at();
