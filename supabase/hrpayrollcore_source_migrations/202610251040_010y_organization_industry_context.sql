-- 010y: tenant organization/industry context for PMS recommendations and host-SaaS integration
create table if not exists public.hr_organization_profiles (
  tenant_id uuid primary key references public.tenants(id) on delete cascade,
  industry text not null default 'general',
  sector_detail text,
  integration_source text not null default 'standalone',
  host_product text,
  host_tenant_reference text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint hr_organization_profiles_industry_check check (industry in ('general','education','trading','ngo','banking','healthcare','hospitality','manufacturing','professional_services','government','other')),
  constraint hr_organization_profiles_integration_check check (integration_source in ('standalone','host_saas'))
);

alter table public.hr_organization_profiles enable row level security;

drop policy if exists hr_organization_profiles_select on public.hr_organization_profiles;
create policy hr_organization_profiles_select on public.hr_organization_profiles
for select using (public.is_tenant_member(tenant_id));

drop policy if exists hr_organization_profiles_write on public.hr_organization_profiles;
create policy hr_organization_profiles_write on public.hr_organization_profiles
for all using (public.is_tenant_member(tenant_id)) with check (public.is_tenant_member(tenant_id));

insert into public.hr_organization_profiles(tenant_id,industry,sector_detail,integration_source)
select id,'general',null,'standalone' from public.tenants
on conflict (tenant_id) do nothing;

create index if not exists idx_hr_org_profile_industry on public.hr_organization_profiles(industry);
