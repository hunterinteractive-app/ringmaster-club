create or replace function public.club_sweepstakes_name_contains_all_words(
  p_member_name text,
  p_report_name text
)
returns boolean
language sql
immutable
set search_path = pg_catalog
as $$
  with normalized as (
    select
      trim(regexp_replace(lower(coalesce(p_member_name, '')), '[^a-z0-9]+', ' ', 'g')) as member_name,
      trim(regexp_replace(lower(coalesce(p_report_name, '')), '[^a-z0-9]+', ' ', 'g')) as report_name
  ), member_words as (
    select word
    from normalized,
      regexp_split_to_table(member_name, '\s+') as word
    where word <> ''
  )
  select
    (select count(*) from member_words) >= 2
    and not exists (
      select 1
      from member_words
      where position(' ' || word || ' ' in ' ' || (select report_name from normalized) || ' ') = 0
    )
  from normalized;
$$;
