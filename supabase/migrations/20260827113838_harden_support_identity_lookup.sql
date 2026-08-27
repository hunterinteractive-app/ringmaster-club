-- Resolve platform support identity from auth.users rather than the JWT email
-- claim.  Some valid browser sessions do not carry an email claim, while the
-- authenticated user id remains authoritative.
create or replace function public.is_ringmaster_support_user(
  p_user_id uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path = public, auth, pg_temp
as $$
  select p_user_id is not null
    and p_user_id = auth.uid()
    and exists (
      select 1
      from public.ringmaster_support_users support
      join auth.users account on account.id = p_user_id
      where support.email = lower(account.email)
        and support.is_active
    );
$$;

revoke all on function public.is_ringmaster_support_user(uuid) from public;
grant execute on function public.is_ringmaster_support_user(uuid) to authenticated;
