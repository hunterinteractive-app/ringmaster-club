create or replace function public.auto_approve_membership_application()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_type public.club_membership_types%rowtype;
  v_membership_id uuid;
  v_term_start date := current_date;
  v_term_end date;
begin
  select * into v_type
  from public.club_membership_types
  where id = new.membership_type_id
    and club_id = new.club_id;

  if not found or coalesce(v_type.requires_approval, true) then
    return new;
  end if;

  v_term_end := case v_type.term_type
    when 'calendar_year' then make_date(extract(year from v_term_start)::integer, 12, 31)
    when 'rolling_year' then (v_term_start + interval '1 year' - interval '1 day')::date
    when 'monthly' then (v_term_start + interval '1 month' - interval '1 day')::date
    when 'multi_year' then (v_term_start + make_interval(months => greatest(coalesce(v_type.term_months, 12), 1)) - interval '1 day')::date
    when 'lifetime' then null
    else null
  end;

  select id into v_membership_id
  from public.club_memberships
  where club_id = new.club_id
    and ((new.user_id is not null and user_id = new.user_id)
      or (new.user_id is null and lower(trim(email)) = lower(trim(new.email))))
  order by created_at desc
  limit 1;

  if v_membership_id is null then
    insert into public.club_memberships (
      club_id, user_id, membership_type_id, first_name, last_name,
      showing_name, email, phone, address_line1, address_line2, city, state,
      postal_code, country, date_of_birth, status, joined_at,
      current_term_start, current_term_end, auto_renew, source
    ) values (
      new.club_id, new.user_id, new.membership_type_id, new.first_name, new.last_name,
      new.showing_name, new.email, new.phone, new.address_line1, new.address_line2,
      new.city, new.state, new.postal_code, coalesce(new.country, 'US'), new.date_of_birth,
      'active', current_date, v_term_start, v_term_end,
      coalesce((new.application_details -> 'auto_renew' ->> 'selected')::boolean, false),
      'application'
    ) returning id into v_membership_id;
  else
    update public.club_memberships
    set membership_type_id = new.membership_type_id, status = 'active',
        current_term_start = v_term_start, current_term_end = v_term_end,
        updated_at = now()
    where id = v_membership_id;
  end if;

  update public.club_membership_applications
  set status = 'approved', reviewed_at = now(), updated_at = now()
  where id = new.id;

  return new;
end;
$$;

revoke all on function public.auto_approve_membership_application() from public;

drop trigger if exists auto_approve_membership_application on public.club_membership_applications;
create trigger auto_approve_membership_application
after insert on public.club_membership_applications
for each row execute function public.auto_approve_membership_application();
