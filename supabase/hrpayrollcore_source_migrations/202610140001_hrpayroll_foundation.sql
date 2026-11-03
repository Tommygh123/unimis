create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  phone text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.tenants (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  code text not null unique,
  country_code text not null default 'GH',
  base_currency text not null default 'GHS',
  hr_enabled boolean not null default true,
  payroll_enabled boolean not null default true,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create table if not exists public.tenant_memberships (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('owner','administrator','hr_manager','hr_officer','payroll_manager','payroll_officer','finance_manager','approver','auditor','employee')),
  status text not null default 'active' check (status in ('active','invited','suspended')),
  created_at timestamptz not null default now(),
  unique (tenant_id,user_id)
);

create or replace function public.is_tenant_member(p_tenant uuid)
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.tenant_memberships m where m.tenant_id=p_tenant and m.user_id=auth.uid() and m.status='active');
$$;
create or replace function public.has_tenant_role(p_tenant uuid, p_roles text[])
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.tenant_memberships m where m.tenant_id=p_tenant and m.user_id=auth.uid() and m.status='active' and m.role=any(p_roles));
$$;

grant execute on function public.is_tenant_member(uuid) to authenticated;
grant execute on function public.has_tenant_role(uuid,text[]) to authenticated;

create table if not exists public.legal_entities (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.tenants(id) on delete cascade,
 name text not null, registration_no text, tax_id text, country_code text not null default 'GH', currency text not null default 'GHS', created_at timestamptz default now()
);
create table if not exists public.branches (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.tenants(id) on delete cascade,
 legal_entity_id uuid references public.legal_entities(id) on delete cascade, code text not null, name text not null, city text, active boolean default true, created_at timestamptz default now(), unique(tenant_id,code)
);
create table if not exists public.departments (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.tenants(id) on delete cascade,
 branch_id uuid references public.branches(id) on delete set null, code text not null, name text not null, active boolean default true, created_at timestamptz default now(), unique(tenant_id,code)
);
create table if not exists public.hr_job_grades (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.tenants(id) on delete cascade,
 code text not null, name text not null, min_salary numeric(14,2), max_salary numeric(14,2), created_at timestamptz default now(), unique(tenant_id,code)
);
create table if not exists public.hr_positions (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.tenants(id) on delete cascade,
 department_id uuid references public.departments(id) on delete set null, grade_id uuid references public.hr_job_grades(id) on delete set null,
 code text not null, title text not null, active boolean default true, created_at timestamptz default now(), unique(tenant_id,code)
);
create table if not exists public.hr_employees (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.tenants(id) on delete cascade,
 employee_no text not null, first_name text not null, last_name text not null, other_names text, email text, phone text,
 branch_id uuid references public.branches(id) on delete set null, department_id uuid references public.departments(id) on delete set null,
 position_id uuid references public.hr_positions(id) on delete set null, hire_date date, employment_status text not null default 'active',
 created_at timestamptz default now(), unique(tenant_id,employee_no)
);
create table if not exists public.hr_employment_contracts (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.tenants(id) on delete cascade,
 employee_id uuid not null references public.hr_employees(id) on delete cascade, contract_type text not null default 'permanent', start_date date not null,
 end_date date, basic_salary numeric(14,2) not null default 0, pay_frequency text not null default 'monthly', status text not null default 'active', created_at timestamptz default now()
);

create table if not exists public.payroll_pay_groups (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.tenants(id) on delete cascade,
 code text not null, name text not null, frequency text not null default 'monthly', active boolean default true, created_at timestamptz default now(), unique(tenant_id,code)
);
create table if not exists public.payroll_profiles (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.tenants(id) on delete cascade,
 employee_id uuid not null references public.hr_employees(id) on delete cascade, pay_group_id uuid references public.payroll_pay_groups(id) on delete set null,
 tax_number text, ssnit_number text, bank_name text, bank_account_name text, bank_account_number text,
 payment_method text not null default 'bank', active boolean default true, created_at timestamptz default now(), unique(tenant_id,employee_id)
);
create table if not exists public.payroll_components (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.tenants(id) on delete cascade,
 code text not null, name text not null, component_type text not null check(component_type in ('earning','deduction','employer_contribution')),
 taxable boolean not null default false, pensionable boolean not null default false, calculation_type text not null default 'fixed', default_amount numeric(14,2) default 0,
 active boolean default true, created_at timestamptz default now(), unique(tenant_id,code)
);
create table if not exists public.payroll_employee_components (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.tenants(id) on delete cascade,
 employee_id uuid not null references public.hr_employees(id) on delete cascade, component_id uuid not null references public.payroll_components(id) on delete cascade,
 amount numeric(14,2) not null default 0, effective_from date not null default current_date, effective_to date, unique(employee_id,component_id,effective_from)
);
create table if not exists public.payroll_periods (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.tenants(id) on delete cascade,
 pay_group_id uuid references public.payroll_pay_groups(id) on delete set null, name text not null, start_date date not null, end_date date not null, pay_date date not null,
 status text not null default 'open' check(status in ('open','processing','review','approved','posted','closed')), created_at timestamptz default now()
);
create table if not exists public.payroll_statutory_rules (
 id uuid primary key default gen_random_uuid(), tenant_id uuid references public.tenants(id) on delete cascade,
 country_code text not null, authority text not null, rule_type text not null, name text not null, effective_from date not null, effective_to date,
 calculation_method text not null default 'configuration', configuration jsonb not null default '{}'::jsonb, active boolean default true, created_at timestamptz default now()
);
create table if not exists public.approval_requests (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.tenants(id) on delete cascade,
 module text not null, record_type text not null, record_id uuid, requested_by uuid references auth.users(id), status text not null default 'pending', notes text, created_at timestamptz default now(), decided_at timestamptz
);
create table if not exists public.audit_events (
 id bigint generated always as identity primary key, tenant_id uuid references public.tenants(id) on delete cascade,
 actor_id uuid references auth.users(id), module text not null, action text not null, record_type text, record_id uuid, details jsonb default '{}'::jsonb, created_at timestamptz default now()
);

create index if not exists idx_membership_user on public.tenant_memberships(user_id,tenant_id);
create index if not exists idx_employee_tenant on public.hr_employees(tenant_id);
create index if not exists idx_payroll_profile_tenant on public.payroll_profiles(tenant_id);

create or replace function public.create_organization(p_name text, p_code text)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_tenant uuid; v_entity uuid;
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 insert into public.tenants(name,code,created_by) values(trim(p_name),upper(trim(p_code)),auth.uid()) returning id into v_tenant;
 insert into public.tenant_memberships(tenant_id,user_id,role) values(v_tenant,auth.uid(),'owner');
 insert into public.legal_entities(tenant_id,name) values(v_tenant,trim(p_name)) returning id into v_entity;
 insert into public.branches(tenant_id,legal_entity_id,code,name) values(v_tenant,v_entity,'HQ','Head Office');
 insert into public.payroll_pay_groups(tenant_id,code,name,frequency) values(v_tenant,'MONTHLY','Monthly Payroll','monthly');
 insert into public.payroll_components(tenant_id,code,name,component_type,taxable,pensionable) values
   (v_tenant,'BASIC','Basic Salary','earning',true,true),
   (v_tenant,'OVERTIME','Overtime','earning',true,true),
   (v_tenant,'BONUS','Bonus','earning',true,false),
   (v_tenant,'OTHERDED','Other Deduction','deduction',false,false);
 insert into public.audit_events(tenant_id,actor_id,module,action,record_type,record_id) values(v_tenant,auth.uid(),'core','organization.created','tenant',v_tenant);
 return v_tenant;
end $$;
grant execute on function public.create_organization(text,text) to authenticated;

create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$
begin insert into public.profiles(id,full_name) values(new.id,coalesce(new.raw_user_meta_data->>'full_name',split_part(new.email,'@',1))) on conflict(id) do nothing; return new; end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

alter table public.profiles enable row level security;
alter table public.tenants enable row level security;
alter table public.tenant_memberships enable row level security;
alter table public.legal_entities enable row level security;
alter table public.branches enable row level security;
alter table public.departments enable row level security;
alter table public.hr_job_grades enable row level security;
alter table public.hr_positions enable row level security;
alter table public.hr_employees enable row level security;
alter table public.hr_employment_contracts enable row level security;
alter table public.payroll_pay_groups enable row level security;
alter table public.payroll_profiles enable row level security;
alter table public.payroll_components enable row level security;
alter table public.payroll_employee_components enable row level security;
alter table public.payroll_periods enable row level security;
alter table public.payroll_statutory_rules enable row level security;
alter table public.approval_requests enable row level security;
alter table public.audit_events enable row level security;

create policy "profile self read" on public.profiles for select using(id=auth.uid());
create policy "profile self update" on public.profiles for update using(id=auth.uid()) with check(id=auth.uid());
create policy "tenant member read" on public.tenants for select using(public.is_tenant_member(id));
create policy "membership member read" on public.tenant_memberships for select using(public.is_tenant_member(tenant_id));

-- Tenant-scoped tables: members read; operational managers write. Owner/admin retain full control.
do $$ declare t text; begin
 foreach t in array array['legal_entities','branches','departments','hr_job_grades','hr_positions','hr_employees','hr_employment_contracts','payroll_pay_groups','payroll_profiles','payroll_components','payroll_employee_components','payroll_periods','approval_requests'] loop
   execute format('create policy %I on public.%I for select using (public.is_tenant_member(tenant_id))', t||'_read', t);
   execute format('create policy %I on public.%I for insert with check (public.has_tenant_role(tenant_id, ARRAY[''owner'',''administrator'',''hr_manager'',''hr_officer'',''payroll_manager'',''payroll_officer'',''finance_manager'']))', t||'_insert', t);
   execute format('create policy %I on public.%I for update using (public.has_tenant_role(tenant_id, ARRAY[''owner'',''administrator'',''hr_manager'',''hr_officer'',''payroll_manager'',''payroll_officer'',''finance_manager''])) with check (public.has_tenant_role(tenant_id, ARRAY[''owner'',''administrator'',''hr_manager'',''hr_officer'',''payroll_manager'',''payroll_officer'',''finance_manager'']))', t||'_update', t);
   execute format('create policy %I on public.%I for delete using (public.has_tenant_role(tenant_id, ARRAY[''owner'',''administrator'']))', t||'_delete', t);
 end loop;
end $$;
create policy "statutory authenticated read" on public.payroll_statutory_rules for select using(tenant_id is null or public.is_tenant_member(tenant_id));
create policy "statutory manager write" on public.payroll_statutory_rules for all using(tenant_id is not null and public.has_tenant_role(tenant_id,array['owner','administrator','payroll_manager'])) with check(tenant_id is not null and public.has_tenant_role(tenant_id,array['owner','administrator','payroll_manager']));
create policy "audit member read" on public.audit_events for select using(public.is_tenant_member(tenant_id));
create policy "audit authenticated insert" on public.audit_events for insert with check(public.is_tenant_member(tenant_id) and actor_id=auth.uid());

insert into public.payroll_statutory_rules(tenant_id,country_code,authority,rule_type,name,effective_from,calculation_method,configuration)
select null,'GH','GRA','PAYE','Ghana PAYE - configure current statutory bands',date '2026-01-01','bands',jsonb_build_object('status','configuration_required','note','Verify current GRA bands before production payroll')
where not exists(select 1 from public.payroll_statutory_rules where tenant_id is null and country_code='GH' and rule_type='PAYE' and effective_from=date '2026-01-01');
insert into public.payroll_statutory_rules(tenant_id,country_code,authority,rule_type,name,effective_from,calculation_method,configuration)
select null,'GH','SSNIT','PENSION','Ghana SSNIT - configure current contribution rates',date '2026-01-01','percentage',jsonb_build_object('status','configuration_required','note','Verify current SSNIT rates and allocation before production payroll')
where not exists(select 1 from public.payroll_statutory_rules where tenant_id is null and country_code='GH' and rule_type='PENSION' and effective_from=date '2026-01-01');
