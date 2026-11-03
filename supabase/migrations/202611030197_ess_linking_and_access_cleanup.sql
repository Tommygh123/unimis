-- Build 197 production migration: secure ESS account-to-employee linking.


create or replace function public.unimis_ess_context197(p_institution_id uuid)
returns jsonb language plpgsql security definer set search_path=public,auth,pg_temp as $$
declare v_email text; v_employee public.hrc_hr_employees%rowtype;
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 if not exists(select 1 from public.institution_users where institution_id=p_institution_id and user_id=auth.uid() and status='active')
 then raise exception 'Institution access denied'; end if;

 -- Prefer the permanent Auth-user link. Fall back to email once, then save the link.
 select * into v_employee from public.hrc_hr_employees
 where tenant_id=p_institution_id and auth_user_id=auth.uid() and employment_status='active' limit 1;
 if v_employee.id is null then
   select lower(email) into v_email from auth.users where id=auth.uid();
   select * into v_employee from public.hrc_hr_employees
   where tenant_id=p_institution_id and lower(coalesce(email,''))=v_email and employment_status='active' limit 1;
   if v_employee.id is not null and v_employee.auth_user_id is null then
     update public.hrc_hr_employees set auth_user_id=auth.uid() where id=v_employee.id;
     select * into v_employee from public.hrc_hr_employees where id=v_employee.id;
   end if;
 end if;
 if v_employee.id is null then
   return jsonb_build_object('employee',null,'attendance','[]'::jsonb,'leaves','[]'::jsonb,'leave_types','[]'::jsonb,'payslips','[]'::jsonb);
 end if;
 return jsonb_build_object(
 'employee',to_jsonb(v_employee),
 'attendance',coalesce((select jsonb_agg(to_jsonb(x) order by x.work_date desc) from (select * from public.hrc_hr_attendance_records where tenant_id=p_institution_id and employee_id=v_employee.id order by work_date desc limit 31)x),'[]'::jsonb),
 'leaves',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from (select * from public.hrc_hr_leave_requests where tenant_id=p_institution_id and employee_id=v_employee.id order by created_at desc)x),'[]'::jsonb),
 'leave_types',coalesce((select jsonb_agg(to_jsonb(x) order by x.name) from (select * from public.hrc_hr_leave_types where tenant_id=p_institution_id and active=true order by name)x),'[]'::jsonb),
 'payslips',coalesce((select jsonb_agg(to_jsonb(x) order by x.issued_at desc) from (select * from public.hrc_payroll_payslips where tenant_id=p_institution_id and employee_id=v_employee.id order by issued_at desc limit 12)x),'[]'::jsonb));
end $$;

create or replace function public.unimis_ess_submit_leave197(p_institution_id uuid,p_leave_type_id uuid,p_start_date date,p_end_date date,p_reason text)
returns uuid language plpgsql security definer set search_path=public,auth,pg_temp as $$
declare v_employee_id uuid; v_email text; v_id uuid;
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 if p_end_date<p_start_date then raise exception 'End date cannot be before start date'; end if;
 if nullif(trim(p_reason),'') is null then raise exception 'Leave reason is required'; end if;
 if not exists(select 1 from public.institution_users where institution_id=p_institution_id and user_id=auth.uid() and status='active') then raise exception 'Institution access denied'; end if;
 select id into v_employee_id from public.hrc_hr_employees where tenant_id=p_institution_id and auth_user_id=auth.uid() and employment_status='active' limit 1;
 if v_employee_id is null then
   select lower(email) into v_email from auth.users where id=auth.uid();
   select id into v_employee_id from public.hrc_hr_employees where tenant_id=p_institution_id and lower(coalesce(email,''))=v_email and employment_status='active' limit 1;
   if v_employee_id is not null then update public.hrc_hr_employees set auth_user_id=coalesce(auth_user_id,auth.uid()) where id=v_employee_id; end if;
 end if;
 if v_employee_id is null then raise exception 'Employee record not linked'; end if;
 if not exists(select 1 from public.hrc_hr_leave_types where id=p_leave_type_id and tenant_id=p_institution_id and active=true) then raise exception 'Invalid leave type'; end if;
 insert into public.hrc_hr_leave_requests(tenant_id,employee_id,leave_type_id,start_date,end_date,reason,status,created_by)
 values(p_institution_id,v_employee_id,p_leave_type_id,p_start_date,p_end_date,trim(p_reason),'submitted',auth.uid()) returning id into v_id;
 return v_id;
end $$;

revoke all on function public.unimis_ess_context197(uuid) from public;
revoke all on function public.unimis_ess_submit_leave197(uuid,uuid,date,date,text) from public;
grant execute on function public.unimis_ess_context197(uuid) to authenticated;
grant execute on function public.unimis_ess_submit_leave197(uuid,uuid,date,date,text) to authenticated;
