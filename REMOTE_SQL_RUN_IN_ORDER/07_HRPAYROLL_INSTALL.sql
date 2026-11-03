-- CONTINUATION: UniMIS Build 172 HR/Payroll repair
set search_path=unimis,public;

-- SOURCE 202610231150_010k_pms_evidence_assessment_decision_engine.sql
-- 010k Evidence-led assessment and rules-based performance decision engine.
-- Human input validates evidence; objective scoring is calculated by the system.

alter table unimis.hrc_hr_performance_plan_items
  add column if not exists system_score numeric(6,2),
  add column if not exists supervisor_validation text not null default 'pending',
  add column if not exists validation_reason text,
  add column if not exists scoring_source text not null default 'system';

do $$ begin
  if not exists(select 1 from pg_constraint where conname='hr_perf_item_validation_check') then
    alter table unimis.hrc_hr_performance_plan_items add constraint hr_perf_item_validation_check
      check(supervisor_validation in ('pending','confirmed','disputed'));
  end if;
end $$;

alter table unimis.hrc_hr_performance_decisions
  add column if not exists rule_code text,
  add column if not exists proposed_value numeric(10,2),
  add column if not exists system_generated boolean not null default false;

create table if not exists unimis.hrc_hr_performance_decision_rules(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
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
alter table unimis.hrc_hr_performance_decision_rules enable row level security;
drop policy if exists tenant_member_all on unimis.hrc_hr_performance_decision_rules;
create policy tenant_member_all on unimis.hrc_hr_performance_decision_rules for all
using (unimis.is_tenant_member(tenant_id)) with check (unimis.is_tenant_member(tenant_id));

-- Safe starter rules. They create recommendations only; they never change salary, grade or employment automatically.
do $$ declare t record; begin
 for t in select id from unimis.hrc_tenants loop
  insert into unimis.hrc_hr_performance_decision_rules(tenant_id,code,action_type,min_final_score,max_final_score,min_conduct_score,increment_percent,require_no_open_pip,description) values
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
create or replace function unimis.hr_performance_system_score(p_tenant uuid,p_review uuid) returns jsonb
language plpgsql security definer set search_path=unimis as $$
declare n integer:=0;
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 if exists(select 1 from hrc_hr_performance_reviews where tenant_id=p_tenant and id=p_review and finalization_status='finalized') then
   raise exception 'Finalized appraisal is locked';
 end if;
 update hrc_hr_performance_plan_items
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
grant execute on function unimis.hr_performance_system_score(uuid,uuid) to authenticated;

-- Supervisor validates system evidence. A dispute never permits a secret arbitrary score: it requires a reason
-- and remains visible for calibration. Confirmed system score becomes the provisional assessed score.
create or replace function unimis.hr_performance_validate_item(p_tenant uuid,p_item uuid,p_validation text,p_reason text default null) returns jsonb
language plpgsql security definer set search_path=unimis as $$
declare rid uuid; s numeric;
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 if p_validation not in ('confirmed','disputed') then raise exception 'Validation must be confirmed or disputed'; end if;
 if p_validation='disputed' and coalesce(length(trim(p_reason)),0)<10 then raise exception 'A meaningful reason is required when disputing system evidence'; end if;
 select review_id,system_score into rid,s from hrc_hr_performance_plan_items where tenant_id=p_tenant and id=p_item;
 if rid is null then raise exception 'Performance item not found'; end if;
 if s is null then raise exception 'System score unavailable; capture actual result first'; end if;
 update hrc_hr_performance_plan_items
 set supervisor_validation=p_validation,validation_reason=nullif(trim(p_reason),''),
     supervisor_score=case when p_validation='confirmed' then s else null end,
     final_score=case when p_validation='confirmed' then s else null end,
     status=case when p_validation='confirmed' and s>=100 then 'exceeded' when p_validation='confirmed' and s>=70 then 'on_track' when p_validation='confirmed' then 'at_risk' else status end
 where tenant_id=p_tenant and id=p_item;
 return jsonb_build_object('review_id',rid,'validation',p_validation,'system_score',s);
end $$;
grant execute on function unimis.hr_performance_validate_item(uuid,uuid,text,text) to authenticated;

-- Rules engine: after finalization, generate auditable recommendations. Consequential actions still require approval.
create or replace function unimis.hr_performance_evaluate_decisions(p_tenant uuid,p_review uuid) returns jsonb
language plpgsql security definer set search_path=unimis as $$
declare r record; rev record; open_pip integer:=0; created integer:=0;
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 select * into rev from hrc_hr_performance_reviews where tenant_id=p_tenant and id=p_review;
 if rev.id is null then raise exception 'Review not found'; end if;
 if rev.finalization_status<>'finalized' or rev.final_score is null then raise exception 'Finalize the appraisal before running decision rules'; end if;
 select count(*) into open_pip from hrc_hr_performance_improvement_plans where tenant_id=p_tenant and review_id=p_review and status='open';
 for r in select * from hrc_hr_performance_decision_rules where tenant_id=p_tenant and active loop
   if (r.min_final_score is null or rev.final_score>=r.min_final_score)
      and (r.max_final_score is null or rev.final_score<=r.max_final_score)
      and (r.min_conduct_score is null or coalesce(rev.professional_conduct_score,0)>=r.min_conduct_score)
      and (not r.require_no_open_pip or open_pip=0) then
     if not exists(select 1 from hrc_hr_performance_decisions where tenant_id=p_tenant and review_id=p_review and rule_code=r.code and status<>'cancelled') then
       insert into hrc_hr_performance_decisions(tenant_id,review_id,action_type,rationale,status,rule_code,proposed_value,system_generated)
       values(p_tenant,p_review,r.action_type,r.description,'recommended',r.code,r.increment_percent,true);
       created:=created+1;
     end if;
   end if;
 end loop;
 return jsonb_build_object('recommendations_created',created,'final_score',rev.final_score,'conduct_score',rev.professional_conduct_score);
end $$;
grant execute on function unimis.hr_performance_evaluate_decisions(uuid,uuid) to authenticated;


-- SOURCE 202610231430_010l_performance_intelligence_engine.sql
-- 010l Performance Intelligence Engine foundation
-- Evidence per measure -> verified actual -> deterministic score -> integrity signal -> governed decision rules.

alter table unimis.hrc_hr_performance_plan_items
  add column if not exists evidence_count integer not null default 0,
  add column if not exists latest_evidence_source text,
  add column if not exists integrity_flag text not null default 'normal';

do $$ begin
 if not exists(select 1 from pg_constraint where conname='hr_perf_integrity_flag_check') then
  alter table unimis.hrc_hr_performance_plan_items add constraint hr_perf_integrity_flag_check check(integrity_flag in ('normal','review'));
 end if;
end $$;

create table if not exists unimis.hrc_hr_performance_checkin_items(
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
 checkin_id uuid not null references unimis.hrc_hr_performance_checkins(id) on delete cascade,
 review_id uuid not null references unimis.hrc_hr_performance_reviews(id) on delete cascade,
 plan_item_id uuid not null references unimis.hrc_hr_performance_plan_items(id) on delete cascade,
 actual_value numeric(14,2) not null,
 evidence text,
 evidence_source text not null default 'manager_observation' check(evidence_source in ('system_record','document','manager_observation','employee_submission','customer_feedback','other')),
 created_by uuid default auth.uid(),
 created_at timestamptz not null default now()
);
alter table unimis.hrc_hr_performance_checkin_items enable row level security;
drop policy if exists tenant_member_all on unimis.hrc_hr_performance_checkin_items;
create policy tenant_member_all on unimis.hrc_hr_performance_checkin_items for all using(unimis.is_tenant_member(tenant_id)) with check(unimis.is_tenant_member(tenant_id));
create index if not exists idx_perf_checkin_items_review on unimis.hrc_hr_performance_checkin_items(review_id,plan_item_id,created_at desc);

create or replace function unimis.hr_performance_refresh_intelligence(p_tenant uuid,p_review uuid) returns jsonb
language plpgsql security definer set search_path=unimis as $$
declare v_progress numeric(6,2); v_weight numeric(8,2); v_scored integer;
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 if exists(select 1 from hrc_hr_performance_reviews where tenant_id=p_tenant and id=p_review and finalization_status='finalized') then raise exception 'Finalized appraisal is locked'; end if;

 -- Latest evidence-backed actual becomes the verified actual. Existing actuals remain valid for legacy/demo records.
 with latest as (
  select distinct on (plan_item_id) plan_item_id,actual_value,evidence_source
  from hrc_hr_performance_checkin_items where tenant_id=p_tenant and review_id=p_review
  order by plan_item_id,created_at desc,id desc
 ), counts as (
  select plan_item_id,count(*)::int evidence_count from hrc_hr_performance_checkin_items where tenant_id=p_tenant and review_id=p_review group by plan_item_id
 )
 update hrc_hr_performance_plan_items p set
  actual_value=coalesce(l.actual_value,p.actual_value),
  latest_evidence_source=coalesce(l.evidence_source,p.latest_evidence_source),
  evidence_count=coalesce(c.evidence_count,p.evidence_count,0)
 from latest l left join counts c on c.plan_item_id=l.plan_item_id
 where p.tenant_id=p_tenant and p.review_id=p_review and p.id=l.plan_item_id;

 -- Backfill evidence count for items with no latest CTE row and preserve legacy actual values.
 update hrc_hr_performance_plan_items p set evidence_count=(select count(*) from hrc_hr_performance_checkin_items ci where ci.tenant_id=p_tenant and ci.review_id=p_review and ci.plan_item_id=p.id)
 where p.tenant_id=p_tenant and p.review_id=p_review;

 update hrc_hr_performance_plan_items set
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
 into v_weight,v_progress from hrc_hr_performance_plan_items where tenant_id=p_tenant and review_id=p_review;

 return jsonb_build_object('items_scored',v_scored,'progress_percent',v_progress,'plan_weight',v_weight);
end $$;
grant execute on function unimis.hr_performance_refresh_intelligence(uuid,uuid) to authenticated;

create or replace function unimis.hr_performance_record_evidence_checkin(
 p_tenant uuid,p_review uuid,p_status text,p_actual_progress text,p_achievements text,p_blockers text,p_evidence text,p_support_required text,p_next_actions text,p_measures jsonb
) returns jsonb language plpgsql security definer set search_path=unimis as $$
declare v_checkin uuid; m jsonb; v_item uuid; v_actual numeric; v_progress numeric;
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 if not exists(select 1 from hrc_hr_performance_reviews where tenant_id=p_tenant and id=p_review and plan_status='activated' and finalization_status<>'finalized') then raise exception 'Review must be activated and not finalized'; end if;
 if p_status not in ('on_track','at_risk','off_track','exceeded') then raise exception 'Invalid check-in status'; end if;
 insert into hrc_hr_performance_checkins(tenant_id,review_id,checkin_date,progress_percent,status,actual_progress,achievements,blockers,evidence,support_required,next_actions)
 values(p_tenant,p_review,current_date,null,p_status,nullif(trim(p_actual_progress),''),nullif(trim(p_achievements),''),nullif(trim(p_blockers),''),nullif(trim(p_evidence),''),nullif(trim(p_support_required),''),nullif(trim(p_next_actions),'')) returning id into v_checkin;

 for m in select * from jsonb_array_elements(coalesce(p_measures,'[]'::jsonb)) loop
  v_item=nullif(m->>'item_id','')::uuid; v_actual=nullif(m->>'actual_value','')::numeric;
  if v_item is not null and v_actual is not null then
   if not exists(select 1 from hrc_hr_performance_plan_items where id=v_item and tenant_id=p_tenant and review_id=p_review) then raise exception 'Invalid performance measure in check-in'; end if;
   insert into hrc_hr_performance_checkin_items(tenant_id,checkin_id,review_id,plan_item_id,actual_value,evidence,evidence_source)
   values(p_tenant,v_checkin,p_review,v_item,v_actual,nullif(trim(m->>'evidence'),''),coalesce(nullif(m->>'evidence_source',''),'manager_observation'));
  end if;
 end loop;

 perform unimis.hr_performance_refresh_intelligence(p_tenant,p_review);
 select case when coalesce(sum(weight) filter (where system_score is not null),0)=0 then null else round(sum(system_score*weight) filter (where system_score is not null)/sum(weight) filter (where system_score is not null),2) end
 into v_progress from hrc_hr_performance_plan_items where tenant_id=p_tenant and review_id=p_review;
 update hrc_hr_performance_checkins set progress_percent=v_progress where id=v_checkin;
 return jsonb_build_object('checkin_id',v_checkin,'progress_percent',v_progress);
end $$;
grant execute on function unimis.hr_performance_record_evidence_checkin(uuid,uuid,text,text,text,text,text,text,text,jsonb) to authenticated;

-- Make 010k scoring use the same intelligence refresh so legacy Actual values and new evidence records behave consistently.
create or replace function unimis.hr_performance_system_score(p_tenant uuid,p_review uuid) returns jsonb
language plpgsql security definer set search_path=unimis as $$
begin return unimis.hr_performance_refresh_intelligence(p_tenant,p_review); end $$;
grant execute on function unimis.hr_performance_system_score(uuid,uuid) to authenticated;

-- Existing demo actuals pre-date evidence capture. Flag them for review rather than pretending they are evidence-backed.
update unimis.hrc_hr_performance_plan_items set integrity_flag='review'
where actual_value is not null and evidence_count=0;


-- SOURCE 202610241000_010m_hr_setup_policy_probation.sql
-- 010m HR setup, policy-gated career/compensation decisions, and probation lifecycle.

create table if not exists unimis.hrc_hr_policy_configs(
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
 policy_type text not null,
 config jsonb not null default '{}'::jsonb,
 updated_at timestamptz not null default now(),
 updated_by uuid default auth.uid(),
 unique(tenant_id,policy_type)
);
alter table unimis.hrc_hr_policy_configs enable row level security;
drop policy if exists tenant_member_all on unimis.hrc_hr_policy_configs;
create policy tenant_member_all on unimis.hrc_hr_policy_configs for all using(unimis.is_tenant_member(tenant_id)) with check(unimis.is_tenant_member(tenant_id));

create table if not exists unimis.hrc_hr_probation_records(
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
 employee_id uuid not null references unimis.hrc_hr_employees(id) on delete cascade,
 start_date date not null,
 expected_end_date date not null,
 actual_end_date date,
 status text not null default 'active' check(status in ('active','review_due','eligible_confirmation','extended','confirmed','management_review','closed')),
 extension_months integer not null default 0,
 review_id uuid references unimis.hrc_hr_performance_reviews(id) on delete set null,
 final_score numeric(6,2),
 policy_result jsonb not null default '{}'::jsonb,
 notes text,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(tenant_id,employee_id,start_date)
);
alter table unimis.hrc_hr_probation_records enable row level security;
drop policy if exists tenant_member_all on unimis.hrc_hr_probation_records;
create policy tenant_member_all on unimis.hrc_hr_probation_records for all using(unimis.is_tenant_member(tenant_id)) with check(unimis.is_tenant_member(tenant_id));
create index if not exists idx_hr_probation_status on unimis.hrc_hr_probation_records(tenant_id,status,expected_end_date);

alter table unimis.hrc_hr_performance_reviews
 add column if not exists performance_remark text,
 add column if not exists policy_eligibility jsonb not null default '{}'::jsonb;

-- Safe defaults: performance is rated independently; promotion/increment need policy eligibility.
do $$ declare t record; begin
 for t in select id from unimis.hrc_tenants loop
  insert into unimis.hrc_hr_policy_configs(tenant_id,policy_type,config) values
  (t.id,'career_compensation',jsonb_build_object(
    'promotion_enabled',true,'promotion_min_score',80,'promotion_min_service_months',36,'promotion_min_conduct',80,
    'promotion_require_no_open_pip',true,'promotion_require_no_queries',true,'promotion_require_training',true,'promotion_require_vacancy',false,
    'increment_enabled',true,'increment_min_score',70,'increment_min_service_months',12,'increment_require_confirmed',true,'increment_require_no_queries',true)),
  (t.id,'probation',jsonb_build_object(
    'enabled',true,'default_months',6,'mid_review_month',3,'max_extension_months',3,'min_score',70,'min_attendance',90,
    'conduct_required',true,'induction_required',true,'auto_create_plan',true)),
  (t.id,'performance_ratings',jsonb_build_object('exceptional_min',90,'very_good_min',80,'good_min',70,'fair_min',60))
  on conflict(tenant_id,policy_type) do nothing;
 end loop;
end $$;

-- New hires enter probation when the tenant policy enables it. This does not auto-confirm or auto-terminate anyone.
create or replace function unimis.hr_create_probation_for_new_employee() returns trigger
language plpgsql security definer set search_path=unimis as $$
declare cfg jsonb; months integer;
begin
 select config into cfg from hrc_hr_policy_configs where tenant_id=new.tenant_id and policy_type='probation';
 if coalesce((cfg->>'enabled')::boolean,false) then
  months:=coalesce((cfg->>'default_months')::integer,6);
  insert into hrc_hr_probation_records(tenant_id,employee_id,start_date,expected_end_date,status)
  values(new.tenant_id,new.id,coalesce(new.hire_date,current_date),coalesce(new.hire_date,current_date)+(months||' months')::interval,'active')
  on conflict do nothing;
 end if;
 return new;
end $$;
drop trigger if exists trg_hr_new_employee_probation on unimis.hrc_hr_employees;
create trigger trg_hr_new_employee_probation after insert on unimis.hrc_hr_employees for each row execute function unimis.hr_create_probation_for_new_employee();

-- Performance result and career/compensation eligibility are deliberately separate.
-- Manual policy gates (queries, mandatory training, vacancy) prevent automatic career action until verified.
create or replace function unimis.hr_performance_evaluate_decisions(p_tenant uuid,p_review uuid) returns jsonb
language plpgsql security definer set search_path=unimis as $$
declare rev record; emp record; cfg jsonb; open_pip integer:=0; service_months integer:=0; created integer:=0;
        remark text; promo_ok boolean:=false; incr_ok boolean:=false; promo_manual boolean:=false; incr_manual boolean:=false;
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 select * into rev from hrc_hr_performance_reviews where tenant_id=p_tenant and id=p_review;
 if rev.id is null then raise exception 'Review not found'; end if;
 if rev.finalization_status<>'finalized' or rev.final_score is null then raise exception 'Finalize the appraisal before evaluating policy eligibility'; end if;
 select * into emp from hrc_hr_employees where tenant_id=p_tenant and id=rev.employee_id;
 select config into cfg from hrc_hr_policy_configs where tenant_id=p_tenant and policy_type='career_compensation';
 cfg:=coalesce(cfg,'{}'::jsonb);
 service_months:=greatest(0,(extract(year from age(current_date,coalesce(emp.hire_date,current_date)))::int*12)+extract(month from age(current_date,coalesce(emp.hire_date,current_date)))::int);
 select count(*) into open_pip from hrc_hr_performance_improvement_plans where tenant_id=p_tenant and employee_id=rev.employee_id and status in ('open','on_track','extended');
 remark:=case when rev.final_score>=90 then 'Exceptional performance for the review period.' when rev.final_score>=80 then 'Very good performance for the review period.' when rev.final_score>=70 then 'Good and satisfactory performance for the review period.' when rev.final_score>=60 then 'Fair performance; improvement is required in identified areas.' else 'Performance is below the satisfactory level; structured improvement support is required.' end;

 promo_manual:=coalesce((cfg->>'promotion_require_no_queries')::boolean,false) or coalesce((cfg->>'promotion_require_training')::boolean,false) or coalesce((cfg->>'promotion_require_vacancy')::boolean,false);
 promo_ok:=coalesce((cfg->>'promotion_enabled')::boolean,false)
   and rev.final_score>=coalesce((cfg->>'promotion_min_score')::numeric,80)
   and service_months>=coalesce((cfg->>'promotion_min_service_months')::int,36)
   and coalesce(rev.professional_conduct_score,0)>=coalesce((cfg->>'promotion_min_conduct')::numeric,80)
   and (not coalesce((cfg->>'promotion_require_no_open_pip')::boolean,true) or open_pip=0);
 incr_manual:=coalesce((cfg->>'increment_require_no_queries')::boolean,false) or coalesce((cfg->>'increment_require_confirmed')::boolean,false);
 incr_ok:=coalesce((cfg->>'increment_enabled')::boolean,false)
   and rev.final_score>=coalesce((cfg->>'increment_min_score')::numeric,70)
   and service_months>=coalesce((cfg->>'increment_min_service_months')::int,12);

 update hrc_hr_performance_reviews set performance_remark=remark,policy_eligibility=jsonb_build_object(
   'performance_rating',coalesce(rev.final_rating,''),'performance_remark',remark,'service_months',service_months,
   'promotion',case when not promo_ok then 'not_eligible' when promo_manual then 'policy_review_required' else 'eligible' end,
   'promotion_manual_checks',jsonb_build_object('disciplinary_queries',coalesce((cfg->>'promotion_require_no_queries')::boolean,false),'mandatory_training',coalesce((cfg->>'promotion_require_training')::boolean,false),'vacancy',coalesce((cfg->>'promotion_require_vacancy')::boolean,false)),
   'salary_increment',case when not incr_ok then 'not_eligible' when incr_manual then 'policy_review_required' else 'eligible' end,
   'increment_manual_checks',jsonb_build_object('confirmed_appointment',coalesce((cfg->>'increment_require_confirmed')::boolean,false),'disciplinary_queries',coalesce((cfg->>'increment_require_no_queries')::boolean,false)))
 where tenant_id=p_tenant and id=p_review;

 -- Development interventions remain evidence/rule driven. Career rewards are created only when all configured gates are machine-clear.
 if rev.final_score<50 and not exists(select 1 from hrc_hr_performance_decisions where tenant_id=p_tenant and review_id=p_review and rule_code='POLICY-PIP' and status<>'cancelled') then
  insert into hrc_hr_performance_decisions(tenant_id,review_id,action_type,rationale,status,rule_code,system_generated) values(p_tenant,p_review,'pip','Final performance is below the satisfactory threshold.','recommended','POLICY-PIP',true); created:=created+1;
 elsif rev.final_score<70 and not exists(select 1 from hrc_hr_performance_decisions where tenant_id=p_tenant and review_id=p_review and rule_code='POLICY-TRAIN' and status<>'cancelled') then
  insert into hrc_hr_performance_decisions(tenant_id,review_id,action_type,rationale,status,rule_code,system_generated) values(p_tenant,p_review,'training','Performance indicates a development need; targeted training/support is recommended.','recommended','POLICY-TRAIN',true); created:=created+1;
 end if;
 if promo_ok and not promo_manual and not exists(select 1 from hrc_hr_performance_decisions where tenant_id=p_tenant and review_id=p_review and rule_code='POLICY-PROMOTION' and status<>'cancelled') then
  insert into hrc_hr_performance_decisions(tenant_id,review_id,action_type,rationale,status,rule_code,system_generated) values(p_tenant,p_review,'promotion','All configured promotion eligibility gates are satisfied; submit for authorized career approval.','recommended','POLICY-PROMOTION',true); created:=created+1;
 end if;
 if incr_ok and not incr_manual and not exists(select 1 from hrc_hr_performance_decisions where tenant_id=p_tenant and review_id=p_review and rule_code='POLICY-INCREMENT' and status<>'cancelled') then
  insert into hrc_hr_performance_decisions(tenant_id,review_id,action_type,rationale,status,rule_code,system_generated) values(p_tenant,p_review,'salary_increment','All configured increment eligibility gates are satisfied; submit through the salary-adjustment approval workflow.','recommended','POLICY-INCREMENT',true); created:=created+1;
 end if;
 return jsonb_build_object('recommendations_created',created,'final_score',rev.final_score,'remark',remark,'service_months',service_months,'promotion',case when not promo_ok then 'not_eligible' when promo_manual then 'policy_review_required' else 'eligible' end,'salary_increment',case when not incr_ok then 'not_eligible' when incr_manual then 'policy_review_required' else 'eligible' end);
end $$;
grant execute on function unimis.hr_performance_evaluate_decisions(uuid,uuid) to authenticated;


-- SOURCE 202610250010_010t_employee_reporting_structure.sql
-- 010t: employee reporting structure integration for PMS
create or replace function unimis.hr_update_employee_master(
 p_tenant uuid,p_employee uuid,p_first_name text,p_last_name text,p_email text,p_phone text,
 p_date_of_birth date,p_gender text,p_marital_status text,p_nationality text,p_national_id text,p_address text,
 p_branch uuid,p_department uuid,p_position uuid,p_supervisor uuid,p_employment_type text,p_work_schedule text,p_pay_basis text,
 p_basic_salary numeric,p_salary_effective date,p_ssnit_number text,p_tax_number text,
 p_bank_name text,p_bank_branch text,p_bank_account_name text,p_bank_account_number text,
 p_payment_method text,p_momo_network text,p_momo_number text
) returns jsonb language plpgsql security definer set search_path=unimis as $$
declare old_salary numeric(14,2); active_contract uuid; old_supervisor uuid; result jsonb;
begin
 if not is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 if not exists(select 1 from hrc_hr_employees where id=p_employee and tenant_id=p_tenant) then raise exception 'Employee not found'; end if;
 if p_supervisor=p_employee then raise exception 'An employee cannot be their own supervisor'; end if;
 if p_supervisor is not null and not exists(select 1 from hrc_hr_employees where id=p_supervisor and tenant_id=p_tenant and employment_status='active') then raise exception 'Supervisor must be an active employee in this organization'; end if;
 if p_pay_basis not in ('monthly','weekly','daily','hourly') then raise exception 'Invalid pay basis'; end if;
 select supervisor_id into old_supervisor from hrc_hr_employees where id=p_employee;
 select id,basic_salary into active_contract,old_salary from hrc_hr_employment_contracts where tenant_id=p_tenant and employee_id=p_employee and status='active' order by start_date desc limit 1;
 old_salary:=coalesce((select sh.new_salary from hrc_hr_salary_history sh where sh.employee_id=p_employee and sh.effective_from<=coalesce(p_salary_effective,current_date) order by sh.effective_from desc,sh.created_at desc limit 1),old_salary,0);
 update hrc_hr_employees set first_name=p_first_name,last_name=p_last_name,email=nullif(p_email,''),phone=nullif(p_phone,''),date_of_birth=p_date_of_birth,gender=nullif(p_gender,''),marital_status=nullif(p_marital_status,''),nationality=nullif(p_nationality,''),national_id=nullif(p_national_id,''),residential_address=nullif(p_address,''),branch_id=p_branch,department_id=p_department,position_id=p_position,supervisor_id=p_supervisor,employment_type=p_employment_type,work_schedule=p_work_schedule where id=p_employee and tenant_id=p_tenant;
 if active_contract is not null then update hrc_hr_employment_contracts set contract_type=p_employment_type,pay_basis=p_pay_basis,pay_frequency=p_pay_basis where id=active_contract; end if;
 update hrc_payroll_profiles set ssnit_number=nullif(p_ssnit_number,''),tax_number=nullif(p_tax_number,''),bank_name=nullif(p_bank_name,''),bank_branch=nullif(p_bank_branch,''),bank_account_name=nullif(p_bank_account_name,''),bank_account_number=nullif(p_bank_account_number,''),payment_method=coalesce(nullif(p_payment_method,''),'bank'),momo_network=nullif(p_momo_network,''),momo_number=nullif(p_momo_number,'') where employee_id=p_employee and tenant_id=p_tenant;
 if p_basic_salary is not null and p_basic_salary<>old_salary then
   insert into hrc_hr_salary_history(tenant_id,employee_id,old_salary,new_salary,change_type,reason,effective_from,approved_by,created_by) values(p_tenant,p_employee,old_salary,p_basic_salary,case when old_salary=0 then 'initial' else 'manual' end,'Employee Master compensation update',coalesce(p_salary_effective,current_date),auth.uid(),auth.uid());
   if active_contract is not null and coalesce(p_salary_effective,current_date)<=current_date then update hrc_hr_employment_contracts set basic_salary=p_basic_salary where id=active_contract; end if;
 end if;
 insert into hrc_hr_employment_events(tenant_id,employee_id,event_type,effective_date,title,details,created_by) values(p_tenant,p_employee,'profile_update',current_date,'Employee master updated',jsonb_build_object('branch_id',p_branch,'department_id',p_department,'position_id',p_position,'supervisor_id',p_supervisor,'previous_supervisor_id',old_supervisor,'pay_basis',p_pay_basis,'salary_effective',p_salary_effective),auth.uid());
 result:=jsonb_build_object('ok',true,'old_salary',old_salary,'new_salary',p_basic_salary,'supervisor_id',p_supervisor); return result;
end $$;
grant execute on function unimis.hr_update_employee_master(uuid,uuid,text,text,text,text,date,text,text,text,text,text,uuid,uuid,uuid,uuid,text,text,text,numeric,date,text,text,text,text,text,text,text,text,text) to authenticated;


-- SOURCE 202610250730_010n_configurable_hr_setup_governance.sql
-- 010n Configurable HR setup, dynamic performance pillars, editable job architecture, policy defaults and governance support.

-- Grades are institution-managed and may be retired without deleting history.
alter table unimis.hrc_hr_job_grades add column if not exists active boolean not null default true;

-- Performance pillars are configuration data, not hard-coded application constants.
create table if not exists unimis.hrc_hr_performance_pillars(
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
 code text not null,
 name text not null,
 description text,
 display_order integer not null default 10,
 active boolean not null default true,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(tenant_id,code)
);
alter table unimis.hrc_hr_performance_pillars enable row level security;
drop policy if exists tenant_member_all on unimis.hrc_hr_performance_pillars;
create policy tenant_member_all on unimis.hrc_hr_performance_pillars for all
 using(unimis.is_tenant_member(tenant_id)) with check(unimis.is_tenant_member(tenant_id));

-- Remove the original three-value pillar checks so hrc_tenants can add their own pillars.
alter table unimis.hrc_hr_performance_metric_library drop constraint if exists hr_performance_metric_library_pillar_check;
alter table unimis.hrc_hr_performance_plan_items drop constraint if exists hr_performance_plan_items_pillar_check;

-- Starter pillars remain defaults only.
insert into unimis.hrc_hr_performance_pillars(tenant_id,code,name,description,display_order)
select t.id,v.code,v.name,v.description,v.display_order
from unimis.hrc_tenants t
cross join (values
 ('target_output','Target & Output','Quantitative targets, deliverables and measurable output.',10),
 ('responsibility_quality','Responsibilities & Quality','Role responsibilities, quality, accuracy and SOP execution.',20),
 ('professional_conduct','Professional Conduct','Attendance, collaboration, ethics and professional behaviour.',30)
) as v(code,name,description,display_order)
on conflict(tenant_id,code) do nothing;

-- Complete policy views have editable defaults in System Setup.
insert into unimis.hrc_hr_policy_configs(tenant_id,policy_type,config)
select id,'performance_policy','{"frequency":"annual","checkins_required":true,"min_checkins":2,"evidence_required":true,"employee_response":true,"supervisor_validation":true,"second_level_approval":true,"weights_must_total_100":true}'::jsonb
from unimis.hrc_tenants
on conflict(tenant_id,policy_type) do nothing;

-- Helpful indexes for the new filtered setup/governance views.
create index if not exists idx_hr_performance_pillars_tenant_active on unimis.hrc_hr_performance_pillars(tenant_id,active,display_order);
create index if not exists idx_hr_metric_library_filters on unimis.hrc_hr_performance_metric_library(tenant_id,active,industry,pillar);
create index if not exists idx_hr_leave_types_tenant_active on unimis.hrc_hr_leave_types(tenant_id,active,name);
create index if not exists idx_audit_events_tenant_created on unimis.hrc_audit_events(tenant_id,created_at desc);


-- SOURCE 202610250900_010p_pms_e2e_test_seed.sql
-- 010p PMS E2E test seed/reset
-- Purpose: preserve existing staged PMS demo records while reserving EMP004 (Kojo Owusu)
-- as a clean employee for a true UI-driven end-to-end PMS test.
-- No appraisal is pre-created for EMP004: the tester must create it through the UI.
do $$
declare
  v_tenant uuid;
  v_employee uuid;
  v_cycle uuid;
  v_review uuid;
  n integer;
begin
  select e.tenant_id into v_tenant
  from unimis.hrc_hr_employees e
  where e.employee_no in ('EMP001','EMP002','EMP003','EMP004')
  group by e.tenant_id
  having count(distinct e.employee_no)=4
  order by e.tenant_id
  limit 1;
  if v_tenant is null then
    raise exception '010p: expected EMP001-EMP004 under one demo tenant. Run the earlier demo seed migrations first.';
  end if;

  select id into v_employee from unimis.hrc_hr_employees
  where tenant_id=v_tenant and employee_no='EMP004' limit 1;
  if v_employee is null then raise exception '010p: EMP004 not found'; end if;

  -- Ensure the controlled 2026 test cycle exists and remains open.
  select id into v_cycle from unimis.hrc_hr_performance_cycles
  where tenant_id=v_tenant and name='2026 Annual Performance Review'
  order by created_at desc limit 1;
  if v_cycle is null then
    insert into unimis.hrc_hr_performance_cycles(tenant_id,name,cycle_type,start_date,end_date,status)
    values(v_tenant,'2026 Annual Performance Review','annual','2026-01-01','2026-12-31','open')
    returning id into v_cycle;
  else
    update unimis.hrc_hr_performance_cycles
    set start_date='2026-01-01',end_date='2026-12-31',status='open'
    where id=v_cycle;
  end if;

  -- Guarantee the standard editable KPI library needed for the E2E test.
  insert into unimis.hrc_hr_performance_metric_library
    (tenant_id,code,name,pillar,industry,unit,direction,description,default_target,default_weight,active)
  values
    (v_tenant,'GEN-OUTPUT','Target / Output Achievement','target_output','general','percent','higher_better','Achievement against agreed quantitative targets, deliverables or milestones.',90,20,true),
    (v_tenant,'GEN-DEADLINE','Deadline Delivery','target_output','general','percent','higher_better','Delivery of agreed work within committed timelines.',90,20,true),
    (v_tenant,'GEN-QUALITY','Work Quality & Accuracy','responsibility_quality','general','percent','higher_better','Accuracy, completeness, rework and quality of assigned responsibilities.',90,15,true),
    (v_tenant,'GEN-SOP','Responsibility / SOP Execution','responsibility_quality','general','percent','higher_better','Execution of job-description duties, procedures and controls.',90,15,true),
    (v_tenant,'GEN-ATTEND','Attendance & Punctuality','professional_conduct','general','percent','higher_better','Attendance and punctuality considered with authorised context.',95,10,true),
    (v_tenant,'GEN-TEAM','Collaboration & Communication','professional_conduct','general','score','higher_better','Teamwork, communication and constructive workplace behaviour.',4,10,true),
    (v_tenant,'GEN-CONDUCT','Professional Conduct & Ethics','professional_conduct','general','score','higher_better','Integrity, professionalism and adherence to organisational values.',4,10,true)
  on conflict(tenant_id,code) do update set
    name=excluded.name,pillar=excluded.pillar,industry=excluded.industry,unit=excluded.unit,
    direction=excluded.direction,description=excluded.description,default_target=excluded.default_target,
    default_weight=excluded.default_weight,active=true;

  -- Clean only EMP004's appraisal in this cycle so the entire workflow is tested from the UI.
  select id into v_review from unimis.hrc_hr_performance_reviews
  where tenant_id=v_tenant and employee_id=v_employee and cycle_id=v_cycle limit 1;
  if v_review is not null then
    -- Unlock only this disposable E2E record before removing it.
    update unimis.hrc_hr_performance_reviews
    set finalization_status='not_started',finalized_at=null,finalized_by=null,
        final_score=null,final_rating=null,completed_at=null,status='draft',plan_status='planning'
    where id=v_review;
    delete from unimis.hrc_hr_performance_improvement_plans where tenant_id=v_tenant and review_id=v_review;
    delete from unimis.hrc_hr_performance_reviews where tenant_id=v_tenant and id=v_review;
  end if;

  select count(*) into n from unimis.hrc_hr_performance_metric_library
  where tenant_id=v_tenant and code in ('GEN-OUTPUT','GEN-DEADLINE','GEN-QUALITY','GEN-SOP','GEN-ATTEND','GEN-TEAM','GEN-CONDUCT') and active;
  if n<>7 then raise exception '010p verification failed: expected 7 active generic PMS measures, got %',n; end if;
  if exists(select 1 from unimis.hrc_hr_performance_reviews where tenant_id=v_tenant and employee_id=v_employee and cycle_id=v_cycle) then
    raise exception '010p verification failed: EMP004 must start without a review';
  end if;
  raise notice '010p ready: EMP004 Kojo Owusu is clean for UI-driven PMS E2E testing; 2026 cycle open; 7 standard KPIs active.';
end $$;


-- SOURCE 202610251000_010v_employee_photo_reporting_fix.sql
-- 010v: reliable employee photo linkage after Storage upload.
create or replace function unimis.hr_set_employee_photo_path(p_tenant uuid,p_employee uuid,p_photo_path text)
returns jsonb language plpgsql security definer set search_path=unimis as $$
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 if not unimis.has_tenant_role(p_tenant,array['owner','administrator','hr_manager','hr_officer']) then raise exception 'HR write access required'; end if;
 if p_photo_path is null or p_photo_path='' or split_part(p_photo_path,'/',1)<>p_tenant::text then raise exception 'Invalid employee photo path'; end if;
 update unimis.hrc_hr_employees set photo_path=p_photo_path where id=p_employee and tenant_id=p_tenant;
 if not found then raise exception 'Employee not found'; end if;
 insert into unimis.hrc_audit_events(tenant_id,actor_id,module,action,record_type,record_id,details)
 values(p_tenant,auth.uid(),'hr','employee.photo.updated','hr_employee',p_employee,jsonb_build_object('photo_path',p_photo_path));
 return jsonb_build_object('ok',true,'photo_path',p_photo_path);
end $$;
grant execute on function unimis.hr_set_employee_photo_path(uuid,uuid,text) to authenticated;


-- SOURCE 202610251030_010x_kpi_applicability_filtering.sql
-- 010x: KPI applicability and role-aware PMS recommendations
alter table unimis.hrc_hr_performance_metric_library
  add column if not exists scope_level text not null default 'organization',
  add column if not exists department_id uuid references unimis.hrc_departments(id) on delete set null,
  add column if not exists position_id uuid references unimis.hrc_hr_positions(id) on delete set null;

alter table unimis.hrc_hr_performance_metric_library drop constraint if exists hr_performance_metric_library_scope_level_check;
alter table unimis.hrc_hr_performance_metric_library add constraint hr_performance_metric_library_scope_level_check
  check (scope_level in ('organization','department','position'));

create index if not exists idx_hr_perf_metric_scope on unimis.hrc_hr_performance_metric_library(tenant_id,scope_level,department_id,position_id) where active=true;

-- Existing general KPIs remain organization-wide. Sector-specific metrics stay available as overrides
-- unless HR explicitly scopes them to a department/position.
update unimis.hrc_hr_performance_metric_library
set scope_level=coalesce(scope_level,'organization')
where scope_level is null;

-- Add realistic Operations Officer KPIs for hrc_tenants that have the seeded Operations Officer position.
do $$
declare t record; d uuid; p uuid;
begin
 for t in select id from unimis.hrc_tenants loop
   select hp.id,hp.department_id into p,d from unimis.hrc_hr_positions hp
   where hp.tenant_id=t.id and lower(hp.title)='operations officer' and hp.active=true limit 1;
   if p is not null then
     insert into unimis.hrc_hr_performance_metric_library
       (tenant_id,code,name,pillar,industry,unit,direction,description,default_target,default_weight,scope_level,department_id,position_id,active)
     values
       (t.id,'OPS-TASK','Task Completion Rate','target_output','general','percent','higher_better','Percentage of assigned operational tasks completed to the agreed standard within the appraisal period.',90,30,'position',d,p,true),
       (t.id,'OPS-DEADLINE','Operational Deadline Compliance','target_output','general','percent','higher_better','Percentage of assigned operational deliverables completed by the agreed deadline.',90,20,'position',d,p,true),
       (t.id,'OPS-QUALITY','Operational Work Quality & Accuracy','responsibility_quality','general','percent','higher_better','Accuracy and completeness of operational work, with avoidable rework kept within agreed tolerance.',95,25,'position',d,p,true),
       (t.id,'OPS-SOP','SOP & Process Compliance','responsibility_quality','general','percent','higher_better','Compliance with approved operating procedures, controls and required documentation.',95,15,'position',d,p,true),
       (t.id,'OPS-CONDUCT','Operational Collaboration & Conduct','professional_conduct','general','score','higher_better','Collaboration, communication, accountability and professional conduct in operational work.',4,10,'position',d,p,true)
     on conflict(tenant_id,code) do update set
       name=excluded.name,pillar=excluded.pillar,industry=excluded.industry,unit=excluded.unit,direction=excluded.direction,
       description=excluded.description,default_target=excluded.default_target,default_weight=excluded.default_weight,
       scope_level=excluded.scope_level,department_id=excluded.department_id,position_id=excluded.position_id,active=true;
   end if;
 end loop;
end $$;


-- SOURCE 202610251040_010y_organization_industry_context.sql
-- 010y: tenant organization/industry context for PMS recommendations and host-SaaS integration
create table if not exists unimis.hrc_hr_organization_profiles (
  tenant_id uuid primary key references unimis.hrc_tenants(id) on delete cascade,
  industry text not null default 'general',
  sector_detail text,
  integration_source text not null default 'standalone',
  host_product text,
  host_tenant_reference text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint hr_organization_profiles_industry_check check (industry in ('general','education','trading','ngo','banking','healthcare','hospitality','manufacturing','professional_services','government','other')),
  constraint hr_organization_profiles_integration_check check (integration_source in ('standalone','host_saas'))
);

alter table unimis.hrc_hr_organization_profiles enable row level security;

drop policy if exists hr_organization_profiles_select on unimis.hrc_hr_organization_profiles;
create policy hr_organization_profiles_select on unimis.hrc_hr_organization_profiles
for select using (unimis.is_tenant_member(tenant_id));

drop policy if exists hr_organization_profiles_write on unimis.hrc_hr_organization_profiles;
create policy hr_organization_profiles_write on unimis.hrc_hr_organization_profiles
for all using (unimis.is_tenant_member(tenant_id)) with check (unimis.is_tenant_member(tenant_id));

insert into unimis.hrc_hr_organization_profiles(tenant_id,industry,sector_detail,integration_source)
select id,'general',null,'standalone' from unimis.hrc_tenants
on conflict (tenant_id) do nothing;

create index if not exists idx_hr_org_profile_industry on unimis.hrc_hr_organization_profiles(industry);


-- SOURCE 202610251050_010z_system_generated_codes.sql
-- 010z: Central tenant-safe automatic code generation.
-- Existing codes are preserved. New blank/null codes are generated at INSERT time.

create table if not exists unimis.hrc_hr_code_counters(
  tenant_key uuid not null,
  entity_key text not null,
  last_value bigint not null default 0,
  updated_at timestamptz not null default now(),
  primary key(tenant_key,entity_key)
);

create or replace function unimis.hr_next_code(p_tenant uuid,p_entity text,p_prefix text,p_table regclass)
returns text language plpgsql security definer set search_path=unimis as $$
declare
  k uuid:=coalesce(p_tenant,'00000000-0000-0000-0000-000000000000'::uuid);
  n bigint;
  mx bigint:=0;
begin
  perform pg_advisory_xact_lock(hashtext(k::text||':'||p_entity));
  execute format('select coalesce(max((regexp_match(code, %L))[1]::bigint),0) from %s where coalesce(tenant_id,%L::uuid)=%L::uuid and code ~ %L',
    '^'||p_prefix||'-([0-9]+)$',p_table,'00000000-0000-0000-0000-000000000000',k::text,'^'||p_prefix||'-[0-9]+$') into mx;
  insert into unimis.hrc_hr_code_counters(tenant_key,entity_key,last_value)
  values(k,p_entity,mx)
  on conflict(tenant_key,entity_key) do update set last_value=greatest(unimis.hrc_hr_code_counters.last_value,excluded.last_value),updated_at=now();
  update unimis.hrc_hr_code_counters set last_value=last_value+1,updated_at=now()
   where tenant_key=k and entity_key=p_entity returning last_value into n;
  return p_prefix||'-'||lpad(n::text,4,'0');
end $$;

create or replace function unimis.hr_autocode_row()
returns trigger language plpgsql security definer set search_path=unimis as $$
begin
  if new.code is null or btrim(new.code)='' then
    new.code:=unimis.hr_next_code(new.tenant_id,TG_TABLE_NAME,TG_ARGV[0],TG_RELID);
  end if;
  return new;
end $$;

create or replace function unimis.hr_auto_employee_no()
returns trigger language plpgsql security definer set search_path=unimis as $$
begin
  if new.employee_no is null or btrim(new.employee_no)='' then
    new.employee_no:=unimis.hr_next_code(new.tenant_id,'hrc_hr_employees','EMP',TG_RELID);
  end if;
  return new;
end $$;

create or replace function unimis.hr_auto_tenant_code()
returns trigger language plpgsql security definer set search_path=unimis as $$
declare n bigint;
begin
  if new.code is null or btrim(new.code)='' then
    perform pg_advisory_xact_lock(hashtext('tenant:auto-code'));
    select coalesce(max((regexp_match(code,'^ORG-([0-9]+)$'))[1]::bigint),0) into n from unimis.hrc_tenants where code ~ '^ORG-[0-9]+$';
    new.code:='ORG-'||lpad((n+1)::text,4,'0');
  end if;
  return new;
end $$;

drop trigger if exists trg_auto_tenant_code on unimis.hrc_tenants;
create trigger trg_auto_tenant_code before insert on unimis.hrc_tenants for each row execute function unimis.hr_auto_tenant_code();

drop trigger if exists trg_auto_employee_no on unimis.hrc_hr_employees;
create trigger trg_auto_employee_no before insert on unimis.hrc_hr_employees for each row execute function unimis.hr_auto_employee_no();

do $$
declare r record;
begin
  for r in select * from (values
    ('hrc_branches','BR'),('hrc_departments','DEP'),('hrc_hr_job_grades','GRD'),('hrc_hr_positions','POS'),
    ('hrc_hr_work_schedules','SCH'),('hrc_hr_leave_types','LVE'),('hrc_hr_performance_pillars','PIL'),
    ('hrc_hr_performance_metric_library','KPI'),('hrc_hr_performance_decision_rules','PDR'),
    ('hrc_hr_attendance_sites','SITE'),('hrc_hr_training_programs','TRN'),
    ('hrc_payroll_pay_groups','PGR'),('hrc_payroll_components','PAY'),('hrc_payroll_earning_sources','PES'),
    ('hrc_payroll_deduction_definitions','PDD'),('hrc_payroll_adjustments','ADJ'),('hrc_payroll_relief_types','RLF')
  ) as x(tbl,prefix)
  loop
    if to_regclass('unimis.'||r.tbl) is not null then
      execute format('drop trigger if exists trg_auto_code on unimis.%I',r.tbl);
      execute format('create trigger trg_auto_code before insert on unimis.%I for each row execute function unimis.hr_autocode_row(%L)',r.tbl,r.prefix);
    end if;
  end loop;
end $$;

grant execute on function unimis.hr_next_code(uuid,text,text,regclass) to authenticated;

-- Keep manually meaningful external identifiers untouched: Ghana Card, TIN, SSNIT,
-- bank/MoMo numbers, certificate numbers and bank/payment references are not internal codes.


-- SOURCE 202610251100_011c_industry_sector_master.sql
-- 011c: Editable tenant industry/sector master for organization context and PMS KPI recommendations.
-- Standard sectors are seeded per tenant; administrators can add/edit/deactivate their own sectors.

create table if not exists unimis.hrc_hr_industries (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
  code text,
  industry_key text not null,
  name text not null,
  description text,
  active boolean not null default true,
  system_default boolean not null default false,
  display_order integer not null default 100,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id,industry_key),
  unique(tenant_id,code)
);

alter table unimis.hrc_hr_industries enable row level security;
drop policy if exists hr_industries_select on unimis.hrc_hr_industries;
create policy hr_industries_select on unimis.hrc_hr_industries for select using (unimis.is_tenant_member(tenant_id));
drop policy if exists hr_industries_write on unimis.hrc_hr_industries;
create policy hr_industries_write on unimis.hrc_hr_industries for all using (unimis.is_tenant_member(tenant_id)) with check (unimis.is_tenant_member(tenant_id));

create or replace function unimis.hr_industry_prepare_row()
returns trigger language plpgsql security definer set search_path=unimis as $$
begin
  if new.code is null or btrim(new.code)='' then
    new.code:=unimis.hr_next_code(new.tenant_id,'hrc_hr_industries','IND',TG_RELID);
  end if;
  if new.industry_key is null or btrim(new.industry_key)='' then
    new.industry_key:='custom_'||replace(gen_random_uuid()::text,'-','');
  end if;
  new.name:=btrim(new.name);
  new.updated_at:=now();
  return new;
end $$;

drop trigger if exists trg_hr_industry_prepare on unimis.hrc_hr_industries;
create trigger trg_hr_industry_prepare before insert or update on unimis.hrc_hr_industries
for each row execute function unimis.hr_industry_prepare_row();

-- The old profile constraint prevented new sectors. The master now controls valid choices in the UI.
alter table unimis.hrc_hr_organization_profiles drop constraint if exists hr_organization_profiles_industry_check;

-- Normalize the one legacy label that was renamed in the expanded master.
update unimis.hrc_hr_organization_profiles set industry='financial_services',updated_at=now() where industry='banking';
update unimis.hrc_hr_performance_metric_library set industry='financial_services' where industry='banking';

insert into unimis.hrc_hr_industries(tenant_id,industry_key,name,description,system_default,display_order)
select t.id,v.industry_key,v.name,v.description,true,v.display_order
from unimis.hrc_tenants t
cross join (values
 ('general','General','General-purpose organization / uncategorized employer',10),
 ('agriculture_agribusiness','Agriculture & Agribusiness','Farming, agricultural inputs, agrochemicals, agribusiness and related services',20),
 ('manufacturing','Manufacturing & Industry','Manufacturing, processing and industrial operations',30),
 ('trading','Trading / Retail / Wholesale','Trading, retail, wholesale and distribution businesses',40),
 ('healthcare','Health','Hospitals, clinics, diagnostics and other healthcare services',50),
 ('education','Education','Schools, TVET institutions, universities and education services',60),
 ('hospitality','Hospitality','Hotels, accommodation, restaurants and hospitality services',70),
 ('financial_services','Financial Services','Banking, insurance, fintech and other financial services',80),
 ('construction','Construction & Real Estate','Construction, engineering works, property and real estate',90),
 ('transport_logistics','Transport & Logistics','Transport, warehousing, freight and logistics services',100),
 ('ict_technology','ICT / Technology','Software, telecommunications, IT and technology services',110),
 ('ngo','NGO / Non-profit','Non-governmental, charitable and non-profit organizations',120),
 ('government','Government / Public Sector','Government agencies, public institutions and state bodies',130),
 ('professional_services','Professional Services','Consulting, legal, audit, advisory and other professional services',140),
 ('energy_utilities','Energy & Utilities','Power, water, energy and utility services',150),
 ('mining_natural_resources','Mining & Natural Resources','Mining, extractives and natural-resource operations',160),
 ('other','Other','Other sector not represented by the standard classifications',999)
) as v(industry_key,name,description,display_order)
on conflict(tenant_id,industry_key) do update set
 name=excluded.name,
 description=excluded.description,
 system_default=true,
 display_order=excluded.display_order;

create index if not exists idx_hr_industries_tenant_active on unimis.hrc_hr_industries(tenant_id,active,display_order);


-- SOURCE 202610251110_011e_pms_measure_integrity.sql
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
  from unimis.hrc_hr_performance_plan_items
  where metric_id is not null
)
delete from unimis.hrc_hr_performance_plan_items p
using ranked r
where p.id=r.id and r.rn>1;

create unique index if not exists hr_perf_plan_unique_library_metric
  on unimis.hrc_hr_performance_plan_items(review_id, metric_id)
  where metric_id is not null;


-- SOURCE 202610251120_011g_pms_100pct_weight_guard.sql
-- 011h correction of 011g: enforce performance plan total weight ceiling.
-- 011g failed before application, so this intentionally replaces the same migration version.
create or replace function unimis.hr_guard_performance_plan_weight() returns trigger
language plpgsql security definer set search_path=unimis as $$
declare
  v_total numeric;
begin
  if new.weight is null or new.weight <= 0 then
    raise exception 'Performance measure weight must be greater than 0%%.';
  end if;

  select coalesce(sum(weight),0)
    into v_total
  from unimis.hrc_hr_performance_plan_items
  where tenant_id = new.tenant_id
    and review_id = new.review_id
    and id is distinct from new.id;

  if v_total + new.weight > 100.0001 then
    raise exception 'Performance plan total weight cannot exceed 100%%. Current other measures total %, attempted measure %.', v_total, new.weight;
  end if;

  return new;
end
$$;

drop trigger if exists trg_hr_performance_plan_weight_ceiling on unimis.hrc_hr_performance_plan_items;
create trigger trg_hr_performance_plan_weight_ceiling
before insert or update of weight, review_id
on unimis.hrc_hr_performance_plan_items
for each row execute function unimis.hr_guard_performance_plan_weight();




-- Refresh Supabase/PostgREST schema cache after this stage.
NOTIFY pgrst, 'reload schema';
