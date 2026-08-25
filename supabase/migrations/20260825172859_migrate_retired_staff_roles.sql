-- Keep existing staff and pending invitations usable after consolidating the
-- old office-specific roles.  The office title remains visible on the person.

with replacements as (
  select old_role.id as old_role_id,
         replacement.id as replacement_role_id,
         case old_role.code
           when 'membership_secretary' then 'Secretary'
           when 'document_manager' then 'Document Manager'
           when 'sweepstakes_secretary' then null
         end as default_title
  from public.club_roles old_role
  join public.club_roles replacement
    on replacement.club_id = old_role.club_id
   and replacement.code = case old_role.code
     when 'membership_secretary' then 'club_admin'
     when 'document_manager' then 'club_admin'
     when 'sweepstakes_secretary' then 'sanctions_sweepstakes_secretary'
   end
  where old_role.code in (
    'membership_secretary',
    'document_manager',
    'sweepstakes_secretary'
  )
)
update public.club_staff_assignments assignment
set role_id = replacements.replacement_role_id,
    title_override = coalesce(assignment.title_override, replacements.default_title),
    updated_at = now()
from replacements
where assignment.role_id = replacements.old_role_id;

with replacements as (
  select old_role.id as old_role_id,
         replacement.id as replacement_role_id,
         case old_role.code
           when 'membership_secretary' then 'Secretary'
           when 'document_manager' then 'Document Manager'
           when 'sweepstakes_secretary' then null
         end as default_title
  from public.club_roles old_role
  join public.club_roles replacement
    on replacement.club_id = old_role.club_id
   and replacement.code = case old_role.code
     when 'membership_secretary' then 'club_admin'
     when 'document_manager' then 'club_admin'
     when 'sweepstakes_secretary' then 'sanctions_sweepstakes_secretary'
   end
  where old_role.code in (
    'membership_secretary',
    'document_manager',
    'sweepstakes_secretary'
  )
)
update public.club_staff_invitations invitation
set role_id = replacements.replacement_role_id,
    title_override = coalesce(invitation.title_override, replacements.default_title),
    updated_at = now()
from replacements
where invitation.role_id = replacements.old_role_id
  and invitation.status = 'pending';
