create or replace function public.get_club_operations_dashboard()
returns jsonb language plpgsql security definer set search_path = public, auth, pg_temp as $$
declare v_drafts jsonb;
begin
  if not public.is_club_operations_user() then raise exception 'RingMaster Operations access is required.'; end if;
  select coalesce(jsonb_agg(row_data order by (row_data->>'updated_at') desc), '[]'::jsonb) into v_drafts from (
    select jsonb_build_object('id',draft.id,'status',draft.status,'email',draft.invited_email,
      'club_name',coalesce(nullif(draft.answers #>> '{club,name}',''),'Untitled club'),'current_step',draft.current_step,
      'updated_at',draft.updated_at,'payment_provider',coalesce(nullif(draft.answers #>> '{setup,payment_provider}',''),'not_ready'),
      'plan_key',coalesce(draft.purchased_entitlements->>'plan_key','small_club_base'),'purchased_entitlements',draft.purchased_entitlements,
      'answers',draft.answers,'provisioned_club_id',draft.provisioned_club_id,'payment_status',payment.account_status,
      'payment_provider_connected',payment.provider) row_data
    from public.club_onboarding_drafts draft
    left join lateral (select account_status,provider from public.club_payment_accounts account where account.club_id=draft.provisioned_club_id order by account.updated_at desc limit 1) payment on true
  ) rows;
  return jsonb_build_object('drafts',v_drafts,'ready_for_review_count',(select count(*) from public.club_onboarding_drafts where status='ready_for_review'),'approved_count',(select count(*) from public.club_onboarding_drafts where status='approved'));
end; $$;
