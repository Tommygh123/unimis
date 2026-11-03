-- 011u Attendance Administration & Historical Import
create table if not exists public.hr_attendance_change_audit(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.tenants(id) on delete cascade,
 attendance_id uuid references public.hr_attendance_records(id) on delete set null, employee_id uuid not null references public.hr_employees(id) on delete cascade,
 work_date date not null, action text not null check(action in ('create','correct','import_create','import_correct')),
 reason text not null, old_record jsonb, new_record jsonb, changed_by uuid default auth.uid(), changed_at timestamptz not null default now()
);
alter table public.hr_attendance_change_audit enable row level security;
drop policy if exists attendance_change_audit_member_select on public.hr_attendance_change_audit;
create policy attendance_change_audit_member_select on public.hr_attendance_change_audit for select to authenticated using(public.is_tenant_member(tenant_id));
create index if not exists idx_attendance_change_audit_tenant_date on public.hr_attendance_change_audit(tenant_id,work_date desc);

create or replace function public.hr_admin_upsert_attendance(p_tenant uuid,p_employee uuid,p_work_date date,p_check_in timestamptz,p_check_out timestamptz,p_status text,p_site uuid,p_reason text,p_capture_method text default 'manual') returns jsonb
language plpgsql security definer set search_path=public as $$
declare oldr public.hr_attendance_records%rowtype; newr public.hr_attendance_records%rowtype; act text;
begin
 if not public.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 if coalesce(trim(p_reason),'')='' then raise exception 'Reason is required for manual attendance entry or correction'; end if;
 if p_capture_method not in ('manual','import') then raise exception 'Invalid administrative attendance source'; end if;
 if p_status not in ('present','absent','late','half_day','on_leave','holiday','off_day') then raise exception 'Invalid attendance status'; end if;
 if not exists(select 1 from public.hr_employees where tenant_id=p_tenant and id=p_employee) then raise exception 'Employee not found'; end if;
 select * into oldr from public.hr_attendance_records where tenant_id=p_tenant and employee_id=p_employee and work_date=p_work_date for update;
 if oldr.id is null then
  insert into public.hr_attendance_records(tenant_id,employee_id,work_date,check_in,check_out,status,capture_method,attendance_site_id,notes,correction_reason,approval_status,approved_by,approved_at)
  values(p_tenant,p_employee,p_work_date,p_check_in,p_check_out,p_status,p_capture_method,p_site,p_reason,p_reason,'approved',auth.uid(),now()) returning * into newr;
  act=case when p_capture_method='import' then 'import_create' else 'create' end;
 else
  update public.hr_attendance_records set check_in=p_check_in,check_out=p_check_out,status=p_status,capture_method=p_capture_method,attendance_site_id=p_site,notes=p_reason,correction_reason=p_reason,approval_status='approved',approved_by=auth.uid(),approved_at=now()
  where id=oldr.id returning * into newr;
  act=case when p_capture_method='import' then 'import_correct' else 'correct' end;
 end if;
 insert into public.hr_attendance_change_audit(tenant_id,attendance_id,employee_id,work_date,action,reason,old_record,new_record)
 values(p_tenant,newr.id,p_employee,p_work_date,act,p_reason,case when oldr.id is null then null else to_jsonb(oldr) end,to_jsonb(newr));
 return jsonb_build_object('ok',true,'attendance_id',newr.id,'action',act);
end $$;
grant execute on function public.hr_admin_upsert_attendance(uuid,uuid,date,timestamptz,timestamptz,text,uuid,text,text) to authenticated;
