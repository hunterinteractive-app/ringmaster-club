-- clubs insert their standard roles via a trigger.  The onboarding provisioner
-- enriches those same roles, so make that insert idempotent rather than failing.
do $$
declare definition text;
begin
  select pg_get_functiondef('public.approve_club_onboarding_draft(uuid)'::regprocedure)
  into definition;
  definition := replace(
    definition,
    '    (v_club_id, ''sanction_coordinator'', ''Sanction & Sweepstakes Secretary'', ''sanctions_sweepstakes_secretary'', ''Manages sanction and sweepstakes work.'', 600, true, true);',
    E'    (v_club_id, ''sanction_coordinator'', ''Sanction & Sweepstakes Secretary'', ''sanctions_sweepstakes_secretary'', ''Manages sanction and sweepstakes work.'', 600, true, true)\n  on conflict (club_id, role_key) do update set\n    name=excluded.name, code=excluded.code, description=excluded.description,\n    role_rank=excluded.role_rank, is_system=excluded.is_system, is_active=excluded.is_active;'
  );
  if definition = pg_get_functiondef('public.approve_club_onboarding_draft(uuid)'::regprocedure) then
    raise exception 'Could not update the onboarding role provisioner.';
  end if;
  execute definition;
end $$;
