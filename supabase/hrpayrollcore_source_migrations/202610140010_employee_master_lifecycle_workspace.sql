-- Package 004: Employee Master Lifecycle Workspace foundation.
-- Employee Master remains the single source of truth across the employment lifecycle.

alter table public.hr_employees
 add column if not exists job_description text,
 add column if not exists job_responsibilities text,
 add column if not exists work_location text;

-- Preserve the accepted recruitment terms on hire. Verified documents continue to reuse
-- the same private storage object path; no binary file is copied.
create or replace function public.hr_hire_applicant(p_tenant uuid,p_applicant uuid,p_employee_no text,p_hire_date date,p_basic_salary numeric default 0)
returns uuid language plpgsql security definer set search_path=public as $$
declare
 a public.hr_applicants%rowtype;
 v public.hr_vacancies%rowtype;
 o public.hr_offers%rowtype;
 e uuid;
 effective_salary numeric;
 effective_type text;
begin
 if not public.has_tenant_role(p_tenant,array['owner','administrator','hr_manager']) then raise exception 'Hiring access denied'; end if;
 select * into a from public.hr_applicants where id=p_applicant and tenant_id=p_tenant for update;
 if a.id is null then raise exception 'Applicant not found'; end if;
 if a.status <> 'offer_accepted' then raise exception 'Offer must be accepted before hiring'; end if;
 if a.employee_id is not null then raise exception 'Applicant is already linked to an employee'; end if;
 if a.vacancy_id is not null then select * into v from public.hr_vacancies where id=a.vacancy_id and tenant_id=p_tenant; end if;
 select * into o from public.hr_offers where applicant_id=a.id and tenant_id=p_tenant and status='accepted' order by responded_at desc nulls last,created_at desc limit 1;
 effective_salary:=coalesce(nullif(p_basic_salary,0),o.offered_salary,0);
 effective_type:=coalesce(o.employment_type,v.employment_type,'regular');
 e:=public.hr_create_employee(p_tenant,p_employee_no,a.first_name,a.last_name,coalesce(a.email,''),v.department_id,v.position_id,a.date_of_birth,coalesce(o.proposed_start_date,p_hire_date,current_date),effective_salary,effective_type,'full_time','monthly',null,'applicable');
 update public.hr_employees set
   phone=coalesce(a.phone,phone),
   job_description=v.description,
   job_responsibilities=v.responsibilities,
   work_location=coalesce(v.location_text,v.work_arrangement)
 where id=e;
 insert into public.hr_employee_documents(tenant_id,employee_id,document_type,title,file_path,notes,uploaded_by)
 select d.tenant_id,e,d.document_type,d.title,d.file_path,'Linked from verified recruitment document; storage object not duplicated',auth.uid()
 from public.hr_applicant_documents d
 where d.applicant_id=a.id and d.tenant_id=p_tenant and d.review_status='verified'
 and not exists(select 1 from public.hr_employee_documents ed where ed.employee_id=e and ed.file_path=d.file_path);
 update public.hr_applicant_documents set transferred_employee_id=e where applicant_id=a.id and tenant_id=p_tenant and review_status='verified';
 update public.hr_applicants set status='hired',employee_id=e,updated_at=now() where id=a.id;
 perform public.hr_record_employment_event(p_tenant,e,'recruitment_hire',coalesce(o.proposed_start_date,p_hire_date,current_date),'Hired from recruitment',jsonb_build_object('applicant_id',a.id,'vacancy_id',a.vacancy_id,'offer_id',o.id,'employment_type',effective_type,'offered_salary',effective_salary,'job_responsibilities',v.responsibilities));
 return e;
end $$;
grant execute on function public.hr_hire_applicant(uuid,uuid,text,date,numeric) to authenticated;

notify pgrst, 'reload schema';
