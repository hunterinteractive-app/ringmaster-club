-- Square OAuth state and tokens belong to RingMaster Club only.  RMS uses a
-- separate state table and credential store even when both products share one
-- Square application/client ID.
alter table public.club_payment_accounts
  add column if not exists provider_account_id text,
  add column if not exists provider_location_id text,
  add column if not exists authorization_expires_at timestamptz,
  add column if not exists metadata jsonb not null default '{}'::jsonb;

create table public.club_payment_provider_oauth_states (
  id uuid primary key default gen_random_uuid(),
  state_hash text not null unique,
  provider text not null check (provider in ('square')),
  club_id uuid not null references public.clubs(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  expires_at timestamptz not null,
  consumed_at timestamptz,
  created_at timestamptz not null default now()
);

create index club_payment_provider_oauth_states_lookup_idx
  on public.club_payment_provider_oauth_states (provider, state_hash, expires_at)
  where consumed_at is null;

create table public.club_payment_provider_credentials (
  id uuid primary key default gen_random_uuid(),
  club_payment_account_id uuid not null references public.club_payment_accounts(id) on delete cascade,
  provider text not null check (provider in ('square')),
  access_token_encrypted text not null,
  refresh_token_encrypted text not null,
  token_expires_at timestamptz,
  granted_scopes text[] not null default '{}'::text[],
  credential_metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (club_payment_account_id, provider)
);

alter table public.club_payment_provider_oauth_states enable row level security;
alter table public.club_payment_provider_credentials enable row level security;

revoke all on public.club_payment_provider_oauth_states from anon, authenticated;
revoke all on public.club_payment_provider_credentials from anon, authenticated;
grant all on public.club_payment_provider_oauth_states to service_role;
grant all on public.club_payment_provider_credentials to service_role;

comment on table public.club_payment_provider_oauth_states is
  'Short-lived, one-time Club OAuth CSRF state hashes. Raw state values are never stored.';
