-- ISRBA breed payback fund. Each sanctioned show's breed count creates a
-- collection obligation: 10 cents collected, 8 cents to the breed fund, and
-- 2 cents retained for ISRBA's separate allocation.

create table public.club_sweepstakes_breed_payback_settings (
  club_id uuid primary key references public.clubs(id) on delete cascade,
  is_enabled boolean not null default false,
  collection_cents_per_rabbit integer not null default 10 check (collection_cents_per_rabbit > 0),
  breed_fund_cents_per_rabbit integer not null default 8 check (breed_fund_cents_per_rabbit >= 0),
  isrba_allocation_cents_per_rabbit integer not null default 2 check (isrba_allocation_cents_per_rabbit >= 0),
  updated_at timestamptz not null default now(),
  check (breed_fund_cents_per_rabbit + isrba_allocation_cents_per_rabbit = collection_cents_per_rabbit)
);

create table public.club_sweepstakes_breed_payback_obligations (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  season_id uuid references public.club_sweepstakes_seasons(id) on delete set null,
  expected_report_id uuid not null references public.club_sweepstakes_expected_reports(id) on delete cascade,
  breed text not null check (length(trim(breed)) > 0),
  rabbits_shown integer not null check (rabbits_shown >= 0),
  collection_cents_per_rabbit integer not null check (collection_cents_per_rabbit > 0),
  breed_fund_cents_per_rabbit integer not null check (breed_fund_cents_per_rabbit >= 0),
  isrba_allocation_cents_per_rabbit integer not null check (isrba_allocation_cents_per_rabbit >= 0),
  expected_collection_cents integer not null check (expected_collection_cents >= 0),
  expected_breed_fund_cents integer not null check (expected_breed_fund_cents >= 0),
  expected_isrba_allocation_cents integer not null check (expected_isrba_allocation_cents >= 0),
  notes text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (expected_report_id, breed),
  check (breed_fund_cents_per_rabbit + isrba_allocation_cents_per_rabbit = collection_cents_per_rabbit),
  check (expected_collection_cents = rabbits_shown * collection_cents_per_rabbit),
  check (expected_breed_fund_cents = rabbits_shown * breed_fund_cents_per_rabbit),
  check (expected_isrba_allocation_cents = rabbits_shown * isrba_allocation_cents_per_rabbit)
);

create table public.club_sweepstakes_breed_payback_payments (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  received_date date not null default current_date,
  amount_cents integer not null check (amount_cents > 0),
  payment_method text not null check (payment_method in ('cash', 'check', 'online', 'other')),
  payer_name text,
  payer_email text,
  reference text,
  notes text,
  received_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.club_sweepstakes_breed_payback_payment_allocations (
  id uuid primary key default gen_random_uuid(),
  payment_id uuid not null references public.club_sweepstakes_breed_payback_payments(id) on delete cascade,
  obligation_id uuid not null references public.club_sweepstakes_breed_payback_obligations(id) on delete cascade,
  amount_cents integer not null check (amount_cents > 0),
  created_at timestamptz not null default now(),
  unique (payment_id, obligation_id)
);

create index club_sweepstakes_breed_payback_obligations_club_season_idx
  on public.club_sweepstakes_breed_payback_obligations (club_id, season_id);
create index club_sweepstakes_breed_payback_payment_allocations_obligation_idx
  on public.club_sweepstakes_breed_payback_payment_allocations (obligation_id);

alter table public.club_sweepstakes_breed_payback_settings enable row level security;
alter table public.club_sweepstakes_breed_payback_obligations enable row level security;
alter table public.club_sweepstakes_breed_payback_payments enable row level security;
alter table public.club_sweepstakes_breed_payback_payment_allocations enable row level security;

create policy "Club staff can manage breed payback settings"
  on public.club_sweepstakes_breed_payback_settings for all to authenticated
  using (is_club_staff(club_id, auth.uid()))
  with check (is_club_staff(club_id, auth.uid()));

create policy "Club staff can manage breed payback obligations"
  on public.club_sweepstakes_breed_payback_obligations for all to authenticated
  using (is_club_staff(club_id, auth.uid()))
  with check (is_club_staff(club_id, auth.uid()));

create policy "Club staff can manage breed payback payments"
  on public.club_sweepstakes_breed_payback_payments for all to authenticated
  using (is_club_staff(club_id, auth.uid()))
  with check (is_club_staff(club_id, auth.uid()));

create policy "Club staff can manage breed payback payment allocations"
  on public.club_sweepstakes_breed_payback_payment_allocations for all to authenticated
  using (
    exists (
      select 1
      from public.club_sweepstakes_breed_payback_payments payment
      where payment.id = payment_id
        and is_club_staff(payment.club_id, auth.uid())
    )
  )
  with check (
    exists (
      select 1
      from public.club_sweepstakes_breed_payback_payments payment
      join public.club_sweepstakes_breed_payback_obligations obligation
        on obligation.id = obligation_id
      where payment.id = payment_id
        and payment.club_id = obligation.club_id
        and is_club_staff(payment.club_id, auth.uid())
    )
  );

create or replace function public.touch_club_sweepstakes_breed_payback_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger touch_club_sweepstakes_breed_payback_settings_updated_at
before update on public.club_sweepstakes_breed_payback_settings
for each row execute function public.touch_club_sweepstakes_breed_payback_updated_at();
create trigger touch_club_sweepstakes_breed_payback_obligations_updated_at
before update on public.club_sweepstakes_breed_payback_obligations
for each row execute function public.touch_club_sweepstakes_breed_payback_updated_at();
create trigger touch_club_sweepstakes_breed_payback_payments_updated_at
before update on public.club_sweepstakes_breed_payback_payments
for each row execute function public.touch_club_sweepstakes_breed_payback_updated_at();

-- Enable only for ISRBA. The tables remain reusable if another state club
-- adopts the same collection model later.
insert into public.club_sweepstakes_breed_payback_settings (club_id, is_enabled)
select id, true
from public.clubs
where lower(name) in ('indiana state rabbit breeders association', 'isrba')
on conflict (club_id) do update set is_enabled = true, updated_at = now();
