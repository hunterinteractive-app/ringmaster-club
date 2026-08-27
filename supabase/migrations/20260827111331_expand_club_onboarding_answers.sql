-- Carry the full onboarding questionnaire into the club record. Existing
-- drafts remain valid because every new answer has a safe default/fallback.
do $$
declare
  definition text;
begin
  select pg_get_functiondef('public.approve_club_onboarding_draft(uuid)'::regprocedure)
    into definition;

  definition := replace(
    definition,
    'name, short_name, slug, club_type, species_scope, description, website_url,' || chr(10) ||
    '    mailing_address_line1, mailing_city, mailing_state, mailing_postal_code,' || chr(10) ||
    '    contact_name, contact_email, contact_phone, owner_user_id,' || chr(10) ||
    '    billing_plan_key, billing_status, membership_management_addon_enabled,',
    'name, short_name, slug, club_type, species_scope, description, logo_url, website_url,' || chr(10) ||
    '    mailing_address_line1, mailing_address_line2, mailing_city, mailing_state, mailing_postal_code,' || chr(10) ||
    '    contact_name, contact_email, contact_phone, owner_user_id,' || chr(10) ||
    '    allow_public_profile, allow_public_events, allow_public_documents, allow_public_sweepstakes, settings,' || chr(10) ||
    '    billing_plan_key, billing_status, membership_management_addon_enabled,'
  );
  definition := replace(
    definition,
    'nullif(trim(v_answers #>> ''{club,description}''), ''''),' || chr(10) ||
    '    nullif(trim(v_answers #>> ''{club,website_url}''), ''''),' || chr(10) ||
    '    nullif(trim(v_answers #>> ''{club,address_line1}''), ''''),' || chr(10) ||
    '    nullif(trim(v_answers #>> ''{club,city}''), ''''),' || chr(10) ||
    '    nullif(trim(v_answers #>> ''{club,state}''), ''''),' || chr(10) ||
    '    nullif(trim(v_answers #>> ''{club,postal_code}''), ''''),' || chr(10) ||
    '    nullif(trim(v_answers #>> ''{club,contact_name}''), ''''),' || chr(10) ||
    '    v_draft.invited_email,' || chr(10) ||
    '    nullif(trim(v_answers #>> ''{club,contact_phone}''), ''''),' || chr(10) ||
    '    v_draft.submitted_by_user_id,' || chr(10) ||
    '    coalesce(v_entitlements->>''plan_key'', ''small_club_base''), ''active'',',
    'nullif(trim(v_answers #>> ''{club,description}''), ''''),' || chr(10) ||
    '    nullif(trim(v_answers #>> ''{club,logo_url}''), ''''),' || chr(10) ||
    '    nullif(trim(v_answers #>> ''{club,website_url}''), ''''),' || chr(10) ||
    '    coalesce(nullif(trim(v_answers #>> ''{club,address_line1}''), ''''), nullif(trim(v_answers #>> ''{club,address}''), '''')),' || chr(10) ||
    '    nullif(trim(v_answers #>> ''{club,address_line2}''), ''''),' || chr(10) ||
    '    nullif(trim(v_answers #>> ''{club,city}''), ''''),' || chr(10) ||
    '    nullif(trim(v_answers #>> ''{club,state}''), ''''),' || chr(10) ||
    '    nullif(trim(v_answers #>> ''{club,postal_code}''), ''''),' || chr(10) ||
    '    nullif(trim(v_answers #>> ''{club,contact_name}''), ''''),' || chr(10) ||
    '    v_draft.invited_email,' || chr(10) ||
    '    nullif(trim(v_answers #>> ''{club,contact_phone}''), ''''),' || chr(10) ||
    '    v_draft.submitted_by_user_id,' || chr(10) ||
    '    coalesce((v_answers #>> ''{club,public_profile}'')::boolean, true),' || chr(10) ||
    '    coalesce((v_answers #>> ''{club,public_events}'')::boolean, false),' || chr(10) ||
    '    coalesce((v_answers #>> ''{club,public_documents}'')::boolean, false),' || chr(10) ||
    '    coalesce((v_answers #>> ''{club,public_sweepstakes}'')::boolean, false),' || chr(10) ||
    '    jsonb_strip_nulls(jsonb_build_object(''branding'', v_answers #> ''{club,branding}'')),' || chr(10) ||
    '    coalesce(v_entitlements->>''plan_key'', ''small_club_base''), ''active'', '
  );
  definition := replace(
    definition,
    'false,' || chr(10) ||
    '    coalesce((v_answers #>> ''{setup,mailed_checks}'')::boolean, false),',
    'coalesce((v_answers #>> ''{setup,online_payments}'')::boolean, false),' || chr(10) ||
    '    coalesce((v_answers #>> ''{setup,mailed_checks}'')::boolean, false),'
  );
  definition := replace(
    definition,
    'treasurer_name, treasurer_email, treasurer_address_line1,' || chr(10) ||
    '    communication_sender_name, communication_reply_to_email',
    'treasurer_name, treasurer_email, treasurer_address_line1, treasurer_address_line2,' || chr(10) ||
    '    treasurer_city, treasurer_state, treasurer_zip,' || chr(10) ||
    '    communication_sender_name, communication_reply_to_email'
  );
  definition := replace(
    definition,
    'nullif(trim(v_answers #>> ''{treasurer,address}''), ''''),' || chr(10) ||
    '    coalesce(nullif(trim(v_answers #>> ''{club,short_name}''), ''''), v_name),' || chr(10) ||
    '    v_draft.invited_email',
    'coalesce(nullif(trim(v_answers #>> ''{treasurer,address_line1}''), ''''), nullif(trim(v_answers #>> ''{treasurer,address}''), '''')),' || chr(10) ||
    '    nullif(trim(v_answers #>> ''{treasurer,address_line2}''), ''''),' || chr(10) ||
    '    nullif(trim(v_answers #>> ''{treasurer,city}''), ''''),' || chr(10) ||
    '    nullif(trim(v_answers #>> ''{treasurer,state}''), ''''),' || chr(10) ||
    '    nullif(trim(v_answers #>> ''{treasurer,postal_code}''), ''''),' || chr(10) ||
    '    coalesce(nullif(trim(v_answers #>> ''{setup,communication_sender_name}''), ''''), nullif(trim(v_answers #>> ''{club,short_name}''), ''''), v_name),' || chr(10) ||
    '    coalesce(nullif(trim(v_answers #>> ''{setup,communication_reply_to_email}''), ''''), v_draft.invited_email)'
  );
  definition := replace(
    definition,
    '  update public.club_onboarding_drafts' || chr(10),
    '  if (v_entitlements->''addons'') ? ''membership_management'' then' || chr(10) ||
    '    update public.club_membership_types set' || chr(10) ||
    '      requires_approval=coalesce((v_answers #>> ''{setup,membership_rules,requires_approval}'')::boolean, false),' || chr(10) ||
    '      allow_auto_renew=coalesce((v_answers #>> ''{setup,membership_rules,allow_auto_renew}'')::boolean, false),' || chr(10) ||
    '      require_arba_number=coalesce((v_answers #>> ''{setup,membership_rules,require_arba_number}'')::boolean, true),' || chr(10) ||
    '      minimum_age=case when code=''IND'' then coalesce((v_answers #>> ''{setup,membership_rules,adult_minimum_age}'')::integer, 19) else minimum_age end,' || chr(10) ||
    '      maximum_age=case when code=''YTH'' then coalesce((v_answers #>> ''{setup,membership_rules,youth_maximum_age}'')::integer, 18) else maximum_age end,' || chr(10) ||
    '      settings=case when code=''FAM'' then jsonb_build_object(''included_adults'', coalesce((v_answers #>> ''{setup,membership_rules,family_included_adults}'')::integer, 2), ''included_youth'', coalesce((v_answers #>> ''{setup,membership_rules,family_included_youth}'')::integer, 3), ''additional_youth_price'', coalesce((v_answers #>> ''{setup,membership_rules,additional_youth_price}'')::numeric, 0)) else settings end' || chr(10) ||
    '    where club_id=v_club_id;' || chr(10) ||
    '  end if;' || chr(10) || chr(10) ||
    '  update public.club_onboarding_drafts' || chr(10)
  );

  if definition = pg_get_functiondef('public.approve_club_onboarding_draft(uuid)'::regprocedure) then
    raise exception 'Could not update the onboarding provisioner.';
  end if;
  execute definition;
end $$;
