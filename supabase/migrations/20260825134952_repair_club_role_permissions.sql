-- The original role setup retained the legacy permission_key values but left
-- the UI-facing foreign keys empty. Restore the canonical identifiers, then
-- resolve each stored mapping to its permission record.

update public.club_roles
set code = case name
  when 'Club Owner' then 'club_owner'
  when 'Club Administrator' then 'club_admin'
  when 'Document Manager' then 'document_manager'
  when 'Membership Secretary' then 'membership_secretary'
  when 'Sanction Coordinator' then 'sanction_coordinator'
  when 'Sweepstakes Secretary' then 'sweepstakes_secretary'
  else code
end
where name in (
  'Club Owner',
  'Club Administrator',
  'Document Manager',
  'Membership Secretary',
  'Sanction Coordinator',
  'Sweepstakes Secretary'
);

update public.club_permissions
set code = permission_key,
    label = name
where code is distinct from permission_key
   or label is distinct from name;

update public.club_role_permissions role_permission
set permission_id = permission.id
from public.club_permissions permission
where permission.permission_key = role_permission.permission_key
  and role_permission.permission_id is distinct from permission.id;

do $$
begin
  if exists (
    select 1
    from public.club_role_permissions role_permission
    left join public.club_permissions permission
      on permission.id = role_permission.permission_id
    where role_permission.permission_id is null
       or permission.id is null
  ) then
    raise exception
      'Unable to resolve every club role permission to a permission record.';
  end if;
end;
$$;
