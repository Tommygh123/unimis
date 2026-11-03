-- Package 002c: Employee Master + employment classification + compensation history + private photos.
alter table public.hr_employees
  add column if not exists photo_path text,
  add column if not exists employment_type text not null default 'regular',
  add column if not exists work_schedule text not null default 'full_time',
  add column if not exists pension_status text not null default 'applicable';

alter table public.hr_employment_contracts
  add column if not exists pay_basis text not null default 'monthly',
  add column if not exists daily_rate numeric(14,2) not null default 0,
  add column if not exists hourly_rate numeric(14,2) not null default 0,
  add column if not exists probation_end_date date,
  add column if not exists notice_days integer not null default 30;

create table if not exists public.hr_salary_history (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete cascade,
 employee_id uuid not null references public.hr_employees(id) on delete cascade,
 old_salary numeric(14,2), new_salary numeric(14,2) not null,
 change_type text not null default 'initial' check(change_type in ('initial','manual','grade_step','promotion','bulk_adjustment','correction')),
 reason text, effective_from date not null, approved_by uuid references auth.users(id), created_by uuid references auth.users(id), created_at timestamptz default now()
);
create index if not exists hr_salary_history_employee_idx on public.hr_salary_history(employee_id,effective_from desc);
alter table public.hr_salary_history enable row level security;
drop policy if exists hr_salary_history_tenant on public.hr_salary_history;
create policy hr_salary_history_tenant on public.hr_salary_history for all to authenticated using(public.is_tenant_member(tenant_id)) with check(public.is_tenant_member(tenant_id));

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('employee-photos','employee-photos',false,5242880,array['image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists employee_photos_read on storage.objects;
create policy employee_photos_read on storage.objects for select to authenticated
using(bucket_id='employee-photos' and public.is_tenant_member(((storage.foldername(name))[1])::uuid));
drop policy if exists employee_photos_insert on storage.objects;
create policy employee_photos_insert on storage.objects for insert to authenticated
with check(bucket_id='employee-photos' and public.has_tenant_role(((storage.foldername(name))[1])::uuid,array['owner','administrator','hr_manager','hr_officer']));
drop policy if exists employee_photos_update on storage.objects;
create policy employee_photos_update on storage.objects for update to authenticated
using(bucket_id='employee-photos' and public.has_tenant_role(((storage.foldername(name))[1])::uuid,array['owner','administrator','hr_manager','hr_officer']))
with check(bucket_id='employee-photos' and public.has_tenant_role(((storage.foldername(name))[1])::uuid,array['owner','administrator','hr_manager','hr_officer']));

-- Replace Package 002b employee RPC with richer employment master signature.
drop function if exists public.hr_create_employee(uuid,text,text,text,text,uuid,uuid,date,date,numeric);
create or replace function public.hr_create_employee(
 p_tenant uuid,p_employee_no text,p_first_name text,p_last_name text,p_email text,
 p_department uuid,p_position uuid,p_date_of_birth date,p_hire_date date,p_basic_salary numeric,
 p_employment_type text default 'regular',p_work_schedule text default 'full_time',p_pay_basis text default 'monthly',
 p_contract_end date default null,p_pension_status text default 'applicable'
) returns uuid language plpgsql security definer set search_path=public as $$
declare e uuid; g uuid;
begin
 if not public.has_tenant_role(p_tenant,array['owner','administrator','hr_manager','hr_officer']) then raise exception 'HR access denied'; end if;
 if p_date_of_birth is not null and p_date_of_birth > current_date then raise exception 'Date of birth cannot be in the future'; end if;
 if p_employment_type not in ('regular','fixed_term','casual','temporary','intern','national_service','consultant') then raise exception 'Invalid employment type'; end if;
 if p_work_schedule not in ('full_time','part_time','shift','hourly') then raise exception 'Invalid work schedule'; end if;
 if p_pay_basis not in ('monthly','weekly','daily','hourly') then raise exception 'Invalid pay basis'; end if;
 insert into public.hr_employees(tenant_id,employee_no,first_name,last_name,email,department_id,position_id,date_of_birth,hire_date,employment_type,work_schedule,pension_status)
 values(p_tenant,upper(trim(p_employee_no)),trim(p_first_name),trim(p_last_name),nullif(trim(p_email),''),p_department,p_position,p_date_of_birth,p_hire_date,p_employment_type,p_work_schedule,p_pension_status)
 returning id into e;
 insert into public.hr_employment_contracts(tenant_id,employee_id,contract_type,start_date,end_date,basic_salary,pay_frequency,pay_basis)
 values(p_tenant,e,p_employment_type,coalesce(p_hire_date,current_date),p_contract_end,coalesce(p_basic_salary,0),p_pay_basis,p_pay_basis);
 insert into public.hr_salary_history(tenant_id,employee_id,new_salary,change_type,reason,effective_from,created_by)
 values(p_tenant,e,coalesce(p_basic_salary,0),'initial','Initial appointment',coalesce(p_hire_date,current_date),auth.uid());
 select id into g from public.payroll_pay_groups where tenant_id=p_tenant and active order by created_at limit 1;
 insert into public.payroll_profiles(tenant_id,employee_id,pay_group_id) values(p_tenant,e,g);
 insert into public.audit_events(tenant_id,actor_id,module,action,record_type,record_id,details)
 values(p_tenant,auth.uid(),'hr','employee.created','employee',e,jsonb_build_object('employment_type',p_employment_type,'pay_basis',p_pay_basis));
 return e;
end $$;
grant execute on function public.hr_create_employee(uuid,text,text,text,text,uuid,uuid,date,date,numeric,text,text,text,date,text) to authenticated;

create or replace function public.hr_change_salary(p_tenant uuid,p_employee uuid,p_new_salary numeric,p_effective date,p_change_type text default 'manual',p_reason text default null)
returns uuid language plpgsql security definer set search_path=public as $$
declare c uuid; oldv numeric; h uuid;
begin
 if not public.has_tenant_role(p_tenant,array['owner','administrator','hr_manager','payroll_manager']) then raise exception 'Salary change access denied'; end if;
 if p_new_salary < 0 then raise exception 'Salary cannot be negative'; end if;
 select id,basic_salary into c,oldv from public.hr_employment_contracts where tenant_id=p_tenant and employee_id=p_employee and status='active' order by start_date desc limit 1;
 if c is null then raise exception 'Active contract not found'; end if;
 update public.hr_employment_contracts set basic_salary=p_new_salary where id=c;
 insert into public.hr_salary_history(tenant_id,employee_id,old_salary,new_salary,change_type,reason,effective_from,approved_by,created_by)
 values(p_tenant,p_employee,oldv,p_new_salary,p_change_type,p_reason,coalesce(p_effective,current_date),auth.uid(),auth.uid()) returning id into h;
 return h;
end $$;
grant execute on function public.hr_change_salary(uuid,uuid,numeric,date,text,text) to authenticated;
