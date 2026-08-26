-- Club creation assigns the initial owner automatically.  Preserve that
-- default row while applying the onboarding contact fields.
do $$
declare definition text;
begin
  select pg_get_functiondef('public.approve_club_onboarding_draft(uuid)'::regprocedure)
  into definition;
  definition := replace(
    definition,
    '  ) returning id into v_assignment_id;',
    E'  ) on conflict (club_id, user_id) do update set\n    role_id=excluded.role_id, status=excluded.status, display_name=excluded.display_name,\n    invited_email=excluded.invited_email, accepted_at=excluded.accepted_at,\n    updated_at=now()\n  returning id into v_assignment_id;'
  );
  execute definition;
end $$;
