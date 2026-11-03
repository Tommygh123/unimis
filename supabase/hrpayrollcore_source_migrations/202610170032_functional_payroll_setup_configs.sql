-- HRPayrollCore 008c: functional payroll setup destinations
create table if not exists public.payroll_setup_configs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  section text not null,
  config jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id, section)
);
alter table public.payroll_setup_configs enable row level security;
drop policy if exists payroll_setup_configs_select on public.payroll_setup_configs;
create policy payroll_setup_configs_select on public.payroll_setup_configs for select using (
 exists(select 1 from public.tenant_memberships tm where tm.tenant_id=payroll_setup_configs.tenant_id and tm.user_id=auth.uid() and tm.status='active')
);
drop policy if exists payroll_setup_configs_write on public.payroll_setup_configs;
create policy payroll_setup_configs_write on public.payroll_setup_configs for all using (
 exists(select 1 from public.tenant_memberships tm where tm.tenant_id=payroll_setup_configs.tenant_id and tm.user_id=auth.uid() and tm.status='active' and tm.role in ('owner','administrator','accountant','payroll_manager','payroll_officer','finance_manager'))
) with check (
 exists(select 1 from public.tenant_memberships tm where tm.tenant_id=payroll_setup_configs.tenant_id and tm.user_id=auth.uid() and tm.status='active' and tm.role in ('owner','administrator','accountant','payroll_manager','payroll_officer','finance_manager'))
);
create index if not exists payroll_setup_configs_tenant_section_idx on public.payroll_setup_configs(tenant_id,section);
