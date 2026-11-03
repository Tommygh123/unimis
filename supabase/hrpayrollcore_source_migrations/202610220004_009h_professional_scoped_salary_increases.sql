-- 009h: professional scoped salary adjustments.
-- Adds auditable scope metadata and creates preview batches for an individual or selected employee category.
alter table public.payroll_salary_change_batches
  add column if not exists scope_type text,
  add column if not exists scope_value text,
  add column if not exists scope_label text;

alter table public.payroll_salary_change_batches drop constraint if exists payroll_salary_change_batches_change_mode_check;
alter table public.payroll_salary_change_batches add constraint payroll_salary_change_batches_change_mode_check
  check (change_mode in ('percentage','fixed','grade_step','manual','set_salary'));

create or replace function public.payroll_create_scoped_salary_batch(
 p_tenant uuid,p_scope text,p_scope_value text,p_mode text,p_value numeric,p_effective date,p_reason text default null
) returns jsonb language plpgsql security definer set search_path=public as $$
declare b uuid; bn text; r record; oldv numeric; newv numeric; n integer:=0; lbl text;
begin
 if not public.has_tenant_role(p_tenant,array['owner','administrator','payroll_manager','hr_manager']) then raise exception 'Salary change access denied'; end if;
 if p_scope not in ('employee','department','position','grade','employment_type','employment_status','all') then raise exception 'Invalid salary adjustment scope'; end if;
 if p_mode not in ('percentage','fixed','set_salary') then raise exception 'Invalid salary adjustment method'; end if;
 if coalesce(p_value,0)<=0 then raise exception 'Adjustment value must be greater than zero'; end if;
 if p_effective is null then raise exception 'Effective date is required'; end if;
 if p_scope<>'all' and nullif(trim(coalesce(p_scope_value,'')),'') is null then raise exception 'Select an employee/category'; end if;

 lbl:=case p_scope
  when 'all' then 'All active employees'
  when 'employee' then (select employee_no||' · '||first_name||' '||last_name from public.hr_employees where tenant_id=p_tenant and id=p_scope_value::uuid)
  when 'department' then (select name from public.departments where tenant_id=p_tenant and id=p_scope_value::uuid)
  when 'position' then (select title from public.hr_positions where tenant_id=p_tenant and id=p_scope_value::uuid)
  when 'grade' then (select code||' · '||name from public.hr_job_grades where tenant_id=p_tenant and id=p_scope_value::uuid)
  else initcap(replace(p_scope_value,'_',' ')) end;

 bn:='SAL-'||to_char(clock_timestamp(),'YYYYMMDDHH24MISSMS');
 insert into public.payroll_salary_change_batches(tenant_id,batch_no,change_mode,value,effective_date,reason,status,scope_type,scope_value,scope_label,created_by)
 values(p_tenant,bn,p_mode,p_value,p_effective,p_reason,'draft',p_scope,p_scope_value,lbl,auth.uid()) returning id into b;

 for r in
  select e.id
  from public.hr_employees e
  left join public.hr_positions pos on pos.id=e.position_id
  where e.tenant_id=p_tenant and e.employment_status='active'
   and case p_scope
    when 'all' then true
    when 'employee' then e.id=p_scope_value::uuid
    when 'department' then e.department_id=p_scope_value::uuid
    when 'position' then e.position_id=p_scope_value::uuid
    when 'grade' then pos.grade_id=p_scope_value::uuid
    when 'employment_type' then lower(coalesce(e.employment_type,''))=lower(p_scope_value)
    when 'employment_status' then lower(coalesce(e.employment_status,''))=lower(p_scope_value)
    else false end
 loop
  select coalesce(
   (select sh.new_salary from public.hr_salary_history sh where sh.employee_id=r.id and sh.effective_from<=p_effective order by sh.effective_from desc,sh.created_at desc limit 1),
   (select c.basic_salary from public.hr_employment_contracts c where c.employee_id=r.id and c.status='active' order by c.start_date desc limit 1),0) into oldv;
  newv:=case when p_mode='percentage' then round(oldv*(1+p_value/100),2) when p_mode='fixed' then round(oldv+p_value,2) when p_mode='set_salary' then round(p_value,2) else oldv end;
  insert into public.payroll_salary_change_items(tenant_id,batch_id,employee_id,old_salary,new_salary) values(p_tenant,b,r.id,oldv,newv);
  n:=n+1;
 end loop;
 if n=0 then delete from public.payroll_salary_change_batches where id=b; raise exception 'No active employees matched the selected category'; end if;
 return jsonb_build_object('batch_id',b,'affected',n,'scope',p_scope,'scope_label',lbl);
end $$;
grant execute on function public.payroll_create_scoped_salary_batch(uuid,text,text,text,numeric,date,text) to authenticated;
notify pgrst,'reload schema';
