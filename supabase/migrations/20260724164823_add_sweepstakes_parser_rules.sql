-- Editable, auditable rules replace club-specific parser code exceptions.
create table public.club_sweepstakes_parser_rules (
  id uuid primary key default gen_random_uuid(),
  club_id uuid not null references public.clubs(id) on delete cascade,
  rule_type text not null check (rule_type in (
    'name_alias', 'name_pattern', 'address_stop_word', 'breed_alias',
    'division_assignment', 'points_rule'
  )),
  match_value text not null,
  replacement_value text,
  rule_config jsonb not null default '{}'::jsonb,
  description text,
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index club_sweepstakes_parser_rules_club_type_idx
  on public.club_sweepstakes_parser_rules(club_id, rule_type, is_active, sort_order);

alter table public.club_sweepstakes_parser_rules enable row level security;

create policy "Club staff can manage sweepstakes parser rules"
  on public.club_sweepstakes_parser_rules for all to authenticated
  using (is_club_staff(club_id, auth.uid()))
  with check (is_club_staff(club_id, auth.uid()));
