-- Package 004b: governed career actions, separation and rehire.
create table if not exists public.hr_employee_lifecycle_actions(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.tenants(id) on delete cascade,
 employee_id uuid not null references public.hr_employees(id) on delete cascade,
 action_type text not null, effective_date date not null, reason_category text, reason_details text,
 old_department_id uuid references public.departments(id), new_department_id uuid references public.departments(id),
 old_position_id uuid references public.hr_positions(id), new_position_id uuid references public.hr_positions(id),
 old_employment_type text, new_employment_type text, new_salary numeric(14,2), notice_date date, last_working_date date,
 supporting_reference text, status text not null default 'submitted', submitted_by uuid references auth.users(id),
 approved_by uuid references auth.users(id), approved_at timestamptz, applied_at timestamptz, created_at timestamptz default now(),
 constraint lifecycle_action_type_ck check(action_type in ('promotion','transfer','demotion','acting_appointment','grade_change','contract_renewal','secondment','suspension','reinstatement','award','resignation','termination','dismissal','retirement','contract_end','redundancy','death_in_service','rehire')),
 constraint lifecycle_status_ck check(status in ('draft','submitted','approved','rejected','applied'))
);
alter table public.hr_employee_lifecycle_actions enable row level security;
drop policy if exists lifecycle_read on public.hr_employee_lifecycle_actions;
create policy lifecycle_read on public.hr_employee_lifecycle_actions for select using(public.is_tenant_member(tenant_id));
drop policy if exists lifecycle_insert on public.hr_employee_lifecycle_actions;
create policy lifecycle_insert on public.hr_employee_lifecycle_actions for insert with check(public.has_tenant_role(tenant_id,array['owner','administrator','hr_manager','hr_officer']));
drop policy if exists lifecycle_update on public.hr_employee_lifecycle_actions;
create policy lifecycle_update on public.hr_employee_lifecycle_actions for update using(public.has_tenant_role(tenant_id,array['owner','administrator','hr_manager'])) with check(public.has_tenant_role(tenant_id,array['owner','administrator','hr_manager']));

create or replace function public.hr_submit_lifecycle_action(p_tenant uuid,p_employee uuid,p_action_type text,p_effective_date date,p_reason_category text default null,p_reason_details text default null,p_new_position uuid default null,p_new_department uuid default null,p_new_employment_type text default null,p_new_salary numeric default null,p_last_working_date date default null,p_notice_date date default null,p_supporting_reference text default null)
returns uuid language plpgsql security definer set search_path=public as $$
declare e public.hr_employees%rowtype; x uuid;
begin
 if not public.has_tenant_role(p_tenant,array['owner','administrator','hr_manager','hr_officer']) then raise exception 'HR access denied'; end if;
 select * into e from public.hr_employees where id=p_employee and tenant_id=p_tenant;
 if e.id is null then raise exception 'Employee not found'; end if;
 if p_action_type='rehire' and e.employment_status='active' then raise exception 'Employee is already active'; end if;
 if p_action_type in ('resignation','termination','dismissal','retirement','contract_end','redundancy','death_in_service') and e.employment_status<>'active' then raise exception 'Only an active employee can be separated'; end if;
 insert into public.hr_employee_lifecycle_actions(tenant_id,employee_id,action_type,effective_date,reason_category,reason_details,old_department_id,new_department_id,old_position_id,new_position_id,old_employment_type,new_employment_type,new_salary,last_working_date,notice_date,supporting_reference,status,submitted_by)
 values(p_tenant,p_employee,p_action_type,coalesce(p_effective_date,current_date),p_reason_category,p_reason_details,e.department_id,p_new_department,e.position_id,p_new_position,e.employment_type,p_new_employment_type,p_new_salary,p_last_working_date,p_notice_date,p_supporting_reference,'submitted',auth.uid()) returning id into x;
 return x;
end $$;
grant execute on function public.hr_submit_lifecycle_action(uuid,uuid,text,date,text,text,uuid,uuid,text,numeric,date,date,text) to authenticated;

create or replace function public.hr_approve_lifecycle_action(p_tenant uuid,p_action uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare a public.hr_employee_lifecycle_actions%rowtype; e public.hr_employees%rowtype; new_status text;
begin
 if not public.has_tenant_role(p_tenant,array['owner','administrator','hr_manager']) then raise exception 'Approval access denied'; end if;
 select * into a from public.hr_employee_lifecycle_actions where id=p_action and tenant_id=p_tenant for update;
 if a.id is null then raise exception 'Action not found'; end if;
 if a.status<>'submitted' then raise exception 'Action is not awaiting approval'; end if;
 select * into e from public.hr_employees where id=a.employee_id and tenant_id=p_tenant for update;
 if a.action_type in ('promotion','transfer','demotion','acting_appointment','grade_change','secondment') then
   update public.hr_employees set department_id=coalesce(a.new_department_id,department_id),position_id=coalesce(a.new_position_id,position_id) where id=e.id;
 elsif a.action_type='suspension' then update public.hr_employees set employment_status='suspended' where id=e.id;
 elsif a.action_type='reinstatement' then update public.hr_employees set employment_status='active' where id=e.id;
 elsif a.action_type in ('resignation','termination','dismissal','retirement','contract_end','redundancy','death_in_service') then
   new_status=case a.action_type when 'resignation' then 'resigned' when 'retirement' then 'retired' when 'death_in_service' then 'deceased' when 'contract_end' then 'contract_ended' else 'terminated' end;
   update public.hr_employees set employment_status=new_status where id=e.id;
   update public.payroll_profiles set active=false where employee_id=e.id;
   update public.hr_employment_contracts set status='ended',end_date=coalesce(a.last_working_date,a.effective_date) where employee_id=e.id and status='active';
 elsif a.action_type='rehire' then
   update public.hr_employees set employment_status='active',hire_date=a.effective_date,department_id=coalesce(a.new_department_id,department_id),position_id=coalesce(a.new_position_id,position_id),employment_type=coalesce(a.new_employment_type,employment_type) where id=e.id;
   update public.payroll_profiles set active=true where employee_id=e.id;
   insert into public.hr_employment_contracts(tenant_id,employee_id,contract_type,start_date,basic_salary,pay_frequency,status) values(p_tenant,e.id,coalesce(a.new_employment_type,'regular'),a.effective_date,coalesce(a.new_salary,0),'monthly','active');
 end if;
 update public.hr_employee_lifecycle_actions set status='applied',approved_by=auth.uid(),approved_at=now(),applied_at=now() where id=a.id;
 perform public.hr_record_employment_event(p_tenant,e.id,a.action_type,a.effective_date,initcap(replace(a.action_type,'_',' ')),jsonb_build_object('lifecycle_action_id',a.id,'reason_category',a.reason_category,'reason_details',a.reason_details,'old_department_id',a.old_department_id,'new_department_id',a.new_department_id,'old_position_id',a.old_position_id,'new_position_id',a.new_position_id,'last_working_date',a.last_working_date));
 return jsonb_build_object('ok',true,'employee_id',e.id,'action',a.action_type);
end $$;
grant execute on function public.hr_approve_lifecycle_action(uuid,uuid) to authenticated;
notify pgrst, 'reload schema';
