-- 011h correction of 011g: enforce performance plan total weight ceiling.
-- 011g failed before application, so this intentionally replaces the same migration version.
create or replace function public.hr_guard_performance_plan_weight() returns trigger
language plpgsql security definer set search_path=public as $$
declare
  v_total numeric;
begin
  if new.weight is null or new.weight <= 0 then
    raise exception 'Performance measure weight must be greater than 0%%.';
  end if;

  select coalesce(sum(weight),0)
    into v_total
  from public.hr_performance_plan_items
  where tenant_id = new.tenant_id
    and review_id = new.review_id
    and id is distinct from new.id;

  if v_total + new.weight > 100.0001 then
    raise exception 'Performance plan total weight cannot exceed 100%%. Current other measures total %, attempted measure %.', v_total, new.weight;
  end if;

  return new;
end
$$;

drop trigger if exists trg_hr_performance_plan_weight_ceiling on public.hr_performance_plan_items;
create trigger trg_hr_performance_plan_weight_ceiling
before insert or update of weight, review_id
on public.hr_performance_plan_items
for each row execute function public.hr_guard_performance_plan_weight();
