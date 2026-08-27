-- The invitation email owns the workspace, while the public contact may use
-- a different address.
do $$
declare
  definition text;
begin
  select pg_get_functiondef('public.approve_club_onboarding_draft(uuid)'::regprocedure)
    into definition;
  definition := replace(
    definition,
    '    v_draft.invited_email,' || chr(10) ||
    '    nullif(trim(v_answers #>> ''{club,contact_phone}''), ''''),',
    '    coalesce(nullif(trim(v_answers #>> ''{club,contact_email}''), ''''), v_draft.invited_email),' || chr(10) ||
    '    nullif(trim(v_answers #>> ''{club,contact_phone}''), ''''),'
  );
  if definition = pg_get_functiondef('public.approve_club_onboarding_draft(uuid)'::regprocedure) then
    raise exception 'Could not update onboarding contact-email mapping.';
  end if;
  execute definition;
end $$;
