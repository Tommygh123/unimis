-- CONTINUATION: UniMIS Build 172 HR/Payroll repair
set search_path=unimis,public;

-- SOURCE 202610140007_lean_recruitment_documents.sql
-- Package 003a: Lean recruitment funnel, progressive documents and retention-ready hiring.
-- Large applicant pools keep only light application data/CV; supporting evidence is requested only after selection.

alter table unimis.hrc_hr_applicants
  add column if not exists highest_qualification text,
  add column if not exists years_experience numeric(5,1),
  add column if not exists key_skills text,
  add column if not exists screening_score numeric(5,2),
  add column if not exists screening_notes text,
  add column if not exists selected_at timestamptz,
  add column if not exists retention_until date;

alter table unimis.hrc_hr_applicants drop constraint if exists hr_applicants_status_check;
alter table unimis.hrc_hr_applicants add constraint hr_applicants_status_check check(status in
 ('applied','shortlisted','interviewed','rejected','selected','documents_pending','documents_verified','offered','offer_accepted','offer_declined','hired','withdrawn'));

alter table unimis.hrc_hr_vacancies
  add column if not exists cv_required boolean not null default true,
  add column if not exists supporting_documents jsonb not null default '["National ID / Ghana Card","Academic certificate"]'::jsonb;

create table if not exists unimis.hrc_hr_applicant_documents(
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
 applicant_id uuid not null references unimis.hrc_hr_applicants(id) on delete cascade,
 document_type text not null,
 title text not null,
 file_path text not null,
 stage text not null default 'application' check(stage in ('application','selected')),
 review_status text not null default 'pending' check(review_status in ('pending','verified','rejected','clarification')),
 review_notes text,
 reviewed_by uuid references auth.users(id), reviewed_at timestamptz,
 transferred_employee_id uuid references unimis.hrc_hr_employees(id) on delete set null,
 created_at timestamptz not null default now()
);

create table if not exists unimis.hrc_hr_recruitment_settings(
 tenant_id uuid primary key references unimis.hrc_tenants(id) on delete cascade,
 unsuccessful_retention_months integer not null default 12 check(unsuccessful_retention_months between 1 and 120),
 cv_retention_months integer not null default 6 check(cv_retention_months between 1 and 120),
 require_verified_documents_before_offer boolean not null default true,
 updated_at timestamptz not null default now()
);

insert into unimis.hrc_hr_recruitment_settings(tenant_id)
select id from unimis.hrc_tenants on conflict(tenant_id) do nothing;

alter table unimis.hrc_hr_applicant_documents enable row level security;
alter table unimis.hrc_hr_recruitment_settings enable row level security;

drop policy if exists hr_applicant_documents_read on unimis.hrc_hr_applicant_documents;
create policy hr_applicant_documents_read on unimis.hrc_hr_applicant_documents for select
 using(unimis.is_tenant_member(tenant_id));
drop policy if exists hr_applicant_documents_insert on unimis.hrc_hr_applicant_documents;
create policy hr_applicant_documents_insert on unimis.hrc_hr_applicant_documents for insert
 with check(unimis.has_tenant_role(tenant_id,array['owner','administrator','hr_manager','hr_officer']));
drop policy if exists hr_applicant_documents_update on unimis.hrc_hr_applicant_documents;
create policy hr_applicant_documents_update on unimis.hrc_hr_applicant_documents for update
 using(unimis.has_tenant_role(tenant_id,array['owner','administrator','hr_manager','hr_officer']))
 with check(unimis.has_tenant_role(tenant_id,array['owner','administrator','hr_manager','hr_officer']));
drop policy if exists hr_applicant_documents_delete on unimis.hrc_hr_applicant_documents;
create policy hr_applicant_documents_delete on unimis.hrc_hr_applicant_documents for delete
 using(unimis.has_tenant_role(tenant_id,array['owner','administrator','hr_manager']));

drop policy if exists hr_recruitment_settings_read on unimis.hrc_hr_recruitment_settings;
create policy hr_recruitment_settings_read on unimis.hrc_hr_recruitment_settings for select using(unimis.is_tenant_member(tenant_id));
drop policy if exists hr_recruitment_settings_write on unimis.hrc_hr_recruitment_settings;
create policy hr_recruitment_settings_write on unimis.hrc_hr_recruitment_settings for all
 using(unimis.has_tenant_role(tenant_id,array['owner','administrator','hr_manager']))
 with check(unimis.has_tenant_role(tenant_id,array['owner','administrator','hr_manager']));

create index if not exists hr_applicant_documents_applicant_idx on unimis.hrc_hr_applicant_documents(applicant_id,stage,review_status);

-- Replace Package 003 hire RPC. No storage object is copied: verified recruitment documents are linked
-- into the employee document register using the same private employee-documents object path.
create or replace function unimis.hr_hire_applicant(p_tenant uuid,p_applicant uuid,p_employee_no text,p_hire_date date,p_basic_salary numeric default 0)
returns uuid language plpgsql security definer set search_path=unimis as $$
declare a unimis.hrc_hr_applicants%rowtype; v unimis.hrc_hr_vacancies%rowtype; e uuid;
begin
 if not unimis.has_tenant_role(p_tenant,array['owner','administrator','hr_manager']) then raise exception 'Hiring access denied'; end if;
 select * into a from unimis.hrc_hr_applicants where id=p_applicant and tenant_id=p_tenant for update;
 if a.id is null then raise exception 'Applicant not found'; end if;
 if a.status <> 'offer_accepted' then raise exception 'Offer must be accepted before hiring'; end if;
 if a.employee_id is not null then raise exception 'Applicant is already linked to an employee'; end if;
 if a.vacancy_id is not null then select * into v from unimis.hrc_hr_vacancies where id=a.vacancy_id and tenant_id=p_tenant; end if;
 e:=unimis.hr_create_employee(p_tenant,p_employee_no,a.first_name,a.last_name,coalesce(a.email,''),v.department_id,v.position_id,a.date_of_birth,p_hire_date,coalesce(p_basic_salary,0),coalesce(v.employment_type,'regular'),'full_time','monthly',null,'applicable');
 update unimis.hrc_hr_employees set phone=coalesce(a.phone,phone) where id=e;
 -- Reuse the exact same private storage object; only create an Employee Master metadata reference.
 insert into unimis.hrc_hr_employee_documents(tenant_id,employee_id,document_type,title,file_path,notes,uploaded_by)
 select d.tenant_id,e,d.document_type,d.title,d.file_path,'Transferred from recruitment without duplicating storage',auth.uid()
 from unimis.hrc_hr_applicant_documents d
 where d.applicant_id=a.id and d.tenant_id=p_tenant and d.review_status='verified';
 update unimis.hrc_hr_applicant_documents set transferred_employee_id=e where applicant_id=a.id and tenant_id=p_tenant and review_status='verified';
 update unimis.hrc_hr_applicants set status='hired',employee_id=e,updated_at=now() where id=a.id;
 perform unimis.hr_record_employment_event(p_tenant,e,'recruitment_hire',p_hire_date,'Hired from recruitment',jsonb_build_object('applicant_id',a.id,'vacancy_id',a.vacancy_id));
 return e;
end $$;
grant execute on function unimis.hr_hire_applicant(uuid,uuid,text,date,numeric) to authenticated;

notify pgrst, 'reload schema';

create or replace function unimis.hr_set_applicant_retention() returns trigger language plpgsql set search_path=unimis as $$
declare m integer;
begin
 if new.status in ('rejected','withdrawn','offer_declined') and (old.status is distinct from new.status or new.retention_until is null) then
   select unsuccessful_retention_months into m from unimis.hrc_hr_recruitment_settings where tenant_id=new.tenant_id;
   new.retention_until := current_date + make_interval(months=>coalesce(m,12));
 end if;
 return new;
end $$;
drop trigger if exists hr_applicant_retention_trigger on unimis.hrc_hr_applicants;
create trigger hr_applicant_retention_trigger before update on unimis.hrc_hr_applicants for each row execute function unimis.hr_set_applicant_retention();

notify pgrst, 'reload schema';


-- SOURCE 202610140008_vacancy_details_publishing.sql
-- Package 003b: richer vacancy specification and controlled publishing workflow.
alter table unimis.hrc_hr_vacancies add column if not exists responsibilities text;
alter table unimis.hrc_hr_vacancies add column if not exists experience_required text;
alter table unimis.hrc_hr_vacancies add column if not exists conditions_text text;
alter table unimis.hrc_hr_vacancies add column if not exists location_text text;
alter table unimis.hrc_hr_vacancies add column if not exists work_arrangement text not null default 'on_site';
alter table unimis.hrc_hr_vacancies add column if not exists cv_required boolean not null default true;
alter table unimis.hrc_hr_vacancies add column if not exists published_at timestamptz;
alter table unimis.hrc_hr_vacancies add column if not exists approved_at timestamptz;
alter table unimis.hrc_hr_vacancies add column if not exists approved_by uuid references auth.users(id) on delete set null;

update unimis.hrc_hr_vacancies set status='published',published_at=coalesce(published_at,created_at) where status='open';

alter table unimis.hrc_hr_vacancies drop constraint if exists hr_vacancies_status_check;
alter table unimis.hrc_hr_vacancies add constraint hr_vacancies_status_check check(status in ('draft','pending_approval','approved','published','closed','cancelled'));
alter table unimis.hrc_hr_vacancies drop constraint if exists hr_vacancies_work_arrangement_check;
alter table unimis.hrc_hr_vacancies add constraint hr_vacancies_work_arrangement_check check(work_arrangement in ('on_site','hybrid','remote'));

create index if not exists hr_vacancies_public_idx on unimis.hrc_hr_vacancies(tenant_id,status,closing_date);

-- Keep approval metadata when an authorised HR user moves a vacancy through review.
create or replace function unimis.hr_set_vacancy_status(p_tenant uuid,p_vacancy uuid,p_status text)
returns unimis.hrc_hr_vacancies language plpgsql security definer set search_path=unimis as $$
declare v unimis.hrc_hr_vacancies;
begin
 if not unimis.has_tenant_role(p_tenant,array['owner','administrator','hr_manager','hr_officer']) then raise exception 'Vacancy workflow access denied'; end if;
 if p_status not in ('draft','pending_approval','approved','published','closed','cancelled') then raise exception 'Invalid vacancy status'; end if;
 select * into v from unimis.hrc_hr_vacancies where id=p_vacancy and tenant_id=p_tenant for update;
 if v.id is null then raise exception 'Vacancy not found'; end if;
 if p_status='approved' and not unimis.has_tenant_role(p_tenant,array['owner','administrator','hr_manager']) then raise exception 'Approval access denied'; end if;
 update unimis.hrc_hr_vacancies set status=p_status,
   approved_at=case when p_status='approved' then now() else approved_at end,
   approved_by=case when p_status='approved' then auth.uid() else approved_by end,
   published_at=case when p_status='published' then now() else published_at end
 where id=p_vacancy returning * into v;
 return v;
end $$;
grant execute on function unimis.hr_set_vacancy_status(uuid,uuid,text) to authenticated;
notify pgrst, 'reload schema';


-- SOURCE 202610140009_vacancy_edit_recruitment_seed.sql
-- Package 003f: recruitment test seed helper. Production data is untouched.
create or replace function unimis.seed_recruitment_test(p_tenant uuid)
returns jsonb language plpgsql security definer set search_path=unimis as $$
declare
  v_vacancy uuid; v_title text; a1 uuid; a2 uuid; a3 uuid; a4 uuid; a5 uuid;
begin
  if not unimis.has_tenant_role(p_tenant,array['owner','administrator','hr_manager','hr_officer']) then
    raise exception 'Recruitment seed access denied';
  end if;

  select id,title into v_vacancy,v_title from unimis.hrc_hr_vacancies
   where tenant_id=p_tenant and status='published'
   order by published_at desc nulls last, created_at desc limit 1;
  if v_vacancy is null then
    raise exception 'Publish at least one vacancy before loading the recruitment test seed';
  end if;

  -- Idempotent demo seed: remove only our known, non-hired test candidates.
  delete from unimis.hrc_hr_applicants
   where tenant_id=p_tenant and email like 'recruit.test.%@hrpayrollcore.local' and status <> 'hired';

  insert into unimis.hrc_hr_applicants(tenant_id,vacancy_id,first_name,last_name,email,phone,date_of_birth,source,status,highest_qualification,years_experience,key_skills,screening_score,screening_notes)
  values(p_tenant,v_vacancy,'Adwoa','Owusu','recruit.test.1@hrpayrollcore.local','0240001001','1995-04-12','Seed test','applied','BSc Business Administration',3,'Administration, records, Microsoft Office',72,'Meets basic requirements') returning id into a1;

  insert into unimis.hrc_hr_applicants(tenant_id,vacancy_id,first_name,last_name,email,phone,date_of_birth,source,status,highest_qualification,years_experience,key_skills,screening_score,screening_notes)
  values(p_tenant,v_vacancy,'Kofi','Boateng','recruit.test.2@hrpayrollcore.local','0240001002','1992-09-21','Seed test','shortlisted','HND Accounting',5,'Accounting, Excel, reconciliation',84,'Strong relevant experience') returning id into a2;

  insert into unimis.hrc_hr_applicants(tenant_id,vacancy_id,first_name,last_name,email,phone,date_of_birth,source,status,highest_qualification,years_experience,key_skills,screening_score,screening_notes)
  values(p_tenant,v_vacancy,'Akosua','Mensimah','recruit.test.3@hrpayrollcore.local','0240001003','1997-01-08','Seed test','shortlisted','BCom',2,'Customer service, reporting, Excel',80,'Suitable for interview') returning id into a3;

  insert into unimis.hrc_hr_applicants(tenant_id,vacancy_id,first_name,last_name,email,phone,date_of_birth,source,status,highest_qualification,years_experience,key_skills,screening_score,screening_notes)
  values(p_tenant,v_vacancy,'Yaw','Asante','recruit.test.4@hrpayrollcore.local','0240001004','1993-07-15','Seed test','interviewed','BSc Accounting',6,'Accounting, ERP, reporting',91,'Interview completed; strong recommendation') returning id into a4;
  insert into unimis.hrc_hr_interviews(tenant_id,applicant_id,interview_at,interview_type,panel_notes,score,recommendation,created_by)
  values(p_tenant,a4,now()-interval '1 day','in_person','Clear communication and strong practical examples.',88,'Recommended for selection',auth.uid());

  insert into unimis.hrc_hr_applicants(tenant_id,vacancy_id,first_name,last_name,email,phone,date_of_birth,source,status,highest_qualification,years_experience,key_skills,screening_score,screening_notes,selected_at)
  values(p_tenant,v_vacancy,'Esi','Agyeman','recruit.test.5@hrpayrollcore.local','0240001005','1991-11-30','Seed test','offer_accepted','BSc Accounting',7,'Accounting, payroll, ERP, supervision',95,'Preferred candidate after interview',now()-interval '2 days') returning id into a5;
  insert into unimis.hrc_hr_interviews(tenant_id,applicant_id,interview_at,interview_type,panel_notes,score,recommendation,created_by)
  values(p_tenant,a5,now()-interval '3 days','in_person','Excellent technical and behavioural interview.',94,'Select',auth.uid());
  insert into unimis.hrc_hr_offers(tenant_id,applicant_id,offered_salary,proposed_start_date,employment_type,status,issued_at,responded_at,created_by)
  values(p_tenant,a5,4500,current_date+7,'regular','accepted',now()-interval '2 days',now()-interval '1 day',auth.uid());

  return jsonb_build_object('message','5 test applicants added to '||v_title||'. Final Hire is intentionally left for manual testing.','vacancy_id',v_vacancy,'hire_ready_applicant',a5);
end $$;
grant execute on function unimis.seed_recruitment_test(uuid) to authenticated;
notify pgrst, 'reload schema';


-- SOURCE 202610140010_employee_master_lifecycle_workspace.sql
-- Package 004: Employee Master Lifecycle Workspace foundation.
-- Employee Master remains the single source of truth across the employment lifecycle.

alter table unimis.hrc_hr_employees
 add column if not exists job_description text,
 add column if not exists job_responsibilities text,
 add column if not exists work_location text;

-- Preserve the accepted recruitment terms on hire. Verified documents continue to reuse
-- the same private storage object path; no binary file is copied.
create or replace function unimis.hr_hire_applicant(p_tenant uuid,p_applicant uuid,p_employee_no text,p_hire_date date,p_basic_salary numeric default 0)
returns uuid language plpgsql security definer set search_path=unimis as $$
declare
 a unimis.hrc_hr_applicants%rowtype;
 v unimis.hrc_hr_vacancies%rowtype;
 o unimis.hrc_hr_offers%rowtype;
 e uuid;
 effective_salary numeric;
 effective_type text;
begin
 if not unimis.has_tenant_role(p_tenant,array['owner','administrator','hr_manager']) then raise exception 'Hiring access denied'; end if;
 select * into a from unimis.hrc_hr_applicants where id=p_applicant and tenant_id=p_tenant for update;
 if a.id is null then raise exception 'Applicant not found'; end if;
 if a.status <> 'offer_accepted' then raise exception 'Offer must be accepted before hiring'; end if;
 if a.employee_id is not null then raise exception 'Applicant is already linked to an employee'; end if;
 if a.vacancy_id is not null then select * into v from unimis.hrc_hr_vacancies where id=a.vacancy_id and tenant_id=p_tenant; end if;
 select * into o from unimis.hrc_hr_offers where applicant_id=a.id and tenant_id=p_tenant and status='accepted' order by responded_at desc nulls last,created_at desc limit 1;
 effective_salary:=coalesce(nullif(p_basic_salary,0),o.offered_salary,0);
 effective_type:=coalesce(o.employment_type,v.employment_type,'regular');
 e:=unimis.hr_create_employee(p_tenant,p_employee_no,a.first_name,a.last_name,coalesce(a.email,''),v.department_id,v.position_id,a.date_of_birth,coalesce(o.proposed_start_date,p_hire_date,current_date),effective_salary,effective_type,'full_time','monthly',null,'applicable');
 update unimis.hrc_hr_employees set
   phone=coalesce(a.phone,phone),
   job_description=v.description,
   job_responsibilities=v.responsibilities,
   work_location=coalesce(v.location_text,v.work_arrangement)
 where id=e;
 insert into unimis.hrc_hr_employee_documents(tenant_id,employee_id,document_type,title,file_path,notes,uploaded_by)
 select d.tenant_id,e,d.document_type,d.title,d.file_path,'Linked from verified recruitment document; storage object not duplicated',auth.uid()
 from unimis.hrc_hr_applicant_documents d
 where d.applicant_id=a.id and d.tenant_id=p_tenant and d.review_status='verified'
 and not exists(select 1 from unimis.hrc_hr_employee_documents ed where ed.employee_id=e and ed.file_path=d.file_path);
 update unimis.hrc_hr_applicant_documents set transferred_employee_id=e where applicant_id=a.id and tenant_id=p_tenant and review_status='verified';
 update unimis.hrc_hr_applicants set status='hired',employee_id=e,updated_at=now() where id=a.id;
 perform unimis.hr_record_employment_event(p_tenant,e,'recruitment_hire',coalesce(o.proposed_start_date,p_hire_date,current_date),'Hired from recruitment',jsonb_build_object('applicant_id',a.id,'vacancy_id',a.vacancy_id,'offer_id',o.id,'employment_type',effective_type,'offered_salary',effective_salary,'job_responsibilities',v.responsibilities));
 return e;
end $$;
grant execute on function unimis.hr_hire_applicant(uuid,uuid,text,date,numeric) to authenticated;

notify pgrst, 'reload schema';


-- SOURCE 202610140011_career_exit_rehire.sql
-- Package 004b: governed career actions, separation and rehire.
create table if not exists unimis.hrc_hr_employee_lifecycle_actions(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
 employee_id uuid not null references unimis.hrc_hr_employees(id) on delete cascade,
 action_type text not null, effective_date date not null, reason_category text, reason_details text,
 old_department_id uuid references unimis.hrc_departments(id), new_department_id uuid references unimis.hrc_departments(id),
 old_position_id uuid references unimis.hrc_hr_positions(id), new_position_id uuid references unimis.hrc_hr_positions(id),
 old_employment_type text, new_employment_type text, new_salary numeric(14,2), notice_date date, last_working_date date,
 supporting_reference text, status text not null default 'submitted', submitted_by uuid references auth.users(id),
 approved_by uuid references auth.users(id), approved_at timestamptz, applied_at timestamptz, created_at timestamptz default now(),
 constraint lifecycle_action_type_ck check(action_type in ('promotion','transfer','demotion','acting_appointment','grade_change','contract_renewal','secondment','suspension','reinstatement','award','resignation','termination','dismissal','retirement','contract_end','redundancy','death_in_service','rehire')),
 constraint lifecycle_status_ck check(status in ('draft','submitted','approved','rejected','applied'))
);
alter table unimis.hrc_hr_employee_lifecycle_actions enable row level security;
drop policy if exists lifecycle_read on unimis.hrc_hr_employee_lifecycle_actions;
create policy lifecycle_read on unimis.hrc_hr_employee_lifecycle_actions for select using(unimis.is_tenant_member(tenant_id));
drop policy if exists lifecycle_insert on unimis.hrc_hr_employee_lifecycle_actions;
create policy lifecycle_insert on unimis.hrc_hr_employee_lifecycle_actions for insert with check(unimis.has_tenant_role(tenant_id,array['owner','administrator','hr_manager','hr_officer']));
drop policy if exists lifecycle_update on unimis.hrc_hr_employee_lifecycle_actions;
create policy lifecycle_update on unimis.hrc_hr_employee_lifecycle_actions for update using(unimis.has_tenant_role(tenant_id,array['owner','administrator','hr_manager'])) with check(unimis.has_tenant_role(tenant_id,array['owner','administrator','hr_manager']));

create or replace function unimis.hr_submit_lifecycle_action(p_tenant uuid,p_employee uuid,p_action_type text,p_effective_date date,p_reason_category text default null,p_reason_details text default null,p_new_position uuid default null,p_new_department uuid default null,p_new_employment_type text default null,p_new_salary numeric default null,p_last_working_date date default null,p_notice_date date default null,p_supporting_reference text default null)
returns uuid language plpgsql security definer set search_path=unimis as $$
declare e unimis.hrc_hr_employees%rowtype; x uuid;
begin
 if not unimis.has_tenant_role(p_tenant,array['owner','administrator','hr_manager','hr_officer']) then raise exception 'HR access denied'; end if;
 select * into e from unimis.hrc_hr_employees where id=p_employee and tenant_id=p_tenant;
 if e.id is null then raise exception 'Employee not found'; end if;
 if p_action_type='rehire' and e.employment_status='active' then raise exception 'Employee is already active'; end if;
 if p_action_type in ('resignation','termination','dismissal','retirement','contract_end','redundancy','death_in_service') and e.employment_status<>'active' then raise exception 'Only an active employee can be separated'; end if;
 insert into unimis.hrc_hr_employee_lifecycle_actions(tenant_id,employee_id,action_type,effective_date,reason_category,reason_details,old_department_id,new_department_id,old_position_id,new_position_id,old_employment_type,new_employment_type,new_salary,last_working_date,notice_date,supporting_reference,status,submitted_by)
 values(p_tenant,p_employee,p_action_type,coalesce(p_effective_date,current_date),p_reason_category,p_reason_details,e.department_id,p_new_department,e.position_id,p_new_position,e.employment_type,p_new_employment_type,p_new_salary,p_last_working_date,p_notice_date,p_supporting_reference,'submitted',auth.uid()) returning id into x;
 return x;
end $$;
grant execute on function unimis.hr_submit_lifecycle_action(uuid,uuid,text,date,text,text,uuid,uuid,text,numeric,date,date,text) to authenticated;

create or replace function unimis.hr_approve_lifecycle_action(p_tenant uuid,p_action uuid)
returns jsonb language plpgsql security definer set search_path=unimis as $$
declare a unimis.hrc_hr_employee_lifecycle_actions%rowtype; e unimis.hrc_hr_employees%rowtype; new_status text;
begin
 if not unimis.has_tenant_role(p_tenant,array['owner','administrator','hr_manager']) then raise exception 'Approval access denied'; end if;
 select * into a from unimis.hrc_hr_employee_lifecycle_actions where id=p_action and tenant_id=p_tenant for update;
 if a.id is null then raise exception 'Action not found'; end if;
 if a.status<>'submitted' then raise exception 'Action is not awaiting approval'; end if;
 select * into e from unimis.hrc_hr_employees where id=a.employee_id and tenant_id=p_tenant for update;
 if a.action_type in ('promotion','transfer','demotion','acting_appointment','grade_change','secondment') then
   update unimis.hrc_hr_employees set department_id=coalesce(a.new_department_id,department_id),position_id=coalesce(a.new_position_id,position_id) where id=e.id;
 elsif a.action_type='suspension' then update unimis.hrc_hr_employees set employment_status='suspended' where id=e.id;
 elsif a.action_type='reinstatement' then update unimis.hrc_hr_employees set employment_status='active' where id=e.id;
 elsif a.action_type in ('resignation','termination','dismissal','retirement','contract_end','redundancy','death_in_service') then
   new_status=case a.action_type when 'resignation' then 'resigned' when 'retirement' then 'retired' when 'death_in_service' then 'deceased' when 'contract_end' then 'contract_ended' else 'terminated' end;
   update unimis.hrc_hr_employees set employment_status=new_status where id=e.id;
   update unimis.hrc_payroll_profiles set active=false where employee_id=e.id;
   update unimis.hrc_hr_employment_contracts set status='ended',end_date=coalesce(a.last_working_date,a.effective_date) where employee_id=e.id and status='active';
 elsif a.action_type='rehire' then
   update unimis.hrc_hr_employees set employment_status='active',hire_date=a.effective_date,department_id=coalesce(a.new_department_id,department_id),position_id=coalesce(a.new_position_id,position_id),employment_type=coalesce(a.new_employment_type,employment_type) where id=e.id;
   update unimis.hrc_payroll_profiles set active=true where employee_id=e.id;
   insert into unimis.hrc_hr_employment_contracts(tenant_id,employee_id,contract_type,start_date,basic_salary,pay_frequency,status) values(p_tenant,e.id,coalesce(a.new_employment_type,'regular'),a.effective_date,coalesce(a.new_salary,0),'monthly','active');
 end if;
 update unimis.hrc_hr_employee_lifecycle_actions set status='applied',approved_by=auth.uid(),approved_at=now(),applied_at=now() where id=a.id;
 perform unimis.hr_record_employment_event(p_tenant,e.id,a.action_type,a.effective_date,initcap(replace(a.action_type,'_',' ')),jsonb_build_object('lifecycle_action_id',a.id,'reason_category',a.reason_category,'reason_details',a.reason_details,'old_department_id',a.old_department_id,'new_department_id',a.new_department_id,'old_position_id',a.old_position_id,'new_position_id',a.new_position_id,'last_working_date',a.last_working_date));
 return jsonb_build_object('ok',true,'employee_id',e.id,'action',a.action_type);
end $$;
grant execute on function unimis.hr_approve_lifecycle_action(uuid,uuid) to authenticated;
notify pgrst, 'reload schema';


-- SOURCE 202610140012_lifecycle_supporting_documents.sql
-- Package 004c: secure supporting documents for employee lifecycle actions.
alter table unimis.hrc_hr_employee_lifecycle_actions
  add column if not exists supporting_file_path text,
  add column if not exists supporting_file_name text;

create or replace function unimis.hr_attach_lifecycle_document(
  p_tenant uuid,
  p_action uuid,
  p_file_path text,
  p_file_name text
) returns void
language plpgsql security definer set search_path=unimis as $$
begin
  if not unimis.has_tenant_role(p_tenant,array['owner','administrator','hr_manager','hr_officer']) then
    raise exception 'HR access denied';
  end if;
  update unimis.hrc_hr_employee_lifecycle_actions
     set supporting_file_path=p_file_path,
         supporting_file_name=p_file_name
   where id=p_action and tenant_id=p_tenant;
  if not found then raise exception 'Lifecycle action not found'; end if;
end $$;
grant execute on function unimis.hr_attach_lifecycle_document(uuid,uuid,text,text) to authenticated;

notify pgrst, 'reload schema';


-- SOURCE 202610140013_lifecycle_controls_document_types.sql
-- Package 004e: lifecycle controls, richer HR document types, duplicate prevention.
update storage.buckets
set allowed_mime_types = array[
 'application/pdf','image/jpeg','image/png','image/webp',
 'application/msword','application/vnd.openxmlformats-officedocument.wordprocessingml.document',
 'application/vnd.ms-excel','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
]
where id='employee-documents';

alter table unimis.hrc_hr_employee_lifecycle_actions
  add column if not exists rejected_by uuid references auth.users(id),
  add column if not exists rejected_at timestamptz,
  add column if not exists cancelled_by uuid references auth.users(id),
  add column if not exists cancelled_at timestamptz,
  add column if not exists decision_notes text;

alter table unimis.hrc_hr_employee_lifecycle_actions drop constraint if exists lifecycle_status_ck;
alter table unimis.hrc_hr_employee_lifecycle_actions add constraint lifecycle_status_ck
 check(status in ('draft','submitted','approved','rejected','cancelled','applied'));

create or replace function unimis.hr_submit_lifecycle_action(p_tenant uuid,p_employee uuid,p_action_type text,p_effective_date date,p_reason_category text default null,p_reason_details text default null,p_new_position uuid default null,p_new_department uuid default null,p_new_employment_type text default null,p_new_salary numeric default null,p_last_working_date date default null,p_notice_date date default null,p_supporting_reference text default null)
returns uuid language plpgsql security definer set search_path=unimis as $$
declare e unimis.hrc_hr_employees%rowtype; x uuid; pending_count integer;
begin
 if not unimis.has_tenant_role(p_tenant,array['owner','administrator','hr_manager','hr_officer']) then raise exception 'HR access denied'; end if;
 select * into e from unimis.hrc_hr_employees where id=p_employee and tenant_id=p_tenant;
 if e.id is null then raise exception 'Employee not found'; end if;
 if p_action_type='rehire' and e.employment_status='active' then raise exception 'Employee is already active'; end if;
 if p_action_type in ('resignation','termination','dismissal','retirement','contract_end','redundancy','death_in_service') and e.employment_status<>'active' then raise exception 'Only an active employee can be separated'; end if;
 if p_action_type in ('resignation','termination','dismissal','retirement','contract_end','redundancy','death_in_service') then
   select count(*) into pending_count from unimis.hrc_hr_employee_lifecycle_actions
    where tenant_id=p_tenant and employee_id=p_employee and status='submitted'
      and action_type in ('resignation','termination','dismissal','retirement','contract_end','redundancy','death_in_service');
   if pending_count>0 then raise exception 'A separation request is already awaiting approval. Approve, reject or cancel it before submitting another.'; end if;
 end if;
 insert into unimis.hrc_hr_employee_lifecycle_actions(tenant_id,employee_id,action_type,effective_date,reason_category,reason_details,old_department_id,new_department_id,old_position_id,new_position_id,old_employment_type,new_employment_type,new_salary,last_working_date,notice_date,supporting_reference,status,submitted_by)
 values(p_tenant,p_employee,p_action_type,coalesce(p_effective_date,current_date),p_reason_category,p_reason_details,e.department_id,p_new_department,e.position_id,p_new_position,e.employment_type,p_new_employment_type,p_new_salary,p_last_working_date,p_notice_date,p_supporting_reference,'submitted',auth.uid()) returning id into x;
 return x;
end $$;
grant execute on function unimis.hr_submit_lifecycle_action(uuid,uuid,text,date,text,text,uuid,uuid,text,numeric,date,date,text) to authenticated;

create or replace function unimis.hr_reject_lifecycle_action(p_tenant uuid,p_action uuid,p_notes text default null)
returns void language plpgsql security definer set search_path=unimis as $$
begin
 if not unimis.has_tenant_role(p_tenant,array['owner','administrator','hr_manager']) then raise exception 'Approval access denied'; end if;
 update unimis.hrc_hr_employee_lifecycle_actions set status='rejected',rejected_by=auth.uid(),rejected_at=now(),decision_notes=p_notes
 where id=p_action and tenant_id=p_tenant and status='submitted';
 if not found then raise exception 'Action is not awaiting approval'; end if;
end $$;
grant execute on function unimis.hr_reject_lifecycle_action(uuid,uuid,text) to authenticated;

create or replace function unimis.hr_cancel_lifecycle_action(p_tenant uuid,p_action uuid)
returns void language plpgsql security definer set search_path=unimis as $$
begin
 if not unimis.has_tenant_role(p_tenant,array['owner','administrator','hr_manager','hr_officer']) then raise exception 'HR access denied'; end if;
 update unimis.hrc_hr_employee_lifecycle_actions set status='cancelled',cancelled_by=auth.uid(),cancelled_at=now()
 where id=p_action and tenant_id=p_tenant and status='submitted';
 if not found then raise exception 'Only a submitted action can be cancelled'; end if;
end $$;
grant execute on function unimis.hr_cancel_lifecycle_action(uuid,uuid) to authenticated;

notify pgrst, 'reload schema';


-- SOURCE 202610160014_attendance_leave_core.sql
-- Package 005: Attendance + Leave Core
create table if not exists unimis.hrc_hr_work_schedules(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
 code text not null, name text not null, start_time time not null default '08:00', end_time time not null default '17:00',
 grace_minutes integer not null default 10, standard_minutes integer not null default 480, work_days integer[] not null default array[1,2,3,4,5], active boolean not null default true,
 created_at timestamptz not null default now(), unique(tenant_id,code)
);
create table if not exists unimis.hrc_hr_employee_schedule_assignments(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
 employee_id uuid not null references unimis.hrc_hr_employees(id) on delete cascade,schedule_id uuid not null references unimis.hrc_hr_work_schedules(id),
 effective_from date not null default current_date,effective_to date,created_at timestamptz not null default now()
);
create table if not exists unimis.hrc_hr_attendance_records(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
 employee_id uuid not null references unimis.hrc_hr_employees(id) on delete cascade,work_date date not null,
 check_in timestamptz,check_out timestamptz,status text not null default 'present' check(status in ('present','absent','late','half_day','on_leave','holiday','off_day')),
 capture_method text not null default 'manual' check(capture_method in ('manual','qr','gps','nfc','biometric','import','api')),
 late_minutes integer not null default 0,overtime_minutes integer not null default 0,worked_minutes integer not null default 0,
 latitude numeric(10,7),longitude numeric(10,7),notes text,correction_status text not null default 'none',created_by uuid default auth.uid(),created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 unique(tenant_id,employee_id,work_date)
);
create table if not exists unimis.hrc_hr_public_holidays(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
 holiday_date date not null,name text not null,country_code text default 'GH',active boolean default true,unique(tenant_id,holiday_date)
);
create table if not exists unimis.hrc_hr_leave_types(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
 code text not null,name text not null,default_days numeric(7,2) not null default 0,paid boolean not null default true,
 requires_attachment boolean not null default false,carry_forward boolean not null default false,max_carry_forward numeric(7,2),active boolean not null default true,
 created_at timestamptz not null default now(),unique(tenant_id,code)
);
create table if not exists unimis.hrc_hr_leave_entitlements(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
 employee_id uuid not null references unimis.hrc_hr_employees(id) on delete cascade,leave_type_id uuid not null references unimis.hrc_hr_leave_types(id) on delete cascade,
 leave_year integer not null,entitled_days numeric(7,2) not null default 0,carried_days numeric(7,2) not null default 0,adjustment_days numeric(7,2) not null default 0,
 unique(tenant_id,employee_id,leave_type_id,leave_year)
);
create table if not exists unimis.hrc_hr_leave_requests(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
 employee_id uuid not null references unimis.hrc_hr_employees(id) on delete cascade,leave_type_id uuid not null references unimis.hrc_hr_leave_types(id),
 start_date date not null,end_date date not null,requested_days numeric(7,2) generated always as ((end_date-start_date)+1) stored,
 reason text,status text not null default 'draft' check(status in ('draft','submitted','approved','rejected','cancelled')),
 attachment_path text,decision_notes text,decided_by uuid,decided_at timestamptz,created_by uuid default auth.uid(),created_at timestamptz not null default now(),
 check(end_date>=start_date)
);

alter table unimis.hrc_hr_work_schedules enable row level security;alter table unimis.hrc_hr_employee_schedule_assignments enable row level security;alter table unimis.hrc_hr_attendance_records enable row level security;alter table unimis.hrc_hr_public_holidays enable row level security;alter table unimis.hrc_hr_leave_types enable row level security;alter table unimis.hrc_hr_leave_entitlements enable row level security;alter table unimis.hrc_hr_leave_requests enable row level security;
do $$ declare t text; begin foreach t in array array['hrc_hr_work_schedules','hrc_hr_employee_schedule_assignments','hrc_hr_attendance_records','hrc_hr_public_holidays','hrc_hr_leave_types','hrc_hr_leave_entitlements','hrc_hr_leave_requests'] loop execute format('drop policy if exists tenant_member_all on unimis.%I',t); execute format('create policy tenant_member_all on unimis.%I for all using (unimis.is_tenant_member(tenant_id)) with check (unimis.is_tenant_member(tenant_id))',t); end loop; end $$;

create or replace function unimis.hr_seed_time_leave_defaults(p_tenant uuid) returns jsonb language plpgsql security definer set search_path=unimis as $$
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 insert into hrc_hr_work_schedules(tenant_id,code,name,start_time,end_time,grace_minutes,standard_minutes) values(p_tenant,'STD','Standard Monday-Friday','08:00','17:00',10,480) on conflict(tenant_id,code) do nothing;
 insert into hrc_hr_leave_types(tenant_id,code,name,default_days,paid,requires_attachment,carry_forward) values
 (p_tenant,'ANNUAL','Annual Leave',20,true,false,true),(p_tenant,'SICK','Sick Leave',10,true,true,false),(p_tenant,'MATERNITY','Maternity Leave',84,true,true,false),(p_tenant,'PATERNITY','Paternity Leave',5,true,false,false),(p_tenant,'UNPAID','Unpaid Leave',0,false,false,false),(p_tenant,'STUDY','Study Leave',0,true,true,false)
 on conflict(tenant_id,code) do nothing;
 return jsonb_build_object('ok',true);
end $$;

create or replace function unimis.hr_attendance_compute() returns trigger language plpgsql set search_path=unimis as $$
declare s hrc_hr_work_schedules%rowtype; sched_start timestamptz;begin
 select ws.* into s from hrc_hr_employee_schedule_assignments a join hrc_hr_work_schedules ws on ws.id=a.schedule_id where a.tenant_id=new.tenant_id and a.employee_id=new.employee_id and a.effective_from<=new.work_date and (a.effective_to is null or a.effective_to>=new.work_date) order by a.effective_from desc limit 1;
 if s.id is null then select * into s from hrc_hr_work_schedules where tenant_id=new.tenant_id and active order by created_at limit 1; end if;
 if new.check_in is not null and s.id is not null then sched_start=(new.work_date+s.start_time)::timestamp at time zone 'UTC'; new.late_minutes=greatest(0,floor(extract(epoch from(new.check_in-sched_start))/60)-s.grace_minutes); if new.late_minutes>0 then new.status='late'; end if; end if;
 if new.check_in is not null and new.check_out is not null and new.check_out>=new.check_in then new.worked_minutes=floor(extract(epoch from(new.check_out-new.check_in))/60); if s.id is not null then new.overtime_minutes=greatest(0,new.worked_minutes-s.standard_minutes); end if; end if;
 new.updated_at=now(); return new;end $$;
drop trigger if exists trg_attendance_compute on unimis.hrc_hr_attendance_records;create trigger trg_attendance_compute before insert or update on unimis.hrc_hr_attendance_records for each row execute function unimis.hr_attendance_compute();

create or replace function unimis.hr_decide_leave_request(p_tenant uuid,p_request uuid,p_decision text,p_notes text default null) returns jsonb language plpgsql security definer set search_path=unimis as $$
declare r hrc_hr_leave_requests%rowtype; d date;begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 if p_decision not in ('approved','rejected') then raise exception 'Invalid decision'; end if;
 select * into r from hrc_hr_leave_requests where id=p_request and tenant_id=p_tenant for update; if r.id is null then raise exception 'Request not found'; end if; if r.status<>'submitted' then raise exception 'Only submitted requests can be decided'; end if;
 update hrc_hr_leave_requests set status=p_decision,decision_notes=p_notes,decided_by=auth.uid(),decided_at=now() where id=r.id;
 if p_decision='approved' then for d in select generate_series(r.start_date,r.end_date,'1 day'::interval)::date loop insert into hrc_hr_attendance_records(tenant_id,employee_id,work_date,status,capture_method,notes) values(p_tenant,r.employee_id,d,'on_leave','api','Approved leave') on conflict(tenant_id,employee_id,work_date) do update set status='on_leave',notes='Approved leave'; end loop; end if;
 return jsonb_build_object('ok',true,'status',p_decision);end $$;

grant execute on function unimis.hr_seed_time_leave_defaults(uuid) to authenticated;grant execute on function unimis.hr_decide_leave_request(uuid,uuid,text,text) to authenticated;
create index if not exists idx_attendance_tenant_date on unimis.hrc_hr_attendance_records(tenant_id,work_date desc);create index if not exists idx_leave_tenant_status on unimis.hrc_hr_leave_requests(tenant_id,status,created_at desc);


-- SOURCE 202610160015_attendance_leave_synchronization.sql
-- Package 005a: Attendance / Leave Synchronization Engine
alter table unimis.hrc_hr_leave_requests add column if not exists day_portion text not null default 'full' check(day_portion in ('full','first_half','second_half'));
alter table unimis.hrc_hr_leave_requests add column if not exists approved_working_days numeric(7,2);
alter table unimis.hrc_hr_attendance_records add column if not exists leave_request_id uuid references unimis.hrc_hr_leave_requests(id) on delete set null;
alter table unimis.hrc_hr_attendance_records add column if not exists leave_fraction numeric(3,2) check(leave_fraction is null or leave_fraction in (0.5,1.0));
alter table unimis.hrc_hr_attendance_records add column if not exists leave_paid boolean;
alter table unimis.hrc_hr_attendance_records add column if not exists leave_generated boolean not null default false;
create index if not exists idx_attendance_leave_request on unimis.hrc_hr_attendance_records(leave_request_id);

create or replace function unimis.hr_leave_is_working_day(p_tenant uuid,p_employee uuid,p_day date)
returns boolean language plpgsql stable set search_path=unimis as $$
declare s hrc_hr_work_schedules%rowtype; dow integer; holiday_exists boolean;
begin
 select ws.* into s from hrc_hr_employee_schedule_assignments a join hrc_hr_work_schedules ws on ws.id=a.schedule_id
 where a.tenant_id=p_tenant and a.employee_id=p_employee and a.effective_from<=p_day and (a.effective_to is null or a.effective_to>=p_day)
 order by a.effective_from desc limit 1;
 if s.id is null then select * into s from hrc_hr_work_schedules where tenant_id=p_tenant and active order by created_at limit 1; end if;
 dow=extract(isodow from p_day)::integer;
 if s.id is not null and not (dow=any(s.work_days)) then return false; end if;
 select exists(select 1 from hrc_hr_public_holidays where tenant_id=p_tenant and holiday_date=p_day and active) into holiday_exists;
 return not holiday_exists;
end $$;

create or replace function unimis.hr_sync_leave_attendance(p_tenant uuid,p_request uuid)
returns jsonb language plpgsql security definer set search_path=unimis as $$
declare r hrc_hr_leave_requests%rowtype; lt hrc_hr_leave_types%rowtype; d date; rec hrc_hr_attendance_records%rowtype; frac numeric; workdays numeric:=0; note_text text;
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 select * into r from hrc_hr_leave_requests where id=p_request and tenant_id=p_tenant; if r.id is null then raise exception 'Request not found'; end if;
 select * into lt from hrc_hr_leave_types where id=r.leave_type_id and tenant_id=p_tenant;
 if r.status<>'approved' then raise exception 'Only approved leave can be synchronized'; end if;
 frac=case when r.day_portion='full' then 1.0 else 0.5 end;
 -- remove stale system-generated rows for this request before rebuilding
 delete from hrc_hr_attendance_records where tenant_id=p_tenant and leave_request_id=r.id and leave_generated=true and check_in is null and check_out is null;
 for d in select generate_series(r.start_date,r.end_date,'1 day'::interval)::date loop
   if unimis.hr_leave_is_working_day(p_tenant,r.employee_id,d) then
     workdays=workdays+frac;
     note_text=case when frac=0.5 then 'Approved '||replace(r.day_portion,'_',' ')||' leave' else 'Approved leave' end;
     select * into rec from hrc_hr_attendance_records where tenant_id=p_tenant and employee_id=r.employee_id and work_date=d for update;
     if rec.id is null then
       insert into hrc_hr_attendance_records(tenant_id,employee_id,work_date,status,capture_method,notes,leave_request_id,leave_fraction,leave_paid,leave_generated)
       values(p_tenant,r.employee_id,d,case when frac=0.5 then 'half_day' else 'on_leave' end,'api',note_text,r.id,frac,coalesce(lt.paid,true),true);
     elsif rec.check_in is null and rec.check_out is null then
       update hrc_hr_attendance_records set status=case when frac=0.5 then 'half_day' else 'on_leave' end,
         notes=note_text,leave_request_id=r.id,leave_fraction=frac,leave_paid=coalesce(lt.paid,true),leave_generated=true,
         late_minutes=0,overtime_minutes=0,worked_minutes=0 where id=rec.id;
     else
       -- preserve genuine clock evidence; annotate the overlap instead of destroying it
       update hrc_hr_attendance_records set status=case when frac=0.5 then 'half_day' else status end,
         notes=concat_ws(' · ',nullif(notes,''),note_text||' (attendance retained)'),leave_request_id=r.id,
         leave_fraction=frac,leave_paid=coalesce(lt.paid,true),leave_generated=false where id=rec.id;
     end if;
   end if;
 end loop;
 update hrc_hr_leave_requests set approved_working_days=workdays where id=r.id;
 return jsonb_build_object('ok',true,'working_days',workdays);
end $$;

create or replace function unimis.hr_decide_leave_request(p_tenant uuid,p_request uuid,p_decision text,p_notes text default null)
returns jsonb language plpgsql security definer set search_path=unimis as $$
declare r hrc_hr_leave_requests%rowtype; result jsonb;
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 if p_decision not in ('approved','rejected') then raise exception 'Invalid decision'; end if;
 select * into r from hrc_hr_leave_requests where id=p_request and tenant_id=p_tenant for update;
 if r.id is null then raise exception 'Request not found'; end if;
 if r.status<>'submitted' then raise exception 'Only submitted requests can be decided'; end if;
 update hrc_hr_leave_requests set status=p_decision,decision_notes=p_notes,decided_by=auth.uid(),decided_at=now() where id=r.id;
 if p_decision='approved' then result=unimis.hr_sync_leave_attendance(p_tenant,r.id); else result=jsonb_build_object('ok',true); end if;
 return result||jsonb_build_object('status',p_decision);
end $$;

create or replace function unimis.hr_cancel_leave_request(p_tenant uuid,p_request uuid,p_notes text default null)
returns jsonb language plpgsql security definer set search_path=unimis as $$
declare r hrc_hr_leave_requests%rowtype;
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 select * into r from hrc_hr_leave_requests where id=p_request and tenant_id=p_tenant for update;
 if r.id is null then raise exception 'Request not found'; end if;
 if r.status not in ('submitted','approved') then raise exception 'Only submitted or approved leave can be cancelled'; end if;
 -- delete only rows created solely by leave; preserve genuine attendance and remove leave annotation metadata
 delete from hrc_hr_attendance_records where tenant_id=p_tenant and leave_request_id=r.id and leave_generated=true and check_in is null and check_out is null;
 update hrc_hr_attendance_records set leave_request_id=null,leave_fraction=null,leave_paid=null,leave_generated=false,
   notes=case when notes like '%Approved leave%' then 'Leave cancelled; attendance retained' else notes end
 where tenant_id=p_tenant and leave_request_id=r.id;
 update hrc_hr_leave_requests set status='cancelled',decision_notes=coalesce(p_notes,'Leave cancelled'),decided_by=auth.uid(),decided_at=now(),approved_working_days=0 where id=r.id;
 return jsonb_build_object('ok',true,'status','cancelled');
end $$;

grant execute on function unimis.hr_sync_leave_attendance(uuid,uuid) to authenticated;
grant execute on function unimis.hr_cancel_leave_request(uuid,uuid,text) to authenticated;


-- SOURCE 202610160016_smart_attendance_capture.sql
-- Package 005b: Smart Attendance Capture (rotating QR token + optional GPS geofence)
create extension if not exists pgcrypto;

create table if not exists unimis.hrc_hr_attendance_sites(
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
 code text not null,
 name text not null,
 latitude numeric(10,7),
 longitude numeric(10,7),
 radius_meters integer not null default 150 check(radius_meters between 20 and 5000),
 gps_required boolean not null default false,
 qr_enabled boolean not null default true,
 active boolean not null default true,
 created_at timestamptz not null default now(),
 unique(tenant_id,code),
 check(not gps_required or (latitude is not null and longitude is not null))
);
create table if not exists unimis.hrc_hr_attendance_qr_tokens(
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
 site_id uuid not null references unimis.hrc_hr_attendance_sites(id) on delete cascade,
 token_hash text not null,
 expires_at timestamptz not null,
 revoked_at timestamptz,
 created_by uuid default auth.uid(),
 created_at timestamptz not null default now()
);
create table if not exists unimis.hrc_hr_attendance_capture_events(
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
 employee_id uuid not null references unimis.hrc_hr_employees(id) on delete cascade,
 site_id uuid references unimis.hrc_hr_attendance_sites(id) on delete set null,
 attendance_id uuid references unimis.hrc_hr_attendance_records(id) on delete set null,
 event_type text not null check(event_type in ('check_in','check_out')),
 captured_at timestamptz not null default now(),
 capture_method text not null default 'qr' check(capture_method in ('qr','gps','nfc','biometric','api')),
 latitude numeric(10,7),longitude numeric(10,7),
 distance_meters numeric(10,2),gps_verified boolean,
 token_id uuid references unimis.hrc_hr_attendance_qr_tokens(id) on delete set null,
 created_by uuid default auth.uid()
);
alter table unimis.hrc_hr_attendance_records add column if not exists attendance_site_id uuid references unimis.hrc_hr_attendance_sites(id) on delete set null;
alter table unimis.hrc_hr_attendance_records add column if not exists gps_verified boolean;
alter table unimis.hrc_hr_attendance_records add column if not exists check_in_source text;
alter table unimis.hrc_hr_attendance_records add column if not exists check_out_source text;

alter table unimis.hrc_hr_attendance_sites enable row level security;
alter table unimis.hrc_hr_attendance_qr_tokens enable row level security;
alter table unimis.hrc_hr_attendance_capture_events enable row level security;
drop policy if exists tenant_member_all on unimis.hrc_hr_attendance_sites;
create policy tenant_member_all on unimis.hrc_hr_attendance_sites for all using(unimis.is_tenant_member(tenant_id)) with check(unimis.is_tenant_member(tenant_id));
drop policy if exists tenant_member_all on unimis.hrc_hr_attendance_qr_tokens;
create policy tenant_member_all on unimis.hrc_hr_attendance_qr_tokens for all using(unimis.is_tenant_member(tenant_id)) with check(unimis.is_tenant_member(tenant_id));
drop policy if exists tenant_member_all on unimis.hrc_hr_attendance_capture_events;
create policy tenant_member_all on unimis.hrc_hr_attendance_capture_events for all using(unimis.is_tenant_member(tenant_id)) with check(unimis.is_tenant_member(tenant_id));

create or replace function unimis.hr_distance_meters(lat1 numeric,lon1 numeric,lat2 numeric,lon2 numeric)
returns numeric language sql immutable as $$
 select 6371000 * 2 * asin(sqrt(power(sin(radians((lat2-lat1)/2)),2)+cos(radians(lat1))*cos(radians(lat2))*power(sin(radians((lon2-lon1)/2)),2)));
$$;

create or replace function unimis.hr_create_attendance_qr_token(p_tenant uuid,p_site uuid,p_valid_minutes integer default 5)
returns jsonb language plpgsql security definer set search_path=unimis as $$
declare raw_token text; exp timestamptz; tid uuid;
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 if p_valid_minutes not between 1 and 30 then raise exception 'Token validity must be 1-30 minutes'; end if;
 if not exists(select 1 from hrc_hr_attendance_sites where id=p_site and tenant_id=p_tenant and active and qr_enabled) then raise exception 'Active QR-enabled site not found'; end if;
 update hrc_hr_attendance_qr_tokens set revoked_at=now() where tenant_id=p_tenant and site_id=p_site and revoked_at is null and expires_at>now();
 raw_token=upper(substr(encode(gen_random_bytes(12),'hex'),1,20)); exp=now()+make_interval(mins=>p_valid_minutes);
 insert into hrc_hr_attendance_qr_tokens(tenant_id,site_id,token_hash,expires_at) values(p_tenant,p_site,encode(digest(raw_token,'sha256'),'hex'),exp) returning id into tid;
 return jsonb_build_object('token',raw_token,'expires_at',exp,'token_id',tid);
end $$;

create or replace function unimis.hr_capture_attendance(p_tenant uuid,p_employee uuid,p_site uuid,p_token text,p_action text,p_latitude numeric default null,p_longitude numeric default null)
returns jsonb language plpgsql security definer set search_path=unimis as $$
declare s hrc_hr_attendance_sites%rowtype; tok hrc_hr_attendance_qr_tokens%rowtype; rec hrc_hr_attendance_records%rowtype; dist numeric; nowts timestamptz:=now(); d date:=current_date; verified boolean:=null; method text:='qr';
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 if p_action not in ('check_in','check_out') then raise exception 'Invalid attendance action'; end if;
 if not exists(select 1 from hrc_hr_employees where id=p_employee and tenant_id=p_tenant and employment_status='active') then raise exception 'Active employee not found'; end if;
 select * into s from hrc_hr_attendance_sites where id=p_site and tenant_id=p_tenant and active;
 if s.id is null then raise exception 'Attendance site not found'; end if;
 select * into tok from hrc_hr_attendance_qr_tokens where tenant_id=p_tenant and site_id=p_site and token_hash=encode(digest(upper(trim(p_token)),'sha256'),'hex') and revoked_at is null and expires_at>=now() order by created_at desc limit 1;
 if tok.id is null then raise exception 'QR token is invalid or expired'; end if;
 if s.gps_required then
   if p_latitude is null or p_longitude is null then raise exception 'GPS location is required at this attendance site'; end if;
   dist=unimis.hr_distance_meters(s.latitude,s.longitude,p_latitude,p_longitude); verified=dist<=s.radius_meters; method='gps';
   if not verified then raise exception 'Outside attendance site geofence (% m away; allowed radius % m)',round(dist),s.radius_meters; end if;
 end if;
 select * into rec from hrc_hr_attendance_records where tenant_id=p_tenant and employee_id=p_employee and work_date=d for update;
 if rec.id is null then
   insert into hrc_hr_attendance_records(tenant_id,employee_id,work_date,status,capture_method,attendance_site_id,gps_verified,check_in,check_in_source,latitude,longitude,notes)
   values(p_tenant,p_employee,d,'present',method,p_site,verified,case when p_action='check_in' then nowts end,case when p_action='check_in' then method end,p_latitude,p_longitude,'Smart attendance capture')
   returning * into rec;
 end if;
 if p_action='check_in' then
   if rec.status in ('on_leave','holiday','off_day') then raise exception 'Check-in blocked because attendance status is %',replace(rec.status,'_',' '); end if;
   if rec.check_in is not null then raise exception 'Employee has already checked in today'; end if;
   update hrc_hr_attendance_records set check_in=nowts,status='present',capture_method=method,attendance_site_id=p_site,gps_verified=verified,check_in_source=method,latitude=p_latitude,longitude=p_longitude where id=rec.id returning * into rec;
 else
   if rec.check_in is null then raise exception 'Employee must check in before checking out'; end if;
   if rec.check_out is not null then raise exception 'Employee has already checked out today'; end if;
   update hrc_hr_attendance_records set check_out=nowts,capture_method=method,attendance_site_id=coalesce(attendance_site_id,p_site),gps_verified=coalesce(verified,gps_verified),check_out_source=method where id=rec.id returning * into rec;
 end if;
 insert into hrc_hr_attendance_capture_events(tenant_id,employee_id,site_id,attendance_id,event_type,captured_at,capture_method,latitude,longitude,distance_meters,gps_verified,token_id)
 values(p_tenant,p_employee,p_site,rec.id,p_action,nowts,method,p_latitude,p_longitude,dist,verified,tok.id);
 return jsonb_build_object('ok',true,'message',case when p_action='check_in' then 'Check-in recorded successfully.' else 'Check-out recorded successfully.' end,'attendance_id',rec.id,'gps_verified',verified,'distance_meters',dist);
end $$;

grant execute on function unimis.hr_create_attendance_qr_token(uuid,uuid,integer) to authenticated;
grant execute on function unimis.hr_capture_attendance(uuid,uuid,uuid,text,text,numeric,numeric) to authenticated;
create index if not exists idx_attendance_sites_tenant on unimis.hrc_hr_attendance_sites(tenant_id,active);
create index if not exists idx_attendance_tokens_site_expiry on unimis.hrc_hr_attendance_qr_tokens(tenant_id,site_id,expires_at desc);
create index if not exists idx_attendance_events_employee_time on unimis.hrc_hr_attendance_capture_events(tenant_id,employee_id,captured_at desc);


-- SOURCE 202610160017_employee_qr_kiosk.sql
-- 005d Employee QR Scanner & Site Kiosk
alter table unimis.hrc_hr_employees add column if not exists auth_user_id uuid references auth.users(id) on delete set null;
create unique index if not exists uq_hr_employee_auth_user on unimis.hrc_hr_employees(auth_user_id) where auth_user_id is not null;

create or replace function unimis.hr_my_employee(p_tenant uuid)
returns jsonb language plpgsql security definer set search_path=unimis as $$
declare e unimis.hrc_hr_employees%rowtype; mail text;
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 select * into e from unimis.hrc_hr_employees where tenant_id=p_tenant and auth_user_id=auth.uid() and employment_status='active' limit 1;
 if e.id is null then
   mail=lower(coalesce(auth.jwt()->>'email',''));
   if mail<>'' then
     select * into e from unimis.hrc_hr_employees where tenant_id=p_tenant and lower(coalesce(email,''))=mail and employment_status='active' limit 1;
     if e.id is not null and e.auth_user_id is null then update unimis.hrc_hr_employees set auth_user_id=auth.uid() where id=e.id; end if;
   end if;
 end if;
 if e.id is null then return null; end if;
 return jsonb_build_object('id',e.id,'employee_no',e.employee_no,'first_name',e.first_name,'last_name',e.last_name,'email',e.email);
end $$;
grant execute on function unimis.hr_my_employee(uuid) to authenticated;


-- SOURCE 202610160018_fix_attendance_qr_pgcrypto.sql
-- 005d1: make QR token crypto functions resolvable on local/hosted Supabase.
-- Supabase commonly installs pgcrypto in the extensions schema, while older/local
-- projects may expose it from unimis. Keep both schemas on the function search path.
create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

create or replace function unimis.hr_create_attendance_qr_token(
  p_tenant uuid,
  p_site uuid,
  p_valid_minutes integer default 5
)
returns jsonb
language plpgsql
security definer
set search_path=unimis,extensions
as $$
declare
  raw_token text;
  exp timestamptz;
  tid uuid;
begin
  if not unimis.is_tenant_member(p_tenant) then
    raise exception 'Tenant access denied';
  end if;
  if p_valid_minutes not between 1 and 30 then
    raise exception 'Token validity must be 1-30 minutes';
  end if;
  if not exists(
    select 1 from unimis.hrc_hr_attendance_sites
    where id=p_site and tenant_id=p_tenant and active and qr_enabled
  ) then
    raise exception 'Active QR-enabled site not found';
  end if;

  update unimis.hrc_hr_attendance_qr_tokens
     set revoked_at=now()
   where tenant_id=p_tenant
     and site_id=p_site
     and revoked_at is null
     and expires_at>now();

  raw_token=upper(substr(encode(gen_random_bytes(12),'hex'),1,20));
  exp=now()+make_interval(mins=>p_valid_minutes);

  insert into unimis.hrc_hr_attendance_qr_tokens(tenant_id,site_id,token_hash,expires_at)
  values(p_tenant,p_site,encode(digest(raw_token,'sha256'),'hex'),exp)
  returning id into tid;

  return jsonb_build_object('token',raw_token,'expires_at',exp,'token_id',tid);
end
$$;

grant execute on function unimis.hr_create_attendance_qr_token(uuid,uuid,integer) to authenticated;

-- The capture function also uses digest(), so ensure the same extension search path.
alter function unimis.hr_capture_attendance(uuid,uuid,uuid,text,text,numeric,numeric)
  set search_path=unimis,extensions;

notify pgrst, 'reload schema';




-- Refresh Supabase/PostgREST schema cache after this stage.
NOTIFY pgrst, 'reload schema';
