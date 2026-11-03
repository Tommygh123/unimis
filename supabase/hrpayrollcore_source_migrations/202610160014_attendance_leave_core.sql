-- Package 005: Attendance + Leave Core
create table if not exists public.hr_work_schedules(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.tenants(id) on delete cascade,
 code text not null, name text not null, start_time time not null default '08:00', end_time time not null default '17:00',
 grace_minutes integer not null default 10, standard_minutes integer not null default 480, work_days integer[] not null default array[1,2,3,4,5], active boolean not null default true,
 created_at timestamptz not null default now(), unique(tenant_id,code)
);
create table if not exists public.hr_employee_schedule_assignments(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete cascade,
 employee_id uuid not null references public.hr_employees(id) on delete cascade,schedule_id uuid not null references public.hr_work_schedules(id),
 effective_from date not null default current_date,effective_to date,created_at timestamptz not null default now()
);
create table if not exists public.hr_attendance_records(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete cascade,
 employee_id uuid not null references public.hr_employees(id) on delete cascade,work_date date not null,
 check_in timestamptz,check_out timestamptz,status text not null default 'present' check(status in ('present','absent','late','half_day','on_leave','holiday','off_day')),
 capture_method text not null default 'manual' check(capture_method in ('manual','qr','gps','nfc','biometric','import','api')),
 late_minutes integer not null default 0,overtime_minutes integer not null default 0,worked_minutes integer not null default 0,
 latitude numeric(10,7),longitude numeric(10,7),notes text,correction_status text not null default 'none',created_by uuid default auth.uid(),created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 unique(tenant_id,employee_id,work_date)
);
create table if not exists public.hr_public_holidays(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete cascade,
 holiday_date date not null,name text not null,country_code text default 'GH',active boolean default true,unique(tenant_id,holiday_date)
);
create table if not exists public.hr_leave_types(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete cascade,
 code text not null,name text not null,default_days numeric(7,2) not null default 0,paid boolean not null default true,
 requires_attachment boolean not null default false,carry_forward boolean not null default false,max_carry_forward numeric(7,2),active boolean not null default true,
 created_at timestamptz not null default now(),unique(tenant_id,code)
);
create table if not exists public.hr_leave_entitlements(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete cascade,
 employee_id uuid not null references public.hr_employees(id) on delete cascade,leave_type_id uuid not null references public.hr_leave_types(id) on delete cascade,
 leave_year integer not null,entitled_days numeric(7,2) not null default 0,carried_days numeric(7,2) not null default 0,adjustment_days numeric(7,2) not null default 0,
 unique(tenant_id,employee_id,leave_type_id,leave_year)
);
create table if not exists public.hr_leave_requests(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete cascade,
 employee_id uuid not null references public.hr_employees(id) on delete cascade,leave_type_id uuid not null references public.hr_leave_types(id),
 start_date date not null,end_date date not null,requested_days numeric(7,2) generated always as ((end_date-start_date)+1) stored,
 reason text,status text not null default 'draft' check(status in ('draft','submitted','approved','rejected','cancelled')),
 attachment_path text,decision_notes text,decided_by uuid,decided_at timestamptz,created_by uuid default auth.uid(),created_at timestamptz not null default now(),
 check(end_date>=start_date)
);

alter table public.hr_work_schedules enable row level security;alter table public.hr_employee_schedule_assignments enable row level security;alter table public.hr_attendance_records enable row level security;alter table public.hr_public_holidays enable row level security;alter table public.hr_leave_types enable row level security;alter table public.hr_leave_entitlements enable row level security;alter table public.hr_leave_requests enable row level security;
do $$ declare t text; begin foreach t in array array['hr_work_schedules','hr_employee_schedule_assignments','hr_attendance_records','hr_public_holidays','hr_leave_types','hr_leave_entitlements','hr_leave_requests'] loop execute format('drop policy if exists tenant_member_all on public.%I',t); execute format('create policy tenant_member_all on public.%I for all using (public.is_tenant_member(tenant_id)) with check (public.is_tenant_member(tenant_id))',t); end loop; end $$;

create or replace function public.hr_seed_time_leave_defaults(p_tenant uuid) returns jsonb language plpgsql security definer set search_path=public as $$
begin
 if not public.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 insert into hr_work_schedules(tenant_id,code,name,start_time,end_time,grace_minutes,standard_minutes) values(p_tenant,'STD','Standard Monday-Friday','08:00','17:00',10,480) on conflict(tenant_id,code) do nothing;
 insert into hr_leave_types(tenant_id,code,name,default_days,paid,requires_attachment,carry_forward) values
 (p_tenant,'ANNUAL','Annual Leave',20,true,false,true),(p_tenant,'SICK','Sick Leave',10,true,true,false),(p_tenant,'MATERNITY','Maternity Leave',84,true,true,false),(p_tenant,'PATERNITY','Paternity Leave',5,true,false,false),(p_tenant,'UNPAID','Unpaid Leave',0,false,false,false),(p_tenant,'STUDY','Study Leave',0,true,true,false)
 on conflict(tenant_id,code) do nothing;
 return jsonb_build_object('ok',true);
end $$;

create or replace function public.hr_attendance_compute() returns trigger language plpgsql set search_path=public as $$
declare s hr_work_schedules%rowtype; sched_start timestamptz;begin
 select ws.* into s from hr_employee_schedule_assignments a join hr_work_schedules ws on ws.id=a.schedule_id where a.tenant_id=new.tenant_id and a.employee_id=new.employee_id and a.effective_from<=new.work_date and (a.effective_to is null or a.effective_to>=new.work_date) order by a.effective_from desc limit 1;
 if s.id is null then select * into s from hr_work_schedules where tenant_id=new.tenant_id and active order by created_at limit 1; end if;
 if new.check_in is not null and s.id is not null then sched_start=(new.work_date+s.start_time)::timestamp at time zone 'UTC'; new.late_minutes=greatest(0,floor(extract(epoch from(new.check_in-sched_start))/60)-s.grace_minutes); if new.late_minutes>0 then new.status='late'; end if; end if;
 if new.check_in is not null and new.check_out is not null and new.check_out>=new.check_in then new.worked_minutes=floor(extract(epoch from(new.check_out-new.check_in))/60); if s.id is not null then new.overtime_minutes=greatest(0,new.worked_minutes-s.standard_minutes); end if; end if;
 new.updated_at=now(); return new;end $$;
drop trigger if exists trg_attendance_compute on public.hr_attendance_records;create trigger trg_attendance_compute before insert or update on public.hr_attendance_records for each row execute function public.hr_attendance_compute();

create or replace function public.hr_decide_leave_request(p_tenant uuid,p_request uuid,p_decision text,p_notes text default null) returns jsonb language plpgsql security definer set search_path=public as $$
declare r hr_leave_requests%rowtype; d date;begin
 if not public.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 if p_decision not in ('approved','rejected') then raise exception 'Invalid decision'; end if;
 select * into r from hr_leave_requests where id=p_request and tenant_id=p_tenant for update; if r.id is null then raise exception 'Request not found'; end if; if r.status<>'submitted' then raise exception 'Only submitted requests can be decided'; end if;
 update hr_leave_requests set status=p_decision,decision_notes=p_notes,decided_by=auth.uid(),decided_at=now() where id=r.id;
 if p_decision='approved' then for d in select generate_series(r.start_date,r.end_date,'1 day'::interval)::date loop insert into hr_attendance_records(tenant_id,employee_id,work_date,status,capture_method,notes) values(p_tenant,r.employee_id,d,'on_leave','api','Approved leave') on conflict(tenant_id,employee_id,work_date) do update set status='on_leave',notes='Approved leave'; end loop; end if;
 return jsonb_build_object('ok',true,'status',p_decision);end $$;

grant execute on function public.hr_seed_time_leave_defaults(uuid) to authenticated;grant execute on function public.hr_decide_leave_request(uuid,uuid,text,text) to authenticated;
create index if not exists idx_attendance_tenant_date on public.hr_attendance_records(tenant_id,work_date desc);create index if not exists idx_leave_tenant_status on public.hr_leave_requests(tenant_id,status,created_at desc);
