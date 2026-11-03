-- Package 003a: Lean recruitment funnel, progressive documents and retention-ready hiring.
-- Large applicant pools keep only light application data/CV; supporting evidence is requested only after selection.

alter table public.hr_applicants
  add column if not exists highest_qualification text,
  add column if not exists years_experience numeric(5,1),
  add column if not exists key_skills text,
  add column if not exists screening_score numeric(5,2),
  add column if not exists screening_notes text,
  add column if not exists selected_at timestamptz,
  add column if not exists retention_until date;

alter table public.hr_applicants drop constraint if exists hr_applicants_status_check;
alter table public.hr_applicants add constraint hr_applicants_status_check check(status in
 ('applied','shortlisted','interviewed','rejected','selected','documents_pending','documents_verified','offered','offer_accepted','offer_declined','hired','withdrawn'));

alter table public.hr_vacancies
  add column if not exists cv_required boolean not null default true,
  add column if not exists supporting_documents jsonb not null default '["National ID / Ghana Card","Academic certificate"]'::jsonb;

create table if not exists public.hr_applicant_documents(
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete cascade,
 applicant_id uuid not null references public.hr_applicants(id) on delete cascade,
 document_type text not null,
 title text not null,
 file_path text not null,
 stage text not null default 'application' check(stage in ('application','selected')),
 review_status text not null default 'pending' check(review_status in ('pending','verified','rejected','clarification')),
 review_notes text,
 reviewed_by uuid references auth.users(id), reviewed_at timestamptz,
 transferred_employee_id uuid references public.hr_employees(id) on delete set null,
 created_at timestamptz not null default now()
);

create table if not exists public.hr_recruitment_settings(
 tenant_id uuid primary key references public.tenants(id) on delete cascade,
 unsuccessful_retention_months integer not null default 12 check(unsuccessful_retention_months between 1 and 120),
 cv_retention_months integer not null default 6 check(cv_retention_months between 1 and 120),
 require_verified_documents_before_offer boolean not null default true,
 updated_at timestamptz not null default now()
);

insert into public.hr_recruitment_settings(tenant_id)
select id from public.tenants on conflict(tenant_id) do nothing;

alter table public.hr_applicant_documents enable row level security;
alter table public.hr_recruitment_settings enable row level security;

drop policy if exists hr_applicant_documents_read on public.hr_applicant_documents;
create policy hr_applicant_documents_read on public.hr_applicant_documents for select
 using(public.is_tenant_member(tenant_id));
drop policy if exists hr_applicant_documents_insert on public.hr_applicant_documents;
create policy hr_applicant_documents_insert on public.hr_applicant_documents for insert
 with check(public.has_tenant_role(tenant_id,array['owner','administrator','hr_manager','hr_officer']));
drop policy if exists hr_applicant_documents_update on public.hr_applicant_documents;
create policy hr_applicant_documents_update on public.hr_applicant_documents for update
 using(public.has_tenant_role(tenant_id,array['owner','administrator','hr_manager','hr_officer']))
 with check(public.has_tenant_role(tenant_id,array['owner','administrator','hr_manager','hr_officer']));
drop policy if exists hr_applicant_documents_delete on public.hr_applicant_documents;
create policy hr_applicant_documents_delete on public.hr_applicant_documents for delete
 using(public.has_tenant_role(tenant_id,array['owner','administrator','hr_manager']));

drop policy if exists hr_recruitment_settings_read on public.hr_recruitment_settings;
create policy hr_recruitment_settings_read on public.hr_recruitment_settings for select using(public.is_tenant_member(tenant_id));
drop policy if exists hr_recruitment_settings_write on public.hr_recruitment_settings;
create policy hr_recruitment_settings_write on public.hr_recruitment_settings for all
 using(public.has_tenant_role(tenant_id,array['owner','administrator','hr_manager']))
 with check(public.has_tenant_role(tenant_id,array['owner','administrator','hr_manager']));

create index if not exists hr_applicant_documents_applicant_idx on public.hr_applicant_documents(applicant_id,stage,review_status);

-- Replace Package 003 hire RPC. No storage object is copied: verified recruitment documents are linked
-- into the employee document register using the same private employee-documents object path.
create or replace function public.hr_hire_applicant(p_tenant uuid,p_applicant uuid,p_employee_no text,p_hire_date date,p_basic_salary numeric default 0)
returns uuid language plpgsql security definer set search_path=public as $$
declare a public.hr_applicants%rowtype; v public.hr_vacancies%rowtype; e uuid;
begin
 if not public.has_tenant_role(p_tenant,array['owner','administrator','hr_manager']) then raise exception 'Hiring access denied'; end if;
 select * into a from public.hr_applicants where id=p_applicant and tenant_id=p_tenant for update;
 if a.id is null then raise exception 'Applicant not found'; end if;
 if a.status <> 'offer_accepted' then raise exception 'Offer must be accepted before hiring'; end if;
 if a.employee_id is not null then raise exception 'Applicant is already linked to an employee'; end if;
 if a.vacancy_id is not null then select * into v from public.hr_vacancies where id=a.vacancy_id and tenant_id=p_tenant; end if;
 e:=public.hr_create_employee(p_tenant,p_employee_no,a.first_name,a.last_name,coalesce(a.email,''),v.department_id,v.position_id,a.date_of_birth,p_hire_date,coalesce(p_basic_salary,0),coalesce(v.employment_type,'regular'),'full_time','monthly',null,'applicable');
 update public.hr_employees set phone=coalesce(a.phone,phone) where id=e;
 -- Reuse the exact same private storage object; only create an Employee Master metadata reference.
 insert into public.hr_employee_documents(tenant_id,employee_id,document_type,title,file_path,notes,uploaded_by)
 select d.tenant_id,e,d.document_type,d.title,d.file_path,'Transferred from recruitment without duplicating storage',auth.uid()
 from public.hr_applicant_documents d
 where d.applicant_id=a.id and d.tenant_id=p_tenant and d.review_status='verified';
 update public.hr_applicant_documents set transferred_employee_id=e where applicant_id=a.id and tenant_id=p_tenant and review_status='verified';
 update public.hr_applicants set status='hired',employee_id=e,updated_at=now() where id=a.id;
 perform public.hr_record_employment_event(p_tenant,e,'recruitment_hire',p_hire_date,'Hired from recruitment',jsonb_build_object('applicant_id',a.id,'vacancy_id',a.vacancy_id));
 return e;
end $$;
grant execute on function public.hr_hire_applicant(uuid,uuid,text,date,numeric) to authenticated;

notify pgrst, 'reload schema';

create or replace function public.hr_set_applicant_retention() returns trigger language plpgsql set search_path=public as $$
declare m integer;
begin
 if new.status in ('rejected','withdrawn','offer_declined') and (old.status is distinct from new.status or new.retention_until is null) then
   select unsuccessful_retention_months into m from public.hr_recruitment_settings where tenant_id=new.tenant_id;
   new.retention_until := current_date + make_interval(months=>coalesce(m,12));
 end if;
 return new;
end $$;
drop trigger if exists hr_applicant_retention_trigger on public.hr_applicants;
create trigger hr_applicant_retention_trigger before update on public.hr_applicants for each row execute function public.hr_set_applicant_retention();

notify pgrst, 'reload schema';
