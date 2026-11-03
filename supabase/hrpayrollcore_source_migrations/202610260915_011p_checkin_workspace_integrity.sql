-- 011p: prevent accidental duplicate scheduled-period check-ins and suppress legacy duplicate pending evidence.

create or replace function public.hr_guard_duplicate_performance_checkin_period() returns trigger
language plpgsql security definer set search_path=public as $$
begin
  if coalesce(new.period_key,'') <> '' and upper(new.period_key) <> 'ADHOC' and exists (
    select 1 from public.hr_performance_checkins c
    where c.tenant_id=new.tenant_id and c.review_id=new.review_id
      and c.period_key=new.period_key and c.id<>new.id
  ) then
    raise exception 'A check-in has already been recorded for this employee and review period. Open Check-in History instead of submitting the same period again.';
  end if;
  return new;
end $$;

drop trigger if exists trg_hr_guard_duplicate_performance_checkin_period on public.hr_performance_checkins;
create trigger trg_hr_guard_duplicate_performance_checkin_period
before insert or update of tenant_id,review_id,period_key on public.hr_performance_checkins
for each row execute function public.hr_guard_duplicate_performance_checkin_period();

-- Preserve audit rows but close exact pending duplicates where an identical result/reference is already verified.
update public.hr_performance_checkin_items p
set verification_status='rejected',
    verified_at=coalesce(p.verified_at,now()),
    verification_note=coalesce(p.verification_note,'Duplicate submission suppressed: an identical result and evidence reference is already verified.')
where p.verification_status='pending'
  and exists (
    select 1 from public.hr_performance_checkin_items v
    where v.tenant_id=p.tenant_id
      and v.review_id=p.review_id
      and v.plan_item_id=p.plan_item_id
      and v.id<>p.id
      and v.actual_value is not distinct from p.actual_value
      and coalesce(v.evidence,'')=coalesce(p.evidence,'')
      and v.verification_status in ('verified','system_verified','manager_attested')
  );
