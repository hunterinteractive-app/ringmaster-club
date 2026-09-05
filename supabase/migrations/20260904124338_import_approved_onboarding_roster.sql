-- A reviewed onboarding roster becomes the club's live membership roster when
-- Operations approves the draft.  The import is idempotent so it is also safe
-- to run once for clubs approved before this workflow existed.
create or replace function public.import_approved_onboarding_roster(
  p_draft_id uuid,
  p_club_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_preview_id uuid;
  v_row record;
  v_member jsonb;
  v_membership_type_id uuid;
  v_scope text;
  v_type_name text;
  v_term_type text;
  v_status text;
  v_term_end date;
  v_imported integer := 0;
  v_skipped integer := 0;
begin
  select id into v_preview_id
  from public.club_onboarding_roster_previews
  where draft_id = p_draft_id;

  if v_preview_id is null then
    return jsonb_build_object('imported', 0, 'skipped', 0, 'has_roster', false);
  end if;

  for v_row in
    select row_number, proposed_member
    from public.club_onboarding_roster_preview_rows
    where preview_id = v_preview_id
      and jsonb_array_length(errors) = 0
    order by row_number
  loop
    v_member := v_row.proposed_member;
    v_type_name := coalesce(nullif(trim(v_member->>'membership_type'), ''), 'Individual');
    v_scope := case lower(v_type_name)
      when 'family' then 'family'
      when 'youth' then 'youth'
      else 'individual'
    end;
    v_term_type := case when lower(coalesce(v_member->>'membership_term', '')) = 'lifetime'
      or upper(coalesce(v_member->>'expiration', '')) = 'LIFE'
      then 'lifetime' else 'rolling_year' end;

    -- Preserve the fact that a legacy member is lifetime without changing the
    -- club's normal paid Individual, Family, or Youth type.
    if v_term_type = 'lifetime' then
      select id into v_membership_type_id
      from public.club_membership_types
      where club_id = p_club_id and code = 'LIFE-' || case v_scope
        when 'family' then 'FAM' when 'youth' then 'YTH' else 'IND' end
      limit 1;

      if v_membership_type_id is null then
        insert into public.club_membership_types (
          club_id, name, code, description, membership_scope, billing_type,
          term_type, price, currency, requires_approval, allow_auto_renew,
          is_public, is_active, sort_order, settings, require_arba_number
        ) values (
          p_club_id,
          'Lifetime ' || case v_scope when 'family' then 'Family' when 'youth' then 'Youth' else 'Individual' end,
          'LIFE-' || case v_scope when 'family' then 'FAM' when 'youth' then 'YTH' else 'IND' end,
          'Legacy lifetime membership.', v_scope, 'one_time', 'lifetime', 0, 'usd',
          false, false, false, true,
          90 + case v_scope when 'individual' then 1 when 'family' then 2 else 3 end,
          '{}'::jsonb, false
        ) returning id into v_membership_type_id;
      end if;
    else
      select id into v_membership_type_id
      from public.club_membership_types
      where club_id = p_club_id and membership_scope = v_scope and is_active
      order by sort_order, created_at
      limit 1;
    end if;

    if v_membership_type_id is null then
      raise exception 'No active % membership type exists for club %.', v_scope, p_club_id;
    end if;

    v_status := case lower(coalesce(v_member->>'status', 'active'))
      when 'inactive' then 'inactive'
      when 'expired' then 'inactive'
      else 'active'
    end;
    v_term_end := case
      when v_term_type = 'lifetime' then null
      when coalesce(v_member->>'expiration', '') ~ '^\\d{1,2}/\\d{1,2}/\\d{4}$'
        then to_date(v_member->>'expiration', 'MM/DD/YYYY')
      else null
    end;

    -- Households commonly share an email address, so a person is only treated
    -- as previously imported when their name and street address also match.
    if exists (
      select 1 from public.club_memberships member
      where member.club_id = p_club_id
        and lower(member.first_name) = lower(coalesce(v_member->>'first_name', ''))
        and lower(member.last_name) = lower(coalesce(v_member->>'last_name', ''))
        and coalesce(lower(member.address_line1), '') = lower(coalesce(v_member->>'address_line1', ''))
    ) then
      v_skipped := v_skipped + 1;
      continue;
    end if;

    insert into public.club_memberships (
      club_id, membership_type_id, first_name, last_name, showing_name, email,
      phone, address_line1, city, state, postal_code, country, status,
      joined_at, current_term_start, current_term_end, auto_renew, source,
      notes, arba_number, linked_people
    ) values (
      p_club_id, v_membership_type_id,
      coalesce(nullif(trim(v_member->>'first_name'), ''), 'Unknown'),
      coalesce(nullif(trim(v_member->>'last_name'), ''), 'Member'),
      nullif(trim(v_member->>'showing_name'), ''),
      nullif(trim(v_member->>'email'), ''),
      nullif(trim(v_member->>'phone'), ''),
      nullif(trim(v_member->>'address_line1'), ''),
      nullif(trim(v_member->>'city'), ''),
      nullif(trim(v_member->>'state'), ''),
      nullif(trim(v_member->>'postal_code'), ''),
      coalesce(nullif(trim(v_member->>'country'), ''), 'US'), v_status,
      current_date, current_date, v_term_end, false, 'legacy',
      format('Imported from approved onboarding roster (source row %s).', v_row.row_number),
      nullif(trim(v_member->>'arba_number'), ''),
      case when jsonb_typeof(v_member->'household') = 'array'
        then jsonb_build_object('additional_people', v_member->'household')
        else '{}'::jsonb end
    );
    v_imported := v_imported + 1;
  end loop;

  return jsonb_build_object('imported', v_imported, 'skipped', v_skipped, 'has_roster', true);
end;
$$;

revoke all on function public.import_approved_onboarding_roster(uuid, uuid) from public;

create or replace function public.import_roster_when_onboarding_is_approved()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.status = 'approved'
     and old.status is distinct from 'approved'
     and new.provisioned_club_id is not null then
    perform public.import_approved_onboarding_roster(new.id, new.provisioned_club_id);
  end if;
  return new;
end;
$$;

revoke all on function public.import_roster_when_onboarding_is_approved() from public;

drop trigger if exists import_roster_when_onboarding_is_approved
  on public.club_onboarding_drafts;
create trigger import_roster_when_onboarding_is_approved
after update of status on public.club_onboarding_drafts
for each row execute function public.import_roster_when_onboarding_is_approved();
