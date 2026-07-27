-- ISRBA's established shared-exhibitor names.  These remain ordinary, editable
-- Club Rules.  Award standings use them only when every named person is an
-- active eligible member.
with isrba as (
  select id
  from public.clubs
  where name = 'Indiana State Rabbit Breeders Association'
), rules(rule_type, match_value, replacement_value, match_mode, sort_order) as (
  values
    ('name_pattern', 'boyce brad katie', 'Brad Boyce / Katie Boyce', 'contains_all_words', 100),
    ('name_pattern', 'boxell nathan lisa case', 'Nathan and Lisa and Case Boxell', 'contains_all_words', 110),
    ('name_pattern', 'kilander leon louella', 'Leon and Louella Kilander', 'contains_all_words', 120),
    ('name_pattern', 'stewart julie gary', 'Julie AND Gary Stewart', 'contains_all_words', 130),
    ('name_pattern', 'mckinney walker briana', 'LeAnn McKinney / Briana Walker', 'contains_all_words', 140),
    ('name_alias', 'briana', 'LeAnn McKinney / Briana Walker', 'exact', 150),
    ('name_pattern', 'marley heretier cathy', 'Marley Heritier / Cathy McDevitt', 'contains_all_words', 160),
    ('name_pattern', 'mckinney walker', 'LeAnn McKinney / Briana Walker', 'contains_all_words', 170),
    ('name_pattern', 'mckinney p.o.', 'LeAnn McKinney / Briana Walker', 'contains_all_words', 180),
    ('name_pattern', 'kilander david megan bryce', 'David and Megan and Bryce Kilander', 'contains_all_words', 190),
    ('name_pattern', 'lowe justin danielle benjamin micah olivia', 'Justin AND Danielle AND Benjamin AND Micah AND Olivia Lowe', 'contains_all_words', 200),
    ('name_pattern', 'batchler keller', 'Jeff Batchler / Paula Keller', 'contains_all_words', 210)
)
insert into public.club_sweepstakes_parser_rules (
  club_id, rule_type, match_value, replacement_value, rule_config,
  description, is_active, sort_order
)
select
  isrba.id,
  rules.rule_type,
  rules.match_value,
  rules.replacement_value,
  jsonb_build_object('match_mode', rules.match_mode),
  'Recognize a shared exhibitor result for active ISRBA members.',
  true,
  rules.sort_order
from isrba
cross join rules
where not exists (
  select 1
  from public.club_sweepstakes_parser_rules existing
  where existing.club_id = isrba.id
    and existing.rule_type = rules.rule_type
    and lower(existing.match_value) = lower(rules.match_value)
);
