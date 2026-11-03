-- Package 003: Recruitment + onboarding feeding the HR Employee Master.
create table if not exists public.hr_vacancies(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.tenants(id) on delete cascade,
 title text not null, department_id uuid references public.departments(id) on delete set null,
 position_id uuid references public.hr_positions(id) on delete set null, openings integer not null default 1 check(openings>0),
 employment_type text not null default 'regular', description text, requirements text, closing_date date,
 status text not null default 'draft' check(status in ('draft','open','closed','cancelled')),
 created_by uuid references auth.users(id), created_at timestamptz not null default now()
);
create table if not exists public.hr_applicants(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.tenants(id) on delete cascade,
 vacancy_id uuid references public.hr_vacancies(id) on delete set null, first_name text not null, last_name text not null,
 email text, phone text, date_of_birth date, source text, cv_path text,
 status text not null default 'applied' check(status in ('applied','shortlisted','interviewed','rejected','offered','offer_accepted','offer_declined','hired')),
 employee_id uuid references public.hr_employees(id) on delete set null, notes text,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.hr_interviews(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.tenants(id) on delete cascade,
 applicant_id uuid not null references public.hr_applicants(id) on delete cascade, interview_at timestamptz,
 interview_type text default 'in_person', panel_notes text, score numeric(5,2), recommendation text,
 created_by uuid references auth.users(id), created_at timestamptz default now()
);
create table if not exists public.hr_offers(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.tenants(id) on delete cascade,
 applicant_id uuid not null references public.hr_applicants(id) on delete cascade, offered_salary numeric(14,2) default 0,
 proposed_start_date date, employment_type text default 'regular', status text default 'draft' check(status in ('draft','issued','accepted','declined','withdrawn')),
 issued_at timestamptz, responded_at timestamptz, created_by uuid references auth.users(id), created_at timestamptz default now()
);

do $$ declare t text; begin
 foreach t in array array['hr_vacancies','hr_applicants','hr_interviews','hr_offers'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('create policy %I on public.%I for select using(public.is_tenant_member(tenant_id))',t||'_read',t);
  execute format('create policy %I on public.%I for insert with check(public.has_tenant_role(tenant_id,array[''owner'',''administrator'',''hr_manager'',''hr_officer'']))',t||'_insert',t);
  execute format('create policy %I on public.%I for update using(public.has_tenant_role(tenant_id,array[''owner'',''administrator'',''hr_manager'',''hr_officer''])) with check(public.has_tenant_role(tenant_id,array[''owner'',''administrator'',''hr_manager'',''hr_officer'']))',t||'_update',t);
  execute format('create policy %I on public.%I for delete using(public.has_tenant_role(tenant_id,array[''owner'',''administrator'',''hr_manager'']))',t||'_delete',t);
 end loop;
end $$;

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
 update public.hr_applicants set status='hired',employee_id=e,updated_at=now() where id=a.id;
 perform public.hr_record_employment_event(p_tenant,e,'recruitment_hire',p_hire_date,'Hired from recruitment',jsonb_build_object('applicant_id',a.id,'vacancy_id',a.vacancy_id));
 return e;
end $$;
grant execute on function public.hr_hire_applicant(uuid,uuid,text,date,numeric) to authenticated;

create index if not exists hr_vacancies_tenant_status_idx on public.hr_vacancies(tenant_id,status);
create index if not exists hr_applicants_tenant_status_idx on public.hr_applicants(tenant_id,status);
notify pgrst, 'reload schema';
