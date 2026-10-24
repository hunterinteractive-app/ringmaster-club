-- Supporting schema only. Pricing is defined in club_base_plus_usage_pricing.
-- RingMaster Club flyer pricing is annual and is determined from the club's
-- rolling 12-month activity.  Retain the measured inputs and the quoted
-- result so a renewal can always be explained after the fact.
alter table public.clubs
  add column if not exists billing_pricing_year integer,
  add column if not exists billing_rolling_12_month_avg_membership numeric(10, 2),
  add column if not exists billing_rolling_12_month_sanction_count integer,
  add column if not exists billing_pricing_snapshot jsonb not null default '{}'::jsonb;

alter table public.clubs
  drop constraint if exists clubs_billing_pricing_year_check;

alter table public.clubs
  add constraint clubs_billing_pricing_year_check
  check (billing_pricing_year is null or billing_pricing_year between 2000 and 3000);

alter table public.clubs
  drop constraint if exists clubs_billing_rolling_12_month_avg_membership_check;

alter table public.clubs
  add constraint clubs_billing_rolling_12_month_avg_membership_check
  check (
    billing_rolling_12_month_avg_membership is null
    or billing_rolling_12_month_avg_membership >= 0
  );

alter table public.clubs
  drop constraint if exists clubs_billing_rolling_12_month_sanction_count_check;

alter table public.clubs
  add constraint clubs_billing_rolling_12_month_sanction_count_check
  check (
    billing_rolling_12_month_sanction_count is null
    or billing_rolling_12_month_sanction_count >= 0
  );

-- A club may explicitly include or exclude a sanctioned activity from the
-- rolling renewal total.  The override is per request because a request can
-- contain one or more issued sanction numbers.
create table if not exists public.club_billing_sanction_overrides (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  sanction_request_id uuid not null references public.club_sanction_requests(id) on delete cascade,
  counts_toward_renewal boolean not null,
  reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null,
  unique (club_id, sanction_request_id)
);

create index if not exists club_billing_sanction_overrides_club_idx
  on public.club_billing_sanction_overrides (club_id);

alter table public.club_billing_sanction_overrides enable row level security;

drop policy if exists "Billing managers can view sanction renewal overrides" on public.club_billing_sanction_overrides;
create policy "Billing managers can view sanction renewal overrides"
  on public.club_billing_sanction_overrides for select to authenticated
  using (public.has_club_permission(club_id, 'payments.manage'));

drop policy if exists "Billing managers can create sanction renewal overrides" on public.club_billing_sanction_overrides;
create policy "Billing managers can create sanction renewal overrides"
  on public.club_billing_sanction_overrides for insert to authenticated
  with check (
    public.has_club_permission(club_id, 'payments.manage')
    and created_by = auth.uid()
  );

drop policy if exists "Billing managers can update sanction renewal overrides" on public.club_billing_sanction_overrides;
create policy "Billing managers can update sanction renewal overrides"
  on public.club_billing_sanction_overrides for update to authenticated
  using (public.has_club_permission(club_id, 'payments.manage'))
  with check (public.has_club_permission(club_id, 'payments.manage'));

drop policy if exists "Billing managers can delete sanction renewal overrides" on public.club_billing_sanction_overrides;
create policy "Billing managers can delete sanction renewal overrides"
  on public.club_billing_sanction_overrides for delete to authenticated
  using (public.has_club_permission(club_id, 'payments.manage'));
