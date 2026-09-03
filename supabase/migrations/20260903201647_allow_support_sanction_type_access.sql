-- RingMaster support users can open a club through the support dashboard, but
-- the original policy only allowed direct club-staff assignments. Align the
-- sanction-type policy with that dashboard access model.
drop policy if exists "Club staff can manage sanction types"
  on public.club_sanction_types;

create policy "Club staff and RingMaster support can manage sanction types"
on public.club_sanction_types
for all
to authenticated
using (
  public.is_ringmaster_support_user()
  or exists (
    select 1
    from public.club_staff_assignments assignment
    where assignment.club_id = club_sanction_types.club_id
      and assignment.user_id = auth.uid()
      and assignment.status = 'active'
  )
)
with check (
  public.is_ringmaster_support_user()
  or exists (
    select 1
    from public.club_staff_assignments assignment
    where assignment.club_id = club_sanction_types.club_id
      and assignment.user_id = auth.uid()
      and assignment.status = 'active'
  )
);
