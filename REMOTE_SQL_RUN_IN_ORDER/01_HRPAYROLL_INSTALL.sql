-- TARGET: shared remote Supabase, schema unimis
create schema if not exists unimis;
-- UniMIS Build 171: conflict-proof HRPayrollCore database integration
-- HRPayrollCore-owned tables are namespaced hrc_* to protect existing UniMIS academic/finance tables.
-- UniMIS remains owner of auth.users onboarding. Institution UUID is reused as HR tenant UUID.

-- SOURCE 202610140001_hrpayroll_foundation.sql
create extension if not exists pgcrypto;

create table if not exists unimis.hrc_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  phone text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists unimis.hrc_tenants (
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

create table if not exists unimis.hrc_tenant_memberships (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('owner','administrator','hr_manager','hr_officer','payroll_manager','payroll_officer','finance_manager','approver','auditor','employee')),
  status text not null default 'active' check (status in ('active','invited','suspended')),
  created_at timestamptz not null default now(),
  unique (tenant_id,user_id)
);

create or replace function unimis.is_tenant_member(p_tenant uuid)
returns boolean language sql stable security definer set search_path=unimis as $$
  select exists(select 1 from unimis.hrc_tenant_memberships m where m.tenant_id=p_tenant and m.user_id=auth.uid() and m.status='active');
$$;
create or replace function unimis.has_tenant_role(p_tenant uuid, p_roles text[])
returns boolean language sql stable security definer set search_path=unimis as $$
  select exists(select 1 from unimis.hrc_tenant_memberships m where m.tenant_id=p_tenant and m.user_id=auth.uid() and m.status='active' and m.role=any(p_roles));
$$;

grant execute on function unimis.is_tenant_member(uuid) to authenticated;
grant execute on function unimis.has_tenant_role(uuid,text[]) to authenticated;

create table if not exists unimis.hrc_legal_entities (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
 name text not null, registration_no text, tax_id text, country_code text not null default 'GH', currency text not null default 'GHS', created_at timestamptz default now()
);
create table if not exists unimis.hrc_branches (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
 legal_entity_id uuid references unimis.hrc_legal_entities(id) on delete cascade, code text not null, name text not null, city text, active boolean default true, created_at timestamptz default now(), unique(tenant_id,code)
);
create table if not exists unimis.hrc_departments (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
 branch_id uuid references unimis.hrc_branches(id) on delete set null, code text not null, name text not null, active boolean default true, created_at timestamptz default now(), unique(tenant_id,code)
);
create table if not exists unimis.hrc_hr_job_grades (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
 code text not null, name text not null, min_salary numeric(14,2), max_salary numeric(14,2), created_at timestamptz default now(), unique(tenant_id,code)
);
create table if not exists unimis.hrc_hr_positions (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
 department_id uuid references unimis.hrc_departments(id) on delete set null, grade_id uuid references unimis.hrc_hr_job_grades(id) on delete set null,
 code text not null, title text not null, active boolean default true, created_at timestamptz default now(), unique(tenant_id,code)
);
create table if not exists unimis.hrc_hr_employees (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
 employee_no text not null, first_name text not null, last_name text not null, other_names text, email text, phone text,
 branch_id uuid references unimis.hrc_branches(id) on delete set null, department_id uuid references unimis.hrc_departments(id) on delete set null,
 position_id uuid references unimis.hrc_hr_positions(id) on delete set null, hire_date date, employment_status text not null default 'active',
 created_at timestamptz default now(), unique(tenant_id,employee_no)
);
create table if not exists unimis.hrc_hr_employment_contracts (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
 employee_id uuid not null references unimis.hrc_hr_employees(id) on delete cascade, contract_type text not null default 'permanent', start_date date not null,
 end_date date, basic_salary numeric(14,2) not null default 0, pay_frequency text not null default 'monthly', status text not null default 'active', created_at timestamptz default now()
);

create table if not exists unimis.hrc_payroll_pay_groups (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
 code text not null, name text not null, frequency text not null default 'monthly', active boolean default true, created_at timestamptz default now(), unique(tenant_id,code)
);
create table if not exists unimis.hrc_payroll_profiles (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
 employee_id uuid not null references unimis.hrc_hr_employees(id) on delete cascade, pay_group_id uuid references unimis.hrc_payroll_pay_groups(id) on delete set null,
 tax_number text, ssnit_number text, bank_name text, bank_account_name text, bank_account_number text,
 payment_method text not null default 'bank', active boolean default true, created_at timestamptz default now(), unique(tenant_id,employee_id)
);
create table if not exists unimis.hrc_payroll_components (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
 code text not null, name text not null, component_type text not null check(component_type in ('earning','deduction','employer_contribution')),
 taxable boolean not null default false, pensionable boolean not null default false, calculation_type text not null default 'fixed', default_amount numeric(14,2) default 0,
 active boolean default true, created_at timestamptz default now(), unique(tenant_id,code)
);
create table if not exists unimis.hrc_payroll_employee_components (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
 employee_id uuid not null references unimis.hrc_hr_employees(id) on delete cascade, component_id uuid not null references unimis.hrc_payroll_components(id) on delete cascade,
 amount numeric(14,2) not null default 0, effective_from date not null default current_date, effective_to date, unique(employee_id,component_id,effective_from)
);
create table if not exists unimis.hrc_payroll_periods (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
 pay_group_id uuid references unimis.hrc_payroll_pay_groups(id) on delete set null, name text not null, start_date date not null, end_date date not null, pay_date date not null,
 status text not null default 'open' check(status in ('open','processing','review','approved','posted','closed')), created_at timestamptz default now()
);
create table if not exists unimis.hrc_payroll_statutory_rules (
 id uuid primary key default gen_random_uuid(), tenant_id uuid references unimis.hrc_tenants(id) on delete cascade,
 country_code text not null, authority text not null, rule_type text not null, name text not null, effective_from date not null, effective_to date,
 calculation_method text not null default 'configuration', configuration jsonb not null default '{}'::jsonb, active boolean default true, created_at timestamptz default now()
);
create table if not exists unimis.hrc_approval_requests (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
 module text not null, record_type text not null, record_id uuid, requested_by uuid references auth.users(id), status text not null default 'pending', notes text, created_at timestamptz default now(), decided_at timestamptz
);
create table if not exists unimis.hrc_audit_events (
 id bigint generated always as identity primary key, tenant_id uuid references unimis.hrc_tenants(id) on delete cascade,
 actor_id uuid references auth.users(id), module text not null, action text not null, record_type text, record_id uuid, details jsonb default '{}'::jsonb, created_at timestamptz default now()
);

create index if not exists idx_membership_user on unimis.hrc_tenant_memberships(user_id,tenant_id);
create index if not exists idx_employee_tenant on unimis.hrc_hr_employees(tenant_id);
create index if not exists idx_payroll_profile_tenant on unimis.hrc_payroll_profiles(tenant_id);

create or replace function unimis.create_organization(p_name text, p_code text)
returns uuid language plpgsql security definer set search_path=unimis as $$
declare v_tenant uuid; v_entity uuid;
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 insert into unimis.hrc_tenants(name,code,created_by) values(trim(p_name),upper(trim(p_code)),auth.uid()) returning id into v_tenant;
 insert into unimis.hrc_tenant_memberships(tenant_id,user_id,role) values(v_tenant,auth.uid(),'owner');
 insert into unimis.hrc_legal_entities(tenant_id,name) values(v_tenant,trim(p_name)) returning id into v_entity;
 insert into unimis.hrc_branches(tenant_id,legal_entity_id,code,name) values(v_tenant,v_entity,'HQ','Head Office');
 insert into unimis.hrc_payroll_pay_groups(tenant_id,code,name,frequency) values(v_tenant,'MONTHLY','Monthly Payroll','monthly');
 insert into unimis.hrc_payroll_components(tenant_id,code,name,component_type,taxable,pensionable) values
   (v_tenant,'BASIC','Basic Salary','earning',true,true),
   (v_tenant,'OVERTIME','Overtime','earning',true,true),
   (v_tenant,'BONUS','Bonus','earning',true,false),
   (v_tenant,'OTHERDED','Other Deduction','deduction',false,false);
 insert into unimis.hrc_audit_events(tenant_id,actor_id,module,action,record_type,record_id) values(v_tenant,auth.uid(),'core','organization.created','tenant',v_tenant);
 return v_tenant;
end $$;
grant execute on function unimis.create_organization(text,text) to authenticated;

create or replace function unimis.handle_new_user() returns trigger language plpgsql security definer set search_path=unimis as $$
begin insert into unimis.hrc_profiles(id,full_name) values(new.id,coalesce(new.raw_user_meta_data->>'full_name',split_part(new.email,'@',1))) on conflict(id) do nothing; return new; end $$;
-- Build 171: auth.users trigger intentionally not installed; UniMIS owns authentication onboarding.

alter table unimis.hrc_profiles enable row level security;
alter table unimis.hrc_tenants enable row level security;
alter table unimis.hrc_tenant_memberships enable row level security;
alter table unimis.hrc_legal_entities enable row level security;
alter table unimis.hrc_branches enable row level security;
alter table unimis.hrc_departments enable row level security;
alter table unimis.hrc_hr_job_grades enable row level security;
alter table unimis.hrc_hr_positions enable row level security;
alter table unimis.hrc_hr_employees enable row level security;
alter table unimis.hrc_hr_employment_contracts enable row level security;
alter table unimis.hrc_payroll_pay_groups enable row level security;
alter table unimis.hrc_payroll_profiles enable row level security;
alter table unimis.hrc_payroll_components enable row level security;
alter table unimis.hrc_payroll_employee_components enable row level security;
alter table unimis.hrc_payroll_periods enable row level security;
alter table unimis.hrc_payroll_statutory_rules enable row level security;
alter table unimis.hrc_approval_requests enable row level security;
alter table unimis.hrc_audit_events enable row level security;

create policy "profile self read" on unimis.hrc_profiles for select using(id=auth.uid());
create policy "profile self update" on unimis.hrc_profiles for update using(id=auth.uid()) with check(id=auth.uid());
create policy "tenant member read" on unimis.hrc_tenants for select using(unimis.is_tenant_member(id));
create policy "membership member read" on unimis.hrc_tenant_memberships for select using(unimis.is_tenant_member(tenant_id));

-- Tenant-scoped tables: members read; operational managers write. Owner/admin retain full control.
do $$ declare t text; begin
 foreach t in array array['hrc_legal_entities','hrc_branches','hrc_departments','hrc_hr_job_grades','hrc_hr_positions','hrc_hr_employees','hrc_hr_employment_contracts','hrc_payroll_pay_groups','hrc_payroll_profiles','hrc_payroll_components','hrc_payroll_employee_components','hrc_payroll_periods','hrc_approval_requests'] loop
   execute format('create policy %I on unimis.%I for select using (unimis.is_tenant_member(tenant_id))', t||'_read', t);
   execute format('create policy %I on unimis.%I for insert with check (unimis.has_tenant_role(tenant_id, ARRAY[''owner'',''administrator'',''hr_manager'',''hr_officer'',''payroll_manager'',''payroll_officer'',''finance_manager'']))', t||'_insert', t);
   execute format('create policy %I on unimis.%I for update using (unimis.has_tenant_role(tenant_id, ARRAY[''owner'',''administrator'',''hr_manager'',''hr_officer'',''payroll_manager'',''payroll_officer'',''finance_manager''])) with check (unimis.has_tenant_role(tenant_id, ARRAY[''owner'',''administrator'',''hr_manager'',''hr_officer'',''payroll_manager'',''payroll_officer'',''finance_manager'']))', t||'_update', t);
   execute format('create policy %I on unimis.%I for delete using (unimis.has_tenant_role(tenant_id, ARRAY[''owner'',''administrator'']))', t||'_delete', t);
 end loop;
end $$;
create policy "statutory authenticated read" on unimis.hrc_payroll_statutory_rules for select using(tenant_id is null or unimis.is_tenant_member(tenant_id));
create policy "statutory manager write" on unimis.hrc_payroll_statutory_rules for all using(tenant_id is not null and unimis.has_tenant_role(tenant_id,array['owner','administrator','payroll_manager'])) with check(tenant_id is not null and unimis.has_tenant_role(tenant_id,array['owner','administrator','payroll_manager']));
create policy "audit member read" on unimis.hrc_audit_events for select using(unimis.is_tenant_member(tenant_id));
create policy "audit authenticated insert" on unimis.hrc_audit_events for insert with check(unimis.is_tenant_member(tenant_id) and actor_id=auth.uid());

insert into unimis.hrc_payroll_statutory_rules(tenant_id,country_code,authority,rule_type,name,effective_from,calculation_method,configuration)
select null,'GH','GRA','PAYE','Ghana PAYE - configure current statutory bands',date '2026-01-01','bands',jsonb_build_object('status','configuration_required','note','Verify current GRA bands before production payroll')
where not exists(select 1 from unimis.hrc_payroll_statutory_rules where tenant_id is null and country_code='GH' and rule_type='PAYE' and effective_from=date '2026-01-01');
insert into unimis.hrc_payroll_statutory_rules(tenant_id,country_code,authority,rule_type,name,effective_from,calculation_method,configuration)
select null,'GH','SSNIT','PENSION','Ghana SSNIT - configure current contribution rates',date '2026-01-01','percentage',jsonb_build_object('status','configuration_required','note','Verify current SSNIT rates and allocation before production payroll')
where not exists(select 1 from unimis.hrc_payroll_statutory_rules where tenant_id is null and country_code='GH' and rule_type='PENSION' and effective_from=date '2026-01-01');


-- SOURCE 202610140002_hr_payroll_operational_core.sql
-- HRPayrollCore Package 002: operational HR + payroll core
-- Preserves all Package 001 data.

create table if not exists unimis.hrc_payroll_settings (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null unique references unimis.hrc_tenants(id) on delete cascade,
 country_code text not null default 'GH',
 currency text not null default 'GHS',
 employee_pension_rate numeric(8,5) not null default 0,
 employer_pension_rate numeric(8,5) not null default 0,
 paye_enabled boolean not null default false,
 statutory_note text not null default 'Configure and verify current statutory rates before production payroll.',
 updated_at timestamptz not null default now()
);

create table if not exists unimis.hrc_payroll_runs (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
 period_id uuid not null references unimis.hrc_payroll_periods(id) on delete restrict,
 run_no text not null,
 status text not null default 'draft' check(status in ('draft','calculated','review','approved','posted','void')),
 gross_total numeric(14,2) not null default 0,
 deduction_total numeric(14,2) not null default 0,
 employee_pension_total numeric(14,2) not null default 0,
 employer_pension_total numeric(14,2) not null default 0,
 tax_total numeric(14,2) not null default 0,
 net_total numeric(14,2) not null default 0,
 employee_count integer not null default 0,
 created_by uuid references auth.users(id),
 approved_by uuid references auth.users(id),
 posted_by uuid references auth.users(id),
 created_at timestamptz not null default now(), approved_at timestamptz, posted_at timestamptz,
 unique(tenant_id,run_no), unique(tenant_id,period_id)
);

create table if not exists unimis.hrc_payroll_run_employees (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
 run_id uuid not null references unimis.hrc_payroll_runs(id) on delete cascade,
 employee_id uuid not null references unimis.hrc_hr_employees(id) on delete restrict,
 employee_no text not null, employee_name text not null,
 basic_salary numeric(14,2) not null default 0, other_earnings numeric(14,2) not null default 0,
 gross_pay numeric(14,2) not null default 0, employee_pension numeric(14,2) not null default 0,
 employer_pension numeric(14,2) not null default 0, tax numeric(14,2) not null default 0,
 other_deductions numeric(14,2) not null default 0, net_pay numeric(14,2) not null default 0,
 created_at timestamptz not null default now(), unique(run_id,employee_id)
);

create table if not exists unimis.hrc_payroll_run_items (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
 run_employee_id uuid not null references unimis.hrc_payroll_run_employees(id) on delete cascade,
 component_code text not null, component_name text not null, component_type text not null,
 amount numeric(14,2) not null default 0, taxable boolean not null default false, pensionable boolean not null default false
);

create table if not exists unimis.hrc_payroll_payslips (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
 run_id uuid not null references unimis.hrc_payroll_runs(id) on delete cascade,
 run_employee_id uuid not null references unimis.hrc_payroll_run_employees(id) on delete cascade,
 employee_id uuid not null references unimis.hrc_hr_employees(id) on delete restrict,
 payslip_no text not null, issued_at timestamptz not null default now(), unique(tenant_id,payslip_no), unique(run_employee_id)
);

create table if not exists unimis.hrc_payroll_payment_batches (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
 run_id uuid not null references unimis.hrc_payroll_runs(id) on delete restrict,
 batch_no text not null, payment_method text not null default 'bank', amount numeric(14,2) not null default 0,
 status text not null default 'draft' check(status in ('draft','ready','paid','cancelled')),
 created_by uuid references auth.users(id), created_at timestamptz not null default now(), paid_at timestamptz,
 unique(tenant_id,batch_no)
);

create index if not exists idx_payroll_runs_tenant on unimis.hrc_payroll_runs(tenant_id,created_at desc);
create index if not exists idx_run_employees_run on unimis.hrc_payroll_run_employees(run_id);
create index if not exists idx_payslips_employee on unimis.hrc_payroll_payslips(employee_id,issued_at desc);

alter table unimis.hrc_payroll_settings enable row level security;
alter table unimis.hrc_payroll_runs enable row level security;
alter table unimis.hrc_payroll_run_employees enable row level security;
alter table unimis.hrc_payroll_run_items enable row level security;
alter table unimis.hrc_payroll_payslips enable row level security;
alter table unimis.hrc_payroll_payment_batches enable row level security;

do $$ declare t text; begin
 foreach t in array array['hrc_payroll_settings','hrc_payroll_runs','hrc_payroll_run_employees','hrc_payroll_run_items','hrc_payroll_payslips','hrc_payroll_payment_batches'] loop
   execute format('create policy %I on unimis.%I for select using (unimis.is_tenant_member(tenant_id))', t||'_read_002', t);
 end loop;
end $$;
create policy "payroll settings managers" on unimis.hrc_payroll_settings for all
 using(unimis.has_tenant_role(tenant_id,array['owner','administrator','payroll_manager']))
 with check(unimis.has_tenant_role(tenant_id,array['owner','administrator','payroll_manager']));
create policy "payroll runs managers" on unimis.hrc_payroll_runs for all
 using(unimis.has_tenant_role(tenant_id,array['owner','administrator','payroll_manager','payroll_officer','finance_manager']))
 with check(unimis.has_tenant_role(tenant_id,array['owner','administrator','payroll_manager','payroll_officer','finance_manager']));
create policy "run employees managers" on unimis.hrc_payroll_run_employees for all
 using(unimis.has_tenant_role(tenant_id,array['owner','administrator','payroll_manager','payroll_officer','finance_manager']))
 with check(unimis.has_tenant_role(tenant_id,array['owner','administrator','payroll_manager','payroll_officer','finance_manager']));
create policy "run items managers" on unimis.hrc_payroll_run_items for all
 using(unimis.has_tenant_role(tenant_id,array['owner','administrator','payroll_manager','payroll_officer','finance_manager']))
 with check(unimis.has_tenant_role(tenant_id,array['owner','administrator','payroll_manager','payroll_officer','finance_manager']));
create policy "payslip managers" on unimis.hrc_payroll_payslips for all
 using(unimis.has_tenant_role(tenant_id,array['owner','administrator','payroll_manager','payroll_officer','finance_manager']))
 with check(unimis.has_tenant_role(tenant_id,array['owner','administrator','payroll_manager','payroll_officer','finance_manager']));
create policy "payment batch managers" on unimis.hrc_payroll_payment_batches for all
 using(unimis.has_tenant_role(tenant_id,array['owner','administrator','payroll_manager','finance_manager']))
 with check(unimis.has_tenant_role(tenant_id,array['owner','administrator','payroll_manager','finance_manager']));

-- Create one employee + contract + payroll profile atomically.
create or replace function unimis.hr_create_employee(
 p_tenant uuid,p_employee_no text,p_first_name text,p_last_name text,p_email text,
 p_department uuid,p_position uuid,p_hire_date date,p_basic_salary numeric
) returns uuid language plpgsql security definer set search_path=unimis as $$
declare e uuid; g uuid;
begin
 if not unimis.has_tenant_role(p_tenant,array['owner','administrator','hr_manager','hr_officer']) then raise exception 'HR access denied'; end if;
 insert into unimis.hrc_hr_employees(tenant_id,employee_no,first_name,last_name,email,department_id,position_id,hire_date)
 values(p_tenant,upper(trim(p_employee_no)),trim(p_first_name),trim(p_last_name),nullif(trim(p_email),''),p_department,p_position,p_hire_date)
 returning id into e;
 insert into unimis.hrc_hr_employment_contracts(tenant_id,employee_id,start_date,basic_salary)
 values(p_tenant,e,coalesce(p_hire_date,current_date),coalesce(p_basic_salary,0));
 select id into g from unimis.hrc_payroll_pay_groups where tenant_id=p_tenant and active order by created_at limit 1;
 insert into unimis.hrc_payroll_profiles(tenant_id,employee_id,pay_group_id) values(p_tenant,e,g);
 insert into unimis.hrc_audit_events(tenant_id,actor_id,module,action,record_type,record_id)
 values(p_tenant,auth.uid(),'hr','employee.created','employee',e);
 return e;
end $$;
grant execute on function unimis.hr_create_employee(uuid,text,text,text,text,uuid,uuid,date,numeric) to authenticated;

-- Calculate a payroll run. Statutory percentages are tenant-configurable and default to zero until verified.
create or replace function unimis.payroll_calculate_run(p_tenant uuid,p_period uuid)
returns uuid language plpgsql security definer set search_path=unimis as $$
declare r uuid; rn text; s unimis.hrc_payroll_settings%rowtype; rec record; re uuid;
        basic numeric; earn numeric; ded numeric; gross numeric; ep numeric; erp numeric; tx numeric; net numeric;
begin
 if not unimis.has_tenant_role(p_tenant,array['owner','administrator','payroll_manager','payroll_officer']) then raise exception 'Payroll access denied'; end if;
 if not exists(select 1 from unimis.hrc_payroll_periods where id=p_period and tenant_id=p_tenant) then raise exception 'Invalid payroll period'; end if;
 insert into unimis.hrc_payroll_settings(tenant_id) values(p_tenant) on conflict(tenant_id) do nothing;
 select * into s from unimis.hrc_payroll_settings where tenant_id=p_tenant;
 select id into r from unimis.hrc_payroll_runs where tenant_id=p_tenant and period_id=p_period;
 if r is null then
   rn:='RUN-'||to_char(current_date,'YYYYMM')||'-'||lpad((1+(select count(*) from unimis.hrc_payroll_runs where tenant_id=p_tenant))::text,3,'0');
   insert into unimis.hrc_payroll_runs(tenant_id,period_id,run_no,status,created_by) values(p_tenant,p_period,rn,'draft',auth.uid()) returning id into r;
 else
   if exists(select 1 from unimis.hrc_payroll_runs where id=r and status in ('approved','posted')) then raise exception 'Approved/posted payroll cannot be recalculated'; end if;
   delete from unimis.hrc_payroll_run_employees where run_id=r; update unimis.hrc_payroll_runs set status='draft' where id=r;
 end if;
 for rec in select e.* from unimis.hrc_hr_employees e join unimis.hrc_payroll_profiles pp on pp.employee_id=e.id and pp.active
            where e.tenant_id=p_tenant and e.employment_status='active' loop
   select coalesce(c.basic_salary,0) into basic from unimis.hrc_hr_employment_contracts c where c.employee_id=rec.id and c.status='active' order by c.start_date desc limit 1;
   select coalesce(sum(pec.amount) filter (where pc.component_type='earning'),0), coalesce(sum(pec.amount) filter (where pc.component_type='deduction'),0)
     into earn,ded from unimis.hrc_payroll_employee_components pec join unimis.hrc_payroll_components pc on pc.id=pec.component_id
     where pec.employee_id=rec.id and pec.tenant_id=p_tenant and pec.effective_from <= current_date and (pec.effective_to is null or pec.effective_to>=current_date) and pc.code<>'BASIC';
   earn:=coalesce(earn,0); ded:=coalesce(ded,0); gross:=basic+earn;
   ep:=round(gross*s.employee_pension_rate/100,2); erp:=round(gross*s.employer_pension_rate/100,2);
   tx:=0; -- PAYE engine remains disabled until verified statutory bands are configured.
   net:=gross-ep-tx-ded;
   insert into unimis.hrc_payroll_run_employees(tenant_id,run_id,employee_id,employee_no,employee_name,basic_salary,other_earnings,gross_pay,employee_pension,employer_pension,tax,other_deductions,net_pay)
   values(p_tenant,r,rec.id,rec.employee_no,concat_ws(' ',rec.first_name,rec.other_names,rec.last_name),basic,earn,gross,ep,erp,tx,ded,net) returning id into re;
   insert into unimis.hrc_payroll_run_items(tenant_id,run_employee_id,component_code,component_name,component_type,amount,taxable,pensionable)
   values(p_tenant,re,'BASIC','Basic Salary','earning',basic,true,true);
   insert into unimis.hrc_payroll_run_items(tenant_id,run_employee_id,component_code,component_name,component_type,amount,taxable,pensionable)
   select p_tenant,re,pc.code,pc.name,pc.component_type,pec.amount,pc.taxable,pc.pensionable
   from unimis.hrc_payroll_employee_components pec join unimis.hrc_payroll_components pc on pc.id=pec.component_id
   where pec.employee_id=rec.id and pec.tenant_id=p_tenant and pc.code<>'BASIC' and pec.effective_from<=current_date and (pec.effective_to is null or pec.effective_to>=current_date);
 end loop;
 update unimis.hrc_payroll_runs pr set status='calculated', employee_count=x.cnt,gross_total=x.gross,deduction_total=x.ded,
 employee_pension_total=x.ep,employer_pension_total=x.erp,tax_total=x.tax,net_total=x.net
 from (select count(*) cnt,coalesce(sum(gross_pay),0) gross,coalesce(sum(other_deductions),0) ded,coalesce(sum(employee_pension),0) ep,
 coalesce(sum(employer_pension),0) erp,coalesce(sum(tax),0) tax,coalesce(sum(net_pay),0) net from unimis.hrc_payroll_run_employees where run_id=r) x where pr.id=r;
 update unimis.hrc_payroll_periods set status='review' where id=p_period;
 insert into unimis.hrc_audit_events(tenant_id,actor_id,module,action,record_type,record_id) values(p_tenant,auth.uid(),'payroll','run.calculated','payroll_run',r);
 return r;
end $$;
grant execute on function unimis.payroll_calculate_run(uuid,uuid) to authenticated;

create or replace function unimis.payroll_approve_run(p_tenant uuid,p_run uuid)
returns void language plpgsql security definer set search_path=unimis as $$
begin
 if not unimis.has_tenant_role(p_tenant,array['owner','administrator','payroll_manager','approver']) then raise exception 'Approval access denied'; end if;
 update unimis.hrc_payroll_runs set status='approved',approved_by=auth.uid(),approved_at=now() where id=p_run and tenant_id=p_tenant and status in ('calculated','review');
 if not found then raise exception 'Payroll run is not ready for approval'; end if;
 update unimis.hrc_payroll_periods set status='approved' where id=(select period_id from unimis.hrc_payroll_runs where id=p_run);
 insert into unimis.hrc_audit_events(tenant_id,actor_id,module,action,record_type,record_id) values(p_tenant,auth.uid(),'payroll','run.approved','payroll_run',p_run);
end $$;
grant execute on function unimis.payroll_approve_run(uuid,uuid) to authenticated;

create or replace function unimis.payroll_post_run(p_tenant uuid,p_run uuid)
returns void language plpgsql security definer set search_path=unimis as $$
declare rr record; n integer:=0;
begin
 if not unimis.has_tenant_role(p_tenant,array['owner','administrator','payroll_manager','finance_manager']) then raise exception 'Posting access denied'; end if;
 if not exists(select 1 from unimis.hrc_payroll_runs where id=p_run and tenant_id=p_tenant and status='approved') then raise exception 'Only approved payroll can be posted'; end if;
 for rr in select * from unimis.hrc_payroll_run_employees where run_id=p_run loop
   n:=n+1;
   insert into unimis.hrc_payroll_payslips(tenant_id,run_id,run_employee_id,employee_id,payslip_no)
   values(p_tenant,p_run,rr.id,rr.employee_id,'PS-'||to_char(current_date,'YYYYMM')||'-'||lpad(n::text,4,'0')) on conflict(run_employee_id) do nothing;
 end loop;
 update unimis.hrc_payroll_runs set status='posted',posted_by=auth.uid(),posted_at=now() where id=p_run;
 update unimis.hrc_payroll_periods set status='posted' where id=(select period_id from unimis.hrc_payroll_runs where id=p_run);
 insert into unimis.hrc_payroll_payment_batches(tenant_id,run_id,batch_no,amount,created_by)
 select p_tenant,p_run,'PB-'||to_char(current_date,'YYYYMMDD')||'-'||substr(p_run::text,1,6),net_total,auth.uid() from unimis.hrc_payroll_runs where id=p_run
 on conflict(tenant_id,batch_no) do nothing;
 insert into unimis.hrc_audit_events(tenant_id,actor_id,module,action,record_type,record_id) values(p_tenant,auth.uid(),'payroll','run.posted','payroll_run',p_run);
end $$;
grant execute on function unimis.payroll_post_run(uuid,uuid) to authenticated;

-- Optional demo data for testing. It never runs automatically.
create or replace function unimis.seed_hrpayroll_demo(p_tenant uuid)
returns void language plpgsql security definer set search_path=unimis as $$
declare b uuid; d1 uuid; d2 uuid; g1 uuid; p1 uuid; p2 uuid; pg uuid; e uuid; i int;
begin
 if not unimis.has_tenant_role(p_tenant,array['owner','administrator']) then raise exception 'Owner/admin required'; end if;
 select id into b from unimis.hrc_branches where tenant_id=p_tenant order by created_at limit 1;
 insert into unimis.hrc_departments(tenant_id,branch_id,code,name) values(p_tenant,b,'ADM','Administration') on conflict(tenant_id,code) do update set name=excluded.name returning id into d1;
 insert into unimis.hrc_departments(tenant_id,branch_id,code,name) values(p_tenant,b,'FIN','Finance') on conflict(tenant_id,code) do update set name=excluded.name returning id into d2;
 insert into unimis.hrc_hr_job_grades(tenant_id,code,name,min_salary,max_salary) values(p_tenant,'G1','Officer',2500,6000) on conflict(tenant_id,code) do update set name=excluded.name returning id into g1;
 insert into unimis.hrc_hr_positions(tenant_id,department_id,grade_id,code,title) values(p_tenant,d1,g1,'ADMIN-OFF','Administrative Officer') on conflict(tenant_id,code) do update set title=excluded.title returning id into p1;
 insert into unimis.hrc_hr_positions(tenant_id,department_id,grade_id,code,title) values(p_tenant,d2,g1,'ACCT-OFF','Accounts Officer') on conflict(tenant_id,code) do update set title=excluded.title returning id into p2;
 select id into pg from unimis.hrc_payroll_pay_groups where tenant_id=p_tenant order by created_at limit 1;
 if not exists(select 1 from unimis.hrc_hr_employees where tenant_id=p_tenant and employee_no='EMP001') then
  insert into unimis.hrc_hr_employees(tenant_id,employee_no,first_name,last_name,email,branch_id,department_id,position_id,hire_date) values(p_tenant,'EMP001','Ama','Mensah','ama.mensah@example.test',b,d1,p1,current_date-500) returning id into e;
  insert into unimis.hrc_hr_employment_contracts(tenant_id,employee_id,start_date,basic_salary) values(p_tenant,e,current_date-500,4200);
  insert into unimis.hrc_payroll_profiles(tenant_id,employee_id,pay_group_id,bank_name,payment_method) values(p_tenant,e,pg,'Demo Bank','bank');
 end if;
 if not exists(select 1 from unimis.hrc_hr_employees where tenant_id=p_tenant and employee_no='EMP002') then
  insert into unimis.hrc_hr_employees(tenant_id,employee_no,first_name,last_name,email,branch_id,department_id,position_id,hire_date) values(p_tenant,'EMP002','Kwame','Asare','kwame.asare@example.test',b,d2,p2,current_date-420) returning id into e;
  insert into unimis.hrc_hr_employment_contracts(tenant_id,employee_id,start_date,basic_salary) values(p_tenant,e,current_date-420,5000);
  insert into unimis.hrc_payroll_profiles(tenant_id,employee_id,pay_group_id,bank_name,payment_method) values(p_tenant,e,pg,'Demo Bank','bank');
 end if;
 if not exists(select 1 from unimis.hrc_payroll_periods where tenant_id=p_tenant and name=to_char(current_date,'FMMonth YYYY')) then
  insert into unimis.hrc_payroll_periods(tenant_id,pay_group_id,name,start_date,end_date,pay_date)
  values(p_tenant,pg,to_char(current_date,'FMMonth YYYY'),date_trunc('month',current_date)::date,(date_trunc('month',current_date)+interval '1 month - 1 day')::date,(date_trunc('month',current_date)+interval '1 month - 1 day')::date);
 end if;
 insert into unimis.hrc_payroll_settings(tenant_id) values(p_tenant) on conflict(tenant_id) do nothing;
 insert into unimis.hrc_audit_events(tenant_id,actor_id,module,action,record_type,record_id,details) values(p_tenant,auth.uid(),'core','demo.seeded','tenant',p_tenant,jsonb_build_object('package','002'));
end $$;
grant execute on function unimis.seed_hrpayroll_demo(uuid) to authenticated;

notify pgrst, 'reload schema';


-- SOURCE 202610140003_employee_dob_ui.sql
-- Package 002b: employee DOB foundation for age-aware payroll/statutory processing.
alter table unimis.hrc_hr_employees add column if not exists date_of_birth date;

-- Replace the employee creation RPC with a DOB-aware signature.
drop function if exists unimis.hr_create_employee(uuid,text,text,text,text,uuid,uuid,date,numeric);
create or replace function unimis.hr_create_employee(
 p_tenant uuid,p_employee_no text,p_first_name text,p_last_name text,p_email text,
 p_department uuid,p_position uuid,p_date_of_birth date,p_hire_date date,p_basic_salary numeric
) returns uuid language plpgsql security definer set search_path=unimis as $$
declare e uuid; g uuid;
begin
 if not unimis.has_tenant_role(p_tenant,array['owner','administrator','hr_manager','hr_officer']) then raise exception 'HR access denied'; end if;
 if p_date_of_birth is not null and p_date_of_birth > current_date then raise exception 'Date of birth cannot be in the future'; end if;
 insert into unimis.hrc_hr_employees(tenant_id,employee_no,first_name,last_name,email,department_id,position_id,date_of_birth,hire_date)
 values(p_tenant,upper(trim(p_employee_no)),trim(p_first_name),trim(p_last_name),nullif(trim(p_email),''),p_department,p_position,p_date_of_birth,p_hire_date)
 returning id into e;
 insert into unimis.hrc_hr_employment_contracts(tenant_id,employee_id,start_date,basic_salary)
 values(p_tenant,e,coalesce(p_hire_date,current_date),coalesce(p_basic_salary,0));
 select id into g from unimis.hrc_payroll_pay_groups where tenant_id=p_tenant and active order by created_at limit 1;
 insert into unimis.hrc_payroll_profiles(tenant_id,employee_id,pay_group_id) values(p_tenant,e,g);
 insert into unimis.hrc_audit_events(tenant_id,actor_id,module,action,record_type,record_id)
 values(p_tenant,auth.uid(),'hr','employee.created','employee',e);
 return e;
end $$;
grant execute on function unimis.hr_create_employee(uuid,text,text,text,text,uuid,uuid,date,date,numeric) to authenticated;

comment on column unimis.hrc_hr_employees.date_of_birth is 'Employee date of birth; supports age-aware statutory eligibility, retirement/pension handling, birthday workflows and HR reporting.';


-- SOURCE 202610140004_employee_master_compensation.sql
-- Package 002c: Employee Master + employment classification + compensation history + private photos.
alter table unimis.hrc_hr_employees
  add column if not exists photo_path text,
  add column if not exists employment_type text not null default 'regular',
  add column if not exists work_schedule text not null default 'full_time',
  add column if not exists pension_status text not null default 'applicable';

alter table unimis.hrc_hr_employment_contracts
  add column if not exists pay_basis text not null default 'monthly',
  add column if not exists daily_rate numeric(14,2) not null default 0,
  add column if not exists hourly_rate numeric(14,2) not null default 0,
  add column if not exists probation_end_date date,
  add column if not exists notice_days integer not null default 30;

create table if not exists unimis.hrc_hr_salary_history (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
 employee_id uuid not null references unimis.hrc_hr_employees(id) on delete cascade,
 old_salary numeric(14,2), new_salary numeric(14,2) not null,
 change_type text not null default 'initial' check(change_type in ('initial','manual','grade_step','promotion','bulk_adjustment','correction')),
 reason text, effective_from date not null, approved_by uuid references auth.users(id), created_by uuid references auth.users(id), created_at timestamptz default now()
);
create index if not exists hr_salary_history_employee_idx on unimis.hrc_hr_salary_history(employee_id,effective_from desc);
alter table unimis.hrc_hr_salary_history enable row level security;
drop policy if exists hr_salary_history_tenant on unimis.hrc_hr_salary_history;
create policy hr_salary_history_tenant on unimis.hrc_hr_salary_history for all to authenticated using(unimis.is_tenant_member(tenant_id)) with check(unimis.is_tenant_member(tenant_id));

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('employee-photos','employee-photos',false,5242880,array['image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists employee_photos_read on storage.objects;
create policy employee_photos_read on storage.objects for select to authenticated
using(bucket_id='employee-photos' and unimis.is_tenant_member(((storage.foldername(name))[1])::uuid));
drop policy if exists employee_photos_insert on storage.objects;
create policy employee_photos_insert on storage.objects for insert to authenticated
with check(bucket_id='employee-photos' and unimis.has_tenant_role(((storage.foldername(name))[1])::uuid,array['owner','administrator','hr_manager','hr_officer']));
drop policy if exists employee_photos_update on storage.objects;
create policy employee_photos_update on storage.objects for update to authenticated
using(bucket_id='employee-photos' and unimis.has_tenant_role(((storage.foldername(name))[1])::uuid,array['owner','administrator','hr_manager','hr_officer']))
with check(bucket_id='employee-photos' and unimis.has_tenant_role(((storage.foldername(name))[1])::uuid,array['owner','administrator','hr_manager','hr_officer']));

-- Replace Package 002b employee RPC with richer employment master signature.
drop function if exists unimis.hr_create_employee(uuid,text,text,text,text,uuid,uuid,date,date,numeric);
create or replace function unimis.hr_create_employee(
 p_tenant uuid,p_employee_no text,p_first_name text,p_last_name text,p_email text,
 p_department uuid,p_position uuid,p_date_of_birth date,p_hire_date date,p_basic_salary numeric,
 p_employment_type text default 'regular',p_work_schedule text default 'full_time',p_pay_basis text default 'monthly',
 p_contract_end date default null,p_pension_status text default 'applicable'
) returns uuid language plpgsql security definer set search_path=unimis as $$
declare e uuid; g uuid;
begin
 if not unimis.has_tenant_role(p_tenant,array['owner','administrator','hr_manager','hr_officer']) then raise exception 'HR access denied'; end if;
 if p_date_of_birth is not null and p_date_of_birth > current_date then raise exception 'Date of birth cannot be in the future'; end if;
 if p_employment_type not in ('regular','fixed_term','casual','temporary','intern','national_service','consultant') then raise exception 'Invalid employment type'; end if;
 if p_work_schedule not in ('full_time','part_time','shift','hourly') then raise exception 'Invalid work schedule'; end if;
 if p_pay_basis not in ('monthly','weekly','daily','hourly') then raise exception 'Invalid pay basis'; end if;
 insert into unimis.hrc_hr_employees(tenant_id,employee_no,first_name,last_name,email,department_id,position_id,date_of_birth,hire_date,employment_type,work_schedule,pension_status)
 values(p_tenant,upper(trim(p_employee_no)),trim(p_first_name),trim(p_last_name),nullif(trim(p_email),''),p_department,p_position,p_date_of_birth,p_hire_date,p_employment_type,p_work_schedule,p_pension_status)
 returning id into e;
 insert into unimis.hrc_hr_employment_contracts(tenant_id,employee_id,contract_type,start_date,end_date,basic_salary,pay_frequency,pay_basis)
 values(p_tenant,e,p_employment_type,coalesce(p_hire_date,current_date),p_contract_end,coalesce(p_basic_salary,0),p_pay_basis,p_pay_basis);
 insert into unimis.hrc_hr_salary_history(tenant_id,employee_id,new_salary,change_type,reason,effective_from,created_by)
 values(p_tenant,e,coalesce(p_basic_salary,0),'initial','Initial appointment',coalesce(p_hire_date,current_date),auth.uid());
 select id into g from unimis.hrc_payroll_pay_groups where tenant_id=p_tenant and active order by created_at limit 1;
 insert into unimis.hrc_payroll_profiles(tenant_id,employee_id,pay_group_id) values(p_tenant,e,g);
 insert into unimis.hrc_audit_events(tenant_id,actor_id,module,action,record_type,record_id,details)
 values(p_tenant,auth.uid(),'hr','employee.created','employee',e,jsonb_build_object('employment_type',p_employment_type,'pay_basis',p_pay_basis));
 return e;
end $$;
grant execute on function unimis.hr_create_employee(uuid,text,text,text,text,uuid,uuid,date,date,numeric,text,text,text,date,text) to authenticated;

create or replace function unimis.hr_change_salary(p_tenant uuid,p_employee uuid,p_new_salary numeric,p_effective date,p_change_type text default 'manual',p_reason text default null)
returns uuid language plpgsql security definer set search_path=unimis as $$
declare c uuid; oldv numeric; h uuid;
begin
 if not unimis.has_tenant_role(p_tenant,array['owner','administrator','hr_manager','payroll_manager']) then raise exception 'Salary change access denied'; end if;
 if p_new_salary < 0 then raise exception 'Salary cannot be negative'; end if;
 select id,basic_salary into c,oldv from unimis.hrc_hr_employment_contracts where tenant_id=p_tenant and employee_id=p_employee and status='active' order by start_date desc limit 1;
 if c is null then raise exception 'Active contract not found'; end if;
 update unimis.hrc_hr_employment_contracts set basic_salary=p_new_salary where id=c;
 insert into unimis.hrc_hr_salary_history(tenant_id,employee_id,old_salary,new_salary,change_type,reason,effective_from,approved_by,created_by)
 values(p_tenant,p_employee,oldv,p_new_salary,p_change_type,p_reason,coalesce(p_effective,current_date),auth.uid(),auth.uid()) returning id into h;
 return h;
end $$;
grant execute on function unimis.hr_change_salary(uuid,uuid,numeric,date,text,text) to authenticated;


-- SOURCE 202610140005_employee_master_full_profile.sql
-- Package 002d: Full HR Employee Master.
alter table unimis.hrc_hr_employees
 add column if not exists gender text,
 add column if not exists marital_status text,
 add column if not exists nationality text default 'Ghanaian',
 add column if not exists national_id text,
 add column if not exists residential_address text,
 add column if not exists postal_address text,
 add column if not exists supervisor_id uuid references unimis.hrc_hr_employees(id) on delete set null;

alter table unimis.hrc_payroll_profiles
 add column if not exists bank_branch text,
 add column if not exists momo_number text,
 add column if not exists momo_network text;

create table if not exists unimis.hrc_hr_employee_qualifications(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
 employee_id uuid not null references unimis.hrc_hr_employees(id) on delete cascade,
 qualification_type text not null default 'academic', qualification text not null, institution text,
 field_of_study text, start_year integer, completion_year integer, certificate_no text, notes text,
 created_at timestamptz default now()
);
create table if not exists unimis.hrc_hr_employee_documents(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
 employee_id uuid not null references unimis.hrc_hr_employees(id) on delete cascade,
 document_type text not null, title text not null, file_path text not null, issue_date date, expiry_date date,
 notes text, uploaded_by uuid references auth.users(id), created_at timestamptz default now()
);
create table if not exists unimis.hrc_hr_emergency_contacts(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
 employee_id uuid not null references unimis.hrc_hr_employees(id) on delete cascade,
 full_name text not null, relationship text, phone text not null, alternate_phone text, address text,
 is_primary boolean default true, created_at timestamptz default now()
);
create table if not exists unimis.hrc_hr_employment_events(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
 employee_id uuid not null references unimis.hrc_hr_employees(id) on delete cascade,
 event_type text not null, effective_date date not null, title text, details jsonb default '{}'::jsonb,
 created_by uuid references auth.users(id), created_at timestamptz default now()
);

do $$ declare t text; begin
 foreach t in array array['hrc_hr_employee_qualifications','hrc_hr_employee_documents','hrc_hr_emergency_contacts','hrc_hr_employment_events'] loop
   execute format('alter table unimis.%I enable row level security',t);
   execute format('create policy %I on unimis.%I for select using(unimis.is_tenant_member(tenant_id))',t||'_read',t);
   execute format('create policy %I on unimis.%I for insert with check(unimis.has_tenant_role(tenant_id,array[''owner'',''administrator'',''hr_manager'',''hr_officer'']))',t||'_insert',t);
   execute format('create policy %I on unimis.%I for update using(unimis.has_tenant_role(tenant_id,array[''owner'',''administrator'',''hr_manager'',''hr_officer''])) with check(unimis.has_tenant_role(tenant_id,array[''owner'',''administrator'',''hr_manager'',''hr_officer'']))',t||'_update',t);
   execute format('create policy %I on unimis.%I for delete using(unimis.has_tenant_role(tenant_id,array[''owner'',''administrator'',''hr_manager'']))',t||'_delete',t);
 end loop;
end $$;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('employee-documents','employee-documents',false,10485760,array['application/pdf','image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists employee_documents_read on storage.objects;
create policy employee_documents_read on storage.objects for select to authenticated
using(bucket_id='employee-documents' and unimis.is_tenant_member(((storage.foldername(name))[1])::uuid));
drop policy if exists employee_documents_insert on storage.objects;
create policy employee_documents_insert on storage.objects for insert to authenticated
with check(bucket_id='employee-documents' and unimis.has_tenant_role(((storage.foldername(name))[1])::uuid,array['owner','administrator','hr_manager','hr_officer']));
drop policy if exists employee_documents_update on storage.objects;
create policy employee_documents_update on storage.objects for update to authenticated
using(bucket_id='employee-documents' and unimis.has_tenant_role(((storage.foldername(name))[1])::uuid,array['owner','administrator','hr_manager','hr_officer']))
with check(bucket_id='employee-documents' and unimis.has_tenant_role(((storage.foldername(name))[1])::uuid,array['owner','administrator','hr_manager','hr_officer']));
drop policy if exists employee_documents_delete on storage.objects;
create policy employee_documents_delete on storage.objects for delete to authenticated
using(bucket_id='employee-documents' and unimis.has_tenant_role(((storage.foldername(name))[1])::uuid,array['owner','administrator','hr_manager']));

create or replace function unimis.hr_record_employment_event(p_tenant uuid,p_employee uuid,p_type text,p_effective date,p_title text,p_details jsonb default '{}'::jsonb)
returns uuid language plpgsql security definer set search_path=unimis as $$ declare x uuid; begin
 if not unimis.has_tenant_role(p_tenant,array['owner','administrator','hr_manager','hr_officer']) then raise exception 'HR access denied'; end if;
 insert into unimis.hrc_hr_employment_events(tenant_id,employee_id,event_type,effective_date,title,details,created_by)
 values(p_tenant,p_employee,p_type,coalesce(p_effective,current_date),p_title,coalesce(p_details,'{}'::jsonb),auth.uid()) returning id into x;
 return x; end $$;
grant execute on function unimis.hr_record_employment_event(uuid,uuid,text,date,text,jsonb) to authenticated;

notify pgrst, 'reload schema';


-- SOURCE 202610140006_recruitment_onboarding.sql
-- Package 003: Recruitment + onboarding feeding the HR Employee Master.
create table if not exists unimis.hrc_hr_vacancies(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
 title text not null, department_id uuid references unimis.hrc_departments(id) on delete set null,
 position_id uuid references unimis.hrc_hr_positions(id) on delete set null, openings integer not null default 1 check(openings>0),
 employment_type text not null default 'regular', description text, requirements text, closing_date date,
 status text not null default 'draft' check(status in ('draft','open','closed','cancelled')),
 created_by uuid references auth.users(id), created_at timestamptz not null default now()
);
create table if not exists unimis.hrc_hr_applicants(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
 vacancy_id uuid references unimis.hrc_hr_vacancies(id) on delete set null, first_name text not null, last_name text not null,
 email text, phone text, date_of_birth date, source text, cv_path text,
 status text not null default 'applied' check(status in ('applied','shortlisted','interviewed','rejected','offered','offer_accepted','offer_declined','hired')),
 employee_id uuid references unimis.hrc_hr_employees(id) on delete set null, notes text,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists unimis.hrc_hr_interviews(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
 applicant_id uuid not null references unimis.hrc_hr_applicants(id) on delete cascade, interview_at timestamptz,
 interview_type text default 'in_person', panel_notes text, score numeric(5,2), recommendation text,
 created_by uuid references auth.users(id), created_at timestamptz default now()
);
create table if not exists unimis.hrc_hr_offers(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.hrc_tenants(id) on delete cascade,
 applicant_id uuid not null references unimis.hrc_hr_applicants(id) on delete cascade, offered_salary numeric(14,2) default 0,
 proposed_start_date date, employment_type text default 'regular', status text default 'draft' check(status in ('draft','issued','accepted','declined','withdrawn')),
 issued_at timestamptz, responded_at timestamptz, created_by uuid references auth.users(id), created_at timestamptz default now()
);

do $$ declare t text; begin
 foreach t in array array['hrc_hr_vacancies','hrc_hr_applicants','hrc_hr_interviews','hrc_hr_offers'] loop
  execute format('alter table unimis.%I enable row level security',t);
  execute format('create policy %I on unimis.%I for select using(unimis.is_tenant_member(tenant_id))',t||'_read',t);
  execute format('create policy %I on unimis.%I for insert with check(unimis.has_tenant_role(tenant_id,array[''owner'',''administrator'',''hr_manager'',''hr_officer'']))',t||'_insert',t);
  execute format('create policy %I on unimis.%I for update using(unimis.has_tenant_role(tenant_id,array[''owner'',''administrator'',''hr_manager'',''hr_officer''])) with check(unimis.has_tenant_role(tenant_id,array[''owner'',''administrator'',''hr_manager'',''hr_officer'']))',t||'_update',t);
  execute format('create policy %I on unimis.%I for delete using(unimis.has_tenant_role(tenant_id,array[''owner'',''administrator'',''hr_manager'']))',t||'_delete',t);
 end loop;
end $$;

create or replace function unimis.hr_hire_applicant(p_tenant uuid,p_applicant uuid,p_employee_no text,p_hire_date date,p_basic_salary numeric default 0)
returns uuid language plpgsql security definer set search_path=unimis as $$
declare a unimis.hrc_hr_applicants%rowtype; v unimis.hrc_hr_vacancies%rowtype; e uuid;
begin
 if not unimis.has_tenant_role(p_tenant,array['owner','administrator','hr_manager']) then raise exception 'Hiring access denied'; end if;
 select * into a from unimis.hrc_hr_applicants where id=p_applicant and tenant_id=p_tenant for update;
 if a.id is null then raise exception 'Applicant not found'; end if;
 if a.status <> 'offer_accepted' then raise exception 'Offer must be accepted before hiring'; end if;
 if a.employee_id is not null then raise exception 'Applicant is already linked to an employee'; end if;
 if a.vacancy_id is not null then select * into v from unimis.hrc_hr_vacancies where id=a.vacancy_id and tenant_id=p_tenant; end if;
 e:=unimis.hr_create_employee(p_tenant,p_employee_no,a.first_name,a.last_name,coalesce(a.email,''),v.department_id,v.position_id,a.date_of_birth,p_hire_date,coalesce(p_basic_salary,0),coalesce(v.employment_type,'regular'),'full_time','monthly',null,'applicable');
 update unimis.hrc_hr_employees set phone=coalesce(a.phone,phone) where id=e;
 update unimis.hrc_hr_applicants set status='hired',employee_id=e,updated_at=now() where id=a.id;
 perform unimis.hr_record_employment_event(p_tenant,e,'recruitment_hire',p_hire_date,'Hired from recruitment',jsonb_build_object('applicant_id',a.id,'vacancy_id',a.vacancy_id));
 return e;
end $$;
grant execute on function unimis.hr_hire_applicant(uuid,uuid,text,date,numeric) to authenticated;

create index if not exists hr_vacancies_tenant_status_idx on unimis.hrc_hr_vacancies(tenant_id,status);
create index if not exists hr_applicants_tenant_status_idx on unimis.hrc_hr_applicants(tenant_id,status);
notify pgrst, 'reload schema';




-- Refresh Supabase/PostgREST schema cache after this stage.
NOTIFY pgrst, 'reload schema';
