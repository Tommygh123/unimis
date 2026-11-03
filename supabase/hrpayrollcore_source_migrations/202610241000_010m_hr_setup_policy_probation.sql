-- 010m HR setup, policy-gated career/compensation decisions, and probation lifecycle.

create table if not exists public.hr_policy_configs(
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete cascade,
 policy_type text not null,
 config jsonb not null default '{}'::jsonb,
 updated_at timestamptz not null default now(),
 updated_by uuid default auth.uid(),
 unique(tenant_id,policy_type)
);
alter table public.hr_policy_configs enable row level security;
drop policy if exists tenant_member_all on public.hr_policy_configs;
create policy tenant_member_all on public.hr_policy_configs for all using(public.is_tenant_member(tenant_id)) with check(public.is_tenant_member(tenant_id));

create table if not exists public.hr_probation_records(
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete cascade,
 employee_id uuid not null references public.hr_employees(id) on delete cascade,
 start_date date not null,
 expected_end_date date not null,
 actual_end_date date,
 status text not null default 'active' check(status in ('active','review_due','eligible_confirmation','extended','confirmed','management_review','closed')),
 extension_months integer not null default 0,
 review_id uuid references public.hr_performance_reviews(id) on delete set null,
 final_score numeric(6,2),
 policy_result jsonb not null default '{}'::jsonb,
 notes text,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(tenant_id,employee_id,start_date)
);
alter table public.hr_probation_records enable row level security;
drop policy if exists tenant_member_all on public.hr_probation_records;
create policy tenant_member_all on public.hr_probation_records for all using(public.is_tenant_member(tenant_id)) with check(public.is_tenant_member(tenant_id));
create index if not exists idx_hr_probation_status on public.hr_probation_records(tenant_id,status,expected_end_date);

alter table public.hr_performance_reviews
 add column if not exists performance_remark text,
 add column if not exists policy_eligibility jsonb not null default '{}'::jsonb;

-- Safe defaults: performance is rated independently; promotion/increment need policy eligibility.
do $$ declare t record; begin
 for t in select id from public.tenants loop
  insert into public.hr_policy_configs(tenant_id,policy_type,config) values
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
create or replace function public.hr_create_probation_for_new_employee() returns trigger
language plpgsql security definer set search_path=public as $$
declare cfg jsonb; months integer;
begin
 select config into cfg from hr_policy_configs where tenant_id=new.tenant_id and policy_type='probation';
 if coalesce((cfg->>'enabled')::boolean,false) then
  months:=coalesce((cfg->>'default_months')::integer,6);
  insert into hr_probation_records(tenant_id,employee_id,start_date,expected_end_date,status)
  values(new.tenant_id,new.id,coalesce(new.hire_date,current_date),coalesce(new.hire_date,current_date)+(months||' months')::interval,'active')
  on conflict do nothing;
 end if;
 return new;
end $$;
drop trigger if exists trg_hr_new_employee_probation on public.hr_employees;
create trigger trg_hr_new_employee_probation after insert on public.hr_employees for each row execute function public.hr_create_probation_for_new_employee();

-- Performance result and career/compensation eligibility are deliberately separate.
-- Manual policy gates (queries, mandatory training, vacancy) prevent automatic career action until verified.
create or replace function public.hr_performance_evaluate_decisions(p_tenant uuid,p_review uuid) returns jsonb
language plpgsql security definer set search_path=public as $$
declare rev record; emp record; cfg jsonb; open_pip integer:=0; service_months integer:=0; created integer:=0;
        remark text; promo_ok boolean:=false; incr_ok boolean:=false; promo_manual boolean:=false; incr_manual boolean:=false;
begin
 if not public.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 select * into rev from hr_performance_reviews where tenant_id=p_tenant and id=p_review;
 if rev.id is null then raise exception 'Review not found'; end if;
 if rev.finalization_status<>'finalized' or rev.final_score is null then raise exception 'Finalize the appraisal before evaluating policy eligibility'; end if;
 select * into emp from hr_employees where tenant_id=p_tenant and id=rev.employee_id;
 select config into cfg from hr_policy_configs where tenant_id=p_tenant and policy_type='career_compensation';
 cfg:=coalesce(cfg,'{}'::jsonb);
 service_months:=greatest(0,(extract(year from age(current_date,coalesce(emp.hire_date,current_date)))::int*12)+extract(month from age(current_date,coalesce(emp.hire_date,current_date)))::int);
 select count(*) into open_pip from hr_performance_improvement_plans where tenant_id=p_tenant and employee_id=rev.employee_id and status in ('open','on_track','extended');
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

 update hr_performance_reviews set performance_remark=remark,policy_eligibility=jsonb_build_object(
   'performance_rating',coalesce(rev.final_rating,''),'performance_remark',remark,'service_months',service_months,
   'promotion',case when not promo_ok then 'not_eligible' when promo_manual then 'policy_review_required' else 'eligible' end,
   'promotion_manual_checks',jsonb_build_object('disciplinary_queries',coalesce((cfg->>'promotion_require_no_queries')::boolean,false),'mandatory_training',coalesce((cfg->>'promotion_require_training')::boolean,false),'vacancy',coalesce((cfg->>'promotion_require_vacancy')::boolean,false)),
   'salary_increment',case when not incr_ok then 'not_eligible' when incr_manual then 'policy_review_required' else 'eligible' end,
   'increment_manual_checks',jsonb_build_object('confirmed_appointment',coalesce((cfg->>'increment_require_confirmed')::boolean,false),'disciplinary_queries',coalesce((cfg->>'increment_require_no_queries')::boolean,false)))
 where tenant_id=p_tenant and id=p_review;

 -- Development interventions remain evidence/rule driven. Career rewards are created only when all configured gates are machine-clear.
 if rev.final_score<50 and not exists(select 1 from hr_performance_decisions where tenant_id=p_tenant and review_id=p_review and rule_code='POLICY-PIP' and status<>'cancelled') then
  insert into hr_performance_decisions(tenant_id,review_id,action_type,rationale,status,rule_code,system_generated) values(p_tenant,p_review,'pip','Final performance is below the satisfactory threshold.','recommended','POLICY-PIP',true); created:=created+1;
 elsif rev.final_score<70 and not exists(select 1 from hr_performance_decisions where tenant_id=p_tenant and review_id=p_review and rule_code='POLICY-TRAIN' and status<>'cancelled') then
  insert into hr_performance_decisions(tenant_id,review_id,action_type,rationale,status,rule_code,system_generated) values(p_tenant,p_review,'training','Performance indicates a development need; targeted training/support is recommended.','recommended','POLICY-TRAIN',true); created:=created+1;
 end if;
 if promo_ok and not promo_manual and not exists(select 1 from hr_performance_decisions where tenant_id=p_tenant and review_id=p_review and rule_code='POLICY-PROMOTION' and status<>'cancelled') then
  insert into hr_performance_decisions(tenant_id,review_id,action_type,rationale,status,rule_code,system_generated) values(p_tenant,p_review,'promotion','All configured promotion eligibility gates are satisfied; submit for authorized career approval.','recommended','POLICY-PROMOTION',true); created:=created+1;
 end if;
 if incr_ok and not incr_manual and not exists(select 1 from hr_performance_decisions where tenant_id=p_tenant and review_id=p_review and rule_code='POLICY-INCREMENT' and status<>'cancelled') then
  insert into hr_performance_decisions(tenant_id,review_id,action_type,rationale,status,rule_code,system_generated) values(p_tenant,p_review,'salary_increment','All configured increment eligibility gates are satisfied; submit through the salary-adjustment approval workflow.','recommended','POLICY-INCREMENT',true); created:=created+1;
 end if;
 return jsonb_build_object('recommendations_created',created,'final_score',rev.final_score,'remark',remark,'service_months',service_months,'promotion',case when not promo_ok then 'not_eligible' when promo_manual then 'policy_review_required' else 'eligible' end,'salary_increment',case when not incr_ok then 'not_eligible' when incr_manual then 'policy_review_required' else 'eligible' end);
end $$;
grant execute on function public.hr_performance_evaluate_decisions(uuid,uuid) to authenticated;
