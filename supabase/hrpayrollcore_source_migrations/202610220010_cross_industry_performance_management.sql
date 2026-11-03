-- Package 010: Cross-industry Performance Management System (PMS)
-- Tracker + Tracer + Appraisal + Development / Decision Support

alter table public.hr_performance_policies add column if not exists target_output_weight numeric(5,2) not null default 50;
alter table public.hr_performance_policies add column if not exists responsibility_quality_weight numeric(5,2) not null default 30;
alter table public.hr_performance_policies add column if not exists professional_conduct_weight numeric(5,2) not null default 20;
alter table public.hr_performance_policies add column if not exists industry_template text not null default 'general';
alter table public.hr_performance_policies add column if not exists appraisal_frequency text not null default 'annual';
alter table public.hr_performance_policies add column if not exists enable_360 boolean not null default false;
alter table public.hr_performance_policies add column if not exists enable_continuous_checkins boolean not null default true;

alter table public.hr_performance_reviews add column if not exists target_output_score numeric(6,2);
alter table public.hr_performance_reviews add column if not exists responsibility_quality_score numeric(6,2);
alter table public.hr_performance_reviews add column if not exists professional_conduct_score numeric(6,2);
alter table public.hr_performance_reviews add column if not exists self_score numeric(6,2);
alter table public.hr_performance_reviews add column if not exists supervisor_score numeric(6,2);
alter table public.hr_performance_reviews add column if not exists trend text;
alter table public.hr_performance_reviews add column if not exists strengths text;
alter table public.hr_performance_reviews add column if not exists skill_gaps text;
alter table public.hr_performance_reviews add column if not exists recommended_action text;
alter table public.hr_performance_reviews add column if not exists approved_by uuid;
alter table public.hr_performance_reviews add column if not exists approved_at timestamptz;

create table if not exists public.hr_performance_metric_library(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.tenants(id) on delete cascade,
 code text not null, name text not null, pillar text not null check(pillar in ('target_output','responsibility_quality','professional_conduct')),
 industry text not null default 'general', unit text not null default 'score', direction text not null default 'higher_better' check(direction in ('higher_better','lower_better','milestone','pass_fail')),
 description text, default_target numeric(14,2), default_weight numeric(6,2) not null default 0, active boolean not null default true,
 created_by uuid default auth.uid(), created_at timestamptz not null default now(), unique(tenant_id,code)
);

create table if not exists public.hr_performance_plan_items(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.tenants(id) on delete cascade,
 review_id uuid not null references public.hr_performance_reviews(id) on delete cascade,
 metric_id uuid references public.hr_performance_metric_library(id) on delete set null,
 pillar text not null check(pillar in ('target_output','responsibility_quality','professional_conduct')),
 title text not null, description text, unit text not null default 'score', direction text not null default 'higher_better', target_value numeric(14,2), actual_value numeric(14,2),
 weight numeric(6,2) not null default 0, employee_score numeric(6,2), supervisor_score numeric(6,2), final_score numeric(6,2), evidence text, due_date date,
 status text not null default 'planned' check(status in ('planned','on_track','at_risk','exceeded','completed','not_met','cancelled')),
 created_by uuid default auth.uid(), created_at timestamptz not null default now()
);

create table if not exists public.hr_performance_checkins(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.tenants(id) on delete cascade,
 review_id uuid not null references public.hr_performance_reviews(id) on delete cascade,
 checkin_date date not null default current_date, progress_percent numeric(6,2), status text not null default 'on_track' check(status in ('on_track','at_risk','off_track','exceeded')),
 achievements text, blockers text, support_required text, next_actions text, manager_comments text,
 created_by uuid default auth.uid(), created_at timestamptz not null default now()
);

create table if not exists public.hr_performance_feedback(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.tenants(id) on delete cascade,
 review_id uuid not null references public.hr_performance_reviews(id) on delete cascade,
 feedback_type text not null default 'manager' check(feedback_type in ('self','manager','peer','direct_report','customer','other')),
 rater_employee_id uuid references public.hr_employees(id) on delete set null, score numeric(6,2), comments text, evidence text,
 created_by uuid default auth.uid(), created_at timestamptz not null default now()
);

create table if not exists public.hr_performance_decisions(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.tenants(id) on delete cascade,
 review_id uuid not null references public.hr_performance_reviews(id) on delete cascade,
 action_type text not null check(action_type in ('recognition','merit_bonus','salary_increment','promotion','training','mentoring','workload_realignment','pip','conduct_coaching','management_review','succession_pool','no_action','other')),
 rationale text, status text not null default 'recommended' check(status in ('recommended','approved','rejected','implemented','cancelled')),
 decision_by uuid, decision_at timestamptz, created_by uuid default auth.uid(), created_at timestamptz not null default now()
);

do $$ declare t text; begin
 foreach t in array array['hr_performance_metric_library','hr_performance_plan_items','hr_performance_checkins','hr_performance_feedback','hr_performance_decisions'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('drop policy if exists tenant_member_all on public.%I',t);
  execute format('create policy tenant_member_all on public.%I for all using (public.is_tenant_member(tenant_id)) with check (public.is_tenant_member(tenant_id))',t);
 end loop;
end $$;

create index if not exists idx_perf_metric_tenant_pillar on public.hr_performance_metric_library(tenant_id,pillar,active);
create index if not exists idx_perf_plan_review on public.hr_performance_plan_items(review_id,pillar);
create index if not exists idx_perf_checkin_review on public.hr_performance_checkins(review_id,checkin_date desc);
create index if not exists idx_perf_feedback_review on public.hr_performance_feedback(review_id,feedback_type);
create index if not exists idx_perf_decision_review on public.hr_performance_decisions(review_id,status);

-- Cross-industry starter library. These are editable templates, never hard-coded scoring rules.
do $$ declare t record; begin
 for t in select id from public.tenants loop
  insert into public.hr_performance_metric_library(tenant_id,code,name,pillar,industry,unit,direction,description,default_weight) values
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

create or replace function public.hr_performance_recalculate(p_tenant uuid,p_review uuid) returns jsonb language plpgsql security definer set search_path=public as $$
declare a numeric:=0;b numeric:=0;c numeric:=0; wa numeric:=50;wb numeric:=30;wc numeric:=20; total numeric; rating text;
begin
 if not public.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 select coalesce(target_output_weight,50),coalesce(responsibility_quality_weight,30),coalesce(professional_conduct_weight,20) into wa,wb,wc from hr_performance_policies where tenant_id=p_tenant and active order by effective_from desc limit 1;
 select coalesce(avg(final_score),0) into a from hr_performance_plan_items where tenant_id=p_tenant and review_id=p_review and pillar='target_output' and final_score is not null;
 select coalesce(avg(final_score),0) into b from hr_performance_plan_items where tenant_id=p_tenant and review_id=p_review and pillar='responsibility_quality' and final_score is not null;
 select coalesce(avg(final_score),0) into c from hr_performance_plan_items where tenant_id=p_tenant and review_id=p_review and pillar='professional_conduct' and final_score is not null;
 total:=round((a*wa+b*wb+c*wc)/100,2);
 rating:=case when total>=90 then 'Exceptional' when total>=80 then 'Exceeds Expectations' when total>=65 then 'Meets Expectations' when total>=50 then 'Needs Improvement' else 'Unsatisfactory' end;
 update hr_performance_reviews set target_output_score=a,responsibility_quality_score=b,professional_conduct_score=c,final_score=total,final_rating=rating where tenant_id=p_tenant and id=p_review;
 return jsonb_build_object('target_output',a,'responsibility_quality',b,'professional_conduct',c,'final_score',total,'rating',rating);
end $$;
grant execute on function public.hr_performance_recalculate(uuid,uuid) to authenticated;
