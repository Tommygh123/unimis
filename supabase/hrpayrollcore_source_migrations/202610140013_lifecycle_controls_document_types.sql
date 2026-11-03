-- Package 004e: lifecycle controls, richer HR document types, duplicate prevention.
update storage.buckets
set allowed_mime_types = array[
 'application/pdf','image/jpeg','image/png','image/webp',
 'application/msword','application/vnd.openxmlformats-officedocument.wordprocessingml.document',
 'application/vnd.ms-excel','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
]
where id='employee-documents';

alter table public.hr_employee_lifecycle_actions
  add column if not exists rejected_by uuid references auth.users(id),
  add column if not exists rejected_at timestamptz,
  add column if not exists cancelled_by uuid references auth.users(id),
  add column if not exists cancelled_at timestamptz,
  add column if not exists decision_notes text;

alter table public.hr_employee_lifecycle_actions drop constraint if exists lifecycle_status_ck;
alter table public.hr_employee_lifecycle_actions add constraint lifecycle_status_ck
 check(status in ('draft','submitted','approved','rejected','cancelled','applied'));

create or replace function public.hr_submit_lifecycle_action(p_tenant uuid,p_employee uuid,p_action_type text,p_effective_date date,p_reason_category text default null,p_reason_details text default null,p_new_position uuid default null,p_new_department uuid default null,p_new_employment_type text default null,p_new_salary numeric default null,p_last_working_date date default null,p_notice_date date default null,p_supporting_reference text default null)
returns uuid language plpgsql security definer set search_path=public as $$
declare e public.hr_employees%rowtype; x uuid; pending_count integer;
begin
 if not public.has_tenant_role(p_tenant,array['owner','administrator','hr_manager','hr_officer']) then raise exception 'HR access denied'; end if;
 select * into e from public.hr_employees where id=p_employee and tenant_id=p_tenant;
 if e.id is null then raise exception 'Employee not found'; end if;
 if p_action_type='rehire' and e.employment_status='active' then raise exception 'Employee is already active'; end if;
 if p_action_type in ('resignation','termination','dismissal','retirement','contract_end','redundancy','death_in_service') and e.employment_status<>'active' then raise exception 'Only an active employee can be separated'; end if;
 if p_action_type in ('resignation','termination','dismissal','retirement','contract_end','redundancy','death_in_service') then
   select count(*) into pending_count from public.hr_employee_lifecycle_actions
    where tenant_id=p_tenant and employee_id=p_employee and status='submitted'
      and action_type in ('resignation','termination','dismissal','retirement','contract_end','redundancy','death_in_service');
   if pending_count>0 then raise exception 'A separation request is already awaiting approval. Approve, reject or cancel it before submitting another.'; end if;
 end if;
 insert into public.hr_employee_lifecycle_actions(tenant_id,employee_id,action_type,effective_date,reason_category,reason_details,old_department_id,new_department_id,old_position_id,new_position_id,old_employment_type,new_employment_type,new_salary,last_working_date,notice_date,supporting_reference,status,submitted_by)
 values(p_tenant,p_employee,p_action_type,coalesce(p_effective_date,current_date),p_reason_category,p_reason_details,e.department_id,p_new_department,e.position_id,p_new_position,e.employment_type,p_new_employment_type,p_new_salary,p_last_working_date,p_notice_date,p_supporting_reference,'submitted',auth.uid()) returning id into x;
 return x;
end $$;
grant execute on function public.hr_submit_lifecycle_action(uuid,uuid,text,date,text,text,uuid,uuid,text,numeric,date,date,text) to authenticated;

create or replace function public.hr_reject_lifecycle_action(p_tenant uuid,p_action uuid,p_notes text default null)
returns void language plpgsql security definer set search_path=public as $$
begin
 if not public.has_tenant_role(p_tenant,array['owner','administrator','hr_manager']) then raise exception 'Approval access denied'; end if;
 update public.hr_employee_lifecycle_actions set status='rejected',rejected_by=auth.uid(),rejected_at=now(),decision_notes=p_notes
 where id=p_action and tenant_id=p_tenant and status='submitted';
 if not found then raise exception 'Action is not awaiting approval'; end if;
end $$;
grant execute on function public.hr_reject_lifecycle_action(uuid,uuid,text) to authenticated;

create or replace function public.hr_cancel_lifecycle_action(p_tenant uuid,p_action uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
 if not public.has_tenant_role(p_tenant,array['owner','administrator','hr_manager','hr_officer']) then raise exception 'HR access denied'; end if;
 update public.hr_employee_lifecycle_actions set status='cancelled',cancelled_by=auth.uid(),cancelled_at=now()
 where id=p_action and tenant_id=p_tenant and status='submitted';
 if not found then raise exception 'Only a submitted action can be cancelled'; end if;
end $$;
grant execute on function public.hr_cancel_lifecycle_action(uuid,uuid) to authenticated;

notify pgrst, 'reload schema';
