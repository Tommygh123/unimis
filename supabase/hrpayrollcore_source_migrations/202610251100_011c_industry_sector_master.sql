-- 011c: Editable tenant industry/sector master for organization context and PMS KPI recommendations.
-- Standard sectors are seeded per tenant; administrators can add/edit/deactivate their own sectors.

create table if not exists public.hr_industries (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  code text,
  industry_key text not null,
  name text not null,
  description text,
  active boolean not null default true,
  system_default boolean not null default false,
  display_order integer not null default 100,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id,industry_key),
  unique(tenant_id,code)
);

alter table public.hr_industries enable row level security;
drop policy if exists hr_industries_select on public.hr_industries;
create policy hr_industries_select on public.hr_industries for select using (public.is_tenant_member(tenant_id));
drop policy if exists hr_industries_write on public.hr_industries;
create policy hr_industries_write on public.hr_industries for all using (public.is_tenant_member(tenant_id)) with check (public.is_tenant_member(tenant_id));

create or replace function public.hr_industry_prepare_row()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if new.code is null or btrim(new.code)='' then
    new.code:=public.hr_next_code(new.tenant_id,'hr_industries','IND',TG_RELID);
  end if;
  if new.industry_key is null or btrim(new.industry_key)='' then
    new.industry_key:='custom_'||replace(gen_random_uuid()::text,'-','');
  end if;
  new.name:=btrim(new.name);
  new.updated_at:=now();
  return new;
end $$;

drop trigger if exists trg_hr_industry_prepare on public.hr_industries;
create trigger trg_hr_industry_prepare before insert or update on public.hr_industries
for each row execute function public.hr_industry_prepare_row();

-- The old profile constraint prevented new sectors. The master now controls valid choices in the UI.
alter table public.hr_organization_profiles drop constraint if exists hr_organization_profiles_industry_check;

-- Normalize the one legacy label that was renamed in the expanded master.
update public.hr_organization_profiles set industry='financial_services',updated_at=now() where industry='banking';
update public.hr_performance_metric_library set industry='financial_services' where industry='banking';

insert into public.hr_industries(tenant_id,industry_key,name,description,system_default,display_order)
select t.id,v.industry_key,v.name,v.description,true,v.display_order
from public.tenants t
cross join (values
 ('general','General','General-purpose organization / uncategorized employer',10),
 ('agriculture_agribusiness','Agriculture & Agribusiness','Farming, agricultural inputs, agrochemicals, agribusiness and related services',20),
 ('manufacturing','Manufacturing & Industry','Manufacturing, processing and industrial operations',30),
 ('trading','Trading / Retail / Wholesale','Trading, retail, wholesale and distribution businesses',40),
 ('healthcare','Health','Hospitals, clinics, diagnostics and other healthcare services',50),
 ('education','Education','Schools, TVET institutions, universities and education services',60),
 ('hospitality','Hospitality','Hotels, accommodation, restaurants and hospitality services',70),
 ('financial_services','Financial Services','Banking, insurance, fintech and other financial services',80),
 ('construction','Construction & Real Estate','Construction, engineering works, property and real estate',90),
 ('transport_logistics','Transport & Logistics','Transport, warehousing, freight and logistics services',100),
 ('ict_technology','ICT / Technology','Software, telecommunications, IT and technology services',110),
 ('ngo','NGO / Non-profit','Non-governmental, charitable and non-profit organizations',120),
 ('government','Government / Public Sector','Government agencies, public institutions and state bodies',130),
 ('professional_services','Professional Services','Consulting, legal, audit, advisory and other professional services',140),
 ('energy_utilities','Energy & Utilities','Power, water, energy and utility services',150),
 ('mining_natural_resources','Mining & Natural Resources','Mining, extractives and natural-resource operations',160),
 ('other','Other','Other sector not represented by the standard classifications',999)
) as v(industry_key,name,description,display_order)
on conflict(tenant_id,industry_key) do update set
 name=excluded.name,
 description=excluded.description,
 system_default=true,
 display_order=excluded.display_order;

create index if not exists idx_hr_industries_tenant_active on public.hr_industries(tenant_id,active,display_order);
