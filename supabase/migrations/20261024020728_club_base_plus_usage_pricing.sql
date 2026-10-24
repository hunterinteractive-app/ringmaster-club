-- Flyer pricing: yearly licensed quantities, counted on the server.
alter table public.clubs add column if not exists billing_active_member_count integer;
alter table public.clubs drop constraint if exists clubs_billing_plan_key_check;
alter table public.clubs add constraint clubs_billing_plan_key_check check
  (billing_plan_key in ('none','small_club_base','standard_club_base','standard_club_complete','membership_plus'));
alter table public.club_plan_subscriptions drop constraint if exists club_plan_subscriptions_plan_key_check;
alter table public.club_plan_subscriptions add constraint club_plan_subscriptions_plan_key_check check
  (plan_key in ('small_club_base','standard_club_base','standard_club_complete','membership_plus'));

-- A family record includes its primary member plus its covered people.
-- Support both the current application/roster format and older imported rosters.
create or replace function public.club_membership_person_count(p_linked_people jsonb)
returns integer language sql immutable security invoker set search_path = '' as $$
  select 1 + (
    select count(distinct btrim(value))::integer
    from jsonb_array_elements_text(case when jsonb_typeof(p_linked_people->'additional_exhibitor_ids')='array'
      then p_linked_people->'additional_exhibitor_ids' else '[]'::jsonb end)
    where nullif(btrim(value),'') is not null
      and value is distinct from p_linked_people->>'primary_exhibitor_id'
  ) + (
    select count(distinct lower(concat_ws('|',btrim(person->>'first_name'),btrim(person->>'last_name'))))::integer
    from jsonb_array_elements(case
      when jsonb_typeof(p_linked_people->'additional_manual_people')='array' then p_linked_people->'additional_manual_people'
      when jsonb_typeof(p_linked_people->'additional_people')='array' then p_linked_people->'additional_people'
      else '[]'::jsonb end) person
    where nullif(btrim(concat_ws('',person->>'first_name',person->>'last_name')),'') is not null
  );
$$;

-- Retain the existing RPC contract for older clients. The membership input now
-- represents the current covered-person count, not a historical tier/average.
create or replace function public.club_pricing_from_prior_year_usage(
  p_average_membership numeric, p_sanctions_issued integer default 0
) returns jsonb language sql immutable security invoker set search_path = '' as $$
  with usage as (select ceil(greatest(0,coalesce(p_average_membership,0)))::integer members,
    greatest(0,coalesce(p_sanctions_issued,0)) sanctions)
  select jsonb_build_object(
    'pricing_version','base_plus_usage_v1', 'currency','usd',
    'club_core',jsonb_build_object('key','membership_plus','base_annual_price',100,
      'unit_annual_price',1,'quantity',members,'checkout_annual_price',100+members,
      'base_lookup_key','rmc_membership_base_annual_v1','unit_lookup_key','rmc_member_annual_v1',
      'custom_quote_required',false,'custom_quote_available',false),
    'sanctions_sweepstakes',jsonb_build_object('key','sanctions_sweepstakes',
      'base_annual_price',50,'unit_annual_price',0.50,'quantity',sanctions,
      'checkout_annual_price',50+sanctions*0.50,
      'base_lookup_key','rmc_sanctions_base_annual_v1','unit_lookup_key','rmc_sanction_annual_v1',
      'custom_quote_required',false)) from usage;
$$;

create or replace function public.get_club_renewal_preview(p_club_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_members integer;
  v_sanctions integer;
  v_enabled boolean;
  v_pricing jsonb;
  v_start timestamptz := now()-interval '12 months';
begin
  if coalesce(auth.jwt()->>'role','') <> 'service_role' and
    (auth.uid() is null or not public.has_club_permission(p_club_id,'payments.manage')) then
    raise exception 'You do not have permission to review this club renewal.';
  end if;
  select (sanction_requests_addon_enabled or sweepstakes_addon_enabled) into v_enabled
    from public.clubs where id=p_club_id;
  if not found then raise exception 'Club not found.'; end if;
  select coalesce(sum(public.club_membership_person_count(linked_people)),0)::integer
    into v_members from public.club_memberships
    where club_id=p_club_id and status in ('active','expiring')
      and coalesce(current_term_start,joined_at::date,current_date)<=current_date
      and coalesce(current_term_end,'infinity'::date)>=current_date;
  select count(*)::integer into v_sanctions
    from public.club_sanction_requests request
    left join public.club_billing_sanction_overrides override
      on override.club_id=request.club_id and override.sanction_request_id=request.id
    cross join lateral regexp_split_to_table(coalesce(request.sanction_number,''),E'\n+') number_line
    where request.club_id=p_club_id and request.status='approved'
      and request.reviewed_at>=v_start and request.reviewed_at<=now()
      and override.counts_toward_renewal is distinct from false
      and btrim(number_line)<>''
      and (position(':' in number_line)=0 or nullif(btrim(split_part(number_line,':',2)),'') is not null);
  v_pricing:=public.club_pricing_from_prior_year_usage(v_members,v_sanctions);
  return jsonb_build_object('club_id',p_club_id,'active_member_count',v_members,
    'average_active_members',v_members,'membership_count_basis','covered_people',
    'window_start',v_start,'window_end',now(),'sanctions_issued',v_sanctions,
    'sanctions_sweepstakes_enabled',v_enabled,'pricing',v_pricing,
    'total_annual_price',100+v_members+case when v_enabled then 50+v_sanctions*0.50 else 0 end);
end;
$$;
revoke all on function public.club_membership_person_count(jsonb) from public,anon;
revoke all on function public.club_pricing_from_prior_year_usage(numeric,integer) from public,anon;
revoke all on function public.get_club_renewal_preview(uuid) from public,anon;
grant execute on function public.club_membership_person_count(jsonb) to authenticated,service_role;
grant execute on function public.club_pricing_from_prior_year_usage(numeric,integer) to authenticated,service_role;
grant execute on function public.get_club_renewal_preview(uuid) to authenticated,service_role;
