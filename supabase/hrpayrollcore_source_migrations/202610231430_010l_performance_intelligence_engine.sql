-- 010l Performance Intelligence Engine foundation
-- Evidence per measure -> verified actual -> deterministic score -> integrity signal -> governed decision rules.

alter table public.hr_performance_plan_items
  add column if not exists evidence_count integer not null default 0,
  add column if not exists latest_evidence_source text,
  add column if not exists integrity_flag text not null default 'normal';

do $$ begin
 if not exists(select 1 from pg_constraint where conname='hr_perf_integrity_flag_check') then
  alter table public.hr_performance_plan_items add constraint hr_perf_integrity_flag_check check(integrity_flag in ('normal','review'));
 end if;
end $$;

create table if not exists public.hr_performance_checkin_items(
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete cascade,
 checkin_id uuid not null references public.hr_performance_checkins(id) on delete cascade,
 review_id uuid not null references public.hr_performance_reviews(id) on delete cascade,
 plan_item_id uuid not null references public.hr_performance_plan_items(id) on delete cascade,
 actual_value numeric(14,2) not null,
 evidence text,
 evidence_source text not null default 'manager_observation' check(evidence_source in ('system_record','document','manager_observation','employee_submission','customer_feedback','other')),
 created_by uuid default auth.uid(),
 created_at timestamptz not null default now()
);
alter table public.hr_performance_checkin_items enable row level security;
drop policy if exists tenant_member_all on public.hr_performance_checkin_items;
create policy tenant_member_all on public.hr_performance_checkin_items for all using(public.is_tenant_member(tenant_id)) with check(public.is_tenant_member(tenant_id));
create index if not exists idx_perf_checkin_items_review on public.hr_performance_checkin_items(review_id,plan_item_id,created_at desc);

create or replace function public.hr_performance_refresh_intelligence(p_tenant uuid,p_review uuid) returns jsonb
language plpgsql security definer set search_path=public as $$
declare v_progress numeric(6,2); v_weight numeric(8,2); v_scored integer;
begin
 if not public.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 if exists(select 1 from hr_performance_reviews where tenant_id=p_tenant and id=p_review and finalization_status='finalized') then raise exception 'Finalized appraisal is locked'; end if;

 -- Latest evidence-backed actual becomes the verified actual. Existing actuals remain valid for legacy/demo records.
 with latest as (
  select distinct on (plan_item_id) plan_item_id,actual_value,evidence_source
  from hr_performance_checkin_items where tenant_id=p_tenant and review_id=p_review
  order by plan_item_id,created_at desc,id desc
 ), counts as (
  select plan_item_id,count(*)::int evidence_count from hr_performance_checkin_items where tenant_id=p_tenant and review_id=p_review group by plan_item_id
 )
 update hr_performance_plan_items p set
  actual_value=coalesce(l.actual_value,p.actual_value),
  latest_evidence_source=coalesce(l.evidence_source,p.latest_evidence_source),
  evidence_count=coalesce(c.evidence_count,p.evidence_count,0)
 from latest l left join counts c on c.plan_item_id=l.plan_item_id
 where p.tenant_id=p_tenant and p.review_id=p_review and p.id=l.plan_item_id;

 -- Backfill evidence count for items with no latest CTE row and preserve legacy actual values.
 update hr_performance_plan_items p set evidence_count=(select count(*) from hr_performance_checkin_items ci where ci.tenant_id=p_tenant and ci.review_id=p_review and ci.plan_item_id=p.id)
 where p.tenant_id=p_tenant and p.review_id=p_review;

 update hr_performance_plan_items set
  system_score=case
   when actual_value is null or target_value is null then null
   when direction='higher_better' and target_value<>0 then round(least(100,(actual_value/target_value)*100),2)
   when direction='lower_better' and actual_value=0 then 100
   when direction='lower_better' and actual_value<>0 then round(least(100,(target_value/actual_value)*100),2)
   when direction='pass_fail' then case when actual_value>=target_value then 100 else 0 end
   when direction='milestone' and target_value<>0 then round(least(100,(actual_value/target_value)*100),2)
   else null end,
  scoring_source='system',
  integrity_flag=case
   when actual_value is not null and evidence_count=0 then 'review'
   when supervisor_validation='disputed' then 'review'
   else 'normal' end
 where tenant_id=p_tenant and review_id=p_review;
 get diagnostics v_scored=row_count;

 select coalesce(sum(weight),0),
        case when coalesce(sum(weight) filter (where system_score is not null),0)=0 then null
             else round(sum(system_score*weight) filter (where system_score is not null)/sum(weight) filter (where system_score is not null),2) end
 into v_weight,v_progress from hr_performance_plan_items where tenant_id=p_tenant and review_id=p_review;

 return jsonb_build_object('items_scored',v_scored,'progress_percent',v_progress,'plan_weight',v_weight);
end $$;
grant execute on function public.hr_performance_refresh_intelligence(uuid,uuid) to authenticated;

create or replace function public.hr_performance_record_evidence_checkin(
 p_tenant uuid,p_review uuid,p_status text,p_actual_progress text,p_achievements text,p_blockers text,p_evidence text,p_support_required text,p_next_actions text,p_measures jsonb
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_checkin uuid; m jsonb; v_item uuid; v_actual numeric; v_progress numeric;
begin
 if not public.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 if not exists(select 1 from hr_performance_reviews where tenant_id=p_tenant and id=p_review and plan_status='activated' and finalization_status<>'finalized') then raise exception 'Review must be activated and not finalized'; end if;
 if p_status not in ('on_track','at_risk','off_track','exceeded') then raise exception 'Invalid check-in status'; end if;
 insert into hr_performance_checkins(tenant_id,review_id,checkin_date,progress_percent,status,actual_progress,achievements,blockers,evidence,support_required,next_actions)
 values(p_tenant,p_review,current_date,null,p_status,nullif(trim(p_actual_progress),''),nullif(trim(p_achievements),''),nullif(trim(p_blockers),''),nullif(trim(p_evidence),''),nullif(trim(p_support_required),''),nullif(trim(p_next_actions),'')) returning id into v_checkin;

 for m in select * from jsonb_array_elements(coalesce(p_measures,'[]'::jsonb)) loop
  v_item=nullif(m->>'item_id','')::uuid; v_actual=nullif(m->>'actual_value','')::numeric;
  if v_item is not null and v_actual is not null then
   if not exists(select 1 from hr_performance_plan_items where id=v_item and tenant_id=p_tenant and review_id=p_review) then raise exception 'Invalid performance measure in check-in'; end if;
   insert into hr_performance_checkin_items(tenant_id,checkin_id,review_id,plan_item_id,actual_value,evidence,evidence_source)
   values(p_tenant,v_checkin,p_review,v_item,v_actual,nullif(trim(m->>'evidence'),''),coalesce(nullif(m->>'evidence_source',''),'manager_observation'));
  end if;
 end loop;

 perform public.hr_performance_refresh_intelligence(p_tenant,p_review);
 select case when coalesce(sum(weight) filter (where system_score is not null),0)=0 then null else round(sum(system_score*weight) filter (where system_score is not null)/sum(weight) filter (where system_score is not null),2) end
 into v_progress from hr_performance_plan_items where tenant_id=p_tenant and review_id=p_review;
 update hr_performance_checkins set progress_percent=v_progress where id=v_checkin;
 return jsonb_build_object('checkin_id',v_checkin,'progress_percent',v_progress);
end $$;
grant execute on function public.hr_performance_record_evidence_checkin(uuid,uuid,text,text,text,text,text,text,text,jsonb) to authenticated;

-- Make 010k scoring use the same intelligence refresh so legacy Actual values and new evidence records behave consistently.
create or replace function public.hr_performance_system_score(p_tenant uuid,p_review uuid) returns jsonb
language plpgsql security definer set search_path=public as $$
begin return public.hr_performance_refresh_intelligence(p_tenant,p_review); end $$;
grant execute on function public.hr_performance_system_score(uuid,uuid) to authenticated;

-- Existing demo actuals pre-date evidence capture. Flag them for review rather than pretending they are evidence-backed.
update public.hr_performance_plan_items set integrity_flag='review'
where actual_value is not null and evidence_count=0;
