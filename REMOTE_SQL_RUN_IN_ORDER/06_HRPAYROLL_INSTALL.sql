-- CONTINUATION: UniMIS Build 172 HR/Payroll repair
set search_path=unimis,public;

-- SOURCE 202610220005_009h2_salary_adjustment_controls_and_reversal.sql
-- 009h2: salary adjustment safety controls, duplicate prevention, stale-preview protection and audited reversal.

alter table unimis.hrc_hr_salary_history
  add column if not exists source_salary_batch_id uuid references unimis.hrc_payroll_salary_change_batches(id) on delete set null;

alter table unimis.hrc_payroll_salary_change_batches
  add column if not exists reversal_reason text,
  add column if not exists reversed_by uuid references auth.users(id),
  add column if not exists reversed_at timestamptz;

alter table unimis.hrc_payroll_salary_change_batches drop constraint if exists payroll_salary_change_batches_status_check;
alter table unimis.hrc_payroll_salary_change_batches add constraint payroll_salary_change_batches_status_check
  check(status in ('draft','approved','applied','cancelled','reversed'));

create index if not exists hr_salary_history_source_batch_idx on unimis.hrc_hr_salary_history(source_salary_batch_id);

create or replace function unimis.payroll_create_scoped_salary_batch(
 p_tenant uuid,p_scope text,p_scope_value text,p_mode text,p_value numeric,p_effective date,p_reason text default null
) returns jsonb language plpgsql security definer set search_path=unimis as $$
declare b uuid; bn text; r record; oldv numeric; newv numeric; n integer:=0; lbl text; dup record;
begin
 if not unimis.has_tenant_role(p_tenant,array['owner','administrator','payroll_manager','hr_manager']) then raise exception 'Salary change access denied'; end if;
 if p_scope not in ('employee','department','position','grade','employment_type','employment_status','all') then raise exception 'Invalid salary adjustment scope'; end if;
 if p_mode not in ('percentage','fixed','set_salary') then raise exception 'Invalid salary adjustment method'; end if;
 if coalesce(p_value,0)<=0 then raise exception 'Adjustment value must be greater than zero'; end if;
 if p_effective is null then raise exception 'Effective date is required'; end if;
 if p_scope<>'all' and nullif(trim(coalesce(p_scope_value,'')),'') is null then raise exception 'Select an employee/category'; end if;

 select id,batch_no,status into dup from unimis.hrc_payroll_salary_change_batches
 where tenant_id=p_tenant and coalesce(scope_type,'all')=p_scope
   and coalesce(scope_value,'')=coalesce(p_scope_value,'')
   and change_mode=p_mode and value=p_value and effective_date=p_effective
   and status in ('draft','applied')
 order by created_at desc limit 1;
 if dup.id is not null then
   raise exception 'Possible duplicate salary adjustment: batch % is already %. Review that batch instead of creating another identical adjustment.',dup.batch_no,dup.status;
 end if;

 lbl:=case p_scope
  when 'all' then 'All active employees'
  when 'employee' then (select employee_no||' · '||first_name||' '||last_name from unimis.hrc_hr_employees where tenant_id=p_tenant and id=p_scope_value::uuid)
  when 'department' then (select name from unimis.hrc_departments where tenant_id=p_tenant and id=p_scope_value::uuid)
  when 'position' then (select title from unimis.hrc_hr_positions where tenant_id=p_tenant and id=p_scope_value::uuid)
  when 'grade' then (select code||' · '||name from unimis.hrc_hr_job_grades where tenant_id=p_tenant and id=p_scope_value::uuid)
  else initcap(replace(p_scope_value,'_',' ')) end;

 bn:='SAL-'||to_char(clock_timestamp(),'YYYYMMDDHH24MISSMS');
 insert into unimis.hrc_payroll_salary_change_batches(tenant_id,batch_no,change_mode,value,effective_date,reason,status,scope_type,scope_value,scope_label,created_by)
 values(p_tenant,bn,p_mode,p_value,p_effective,p_reason,'draft',p_scope,p_scope_value,lbl,auth.uid()) returning id into b;

 for r in
  select e.id from unimis.hrc_hr_employees e left join unimis.hrc_hr_positions pos on pos.id=e.position_id
  where e.tenant_id=p_tenant and e.employment_status='active'
   and case p_scope when 'all' then true when 'employee' then e.id=p_scope_value::uuid when 'department' then e.department_id=p_scope_value::uuid
    when 'position' then e.position_id=p_scope_value::uuid when 'grade' then pos.grade_id=p_scope_value::uuid
    when 'employment_type' then lower(coalesce(e.employment_type,''))=lower(p_scope_value)
    when 'employment_status' then lower(coalesce(e.employment_status,''))=lower(p_scope_value) else false end
 loop
  select coalesce((select sh.new_salary from unimis.hrc_hr_salary_history sh where sh.employee_id=r.id and sh.effective_from<=p_effective order by sh.effective_from desc,sh.created_at desc limit 1),(select c.basic_salary from unimis.hrc_hr_employment_contracts c where c.employee_id=r.id and c.status='active' order by c.start_date desc limit 1),0) into oldv;
  newv:=case when p_mode='percentage' then round(oldv*(1+p_value/100),2) when p_mode='fixed' then round(oldv+p_value,2) when p_mode='set_salary' then round(p_value,2) else oldv end;
  insert into unimis.hrc_payroll_salary_change_items(tenant_id,batch_id,employee_id,old_salary,new_salary) values(p_tenant,b,r.id,oldv,newv); n:=n+1;
 end loop;
 if n=0 then delete from unimis.hrc_payroll_salary_change_batches where id=b; raise exception 'No active employees matched the selected category'; end if;
 return jsonb_build_object('batch_id',b,'affected',n,'scope',p_scope,'scope_label',lbl,'batch_no',bn);
end $$;

grant execute on function unimis.payroll_create_scoped_salary_batch(uuid,text,text,text,numeric,date,text) to authenticated;

create or replace function unimis.payroll_apply_salary_batch(p_tenant uuid,p_batch uuid)
returns void language plpgsql security definer set search_path=unimis as $$
declare r record; d date; rs text; bn text; currentv numeric;
begin
 if not unimis.has_tenant_role(p_tenant,array['owner','administrator','payroll_manager']) then raise exception 'Salary approval access denied'; end if;
 select effective_date,reason,batch_no into d,rs,bn from unimis.hrc_payroll_salary_change_batches where id=p_batch and tenant_id=p_tenant and status='draft';
 if d is null then raise exception 'Draft batch not found or it has already been processed'; end if;
 for r in select * from unimis.hrc_payroll_salary_change_items where batch_id=p_batch order by employee_id loop
  select coalesce((select sh.new_salary from unimis.hrc_hr_salary_history sh where sh.employee_id=r.employee_id and sh.effective_from<=d order by sh.effective_from desc,sh.created_at desc limit 1),(select c.basic_salary from unimis.hrc_hr_employment_contracts c where c.employee_id=r.employee_id and c.status='active' order by c.start_date desc limit 1),0) into currentv;
  if round(currentv,2)<>round(r.old_salary,2) then
    raise exception 'Preview is stale for an employee: current salary is %, but this draft was prepared from %. Cancel/recreate the draft and review again.',currentv,r.old_salary;
  end if;
 end loop;
 for r in select * from unimis.hrc_payroll_salary_change_items where batch_id=p_batch loop
  insert into unimis.hrc_hr_salary_history(tenant_id,employee_id,old_salary,new_salary,change_type,reason,effective_from,approved_by,created_by,source_salary_batch_id)
  values(p_tenant,r.employee_id,r.old_salary,r.new_salary,'bulk_adjustment',rs,d,auth.uid(),auth.uid(),p_batch);
  if d<=current_date then update unimis.hrc_hr_employment_contracts set basic_salary=r.new_salary where tenant_id=p_tenant and employee_id=r.employee_id and status='active'; end if;
 end loop;
 update unimis.hrc_payroll_salary_change_batches set status='applied',approved_by=auth.uid() where id=p_batch and tenant_id=p_tenant;
end $$;
grant execute on function unimis.payroll_apply_salary_batch(uuid,uuid) to authenticated;

create or replace function unimis.payroll_cancel_salary_batch(p_tenant uuid,p_batch uuid)
returns void language plpgsql security definer set search_path=unimis as $$
begin
 if not unimis.has_tenant_role(p_tenant,array['owner','administrator','payroll_manager','hr_manager']) then raise exception 'Salary change access denied'; end if;
 update unimis.hrc_payroll_salary_change_batches set status='cancelled'
 where tenant_id=p_tenant and id=p_batch and status='draft';
 if not found then raise exception 'Only a draft salary adjustment can be cancelled'; end if;
end $$;
grant execute on function unimis.payroll_cancel_salary_batch(uuid,uuid) to authenticated;

create or replace function unimis.payroll_reverse_salary_batch(p_tenant uuid,p_batch uuid,p_reason text)
returns void language plpgsql security definer set search_path=unimis as $$
declare r record; d date; bn text; currentv numeric; revdate date:=current_date;
begin
 if not unimis.has_tenant_role(p_tenant,array['owner','administrator','payroll_manager']) then raise exception 'Salary reversal access denied'; end if;
 if nullif(trim(coalesce(p_reason,'')),'') is null then raise exception 'Enter a reversal reason / authority'; end if;
 select effective_date,batch_no into d,bn from unimis.hrc_payroll_salary_change_batches where tenant_id=p_tenant and id=p_batch and status='applied';
 if d is null then raise exception 'Only an applied salary batch can be reversed'; end if;
 for r in select * from unimis.hrc_payroll_salary_change_items where batch_id=p_batch order by employee_id loop
  select coalesce((select sh.new_salary from unimis.hrc_hr_salary_history sh where sh.employee_id=r.employee_id and sh.effective_from<=current_date order by sh.effective_from desc,sh.created_at desc limit 1),(select c.basic_salary from unimis.hrc_hr_employment_contracts c where c.employee_id=r.employee_id and c.status='active' order by c.start_date desc limit 1),0) into currentv;
  if round(currentv,2)<>round(r.new_salary,2) then
    raise exception 'Batch % cannot be reversed because a later salary change exists for an affected employee (current %, batch result %). Reverse the latest applicable change first.',bn,currentv,r.new_salary;
  end if;
 end loop;
 for r in select * from unimis.hrc_payroll_salary_change_items where batch_id=p_batch loop
  insert into unimis.hrc_hr_salary_history(tenant_id,employee_id,old_salary,new_salary,change_type,reason,effective_from,approved_by,created_by,source_salary_batch_id)
  values(p_tenant,r.employee_id,r.new_salary,r.old_salary,'salary_adjustment_reversal','Reversal of '||bn||': '||trim(p_reason),greatest(d,revdate),auth.uid(),auth.uid(),p_batch);
  if greatest(d,revdate)<=current_date then update unimis.hrc_hr_employment_contracts set basic_salary=r.old_salary where tenant_id=p_tenant and employee_id=r.employee_id and status='active'; end if;
 end loop;
 update unimis.hrc_payroll_salary_change_batches set status='reversed',reversal_reason=trim(p_reason),reversed_by=auth.uid(),reversed_at=now() where tenant_id=p_tenant and id=p_batch;
end $$;
grant execute on function unimis.payroll_reverse_salary_batch(uuid,uuid,text) to authenticated;

notify pgrst,'reload schema';


-- SOURCE 202610220010_cross_industry_performance_management.sql
-- Package 010: Cross-industry Performance Management System (PMS)
-- Tracker + Tracer + Appraisal + Development / Decision Support

alter table unimis.hrc_hr_performance_policies add column if not exists target_output_weight numeric(5,2) not null default 50;
alter table unimis.hrc_hr_performance_policies add column if not exists responsibility_quality_weight numeric(5,2) not null default 30;
alter table unimis.hrc_hr_performance_policies add column if not exists professional_conduct_weight numeric(5,2) not null default 20;
alter table unimis.hrc_hr_performance_policies add column if not exists industry_template text not null default 'general';
alter table unimis.hrc_hr_performance_policies add column if not exists appraisal_frequency text not null default 'annual';
alter table unimis.hrc_hr_performance_policies add column if not exists enable_360 boolean not null default false;
alter table unimis.hrc_hr_performance_policies add column if not exists enable_continuous_checkins boolean not null default true;

alter table unimis.hrc_hr_performance_reviews add column if not exists target_output_score numeric(6,2);
alter table unimis.hrc_hr_performance_reviews add column if not exists responsibility_quality_score numeric(6,2);
alter table unimis.hrc_hr_performance_reviews add column if not exists professional_conduct_score numeric(6,2);
alter table unimis.hrc_hr_performance_reviews add column if not exists self_score numeric(6,2);
alter table unimis.hrc_hr_performance_reviews add column if not exists supervisor_score numeric(6,2);
alter table unimis.hrc_hr_performance_reviews add column if not exists trend text;
alter table unimis.hrc_hr_performance_reviews add column if not exists strengths text;
alter table unimis.hrc_hr_performance_reviews add column if not exists skill_gaps text;
alter table unimis.hrc_hr_performance_reviews add column if not exists recommended_action text;
alter table unimis.hrc_hr_performance_reviews add column if not exists approved_by uuid;
alter table unimis.hrc_hr_performance_reviews add column if not exists approved_at timestamptz;

create table if not exists unimis.hrc_hr_performance_metric_library(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
 code text not null, name text not null, pillar text not null check(pillar in ('target_output','responsibility_quality','professional_conduct')),
 industry text not null default 'general', unit text not null default 'score', direction text not null default 'higher_better' check(direction in ('higher_better','lower_better','milestone','pass_fail')),
 description text, default_target numeric(14,2), default_weight numeric(6,2) not null default 0, active boolean not null default true,
 created_by uuid default auth.uid(), created_at timestamptz not null default now(), unique(tenant_id,code)
);

create table if not exists unimis.hrc_hr_performance_plan_items(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
 review_id uuid not null references unimis.hrc_hr_performance_reviews(id) on delete cascade,
 metric_id uuid references unimis.hrc_hr_performance_metric_library(id) on delete set null,
 pillar text not null check(pillar in ('target_output','responsibility_quality','professional_conduct')),
 title text not null, description text, unit text not null default 'score', direction text not null default 'higher_better', target_value numeric(14,2), actual_value numeric(14,2),
 weight numeric(6,2) not null default 0, employee_score numeric(6,2), supervisor_score numeric(6,2), final_score numeric(6,2), evidence text, due_date date,
 status text not null default 'planned' check(status in ('planned','on_track','at_risk','exceeded','completed','not_met','cancelled')),
 created_by uuid default auth.uid(), created_at timestamptz not null default now()
);

create table if not exists unimis.hrc_hr_performance_checkins(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
 review_id uuid not null references unimis.hrc_hr_performance_reviews(id) on delete cascade,
 checkin_date date not null default current_date, progress_percent numeric(6,2), status text not null default 'on_track' check(status in ('on_track','at_risk','off_track','exceeded')),
 achievements text, blockers text, support_required text, next_actions text, manager_comments text,
 created_by uuid default auth.uid(), created_at timestamptz not null default now()
);

create table if not exists unimis.hrc_hr_performance_feedback(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
 review_id uuid not null references unimis.hrc_hr_performance_reviews(id) on delete cascade,
 feedback_type text not null default 'manager' check(feedback_type in ('self','manager','peer','direct_report','customer','other')),
 rater_employee_id uuid references unimis.hrc_hr_employees(id) on delete set null, score numeric(6,2), comments text, evidence text,
 created_by uuid default auth.uid(), created_at timestamptz not null default now()
);

create table if not exists unimis.hrc_hr_performance_decisions(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
 review_id uuid not null references unimis.hrc_hr_performance_reviews(id) on delete cascade,
 action_type text not null check(action_type in ('recognition','merit_bonus','salary_increment','promotion','training','mentoring','workload_realignment','pip','conduct_coaching','management_review','succession_pool','no_action','other')),
 rationale text, status text not null default 'recommended' check(status in ('recommended','approved','rejected','implemented','cancelled')),
 decision_by uuid, decision_at timestamptz, created_by uuid default auth.uid(), created_at timestamptz not null default now()
);

do $$ declare t text; begin
 foreach t in array array['hrc_hr_performance_metric_library','hrc_hr_performance_plan_items','hrc_hr_performance_checkins','hrc_hr_performance_feedback','hrc_hr_performance_decisions'] loop
  execute format('alter table unimis.%I enable row level security',t);
  execute format('drop policy if exists tenant_member_all on unimis.%I',t);
  execute format('create policy tenant_member_all on unimis.%I for all using (unimis.is_tenant_member(tenant_id)) with check (unimis.is_tenant_member(tenant_id))',t);
 end loop;
end $$;

create index if not exists idx_perf_metric_tenant_pillar on unimis.hrc_hr_performance_metric_library(tenant_id,pillar,active);
create index if not exists idx_perf_plan_review on unimis.hrc_hr_performance_plan_items(review_id,pillar);
create index if not exists idx_perf_checkin_review on unimis.hrc_hr_performance_checkins(review_id,checkin_date desc);
create index if not exists idx_perf_feedback_review on unimis.hrc_hr_performance_feedback(review_id,feedback_type);
create index if not exists idx_perf_decision_review on unimis.hrc_hr_performance_decisions(review_id,status);

-- Cross-industry starter library. These are editable templates, never hard-coded scoring rules.
do $$ declare t record; begin
 for t in select id from unimis.hrc_tenants loop
  insert into unimis.hrc_hr_performance_metric_library(tenant_id,code,name,pillar,industry,unit,direction,description,default_weight) values
   (t.id,'GEN-OUTPUT','Target / Output Achievement','target_output','general','percent','higher_better','Achievement against agreed quantitative targets, deliverables or milestones.',20),
   (t.id,'GEN-DEADLINE','Deadline Delivery','target_output','general','percent','higher_better','Delivery of agreed work within committed timelines.',10),
   (t.id,'GEN-QUALITY','Work Quality & Accuracy','responsibility_quality','general','score','higher_better','Accuracy, completeness, rework and quality of assigned responsibilities.',15),
   (t.id,'GEN-SOP','Responsibility / SOP Execution','responsibility_quality','general','score','higher_better','Execution of job-description duties, procedures and controls.',15),
   (t.id,'GEN-CONDUCT','Professional Conduct & Ethics','professional_conduct','general','score','higher_better','Integrity, professionalism and adherence to organisational values.',10),
   (t.id,'GEN-TEAM','Collaboration & Communication','professional_conduct','general','score','higher_better','Teamwork, communication and constructive workplace behaviour.',5),
   (t.id,'GEN-ATTEND','Attendance & Punctuality','professional_conduct','general','percent','higher_better','Attendance and punctuality considered with authorised context.',5),
   (t.id,'EDU-RESULT','Learner / Examination Outcomes','target_output','education','percent','higher_better','Learner achievement, pass rate or agreed educational outcome.',20),
   (t.id,'TRADE-SALES','Sales / Revenue Achievement','target_output','trading','percent','higher_better','Sales, revenue, margin or collection target achievement.',25),
   (t.id,'NGO-DELIV','Programme / Donor Milestones','target_output','ngo','percent','higher_better','Delivery against project outputs, beneficiary and donor milestones.',20),
   (t.id,'BANK-COMP','Control & Compliance Quality','responsibility_quality','banking','score','higher_better','KYC, reconciliation, risk and control execution quality.',20),
   (t.id,'HEALTH-QLT','Clinical / Service Quality','responsibility_quality','healthcare','score','higher_better','Quality, documentation and protocol adherence for health services.',20),
   (t.id,'HOTEL-SVC','Guest Service Quality','responsibility_quality','hospitality','score','higher_better','Service standards, complaint resolution and guest experience.',20),
   (t.id,'MFG-YIELD','Production / Yield Achievement','target_output','manufacturing','percent','higher_better','Output, yield, waste or downtime target achievement.',20)
  on conflict(tenant_id,code) do nothing;
 end loop;
end $$;

create or replace function unimis.hr_performance_recalculate(p_tenant uuid,p_review uuid) returns jsonb language plpgsql security definer set search_path=unimis as $$
declare a numeric:=0;b numeric:=0;c numeric:=0; wa numeric:=50;wb numeric:=30;wc numeric:=20; total numeric; rating text;
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 select coalesce(target_output_weight,50),coalesce(responsibility_quality_weight,30),coalesce(professional_conduct_weight,20) into wa,wb,wc from hrc_hr_performance_policies where tenant_id=p_tenant and active order by effective_from desc limit 1;
 select coalesce(avg(final_score),0) into a from hrc_hr_performance_plan_items where tenant_id=p_tenant and review_id=p_review and pillar='target_output' and final_score is not null;
 select coalesce(avg(final_score),0) into b from hrc_hr_performance_plan_items where tenant_id=p_tenant and review_id=p_review and pillar='responsibility_quality' and final_score is not null;
 select coalesce(avg(final_score),0) into c from hrc_hr_performance_plan_items where tenant_id=p_tenant and review_id=p_review and pillar='professional_conduct' and final_score is not null;
 total:=round((a*wa+b*wb+c*wc)/100,2);
 rating:=case when total>=90 then 'Exceptional' when total>=80 then 'Exceeds Expectations' when total>=65 then 'Meets Expectations' when total>=50 then 'Needs Improvement' else 'Unsatisfactory' end;
 update hrc_hr_performance_reviews set target_output_score=a,responsibility_quality_score=b,professional_conduct_score=c,final_score=total,final_rating=rating where tenant_id=p_tenant and id=p_review;
 return jsonb_build_object('target_output',a,'responsibility_quality',b,'professional_conduct',c,'final_score',total,'rating',rating);
end $$;
grant execute on function unimis.hr_performance_recalculate(uuid,uuid) to authenticated;


-- SOURCE 202610221130_009h5_salary_reversal_constraint_fix.sql
-- HRPayrollCore 009h5
-- Permit audited salary-adjustment reversal history entries.
-- Preserves every previously allowed hrc_hr_salary_history.change_type value.

alter table unimis.hrc_hr_salary_history
  drop constraint if exists hr_salary_history_change_type_check;

alter table unimis.hrc_hr_salary_history
  add constraint hr_salary_history_change_type_check
  check (
    change_type = any (
      array[
        'initial'::text,
        'manual'::text,
        'grade_step'::text,
        'promotion'::text,
        'bulk_adjustment'::text,
        'correction'::text,
        'reversal'::text
      ]
    )
  );

notify pgrst, 'reload schema';


-- SOURCE 202610221140_009h6_exact_salary_reversal_constraint_fix.sql
-- HRPayrollCore 009h6
-- Exact compatibility fix for payroll_reverse_salary_batch().
-- The reversal RPC writes change_type = 'salary_adjustment_reversal'.

alter table unimis.hrc_hr_salary_history
  drop constraint if exists hr_salary_history_change_type_check;

alter table unimis.hrc_hr_salary_history
  add constraint hr_salary_history_change_type_check
  check (
    change_type = any (
      array[
        'initial'::text,
        'manual'::text,
        'grade_step'::text,
        'promotion'::text,
        'bulk_adjustment'::text,
        'correction'::text,
        'reversal'::text,
        'salary_adjustment_reversal'::text
      ]
    )
  );

notify pgrst, 'reload schema';


-- SOURCE 202610221230_010b_complete_pms_evaluation_workflow.sql
-- 010b Complete PMS Evaluation Workflow
-- Adds controlled plan activation and separate self/supervisor assessment evidence.

alter table unimis.hrc_hr_performance_reviews add column if not exists plan_status text not null default 'planning';
alter table unimis.hrc_hr_performance_reviews drop constraint if exists hr_performance_reviews_plan_status_check;
alter table unimis.hrc_hr_performance_reviews add constraint hr_performance_reviews_plan_status_check check(plan_status in ('planning','activated','amended','closed'));
alter table unimis.hrc_hr_performance_reviews add column if not exists plan_activated_at timestamptz;
alter table unimis.hrc_hr_performance_reviews add column if not exists self_assessment_at timestamptz;
alter table unimis.hrc_hr_performance_reviews add column if not exists supervisor_assessment_at timestamptz;

alter table unimis.hrc_hr_performance_plan_items add column if not exists self_comments text;
alter table unimis.hrc_hr_performance_plan_items add column if not exists supervisor_comments text;

-- Existing 010 plans that already contain measures remain editable until deliberately activated.
update unimis.hrc_hr_performance_reviews r
set plan_status='planning'
where plan_status is null;

-- Recalculate each pillar using the employee plan's item weights, normalized inside the pillar.
-- This lets each industry/position have a different number of measures without distorting the 50/30/20 policy weights.
create or replace function unimis.hr_performance_recalculate(p_tenant uuid,p_review uuid) returns jsonb language plpgsql security definer set search_path=unimis as $$
declare a numeric:=0;b numeric:=0;c numeric:=0; wa numeric:=50;wb numeric:=30;wc numeric:=20; total numeric; rating text;
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 select coalesce(target_output_weight,50),coalesce(responsibility_quality_weight,30),coalesce(professional_conduct_weight,20)
 into wa,wb,wc from hrc_hr_performance_policies where tenant_id=p_tenant and active order by effective_from desc limit 1;

 select coalesce(sum(final_score*greatest(weight,0))/nullif(sum(greatest(weight,0)),0),avg(final_score),0) into a
 from hrc_hr_performance_plan_items where tenant_id=p_tenant and review_id=p_review and pillar='target_output' and final_score is not null;
 select coalesce(sum(final_score*greatest(weight,0))/nullif(sum(greatest(weight,0)),0),avg(final_score),0) into b
 from hrc_hr_performance_plan_items where tenant_id=p_tenant and review_id=p_review and pillar='responsibility_quality' and final_score is not null;
 select coalesce(sum(final_score*greatest(weight,0))/nullif(sum(greatest(weight,0)),0),avg(final_score),0) into c
 from hrc_hr_performance_plan_items where tenant_id=p_tenant and review_id=p_review and pillar='professional_conduct' and final_score is not null;

 total:=round((a*wa+b*wb+c*wc)/nullif(wa+wb+wc,0),2);
 rating:=case when total>=90 then 'Exceptional' when total>=80 then 'Exceeds Expectations' when total>=65 then 'Meets Expectations' when total>=50 then 'Needs Improvement' else 'Unsatisfactory' end;
 update hrc_hr_performance_reviews set target_output_score=round(a,2),responsibility_quality_score=round(b,2),professional_conduct_score=round(c,2),supervisor_score=total,final_score=total,final_rating=rating where tenant_id=p_tenant and id=p_review;
 return jsonb_build_object('target_output',round(a,2),'responsibility_quality',round(b,2),'professional_conduct',round(c,2),'final_score',total,'rating',rating);
end $$;
grant execute on function unimis.hr_performance_recalculate(uuid,uuid) to authenticated;


-- SOURCE 202610230810_010e_pms_controlled_demo_seed.sql
-- 010e Controlled PMS demo seed
-- Reuses the existing 2026 cycle and employee records. Safe to rerun.
-- Test stages: Esi=active/check-ins, Ama=assessment, Kwame=completed/PIP.

do $$
declare
  v_tenant uuid; v_cycle uuid; v_esi uuid; v_ama uuid; v_kwame uuid;
  r_esi uuid; r_ama uuid; r_kwame uuid;
  m record;
begin
  select id into v_tenant from unimis.hrc_tenants where code='TECHCITY' limit 1;
  if v_tenant is null then raise notice '010e seed skipped: tenant TECHCITY not found'; return; end if;

  select id into v_cycle from unimis.hrc_hr_performance_cycles
   where tenant_id=v_tenant and name='2026 Annual Performance Review' order by created_at desc limit 1;
  if v_cycle is null then
    insert into unimis.hrc_hr_performance_cycles(tenant_id,name,cycle_type,start_date,end_date,status)
    values(v_tenant,'2026 Annual Performance Review','annual','2026-01-01','2026-12-31','open') returning id into v_cycle;
  else
    update unimis.hrc_hr_performance_cycles set status='open' where id=v_cycle;
  end if;

  select id into v_esi from unimis.hrc_hr_employees where tenant_id=v_tenant and employee_no='EMP003' limit 1;
  select id into v_ama from unimis.hrc_hr_employees where tenant_id=v_tenant and employee_no='EMP001' limit 1;
  select id into v_kwame from unimis.hrc_hr_employees where tenant_id=v_tenant and employee_no='EMP002' limit 1;
  if v_esi is null or v_ama is null or v_kwame is null then
    raise exception '010e seed requires EMP001 Ama, EMP002 Kwame and EMP003 Esi';
  end if;

  insert into unimis.hrc_hr_performance_reviews(tenant_id,cycle_id,employee_id,status,plan_status,plan_activated_at)
  values(v_tenant,v_cycle,v_esi,'draft','activated',now())
  on conflict(tenant_id,cycle_id,employee_id) do update set plan_status='activated',plan_activated_at=coalesce(hrc_hr_performance_reviews.plan_activated_at,now())
  returning id into r_esi;

  insert into unimis.hrc_hr_performance_reviews(tenant_id,cycle_id,employee_id,status,plan_status,plan_activated_at,self_assessment_at,supervisor_assessment_at)
  values(v_tenant,v_cycle,v_ama,'reviewed','activated',now(),now(),now())
  on conflict(tenant_id,cycle_id,employee_id) do update set status='reviewed',plan_status='activated',plan_activated_at=coalesce(hrc_hr_performance_reviews.plan_activated_at,now()),self_assessment_at=now(),supervisor_assessment_at=now()
  returning id into r_ama;

  insert into unimis.hrc_hr_performance_reviews(tenant_id,cycle_id,employee_id,status,plan_status,plan_activated_at,self_assessment_at,supervisor_assessment_at,completed_at,strengths,skill_gaps,recommended_action)
  values(v_tenant,v_cycle,v_kwame,'completed','closed',now(),now(),now(),now(),'Professional conduct, reliability and collaboration.','Target execution and work planning need improvement.','Targeted training, mentoring and a Performance Improvement Plan.')
  on conflict(tenant_id,cycle_id,employee_id) do update set status='completed',plan_status='closed',plan_activated_at=coalesce(hrc_hr_performance_reviews.plan_activated_at,now()),self_assessment_at=now(),supervisor_assessment_at=now(),completed_at=now(),strengths=excluded.strengths,skill_gaps=excluded.skill_gaps,recommended_action=excluded.recommended_action
  returning id into r_kwame;

  -- Controlled rerun: replace only demo plan/check-in/decision/PIP content for these three 2026 reviews.
  delete from unimis.hrc_hr_performance_checkins where tenant_id=v_tenant and review_id in (r_esi,r_ama,r_kwame);
  delete from unimis.hrc_hr_performance_decisions where tenant_id=v_tenant and review_id in (r_esi,r_ama,r_kwame);
  delete from unimis.hrc_hr_performance_improvement_plans where tenant_id=v_tenant and review_id in (r_esi,r_ama,r_kwame);
  delete from unimis.hrc_hr_performance_plan_items where tenant_id=v_tenant and review_id in (r_esi,r_ama,r_kwame);

  -- ESI: active baseline + check-ins; 2 target, 2 quality, 3 conduct = 100%.
  insert into unimis.hrc_hr_performance_plan_items(tenant_id,review_id,metric_id,pillar,title,description,unit,direction,target_value,actual_value,weight,due_date,status)
  select v_tenant,r_esi,id,pillar,name,description,unit,direction,
    case code when 'GEN-OUTPUT' then 90 when 'GEN-DEADLINE' then 90 when 'GEN-QUALITY' then 90 when 'GEN-SOP' then 90 when 'GEN-ATTEND' then 95 else 4 end,
    case code when 'GEN-OUTPUT' then 72 when 'GEN-DEADLINE' then 78 when 'GEN-QUALITY' then 84 when 'GEN-SOP' then 88 when 'GEN-ATTEND' then 96 when 'GEN-TEAM' then 4 else 4 end,
    case code when 'GEN-OUTPUT' then 20 when 'GEN-DEADLINE' then 20 when 'GEN-QUALITY' then 15 when 'GEN-SOP' then 15 when 'GEN-ATTEND' then 10 when 'GEN-TEAM' then 10 else 10 end,
    '2026-12-31',
    case when code in ('GEN-OUTPUT','GEN-DEADLINE') then 'on_track' else 'planned' end
  from unimis.hrc_hr_performance_metric_library where tenant_id=v_tenant and code in ('GEN-OUTPUT','GEN-DEADLINE','GEN-QUALITY','GEN-SOP','GEN-ATTEND','GEN-TEAM','GEN-CONDUCT');

  insert into unimis.hrc_hr_performance_checkins(tenant_id,review_id,checkin_date,progress_percent,status,achievements,blockers,support_required,next_actions,manager_comments) values
   (v_tenant,r_esi,'2026-04-30',32,'on_track','Core assignments delivered; attendance and teamwork strong.','Some delays obtaining source documents.','Earlier access to operational records.','Complete outstanding Q2 deliverables and document evidence.','Good start; maintain evidence for each target.'),
   (v_tenant,r_esi,'2026-07-31',58,'on_track','Quality improved and most deadlines met.','Competing operational priorities.','Priority clarification during peak periods.','Focus on target completion and reduce rework.','Progress is satisfactory with clear improvement.'),
   (v_tenant,r_esi,'2026-10-15',78,'on_track','Strong attendance, collaboration and SOP compliance.','Two deliverables remain behind schedule.','Weekly supervisor check-in until year end.','Close remaining deliverables before final appraisal.','On track overall; deadline discipline remains the key focus.');

  -- AMA: assessment-stage example with deliberate self/supervisor gap.
  insert into unimis.hrc_hr_performance_plan_items(tenant_id,review_id,metric_id,pillar,title,description,unit,direction,target_value,actual_value,weight,due_date,status,employee_score,supervisor_score,final_score,self_comments,supervisor_comments)
  select v_tenant,r_ama,id,pillar,name,description,unit,direction,
    case code when 'GEN-OUTPUT' then 90 when 'GEN-DEADLINE' then 90 when 'GEN-QUALITY' then 90 when 'GEN-SOP' then 90 when 'GEN-ATTEND' then 95 else 4 end,
    case code when 'GEN-OUTPUT' then 88 when 'GEN-DEADLINE' then 86 when 'GEN-QUALITY' then 90 when 'GEN-SOP' then 91 when 'GEN-ATTEND' then 97 when 'GEN-TEAM' then 4 else 4 end,
    case code when 'GEN-OUTPUT' then 20 when 'GEN-DEADLINE' then 20 when 'GEN-QUALITY' then 15 when 'GEN-SOP' then 15 when 'GEN-ATTEND' then 10 when 'GEN-TEAM' then 10 else 10 end,
    '2026-12-31','on_track',
    case code when 'GEN-OUTPUT' then 94 when 'GEN-DEADLINE' then 90 when 'GEN-QUALITY' then 93 when 'GEN-SOP' then 92 when 'GEN-ATTEND' then 96 when 'GEN-TEAM' then 92 else 95 end,
    case code when 'GEN-OUTPUT' then 84 when 'GEN-DEADLINE' then 82 when 'GEN-QUALITY' then 86 when 'GEN-SOP' then 85 when 'GEN-ATTEND' then 95 when 'GEN-TEAM' then 88 else 90 end,
    case code when 'GEN-OUTPUT' then 84 when 'GEN-DEADLINE' then 82 when 'GEN-QUALITY' then 86 when 'GEN-SOP' then 85 when 'GEN-ATTEND' then 95 when 'GEN-TEAM' then 88 else 90 end,
    'Employee self-assessment: strong delivery and professional contribution during the cycle.',
    'Supervisor assessment: strong overall performance; target evidence supports a slightly lower rating than the self-assessment.'
  from unimis.hrc_hr_performance_metric_library where tenant_id=v_tenant and code in ('GEN-OUTPUT','GEN-DEADLINE','GEN-QUALITY','GEN-SOP','GEN-ATTEND','GEN-TEAM','GEN-CONDUCT');

  perform unimis.hr_performance_recalculate(v_tenant,r_ama);

  -- KWAME: completed example: high professionalism but weaker output => development/PIP path.
  insert into unimis.hrc_hr_performance_plan_items(tenant_id,review_id,metric_id,pillar,title,description,unit,direction,target_value,actual_value,weight,due_date,status,employee_score,supervisor_score,final_score,self_comments,supervisor_comments)
  select v_tenant,r_kwame,id,pillar,name,description,unit,direction,
    case code when 'GEN-OUTPUT' then 90 when 'GEN-DEADLINE' then 90 when 'GEN-QUALITY' then 90 when 'GEN-SOP' then 90 when 'GEN-ATTEND' then 95 else 4 end,
    case code when 'GEN-OUTPUT' then 58 when 'GEN-DEADLINE' then 62 when 'GEN-QUALITY' then 74 when 'GEN-SOP' then 78 when 'GEN-ATTEND' then 97 when 'GEN-TEAM' then 4 else 4 end,
    case code when 'GEN-OUTPUT' then 20 when 'GEN-DEADLINE' then 20 when 'GEN-QUALITY' then 15 when 'GEN-SOP' then 15 when 'GEN-ATTEND' then 10 when 'GEN-TEAM' then 10 else 10 end,
    '2026-12-31',case when code in ('GEN-OUTPUT','GEN-DEADLINE') then 'at_risk' else 'on_track' end,
    case code when 'GEN-OUTPUT' then 70 when 'GEN-DEADLINE' then 68 when 'GEN-QUALITY' then 78 when 'GEN-SOP' then 80 when 'GEN-ATTEND' then 96 when 'GEN-TEAM' then 90 else 92 end,
    case code when 'GEN-OUTPUT' then 58 when 'GEN-DEADLINE' then 62 when 'GEN-QUALITY' then 74 when 'GEN-SOP' then 78 when 'GEN-ATTEND' then 96 when 'GEN-TEAM' then 90 else 92 end,
    case code when 'GEN-OUTPUT' then 58 when 'GEN-DEADLINE' then 62 when 'GEN-QUALITY' then 74 when 'GEN-SOP' then 78 when 'GEN-ATTEND' then 96 when 'GEN-TEAM' then 90 else 92 end,
    'Employee acknowledges target-delivery challenges but reports strong teamwork and reliability.',
    'Supervisor confirms good conduct but identifies a material output and planning gap requiring structured support.'
  from unimis.hrc_hr_performance_metric_library where tenant_id=v_tenant and code in ('GEN-OUTPUT','GEN-DEADLINE','GEN-QUALITY','GEN-SOP','GEN-ATTEND','GEN-TEAM','GEN-CONDUCT');

  perform unimis.hr_performance_recalculate(v_tenant,r_kwame);
  update unimis.hrc_hr_performance_reviews set status='completed',plan_status='closed',completed_at=now(),strengths='Professional conduct, attendance and collaboration.',skill_gaps='Target execution, prioritisation and deadline management.',recommended_action='Training + mentoring + monitored Performance Improvement Plan.' where id=r_kwame;

  insert into unimis.hrc_hr_performance_decisions(tenant_id,review_id,action_type,rationale,status) values
   (v_tenant,r_kwame,'training','Target output is below expectation while professional conduct remains strong; targeted skills development is appropriate.','approved'),
   (v_tenant,r_kwame,'mentoring','Provide structured work-planning and prioritisation support.','approved'),
   (v_tenant,r_kwame,'pip','Use measurable improvement targets and scheduled supervisor reviews.','approved');

  insert into unimis.hrc_hr_performance_improvement_plans(tenant_id,employee_id,review_id,title,objectives,actions_support,start_date,review_date,status)
  values(v_tenant,v_kwame,r_kwame,'2026 Target Delivery Improvement Plan','Improve target completion and deadline delivery to at least 80% while maintaining current professional conduct.','Weekly planning review with supervisor; prioritisation coaching; targeted training; monthly evidence-based progress review.','2026-10-23','2026-12-23','open');

  raise notice '010e PMS demo seed complete: Esi active/check-ins, Ama assessed, Kwame completed/PIP.';
end $$;


-- SOURCE 202610230845_010g_pms_verified_demo_seed_tenant_fix.sql
-- 010g PMS verified controlled demo seed fix (corrected for migration execution context)
-- Guarantees the generic metric library exists, reuses one 2026 cycle, seeds three staged reviews,
-- and aborts the migration if the expected demo state is not present.
do $$
declare
 v_tenant uuid; v_cycle uuid; v_esi uuid; v_ama uuid; v_kwame uuid;
 r_esi uuid; r_ama uuid; r_kwame uuid; n int; w numeric;
begin
 select e.tenant_id into v_tenant
 from unimis.hrc_hr_employees e
 where e.employee_no in ('EMP001','EMP002','EMP003')
 group by e.tenant_id
 having count(distinct e.employee_no)=3
 order by e.tenant_id
 limit 1;
 if v_tenant is null then raise exception '010g: could not find EMP001, EMP002 and EMP003 under one tenant'; end if;
 select id into v_esi from unimis.hrc_hr_employees where tenant_id=v_tenant and employee_no='EMP003' limit 1;
 select id into v_ama from unimis.hrc_hr_employees where tenant_id=v_tenant and employee_no='EMP001' limit 1;
 select id into v_kwame from unimis.hrc_hr_employees where tenant_id=v_tenant and employee_no='EMP002' limit 1;
 if v_esi is null or v_ama is null or v_kwame is null then raise exception '010g requires EMP001, EMP002 and EMP003'; end if;

 select id into v_cycle from unimis.hrc_hr_performance_cycles where tenant_id=v_tenant and name='2026 Annual Performance Review' order by created_at desc limit 1;
 if v_cycle is null then
  insert into unimis.hrc_hr_performance_cycles(tenant_id,name,cycle_type,start_date,end_date,status)
  values(v_tenant,'2026 Annual Performance Review','annual','2026-01-01','2026-12-31','open') returning id into v_cycle;
 else update unimis.hrc_hr_performance_cycles set status='open',start_date='2026-01-01',end_date='2026-12-31' where id=v_cycle; end if;

 -- Guarantee the seven generic metrics required by the controlled test.
 insert into unimis.hrc_hr_performance_metric_library(tenant_id,code,name,pillar,industry,unit,direction,description,default_target,default_weight,active) values
 (v_tenant,'GEN-OUTPUT','Target / Output Achievement','target_output','general','percent','higher_better','Achievement against agreed quantitative targets, deliverables or milestones.',90,20,true),
 (v_tenant,'GEN-DEADLINE','Deadline Delivery','target_output','general','percent','higher_better','Delivery of agreed work within committed timelines.',90,20,true),
 (v_tenant,'GEN-QUALITY','Work Quality & Accuracy','responsibility_quality','general','percent','higher_better','Accuracy, completeness, rework and quality of assigned responsibilities.',90,15,true),
 (v_tenant,'GEN-SOP','Responsibility / SOP Execution','responsibility_quality','general','percent','higher_better','Execution of job-description duties, procedures and controls.',90,15,true),
 (v_tenant,'GEN-ATTEND','Attendance & Punctuality','professional_conduct','general','percent','higher_better','Attendance and punctuality considered with authorised context.',95,10,true),
 (v_tenant,'GEN-TEAM','Collaboration & Communication','professional_conduct','general','score','higher_better','Teamwork, communication and constructive workplace behaviour.',4,10,true),
 (v_tenant,'GEN-CONDUCT','Professional Conduct & Ethics','professional_conduct','general','score','higher_better','Integrity, professionalism and adherence to organisational values.',4,10,true)
 on conflict(tenant_id,code) do update set name=excluded.name,pillar=excluded.pillar,industry=excluded.industry,unit=excluded.unit,direction=excluded.direction,description=excluded.description,default_target=excluded.default_target,default_weight=excluded.default_weight,active=true;

 insert into unimis.hrc_hr_performance_reviews(tenant_id,cycle_id,employee_id,status,plan_status,plan_activated_at)
 values(v_tenant,v_cycle,v_esi,'draft','activated',now()) on conflict(tenant_id,cycle_id,employee_id) do update set plan_status='activated',plan_activated_at=coalesce(unimis.hrc_hr_performance_reviews.plan_activated_at,now()) returning id into r_esi;
 insert into unimis.hrc_hr_performance_reviews(tenant_id,cycle_id,employee_id,status,plan_status,plan_activated_at,self_assessment_at,supervisor_assessment_at)
 values(v_tenant,v_cycle,v_ama,'reviewed','activated',now(),now(),now()) on conflict(tenant_id,cycle_id,employee_id) do update set status='reviewed',plan_status='activated',plan_activated_at=coalesce(unimis.hrc_hr_performance_reviews.plan_activated_at,now()),self_assessment_at=now(),supervisor_assessment_at=now() returning id into r_ama;
 insert into unimis.hrc_hr_performance_reviews(tenant_id,cycle_id,employee_id,status,plan_status,plan_activated_at,self_assessment_at,supervisor_assessment_at,completed_at,strengths,skill_gaps,recommended_action)
 values(v_tenant,v_cycle,v_kwame,'completed','closed',now(),now(),now(),now(),'Professional conduct, reliability and collaboration.','Target execution and work planning need improvement.','Training + mentoring + monitored Performance Improvement Plan.') on conflict(tenant_id,cycle_id,employee_id) do update set status='completed',plan_status='closed',completed_at=now(),strengths=excluded.strengths,skill_gaps=excluded.skill_gaps,recommended_action=excluded.recommended_action returning id into r_kwame;

 delete from unimis.hrc_hr_performance_checkins where tenant_id=v_tenant and review_id in(r_esi,r_ama,r_kwame);
 delete from unimis.hrc_hr_performance_decisions where tenant_id=v_tenant and review_id in(r_esi,r_ama,r_kwame);
 delete from unimis.hrc_hr_performance_improvement_plans where tenant_id=v_tenant and review_id in(r_esi,r_ama,r_kwame);
 delete from unimis.hrc_hr_performance_plan_items where tenant_id=v_tenant and review_id in(r_esi,r_ama,r_kwame);

 -- Esi baseline: 7 measures, total weight 100.
 insert into unimis.hrc_hr_performance_plan_items(tenant_id,review_id,metric_id,pillar,title,description,unit,direction,target_value,actual_value,weight,due_date,status)
 select v_tenant,r_esi,id,pillar,name,description,unit,direction,default_target,
 case code when 'GEN-OUTPUT' then 72 when 'GEN-DEADLINE' then 78 when 'GEN-QUALITY' then 84 when 'GEN-SOP' then 88 when 'GEN-ATTEND' then 96 else 4 end,
 default_weight,'2026-12-31',case when code in('GEN-OUTPUT','GEN-DEADLINE') then 'on_track' else 'planned' end
 from unimis.hrc_hr_performance_metric_library where tenant_id=v_tenant and code in('GEN-OUTPUT','GEN-DEADLINE','GEN-QUALITY','GEN-SOP','GEN-ATTEND','GEN-TEAM','GEN-CONDUCT');
 insert into unimis.hrc_hr_performance_checkins(tenant_id,review_id,checkin_date,progress_percent,status,achievements,blockers,support_required,next_actions,manager_comments) values
 (v_tenant,r_esi,'2026-04-30',32,'on_track','Core assignments delivered; attendance and teamwork strong.','Some delays obtaining source documents.','Earlier access to operational records.','Complete outstanding Q2 deliverables and document evidence.','Good start; maintain evidence for each target.'),
 (v_tenant,r_esi,'2026-07-31',58,'on_track','Quality improved and most deadlines met.','Competing operational priorities.','Priority clarification during peak periods.','Focus on target completion and reduce rework.','Progress is satisfactory with clear improvement.'),
 (v_tenant,r_esi,'2026-10-15',78,'on_track','Strong attendance, collaboration and SOP compliance.','Two deliverables remain behind schedule.','Weekly supervisor check-in until year end.','Close remaining deliverables before final appraisal.','On track overall; deadline discipline remains the key focus.');

 -- Ama assessment stage.
 insert into unimis.hrc_hr_performance_plan_items(tenant_id,review_id,metric_id,pillar,title,description,unit,direction,target_value,actual_value,weight,due_date,status,employee_score,supervisor_score,final_score,self_comments,supervisor_comments)
 select v_tenant,r_ama,id,pillar,name,description,unit,direction,default_target,
 case code when 'GEN-OUTPUT' then 88 when 'GEN-DEADLINE' then 86 when 'GEN-QUALITY' then 90 when 'GEN-SOP' then 91 when 'GEN-ATTEND' then 97 else 4 end,
 default_weight,'2026-12-31','on_track',
 case code when 'GEN-OUTPUT' then 94 when 'GEN-DEADLINE' then 90 when 'GEN-QUALITY' then 93 when 'GEN-SOP' then 92 when 'GEN-ATTEND' then 96 when 'GEN-TEAM' then 92 else 95 end,
 case code when 'GEN-OUTPUT' then 84 when 'GEN-DEADLINE' then 82 when 'GEN-QUALITY' then 86 when 'GEN-SOP' then 85 when 'GEN-ATTEND' then 95 when 'GEN-TEAM' then 88 else 90 end,
 case code when 'GEN-OUTPUT' then 84 when 'GEN-DEADLINE' then 82 when 'GEN-QUALITY' then 86 when 'GEN-SOP' then 85 when 'GEN-ATTEND' then 95 when 'GEN-TEAM' then 88 else 90 end,
 'Employee self-assessment: strong delivery and professional contribution.','Supervisor: strong overall performance; target evidence supports a slightly lower rating.'
 from unimis.hrc_hr_performance_metric_library where tenant_id=v_tenant and code in('GEN-OUTPUT','GEN-DEADLINE','GEN-QUALITY','GEN-SOP','GEN-ATTEND','GEN-TEAM','GEN-CONDUCT');
 -- Seed migrations run without an authenticated app user, so do not call the tenant-guarded RPC here.
 -- Calculate the same three-pillar score directly for the seeded review.
 update unimis.hrc_hr_performance_reviews r set
  target_output_score=x.a, responsibility_quality_score=x.b, professional_conduct_score=x.c,
  self_score=x.self_total, supervisor_score=x.total, final_score=x.total,
  final_rating=case when x.total>=90 then 'Exceptional' when x.total>=80 then 'Exceeds Expectations' when x.total>=65 then 'Meets Expectations' when x.total>=50 then 'Needs Improvement' else 'Unsatisfactory' end
 from (
  select
   round(coalesce(sum(final_score*weight) filter(where pillar='target_output')/nullif(sum(weight) filter(where pillar='target_output'),0),0),2) a,
   round(coalesce(sum(final_score*weight) filter(where pillar='responsibility_quality')/nullif(sum(weight) filter(where pillar='responsibility_quality'),0),0),2) b,
   round(coalesce(sum(final_score*weight) filter(where pillar='professional_conduct')/nullif(sum(weight) filter(where pillar='professional_conduct'),0),0),2) c,
   round(coalesce(sum(employee_score*weight)/nullif(sum(weight),0),0),2) self_total,
   round(coalesce(sum(final_score*weight)/nullif(sum(weight),0),0),2) total
  from unimis.hrc_hr_performance_plan_items where tenant_id=v_tenant and review_id=r_ama
 ) x where r.id=r_ama and r.tenant_id=v_tenant;

 -- Kwame completed development/PIP scenario.
 insert into unimis.hrc_hr_performance_plan_items(tenant_id,review_id,metric_id,pillar,title,description,unit,direction,target_value,actual_value,weight,due_date,status,employee_score,supervisor_score,final_score,self_comments,supervisor_comments)
 select v_tenant,r_kwame,id,pillar,name,description,unit,direction,default_target,
 case code when 'GEN-OUTPUT' then 58 when 'GEN-DEADLINE' then 62 when 'GEN-QUALITY' then 74 when 'GEN-SOP' then 78 when 'GEN-ATTEND' then 97 else 4 end,
 default_weight,'2026-12-31',case when code in('GEN-OUTPUT','GEN-DEADLINE') then 'at_risk' else 'on_track' end,
 case code when 'GEN-OUTPUT' then 70 when 'GEN-DEADLINE' then 68 when 'GEN-QUALITY' then 78 when 'GEN-SOP' then 80 when 'GEN-ATTEND' then 96 when 'GEN-TEAM' then 90 else 92 end,
 case code when 'GEN-OUTPUT' then 58 when 'GEN-DEADLINE' then 62 when 'GEN-QUALITY' then 74 when 'GEN-SOP' then 78 when 'GEN-ATTEND' then 96 when 'GEN-TEAM' then 90 else 92 end,
 case code when 'GEN-OUTPUT' then 58 when 'GEN-DEADLINE' then 62 when 'GEN-QUALITY' then 74 when 'GEN-SOP' then 78 when 'GEN-ATTEND' then 96 when 'GEN-TEAM' then 90 else 92 end,
 'Employee acknowledges target-delivery challenges but reports strong teamwork and reliability.','Supervisor confirms good conduct but identifies a material output and planning gap requiring structured support.'
 from unimis.hrc_hr_performance_metric_library where tenant_id=v_tenant and code in('GEN-OUTPUT','GEN-DEADLINE','GEN-QUALITY','GEN-SOP','GEN-ATTEND','GEN-TEAM','GEN-CONDUCT');
 -- Seed migrations run without an authenticated app user, so do not call the tenant-guarded RPC here.
 -- Calculate the same three-pillar score directly for the seeded review.
 update unimis.hrc_hr_performance_reviews r set
  target_output_score=x.a, responsibility_quality_score=x.b, professional_conduct_score=x.c,
  self_score=x.self_total, supervisor_score=x.total, final_score=x.total,
  final_rating=case when x.total>=90 then 'Exceptional' when x.total>=80 then 'Exceeds Expectations' when x.total>=65 then 'Meets Expectations' when x.total>=50 then 'Needs Improvement' else 'Unsatisfactory' end
 from (
  select
   round(coalesce(sum(final_score*weight) filter(where pillar='target_output')/nullif(sum(weight) filter(where pillar='target_output'),0),0),2) a,
   round(coalesce(sum(final_score*weight) filter(where pillar='responsibility_quality')/nullif(sum(weight) filter(where pillar='responsibility_quality'),0),0),2) b,
   round(coalesce(sum(final_score*weight) filter(where pillar='professional_conduct')/nullif(sum(weight) filter(where pillar='professional_conduct'),0),0),2) c,
   round(coalesce(sum(employee_score*weight)/nullif(sum(weight),0),0),2) self_total,
   round(coalesce(sum(final_score*weight)/nullif(sum(weight),0),0),2) total
  from unimis.hrc_hr_performance_plan_items where tenant_id=v_tenant and review_id=r_kwame
 ) x where r.id=r_kwame and r.tenant_id=v_tenant;
 update unimis.hrc_hr_performance_reviews set status='completed',plan_status='closed',completed_at=now() where id=r_kwame;
 insert into unimis.hrc_hr_performance_decisions(tenant_id,review_id,action_type,rationale,status) values
 (v_tenant,r_kwame,'training','Output is below expectation while conduct remains strong; targeted development is appropriate.','approved'),
 (v_tenant,r_kwame,'mentoring','Provide structured work-planning and prioritisation support.','approved'),
 (v_tenant,r_kwame,'pip','Use measurable improvement targets and scheduled supervisor reviews.','approved');
 insert into unimis.hrc_hr_performance_improvement_plans(tenant_id,employee_id,review_id,title,objectives,actions_support,start_date,review_date,status)
 values(v_tenant,v_kwame,r_kwame,'2026 Target Delivery Improvement Plan','Improve target completion and deadline delivery to at least 80% while maintaining professional conduct.','Weekly supervisor planning review; prioritisation coaching; targeted training; monthly evidence-based progress review.','2026-10-23','2026-12-23','open');

 -- Self-verification. Any mismatch aborts the migration rather than reporting false success.
 select count(*),coalesce(sum(weight),0) into n,w from unimis.hrc_hr_performance_plan_items where review_id=r_esi;
 if n<>7 or w<>100 then raise exception '010g verification failed for Esi: expected 7 measures / 100 weight, got % / %',n,w; end if;
 select count(*) into n from unimis.hrc_hr_performance_checkins where review_id=r_esi; if n<>3 then raise exception '010g verification failed for Esi check-ins: expected 3, got %',n; end if;
 select count(*) into n from unimis.hrc_hr_performance_plan_items where review_id=r_ama and employee_score is not null and supervisor_score is not null; if n<>7 then raise exception '010g verification failed for Ama assessments: expected 7, got %',n; end if;
 select count(*) into n from unimis.hrc_hr_performance_plan_items where review_id=r_kwame and final_score is not null; if n<>7 then raise exception '010g verification failed for Kwame scorecard: expected 7, got %',n; end if;
 select count(*) into n from unimis.hrc_hr_performance_decisions where review_id=r_kwame; if n<>3 then raise exception '010g verification failed for Kwame decisions: expected 3, got %',n; end if;
 select count(*) into n from unimis.hrc_hr_performance_improvement_plans where review_id=r_kwame and status='open'; if n<>1 then raise exception '010g verification failed for Kwame PIP: expected 1 open PIP, got %',n; end if;
 raise notice '010g verified: Esi 7/100 + 3 check-ins; Ama 7 assessed; Kwame 7 completed + 3 decisions + PIP.';
end $$;


-- SOURCE 202610230930_010h_pms_finalization_lifecycle.sql
-- 010h PMS lifecycle: provisional scoring is distinct from approved/finalized results.
-- Existing historical completed appraisals are preserved as finalized. The controlled 2026 demo
-- reviews for Ama/Kwame are returned to pre-final state so the remaining workflow can be tested.

alter table unimis.hrc_hr_performance_reviews
  add column if not exists provisional_score numeric(6,2),
  add column if not exists provisional_rating text,
  add column if not exists finalization_status text not null default 'not_started',
  add column if not exists finalized_at timestamptz,
  add column if not exists finalized_by uuid;

do $$ begin
  if not exists(select 1 from pg_constraint where conname='hr_performance_reviews_finalization_status_check') then
    alter table unimis.hrc_hr_performance_reviews add constraint hr_performance_reviews_finalization_status_check
      check(finalization_status in ('not_started','pending_approval','finalized'));
  end if;
end $$;

-- Preserve genuinely completed historical records as finalized before changing calculation semantics.
update unimis.hrc_hr_performance_reviews
set provisional_score=coalesce(provisional_score,final_score),
    provisional_rating=coalesce(provisional_rating,final_rating),
    finalization_status='finalized',
    finalized_at=coalesce(finalized_at,completed_at,now())
where status='completed' and finalization_status<>'finalized';

-- Reviewed records may already contain a calculated score from the old engine. It is provisional.
update unimis.hrc_hr_performance_reviews
set provisional_score=coalesce(provisional_score,final_score),
    provisional_rating=coalesce(provisional_rating,final_rating),
    final_score=null,
    final_rating=null,
    finalization_status='not_started',
    finalized_at=null,
    finalized_by=null
where status<>'completed';

-- The controlled 2026 Kwame demo was marked completed only to demonstrate downstream data.
-- Return it to supervisor-reviewed state so final approval can be tested properly.
update unimis.hrc_hr_performance_reviews r
set status='reviewed', plan_status='activated', completed_at=null,
    provisional_score=coalesce(r.provisional_score,r.final_score),
    provisional_rating=coalesce(r.provisional_rating,r.final_rating),
    final_score=null, final_rating=null, finalization_status='not_started', finalized_at=null, finalized_by=null
from unimis.hrc_hr_employees e, unimis.hrc_hr_performance_cycles c, unimis.hrc_tenants t
where r.employee_id=e.id and r.cycle_id=c.id and r.tenant_id=t.id
  and e.employee_no='EMP002' and c.name='2026 Annual Performance Review' and t.code='TCC001';

create or replace function unimis.hr_performance_recalculate(p_tenant uuid,p_review uuid) returns jsonb language plpgsql security definer set search_path=unimis as $$
declare a numeric:=0;b numeric:=0;c numeric:=0; wa numeric:=50;wb numeric:=30;wc numeric:=20; total numeric; rating text; fin text;
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 select finalization_status into fin from hrc_hr_performance_reviews where tenant_id=p_tenant and id=p_review;
 if fin='finalized' then raise exception 'Finalized appraisal is locked'; end if;
 select coalesce(target_output_weight,50),coalesce(responsibility_quality_weight,30),coalesce(professional_conduct_weight,20)
 into wa,wb,wc from hrc_hr_performance_policies where tenant_id=p_tenant and active order by effective_from desc limit 1;

 select coalesce(sum(final_score*greatest(weight,0))/nullif(sum(greatest(weight,0)),0),avg(final_score),0) into a
 from hrc_hr_performance_plan_items where tenant_id=p_tenant and review_id=p_review and pillar='target_output' and final_score is not null;
 select coalesce(sum(final_score*greatest(weight,0))/nullif(sum(greatest(weight,0)),0),avg(final_score),0) into b
 from hrc_hr_performance_plan_items where tenant_id=p_tenant and review_id=p_review and pillar='responsibility_quality' and final_score is not null;
 select coalesce(sum(final_score*greatest(weight,0))/nullif(sum(greatest(weight,0)),0),avg(final_score),0) into c
 from hrc_hr_performance_plan_items where tenant_id=p_tenant and review_id=p_review and pillar='professional_conduct' and final_score is not null;

 total:=round((a*wa+b*wb+c*wc)/nullif(wa+wb+wc,0),2);
 rating:=case when total>=90 then 'Exceptional' when total>=80 then 'Exceeds Expectations' when total>=65 then 'Meets Expectations' when total>=50 then 'Needs Improvement' else 'Unsatisfactory' end;
 update hrc_hr_performance_reviews set target_output_score=round(a,2),responsibility_quality_score=round(b,2),professional_conduct_score=round(c,2),supervisor_score=total,provisional_score=total,provisional_rating=rating,final_score=null,final_rating=null where tenant_id=p_tenant and id=p_review;
 return jsonb_build_object('target_output',round(a,2),'responsibility_quality',round(b,2),'professional_conduct',round(c,2),'provisional_score',total,'provisional_rating',rating);
end $$;

-- Database guard: finalized plan items cannot be silently changed or removed.
create or replace function unimis.hr_performance_guard_finalized_item() returns trigger language plpgsql set search_path=unimis as $$
declare rid uuid; fin text;
begin
 rid:=coalesce(new.review_id,old.review_id);
 select finalization_status into fin from hrc_hr_performance_reviews where id=rid;
 if fin='finalized' then raise exception 'Finalized appraisal is locked; use a controlled amendment workflow'; end if;
 return coalesce(new,old);
end $$;

drop trigger if exists trg_hr_performance_guard_finalized_item on unimis.hrc_hr_performance_plan_items;
create trigger trg_hr_performance_guard_finalized_item before update or delete on unimis.hrc_hr_performance_plan_items
for each row execute function unimis.hr_performance_guard_finalized_item();


-- SOURCE 202610231120_010j_pms_checkin_evidence.sql
-- 010j: strengthen performance check-ins with explicit actual-result and evidence capture.
-- Existing check-ins remain valid; new fields are nullable for backward compatibility.
alter table unimis.hrc_hr_performance_checkins
  add column if not exists actual_progress text,
  add column if not exists evidence text;

comment on column unimis.hrc_hr_performance_checkins.actual_progress is
  'Narrative of actual results/progress achieved against the agreed performance baseline at this check-in.';
comment on column unimis.hrc_hr_performance_checkins.evidence is
  'Evidence supporting the check-in, e.g. reports, records, links, observations, feedback or document references.';




-- Refresh Supabase/PostgREST schema cache after this stage.
NOTIFY pgrst, 'reload schema';
