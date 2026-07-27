-- Award boards are the club-facing standings. They are deliberately separate
-- from the underlying point ledger so each club can decide how awards are
-- ranked without losing its complete audit history.
create table public.club_sweepstakes_award_boards (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  season_id uuid not null references public.club_sweepstakes_seasons(id) on delete cascade,
  name text not null,
  grouping text not null check (grouping in ('overall', 'breed')),
  membership_type_ids uuid[] not null default '{}',
  eligibility_state text,
  top_n integer not null default 10 check (top_n between 1 and 100),
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index club_sweepstakes_award_boards_club_season_idx
  on public.club_sweepstakes_award_boards(club_id, season_id, is_active, sort_order);

alter table public.club_sweepstakes_award_boards enable row level security;

create policy "Club staff can manage sweepstakes award boards"
  on public.club_sweepstakes_award_boards for all to authenticated
  using (is_club_staff(club_id, auth.uid()))
  with check (is_club_staff(club_id, auth.uid()));

-- Returns entries only for a club staff member. A membership must be active
-- today (and not past its term end) to appear. Membership type selection is
-- what lets a club create Open, Youth, family, or other award groupings.
create or replace function public.get_club_sweepstakes_award_board_entries(
  p_award_board_id uuid
)
returns table (
  rank integer,
  exhibitor_name text,
  membership_type_name text,
  breed text,
  points numeric
)
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  v_board public.club_sweepstakes_award_boards%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication is required.';
  end if;

  select * into v_board
  from public.club_sweepstakes_award_boards
  where id = p_award_board_id;

  if not found then
    raise exception 'Award board not found.';
  end if;
  if not public.is_club_staff(v_board.club_id, auth.uid()) then
    raise exception 'You do not have permission to view these award standings.';
  end if;

  if v_board.grouping = 'overall' then
    return query
    with eligible_members as (
      select m.id, m.showing_name, m.first_name, m.last_name, m.membership_type_id,
             mt.name as membership_type_name
      from public.club_memberships m
      join public.club_membership_types mt on mt.id = m.membership_type_id
      where m.club_id = v_board.club_id
        and m.status = 'active'
        and (m.current_term_end is null or m.current_term_end >= current_date)
        and (cardinality(v_board.membership_type_ids) = 0 or m.membership_type_id = any(v_board.membership_type_ids))
        and (v_board.eligibility_state is null or upper(coalesce(m.state, '')) = upper(v_board.eligibility_state))
    ), ranked as (
      select
        row_number() over (order by sum(s.total_points) desc, min(s.exhibitor_name))::integer as entry_rank,
        coalesce(nullif(e.showing_name, ''), nullif(concat_ws(' ', e.first_name, e.last_name), ''), min(s.exhibitor_name)) as entry_name,
        min(e.membership_type_name) as entry_type,
        sum(s.total_points) as entry_points
      from public.club_sweepstakes_standings s
      join eligible_members e on (
        lower(trim(coalesce(e.showing_name, ''))) = lower(trim(s.exhibitor_name))
        or lower(trim(concat_ws(' ', e.first_name, e.last_name))) = lower(trim(s.exhibitor_name))
      )
      where s.club_id = v_board.club_id and s.season_id = v_board.season_id
      group by e.id, e.showing_name, e.first_name, e.last_name
    )
    select entry_rank, entry_name, entry_type, null::text, entry_points
    from ranked
    where entry_rank <= v_board.top_n
    order by entry_rank;
  else
    return query
    with eligible_members as (
      select m.id, m.showing_name, m.first_name, m.last_name, m.membership_type_id,
             mt.name as membership_type_name
      from public.club_memberships m
      join public.club_membership_types mt on mt.id = m.membership_type_id
      where m.club_id = v_board.club_id
        and m.status = 'active'
        and (m.current_term_end is null or m.current_term_end >= current_date)
        and (cardinality(v_board.membership_type_ids) = 0 or m.membership_type_id = any(v_board.membership_type_ids))
        and (v_board.eligibility_state is null or upper(coalesce(m.state, '')) = upper(v_board.eligibility_state))
    ), ranked as (
      select
        row_number() over (partition by r.breed order by sum(a.points_applied) desc, min(r.exhibitor_name))::integer as entry_rank,
        coalesce(nullif(e.showing_name, ''), nullif(concat_ws(' ', e.first_name, e.last_name), ''), min(r.exhibitor_name)) as entry_name,
        min(e.membership_type_name) as entry_type,
        r.breed as entry_breed,
        sum(a.points_applied) as entry_points
      from public.club_sweepstakes_result_applications a
      join public.club_sweepstakes_result_import_rows r on r.id = a.result_row_id
      join public.club_sweepstakes_result_imports i on i.id = a.import_id
      join eligible_members e on (
        lower(trim(coalesce(e.showing_name, ''))) = lower(trim(r.exhibitor_name))
        or lower(trim(concat_ws(' ', e.first_name, e.last_name))) = lower(trim(r.exhibitor_name))
      )
      where a.club_id = v_board.club_id and i.season_id = v_board.season_id
        and nullif(trim(coalesce(r.breed, '')), '') is not null
      group by e.id, e.showing_name, e.first_name, e.last_name, r.breed
    )
    select entry_rank, entry_name, entry_type, entry_breed, entry_points
    from ranked
    where entry_rank <= v_board.top_n
    order by entry_breed, entry_rank;
  end if;
end;
$$;

revoke execute on function public.get_club_sweepstakes_award_board_entries(uuid) from public;
grant execute on function public.get_club_sweepstakes_award_board_entries(uuid) to authenticated;

-- Set up the four ISRBA boards from its existing membership categories.
insert into public.club_sweepstakes_award_boards (
  club_id, season_id, name, grouping, membership_type_ids, eligibility_state, top_n, sort_order
)
select
  c.id,
  s.id,
  board.name,
  board.grouping,
  board.membership_type_ids,
  'IN',
  10,
  board.sort_order
from public.clubs c
join public.club_sweepstakes_seasons s on s.club_id = c.id
cross join lateral (
  select
    'Open — Top 10 Overall'::text as name,
    'overall'::text as grouping,
    array_agg(mt.id) filter (where lower(mt.name) <> 'youth') as membership_type_ids,
    10 as sort_order
  from public.club_membership_types mt
  where mt.club_id = c.id and mt.is_active
  union all
  select 'Youth — Top 10 Overall', 'overall', array_agg(mt.id) filter (where lower(mt.name) = 'youth'), 20
  from public.club_membership_types mt
  where mt.club_id = c.id and mt.is_active
  union all
  select 'Open — Top 10 by Breed', 'breed', array_agg(mt.id) filter (where lower(mt.name) <> 'youth'), 30
  from public.club_membership_types mt
  where mt.club_id = c.id and mt.is_active
  union all
  select 'Youth — Top 10 by Breed', 'breed', array_agg(mt.id) filter (where lower(mt.name) = 'youth'), 40
  from public.club_membership_types mt
  where mt.club_id = c.id and mt.is_active
) board
where c.name = 'Indiana State Rabbit Breeders Association'
  and not exists (
    select 1 from public.club_sweepstakes_award_boards existing
    where existing.club_id = c.id and existing.season_id = s.id and existing.name = board.name
  );
