alter table public.club_memberships
  drop constraint if exists club_memberships_status_check;

alter table public.club_memberships
  add constraint club_memberships_status_check
  check (
    status = any (
      array[
        'pending'::text,
        'active'::text,
        'expiring'::text,
        'expired'::text,
        'inactive'::text,
        'suspended'::text,
        'denied'::text,
        'cancelled'::text
      ]
    )
  );
