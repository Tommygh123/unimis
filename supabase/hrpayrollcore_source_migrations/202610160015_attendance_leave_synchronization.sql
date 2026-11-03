-- Package 005a: Attendance / Leave Synchronization Engine
alter table public.hr_leave_requests add column if not exists day_portion text not null default 'full' check(day_portion in ('full','first_half','second_half'));
alter table public.hr_leave_requests add column if not exists approved_working_days numeric(7,2);
alter table public.hr_attendance_records add column if not exists leave_request_id uuid references public.hr_leave_requests(id) on delete set null;
alter table public.hr_attendance_records add column if not exists leave_fraction numeric(3,2) check(leave_fraction is null or leave_fraction in (0.5,1.0));
alter table public.hr_attendance_records add column if not exists leave_paid boolean;
alter table public.hr_attendance_records add column if not exists leave_generated boolean not null default false;
create index if not exists idx_attendance_leave_request on public.hr_attendance_records(leave_request_id);

create or replace function public.hr_leave_is_working_day(p_tenant uuid,p_employee uuid,p_day date)
returns boolean language plpgsql stable set search_path=public as $$
declare s hr_work_schedules%rowtype; dow integer; holiday_exists boolean;
begin
 select ws.* into s from hr_employee_schedule_assignments a join hr_work_schedules ws on ws.id=a.schedule_id
 where a.tenant_id=p_tenant and a.employee_id=p_employee and a.effective_from<=p_day and (a.effective_to is null or a.effective_to>=p_day)
 order by a.effective_from desc limit 1;
 if s.id is null then select * into s from hr_work_schedules where tenant_id=p_tenant and active order by created_at limit 1; end if;
 dow=extract(isodow from p_day)::integer;
 if s.id is not null and not (dow=any(s.work_days)) then return false; end if;
 select exists(select 1 from hr_public_holidays where tenant_id=p_tenant and holiday_date=p_day and active) into holiday_exists;
 return not holiday_exists;
end $$;

create or replace function public.hr_sync_leave_attendance(p_tenant uuid,p_request uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare r hr_leave_requests%rowtype; lt hr_leave_types%rowtype; d date; rec hr_attendance_records%rowtype; frac numeric; workdays numeric:=0; note_text text;
begin
 if not public.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 select * into r from hr_leave_requests where id=p_request and tenant_id=p_tenant; if r.id is null then raise exception 'Request not found'; end if;
 select * into lt from hr_leave_types where id=r.leave_type_id and tenant_id=p_tenant;
 if r.status<>'approved' then raise exception 'Only approved leave can be synchronized'; end if;
 frac=case when r.day_portion='full' then 1.0 else 0.5 end;
 -- remove stale system-generated rows for this request before rebuilding
 delete from hr_attendance_records where tenant_id=p_tenant and leave_request_id=r.id and leave_generated=true and check_in is null and check_out is null;
 for d in select generate_series(r.start_date,r.end_date,'1 day'::interval)::date loop
   if public.hr_leave_is_working_day(p_tenant,r.employee_id,d) then
     workdays=workdays+frac;
     note_text=case when frac=0.5 then 'Approved '||replace(r.day_portion,'_',' ')||' leave' else 'Approved leave' end;
     select * into rec from hr_attendance_records where tenant_id=p_tenant and employee_id=r.employee_id and work_date=d for update;
     if rec.id is null then
       insert into hr_attendance_records(tenant_id,employee_id,work_date,status,capture_method,notes,leave_request_id,leave_fraction,leave_paid,leave_generated)
       values(p_tenant,r.employee_id,d,case when frac=0.5 then 'half_day' else 'on_leave' end,'api',note_text,r.id,frac,coalesce(lt.paid,true),true);
     elsif rec.check_in is null and rec.check_out is null then
       update hr_attendance_records set status=case when frac=0.5 then 'half_day' else 'on_leave' end,
         notes=note_text,leave_request_id=r.id,leave_fraction=frac,leave_paid=coalesce(lt.paid,true),leave_generated=true,
         late_minutes=0,overtime_minutes=0,worked_minutes=0 where id=rec.id;
     else
       -- preserve genuine clock evidence; annotate the overlap instead of destroying it
       update hr_attendance_records set status=case when frac=0.5 then 'half_day' else status end,
         notes=concat_ws(' · ',nullif(notes,''),note_text||' (attendance retained)'),leave_request_id=r.id,
         leave_fraction=frac,leave_paid=coalesce(lt.paid,true),leave_generated=false where id=rec.id;
     end if;
   end if;
 end loop;
 update hr_leave_requests set approved_working_days=workdays where id=r.id;
 return jsonb_build_object('ok',true,'working_days',workdays);
end $$;

create or replace function public.hr_decide_leave_request(p_tenant uuid,p_request uuid,p_decision text,p_notes text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare r hr_leave_requests%rowtype; result jsonb;
begin
 if not public.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 if p_decision not in ('approved','rejected') then raise exception 'Invalid decision'; end if;
 select * into r from hr_leave_requests where id=p_request and tenant_id=p_tenant for update;
 if r.id is null then raise exception 'Request not found'; end if;
 if r.status<>'submitted' then raise exception 'Only submitted requests can be decided'; end if;
 update hr_leave_requests set status=p_decision,decision_notes=p_notes,decided_by=auth.uid(),decided_at=now() where id=r.id;
 if p_decision='approved' then result=public.hr_sync_leave_attendance(p_tenant,r.id); else result=jsonb_build_object('ok',true); end if;
 return result||jsonb_build_object('status',p_decision);
end $$;

create or replace function public.hr_cancel_leave_request(p_tenant uuid,p_request uuid,p_notes text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare r hr_leave_requests%rowtype;
begin
 if not public.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 select * into r from hr_leave_requests where id=p_request and tenant_id=p_tenant for update;
 if r.id is null then raise exception 'Request not found'; end if;
 if r.status not in ('submitted','approved') then raise exception 'Only submitted or approved leave can be cancelled'; end if;
 -- delete only rows created solely by leave; preserve genuine attendance and remove leave annotation metadata
 delete from hr_attendance_records where tenant_id=p_tenant and leave_request_id=r.id and leave_generated=true and check_in is null and check_out is null;
 update hr_attendance_records set leave_request_id=null,leave_fraction=null,leave_paid=null,leave_generated=false,
   notes=case when notes like '%Approved leave%' then 'Leave cancelled; attendance retained' else notes end
 where tenant_id=p_tenant and leave_request_id=r.id;
 update hr_leave_requests set status='cancelled',decision_notes=coalesce(p_notes,'Leave cancelled'),decided_by=auth.uid(),decided_at=now(),approved_working_days=0 where id=r.id;
 return jsonb_build_object('ok',true,'status','cancelled');
end $$;

grant execute on function public.hr_sync_leave_attendance(uuid,uuid) to authenticated;
grant execute on function public.hr_cancel_leave_request(uuid,uuid,text) to authenticated;
