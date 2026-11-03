-- Package 006: HR Operations Completion - attendance controls, performance, training and DSS
alter table public.hr_attendance_records add column if not exists approval_status text not null default 'draft';
alter table public.hr_attendance_records add column if not exists approved_by uuid;
alter table public.hr_attendance_records add column if not exists approved_at timestamptz;
alter table public.hr_attendance_records add column if not exists correction_reason text;
alter table public.hr_attendance_records drop constraint if exists hr_attendance_records_approval_status_check;
alter table public.hr_attendance_records add constraint hr_attendance_records_approval_status_check check(approval_status in ('draft','submitted','approved','rejected'));

create table if not exists public.hr_performance_cycles(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete cascade,
 name text not null,cycle_type text not null default 'annual' check(cycle_type in ('annual','quarterly','probation','project','other')),
 start_date date not null,end_date date not null,status text not null default 'draft' check(status in ('draft','open','closed','archived')),
 created_by uuid default auth.uid(),created_at timestamptz not null default now(),check(end_date>=start_date)
);
create table if not exists public.hr_performance_reviews(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete cascade,
 cycle_id uuid not null references public.hr_performance_cycles(id) on delete cascade,employee_id uuid not null references public.hr_employees(id) on delete cascade,
 reviewer_employee_id uuid references public.hr_employees(id),status text not null default 'draft' check(status in ('draft','submitted','reviewed','completed','cancelled')),
 objective_score numeric(6,2),competency_score numeric(6,2),final_score numeric(6,2),final_rating text,employee_comments text,reviewer_comments text,development_needs text,
 submitted_at timestamptz,completed_at timestamptz,created_by uuid default auth.uid(),created_at timestamptz not null default now(),unique(tenant_id,cycle_id,employee_id)
);
create table if not exists public.hr_performance_objectives(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete cascade,review_id uuid not null references public.hr_performance_reviews(id) on delete cascade,
 title text not null,description text,weight numeric(6,2) not null default 0,target text,achievement text,score numeric(6,2),created_at timestamptz not null default now()
);
create table if not exists public.hr_performance_competencies(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete cascade,review_id uuid not null references public.hr_performance_reviews(id) on delete cascade,
 competency text not null,weight numeric(6,2) not null default 0,score numeric(6,2),comments text,created_at timestamptz not null default now()
);
create table if not exists public.hr_training_programs(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete cascade,code text not null,name text not null,
 provider text,venue text,start_date date,end_date date,cost numeric(14,2) not null default 0,currency text not null default 'GHS',status text not null default 'planned' check(status in ('planned','open','in_progress','completed','cancelled')),
 certificate_required boolean not null default false,certificate_valid_months integer,notes text,created_by uuid default auth.uid(),created_at timestamptz not null default now(),unique(tenant_id,code)
);
create table if not exists public.hr_training_enrollments(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references public.tenants(id) on delete cascade,program_id uuid not null references public.hr_training_programs(id) on delete cascade,
 employee_id uuid not null references public.hr_employees(id) on delete cascade,source text not null default 'hr' check(source in ('hr','performance','employee','manager')),
 performance_review_id uuid references public.hr_performance_reviews(id) on delete set null,status text not null default 'nominated' check(status in ('nominated','approved','enrolled','attended','completed','failed','cancelled')),
 result text,score numeric(6,2),certificate_path text,certificate_no text,certificate_expiry date,completion_date date,created_by uuid default auth.uid(),created_at timestamptz not null default now(),unique(tenant_id,program_id,employee_id)
);

do $$ declare t text; begin foreach t in array array['hr_performance_cycles','hr_performance_reviews','hr_performance_objectives','hr_performance_competencies','hr_training_programs','hr_training_enrollments'] loop execute format('alter table public.%I enable row level security',t);execute format('drop policy if exists tenant_member_all on public.%I',t);execute format('create policy tenant_member_all on public.%I for all using (public.is_tenant_member(tenant_id)) with check (public.is_tenant_member(tenant_id))',t);end loop;end $$;

create or replace function public.hr_decide_attendance(p_tenant uuid,p_record uuid,p_decision text,p_reason text default null) returns jsonb language plpgsql security definer set search_path=public as $$
begin if not public.is_tenant_member(p_tenant) then raise exception 'Tenant access denied';end if;if p_decision not in ('approved','rejected') then raise exception 'Invalid decision';end if;update hr_attendance_records set approval_status=p_decision,approved_by=auth.uid(),approved_at=now(),correction_reason=coalesce(p_reason,correction_reason) where tenant_id=p_tenant and id=p_record;if not found then raise exception 'Attendance record not found';end if;return jsonb_build_object('ok',true,'status',p_decision);end $$;
grant execute on function public.hr_decide_attendance(uuid,uuid,text,text) to authenticated;
create index if not exists idx_perf_review_tenant_employee on public.hr_performance_reviews(tenant_id,employee_id,created_at desc);
create index if not exists idx_training_enrol_tenant_employee on public.hr_training_enrollments(tenant_id,employee_id,created_at desc);
