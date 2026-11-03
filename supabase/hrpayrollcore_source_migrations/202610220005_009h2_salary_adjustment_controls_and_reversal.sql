-- 009h2: salary adjustment safety controls, duplicate prevention, stale-preview protection and audited reversal.

alter table public.hr_salary_history
  add column if not exists source_salary_batch_id uuid references public.payroll_salary_change_batches(id) on delete set null;

alter table public.payroll_salary_change_batches
  add column if not exists reversal_reason text,
  add column if not exists reversed_by uuid references auth.users(id),
  add column if not exists reversed_at timestamptz;

alter table public.payroll_salary_change_batches drop constraint if exists payroll_salary_change_batches_status_check;
alter table public.payroll_salary_change_batches add constraint payroll_salary_change_batches_status_check
  check(status in ('draft','approved','applied','cancelled','reversed'));

create index if not exists hr_salary_history_source_batch_idx on public.hr_salary_history(source_salary_batch_id);

create or replace function public.payroll_create_scoped_salary_batch(
 p_tenant uuid,p_scope text,p_scope_value text,p_mode text,p_value numeric,p_effective date,p_reason text default null
) returns jsonb language plpgsql security definer set search_path=public as $$
declare b uuid; bn text; r record; oldv numeric; newv numeric; n integer:=0; lbl text; dup record;
begin
 if not public.has_tenant_role(p_tenant,array['owner','administrator','payroll_manager','hr_manager']) then raise exception 'Salary change access denied'; end if;
 if p_scope not in ('employee','department','position','grade','employment_type','employment_status','all') then raise exception 'Invalid salary adjustment scope'; end if;
 if p_mode not in ('percentage','fixed','set_salary') then raise exception 'Invalid salary adjustment method'; end if;
 if coalesce(p_value,0)<=0 then raise exception 'Adjustment value must be greater than zero'; end if;
 if p_effective is null then raise exception 'Effective date is required'; end if;
 if p_scope<>'all' and nullif(trim(coalesce(p_scope_value,'')),'') is null then raise exception 'Select an employee/category'; end if;

 select id,batch_no,status into dup from public.payroll_salary_change_batches
 where tenant_id=p_tenant and coalesce(scope_type,'all')=p_scope
   and coalesce(scope_value,'')=coalesce(p_scope_value,'')
   and change_mode=p_mode and value=p_value and effective_date=p_effective
   and status in ('draft','applied')
 order by created_at desc limit 1;
 if dup.id is not null then
   raise exception 'Possible duplicate salary adjustment: batch % is already %. Review that batch instead of creating another identical adjustment.',dup.batch_no,dup.status;
 end if;

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
  select e.id from public.hr_employees e left join public.hr_positions pos on pos.id=e.position_id
  where e.tenant_id=p_tenant and e.employment_status='active'
   and case p_scope when 'all' then true when 'employee' then e.id=p_scope_value::uuid when 'department' then e.department_id=p_scope_value::uuid
    when 'position' then e.position_id=p_scope_value::uuid when 'grade' then pos.grade_id=p_scope_value::uuid
    when 'employment_type' then lower(coalesce(e.employment_type,''))=lower(p_scope_value)
    when 'employment_status' then lower(coalesce(e.employment_status,''))=lower(p_scope_value) else false end
 loop
  select coalesce((select sh.new_salary from public.hr_salary_history sh where sh.employee_id=r.id and sh.effective_from<=p_effective order by sh.effective_from desc,sh.created_at desc limit 1),(select c.basic_salary from public.hr_employment_contracts c where c.employee_id=r.id and c.status='active' order by c.start_date desc limit 1),0) into oldv;
  newv:=case when p_mode='percentage' then round(oldv*(1+p_value/100),2) when p_mode='fixed' then round(oldv+p_value,2) when p_mode='set_salary' then round(p_value,2) else oldv end;
  insert into public.payroll_salary_change_items(tenant_id,batch_id,employee_id,old_salary,new_salary) values(p_tenant,b,r.id,oldv,newv); n:=n+1;
 end loop;
 if n=0 then delete from public.payroll_salary_change_batches where id=b; raise exception 'No active employees matched the selected category'; end if;
 return jsonb_build_object('batch_id',b,'affected',n,'scope',p_scope,'scope_label',lbl,'batch_no',bn);
end $$;

grant execute on function public.payroll_create_scoped_salary_batch(uuid,text,text,text,numeric,date,text) to authenticated;

create or replace function public.payroll_apply_salary_batch(p_tenant uuid,p_batch uuid)
returns void language plpgsql security definer set search_path=public as $$
declare r record; d date; rs text; bn text; currentv numeric;
begin
 if not public.has_tenant_role(p_tenant,array['owner','administrator','payroll_manager']) then raise exception 'Salary approval access denied'; end if;
 select effective_date,reason,batch_no into d,rs,bn from public.payroll_salary_change_batches where id=p_batch and tenant_id=p_tenant and status='draft';
 if d is null then raise exception 'Draft batch not found or it has already been processed'; end if;
 for r in select * from public.payroll_salary_change_items where batch_id=p_batch order by employee_id loop
  select coalesce((select sh.new_salary from public.hr_salary_history sh where sh.employee_id=r.employee_id and sh.effective_from<=d order by sh.effective_from desc,sh.created_at desc limit 1),(select c.basic_salary from public.hr_employment_contracts c where c.employee_id=r.employee_id and c.status='active' order by c.start_date desc limit 1),0) into currentv;
  if round(currentv,2)<>round(r.old_salary,2) then
    raise exception 'Preview is stale for an employee: current salary is %, but this draft was prepared from %. Cancel/recreate the draft and review again.',currentv,r.old_salary;
  end if;
 end loop;
 for r in select * from public.payroll_salary_change_items where batch_id=p_batch loop
  insert into public.hr_salary_history(tenant_id,employee_id,old_salary,new_salary,change_type,reason,effective_from,approved_by,created_by,source_salary_batch_id)
  values(p_tenant,r.employee_id,r.old_salary,r.new_salary,'bulk_adjustment',rs,d,auth.uid(),auth.uid(),p_batch);
  if d<=current_date then update public.hr_employment_contracts set basic_salary=r.new_salary where tenant_id=p_tenant and employee_id=r.employee_id and status='active'; end if;
 end loop;
 update public.payroll_salary_change_batches set status='applied',approved_by=auth.uid() where id=p_batch and tenant_id=p_tenant;
end $$;
grant execute on function public.payroll_apply_salary_batch(uuid,uuid) to authenticated;

create or replace function public.payroll_cancel_salary_batch(p_tenant uuid,p_batch uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
 if not public.has_tenant_role(p_tenant,array['owner','administrator','payroll_manager','hr_manager']) then raise exception 'Salary change access denied'; end if;
 update public.payroll_salary_change_batches set status='cancelled'
 where tenant_id=p_tenant and id=p_batch and status='draft';
 if not found then raise exception 'Only a draft salary adjustment can be cancelled'; end if;
end $$;
grant execute on function public.payroll_cancel_salary_batch(uuid,uuid) to authenticated;

create or replace function public.payroll_reverse_salary_batch(p_tenant uuid,p_batch uuid,p_reason text)
returns void language plpgsql security definer set search_path=public as $$
declare r record; d date; bn text; currentv numeric; revdate date:=current_date;
begin
 if not public.has_tenant_role(p_tenant,array['owner','administrator','payroll_manager']) then raise exception 'Salary reversal access denied'; end if;
 if nullif(trim(coalesce(p_reason,'')),'') is null then raise exception 'Enter a reversal reason / authority'; end if;
 select effective_date,batch_no into d,bn from public.payroll_salary_change_batches where tenant_id=p_tenant and id=p_batch and status='applied';
 if d is null then raise exception 'Only an applied salary batch can be reversed'; end if;
 for r in select * from public.payroll_salary_change_items where batch_id=p_batch order by employee_id loop
  select coalesce((select sh.new_salary from public.hr_salary_history sh where sh.employee_id=r.employee_id and sh.effective_from<=current_date order by sh.effective_from desc,sh.created_at desc limit 1),(select c.basic_salary from public.hr_employment_contracts c where c.employee_id=r.employee_id and c.status='active' order by c.start_date desc limit 1),0) into currentv;
  if round(currentv,2)<>round(r.new_salary,2) then
    raise exception 'Batch % cannot be reversed because a later salary change exists for an affected employee (current %, batch result %). Reverse the latest applicable change first.',bn,currentv,r.new_salary;
  end if;
 end loop;
 for r in select * from public.payroll_salary_change_items where batch_id=p_batch loop
  insert into public.hr_salary_history(tenant_id,employee_id,old_salary,new_salary,change_type,reason,effective_from,approved_by,created_by,source_salary_batch_id)
  values(p_tenant,r.employee_id,r.new_salary,r.old_salary,'salary_adjustment_reversal','Reversal of '||bn||': '||trim(p_reason),greatest(d,revdate),auth.uid(),auth.uid(),p_batch);
  if greatest(d,revdate)<=current_date then update public.hr_employment_contracts set basic_salary=r.old_salary where tenant_id=p_tenant and employee_id=r.employee_id and status='active'; end if;
 end loop;
 update public.payroll_salary_change_batches set status='reversed',reversal_reason=trim(p_reason),reversed_by=auth.uid(),reversed_at=now() where tenant_id=p_tenant and id=p_batch;
end $$;
grant execute on function public.payroll_reverse_salary_batch(uuid,uuid,text) to authenticated;

notify pgrst,'reload schema';
