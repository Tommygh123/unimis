-- 016 Generated performance data collection templates
create table if not exists public.hr_performance_collection_templates(
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete cascade,
 template_token text not null,
 name text not null,
 performance_template_id uuid references public.hr_performance_templates(id) on delete set null,
 period_key text not null,
 frequency text not null default 'monthly',
 employee_count int not null default 0,
 measure_count int not null default 0,
 metadata jsonb not null default '{}'::jsonb,
 active boolean not null default true,
 created_at timestamptz not null default now(),
 unique(tenant_id,template_token)
);
alter table public.hr_performance_collection_templates enable row level security;
drop policy if exists tenant_member_all on public.hr_performance_collection_templates;
create policy tenant_member_all on public.hr_performance_collection_templates for all
 using (public.is_tenant_member(tenant_id)) with check (public.is_tenant_member(tenant_id));
create index if not exists idx_perf_collection_template_lookup
 on public.hr_performance_collection_templates(tenant_id,period_key,performance_template_id,active);
