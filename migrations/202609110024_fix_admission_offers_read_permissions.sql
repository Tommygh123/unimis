-- UniMIS: fix authenticated access to admission_offers.
-- Recommendation/approval writes continue through SECURITY DEFINER RPCs.
-- This migration only gives institution members permission to READ their
-- institution's offer rows so Admissions refresh / Approval & Offers can load.

begin;

grant select on table public.admission_offers to authenticated;
revoke all on table public.admission_offers from anon;

alter table public.admission_offers enable row level security;

drop policy if exists "Institution members can view admission offers"
  on public.admission_offers;

create policy "Institution members can view admission offers"
on public.admission_offers
for select
to authenticated
using (
  exists (
    select 1
    from public.institution_users iu
    where iu.user_id = auth.uid()
      and iu.institution_id = admission_offers.institution_id
      and iu.status = 'active'
  )
);

commit;
