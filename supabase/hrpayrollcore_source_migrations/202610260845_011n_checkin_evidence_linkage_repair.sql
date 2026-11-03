-- 011n: repair legacy check-in/evidence linkage and refresh historical verification progress.
-- Future submissions already carry checkin_id; this repair is deliberately conservative:
-- legacy/mismatched rows are reassigned only when the review has exactly one check-in.

with single_checkin_reviews as (
  select tenant_id, review_id, min(id::text)::uuid as checkin_id
  from public.hr_performance_checkins
  group by tenant_id, review_id
  having count(*) = 1
)
update public.hr_performance_checkin_items ci
set checkin_id = s.checkin_id
from single_checkin_reviews s
where ci.tenant_id = s.tenant_id
  and ci.review_id = s.review_id
  and ci.checkin_id is distinct from s.checkin_id;

-- Recalculate every historical check-in strictly from submissions linked to that check-in.
with totals as (
  select tenant_id, review_id, count(*)::int as total_count
  from public.hr_performance_plan_items
  group by tenant_id, review_id
), accepted as (
  select distinct on (ci.tenant_id, ci.checkin_id, ci.plan_item_id)
         ci.tenant_id, ci.checkin_id, ci.review_id, ci.plan_item_id, ci.actual_value
  from public.hr_performance_checkin_items ci
  where ci.checkin_id is not null
    and ci.verification_status in ('verified','system_verified','manager_attested')
  order by ci.tenant_id, ci.checkin_id, ci.plan_item_id, ci.created_at desc, ci.id desc
), scored as (
  select a.tenant_id, a.checkin_id, a.review_id, p.weight,
         case
           when a.actual_value is null or p.target_value is null then null
           when p.direction='higher_better' and p.target_value<>0 then least(100,(a.actual_value/p.target_value)*100)
           when p.direction='lower_better' and a.actual_value=0 then 100
           when p.direction='lower_better' and a.actual_value<>0 then least(100,(p.target_value/a.actual_value)*100)
           when p.direction='pass_fail' then case when a.actual_value>=p.target_value then 100 else 0 end
           when p.direction='milestone' and p.target_value<>0 then least(100,(a.actual_value/p.target_value)*100)
           else null
         end as score
  from accepted a
  join public.hr_performance_plan_items p
    on p.tenant_id=a.tenant_id and p.review_id=a.review_id and p.id=a.plan_item_id
), agg as (
  select tenant_id, checkin_id, review_id,
         count(*) filter (where score is not null)::int as verified_count,
         round(coalesce(sum(score*weight/100.0) filter (where score is not null),0),2) as current_progress
  from scored
  group by tenant_id, checkin_id, review_id
)
update public.hr_performance_checkins c
set current_verified_progress_percent = coalesce(a.current_progress,0),
    verified_measure_count = coalesce(a.verified_count,0),
    total_measure_count = coalesce(t.total_count,0),
    verification_progress_updated_at = now()
from totals t
left join agg a
  on a.tenant_id=t.tenant_id and a.review_id=t.review_id
where c.tenant_id=t.tenant_id
  and c.review_id=t.review_id
  and (a.checkin_id=c.id or not exists (
        select 1 from agg ax
        where ax.tenant_id=c.tenant_id and ax.review_id=c.review_id and ax.checkin_id=c.id
      ));

-- Keep the runtime refresh function exact-check-in scoped.
create or replace function public.hr_refresh_checkin_verified_progress(p_tenant uuid,p_checkin uuid) returns jsonb
language plpgsql security definer set search_path=public as $$
declare v_review uuid; v_progress numeric(6,2); v_verified integer; v_total integer;
begin
 if not public.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 select review_id into v_review from hr_performance_checkins where tenant_id=p_tenant and id=p_checkin;
 if not found then raise exception 'Check-in not found'; end if;
 select count(*) into v_total from hr_performance_plan_items where tenant_id=p_tenant and review_id=v_review;
 with accepted as (
  select distinct on (ci.plan_item_id) ci.plan_item_id,ci.actual_value
  from hr_performance_checkin_items ci
  where ci.tenant_id=p_tenant and ci.review_id=v_review and ci.checkin_id=p_checkin
    and ci.verification_status in ('verified','system_verified','manager_attested')
  order by ci.plan_item_id,ci.created_at desc,ci.id desc
 ), scored as (
  select p.id,p.weight,
   case
    when a.actual_value is null or p.target_value is null then null
    when p.direction='higher_better' and p.target_value<>0 then least(100,(a.actual_value/p.target_value)*100)
    when p.direction='lower_better' and a.actual_value=0 then 100
    when p.direction='lower_better' and a.actual_value<>0 then least(100,(p.target_value/a.actual_value)*100)
    when p.direction='pass_fail' then case when a.actual_value>=p.target_value then 100 else 0 end
    when p.direction='milestone' and p.target_value<>0 then least(100,(a.actual_value/p.target_value)*100)
    else null end as score
  from accepted a join hr_performance_plan_items p on p.id=a.plan_item_id
  where p.tenant_id=p_tenant and p.review_id=v_review
 )
 select count(*) filter(where score is not null)::int,
        round(coalesce(sum(score*weight/100.0) filter(where score is not null),0),2)
 into v_verified,v_progress from scored;
 update hr_performance_checkins set current_verified_progress_percent=v_progress,
  verified_measure_count=coalesce(v_verified,0),total_measure_count=v_total,
  verification_progress_updated_at=now()
 where tenant_id=p_tenant and id=p_checkin;
 return jsonb_build_object('checkin_id',p_checkin,'current_verified_progress_percent',v_progress,'verified_measure_count',coalesce(v_verified,0),'total_measure_count',v_total);
end $$;
grant execute on function public.hr_refresh_checkin_verified_progress(uuid,uuid) to authenticated;
