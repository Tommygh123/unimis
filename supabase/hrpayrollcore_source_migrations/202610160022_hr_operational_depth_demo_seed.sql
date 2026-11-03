-- Package 006c: HR operational depth + demonstration data
-- Attendance reporting remains sourced from hr_attendance_records/capture_events.

create table if not exists public.hr_performance_policies(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.tenants(id) on delete cascade,
 name text not null, effective_from date not null default current_date, effective_to date, active boolean not null default true,
 objective_weight numeric(5,2) not null default 60, competency_weight numeric(5,2) not null default 30,
 attendance_conduct_weight numeric(5,2) not null default 10, satisfactory_score numeric(5,2) not null default 2.50,
 self_assessment text not null default 'optional' check(self_assessment in ('disabled','optional','required')),
 supervisor_required boolean not null default true, second_level_approval boolean not null default true,
 evidence_required boolean not null default true, rating_scale jsonb not null default '[{"min":4.5,"max":5,"label":"Outstanding"},{"min":3.5,"max":4.49,"label":"Exceeds Expectations"},{"min":2.5,"max":3.49,"label":"Meets Expectations"},{"min":1.5,"max":2.49,"label":"Needs Improvement"},{"min":1,"max":1.49,"label":"Unsatisfactory"}]'::jsonb,
 created_by uuid default auth.uid(), created_at timestamptz not null default now(), unique(tenant_id,name,effective_from),
 check(objective_weight+competency_weight+attendance_conduct_weight=100)
);
create table if not exists public.hr_performance_improvement_plans(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.tenants(id) on delete cascade,
 employee_id uuid not null references public.hr_employees(id) on delete cascade, review_id uuid references public.hr_performance_reviews(id) on delete set null,
 title text not null, objectives text not null, actions_support text, start_date date not null, review_date date not null,
 status text not null default 'open' check(status in ('open','on_track','extended','successfully_closed','unsuccessfully_closed')),
 outcome text, created_by uuid default auth.uid(), created_at timestamptz not null default now()
);
alter table public.hr_training_programs add column if not exists training_type text default 'professional_development';
alter table public.hr_training_programs add column if not exists purpose text;
alter table public.hr_training_programs add column if not exists objectives text;
alter table public.hr_training_programs add column if not exists delivery_mode text default 'in_person';
alter table public.hr_training_programs add column if not exists trainer text;
alter table public.hr_training_programs add column if not exists start_time time;
alter table public.hr_training_programs add column if not exists end_time time;
alter table public.hr_training_programs add column if not exists duration_hours numeric(7,2);
alter table public.hr_training_programs add column if not exists target_group text;
alter table public.hr_training_programs add column if not exists capacity integer;
alter table public.hr_training_programs add column if not exists mandatory boolean not null default false;
alter table public.hr_training_programs add column if not exists assessment_required boolean not null default false;
alter table public.hr_training_enrollments add column if not exists attendance_percent numeric(5,2);
alter table public.hr_training_enrollments add column if not exists feedback text;

do $$ declare t text; begin foreach t in array array['hr_performance_policies','hr_performance_improvement_plans'] loop execute format('alter table public.%I enable row level security',t);execute format('drop policy if exists tenant_member_all on public.%I',t);execute format('create policy tenant_member_all on public.%I for all using(public.is_tenant_member(tenant_id)) with check(public.is_tenant_member(tenant_id))',t);end loop;end $$;

-- Demonstration data: created per tenant only when enough employee records exist.
do $$
declare t record; e1 uuid; e2 uuid; e3 uuid; cyc uuid; rev uuid; prog1 uuid; prog2 uuid; s uuid;
begin
 for t in select id from public.tenants loop
  select id into e1 from public.hr_employees where tenant_id=t.id order by created_at limit 1 offset 0;
  select id into e2 from public.hr_employees where tenant_id=t.id order by created_at limit 1 offset 1;
  select id into e3 from public.hr_employees where tenant_id=t.id order by created_at limit 1 offset 2;
  if e1 is null then continue; end if;
  insert into public.hr_performance_policies(tenant_id,name,effective_from) values(t.id,'Standard Performance Policy',date_trunc('year',current_date)::date) on conflict do nothing;
  insert into public.hr_performance_cycles(tenant_id,name,cycle_type,start_date,end_date,status)
   values(t.id,'2026 Annual Performance Review','annual',date '2026-01-01',date '2026-12-31','open')
   on conflict do nothing;
  select id into cyc from public.hr_performance_cycles where tenant_id=t.id and name='2026 Annual Performance Review' limit 1;
  insert into public.hr_performance_reviews(tenant_id,cycle_id,employee_id,status,objective_score,competency_score,final_score,final_rating,reviewer_comments,development_needs,completed_at)
   values(t.id,cyc,e1,'completed',4.2,4.0,4.1,'Exceeds Expectations','Strong delivery and collaboration.','Advanced leadership and reporting skills.',now()-interval '10 days') on conflict do nothing;
  select id into rev from public.hr_performance_reviews where tenant_id=t.id and cycle_id=cyc and employee_id=e1;
  if rev is not null and not exists(select 1 from public.hr_performance_objectives where review_id=rev) then
   insert into public.hr_performance_objectives(tenant_id,review_id,title,description,weight,target,achievement,score) values
    (t.id,rev,'Service delivery','Improve turnaround time',60,'95% on-time completion','96% achieved',4.2);
   insert into public.hr_performance_competencies(tenant_id,review_id,competency,weight,score,comments) values
    (t.id,rev,'Teamwork and communication',40,4.0,'Consistently collaborates well.');
  end if;
  if e2 is not null then insert into public.hr_performance_reviews(tenant_id,cycle_id,employee_id,status,development_needs) values(t.id,cyc,e2,'submitted','Excel analytics and supervisory skills') on conflict do nothing; end if;

  insert into public.hr_training_programs(tenant_id,code,name,training_type,purpose,objectives,provider,trainer,venue,delivery_mode,start_date,end_date,start_time,end_time,duration_hours,target_group,capacity,cost,status,certificate_required,certificate_valid_months,mandatory,assessment_required)
   values(t.id,'TRN-LEAD-26','Supervisory Leadership Essentials','leadership','Prepare emerging supervisors for people-management responsibilities.','Coaching, delegation, feedback and team leadership.','Internal / External Facilitator','HR Development Facilitator','Main Training Room','in_person',current_date-20,current_date-19,'09:00','16:00',12,'Supervisors and high-potential staff',20,2500,'completed',true,24,false,true)
   on conflict(tenant_id,code) do nothing;
  select id into prog1 from public.hr_training_programs where tenant_id=t.id and code='TRN-LEAD-26';
  insert into public.hr_training_programs(tenant_id,code,name,training_type,purpose,objectives,provider,trainer,venue,delivery_mode,start_date,end_date,start_time,end_time,duration_hours,target_group,capacity,cost,status,certificate_required,mandatory,assessment_required)
   values(t.id,'TRN-SAFE-26','Workplace Safety Refresher','safety','Refresh workplace safety practices and incident prevention.','Hazard identification, reporting and emergency response.','Internal','Safety Officer','Conference Room','in_person',current_date+7,current_date+7,'09:00','13:00',4,'All staff',40,800,'planned',false,true,true)
   on conflict(tenant_id,code) do nothing;
  select id into prog2 from public.hr_training_programs where tenant_id=t.id and code='TRN-SAFE-26';
  insert into public.hr_training_enrollments(tenant_id,program_id,employee_id,source,status,result,score,attendance_percent,completion_date,certificate_no,certificate_expiry,feedback)
   values(t.id,prog1,e1,'performance','completed','Pass',86,100,current_date-19,'CERT-DEMO-001',current_date+interval '24 months','Useful practical leadership session.') on conflict do nothing;
  if e2 is not null then insert into public.hr_training_enrollments(tenant_id,program_id,employee_id,source,status) values(t.id,prog2,e2,'manager','nominated') on conflict do nothing; end if;

  select id into s from public.hr_attendance_sites where tenant_id=t.id and active order by created_at limit 1;
  -- ten-day attendance demonstration, preserving any existing real record via ON CONFLICT DO NOTHING.
  insert into public.hr_attendance_records(tenant_id,employee_id,work_date,check_in,check_out,status,capture_method,attendance_site_id,gps_verified,late_minutes,overtime_minutes,worked_minutes,approval_status,notes)
  values
   (t.id,e1,current_date-9,(current_date-9)+time '07:55',(current_date-9)+time '17:05','present','manual',s,true,0,5,550,'approved','Demo attendance'),
   (t.id,e1,current_date-8,(current_date-8)+time '08:22',(current_date-8)+time '17:00','late','manual',s,true,12,0,518,'approved','Demo late arrival'),
   (t.id,e1,current_date-7,(current_date-7)+time '07:58',(current_date-7)+time '18:10','present','manual',s,true,0,70,612,'approved','Demo overtime'),
   (t.id,e1,current_date-6,(current_date-6)+time '08:02',null,'present','manual',s,true,0,0,0,'submitted','Demo missing checkout')
  on conflict(tenant_id,employee_id,work_date) do nothing;
  if e2 is not null then
   insert into public.hr_attendance_records(tenant_id,employee_id,work_date,check_in,check_out,status,capture_method,attendance_site_id,gps_verified,late_minutes,overtime_minutes,worked_minutes,approval_status,notes) values
    (t.id,e2,current_date-9,(current_date-9)+time '08:04',(current_date-9)+time '17:03','present','manual',s,true,0,3,539,'approved','Demo attendance'),
    (t.id,e2,current_date-8,null,null,'absent','manual',s,null,0,0,0,'submitted','Demo unexplained absence'),
    (t.id,e2,current_date-7,(current_date-7)+time '08:35',(current_date-7)+time '17:00','late','manual',s,true,25,0,505,'approved','Demo late arrival')
   on conflict(tenant_id,employee_id,work_date) do nothing;
  end if;
  if e3 is not null then
   insert into public.hr_attendance_records(tenant_id,employee_id,work_date,status,capture_method,attendance_site_id,worked_minutes,approval_status,notes) values
    (t.id,e3,current_date-9,'on_leave','api',s,0,'approved','Demo approved leave'),
    (t.id,e3,current_date-8,'half_day','manual',s,240,'approved','Demo half day')
   on conflict(tenant_id,employee_id,work_date) do nothing;
  end if;
 end loop;
end $$;
create index if not exists idx_perf_policy_tenant_active on public.hr_performance_policies(tenant_id,active,effective_from desc);
create index if not exists idx_pip_tenant_employee on public.hr_performance_improvement_plans(tenant_id,employee_id,created_at desc);
