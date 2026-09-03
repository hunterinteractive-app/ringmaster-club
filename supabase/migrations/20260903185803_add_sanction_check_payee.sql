alter table public.clubs
  add column if not exists sanction_check_payee text;

-- Extend the onboarding provisioning trigger with the check-payee and
-- treasurer phone details captured for sanction requests.
create or replace function public.provision_onboarding_sanction_types()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_type jsonb;
  v_name text;
  v_description text;
  v_scope text;
  v_price numeric;
  v_currency text;
  v_open_count integer;
  v_youth_count integer;
  v_sort_order integer := 10;
begin
  if new.status <> 'approved'
      or new.provisioned_club_id is null
      or not (coalesce(new.purchased_entitlements->'addons', '[]'::jsonb)
        ? 'sanction_requests') then
    return new;
  end if;

  update public.clubs
  set
    sanction_check_payee = nullif(trim(new.answers #>> '{setup,sanction_check_payee}'), ''),
    treasurer_phone = nullif(trim(new.answers #>> '{treasurer,phone}'), ''),
    updated_at = now()
  where id = new.provisioned_club_id;

  for v_type in
    select value
    from jsonb_array_elements(
      coalesce(new.answers #> '{setup,sanction_types}', '[]'::jsonb)
    )
  loop
    v_name := nullif(trim(v_type->>'name'), '');
    if v_name is null then
      continue;
    end if;

    v_description := nullif(trim(v_type->>'description'), '');
    v_scope := coalesce(nullif(trim(v_type->>'sanction_scope'), ''), 'other');
    if v_scope not in ('open', 'youth', 'open_youth_bundle', 'other') then
      raise exception 'Unsupported onboarding sanction scope: %', v_scope;
    end if;

    v_price := case
      when coalesce(v_type->>'base_price', '') ~ '^[0-9]+(\.[0-9]+)?$'
        then (v_type->>'base_price')::numeric
      else 0
    end;
    v_currency := upper(coalesce(nullif(trim(v_type->>'currency'), ''), 'USD'));
    v_open_count := greatest(0, coalesce(nullif(v_type->>'included_open_count', '')::integer, 0));
    v_youth_count := greatest(0, coalesce(nullif(v_type->>'included_youth_count', '')::integer, 0));

    if v_scope = 'open' and v_open_count = 0 then v_open_count := 1; end if;
    if v_scope = 'youth' and v_youth_count = 0 then v_youth_count := 1; end if;
    if v_scope = 'open_youth_bundle' then
      if v_open_count = 0 then v_open_count := 1; end if;
      if v_youth_count = 0 then v_youth_count := 1; end if;
    end if;

    insert into public.club_sanction_types (
      club_id, name, description, sanction_scope, base_price, currency,
      is_bundle, included_open_count, included_youth_count, is_active, sort_order
    )
    select
      new.provisioned_club_id, v_name, v_description, v_scope, v_price, v_currency,
      v_scope = 'open_youth_bundle', v_open_count, v_youth_count, true, v_sort_order
    where not exists (
      select 1
      from public.club_sanction_types existing
      where existing.club_id = new.provisioned_club_id
        and lower(existing.name) = lower(v_name)
    );

    v_sort_order := v_sort_order + 10;
  end loop;

  return new;
end;
$$;

update public.clubs
set
  sanction_check_payee = 'ASCRBA',
  treasurer_phone = '(814) 521-9320',
  updated_at = now()
where id = 'd50a579c-922c-4888-b0f8-e6b7dab5fec5';
