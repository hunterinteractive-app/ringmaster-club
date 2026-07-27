create or replace function public.club_sweepstakes_names_match(
  p_member_name text,
  p_report_name text
)
returns boolean
language sql
immutable
set search_path = pg_catalog
as $$
  with names as (
    select
      trim(regexp_replace(lower(coalesce(p_member_name, '')), '[^a-z0-9]+', ' ', 'g')) as member_name,
      trim(regexp_replace(lower(coalesce(p_report_name, '')), '[^a-z0-9]+', ' ', 'g')) as report_name
  )
  select
    member_name <> ''
    and report_name <> ''
    and (
      member_name = report_name
      or concat_ws(
        ' ',
        regexp_replace(report_name, '^\S+\s*', ''),
        split_part(report_name, ' ', 1)
      ) = member_name
    )
  from names;
$$;
