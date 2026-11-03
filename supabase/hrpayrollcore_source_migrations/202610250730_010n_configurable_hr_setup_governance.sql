-- 010n Configurable HR setup, dynamic performance pillars, editable job architecture, policy defaults and governance support.

-- Grades are institution-managed and may be retired without deleting history.
alter table public.hr_job_grades add column if not exists active boolean not null default true;

-- Performance pillars are configuration data, not hard-coded application constants.
create table if not exists public.hr_performance_pillars(
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete cascade,
 code text not null,
 name text not null,
 description text,
 display_order integer not null default 10,
 active boolean not null default true,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(tenant_id,code)
);
alter table public.hr_performance_pillars enable row level security;
drop policy if exists tenant_member_all on public.hr_performance_pillars;
create policy tenant_member_all on public.hr_performance_pillars for all
 using(public.is_tenant_member(tenant_id)) with check(public.is_tenant_member(tenant_id));

-- Remove the original three-value pillar checks so tenants can add their own pillars.
alter table public.hr_performance_metric_library drop constraint if exists hr_performance_metric_library_pillar_check;
alter table public.hr_performance_plan_items drop constraint if exists hr_performance_plan_items_pillar_check;

-- Starter pillars remain defaults only.
insert into public.hr_performance_pillars(tenant_id,code,name,description,display_order)
select t.id,v.code,v.name,v.description,v.display_order
from public.tenants t
cross join (values
 ('target_output','Target & Output','Quantitative targets, deliverables and measurable output.',10),
 ('responsibility_quality','Responsibilities & Quality','Role responsibilities, quality, accuracy and SOP execution.',20),
 ('professional_conduct','Professional Conduct','Attendance, collaboration, ethics and professional behaviour.',30)
) as v(code,name,description,display_order)
on conflict(tenant_id,code) do nothing;

-- Complete policy views have editable defaults in System Setup.
insert into public.hr_policy_configs(tenant_id,policy_type,config)
select id,'performance_policy','{"frequency":"annual","checkins_required":true,"min_checkins":2,"evidence_required":true,"employee_response":true,"supervisor_validation":true,"second_level_approval":true,"weights_must_total_100":true}'::jsonb
from public.tenants
on conflict(tenant_id,policy_type) do nothing;

-- Helpful indexes for the new filtered setup/governance views.
create index if not exists idx_hr_performance_pillars_tenant_active on public.hr_performance_pillars(tenant_id,active,display_order);
create index if not exists idx_hr_metric_library_filters on public.hr_performance_metric_library(tenant_id,active,industry,pillar);
create index if not exists idx_hr_leave_types_tenant_active on public.hr_leave_types(tenant_id,active,name);
create index if not exists idx_audit_events_tenant_created on public.audit_events(tenant_id,created_at desc);
