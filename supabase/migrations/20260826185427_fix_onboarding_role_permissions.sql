-- Default club creation also seeds permission mappings.  The onboarding
-- provisioner must enrich rather than duplicate those mappings.
do $$
declare definition text;
begin
  select pg_get_functiondef('public.approve_club_onboarding_draft(uuid)'::regprocedure)
  into definition;
  definition := replace(
    definition,
    '  where role.club_id=v_club_id and role.code in (''club_owner'',''club_admin'');',
    '  where role.club_id=v_club_id and role.code in (''club_owner'',''club_admin'')\n  on conflict (role_id, permission_key) do nothing;'
  );
  definition := replace(
    definition,
    '  where permission.code in (''payments.view'',''payments.manage'',''payments.refund'');',
    '  where permission.code in (''payments.view'',''payments.manage'',''payments.refund'')\n  on conflict (role_id, permission_key) do nothing;'
  );
  execute replace(definition, E'\\n', E'\n');
end $$;
