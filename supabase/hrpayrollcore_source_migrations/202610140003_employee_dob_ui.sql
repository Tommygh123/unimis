-- Package 002b: employee DOB foundation for age-aware payroll/statutory processing.
alter table public.hr_employees add column if not exists date_of_birth date;

-- Replace the employee creation RPC with a DOB-aware signature.
drop function if exists public.hr_create_employee(uuid,text,text,text,text,uuid,uuid,date,numeric);
create or replace function public.hr_create_employee(
 p_tenant uuid,p_employee_no text,p_first_name text,p_last_name text,p_email text,
 p_department uuid,p_position uuid,p_date_of_birth date,p_hire_date date,p_basic_salary numeric
) returns uuid language plpgsql security definer set search_path=public as $$
declare e uuid; g uuid;
begin
 if not public.has_tenant_role(p_tenant,array['owner','administrator','hr_manager','hr_officer']) then raise exception 'HR access denied'; end if;
 if p_date_of_birth is not null and p_date_of_birth > current_date then raise exception 'Date of birth cannot be in the future'; end if;
 insert into public.hr_employees(tenant_id,employee_no,first_name,last_name,email,department_id,position_id,date_of_birth,hire_date)
 values(p_tenant,upper(trim(p_employee_no)),trim(p_first_name),trim(p_last_name),nullif(trim(p_email),''),p_department,p_position,p_date_of_birth,p_hire_date)
 returning id into e;
 insert into public.hr_employment_contracts(tenant_id,employee_id,start_date,basic_salary)
 values(p_tenant,e,coalesce(p_hire_date,current_date),coalesce(p_basic_salary,0));
 select id into g from public.payroll_pay_groups where tenant_id=p_tenant and active order by created_at limit 1;
 insert into public.payroll_profiles(tenant_id,employee_id,pay_group_id) values(p_tenant,e,g);
 insert into public.audit_events(tenant_id,actor_id,module,action,record_type,record_id)
 values(p_tenant,auth.uid(),'hr','employee.created','employee',e);
 return e;
end $$;
grant execute on function public.hr_create_employee(uuid,text,text,text,text,uuid,uuid,date,date,numeric) to authenticated;

comment on column public.hr_employees.date_of_birth is 'Employee date of birth; supports age-aware statutory eligibility, retirement/pension handling, birthday workflows and HR reporting.';
