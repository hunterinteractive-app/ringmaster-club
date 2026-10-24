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

-- Club Core follows the established Easy2Show annual member bands.  The
-- matching Stripe Price is resolved by its stable lookup key, never by a
-- test- or live-mode price ID stored in the client.
create or replace function public.club_pricing_from_prior_year_usage(
  p_average_membership numeric,
  p_sanctions_issued integer default 0
)
returns jsonb
language sql
immutable
set search_path = public, pg_temp
as $$
  with usage as (
    select greatest(0, coalesce(p_average_membership, 0)) as avg_membership,
           greatest(0, coalesce(p_sanctions_issued, 0)) as sanctions
  ), core as (
    select avg_membership,
    case
      when avg_membership <= 50 then 'club_core_000_050'
      when avg_membership <= 100 then 'club_core_051_100'
      when avg_membership <= 200 then 'club_core_101_200'
      when avg_membership <= 300 then 'club_core_201_300'
      when avg_membership <= 400 then 'club_core_301_400'
      when avg_membership <= 500 then 'club_core_401_500'
      when avg_membership <= 750 then 'club_core_501_750'
      when avg_membership <= 1000 then 'club_core_751_1000'
      when avg_membership <= 1500 then 'club_core_1001_1500'
      when avg_membership <= 9999 then 'club_core_1501_9999'
      else 'club_core_10000_plus'
    end as key,
    case
      when avg_membership <= 50 then 25
      when avg_membership <= 100 then 50
      when avg_membership <= 200 then 75
      when avg_membership <= 300 then 100
      when avg_membership <= 400 then 125
      when avg_membership <= 500 then 150
      when avg_membership <= 750 then 200
      when avg_membership <= 1000 then 250
      when avg_membership <= 1500 then 350
      when avg_membership <= 9999 then 450
      else null
    end as checkout_price,
    case
      when avg_membership <= 50 then 'club_core_000_050_annual'
      when avg_membership <= 100 then 'club_core_051_100_annual'
      when avg_membership <= 200 then 'club_core_101_200_annual'
      when avg_membership <= 300 then 'club_core_201_300_annual'
      when avg_membership <= 400 then 'club_core_301_400_annual'
      when avg_membership <= 500 then 'club_core_401_500_annual'
      when avg_membership <= 750 then 'club_core_501_750_annual'
      when avg_membership <= 1000 then 'club_core_751_1000_annual'
      when avg_membership <= 1500 then 'club_core_1001_1500_annual'
      when avg_membership <= 9999 then 'club_core_1501_9999_annual'
      else null
    end as stripe_lookup_key
    from usage
  ), sanctions as (
    select usage.sanctions,
    case
      when usage.sanctions <= 2000 then
        greatest(25, ceil(usage.sanctions / 100) * 25)
      else null
    end as checkout_price,
    case
      when usage.sanctions <= 100 then 'sanctions_up_to_100'
      when usage.sanctions <= 500 then 'sanctions_101_500'
      when usage.sanctions <= 1000 then 'sanctions_501_1000'
      when usage.sanctions <= 1500 then 'sanctions_1001_1500'
      when usage.sanctions <= 2000 then 'sanctions_1501_2000'
      else 'sanctions_2001_plus'
    end as key
    from usage
  )
  select jsonb_build_object(
    'club_core', jsonb_build_object(
      'key', core.key,
      'stripe_lookup_key', core.stripe_lookup_key,
      'checkout_annual_price', core.checkout_price,
      'custom_quote_required', core.checkout_price is null,
      'custom_quote_available', core.checkout_price is null
    ),
    'sanctions_sweepstakes', jsonb_build_object(
      'key', sanctions.key,
      'checkout_annual_price', sanctions.checkout_price,
      'custom_quote_required', sanctions.sanctions > 2000,
      'checkout_increment', 25,
      'sanctions_per_increment', 100
    )
  )
  from core cross join sanctions;
$$;

comment on function public.club_pricing_from_prior_year_usage(numeric, integer) is
  'Returns Easy2Show-aligned annual Club Core and optional Sanctions & Sweepstakes pricing from rolling 12-month activity.';

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

create policy "Billing managers can view sanction renewal overrides"
  on public.club_billing_sanction_overrides for select to authenticated
  using (public.has_club_permission(club_id, 'payments.manage'));

create policy "Billing managers can create sanction renewal overrides"
  on public.club_billing_sanction_overrides for insert to authenticated
  with check (
    public.has_club_permission(club_id, 'payments.manage')
    and created_by = auth.uid()
  );

create policy "Billing managers can update sanction renewal overrides"
  on public.club_billing_sanction_overrides for update to authenticated
  using (public.has_club_permission(club_id, 'payments.manage'))
  with check (public.has_club_permission(club_id, 'payments.manage'));

create policy "Billing managers can delete sanction renewal overrides"
  on public.club_billing_sanction_overrides for delete to authenticated
  using (public.has_club_permission(club_id, 'payments.manage'));

-- This is deliberately rolling, not calendar-year based: renewals can occur
-- in any month.  Membership is sampled on each of the last 12 monthly
-- anniversaries using its effective term dates, rather than its status today.
create or replace function public.get_club_renewal_preview(p_club_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_average_membership numeric(10, 2);
  v_sanctions_issued integer;
  v_pricing jsonb;
  v_window_start timestamptz := now() - interval '12 months';
begin
  if auth.uid() is null
     or not public.has_club_permission(p_club_id, 'payments.manage') then
    raise exception 'You do not have permission to review this club renewal.';
  end if;

  with sample_dates as (
    select (current_date - (interval '1 month' * month_offset))::date as sample_date
    from generate_series(0, 11) as month_offset
  ), monthly_counts as (
    select sample_date,
           count(membership.id)::integer as active_members
    from sample_dates
    left join public.club_memberships membership
      on membership.club_id = p_club_id
     and coalesce(membership.current_term_start, membership.joined_at::date)
           <= sample_date
     and coalesce(membership.current_term_end, 'infinity'::date) >= sample_date
    group by sample_date
  )
  select round(avg(active_members)::numeric, 2)
  into v_average_membership
  from monthly_counts;

  with issued_requests as (
    select request.id,
           count(number_line)::integer as issued_number_count,
           override.counts_toward_renewal
    from public.club_sanction_requests request
    left join public.club_billing_sanction_overrides override
      on override.club_id = request.club_id
     and override.sanction_request_id = request.id
    cross join lateral regexp_split_to_table(
      coalesce(request.sanction_number, ''), E'\\n+'
    ) as number_line
    where request.club_id = p_club_id
      and request.status = 'approved'
      and request.reviewed_at >= v_window_start
      and btrim(number_line) <> ''
      and (position(':' in number_line) = 0
           or nullif(btrim(split_part(number_line, ':', 2)), '') is not null)
    group by request.id, override.counts_toward_renewal
  )
  select coalesce(sum(
    case when counts_toward_renewal is false then 0 else issued_number_count end
  ), 0)::integer
  into v_sanctions_issued
  from issued_requests;

  v_pricing := public.club_pricing_from_prior_year_usage(
    coalesce(v_average_membership, 0),
    v_sanctions_issued
  );

  return jsonb_build_object(
    'lookback_start', v_window_start,
    'lookback_end', now(),
    'average_active_members', coalesce(v_average_membership, 0),
    'sanctions_issued', v_sanctions_issued,
    'pricing', v_pricing
  );
end;
$$;

-- This recipient list is consumed by the renewal notification job and avoids
-- sending billing messages to every officer.  Titles are intentionally read
-- from staff assignments, where clubs manage them.
create or replace function public.get_club_renewal_recipients(p_club_id uuid)
returns table(recipient_name text, recipient_email text, recipient_user_id uuid)
language plpgsql
stable
security definer
set search_path = public, auth, pg_temp
as $$
begin
  if auth.uid() is null
     or not public.has_club_permission(p_club_id, 'payments.manage') then
    raise exception 'You do not have permission to view renewal recipients.';
  end if;

  return query
  with recipients as (
    select coalesce(club.contact_name, club.name) as name,
           lower(nullif(trim(club.contact_email), '')) as email,
           club.owner_user_id as user_id
    from public.clubs club
    where club.id = p_club_id
    union all
    select coalesce(assignment.display_name, assignment.title_override, 'Club officer') as name,
           lower(nullif(trim(coalesce(assignment.invited_email, member.email)), '')) as email,
           assignment.user_id as user_id
    from public.club_staff_assignments assignment
    left join auth.users member on member.id = assignment.user_id
    where assignment.club_id = p_club_id
      and assignment.status = 'active'
      and lower(coalesce(assignment.title_override, '')) in ('president', 'secretary')
  ), deduplicated as (
    select distinct on (email) name, email, user_id
    from recipients
    where email is not null
    order by email, name
  )
  select name, email, user_id from deduplicated;
end;
$$;

revoke all on function public.get_club_renewal_preview(uuid) from public;
revoke all on function public.get_club_renewal_recipients(uuid) from public;
grant execute on function public.get_club_renewal_preview(uuid) to authenticated;
grant execute on function public.get_club_renewal_recipients(uuid) to authenticated;
