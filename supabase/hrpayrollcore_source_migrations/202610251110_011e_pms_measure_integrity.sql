-- 011e PMS measure integrity
-- A library KPI may appear only once in an employee review plan.
-- Custom/ad-hoc measures (metric_id is null) remain unrestricted.

-- Clean up any pre-existing accidental duplicate library KPIs before enforcing uniqueness.
-- Keep the earliest-created plan item and remove only later duplicates of the same metric
-- inside the same review.
with ranked as (
  select id,
         row_number() over (
           partition by review_id, metric_id
           order by created_at nulls last, id
         ) as rn
  from public.hr_performance_plan_items
  where metric_id is not null
)
delete from public.hr_performance_plan_items p
using ranked r
where p.id=r.id and r.rn>1;

create unique index if not exists hr_perf_plan_unique_library_metric
  on public.hr_performance_plan_items(review_id, metric_id)
  where metric_id is not null;
