-- Respect the sanction-check choice captured during onboarding when a club is
-- provisioned. Membership and sanction checks use the same treasurer details.
do $$
declare
  definition text;
begin
  select pg_get_functiondef('public.approve_club_onboarding_draft(uuid)'::regprocedure)
    into definition;

  definition := replace(
    definition,
    '    coalesce((v_answers #>> ''{setup,mailed_checks}'')::boolean, false),' || chr(10) ||
    '    false,' || chr(10) ||
    '    nullif(trim(v_answers #>> ''{treasurer,name}''), ''''),',
    '    coalesce((v_answers #>> ''{setup,mailed_checks}'')::boolean, false),' || chr(10) ||
    '    coalesce((v_answers #>> ''{setup,sanction_check_payments}'')::boolean, false),' || chr(10) ||
    '    nullif(trim(v_answers #>> ''{treasurer,name}''), ''''),'
  );

  if definition = pg_get_functiondef('public.approve_club_onboarding_draft(uuid)'::regprocedure) then
    raise exception 'Could not update onboarding sanction-check mapping.';
  end if;

  execute definition;
end $$;
