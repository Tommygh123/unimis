-- 010k Evidence-led assessment and rules-based performance decision engine.
-- Human input validates evidence; objective scoring is calculated by the system.

alter table public.hr_performance_plan_items
  add column if not exists system_score numeric(6,2),
  add column if not exists supervisor_validation text not null default 'pending',
  add column if not exists validation_reason text,
  add column if not exists scoring_source text not null default 'system';

do $$ begin
  if not exists(select 1 from pg_constraint where conname='hr_perf_item_validation_check') then
    alter table public.hr_performance_plan_items add constraint hr_perf_item_validation_check
      check(supervisor_validation in ('pending','confirmed','disputed'));
  end if;
end $$;

alter table public.hr_performance_decisions
  add column if not exists rule_code text,
  add column if not exists proposed_value numeric(10,2),
  add column if not exists system_generated boolean not null default false;

create table if not exists public.hr_performance_decision_rules(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  code text not null,
  action_type text not null check(action_type in ('recognition','merit_bonus','salary_increment','promotion','training','mentoring','workload_realignment','pip','conduct_coaching','management_review','succession_pool','no_action','other')),
  min_final_score numeric(6,2),
  max_final_score numeric(6,2),
  min_conduct_score numeric(6,2),
  increment_percent numeric(6,2),
  require_no_open_pip boolean not null default false,
  active boolean not null default true,
  approval_required boolean not null default true,
  description text,
  created_at timestamptz not null default now(),
  unique(tenant_id,code)
);
alter table public.hr_performance_decision_rules enable row level security;
drop policy if exists tenant_member_all on public.hr_performance_decision_rules;
create policy tenant_member_all on public.hr_performance_decision_rules for all
using (public.is_tenant_member(tenant_id)) with check (public.is_tenant_member(tenant_id));

-- Safe starter rules. They create recommendations only; they never change salary, grade or employment automatically.
do $$ declare t record; begin
 for t in select id from public.tenants loop
  insert into public.hr_performance_decision_rules(tenant_id,code,action_type,min_final_score,max_final_score,min_conduct_score,increment_percent,require_no_open_pip,description) values
   (t.id,'PERF-PROMO-85','promotion',85,null,80,null,true,'Promotion eligibility: strong approved performance, conduct >=80 and no open PIP.'),
   (t.id,'PERF-INCR-90','salary_increment',90,null,80,8,true,'8% performance increment recommendation for approved score >=90.'),
   (t.id,'PERF-INCR-80','salary_increment',80,89.99,75,5,true,'5% performance increment recommendation for approved score 80-89.99.'),
   (t.id,'PERF-INCR-70','salary_increment',70,79.99,70,2,true,'2% performance increment recommendation for approved score 70-79.99.'),
   (t.id,'PERF-TRAIN-50','training',50,69.99,null,null,false,'Targeted development recommended for performance between 50 and 69.99.'),
   (t.id,'PERF-PIP-LOW','pip',null,49.99,null,null,false,'PIP recommended when approved performance is below 50.')
  on conflict(tenant_id,code) do nothing;
 end loop;
end $$;

-- Calculate objective item scores from agreed target vs actual. Scores are capped at 100 for appraisal weighting.
create or replace function public.hr_performance_system_score(p_tenant uuid,p_review uuid) returns jsonb
language plpgsql security definer set search_path=public as $$
declare n integer:=0;
begin
 if not public.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 if exists(select 1 from hr_performance_reviews where tenant_id=p_tenant and id=p_review and finalization_status='finalized') then
   raise exception 'Finalized appraisal is locked';
 end if;
 update hr_performance_plan_items
 set system_score = case
   when actual_value is null or target_value is null then null
   when direction='higher_better' and target_value<>0 then round(least(100,(actual_value/target_value)*100),2)
   when direction='lower_better' and actual_value<>0 then round(least(100,(target_value/actual_value)*100),2)
   when direction='pass_fail' then case when actual_value>=target_value then 100 else 0 end
   when direction='milestone' and target_value<>0 then round(least(100,(actual_value/target_value)*100),2)
   else null end,
   scoring_source='system'
 where tenant_id=p_tenant and review_id=p_review;
 get diagnostics n=row_count;
 return jsonb_build_object('items_scored',n);
end $$;
grant execute on function public.hr_performance_system_score(uuid,uuid) to authenticated;

-- Supervisor validates system evidence. A dispute never permits a secret arbitrary score: it requires a reason
-- and remains visible for calibration. Confirmed system score becomes the provisional assessed score.
create or replace function public.hr_performance_validate_item(p_tenant uuid,p_item uuid,p_validation text,p_reason text default null) returns jsonb
language plpgsql security definer set search_path=public as $$
declare rid uuid; s numeric;
begin
 if not public.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 if p_validation not in ('confirmed','disputed') then raise exception 'Validation must be confirmed or disputed'; end if;
 if p_validation='disputed' and coalesce(length(trim(p_reason)),0)<10 then raise exception 'A meaningful reason is required when disputing system evidence'; end if;
 select review_id,system_score into rid,s from hr_performance_plan_items where tenant_id=p_tenant and id=p_item;
 if rid is null then raise exception 'Performance item not found'; end if;
 if s is null then raise exception 'System score unavailable; capture actual result first'; end if;
 update hr_performance_plan_items
 set supervisor_validation=p_validation,validation_reason=nullif(trim(p_reason),''),
     supervisor_score=case when p_validation='confirmed' then s else null end,
     final_score=case when p_validation='confirmed' then s else null end,
     status=case when p_validation='confirmed' and s>=100 then 'exceeded' when p_validation='confirmed' and s>=70 then 'on_track' when p_validation='confirmed' then 'at_risk' else status end
 where tenant_id=p_tenant and id=p_item;
 return jsonb_build_object('review_id',rid,'validation',p_validation,'system_score',s);
end $$;
grant execute on function public.hr_performance_validate_item(uuid,uuid,text,text) to authenticated;

-- Rules engine: after finalization, generate auditable recommendations. Consequential actions still require approval.
create or replace function public.hr_performance_evaluate_decisions(p_tenant uuid,p_review uuid) returns jsonb
language plpgsql security definer set search_path=public as $$
declare r record; rev record; open_pip integer:=0; created integer:=0;
begin
 if not public.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 select * into rev from hr_performance_reviews where tenant_id=p_tenant and id=p_review;
 if rev.id is null then raise exception 'Review not found'; end if;
 if rev.finalization_status<>'finalized' or rev.final_score is null then raise exception 'Finalize the appraisal before running decision rules'; end if;
 select count(*) into open_pip from hr_performance_improvement_plans where tenant_id=p_tenant and review_id=p_review and status='open';
 for r in select * from hr_performance_decision_rules where tenant_id=p_tenant and active loop
   if (r.min_final_score is null or rev.final_score>=r.min_final_score)
      and (r.max_final_score is null or rev.final_score<=r.max_final_score)
      and (r.min_conduct_score is null or coalesce(rev.professional_conduct_score,0)>=r.min_conduct_score)
      and (not r.require_no_open_pip or open_pip=0) then
     if not exists(select 1 from hr_performance_decisions where tenant_id=p_tenant and review_id=p_review and rule_code=r.code and status<>'cancelled') then
       insert into hr_performance_decisions(tenant_id,review_id,action_type,rationale,status,rule_code,proposed_value,system_generated)
       values(p_tenant,p_review,r.action_type,r.description,'recommended',r.code,r.increment_percent,true);
       created:=created+1;
     end if;
   end if;
 end loop;
 return jsonb_build_object('recommendations_created',created,'final_score',rev.final_score,'conduct_score',rev.professional_conduct_score);
end $$;
grant execute on function public.hr_performance_evaluate_decisions(uuid,uuid) to authenticated;
