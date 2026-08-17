create table public.personal_membership_cards (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  club_name text not null check (char_length(trim(club_name)) between 1 and 160),
  expires_on date,
  photo_paths jsonb not null default '[]'::jsonb
    check (jsonb_typeof(photo_paths) = 'array' and jsonb_array_length(photo_paths) <= 2),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index personal_membership_cards_user_idx
  on public.personal_membership_cards (user_id, expires_on);

alter table public.personal_membership_cards enable row level security;

create policy "Users manage their own personal membership cards"
  on public.personal_membership_cards for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'personal-membership-cards',
  'personal-membership-cards',
  false,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do nothing;

create policy "Users read their own membership card photos"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'personal-membership-cards'
    and (storage.foldername(name))[1] = (select auth.uid()::text)
  );

create policy "Users upload their own membership card photos"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'personal-membership-cards'
    and (storage.foldername(name))[1] = (select auth.uid()::text)
  );

create policy "Users update their own membership card photos"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'personal-membership-cards'
    and (storage.foldername(name))[1] = (select auth.uid()::text)
  )
  with check (
    bucket_id = 'personal-membership-cards'
    and (storage.foldername(name))[1] = (select auth.uid()::text)
  );

create policy "Users delete their own membership card photos"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'personal-membership-cards'
    and (storage.foldername(name))[1] = (select auth.uid()::text)
  );
