-- UniMIS Build 167 shared-test HRPayrollCore installer
-- Target: shared Supabase, UniMIS schema. Review before execution.
create schema if not exists unimis;

-- SOURCE 202610140001_hrpayroll_foundation.sql
create extension if not exists pgcrypto;

create table if not exists unimis.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  phone text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists unimis.tenants (
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

create table if not exists unimis.tenant_memberships (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references unimis.tenants(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('owner','administrator','hr_manager','hr_officer','payroll_manager','payroll_officer','finance_manager','approver','auditor','employee')),
  status text not null default 'active' check (status in ('active','invited','suspended')),
  created_at timestamptz not null default now(),
  unique (tenant_id,user_id)
);

create or replace function unimis.is_tenant_member(p_tenant uuid)
returns boolean language sql stable security definer set search_path=unimis as $$
  select exists(select 1 from unimis.tenant_memberships m where m.tenant_id=p_tenant and m.user_id=auth.uid() and m.status='active');
$$;
create or replace function unimis.has_tenant_role(p_tenant uuid, p_roles text[])
returns boolean language sql stable security definer set search_path=unimis as $$
  select exists(select 1 from unimis.tenant_memberships m where m.tenant_id=p_tenant and m.user_id=auth.uid() and m.status='active' and m.role=any(p_roles));
$$;

grant execute on function unimis.is_tenant_member(uuid) to authenticated;
grant execute on function unimis.has_tenant_role(uuid,text[]) to authenticated;

create table if not exists unimis.legal_entities (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.tenants(id) on delete cascade,
 name text not null, registration_no text, tax_id text, country_code text not null default 'GH', currency text not null default 'GHS', created_at timestamptz default now()
);
create table if not exists unimis.branches (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.tenants(id) on delete cascade,
 legal_entity_id uuid references unimis.legal_entities(id) on delete cascade, code text not null, name text not null, city text, active boolean default true, created_at timestamptz default now(), unique(tenant_id,code)
);
create table if not exists unimis.departments (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.tenants(id) on delete cascade,
 branch_id uuid references unimis.branches(id) on delete set null, code text not null, name text not null, active boolean default true, created_at timestamptz default now(), unique(tenant_id,code)
);
create table if not exists unimis.hr_job_grades (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.tenants(id) on delete cascade,
 code text not null, name text not null, min_salary numeric(14,2), max_salary numeric(14,2), created_at timestamptz default now(), unique(tenant_id,code)
);
create table if not exists unimis.hr_positions (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.tenants(id) on delete cascade,
 department_id uuid references unimis.departments(id) on delete set null, grade_id uuid references unimis.hr_job_grades(id) on delete set null,
 code text not null, title text not null, active boolean default true, created_at timestamptz default now(), unique(tenant_id,code)
);
create table if not exists unimis.hr_employees (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.tenants(id) on delete cascade,
 employee_no text not null, first_name text not null, last_name text not null, other_names text, email text, phone text,
 branch_id uuid references unimis.branches(id) on delete set null, department_id uuid references unimis.departments(id) on delete set null,
 position_id uuid references unimis.hr_positions(id) on delete set null, hire_date date, employment_status text not null default 'active',
 created_at timestamptz default now(), unique(tenant_id,employee_no)
);
create table if not exists unimis.hr_employment_contracts (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.tenants(id) on delete cascade,
 employee_id uuid not null references unimis.hr_employees(id) on delete cascade, contract_type text not null default 'permanent', start_date date not null,
 end_date date, basic_salary numeric(14,2) not null default 0, pay_frequency text not null default 'monthly', status text not null default 'active', created_at timestamptz default now()
);

create table if not exists unimis.payroll_pay_groups (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.tenants(id) on delete cascade,
 code text not null, name text not null, frequency text not null default 'monthly', active boolean default true, created_at timestamptz default now(), unique(tenant_id,code)
);
create table if not exists unimis.payroll_profiles (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.tenants(id) on delete cascade,
 employee_id uuid not null references unimis.hr_employees(id) on delete cascade, pay_group_id uuid references unimis.payroll_pay_groups(id) on delete set null,
 tax_number text, ssnit_number text, bank_name text, bank_account_name text, bank_account_number text,
 payment_method text not null default 'bank', active boolean default true, created_at timestamptz default now(), unique(tenant_id,employee_id)
);
create table if not exists unimis.payroll_components (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.tenants(id) on delete cascade,
 code text not null, name text not null, component_type text not null check(component_type in ('earning','deduction','employer_contribution')),
 taxable boolean not null default false, pensionable boolean not null default false, calculation_type text not null default 'fixed', default_amount numeric(14,2) default 0,
 active boolean default true, created_at timestamptz default now(), unique(tenant_id,code)
);
create table if not exists unimis.payroll_employee_components (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.tenants(id) on delete cascade,
 employee_id uuid not null references unimis.hr_employees(id) on delete cascade, component_id uuid not null references unimis.payroll_components(id) on delete cascade,
 amount numeric(14,2) not null default 0, effective_from date not null default current_date, effective_to date, unique(employee_id,component_id,effective_from)
);
create table if not exists unimis.payroll_periods (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.tenants(id) on delete cascade,
 pay_group_id uuid references unimis.payroll_pay_groups(id) on delete set null, name text not null, start_date date not null, end_date date not null, pay_date date not null,
 status text not null default 'open' check(status in ('open','processing','review','approved','posted','closed')), created_at timestamptz default now()
);
create table if not exists unimis.payroll_statutory_rules (
 id uuid primary key default gen_random_uuid(), tenant_id uuid references unimis.tenants(id) on delete cascade,
 country_code text not null, authority text not null, rule_type text not null, name text not null, effective_from date not null, effective_to date,
 calculation_method text not null default 'configuration', configuration jsonb not null default '{}'::jsonb, active boolean default true, created_at timestamptz default now()
);
create table if not exists unimis.approval_requests (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.tenants(id) on delete cascade,
 module text not null, record_type text not null, record_id uuid, requested_by uuid references auth.users(id), status text not null default 'pending', notes text, created_at timestamptz default now(), decided_at timestamptz
);
create table if not exists unimis.audit_events (
 id bigint generated always as identity primary key, tenant_id uuid references unimis.tenants(id) on delete cascade,
 actor_id uuid references auth.users(id), module text not null, action text not null, record_type text, record_id uuid, details jsonb default '{}'::jsonb, created_at timestamptz default now()
);

create index if not exists idx_membership_user on unimis.tenant_memberships(user_id,tenant_id);
create index if not exists idx_employee_tenant on unimis.hr_employees(tenant_id);
create index if not exists idx_payroll_profile_tenant on unimis.payroll_profiles(tenant_id);

create or replace function unimis.create_organization(p_name text, p_code text)
returns uuid language plpgsql security definer set search_path=unimis as $$
declare v_tenant uuid; v_entity uuid;
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 insert into unimis.tenants(name,code,created_by) values(trim(p_name),upper(trim(p_code)),auth.uid()) returning id into v_tenant;
 insert into unimis.tenant_memberships(tenant_id,user_id,role) values(v_tenant,auth.uid(),'owner');
 insert into unimis.legal_entities(tenant_id,name) values(v_tenant,trim(p_name)) returning id into v_entity;
 insert into unimis.branches(tenant_id,legal_entity_id,code,name) values(v_tenant,v_entity,'HQ','Head Office');
 insert into unimis.payroll_pay_groups(tenant_id,code,name,frequency) values(v_tenant,'MONTHLY','Monthly Payroll','monthly');
 insert into unimis.payroll_components(tenant_id,code,name,component_type,taxable,pensionable) values
   (v_tenant,'BASIC','Basic Salary','earning',true,true),
   (v_tenant,'OVERTIME','Overtime','earning',true,true),
   (v_tenant,'BONUS','Bonus','earning',true,false),
   (v_tenant,'OTHERDED','Other Deduction','deduction',false,false);
 insert into unimis.audit_events(tenant_id,actor_id,module,action,record_type,record_id) values(v_tenant,auth.uid(),'core','organization.created','tenant',v_tenant);
 return v_tenant;
end $$;
grant execute on function unimis.create_organization(text,text) to authenticated;

create or replace function unimis.handle_new_user() returns trigger language plpgsql security definer set search_path=unimis as $$
begin insert into unimis.profiles(id,full_name) values(new.id,coalesce(new.raw_user_meta_data->>'full_name',split_part(new.email,'@',1))) on conflict(id) do nothing; return new; end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function unimis.handle_new_user();

alter table unimis.profiles enable row level security;
alter table unimis.tenants enable row level security;
alter table unimis.tenant_memberships enable row level security;
alter table unimis.legal_entities enable row level security;
alter table unimis.branches enable row level security;
alter table unimis.departments enable row level security;
alter table unimis.hr_job_grades enable row level security;
alter table unimis.hr_positions enable row level security;
alter table unimis.hr_employees enable row level security;
alter table unimis.hr_employment_contracts enable row level security;
alter table unimis.payroll_pay_groups enable row level security;
alter table unimis.payroll_profiles enable row level security;
alter table unimis.payroll_components enable row level security;
alter table unimis.payroll_employee_components enable row level security;
alter table unimis.payroll_periods enable row level security;
alter table unimis.payroll_statutory_rules enable row level security;
alter table unimis.approval_requests enable row level security;
alter table unimis.audit_events enable row level security;

create policy "profile self read" on unimis.profiles for select using(id=auth.uid());
create policy "profile self update" on unimis.profiles for update using(id=auth.uid()) with check(id=auth.uid());
create policy "tenant member read" on unimis.tenants for select using(unimis.is_tenant_member(id));
create policy "membership member read" on unimis.tenant_memberships for select using(unimis.is_tenant_member(tenant_id));

-- Tenant-scoped tables: members read; operational managers write. Owner/admin retain full control.
do $$ declare t text; begin
 foreach t in array array['legal_entities','branches','departments','hr_job_grades','hr_positions','hr_employees','hr_employment_contracts','payroll_pay_groups','payroll_profiles','payroll_components','payroll_employee_components','payroll_periods','approval_requests'] loop
   execute format('create policy %I on unimis.%I for select using (unimis.is_tenant_member(tenant_id))', t||'_read', t);
   execute format('create policy %I on unimis.%I for insert with check (unimis.has_tenant_role(tenant_id, ARRAY[''owner'',''administrator'',''hr_manager'',''hr_officer'',''payroll_manager'',''payroll_officer'',''finance_manager'']))', t||'_insert', t);
   execute format('create policy %I on unimis.%I for update using (unimis.has_tenant_role(tenant_id, ARRAY[''owner'',''administrator'',''hr_manager'',''hr_officer'',''payroll_manager'',''payroll_officer'',''finance_manager''])) with check (unimis.has_tenant_role(tenant_id, ARRAY[''owner'',''administrator'',''hr_manager'',''hr_officer'',''payroll_manager'',''payroll_officer'',''finance_manager'']))', t||'_update', t);
   execute format('create policy %I on unimis.%I for delete using (unimis.has_tenant_role(tenant_id, ARRAY[''owner'',''administrator'']))', t||'_delete', t);
 end loop;
end $$;
create policy "statutory authenticated read" on unimis.payroll_statutory_rules for select using(tenant_id is null or unimis.is_tenant_member(tenant_id));
create policy "statutory manager write" on unimis.payroll_statutory_rules for all using(tenant_id is not null and unimis.has_tenant_role(tenant_id,array['owner','administrator','payroll_manager'])) with check(tenant_id is not null and unimis.has_tenant_role(tenant_id,array['owner','administrator','payroll_manager']));
create policy "audit member read" on unimis.audit_events for select using(unimis.is_tenant_member(tenant_id));
create policy "audit authenticated insert" on unimis.audit_events for insert with check(unimis.is_tenant_member(tenant_id) and actor_id=auth.uid());

insert into unimis.payroll_statutory_rules(tenant_id,country_code,authority,rule_type,name,effective_from,calculation_method,configuration)
select null,'GH','GRA','PAYE','Ghana PAYE - configure current statutory bands',date '2026-01-01','bands',jsonb_build_object('status','configuration_required','note','Verify current GRA bands before production payroll')
where not exists(select 1 from unimis.payroll_statutory_rules where tenant_id is null and country_code='GH' and rule_type='PAYE' and effective_from=date '2026-01-01');
insert into unimis.payroll_statutory_rules(tenant_id,country_code,authority,rule_type,name,effective_from,calculation_method,configuration)
select null,'GH','SSNIT','PENSION','Ghana SSNIT - configure current contribution rates',date '2026-01-01','percentage',jsonb_build_object('status','configuration_required','note','Verify current SSNIT rates and allocation before production payroll')
where not exists(select 1 from unimis.payroll_statutory_rules where tenant_id is null and country_code='GH' and rule_type='PENSION' and effective_from=date '2026-01-01');


-- SOURCE 202610140002_hr_payroll_operational_core.sql
-- HRPayrollCore Package 002: operational HR + payroll core
-- Preserves all Package 001 data.

create table if not exists unimis.payroll_settings (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null unique references unimis.tenants(id) on delete cascade,
 country_code text not null default 'GH',
 currency text not null default 'GHS',
 employee_pension_rate numeric(8,5) not null default 0,
 employer_pension_rate numeric(8,5) not null default 0,
 paye_enabled boolean not null default false,
 statutory_note text not null default 'Configure and verify current statutory rates before production payroll.',
 updated_at timestamptz not null default now()
);

create table if not exists unimis.payroll_runs (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references unimis.tenants(id) on delete cascade,
 period_id uuid not null references unimis.payroll_periods(id) on delete restrict,
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

create table if not exists unimis.payroll_run_employees (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.tenants(id) on delete cascade,
 run_id uuid not null references unimis.payroll_runs(id) on delete cascade,
 employee_id uuid not null references unimis.hr_employees(id) on delete restrict,
 employee_no text not null, employee_name text not null,
 basic_salary numeric(14,2) not null default 0, other_earnings numeric(14,2) not null default 0,
 gross_pay numeric(14,2) not null default 0, employee_pension numeric(14,2) not null default 0,
 employer_pension numeric(14,2) not null default 0, tax numeric(14,2) not null default 0,
 other_deductions numeric(14,2) not null default 0, net_pay numeric(14,2) not null default 0,
 created_at timestamptz not null default now(), unique(run_id,employee_id)
);

create table if not exists unimis.payroll_run_items (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.tenants(id) on delete cascade,
 run_employee_id uuid not null references unimis.payroll_run_employees(id) on delete cascade,
 component_code text not null, component_name text not null, component_type text not null,
 amount numeric(14,2) not null default 0, taxable boolean not null default false, pensionable boolean not null default false
);

create table if not exists unimis.payroll_payslips (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.tenants(id) on delete cascade,
 run_id uuid not null references unimis.payroll_runs(id) on delete cascade,
 run_employee_id uuid not null references unimis.payroll_run_employees(id) on delete cascade,
 employee_id uuid not null references unimis.hr_employees(id) on delete restrict,
 payslip_no text not null, issued_at timestamptz not null default now(), unique(tenant_id,payslip_no), unique(run_employee_id)
);

create table if not exists unimis.payroll_payment_batches (
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.tenants(id) on delete cascade,
 run_id uuid not null references unimis.payroll_runs(id) on delete restrict,
 batch_no text not null, payment_method text not null default 'bank', amount numeric(14,2) not null default 0,
 status text not null default 'draft' check(status in ('draft','ready','paid','cancelled')),
 created_by uuid references auth.users(id), created_at timestamptz not null default now(), paid_at timestamptz,
 unique(tenant_id,batch_no)
);

create index if not exists idx_payroll_runs_tenant on unimis.payroll_runs(tenant_id,created_at desc);
create index if not exists idx_run_employees_run on unimis.payroll_run_employees(run_id);
create index if not exists idx_payslips_employee on unimis.payroll_payslips(employee_id,issued_at desc);

alter table unimis.payroll_settings enable row level security;
alter table unimis.payroll_runs enable row level security;
alter table unimis.payroll_run_employees enable row level security;
alter table unimis.payroll_run_items enable row level security;
alter table unimis.payroll_payslips enable row level security;
alter table unimis.payroll_payment_batches enable row level security;

do $$ declare t text; begin
 foreach t in array array['payroll_settings','payroll_runs','payroll_run_employees','payroll_run_items','payroll_payslips','payroll_payment_batches'] loop
   execute format('create policy %I on unimis.%I for select using (unimis.is_tenant_member(tenant_id))', t||'_read_002', t);
 end loop;
end $$;
create policy "payroll settings managers" on unimis.payroll_settings for all
 using(unimis.has_tenant_role(tenant_id,array['owner','administrator','payroll_manager']))
 with check(unimis.has_tenant_role(tenant_id,array['owner','administrator','payroll_manager']));
create policy "payroll runs managers" on unimis.payroll_runs for all
 using(unimis.has_tenant_role(tenant_id,array['owner','administrator','payroll_manager','payroll_officer','finance_manager']))
 with check(unimis.has_tenant_role(tenant_id,array['owner','administrator','payroll_manager','payroll_officer','finance_manager']));
create policy "run employees managers" on unimis.payroll_run_employees for all
 using(unimis.has_tenant_role(tenant_id,array['owner','administrator','payroll_manager','payroll_officer','finance_manager']))
 with check(unimis.has_tenant_role(tenant_id,array['owner','administrator','payroll_manager','payroll_officer','finance_manager']));
create policy "run items managers" on unimis.payroll_run_items for all
 using(unimis.has_tenant_role(tenant_id,array['owner','administrator','payroll_manager','payroll_officer','finance_manager']))
 with check(unimis.has_tenant_role(tenant_id,array['owner','administrator','payroll_manager','payroll_officer','finance_manager']));
create policy "payslip managers" on unimis.payroll_payslips for all
 using(unimis.has_tenant_role(tenant_id,array['owner','administrator','payroll_manager','payroll_officer','finance_manager']))
 with check(unimis.has_tenant_role(tenant_id,array['owner','administrator','payroll_manager','payroll_officer','finance_manager']));
create policy "payment batch managers" on unimis.payroll_payment_batches for all
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
 insert into unimis.hr_employees(tenant_id,employee_no,first_name,last_name,email,department_id,position_id,hire_date)
 values(p_tenant,upper(trim(p_employee_no)),trim(p_first_name),trim(p_last_name),nullif(trim(p_email),''),p_department,p_position,p_hire_date)
 returning id into e;
 insert into unimis.hr_employment_contracts(tenant_id,employee_id,start_date,basic_salary)
 values(p_tenant,e,coalesce(p_hire_date,current_date),coalesce(p_basic_salary,0));
 select id into g from unimis.payroll_pay_groups where tenant_id=p_tenant and active order by created_at limit 1;
 insert into unimis.payroll_profiles(tenant_id,employee_id,pay_group_id) values(p_tenant,e,g);
 insert into unimis.audit_events(tenant_id,actor_id,module,action,record_type,record_id)
 values(p_tenant,auth.uid(),'hr','employee.created','employee',e);
 return e;
end $$;
grant execute on function unimis.hr_create_employee(uuid,text,text,text,text,uuid,uuid,date,numeric) to authenticated;

-- Calculate a payroll run. Statutory percentages are tenant-configurable and default to zero until verified.
create or replace function unimis.payroll_calculate_run(p_tenant uuid,p_period uuid)
returns uuid language plpgsql security definer set search_path=unimis as $$
declare r uuid; rn text; s unimis.payroll_settings%rowtype; rec record; re uuid;
        basic numeric; earn numeric; ded numeric; gross numeric; ep numeric; erp numeric; tx numeric; net numeric;
begin
 if not unimis.has_tenant_role(p_tenant,array['owner','administrator','payroll_manager','payroll_officer']) then raise exception 'Payroll access denied'; end if;
 if not exists(select 1 from unimis.payroll_periods where id=p_period and tenant_id=p_tenant) then raise exception 'Invalid payroll period'; end if;
 insert into unimis.payroll_settings(tenant_id) values(p_tenant) on conflict(tenant_id) do nothing;
 select * into s from unimis.payroll_settings where tenant_id=p_tenant;
 select id into r from unimis.payroll_runs where tenant_id=p_tenant and period_id=p_period;
 if r is null then
   rn:='RUN-'||to_char(current_date,'YYYYMM')||'-'||lpad((1+(select count(*) from unimis.payroll_runs where tenant_id=p_tenant))::text,3,'0');
   insert into unimis.payroll_runs(tenant_id,period_id,run_no,status,created_by) values(p_tenant,p_period,rn,'draft',auth.uid()) returning id into r;
 else
   if exists(select 1 from unimis.payroll_runs where id=r and status in ('approved','posted')) then raise exception 'Approved/posted payroll cannot be recalculated'; end if;
   delete from unimis.payroll_run_employees where run_id=r; update unimis.payroll_runs set status='draft' where id=r;
 end if;
 for rec in select e.* from unimis.hr_employees e join unimis.payroll_profiles pp on pp.employee_id=e.id and pp.active
            where e.tenant_id=p_tenant and e.employment_status='active' loop
   select coalesce(c.basic_salary,0) into basic from unimis.hr_employment_contracts c where c.employee_id=rec.id and c.status='active' order by c.start_date desc limit 1;
   select coalesce(sum(pec.amount) filter (where pc.component_type='earning'),0), coalesce(sum(pec.amount) filter (where pc.component_type='deduction'),0)
     into earn,ded from unimis.payroll_employee_components pec join unimis.payroll_components pc on pc.id=pec.component_id
     where pec.employee_id=rec.id and pec.tenant_id=p_tenant and pec.effective_from <= current_date and (pec.effective_to is null or pec.effective_to>=current_date) and pc.code<>'BASIC';
   earn:=coalesce(earn,0); ded:=coalesce(ded,0); gross:=basic+earn;
   ep:=round(gross*s.employee_pension_rate/100,2); erp:=round(gross*s.employer_pension_rate/100,2);
   tx:=0; -- PAYE engine remains disabled until verified statutory bands are configured.
   net:=gross-ep-tx-ded;
   insert into unimis.payroll_run_employees(tenant_id,run_id,employee_id,employee_no,employee_name,basic_salary,other_earnings,gross_pay,employee_pension,employer_pension,tax,other_deductions,net_pay)
   values(p_tenant,r,rec.id,rec.employee_no,concat_ws(' ',rec.first_name,rec.other_names,rec.last_name),basic,earn,gross,ep,erp,tx,ded,net) returning id into re;
   insert into unimis.payroll_run_items(tenant_id,run_employee_id,component_code,component_name,component_type,amount,taxable,pensionable)
   values(p_tenant,re,'BASIC','Basic Salary','earning',basic,true,true);
   insert into unimis.payroll_run_items(tenant_id,run_employee_id,component_code,component_name,component_type,amount,taxable,pensionable)
   select p_tenant,re,pc.code,pc.name,pc.component_type,pec.amount,pc.taxable,pc.pensionable
   from unimis.payroll_employee_components pec join unimis.payroll_components pc on pc.id=pec.component_id
   where pec.employee_id=rec.id and pec.tenant_id=p_tenant and pc.code<>'BASIC' and pec.effective_from<=current_date and (pec.effective_to is null or pec.effective_to>=current_date);
 end loop;
 update unimis.payroll_runs pr set status='calculated', employee_count=x.cnt,gross_total=x.gross,deduction_total=x.ded,
 employee_pension_total=x.ep,employer_pension_total=x.erp,tax_total=x.tax,net_total=x.net
 from (select count(*) cnt,coalesce(sum(gross_pay),0) gross,coalesce(sum(other_deductions),0) ded,coalesce(sum(employee_pension),0) ep,
 coalesce(sum(employer_pension),0) erp,coalesce(sum(tax),0) tax,coalesce(sum(net_pay),0) net from unimis.payroll_run_employees where run_id=r) x where pr.id=r;
 update unimis.payroll_periods set status='review' where id=p_period;
 insert into unimis.audit_events(tenant_id,actor_id,module,action,record_type,record_id) values(p_tenant,auth.uid(),'payroll','run.calculated','payroll_run',r);
 return r;
end $$;
grant execute on function unimis.payroll_calculate_run(uuid,uuid) to authenticated;

create or replace function unimis.payroll_approve_run(p_tenant uuid,p_run uuid)
returns void language plpgsql security definer set search_path=unimis as $$
begin
 if not unimis.has_tenant_role(p_tenant,array['owner','administrator','payroll_manager','approver']) then raise exception 'Approval access denied'; end if;
 update unimis.payroll_runs set status='approved',approved_by=auth.uid(),approved_at=now() where id=p_run and tenant_id=p_tenant and status in ('calculated','review');
 if not found then raise exception 'Payroll run is not ready for approval'; end if;
 update unimis.payroll_periods set status='approved' where id=(select period_id from unimis.payroll_runs where id=p_run);
 insert into unimis.audit_events(tenant_id,actor_id,module,action,record_type,record_id) values(p_tenant,auth.uid(),'payroll','run.approved','payroll_run',p_run);
end $$;
grant execute on function unimis.payroll_approve_run(uuid,uuid) to authenticated;

create or replace function unimis.payroll_post_run(p_tenant uuid,p_run uuid)
returns void language plpgsql security definer set search_path=unimis as $$
declare rr record; n integer:=0;
begin
 if not unimis.has_tenant_role(p_tenant,array['owner','administrator','payroll_manager','finance_manager']) then raise exception 'Posting access denied'; end if;
 if not exists(select 1 from unimis.payroll_runs where id=p_run and tenant_id=p_tenant and status='approved') then raise exception 'Only approved payroll can be posted'; end if;
 for rr in select * from unimis.payroll_run_employees where run_id=p_run loop
   n:=n+1;
   insert into unimis.payroll_payslips(tenant_id,run_id,run_employee_id,employee_id,payslip_no)
   values(p_tenant,p_run,rr.id,rr.employee_id,'PS-'||to_char(current_date,'YYYYMM')||'-'||lpad(n::text,4,'0')) on conflict(run_employee_id) do nothing;
 end loop;
 update unimis.payroll_runs set status='posted',posted_by=auth.uid(),posted_at=now() where id=p_run;
 update unimis.payroll_periods set status='posted' where id=(select period_id from unimis.payroll_runs where id=p_run);
 insert into unimis.payroll_payment_batches(tenant_id,run_id,batch_no,amount,created_by)
 select p_tenant,p_run,'PB-'||to_char(current_date,'YYYYMMDD')||'-'||substr(p_run::text,1,6),net_total,auth.uid() from unimis.payroll_runs where id=p_run
 on conflict(tenant_id,batch_no) do nothing;
 insert into unimis.audit_events(tenant_id,actor_id,module,action,record_type,record_id) values(p_tenant,auth.uid(),'payroll','run.posted','payroll_run',p_run);
end $$;
grant execute on function unimis.payroll_post_run(uuid,uuid) to authenticated;

-- Optional demo data for testing. It never runs automatically.
create or replace function unimis.seed_hrpayroll_demo(p_tenant uuid)
returns void language plpgsql security definer set search_path=unimis as $$
declare b uuid; d1 uuid; d2 uuid; g1 uuid; p1 uuid; p2 uuid; pg uuid; e uuid; i int;
begin
 if not unimis.has_tenant_role(p_tenant,array['owner','administrator']) then raise exception 'Owner/admin required'; end if;
 select id into b from unimis.branches where tenant_id=p_tenant order by created_at limit 1;
 insert into unimis.departments(tenant_id,branch_id,code,name) values(p_tenant,b,'ADM','Administration') on conflict(tenant_id,code) do update set name=excluded.name returning id into d1;
 insert into unimis.departments(tenant_id,branch_id,code,name) values(p_tenant,b,'FIN','Finance') on conflict(tenant_id,code) do update set name=excluded.name returning id into d2;
 insert into unimis.hr_job_grades(tenant_id,code,name,min_salary,max_salary) values(p_tenant,'G1','Officer',2500,6000) on conflict(tenant_id,code) do update set name=excluded.name returning id into g1;
 insert into unimis.hr_positions(tenant_id,department_id,grade_id,code,title) values(p_tenant,d1,g1,'ADMIN-OFF','Administrative Officer') on conflict(tenant_id,code) do update set title=excluded.title returning id into p1;
 insert into unimis.hr_positions(tenant_id,department_id,grade_id,code,title) values(p_tenant,d2,g1,'ACCT-OFF','Accounts Officer') on conflict(tenant_id,code) do update set title=excluded.title returning id into p2;
 select id into pg from unimis.payroll_pay_groups where tenant_id=p_tenant order by created_at limit 1;
 if not exists(select 1 from unimis.hr_employees where tenant_id=p_tenant and employee_no='EMP001') then
  insert into unimis.hr_employees(tenant_id,employee_no,first_name,last_name,email,branch_id,department_id,position_id,hire_date) values(p_tenant,'EMP001','Ama','Mensah','ama.mensah@example.test',b,d1,p1,current_date-500) returning id into e;
  insert into unimis.hr_employment_contracts(tenant_id,employee_id,start_date,basic_salary) values(p_tenant,e,current_date-500,4200);
  insert into unimis.payroll_profiles(tenant_id,employee_id,pay_group_id,bank_name,payment_method) values(p_tenant,e,pg,'Demo Bank','bank');
 end if;
 if not exists(select 1 from unimis.hr_employees where tenant_id=p_tenant and employee_no='EMP002') then
  insert into unimis.hr_employees(tenant_id,employee_no,first_name,last_name,email,branch_id,department_id,position_id,hire_date) values(p_tenant,'EMP002','Kwame','Asare','kwame.asare@example.test',b,d2,p2,current_date-420) returning id into e;
  insert into unimis.hr_employment_contracts(tenant_id,employee_id,start_date,basic_salary) values(p_tenant,e,current_date-420,5000);
  insert into unimis.payroll_profiles(tenant_id,employee_id,pay_group_id,bank_name,payment_method) values(p_tenant,e,pg,'Demo Bank','bank');
 end if;
 if not exists(select 1 from unimis.payroll_periods where tenant_id=p_tenant and name=to_char(current_date,'FMMonth YYYY')) then
  insert into unimis.payroll_periods(tenant_id,pay_group_id,name,start_date,end_date,pay_date)
  values(p_tenant,pg,to_char(current_date,'FMMonth YYYY'),date_trunc('month',current_date)::date,(date_trunc('month',current_date)+interval '1 month - 1 day')::date,(date_trunc('month',current_date)+interval '1 month - 1 day')::date);
 end if;
 insert into unimis.payroll_settings(tenant_id) values(p_tenant) on conflict(tenant_id) do nothing;
 insert into unimis.audit_events(tenant_id,actor_id,module,action,record_type,record_id,details) values(p_tenant,auth.uid(),'core','demo.seeded','tenant',p_tenant,jsonb_build_object('package','002'));
end $$;
grant execute on function unimis.seed_hrpayroll_demo(uuid) to authenticated;

notify pgrst, 'reload schema';


-- SOURCE 202610140003_employee_dob_ui.sql
-- Package 002b: employee DOB foundation for age-aware payroll/statutory processing.
alter table unimis.hr_employees add column if not exists date_of_birth date;

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
 insert into unimis.hr_employees(tenant_id,employee_no,first_name,last_name,email,department_id,position_id,date_of_birth,hire_date)
 values(p_tenant,upper(trim(p_employee_no)),trim(p_first_name),trim(p_last_name),nullif(trim(p_email),''),p_department,p_position,p_date_of_birth,p_hire_date)
 returning id into e;
 insert into unimis.hr_employment_contracts(tenant_id,employee_id,start_date,basic_salary)
 values(p_tenant,e,coalesce(p_hire_date,current_date),coalesce(p_basic_salary,0));
 select id into g from unimis.payroll_pay_groups where tenant_id=p_tenant and active order by created_at limit 1;
 insert into unimis.payroll_profiles(tenant_id,employee_id,pay_group_id) values(p_tenant,e,g);
 insert into unimis.audit_events(tenant_id,actor_id,module,action,record_type,record_id)
 values(p_tenant,auth.uid(),'hr','employee.created','employee',e);
 return e;
end $$;
grant execute on function unimis.hr_create_employee(uuid,text,text,text,text,uuid,uuid,date,date,numeric) to authenticated;

comment on column unimis.hr_employees.date_of_birth is 'Employee date of birth; supports age-aware statutory eligibility, retirement/pension handling, birthday workflows and HR reporting.';


-- SOURCE 202610140004_employee_master_compensation.sql
-- Package 002c: Employee Master + employment classification + compensation history + private photos.
alter table unimis.hr_employees
  add column if not exists photo_path text,
  add column if not exists employment_type text not null default 'regular',
  add column if not exists work_schedule text not null default 'full_time',
  add column if not exists pension_status text not null default 'applicable';

alter table unimis.hr_employment_contracts
  add column if not exists pay_basis text not null default 'monthly',
  add column if not exists daily_rate numeric(14,2) not null default 0,
  add column if not exists hourly_rate numeric(14,2) not null default 0,
  add column if not exists probation_end_date date,
  add column if not exists notice_days integer not null default 30;

create table if not exists unimis.hr_salary_history (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references unimis.tenants(id) on delete cascade,
 employee_id uuid not null references unimis.hr_employees(id) on delete cascade,
 old_salary numeric(14,2), new_salary numeric(14,2) not null,
 change_type text not null default 'initial' check(change_type in ('initial','manual','grade_step','promotion','bulk_adjustment','correction')),
 reason text, effective_from date not null, approved_by uuid references auth.users(id), created_by uuid references auth.users(id), created_at timestamptz default now()
);
create index if not exists hr_salary_history_employee_idx on unimis.hr_salary_history(employee_id,effective_from desc);
alter table unimis.hr_salary_history enable row level security;
drop policy if exists hr_salary_history_tenant on unimis.hr_salary_history;
create policy hr_salary_history_tenant on unimis.hr_salary_history for all to authenticated using(unimis.is_tenant_member(tenant_id)) with check(unimis.is_tenant_member(tenant_id));

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
 insert into unimis.hr_employees(tenant_id,employee_no,first_name,last_name,email,department_id,position_id,date_of_birth,hire_date,employment_type,work_schedule,pension_status)
 values(p_tenant,upper(trim(p_employee_no)),trim(p_first_name),trim(p_last_name),nullif(trim(p_email),''),p_department,p_position,p_date_of_birth,p_hire_date,p_employment_type,p_work_schedule,p_pension_status)
 returning id into e;
 insert into unimis.hr_employment_contracts(tenant_id,employee_id,contract_type,start_date,end_date,basic_salary,pay_frequency,pay_basis)
 values(p_tenant,e,p_employment_type,coalesce(p_hire_date,current_date),p_contract_end,coalesce(p_basic_salary,0),p_pay_basis,p_pay_basis);
 insert into unimis.hr_salary_history(tenant_id,employee_id,new_salary,change_type,reason,effective_from,created_by)
 values(p_tenant,e,coalesce(p_basic_salary,0),'initial','Initial appointment',coalesce(p_hire_date,current_date),auth.uid());
 select id into g from unimis.payroll_pay_groups where tenant_id=p_tenant and active order by created_at limit 1;
 insert into unimis.payroll_profiles(tenant_id,employee_id,pay_group_id) values(p_tenant,e,g);
 insert into unimis.audit_events(tenant_id,actor_id,module,action,record_type,record_id,details)
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
 select id,basic_salary into c,oldv from unimis.hr_employment_contracts where tenant_id=p_tenant and employee_id=p_employee and status='active' order by start_date desc limit 1;
 if c is null then raise exception 'Active contract not found'; end if;
 update unimis.hr_employment_contracts set basic_salary=p_new_salary where id=c;
 insert into unimis.hr_salary_history(tenant_id,employee_id,old_salary,new_salary,change_type,reason,effective_from,approved_by,created_by)
 values(p_tenant,p_employee,oldv,p_new_salary,p_change_type,p_reason,coalesce(p_effective,current_date),auth.uid(),auth.uid()) returning id into h;
 return h;
end $$;
grant execute on function unimis.hr_change_salary(uuid,uuid,numeric,date,text,text) to authenticated;


-- SOURCE 202610140005_employee_master_full_profile.sql
-- Package 002d: Full HR Employee Master.
alter table unimis.hr_employees
 add column if not exists gender text,
 add column if not exists marital_status text,
 add column if not exists nationality text default 'Ghanaian',
 add column if not exists national_id text,
 add column if not exists residential_address text,
 add column if not exists postal_address text,
 add column if not exists supervisor_id uuid references unimis.hr_employees(id) on delete set null;

alter table unimis.payroll_profiles
 add column if not exists bank_branch text,
 add column if not exists momo_number text,
 add column if not exists momo_network text;

create table if not exists unimis.hr_employee_qualifications(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.tenants(id) on delete cascade,
 employee_id uuid not null references unimis.hr_employees(id) on delete cascade,
 qualification_type text not null default 'academic', qualification text not null, institution text,
 field_of_study text, start_year integer, completion_year integer, certificate_no text, notes text,
 created_at timestamptz default now()
);
create table if not exists unimis.hr_employee_documents(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.tenants(id) on delete cascade,
 employee_id uuid not null references unimis.hr_employees(id) on delete cascade,
 document_type text not null, title text not null, file_path text not null, issue_date date, expiry_date date,
 notes text, uploaded_by uuid references auth.users(id), created_at timestamptz default now()
);
create table if not exists unimis.hr_emergency_contacts(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.tenants(id) on delete cascade,
 employee_id uuid not null references unimis.hr_employees(id) on delete cascade,
 full_name text not null, relationship text, phone text not null, alternate_phone text, address text,
 is_primary boolean default true, created_at timestamptz default now()
);
create table if not exists unimis.hr_employment_events(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.tenants(id) on delete cascade,
 employee_id uuid not null references unimis.hr_employees(id) on delete cascade,
 event_type text not null, effective_date date not null, title text, details jsonb default '{}'::jsonb,
 created_by uuid references auth.users(id), created_at timestamptz default now()
);

do $$ declare t text; begin
 foreach t in array array['hr_employee_qualifications','hr_employee_documents','hr_emergency_contacts','hr_employment_events'] loop
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
 insert into unimis.hr_employment_events(tenant_id,employee_id,event_type,effective_date,title,details,created_by)
 values(p_tenant,p_employee,p_type,coalesce(p_effective,current_date),p_title,coalesce(p_details,'{}'::jsonb),auth.uid()) returning id into x;
 return x; end $$;
grant execute on function unimis.hr_record_employment_event(uuid,uuid,text,date,text,jsonb) to authenticated;

notify pgrst, 'reload schema';


-- SOURCE 202610140006_recruitment_onboarding.sql
-- Package 003: Recruitment + onboarding feeding the HR Employee Master.
create table if not exists unimis.hr_vacancies(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.tenants(id) on delete cascade,
 title text not null, department_id uuid references unimis.departments(id) on delete set null,
 position_id uuid references unimis.hr_positions(id) on delete set null, openings integer not null default 1 check(openings>0),
 employment_type text not null default 'regular', description text, requirements text, closing_date date,
 status text not null default 'draft' check(status in ('draft','open','closed','cancelled')),
 created_by uuid references auth.users(id), created_at timestamptz not null default now()
);
create table if not exists unimis.hr_applicants(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.tenants(id) on delete cascade,
 vacancy_id uuid references unimis.hr_vacancies(id) on delete set null, first_name text not null, last_name text not null,
 email text, phone text, date_of_birth date, source text, cv_path text,
 status text not null default 'applied' check(status in ('applied','shortlisted','interviewed','rejected','offered','offer_accepted','offer_declined','hired')),
 employee_id uuid references unimis.hr_employees(id) on delete set null, notes text,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists unimis.hr_interviews(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.tenants(id) on delete cascade,
 applicant_id uuid not null references unimis.hr_applicants(id) on delete cascade, interview_at timestamptz,
 interview_type text default 'in_person', panel_notes text, score numeric(5,2), recommendation text,
 created_by uuid references auth.users(id), created_at timestamptz default now()
);
create table if not exists unimis.hr_offers(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.tenants(id) on delete cascade,
 applicant_id uuid not null references unimis.hr_applicants(id) on delete cascade, offered_salary numeric(14,2) default 0,
 proposed_start_date date, employment_type text default 'regular', status text default 'draft' check(status in ('draft','issued','accepted','declined','withdrawn')),
 issued_at timestamptz, responded_at timestamptz, created_by uuid references auth.users(id), created_at timestamptz default now()
);

do $$ declare t text; begin
 foreach t in array array['hr_vacancies','hr_applicants','hr_interviews','hr_offers'] loop
  execute format('alter table unimis.%I enable row level security',t);
  execute format('create policy %I on unimis.%I for select using(unimis.is_tenant_member(tenant_id))',t||'_read',t);
  execute format('create policy %I on unimis.%I for insert with check(unimis.has_tenant_role(tenant_id,array[''owner'',''administrator'',''hr_manager'',''hr_officer'']))',t||'_insert',t);
  execute format('create policy %I on unimis.%I for update using(unimis.has_tenant_role(tenant_id,array[''owner'',''administrator'',''hr_manager'',''hr_officer''])) with check(unimis.has_tenant_role(tenant_id,array[''owner'',''administrator'',''hr_manager'',''hr_officer'']))',t||'_update',t);
  execute format('create policy %I on unimis.%I for delete using(unimis.has_tenant_role(tenant_id,array[''owner'',''administrator'',''hr_manager'']))',t||'_delete',t);
 end loop;
end $$;

create or replace function unimis.hr_hire_applicant(p_tenant uuid,p_applicant uuid,p_employee_no text,p_hire_date date,p_basic_salary numeric default 0)
returns uuid language plpgsql security definer set search_path=unimis as $$
declare a unimis.hr_applicants%rowtype; v unimis.hr_vacancies%rowtype; e uuid;
begin
 if not unimis.has_tenant_role(p_tenant,array['owner','administrator','hr_manager']) then raise exception 'Hiring access denied'; end if;
 select * into a from unimis.hr_applicants where id=p_applicant and tenant_id=p_tenant for update;
 if a.id is null then raise exception 'Applicant not found'; end if;
 if a.status <> 'offer_accepted' then raise exception 'Offer must be accepted before hiring'; end if;
 if a.employee_id is not null then raise exception 'Applicant is already linked to an employee'; end if;
 if a.vacancy_id is not null then select * into v from unimis.hr_vacancies where id=a.vacancy_id and tenant_id=p_tenant; end if;
 e:=unimis.hr_create_employee(p_tenant,p_employee_no,a.first_name,a.last_name,coalesce(a.email,''),v.department_id,v.position_id,a.date_of_birth,p_hire_date,coalesce(p_basic_salary,0),coalesce(v.employment_type,'regular'),'full_time','monthly',null,'applicable');
 update unimis.hr_employees set phone=coalesce(a.phone,phone) where id=e;
 update unimis.hr_applicants set status='hired',employee_id=e,updated_at=now() where id=a.id;
 perform unimis.hr_record_employment_event(p_tenant,e,'recruitment_hire',p_hire_date,'Hired from recruitment',jsonb_build_object('applicant_id',a.id,'vacancy_id',a.vacancy_id));
 return e;
end $$;
grant execute on function unimis.hr_hire_applicant(uuid,uuid,text,date,numeric) to authenticated;

create index if not exists hr_vacancies_tenant_status_idx on unimis.hr_vacancies(tenant_id,status);
create index if not exists hr_applicants_tenant_status_idx on unimis.hr_applicants(tenant_id,status);
notify pgrst, 'reload schema';


-- SOURCE 202610140007_lean_recruitment_documents.sql
-- Package 003a: Lean recruitment funnel, progressive documents and retention-ready hiring.
-- Large applicant pools keep only light application data/CV; supporting evidence is requested only after selection.

alter table unimis.hr_applicants
  add column if not exists highest_qualification text,
  add column if not exists years_experience numeric(5,1),
  add column if not exists key_skills text,
  add column if not exists screening_score numeric(5,2),
  add column if not exists screening_notes text,
  add column if not exists selected_at timestamptz,
  add column if not exists retention_until date;

alter table unimis.hr_applicants drop constraint if exists hr_applicants_status_check;
alter table unimis.hr_applicants add constraint hr_applicants_status_check check(status in
 ('applied','shortlisted','interviewed','rejected','selected','documents_pending','documents_verified','offered','offer_accepted','offer_declined','hired','withdrawn'));

alter table unimis.hr_vacancies
  add column if not exists cv_required boolean not null default true,
  add column if not exists supporting_documents jsonb not null default '["National ID / Ghana Card","Academic certificate"]'::jsonb;

create table if not exists unimis.hr_applicant_documents(
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references unimis.tenants(id) on delete cascade,
 applicant_id uuid not null references unimis.hr_applicants(id) on delete cascade,
 document_type text not null,
 title text not null,
 file_path text not null,
 stage text not null default 'application' check(stage in ('application','selected')),
 review_status text not null default 'pending' check(review_status in ('pending','verified','rejected','clarification')),
 review_notes text,
 reviewed_by uuid references auth.users(id), reviewed_at timestamptz,
 transferred_employee_id uuid references unimis.hr_employees(id) on delete set null,
 created_at timestamptz not null default now()
);

create table if not exists unimis.hr_recruitment_settings(
 tenant_id uuid primary key references unimis.tenants(id) on delete cascade,
 unsuccessful_retention_months integer not null default 12 check(unsuccessful_retention_months between 1 and 120),
 cv_retention_months integer not null default 6 check(cv_retention_months between 1 and 120),
 require_verified_documents_before_offer boolean not null default true,
 updated_at timestamptz not null default now()
);

insert into unimis.hr_recruitment_settings(tenant_id)
select id from unimis.tenants on conflict(tenant_id) do nothing;

alter table unimis.hr_applicant_documents enable row level security;
alter table unimis.hr_recruitment_settings enable row level security;

drop policy if exists hr_applicant_documents_read on unimis.hr_applicant_documents;
create policy hr_applicant_documents_read on unimis.hr_applicant_documents for select
 using(unimis.is_tenant_member(tenant_id));
drop policy if exists hr_applicant_documents_insert on unimis.hr_applicant_documents;
create policy hr_applicant_documents_insert on unimis.hr_applicant_documents for insert
 with check(unimis.has_tenant_role(tenant_id,array['owner','administrator','hr_manager','hr_officer']));
drop policy if exists hr_applicant_documents_update on unimis.hr_applicant_documents;
create policy hr_applicant_documents_update on unimis.hr_applicant_documents for update
 using(unimis.has_tenant_role(tenant_id,array['owner','administrator','hr_manager','hr_officer']))
 with check(unimis.has_tenant_role(tenant_id,array['owner','administrator','hr_manager','hr_officer']));
drop policy if exists hr_applicant_documents_delete on unimis.hr_applicant_documents;
create policy hr_applicant_documents_delete on unimis.hr_applicant_documents for delete
 using(unimis.has_tenant_role(tenant_id,array['owner','administrator','hr_manager']));

drop policy if exists hr_recruitment_settings_read on unimis.hr_recruitment_settings;
create policy hr_recruitment_settings_read on unimis.hr_recruitment_settings for select using(unimis.is_tenant_member(tenant_id));
drop policy if exists hr_recruitment_settings_write on unimis.hr_recruitment_settings;
create policy hr_recruitment_settings_write on unimis.hr_recruitment_settings for all
 using(unimis.has_tenant_role(tenant_id,array['owner','administrator','hr_manager']))
 with check(unimis.has_tenant_role(tenant_id,array['owner','administrator','hr_manager']));

create index if not exists hr_applicant_documents_applicant_idx on unimis.hr_applicant_documents(applicant_id,stage,review_status);

-- Replace Package 003 hire RPC. No storage object is copied: verified recruitment documents are linked
-- into the employee document register using the same private employee-documents object path.
create or replace function unimis.hr_hire_applicant(p_tenant uuid,p_applicant uuid,p_employee_no text,p_hire_date date,p_basic_salary numeric default 0)
returns uuid language plpgsql security definer set search_path=unimis as $$
declare a unimis.hr_applicants%rowtype; v unimis.hr_vacancies%rowtype; e uuid;
begin
 if not unimis.has_tenant_role(p_tenant,array['owner','administrator','hr_manager']) then raise exception 'Hiring access denied'; end if;
 select * into a from unimis.hr_applicants where id=p_applicant and tenant_id=p_tenant for update;
 if a.id is null then raise exception 'Applicant not found'; end if;
 if a.status <> 'offer_accepted' then raise exception 'Offer must be accepted before hiring'; end if;
 if a.employee_id is not null then raise exception 'Applicant is already linked to an employee'; end if;
 if a.vacancy_id is not null then select * into v from unimis.hr_vacancies where id=a.vacancy_id and tenant_id=p_tenant; end if;
 e:=unimis.hr_create_employee(p_tenant,p_employee_no,a.first_name,a.last_name,coalesce(a.email,''),v.department_id,v.position_id,a.date_of_birth,p_hire_date,coalesce(p_basic_salary,0),coalesce(v.employment_type,'regular'),'full_time','monthly',null,'applicable');
 update unimis.hr_employees set phone=coalesce(a.phone,phone) where id=e;
 -- Reuse the exact same private storage object; only create an Employee Master metadata reference.
 insert into unimis.hr_employee_documents(tenant_id,employee_id,document_type,title,file_path,notes,uploaded_by)
 select d.tenant_id,e,d.document_type,d.title,d.file_path,'Transferred from recruitment without duplicating storage',auth.uid()
 from unimis.hr_applicant_documents d
 where d.applicant_id=a.id and d.tenant_id=p_tenant and d.review_status='verified';
 update unimis.hr_applicant_documents set transferred_employee_id=e where applicant_id=a.id and tenant_id=p_tenant and review_status='verified';
 update unimis.hr_applicants set status='hired',employee_id=e,updated_at=now() where id=a.id;
 perform unimis.hr_record_employment_event(p_tenant,e,'recruitment_hire',p_hire_date,'Hired from recruitment',jsonb_build_object('applicant_id',a.id,'vacancy_id',a.vacancy_id));
 return e;
end $$;
grant execute on function unimis.hr_hire_applicant(uuid,uuid,text,date,numeric) to authenticated;

notify pgrst, 'reload schema';

create or replace function unimis.hr_set_applicant_retention() returns trigger language plpgsql set search_path=unimis as $$
declare m integer;
begin
 if new.status in ('rejected','withdrawn','offer_declined') and (old.status is distinct from new.status or new.retention_until is null) then
   select unsuccessful_retention_months into m from unimis.hr_recruitment_settings where tenant_id=new.tenant_id;
   new.retention_until := current_date + make_interval(months=>coalesce(m,12));
 end if;
 return new;
end $$;
drop trigger if exists hr_applicant_retention_trigger on unimis.hr_applicants;
create trigger hr_applicant_retention_trigger before update on unimis.hr_applicants for each row execute function unimis.hr_set_applicant_retention();

notify pgrst, 'reload schema';


-- SOURCE 202610140008_vacancy_details_publishing.sql
-- Package 003b: richer vacancy specification and controlled publishing workflow.
alter table unimis.hr_vacancies add column if not exists responsibilities text;
alter table unimis.hr_vacancies add column if not exists experience_required text;
alter table unimis.hr_vacancies add column if not exists conditions_text text;
alter table unimis.hr_vacancies add column if not exists location_text text;
alter table unimis.hr_vacancies add column if not exists work_arrangement text not null default 'on_site';
alter table unimis.hr_vacancies add column if not exists cv_required boolean not null default true;
alter table unimis.hr_vacancies add column if not exists published_at timestamptz;
alter table unimis.hr_vacancies add column if not exists approved_at timestamptz;
alter table unimis.hr_vacancies add column if not exists approved_by uuid references auth.users(id) on delete set null;

update unimis.hr_vacancies set status='published',published_at=coalesce(published_at,created_at) where status='open';

alter table unimis.hr_vacancies drop constraint if exists hr_vacancies_status_check;
alter table unimis.hr_vacancies add constraint hr_vacancies_status_check check(status in ('draft','pending_approval','approved','published','closed','cancelled'));
alter table unimis.hr_vacancies drop constraint if exists hr_vacancies_work_arrangement_check;
alter table unimis.hr_vacancies add constraint hr_vacancies_work_arrangement_check check(work_arrangement in ('on_site','hybrid','remote'));

create index if not exists hr_vacancies_public_idx on unimis.hr_vacancies(tenant_id,status,closing_date);

-- Keep approval metadata when an authorised HR user moves a vacancy through review.
create or replace function unimis.hr_set_vacancy_status(p_tenant uuid,p_vacancy uuid,p_status text)
returns unimis.hr_vacancies language plpgsql security definer set search_path=unimis as $$
declare v unimis.hr_vacancies;
begin
 if not unimis.has_tenant_role(p_tenant,array['owner','administrator','hr_manager','hr_officer']) then raise exception 'Vacancy workflow access denied'; end if;
 if p_status not in ('draft','pending_approval','approved','published','closed','cancelled') then raise exception 'Invalid vacancy status'; end if;
 select * into v from unimis.hr_vacancies where id=p_vacancy and tenant_id=p_tenant for update;
 if v.id is null then raise exception 'Vacancy not found'; end if;
 if p_status='approved' and not unimis.has_tenant_role(p_tenant,array['owner','administrator','hr_manager']) then raise exception 'Approval access denied'; end if;
 update unimis.hr_vacancies set status=p_status,
   approved_at=case when p_status='approved' then now() else approved_at end,
   approved_by=case when p_status='approved' then auth.uid() else approved_by end,
   published_at=case when p_status='published' then now() else published_at end
 where id=p_vacancy returning * into v;
 return v;
end $$;
grant execute on function unimis.hr_set_vacancy_status(uuid,uuid,text) to authenticated;
notify pgrst, 'reload schema';


-- SOURCE 202610140009_vacancy_edit_recruitment_seed.sql
-- Package 003f: recruitment test seed helper. Production data is untouched.
create or replace function unimis.seed_recruitment_test(p_tenant uuid)
returns jsonb language plpgsql security definer set search_path=unimis as $$
declare
  v_vacancy uuid; v_title text; a1 uuid; a2 uuid; a3 uuid; a4 uuid; a5 uuid;
begin
  if not unimis.has_tenant_role(p_tenant,array['owner','administrator','hr_manager','hr_officer']) then
    raise exception 'Recruitment seed access denied';
  end if;

  select id,title into v_vacancy,v_title from unimis.hr_vacancies
   where tenant_id=p_tenant and status='published'
   order by published_at desc nulls last, created_at desc limit 1;
  if v_vacancy is null then
    raise exception 'Publish at least one vacancy before loading the recruitment test seed';
  end if;

  -- Idempotent demo seed: remove only our known, non-hired test candidates.
  delete from unimis.hr_applicants
   where tenant_id=p_tenant and email like 'recruit.test.%@hrpayrollcore.local' and status <> 'hired';

  insert into unimis.hr_applicants(tenant_id,vacancy_id,first_name,last_name,email,phone,date_of_birth,source,status,highest_qualification,years_experience,key_skills,screening_score,screening_notes)
  values(p_tenant,v_vacancy,'Adwoa','Owusu','recruit.test.1@hrpayrollcore.local','0240001001','1995-04-12','Seed test','applied','BSc Business Administration',3,'Administration, records, Microsoft Office',72,'Meets basic requirements') returning id into a1;

  insert into unimis.hr_applicants(tenant_id,vacancy_id,first_name,last_name,email,phone,date_of_birth,source,status,highest_qualification,years_experience,key_skills,screening_score,screening_notes)
  values(p_tenant,v_vacancy,'Kofi','Boateng','recruit.test.2@hrpayrollcore.local','0240001002','1992-09-21','Seed test','shortlisted','HND Accounting',5,'Accounting, Excel, reconciliation',84,'Strong relevant experience') returning id into a2;

  insert into unimis.hr_applicants(tenant_id,vacancy_id,first_name,last_name,email,phone,date_of_birth,source,status,highest_qualification,years_experience,key_skills,screening_score,screening_notes)
  values(p_tenant,v_vacancy,'Akosua','Mensimah','recruit.test.3@hrpayrollcore.local','0240001003','1997-01-08','Seed test','shortlisted','BCom',2,'Customer service, reporting, Excel',80,'Suitable for interview') returning id into a3;

  insert into unimis.hr_applicants(tenant_id,vacancy_id,first_name,last_name,email,phone,date_of_birth,source,status,highest_qualification,years_experience,key_skills,screening_score,screening_notes)
  values(p_tenant,v_vacancy,'Yaw','Asante','recruit.test.4@hrpayrollcore.local','0240001004','1993-07-15','Seed test','interviewed','BSc Accounting',6,'Accounting, ERP, reporting',91,'Interview completed; strong recommendation') returning id into a4;
  insert into unimis.hr_interviews(tenant_id,applicant_id,interview_at,interview_type,panel_notes,score,recommendation,created_by)
  values(p_tenant,a4,now()-interval '1 day','in_person','Clear communication and strong practical examples.',88,'Recommended for selection',auth.uid());

  insert into unimis.hr_applicants(tenant_id,vacancy_id,first_name,last_name,email,phone,date_of_birth,source,status,highest_qualification,years_experience,key_skills,screening_score,screening_notes,selected_at)
  values(p_tenant,v_vacancy,'Esi','Agyeman','recruit.test.5@hrpayrollcore.local','0240001005','1991-11-30','Seed test','offer_accepted','BSc Accounting',7,'Accounting, payroll, ERP, supervision',95,'Preferred candidate after interview',now()-interval '2 days') returning id into a5;
  insert into unimis.hr_interviews(tenant_id,applicant_id,interview_at,interview_type,panel_notes,score,recommendation,created_by)
  values(p_tenant,a5,now()-interval '3 days','in_person','Excellent technical and behavioural interview.',94,'Select',auth.uid());
  insert into unimis.hr_offers(tenant_id,applicant_id,offered_salary,proposed_start_date,employment_type,status,issued_at,responded_at,created_by)
  values(p_tenant,a5,4500,current_date+7,'regular','accepted',now()-interval '2 days',now()-interval '1 day',auth.uid());

  return jsonb_build_object('message','5 test applicants added to '||v_title||'. Final Hire is intentionally left for manual testing.','vacancy_id',v_vacancy,'hire_ready_applicant',a5);
end $$;
grant execute on function unimis.seed_recruitment_test(uuid) to authenticated;
notify pgrst, 'reload schema';


-- SOURCE 202610140010_employee_master_lifecycle_workspace.sql
-- Package 004: Employee Master Lifecycle Workspace foundation.
-- Employee Master remains the single source of truth across the employment lifecycle.

alter table unimis.hr_employees
 add column if not exists job_description text,
 add column if not exists job_responsibilities text,
 add column if not exists work_location text;

-- Preserve the accepted recruitment terms on hire. Verified documents continue to reuse
-- the same private storage object path; no binary file is copied.
create or replace function unimis.hr_hire_applicant(p_tenant uuid,p_applicant uuid,p_employee_no text,p_hire_date date,p_basic_salary numeric default 0)
returns uuid language plpgsql security definer set search_path=unimis as $$
declare
 a unimis.hr_applicants%rowtype;
 v unimis.hr_vacancies%rowtype;
 o unimis.hr_offers%rowtype;
 e uuid;
 effective_salary numeric;
 effective_type text;
begin
 if not unimis.has_tenant_role(p_tenant,array['owner','administrator','hr_manager']) then raise exception 'Hiring access denied'; end if;
 select * into a from unimis.hr_applicants where id=p_applicant and tenant_id=p_tenant for update;
 if a.id is null then raise exception 'Applicant not found'; end if;
 if a.status <> 'offer_accepted' then raise exception 'Offer must be accepted before hiring'; end if;
 if a.employee_id is not null then raise exception 'Applicant is already linked to an employee'; end if;
 if a.vacancy_id is not null then select * into v from unimis.hr_vacancies where id=a.vacancy_id and tenant_id=p_tenant; end if;
 select * into o from unimis.hr_offers where applicant_id=a.id and tenant_id=p_tenant and status='accepted' order by responded_at desc nulls last,created_at desc limit 1;
 effective_salary:=coalesce(nullif(p_basic_salary,0),o.offered_salary,0);
 effective_type:=coalesce(o.employment_type,v.employment_type,'regular');
 e:=unimis.hr_create_employee(p_tenant,p_employee_no,a.first_name,a.last_name,coalesce(a.email,''),v.department_id,v.position_id,a.date_of_birth,coalesce(o.proposed_start_date,p_hire_date,current_date),effective_salary,effective_type,'full_time','monthly',null,'applicable');
 update unimis.hr_employees set
   phone=coalesce(a.phone,phone),
   job_description=v.description,
   job_responsibilities=v.responsibilities,
   work_location=coalesce(v.location_text,v.work_arrangement)
 where id=e;
 insert into unimis.hr_employee_documents(tenant_id,employee_id,document_type,title,file_path,notes,uploaded_by)
 select d.tenant_id,e,d.document_type,d.title,d.file_path,'Linked from verified recruitment document; storage object not duplicated',auth.uid()
 from unimis.hr_applicant_documents d
 where d.applicant_id=a.id and d.tenant_id=p_tenant and d.review_status='verified'
 and not exists(select 1 from unimis.hr_employee_documents ed where ed.employee_id=e and ed.file_path=d.file_path);
 update unimis.hr_applicant_documents set transferred_employee_id=e where applicant_id=a.id and tenant_id=p_tenant and review_status='verified';
 update unimis.hr_applicants set status='hired',employee_id=e,updated_at=now() where id=a.id;
 perform unimis.hr_record_employment_event(p_tenant,e,'recruitment_hire',coalesce(o.proposed_start_date,p_hire_date,current_date),'Hired from recruitment',jsonb_build_object('applicant_id',a.id,'vacancy_id',a.vacancy_id,'offer_id',o.id,'employment_type',effective_type,'offered_salary',effective_salary,'job_responsibilities',v.responsibilities));
 return e;
end $$;
grant execute on function unimis.hr_hire_applicant(uuid,uuid,text,date,numeric) to authenticated;

notify pgrst, 'reload schema';


-- SOURCE 202610140011_career_exit_rehire.sql
-- Package 004b: governed career actions, separation and rehire.
create table if not exists unimis.hr_employee_lifecycle_actions(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.tenants(id) on delete cascade,
 employee_id uuid not null references unimis.hr_employees(id) on delete cascade,
 action_type text not null, effective_date date not null, reason_category text, reason_details text,
 old_department_id uuid references unimis.departments(id), new_department_id uuid references unimis.departments(id),
 old_position_id uuid references unimis.hr_positions(id), new_position_id uuid references unimis.hr_positions(id),
 old_employment_type text, new_employment_type text, new_salary numeric(14,2), notice_date date, last_working_date date,
 supporting_reference text, status text not null default 'submitted', submitted_by uuid references auth.users(id),
 approved_by uuid references auth.users(id), approved_at timestamptz, applied_at timestamptz, created_at timestamptz default now(),
 constraint lifecycle_action_type_ck check(action_type in ('promotion','transfer','demotion','acting_appointment','grade_change','contract_renewal','secondment','suspension','reinstatement','award','resignation','termination','dismissal','retirement','contract_end','redundancy','death_in_service','rehire')),
 constraint lifecycle_status_ck check(status in ('draft','submitted','approved','rejected','applied'))
);
alter table unimis.hr_employee_lifecycle_actions enable row level security;
drop policy if exists lifecycle_read on unimis.hr_employee_lifecycle_actions;
create policy lifecycle_read on unimis.hr_employee_lifecycle_actions for select using(unimis.is_tenant_member(tenant_id));
drop policy if exists lifecycle_insert on unimis.hr_employee_lifecycle_actions;
create policy lifecycle_insert on unimis.hr_employee_lifecycle_actions for insert with check(unimis.has_tenant_role(tenant_id,array['owner','administrator','hr_manager','hr_officer']));
drop policy if exists lifecycle_update on unimis.hr_employee_lifecycle_actions;
create policy lifecycle_update on unimis.hr_employee_lifecycle_actions for update using(unimis.has_tenant_role(tenant_id,array['owner','administrator','hr_manager'])) with check(unimis.has_tenant_role(tenant_id,array['owner','administrator','hr_manager']));

create or replace function unimis.hr_submit_lifecycle_action(p_tenant uuid,p_employee uuid,p_action_type text,p_effective_date date,p_reason_category text default null,p_reason_details text default null,p_new_position uuid default null,p_new_department uuid default null,p_new_employment_type text default null,p_new_salary numeric default null,p_last_working_date date default null,p_notice_date date default null,p_supporting_reference text default null)
returns uuid language plpgsql security definer set search_path=unimis as $$
declare e unimis.hr_employees%rowtype; x uuid;
begin
 if not unimis.has_tenant_role(p_tenant,array['owner','administrator','hr_manager','hr_officer']) then raise exception 'HR access denied'; end if;
 select * into e from unimis.hr_employees where id=p_employee and tenant_id=p_tenant;
 if e.id is null then raise exception 'Employee not found'; end if;
 if p_action_type='rehire' and e.employment_status='active' then raise exception 'Employee is already active'; end if;
 if p_action_type in ('resignation','termination','dismissal','retirement','contract_end','redundancy','death_in_service') and e.employment_status<>'active' then raise exception 'Only an active employee can be separated'; end if;
 insert into unimis.hr_employee_lifecycle_actions(tenant_id,employee_id,action_type,effective_date,reason_category,reason_details,old_department_id,new_department_id,old_position_id,new_position_id,old_employment_type,new_employment_type,new_salary,last_working_date,notice_date,supporting_reference,status,submitted_by)
 values(p_tenant,p_employee,p_action_type,coalesce(p_effective_date,current_date),p_reason_category,p_reason_details,e.department_id,p_new_department,e.position_id,p_new_position,e.employment_type,p_new_employment_type,p_new_salary,p_last_working_date,p_notice_date,p_supporting_reference,'submitted',auth.uid()) returning id into x;
 return x;
end $$;
grant execute on function unimis.hr_submit_lifecycle_action(uuid,uuid,text,date,text,text,uuid,uuid,text,numeric,date,date,text) to authenticated;

create or replace function unimis.hr_approve_lifecycle_action(p_tenant uuid,p_action uuid)
returns jsonb language plpgsql security definer set search_path=unimis as $$
declare a unimis.hr_employee_lifecycle_actions%rowtype; e unimis.hr_employees%rowtype; new_status text;
begin
 if not unimis.has_tenant_role(p_tenant,array['owner','administrator','hr_manager']) then raise exception 'Approval access denied'; end if;
 select * into a from unimis.hr_employee_lifecycle_actions where id=p_action and tenant_id=p_tenant for update;
 if a.id is null then raise exception 'Action not found'; end if;
 if a.status<>'submitted' then raise exception 'Action is not awaiting approval'; end if;
 select * into e from unimis.hr_employees where id=a.employee_id and tenant_id=p_tenant for update;
 if a.action_type in ('promotion','transfer','demotion','acting_appointment','grade_change','secondment') then
   update unimis.hr_employees set department_id=coalesce(a.new_department_id,department_id),position_id=coalesce(a.new_position_id,position_id) where id=e.id;
 elsif a.action_type='suspension' then update unimis.hr_employees set employment_status='suspended' where id=e.id;
 elsif a.action_type='reinstatement' then update unimis.hr_employees set employment_status='active' where id=e.id;
 elsif a.action_type in ('resignation','termination','dismissal','retirement','contract_end','redundancy','death_in_service') then
   new_status=case a.action_type when 'resignation' then 'resigned' when 'retirement' then 'retired' when 'death_in_service' then 'deceased' when 'contract_end' then 'contract_ended' else 'terminated' end;
   update unimis.hr_employees set employment_status=new_status where id=e.id;
   update unimis.payroll_profiles set active=false where employee_id=e.id;
   update unimis.hr_employment_contracts set status='ended',end_date=coalesce(a.last_working_date,a.effective_date) where employee_id=e.id and status='active';
 elsif a.action_type='rehire' then
   update unimis.hr_employees set employment_status='active',hire_date=a.effective_date,department_id=coalesce(a.new_department_id,department_id),position_id=coalesce(a.new_position_id,position_id),employment_type=coalesce(a.new_employment_type,employment_type) where id=e.id;
   update unimis.payroll_profiles set active=true where employee_id=e.id;
   insert into unimis.hr_employment_contracts(tenant_id,employee_id,contract_type,start_date,basic_salary,pay_frequency,status) values(p_tenant,e.id,coalesce(a.new_employment_type,'regular'),a.effective_date,coalesce(a.new_salary,0),'monthly','active');
 end if;
 update unimis.hr_employee_lifecycle_actions set status='applied',approved_by=auth.uid(),approved_at=now(),applied_at=now() where id=a.id;
 perform unimis.hr_record_employment_event(p_tenant,e.id,a.action_type,a.effective_date,initcap(replace(a.action_type,'_',' ')),jsonb_build_object('lifecycle_action_id',a.id,'reason_category',a.reason_category,'reason_details',a.reason_details,'old_department_id',a.old_department_id,'new_department_id',a.new_department_id,'old_position_id',a.old_position_id,'new_position_id',a.new_position_id,'last_working_date',a.last_working_date));
 return jsonb_build_object('ok',true,'employee_id',e.id,'action',a.action_type);
end $$;
grant execute on function unimis.hr_approve_lifecycle_action(uuid,uuid) to authenticated;
notify pgrst, 'reload schema';


-- SOURCE 202610140012_lifecycle_supporting_documents.sql
-- Package 004c: secure supporting documents for employee lifecycle actions.
alter table unimis.hr_employee_lifecycle_actions
  add column if not exists supporting_file_path text,
  add column if not exists supporting_file_name text;

create or replace function unimis.hr_attach_lifecycle_document(
  p_tenant uuid,
  p_action uuid,
  p_file_path text,
  p_file_name text
) returns void
language plpgsql security definer set search_path=unimis as $$
begin
  if not unimis.has_tenant_role(p_tenant,array['owner','administrator','hr_manager','hr_officer']) then
    raise exception 'HR access denied';
  end if;
  update unimis.hr_employee_lifecycle_actions
     set supporting_file_path=p_file_path,
         supporting_file_name=p_file_name
   where id=p_action and tenant_id=p_tenant;
  if not found then raise exception 'Lifecycle action not found'; end if;
end $$;
grant execute on function unimis.hr_attach_lifecycle_document(uuid,uuid,text,text) to authenticated;

notify pgrst, 'reload schema';


-- SOURCE 202610140013_lifecycle_controls_document_types.sql
-- Package 004e: lifecycle controls, richer HR document types, duplicate prevention.
update storage.buckets
set allowed_mime_types = array[
 'application/pdf','image/jpeg','image/png','image/webp',
 'application/msword','application/vnd.openxmlformats-officedocument.wordprocessingml.document',
 'application/vnd.ms-excel','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
]
where id='employee-documents';

alter table unimis.hr_employee_lifecycle_actions
  add column if not exists rejected_by uuid references auth.users(id),
  add column if not exists rejected_at timestamptz,
  add column if not exists cancelled_by uuid references auth.users(id),
  add column if not exists cancelled_at timestamptz,
  add column if not exists decision_notes text;

alter table unimis.hr_employee_lifecycle_actions drop constraint if exists lifecycle_status_ck;
alter table unimis.hr_employee_lifecycle_actions add constraint lifecycle_status_ck
 check(status in ('draft','submitted','approved','rejected','cancelled','applied'));

create or replace function unimis.hr_submit_lifecycle_action(p_tenant uuid,p_employee uuid,p_action_type text,p_effective_date date,p_reason_category text default null,p_reason_details text default null,p_new_position uuid default null,p_new_department uuid default null,p_new_employment_type text default null,p_new_salary numeric default null,p_last_working_date date default null,p_notice_date date default null,p_supporting_reference text default null)
returns uuid language plpgsql security definer set search_path=unimis as $$
declare e unimis.hr_employees%rowtype; x uuid; pending_count integer;
begin
 if not unimis.has_tenant_role(p_tenant,array['owner','administrator','hr_manager','hr_officer']) then raise exception 'HR access denied'; end if;
 select * into e from unimis.hr_employees where id=p_employee and tenant_id=p_tenant;
 if e.id is null then raise exception 'Employee not found'; end if;
 if p_action_type='rehire' and e.employment_status='active' then raise exception 'Employee is already active'; end if;
 if p_action_type in ('resignation','termination','dismissal','retirement','contract_end','redundancy','death_in_service') and e.employment_status<>'active' then raise exception 'Only an active employee can be separated'; end if;
 if p_action_type in ('resignation','termination','dismissal','retirement','contract_end','redundancy','death_in_service') then
   select count(*) into pending_count from unimis.hr_employee_lifecycle_actions
    where tenant_id=p_tenant and employee_id=p_employee and status='submitted'
      and action_type in ('resignation','termination','dismissal','retirement','contract_end','redundancy','death_in_service');
   if pending_count>0 then raise exception 'A separation request is already awaiting approval. Approve, reject or cancel it before submitting another.'; end if;
 end if;
 insert into unimis.hr_employee_lifecycle_actions(tenant_id,employee_id,action_type,effective_date,reason_category,reason_details,old_department_id,new_department_id,old_position_id,new_position_id,old_employment_type,new_employment_type,new_salary,last_working_date,notice_date,supporting_reference,status,submitted_by)
 values(p_tenant,p_employee,p_action_type,coalesce(p_effective_date,current_date),p_reason_category,p_reason_details,e.department_id,p_new_department,e.position_id,p_new_position,e.employment_type,p_new_employment_type,p_new_salary,p_last_working_date,p_notice_date,p_supporting_reference,'submitted',auth.uid()) returning id into x;
 return x;
end $$;
grant execute on function unimis.hr_submit_lifecycle_action(uuid,uuid,text,date,text,text,uuid,uuid,text,numeric,date,date,text) to authenticated;

create or replace function unimis.hr_reject_lifecycle_action(p_tenant uuid,p_action uuid,p_notes text default null)
returns void language plpgsql security definer set search_path=unimis as $$
begin
 if not unimis.has_tenant_role(p_tenant,array['owner','administrator','hr_manager']) then raise exception 'Approval access denied'; end if;
 update unimis.hr_employee_lifecycle_actions set status='rejected',rejected_by=auth.uid(),rejected_at=now(),decision_notes=p_notes
 where id=p_action and tenant_id=p_tenant and status='submitted';
 if not found then raise exception 'Action is not awaiting approval'; end if;
end $$;
grant execute on function unimis.hr_reject_lifecycle_action(uuid,uuid,text) to authenticated;

create or replace function unimis.hr_cancel_lifecycle_action(p_tenant uuid,p_action uuid)
returns void language plpgsql security definer set search_path=unimis as $$
begin
 if not unimis.has_tenant_role(p_tenant,array['owner','administrator','hr_manager','hr_officer']) then raise exception 'HR access denied'; end if;
 update unimis.hr_employee_lifecycle_actions set status='cancelled',cancelled_by=auth.uid(),cancelled_at=now()
 where id=p_action and tenant_id=p_tenant and status='submitted';
 if not found then raise exception 'Only a submitted action can be cancelled'; end if;
end $$;
grant execute on function unimis.hr_cancel_lifecycle_action(uuid,uuid) to authenticated;

notify pgrst, 'reload schema';


-- SOURCE 202610160014_attendance_leave_core.sql
-- Package 005: Attendance + Leave Core
create table if not exists unimis.hr_work_schedules(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.tenants(id) on delete cascade,
 code text not null, name text not null, start_time time not null default '08:00', end_time time not null default '17:00',
 grace_minutes integer not null default 10, standard_minutes integer not null default 480, work_days integer[] not null default array[1,2,3,4,5], active boolean not null default true,
 created_at timestamptz not null default now(), unique(tenant_id,code)
);
create table if not exists unimis.hr_employee_schedule_assignments(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references unimis.tenants(id) on delete cascade,
 employee_id uuid not null references unimis.hr_employees(id) on delete cascade,schedule_id uuid not null references unimis.hr_work_schedules(id),
 effective_from date not null default current_date,effective_to date,created_at timestamptz not null default now()
);
create table if not exists unimis.hr_attendance_records(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references unimis.tenants(id) on delete cascade,
 employee_id uuid not null references unimis.hr_employees(id) on delete cascade,work_date date not null,
 check_in timestamptz,check_out timestamptz,status text not null default 'present' check(status in ('present','absent','late','half_day','on_leave','holiday','off_day')),
 capture_method text not null default 'manual' check(capture_method in ('manual','qr','gps','nfc','biometric','import','api')),
 late_minutes integer not null default 0,overtime_minutes integer not null default 0,worked_minutes integer not null default 0,
 latitude numeric(10,7),longitude numeric(10,7),notes text,correction_status text not null default 'none',created_by uuid default auth.uid(),created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 unique(tenant_id,employee_id,work_date)
);
create table if not exists unimis.hr_public_holidays(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references unimis.tenants(id) on delete cascade,
 holiday_date date not null,name text not null,country_code text default 'GH',active boolean default true,unique(tenant_id,holiday_date)
);
create table if not exists unimis.hr_leave_types(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references unimis.tenants(id) on delete cascade,
 code text not null,name text not null,default_days numeric(7,2) not null default 0,paid boolean not null default true,
 requires_attachment boolean not null default false,carry_forward boolean not null default false,max_carry_forward numeric(7,2),active boolean not null default true,
 created_at timestamptz not null default now(),unique(tenant_id,code)
);
create table if not exists unimis.hr_leave_entitlements(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references unimis.tenants(id) on delete cascade,
 employee_id uuid not null references unimis.hr_employees(id) on delete cascade,leave_type_id uuid not null references unimis.hr_leave_types(id) on delete cascade,
 leave_year integer not null,entitled_days numeric(7,2) not null default 0,carried_days numeric(7,2) not null default 0,adjustment_days numeric(7,2) not null default 0,
 unique(tenant_id,employee_id,leave_type_id,leave_year)
);
create table if not exists unimis.hr_leave_requests(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references unimis.tenants(id) on delete cascade,
 employee_id uuid not null references unimis.hr_employees(id) on delete cascade,leave_type_id uuid not null references unimis.hr_leave_types(id),
 start_date date not null,end_date date not null,requested_days numeric(7,2) generated always as ((end_date-start_date)+1) stored,
 reason text,status text not null default 'draft' check(status in ('draft','submitted','approved','rejected','cancelled')),
 attachment_path text,decision_notes text,decided_by uuid,decided_at timestamptz,created_by uuid default auth.uid(),created_at timestamptz not null default now(),
 check(end_date>=start_date)
);

alter table unimis.hr_work_schedules enable row level security;alter table unimis.hr_employee_schedule_assignments enable row level security;alter table unimis.hr_attendance_records enable row level security;alter table unimis.hr_public_holidays enable row level security;alter table unimis.hr_leave_types enable row level security;alter table unimis.hr_leave_entitlements enable row level security;alter table unimis.hr_leave_requests enable row level security;
do $$ declare t text; begin foreach t in array array['hr_work_schedules','hr_employee_schedule_assignments','hr_attendance_records','hr_public_holidays','hr_leave_types','hr_leave_entitlements','hr_leave_requests'] loop execute format('drop policy if exists tenant_member_all on unimis.%I',t); execute format('create policy tenant_member_all on unimis.%I for all using (unimis.is_tenant_member(tenant_id)) with check (unimis.is_tenant_member(tenant_id))',t); end loop; end $$;

create or replace function unimis.hr_seed_time_leave_defaults(p_tenant uuid) returns jsonb language plpgsql security definer set search_path=unimis as $$
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 insert into hr_work_schedules(tenant_id,code,name,start_time,end_time,grace_minutes,standard_minutes) values(p_tenant,'STD','Standard Monday-Friday','08:00','17:00',10,480) on conflict(tenant_id,code) do nothing;
 insert into hr_leave_types(tenant_id,code,name,default_days,paid,requires_attachment,carry_forward) values
 (p_tenant,'ANNUAL','Annual Leave',20,true,false,true),(p_tenant,'SICK','Sick Leave',10,true,true,false),(p_tenant,'MATERNITY','Maternity Leave',84,true,true,false),(p_tenant,'PATERNITY','Paternity Leave',5,true,false,false),(p_tenant,'UNPAID','Unpaid Leave',0,false,false,false),(p_tenant,'STUDY','Study Leave',0,true,true,false)
 on conflict(tenant_id,code) do nothing;
 return jsonb_build_object('ok',true);
end $$;

create or replace function unimis.hr_attendance_compute() returns trigger language plpgsql set search_path=unimis as $$
declare s hr_work_schedules%rowtype; sched_start timestamptz;begin
 select ws.* into s from hr_employee_schedule_assignments a join hr_work_schedules ws on ws.id=a.schedule_id where a.tenant_id=new.tenant_id and a.employee_id=new.employee_id and a.effective_from<=new.work_date and (a.effective_to is null or a.effective_to>=new.work_date) order by a.effective_from desc limit 1;
 if s.id is null then select * into s from hr_work_schedules where tenant_id=new.tenant_id and active order by created_at limit 1; end if;
 if new.check_in is not null and s.id is not null then sched_start=(new.work_date+s.start_time)::timestamp at time zone 'UTC'; new.late_minutes=greatest(0,floor(extract(epoch from(new.check_in-sched_start))/60)-s.grace_minutes); if new.late_minutes>0 then new.status='late'; end if; end if;
 if new.check_in is not null and new.check_out is not null and new.check_out>=new.check_in then new.worked_minutes=floor(extract(epoch from(new.check_out-new.check_in))/60); if s.id is not null then new.overtime_minutes=greatest(0,new.worked_minutes-s.standard_minutes); end if; end if;
 new.updated_at=now(); return new;end $$;
drop trigger if exists trg_attendance_compute on unimis.hr_attendance_records;create trigger trg_attendance_compute before insert or update on unimis.hr_attendance_records for each row execute function unimis.hr_attendance_compute();

create or replace function unimis.hr_decide_leave_request(p_tenant uuid,p_request uuid,p_decision text,p_notes text default null) returns jsonb language plpgsql security definer set search_path=unimis as $$
declare r hr_leave_requests%rowtype; d date;begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 if p_decision not in ('approved','rejected') then raise exception 'Invalid decision'; end if;
 select * into r from hr_leave_requests where id=p_request and tenant_id=p_tenant for update; if r.id is null then raise exception 'Request not found'; end if; if r.status<>'submitted' then raise exception 'Only submitted requests can be decided'; end if;
 update hr_leave_requests set status=p_decision,decision_notes=p_notes,decided_by=auth.uid(),decided_at=now() where id=r.id;
 if p_decision='approved' then for d in select generate_series(r.start_date,r.end_date,'1 day'::interval)::date loop insert into hr_attendance_records(tenant_id,employee_id,work_date,status,capture_method,notes) values(p_tenant,r.employee_id,d,'on_leave','api','Approved leave') on conflict(tenant_id,employee_id,work_date) do update set status='on_leave',notes='Approved leave'; end loop; end if;
 return jsonb_build_object('ok',true,'status',p_decision);end $$;

grant execute on function unimis.hr_seed_time_leave_defaults(uuid) to authenticated;grant execute on function unimis.hr_decide_leave_request(uuid,uuid,text,text) to authenticated;
create index if not exists idx_attendance_tenant_date on unimis.hr_attendance_records(tenant_id,work_date desc);create index if not exists idx_leave_tenant_status on unimis.hr_leave_requests(tenant_id,status,created_at desc);


-- SOURCE 202610160015_attendance_leave_synchronization.sql
-- Package 005a: Attendance / Leave Synchronization Engine
alter table unimis.hr_leave_requests add column if not exists day_portion text not null default 'full' check(day_portion in ('full','first_half','second_half'));
alter table unimis.hr_leave_requests add column if not exists approved_working_days numeric(7,2);
alter table unimis.hr_attendance_records add column if not exists leave_request_id uuid references unimis.hr_leave_requests(id) on delete set null;
alter table unimis.hr_attendance_records add column if not exists leave_fraction numeric(3,2) check(leave_fraction is null or leave_fraction in (0.5,1.0));
alter table unimis.hr_attendance_records add column if not exists leave_paid boolean;
alter table unimis.hr_attendance_records add column if not exists leave_generated boolean not null default false;
create index if not exists idx_attendance_leave_request on unimis.hr_attendance_records(leave_request_id);

create or replace function unimis.hr_leave_is_working_day(p_tenant uuid,p_employee uuid,p_day date)
returns boolean language plpgsql stable set search_path=unimis as $$
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

create or replace function unimis.hr_sync_leave_attendance(p_tenant uuid,p_request uuid)
returns jsonb language plpgsql security definer set search_path=unimis as $$
declare r hr_leave_requests%rowtype; lt hr_leave_types%rowtype; d date; rec hr_attendance_records%rowtype; frac numeric; workdays numeric:=0; note_text text;
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 select * into r from hr_leave_requests where id=p_request and tenant_id=p_tenant; if r.id is null then raise exception 'Request not found'; end if;
 select * into lt from hr_leave_types where id=r.leave_type_id and tenant_id=p_tenant;
 if r.status<>'approved' then raise exception 'Only approved leave can be synchronized'; end if;
 frac=case when r.day_portion='full' then 1.0 else 0.5 end;
 -- remove stale system-generated rows for this request before rebuilding
 delete from hr_attendance_records where tenant_id=p_tenant and leave_request_id=r.id and leave_generated=true and check_in is null and check_out is null;
 for d in select generate_series(r.start_date,r.end_date,'1 day'::interval)::date loop
   if unimis.hr_leave_is_working_day(p_tenant,r.employee_id,d) then
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

create or replace function unimis.hr_decide_leave_request(p_tenant uuid,p_request uuid,p_decision text,p_notes text default null)
returns jsonb language plpgsql security definer set search_path=unimis as $$
declare r hr_leave_requests%rowtype; result jsonb;
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 if p_decision not in ('approved','rejected') then raise exception 'Invalid decision'; end if;
 select * into r from hr_leave_requests where id=p_request and tenant_id=p_tenant for update;
 if r.id is null then raise exception 'Request not found'; end if;
 if r.status<>'submitted' then raise exception 'Only submitted requests can be decided'; end if;
 update hr_leave_requests set status=p_decision,decision_notes=p_notes,decided_by=auth.uid(),decided_at=now() where id=r.id;
 if p_decision='approved' then result=unimis.hr_sync_leave_attendance(p_tenant,r.id); else result=jsonb_build_object('ok',true); end if;
 return result||jsonb_build_object('status',p_decision);
end $$;

create or replace function unimis.hr_cancel_leave_request(p_tenant uuid,p_request uuid,p_notes text default null)
returns jsonb language plpgsql security definer set search_path=unimis as $$
declare r hr_leave_requests%rowtype;
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
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

grant execute on function unimis.hr_sync_leave_attendance(uuid,uuid) to authenticated;
grant execute on function unimis.hr_cancel_leave_request(uuid,uuid,text) to authenticated;


-- SOURCE 202610160016_smart_attendance_capture.sql
-- Package 005b: Smart Attendance Capture (rotating QR token + optional GPS geofence)
create extension if not exists pgcrypto;

create table if not exists unimis.hr_attendance_sites(
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references unimis.tenants(id) on delete cascade,
 code text not null,
 name text not null,
 latitude numeric(10,7),
 longitude numeric(10,7),
 radius_meters integer not null default 150 check(radius_meters between 20 and 5000),
 gps_required boolean not null default false,
 qr_enabled boolean not null default true,
 active boolean not null default true,
 created_at timestamptz not null default now(),
 unique(tenant_id,code),
 check(not gps_required or (latitude is not null and longitude is not null))
);
create table if not exists unimis.hr_attendance_qr_tokens(
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references unimis.tenants(id) on delete cascade,
 site_id uuid not null references unimis.hr_attendance_sites(id) on delete cascade,
 token_hash text not null,
 expires_at timestamptz not null,
 revoked_at timestamptz,
 created_by uuid default auth.uid(),
 created_at timestamptz not null default now()
);
create table if not exists unimis.hr_attendance_capture_events(
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references unimis.tenants(id) on delete cascade,
 employee_id uuid not null references unimis.hr_employees(id) on delete cascade,
 site_id uuid references unimis.hr_attendance_sites(id) on delete set null,
 attendance_id uuid references unimis.hr_attendance_records(id) on delete set null,
 event_type text not null check(event_type in ('check_in','check_out')),
 captured_at timestamptz not null default now(),
 capture_method text not null default 'qr' check(capture_method in ('qr','gps','nfc','biometric','api')),
 latitude numeric(10,7),longitude numeric(10,7),
 distance_meters numeric(10,2),gps_verified boolean,
 token_id uuid references unimis.hr_attendance_qr_tokens(id) on delete set null,
 created_by uuid default auth.uid()
);
alter table unimis.hr_attendance_records add column if not exists attendance_site_id uuid references unimis.hr_attendance_sites(id) on delete set null;
alter table unimis.hr_attendance_records add column if not exists gps_verified boolean;
alter table unimis.hr_attendance_records add column if not exists check_in_source text;
alter table unimis.hr_attendance_records add column if not exists check_out_source text;

alter table unimis.hr_attendance_sites enable row level security;
alter table unimis.hr_attendance_qr_tokens enable row level security;
alter table unimis.hr_attendance_capture_events enable row level security;
drop policy if exists tenant_member_all on unimis.hr_attendance_sites;
create policy tenant_member_all on unimis.hr_attendance_sites for all using(unimis.is_tenant_member(tenant_id)) with check(unimis.is_tenant_member(tenant_id));
drop policy if exists tenant_member_all on unimis.hr_attendance_qr_tokens;
create policy tenant_member_all on unimis.hr_attendance_qr_tokens for all using(unimis.is_tenant_member(tenant_id)) with check(unimis.is_tenant_member(tenant_id));
drop policy if exists tenant_member_all on unimis.hr_attendance_capture_events;
create policy tenant_member_all on unimis.hr_attendance_capture_events for all using(unimis.is_tenant_member(tenant_id)) with check(unimis.is_tenant_member(tenant_id));

create or replace function unimis.hr_distance_meters(lat1 numeric,lon1 numeric,lat2 numeric,lon2 numeric)
returns numeric language sql immutable as $$
 select 6371000 * 2 * asin(sqrt(power(sin(radians((lat2-lat1)/2)),2)+cos(radians(lat1))*cos(radians(lat2))*power(sin(radians((lon2-lon1)/2)),2)));
$$;

create or replace function unimis.hr_create_attendance_qr_token(p_tenant uuid,p_site uuid,p_valid_minutes integer default 5)
returns jsonb language plpgsql security definer set search_path=unimis as $$
declare raw_token text; exp timestamptz; tid uuid;
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 if p_valid_minutes not between 1 and 30 then raise exception 'Token validity must be 1-30 minutes'; end if;
 if not exists(select 1 from hr_attendance_sites where id=p_site and tenant_id=p_tenant and active and qr_enabled) then raise exception 'Active QR-enabled site not found'; end if;
 update hr_attendance_qr_tokens set revoked_at=now() where tenant_id=p_tenant and site_id=p_site and revoked_at is null and expires_at>now();
 raw_token=upper(substr(encode(gen_random_bytes(12),'hex'),1,20)); exp=now()+make_interval(mins=>p_valid_minutes);
 insert into hr_attendance_qr_tokens(tenant_id,site_id,token_hash,expires_at) values(p_tenant,p_site,encode(digest(raw_token,'sha256'),'hex'),exp) returning id into tid;
 return jsonb_build_object('token',raw_token,'expires_at',exp,'token_id',tid);
end $$;

create or replace function unimis.hr_capture_attendance(p_tenant uuid,p_employee uuid,p_site uuid,p_token text,p_action text,p_latitude numeric default null,p_longitude numeric default null)
returns jsonb language plpgsql security definer set search_path=unimis as $$
declare s hr_attendance_sites%rowtype; tok hr_attendance_qr_tokens%rowtype; rec hr_attendance_records%rowtype; dist numeric; nowts timestamptz:=now(); d date:=current_date; verified boolean:=null; method text:='qr';
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 if p_action not in ('check_in','check_out') then raise exception 'Invalid attendance action'; end if;
 if not exists(select 1 from hr_employees where id=p_employee and tenant_id=p_tenant and employment_status='active') then raise exception 'Active employee not found'; end if;
 select * into s from hr_attendance_sites where id=p_site and tenant_id=p_tenant and active;
 if s.id is null then raise exception 'Attendance site not found'; end if;
 select * into tok from hr_attendance_qr_tokens where tenant_id=p_tenant and site_id=p_site and token_hash=encode(digest(upper(trim(p_token)),'sha256'),'hex') and revoked_at is null and expires_at>=now() order by created_at desc limit 1;
 if tok.id is null then raise exception 'QR token is invalid or expired'; end if;
 if s.gps_required then
   if p_latitude is null or p_longitude is null then raise exception 'GPS location is required at this attendance site'; end if;
   dist=unimis.hr_distance_meters(s.latitude,s.longitude,p_latitude,p_longitude); verified=dist<=s.radius_meters; method='gps';
   if not verified then raise exception 'Outside attendance site geofence (% m away; allowed radius % m)',round(dist),s.radius_meters; end if;
 end if;
 select * into rec from hr_attendance_records where tenant_id=p_tenant and employee_id=p_employee and work_date=d for update;
 if rec.id is null then
   insert into hr_attendance_records(tenant_id,employee_id,work_date,status,capture_method,attendance_site_id,gps_verified,check_in,check_in_source,latitude,longitude,notes)
   values(p_tenant,p_employee,d,'present',method,p_site,verified,case when p_action='check_in' then nowts end,case when p_action='check_in' then method end,p_latitude,p_longitude,'Smart attendance capture')
   returning * into rec;
 end if;
 if p_action='check_in' then
   if rec.status in ('on_leave','holiday','off_day') then raise exception 'Check-in blocked because attendance status is %',replace(rec.status,'_',' '); end if;
   if rec.check_in is not null then raise exception 'Employee has already checked in today'; end if;
   update hr_attendance_records set check_in=nowts,status='present',capture_method=method,attendance_site_id=p_site,gps_verified=verified,check_in_source=method,latitude=p_latitude,longitude=p_longitude where id=rec.id returning * into rec;
 else
   if rec.check_in is null then raise exception 'Employee must check in before checking out'; end if;
   if rec.check_out is not null then raise exception 'Employee has already checked out today'; end if;
   update hr_attendance_records set check_out=nowts,capture_method=method,attendance_site_id=coalesce(attendance_site_id,p_site),gps_verified=coalesce(verified,gps_verified),check_out_source=method where id=rec.id returning * into rec;
 end if;
 insert into hr_attendance_capture_events(tenant_id,employee_id,site_id,attendance_id,event_type,captured_at,capture_method,latitude,longitude,distance_meters,gps_verified,token_id)
 values(p_tenant,p_employee,p_site,rec.id,p_action,nowts,method,p_latitude,p_longitude,dist,verified,tok.id);
 return jsonb_build_object('ok',true,'message',case when p_action='check_in' then 'Check-in recorded successfully.' else 'Check-out recorded successfully.' end,'attendance_id',rec.id,'gps_verified',verified,'distance_meters',dist);
end $$;

grant execute on function unimis.hr_create_attendance_qr_token(uuid,uuid,integer) to authenticated;
grant execute on function unimis.hr_capture_attendance(uuid,uuid,uuid,text,text,numeric,numeric) to authenticated;
create index if not exists idx_attendance_sites_tenant on unimis.hr_attendance_sites(tenant_id,active);
create index if not exists idx_attendance_tokens_site_expiry on unimis.hr_attendance_qr_tokens(tenant_id,site_id,expires_at desc);
create index if not exists idx_attendance_events_employee_time on unimis.hr_attendance_capture_events(tenant_id,employee_id,captured_at desc);


-- SOURCE 202610160017_employee_qr_kiosk.sql
-- 005d Employee QR Scanner & Site Kiosk
alter table unimis.hr_employees add column if not exists auth_user_id uuid references auth.users(id) on delete set null;
create unique index if not exists uq_hr_employee_auth_user on unimis.hr_employees(auth_user_id) where auth_user_id is not null;

create or replace function unimis.hr_my_employee(p_tenant uuid)
returns jsonb language plpgsql security definer set search_path=unimis as $$
declare e unimis.hr_employees%rowtype; mail text;
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 select * into e from unimis.hr_employees where tenant_id=p_tenant and auth_user_id=auth.uid() and employment_status='active' limit 1;
 if e.id is null then
   mail=lower(coalesce(auth.jwt()->>'email',''));
   if mail<>'' then
     select * into e from unimis.hr_employees where tenant_id=p_tenant and lower(coalesce(email,''))=mail and employment_status='active' limit 1;
     if e.id is not null and e.auth_user_id is null then update unimis.hr_employees set auth_user_id=auth.uid() where id=e.id; end if;
   end if;
 end if;
 if e.id is null then return null; end if;
 return jsonb_build_object('id',e.id,'employee_no',e.employee_no,'first_name',e.first_name,'last_name',e.last_name,'email',e.email);
end $$;
grant execute on function unimis.hr_my_employee(uuid) to authenticated;


-- SOURCE 202610160018_fix_attendance_qr_pgcrypto.sql
-- 005d1: make QR token crypto functions resolvable on local/hosted Supabase.
-- Supabase commonly installs pgcrypto in the extensions schema, while older/local
-- projects may expose it from unimis. Keep both schemas on the function search path.
create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

create or replace function unimis.hr_create_attendance_qr_token(
  p_tenant uuid,
  p_site uuid,
  p_valid_minutes integer default 5
)
returns jsonb
language plpgsql
security definer
set search_path=unimis,extensions
as $$
declare
  raw_token text;
  exp timestamptz;
  tid uuid;
begin
  if not unimis.is_tenant_member(p_tenant) then
    raise exception 'Tenant access denied';
  end if;
  if p_valid_minutes not between 1 and 30 then
    raise exception 'Token validity must be 1-30 minutes';
  end if;
  if not exists(
    select 1 from unimis.hr_attendance_sites
    where id=p_site and tenant_id=p_tenant and active and qr_enabled
  ) then
    raise exception 'Active QR-enabled site not found';
  end if;

  update unimis.hr_attendance_qr_tokens
     set revoked_at=now()
   where tenant_id=p_tenant
     and site_id=p_site
     and revoked_at is null
     and expires_at>now();

  raw_token=upper(substr(encode(gen_random_bytes(12),'hex'),1,20));
  exp=now()+make_interval(mins=>p_valid_minutes);

  insert into unimis.hr_attendance_qr_tokens(tenant_id,site_id,token_hash,expires_at)
  values(p_tenant,p_site,encode(digest(raw_token,'sha256'),'hex'),exp)
  returning id into tid;

  return jsonb_build_object('token',raw_token,'expires_at',exp,'token_id',tid);
end
$$;

grant execute on function unimis.hr_create_attendance_qr_token(uuid,uuid,integer) to authenticated;

-- The capture function also uses digest(), so ensure the same extension search path.
alter function unimis.hr_capture_attendance(uuid,uuid,uuid,text,text,numeric,numeric)
  set search_path=unimis,extensions;

notify pgrst, 'reload schema';


-- SOURCE 202610160019_permanent_printable_attendance_qr.sql
-- 005e Permanent/revocable site QR for printed attendance posters.
create extension if not exists pgcrypto with schema extensions;

create or replace function unimis.hr_create_permanent_attendance_qr(
  p_tenant uuid,
  p_site uuid
) returns jsonb
language plpgsql security definer
set search_path=unimis,extensions
as $$
declare raw_token text; exp timestamptz; tid uuid;
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 if not exists(select 1 from unimis.hr_attendance_sites where id=p_site and tenant_id=p_tenant and active and qr_enabled) then
   raise exception 'Active QR-enabled site not found';
 end if;
 -- One permanent printed QR per site. Generating a replacement revokes the old one.
 update unimis.hr_attendance_qr_tokens set revoked_at=now()
 where tenant_id=p_tenant and site_id=p_site and revoked_at is null;
 raw_token=upper(substr(encode(gen_random_bytes(18),'hex'),1,28));
 -- Existing capture engine requires expires_at. Use a far-future date; revocation is the real control.
 exp=now()+interval '20 years';
 insert into unimis.hr_attendance_qr_tokens(tenant_id,site_id,token_hash,expires_at)
 values(p_tenant,p_site,encode(digest(raw_token,'sha256'),'hex'),exp)
 returning id into tid;
 return jsonb_build_object('token',raw_token,'expires_at',exp,'token_id',tid,'mode','permanent');
end $$;
grant execute on function unimis.hr_create_permanent_attendance_qr(uuid,uuid) to authenticated;
notify pgrst, 'reload schema';


-- SOURCE 202610160020_passwordless_employee_attendance.sql
-- 005e1 Passwordless employee attendance: one-time phone activation + permanent site QR
alter table unimis.hr_attendance_sites add column if not exists permanent_qr_token text;
create unique index if not exists uq_attendance_site_permanent_qr on unimis.hr_attendance_sites(permanent_qr_token) where permanent_qr_token is not null;

create table if not exists unimis.hr_attendance_device_activations(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.tenants(id) on delete cascade,
 employee_id uuid not null references unimis.hr_employees(id) on delete cascade, token_hash text not null unique,
 expires_at timestamptz not null, redeemed_at timestamptz, created_by uuid default auth.uid(), created_at timestamptz not null default now());
create table if not exists unimis.hr_attendance_devices(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.tenants(id) on delete cascade,
 employee_id uuid not null references unimis.hr_employees(id) on delete cascade, credential_hash text not null unique,
 label text default 'Employee phone', active boolean not null default true, activated_at timestamptz not null default now(),
 last_used_at timestamptz, revoked_at timestamptz, created_at timestamptz not null default now());
alter table unimis.hr_attendance_device_activations enable row level security;
alter table unimis.hr_attendance_devices enable row level security;
drop policy if exists tenant_member_all on unimis.hr_attendance_device_activations;
create policy tenant_member_all on unimis.hr_attendance_device_activations for all using(unimis.is_tenant_member(tenant_id)) with check(unimis.is_tenant_member(tenant_id));
drop policy if exists tenant_member_all on unimis.hr_attendance_devices;
create policy tenant_member_all on unimis.hr_attendance_devices for all using(unimis.is_tenant_member(tenant_id)) with check(unimis.is_tenant_member(tenant_id));

create or replace function unimis.hr_get_or_create_permanent_site_qr(p_tenant uuid,p_site uuid) returns jsonb
language plpgsql security definer set search_path=unimis,extensions as $$
declare t text;
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 select permanent_qr_token into t from unimis.hr_attendance_sites where id=p_site and tenant_id=p_tenant and active;
 if not found then raise exception 'Attendance site not found'; end if;
 if t is null then t=encode(extensions.gen_random_bytes(24),'hex'); update unimis.hr_attendance_sites set permanent_qr_token=t where id=p_site; end if;
 return jsonb_build_object('token',t);
end $$;
create or replace function unimis.hr_regenerate_permanent_site_qr(p_tenant uuid,p_site uuid) returns void
language plpgsql security definer set search_path=unimis,extensions as $$ begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 update unimis.hr_attendance_sites set permanent_qr_token=encode(extensions.gen_random_bytes(24),'hex') where id=p_site and tenant_id=p_tenant;
 if not found then raise exception 'Attendance site not found'; end if;
end $$;

create or replace function unimis.hr_create_attendance_device_activation(p_tenant uuid,p_employee uuid) returns jsonb
language plpgsql security definer set search_path=unimis,extensions as $$
declare raw text; exp timestamptz:=now()+interval '30 minutes'; n text;
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 select concat(first_name,' ',last_name) into n from unimis.hr_employees where id=p_employee and tenant_id=p_tenant and employment_status='active';
 if n is null then raise exception 'Active employee not found'; end if;
 update unimis.hr_attendance_device_activations set expires_at=now() where tenant_id=p_tenant and employee_id=p_employee and redeemed_at is null and expires_at>now();
 raw=encode(extensions.gen_random_bytes(24),'hex');
 insert into unimis.hr_attendance_device_activations(tenant_id,employee_id,token_hash,expires_at) values(p_tenant,p_employee,encode(extensions.digest(raw,'sha256'),'hex'),exp);
 return jsonb_build_object('activation_token',raw,'expires_at',exp,'employee_name',n);
end $$;

create or replace function unimis.hr_redeem_attendance_device_activation(p_activation_token text) returns jsonb
language plpgsql security definer set search_path=unimis,extensions as $$
declare a unimis.hr_attendance_device_activations%rowtype; raw text; n text;
begin
 select * into a from unimis.hr_attendance_device_activations where token_hash=encode(extensions.digest(trim(p_activation_token),'sha256'),'hex') and redeemed_at is null and expires_at>=now() for update;
 if a.id is null then raise exception 'Activation QR is invalid, expired or already used'; end if;
 raw=encode(extensions.gen_random_bytes(32),'hex');
 insert into unimis.hr_attendance_devices(tenant_id,employee_id,credential_hash) values(a.tenant_id,a.employee_id,encode(extensions.digest(raw,'sha256'),'hex'));
 update unimis.hr_attendance_device_activations set redeemed_at=now() where id=a.id;
 select concat(first_name,' ',last_name) into n from unimis.hr_employees where id=a.employee_id;
 return jsonb_build_object('tenant_id',a.tenant_id,'employee_name',n,'device_credential',raw);
end $$;

create or replace function unimis.hr_public_attendance_context(p_tenant uuid,p_site uuid,p_site_token text,p_device_credential text) returns jsonb
language plpgsql security definer set search_path=unimis,extensions as $$
declare s unimis.hr_attendance_sites%rowtype; d unimis.hr_attendance_devices%rowtype; e unimis.hr_employees%rowtype; r unimis.hr_attendance_records%rowtype; act text;
begin
 select * into s from unimis.hr_attendance_sites where id=p_site and tenant_id=p_tenant and active and qr_enabled and permanent_qr_token=p_site_token;
 if s.id is null then raise exception 'Workplace QR is invalid or has been revoked'; end if;
 select * into d from unimis.hr_attendance_devices where tenant_id=p_tenant and credential_hash=encode(extensions.digest(trim(p_device_credential),'sha256'),'hex') and active and revoked_at is null;
 if d.id is null then raise exception 'This phone is not activated for attendance'; end if;
 select * into e from unimis.hr_employees where id=d.employee_id and tenant_id=p_tenant and employment_status='active'; if e.id is null then raise exception 'Employee is not active'; end if;
 select * into r from unimis.hr_attendance_records where tenant_id=p_tenant and employee_id=e.id and work_date=current_date;
 act=case when r.check_in is null then 'check_in' when r.check_out is null then 'check_out' else 'complete' end;
 return jsonb_build_object('employee',jsonb_build_object('name',concat(e.first_name,' ',e.last_name),'employee_no',e.employee_no),'site',jsonb_build_object('name',s.name,'gps_required',s.gps_required),'action',act,'complete',(act='complete'));
end $$;

create or replace function unimis.hr_public_device_attendance(p_tenant uuid,p_site uuid,p_site_token text,p_device_credential text,p_latitude numeric default null,p_longitude numeric default null) returns jsonb
language plpgsql security definer set search_path=unimis,extensions as $$
declare s unimis.hr_attendance_sites%rowtype; d unimis.hr_attendance_devices%rowtype; e unimis.hr_employees%rowtype; r unimis.hr_attendance_records%rowtype; dist numeric; verified boolean:=null; nowts timestamptz:=now(); act text;
begin
 select * into s from unimis.hr_attendance_sites where id=p_site and tenant_id=p_tenant and active and qr_enabled and permanent_qr_token=p_site_token; if s.id is null then raise exception 'Workplace QR is invalid or revoked'; end if;
 select * into d from unimis.hr_attendance_devices where tenant_id=p_tenant and credential_hash=encode(extensions.digest(trim(p_device_credential),'sha256'),'hex') and active and revoked_at is null; if d.id is null then raise exception 'Phone attendance activation is invalid or revoked'; end if;
 select * into e from unimis.hr_employees where id=d.employee_id and tenant_id=p_tenant and employment_status='active'; if e.id is null then raise exception 'Employee is not active'; end if;
 if s.gps_required then if p_latitude is null or p_longitude is null then raise exception 'GPS location is required'; end if; dist=unimis.hr_distance_meters(s.latitude,s.longitude,p_latitude,p_longitude); verified=dist<=s.radius_meters; if not verified then raise exception 'Outside attendance site geofence (% m away; allowed radius % m)',round(dist),s.radius_meters; end if; end if;
 select * into r from unimis.hr_attendance_records where tenant_id=p_tenant and employee_id=e.id and work_date=current_date for update;
 if r.id is null then insert into unimis.hr_attendance_records(tenant_id,employee_id,work_date,status,capture_method,attendance_site_id,gps_verified,check_in,check_in_source,latitude,longitude,notes) values(p_tenant,e.id,current_date,'present',case when s.gps_required then 'gps' else 'qr' end,p_site,verified,nowts,case when s.gps_required then 'gps' else 'qr' end,p_latitude,p_longitude,'Passwordless employee attendance') returning * into r; act='check_in';
 elsif r.check_in is null then update unimis.hr_attendance_records set check_in=nowts,status='present',attendance_site_id=p_site,gps_verified=verified,latitude=p_latitude,longitude=p_longitude where id=r.id returning * into r; act='check_in';
 elsif r.check_out is null then update unimis.hr_attendance_records set check_out=nowts,gps_verified=coalesce(verified,gps_verified),check_out_source=case when s.gps_required then 'gps' else 'qr' end where id=r.id returning * into r; act='check_out';
 else raise exception 'Attendance is already complete for today'; end if;
 insert into unimis.hr_attendance_capture_events(tenant_id,employee_id,site_id,attendance_id,event_type,captured_at,capture_method,latitude,longitude,distance_meters,gps_verified) values(p_tenant,e.id,p_site,r.id,act,nowts,case when s.gps_required then 'gps' else 'qr' end,p_latitude,p_longitude,dist,verified);
 update unimis.hr_attendance_devices set last_used_at=now() where id=d.id;
 return jsonb_build_object('message',case when act='check_in' then 'Checked in successfully.' else 'Checked out successfully.' end,'action',act,'gps_verified',verified,'distance_meters',dist);
end $$;

grant execute on function unimis.hr_get_or_create_permanent_site_qr(uuid,uuid) to authenticated;
grant execute on function unimis.hr_regenerate_permanent_site_qr(uuid,uuid) to authenticated;
grant execute on function unimis.hr_create_attendance_device_activation(uuid,uuid) to authenticated;
grant execute on function unimis.hr_redeem_attendance_device_activation(text) to anon,authenticated;
grant execute on function unimis.hr_public_attendance_context(uuid,uuid,text,text) to anon,authenticated;
grant execute on function unimis.hr_public_device_attendance(uuid,uuid,text,text,numeric,numeric) to anon,authenticated;


-- SOURCE 202610160021_hr_operations_performance_training_reports.sql
-- Package 006: HR Operations Completion - attendance controls, performance, training and DSS
alter table unimis.hr_attendance_records add column if not exists approval_status text not null default 'draft';
alter table unimis.hr_attendance_records add column if not exists approved_by uuid;
alter table unimis.hr_attendance_records add column if not exists approved_at timestamptz;
alter table unimis.hr_attendance_records add column if not exists correction_reason text;
alter table unimis.hr_attendance_records drop constraint if exists hr_attendance_records_approval_status_check;
alter table unimis.hr_attendance_records add constraint hr_attendance_records_approval_status_check check(approval_status in ('draft','submitted','approved','rejected'));

create table if not exists unimis.hr_performance_cycles(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references unimis.tenants(id) on delete cascade,
 name text not null,cycle_type text not null default 'annual' check(cycle_type in ('annual','quarterly','probation','project','other')),
 start_date date not null,end_date date not null,status text not null default 'draft' check(status in ('draft','open','closed','archived')),
 created_by uuid default auth.uid(),created_at timestamptz not null default now(),check(end_date>=start_date)
);
create table if not exists unimis.hr_performance_reviews(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references unimis.tenants(id) on delete cascade,
 cycle_id uuid not null references unimis.hr_performance_cycles(id) on delete cascade,employee_id uuid not null references unimis.hr_employees(id) on delete cascade,
 reviewer_employee_id uuid references unimis.hr_employees(id),status text not null default 'draft' check(status in ('draft','submitted','reviewed','completed','cancelled')),
 objective_score numeric(6,2),competency_score numeric(6,2),final_score numeric(6,2),final_rating text,employee_comments text,reviewer_comments text,development_needs text,
 submitted_at timestamptz,completed_at timestamptz,created_by uuid default auth.uid(),created_at timestamptz not null default now(),unique(tenant_id,cycle_id,employee_id)
);
create table if not exists unimis.hr_performance_objectives(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references unimis.tenants(id) on delete cascade,review_id uuid not null references unimis.hr_performance_reviews(id) on delete cascade,
 title text not null,description text,weight numeric(6,2) not null default 0,target text,achievement text,score numeric(6,2),created_at timestamptz not null default now()
);
create table if not exists unimis.hr_performance_competencies(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references unimis.tenants(id) on delete cascade,review_id uuid not null references unimis.hr_performance_reviews(id) on delete cascade,
 competency text not null,weight numeric(6,2) not null default 0,score numeric(6,2),comments text,created_at timestamptz not null default now()
);
create table if not exists unimis.hr_training_programs(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references unimis.tenants(id) on delete cascade,code text not null,name text not null,
 provider text,venue text,start_date date,end_date date,cost numeric(14,2) not null default 0,currency text not null default 'GHS',status text not null default 'planned' check(status in ('planned','open','in_progress','completed','cancelled')),
 certificate_required boolean not null default false,certificate_valid_months integer,notes text,created_by uuid default auth.uid(),created_at timestamptz not null default now(),unique(tenant_id,code)
);
create table if not exists unimis.hr_training_enrollments(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references unimis.tenants(id) on delete cascade,program_id uuid not null references unimis.hr_training_programs(id) on delete cascade,
 employee_id uuid not null references unimis.hr_employees(id) on delete cascade,source text not null default 'hr' check(source in ('hr','performance','employee','manager')),
 performance_review_id uuid references unimis.hr_performance_reviews(id) on delete set null,status text not null default 'nominated' check(status in ('nominated','approved','enrolled','attended','completed','failed','cancelled')),
 result text,score numeric(6,2),certificate_path text,certificate_no text,certificate_expiry date,completion_date date,created_by uuid default auth.uid(),created_at timestamptz not null default now(),unique(tenant_id,program_id,employee_id)
);

do $$ declare t text; begin foreach t in array array['hr_performance_cycles','hr_performance_reviews','hr_performance_objectives','hr_performance_competencies','hr_training_programs','hr_training_enrollments'] loop execute format('alter table unimis.%I enable row level security',t);execute format('drop policy if exists tenant_member_all on unimis.%I',t);execute format('create policy tenant_member_all on unimis.%I for all using (unimis.is_tenant_member(tenant_id)) with check (unimis.is_tenant_member(tenant_id))',t);end loop;end $$;

create or replace function unimis.hr_decide_attendance(p_tenant uuid,p_record uuid,p_decision text,p_reason text default null) returns jsonb language plpgsql security definer set search_path=unimis as $$
begin if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied';end if;if p_decision not in ('approved','rejected') then raise exception 'Invalid decision';end if;update hr_attendance_records set approval_status=p_decision,approved_by=auth.uid(),approved_at=now(),correction_reason=coalesce(p_reason,correction_reason) where tenant_id=p_tenant and id=p_record;if not found then raise exception 'Attendance record not found';end if;return jsonb_build_object('ok',true,'status',p_decision);end $$;
grant execute on function unimis.hr_decide_attendance(uuid,uuid,text,text) to authenticated;
create index if not exists idx_perf_review_tenant_employee on unimis.hr_performance_reviews(tenant_id,employee_id,created_at desc);
create index if not exists idx_training_enrol_tenant_employee on unimis.hr_training_enrollments(tenant_id,employee_id,created_at desc);


-- SOURCE 202610160022_hr_operational_depth_demo_seed.sql
-- Package 006c: HR operational depth + demonstration data
-- Attendance reporting remains sourced from hr_attendance_records/capture_events.

create table if not exists unimis.hr_performance_policies(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.tenants(id) on delete cascade,
 name text not null, effective_from date not null default current_date, effective_to date, active boolean not null default true,
 objective_weight numeric(5,2) not null default 60, competency_weight numeric(5,2) not null default 30,
 attendance_conduct_weight numeric(5,2) not null default 10, satisfactory_score numeric(5,2) not null default 2.50,
 self_assessment text not null default 'optional' check(self_assessment in ('disabled','optional','required')),
 supervisor_required boolean not null default true, second_level_approval boolean not null default true,
 evidence_required boolean not null default true, rating_scale jsonb not null default '[{"min":4.5,"max":5,"label":"Outstanding"},{"min":3.5,"max":4.49,"label":"Exceeds Expectations"},{"min":2.5,"max":3.49,"label":"Meets Expectations"},{"min":1.5,"max":2.49,"label":"Needs Improvement"},{"min":1,"max":1.49,"label":"Unsatisfactory"}]'::jsonb,
 created_by uuid default auth.uid(), created_at timestamptz not null default now(), unique(tenant_id,name,effective_from),
 check(objective_weight+competency_weight+attendance_conduct_weight=100)
);
create table if not exists unimis.hr_performance_improvement_plans(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.tenants(id) on delete cascade,
 employee_id uuid not null references unimis.hr_employees(id) on delete cascade, review_id uuid references unimis.hr_performance_reviews(id) on delete set null,
 title text not null, objectives text not null, actions_support text, start_date date not null, review_date date not null,
 status text not null default 'open' check(status in ('open','on_track','extended','successfully_closed','unsuccessfully_closed')),
 outcome text, created_by uuid default auth.uid(), created_at timestamptz not null default now()
);
alter table unimis.hr_training_programs add column if not exists training_type text default 'professional_development';
alter table unimis.hr_training_programs add column if not exists purpose text;
alter table unimis.hr_training_programs add column if not exists objectives text;
alter table unimis.hr_training_programs add column if not exists delivery_mode text default 'in_person';
alter table unimis.hr_training_programs add column if not exists trainer text;
alter table unimis.hr_training_programs add column if not exists start_time time;
alter table unimis.hr_training_programs add column if not exists end_time time;
alter table unimis.hr_training_programs add column if not exists duration_hours numeric(7,2);
alter table unimis.hr_training_programs add column if not exists target_group text;
alter table unimis.hr_training_programs add column if not exists capacity integer;
alter table unimis.hr_training_programs add column if not exists mandatory boolean not null default false;
alter table unimis.hr_training_programs add column if not exists assessment_required boolean not null default false;
alter table unimis.hr_training_enrollments add column if not exists attendance_percent numeric(5,2);
alter table unimis.hr_training_enrollments add column if not exists feedback text;

do $$ declare t text; begin foreach t in array array['hr_performance_policies','hr_performance_improvement_plans'] loop execute format('alter table unimis.%I enable row level security',t);execute format('drop policy if exists tenant_member_all on unimis.%I',t);execute format('create policy tenant_member_all on unimis.%I for all using(unimis.is_tenant_member(tenant_id)) with check(unimis.is_tenant_member(tenant_id))',t);end loop;end $$;

-- Demonstration data: created per tenant only when enough employee records exist.
do $$
declare t record; e1 uuid; e2 uuid; e3 uuid; cyc uuid; rev uuid; prog1 uuid; prog2 uuid; s uuid;
begin
 for t in select id from unimis.tenants loop
  select id into e1 from unimis.hr_employees where tenant_id=t.id order by created_at limit 1 offset 0;
  select id into e2 from unimis.hr_employees where tenant_id=t.id order by created_at limit 1 offset 1;
  select id into e3 from unimis.hr_employees where tenant_id=t.id order by created_at limit 1 offset 2;
  if e1 is null then continue; end if;
  insert into unimis.hr_performance_policies(tenant_id,name,effective_from) values(t.id,'Standard Performance Policy',date_trunc('year',current_date)::date) on conflict do nothing;
  insert into unimis.hr_performance_cycles(tenant_id,name,cycle_type,start_date,end_date,status)
   values(t.id,'2026 Annual Performance Review','annual',date '2026-01-01',date '2026-12-31','open')
   on conflict do nothing;
  select id into cyc from unimis.hr_performance_cycles where tenant_id=t.id and name='2026 Annual Performance Review' limit 1;
  insert into unimis.hr_performance_reviews(tenant_id,cycle_id,employee_id,status,objective_score,competency_score,final_score,final_rating,reviewer_comments,development_needs,completed_at)
   values(t.id,cyc,e1,'completed',4.2,4.0,4.1,'Exceeds Expectations','Strong delivery and collaboration.','Advanced leadership and reporting skills.',now()-interval '10 days') on conflict do nothing;
  select id into rev from unimis.hr_performance_reviews where tenant_id=t.id and cycle_id=cyc and employee_id=e1;
  if rev is not null and not exists(select 1 from unimis.hr_performance_objectives where review_id=rev) then
   insert into unimis.hr_performance_objectives(tenant_id,review_id,title,description,weight,target,achievement,score) values
    (t.id,rev,'Service delivery','Improve turnaround time',60,'95% on-time completion','96% achieved',4.2);
   insert into unimis.hr_performance_competencies(tenant_id,review_id,competency,weight,score,comments) values
    (t.id,rev,'Teamwork and communication',40,4.0,'Consistently collaborates well.');
  end if;
  if e2 is not null then insert into unimis.hr_performance_reviews(tenant_id,cycle_id,employee_id,status,development_needs) values(t.id,cyc,e2,'submitted','Excel analytics and supervisory skills') on conflict do nothing; end if;

  insert into unimis.hr_training_programs(tenant_id,code,name,training_type,purpose,objectives,provider,trainer,venue,delivery_mode,start_date,end_date,start_time,end_time,duration_hours,target_group,capacity,cost,status,certificate_required,certificate_valid_months,mandatory,assessment_required)
   values(t.id,'TRN-LEAD-26','Supervisory Leadership Essentials','leadership','Prepare emerging supervisors for people-management responsibilities.','Coaching, delegation, feedback and team leadership.','Internal / External Facilitator','HR Development Facilitator','Main Training Room','in_person',current_date-20,current_date-19,'09:00','16:00',12,'Supervisors and high-potential staff',20,2500,'completed',true,24,false,true)
   on conflict(tenant_id,code) do nothing;
  select id into prog1 from unimis.hr_training_programs where tenant_id=t.id and code='TRN-LEAD-26';
  insert into unimis.hr_training_programs(tenant_id,code,name,training_type,purpose,objectives,provider,trainer,venue,delivery_mode,start_date,end_date,start_time,end_time,duration_hours,target_group,capacity,cost,status,certificate_required,mandatory,assessment_required)
   values(t.id,'TRN-SAFE-26','Workplace Safety Refresher','safety','Refresh workplace safety practices and incident prevention.','Hazard identification, reporting and emergency response.','Internal','Safety Officer','Conference Room','in_person',current_date+7,current_date+7,'09:00','13:00',4,'All staff',40,800,'planned',false,true,true)
   on conflict(tenant_id,code) do nothing;
  select id into prog2 from unimis.hr_training_programs where tenant_id=t.id and code='TRN-SAFE-26';
  insert into unimis.hr_training_enrollments(tenant_id,program_id,employee_id,source,status,result,score,attendance_percent,completion_date,certificate_no,certificate_expiry,feedback)
   values(t.id,prog1,e1,'performance','completed','Pass',86,100,current_date-19,'CERT-DEMO-001',current_date+interval '24 months','Useful practical leadership session.') on conflict do nothing;
  if e2 is not null then insert into unimis.hr_training_enrollments(tenant_id,program_id,employee_id,source,status) values(t.id,prog2,e2,'manager','nominated') on conflict do nothing; end if;

  select id into s from unimis.hr_attendance_sites where tenant_id=t.id and active order by created_at limit 1;
  -- ten-day attendance demonstration, preserving any existing real record via ON CONFLICT DO NOTHING.
  insert into unimis.hr_attendance_records(tenant_id,employee_id,work_date,check_in,check_out,status,capture_method,attendance_site_id,gps_verified,late_minutes,overtime_minutes,worked_minutes,approval_status,notes)
  values
   (t.id,e1,current_date-9,(current_date-9)+time '07:55',(current_date-9)+time '17:05','present','manual',s,true,0,5,550,'approved','Demo attendance'),
   (t.id,e1,current_date-8,(current_date-8)+time '08:22',(current_date-8)+time '17:00','late','manual',s,true,12,0,518,'approved','Demo late arrival'),
   (t.id,e1,current_date-7,(current_date-7)+time '07:58',(current_date-7)+time '18:10','present','manual',s,true,0,70,612,'approved','Demo overtime'),
   (t.id,e1,current_date-6,(current_date-6)+time '08:02',null,'present','manual',s,true,0,0,0,'submitted','Demo missing checkout')
  on conflict(tenant_id,employee_id,work_date) do nothing;
  if e2 is not null then
   insert into unimis.hr_attendance_records(tenant_id,employee_id,work_date,check_in,check_out,status,capture_method,attendance_site_id,gps_verified,late_minutes,overtime_minutes,worked_minutes,approval_status,notes) values
    (t.id,e2,current_date-9,(current_date-9)+time '08:04',(current_date-9)+time '17:03','present','manual',s,true,0,3,539,'approved','Demo attendance'),
    (t.id,e2,current_date-8,null,null,'absent','manual',s,null,0,0,0,'submitted','Demo unexplained absence'),
    (t.id,e2,current_date-7,(current_date-7)+time '08:35',(current_date-7)+time '17:00','late','manual',s,true,25,0,505,'approved','Demo late arrival')
   on conflict(tenant_id,employee_id,work_date) do nothing;
  end if;
  if e3 is not null then
   insert into unimis.hr_attendance_records(tenant_id,employee_id,work_date,status,capture_method,attendance_site_id,worked_minutes,approval_status,notes) values
    (t.id,e3,current_date-9,'on_leave','api',s,0,'approved','Demo approved leave'),
    (t.id,e3,current_date-8,'half_day','manual',s,240,'approved','Demo half day')
   on conflict(tenant_id,employee_id,work_date) do nothing;
  end if;
 end loop;
end $$;
create index if not exists idx_perf_policy_tenant_active on unimis.hr_performance_policies(tenant_id,active,effective_from desc);
create index if not exists idx_pip_tenant_employee on unimis.hr_performance_improvement_plans(tenant_id,employee_id,created_at desc);


-- SOURCE 202610160023_configurable_ghana_payroll_2026.sql
-- HRPayrollCore 007: Configurable Ghana statutory payroll engine (effective-dated; not hard-coded in UI)
-- Official seed basis: GRA 2026 PAYE effective 2026-09-01; SSNIT/NPRA 3-tier pension framework and 2026 insurable earnings.

alter table unimis.payroll_profiles
 add column if not exists tax_residency text not null default 'resident',
 add column if not exists pension_tier1_enabled boolean not null default true,
 add column if not exists pension_tier2_enabled boolean not null default true,
 add column if not exists provident_fund_enabled boolean not null default false,
 add column if not exists provident_employee_rate numeric(8,4) not null default 0,
 add column if not exists provident_employer_rate numeric(8,4) not null default 0,
 add column if not exists provident_scheme_name text;

alter table unimis.payroll_run_employees
 add column if not exists taxable_income numeric(14,2) not null default 0,
 add column if not exists chargeable_income numeric(14,2) not null default 0,
 add column if not exists tier1_total numeric(14,2) not null default 0,
 add column if not exists tier2_total numeric(14,2) not null default 0,
 add column if not exists provident_employee numeric(14,2) not null default 0,
 add column if not exists provident_employer numeric(14,2) not null default 0,
 add column if not exists tax_relief numeric(14,2) not null default 0,
 add column if not exists employer_cost numeric(14,2) not null default 0;

alter table unimis.payroll_components
 add column if not exists tax_treatment text not null default 'graduated',
 add column if not exists pre_tax boolean not null default false,
 add column if not exists recurring boolean not null default true;

create table if not exists unimis.payroll_tax_bands(
 id uuid primary key default gen_random_uuid(), tenant_id uuid references unimis.tenants(id) on delete cascade,
 country_code text not null default 'GH', tax_year int not null, frequency text not null default 'monthly',
 band_order int not null, band_amount numeric(14,2), rate numeric(8,4) not null,
 effective_from date not null, effective_to date, active boolean not null default true,
 source_note text, unique(tenant_id,country_code,frequency,effective_from,band_order)
);
create table if not exists unimis.payroll_pension_rules(
 id uuid primary key default gen_random_uuid(), tenant_id uuid references unimis.tenants(id) on delete cascade,
 country_code text not null default 'GH', name text not null, effective_from date not null, effective_to date,
 employee_rate numeric(8,4) not null default 0, employer_rate numeric(8,4) not null default 0,
 tier1_total_rate numeric(8,4) not null default 0, tier2_total_rate numeric(8,4) not null default 0,
 minimum_insurable numeric(14,2), maximum_insurable numeric(14,2), provident_tax_relief_cap_rate numeric(8,4) not null default 0,
 active boolean not null default true, source_note text, unique(tenant_id,country_code,effective_from)
);
create table if not exists unimis.payroll_relief_types(
 id uuid primary key default gen_random_uuid(), tenant_id uuid references unimis.tenants(id) on delete cascade,
 country_code text not null default 'GH', code text not null, name text not null, calculation_type text not null default 'fixed_annual',
 annual_amount numeric(14,2), percent_rate numeric(8,4), max_units int, requires_approval boolean not null default true,
 active boolean not null default true, source_note text, unique(tenant_id,country_code,code)
);
create table if not exists unimis.payroll_employee_reliefs(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.tenants(id) on delete cascade,
 employee_id uuid not null references unimis.hr_employees(id) on delete cascade, relief_type_id uuid not null references unimis.payroll_relief_types(id),
 tax_year int not null, units int not null default 1, approved_annual_amount numeric(14,2), approved boolean not null default false,
 effective_from date not null, effective_to date, reference text, created_at timestamptz not null default now(),
 unique(employee_id,relief_type_id,tax_year)
);
create table if not exists unimis.payroll_adjustments(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.tenants(id) on delete cascade,
 employee_id uuid not null references unimis.hr_employees(id) on delete cascade, period_id uuid references unimis.payroll_periods(id) on delete cascade,
 adjustment_type text not null check(adjustment_type in ('earning','deduction','pre_tax_deduction','loan','arrears','overtime','unpaid_absence','bonus')),
 code text not null, description text not null, amount numeric(14,2) not null, taxable boolean not null default true,
 pensionable boolean not null default false, status text not null default 'approved' check(status in ('draft','pending','approved','rejected')),
 source_module text, source_reference text, created_by uuid references auth.users(id), created_at timestamptz not null default now()
);
create table if not exists unimis.payroll_salary_change_batches(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.tenants(id) on delete cascade,
 batch_no text not null, change_mode text not null check(change_mode in ('percentage','fixed','grade_step','manual')),
 value numeric(14,4), effective_date date not null, reason text, status text not null default 'draft' check(status in ('draft','approved','applied','cancelled')),
 created_by uuid references auth.users(id), approved_by uuid references auth.users(id), created_at timestamptz not null default now(), unique(tenant_id,batch_no)
);
create table if not exists unimis.payroll_salary_change_items(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.tenants(id) on delete cascade,
 batch_id uuid not null references unimis.payroll_salary_change_batches(id) on delete cascade, employee_id uuid not null references unimis.hr_employees(id) on delete cascade,
 old_salary numeric(14,2) not null, new_salary numeric(14,2) not null, unique(batch_id,employee_id)
);

-- RLS
alter table unimis.payroll_tax_bands enable row level security; alter table unimis.payroll_pension_rules enable row level security;
alter table unimis.payroll_relief_types enable row level security; alter table unimis.payroll_employee_reliefs enable row level security;
alter table unimis.payroll_adjustments enable row level security; alter table unimis.payroll_salary_change_batches enable row level security; alter table unimis.payroll_salary_change_items enable row level security;
do $$ declare t text; begin
 foreach t in array array['payroll_tax_bands','payroll_pension_rules','payroll_relief_types'] loop
  execute format('create policy %I on unimis.%I for select to authenticated using (tenant_id is null or unimis.is_tenant_member(tenant_id))',t||'_read_007',t);
  execute format('create policy %I on unimis.%I for all to authenticated using (tenant_id is not null and unimis.has_tenant_role(tenant_id,array[''owner'',''administrator'',''payroll_manager''])) with check (tenant_id is not null and unimis.has_tenant_role(tenant_id,array[''owner'',''administrator'',''payroll_manager'']))',t||'_manage_007',t);
 end loop;
 foreach t in array array['payroll_employee_reliefs','payroll_adjustments','payroll_salary_change_batches','payroll_salary_change_items'] loop
  execute format('create policy %I on unimis.%I for select to authenticated using (unimis.is_tenant_member(tenant_id))',t||'_read_007',t);
  execute format('create policy %I on unimis.%I for all to authenticated using (unimis.has_tenant_role(tenant_id,array[''owner'',''administrator'',''payroll_manager'',''payroll_officer''])) with check (unimis.has_tenant_role(tenant_id,array[''owner'',''administrator'',''payroll_manager'',''payroll_officer'']))',t||'_manage_007',t);
 end loop;
end $$;

-- Official Ghana defaults are global templates (tenant_id NULL); tenants may clone/override later.
insert into unimis.payroll_tax_bands(tenant_id,country_code,tax_year,frequency,band_order,band_amount,rate,effective_from,source_note) values
(null,'GH',2026,'monthly',1,588,0,'2026-09-01','GRA Act 1178 / PAYE 2026'),
(null,'GH',2026,'monthly',2,80,5,'2026-09-01','GRA Act 1178 / PAYE 2026'),
(null,'GH',2026,'monthly',3,100,10,'2026-09-01','GRA Act 1178 / PAYE 2026'),
(null,'GH',2026,'monthly',4,2900,17.5,'2026-09-01','GRA Act 1178 / PAYE 2026'),
(null,'GH',2026,'monthly',5,16000,25,'2026-09-01','GRA Act 1178 / PAYE 2026'),
(null,'GH',2026,'monthly',6,30332,30,'2026-09-01','GRA Act 1178 / PAYE 2026'),
(null,'GH',2026,'monthly',7,null,35,'2026-09-01','GRA Act 1178 / PAYE 2026')
on conflict do nothing;
insert into unimis.payroll_pension_rules(tenant_id,country_code,name,effective_from,employee_rate,employer_rate,tier1_total_rate,tier2_total_rate,minimum_insurable,maximum_insurable,provident_tax_relief_cap_rate,source_note)
values(null,'GH','Ghana 3-Tier Pension 2026','2026-01-01',5.5,13,13.5,5,587.80,69000,16.5,'SSNIT/NPRA 2026') on conflict do nothing;
insert into unimis.payroll_relief_types(tenant_id,country_code,code,name,calculation_type,annual_amount,percent_rate,max_units,source_note) values
(null,'GH','MARRIAGE','Marriage / Responsibility','fixed_annual',1200,null,1,'GRA personal tax relief'),
(null,'GH','CHILD_EDU','Child Education','per_unit_annual',600,null,3,'GRA personal tax relief'),
(null,'GH','DISABILITY','Disability','percent_income',null,25,1,'GRA personal tax relief'),
(null,'GH','OLD_AGE','Old Age (60+)','fixed_annual',1500,null,1,'GRA personal tax relief'),
(null,'GH','AGED_DEP','Aged Dependent Relative','per_unit_annual',1000,null,2,'GRA personal tax relief'),
(null,'GH','EDUCATION','Professional / Technical Education','fixed_annual',2000,null,1,'GRA personal tax relief'),
(null,'GH','MORTGAGE','Qualifying Mortgage Interest','approved_amount',null,null,1,'GRA personal tax relief') on conflict do nothing;

create or replace function unimis.payroll_progressive_tax(p_tenant uuid,p_country text,p_date date,p_chargeable numeric)
returns numeric language plpgsql stable security definer set search_path=unimis as $$
declare rem numeric:=greatest(coalesce(p_chargeable,0),0); ans numeric:=0; b record; use_amt numeric;
begin
 for b in select * from unimis.payroll_tax_bands where country_code=p_country and active and effective_from<=p_date and (effective_to is null or effective_to>=p_date) and (tenant_id=p_tenant or tenant_id is null)
          order by (tenant_id is not null) desc, effective_from desc, band_order loop
  -- prefer one effective rule set; avoid mixing global and tenant overrides with same band order
  if exists(select 1 from unimis.payroll_tax_bands x where x.tenant_id=p_tenant and x.country_code=p_country and x.active and x.effective_from<=p_date and (x.effective_to is null or x.effective_to>=p_date)) and b.tenant_id is null then continue; end if;
  exit when rem<=0; use_amt:=case when b.band_amount is null then rem else least(rem,b.band_amount) end;
  ans:=ans+(use_amt*b.rate/100); rem:=rem-use_amt;
 end loop;
 return round(ans,2);
end $$;
grant execute on function unimis.payroll_progressive_tax(uuid,text,date,numeric) to authenticated;

create or replace function unimis.payroll_create_salary_batch(p_tenant uuid,p_mode text,p_value numeric,p_effective date,p_reason text default null)
returns uuid language plpgsql security definer set search_path=unimis as $$
declare b uuid; bn text; r record; oldv numeric; newv numeric;
begin
 if not unimis.has_tenant_role(p_tenant,array['owner','administrator','payroll_manager','hr_manager']) then raise exception 'Salary change access denied'; end if;
 bn:='SAL-'||to_char(now(),'YYYYMMDDHH24MISS'); insert into unimis.payroll_salary_change_batches(tenant_id,batch_no,change_mode,value,effective_date,reason,created_by) values(p_tenant,bn,p_mode,p_value,p_effective,p_reason,auth.uid()) returning id into b;
 for r in select e.id from unimis.hr_employees e where e.tenant_id=p_tenant and e.employment_status='active' loop
  select coalesce((select sh.new_salary from unimis.hr_salary_history sh where sh.employee_id=r.id and sh.effective_from<=p_effective order by sh.effective_from desc,sh.created_at desc limit 1),(select c.basic_salary from unimis.hr_employment_contracts c where c.employee_id=r.id and c.status='active' order by c.start_date desc limit 1),0) into oldv;
  newv:=case when p_mode='percentage' then round(oldv*(1+p_value/100),2) when p_mode='fixed' then round(oldv+p_value,2) else oldv end;
  insert into unimis.payroll_salary_change_items(tenant_id,batch_id,employee_id,old_salary,new_salary) values(p_tenant,b,r.id,oldv,newv);
 end loop; return b;
end $$;
grant execute on function unimis.payroll_create_salary_batch(uuid,text,numeric,date,text) to authenticated;

create or replace function unimis.payroll_apply_salary_batch(p_tenant uuid,p_batch uuid)
returns void language plpgsql security definer set search_path=unimis as $$
declare r record; d date; rs text;
begin
 if not unimis.has_tenant_role(p_tenant,array['owner','administrator','payroll_manager']) then raise exception 'Salary approval access denied'; end if;
 select effective_date,reason into d,rs from unimis.payroll_salary_change_batches where id=p_batch and tenant_id=p_tenant and status='draft'; if d is null then raise exception 'Draft batch not found'; end if;
 for r in select * from unimis.payroll_salary_change_items where batch_id=p_batch loop
  insert into unimis.hr_salary_history(tenant_id,employee_id,old_salary,new_salary,change_type,reason,effective_from,approved_by,created_by) values(p_tenant,r.employee_id,r.old_salary,r.new_salary,'bulk_adjustment',rs,d,auth.uid(),auth.uid());
  if d<=current_date then update unimis.hr_employment_contracts set basic_salary=r.new_salary where tenant_id=p_tenant and employee_id=r.employee_id and status='active'; end if;
 end loop;
 update unimis.payroll_salary_change_batches set status='applied',approved_by=auth.uid() where id=p_batch;
end $$;
grant execute on function unimis.payroll_apply_salary_batch(uuid,uuid) to authenticated;

-- Replace calculation engine: effective salary + configurable earnings/deductions + Ghana pension/PAYE + approved reliefs/adjustments.
create or replace function unimis.payroll_calculate_run(p_tenant uuid,p_period uuid)
returns uuid language plpgsql security definer set search_path=unimis as $$
declare r uuid; rn text; rec record; re uuid; pend date; country text; pr unimis.payroll_pension_rules%rowtype;
 basic numeric; earn numeric; ded numeric; taxable_extra numeric; pretax numeric; gross numeric; taxable numeric; insurable numeric; emp_pen numeric; er_pen numeric; tier1 numeric; tier2 numeric;
 pf_emp numeric; pf_er numeric; relief numeric; chargeable numeric; tx numeric; net numeric; adjearn numeric; adjded numeric; adjpretax numeric;
begin
 if not unimis.has_tenant_role(p_tenant,array['owner','administrator','payroll_manager','payroll_officer']) then raise exception 'Payroll access denied'; end if;
 select end_date into pend from unimis.payroll_periods where id=p_period and tenant_id=p_tenant; if pend is null then raise exception 'Invalid payroll period'; end if;
 select coalesce(country_code,'GH') into country from unimis.payroll_settings where tenant_id=p_tenant; country:=coalesce(country,'GH');
 select * into pr from unimis.payroll_pension_rules x where x.country_code=country and x.active and x.effective_from<=pend and (x.effective_to is null or x.effective_to>=pend) and (x.tenant_id=p_tenant or x.tenant_id is null) order by (x.tenant_id is not null) desc,x.effective_from desc limit 1;
 if country='GH' and not exists(select 1 from unimis.payroll_tax_bands b where b.country_code='GH' and b.active and b.effective_from<=pend and (b.effective_to is null or b.effective_to>=pend) and (b.tenant_id=p_tenant or b.tenant_id is null)) then raise exception 'No effective PAYE bands configured for payroll period end %',pend; end if;
 select id into r from unimis.payroll_runs where tenant_id=p_tenant and period_id=p_period;
 if r is null then rn:='RUN-'||to_char(pend,'YYYYMM')||'-'||lpad((1+(select count(*) from unimis.payroll_runs where tenant_id=p_tenant))::text,3,'0'); insert into unimis.payroll_runs(tenant_id,period_id,run_no,status,created_by) values(p_tenant,p_period,rn,'draft',auth.uid()) returning id into r;
 else if exists(select 1 from unimis.payroll_runs where id=r and status in ('approved','posted')) then raise exception 'Approved/posted payroll cannot be recalculated'; end if; delete from unimis.payroll_run_employees where run_id=r; end if;
 for rec in select e.*,pp.tax_residency,pp.pension_tier1_enabled,pp.pension_tier2_enabled,pp.provident_fund_enabled,pp.provident_employee_rate,pp.provident_employer_rate from unimis.hr_employees e join unimis.payroll_profiles pp on pp.employee_id=e.id and pp.active where e.tenant_id=p_tenant and e.employment_status='active' loop
  select coalesce((select sh.new_salary from unimis.hr_salary_history sh where sh.employee_id=rec.id and sh.effective_from<=pend order by sh.effective_from desc,sh.created_at desc limit 1),(select c.basic_salary from unimis.hr_employment_contracts c where c.employee_id=rec.id and c.status='active' order by c.start_date desc limit 1),0) into basic;
  select coalesce(sum(case when pc.component_type='earning' then pec.amount else 0 end),0),coalesce(sum(case when pc.component_type='deduction' then pec.amount else 0 end),0),coalesce(sum(case when pc.component_type='earning' and pc.taxable then pec.amount else 0 end),0),coalesce(sum(case when pc.component_type='deduction' and pc.pre_tax then pec.amount else 0 end),0) into earn,ded,taxable_extra,pretax from unimis.payroll_employee_components pec join unimis.payroll_components pc on pc.id=pec.component_id where pec.employee_id=rec.id and pec.tenant_id=p_tenant and pec.effective_from<=pend and (pec.effective_to is null or pec.effective_to>=pend) and pc.code<>'BASIC';
  select coalesce(sum(case when adjustment_type in ('earning','arrears','overtime','bonus') then amount else 0 end),0),coalesce(sum(case when adjustment_type in ('deduction','loan','unpaid_absence') then amount else 0 end),0),coalesce(sum(case when adjustment_type='pre_tax_deduction' then amount else 0 end),0) into adjearn,adjded,adjpretax from unimis.payroll_adjustments where tenant_id=p_tenant and employee_id=rec.id and period_id=p_period and status='approved';
  gross:=basic+earn+adjearn; taxable:=basic+taxable_extra+adjearn; insurable:=least(greatest(basic,coalesce(pr.minimum_insurable,0)),coalesce(pr.maximum_insurable,basic));
  emp_pen:=case when rec.pension_tier1_enabled then round(insurable*coalesce(pr.employee_rate,0)/100,2) else 0 end; er_pen:=case when rec.pension_tier1_enabled then round(insurable*coalesce(pr.employer_rate,0)/100,2) else 0 end;
  tier1:=case when rec.pension_tier1_enabled then round(insurable*coalesce(pr.tier1_total_rate,0)/100,2) else 0 end; tier2:=case when rec.pension_tier2_enabled then round(insurable*coalesce(pr.tier2_total_rate,0)/100,2) else 0 end;
  pf_emp:=case when rec.provident_fund_enabled then round(basic*coalesce(rec.provident_employee_rate,0)/100,2) else 0 end; pf_er:=case when rec.provident_fund_enabled then round(basic*coalesce(rec.provident_employer_rate,0)/100,2) else 0 end;
  select coalesce(sum(case when rt.calculation_type='percent_income' then taxable*coalesce(rt.percent_rate,0)/100 else coalesce(er.approved_annual_amount,case when rt.calculation_type='per_unit_annual' then rt.annual_amount*least(er.units,coalesce(rt.max_units,er.units)) else rt.annual_amount end,0) end)/12,0) into relief from unimis.payroll_employee_reliefs er join unimis.payroll_relief_types rt on rt.id=er.relief_type_id where er.tenant_id=p_tenant and er.employee_id=rec.id and er.approved and er.tax_year=extract(year from pend)::int and er.effective_from<=pend and (er.effective_to is null or er.effective_to>=pend);
  chargeable:=greatest(taxable-emp_pen-least(pf_emp+pf_er,basic*coalesce(pr.provident_tax_relief_cap_rate,0)/100)-pretax-adjpretax-relief,0);
  tx:=case when rec.tax_residency='non_resident' then round(chargeable*25/100,2) else unimis.payroll_progressive_tax(p_tenant,country,pend,chargeable) end;
  net:=gross-emp_pen-pf_emp-tx-ded-adjded-pretax-adjpretax;
  insert into unimis.payroll_run_employees(tenant_id,run_id,employee_id,employee_no,employee_name,basic_salary,other_earnings,gross_pay,employee_pension,employer_pension,tax,other_deductions,net_pay,taxable_income,chargeable_income,tier1_total,tier2_total,provident_employee,provident_employer,tax_relief,employer_cost) values(p_tenant,r,rec.id,rec.employee_no,concat_ws(' ',rec.first_name,rec.other_names,rec.last_name),basic,earn+adjearn,gross,emp_pen,er_pen,tx,ded+adjded+pretax+adjpretax,net,taxable,chargeable,tier1,tier2,pf_emp,pf_er,relief,gross+er_pen+pf_er) returning id into re;
  insert into unimis.payroll_run_items(tenant_id,run_employee_id,component_code,component_name,component_type,amount,taxable,pensionable) values(p_tenant,re,'BASIC','Basic Salary','earning',basic,true,true),(p_tenant,re,'SSNIT-EE','Employee SSNIT','deduction',emp_pen,false,false),(p_tenant,re,'PAYE','PAYE','deduction',tx,false,false);
  if pf_emp>0 then insert into unimis.payroll_run_items(tenant_id,run_employee_id,component_code,component_name,component_type,amount,taxable,pensionable) values(p_tenant,re,'TIER3-EE','Provident Fund Employee','deduction',pf_emp,false,false); end if;
 end loop;
 update unimis.payroll_runs prun set status='calculated',employee_count=x.cnt,gross_total=x.gross,deduction_total=x.ded,employee_pension_total=x.ep,employer_pension_total=x.erp,tax_total=x.tax,net_total=x.net from (select count(*) cnt,coalesce(sum(gross_pay),0) gross,coalesce(sum(other_deductions),0) ded,coalesce(sum(employee_pension),0) ep,coalesce(sum(employer_pension),0) erp,coalesce(sum(tax),0) tax,coalesce(sum(net_pay),0) net from unimis.payroll_run_employees where run_id=r)x where prun.id=r;
 update unimis.payroll_periods set status='review' where id=p_period; return r;
end $$;
grant execute on function unimis.payroll_calculate_run(uuid,uuid) to authenticated;

update unimis.payroll_settings set paye_enabled=true,employee_pension_rate=5.5,employer_pension_rate=13,statutory_note='Ghana statutory templates installed. Effective-dated rules apply; verify future amendments before production.' where country_code='GH';


-- SOURCE 202610160024_payroll_settings_inputs_governance_reports.sql
-- HRPayrollCore 007a: unified settings, employee payroll inputs, separate HR/payroll governance, report builder support

create table if not exists unimis.payroll_deduction_definitions(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.tenants(id) on delete cascade,
 code text not null, name text not null, description text, employee_or_employer text not null default 'employee' check(employee_or_employer in ('employee','employer','both')),
 calculation_method text not null default 'fixed' check(calculation_method in ('fixed','percentage')), default_value numeric(14,4) not null default 0,
 percentage_base text not null default 'basic', pre_tax boolean not null default false, recurring boolean not null default true,
 mandatory boolean not null default false, requires_consent boolean not null default true, requires_approval boolean not null default true,
 minimum_amount numeric(14,2), maximum_amount numeric(14,2), gl_account text, effective_from date not null default current_date, effective_to date,
 active boolean not null default true, created_at timestamptz not null default now(), unique(tenant_id,code)
);
create table if not exists unimis.payroll_employee_deductions(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.tenants(id) on delete cascade,
 employee_id uuid not null references unimis.hr_employees(id) on delete cascade, deduction_id uuid not null references unimis.payroll_deduction_definitions(id),
 amount numeric(14,2), rate numeric(8,4), effective_from date not null, effective_to date, consent_reference text,
 status text not null default 'pending' check(status in ('draft','pending','approved','rejected','inactive')), created_at timestamptz not null default now()
);
create table if not exists unimis.payroll_employee_loans(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.tenants(id) on delete cascade, employee_id uuid not null references unimis.hr_employees(id) on delete cascade,
 loan_type text not null default 'staff_loan', reference text, principal numeric(14,2) not null, installment numeric(14,2) not null, balance numeric(14,2) not null,
 start_period date not null, end_period date, status text not null default 'active' check(status in ('pending','active','settled','suspended','cancelled')), notes text, created_at timestamptz not null default now()
);
create table if not exists unimis.hrpay_approval_events(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.tenants(id) on delete cascade, domain text not null check(domain in ('hr','payroll')),
 workflow_type text not null, reference text, status text not null default 'pending', submitted_by uuid references auth.users(id), approved_by uuid references auth.users(id),
 submitted_label text, approved_label text, notes text, created_at timestamptz not null default now(), decided_at timestamptz
);
create table if not exists unimis.hrpay_audit_events(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.tenants(id) on delete cascade, domain text not null check(domain in ('hr','payroll')),
 action text not null, entity_type text not null, entity_id uuid, entity_reference text, old_data jsonb, new_data jsonb, actor_id uuid references auth.users(id), actor_label text,
 created_at timestamptz not null default now()
);

alter table unimis.payroll_deduction_definitions enable row level security; alter table unimis.payroll_employee_deductions enable row level security; alter table unimis.payroll_employee_loans enable row level security; alter table unimis.hrpay_approval_events enable row level security; alter table unimis.hrpay_audit_events enable row level security;
do $$ declare t text; begin foreach t in array array['payroll_deduction_definitions','payroll_employee_deductions','payroll_employee_loans','hrpay_approval_events','hrpay_audit_events'] loop execute format('create policy %I on unimis.%I for select to authenticated using (unimis.is_tenant_member(tenant_id))',t||'_read_007a',t); execute format('create policy %I on unimis.%I for all to authenticated using (unimis.has_tenant_role(tenant_id,array[''owner'',''administrator'',''payroll_manager'',''payroll_officer''])) with check (unimis.has_tenant_role(tenant_id,array[''owner'',''administrator'',''payroll_manager'',''payroll_officer'']))',t||'_manage_007a',t); end loop; end $$;

-- Seed organization-specific non-statutory deductions for demonstration only; values remain editable.
insert into unimis.payroll_deduction_definitions(tenant_id,code,name,description,calculation_method,default_value,employee_or_employer,requires_consent,requires_approval,effective_from)
select t.id,'WELFARE','Staff Welfare','Agreed staff welfare contribution','fixed',50,'employee',true,true,'2026-10-01' from unimis.tenants t where not exists(select 1 from unimis.payroll_deduction_definitions d where d.tenant_id=t.id and d.code='WELFARE');
insert into unimis.payroll_deduction_definitions(tenant_id,code,name,description,calculation_method,default_value,employee_or_employer,requires_consent,requires_approval,effective_from)
select t.id,'STAFF_ASSOC','Staff Association','Agreed staff association contribution','fixed',25,'employee',true,true,'2026-10-01' from unimis.tenants t where not exists(select 1 from unimis.payroll_deduction_definitions d where d.tenant_id=t.id and d.code='STAFF_ASSOC');

-- Demonstration payroll inputs: pending so payroll approval is visible before calculation.
insert into unimis.payroll_adjustments(tenant_id,employee_id,period_id,adjustment_type,code,description,amount,taxable,pensionable,status,source_module,source_reference)
select e.tenant_id,e.id,p.id,'overtime','OT-DEMO','Approved HR overtime imported for payroll',180,true,false,'pending','attendance','DEMO-OT-001'
from unimis.hr_employees e join lateral(select id from unimis.payroll_periods p where p.tenant_id=e.tenant_id order by start_date desc limit 1)p on true
where e.employment_status='active' and e.employee_no=(select min(e2.employee_no) from unimis.hr_employees e2 where e2.tenant_id=e.tenant_id and e2.employment_status='active')
and not exists(select 1 from unimis.payroll_adjustments a where a.tenant_id=e.tenant_id and a.source_reference='DEMO-OT-001');

-- Separate governance seed demonstrates the two approval/audit streams.
insert into unimis.hrpay_approval_events(tenant_id,domain,workflow_type,reference,status,submitted_label,notes)
select id,'hr','attendance_correction','ATT-DEMO-001','pending','HR Officer','Example HR approval stream' from unimis.tenants t where not exists(select 1 from unimis.hrpay_approval_events a where a.tenant_id=t.id and a.reference='ATT-DEMO-001');
insert into unimis.hrpay_approval_events(tenant_id,domain,workflow_type,reference,status,submitted_label,notes)
select id,'payroll','payroll_input','PAY-DEMO-001','pending','Payroll Officer','Example payroll approval stream' from unimis.tenants t where not exists(select 1 from unimis.hrpay_approval_events a where a.tenant_id=t.id and a.reference='PAY-DEMO-001');
insert into unimis.hrpay_audit_events(tenant_id,domain,action,entity_type,entity_reference,actor_label,new_data)
select id,'payroll','settings_seeded','payroll_settings','007A','System',jsonb_build_object('package','007a','note','Configurable payroll settings enabled') from unimis.tenants t where not exists(select 1 from unimis.hrpay_audit_events a where a.tenant_id=t.id and a.entity_reference='007A');

-- Make tenant PAYE copies safely override global templates. Global templates remain immutable historical references.
create or replace function unimis.payroll_progressive_tax(p_tenant uuid,p_country text,p_date date,p_chargeable numeric)
returns numeric language plpgsql stable security definer set search_path=unimis as $$
declare rem numeric:=greatest(coalesce(p_chargeable,0),0); total numeric:=0; b record; take_amt numeric;
begin
 for b in select * from unimis.payroll_tax_bands x where x.country_code=p_country and x.frequency='monthly' and x.active and x.effective_from<=p_date and (x.effective_to is null or x.effective_to>=p_date) and (x.tenant_id=p_tenant or x.tenant_id is null) order by (x.tenant_id is not null) desc,x.effective_from desc,x.band_order loop
  -- If tenant-specific bands exist for the effective date, ignore global bands.
  if b.tenant_id is null and exists(select 1 from unimis.payroll_tax_bands z where z.tenant_id=p_tenant and z.country_code=p_country and z.frequency='monthly' and z.active and z.effective_from<=p_date and (z.effective_to is null or z.effective_to>=p_date)) then continue; end if;
  exit when rem<=0; take_amt:=case when b.band_amount is null then rem else least(rem,b.band_amount) end; total:=total+(take_amt*b.rate/100); rem:=rem-take_amt;
 end loop; return round(total,2);
end $$;

grant execute on function unimis.payroll_progressive_tax(uuid,text,date,numeric) to authenticated;


-- SOURCE 202610160025_statutory_rules_employee_compensation_relief.sql
-- HRPayrollCore 007b: employee compensation profile, GRA relief workflow, statutory treatment and editable PAYE versions
alter table unimis.payroll_profiles add column if not exists worker_tax_category text not null default 'regular', add column if not exists staff_category text not null default 'senior';
alter table unimis.payroll_employee_reliefs add column if not exists relief_status text not null default 'draft', add column if not exists certificate_no text, add column if not exists approval_date date, add column if not exists supporting_document_path text;

-- Ghana statutory treatment remains data-driven. Values can be superseded with new effective-dated rows.
insert into unimis.payroll_statutory_rules(tenant_id,country_code,authority,rule_type,name,effective_from,calculation_method,configuration,active)
select null,'GH','GRA','casual_worker_tax','Casual worker tax','2026-01-01','flat_rate',jsonb_build_object('rate',5,'basis','payment'),true
where not exists(select 1 from unimis.payroll_statutory_rules where tenant_id is null and country_code='GH' and rule_type='casual_worker_tax' and effective_from='2026-01-01');
insert into unimis.payroll_statutory_rules(tenant_id,country_code,authority,rule_type,name,effective_from,calculation_method,configuration,active)
select null,'GH','GRA','temporary_worker_tax','Resident temporary worker','2026-01-01','graduated',jsonb_build_object('method','same_as_regular_employee'),true
where not exists(select 1 from unimis.payroll_statutory_rules where tenant_id is null and country_code='GH' and rule_type='temporary_worker_tax' and effective_from='2026-01-01');
insert into unimis.payroll_statutory_rules(tenant_id,country_code,authority,rule_type,name,effective_from,calculation_method,configuration,active)
select null,'GH','GRA','non_resident_tax','Non-resident employment tax','2026-01-01','flat_rate',jsonb_build_object('general_rate',25,'bonus_overtime_rate',20),true
where not exists(select 1 from unimis.payroll_statutory_rules where tenant_id is null and country_code='GH' and rule_type='non_resident_tax' and effective_from='2026-01-01');
insert into unimis.payroll_statutory_rules(tenant_id,country_code,authority,rule_type,name,effective_from,calculation_method,configuration,active)
select null,'GH','GRA','bonus_tax','Bonus tax','2026-01-01','special',jsonb_build_object('concessionary_rate',5,'annual_basic_threshold_percent',15,'excess_treatment','graduated'),true
where not exists(select 1 from unimis.payroll_statutory_rules where tenant_id is null and country_code='GH' and rule_type='bonus_tax' and effective_from='2026-01-01');
insert into unimis.payroll_statutory_rules(tenant_id,country_code,authority,rule_type,name,effective_from,calculation_method,configuration,active)
select null,'GH','GRA','overtime_tax','Qualifying junior staff overtime','2026-01-01','special',jsonb_build_object('qualifying_annual_income_limit',18000,'up_to_50_percent_basic_rate',5,'excess_rate',10,'non_resident_rate',20),true
where not exists(select 1 from unimis.payroll_statutory_rules where tenant_id is null and country_code='GH' and rule_type='overtime_tax' and effective_from='2026-01-01');

-- Ghana recurring allowance catalogue. Organizations may edit treatment through their component setup.
insert into unimis.payroll_components(tenant_id,code,name,component_type,taxable,pensionable,calculation_type,default_amount,tax_treatment,pre_tax,recurring,active)
select t.id,v.code,v.name,'earning',true,false,'fixed',0,'graduated',false,true,true from unimis.tenants t cross join (values
('TRANSPORT','Transport Allowance'),('ACCOM','Rent / Accommodation Allowance'),('RISK','Risk Allowance'),('NIGHT','Night Duty Allowance'),('RESP','Responsibility Allowance'),('CHILD-ALLOW','Child Education Allowance'),('HOUSEHELP','House Help Allowance'),('COOK','Cook Allowance'),('GARDEN','Garden Boy Allowance'))v(code,name)
on conflict(tenant_id,code) do nothing;

-- Payroll-ready view supports pre-payroll validation without duplicating employee master data.
create or replace view unimis.payroll_employee_readiness as
select e.tenant_id,e.id employee_id,e.employee_no,concat_ws(' ',e.first_name,e.last_name) employee_name,e.employment_type,
       pp.id is not null payroll_profile_exists,coalesce(c.basic_salary,0) basic_salary,pp.tax_residency,pp.worker_tax_category,pp.tax_number,pp.ssnit_number,
       case when pp.id is null then 'Missing payroll profile' when coalesce(c.basic_salary,0)<=0 then 'Missing salary' when pp.tax_residency='resident' and coalesce(pp.tax_number,'')='' then 'Missing TIN/Ghana Card' else 'Ready' end payroll_status
from unimis.hr_employees e left join unimis.payroll_profiles pp on pp.employee_id=e.id and pp.active
left join lateral(select basic_salary from unimis.hr_employment_contracts c where c.employee_id=e.id and c.status='active' order by c.start_date desc limit 1)c on true;

grant select on unimis.payroll_employee_readiness to authenticated;

-- 007b calculation: effective PAYE version + casual/temporary/resident categories + approved relief consolidation.
create or replace function unimis.payroll_calculate_run(p_tenant uuid,p_period uuid)
returns uuid language plpgsql security definer set search_path=unimis as $$
declare r uuid; rn text; rec record; re uuid; pend date; country text; pr unimis.payroll_pension_rules%rowtype;
 basic numeric; earn numeric; ded numeric; taxable_extra numeric; pretax numeric; gross numeric; taxable numeric; insurable numeric; emp_pen numeric; er_pen numeric; tier1 numeric; tier2 numeric;
 pf_emp numeric; pf_er numeric; relief numeric; chargeable numeric; tx numeric; net numeric; adjearn numeric; adjded numeric; adjpretax numeric; bonus_amt numeric; overtime_amt numeric; normal_adj_earn numeric; ot_tax numeric; bonus_tax numeric; bonus_concession numeric;
begin
 if not unimis.has_tenant_role(p_tenant,array['owner','administrator','payroll_manager','payroll_officer']) then raise exception 'Payroll access denied'; end if;
 select end_date into pend from unimis.payroll_periods where id=p_period and tenant_id=p_tenant; if pend is null then raise exception 'Invalid payroll period'; end if;
 select coalesce(country_code,'GH') into country from unimis.payroll_settings where tenant_id=p_tenant; country:=coalesce(country,'GH');
 select * into pr from unimis.payroll_pension_rules x where x.country_code=country and x.active and x.effective_from<=pend and (x.effective_to is null or x.effective_to>=pend) and (x.tenant_id=p_tenant or x.tenant_id is null) order by (x.tenant_id is not null) desc,x.effective_from desc limit 1;
 if country='GH' and not exists(select 1 from unimis.payroll_tax_bands b where b.country_code='GH' and b.active and b.effective_from<=pend and (b.effective_to is null or b.effective_to>=pend) and (b.tenant_id=p_tenant or b.tenant_id is null)) then raise exception 'No effective PAYE bands configured for payroll period end %',pend; end if;
 select id into r from unimis.payroll_runs where tenant_id=p_tenant and period_id=p_period;
 if r is null then rn:='RUN-'||to_char(pend,'YYYYMM')||'-'||lpad((1+(select count(*) from unimis.payroll_runs where tenant_id=p_tenant))::text,3,'0'); insert into unimis.payroll_runs(tenant_id,period_id,run_no,status,created_by) values(p_tenant,p_period,rn,'draft',auth.uid()) returning id into r;
 else if exists(select 1 from unimis.payroll_runs where id=r and status in ('approved','posted')) then raise exception 'Approved/posted payroll cannot be recalculated'; end if; delete from unimis.payroll_run_employees where run_id=r; end if;
 for rec in select e.*,pp.tax_residency,pp.worker_tax_category,pp.staff_category,pp.pension_tier1_enabled,pp.pension_tier2_enabled,pp.provident_fund_enabled,pp.provident_employee_rate,pp.provident_employer_rate from unimis.hr_employees e join unimis.payroll_profiles pp on pp.employee_id=e.id and pp.active where e.tenant_id=p_tenant and e.employment_status='active' loop
  select coalesce((select sh.new_salary from unimis.hr_salary_history sh where sh.employee_id=rec.id and sh.effective_from<=pend order by sh.effective_from desc,sh.created_at desc limit 1),(select c.basic_salary from unimis.hr_employment_contracts c where c.employee_id=rec.id and c.status='active' order by c.start_date desc limit 1),0) into basic;
  select coalesce(sum(case when pc.component_type='earning' then pec.amount else 0 end),0),coalesce(sum(case when pc.component_type='deduction' then pec.amount else 0 end),0),coalesce(sum(case when pc.component_type='earning' and pc.taxable then pec.amount else 0 end),0),coalesce(sum(case when pc.component_type='deduction' and pc.pre_tax then pec.amount else 0 end),0) into earn,ded,taxable_extra,pretax from unimis.payroll_employee_components pec join unimis.payroll_components pc on pc.id=pec.component_id where pec.employee_id=rec.id and pec.tenant_id=p_tenant and pec.effective_from<=pend and (pec.effective_to is null or pec.effective_to>=pend) and pc.code<>'BASIC';
  select coalesce(sum(case when adjustment_type in ('earning','arrears') then amount else 0 end),0),coalesce(sum(case when adjustment_type in ('deduction','loan','unpaid_absence') then amount else 0 end),0),coalesce(sum(case when adjustment_type='pre_tax_deduction' then amount else 0 end),0),coalesce(sum(case when adjustment_type='bonus' then amount else 0 end),0),coalesce(sum(case when adjustment_type='overtime' then amount else 0 end),0) into normal_adj_earn,adjded,adjpretax,bonus_amt,overtime_amt from unimis.payroll_adjustments where tenant_id=p_tenant and employee_id=rec.id and period_id=p_period and status='approved';
  adjearn:=normal_adj_earn+bonus_amt+overtime_amt; gross:=basic+earn+adjearn; taxable:=basic+taxable_extra+normal_adj_earn;
  insurable:=least(greatest(basic,coalesce(pr.minimum_insurable,0)),coalesce(pr.maximum_insurable,basic)); emp_pen:=case when rec.pension_tier1_enabled then round(insurable*coalesce(pr.employee_rate,0)/100,2) else 0 end; er_pen:=case when rec.pension_tier1_enabled then round(insurable*coalesce(pr.employer_rate,0)/100,2) else 0 end; tier1:=case when rec.pension_tier1_enabled then round(insurable*coalesce(pr.tier1_total_rate,0)/100,2) else 0 end; tier2:=case when rec.pension_tier2_enabled then round(insurable*coalesce(pr.tier2_total_rate,0)/100,2) else 0 end;
  pf_emp:=case when rec.provident_fund_enabled then round(basic*coalesce(rec.provident_employee_rate,0)/100,2) else 0 end; pf_er:=case when rec.provident_fund_enabled then round(basic*coalesce(rec.provident_employer_rate,0)/100,2) else 0 end;
  select coalesce(sum(case when rt.calculation_type='percent_income' then taxable*coalesce(rt.percent_rate,0)/100 else coalesce(er.approved_annual_amount,case when rt.calculation_type='per_unit_annual' then rt.annual_amount*least(er.units,coalesce(rt.max_units,er.units)) else rt.annual_amount end,0) end)/12,0) into relief from unimis.payroll_employee_reliefs er join unimis.payroll_relief_types rt on rt.id=er.relief_type_id where er.tenant_id=p_tenant and er.employee_id=rec.id and er.approved and er.relief_status='active' and er.tax_year=extract(year from pend)::int and er.effective_from<=pend and (er.effective_to is null or er.effective_to>=pend);
  chargeable:=greatest(taxable-emp_pen-least(pf_emp+pf_er,basic*coalesce(pr.provident_tax_relief_cap_rate,0)/100)-pretax-adjpretax-relief,0);
  if rec.worker_tax_category='casual' then tx:=round(gross*0.05,2); ot_tax:=0; bonus_tax:=0;
  else
   tx:=case when rec.tax_residency='non_resident' then round(chargeable*0.25,2) else unimis.payroll_progressive_tax(p_tenant,country,pend,chargeable) end;
   if rec.tax_residency='non_resident' then ot_tax:=round(overtime_amt*0.20,2); bonus_tax:=round(bonus_amt*0.20,2);
   else
    if rec.staff_category='junior' and basic*12<=18000 then ot_tax:=round(least(overtime_amt,basic*0.5)*0.05+greatest(overtime_amt-basic*0.5,0)*0.10,2); else taxable:=taxable+overtime_amt; tx:=unimis.payroll_progressive_tax(p_tenant,country,pend,greatest(chargeable+overtime_amt,0)); ot_tax:=0; end if;
    bonus_concession:=least(bonus_amt,basic*12*0.15); bonus_tax:=round(bonus_concession*0.05,2); if bonus_amt>bonus_concession then tx:=tx+(unimis.payroll_progressive_tax(p_tenant,country,pend,chargeable+(bonus_amt-bonus_concession))-unimis.payroll_progressive_tax(p_tenant,country,pend,chargeable)); end if;
   end if; tx:=round(tx+ot_tax+bonus_tax,2);
  end if;
  net:=gross-emp_pen-pf_emp-tx-ded-adjded-pretax-adjpretax;
  insert into unimis.payroll_run_employees(tenant_id,run_id,employee_id,employee_no,employee_name,basic_salary,other_earnings,gross_pay,employee_pension,employer_pension,tax,other_deductions,net_pay,taxable_income,chargeable_income,tier1_total,tier2_total,provident_employee,provident_employer,tax_relief,employer_cost) values(p_tenant,r,rec.id,rec.employee_no,concat_ws(' ',rec.first_name,rec.other_names,rec.last_name),basic,earn+adjearn,gross,emp_pen,er_pen,tx,ded+adjded+pretax+adjpretax,net,taxable,chargeable,tier1,tier2,pf_emp,pf_er,relief,gross+er_pen+pf_er) returning id into re;
  insert into unimis.payroll_run_items(tenant_id,run_employee_id,component_code,component_name,component_type,amount,taxable,pensionable) values(p_tenant,re,'BASIC','Basic Salary','earning',basic,true,true),(p_tenant,re,'SSNIT-EE','Employee SSNIT','deduction',emp_pen,false,false),(p_tenant,re,'PAYE','PAYE / employment tax','deduction',tx,false,false);
 end loop;
 update unimis.payroll_runs prun set status='calculated',employee_count=x.cnt,gross_total=x.gross,deduction_total=x.ded,employee_pension_total=x.ep,employer_pension_total=x.erp,tax_total=x.tax,net_total=x.net from (select count(*) cnt,coalesce(sum(gross_pay),0) gross,coalesce(sum(other_deductions),0) ded,coalesce(sum(employee_pension),0) ep,coalesce(sum(employer_pension),0) erp,coalesce(sum(tax),0) tax,coalesce(sum(net_pay),0) net from unimis.payroll_run_employees where run_id=r)x where prun.id=r;
 update unimis.payroll_periods set status='review' where id=p_period; return r;
end $$;
grant execute on function unimis.payroll_calculate_run(uuid,uuid) to authenticated;


-- SOURCE 202610160026_payroll_reporting_integrity.sql
-- HRPayrollCore 007c: compensation/report reconciliation and payroll-ready reporting view
create or replace view unimis.payroll_employee_compensation_summary
with (security_invoker=true) as
select e.tenant_id,e.id employee_id,e.employee_no,
       concat_ws(' ',e.first_name,e.other_names,e.last_name) employee_name,
       d.name department_name,
       coalesce(sal.basic_salary,0)::numeric(14,2) basic_salary,
       coalesce(pc.recurring_earnings,0)::numeric(14,2) recurring_earnings,
       coalesce(pc.recurring_deductions,0)::numeric(14,2) recurring_deductions,
       (coalesce(sal.basic_salary,0)+coalesce(pc.recurring_earnings,0))::numeric(14,2) gross_structure,
       (coalesce(sal.basic_salary,0)+coalesce(pc.taxable_earnings,0))::numeric(14,2) taxable_structure,
       coalesce(rel.approved_annual_relief,0)::numeric(14,2) approved_annual_relief,
       round(coalesce(rel.approved_annual_relief,0)/12,2)::numeric(14,2) indicative_monthly_relief,
       (pp.id is not null and coalesce(sal.basic_salary,0)>0) payroll_ready
from unimis.hr_employees e
left join unimis.departments d on d.id=e.department_id
left join unimis.payroll_profiles pp on pp.employee_id=e.id and pp.tenant_id=e.tenant_id and pp.active
left join lateral (
  select coalesce(
    (select sh.new_salary from unimis.hr_salary_history sh where sh.employee_id=e.id and sh.tenant_id=e.tenant_id and sh.effective_from<=current_date order by sh.effective_from desc,sh.created_at desc limit 1),
    (select c.basic_salary from unimis.hr_employment_contracts c where c.employee_id=e.id and c.tenant_id=e.tenant_id and c.status='active' and c.start_date<=current_date order by c.start_date desc limit 1),0) basic_salary
) sal on true
left join lateral (
  select coalesce(sum(case when c.component_type='earning' then ec.amount else 0 end),0) recurring_earnings,
         coalesce(sum(case when c.component_type='deduction' then ec.amount else 0 end),0) recurring_deductions,
         coalesce(sum(case when c.component_type='earning' and c.taxable then ec.amount else 0 end),0) taxable_earnings
  from unimis.payroll_employee_components ec join unimis.payroll_components c on c.id=ec.component_id
  where ec.tenant_id=e.tenant_id and ec.employee_id=e.id and ec.effective_from<=current_date and (ec.effective_to is null or ec.effective_to>=current_date) and c.active
) pc on true
left join lateral (
  select coalesce(sum(er.approved_annual_amount),0) approved_annual_relief
  from unimis.payroll_employee_reliefs er
  where er.tenant_id=e.tenant_id and er.employee_id=e.id and er.approved and er.relief_status='active'
    and er.tax_year=extract(year from current_date)::int and er.effective_from<=current_date and (er.effective_to is null or er.effective_to>=current_date)
) rel on true
where e.employment_status='active';

grant select on unimis.payroll_employee_compensation_summary to authenticated;

comment on view unimis.payroll_employee_compensation_summary is '007c reconciliation view: current effective salary structure and consolidated approved annual relief. Payroll run results remain immutable after posting.';


-- SOURCE 202610160027_employee_edit_payroll_onboarding.sql
-- HRPayrollCore 007d: employee edit + payroll onboarding
create or replace function unimis.hr_update_employee_master(
 p_tenant uuid,p_employee uuid,p_first_name text,p_last_name text,p_email text,p_phone text,
 p_date_of_birth date,p_gender text,p_marital_status text,p_nationality text,p_national_id text,p_address text,
 p_department uuid,p_position uuid,p_employment_type text,p_work_schedule text,p_pay_basis text,
 p_basic_salary numeric,p_salary_effective date,p_ssnit_number text,p_tax_number text,
 p_bank_name text,p_bank_branch text,p_bank_account_name text,p_bank_account_number text,
 p_payment_method text,p_momo_network text,p_momo_number text
) returns jsonb language plpgsql security definer set search_path=unimis as $$
declare old_salary numeric(14,2); result jsonb;
begin
 if not is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 if not exists(select 1 from hr_employees where id=p_employee and tenant_id=p_tenant) then raise exception 'Employee not found'; end if;
 select coalesce((select sh.new_salary from hr_salary_history sh where sh.employee_id=p_employee and sh.effective_from<=coalesce(p_salary_effective,current_date) order by sh.effective_from desc,sh.created_at desc limit 1),(select c.basic_salary from hr_employment_contracts c where c.employee_id=p_employee and c.status='active' order by c.start_date desc limit 1),0) into old_salary;
 update hr_employees set first_name=p_first_name,last_name=p_last_name,email=nullif(p_email,''),phone=nullif(p_phone,''),date_of_birth=p_date_of_birth,gender=nullif(p_gender,''),marital_status=nullif(p_marital_status,''),nationality=nullif(p_nationality,''),national_id=nullif(p_national_id,''),residential_address=nullif(p_address,''),department_id=p_department,position_id=p_position,employment_type=p_employment_type,work_schedule=p_work_schedule,pay_basis=p_pay_basis where id=p_employee and tenant_id=p_tenant;
 update payroll_profiles set ssnit_number=nullif(p_ssnit_number,''),tax_number=nullif(p_tax_number,''),bank_name=nullif(p_bank_name,''),bank_branch=nullif(p_bank_branch,''),bank_account_name=nullif(p_bank_account_name,''),bank_account_number=nullif(p_bank_account_number,''),payment_method=coalesce(nullif(p_payment_method,''),'bank'),momo_network=nullif(p_momo_network,''),momo_number=nullif(p_momo_number,'') where employee_id=p_employee and tenant_id=p_tenant;
 if p_basic_salary is not null and p_basic_salary<>old_salary then
   insert into hr_salary_history(tenant_id,employee_id,old_salary,new_salary,change_type,reason,effective_from,approved_by,created_by) values(p_tenant,p_employee,old_salary,p_basic_salary,case when old_salary=0 then 'initial_salary' else 'manual_adjustment' end,'Employee Master compensation update',coalesce(p_salary_effective,current_date),auth.uid(),auth.uid());
   if coalesce(p_salary_effective,current_date)<=current_date then update hr_employment_contracts set basic_salary=p_basic_salary where tenant_id=p_tenant and employee_id=p_employee and status='active'; end if;
 end if;
 insert into hr_employment_events(tenant_id,employee_id,event_type,effective_date,title,details,created_by) values(p_tenant,p_employee,'profile_update',current_date,'Employee master updated',jsonb_build_object('department_id',p_department,'position_id',p_position,'salary_effective',p_salary_effective),auth.uid());
 result:=jsonb_build_object('ok',true,'old_salary',old_salary,'new_salary',p_basic_salary); return result;
end $$;
grant execute on function unimis.hr_update_employee_master(uuid,uuid,text,text,text,text,date,text,text,text,text,text,uuid,uuid,text,text,text,numeric,date,text,text,text,text,text,text,text,text,text) to authenticated;


-- SOURCE 202610160028_employee_edit_schema_search_fix.sql
-- Package 007d1: correct Employee Master edit mapping.
-- pay_basis belongs to hr_employment_contracts, not hr_employees.
create or replace function unimis.hr_update_employee_master(
 p_tenant uuid,p_employee uuid,p_first_name text,p_last_name text,p_email text,p_phone text,
 p_date_of_birth date,p_gender text,p_marital_status text,p_nationality text,p_national_id text,p_address text,
 p_department uuid,p_position uuid,p_employment_type text,p_work_schedule text,p_pay_basis text,
 p_basic_salary numeric,p_salary_effective date,p_ssnit_number text,p_tax_number text,
 p_bank_name text,p_bank_branch text,p_bank_account_name text,p_bank_account_number text,
 p_payment_method text,p_momo_network text,p_momo_number text
) returns jsonb language plpgsql security definer set search_path=unimis as $$
declare old_salary numeric(14,2); active_contract uuid; result jsonb;
begin
 if not is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 if not exists(select 1 from hr_employees where id=p_employee and tenant_id=p_tenant) then raise exception 'Employee not found'; end if;
 if p_pay_basis not in ('monthly','weekly','daily','hourly') then raise exception 'Invalid pay basis'; end if;
 select id,basic_salary into active_contract,old_salary from hr_employment_contracts where tenant_id=p_tenant and employee_id=p_employee and status='active' order by start_date desc limit 1;
 old_salary:=coalesce((select sh.new_salary from hr_salary_history sh where sh.employee_id=p_employee and sh.effective_from<=coalesce(p_salary_effective,current_date) order by sh.effective_from desc,sh.created_at desc limit 1),old_salary,0);
 update hr_employees set first_name=p_first_name,last_name=p_last_name,email=nullif(p_email,''),phone=nullif(p_phone,''),date_of_birth=p_date_of_birth,gender=nullif(p_gender,''),marital_status=nullif(p_marital_status,''),nationality=nullif(p_nationality,''),national_id=nullif(p_national_id,''),residential_address=nullif(p_address,''),department_id=p_department,position_id=p_position,employment_type=p_employment_type,work_schedule=p_work_schedule where id=p_employee and tenant_id=p_tenant;
 if active_contract is not null then
   update hr_employment_contracts set contract_type=p_employment_type,pay_basis=p_pay_basis,pay_frequency=p_pay_basis where id=active_contract;
 end if;
 update payroll_profiles set ssnit_number=nullif(p_ssnit_number,''),tax_number=nullif(p_tax_number,''),bank_name=nullif(p_bank_name,''),bank_branch=nullif(p_bank_branch,''),bank_account_name=nullif(p_bank_account_name,''),bank_account_number=nullif(p_bank_account_number,''),payment_method=coalesce(nullif(p_payment_method,''),'bank'),momo_network=nullif(p_momo_network,''),momo_number=nullif(p_momo_number,'') where employee_id=p_employee and tenant_id=p_tenant;
 if p_basic_salary is not null and p_basic_salary<>old_salary then
   insert into hr_salary_history(tenant_id,employee_id,old_salary,new_salary,change_type,reason,effective_from,approved_by,created_by) values(p_tenant,p_employee,old_salary,p_basic_salary,case when old_salary=0 then 'initial' else 'manual' end,'Employee Master compensation update',coalesce(p_salary_effective,current_date),auth.uid(),auth.uid());
   if active_contract is not null and coalesce(p_salary_effective,current_date)<=current_date then update hr_employment_contracts set basic_salary=p_basic_salary where id=active_contract; end if;
 end if;
 insert into hr_employment_events(tenant_id,employee_id,event_type,effective_date,title,details,created_by) values(p_tenant,p_employee,'profile_update',current_date,'Employee master updated',jsonb_build_object('department_id',p_department,'position_id',p_position,'pay_basis',p_pay_basis,'salary_effective',p_salary_effective),auth.uid());
 result:=jsonb_build_object('ok',true,'old_salary',old_salary,'new_salary',p_basic_salary,'pay_basis',p_pay_basis); return result;
end $$;
grant execute on function unimis.hr_update_employee_master(uuid,uuid,text,text,text,text,date,text,text,text,text,text,uuid,uuid,text,text,text,numeric,date,text,text,text,text,text,text,text,text,text) to authenticated;


-- SOURCE 202610160029_configurable_compensation_components.sql
-- HRPayrollCore 007e: configurable compensation components and agreed deductions
alter table unimis.payroll_components
 add column if not exists employee_or_employer text not null default 'employee',
 add column if not exists requires_consent boolean not null default false,
 add column if not exists requires_approval boolean not null default false,
 add column if not exists effective_from date not null default current_date,
 add column if not exists effective_to date,
 add column if not exists description text;

do $$ begin
  if not exists(select 1 from pg_constraint where conname='payroll_components_employee_or_employer_chk') then
    alter table unimis.payroll_components add constraint payroll_components_employee_or_employer_chk check(employee_or_employer in ('employee','employer','both'));
  end if;
end $$;

-- Organization-editable agreed deductions. These are ordinary payroll components, so the existing calculation engine consumes them.
insert into unimis.payroll_components(tenant_id,code,name,component_type,taxable,pensionable,calculation_type,default_amount,tax_treatment,pre_tax,recurring,active,employee_or_employer,requires_consent,requires_approval,effective_from,description)
select t.id,v.code,v.name,'deduction',false,false,'fixed',v.amount,'post_tax',false,true,true,'employee',v.consent,true,'2026-10-01',v.description
from unimis.tenants t cross join (values
 ('WELFARE','Staff Welfare',50::numeric,true,'Agreed staff welfare contribution'),
 ('STAFF_ASSOC','Staff Association',25::numeric,true,'Agreed staff association contribution'),
 ('UNION','Union Dues',0::numeric,true,'Union or professional association dues'),
 ('CREDIT_UNION','Credit Union',0::numeric,true,'Employee credit union contribution'),
 ('STAFF_INS','Staff Insurance',0::numeric,true,'Employee agreed insurance deduction'),
 ('STAFF_BUS','Staff Transport',0::numeric,true,'Staff transport recovery')
) v(code,name,amount,consent,description)
on conflict(tenant_id,code) do update set component_type='deduction',recurring=true,active=true,employee_or_employer='employee',requires_consent=excluded.requires_consent,requires_approval=true,description=excluded.description;

-- Make common recurring earnings explicit and organization-editable.
update unimis.payroll_components set recurring=true, employee_or_employer='employee', requires_approval=true
where code in ('TRANSPORT','ACCOM','RISK','NIGHT','RESP','CHILD-ALLOW','HOUSEHELP','COOK','GARDEN') and component_type='earning';

-- Overtime and bonus are variable inputs, not recurring compensation components.
update unimis.payroll_components set recurring=false where code in ('OT','OVERTIME','BONUS');

notify pgrst, 'reload schema';


-- SOURCE 202610160030_unified_payroll_component_catalogue.sql
-- HRPayrollCore 007e2: unified payroll component catalogue
-- The old payroll_deduction_definitions table is retained only for historical compatibility.
-- New configuration is performed exclusively through payroll_components.

-- Migrate any organization-specific deductions created in the old settings form (e.g. T & T)
-- into the universal component catalogue without assigning them to any employee.
insert into unimis.payroll_components(
  tenant_id,code,name,component_type,taxable,pensionable,calculation_type,default_amount,
  tax_treatment,pre_tax,recurring,active,employee_or_employer,requires_consent,requires_approval,
  effective_from,effective_to,description
)
select d.tenant_id, upper(replace(trim(d.code),' ','_')), d.name,
       'deduction',
       false,false,d.calculation_method,d.default_value,
       case when d.pre_tax then 'pre_tax' else 'post_tax' end,d.pre_tax,d.recurring,d.active,
       d.employee_or_employer,d.requires_consent,d.requires_approval,d.effective_from,d.effective_to,d.description
from unimis.payroll_deduction_definitions d
on conflict(tenant_id,code) do update set
  name=excluded.name,
  component_type=excluded.component_type,
  calculation_type=excluded.calculation_type,
  default_amount=excluded.default_amount,
  pre_tax=excluded.pre_tax,
  recurring=excluded.recurring,
  active=excluded.active,
  employee_or_employer=excluded.employee_or_employer,
  requires_consent=excluded.requires_consent,
  requires_approval=excluded.requires_approval,
  effective_from=excluded.effective_from,
  effective_to=excluded.effective_to,
  description=coalesce(excluded.description,unimis.payroll_components.description);

-- Safety rule: a component existing/enabled in Settings never means it is assigned to all staff.
-- Employee application remains explicit in payroll_employee_components.

insert into unimis.hrpay_audit_events(tenant_id,domain,action,entity_type,entity_reference,actor_label,new_data)
select t.id,'payroll','component_catalogue_unified','payroll_settings','007E2','System',
       jsonb_build_object('package','007e2','rule','Enabled catalogue components require explicit employee assignment')
from unimis.tenants t
where not exists(select 1 from unimis.hrpay_audit_events a where a.tenant_id=t.id and a.entity_reference='007E2');

notify pgrst, 'reload schema';


-- SOURCE 202610170032_functional_payroll_setup_configs.sql
-- HRPayrollCore 008c: functional payroll setup destinations
create table if not exists unimis.payroll_setup_configs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references unimis.tenants(id) on delete cascade,
  section text not null,
  config jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id, section)
);
alter table unimis.payroll_setup_configs enable row level security;
drop policy if exists payroll_setup_configs_select on unimis.payroll_setup_configs;
create policy payroll_setup_configs_select on unimis.payroll_setup_configs for select using (
 exists(select 1 from unimis.tenant_memberships tm where tm.tenant_id=payroll_setup_configs.tenant_id and tm.user_id=auth.uid() and tm.status='active')
);
drop policy if exists payroll_setup_configs_write on unimis.payroll_setup_configs;
create policy payroll_setup_configs_write on unimis.payroll_setup_configs for all using (
 exists(select 1 from unimis.tenant_memberships tm where tm.tenant_id=payroll_setup_configs.tenant_id and tm.user_id=auth.uid() and tm.status='active' and tm.role in ('owner','administrator','accountant','payroll_manager','payroll_officer','finance_manager'))
) with check (
 exists(select 1 from unimis.tenant_memberships tm where tm.tenant_id=payroll_setup_configs.tenant_id and tm.user_id=auth.uid() and tm.status='active' and tm.role in ('owner','administrator','accountant','payroll_manager','payroll_officer','finance_manager'))
);
create index if not exists payroll_setup_configs_tenant_section_idx on unimis.payroll_setup_configs(tenant_id,section);


-- SOURCE 202610170033_payroll_payment_liabilities.sql
-- HRPayrollCore 008d: payroll settlement/remittance register and accounting handoff foundation
create table if not exists unimis.payroll_payment_liabilities (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references unimis.tenants(id) on delete cascade,
 payroll_run_id uuid null references unimis.payroll_runs(id) on delete cascade,
 liability_type text not null check (liability_type in ('employee_salary','paye','ssnit','tier2','tier3','third_party','other')),
 payee_name text not null,
 payee_reference text null,
 amount numeric(14,2) not null default 0,
 amount_paid numeric(14,2) not null default 0,
 balance numeric(14,2) not null default 0,
 due_date date null,
 payment_date date null,
 payment_method text null,
 payment_reference text null,
 evidence_path text null,
 status text not null default 'unpaid' check (status in ('unpaid','part_paid','paid','reversed')),
 accounting_status text not null default 'not_posted' check (accounting_status in ('not_posted','ready','posted','reversed')),
 accounting_reference text null,
 notes text null,
 created_by uuid null references auth.users(id),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create unique index if not exists uq_payroll_liability_run_type_payee on unimis.payroll_payment_liabilities(payroll_run_id,liability_type,payee_name) where payroll_run_id is not null;
alter table unimis.payroll_payment_liabilities enable row level security;
drop policy if exists payroll_payment_liabilities_member on unimis.payroll_payment_liabilities;
create policy payroll_payment_liabilities_member on unimis.payroll_payment_liabilities for all to authenticated using (unimis.is_tenant_member(tenant_id)) with check (unimis.is_tenant_member(tenant_id));
comment on table unimis.payroll_payment_liabilities is 'Settlement register for salaries, PAYE, pension and third-party payroll liabilities; suitable for accounting handoff.';


-- SOURCE 202610170034_payroll_review_complete_liabilities.sql
-- HRPayrollCore 008e: complete posted-payroll liabilities for settlement/remittance.
-- Idempotent: recreates liabilities for a run only when none exist.
create or replace function unimis.payroll_generate_payment_liabilities(p_tenant uuid,p_run uuid)
returns integer language plpgsql security definer set search_path=unimis as $$
declare r record; n integer:=0; v numeric;
begin
  if not exists(select 1 from tenant_memberships m where m.tenant_id=p_tenant and m.user_id=auth.uid() and m.status='active' and m.role in ('owner','administrator','accountant','finance_manager','payroll_manager','payroll_officer')) then raise exception 'Payroll access denied'; end if;
  select pr.*,pp.end_date into r from payroll_runs pr left join payroll_periods pp on pp.id=pr.period_id where pr.id=p_run and pr.tenant_id=p_tenant;
  if not found then raise exception 'Payroll run not found'; end if;
  if r.status<>'posted' then raise exception 'Payroll must be posted before liabilities can be generated'; end if;
  if exists(select 1 from payroll_payment_liabilities where tenant_id=p_tenant and payroll_run_id=p_run) then return 0; end if;

  select coalesce(sum(net_pay),0) into v from payroll_run_employees where run_id=p_run;
  if v>0 then insert into payroll_payment_liabilities(tenant_id,payroll_run_id,liability_type,payee_name,amount,balance,status,due_date) values(p_tenant,p_run,'employee_salary','Employees / Salary Payable',v,v,'unpaid',r.end_date); n:=n+1; end if;
  select coalesce(sum(tax),0) into v from payroll_run_employees where run_id=p_run;
  if v>0 then insert into payroll_payment_liabilities(tenant_id,payroll_run_id,liability_type,payee_name,amount,balance,status,due_date) values(p_tenant,p_run,'paye','GRA / PAYE Payable',v,v,'unpaid',r.end_date); n:=n+1; end if;
  select coalesce(sum(tier1_total),0) into v from payroll_run_employees where run_id=p_run;
  if v>0 then insert into payroll_payment_liabilities(tenant_id,payroll_run_id,liability_type,payee_name,amount,balance,status,due_date) values(p_tenant,p_run,'ssnit','SSNIT / Tier 1 Payable',v,v,'unpaid',r.end_date); n:=n+1; end if;
  select coalesce(sum(tier2_total),0) into v from payroll_run_employees where run_id=p_run;
  if v>0 then insert into payroll_payment_liabilities(tenant_id,payroll_run_id,liability_type,payee_name,amount,balance,status,due_date) values(p_tenant,p_run,'tier2','Tier 2 Trustee Payable',v,v,'unpaid',r.end_date); n:=n+1; end if;
  select coalesce(sum(provident_employee),0) into v from payroll_run_employees where run_id=p_run;
  if v>0 then insert into payroll_payment_liabilities(tenant_id,payroll_run_id,liability_type,payee_name,amount,balance,status,due_date) values(p_tenant,p_run,'tier3','Tier 3 / Provident Fund Payable',v,v,'unpaid',r.end_date); n:=n+1; end if;
  select coalesce(sum(other_deductions),0) into v from payroll_run_employees where run_id=p_run;
  if v>0 then insert into payroll_payment_liabilities(tenant_id,payroll_run_id,liability_type,payee_name,amount,balance,status,due_date) values(p_tenant,p_run,'third_party','Third-party / Agreed Deductions Payable',v,v,'unpaid',r.end_date); n:=n+1; end if;
  return n;
end $$;
grant execute on function unimis.payroll_generate_payment_liabilities(uuid,uuid) to authenticated;


-- SOURCE 202610170035_reset_payroll_run_for_testing.sql
-- HRPayrollCore 008e3: safe development/test reset for a posted payroll run.
-- This is intentionally explicit and auditable. It refuses to reset any run
-- for which a payment/remittance amount has already been recorded.

create table if not exists unimis.payroll_test_reset_audit (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  payroll_run_id uuid not null,
  run_no text,
  previous_status text,
  reset_by uuid default auth.uid(),
  reset_at timestamptz not null default now(),
  note text not null default 'Reset payroll run for controlled workflow testing'
);

alter table unimis.payroll_test_reset_audit enable row level security;

drop policy if exists payroll_test_reset_audit_select on unimis.payroll_test_reset_audit;
create policy payroll_test_reset_audit_select on unimis.payroll_test_reset_audit
for select using (
  exists (select 1 from unimis.tenant_memberships tm
          where tm.tenant_id=payroll_test_reset_audit.tenant_id
            and tm.user_id=auth.uid() and tm.status='active')
);

create or replace function unimis.payroll_reset_run_for_testing(p_tenant uuid, p_run uuid)
returns jsonb
language plpgsql
security definer
set search_path=unimis
as $$
declare
  v_run unimis.payroll_runs%rowtype;
  v_paid numeric := 0;
  v_liabilities integer := 0;
begin
  if not exists (
    select 1 from unimis.tenant_memberships tm
    where tm.tenant_id=p_tenant and tm.user_id=auth.uid() and tm.status='active'
      and tm.role in ('owner','administrator','accountant','payroll_manager','payroll_officer','finance_manager')
  ) then
    raise exception 'Payroll access denied';
  end if;

  select * into v_run from unimis.payroll_runs
   where id=p_run and tenant_id=p_tenant for update;
  if not found then raise exception 'Payroll run not found'; end if;
  if v_run.status <> 'posted' then
    raise exception 'Only a posted payroll run can be reset with this testing control';
  end if;

  if to_regclass('unimis.payroll_payment_liabilities') is not null then
    execute 'select coalesce(sum(coalesce(amount_paid,0)),0) from unimis.payroll_payment_liabilities where tenant_id=$1 and payroll_run_id=$2'
      into v_paid using p_tenant,p_run;
    if v_paid > 0 then
      raise exception 'Reset blocked: this payroll has recorded payments/remittances totaling GH₵%. Reverse those payments first.', v_paid;
    end if;
    execute 'select count(*) from unimis.payroll_payment_liabilities where tenant_id=$1 and payroll_run_id=$2'
      into v_liabilities using p_tenant,p_run;
    execute 'delete from unimis.payroll_payment_liabilities where tenant_id=$1 and payroll_run_id=$2'
      using p_tenant,p_run;
  end if;

  insert into unimis.payroll_test_reset_audit(tenant_id,payroll_run_id,run_no,previous_status)
  values(p_tenant,p_run,v_run.run_no,v_run.status);

  delete from unimis.payroll_run_employees where run_id=p_run;

  update unimis.payroll_runs
     set status='draft', employee_count=0, gross_total=0, tax_total=0, net_total=0,
         employee_pension_total=0, employer_pension_total=0
   where id=p_run and tenant_id=p_tenant;

  -- Re-open the linked period when the schema uses the standard period_id column.
  update unimis.payroll_periods p set status='open'
   where p.id=v_run.period_id and p.tenant_id=p_tenant;

  return jsonb_build_object(
    'ok',true,'run_no',v_run.run_no,'status','draft',
    'cleared_liabilities',v_liabilities,
    'message','Payroll reset to Draft. Start with Calculate / Recalculate.'
  );
end;
$$;

grant execute on function unimis.payroll_reset_run_for_testing(uuid,uuid) to authenticated;


-- SOURCE 202610170036_universal_payroll_rules_foundation.sql
-- HRPayrollCore 009 - Universal Payroll Rules & Workforce Earnings Engine Foundation
-- Adds effective-dated worker payroll classification, Tier 3 participation mode,
-- earnings-source definitions, and pension-age review flags without hard-coding
-- a person's statutory treatment from age alone.

create table if not exists unimis.payroll_worker_classifications (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references unimis.tenants(id) on delete cascade,
  employee_id uuid not null references unimis.hr_employees(id) on delete cascade,
  employment_relationship text not null default 'regular'
    check (employment_relationship in ('regular','fixed_term','temporary','casual','part_time','intern','national_service','locum','consultant','commission_employee','other')),
  tax_treatment text not null default 'standard_paye'
    check (tax_treatment in ('standard_paye','casual_worker','temporary_worker','non_resident','contractor_wht','special','exempt')),
  pension_status text not null default 'active_contributor'
    check (pension_status in ('active_contributor','pensioner_retiree','exempt','not_applicable','legacy_special','pending_review')),
  tier3_participation text not null default 'organization_default'
    check (tier3_participation in ('organization_default','participating','not_participating')),
  pay_frequency text not null default 'monthly'
    check (pay_frequency in ('monthly','fortnightly','weekly','daily','hourly','per_shift','per_assignment')),
  effective_from date not null default current_date,
  effective_to date,
  reason text,
  evidence_reference text,
  approved boolean not null default false,
  approved_by uuid,
  approved_at timestamptz,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (effective_to is null or effective_to >= effective_from)
);

create index if not exists idx_payroll_worker_classifications_employee
  on unimis.payroll_worker_classifications(tenant_id, employee_id, effective_from desc);
create unique index if not exists uq_payroll_worker_classification_active
  on unimis.payroll_worker_classifications(tenant_id, employee_id)
  where effective_to is null;

alter table unimis.payroll_worker_classifications enable row level security;
drop policy if exists payroll_worker_classifications_member on unimis.payroll_worker_classifications;
create policy payroll_worker_classifications_member on unimis.payroll_worker_classifications
  for all using (unimis.is_tenant_member(tenant_id))
  with check (unimis.is_tenant_member(tenant_id));

-- Explicit Tier 3 mode. Existing provident_fund_enabled/rates remain for compatibility.
alter table unimis.payroll_profiles
  add column if not exists tier3_participation_mode text not null default 'organization_default';

do $$ begin
  alter table unimis.payroll_profiles
    add constraint payroll_profiles_tier3_participation_mode_chk
    check (tier3_participation_mode in ('organization_default','participating','not_participating'));
exception when duplicate_object then null; end $$;

-- Reusable source catalogue: defines WHERE a payroll amount originates.
create table if not exists unimis.payroll_earning_sources (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references unimis.tenants(id) on delete cascade,
  code text not null,
  name text not null,
  source_type text not null
    check (source_type in ('compensation','recurring_component','attendance','leave','roster','overtime','commission','loan','manual_period_input','arrears','external_import','api','other')),
  description text,
  requires_approval boolean not null default true,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tenant_id, code)
);

alter table unimis.payroll_earning_sources enable row level security;
drop policy if exists payroll_earning_sources_member on unimis.payroll_earning_sources;
create policy payroll_earning_sources_member on unimis.payroll_earning_sources
  for all using (unimis.is_tenant_member(tenant_id))
  with check (unimis.is_tenant_member(tenant_id));

-- Maps a configured payroll component to its normal source. No amount is created here.
create table if not exists unimis.payroll_component_sources (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references unimis.tenants(id) on delete cascade,
  component_id uuid not null references unimis.payroll_components(id) on delete cascade,
  earning_source_id uuid not null references unimis.payroll_earning_sources(id) on delete cascade,
  priority integer not null default 100,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique(tenant_id, component_id, earning_source_id)
);

alter table unimis.payroll_component_sources enable row level security;
drop policy if exists payroll_component_sources_member on unimis.payroll_component_sources;
create policy payroll_component_sources_member on unimis.payroll_component_sources
  for all using (unimis.is_tenant_member(tenant_id))
  with check (unimis.is_tenant_member(tenant_id));

-- Configurable review milestones. A milestone raises a review flag only; it never
-- automatically stops SSNIT/Tier 2/Tier 3 or changes tax treatment.
create table if not exists unimis.payroll_pension_review_rules (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references unimis.tenants(id) on delete cascade,
  country_code text not null default 'GH',
  review_age integer not null default 55 check (review_age between 18 and 100),
  label text not null default 'Pension status review',
  message text not null default 'Employee has reached a configured pension milestone. Review contributor/pension status before payroll.',
  active boolean not null default true,
  effective_from date not null default current_date,
  effective_to date,
  created_at timestamptz not null default now(),
  unique(tenant_id, country_code, review_age, effective_from)
);

alter table unimis.payroll_pension_review_rules enable row level security;
drop policy if exists payroll_pension_review_rules_member on unimis.payroll_pension_review_rules;
create policy payroll_pension_review_rules_member on unimis.payroll_pension_review_rules
  for all using (unimis.is_tenant_member(tenant_id))
  with check (unimis.is_tenant_member(tenant_id));

-- Seed source definitions for every tenant. Safe to rerun.
insert into unimis.payroll_earning_sources(tenant_id,code,name,source_type,description,requires_approval)
select t.id,v.code,v.name,v.source_type,v.description,v.requires_approval
from unimis.tenants t
cross join (values
 ('COMPENSATION','Employee compensation','compensation','Basic salary/base rate from the effective compensation profile.',false),
 ('RECURRING','Recurring assignment','recurring_component','Effective-dated recurring earnings or deductions assigned to an employee.',true),
 ('ATTENDANCE','Attendance','attendance','Approved attendance-derived payable time or exception.',true),
 ('LEAVE','Leave','leave','Approved paid/unpaid leave effect.',true),
 ('ROSTER','Roster / shift','roster','Approved scheduled shift or shift premium.',true),
 ('OVERTIME','Overtime','overtime','Approved overtime quantity/value.',true),
 ('COMMISSION','Commission','commission','Approved sales/activity commission.',true),
 ('LOAN','Loan schedule','loan','Scheduled employee loan repayment.',true),
 ('PERIOD_INPUT','Manual period input','manual_period_input','One-off payroll input such as bonus or adjustment.',true),
 ('ARREARS','Arrears','arrears','Approved prior-period arrears or correction.',true),
 ('EXTERNAL','External import / API','external_import','Approved value imported from a host system or external source.',true)
) as v(code,name,source_type,description,requires_approval)
on conflict (tenant_id,code) do nothing;

-- Default Ghana review milestone for existing tenants. This is a REVIEW trigger,
-- not a statutory deduction decision.
insert into unimis.payroll_pension_review_rules(tenant_id,country_code,review_age,label,message,effective_from)
select id,'GH',55,'Pension status review','Employee has reached age 55. Review pension/contributor status; do not automatically stop statutory deductions.',current_date
from unimis.tenants
on conflict (tenant_id,country_code,review_age,effective_from) do nothing;

comment on table unimis.payroll_worker_classifications is 'Effective-dated payroll classification. Employment relationship, tax treatment and pension status are intentionally separate.';
comment on column unimis.payroll_worker_classifications.pension_status is 'Controls pension treatment; age alone must never silently change deductions.';
comment on column unimis.payroll_worker_classifications.tier3_participation is 'Organization default, explicit participation, or explicit non-participation.';
comment on table unimis.payroll_earning_sources is 'Defines the origin of payroll values so one payroll engine can consume compensation, attendance, roster, commission, loans and manual inputs.';


-- SOURCE 202610170037_payroll_classification_workspace.sql
-- HRPayrollCore 009a - Payroll Classification & Pension Status Workspace
-- Safe effective-dated classification setter and employee Tier 3 metadata.

alter table unimis.payroll_profiles
  add column if not exists provident_member_reference text,
  add column if not exists provident_effective_from date,
  add column if not exists provident_effective_to date;

insert into unimis.payroll_pension_review_rules
  (tenant_id,country_code,review_age,label,message,active,effective_from)
select t.id,'GH',55,'Pension status review',
       'Employee has reached a configured pension milestone. Review contributor/pension status before payroll. No deduction is changed automatically.',
       true,current_date
from unimis.tenants t
where not exists (
  select 1 from unimis.payroll_pension_review_rules r
  where r.tenant_id=t.id and r.country_code='GH' and r.active=true
);

create or replace function unimis.payroll_set_worker_classification(
  p_tenant uuid,
  p_employee uuid,
  p_employment_relationship text,
  p_tax_treatment text,
  p_pension_status text,
  p_tier3_participation text,
  p_pay_frequency text,
  p_effective_from date,
  p_reason text default null,
  p_evidence_reference text default null
) returns uuid
language plpgsql
security definer
set search_path=unimis
as $$
declare
  v_id uuid;
  v_existing unimis.payroll_worker_classifications%rowtype;
begin
  if not unimis.is_tenant_member(p_tenant) then
    raise exception 'Tenant access denied';
  end if;
  if not exists(select 1 from unimis.hr_employees where id=p_employee and tenant_id=p_tenant) then
    raise exception 'Employee does not belong to this tenant';
  end if;

  select * into v_existing
  from unimis.payroll_worker_classifications
  where tenant_id=p_tenant and employee_id=p_employee and effective_to is null
  order by effective_from desc limit 1;

  if v_existing.id is not null then
    if p_effective_from < v_existing.effective_from then
      raise exception 'New effective date cannot be earlier than the current classification effective date';
    elsif p_effective_from = v_existing.effective_from then
      update unimis.payroll_worker_classifications
      set employment_relationship=p_employment_relationship,
          tax_treatment=p_tax_treatment,
          pension_status=p_pension_status,
          tier3_participation=p_tier3_participation,
          pay_frequency=p_pay_frequency,
          reason=p_reason,
          evidence_reference=p_evidence_reference,
          updated_at=now()
      where id=v_existing.id
      returning id into v_id;
      return v_id;
    else
      update unimis.payroll_worker_classifications
      set effective_to=p_effective_from-1, updated_at=now()
      where id=v_existing.id;
    end if;
  end if;

  insert into unimis.payroll_worker_classifications(
    tenant_id,employee_id,employment_relationship,tax_treatment,pension_status,
    tier3_participation,pay_frequency,effective_from,reason,evidence_reference
  ) values(
    p_tenant,p_employee,p_employment_relationship,p_tax_treatment,p_pension_status,
    p_tier3_participation,p_pay_frequency,p_effective_from,p_reason,p_evidence_reference
  ) returning id into v_id;

  update unimis.payroll_profiles
  set tier3_participation_mode=p_tier3_participation
  where tenant_id=p_tenant and employee_id=p_employee;

  return v_id;
end $$;

grant execute on function unimis.payroll_set_worker_classification(
  uuid,uuid,text,text,text,text,text,date,text,text
) to authenticated;


-- SOURCE 202610180001_integrated_payroll_engine_review.sql
-- HRPayrollCore 009d - integrated payroll engine + review breakdown
-- Uses effective worker classification and Tier 3 organization setup during calculation.
-- Adds review snapshot columns; historical posted runs are not recalculated.

alter table unimis.payroll_run_employees
 add column if not exists allowances_total numeric(14,2) not null default 0,
 add column if not exists overtime_total numeric(14,2) not null default 0,
 add column if not exists bonus_total numeric(14,2) not null default 0,
 add column if not exists arrears_other_earnings numeric(14,2) not null default 0,
 add column if not exists loan_deductions numeric(14,2) not null default 0,
 add column if not exists other_nonloan_deductions numeric(14,2) not null default 0;

create or replace function unimis.payroll_calculate_run(p_tenant uuid,p_period uuid)
returns uuid language plpgsql security definer set search_path=unimis as $$
declare r uuid; rn text; rec record; re uuid; pend date; country text; pr unimis.payroll_pension_rules%rowtype;
 basic numeric; earn numeric; ded numeric; taxable_extra numeric; pretax numeric; gross numeric; taxable numeric; insurable numeric; emp_pen numeric; er_pen numeric; tier1 numeric; tier2 numeric;
 pf_emp numeric; pf_er numeric; relief numeric; cfg jsonb; cls record; org_pf_emp numeric; org_pf_er numeric; pf_emp_rate numeric; pf_er_rate numeric; tier3_ok boolean; rel text; pension_mode text; tax_mode text; allowances numeric; loans numeric; chargeable numeric; tx numeric; net numeric; adjearn numeric; adjded numeric; adjpretax numeric; bonus_amt numeric; overtime_amt numeric; normal_adj_earn numeric; ot_tax numeric; bonus_tax numeric; bonus_concession numeric;
begin
 if not unimis.has_tenant_role(p_tenant,array['owner','administrator','payroll_manager','payroll_officer']) then raise exception 'Payroll access denied'; end if;
 select end_date into pend from unimis.payroll_periods where id=p_period and tenant_id=p_tenant; if pend is null then raise exception 'Invalid payroll period'; end if;
 select coalesce(country_code,'GH') into country from unimis.payroll_settings where tenant_id=p_tenant; country:=coalesce(country,'GH');
 select * into pr from unimis.payroll_pension_rules x where x.country_code=country and x.active and x.effective_from<=pend and (x.effective_to is null or x.effective_to>=pend) and (x.tenant_id=p_tenant or x.tenant_id is null) order by (x.tenant_id is not null) desc,x.effective_from desc limit 1;
 select coalesce(config,'{}'::jsonb) into cfg from unimis.payroll_setup_configs where tenant_id=p_tenant and lower(section)='tier3' limit 1; cfg:=coalesce(cfg,'{}'::jsonb);
 if country='GH' and not exists(select 1 from unimis.payroll_tax_bands b where b.country_code='GH' and b.active and b.effective_from<=pend and (b.effective_to is null or b.effective_to>=pend) and (b.tenant_id=p_tenant or b.tenant_id is null)) then raise exception 'No effective PAYE bands configured for payroll period end %',pend; end if;
 select id into r from unimis.payroll_runs where tenant_id=p_tenant and period_id=p_period;
 if r is null then rn:='RUN-'||to_char(pend,'YYYYMM')||'-'||lpad((1+(select count(*) from unimis.payroll_runs where tenant_id=p_tenant))::text,3,'0'); insert into unimis.payroll_runs(tenant_id,period_id,run_no,status,created_by) values(p_tenant,p_period,rn,'draft',auth.uid()) returning id into r;
 else if exists(select 1 from unimis.payroll_runs where id=r and status in ('approved','posted')) then raise exception 'Approved/posted payroll cannot be recalculated'; end if; delete from unimis.payroll_run_employees where run_id=r; end if;
 for rec in select e.*,pp.tax_residency,pp.worker_tax_category,pp.staff_category,pp.pension_tier1_enabled,pp.pension_tier2_enabled,pp.provident_fund_enabled,pp.provident_employee_rate,pp.provident_employer_rate,pp.tier3_participation_mode,pp.provident_effective_from,pp.provident_effective_to from unimis.hr_employees e join unimis.payroll_profiles pp on pp.employee_id=e.id and pp.active where e.tenant_id=p_tenant and e.employment_status='active' loop
  select c.* into cls from unimis.payroll_worker_classifications c where c.tenant_id=p_tenant and c.employee_id=rec.id and c.effective_from<=pend and (c.effective_to is null or c.effective_to>=pend) order by c.effective_from desc limit 1;
  rel:=coalesce(cls.employment_relationship,case when lower(coalesce(rec.employment_type,'regular'))='permanent' then 'regular' else lower(coalesce(rec.employment_type,'regular')) end);
  tax_mode:=coalesce(cls.tax_treatment,case when tax_mode='non_resident' then 'non_resident' when rec.worker_tax_category='casual' then 'casual_worker' when rec.worker_tax_category='temporary' then 'temporary_worker' else 'standard_paye' end);
  pension_mode:=coalesce(cls.pension_status,'active_contributor');
  if pension_mode='pending_review' then raise exception 'Payroll blocked: % (%) pension status is Pending Review',concat_ws(' ',rec.first_name,rec.last_name),rec.employee_no; end if;
  select coalesce((select sh.new_salary from unimis.hr_salary_history sh where sh.employee_id=rec.id and sh.effective_from<=pend order by sh.effective_from desc,sh.created_at desc limit 1),(select c.basic_salary from unimis.hr_employment_contracts c where c.employee_id=rec.id and c.status='active' order by c.start_date desc limit 1),0) into basic;
  select coalesce(sum(case when pc.component_type='earning' then pec.amount else 0 end),0),coalesce(sum(case when pc.component_type='deduction' then pec.amount else 0 end),0),coalesce(sum(case when pc.component_type='earning' and pc.taxable then pec.amount else 0 end),0),coalesce(sum(case when pc.component_type='deduction' and pc.pre_tax then pec.amount else 0 end),0) into earn,ded,taxable_extra,pretax from unimis.payroll_employee_components pec join unimis.payroll_components pc on pc.id=pec.component_id where pec.employee_id=rec.id and pec.tenant_id=p_tenant and pec.effective_from<=pend and (pec.effective_to is null or pec.effective_to>=pend) and pc.code<>'BASIC';
  select coalesce(sum(case when adjustment_type in ('earning','arrears') then amount else 0 end),0),coalesce(sum(case when adjustment_type in ('deduction','loan','unpaid_absence') then amount else 0 end),0),coalesce(sum(case when adjustment_type='pre_tax_deduction' then amount else 0 end),0),coalesce(sum(case when adjustment_type='bonus' then amount else 0 end),0),coalesce(sum(case when adjustment_type='overtime' then amount else 0 end),0) into normal_adj_earn,adjded,adjpretax,bonus_amt,overtime_amt from unimis.payroll_adjustments where tenant_id=p_tenant and employee_id=rec.id and period_id=p_period and status='approved';
  allowances:=earn; adjearn:=normal_adj_earn+bonus_amt+overtime_amt; gross:=basic+earn+adjearn; taxable:=basic+taxable_extra+normal_adj_earn;
  insurable:=least(greatest(basic,coalesce(pr.minimum_insurable,0)),coalesce(pr.maximum_insurable,basic)); emp_pen:=case when pension_mode in ('active_contributor','legacy_special') and rec.pension_tier1_enabled then round(insurable*coalesce(pr.employee_rate,0)/100,2) else 0 end; er_pen:=case when pension_mode in ('active_contributor','legacy_special') and rec.pension_tier1_enabled then round(insurable*coalesce(pr.employer_rate,0)/100,2) else 0 end; tier1:=case when pension_mode in ('active_contributor','legacy_special') and rec.pension_tier1_enabled then round(insurable*coalesce(pr.tier1_total_rate,0)/100,2) else 0 end; tier2:=case when pension_mode in ('active_contributor','legacy_special') and rec.pension_tier2_enabled then round(insurable*coalesce(pr.tier2_total_rate,0)/100,2) else 0 end;
  org_pf_emp:=coalesce(nullif(cfg->>'employee_default_rate','')::numeric,0); org_pf_er:=coalesce(nullif(cfg->>'employer_default_rate','')::numeric,0);
  pf_emp_rate:=case when coalesce((cfg->>'employee_rate_variable')::boolean,false) and coalesce(rec.provident_employee_rate,0)>0 and rec.provident_employee_rate<>org_pf_emp then rec.provident_employee_rate else org_pf_emp end;
  pf_er_rate:=case when coalesce((cfg->>'employer_rate_variable')::boolean,false) and coalesce(rec.provident_employer_rate,0)>0 and rec.provident_employer_rate<>org_pf_er then rec.provident_employer_rate else org_pf_er end;
  tier3_ok:=coalesce((cfg->>'enabled')::boolean,false) and coalesce(cls.tier3_participation,rec.tier3_participation_mode,'not_participating')='participating' and
    case when pension_mode='pensioner_retiree' then coalesce((cfg->>'eligible_pensioner')::boolean,false) when rel='regular' then coalesce((cfg->>'eligible_regular')::boolean,true) when rel='fixed_term' then coalesce((cfg->>'eligible_fixed_term')::boolean,true) when rel='part_time' then coalesce((cfg->>'eligible_part_time')::boolean,true) when rel='temporary' then coalesce((cfg->>'eligible_temporary')::boolean,false) when rel='casual' then coalesce((cfg->>'eligible_casual')::boolean,false) when rel='intern' then coalesce((cfg->>'eligible_intern')::boolean,false) when rel='national_service' then coalesce((cfg->>'eligible_national_service')::boolean,false) when rel='locum' then coalesce((cfg->>'eligible_locum')::boolean,false) when rel='consultant' then coalesce((cfg->>'eligible_consultant')::boolean,false) else false end
    and (rec.provident_effective_from is null or rec.provident_effective_from<=pend) and (rec.provident_effective_to is null or rec.provident_effective_to>=pend);
  pf_emp:=case when tier3_ok then round(basic*pf_emp_rate/100,2) else 0 end; pf_er:=case when tier3_ok then round(basic*pf_er_rate/100,2) else 0 end;
  select coalesce(sum(case when rt.calculation_type='percent_income' then taxable*coalesce(rt.percent_rate,0)/100 else coalesce(er.approved_annual_amount,case when rt.calculation_type='per_unit_annual' then rt.annual_amount*least(er.units,coalesce(rt.max_units,er.units)) else rt.annual_amount end,0) end)/12,0) into relief from unimis.payroll_employee_reliefs er join unimis.payroll_relief_types rt on rt.id=er.relief_type_id where er.tenant_id=p_tenant and er.employee_id=rec.id and er.approved and er.relief_status='active' and er.tax_year=extract(year from pend)::int and er.effective_from<=pend and (er.effective_to is null or er.effective_to>=pend);
  chargeable:=greatest(taxable-emp_pen-least(pf_emp+pf_er,basic*coalesce(pr.provident_tax_relief_cap_rate,0)/100)-pretax-adjpretax-relief,0);
  if tax_mode='exempt' then tx:=0; ot_tax:=0; bonus_tax:=0;
  elsif tax_mode='casual_worker' then tx:=round(gross*0.05,2); ot_tax:=0; bonus_tax:=0;
  else
   tx:=case when tax_mode='non_resident' then round(chargeable*0.25,2) else unimis.payroll_progressive_tax(p_tenant,country,pend,chargeable) end;
   if tax_mode='non_resident' then ot_tax:=round(overtime_amt*0.20,2); bonus_tax:=round(bonus_amt*0.20,2);
   else
    if rec.staff_category='junior' and basic*12<=18000 then ot_tax:=round(least(overtime_amt,basic*0.5)*0.05+greatest(overtime_amt-basic*0.5,0)*0.10,2); else taxable:=taxable+overtime_amt; tx:=unimis.payroll_progressive_tax(p_tenant,country,pend,greatest(chargeable+overtime_amt,0)); ot_tax:=0; end if;
    bonus_concession:=least(bonus_amt,basic*12*0.15); bonus_tax:=round(bonus_concession*0.05,2); if bonus_amt>bonus_concession then tx:=tx+(unimis.payroll_progressive_tax(p_tenant,country,pend,chargeable+(bonus_amt-bonus_concession))-unimis.payroll_progressive_tax(p_tenant,country,pend,chargeable)); end if;
   end if; tx:=round(tx+ot_tax+bonus_tax,2);
  end if;
  select coalesce(sum(amount),0) into loans from unimis.payroll_adjustments where tenant_id=p_tenant and employee_id=rec.id and period_id=p_period and status='approved' and adjustment_type='loan';
  net:=gross-emp_pen-pf_emp-tx-ded-adjded-pretax-adjpretax;
  insert into unimis.payroll_run_employees(tenant_id,run_id,employee_id,employee_no,employee_name,basic_salary,other_earnings,gross_pay,employee_pension,employer_pension,tax,other_deductions,net_pay,taxable_income,chargeable_income,tier1_total,tier2_total,provident_employee,provident_employer,tax_relief,employer_cost,allowances_total,overtime_total,bonus_total,arrears_other_earnings,loan_deductions,other_nonloan_deductions) values(p_tenant,r,rec.id,rec.employee_no,concat_ws(' ',rec.first_name,rec.other_names,rec.last_name),basic,earn+adjearn,gross,emp_pen,er_pen,tx,ded+adjded+pretax+adjpretax,net,taxable,chargeable,tier1,tier2,pf_emp,pf_er,relief,gross+er_pen+pf_er,allowances,overtime_amt,bonus_amt,normal_adj_earn,loans,greatest(ded+adjded+pretax+adjpretax-loans,0)) returning id into re;
  insert into unimis.payroll_run_items(tenant_id,run_employee_id,component_code,component_name,component_type,amount,taxable,pensionable) values(p_tenant,re,'BASIC','Basic Salary','earning',basic,true,true),(p_tenant,re,'SSNIT-EE','Employee SSNIT','deduction',emp_pen,false,false),(p_tenant,re,'PAYE','PAYE / employment tax','deduction',tx,false,false);
  if pf_emp>0 then insert into unimis.payroll_run_items(tenant_id,run_employee_id,component_code,component_name,component_type,amount,taxable,pensionable) values(p_tenant,re,'TIER3-EE','Tier 3 / PF Employee','deduction',pf_emp,false,false); end if;
  if relief>0 then insert into unimis.payroll_run_items(tenant_id,run_employee_id,component_code,component_name,component_type,amount,taxable,pensionable) values(p_tenant,re,'RELIEF','Approved Tax Relief','relief',relief,false,false); end if;
 end loop;
 update unimis.payroll_runs prun set status='calculated',employee_count=x.cnt,gross_total=x.gross,deduction_total=x.ded,employee_pension_total=x.ep,employer_pension_total=x.erp,tax_total=x.tax,net_total=x.net from (select count(*) cnt,coalesce(sum(gross_pay),0) gross,coalesce(sum(other_deductions),0) ded,coalesce(sum(employee_pension),0) ep,coalesce(sum(employer_pension),0) erp,coalesce(sum(tax),0) tax,coalesce(sum(net_pay),0) net from unimis.payroll_run_employees where run_id=r)x where prun.id=r;
 update unimis.payroll_periods set status='review' where id=p_period; return r;
end $$;
grant execute on function unimis.payroll_calculate_run(uuid,uuid) to authenticated;


-- SOURCE 202610180002_staff_payroll_statements.sql
create table if not exists unimis.payroll_staff_statements(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.tenants(id) on delete cascade,
 payroll_run_id uuid not null references unimis.payroll_runs(id) on delete cascade,
 run_employee_id uuid not null references unimis.payroll_run_employees(id) on delete cascade,
 employee_id uuid not null references unimis.hr_employees(id), amount_due numeric(14,2) not null default 0,
 amount_paid numeric(14,2) not null default 0,balance numeric(14,2) not null default 0,
 status text not null default 'unpaid' check(status in('unpaid','part_paid','paid')),
 last_payment_date date,last_payment_reference text,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 unique(run_employee_id));
create table if not exists unimis.payroll_staff_payment_transactions(
 id uuid primary key default gen_random_uuid(),tenant_id uuid not null references unimis.tenants(id) on delete cascade,
 statement_id uuid not null references unimis.payroll_staff_statements(id) on delete cascade,
 amount numeric(14,2) not null check(amount>0),payment_date date not null default current_date,reference text not null,
 recorded_by uuid default auth.uid(),created_at timestamptz not null default now());
alter table unimis.payroll_staff_statements enable row level security;alter table unimis.payroll_staff_payment_transactions enable row level security;
drop policy if exists staff_statements_tenant on unimis.payroll_staff_statements;create policy staff_statements_tenant on unimis.payroll_staff_statements for all to authenticated using(unimis.is_tenant_member(tenant_id)) with check(unimis.is_tenant_member(tenant_id));
drop policy if exists staff_payment_tx_tenant on unimis.payroll_staff_payment_transactions;create policy staff_payment_tx_tenant on unimis.payroll_staff_payment_transactions for all to authenticated using(unimis.is_tenant_member(tenant_id)) with check(unimis.is_tenant_member(tenant_id));
create or replace function unimis.payroll_generate_staff_statements(p_tenant uuid,p_run uuid) returns integer language plpgsql security definer set search_path=unimis as $$declare n integer;begin if not unimis.has_tenant_role(p_tenant,array['owner','administrator','accountant','finance_manager','payroll_manager','payroll_officer']) then raise exception 'Payroll access denied';end if;if not exists(select 1 from payroll_runs where id=p_run and tenant_id=p_tenant and status='posted') then raise exception 'Payroll must be posted before staff statements are generated';end if;insert into payroll_staff_statements(tenant_id,payroll_run_id,run_employee_id,employee_id,amount_due,amount_paid,balance,status) select p_tenant,p_run,r.id,r.employee_id,r.net_pay,0,r.net_pay,'unpaid' from payroll_run_employees r where r.run_id=p_run on conflict(run_employee_id) do update set amount_due=excluded.amount_due,balance=greatest(excluded.amount_due-payroll_staff_statements.amount_paid,0),status=case when payroll_staff_statements.amount_paid>=excluded.amount_due then 'paid' when payroll_staff_statements.amount_paid>0 then 'part_paid' else 'unpaid' end,updated_at=now();get diagnostics n=row_count;return n;end$$;
create or replace function unimis.payroll_record_staff_payment(p_tenant uuid,p_statement uuid,p_amount numeric,p_reference text) returns jsonb language plpgsql security definer set search_path=unimis as $$declare s payroll_staff_statements%rowtype;np numeric;nb numeric;begin if not unimis.has_tenant_role(p_tenant,array['owner','administrator','accountant','finance_manager','payroll_manager','payroll_officer']) then raise exception 'Payroll access denied';end if;select * into s from payroll_staff_statements where id=p_statement and tenant_id=p_tenant for update;if s.id is null then raise exception 'Staff payroll statement not found';end if;if p_amount<=0 or p_amount>s.balance then raise exception 'Payment must be greater than zero and not exceed outstanding balance';end if;insert into payroll_staff_payment_transactions(tenant_id,statement_id,amount,reference) values(p_tenant,p_statement,p_amount,p_reference);np:=s.amount_paid+p_amount;nb:=greatest(s.amount_due-np,0);update payroll_staff_statements set amount_paid=np,balance=nb,status=case when nb=0 then 'paid' else 'part_paid' end,last_payment_date=current_date,last_payment_reference=p_reference,updated_at=now() where id=s.id;return jsonb_build_object('ok',true,'paid',np,'balance',nb);end$$;
grant execute on function unimis.payroll_generate_staff_statements(uuid,uuid) to authenticated;grant execute on function unimis.payroll_record_staff_payment(uuid,uuid,numeric,text) to authenticated;


-- SOURCE 202610220001_009f_complete_demo_seed.sql
-- HRPayrollCore 009f: repeatable complete demo seed for fresh local installations.
-- Runs only when an Owner/Administrator clicks Load complete demo data.
create or replace function unimis.seed_hrpayroll_demo(p_tenant uuid)
returns void language plpgsql security definer set search_path=unimis as $$
declare
 b uuid; le uuid; d1 uuid; d2 uuid; d3 uuid; g1 uuid; g2 uuid; p1 uuid; p2 uuid; p3 uuid; pg uuid;
 e1 uuid; e2 uuid; e3 uuid; e4 uuid; c uuid; rt uuid; per uuid; cyc uuid;
 mstart date:=date_trunc('month',current_date)::date; mend date:=(date_trunc('month',current_date)+interval '1 month - 1 day')::date;
begin
 if not unimis.has_tenant_role(p_tenant,array['owner','administrator']) then raise exception 'Owner/admin required'; end if;
 select id into b from unimis.branches where tenant_id=p_tenant order by created_at limit 1;
 if b is null then
   select id into le from unimis.legal_entities where tenant_id=p_tenant order by created_at limit 1;
   if le is null then insert into unimis.legal_entities(tenant_id,name) select p_tenant,name from unimis.tenants where id=p_tenant returning id into le; end if;
   insert into unimis.branches(tenant_id,legal_entity_id,code,name,city) values(p_tenant,le,'HQ','Head Office','Kumasi') returning id into b;
 end if;
 select id into pg from unimis.payroll_pay_groups where tenant_id=p_tenant and active order by created_at limit 1;
 if pg is null then insert into unimis.payroll_pay_groups(tenant_id,code,name,frequency) values(p_tenant,'MONTHLY','Monthly Payroll','monthly') returning id into pg; end if;

 insert into unimis.departments(tenant_id,branch_id,code,name) values
 (p_tenant,b,'ADM','Administration'),(p_tenant,b,'FIN','Finance'),(p_tenant,b,'OPS','Operations')
 on conflict(tenant_id,code) do update set name=excluded.name,branch_id=coalesce(unimis.departments.branch_id,excluded.branch_id);
 select id into d1 from unimis.departments where tenant_id=p_tenant and code='ADM'; select id into d2 from unimis.departments where tenant_id=p_tenant and code='FIN'; select id into d3 from unimis.departments where tenant_id=p_tenant and code='OPS';
 insert into unimis.hr_job_grades(tenant_id,code,name,min_salary,max_salary) values
 (p_tenant,'G1','Officer',2500,6000),(p_tenant,'G2','Senior Officer',4500,9000)
 on conflict(tenant_id,code) do update set name=excluded.name,min_salary=excluded.min_salary,max_salary=excluded.max_salary;
 select id into g1 from unimis.hr_job_grades where tenant_id=p_tenant and code='G1'; select id into g2 from unimis.hr_job_grades where tenant_id=p_tenant and code='G2';
 insert into unimis.hr_positions(tenant_id,department_id,grade_id,code,title) values
 (p_tenant,d1,g1,'ADMIN-OFF','Administrative Officer'),(p_tenant,d2,g2,'ACCT-OFF','Accounts Officer'),(p_tenant,d3,g1,'OPS-OFF','Operations Officer')
 on conflict(tenant_id,code) do update set title=excluded.title,department_id=excluded.department_id,grade_id=excluded.grade_id;
 select id into p1 from unimis.hr_positions where tenant_id=p_tenant and code='ADMIN-OFF'; select id into p2 from unimis.hr_positions where tenant_id=p_tenant and code='ACCT-OFF'; select id into p3 from unimis.hr_positions where tenant_id=p_tenant and code='OPS-OFF';

 insert into unimis.hr_employees(tenant_id,employee_no,first_name,last_name,email,branch_id,department_id,position_id,hire_date,employment_type,work_schedule,pension_status)
 values(p_tenant,'EMP001','Ama','Mensah','ama.mensah@example.test',b,d1,p1,current_date-500,'regular','full_time','active_contributor')
 on conflict(tenant_id,employee_no) do update set first_name='Ama',last_name='Mensah',department_id=d1,position_id=p1,employment_type='regular',employment_status='active' returning id into e1;
 if e1 is null then select id into e1 from unimis.hr_employees where tenant_id=p_tenant and employee_no='EMP001'; end if;
 insert into unimis.hr_employees(tenant_id,employee_no,first_name,last_name,email,branch_id,department_id,position_id,hire_date,employment_type,work_schedule,pension_status)
 values(p_tenant,'EMP002','Kwame','Asare','kwame.asare@example.test',b,d2,p2,current_date-420,'regular','full_time','active_contributor')
 on conflict(tenant_id,employee_no) do update set first_name='Kwame',last_name='Asare',department_id=d2,position_id=p2,employment_type='regular',employment_status='active' returning id into e2;
 if e2 is null then select id into e2 from unimis.hr_employees where tenant_id=p_tenant and employee_no='EMP002'; end if;
 insert into unimis.hr_employees(tenant_id,employee_no,first_name,last_name,email,branch_id,department_id,position_id,hire_date,employment_type,work_schedule,pension_status)
 values(p_tenant,'EMP003','Esi','Agyeman','esi.agyeman@example.test',b,d3,p3,current_date-180,'fixed_term','full_time','active_contributor')
 on conflict(tenant_id,employee_no) do update set first_name='Esi',last_name='Agyeman',department_id=d3,position_id=p3,employment_type='fixed_term',employment_status='active' returning id into e3;
 if e3 is null then select id into e3 from unimis.hr_employees where tenant_id=p_tenant and employee_no='EMP003'; end if;
 insert into unimis.hr_employees(tenant_id,employee_no,first_name,last_name,email,branch_id,department_id,position_id,hire_date,employment_type,work_schedule,pension_status)
 values(p_tenant,'EMP004','Kojo','Owusu','kojo.owusu@example.test',b,d3,p3,current_date-90,'casual','part_time','not_applicable')
 on conflict(tenant_id,employee_no) do update set first_name='Kojo',last_name='Owusu',department_id=d3,position_id=p3,employment_type='casual',employment_status='active' returning id into e4;
 if e4 is null then select id into e4 from unimis.hr_employees where tenant_id=p_tenant and employee_no='EMP004'; end if;

 -- Current contracts: do not duplicate on repeat runs.
 if not exists(select 1 from unimis.hr_employment_contracts where tenant_id=p_tenant and employee_id=e1 and status='active') then insert into unimis.hr_employment_contracts(tenant_id,employee_id,contract_type,start_date,basic_salary,pay_frequency,status) values(p_tenant,e1,'regular',current_date-500,4200,'monthly','active'); end if;
 if not exists(select 1 from unimis.hr_employment_contracts where tenant_id=p_tenant and employee_id=e2 and status='active') then insert into unimis.hr_employment_contracts(tenant_id,employee_id,contract_type,start_date,basic_salary,pay_frequency,status) values(p_tenant,e2,'regular',current_date-420,5000,'monthly','active'); end if;
 if not exists(select 1 from unimis.hr_employment_contracts where tenant_id=p_tenant and employee_id=e3 and status='active') then insert into unimis.hr_employment_contracts(tenant_id,employee_id,contract_type,start_date,end_date,basic_salary,pay_frequency,status) values(p_tenant,e3,'fixed_term',current_date-180,current_date+185,3200,'monthly','active'); end if;
 if not exists(select 1 from unimis.hr_employment_contracts where tenant_id=p_tenant and employee_id=e4 and status='active') then insert into unimis.hr_employment_contracts(tenant_id,employee_id,contract_type,start_date,basic_salary,pay_frequency,status) values(p_tenant,e4,'casual',current_date-90,1800,'monthly','active'); end if;

 insert into unimis.payroll_profiles(tenant_id,employee_id,pay_group_id,bank_name,bank_account_name,bank_account_number,payment_method,tier3_participation_mode,provident_fund_enabled,provident_employee_rate,provident_employer_rate,active) values
 (p_tenant,e1,pg,'Demo Bank','Ama Mensah','001000001','bank','participating',true,1,5,true),
 (p_tenant,e2,pg,'Demo Bank','Kwame Asare','001000002','bank','not_participating',false,0,0,true),
 (p_tenant,e3,pg,'Demo Bank','Esi Agyeman','001000003','bank','not_participating',false,0,0,true),
 (p_tenant,e4,pg,'Mobile Money','Kojo Owusu','0240000000','momo','not_participating',false,0,0,true)
 on conflict(tenant_id,employee_id) do update set pay_group_id=excluded.pay_group_id,bank_name=excluded.bank_name,bank_account_name=excluded.bank_account_name,bank_account_number=excluded.bank_account_number,payment_method=excluded.payment_method,active=true;

 insert into unimis.payroll_worker_classifications(tenant_id,employee_id,employment_relationship,tax_treatment,pension_status,tier3_participation,pay_frequency,effective_from,approved,approved_by,approved_at,reason)
 values
 (p_tenant,e1,'regular','standard_paye','active_contributor','participating','monthly',mstart,true,auth.uid(),now(),'009f demo'),
 (p_tenant,e2,'regular','standard_paye','active_contributor','not_participating','monthly',mstart,true,auth.uid(),now(),'009f demo'),
 (p_tenant,e3,'fixed_term','standard_paye','active_contributor','not_participating','monthly',mstart,true,auth.uid(),now(),'009f demo'),
 (p_tenant,e4,'casual','casual_worker','not_applicable','not_participating','monthly',mstart,true,auth.uid(),now(),'009f demo')
 on conflict(tenant_id,employee_id) where effective_to is null do update set employment_relationship=excluded.employment_relationship,tax_treatment=excluded.tax_treatment,pension_status=excluded.pension_status,tier3_participation=excluded.tier3_participation,pay_frequency=excluded.pay_frequency,approved=true,approved_by=auth.uid(),approved_at=now();

 -- Demo payroll catalogue and Ama's known recurring inputs.
 insert into unimis.payroll_components(tenant_id,code,name,component_type,taxable,pensionable,calculation_type,default_amount,tax_treatment,pre_tax,recurring,active,employee_or_employer,requires_consent,requires_approval,effective_from,description) values
 (p_tenant,'TRANSPORT','Transport Allowance','earning',true,false,'fixed',100,'graduated',false,true,true,'employee',false,true,mstart,'009f demo allowance'),
 (p_tenant,'CHILD_EDU_ALLOW','Child Education Allowance','earning',true,false,'fixed',10,'graduated',false,true,true,'employee',false,true,mstart,'009f demo allowance'),
 (p_tenant,'GARDEN_BOY','Garden Boy Allowance','earning',true,false,'fixed',10,'graduated',false,true,true,'employee',false,true,mstart,'009f demo allowance'),
 (p_tenant,'HOUSE_HELP','House Help Allowance','earning',true,false,'fixed',10,'graduated',false,true,true,'employee',false,true,mstart,'009f demo allowance'),
 (p_tenant,'STAFF_INS','Staff Insurance','deduction',false,false,'fixed',100,'post_tax',false,true,true,'employee',true,true,mstart,'009f demo deduction'),
 (p_tenant,'STAFF_TRANSPORT','Staff Transport','deduction',false,false,'fixed',20,'post_tax',false,true,true,'employee',true,true,mstart,'009f demo deduction')
 on conflict(tenant_id,code) do update set name=excluded.name,component_type=excluded.component_type,active=true;
 for c in select id from unimis.payroll_components where tenant_id=p_tenant and code in ('TRANSPORT','CHILD_EDU_ALLOW','GARDEN_BOY','HOUSE_HELP','STAFF_INS','STAFF_TRANSPORT') loop
   insert into unimis.payroll_employee_components(tenant_id,employee_id,component_id,amount,effective_from)
   select p_tenant,e1,c.id,case (select code from unimis.payroll_components where id=c.id) when 'TRANSPORT' then 100 when 'STAFF_INS' then 100 when 'STAFF_TRANSPORT' then 20 else 10 end,mstart
   on conflict(employee_id,component_id,effective_from) do update set amount=excluded.amount;
 end loop;

 insert into unimis.payroll_setup_configs(tenant_id,section,config) values(p_tenant,'tier3',jsonb_build_object('enabled',true,'participationMode','employee_opt_in','employeeRate',1,'employerRate',5,'basis','basic_salary','employeeRateMayVary',true,'employerRateMayVary',false))
 on conflict(tenant_id,section) do update set config=excluded.config,updated_at=now();

 select id into per from unimis.payroll_periods where tenant_id=p_tenant and start_date=mstart and end_date=mend order by created_at limit 1;
 if per is null then insert into unimis.payroll_periods(tenant_id,pay_group_id,name,start_date,end_date,pay_date,status) values(p_tenant,pg,to_char(mstart,'FMMonth YYYY'),mstart,mend,mend,'open') returning id into per; end if;
 -- Bonus 22 reproduces the known Ama test gross of 4,352 only if all four allowances are active; kept as a visible period input.
 if not exists(select 1 from unimis.payroll_adjustments where tenant_id=p_tenant and employee_id=e1 and period_id=per and source_reference='009F-BONUS-AMA') then
   insert into unimis.payroll_adjustments(tenant_id,employee_id,period_id,adjustment_type,code,description,amount,taxable,pensionable,status,source_module,source_reference,created_by) values(p_tenant,e1,per,'bonus','BONUS','Demo period bonus',22,true,false,'approved','demo','009F-BONUS-AMA',auth.uid());
 end if;

 select id into rt from unimis.payroll_relief_types where country_code='GH' and code='CHILD_EDU' and (tenant_id=p_tenant or tenant_id is null) order by (tenant_id is not null) desc limit 1;
 if rt is not null then
  insert into unimis.payroll_employee_reliefs(tenant_id,employee_id,relief_type_id,tax_year,units,approved_annual_amount,approved,effective_from,reference,relief_status,approval_date)
  values(p_tenant,e1,rt,extract(year from current_date)::int,1,50,true,date_trunc('year',current_date)::date,'009F-DEMO-RELIEF','active',current_date)
  on conflict(employee_id,relief_type_id,tax_year) do update set approved=true,approved_annual_amount=50,relief_status='active',approval_date=current_date;
 end if;

 -- Performance demo now seeds after employees exist (important on a fresh PC).
 if to_regclass('unimis.hr_performance_cycles') is not null then
   insert into unimis.hr_performance_cycles(tenant_id,name,cycle_type,start_date,end_date,status) values(p_tenant,extract(year from current_date)::text||' Annual Performance Review','annual',date_trunc('year',current_date)::date,(date_trunc('year',current_date)+interval '1 year - 1 day')::date,'open') on conflict do nothing;
 end if;
 insert into unimis.payroll_settings(tenant_id) values(p_tenant) on conflict(tenant_id) do nothing;
 insert into unimis.audit_events(tenant_id,actor_id,module,action,record_type,record_id,details) values(p_tenant,auth.uid(),'core','demo.seeded','tenant',p_tenant,jsonb_build_object('package','009f','employees',4,'repeatable',true));
end $$;
grant execute on function unimis.seed_hrpayroll_demo(uuid) to authenticated;
notify pgrst, 'reload schema';


-- SOURCE 202610220002_009f1_seed_loop_fix.sql
-- HRPayrollCore 009f1: corrective replacement of demo seed function (fix component loop record).
-- Runs only when an Owner/Administrator clicks Load complete demo data.
create or replace function unimis.seed_hrpayroll_demo(p_tenant uuid)
returns void language plpgsql security definer set search_path=unimis as $$
declare
 b uuid; le uuid; d1 uuid; d2 uuid; d3 uuid; g1 uuid; g2 uuid; p1 uuid; p2 uuid; p3 uuid; pg uuid;
 e1 uuid; e2 uuid; e3 uuid; e4 uuid; rt uuid; per uuid; cyc uuid;
 c record;
 mstart date:=date_trunc('month',current_date)::date; mend date:=(date_trunc('month',current_date)+interval '1 month - 1 day')::date;
begin
 if not unimis.has_tenant_role(p_tenant,array['owner','administrator']) then raise exception 'Owner/admin required'; end if;
 select id into b from unimis.branches where tenant_id=p_tenant order by created_at limit 1;
 if b is null then
   select id into le from unimis.legal_entities where tenant_id=p_tenant order by created_at limit 1;
   if le is null then insert into unimis.legal_entities(tenant_id,name) select p_tenant,name from unimis.tenants where id=p_tenant returning id into le; end if;
   insert into unimis.branches(tenant_id,legal_entity_id,code,name,city) values(p_tenant,le,'HQ','Head Office','Kumasi') returning id into b;
 end if;
 select id into pg from unimis.payroll_pay_groups where tenant_id=p_tenant and active order by created_at limit 1;
 if pg is null then insert into unimis.payroll_pay_groups(tenant_id,code,name,frequency) values(p_tenant,'MONTHLY','Monthly Payroll','monthly') returning id into pg; end if;

 insert into unimis.departments(tenant_id,branch_id,code,name) values
 (p_tenant,b,'ADM','Administration'),(p_tenant,b,'FIN','Finance'),(p_tenant,b,'OPS','Operations')
 on conflict(tenant_id,code) do update set name=excluded.name,branch_id=coalesce(unimis.departments.branch_id,excluded.branch_id);
 select id into d1 from unimis.departments where tenant_id=p_tenant and code='ADM'; select id into d2 from unimis.departments where tenant_id=p_tenant and code='FIN'; select id into d3 from unimis.departments where tenant_id=p_tenant and code='OPS';
 insert into unimis.hr_job_grades(tenant_id,code,name,min_salary,max_salary) values
 (p_tenant,'G1','Officer',2500,6000),(p_tenant,'G2','Senior Officer',4500,9000)
 on conflict(tenant_id,code) do update set name=excluded.name,min_salary=excluded.min_salary,max_salary=excluded.max_salary;
 select id into g1 from unimis.hr_job_grades where tenant_id=p_tenant and code='G1'; select id into g2 from unimis.hr_job_grades where tenant_id=p_tenant and code='G2';
 insert into unimis.hr_positions(tenant_id,department_id,grade_id,code,title) values
 (p_tenant,d1,g1,'ADMIN-OFF','Administrative Officer'),(p_tenant,d2,g2,'ACCT-OFF','Accounts Officer'),(p_tenant,d3,g1,'OPS-OFF','Operations Officer')
 on conflict(tenant_id,code) do update set title=excluded.title,department_id=excluded.department_id,grade_id=excluded.grade_id;
 select id into p1 from unimis.hr_positions where tenant_id=p_tenant and code='ADMIN-OFF'; select id into p2 from unimis.hr_positions where tenant_id=p_tenant and code='ACCT-OFF'; select id into p3 from unimis.hr_positions where tenant_id=p_tenant and code='OPS-OFF';

 insert into unimis.hr_employees(tenant_id,employee_no,first_name,last_name,email,branch_id,department_id,position_id,hire_date,employment_type,work_schedule,pension_status)
 values(p_tenant,'EMP001','Ama','Mensah','ama.mensah@example.test',b,d1,p1,current_date-500,'regular','full_time','active_contributor')
 on conflict(tenant_id,employee_no) do update set first_name='Ama',last_name='Mensah',department_id=d1,position_id=p1,employment_type='regular',employment_status='active' returning id into e1;
 if e1 is null then select id into e1 from unimis.hr_employees where tenant_id=p_tenant and employee_no='EMP001'; end if;
 insert into unimis.hr_employees(tenant_id,employee_no,first_name,last_name,email,branch_id,department_id,position_id,hire_date,employment_type,work_schedule,pension_status)
 values(p_tenant,'EMP002','Kwame','Asare','kwame.asare@example.test',b,d2,p2,current_date-420,'regular','full_time','active_contributor')
 on conflict(tenant_id,employee_no) do update set first_name='Kwame',last_name='Asare',department_id=d2,position_id=p2,employment_type='regular',employment_status='active' returning id into e2;
 if e2 is null then select id into e2 from unimis.hr_employees where tenant_id=p_tenant and employee_no='EMP002'; end if;
 insert into unimis.hr_employees(tenant_id,employee_no,first_name,last_name,email,branch_id,department_id,position_id,hire_date,employment_type,work_schedule,pension_status)
 values(p_tenant,'EMP003','Esi','Agyeman','esi.agyeman@example.test',b,d3,p3,current_date-180,'fixed_term','full_time','active_contributor')
 on conflict(tenant_id,employee_no) do update set first_name='Esi',last_name='Agyeman',department_id=d3,position_id=p3,employment_type='fixed_term',employment_status='active' returning id into e3;
 if e3 is null then select id into e3 from unimis.hr_employees where tenant_id=p_tenant and employee_no='EMP003'; end if;
 insert into unimis.hr_employees(tenant_id,employee_no,first_name,last_name,email,branch_id,department_id,position_id,hire_date,employment_type,work_schedule,pension_status)
 values(p_tenant,'EMP004','Kojo','Owusu','kojo.owusu@example.test',b,d3,p3,current_date-90,'casual','part_time','not_applicable')
 on conflict(tenant_id,employee_no) do update set first_name='Kojo',last_name='Owusu',department_id=d3,position_id=p3,employment_type='casual',employment_status='active' returning id into e4;
 if e4 is null then select id into e4 from unimis.hr_employees where tenant_id=p_tenant and employee_no='EMP004'; end if;

 -- Current contracts: do not duplicate on repeat runs.
 if not exists(select 1 from unimis.hr_employment_contracts where tenant_id=p_tenant and employee_id=e1 and status='active') then insert into unimis.hr_employment_contracts(tenant_id,employee_id,contract_type,start_date,basic_salary,pay_frequency,status) values(p_tenant,e1,'regular',current_date-500,4200,'monthly','active'); end if;
 if not exists(select 1 from unimis.hr_employment_contracts where tenant_id=p_tenant and employee_id=e2 and status='active') then insert into unimis.hr_employment_contracts(tenant_id,employee_id,contract_type,start_date,basic_salary,pay_frequency,status) values(p_tenant,e2,'regular',current_date-420,5000,'monthly','active'); end if;
 if not exists(select 1 from unimis.hr_employment_contracts where tenant_id=p_tenant and employee_id=e3 and status='active') then insert into unimis.hr_employment_contracts(tenant_id,employee_id,contract_type,start_date,end_date,basic_salary,pay_frequency,status) values(p_tenant,e3,'fixed_term',current_date-180,current_date+185,3200,'monthly','active'); end if;
 if not exists(select 1 from unimis.hr_employment_contracts where tenant_id=p_tenant and employee_id=e4 and status='active') then insert into unimis.hr_employment_contracts(tenant_id,employee_id,contract_type,start_date,basic_salary,pay_frequency,status) values(p_tenant,e4,'casual',current_date-90,1800,'monthly','active'); end if;

 insert into unimis.payroll_profiles(tenant_id,employee_id,pay_group_id,bank_name,bank_account_name,bank_account_number,payment_method,tier3_participation_mode,provident_fund_enabled,provident_employee_rate,provident_employer_rate,active) values
 (p_tenant,e1,pg,'Demo Bank','Ama Mensah','001000001','bank','participating',true,1,5,true),
 (p_tenant,e2,pg,'Demo Bank','Kwame Asare','001000002','bank','not_participating',false,0,0,true),
 (p_tenant,e3,pg,'Demo Bank','Esi Agyeman','001000003','bank','not_participating',false,0,0,true),
 (p_tenant,e4,pg,'Mobile Money','Kojo Owusu','0240000000','momo','not_participating',false,0,0,true)
 on conflict(tenant_id,employee_id) do update set pay_group_id=excluded.pay_group_id,bank_name=excluded.bank_name,bank_account_name=excluded.bank_account_name,bank_account_number=excluded.bank_account_number,payment_method=excluded.payment_method,active=true;

 insert into unimis.payroll_worker_classifications(tenant_id,employee_id,employment_relationship,tax_treatment,pension_status,tier3_participation,pay_frequency,effective_from,approved,approved_by,approved_at,reason)
 values
 (p_tenant,e1,'regular','standard_paye','active_contributor','participating','monthly',mstart,true,auth.uid(),now(),'009f demo'),
 (p_tenant,e2,'regular','standard_paye','active_contributor','not_participating','monthly',mstart,true,auth.uid(),now(),'009f demo'),
 (p_tenant,e3,'fixed_term','standard_paye','active_contributor','not_participating','monthly',mstart,true,auth.uid(),now(),'009f demo'),
 (p_tenant,e4,'casual','casual_worker','not_applicable','not_participating','monthly',mstart,true,auth.uid(),now(),'009f demo')
 on conflict(tenant_id,employee_id) where effective_to is null do update set employment_relationship=excluded.employment_relationship,tax_treatment=excluded.tax_treatment,pension_status=excluded.pension_status,tier3_participation=excluded.tier3_participation,pay_frequency=excluded.pay_frequency,approved=true,approved_by=auth.uid(),approved_at=now();

 -- Demo payroll catalogue and Ama's known recurring inputs.
 insert into unimis.payroll_components(tenant_id,code,name,component_type,taxable,pensionable,calculation_type,default_amount,tax_treatment,pre_tax,recurring,active,employee_or_employer,requires_consent,requires_approval,effective_from,description) values
 (p_tenant,'TRANSPORT','Transport Allowance','earning',true,false,'fixed',100,'graduated',false,true,true,'employee',false,true,mstart,'009f demo allowance'),
 (p_tenant,'CHILD_EDU_ALLOW','Child Education Allowance','earning',true,false,'fixed',10,'graduated',false,true,true,'employee',false,true,mstart,'009f demo allowance'),
 (p_tenant,'GARDEN_BOY','Garden Boy Allowance','earning',true,false,'fixed',10,'graduated',false,true,true,'employee',false,true,mstart,'009f demo allowance'),
 (p_tenant,'HOUSE_HELP','House Help Allowance','earning',true,false,'fixed',10,'graduated',false,true,true,'employee',false,true,mstart,'009f demo allowance'),
 (p_tenant,'STAFF_INS','Staff Insurance','deduction',false,false,'fixed',100,'post_tax',false,true,true,'employee',true,true,mstart,'009f demo deduction'),
 (p_tenant,'STAFF_TRANSPORT','Staff Transport','deduction',false,false,'fixed',20,'post_tax',false,true,true,'employee',true,true,mstart,'009f demo deduction')
 on conflict(tenant_id,code) do update set name=excluded.name,component_type=excluded.component_type,active=true;
 for c in select id from unimis.payroll_components where tenant_id=p_tenant and code in ('TRANSPORT','CHILD_EDU_ALLOW','GARDEN_BOY','HOUSE_HELP','STAFF_INS','STAFF_TRANSPORT') loop
   insert into unimis.payroll_employee_components(tenant_id,employee_id,component_id,amount,effective_from)
   select p_tenant,e1,c.id,case (select code from unimis.payroll_components where id=c.id) when 'TRANSPORT' then 100 when 'STAFF_INS' then 100 when 'STAFF_TRANSPORT' then 20 else 10 end,mstart
   on conflict(employee_id,component_id,effective_from) do update set amount=excluded.amount;
 end loop;

 insert into unimis.payroll_setup_configs(tenant_id,section,config) values(p_tenant,'tier3',jsonb_build_object('enabled',true,'participationMode','employee_opt_in','employeeRate',1,'employerRate',5,'basis','basic_salary','employeeRateMayVary',true,'employerRateMayVary',false))
 on conflict(tenant_id,section) do update set config=excluded.config,updated_at=now();

 select id into per from unimis.payroll_periods where tenant_id=p_tenant and start_date=mstart and end_date=mend order by created_at limit 1;
 if per is null then insert into unimis.payroll_periods(tenant_id,pay_group_id,name,start_date,end_date,pay_date,status) values(p_tenant,pg,to_char(mstart,'FMMonth YYYY'),mstart,mend,mend,'open') returning id into per; end if;
 -- Bonus 22 reproduces the known Ama test gross of 4,352 only if all four allowances are active; kept as a visible period input.
 if not exists(select 1 from unimis.payroll_adjustments where tenant_id=p_tenant and employee_id=e1 and period_id=per and source_reference='009F-BONUS-AMA') then
   insert into unimis.payroll_adjustments(tenant_id,employee_id,period_id,adjustment_type,code,description,amount,taxable,pensionable,status,source_module,source_reference,created_by) values(p_tenant,e1,per,'bonus','BONUS','Demo period bonus',22,true,false,'approved','demo','009F-BONUS-AMA',auth.uid());
 end if;

 select id into rt from unimis.payroll_relief_types where country_code='GH' and code='CHILD_EDU' and (tenant_id=p_tenant or tenant_id is null) order by (tenant_id is not null) desc limit 1;
 if rt is not null then
  insert into unimis.payroll_employee_reliefs(tenant_id,employee_id,relief_type_id,tax_year,units,approved_annual_amount,approved,effective_from,reference,relief_status,approval_date)
  values(p_tenant,e1,rt,extract(year from current_date)::int,1,50,true,date_trunc('year',current_date)::date,'009F-DEMO-RELIEF','active',current_date)
  on conflict(employee_id,relief_type_id,tax_year) do update set approved=true,approved_annual_amount=50,relief_status='active',approval_date=current_date;
 end if;

 -- Performance demo now seeds after employees exist (important on a fresh PC).
 if to_regclass('unimis.hr_performance_cycles') is not null then
   insert into unimis.hr_performance_cycles(tenant_id,name,cycle_type,start_date,end_date,status) values(p_tenant,extract(year from current_date)::text||' Annual Performance Review','annual',date_trunc('year',current_date)::date,(date_trunc('year',current_date)+interval '1 year - 1 day')::date,'open') on conflict do nothing;
 end if;
 insert into unimis.payroll_settings(tenant_id) values(p_tenant) on conflict(tenant_id) do nothing;
 insert into unimis.audit_events(tenant_id,actor_id,module,action,record_type,record_id,details) values(p_tenant,auth.uid(),'core','demo.seeded','tenant',p_tenant,jsonb_build_object('package','009f1','employees',4,'repeatable',true));
end $$;
grant execute on function unimis.seed_hrpayroll_demo(uuid) to authenticated;
notify pgrst, 'reload schema';


-- SOURCE 202610220003_009g_staff_salary_accounts.sql
-- 009g: richer staff salary payment transaction audit trail.
alter table unimis.payroll_staff_payment_transactions
  add column if not exists payment_method text,
  add column if not exists notes text,
  add column if not exists batch_reference text;

create index if not exists payroll_staff_payment_transactions_statement_date_idx
  on unimis.payroll_staff_payment_transactions(statement_id,payment_date desc,created_at desc);

create or replace function unimis.payroll_record_staff_payment_detailed(
  p_tenant uuid,
  p_statement uuid,
  p_amount numeric,
  p_reference text,
  p_payment_date date default current_date,
  p_method text default 'bank_transfer',
  p_notes text default null,
  p_batch_reference text default null
) returns jsonb
language plpgsql security definer set search_path=unimis as $$
declare s payroll_staff_statements%rowtype; np numeric; nb numeric;
begin
  if not unimis.has_tenant_role(p_tenant,array['owner','administrator','accountant','finance_manager','payroll_manager','payroll_officer']) then
    raise exception 'Payroll access denied';
  end if;
  select * into s from payroll_staff_statements where id=p_statement and tenant_id=p_tenant for update;
  if s.id is null then raise exception 'Staff payroll statement not found'; end if;
  if p_amount<=0 or p_amount>s.balance then raise exception 'Payment must be greater than zero and not exceed outstanding balance'; end if;
  if coalesce(trim(p_reference),'')='' then raise exception 'Payment reference is required'; end if;
  insert into payroll_staff_payment_transactions(tenant_id,statement_id,amount,payment_date,reference,payment_method,notes,batch_reference)
  values(p_tenant,p_statement,p_amount,coalesce(p_payment_date,current_date),trim(p_reference),coalesce(nullif(trim(p_method),''),'other'),nullif(trim(p_notes),''),nullif(trim(p_batch_reference),''));
  np:=s.amount_paid+p_amount; nb:=greatest(s.amount_due-np,0);
  update payroll_staff_statements set amount_paid=np,balance=nb,status=case when nb=0 then 'paid' else 'part_paid' end,last_payment_date=coalesce(p_payment_date,current_date),last_payment_reference=trim(p_reference),updated_at=now() where id=s.id;
  return jsonb_build_object('ok',true,'paid',np,'balance',nb,'statement_id',s.id);
end$$;
grant execute on function unimis.payroll_record_staff_payment_detailed(uuid,uuid,numeric,text,date,text,text,text) to authenticated;
notify pgrst,'reload schema';


-- SOURCE 202610220004_009h_professional_scoped_salary_increases.sql
-- 009h: professional scoped salary adjustments.
-- Adds auditable scope metadata and creates preview batches for an individual or selected employee category.
alter table unimis.payroll_salary_change_batches
  add column if not exists scope_type text,
  add column if not exists scope_value text,
  add column if not exists scope_label text;

alter table unimis.payroll_salary_change_batches drop constraint if exists payroll_salary_change_batches_change_mode_check;
alter table unimis.payroll_salary_change_batches add constraint payroll_salary_change_batches_change_mode_check
  check (change_mode in ('percentage','fixed','grade_step','manual','set_salary'));

create or replace function unimis.payroll_create_scoped_salary_batch(
 p_tenant uuid,p_scope text,p_scope_value text,p_mode text,p_value numeric,p_effective date,p_reason text default null
) returns jsonb language plpgsql security definer set search_path=unimis as $$
declare b uuid; bn text; r record; oldv numeric; newv numeric; n integer:=0; lbl text;
begin
 if not unimis.has_tenant_role(p_tenant,array['owner','administrator','payroll_manager','hr_manager']) then raise exception 'Salary change access denied'; end if;
 if p_scope not in ('employee','department','position','grade','employment_type','employment_status','all') then raise exception 'Invalid salary adjustment scope'; end if;
 if p_mode not in ('percentage','fixed','set_salary') then raise exception 'Invalid salary adjustment method'; end if;
 if coalesce(p_value,0)<=0 then raise exception 'Adjustment value must be greater than zero'; end if;
 if p_effective is null then raise exception 'Effective date is required'; end if;
 if p_scope<>'all' and nullif(trim(coalesce(p_scope_value,'')),'') is null then raise exception 'Select an employee/category'; end if;

 lbl:=case p_scope
  when 'all' then 'All active employees'
  when 'employee' then (select employee_no||' · '||first_name||' '||last_name from unimis.hr_employees where tenant_id=p_tenant and id=p_scope_value::uuid)
  when 'department' then (select name from unimis.departments where tenant_id=p_tenant and id=p_scope_value::uuid)
  when 'position' then (select title from unimis.hr_positions where tenant_id=p_tenant and id=p_scope_value::uuid)
  when 'grade' then (select code||' · '||name from unimis.hr_job_grades where tenant_id=p_tenant and id=p_scope_value::uuid)
  else initcap(replace(p_scope_value,'_',' ')) end;

 bn:='SAL-'||to_char(clock_timestamp(),'YYYYMMDDHH24MISSMS');
 insert into unimis.payroll_salary_change_batches(tenant_id,batch_no,change_mode,value,effective_date,reason,status,scope_type,scope_value,scope_label,created_by)
 values(p_tenant,bn,p_mode,p_value,p_effective,p_reason,'draft',p_scope,p_scope_value,lbl,auth.uid()) returning id into b;

 for r in
  select e.id
  from unimis.hr_employees e
  left join unimis.hr_positions pos on pos.id=e.position_id
  where e.tenant_id=p_tenant and e.employment_status='active'
   and case p_scope
    when 'all' then true
    when 'employee' then e.id=p_scope_value::uuid
    when 'department' then e.department_id=p_scope_value::uuid
    when 'position' then e.position_id=p_scope_value::uuid
    when 'grade' then pos.grade_id=p_scope_value::uuid
    when 'employment_type' then lower(coalesce(e.employment_type,''))=lower(p_scope_value)
    when 'employment_status' then lower(coalesce(e.employment_status,''))=lower(p_scope_value)
    else false end
 loop
  select coalesce(
   (select sh.new_salary from unimis.hr_salary_history sh where sh.employee_id=r.id and sh.effective_from<=p_effective order by sh.effective_from desc,sh.created_at desc limit 1),
   (select c.basic_salary from unimis.hr_employment_contracts c where c.employee_id=r.id and c.status='active' order by c.start_date desc limit 1),0) into oldv;
  newv:=case when p_mode='percentage' then round(oldv*(1+p_value/100),2) when p_mode='fixed' then round(oldv+p_value,2) when p_mode='set_salary' then round(p_value,2) else oldv end;
  insert into unimis.payroll_salary_change_items(tenant_id,batch_id,employee_id,old_salary,new_salary) values(p_tenant,b,r.id,oldv,newv);
  n:=n+1;
 end loop;
 if n=0 then delete from unimis.payroll_salary_change_batches where id=b; raise exception 'No active employees matched the selected category'; end if;
 return jsonb_build_object('batch_id',b,'affected',n,'scope',p_scope,'scope_label',lbl);
end $$;
grant execute on function unimis.payroll_create_scoped_salary_batch(uuid,text,text,text,numeric,date,text) to authenticated;
notify pgrst,'reload schema';


-- SOURCE 202610220005_009h2_salary_adjustment_controls_and_reversal.sql
-- 009h2: salary adjustment safety controls, duplicate prevention, stale-preview protection and audited reversal.

alter table unimis.hr_salary_history
  add column if not exists source_salary_batch_id uuid references unimis.payroll_salary_change_batches(id) on delete set null;

alter table unimis.payroll_salary_change_batches
  add column if not exists reversal_reason text,
  add column if not exists reversed_by uuid references auth.users(id),
  add column if not exists reversed_at timestamptz;

alter table unimis.payroll_salary_change_batches drop constraint if exists payroll_salary_change_batches_status_check;
alter table unimis.payroll_salary_change_batches add constraint payroll_salary_change_batches_status_check
  check(status in ('draft','approved','applied','cancelled','reversed'));

create index if not exists hr_salary_history_source_batch_idx on unimis.hr_salary_history(source_salary_batch_id);

create or replace function unimis.payroll_create_scoped_salary_batch(
 p_tenant uuid,p_scope text,p_scope_value text,p_mode text,p_value numeric,p_effective date,p_reason text default null
) returns jsonb language plpgsql security definer set search_path=unimis as $$
declare b uuid; bn text; r record; oldv numeric; newv numeric; n integer:=0; lbl text; dup record;
begin
 if not unimis.has_tenant_role(p_tenant,array['owner','administrator','payroll_manager','hr_manager']) then raise exception 'Salary change access denied'; end if;
 if p_scope not in ('employee','department','position','grade','employment_type','employment_status','all') then raise exception 'Invalid salary adjustment scope'; end if;
 if p_mode not in ('percentage','fixed','set_salary') then raise exception 'Invalid salary adjustment method'; end if;
 if coalesce(p_value,0)<=0 then raise exception 'Adjustment value must be greater than zero'; end if;
 if p_effective is null then raise exception 'Effective date is required'; end if;
 if p_scope<>'all' and nullif(trim(coalesce(p_scope_value,'')),'') is null then raise exception 'Select an employee/category'; end if;

 select id,batch_no,status into dup from unimis.payroll_salary_change_batches
 where tenant_id=p_tenant and coalesce(scope_type,'all')=p_scope
   and coalesce(scope_value,'')=coalesce(p_scope_value,'')
   and change_mode=p_mode and value=p_value and effective_date=p_effective
   and status in ('draft','applied')
 order by created_at desc limit 1;
 if dup.id is not null then
   raise exception 'Possible duplicate salary adjustment: batch % is already %. Review that batch instead of creating another identical adjustment.',dup.batch_no,dup.status;
 end if;

 lbl:=case p_scope
  when 'all' then 'All active employees'
  when 'employee' then (select employee_no||' · '||first_name||' '||last_name from unimis.hr_employees where tenant_id=p_tenant and id=p_scope_value::uuid)
  when 'department' then (select name from unimis.departments where tenant_id=p_tenant and id=p_scope_value::uuid)
  when 'position' then (select title from unimis.hr_positions where tenant_id=p_tenant and id=p_scope_value::uuid)
  when 'grade' then (select code||' · '||name from unimis.hr_job_grades where tenant_id=p_tenant and id=p_scope_value::uuid)
  else initcap(replace(p_scope_value,'_',' ')) end;

 bn:='SAL-'||to_char(clock_timestamp(),'YYYYMMDDHH24MISSMS');
 insert into unimis.payroll_salary_change_batches(tenant_id,batch_no,change_mode,value,effective_date,reason,status,scope_type,scope_value,scope_label,created_by)
 values(p_tenant,bn,p_mode,p_value,p_effective,p_reason,'draft',p_scope,p_scope_value,lbl,auth.uid()) returning id into b;

 for r in
  select e.id from unimis.hr_employees e left join unimis.hr_positions pos on pos.id=e.position_id
  where e.tenant_id=p_tenant and e.employment_status='active'
   and case p_scope when 'all' then true when 'employee' then e.id=p_scope_value::uuid when 'department' then e.department_id=p_scope_value::uuid
    when 'position' then e.position_id=p_scope_value::uuid when 'grade' then pos.grade_id=p_scope_value::uuid
    when 'employment_type' then lower(coalesce(e.employment_type,''))=lower(p_scope_value)
    when 'employment_status' then lower(coalesce(e.employment_status,''))=lower(p_scope_value) else false end
 loop
  select coalesce((select sh.new_salary from unimis.hr_salary_history sh where sh.employee_id=r.id and sh.effective_from<=p_effective order by sh.effective_from desc,sh.created_at desc limit 1),(select c.basic_salary from unimis.hr_employment_contracts c where c.employee_id=r.id and c.status='active' order by c.start_date desc limit 1),0) into oldv;
  newv:=case when p_mode='percentage' then round(oldv*(1+p_value/100),2) when p_mode='fixed' then round(oldv+p_value,2) when p_mode='set_salary' then round(p_value,2) else oldv end;
  insert into unimis.payroll_salary_change_items(tenant_id,batch_id,employee_id,old_salary,new_salary) values(p_tenant,b,r.id,oldv,newv); n:=n+1;
 end loop;
 if n=0 then delete from unimis.payroll_salary_change_batches where id=b; raise exception 'No active employees matched the selected category'; end if;
 return jsonb_build_object('batch_id',b,'affected',n,'scope',p_scope,'scope_label',lbl,'batch_no',bn);
end $$;

grant execute on function unimis.payroll_create_scoped_salary_batch(uuid,text,text,text,numeric,date,text) to authenticated;

create or replace function unimis.payroll_apply_salary_batch(p_tenant uuid,p_batch uuid)
returns void language plpgsql security definer set search_path=unimis as $$
declare r record; d date; rs text; bn text; currentv numeric;
begin
 if not unimis.has_tenant_role(p_tenant,array['owner','administrator','payroll_manager']) then raise exception 'Salary approval access denied'; end if;
 select effective_date,reason,batch_no into d,rs,bn from unimis.payroll_salary_change_batches where id=p_batch and tenant_id=p_tenant and status='draft';
 if d is null then raise exception 'Draft batch not found or it has already been processed'; end if;
 for r in select * from unimis.payroll_salary_change_items where batch_id=p_batch order by employee_id loop
  select coalesce((select sh.new_salary from unimis.hr_salary_history sh where sh.employee_id=r.employee_id and sh.effective_from<=d order by sh.effective_from desc,sh.created_at desc limit 1),(select c.basic_salary from unimis.hr_employment_contracts c where c.employee_id=r.employee_id and c.status='active' order by c.start_date desc limit 1),0) into currentv;
  if round(currentv,2)<>round(r.old_salary,2) then
    raise exception 'Preview is stale for an employee: current salary is %, but this draft was prepared from %. Cancel/recreate the draft and review again.',currentv,r.old_salary;
  end if;
 end loop;
 for r in select * from unimis.payroll_salary_change_items where batch_id=p_batch loop
  insert into unimis.hr_salary_history(tenant_id,employee_id,old_salary,new_salary,change_type,reason,effective_from,approved_by,created_by,source_salary_batch_id)
  values(p_tenant,r.employee_id,r.old_salary,r.new_salary,'bulk_adjustment',rs,d,auth.uid(),auth.uid(),p_batch);
  if d<=current_date then update unimis.hr_employment_contracts set basic_salary=r.new_salary where tenant_id=p_tenant and employee_id=r.employee_id and status='active'; end if;
 end loop;
 update unimis.payroll_salary_change_batches set status='applied',approved_by=auth.uid() where id=p_batch and tenant_id=p_tenant;
end $$;
grant execute on function unimis.payroll_apply_salary_batch(uuid,uuid) to authenticated;

create or replace function unimis.payroll_cancel_salary_batch(p_tenant uuid,p_batch uuid)
returns void language plpgsql security definer set search_path=unimis as $$
begin
 if not unimis.has_tenant_role(p_tenant,array['owner','administrator','payroll_manager','hr_manager']) then raise exception 'Salary change access denied'; end if;
 update unimis.payroll_salary_change_batches set status='cancelled'
 where tenant_id=p_tenant and id=p_batch and status='draft';
 if not found then raise exception 'Only a draft salary adjustment can be cancelled'; end if;
end $$;
grant execute on function unimis.payroll_cancel_salary_batch(uuid,uuid) to authenticated;

create or replace function unimis.payroll_reverse_salary_batch(p_tenant uuid,p_batch uuid,p_reason text)
returns void language plpgsql security definer set search_path=unimis as $$
declare r record; d date; bn text; currentv numeric; revdate date:=current_date;
begin
 if not unimis.has_tenant_role(p_tenant,array['owner','administrator','payroll_manager']) then raise exception 'Salary reversal access denied'; end if;
 if nullif(trim(coalesce(p_reason,'')),'') is null then raise exception 'Enter a reversal reason / authority'; end if;
 select effective_date,batch_no into d,bn from unimis.payroll_salary_change_batches where tenant_id=p_tenant and id=p_batch and status='applied';
 if d is null then raise exception 'Only an applied salary batch can be reversed'; end if;
 for r in select * from unimis.payroll_salary_change_items where batch_id=p_batch order by employee_id loop
  select coalesce((select sh.new_salary from unimis.hr_salary_history sh where sh.employee_id=r.employee_id and sh.effective_from<=current_date order by sh.effective_from desc,sh.created_at desc limit 1),(select c.basic_salary from unimis.hr_employment_contracts c where c.employee_id=r.employee_id and c.status='active' order by c.start_date desc limit 1),0) into currentv;
  if round(currentv,2)<>round(r.new_salary,2) then
    raise exception 'Batch % cannot be reversed because a later salary change exists for an affected employee (current %, batch result %). Reverse the latest applicable change first.',bn,currentv,r.new_salary;
  end if;
 end loop;
 for r in select * from unimis.payroll_salary_change_items where batch_id=p_batch loop
  insert into unimis.hr_salary_history(tenant_id,employee_id,old_salary,new_salary,change_type,reason,effective_from,approved_by,created_by,source_salary_batch_id)
  values(p_tenant,r.employee_id,r.new_salary,r.old_salary,'salary_adjustment_reversal','Reversal of '||bn||': '||trim(p_reason),greatest(d,revdate),auth.uid(),auth.uid(),p_batch);
  if greatest(d,revdate)<=current_date then update unimis.hr_employment_contracts set basic_salary=r.old_salary where tenant_id=p_tenant and employee_id=r.employee_id and status='active'; end if;
 end loop;
 update unimis.payroll_salary_change_batches set status='reversed',reversal_reason=trim(p_reason),reversed_by=auth.uid(),reversed_at=now() where tenant_id=p_tenant and id=p_batch;
end $$;
grant execute on function unimis.payroll_reverse_salary_batch(uuid,uuid,text) to authenticated;

notify pgrst,'reload schema';


-- SOURCE 202610220010_cross_industry_performance_management.sql
-- Package 010: Cross-industry Performance Management System (PMS)
-- Tracker + Tracer + Appraisal + Development / Decision Support

alter table unimis.hr_performance_policies add column if not exists target_output_weight numeric(5,2) not null default 50;
alter table unimis.hr_performance_policies add column if not exists responsibility_quality_weight numeric(5,2) not null default 30;
alter table unimis.hr_performance_policies add column if not exists professional_conduct_weight numeric(5,2) not null default 20;
alter table unimis.hr_performance_policies add column if not exists industry_template text not null default 'general';
alter table unimis.hr_performance_policies add column if not exists appraisal_frequency text not null default 'annual';
alter table unimis.hr_performance_policies add column if not exists enable_360 boolean not null default false;
alter table unimis.hr_performance_policies add column if not exists enable_continuous_checkins boolean not null default true;

alter table unimis.hr_performance_reviews add column if not exists target_output_score numeric(6,2);
alter table unimis.hr_performance_reviews add column if not exists responsibility_quality_score numeric(6,2);
alter table unimis.hr_performance_reviews add column if not exists professional_conduct_score numeric(6,2);
alter table unimis.hr_performance_reviews add column if not exists self_score numeric(6,2);
alter table unimis.hr_performance_reviews add column if not exists supervisor_score numeric(6,2);
alter table unimis.hr_performance_reviews add column if not exists trend text;
alter table unimis.hr_performance_reviews add column if not exists strengths text;
alter table unimis.hr_performance_reviews add column if not exists skill_gaps text;
alter table unimis.hr_performance_reviews add column if not exists recommended_action text;
alter table unimis.hr_performance_reviews add column if not exists approved_by uuid;
alter table unimis.hr_performance_reviews add column if not exists approved_at timestamptz;

create table if not exists unimis.hr_performance_metric_library(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.tenants(id) on delete cascade,
 code text not null, name text not null, pillar text not null check(pillar in ('target_output','responsibility_quality','professional_conduct')),
 industry text not null default 'general', unit text not null default 'score', direction text not null default 'higher_better' check(direction in ('higher_better','lower_better','milestone','pass_fail')),
 description text, default_target numeric(14,2), default_weight numeric(6,2) not null default 0, active boolean not null default true,
 created_by uuid default auth.uid(), created_at timestamptz not null default now(), unique(tenant_id,code)
);

create table if not exists unimis.hr_performance_plan_items(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.tenants(id) on delete cascade,
 review_id uuid not null references unimis.hr_performance_reviews(id) on delete cascade,
 metric_id uuid references unimis.hr_performance_metric_library(id) on delete set null,
 pillar text not null check(pillar in ('target_output','responsibility_quality','professional_conduct')),
 title text not null, description text, unit text not null default 'score', direction text not null default 'higher_better', target_value numeric(14,2), actual_value numeric(14,2),
 weight numeric(6,2) not null default 0, employee_score numeric(6,2), supervisor_score numeric(6,2), final_score numeric(6,2), evidence text, due_date date,
 status text not null default 'planned' check(status in ('planned','on_track','at_risk','exceeded','completed','not_met','cancelled')),
 created_by uuid default auth.uid(), created_at timestamptz not null default now()
);

create table if not exists unimis.hr_performance_checkins(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.tenants(id) on delete cascade,
 review_id uuid not null references unimis.hr_performance_reviews(id) on delete cascade,
 checkin_date date not null default current_date, progress_percent numeric(6,2), status text not null default 'on_track' check(status in ('on_track','at_risk','off_track','exceeded')),
 achievements text, blockers text, support_required text, next_actions text, manager_comments text,
 created_by uuid default auth.uid(), created_at timestamptz not null default now()
);

create table if not exists unimis.hr_performance_feedback(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.tenants(id) on delete cascade,
 review_id uuid not null references unimis.hr_performance_reviews(id) on delete cascade,
 feedback_type text not null default 'manager' check(feedback_type in ('self','manager','peer','direct_report','customer','other')),
 rater_employee_id uuid references unimis.hr_employees(id) on delete set null, score numeric(6,2), comments text, evidence text,
 created_by uuid default auth.uid(), created_at timestamptz not null default now()
);

create table if not exists unimis.hr_performance_decisions(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.tenants(id) on delete cascade,
 review_id uuid not null references unimis.hr_performance_reviews(id) on delete cascade,
 action_type text not null check(action_type in ('recognition','merit_bonus','salary_increment','promotion','training','mentoring','workload_realignment','pip','conduct_coaching','management_review','succession_pool','no_action','other')),
 rationale text, status text not null default 'recommended' check(status in ('recommended','approved','rejected','implemented','cancelled')),
 decision_by uuid, decision_at timestamptz, created_by uuid default auth.uid(), created_at timestamptz not null default now()
);

do $$ declare t text; begin
 foreach t in array array['hr_performance_metric_library','hr_performance_plan_items','hr_performance_checkins','hr_performance_feedback','hr_performance_decisions'] loop
  execute format('alter table unimis.%I enable row level security',t);
  execute format('drop policy if exists tenant_member_all on unimis.%I',t);
  execute format('create policy tenant_member_all on unimis.%I for all using (unimis.is_tenant_member(tenant_id)) with check (unimis.is_tenant_member(tenant_id))',t);
 end loop;
end $$;

create index if not exists idx_perf_metric_tenant_pillar on unimis.hr_performance_metric_library(tenant_id,pillar,active);
create index if not exists idx_perf_plan_review on unimis.hr_performance_plan_items(review_id,pillar);
create index if not exists idx_perf_checkin_review on unimis.hr_performance_checkins(review_id,checkin_date desc);
create index if not exists idx_perf_feedback_review on unimis.hr_performance_feedback(review_id,feedback_type);
create index if not exists idx_perf_decision_review on unimis.hr_performance_decisions(review_id,status);

-- Cross-industry starter library. These are editable templates, never hard-coded scoring rules.
do $$ declare t record; begin
 for t in select id from unimis.tenants loop
  insert into unimis.hr_performance_metric_library(tenant_id,code,name,pillar,industry,unit,direction,description,default_weight) values
   (t.id,'GEN-OUTPUT','Target / Output Achievement','target_output','general','percent','higher_better','Achievement against agreed quantitative targets, deliverables or milestones.',20),
   (t.id,'GEN-DEADLINE','Deadline Delivery','target_output','general','percent','higher_better','Delivery of agreed work within committed timelines.',10),
   (t.id,'GEN-QUALITY','Work Quality & Accuracy','responsibility_quality','general','score','higher_better','Accuracy, completeness, rework and quality of assigned responsibilities.',15),
   (t.id,'GEN-SOP','Responsibility / SOP Execution','responsibility_quality','general','score','higher_better','Execution of job-description duties, procedures and controls.',15),
   (t.id,'GEN-CONDUCT','Professional Conduct & Ethics','professional_conduct','general','score','higher_better','Integrity, professionalism and adherence to organisational values.',10),
   (t.id,'GEN-TEAM','Collaboration & Communication','professional_conduct','general','score','higher_better','Teamwork, communication and constructive workplace behaviour.',5),
   (t.id,'GEN-ATTEND','Attendance & Punctuality','professional_conduct','general','percent','higher_better','Attendance and punctuality considered with authorised context.',5),
   (t.id,'EDU-RESULT','Learner / Examination Outcomes','target_output','education','percent','higher_better','Learner achievement, pass rate or agreed educational outcome.',20),
   (t.id,'TRADE-SALES','Sales / Revenue Achievement','target_output','trading','percent','higher_better','Sales, revenue, margin or collection target achievement.',25),
   (t.id,'NGO-DELIV','Programme / Donor Milestones','target_output','ngo','percent','higher_better','Delivery against project outputs, beneficiary and donor milestones.',20),
   (t.id,'BANK-COMP','Control & Compliance Quality','responsibility_quality','banking','score','higher_better','KYC, reconciliation, risk and control execution quality.',20),
   (t.id,'HEALTH-QLT','Clinical / Service Quality','responsibility_quality','healthcare','score','higher_better','Quality, documentation and protocol adherence for health services.',20),
   (t.id,'HOTEL-SVC','Guest Service Quality','responsibility_quality','hospitality','score','higher_better','Service standards, complaint resolution and guest experience.',20),
   (t.id,'MFG-YIELD','Production / Yield Achievement','target_output','manufacturing','percent','higher_better','Output, yield, waste or downtime target achievement.',20)
  on conflict(tenant_id,code) do nothing;
 end loop;
end $$;

create or replace function unimis.hr_performance_recalculate(p_tenant uuid,p_review uuid) returns jsonb language plpgsql security definer set search_path=unimis as $$
declare a numeric:=0;b numeric:=0;c numeric:=0; wa numeric:=50;wb numeric:=30;wc numeric:=20; total numeric; rating text;
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 select coalesce(target_output_weight,50),coalesce(responsibility_quality_weight,30),coalesce(professional_conduct_weight,20) into wa,wb,wc from hr_performance_policies where tenant_id=p_tenant and active order by effective_from desc limit 1;
 select coalesce(avg(final_score),0) into a from hr_performance_plan_items where tenant_id=p_tenant and review_id=p_review and pillar='target_output' and final_score is not null;
 select coalesce(avg(final_score),0) into b from hr_performance_plan_items where tenant_id=p_tenant and review_id=p_review and pillar='responsibility_quality' and final_score is not null;
 select coalesce(avg(final_score),0) into c from hr_performance_plan_items where tenant_id=p_tenant and review_id=p_review and pillar='professional_conduct' and final_score is not null;
 total:=round((a*wa+b*wb+c*wc)/100,2);
 rating:=case when total>=90 then 'Exceptional' when total>=80 then 'Exceeds Expectations' when total>=65 then 'Meets Expectations' when total>=50 then 'Needs Improvement' else 'Unsatisfactory' end;
 update hr_performance_reviews set target_output_score=a,responsibility_quality_score=b,professional_conduct_score=c,final_score=total,final_rating=rating where tenant_id=p_tenant and id=p_review;
 return jsonb_build_object('target_output',a,'responsibility_quality',b,'professional_conduct',c,'final_score',total,'rating',rating);
end $$;
grant execute on function unimis.hr_performance_recalculate(uuid,uuid) to authenticated;


-- SOURCE 202610221130_009h5_salary_reversal_constraint_fix.sql
-- HRPayrollCore 009h5
-- Permit audited salary-adjustment reversal history entries.
-- Preserves every previously allowed hr_salary_history.change_type value.

alter table unimis.hr_salary_history
  drop constraint if exists hr_salary_history_change_type_check;

alter table unimis.hr_salary_history
  add constraint hr_salary_history_change_type_check
  check (
    change_type = any (
      array[
        'initial'::text,
        'manual'::text,
        'grade_step'::text,
        'promotion'::text,
        'bulk_adjustment'::text,
        'correction'::text,
        'reversal'::text
      ]
    )
  );

notify pgrst, 'reload schema';


-- SOURCE 202610221140_009h6_exact_salary_reversal_constraint_fix.sql
-- HRPayrollCore 009h6
-- Exact compatibility fix for payroll_reverse_salary_batch().
-- The reversal RPC writes change_type = 'salary_adjustment_reversal'.

alter table unimis.hr_salary_history
  drop constraint if exists hr_salary_history_change_type_check;

alter table unimis.hr_salary_history
  add constraint hr_salary_history_change_type_check
  check (
    change_type = any (
      array[
        'initial'::text,
        'manual'::text,
        'grade_step'::text,
        'promotion'::text,
        'bulk_adjustment'::text,
        'correction'::text,
        'reversal'::text,
        'salary_adjustment_reversal'::text
      ]
    )
  );

notify pgrst, 'reload schema';


-- SOURCE 202610221230_010b_complete_pms_evaluation_workflow.sql
-- 010b Complete PMS Evaluation Workflow
-- Adds controlled plan activation and separate self/supervisor assessment evidence.

alter table unimis.hr_performance_reviews add column if not exists plan_status text not null default 'planning';
alter table unimis.hr_performance_reviews drop constraint if exists hr_performance_reviews_plan_status_check;
alter table unimis.hr_performance_reviews add constraint hr_performance_reviews_plan_status_check check(plan_status in ('planning','activated','amended','closed'));
alter table unimis.hr_performance_reviews add column if not exists plan_activated_at timestamptz;
alter table unimis.hr_performance_reviews add column if not exists self_assessment_at timestamptz;
alter table unimis.hr_performance_reviews add column if not exists supervisor_assessment_at timestamptz;

alter table unimis.hr_performance_plan_items add column if not exists self_comments text;
alter table unimis.hr_performance_plan_items add column if not exists supervisor_comments text;

-- Existing 010 plans that already contain measures remain editable until deliberately activated.
update unimis.hr_performance_reviews r
set plan_status='planning'
where plan_status is null;

-- Recalculate each pillar using the employee plan's item weights, normalized inside the pillar.
-- This lets each industry/position have a different number of measures without distorting the 50/30/20 policy weights.
create or replace function unimis.hr_performance_recalculate(p_tenant uuid,p_review uuid) returns jsonb language plpgsql security definer set search_path=unimis as $$
declare a numeric:=0;b numeric:=0;c numeric:=0; wa numeric:=50;wb numeric:=30;wc numeric:=20; total numeric; rating text;
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 select coalesce(target_output_weight,50),coalesce(responsibility_quality_weight,30),coalesce(professional_conduct_weight,20)
 into wa,wb,wc from hr_performance_policies where tenant_id=p_tenant and active order by effective_from desc limit 1;

 select coalesce(sum(final_score*greatest(weight,0))/nullif(sum(greatest(weight,0)),0),avg(final_score),0) into a
 from hr_performance_plan_items where tenant_id=p_tenant and review_id=p_review and pillar='target_output' and final_score is not null;
 select coalesce(sum(final_score*greatest(weight,0))/nullif(sum(greatest(weight,0)),0),avg(final_score),0) into b
 from hr_performance_plan_items where tenant_id=p_tenant and review_id=p_review and pillar='responsibility_quality' and final_score is not null;
 select coalesce(sum(final_score*greatest(weight,0))/nullif(sum(greatest(weight,0)),0),avg(final_score),0) into c
 from hr_performance_plan_items where tenant_id=p_tenant and review_id=p_review and pillar='professional_conduct' and final_score is not null;

 total:=round((a*wa+b*wb+c*wc)/nullif(wa+wb+wc,0),2);
 rating:=case when total>=90 then 'Exceptional' when total>=80 then 'Exceeds Expectations' when total>=65 then 'Meets Expectations' when total>=50 then 'Needs Improvement' else 'Unsatisfactory' end;
 update hr_performance_reviews set target_output_score=round(a,2),responsibility_quality_score=round(b,2),professional_conduct_score=round(c,2),supervisor_score=total,final_score=total,final_rating=rating where tenant_id=p_tenant and id=p_review;
 return jsonb_build_object('target_output',round(a,2),'responsibility_quality',round(b,2),'professional_conduct',round(c,2),'final_score',total,'rating',rating);
end $$;
grant execute on function unimis.hr_performance_recalculate(uuid,uuid) to authenticated;


-- SOURCE 202610230810_010e_pms_controlled_demo_seed.sql
-- 010e Controlled PMS demo seed
-- Reuses the existing 2026 cycle and employee records. Safe to rerun.
-- Test stages: Esi=active/check-ins, Ama=assessment, Kwame=completed/PIP.

do $$
declare
  v_tenant uuid; v_cycle uuid; v_esi uuid; v_ama uuid; v_kwame uuid;
  r_esi uuid; r_ama uuid; r_kwame uuid;
  m record;
begin
  select id into v_tenant from unimis.tenants where code='TECHCITY' limit 1;
  if v_tenant is null then raise notice '010e seed skipped: tenant TECHCITY not found'; return; end if;

  select id into v_cycle from unimis.hr_performance_cycles
   where tenant_id=v_tenant and name='2026 Annual Performance Review' order by created_at desc limit 1;
  if v_cycle is null then
    insert into unimis.hr_performance_cycles(tenant_id,name,cycle_type,start_date,end_date,status)
    values(v_tenant,'2026 Annual Performance Review','annual','2026-01-01','2026-12-31','open') returning id into v_cycle;
  else
    update unimis.hr_performance_cycles set status='open' where id=v_cycle;
  end if;

  select id into v_esi from unimis.hr_employees where tenant_id=v_tenant and employee_no='EMP003' limit 1;
  select id into v_ama from unimis.hr_employees where tenant_id=v_tenant and employee_no='EMP001' limit 1;
  select id into v_kwame from unimis.hr_employees where tenant_id=v_tenant and employee_no='EMP002' limit 1;
  if v_esi is null or v_ama is null or v_kwame is null then
    raise exception '010e seed requires EMP001 Ama, EMP002 Kwame and EMP003 Esi';
  end if;

  insert into unimis.hr_performance_reviews(tenant_id,cycle_id,employee_id,status,plan_status,plan_activated_at)
  values(v_tenant,v_cycle,v_esi,'draft','activated',now())
  on conflict(tenant_id,cycle_id,employee_id) do update set plan_status='activated',plan_activated_at=coalesce(hr_performance_reviews.plan_activated_at,now())
  returning id into r_esi;

  insert into unimis.hr_performance_reviews(tenant_id,cycle_id,employee_id,status,plan_status,plan_activated_at,self_assessment_at,supervisor_assessment_at)
  values(v_tenant,v_cycle,v_ama,'reviewed','activated',now(),now(),now())
  on conflict(tenant_id,cycle_id,employee_id) do update set status='reviewed',plan_status='activated',plan_activated_at=coalesce(hr_performance_reviews.plan_activated_at,now()),self_assessment_at=now(),supervisor_assessment_at=now()
  returning id into r_ama;

  insert into unimis.hr_performance_reviews(tenant_id,cycle_id,employee_id,status,plan_status,plan_activated_at,self_assessment_at,supervisor_assessment_at,completed_at,strengths,skill_gaps,recommended_action)
  values(v_tenant,v_cycle,v_kwame,'completed','closed',now(),now(),now(),now(),'Professional conduct, reliability and collaboration.','Target execution and work planning need improvement.','Targeted training, mentoring and a Performance Improvement Plan.')
  on conflict(tenant_id,cycle_id,employee_id) do update set status='completed',plan_status='closed',plan_activated_at=coalesce(hr_performance_reviews.plan_activated_at,now()),self_assessment_at=now(),supervisor_assessment_at=now(),completed_at=now(),strengths=excluded.strengths,skill_gaps=excluded.skill_gaps,recommended_action=excluded.recommended_action
  returning id into r_kwame;

  -- Controlled rerun: replace only demo plan/check-in/decision/PIP content for these three 2026 reviews.
  delete from unimis.hr_performance_checkins where tenant_id=v_tenant and review_id in (r_esi,r_ama,r_kwame);
  delete from unimis.hr_performance_decisions where tenant_id=v_tenant and review_id in (r_esi,r_ama,r_kwame);
  delete from unimis.hr_performance_improvement_plans where tenant_id=v_tenant and review_id in (r_esi,r_ama,r_kwame);
  delete from unimis.hr_performance_plan_items where tenant_id=v_tenant and review_id in (r_esi,r_ama,r_kwame);

  -- ESI: active baseline + check-ins; 2 target, 2 quality, 3 conduct = 100%.
  insert into unimis.hr_performance_plan_items(tenant_id,review_id,metric_id,pillar,title,description,unit,direction,target_value,actual_value,weight,due_date,status)
  select v_tenant,r_esi,id,pillar,name,description,unit,direction,
    case code when 'GEN-OUTPUT' then 90 when 'GEN-DEADLINE' then 90 when 'GEN-QUALITY' then 90 when 'GEN-SOP' then 90 when 'GEN-ATTEND' then 95 else 4 end,
    case code when 'GEN-OUTPUT' then 72 when 'GEN-DEADLINE' then 78 when 'GEN-QUALITY' then 84 when 'GEN-SOP' then 88 when 'GEN-ATTEND' then 96 when 'GEN-TEAM' then 4 else 4 end,
    case code when 'GEN-OUTPUT' then 20 when 'GEN-DEADLINE' then 20 when 'GEN-QUALITY' then 15 when 'GEN-SOP' then 15 when 'GEN-ATTEND' then 10 when 'GEN-TEAM' then 10 else 10 end,
    '2026-12-31',
    case when code in ('GEN-OUTPUT','GEN-DEADLINE') then 'on_track' else 'planned' end
  from unimis.hr_performance_metric_library where tenant_id=v_tenant and code in ('GEN-OUTPUT','GEN-DEADLINE','GEN-QUALITY','GEN-SOP','GEN-ATTEND','GEN-TEAM','GEN-CONDUCT');

  insert into unimis.hr_performance_checkins(tenant_id,review_id,checkin_date,progress_percent,status,achievements,blockers,support_required,next_actions,manager_comments) values
   (v_tenant,r_esi,'2026-04-30',32,'on_track','Core assignments delivered; attendance and teamwork strong.','Some delays obtaining source documents.','Earlier access to operational records.','Complete outstanding Q2 deliverables and document evidence.','Good start; maintain evidence for each target.'),
   (v_tenant,r_esi,'2026-07-31',58,'on_track','Quality improved and most deadlines met.','Competing operational priorities.','Priority clarification during peak periods.','Focus on target completion and reduce rework.','Progress is satisfactory with clear improvement.'),
   (v_tenant,r_esi,'2026-10-15',78,'on_track','Strong attendance, collaboration and SOP compliance.','Two deliverables remain behind schedule.','Weekly supervisor check-in until year end.','Close remaining deliverables before final appraisal.','On track overall; deadline discipline remains the key focus.');

  -- AMA: assessment-stage example with deliberate self/supervisor gap.
  insert into unimis.hr_performance_plan_items(tenant_id,review_id,metric_id,pillar,title,description,unit,direction,target_value,actual_value,weight,due_date,status,employee_score,supervisor_score,final_score,self_comments,supervisor_comments)
  select v_tenant,r_ama,id,pillar,name,description,unit,direction,
    case code when 'GEN-OUTPUT' then 90 when 'GEN-DEADLINE' then 90 when 'GEN-QUALITY' then 90 when 'GEN-SOP' then 90 when 'GEN-ATTEND' then 95 else 4 end,
    case code when 'GEN-OUTPUT' then 88 when 'GEN-DEADLINE' then 86 when 'GEN-QUALITY' then 90 when 'GEN-SOP' then 91 when 'GEN-ATTEND' then 97 when 'GEN-TEAM' then 4 else 4 end,
    case code when 'GEN-OUTPUT' then 20 when 'GEN-DEADLINE' then 20 when 'GEN-QUALITY' then 15 when 'GEN-SOP' then 15 when 'GEN-ATTEND' then 10 when 'GEN-TEAM' then 10 else 10 end,
    '2026-12-31','on_track',
    case code when 'GEN-OUTPUT' then 94 when 'GEN-DEADLINE' then 90 when 'GEN-QUALITY' then 93 when 'GEN-SOP' then 92 when 'GEN-ATTEND' then 96 when 'GEN-TEAM' then 92 else 95 end,
    case code when 'GEN-OUTPUT' then 84 when 'GEN-DEADLINE' then 82 when 'GEN-QUALITY' then 86 when 'GEN-SOP' then 85 when 'GEN-ATTEND' then 95 when 'GEN-TEAM' then 88 else 90 end,
    case code when 'GEN-OUTPUT' then 84 when 'GEN-DEADLINE' then 82 when 'GEN-QUALITY' then 86 when 'GEN-SOP' then 85 when 'GEN-ATTEND' then 95 when 'GEN-TEAM' then 88 else 90 end,
    'Employee self-assessment: strong delivery and professional contribution during the cycle.',
    'Supervisor assessment: strong overall performance; target evidence supports a slightly lower rating than the self-assessment.'
  from unimis.hr_performance_metric_library where tenant_id=v_tenant and code in ('GEN-OUTPUT','GEN-DEADLINE','GEN-QUALITY','GEN-SOP','GEN-ATTEND','GEN-TEAM','GEN-CONDUCT');

  perform unimis.hr_performance_recalculate(v_tenant,r_ama);

  -- KWAME: completed example: high professionalism but weaker output => development/PIP path.
  insert into unimis.hr_performance_plan_items(tenant_id,review_id,metric_id,pillar,title,description,unit,direction,target_value,actual_value,weight,due_date,status,employee_score,supervisor_score,final_score,self_comments,supervisor_comments)
  select v_tenant,r_kwame,id,pillar,name,description,unit,direction,
    case code when 'GEN-OUTPUT' then 90 when 'GEN-DEADLINE' then 90 when 'GEN-QUALITY' then 90 when 'GEN-SOP' then 90 when 'GEN-ATTEND' then 95 else 4 end,
    case code when 'GEN-OUTPUT' then 58 when 'GEN-DEADLINE' then 62 when 'GEN-QUALITY' then 74 when 'GEN-SOP' then 78 when 'GEN-ATTEND' then 97 when 'GEN-TEAM' then 4 else 4 end,
    case code when 'GEN-OUTPUT' then 20 when 'GEN-DEADLINE' then 20 when 'GEN-QUALITY' then 15 when 'GEN-SOP' then 15 when 'GEN-ATTEND' then 10 when 'GEN-TEAM' then 10 else 10 end,
    '2026-12-31',case when code in ('GEN-OUTPUT','GEN-DEADLINE') then 'at_risk' else 'on_track' end,
    case code when 'GEN-OUTPUT' then 70 when 'GEN-DEADLINE' then 68 when 'GEN-QUALITY' then 78 when 'GEN-SOP' then 80 when 'GEN-ATTEND' then 96 when 'GEN-TEAM' then 90 else 92 end,
    case code when 'GEN-OUTPUT' then 58 when 'GEN-DEADLINE' then 62 when 'GEN-QUALITY' then 74 when 'GEN-SOP' then 78 when 'GEN-ATTEND' then 96 when 'GEN-TEAM' then 90 else 92 end,
    case code when 'GEN-OUTPUT' then 58 when 'GEN-DEADLINE' then 62 when 'GEN-QUALITY' then 74 when 'GEN-SOP' then 78 when 'GEN-ATTEND' then 96 when 'GEN-TEAM' then 90 else 92 end,
    'Employee acknowledges target-delivery challenges but reports strong teamwork and reliability.',
    'Supervisor confirms good conduct but identifies a material output and planning gap requiring structured support.'
  from unimis.hr_performance_metric_library where tenant_id=v_tenant and code in ('GEN-OUTPUT','GEN-DEADLINE','GEN-QUALITY','GEN-SOP','GEN-ATTEND','GEN-TEAM','GEN-CONDUCT');

  perform unimis.hr_performance_recalculate(v_tenant,r_kwame);
  update unimis.hr_performance_reviews set status='completed',plan_status='closed',completed_at=now(),strengths='Professional conduct, attendance and collaboration.',skill_gaps='Target execution, prioritisation and deadline management.',recommended_action='Training + mentoring + monitored Performance Improvement Plan.' where id=r_kwame;

  insert into unimis.hr_performance_decisions(tenant_id,review_id,action_type,rationale,status) values
   (v_tenant,r_kwame,'training','Target output is below expectation while professional conduct remains strong; targeted skills development is appropriate.','approved'),
   (v_tenant,r_kwame,'mentoring','Provide structured work-planning and prioritisation support.','approved'),
   (v_tenant,r_kwame,'pip','Use measurable improvement targets and scheduled supervisor reviews.','approved');

  insert into unimis.hr_performance_improvement_plans(tenant_id,employee_id,review_id,title,objectives,actions_support,start_date,review_date,status)
  values(v_tenant,v_kwame,r_kwame,'2026 Target Delivery Improvement Plan','Improve target completion and deadline delivery to at least 80% while maintaining current professional conduct.','Weekly planning review with supervisor; prioritisation coaching; targeted training; monthly evidence-based progress review.','2026-10-23','2026-12-23','open');

  raise notice '010e PMS demo seed complete: Esi active/check-ins, Ama assessed, Kwame completed/PIP.';
end $$;


-- SOURCE 202610230845_010g_pms_verified_demo_seed_tenant_fix.sql
-- 010g PMS verified controlled demo seed fix (corrected for migration execution context)
-- Guarantees the generic metric library exists, reuses one 2026 cycle, seeds three staged reviews,
-- and aborts the migration if the expected demo state is not present.
do $$
declare
 v_tenant uuid; v_cycle uuid; v_esi uuid; v_ama uuid; v_kwame uuid;
 r_esi uuid; r_ama uuid; r_kwame uuid; n int; w numeric;
begin
 select e.tenant_id into v_tenant
 from unimis.hr_employees e
 where e.employee_no in ('EMP001','EMP002','EMP003')
 group by e.tenant_id
 having count(distinct e.employee_no)=3
 order by e.tenant_id
 limit 1;
 if v_tenant is null then raise exception '010g: could not find EMP001, EMP002 and EMP003 under one tenant'; end if;
 select id into v_esi from unimis.hr_employees where tenant_id=v_tenant and employee_no='EMP003' limit 1;
 select id into v_ama from unimis.hr_employees where tenant_id=v_tenant and employee_no='EMP001' limit 1;
 select id into v_kwame from unimis.hr_employees where tenant_id=v_tenant and employee_no='EMP002' limit 1;
 if v_esi is null or v_ama is null or v_kwame is null then raise exception '010g requires EMP001, EMP002 and EMP003'; end if;

 select id into v_cycle from unimis.hr_performance_cycles where tenant_id=v_tenant and name='2026 Annual Performance Review' order by created_at desc limit 1;
 if v_cycle is null then
  insert into unimis.hr_performance_cycles(tenant_id,name,cycle_type,start_date,end_date,status)
  values(v_tenant,'2026 Annual Performance Review','annual','2026-01-01','2026-12-31','open') returning id into v_cycle;
 else update unimis.hr_performance_cycles set status='open',start_date='2026-01-01',end_date='2026-12-31' where id=v_cycle; end if;

 -- Guarantee the seven generic metrics required by the controlled test.
 insert into unimis.hr_performance_metric_library(tenant_id,code,name,pillar,industry,unit,direction,description,default_target,default_weight,active) values
 (v_tenant,'GEN-OUTPUT','Target / Output Achievement','target_output','general','percent','higher_better','Achievement against agreed quantitative targets, deliverables or milestones.',90,20,true),
 (v_tenant,'GEN-DEADLINE','Deadline Delivery','target_output','general','percent','higher_better','Delivery of agreed work within committed timelines.',90,20,true),
 (v_tenant,'GEN-QUALITY','Work Quality & Accuracy','responsibility_quality','general','percent','higher_better','Accuracy, completeness, rework and quality of assigned responsibilities.',90,15,true),
 (v_tenant,'GEN-SOP','Responsibility / SOP Execution','responsibility_quality','general','percent','higher_better','Execution of job-description duties, procedures and controls.',90,15,true),
 (v_tenant,'GEN-ATTEND','Attendance & Punctuality','professional_conduct','general','percent','higher_better','Attendance and punctuality considered with authorised context.',95,10,true),
 (v_tenant,'GEN-TEAM','Collaboration & Communication','professional_conduct','general','score','higher_better','Teamwork, communication and constructive workplace behaviour.',4,10,true),
 (v_tenant,'GEN-CONDUCT','Professional Conduct & Ethics','professional_conduct','general','score','higher_better','Integrity, professionalism and adherence to organisational values.',4,10,true)
 on conflict(tenant_id,code) do update set name=excluded.name,pillar=excluded.pillar,industry=excluded.industry,unit=excluded.unit,direction=excluded.direction,description=excluded.description,default_target=excluded.default_target,default_weight=excluded.default_weight,active=true;

 insert into unimis.hr_performance_reviews(tenant_id,cycle_id,employee_id,status,plan_status,plan_activated_at)
 values(v_tenant,v_cycle,v_esi,'draft','activated',now()) on conflict(tenant_id,cycle_id,employee_id) do update set plan_status='activated',plan_activated_at=coalesce(unimis.hr_performance_reviews.plan_activated_at,now()) returning id into r_esi;
 insert into unimis.hr_performance_reviews(tenant_id,cycle_id,employee_id,status,plan_status,plan_activated_at,self_assessment_at,supervisor_assessment_at)
 values(v_tenant,v_cycle,v_ama,'reviewed','activated',now(),now(),now()) on conflict(tenant_id,cycle_id,employee_id) do update set status='reviewed',plan_status='activated',plan_activated_at=coalesce(unimis.hr_performance_reviews.plan_activated_at,now()),self_assessment_at=now(),supervisor_assessment_at=now() returning id into r_ama;
 insert into unimis.hr_performance_reviews(tenant_id,cycle_id,employee_id,status,plan_status,plan_activated_at,self_assessment_at,supervisor_assessment_at,completed_at,strengths,skill_gaps,recommended_action)
 values(v_tenant,v_cycle,v_kwame,'completed','closed',now(),now(),now(),now(),'Professional conduct, reliability and collaboration.','Target execution and work planning need improvement.','Training + mentoring + monitored Performance Improvement Plan.') on conflict(tenant_id,cycle_id,employee_id) do update set status='completed',plan_status='closed',completed_at=now(),strengths=excluded.strengths,skill_gaps=excluded.skill_gaps,recommended_action=excluded.recommended_action returning id into r_kwame;

 delete from unimis.hr_performance_checkins where tenant_id=v_tenant and review_id in(r_esi,r_ama,r_kwame);
 delete from unimis.hr_performance_decisions where tenant_id=v_tenant and review_id in(r_esi,r_ama,r_kwame);
 delete from unimis.hr_performance_improvement_plans where tenant_id=v_tenant and review_id in(r_esi,r_ama,r_kwame);
 delete from unimis.hr_performance_plan_items where tenant_id=v_tenant and review_id in(r_esi,r_ama,r_kwame);

 -- Esi baseline: 7 measures, total weight 100.
 insert into unimis.hr_performance_plan_items(tenant_id,review_id,metric_id,pillar,title,description,unit,direction,target_value,actual_value,weight,due_date,status)
 select v_tenant,r_esi,id,pillar,name,description,unit,direction,default_target,
 case code when 'GEN-OUTPUT' then 72 when 'GEN-DEADLINE' then 78 when 'GEN-QUALITY' then 84 when 'GEN-SOP' then 88 when 'GEN-ATTEND' then 96 else 4 end,
 default_weight,'2026-12-31',case when code in('GEN-OUTPUT','GEN-DEADLINE') then 'on_track' else 'planned' end
 from unimis.hr_performance_metric_library where tenant_id=v_tenant and code in('GEN-OUTPUT','GEN-DEADLINE','GEN-QUALITY','GEN-SOP','GEN-ATTEND','GEN-TEAM','GEN-CONDUCT');
 insert into unimis.hr_performance_checkins(tenant_id,review_id,checkin_date,progress_percent,status,achievements,blockers,support_required,next_actions,manager_comments) values
 (v_tenant,r_esi,'2026-04-30',32,'on_track','Core assignments delivered; attendance and teamwork strong.','Some delays obtaining source documents.','Earlier access to operational records.','Complete outstanding Q2 deliverables and document evidence.','Good start; maintain evidence for each target.'),
 (v_tenant,r_esi,'2026-07-31',58,'on_track','Quality improved and most deadlines met.','Competing operational priorities.','Priority clarification during peak periods.','Focus on target completion and reduce rework.','Progress is satisfactory with clear improvement.'),
 (v_tenant,r_esi,'2026-10-15',78,'on_track','Strong attendance, collaboration and SOP compliance.','Two deliverables remain behind schedule.','Weekly supervisor check-in until year end.','Close remaining deliverables before final appraisal.','On track overall; deadline discipline remains the key focus.');

 -- Ama assessment stage.
 insert into unimis.hr_performance_plan_items(tenant_id,review_id,metric_id,pillar,title,description,unit,direction,target_value,actual_value,weight,due_date,status,employee_score,supervisor_score,final_score,self_comments,supervisor_comments)
 select v_tenant,r_ama,id,pillar,name,description,unit,direction,default_target,
 case code when 'GEN-OUTPUT' then 88 when 'GEN-DEADLINE' then 86 when 'GEN-QUALITY' then 90 when 'GEN-SOP' then 91 when 'GEN-ATTEND' then 97 else 4 end,
 default_weight,'2026-12-31','on_track',
 case code when 'GEN-OUTPUT' then 94 when 'GEN-DEADLINE' then 90 when 'GEN-QUALITY' then 93 when 'GEN-SOP' then 92 when 'GEN-ATTEND' then 96 when 'GEN-TEAM' then 92 else 95 end,
 case code when 'GEN-OUTPUT' then 84 when 'GEN-DEADLINE' then 82 when 'GEN-QUALITY' then 86 when 'GEN-SOP' then 85 when 'GEN-ATTEND' then 95 when 'GEN-TEAM' then 88 else 90 end,
 case code when 'GEN-OUTPUT' then 84 when 'GEN-DEADLINE' then 82 when 'GEN-QUALITY' then 86 when 'GEN-SOP' then 85 when 'GEN-ATTEND' then 95 when 'GEN-TEAM' then 88 else 90 end,
 'Employee self-assessment: strong delivery and professional contribution.','Supervisor: strong overall performance; target evidence supports a slightly lower rating.'
 from unimis.hr_performance_metric_library where tenant_id=v_tenant and code in('GEN-OUTPUT','GEN-DEADLINE','GEN-QUALITY','GEN-SOP','GEN-ATTEND','GEN-TEAM','GEN-CONDUCT');
 -- Seed migrations run without an authenticated app user, so do not call the tenant-guarded RPC here.
 -- Calculate the same three-pillar score directly for the seeded review.
 update unimis.hr_performance_reviews r set
  target_output_score=x.a, responsibility_quality_score=x.b, professional_conduct_score=x.c,
  self_score=x.self_total, supervisor_score=x.total, final_score=x.total,
  final_rating=case when x.total>=90 then 'Exceptional' when x.total>=80 then 'Exceeds Expectations' when x.total>=65 then 'Meets Expectations' when x.total>=50 then 'Needs Improvement' else 'Unsatisfactory' end
 from (
  select
   round(coalesce(sum(final_score*weight) filter(where pillar='target_output')/nullif(sum(weight) filter(where pillar='target_output'),0),0),2) a,
   round(coalesce(sum(final_score*weight) filter(where pillar='responsibility_quality')/nullif(sum(weight) filter(where pillar='responsibility_quality'),0),0),2) b,
   round(coalesce(sum(final_score*weight) filter(where pillar='professional_conduct')/nullif(sum(weight) filter(where pillar='professional_conduct'),0),0),2) c,
   round(coalesce(sum(employee_score*weight)/nullif(sum(weight),0),0),2) self_total,
   round(coalesce(sum(final_score*weight)/nullif(sum(weight),0),0),2) total
  from unimis.hr_performance_plan_items where tenant_id=v_tenant and review_id=r_ama
 ) x where r.id=r_ama and r.tenant_id=v_tenant;

 -- Kwame completed development/PIP scenario.
 insert into unimis.hr_performance_plan_items(tenant_id,review_id,metric_id,pillar,title,description,unit,direction,target_value,actual_value,weight,due_date,status,employee_score,supervisor_score,final_score,self_comments,supervisor_comments)
 select v_tenant,r_kwame,id,pillar,name,description,unit,direction,default_target,
 case code when 'GEN-OUTPUT' then 58 when 'GEN-DEADLINE' then 62 when 'GEN-QUALITY' then 74 when 'GEN-SOP' then 78 when 'GEN-ATTEND' then 97 else 4 end,
 default_weight,'2026-12-31',case when code in('GEN-OUTPUT','GEN-DEADLINE') then 'at_risk' else 'on_track' end,
 case code when 'GEN-OUTPUT' then 70 when 'GEN-DEADLINE' then 68 when 'GEN-QUALITY' then 78 when 'GEN-SOP' then 80 when 'GEN-ATTEND' then 96 when 'GEN-TEAM' then 90 else 92 end,
 case code when 'GEN-OUTPUT' then 58 when 'GEN-DEADLINE' then 62 when 'GEN-QUALITY' then 74 when 'GEN-SOP' then 78 when 'GEN-ATTEND' then 96 when 'GEN-TEAM' then 90 else 92 end,
 case code when 'GEN-OUTPUT' then 58 when 'GEN-DEADLINE' then 62 when 'GEN-QUALITY' then 74 when 'GEN-SOP' then 78 when 'GEN-ATTEND' then 96 when 'GEN-TEAM' then 90 else 92 end,
 'Employee acknowledges target-delivery challenges but reports strong teamwork and reliability.','Supervisor confirms good conduct but identifies a material output and planning gap requiring structured support.'
 from unimis.hr_performance_metric_library where tenant_id=v_tenant and code in('GEN-OUTPUT','GEN-DEADLINE','GEN-QUALITY','GEN-SOP','GEN-ATTEND','GEN-TEAM','GEN-CONDUCT');
 -- Seed migrations run without an authenticated app user, so do not call the tenant-guarded RPC here.
 -- Calculate the same three-pillar score directly for the seeded review.
 update unimis.hr_performance_reviews r set
  target_output_score=x.a, responsibility_quality_score=x.b, professional_conduct_score=x.c,
  self_score=x.self_total, supervisor_score=x.total, final_score=x.total,
  final_rating=case when x.total>=90 then 'Exceptional' when x.total>=80 then 'Exceeds Expectations' when x.total>=65 then 'Meets Expectations' when x.total>=50 then 'Needs Improvement' else 'Unsatisfactory' end
 from (
  select
   round(coalesce(sum(final_score*weight) filter(where pillar='target_output')/nullif(sum(weight) filter(where pillar='target_output'),0),0),2) a,
   round(coalesce(sum(final_score*weight) filter(where pillar='responsibility_quality')/nullif(sum(weight) filter(where pillar='responsibility_quality'),0),0),2) b,
   round(coalesce(sum(final_score*weight) filter(where pillar='professional_conduct')/nullif(sum(weight) filter(where pillar='professional_conduct'),0),0),2) c,
   round(coalesce(sum(employee_score*weight)/nullif(sum(weight),0),0),2) self_total,
   round(coalesce(sum(final_score*weight)/nullif(sum(weight),0),0),2) total
  from unimis.hr_performance_plan_items where tenant_id=v_tenant and review_id=r_kwame
 ) x where r.id=r_kwame and r.tenant_id=v_tenant;
 update unimis.hr_performance_reviews set status='completed',plan_status='closed',completed_at=now() where id=r_kwame;
 insert into unimis.hr_performance_decisions(tenant_id,review_id,action_type,rationale,status) values
 (v_tenant,r_kwame,'training','Output is below expectation while conduct remains strong; targeted development is appropriate.','approved'),
 (v_tenant,r_kwame,'mentoring','Provide structured work-planning and prioritisation support.','approved'),
 (v_tenant,r_kwame,'pip','Use measurable improvement targets and scheduled supervisor reviews.','approved');
 insert into unimis.hr_performance_improvement_plans(tenant_id,employee_id,review_id,title,objectives,actions_support,start_date,review_date,status)
 values(v_tenant,v_kwame,r_kwame,'2026 Target Delivery Improvement Plan','Improve target completion and deadline delivery to at least 80% while maintaining professional conduct.','Weekly supervisor planning review; prioritisation coaching; targeted training; monthly evidence-based progress review.','2026-10-23','2026-12-23','open');

 -- Self-verification. Any mismatch aborts the migration rather than reporting false success.
 select count(*),coalesce(sum(weight),0) into n,w from unimis.hr_performance_plan_items where review_id=r_esi;
 if n<>7 or w<>100 then raise exception '010g verification failed for Esi: expected 7 measures / 100 weight, got % / %',n,w; end if;
 select count(*) into n from unimis.hr_performance_checkins where review_id=r_esi; if n<>3 then raise exception '010g verification failed for Esi check-ins: expected 3, got %',n; end if;
 select count(*) into n from unimis.hr_performance_plan_items where review_id=r_ama and employee_score is not null and supervisor_score is not null; if n<>7 then raise exception '010g verification failed for Ama assessments: expected 7, got %',n; end if;
 select count(*) into n from unimis.hr_performance_plan_items where review_id=r_kwame and final_score is not null; if n<>7 then raise exception '010g verification failed for Kwame scorecard: expected 7, got %',n; end if;
 select count(*) into n from unimis.hr_performance_decisions where review_id=r_kwame; if n<>3 then raise exception '010g verification failed for Kwame decisions: expected 3, got %',n; end if;
 select count(*) into n from unimis.hr_performance_improvement_plans where review_id=r_kwame and status='open'; if n<>1 then raise exception '010g verification failed for Kwame PIP: expected 1 open PIP, got %',n; end if;
 raise notice '010g verified: Esi 7/100 + 3 check-ins; Ama 7 assessed; Kwame 7 completed + 3 decisions + PIP.';
end $$;


-- SOURCE 202610230930_010h_pms_finalization_lifecycle.sql
-- 010h PMS lifecycle: provisional scoring is distinct from approved/finalized results.
-- Existing historical completed appraisals are preserved as finalized. The controlled 2026 demo
-- reviews for Ama/Kwame are returned to pre-final state so the remaining workflow can be tested.

alter table unimis.hr_performance_reviews
  add column if not exists provisional_score numeric(6,2),
  add column if not exists provisional_rating text,
  add column if not exists finalization_status text not null default 'not_started',
  add column if not exists finalized_at timestamptz,
  add column if not exists finalized_by uuid;

do $$ begin
  if not exists(select 1 from pg_constraint where conname='hr_performance_reviews_finalization_status_check') then
    alter table unimis.hr_performance_reviews add constraint hr_performance_reviews_finalization_status_check
      check(finalization_status in ('not_started','pending_approval','finalized'));
  end if;
end $$;

-- Preserve genuinely completed historical records as finalized before changing calculation semantics.
update unimis.hr_performance_reviews
set provisional_score=coalesce(provisional_score,final_score),
    provisional_rating=coalesce(provisional_rating,final_rating),
    finalization_status='finalized',
    finalized_at=coalesce(finalized_at,completed_at,now())
where status='completed' and finalization_status<>'finalized';

-- Reviewed records may already contain a calculated score from the old engine. It is provisional.
update unimis.hr_performance_reviews
set provisional_score=coalesce(provisional_score,final_score),
    provisional_rating=coalesce(provisional_rating,final_rating),
    final_score=null,
    final_rating=null,
    finalization_status='not_started',
    finalized_at=null,
    finalized_by=null
where status<>'completed';

-- The controlled 2026 Kwame demo was marked completed only to demonstrate downstream data.
-- Return it to supervisor-reviewed state so final approval can be tested properly.
update unimis.hr_performance_reviews r
set status='reviewed', plan_status='activated', completed_at=null,
    provisional_score=coalesce(r.provisional_score,r.final_score),
    provisional_rating=coalesce(r.provisional_rating,r.final_rating),
    final_score=null, final_rating=null, finalization_status='not_started', finalized_at=null, finalized_by=null
from unimis.hr_employees e, unimis.hr_performance_cycles c, unimis.tenants t
where r.employee_id=e.id and r.cycle_id=c.id and r.tenant_id=t.id
  and e.employee_no='EMP002' and c.name='2026 Annual Performance Review' and t.code='TCC001';

create or replace function unimis.hr_performance_recalculate(p_tenant uuid,p_review uuid) returns jsonb language plpgsql security definer set search_path=unimis as $$
declare a numeric:=0;b numeric:=0;c numeric:=0; wa numeric:=50;wb numeric:=30;wc numeric:=20; total numeric; rating text; fin text;
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 select finalization_status into fin from hr_performance_reviews where tenant_id=p_tenant and id=p_review;
 if fin='finalized' then raise exception 'Finalized appraisal is locked'; end if;
 select coalesce(target_output_weight,50),coalesce(responsibility_quality_weight,30),coalesce(professional_conduct_weight,20)
 into wa,wb,wc from hr_performance_policies where tenant_id=p_tenant and active order by effective_from desc limit 1;

 select coalesce(sum(final_score*greatest(weight,0))/nullif(sum(greatest(weight,0)),0),avg(final_score),0) into a
 from hr_performance_plan_items where tenant_id=p_tenant and review_id=p_review and pillar='target_output' and final_score is not null;
 select coalesce(sum(final_score*greatest(weight,0))/nullif(sum(greatest(weight,0)),0),avg(final_score),0) into b
 from hr_performance_plan_items where tenant_id=p_tenant and review_id=p_review and pillar='responsibility_quality' and final_score is not null;
 select coalesce(sum(final_score*greatest(weight,0))/nullif(sum(greatest(weight,0)),0),avg(final_score),0) into c
 from hr_performance_plan_items where tenant_id=p_tenant and review_id=p_review and pillar='professional_conduct' and final_score is not null;

 total:=round((a*wa+b*wb+c*wc)/nullif(wa+wb+wc,0),2);
 rating:=case when total>=90 then 'Exceptional' when total>=80 then 'Exceeds Expectations' when total>=65 then 'Meets Expectations' when total>=50 then 'Needs Improvement' else 'Unsatisfactory' end;
 update hr_performance_reviews set target_output_score=round(a,2),responsibility_quality_score=round(b,2),professional_conduct_score=round(c,2),supervisor_score=total,provisional_score=total,provisional_rating=rating,final_score=null,final_rating=null where tenant_id=p_tenant and id=p_review;
 return jsonb_build_object('target_output',round(a,2),'responsibility_quality',round(b,2),'professional_conduct',round(c,2),'provisional_score',total,'provisional_rating',rating);
end $$;

-- Database guard: finalized plan items cannot be silently changed or removed.
create or replace function unimis.hr_performance_guard_finalized_item() returns trigger language plpgsql set search_path=unimis as $$
declare rid uuid; fin text;
begin
 rid:=coalesce(new.review_id,old.review_id);
 select finalization_status into fin from hr_performance_reviews where id=rid;
 if fin='finalized' then raise exception 'Finalized appraisal is locked; use a controlled amendment workflow'; end if;
 return coalesce(new,old);
end $$;

drop trigger if exists trg_hr_performance_guard_finalized_item on unimis.hr_performance_plan_items;
create trigger trg_hr_performance_guard_finalized_item before update or delete on unimis.hr_performance_plan_items
for each row execute function unimis.hr_performance_guard_finalized_item();


-- SOURCE 202610231120_010j_pms_checkin_evidence.sql
-- 010j: strengthen performance check-ins with explicit actual-result and evidence capture.
-- Existing check-ins remain valid; new fields are nullable for backward compatibility.
alter table unimis.hr_performance_checkins
  add column if not exists actual_progress text,
  add column if not exists evidence text;

comment on column unimis.hr_performance_checkins.actual_progress is
  'Narrative of actual results/progress achieved against the agreed performance baseline at this check-in.';
comment on column unimis.hr_performance_checkins.evidence is
  'Evidence supporting the check-in, e.g. reports, records, links, observations, feedback or document references.';


-- SOURCE 202610231150_010k_pms_evidence_assessment_decision_engine.sql
-- 010k Evidence-led assessment and rules-based performance decision engine.
-- Human input validates evidence; objective scoring is calculated by the system.

alter table unimis.hr_performance_plan_items
  add column if not exists system_score numeric(6,2),
  add column if not exists supervisor_validation text not null default 'pending',
  add column if not exists validation_reason text,
  add column if not exists scoring_source text not null default 'system';

do $$ begin
  if not exists(select 1 from pg_constraint where conname='hr_perf_item_validation_check') then
    alter table unimis.hr_performance_plan_items add constraint hr_perf_item_validation_check
      check(supervisor_validation in ('pending','confirmed','disputed'));
  end if;
end $$;

alter table unimis.hr_performance_decisions
  add column if not exists rule_code text,
  add column if not exists proposed_value numeric(10,2),
  add column if not exists system_generated boolean not null default false;

create table if not exists unimis.hr_performance_decision_rules(
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references unimis.tenants(id) on delete cascade,
  code text not null,
  action_type text not null check(action_type in ('recognition','merit_bonus','salary_increment','promotion','training','mentoring','workload_realignment','pip','conduct_coaching','management_review','succession_pool','no_action','other')),
  min_final_score numeric(6,2),
  max_final_score numeric(6,2),
  min_conduct_score numeric(6,2),
  increment_percent numeric(6,2),
  require_no_open_pip boolean not null default false,
  active boolean not null default true,
  approval_required boolean not null default true,
  description text,
  created_at timestamptz not null default now(),
  unique(tenant_id,code)
);
alter table unimis.hr_performance_decision_rules enable row level security;
drop policy if exists tenant_member_all on unimis.hr_performance_decision_rules;
create policy tenant_member_all on unimis.hr_performance_decision_rules for all
using (unimis.is_tenant_member(tenant_id)) with check (unimis.is_tenant_member(tenant_id));

-- Safe starter rules. They create recommendations only; they never change salary, grade or employment automatically.
do $$ declare t record; begin
 for t in select id from unimis.tenants loop
  insert into unimis.hr_performance_decision_rules(tenant_id,code,action_type,min_final_score,max_final_score,min_conduct_score,increment_percent,require_no_open_pip,description) values
   (t.id,'PERF-PROMO-85','promotion',85,null,80,null,true,'Promotion eligibility: strong approved performance, conduct >=80 and no open PIP.'),
   (t.id,'PERF-INCR-90','salary_increment',90,null,80,8,true,'8% performance increment recommendation for approved score >=90.'),
   (t.id,'PERF-INCR-80','salary_increment',80,89.99,75,5,true,'5% performance increment recommendation for approved score 80-89.99.'),
   (t.id,'PERF-INCR-70','salary_increment',70,79.99,70,2,true,'2% performance increment recommendation for approved score 70-79.99.'),
   (t.id,'PERF-TRAIN-50','training',50,69.99,null,null,false,'Targeted development recommended for performance between 50 and 69.99.'),
   (t.id,'PERF-PIP-LOW','pip',null,49.99,null,null,false,'PIP recommended when approved performance is below 50.')
  on conflict(tenant_id,code) do nothing;
 end loop;
end $$;

-- Calculate objective item scores from agreed target vs actual. Scores are capped at 100 for appraisal weighting.
create or replace function unimis.hr_performance_system_score(p_tenant uuid,p_review uuid) returns jsonb
language plpgsql security definer set search_path=unimis as $$
declare n integer:=0;
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 if exists(select 1 from hr_performance_reviews where tenant_id=p_tenant and id=p_review and finalization_status='finalized') then
   raise exception 'Finalized appraisal is locked';
 end if;
 update hr_performance_plan_items
 set system_score = case
   when actual_value is null or target_value is null then null
   when direction='higher_better' and target_value<>0 then round(least(100,(actual_value/target_value)*100),2)
   when direction='lower_better' and actual_value<>0 then round(least(100,(target_value/actual_value)*100),2)
   when direction='pass_fail' then case when actual_value>=target_value then 100 else 0 end
   when direction='milestone' and target_value<>0 then round(least(100,(actual_value/target_value)*100),2)
   else null end,
   scoring_source='system'
 where tenant_id=p_tenant and review_id=p_review;
 get diagnostics n=row_count;
 return jsonb_build_object('items_scored',n);
end $$;
grant execute on function unimis.hr_performance_system_score(uuid,uuid) to authenticated;

-- Supervisor validates system evidence. A dispute never permits a secret arbitrary score: it requires a reason
-- and remains visible for calibration. Confirmed system score becomes the provisional assessed score.
create or replace function unimis.hr_performance_validate_item(p_tenant uuid,p_item uuid,p_validation text,p_reason text default null) returns jsonb
language plpgsql security definer set search_path=unimis as $$
declare rid uuid; s numeric;
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 if p_validation not in ('confirmed','disputed') then raise exception 'Validation must be confirmed or disputed'; end if;
 if p_validation='disputed' and coalesce(length(trim(p_reason)),0)<10 then raise exception 'A meaningful reason is required when disputing system evidence'; end if;
 select review_id,system_score into rid,s from hr_performance_plan_items where tenant_id=p_tenant and id=p_item;
 if rid is null then raise exception 'Performance item not found'; end if;
 if s is null then raise exception 'System score unavailable; capture actual result first'; end if;
 update hr_performance_plan_items
 set supervisor_validation=p_validation,validation_reason=nullif(trim(p_reason),''),
     supervisor_score=case when p_validation='confirmed' then s else null end,
     final_score=case when p_validation='confirmed' then s else null end,
     status=case when p_validation='confirmed' and s>=100 then 'exceeded' when p_validation='confirmed' and s>=70 then 'on_track' when p_validation='confirmed' then 'at_risk' else status end
 where tenant_id=p_tenant and id=p_item;
 return jsonb_build_object('review_id',rid,'validation',p_validation,'system_score',s);
end $$;
grant execute on function unimis.hr_performance_validate_item(uuid,uuid,text,text) to authenticated;

-- Rules engine: after finalization, generate auditable recommendations. Consequential actions still require approval.
create or replace function unimis.hr_performance_evaluate_decisions(p_tenant uuid,p_review uuid) returns jsonb
language plpgsql security definer set search_path=unimis as $$
declare r record; rev record; open_pip integer:=0; created integer:=0;
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 select * into rev from hr_performance_reviews where tenant_id=p_tenant and id=p_review;
 if rev.id is null then raise exception 'Review not found'; end if;
 if rev.finalization_status<>'finalized' or rev.final_score is null then raise exception 'Finalize the appraisal before running decision rules'; end if;
 select count(*) into open_pip from hr_performance_improvement_plans where tenant_id=p_tenant and review_id=p_review and status='open';
 for r in select * from hr_performance_decision_rules where tenant_id=p_tenant and active loop
   if (r.min_final_score is null or rev.final_score>=r.min_final_score)
      and (r.max_final_score is null or rev.final_score<=r.max_final_score)
      and (r.min_conduct_score is null or coalesce(rev.professional_conduct_score,0)>=r.min_conduct_score)
      and (not r.require_no_open_pip or open_pip=0) then
     if not exists(select 1 from hr_performance_decisions where tenant_id=p_tenant and review_id=p_review and rule_code=r.code and status<>'cancelled') then
       insert into hr_performance_decisions(tenant_id,review_id,action_type,rationale,status,rule_code,proposed_value,system_generated)
       values(p_tenant,p_review,r.action_type,r.description,'recommended',r.code,r.increment_percent,true);
       created:=created+1;
     end if;
   end if;
 end loop;
 return jsonb_build_object('recommendations_created',created,'final_score',rev.final_score,'conduct_score',rev.professional_conduct_score);
end $$;
grant execute on function unimis.hr_performance_evaluate_decisions(uuid,uuid) to authenticated;


-- SOURCE 202610231430_010l_performance_intelligence_engine.sql
-- 010l Performance Intelligence Engine foundation
-- Evidence per measure -> verified actual -> deterministic score -> integrity signal -> governed decision rules.

alter table unimis.hr_performance_plan_items
  add column if not exists evidence_count integer not null default 0,
  add column if not exists latest_evidence_source text,
  add column if not exists integrity_flag text not null default 'normal';

do $$ begin
 if not exists(select 1 from pg_constraint where conname='hr_perf_integrity_flag_check') then
  alter table unimis.hr_performance_plan_items add constraint hr_perf_integrity_flag_check check(integrity_flag in ('normal','review'));
 end if;
end $$;

create table if not exists unimis.hr_performance_checkin_items(
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references unimis.tenants(id) on delete cascade,
 checkin_id uuid not null references unimis.hr_performance_checkins(id) on delete cascade,
 review_id uuid not null references unimis.hr_performance_reviews(id) on delete cascade,
 plan_item_id uuid not null references unimis.hr_performance_plan_items(id) on delete cascade,
 actual_value numeric(14,2) not null,
 evidence text,
 evidence_source text not null default 'manager_observation' check(evidence_source in ('system_record','document','manager_observation','employee_submission','customer_feedback','other')),
 created_by uuid default auth.uid(),
 created_at timestamptz not null default now()
);
alter table unimis.hr_performance_checkin_items enable row level security;
drop policy if exists tenant_member_all on unimis.hr_performance_checkin_items;
create policy tenant_member_all on unimis.hr_performance_checkin_items for all using(unimis.is_tenant_member(tenant_id)) with check(unimis.is_tenant_member(tenant_id));
create index if not exists idx_perf_checkin_items_review on unimis.hr_performance_checkin_items(review_id,plan_item_id,created_at desc);

create or replace function unimis.hr_performance_refresh_intelligence(p_tenant uuid,p_review uuid) returns jsonb
language plpgsql security definer set search_path=unimis as $$
declare v_progress numeric(6,2); v_weight numeric(8,2); v_scored integer;
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 if exists(select 1 from hr_performance_reviews where tenant_id=p_tenant and id=p_review and finalization_status='finalized') then raise exception 'Finalized appraisal is locked'; end if;

 -- Latest evidence-backed actual becomes the verified actual. Existing actuals remain valid for legacy/demo records.
 with latest as (
  select distinct on (plan_item_id) plan_item_id,actual_value,evidence_source
  from hr_performance_checkin_items where tenant_id=p_tenant and review_id=p_review
  order by plan_item_id,created_at desc,id desc
 ), counts as (
  select plan_item_id,count(*)::int evidence_count from hr_performance_checkin_items where tenant_id=p_tenant and review_id=p_review group by plan_item_id
 )
 update hr_performance_plan_items p set
  actual_value=coalesce(l.actual_value,p.actual_value),
  latest_evidence_source=coalesce(l.evidence_source,p.latest_evidence_source),
  evidence_count=coalesce(c.evidence_count,p.evidence_count,0)
 from latest l left join counts c on c.plan_item_id=l.plan_item_id
 where p.tenant_id=p_tenant and p.review_id=p_review and p.id=l.plan_item_id;

 -- Backfill evidence count for items with no latest CTE row and preserve legacy actual values.
 update hr_performance_plan_items p set evidence_count=(select count(*) from hr_performance_checkin_items ci where ci.tenant_id=p_tenant and ci.review_id=p_review and ci.plan_item_id=p.id)
 where p.tenant_id=p_tenant and p.review_id=p_review;

 update hr_performance_plan_items set
  system_score=case
   when actual_value is null or target_value is null then null
   when direction='higher_better' and target_value<>0 then round(least(100,(actual_value/target_value)*100),2)
   when direction='lower_better' and actual_value=0 then 100
   when direction='lower_better' and actual_value<>0 then round(least(100,(target_value/actual_value)*100),2)
   when direction='pass_fail' then case when actual_value>=target_value then 100 else 0 end
   when direction='milestone' and target_value<>0 then round(least(100,(actual_value/target_value)*100),2)
   else null end,
  scoring_source='system',
  integrity_flag=case
   when actual_value is not null and evidence_count=0 then 'review'
   when supervisor_validation='disputed' then 'review'
   else 'normal' end
 where tenant_id=p_tenant and review_id=p_review;
 get diagnostics v_scored=row_count;

 select coalesce(sum(weight),0),
        case when coalesce(sum(weight) filter (where system_score is not null),0)=0 then null
             else round(sum(system_score*weight) filter (where system_score is not null)/sum(weight) filter (where system_score is not null),2) end
 into v_weight,v_progress from hr_performance_plan_items where tenant_id=p_tenant and review_id=p_review;

 return jsonb_build_object('items_scored',v_scored,'progress_percent',v_progress,'plan_weight',v_weight);
end $$;
grant execute on function unimis.hr_performance_refresh_intelligence(uuid,uuid) to authenticated;

create or replace function unimis.hr_performance_record_evidence_checkin(
 p_tenant uuid,p_review uuid,p_status text,p_actual_progress text,p_achievements text,p_blockers text,p_evidence text,p_support_required text,p_next_actions text,p_measures jsonb
) returns jsonb language plpgsql security definer set search_path=unimis as $$
declare v_checkin uuid; m jsonb; v_item uuid; v_actual numeric; v_progress numeric;
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 if not exists(select 1 from hr_performance_reviews where tenant_id=p_tenant and id=p_review and plan_status='activated' and finalization_status<>'finalized') then raise exception 'Review must be activated and not finalized'; end if;
 if p_status not in ('on_track','at_risk','off_track','exceeded') then raise exception 'Invalid check-in status'; end if;
 insert into hr_performance_checkins(tenant_id,review_id,checkin_date,progress_percent,status,actual_progress,achievements,blockers,evidence,support_required,next_actions)
 values(p_tenant,p_review,current_date,null,p_status,nullif(trim(p_actual_progress),''),nullif(trim(p_achievements),''),nullif(trim(p_blockers),''),nullif(trim(p_evidence),''),nullif(trim(p_support_required),''),nullif(trim(p_next_actions),'')) returning id into v_checkin;

 for m in select * from jsonb_array_elements(coalesce(p_measures,'[]'::jsonb)) loop
  v_item=nullif(m->>'item_id','')::uuid; v_actual=nullif(m->>'actual_value','')::numeric;
  if v_item is not null and v_actual is not null then
   if not exists(select 1 from hr_performance_plan_items where id=v_item and tenant_id=p_tenant and review_id=p_review) then raise exception 'Invalid performance measure in check-in'; end if;
   insert into hr_performance_checkin_items(tenant_id,checkin_id,review_id,plan_item_id,actual_value,evidence,evidence_source)
   values(p_tenant,v_checkin,p_review,v_item,v_actual,nullif(trim(m->>'evidence'),''),coalesce(nullif(m->>'evidence_source',''),'manager_observation'));
  end if;
 end loop;

 perform unimis.hr_performance_refresh_intelligence(p_tenant,p_review);
 select case when coalesce(sum(weight) filter (where system_score is not null),0)=0 then null else round(sum(system_score*weight) filter (where system_score is not null)/sum(weight) filter (where system_score is not null),2) end
 into v_progress from hr_performance_plan_items where tenant_id=p_tenant and review_id=p_review;
 update hr_performance_checkins set progress_percent=v_progress where id=v_checkin;
 return jsonb_build_object('checkin_id',v_checkin,'progress_percent',v_progress);
end $$;
grant execute on function unimis.hr_performance_record_evidence_checkin(uuid,uuid,text,text,text,text,text,text,text,jsonb) to authenticated;

-- Make 010k scoring use the same intelligence refresh so legacy Actual values and new evidence records behave consistently.
create or replace function unimis.hr_performance_system_score(p_tenant uuid,p_review uuid) returns jsonb
language plpgsql security definer set search_path=unimis as $$
begin return unimis.hr_performance_refresh_intelligence(p_tenant,p_review); end $$;
grant execute on function unimis.hr_performance_system_score(uuid,uuid) to authenticated;

-- Existing demo actuals pre-date evidence capture. Flag them for review rather than pretending they are evidence-backed.
update unimis.hr_performance_plan_items set integrity_flag='review'
where actual_value is not null and evidence_count=0;


-- SOURCE 202610241000_010m_hr_setup_policy_probation.sql
-- 010m HR setup, policy-gated career/compensation decisions, and probation lifecycle.

create table if not exists unimis.hr_policy_configs(
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references unimis.tenants(id) on delete cascade,
 policy_type text not null,
 config jsonb not null default '{}'::jsonb,
 updated_at timestamptz not null default now(),
 updated_by uuid default auth.uid(),
 unique(tenant_id,policy_type)
);
alter table unimis.hr_policy_configs enable row level security;
drop policy if exists tenant_member_all on unimis.hr_policy_configs;
create policy tenant_member_all on unimis.hr_policy_configs for all using(unimis.is_tenant_member(tenant_id)) with check(unimis.is_tenant_member(tenant_id));

create table if not exists unimis.hr_probation_records(
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references unimis.tenants(id) on delete cascade,
 employee_id uuid not null references unimis.hr_employees(id) on delete cascade,
 start_date date not null,
 expected_end_date date not null,
 actual_end_date date,
 status text not null default 'active' check(status in ('active','review_due','eligible_confirmation','extended','confirmed','management_review','closed')),
 extension_months integer not null default 0,
 review_id uuid references unimis.hr_performance_reviews(id) on delete set null,
 final_score numeric(6,2),
 policy_result jsonb not null default '{}'::jsonb,
 notes text,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(tenant_id,employee_id,start_date)
);
alter table unimis.hr_probation_records enable row level security;
drop policy if exists tenant_member_all on unimis.hr_probation_records;
create policy tenant_member_all on unimis.hr_probation_records for all using(unimis.is_tenant_member(tenant_id)) with check(unimis.is_tenant_member(tenant_id));
create index if not exists idx_hr_probation_status on unimis.hr_probation_records(tenant_id,status,expected_end_date);

alter table unimis.hr_performance_reviews
 add column if not exists performance_remark text,
 add column if not exists policy_eligibility jsonb not null default '{}'::jsonb;

-- Safe defaults: performance is rated independently; promotion/increment need policy eligibility.
do $$ declare t record; begin
 for t in select id from unimis.tenants loop
  insert into unimis.hr_policy_configs(tenant_id,policy_type,config) values
  (t.id,'career_compensation',jsonb_build_object(
    'promotion_enabled',true,'promotion_min_score',80,'promotion_min_service_months',36,'promotion_min_conduct',80,
    'promotion_require_no_open_pip',true,'promotion_require_no_queries',true,'promotion_require_training',true,'promotion_require_vacancy',false,
    'increment_enabled',true,'increment_min_score',70,'increment_min_service_months',12,'increment_require_confirmed',true,'increment_require_no_queries',true)),
  (t.id,'probation',jsonb_build_object(
    'enabled',true,'default_months',6,'mid_review_month',3,'max_extension_months',3,'min_score',70,'min_attendance',90,
    'conduct_required',true,'induction_required',true,'auto_create_plan',true)),
  (t.id,'performance_ratings',jsonb_build_object('exceptional_min',90,'very_good_min',80,'good_min',70,'fair_min',60))
  on conflict(tenant_id,policy_type) do nothing;
 end loop;
end $$;

-- New hires enter probation when the tenant policy enables it. This does not auto-confirm or auto-terminate anyone.
create or replace function unimis.hr_create_probation_for_new_employee() returns trigger
language plpgsql security definer set search_path=unimis as $$
declare cfg jsonb; months integer;
begin
 select config into cfg from hr_policy_configs where tenant_id=new.tenant_id and policy_type='probation';
 if coalesce((cfg->>'enabled')::boolean,false) then
  months:=coalesce((cfg->>'default_months')::integer,6);
  insert into hr_probation_records(tenant_id,employee_id,start_date,expected_end_date,status)
  values(new.tenant_id,new.id,coalesce(new.hire_date,current_date),coalesce(new.hire_date,current_date)+(months||' months')::interval,'active')
  on conflict do nothing;
 end if;
 return new;
end $$;
drop trigger if exists trg_hr_new_employee_probation on unimis.hr_employees;
create trigger trg_hr_new_employee_probation after insert on unimis.hr_employees for each row execute function unimis.hr_create_probation_for_new_employee();

-- Performance result and career/compensation eligibility are deliberately separate.
-- Manual policy gates (queries, mandatory training, vacancy) prevent automatic career action until verified.
create or replace function unimis.hr_performance_evaluate_decisions(p_tenant uuid,p_review uuid) returns jsonb
language plpgsql security definer set search_path=unimis as $$
declare rev record; emp record; cfg jsonb; open_pip integer:=0; service_months integer:=0; created integer:=0;
        remark text; promo_ok boolean:=false; incr_ok boolean:=false; promo_manual boolean:=false; incr_manual boolean:=false;
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 select * into rev from hr_performance_reviews where tenant_id=p_tenant and id=p_review;
 if rev.id is null then raise exception 'Review not found'; end if;
 if rev.finalization_status<>'finalized' or rev.final_score is null then raise exception 'Finalize the appraisal before evaluating policy eligibility'; end if;
 select * into emp from hr_employees where tenant_id=p_tenant and id=rev.employee_id;
 select config into cfg from hr_policy_configs where tenant_id=p_tenant and policy_type='career_compensation';
 cfg:=coalesce(cfg,'{}'::jsonb);
 service_months:=greatest(0,(extract(year from age(current_date,coalesce(emp.hire_date,current_date)))::int*12)+extract(month from age(current_date,coalesce(emp.hire_date,current_date)))::int);
 select count(*) into open_pip from hr_performance_improvement_plans where tenant_id=p_tenant and employee_id=rev.employee_id and status in ('open','on_track','extended');
 remark:=case when rev.final_score>=90 then 'Exceptional performance for the review period.' when rev.final_score>=80 then 'Very good performance for the review period.' when rev.final_score>=70 then 'Good and satisfactory performance for the review period.' when rev.final_score>=60 then 'Fair performance; improvement is required in identified areas.' else 'Performance is below the satisfactory level; structured improvement support is required.' end;

 promo_manual:=coalesce((cfg->>'promotion_require_no_queries')::boolean,false) or coalesce((cfg->>'promotion_require_training')::boolean,false) or coalesce((cfg->>'promotion_require_vacancy')::boolean,false);
 promo_ok:=coalesce((cfg->>'promotion_enabled')::boolean,false)
   and rev.final_score>=coalesce((cfg->>'promotion_min_score')::numeric,80)
   and service_months>=coalesce((cfg->>'promotion_min_service_months')::int,36)
   and coalesce(rev.professional_conduct_score,0)>=coalesce((cfg->>'promotion_min_conduct')::numeric,80)
   and (not coalesce((cfg->>'promotion_require_no_open_pip')::boolean,true) or open_pip=0);
 incr_manual:=coalesce((cfg->>'increment_require_no_queries')::boolean,false) or coalesce((cfg->>'increment_require_confirmed')::boolean,false);
 incr_ok:=coalesce((cfg->>'increment_enabled')::boolean,false)
   and rev.final_score>=coalesce((cfg->>'increment_min_score')::numeric,70)
   and service_months>=coalesce((cfg->>'increment_min_service_months')::int,12);

 update hr_performance_reviews set performance_remark=remark,policy_eligibility=jsonb_build_object(
   'performance_rating',coalesce(rev.final_rating,''),'performance_remark',remark,'service_months',service_months,
   'promotion',case when not promo_ok then 'not_eligible' when promo_manual then 'policy_review_required' else 'eligible' end,
   'promotion_manual_checks',jsonb_build_object('disciplinary_queries',coalesce((cfg->>'promotion_require_no_queries')::boolean,false),'mandatory_training',coalesce((cfg->>'promotion_require_training')::boolean,false),'vacancy',coalesce((cfg->>'promotion_require_vacancy')::boolean,false)),
   'salary_increment',case when not incr_ok then 'not_eligible' when incr_manual then 'policy_review_required' else 'eligible' end,
   'increment_manual_checks',jsonb_build_object('confirmed_appointment',coalesce((cfg->>'increment_require_confirmed')::boolean,false),'disciplinary_queries',coalesce((cfg->>'increment_require_no_queries')::boolean,false)))
 where tenant_id=p_tenant and id=p_review;

 -- Development interventions remain evidence/rule driven. Career rewards are created only when all configured gates are machine-clear.
 if rev.final_score<50 and not exists(select 1 from hr_performance_decisions where tenant_id=p_tenant and review_id=p_review and rule_code='POLICY-PIP' and status<>'cancelled') then
  insert into hr_performance_decisions(tenant_id,review_id,action_type,rationale,status,rule_code,system_generated) values(p_tenant,p_review,'pip','Final performance is below the satisfactory threshold.','recommended','POLICY-PIP',true); created:=created+1;
 elsif rev.final_score<70 and not exists(select 1 from hr_performance_decisions where tenant_id=p_tenant and review_id=p_review and rule_code='POLICY-TRAIN' and status<>'cancelled') then
  insert into hr_performance_decisions(tenant_id,review_id,action_type,rationale,status,rule_code,system_generated) values(p_tenant,p_review,'training','Performance indicates a development need; targeted training/support is recommended.','recommended','POLICY-TRAIN',true); created:=created+1;
 end if;
 if promo_ok and not promo_manual and not exists(select 1 from hr_performance_decisions where tenant_id=p_tenant and review_id=p_review and rule_code='POLICY-PROMOTION' and status<>'cancelled') then
  insert into hr_performance_decisions(tenant_id,review_id,action_type,rationale,status,rule_code,system_generated) values(p_tenant,p_review,'promotion','All configured promotion eligibility gates are satisfied; submit for authorized career approval.','recommended','POLICY-PROMOTION',true); created:=created+1;
 end if;
 if incr_ok and not incr_manual and not exists(select 1 from hr_performance_decisions where tenant_id=p_tenant and review_id=p_review and rule_code='POLICY-INCREMENT' and status<>'cancelled') then
  insert into hr_performance_decisions(tenant_id,review_id,action_type,rationale,status,rule_code,system_generated) values(p_tenant,p_review,'salary_increment','All configured increment eligibility gates are satisfied; submit through the salary-adjustment approval workflow.','recommended','POLICY-INCREMENT',true); created:=created+1;
 end if;
 return jsonb_build_object('recommendations_created',created,'final_score',rev.final_score,'remark',remark,'service_months',service_months,'promotion',case when not promo_ok then 'not_eligible' when promo_manual then 'policy_review_required' else 'eligible' end,'salary_increment',case when not incr_ok then 'not_eligible' when incr_manual then 'policy_review_required' else 'eligible' end);
end $$;
grant execute on function unimis.hr_performance_evaluate_decisions(uuid,uuid) to authenticated;


-- SOURCE 202610250010_010t_employee_reporting_structure.sql
-- 010t: employee reporting structure integration for PMS
create or replace function unimis.hr_update_employee_master(
 p_tenant uuid,p_employee uuid,p_first_name text,p_last_name text,p_email text,p_phone text,
 p_date_of_birth date,p_gender text,p_marital_status text,p_nationality text,p_national_id text,p_address text,
 p_branch uuid,p_department uuid,p_position uuid,p_supervisor uuid,p_employment_type text,p_work_schedule text,p_pay_basis text,
 p_basic_salary numeric,p_salary_effective date,p_ssnit_number text,p_tax_number text,
 p_bank_name text,p_bank_branch text,p_bank_account_name text,p_bank_account_number text,
 p_payment_method text,p_momo_network text,p_momo_number text
) returns jsonb language plpgsql security definer set search_path=unimis as $$
declare old_salary numeric(14,2); active_contract uuid; old_supervisor uuid; result jsonb;
begin
 if not is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 if not exists(select 1 from hr_employees where id=p_employee and tenant_id=p_tenant) then raise exception 'Employee not found'; end if;
 if p_supervisor=p_employee then raise exception 'An employee cannot be their own supervisor'; end if;
 if p_supervisor is not null and not exists(select 1 from hr_employees where id=p_supervisor and tenant_id=p_tenant and employment_status='active') then raise exception 'Supervisor must be an active employee in this organization'; end if;
 if p_pay_basis not in ('monthly','weekly','daily','hourly') then raise exception 'Invalid pay basis'; end if;
 select supervisor_id into old_supervisor from hr_employees where id=p_employee;
 select id,basic_salary into active_contract,old_salary from hr_employment_contracts where tenant_id=p_tenant and employee_id=p_employee and status='active' order by start_date desc limit 1;
 old_salary:=coalesce((select sh.new_salary from hr_salary_history sh where sh.employee_id=p_employee and sh.effective_from<=coalesce(p_salary_effective,current_date) order by sh.effective_from desc,sh.created_at desc limit 1),old_salary,0);
 update hr_employees set first_name=p_first_name,last_name=p_last_name,email=nullif(p_email,''),phone=nullif(p_phone,''),date_of_birth=p_date_of_birth,gender=nullif(p_gender,''),marital_status=nullif(p_marital_status,''),nationality=nullif(p_nationality,''),national_id=nullif(p_national_id,''),residential_address=nullif(p_address,''),branch_id=p_branch,department_id=p_department,position_id=p_position,supervisor_id=p_supervisor,employment_type=p_employment_type,work_schedule=p_work_schedule where id=p_employee and tenant_id=p_tenant;
 if active_contract is not null then update hr_employment_contracts set contract_type=p_employment_type,pay_basis=p_pay_basis,pay_frequency=p_pay_basis where id=active_contract; end if;
 update payroll_profiles set ssnit_number=nullif(p_ssnit_number,''),tax_number=nullif(p_tax_number,''),bank_name=nullif(p_bank_name,''),bank_branch=nullif(p_bank_branch,''),bank_account_name=nullif(p_bank_account_name,''),bank_account_number=nullif(p_bank_account_number,''),payment_method=coalesce(nullif(p_payment_method,''),'bank'),momo_network=nullif(p_momo_network,''),momo_number=nullif(p_momo_number,'') where employee_id=p_employee and tenant_id=p_tenant;
 if p_basic_salary is not null and p_basic_salary<>old_salary then
   insert into hr_salary_history(tenant_id,employee_id,old_salary,new_salary,change_type,reason,effective_from,approved_by,created_by) values(p_tenant,p_employee,old_salary,p_basic_salary,case when old_salary=0 then 'initial' else 'manual' end,'Employee Master compensation update',coalesce(p_salary_effective,current_date),auth.uid(),auth.uid());
   if active_contract is not null and coalesce(p_salary_effective,current_date)<=current_date then update hr_employment_contracts set basic_salary=p_basic_salary where id=active_contract; end if;
 end if;
 insert into hr_employment_events(tenant_id,employee_id,event_type,effective_date,title,details,created_by) values(p_tenant,p_employee,'profile_update',current_date,'Employee master updated',jsonb_build_object('branch_id',p_branch,'department_id',p_department,'position_id',p_position,'supervisor_id',p_supervisor,'previous_supervisor_id',old_supervisor,'pay_basis',p_pay_basis,'salary_effective',p_salary_effective),auth.uid());
 result:=jsonb_build_object('ok',true,'old_salary',old_salary,'new_salary',p_basic_salary,'supervisor_id',p_supervisor); return result;
end $$;
grant execute on function unimis.hr_update_employee_master(uuid,uuid,text,text,text,text,date,text,text,text,text,text,uuid,uuid,uuid,uuid,text,text,text,numeric,date,text,text,text,text,text,text,text,text,text) to authenticated;


-- SOURCE 202610250730_010n_configurable_hr_setup_governance.sql
-- 010n Configurable HR setup, dynamic performance pillars, editable job architecture, policy defaults and governance support.

-- Grades are institution-managed and may be retired without deleting history.
alter table unimis.hr_job_grades add column if not exists active boolean not null default true;

-- Performance pillars are configuration data, not hard-coded application constants.
create table if not exists unimis.hr_performance_pillars(
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references unimis.tenants(id) on delete cascade,
 code text not null,
 name text not null,
 description text,
 display_order integer not null default 10,
 active boolean not null default true,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(tenant_id,code)
);
alter table unimis.hr_performance_pillars enable row level security;
drop policy if exists tenant_member_all on unimis.hr_performance_pillars;
create policy tenant_member_all on unimis.hr_performance_pillars for all
 using(unimis.is_tenant_member(tenant_id)) with check(unimis.is_tenant_member(tenant_id));

-- Remove the original three-value pillar checks so tenants can add their own pillars.
alter table unimis.hr_performance_metric_library drop constraint if exists hr_performance_metric_library_pillar_check;
alter table unimis.hr_performance_plan_items drop constraint if exists hr_performance_plan_items_pillar_check;

-- Starter pillars remain defaults only.
insert into unimis.hr_performance_pillars(tenant_id,code,name,description,display_order)
select t.id,v.code,v.name,v.description,v.display_order
from unimis.tenants t
cross join (values
 ('target_output','Target & Output','Quantitative targets, deliverables and measurable output.',10),
 ('responsibility_quality','Responsibilities & Quality','Role responsibilities, quality, accuracy and SOP execution.',20),
 ('professional_conduct','Professional Conduct','Attendance, collaboration, ethics and professional behaviour.',30)
) as v(code,name,description,display_order)
on conflict(tenant_id,code) do nothing;

-- Complete policy views have editable defaults in System Setup.
insert into unimis.hr_policy_configs(tenant_id,policy_type,config)
select id,'performance_policy','{"frequency":"annual","checkins_required":true,"min_checkins":2,"evidence_required":true,"employee_response":true,"supervisor_validation":true,"second_level_approval":true,"weights_must_total_100":true}'::jsonb
from unimis.tenants
on conflict(tenant_id,policy_type) do nothing;

-- Helpful indexes for the new filtered setup/governance views.
create index if not exists idx_hr_performance_pillars_tenant_active on unimis.hr_performance_pillars(tenant_id,active,display_order);
create index if not exists idx_hr_metric_library_filters on unimis.hr_performance_metric_library(tenant_id,active,industry,pillar);
create index if not exists idx_hr_leave_types_tenant_active on unimis.hr_leave_types(tenant_id,active,name);
create index if not exists idx_audit_events_tenant_created on unimis.audit_events(tenant_id,created_at desc);


-- SOURCE 202610250900_010p_pms_e2e_test_seed.sql
-- 010p PMS E2E test seed/reset
-- Purpose: preserve existing staged PMS demo records while reserving EMP004 (Kojo Owusu)
-- as a clean employee for a true UI-driven end-to-end PMS test.
-- No appraisal is pre-created for EMP004: the tester must create it through the UI.
do $$
declare
  v_tenant uuid;
  v_employee uuid;
  v_cycle uuid;
  v_review uuid;
  n integer;
begin
  select e.tenant_id into v_tenant
  from unimis.hr_employees e
  where e.employee_no in ('EMP001','EMP002','EMP003','EMP004')
  group by e.tenant_id
  having count(distinct e.employee_no)=4
  order by e.tenant_id
  limit 1;
  if v_tenant is null then
    raise exception '010p: expected EMP001-EMP004 under one demo tenant. Run the earlier demo seed migrations first.';
  end if;

  select id into v_employee from unimis.hr_employees
  where tenant_id=v_tenant and employee_no='EMP004' limit 1;
  if v_employee is null then raise exception '010p: EMP004 not found'; end if;

  -- Ensure the controlled 2026 test cycle exists and remains open.
  select id into v_cycle from unimis.hr_performance_cycles
  where tenant_id=v_tenant and name='2026 Annual Performance Review'
  order by created_at desc limit 1;
  if v_cycle is null then
    insert into unimis.hr_performance_cycles(tenant_id,name,cycle_type,start_date,end_date,status)
    values(v_tenant,'2026 Annual Performance Review','annual','2026-01-01','2026-12-31','open')
    returning id into v_cycle;
  else
    update unimis.hr_performance_cycles
    set start_date='2026-01-01',end_date='2026-12-31',status='open'
    where id=v_cycle;
  end if;

  -- Guarantee the standard editable KPI library needed for the E2E test.
  insert into unimis.hr_performance_metric_library
    (tenant_id,code,name,pillar,industry,unit,direction,description,default_target,default_weight,active)
  values
    (v_tenant,'GEN-OUTPUT','Target / Output Achievement','target_output','general','percent','higher_better','Achievement against agreed quantitative targets, deliverables or milestones.',90,20,true),
    (v_tenant,'GEN-DEADLINE','Deadline Delivery','target_output','general','percent','higher_better','Delivery of agreed work within committed timelines.',90,20,true),
    (v_tenant,'GEN-QUALITY','Work Quality & Accuracy','responsibility_quality','general','percent','higher_better','Accuracy, completeness, rework and quality of assigned responsibilities.',90,15,true),
    (v_tenant,'GEN-SOP','Responsibility / SOP Execution','responsibility_quality','general','percent','higher_better','Execution of job-description duties, procedures and controls.',90,15,true),
    (v_tenant,'GEN-ATTEND','Attendance & Punctuality','professional_conduct','general','percent','higher_better','Attendance and punctuality considered with authorised context.',95,10,true),
    (v_tenant,'GEN-TEAM','Collaboration & Communication','professional_conduct','general','score','higher_better','Teamwork, communication and constructive workplace behaviour.',4,10,true),
    (v_tenant,'GEN-CONDUCT','Professional Conduct & Ethics','professional_conduct','general','score','higher_better','Integrity, professionalism and adherence to organisational values.',4,10,true)
  on conflict(tenant_id,code) do update set
    name=excluded.name,pillar=excluded.pillar,industry=excluded.industry,unit=excluded.unit,
    direction=excluded.direction,description=excluded.description,default_target=excluded.default_target,
    default_weight=excluded.default_weight,active=true;

  -- Clean only EMP004's appraisal in this cycle so the entire workflow is tested from the UI.
  select id into v_review from unimis.hr_performance_reviews
  where tenant_id=v_tenant and employee_id=v_employee and cycle_id=v_cycle limit 1;
  if v_review is not null then
    -- Unlock only this disposable E2E record before removing it.
    update unimis.hr_performance_reviews
    set finalization_status='not_started',finalized_at=null,finalized_by=null,
        final_score=null,final_rating=null,completed_at=null,status='draft',plan_status='planning'
    where id=v_review;
    delete from unimis.hr_performance_improvement_plans where tenant_id=v_tenant and review_id=v_review;
    delete from unimis.hr_performance_reviews where tenant_id=v_tenant and id=v_review;
  end if;

  select count(*) into n from unimis.hr_performance_metric_library
  where tenant_id=v_tenant and code in ('GEN-OUTPUT','GEN-DEADLINE','GEN-QUALITY','GEN-SOP','GEN-ATTEND','GEN-TEAM','GEN-CONDUCT') and active;
  if n<>7 then raise exception '010p verification failed: expected 7 active generic PMS measures, got %',n; end if;
  if exists(select 1 from unimis.hr_performance_reviews where tenant_id=v_tenant and employee_id=v_employee and cycle_id=v_cycle) then
    raise exception '010p verification failed: EMP004 must start without a review';
  end if;
  raise notice '010p ready: EMP004 Kojo Owusu is clean for UI-driven PMS E2E testing; 2026 cycle open; 7 standard KPIs active.';
end $$;


-- SOURCE 202610251000_010v_employee_photo_reporting_fix.sql
-- 010v: reliable employee photo linkage after Storage upload.
create or replace function unimis.hr_set_employee_photo_path(p_tenant uuid,p_employee uuid,p_photo_path text)
returns jsonb language plpgsql security definer set search_path=unimis as $$
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 if not unimis.has_tenant_role(p_tenant,array['owner','administrator','hr_manager','hr_officer']) then raise exception 'HR write access required'; end if;
 if p_photo_path is null or p_photo_path='' or split_part(p_photo_path,'/',1)<>p_tenant::text then raise exception 'Invalid employee photo path'; end if;
 update unimis.hr_employees set photo_path=p_photo_path where id=p_employee and tenant_id=p_tenant;
 if not found then raise exception 'Employee not found'; end if;
 insert into unimis.audit_events(tenant_id,actor_id,module,action,record_type,record_id,details)
 values(p_tenant,auth.uid(),'hr','employee.photo.updated','hr_employee',p_employee,jsonb_build_object('photo_path',p_photo_path));
 return jsonb_build_object('ok',true,'photo_path',p_photo_path);
end $$;
grant execute on function unimis.hr_set_employee_photo_path(uuid,uuid,text) to authenticated;


-- SOURCE 202610251030_010x_kpi_applicability_filtering.sql
-- 010x: KPI applicability and role-aware PMS recommendations
alter table unimis.hr_performance_metric_library
  add column if not exists scope_level text not null default 'organization',
  add column if not exists department_id uuid references unimis.departments(id) on delete set null,
  add column if not exists position_id uuid references unimis.hr_positions(id) on delete set null;

alter table unimis.hr_performance_metric_library drop constraint if exists hr_performance_metric_library_scope_level_check;
alter table unimis.hr_performance_metric_library add constraint hr_performance_metric_library_scope_level_check
  check (scope_level in ('organization','department','position'));

create index if not exists idx_hr_perf_metric_scope on unimis.hr_performance_metric_library(tenant_id,scope_level,department_id,position_id) where active=true;

-- Existing general KPIs remain organization-wide. Sector-specific metrics stay available as overrides
-- unless HR explicitly scopes them to a department/position.
update unimis.hr_performance_metric_library
set scope_level=coalesce(scope_level,'organization')
where scope_level is null;

-- Add realistic Operations Officer KPIs for tenants that have the seeded Operations Officer position.
do $$
declare t record; d uuid; p uuid;
begin
 for t in select id from unimis.tenants loop
   select hp.id,hp.department_id into p,d from unimis.hr_positions hp
   where hp.tenant_id=t.id and lower(hp.title)='operations officer' and hp.active=true limit 1;
   if p is not null then
     insert into unimis.hr_performance_metric_library
       (tenant_id,code,name,pillar,industry,unit,direction,description,default_target,default_weight,scope_level,department_id,position_id,active)
     values
       (t.id,'OPS-TASK','Task Completion Rate','target_output','general','percent','higher_better','Percentage of assigned operational tasks completed to the agreed standard within the appraisal period.',90,30,'position',d,p,true),
       (t.id,'OPS-DEADLINE','Operational Deadline Compliance','target_output','general','percent','higher_better','Percentage of assigned operational deliverables completed by the agreed deadline.',90,20,'position',d,p,true),
       (t.id,'OPS-QUALITY','Operational Work Quality & Accuracy','responsibility_quality','general','percent','higher_better','Accuracy and completeness of operational work, with avoidable rework kept within agreed tolerance.',95,25,'position',d,p,true),
       (t.id,'OPS-SOP','SOP & Process Compliance','responsibility_quality','general','percent','higher_better','Compliance with approved operating procedures, controls and required documentation.',95,15,'position',d,p,true),
       (t.id,'OPS-CONDUCT','Operational Collaboration & Conduct','professional_conduct','general','score','higher_better','Collaboration, communication, accountability and professional conduct in operational work.',4,10,'position',d,p,true)
     on conflict(tenant_id,code) do update set
       name=excluded.name,pillar=excluded.pillar,industry=excluded.industry,unit=excluded.unit,direction=excluded.direction,
       description=excluded.description,default_target=excluded.default_target,default_weight=excluded.default_weight,
       scope_level=excluded.scope_level,department_id=excluded.department_id,position_id=excluded.position_id,active=true;
   end if;
 end loop;
end $$;


-- SOURCE 202610251040_010y_organization_industry_context.sql
-- 010y: tenant organization/industry context for PMS recommendations and host-SaaS integration
create table if not exists unimis.hr_organization_profiles (
  tenant_id uuid primary key references unimis.tenants(id) on delete cascade,
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

alter table unimis.hr_organization_profiles enable row level security;

drop policy if exists hr_organization_profiles_select on unimis.hr_organization_profiles;
create policy hr_organization_profiles_select on unimis.hr_organization_profiles
for select using (unimis.is_tenant_member(tenant_id));

drop policy if exists hr_organization_profiles_write on unimis.hr_organization_profiles;
create policy hr_organization_profiles_write on unimis.hr_organization_profiles
for all using (unimis.is_tenant_member(tenant_id)) with check (unimis.is_tenant_member(tenant_id));

insert into unimis.hr_organization_profiles(tenant_id,industry,sector_detail,integration_source)
select id,'general',null,'standalone' from unimis.tenants
on conflict (tenant_id) do nothing;

create index if not exists idx_hr_org_profile_industry on unimis.hr_organization_profiles(industry);


-- SOURCE 202610251050_010z_system_generated_codes.sql
-- 010z: Central tenant-safe automatic code generation.
-- Existing codes are preserved. New blank/null codes are generated at INSERT time.

create table if not exists unimis.hr_code_counters(
  tenant_key uuid not null,
  entity_key text not null,
  last_value bigint not null default 0,
  updated_at timestamptz not null default now(),
  primary key(tenant_key,entity_key)
);

create or replace function unimis.hr_next_code(p_tenant uuid,p_entity text,p_prefix text,p_table regclass)
returns text language plpgsql security definer set search_path=unimis as $$
declare
  k uuid:=coalesce(p_tenant,'00000000-0000-0000-0000-000000000000'::uuid);
  n bigint;
  mx bigint:=0;
begin
  perform pg_advisory_xact_lock(hashtext(k::text||':'||p_entity));
  execute format('select coalesce(max((regexp_match(code, %L))[1]::bigint),0) from %s where coalesce(tenant_id,%L::uuid)=%L::uuid and code ~ %L',
    '^'||p_prefix||'-([0-9]+)$',p_table,'00000000-0000-0000-0000-000000000000',k::text,'^'||p_prefix||'-[0-9]+$') into mx;
  insert into unimis.hr_code_counters(tenant_key,entity_key,last_value)
  values(k,p_entity,mx)
  on conflict(tenant_key,entity_key) do update set last_value=greatest(unimis.hr_code_counters.last_value,excluded.last_value),updated_at=now();
  update unimis.hr_code_counters set last_value=last_value+1,updated_at=now()
   where tenant_key=k and entity_key=p_entity returning last_value into n;
  return p_prefix||'-'||lpad(n::text,4,'0');
end $$;

create or replace function unimis.hr_autocode_row()
returns trigger language plpgsql security definer set search_path=unimis as $$
begin
  if new.code is null or btrim(new.code)='' then
    new.code:=unimis.hr_next_code(new.tenant_id,TG_TABLE_NAME,TG_ARGV[0],TG_RELID);
  end if;
  return new;
end $$;

create or replace function unimis.hr_auto_employee_no()
returns trigger language plpgsql security definer set search_path=unimis as $$
begin
  if new.employee_no is null or btrim(new.employee_no)='' then
    new.employee_no:=unimis.hr_next_code(new.tenant_id,'hr_employees','EMP',TG_RELID);
  end if;
  return new;
end $$;

create or replace function unimis.hr_auto_tenant_code()
returns trigger language plpgsql security definer set search_path=unimis as $$
declare n bigint;
begin
  if new.code is null or btrim(new.code)='' then
    perform pg_advisory_xact_lock(hashtext('tenant:auto-code'));
    select coalesce(max((regexp_match(code,'^ORG-([0-9]+)$'))[1]::bigint),0) into n from unimis.tenants where code ~ '^ORG-[0-9]+$';
    new.code:='ORG-'||lpad((n+1)::text,4,'0');
  end if;
  return new;
end $$;

drop trigger if exists trg_auto_tenant_code on unimis.tenants;
create trigger trg_auto_tenant_code before insert on unimis.tenants for each row execute function unimis.hr_auto_tenant_code();

drop trigger if exists trg_auto_employee_no on unimis.hr_employees;
create trigger trg_auto_employee_no before insert on unimis.hr_employees for each row execute function unimis.hr_auto_employee_no();

do $$
declare r record;
begin
  for r in select * from (values
    ('branches','BR'),('departments','DEP'),('hr_job_grades','GRD'),('hr_positions','POS'),
    ('hr_work_schedules','SCH'),('hr_leave_types','LVE'),('hr_performance_pillars','PIL'),
    ('hr_performance_metric_library','KPI'),('hr_performance_decision_rules','PDR'),
    ('hr_attendance_sites','SITE'),('hr_training_programs','TRN'),
    ('payroll_pay_groups','PGR'),('payroll_components','PAY'),('payroll_earning_sources','PES'),
    ('payroll_deduction_definitions','PDD'),('payroll_adjustments','ADJ'),('payroll_relief_types','RLF')
  ) as x(tbl,prefix)
  loop
    if to_regclass('unimis.'||r.tbl) is not null then
      execute format('drop trigger if exists trg_auto_code on unimis.%I',r.tbl);
      execute format('create trigger trg_auto_code before insert on unimis.%I for each row execute function unimis.hr_autocode_row(%L)',r.tbl,r.prefix);
    end if;
  end loop;
end $$;

grant execute on function unimis.hr_next_code(uuid,text,text,regclass) to authenticated;

-- Keep manually meaningful external identifiers untouched: Ghana Card, TIN, SSNIT,
-- bank/MoMo numbers, certificate numbers and bank/payment references are not internal codes.


-- SOURCE 202610251100_011c_industry_sector_master.sql
-- 011c: Editable tenant industry/sector master for organization context and PMS KPI recommendations.
-- Standard sectors are seeded per tenant; administrators can add/edit/deactivate their own sectors.

create table if not exists unimis.hr_industries (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references unimis.tenants(id) on delete cascade,
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

alter table unimis.hr_industries enable row level security;
drop policy if exists hr_industries_select on unimis.hr_industries;
create policy hr_industries_select on unimis.hr_industries for select using (unimis.is_tenant_member(tenant_id));
drop policy if exists hr_industries_write on unimis.hr_industries;
create policy hr_industries_write on unimis.hr_industries for all using (unimis.is_tenant_member(tenant_id)) with check (unimis.is_tenant_member(tenant_id));

create or replace function unimis.hr_industry_prepare_row()
returns trigger language plpgsql security definer set search_path=unimis as $$
begin
  if new.code is null or btrim(new.code)='' then
    new.code:=unimis.hr_next_code(new.tenant_id,'hr_industries','IND',TG_RELID);
  end if;
  if new.industry_key is null or btrim(new.industry_key)='' then
    new.industry_key:='custom_'||replace(gen_random_uuid()::text,'-','');
  end if;
  new.name:=btrim(new.name);
  new.updated_at:=now();
  return new;
end $$;

drop trigger if exists trg_hr_industry_prepare on unimis.hr_industries;
create trigger trg_hr_industry_prepare before insert or update on unimis.hr_industries
for each row execute function unimis.hr_industry_prepare_row();

-- The old profile constraint prevented new sectors. The master now controls valid choices in the UI.
alter table unimis.hr_organization_profiles drop constraint if exists hr_organization_profiles_industry_check;

-- Normalize the one legacy label that was renamed in the expanded master.
update unimis.hr_organization_profiles set industry='financial_services',updated_at=now() where industry='banking';
update unimis.hr_performance_metric_library set industry='financial_services' where industry='banking';

insert into unimis.hr_industries(tenant_id,industry_key,name,description,system_default,display_order)
select t.id,v.industry_key,v.name,v.description,true,v.display_order
from unimis.tenants t
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

create index if not exists idx_hr_industries_tenant_active on unimis.hr_industries(tenant_id,active,display_order);


-- SOURCE 202610251110_011e_pms_measure_integrity.sql
-- 011e PMS measure integrity
-- A library KPI may appear only once in an employee review plan.
-- Custom/ad-hoc measures (metric_id is null) remain unrestricted.

-- Clean up any pre-existing accidental duplicate library KPIs before enforcing uniqueness.
-- Keep the earliest-created plan item and remove only later duplicates of the same metric
-- inside the same review.
with ranked as (
  select id,
         row_number() over (
           partition by review_id, metric_id
           order by created_at nulls last, id
         ) as rn
  from unimis.hr_performance_plan_items
  where metric_id is not null
)
delete from unimis.hr_performance_plan_items p
using ranked r
where p.id=r.id and r.rn>1;

create unique index if not exists hr_perf_plan_unique_library_metric
  on unimis.hr_performance_plan_items(review_id, metric_id)
  where metric_id is not null;


-- SOURCE 202610251120_011g_pms_100pct_weight_guard.sql
-- 011h correction of 011g: enforce performance plan total weight ceiling.
-- 011g failed before application, so this intentionally replaces the same migration version.
create or replace function unimis.hr_guard_performance_plan_weight() returns trigger
language plpgsql security definer set search_path=unimis as $$
declare
  v_total numeric;
begin
  if new.weight is null or new.weight <= 0 then
    raise exception 'Performance measure weight must be greater than 0%%.';
  end if;

  select coalesce(sum(weight),0)
    into v_total
  from unimis.hr_performance_plan_items
  where tenant_id = new.tenant_id
    and review_id = new.review_id
    and id is distinct from new.id;

  if v_total + new.weight > 100.0001 then
    raise exception 'Performance plan total weight cannot exceed 100%%. Current other measures total %, attempted measure %.', v_total, new.weight;
  end if;

  return new;
end
$$;

drop trigger if exists trg_hr_performance_plan_weight_ceiling on unimis.hr_performance_plan_items;
create trigger trg_hr_performance_plan_weight_ceiling
before insert or update of weight, review_id
on unimis.hr_performance_plan_items
for each row execute function unimis.hr_guard_performance_plan_weight();


-- SOURCE 202610251140_011i_checkin_periods_activation_guard.sql
-- 011i: dated performance check-ins, activated-plan gate, and activated baseline protection.
alter table unimis.hr_performance_checkins add column if not exists period_key text;
alter table unimis.hr_performance_checkins add column if not exists period_label text;
alter table unimis.hr_performance_checkins add column if not exists period_start date;
alter table unimis.hr_performance_checkins add column if not exists period_end date;
alter table unimis.hr_performance_checkins add column if not exists reviewer_employee_id uuid references unimis.hr_employees(id) on delete set null;

create or replace function unimis.hr_guard_performance_checkin_activation() returns trigger
language plpgsql security definer set search_path=unimis as $$
begin
 if not exists(select 1 from unimis.hr_performance_reviews r where r.id=new.review_id and r.tenant_id=new.tenant_id and r.plan_status='activated' and coalesce(r.finalization_status,'draft')<>'finalized') then
   raise exception 'Check-ins are allowed only for an activated, non-finalized performance plan.';
 end if;
 return new;
end $$;
drop trigger if exists trg_hr_guard_performance_checkin_activation on unimis.hr_performance_checkins;
create trigger trg_hr_guard_performance_checkin_activation before insert or update of review_id,tenant_id on unimis.hr_performance_checkins for each row execute function unimis.hr_guard_performance_checkin_activation();

create or replace function unimis.hr_guard_activated_plan_baseline() returns trigger
language plpgsql security definer set search_path=unimis as $$
declare ps text;
begin
 select plan_status into ps from unimis.hr_performance_reviews where id=coalesce(new.review_id,old.review_id) and tenant_id=coalesce(new.tenant_id,old.tenant_id);
 if ps='activated' then
   if tg_op='DELETE' then raise exception 'Activated performance plan measures cannot be removed. Use an authorized plan amendment.'; end if;
   if tg_op='INSERT' then raise exception 'Measures cannot be added to an activated performance plan. Use an authorized plan amendment.'; end if;
   if new.metric_id is distinct from old.metric_id or new.pillar is distinct from old.pillar or new.title is distinct from old.title or new.description is distinct from old.description or new.unit is distinct from old.unit or new.direction is distinct from old.direction or new.target_value is distinct from old.target_value or new.weight is distinct from old.weight or new.due_date is distinct from old.due_date then
     raise exception 'Activated plan baseline is locked. KPI, pillar, target, weight and due date require an authorized plan amendment.';
   end if;
 end if;
 return case when tg_op='DELETE' then old else new end;
end $$;
drop trigger if exists trg_hr_guard_activated_plan_baseline on unimis.hr_performance_plan_items;
create trigger trg_hr_guard_activated_plan_baseline before insert or update or delete on unimis.hr_performance_plan_items for each row execute function unimis.hr_guard_activated_plan_baseline();

create or replace function unimis.hr_performance_record_period_checkin(
 p_tenant uuid,p_review uuid,p_period_key text,p_period_label text,p_period_start date,p_period_end date,p_checkin_date date,
 p_status text,p_actual_progress text,p_achievements text,p_blockers text,p_evidence text,p_support_required text,p_next_actions text,p_measures jsonb
) returns jsonb language plpgsql security definer set search_path=unimis as $$
declare v_checkin uuid; m jsonb; v_item uuid; v_actual numeric; v_progress numeric; v_reviewer uuid;
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 select reviewer_employee_id into v_reviewer from hr_performance_reviews where tenant_id=p_tenant and id=p_review and plan_status='activated' and coalesce(finalization_status,'draft')<>'finalized';
 if not found then raise exception 'Review must be activated and not finalized'; end if;
 if coalesce(trim(p_period_key),'')='' then raise exception 'Check-in period is required'; end if;
 if p_period_start is not null and p_period_end is not null and p_period_end<p_period_start then raise exception 'Check-in period end date cannot be before its start date'; end if;
 if p_status not in ('on_track','at_risk','off_track','exceeded') then raise exception 'Invalid check-in status'; end if;
 insert into hr_performance_checkins(tenant_id,review_id,checkin_date,period_key,period_label,period_start,period_end,reviewer_employee_id,progress_percent,status,actual_progress,achievements,blockers,evidence,support_required,next_actions)
 values(p_tenant,p_review,coalesce(p_checkin_date,current_date),p_period_key,coalesce(nullif(trim(p_period_label),''),p_period_key),p_period_start,p_period_end,v_reviewer,null,p_status,nullif(trim(p_actual_progress),''),nullif(trim(p_achievements),''),nullif(trim(p_blockers),''),nullif(trim(p_evidence),''),nullif(trim(p_support_required),''),nullif(trim(p_next_actions),'')) returning id into v_checkin;
 for m in select * from jsonb_array_elements(coalesce(p_measures,'[]'::jsonb)) loop
  v_item=nullif(m->>'item_id','')::uuid; v_actual=nullif(m->>'actual_value','')::numeric;
  if v_item is not null and v_actual is not null then
   if not exists(select 1 from hr_performance_plan_items where id=v_item and tenant_id=p_tenant and review_id=p_review) then raise exception 'Invalid performance measure in check-in'; end if;
   insert into hr_performance_checkin_items(tenant_id,checkin_id,review_id,plan_item_id,actual_value,evidence,evidence_source)
   values(p_tenant,v_checkin,p_review,v_item,v_actual,nullif(trim(m->>'evidence'),''),coalesce(nullif(m->>'evidence_source',''),'manager_observation'));
  end if;
 end loop;
 perform unimis.hr_performance_refresh_intelligence(p_tenant,p_review);
 select case when coalesce(sum(weight) filter (where system_score is not null),0)=0 then null else round(sum(system_score*weight) filter (where system_score is not null)/sum(weight) filter (where system_score is not null),2) end
 into v_progress from hr_performance_plan_items where tenant_id=p_tenant and review_id=p_review;
 update hr_performance_checkins set progress_percent=v_progress where id=v_checkin;
 return jsonb_build_object('checkin_id',v_checkin,'progress_percent',v_progress,'period',p_period_label);
end $$;
grant execute on function unimis.hr_performance_record_period_checkin(uuid,uuid,text,text,date,date,date,text,text,text,text,text,text,text,jsonb) to authenticated;


-- SOURCE 202610251210_011j_pms_measurement_evidence_framework.sql
-- 011j: evidence-led PMS measurement framework.
alter table unimis.hr_performance_metric_library
 add column if not exists measurement_type text not null default 'numeric',
 add column if not exists data_source text not null default 'manager_verified',
 add column if not exists measurement_method text,
 add column if not exists evidence_required boolean not null default true,
 add column if not exists evidence_min_count integer not null default 1,
 add column if not exists rubric jsonb not null default '[]'::jsonb,
 add column if not exists checklist jsonb not null default '[]'::jsonb;

do $$ begin
 if not exists(select 1 from pg_constraint where conname='hr_perf_metric_measurement_type_check') then
  alter table unimis.hr_performance_metric_library add constraint hr_perf_metric_measurement_type_check check(measurement_type in ('system_calculated','formula','numeric','milestone','behavioral_rubric','compliance_checklist','development'));
 end if;
end $$;

create table if not exists unimis.hr_performance_evidence_attachments(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.tenants(id) on delete cascade,
 review_id uuid not null references unimis.hr_performance_reviews(id) on delete cascade,
 plan_item_id uuid references unimis.hr_performance_plan_items(id) on delete cascade,
 checkin_id uuid references unimis.hr_performance_checkins(id) on delete cascade,
 file_name text not null, storage_path text not null, mime_type text, file_size bigint,
 description text, verification_status text not null default 'pending' check(verification_status in ('pending','verified','rejected')),
 verified_by uuid, verified_at timestamptz, uploaded_by uuid default auth.uid(), created_at timestamptz not null default now()
);
alter table unimis.hr_performance_evidence_attachments enable row level security;
drop policy if exists tenant_member_all on unimis.hr_performance_evidence_attachments;
create policy tenant_member_all on unimis.hr_performance_evidence_attachments for all using(unimis.is_tenant_member(tenant_id)) with check(unimis.is_tenant_member(tenant_id));

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('performance-evidence','performance-evidence',false,10485760,array['image/jpeg','image/png','image/webp','application/pdf','text/plain','text/csv','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet','application/vnd.openxmlformats-officedocument.wordprocessingml.document'])
on conflict(id) do update set file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists performance_evidence_member_insert on storage.objects;
create policy performance_evidence_member_insert on storage.objects for insert to authenticated with check(bucket_id='performance-evidence' and unimis.is_tenant_member((storage.foldername(name))[1]::uuid));
drop policy if exists performance_evidence_member_select on storage.objects;
create policy performance_evidence_member_select on storage.objects for select to authenticated using(bucket_id='performance-evidence' and unimis.is_tenant_member((storage.foldername(name))[1]::uuid));
drop policy if exists performance_evidence_member_delete on storage.objects;
create policy performance_evidence_member_delete on storage.objects for delete to authenticated using(bucket_id='performance-evidence' and unimis.is_tenant_member((storage.foldername(name))[1]::uuid));

-- System attendance result: percentage of attendance records that are present/late/half-day/on approved leave.
create or replace function unimis.hr_performance_attendance_result(p_tenant uuid,p_employee uuid,p_start date,p_end date) returns numeric
language plpgsql security definer set search_path=unimis as $$
declare total_count integer; acceptable integer;
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 select count(*),count(*) filter(where status in ('present','late','half_day','on_leave','holiday','off_day')) into total_count,acceptable
 from unimis.hr_attendance_records where tenant_id=p_tenant and employee_id=p_employee and work_date between p_start and p_end;
 if total_count=0 then return null; end if;
 return round(acceptable::numeric*100/total_count,2);
end $$;
grant execute on function unimis.hr_performance_attendance_result(uuid,uuid,date,date) to authenticated;

-- Mark the standard attendance KPI as system-calculated where it exists.
update unimis.hr_performance_metric_library set measurement_type='system_calculated',data_source='attendance_module',measurement_method='Calculated from HRPayrollCore attendance records for the selected review period.',evidence_required=false,evidence_min_count=0
where lower(name) like '%attendance%punctuality%';
update unimis.hr_performance_metric_library set measurement_type='behavioral_rubric',data_source='manager_verified',unit='score',measurement_method='Select the behaviourally anchored statement best supported by documented observations/evidence.',rubric='[{"score":1,"label":"Unsatisfactory","anchor":"Serious or persistent breaches of expected professional or ethical standards."},{"score":2,"label":"Needs improvement","anchor":"Repeated concerns requiring management intervention or coaching."},{"score":3,"label":"Meets expectations","anchor":"Generally professional, ethical and compliant; minor issues are corrected promptly."},{"score":4,"label":"Exceeds expectations","anchor":"Consistently professional, ethical and dependable with little or no corrective intervention."},{"score":5,"label":"Exceptional","anchor":"Consistently models integrity and professional conduct and positively influences others."}]'::jsonb,evidence_required=true,evidence_min_count=1
where lower(name) like '%professional conduct%ethic%';


-- SOURCE 202610251230_011k_objective_measurement_templates.sql
-- 011k: objective measurement templates, frozen activated-plan definitions, and check-in input audit trail.
alter table unimis.hr_performance_metric_library
 add column if not exists formula_config jsonb not null default '{}'::jsonb;

alter table unimis.hr_performance_plan_items
 add column if not exists measurement_type_snapshot text,
 add column if not exists data_source_snapshot text,
 add column if not exists measurement_method_snapshot text,
 add column if not exists rubric_snapshot jsonb,
 add column if not exists checklist_snapshot jsonb,
 add column if not exists formula_config_snapshot jsonb,
 add column if not exists evidence_required_snapshot boolean,
 add column if not exists evidence_min_count_snapshot integer;

alter table unimis.hr_performance_checkin_items
 add column if not exists measurement_inputs jsonb not null default '{}'::jsonb,
 add column if not exists measurement_type text;

-- Starter objective definitions. Administrators remain free to edit these in KPI Library before future plans are activated.
update unimis.hr_performance_metric_library
set measurement_type='formula',data_source='operational_record',unit='percent',
 measurement_method='Accuracy % = acceptable/correct work items divided by total work items reviewed × 100. Use a QA, inspection, transaction or rework record as evidence.',
 formula_config='{"numerator_label":"Acceptable / correct work items","denominator_label":"Total work items reviewed"}'::jsonb,
 evidence_required=true,evidence_min_count=1
where lower(name) like '%operational work quality%accuracy%';

update unimis.hr_performance_metric_library
set measurement_type='behavioral_rubric',data_source='manager_verified',unit='score',
 measurement_method='Select the teamwork/collaboration behaviour best supported by documented observations and evidence.',
 rubric='[{"score":1,"label":"Unsatisfactory","anchor":"Frequently undermines teamwork, communication or accountability and requires repeated intervention."},{"score":2,"label":"Needs improvement","anchor":"Inconsistent collaboration or communication causes avoidable friction or follow-up."},{"score":3,"label":"Meets expectations","anchor":"Works cooperatively, communicates appropriately and accepts normal accountability."},{"score":4,"label":"Exceeds expectations","anchor":"Consistently collaborates well, communicates proactively and supports team delivery."},{"score":5,"label":"Exceptional","anchor":"Models outstanding collaboration, resolves issues constructively and materially improves team effectiveness."}]'::jsonb,
 evidence_required=true,evidence_min_count=1
where lower(name) like '%operational collaboration%conduct%';

update unimis.hr_performance_metric_library
set measurement_type='compliance_checklist',data_source='manager_verified',unit='percent',
 measurement_method='Assess applicable SOP/control requirements as Compliant, Partially compliant, Non-compliant or N/A. The system calculates the percentage from applicable items.',
 checklist='[{"label":"Follows documented SOP steps for assigned work"},{"label":"Completes required records/documentation"},{"label":"Observes approval and control requirements"},{"label":"Escalates exceptions or deviations appropriately"},{"label":"Closes corrective actions within agreed timelines"}]'::jsonb,
 evidence_required=true,evidence_min_count=1
where lower(name) like '%responsibility%sop%execution%';

update unimis.hr_performance_metric_library
set measurement_type='formula',data_source='operational_record',unit='percent',
 measurement_method='Achievement % = completed/achieved agreed outputs divided by total agreed outputs due for the review period × 100. The underlying deliverables must be evidenced.',
 formula_config='{"numerator_label":"Outputs / milestones achieved","denominator_label":"Outputs / milestones due"}'::jsonb,
 evidence_required=true,evidence_min_count=1
where lower(name) like '%target%output%achievement%';

-- Freeze measurement definitions into every currently activated plan after the corrected starter definitions above.
update unimis.hr_performance_plan_items pi set
 measurement_type_snapshot=m.measurement_type,
 data_source_snapshot=m.data_source,
 measurement_method_snapshot=m.measurement_method,
 rubric_snapshot=m.rubric,
 checklist_snapshot=m.checklist,
 formula_config_snapshot=m.formula_config,
 evidence_required_snapshot=m.evidence_required,
 evidence_min_count_snapshot=m.evidence_min_count
from unimis.hr_performance_metric_library m, unimis.hr_performance_reviews r
where pi.metric_id=m.id and pi.review_id=r.id and r.plan_status='activated';

create or replace function unimis.hr_snapshot_performance_measurements_on_activation() returns trigger
language plpgsql security definer set search_path=unimis as $$
begin
 if new.plan_status='activated' and coalesce(old.plan_status,'')<>'activated' then
  update unimis.hr_performance_plan_items pi set
   measurement_type_snapshot=m.measurement_type,
   data_source_snapshot=m.data_source,
   measurement_method_snapshot=m.measurement_method,
   rubric_snapshot=m.rubric,
   checklist_snapshot=m.checklist,
   formula_config_snapshot=m.formula_config,
   evidence_required_snapshot=m.evidence_required,
   evidence_min_count_snapshot=m.evidence_min_count
  from unimis.hr_performance_metric_library m
  where pi.review_id=new.id and pi.tenant_id=new.tenant_id and pi.metric_id=m.id;
 end if;
 return new;
end $$;
drop trigger if exists trg_hr_snapshot_performance_measurements_on_activation on unimis.hr_performance_reviews;
create trigger trg_hr_snapshot_performance_measurements_on_activation after update of plan_status on unimis.hr_performance_reviews for each row execute function unimis.hr_snapshot_performance_measurements_on_activation();

create or replace function unimis.hr_performance_record_period_checkin(
 p_tenant uuid,p_review uuid,p_period_key text,p_period_label text,p_period_start date,p_period_end date,p_checkin_date date,
 p_status text,p_actual_progress text,p_achievements text,p_blockers text,p_evidence text,p_support_required text,p_next_actions text,p_measures jsonb
) returns jsonb language plpgsql security definer set search_path=unimis as $$
declare v_checkin uuid; m jsonb; v_item uuid; v_actual numeric; v_progress numeric; v_reviewer uuid; v_type text;
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 select reviewer_employee_id into v_reviewer from hr_performance_reviews where tenant_id=p_tenant and id=p_review and plan_status='activated' and coalesce(finalization_status,'draft')<>'finalized';
 if not found then raise exception 'Review must be activated and not finalized'; end if;
 if coalesce(trim(p_period_key),'')='' then raise exception 'Check-in period is required'; end if;
 if p_period_start is not null and p_period_end is not null and p_period_end<p_period_start then raise exception 'Check-in period end date cannot be before its start date'; end if;
 if p_status not in ('on_track','at_risk','off_track','exceeded') then raise exception 'Invalid check-in status'; end if;
 insert into hr_performance_checkins(tenant_id,review_id,checkin_date,period_key,period_label,period_start,period_end,reviewer_employee_id,progress_percent,status,actual_progress,achievements,blockers,evidence,support_required,next_actions)
 values(p_tenant,p_review,coalesce(p_checkin_date,current_date),p_period_key,coalesce(nullif(trim(p_period_label),''),p_period_key),p_period_start,p_period_end,v_reviewer,null,p_status,nullif(trim(p_actual_progress),''),nullif(trim(p_achievements),''),nullif(trim(p_blockers),''),nullif(trim(p_evidence),''),nullif(trim(p_support_required),''),nullif(trim(p_next_actions),'')) returning id into v_checkin;
 for m in select * from jsonb_array_elements(coalesce(p_measures,'[]'::jsonb)) loop
  v_item=nullif(m->>'item_id','')::uuid; v_actual=nullif(m->>'actual_value','')::numeric;
  if v_item is not null and v_actual is not null then
   select coalesce(pi.measurement_type_snapshot,ml.measurement_type,'numeric') into v_type
   from hr_performance_plan_items pi left join hr_performance_metric_library ml on ml.id=pi.metric_id
   where pi.id=v_item and pi.tenant_id=p_tenant and pi.review_id=p_review;
   if not found then raise exception 'Invalid performance measure in check-in'; end if;
   insert into hr_performance_checkin_items(tenant_id,checkin_id,review_id,plan_item_id,actual_value,evidence,evidence_source,measurement_inputs,measurement_type)
   values(p_tenant,v_checkin,p_review,v_item,v_actual,nullif(trim(m->>'evidence'),''),coalesce(nullif(m->>'evidence_source',''),'manager_observation'),coalesce(m->'measurement_inputs','{}'::jsonb),v_type);
  end if;
 end loop;
 perform unimis.hr_performance_refresh_intelligence(p_tenant,p_review);
 select case when coalesce(sum(weight) filter (where system_score is not null),0)=0 then null else round(sum(system_score*weight) filter (where system_score is not null)/sum(weight) filter (where system_score is not null),2) end
 into v_progress from hr_performance_plan_items where tenant_id=p_tenant and review_id=p_review;
 update hr_performance_checkins set progress_percent=v_progress where id=v_checkin;
 return jsonb_build_object('checkin_id',v_checkin,'progress_percent',v_progress,'period',p_period_label);
end $$;
grant execute on function unimis.hr_performance_record_period_checkin(uuid,uuid,text,text,date,date,date,text,text,text,text,text,text,text,jsonb) to authenticated;


-- SOURCE 202610260800_011l_evidence_verification_gate.sql
-- 011l: evidence verification gate for objective/manual PMS results.
alter table unimis.hr_performance_checkin_items
 add column if not exists verification_status text not null default 'pending',
 add column if not exists verified_by uuid,
 add column if not exists verified_at timestamptz,
 add column if not exists verification_note text;

do $$ begin
 if not exists(select 1 from pg_constraint where conname='hr_perf_checkin_item_verification_status_check') then
  alter table unimis.hr_performance_checkin_items add constraint hr_perf_checkin_item_verification_status_check
   check(verification_status in ('pending','verified','rejected','system_verified','manager_attested'));
 end if;
end $$;

-- Existing historical entries predate this gate; preserve them as verified legacy evidence.
update unimis.hr_performance_checkin_items set verification_status='verified'
where verification_status='pending' and created_at < now() - interval '1 minute';

create or replace function unimis.hr_verify_performance_evidence_submission(p_tenant uuid,p_checkin_item uuid,p_status text,p_note text default null) returns jsonb
language plpgsql security definer set search_path=unimis as $$
declare v_review uuid; v_item uuid;
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 if p_status not in ('verified','rejected') then raise exception 'Verification status must be verified or rejected'; end if;
 if p_status='rejected' and coalesce(trim(p_note),'')='' then raise exception 'A rejection reason is required'; end if;
 update hr_performance_checkin_items set verification_status=p_status,verified_by=auth.uid(),verified_at=now(),verification_note=nullif(trim(p_note),'')
 where tenant_id=p_tenant and id=p_checkin_item and verification_status='pending'
 returning review_id,plan_item_id into v_review,v_item;
 if not found then raise exception 'Pending evidence submission was not found'; end if;
 update hr_performance_evidence_attachments set verification_status=p_status,verified_by=auth.uid(),verified_at=now()
 where tenant_id=p_tenant and review_id=v_review and plan_item_id=v_item and verification_status='pending';
 perform unimis.hr_performance_refresh_intelligence(p_tenant,v_review);
 return jsonb_build_object('status',p_status,'review_id',v_review,'plan_item_id',v_item);
end $$;
grant execute on function unimis.hr_verify_performance_evidence_submission(uuid,uuid,text,text) to authenticated;

create or replace function unimis.hr_performance_refresh_intelligence(p_tenant uuid,p_review uuid) returns jsonb
language plpgsql security definer set search_path=unimis as $$
declare v_progress numeric(6,2); v_weight numeric(8,2); v_scored integer;
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 if exists(select 1 from hr_performance_reviews where tenant_id=p_tenant and id=p_review and finalization_status='finalized') then raise exception 'Finalized appraisal is locked'; end if;

 -- Only verified/system-verified/manager-attested results may become the authoritative actual.
 with latest as (
  select distinct on (plan_item_id) plan_item_id,actual_value,evidence_source
  from hr_performance_checkin_items
  where tenant_id=p_tenant and review_id=p_review and verification_status in ('verified','system_verified','manager_attested')
  order by plan_item_id,created_at desc,id desc
 ), counts as (
  select plan_item_id,count(*)::int evidence_count from hr_performance_checkin_items
  where tenant_id=p_tenant and review_id=p_review and verification_status in ('verified','system_verified','manager_attested') group by plan_item_id
 )
 update hr_performance_plan_items p set
  actual_value=l.actual_value,
  latest_evidence_source=l.evidence_source,
  evidence_count=coalesce(c.evidence_count,0)
 from latest l left join counts c on c.plan_item_id=l.plan_item_id
 where p.tenant_id=p_tenant and p.review_id=p_review and p.id=l.plan_item_id;

 -- If an item has submissions but none accepted, do not let pending/rejected facts become a score.
 update hr_performance_plan_items p set actual_value=null,system_score=null,evidence_count=0
 where p.tenant_id=p_tenant and p.review_id=p_review
 and exists(select 1 from hr_performance_checkin_items ci where ci.tenant_id=p_tenant and ci.review_id=p_review and ci.plan_item_id=p.id)
 and not exists(select 1 from hr_performance_checkin_items ci where ci.tenant_id=p_tenant and ci.review_id=p_review and ci.plan_item_id=p.id and ci.verification_status in ('verified','system_verified','manager_attested'));

 update hr_performance_plan_items set
  system_score=case
   when actual_value is null or target_value is null then null
   when direction='higher_better' and target_value<>0 then round(least(100,(actual_value/target_value)*100),2)
   when direction='lower_better' and actual_value=0 then 100
   when direction='lower_better' and actual_value<>0 then round(least(100,(target_value/actual_value)*100),2)
   when direction='pass_fail' then case when actual_value>=target_value then 100 else 0 end
   when direction='milestone' and target_value<>0 then round(least(100,(actual_value/target_value)*100),2)
   else null end,
  scoring_source='system',
  integrity_flag=case when actual_value is not null and evidence_count=0 then 'review' when supervisor_validation='disputed' then 'review' else 'normal' end
 where tenant_id=p_tenant and review_id=p_review;
 get diagnostics v_scored=row_count;
 select coalesce(sum(weight),0),case when coalesce(sum(weight) filter(where system_score is not null),0)=0 then null else round(sum(system_score*weight) filter(where system_score is not null)/sum(weight) filter(where system_score is not null),2) end
 into v_weight,v_progress from hr_performance_plan_items where tenant_id=p_tenant and review_id=p_review;
 return jsonb_build_object('items_scored',v_scored,'progress_percent',v_progress,'plan_weight',v_weight);
end $$;
grant execute on function unimis.hr_performance_refresh_intelligence(uuid,uuid) to authenticated;

create or replace function unimis.hr_performance_record_period_checkin(
 p_tenant uuid,p_review uuid,p_period_key text,p_period_label text,p_period_start date,p_period_end date,p_checkin_date date,
 p_status text,p_actual_progress text,p_achievements text,p_blockers text,p_evidence text,p_support_required text,p_next_actions text,p_measures jsonb
) returns jsonb language plpgsql security definer set search_path=unimis as $$
declare v_checkin uuid; m jsonb; v_item uuid; v_actual numeric; v_progress numeric; v_reviewer uuid; v_type text; v_source text; v_verification text;
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 select reviewer_employee_id into v_reviewer from hr_performance_reviews where tenant_id=p_tenant and id=p_review and plan_status='activated' and coalesce(finalization_status,'draft')<>'finalized';
 if not found then raise exception 'Review must be activated and not finalized'; end if;
 if coalesce(trim(p_period_key),'')='' then raise exception 'Check-in period is required'; end if;
 if p_period_start is not null and p_period_end is not null and p_period_end<p_period_start then raise exception 'Check-in period end date cannot be before its start date'; end if;
 if p_status not in ('on_track','at_risk','off_track','exceeded') then raise exception 'Invalid check-in status'; end if;
 insert into hr_performance_checkins(tenant_id,review_id,checkin_date,period_key,period_label,period_start,period_end,reviewer_employee_id,progress_percent,status,actual_progress,achievements,blockers,evidence,support_required,next_actions)
 values(p_tenant,p_review,coalesce(p_checkin_date,current_date),p_period_key,coalesce(nullif(trim(p_period_label),''),p_period_key),p_period_start,p_period_end,v_reviewer,null,p_status,nullif(trim(p_actual_progress),''),nullif(trim(p_achievements),''),nullif(trim(p_blockers),''),nullif(trim(p_evidence),''),nullif(trim(p_support_required),''),nullif(trim(p_next_actions),'')) returning id into v_checkin;
 for m in select * from jsonb_array_elements(coalesce(p_measures,'[]'::jsonb)) loop
  v_item=nullif(m->>'item_id','')::uuid; v_actual=nullif(m->>'actual_value','')::numeric;
  if v_item is not null and v_actual is not null then
   select coalesce(pi.measurement_type_snapshot,ml.measurement_type,'numeric'),coalesce(pi.data_source_snapshot,ml.data_source,'manager_verified') into v_type,v_source
   from hr_performance_plan_items pi left join hr_performance_metric_library ml on ml.id=pi.metric_id
   where pi.id=v_item and pi.tenant_id=p_tenant and pi.review_id=p_review;
   if not found then raise exception 'Invalid performance measure in check-in'; end if;
   v_verification=case when v_type='system_calculated' then 'system_verified' when v_type='behavioral_rubric' then 'manager_attested' else 'pending' end;
   if v_verification='pending' and coalesce(trim(m->>'evidence'),'')='' and not exists(select 1 from hr_performance_evidence_attachments a where a.tenant_id=p_tenant and a.review_id=p_review and a.plan_item_id=v_item) then
    raise exception 'Objective/manual source figures require evidence before submission';
   end if;
   insert into hr_performance_checkin_items(tenant_id,checkin_id,review_id,plan_item_id,actual_value,evidence,evidence_source,measurement_inputs,measurement_type,verification_status)
   values(p_tenant,v_checkin,p_review,v_item,v_actual,nullif(trim(m->>'evidence'),''),coalesce(nullif(m->>'evidence_source',''),case when v_source='operational_record' then 'system_record' else 'manager_observation' end),coalesce(m->'measurement_inputs','{}'::jsonb),v_type,v_verification);
  end if;
 end loop;
 perform unimis.hr_performance_refresh_intelligence(p_tenant,p_review);
 select case when coalesce(sum(weight) filter(where system_score is not null),0)=0 then null else round(sum(system_score*weight) filter(where system_score is not null)/sum(weight) filter(where system_score is not null),2) end into v_progress from hr_performance_plan_items where tenant_id=p_tenant and review_id=p_review;
 update hr_performance_checkins set progress_percent=v_progress where id=v_checkin;
 return jsonb_build_object('checkin_id',v_checkin,'progress_percent',v_progress,'period',p_period_label,'verification_required',true);
end $$;
grant execute on function unimis.hr_performance_record_period_checkin(uuid,uuid,text,text,date,date,date,text,text,text,text,text,text,text,jsonb) to authenticated;


-- SOURCE 202610260830_011m_checkin_verified_progress.sql
-- 011m: preserve recorded check-in progress while separately tracking the
-- current verified weighted contribution for that exact check-in.
alter table unimis.hr_performance_checkins
 add column if not exists recorded_progress_percent numeric(6,2),
 add column if not exists current_verified_progress_percent numeric(6,2),
 add column if not exists verified_measure_count integer not null default 0,
 add column if not exists total_measure_count integer not null default 0,
 add column if not exists verification_progress_updated_at timestamptz;

create or replace function unimis.hr_refresh_checkin_verified_progress(p_tenant uuid,p_checkin uuid) returns jsonb
language plpgsql security definer set search_path=unimis as $$
declare v_review uuid; v_progress numeric(6,2); v_verified integer; v_total integer;
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 select review_id into v_review from hr_performance_checkins where tenant_id=p_tenant and id=p_checkin;
 if not found then raise exception 'Check-in not found'; end if;
 select count(*) into v_total from hr_performance_plan_items where tenant_id=p_tenant and review_id=v_review;
 with accepted as (
  select distinct on (ci.plan_item_id) ci.plan_item_id,ci.actual_value
  from hr_performance_checkin_items ci
  where ci.tenant_id=p_tenant and ci.checkin_id=p_checkin
    and ci.verification_status in ('verified','system_verified','manager_attested')
  order by ci.plan_item_id,ci.created_at desc,ci.id desc
 ), scored as (
  select p.id,p.weight,
   case
    when a.actual_value is null or p.target_value is null then null
    when p.direction='higher_better' and p.target_value<>0 then least(100,(a.actual_value/p.target_value)*100)
    when p.direction='lower_better' and a.actual_value=0 then 100
    when p.direction='lower_better' and a.actual_value<>0 then least(100,(p.target_value/a.actual_value)*100)
    when p.direction='pass_fail' then case when a.actual_value>=p.target_value then 100 else 0 end
    when p.direction='milestone' and p.target_value<>0 then least(100,(a.actual_value/p.target_value)*100)
    else null end as score
  from accepted a join hr_performance_plan_items p on p.id=a.plan_item_id
  where p.tenant_id=p_tenant and p.review_id=v_review
 )
 select count(*) filter(where score is not null)::int,
        round(coalesce(sum(score*weight/100.0) filter(where score is not null),0),2)
 into v_verified,v_progress from scored;
 update hr_performance_checkins set current_verified_progress_percent=v_progress,
  verified_measure_count=coalesce(v_verified,0),total_measure_count=v_total,
  verification_progress_updated_at=now()
 where tenant_id=p_tenant and id=p_checkin;
 return jsonb_build_object('checkin_id',p_checkin,'current_verified_progress_percent',v_progress,'verified_measure_count',coalesce(v_verified,0),'total_measure_count',v_total);
end $$;
grant execute on function unimis.hr_refresh_checkin_verified_progress(uuid,uuid) to authenticated;

-- Wrap verification so the affected historical check-in is refreshed after the
-- evidence gate changes status. Review-level intelligence remains unchanged.
create or replace function unimis.hr_verify_performance_evidence_submission(p_tenant uuid,p_checkin_item uuid,p_status text,p_note text default null) returns jsonb
language plpgsql security definer set search_path=unimis as $$
declare v_review uuid; v_item uuid; v_checkin uuid; v_progress jsonb;
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 if p_status not in ('verified','rejected') then raise exception 'Verification status must be verified or rejected'; end if;
 if p_status='rejected' and coalesce(trim(p_note),'')='' then raise exception 'A rejection reason is required'; end if;
 update hr_performance_checkin_items set verification_status=p_status,verified_by=auth.uid(),verified_at=now(),verification_note=nullif(trim(p_note),'')
 where tenant_id=p_tenant and id=p_checkin_item and verification_status='pending'
 returning review_id,plan_item_id,checkin_id into v_review,v_item,v_checkin;
 if not found then raise exception 'Pending evidence submission was not found'; end if;
 update hr_performance_evidence_attachments set verification_status=p_status,verified_by=auth.uid(),verified_at=now()
 where tenant_id=p_tenant and review_id=v_review and plan_item_id=v_item and verification_status='pending';
 perform unimis.hr_performance_refresh_intelligence(p_tenant,v_review);
 v_progress:=unimis.hr_refresh_checkin_verified_progress(p_tenant,v_checkin);
 return jsonb_build_object('status',p_status,'review_id',v_review,'plan_item_id',v_item,'checkin_id',v_checkin,'checkin_progress',v_progress);
end $$;
grant execute on function unimis.hr_verify_performance_evidence_submission(uuid,uuid,text,text) to authenticated;

-- Backfill existing check-ins without depending on session membership during migration.
with totals as (
 select tenant_id,review_id,count(*)::int total_count from unimis.hr_performance_plan_items group by tenant_id,review_id
), accepted as (
 select distinct on (ci.checkin_id,ci.plan_item_id) ci.tenant_id,ci.checkin_id,ci.review_id,ci.plan_item_id,ci.actual_value
 from unimis.hr_performance_checkin_items ci
 where ci.verification_status in ('verified','system_verified','manager_attested')
 order by ci.checkin_id,ci.plan_item_id,ci.created_at desc,ci.id desc
), scored as (
 select a.tenant_id,a.checkin_id,a.review_id,p.weight,
  case
   when a.actual_value is null or p.target_value is null then null
   when p.direction='higher_better' and p.target_value<>0 then least(100,(a.actual_value/p.target_value)*100)
   when p.direction='lower_better' and a.actual_value=0 then 100
   when p.direction='lower_better' and a.actual_value<>0 then least(100,(p.target_value/a.actual_value)*100)
   when p.direction='pass_fail' then case when a.actual_value>=p.target_value then 100 else 0 end
   when p.direction='milestone' and p.target_value<>0 then least(100,(a.actual_value/p.target_value)*100)
   else null end score
 from accepted a join unimis.hr_performance_plan_items p on p.id=a.plan_item_id and p.tenant_id=a.tenant_id
), agg as (
 select tenant_id,checkin_id,review_id,count(*) filter(where score is not null)::int verified_count,
  round(coalesce(sum(score*weight/100.0) filter(where score is not null),0),2) current_progress
 from scored group by tenant_id,checkin_id,review_id
)
update unimis.hr_performance_checkins c set
 current_verified_progress_percent=coalesce(a.current_progress,0),
 verified_measure_count=coalesce(a.verified_count,0),
 total_measure_count=coalesce(t.total_count,0),verification_progress_updated_at=now()
from totals t left join agg a on a.tenant_id=t.tenant_id and a.review_id=t.review_id and a.checkin_id is not null
where c.tenant_id=t.tenant_id and c.review_id=t.review_id and (a.checkin_id=c.id or a.checkin_id is null);

-- Preserve the old progress snapshot as "recorded" where one exists. New rows
-- will receive a snapshot in the application/database flow below.
update unimis.hr_performance_checkins
set recorded_progress_percent=progress_percent
where recorded_progress_percent is null and progress_percent is not null;


create or replace function unimis.hr_performance_record_period_checkin(
 p_tenant uuid,p_review uuid,p_period_key text,p_period_label text,p_period_start date,p_period_end date,p_checkin_date date,
 p_status text,p_actual_progress text,p_achievements text,p_blockers text,p_evidence text,p_support_required text,p_next_actions text,p_measures jsonb
) returns jsonb language plpgsql security definer set search_path=unimis as $$
declare v_checkin uuid; m jsonb; v_item uuid; v_actual numeric; v_progress numeric; v_reviewer uuid; v_type text; v_source text; v_verification text;
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 select reviewer_employee_id into v_reviewer from hr_performance_reviews where tenant_id=p_tenant and id=p_review and plan_status='activated' and coalesce(finalization_status,'draft')<>'finalized';
 if not found then raise exception 'Review must be activated and not finalized'; end if;
 if coalesce(trim(p_period_key),'')='' then raise exception 'Check-in period is required'; end if;
 if p_period_start is not null and p_period_end is not null and p_period_end<p_period_start then raise exception 'Check-in period end date cannot be before its start date'; end if;
 if p_status not in ('on_track','at_risk','off_track','exceeded') then raise exception 'Invalid check-in status'; end if;
 insert into hr_performance_checkins(tenant_id,review_id,checkin_date,period_key,period_label,period_start,period_end,reviewer_employee_id,progress_percent,status,actual_progress,achievements,blockers,evidence,support_required,next_actions)
 values(p_tenant,p_review,coalesce(p_checkin_date,current_date),p_period_key,coalesce(nullif(trim(p_period_label),''),p_period_key),p_period_start,p_period_end,v_reviewer,null,p_status,nullif(trim(p_actual_progress),''),nullif(trim(p_achievements),''),nullif(trim(p_blockers),''),nullif(trim(p_evidence),''),nullif(trim(p_support_required),''),nullif(trim(p_next_actions),'')) returning id into v_checkin;
 for m in select * from jsonb_array_elements(coalesce(p_measures,'[]'::jsonb)) loop
  v_item=nullif(m->>'item_id','')::uuid; v_actual=nullif(m->>'actual_value','')::numeric;
  if v_item is not null and v_actual is not null then
   select coalesce(pi.measurement_type_snapshot,ml.measurement_type,'numeric'),coalesce(pi.data_source_snapshot,ml.data_source,'manager_verified') into v_type,v_source
   from hr_performance_plan_items pi left join hr_performance_metric_library ml on ml.id=pi.metric_id
   where pi.id=v_item and pi.tenant_id=p_tenant and pi.review_id=p_review;
   if not found then raise exception 'Invalid performance measure in check-in'; end if;
   v_verification=case when v_type='system_calculated' then 'system_verified' when v_type='behavioral_rubric' then 'manager_attested' else 'pending' end;
   if v_verification='pending' and coalesce(trim(m->>'evidence'),'')='' and not exists(select 1 from hr_performance_evidence_attachments a where a.tenant_id=p_tenant and a.review_id=p_review and a.plan_item_id=v_item) then
    raise exception 'Objective/manual source figures require evidence before submission';
   end if;
   insert into hr_performance_checkin_items(tenant_id,checkin_id,review_id,plan_item_id,actual_value,evidence,evidence_source,measurement_inputs,measurement_type,verification_status)
   values(p_tenant,v_checkin,p_review,v_item,v_actual,nullif(trim(m->>'evidence'),''),coalesce(nullif(m->>'evidence_source',''),case when v_source='operational_record' then 'system_record' else 'manager_observation' end),coalesce(m->'measurement_inputs','{}'::jsonb),v_type,v_verification);
  end if;
 end loop;
 perform unimis.hr_performance_refresh_intelligence(p_tenant,p_review);
 select case when coalesce(sum(weight) filter(where system_score is not null),0)=0 then null else round(sum(system_score*weight) filter(where system_score is not null)/sum(weight) filter(where system_score is not null),2) end into v_progress from hr_performance_plan_items where tenant_id=p_tenant and review_id=p_review;
 perform unimis.hr_refresh_checkin_verified_progress(p_tenant,v_checkin);
 update hr_performance_checkins set progress_percent=current_verified_progress_percent, recorded_progress_percent=current_verified_progress_percent where id=v_checkin;
 select current_verified_progress_percent into v_progress from hr_performance_checkins where id=v_checkin;
 return jsonb_build_object('checkin_id',v_checkin,'progress_percent',v_progress,'period',p_period_label,'verification_required',true);
end $$;
grant execute on function unimis.hr_performance_record_period_checkin(uuid,uuid,text,text,date,date,date,text,text,text,text,text,text,text,jsonb) to authenticated;


-- SOURCE 202610260845_011n_checkin_evidence_linkage_repair.sql
-- 011n: repair legacy check-in/evidence linkage and refresh historical verification progress.
-- Future submissions already carry checkin_id; this repair is deliberately conservative:
-- legacy/mismatched rows are reassigned only when the review has exactly one check-in.

with single_checkin_reviews as (
  select tenant_id, review_id, min(id::text)::uuid as checkin_id
  from unimis.hr_performance_checkins
  group by tenant_id, review_id
  having count(*) = 1
)
update unimis.hr_performance_checkin_items ci
set checkin_id = s.checkin_id
from single_checkin_reviews s
where ci.tenant_id = s.tenant_id
  and ci.review_id = s.review_id
  and ci.checkin_id is distinct from s.checkin_id;

-- Recalculate every historical check-in strictly from submissions linked to that check-in.
with totals as (
  select tenant_id, review_id, count(*)::int as total_count
  from unimis.hr_performance_plan_items
  group by tenant_id, review_id
), accepted as (
  select distinct on (ci.tenant_id, ci.checkin_id, ci.plan_item_id)
         ci.tenant_id, ci.checkin_id, ci.review_id, ci.plan_item_id, ci.actual_value
  from unimis.hr_performance_checkin_items ci
  where ci.checkin_id is not null
    and ci.verification_status in ('verified','system_verified','manager_attested')
  order by ci.tenant_id, ci.checkin_id, ci.plan_item_id, ci.created_at desc, ci.id desc
), scored as (
  select a.tenant_id, a.checkin_id, a.review_id, p.weight,
         case
           when a.actual_value is null or p.target_value is null then null
           when p.direction='higher_better' and p.target_value<>0 then least(100,(a.actual_value/p.target_value)*100)
           when p.direction='lower_better' and a.actual_value=0 then 100
           when p.direction='lower_better' and a.actual_value<>0 then least(100,(p.target_value/a.actual_value)*100)
           when p.direction='pass_fail' then case when a.actual_value>=p.target_value then 100 else 0 end
           when p.direction='milestone' and p.target_value<>0 then least(100,(a.actual_value/p.target_value)*100)
           else null
         end as score
  from accepted a
  join unimis.hr_performance_plan_items p
    on p.tenant_id=a.tenant_id and p.review_id=a.review_id and p.id=a.plan_item_id
), agg as (
  select tenant_id, checkin_id, review_id,
         count(*) filter (where score is not null)::int as verified_count,
         round(coalesce(sum(score*weight/100.0) filter (where score is not null),0),2) as current_progress
  from scored
  group by tenant_id, checkin_id, review_id
)
update unimis.hr_performance_checkins c
set current_verified_progress_percent = coalesce(a.current_progress,0),
    verified_measure_count = coalesce(a.verified_count,0),
    total_measure_count = coalesce(t.total_count,0),
    verification_progress_updated_at = now()
from totals t
left join agg a
  on a.tenant_id=t.tenant_id and a.review_id=t.review_id
where c.tenant_id=t.tenant_id
  and c.review_id=t.review_id
  and (a.checkin_id=c.id or not exists (
        select 1 from agg ax
        where ax.tenant_id=c.tenant_id and ax.review_id=c.review_id and ax.checkin_id=c.id
      ));

-- Keep the runtime refresh function exact-check-in scoped.
create or replace function unimis.hr_refresh_checkin_verified_progress(p_tenant uuid,p_checkin uuid) returns jsonb
language plpgsql security definer set search_path=unimis as $$
declare v_review uuid; v_progress numeric(6,2); v_verified integer; v_total integer;
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 select review_id into v_review from hr_performance_checkins where tenant_id=p_tenant and id=p_checkin;
 if not found then raise exception 'Check-in not found'; end if;
 select count(*) into v_total from hr_performance_plan_items where tenant_id=p_tenant and review_id=v_review;
 with accepted as (
  select distinct on (ci.plan_item_id) ci.plan_item_id,ci.actual_value
  from hr_performance_checkin_items ci
  where ci.tenant_id=p_tenant and ci.review_id=v_review and ci.checkin_id=p_checkin
    and ci.verification_status in ('verified','system_verified','manager_attested')
  order by ci.plan_item_id,ci.created_at desc,ci.id desc
 ), scored as (
  select p.id,p.weight,
   case
    when a.actual_value is null or p.target_value is null then null
    when p.direction='higher_better' and p.target_value<>0 then least(100,(a.actual_value/p.target_value)*100)
    when p.direction='lower_better' and a.actual_value=0 then 100
    when p.direction='lower_better' and a.actual_value<>0 then least(100,(p.target_value/a.actual_value)*100)
    when p.direction='pass_fail' then case when a.actual_value>=p.target_value then 100 else 0 end
    when p.direction='milestone' and p.target_value<>0 then least(100,(a.actual_value/p.target_value)*100)
    else null end as score
  from accepted a join hr_performance_plan_items p on p.id=a.plan_item_id
  where p.tenant_id=p_tenant and p.review_id=v_review
 )
 select count(*) filter(where score is not null)::int,
        round(coalesce(sum(score*weight/100.0) filter(where score is not null),0),2)
 into v_verified,v_progress from scored;
 update hr_performance_checkins set current_verified_progress_percent=v_progress,
  verified_measure_count=coalesce(v_verified,0),total_measure_count=v_total,
  verification_progress_updated_at=now()
 where tenant_id=p_tenant and id=p_checkin;
 return jsonb_build_object('checkin_id',p_checkin,'current_verified_progress_percent',v_progress,'verified_measure_count',coalesce(v_verified,0),'total_measure_count',v_total);
end $$;
grant execute on function unimis.hr_refresh_checkin_verified_progress(uuid,uuid) to authenticated;


-- SOURCE 202610260900_011o_checkin_verified_progress_exact_refresh.sql
﻿-- 011o: exact check-in verification refresh with safe single-check-in fallback.
-- Repairs the current legacy test without allowing evidence to leak between periods.

create or replace function unimis.hr_refresh_checkin_verified_progress(p_tenant uuid,p_checkin uuid) returns jsonb
language plpgsql security definer set search_path=unimis as $$
declare v_review uuid; v_progress numeric(6,2); v_verified integer; v_total integer; v_checkin_count integer;
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 select review_id into v_review from hr_performance_checkins where tenant_id=p_tenant and id=p_checkin;
 if not found then raise exception 'Check-in not found'; end if;
 select count(*) into v_total from hr_performance_plan_items where tenant_id=p_tenant and review_id=v_review;
 select count(*) into v_checkin_count from hr_performance_checkins where tenant_id=p_tenant and review_id=v_review;
 with accepted as (
  select distinct on (ci.plan_item_id) ci.plan_item_id,ci.actual_value
  from hr_performance_checkin_items ci
  where ci.tenant_id=p_tenant and ci.review_id=v_review
    and (ci.checkin_id=p_checkin or (v_checkin_count=1 and (ci.checkin_id is null or ci.checkin_id<>p_checkin)))
    and ci.verification_status in ('verified','system_verified','manager_attested')
  order by ci.plan_item_id,ci.created_at desc,ci.id desc
 ), scored as (
  select p.id,p.weight,
   case
    when a.actual_value is null or p.target_value is null then null
    when p.direction='higher_better' and p.target_value<>0 then least(100,(a.actual_value/p.target_value)*100)
    when p.direction='lower_better' and a.actual_value=0 then 100
    when p.direction='lower_better' and a.actual_value<>0 then least(100,(p.target_value/a.actual_value)*100)
    when p.direction='pass_fail' then case when a.actual_value>=p.target_value then 100 else 0 end
    when p.direction='milestone' and p.target_value<>0 then least(100,(a.actual_value/p.target_value)*100)
    else null end as score
  from accepted a join hr_performance_plan_items p on p.id=a.plan_item_id
  where p.tenant_id=p_tenant and p.review_id=v_review
 )
 select count(*) filter(where score is not null)::int,
        round(coalesce(sum(score*weight/100.0) filter(where score is not null),0),2)
 into v_verified,v_progress from scored;
 update hr_performance_checkins set current_verified_progress_percent=v_progress,
  verified_measure_count=coalesce(v_verified,0),total_measure_count=v_total,
  verification_progress_updated_at=now()
 where tenant_id=p_tenant and id=p_checkin;
 -- Permanently repair orphan/mismatched legacy submissions only when this review has one check-in.
 if v_checkin_count=1 then
  update hr_performance_checkin_items set checkin_id=p_checkin
  where tenant_id=p_tenant and review_id=v_review and checkin_id is distinct from p_checkin;
 end if;
 return jsonb_build_object('checkin_id',p_checkin,'current_verified_progress_percent',v_progress,'verified_measure_count',coalesce(v_verified,0),'total_measure_count',v_total);
end $$;
grant execute on function unimis.hr_refresh_checkin_verified_progress(uuid,uuid) to authenticated;

create or replace function unimis.hr_verify_performance_evidence_submission(p_tenant uuid,p_checkin_item uuid,p_status text,p_note text default null) returns jsonb
language plpgsql security definer set search_path=unimis as $$
declare v_review uuid; v_item uuid; v_checkin uuid; v_count integer;
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 if p_status not in ('verified','rejected') then raise exception 'Verification status must be verified or rejected'; end if;
 if p_status='rejected' and coalesce(trim(p_note),'')='' then raise exception 'A rejection reason is required'; end if;
 update hr_performance_checkin_items set verification_status=p_status,verified_by=auth.uid(),verified_at=now(),verification_note=nullif(trim(p_note),'')
 where tenant_id=p_tenant and id=p_checkin_item and verification_status='pending'
 returning review_id,plan_item_id,checkin_id into v_review,v_item,v_checkin;
 if not found then raise exception 'Pending evidence submission was not found'; end if;
 update hr_performance_evidence_attachments set verification_status=p_status,verified_by=auth.uid(),verified_at=now()
 where tenant_id=p_tenant and review_id=v_review and plan_item_id=v_item and verification_status='pending';
 perform unimis.hr_performance_refresh_intelligence(p_tenant,v_review);
 if v_checkin is null then
  select count(*), min(id::text)::uuid into v_count,v_checkin from hr_performance_checkins where tenant_id=p_tenant and review_id=v_review;
  if v_count<>1 then v_checkin=null; end if;
 end if;
 if v_checkin is not null then perform unimis.hr_refresh_checkin_verified_progress(p_tenant,v_checkin); end if;
 return jsonb_build_object('status',p_status,'review_id',v_review,'plan_item_id',v_item,'checkin_id',v_checkin);
end $$;
grant execute on function unimis.hr_verify_performance_evidence_submission(uuid,uuid,text,text) to authenticated;



-- SOURCE 202610260915_011p_checkin_workspace_integrity.sql
-- 011p: prevent accidental duplicate scheduled-period check-ins and suppress legacy duplicate pending evidence.

create or replace function unimis.hr_guard_duplicate_performance_checkin_period() returns trigger
language plpgsql security definer set search_path=unimis as $$
begin
  if coalesce(new.period_key,'') <> '' and upper(new.period_key) <> 'ADHOC' and exists (
    select 1 from unimis.hr_performance_checkins c
    where c.tenant_id=new.tenant_id and c.review_id=new.review_id
      and c.period_key=new.period_key and c.id<>new.id
  ) then
    raise exception 'A check-in has already been recorded for this employee and review period. Open Check-in History instead of submitting the same period again.';
  end if;
  return new;
end $$;

drop trigger if exists trg_hr_guard_duplicate_performance_checkin_period on unimis.hr_performance_checkins;
create trigger trg_hr_guard_duplicate_performance_checkin_period
before insert or update of tenant_id,review_id,period_key on unimis.hr_performance_checkins
for each row execute function unimis.hr_guard_duplicate_performance_checkin_period();

-- Preserve audit rows but close exact pending duplicates where an identical result/reference is already verified.
update unimis.hr_performance_checkin_items p
set verification_status='rejected',
    verified_at=coalesce(p.verified_at,now()),
    verification_note=coalesce(p.verification_note,'Duplicate submission suppressed: an identical result and evidence reference is already verified.')
where p.verification_status='pending'
  and exists (
    select 1 from unimis.hr_performance_checkin_items v
    where v.tenant_id=p.tenant_id
      and v.review_id=p.review_id
      and v.plan_item_id=p.plan_item_id
      and v.id<>p.id
      and v.actual_value is not distinct from p.actual_value
      and coalesce(v.evidence,'')=coalesce(p.evidence,'')
      and v.verification_status in ('verified','system_verified','manager_attested')
  );


-- SOURCE 202610260930_011q_checkin_history_integrity.sql
-- 011q: consolidate accidental duplicate scheduled check-ins and enforce period integrity.
-- Canonical row preference: linked evidence first, then verified progress, then earliest creation.
-- Evidence is re-linked before duplicate check-in rows are removed, preserving the audit trail.

do $$
declare r record;
begin
  for r in
    with linked as (
      select c.id,c.tenant_id,c.review_id,c.period_key,c.created_at,
             c.current_verified_progress_percent,
             (select count(*) from unimis.hr_performance_checkin_items i where i.checkin_id=c.id) +
             (select count(*) from unimis.hr_performance_evidence_attachments a where a.checkin_id=c.id) as link_count
      from unimis.hr_performance_checkins c
      where coalesce(c.period_key,'')<>'' and upper(c.period_key)<>'ADHOC'
    ), ranked as (
      select l.*,
             first_value(id) over (
               partition by tenant_id,review_id,period_key
               order by link_count desc,current_verified_progress_percent desc nulls last,created_at asc,id
             ) as keep_id,
             row_number() over (
               partition by tenant_id,review_id,period_key
               order by link_count desc,current_verified_progress_percent desc nulls last,created_at asc,id
             ) as rn
      from linked l
    )
    select id as duplicate_id,keep_id
    from ranked where rn>1
  loop
    update unimis.hr_performance_checkin_items
       set checkin_id=r.keep_id
     where checkin_id=r.duplicate_id;

    update unimis.hr_performance_evidence_attachments
       set checkin_id=r.keep_id
     where checkin_id=r.duplicate_id;

    delete from unimis.hr_performance_checkins
     where id=r.duplicate_id;
  end loop;
end $$;

-- Database-level guarantee in addition to the friendly trigger message.
create unique index if not exists uq_hr_performance_checkins_scheduled_period
on unimis.hr_performance_checkins(tenant_id,review_id,period_key)
where coalesce(period_key,'')<>'' and upper(period_key)<>'ADHOC';


-- SOURCE 202610260940_011u_attendance_administration_historical_import.sql
-- 011u Attendance Administration & Historical Import
create table if not exists unimis.hr_attendance_change_audit(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.tenants(id) on delete cascade,
 attendance_id uuid references unimis.hr_attendance_records(id) on delete set null, employee_id uuid not null references unimis.hr_employees(id) on delete cascade,
 work_date date not null, action text not null check(action in ('create','correct','import_create','import_correct')),
 reason text not null, old_record jsonb, new_record jsonb, changed_by uuid default auth.uid(), changed_at timestamptz not null default now()
);
alter table unimis.hr_attendance_change_audit enable row level security;
drop policy if exists attendance_change_audit_member_select on unimis.hr_attendance_change_audit;
create policy attendance_change_audit_member_select on unimis.hr_attendance_change_audit for select to authenticated using(unimis.is_tenant_member(tenant_id));
create index if not exists idx_attendance_change_audit_tenant_date on unimis.hr_attendance_change_audit(tenant_id,work_date desc);

create or replace function unimis.hr_admin_upsert_attendance(p_tenant uuid,p_employee uuid,p_work_date date,p_check_in timestamptz,p_check_out timestamptz,p_status text,p_site uuid,p_reason text,p_capture_method text default 'manual') returns jsonb
language plpgsql security definer set search_path=unimis as $$
declare oldr unimis.hr_attendance_records%rowtype; newr unimis.hr_attendance_records%rowtype; act text;
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 if coalesce(trim(p_reason),'')='' then raise exception 'Reason is required for manual attendance entry or correction'; end if;
 if p_capture_method not in ('manual','import') then raise exception 'Invalid administrative attendance source'; end if;
 if p_status not in ('present','absent','late','half_day','on_leave','holiday','off_day') then raise exception 'Invalid attendance status'; end if;
 if not exists(select 1 from unimis.hr_employees where tenant_id=p_tenant and id=p_employee) then raise exception 'Employee not found'; end if;
 select * into oldr from unimis.hr_attendance_records where tenant_id=p_tenant and employee_id=p_employee and work_date=p_work_date for update;
 if oldr.id is null then
  insert into unimis.hr_attendance_records(tenant_id,employee_id,work_date,check_in,check_out,status,capture_method,attendance_site_id,notes,correction_reason,approval_status,approved_by,approved_at)
  values(p_tenant,p_employee,p_work_date,p_check_in,p_check_out,p_status,p_capture_method,p_site,p_reason,p_reason,'approved',auth.uid(),now()) returning * into newr;
  act=case when p_capture_method='import' then 'import_create' else 'create' end;
 else
  update unimis.hr_attendance_records set check_in=p_check_in,check_out=p_check_out,status=p_status,capture_method=p_capture_method,attendance_site_id=p_site,notes=p_reason,correction_reason=p_reason,approval_status='approved',approved_by=auth.uid(),approved_at=now()
  where id=oldr.id returning * into newr;
  act=case when p_capture_method='import' then 'import_correct' else 'correct' end;
 end if;
 insert into unimis.hr_attendance_change_audit(tenant_id,attendance_id,employee_id,work_date,action,reason,old_record,new_record)
 values(p_tenant,newr.id,p_employee,p_work_date,act,p_reason,case when oldr.id is null then null else to_jsonb(oldr) end,to_jsonb(newr));
 return jsonb_build_object('ok',true,'attendance_id',newr.id,'action',act);
end $$;
grant execute on function unimis.hr_admin_upsert_attendance(uuid,uuid,date,timestamptz,timestamptz,text,uuid,text,text) to authenticated;


-- SOURCE 202610260945_011r_continue_existing_checkin.sql
-- 011r: continue an existing scheduled check-in instead of trying to create a duplicate period.
-- One scheduled check-in is the parent record; KPI results/evidence are added or updated beneath it.
-- Already verified/system-verified facts are preserved. ADHOC check-ins remain repeatable.

create or replace function unimis.hr_performance_record_period_checkin(
 p_tenant uuid,p_review uuid,p_period_key text,p_period_label text,p_period_start date,p_period_end date,p_checkin_date date,
 p_status text,p_actual_progress text,p_achievements text,p_blockers text,p_evidence text,p_support_required text,p_next_actions text,p_measures jsonb
) returns jsonb language plpgsql security definer set search_path=unimis as $$
declare v_checkin uuid; v_existing_item uuid; v_existing_verification text; m jsonb; v_item uuid; v_actual numeric; v_progress numeric; v_reviewer uuid; v_type text; v_source text; v_verification text; v_reused boolean:=false;
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 select reviewer_employee_id into v_reviewer from hr_performance_reviews where tenant_id=p_tenant and id=p_review and plan_status='activated' and coalesce(finalization_status,'draft')<>'finalized';
 if not found then raise exception 'Review must be activated and not finalized'; end if;
 if coalesce(trim(p_period_key),'')='' then raise exception 'Check-in period is required'; end if;
 if p_period_start is not null and p_period_end is not null and p_period_end<p_period_start then raise exception 'Check-in period end date cannot be before its start date'; end if;
 if p_status not in ('on_track','at_risk','off_track','exceeded') then raise exception 'Invalid check-in status'; end if;
 if upper(p_period_key)<>'ADHOC' then
  select id into v_checkin from hr_performance_checkins
   where tenant_id=p_tenant and review_id=p_review and period_key=p_period_key
   order by created_at asc limit 1;
 end if;
 if v_checkin is null then
  insert into hr_performance_checkins(tenant_id,review_id,checkin_date,period_key,period_label,period_start,period_end,reviewer_employee_id,progress_percent,status,actual_progress,achievements,blockers,evidence,support_required,next_actions)
  values(p_tenant,p_review,coalesce(p_checkin_date,current_date),p_period_key,coalesce(nullif(trim(p_period_label),''),p_period_key),p_period_start,p_period_end,v_reviewer,null,p_status,nullif(trim(p_actual_progress),''),nullif(trim(p_achievements),''),nullif(trim(p_blockers),''),nullif(trim(p_evidence),''),nullif(trim(p_support_required),''),nullif(trim(p_next_actions),'')) returning id into v_checkin;
 else
  v_reused:=true;
  update hr_performance_checkins set
   status=p_status, reviewer_employee_id=coalesce(reviewer_employee_id,v_reviewer),
   actual_progress=coalesce(nullif(trim(p_actual_progress),''),actual_progress),
   achievements=coalesce(nullif(trim(p_achievements),''),achievements),
   blockers=coalesce(nullif(trim(p_blockers),''),blockers),
   evidence=coalesce(nullif(trim(p_evidence),''),evidence),
   support_required=coalesce(nullif(trim(p_support_required),''),support_required),
   next_actions=coalesce(nullif(trim(p_next_actions),''),next_actions)
  where id=v_checkin and tenant_id=p_tenant;
 end if;
 for m in select * from jsonb_array_elements(coalesce(p_measures,'[]'::jsonb)) loop
  v_item=nullif(m->>'item_id','')::uuid; v_actual=nullif(m->>'actual_value','')::numeric;
  if v_item is not null and v_actual is not null then
   select coalesce(pi.measurement_type_snapshot,ml.measurement_type,'numeric'),coalesce(pi.data_source_snapshot,ml.data_source,'manager_verified') into v_type,v_source
   from hr_performance_plan_items pi left join hr_performance_metric_library ml on ml.id=pi.metric_id
   where pi.id=v_item and pi.tenant_id=p_tenant and pi.review_id=p_review;
   if not found then raise exception 'Invalid performance measure in check-in'; end if;
   v_verification=case when v_type='system_calculated' then 'system_verified' when v_type='behavioral_rubric' then 'manager_attested' else 'pending' end;
   if v_verification='pending' and coalesce(trim(m->>'evidence'),'')='' and not exists(select 1 from hr_performance_evidence_attachments a where a.tenant_id=p_tenant and a.review_id=p_review and a.plan_item_id=v_item) then
    raise exception 'Objective/manual source figures require evidence before submission';
   end if;
   v_existing_item:=null; v_existing_verification:=null;
   select id,verification_status into v_existing_item,v_existing_verification
    from hr_performance_checkin_items where tenant_id=p_tenant and checkin_id=v_checkin and plan_item_id=v_item
    order by created_at desc limit 1;
   if v_existing_item is null then
    insert into hr_performance_checkin_items(tenant_id,checkin_id,review_id,plan_item_id,actual_value,evidence,evidence_source,measurement_inputs,measurement_type,verification_status)
    values(p_tenant,v_checkin,p_review,v_item,v_actual,nullif(trim(m->>'evidence'),''),coalesce(nullif(m->>'evidence_source',''),case when v_source='operational_record' then 'system_record' else 'manager_observation' end),coalesce(m->'measurement_inputs','{}'::jsonb),v_type,v_verification);
   elsif v_existing_verification in ('verified','system_verified') then
    null; -- preserve already verified facts; continuing the check-in must never overwrite them
   else
    update hr_performance_checkin_items set actual_value=v_actual,evidence=nullif(trim(m->>'evidence'),''),
     evidence_source=coalesce(nullif(m->>'evidence_source',''),case when v_source='operational_record' then 'system_record' else 'manager_observation' end),
     measurement_inputs=coalesce(m->'measurement_inputs','{}'::jsonb),measurement_type=v_type,verification_status=v_verification,verified_by=null,verified_at=null,verification_note=null
    where id=v_existing_item;
   end if;
  end if;
 end loop;
 perform unimis.hr_performance_refresh_intelligence(p_tenant,p_review);
 select case when coalesce(sum(weight) filter(where system_score is not null),0)=0 then null else round(sum(system_score*weight) filter(where system_score is not null)/sum(weight) filter(where system_score is not null),2) end into v_progress from hr_performance_plan_items where tenant_id=p_tenant and review_id=p_review;
 perform unimis.hr_refresh_checkin_verified_progress(p_tenant,v_checkin);
 update hr_performance_checkins set progress_percent=current_verified_progress_percent, recorded_progress_percent=current_verified_progress_percent where id=v_checkin;
 select current_verified_progress_percent into v_progress from hr_performance_checkins where id=v_checkin;
 return jsonb_build_object('checkin_id',v_checkin,'progress_percent',v_progress,'period',p_period_label,'verification_required',true,'reused_existing',v_reused);
end $$;
grant execute on function unimis.hr_performance_record_period_checkin(uuid,uuid,text,text,date,date,date,text,text,text,text,text,text,text,jsonb) to authenticated;


-- SOURCE 202610261030_011t_checkin_summary_finalization.sql
-- 011t: check-in summary and finalization lifecycle.
alter table unimis.hr_performance_checkins
 add column if not exists finalization_status text not null default 'open',
 add column if not exists finalized_at timestamptz,
 add column if not exists finalized_by uuid,
 add column if not exists status_override_reason text;

do $$ begin
 if not exists(select 1 from pg_constraint where conname='hr_performance_checkins_finalization_status_check') then
  alter table unimis.hr_performance_checkins add constraint hr_performance_checkins_finalization_status_check check(finalization_status in ('open','finalized'));
 end if;
end $$;

-- Recorded Progress is a frozen finalization snapshot, not a live value.
update unimis.hr_performance_checkins set recorded_progress_percent=null
where finalization_status='open';

create or replace function unimis.hr_save_performance_checkin_summary(
 p_tenant uuid,p_checkin uuid,p_status text,p_actual_progress text,p_achievements text,p_blockers text,p_evidence text,p_support_required text,p_next_actions text,p_override_reason text default null
) returns jsonb language plpgsql security definer set search_path=unimis as $$
declare c record; v_suggested text;
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 select * into c from hr_performance_checkins where tenant_id=p_tenant and id=p_checkin for update;
 if not found then raise exception 'Check-in not found'; end if;
 if c.finalization_status='finalized' then raise exception 'This check-in is finalized and locked'; end if;
 if p_status not in ('on_track','at_risk','off_track','exceeded') then raise exception 'Invalid check-in status'; end if;
 if length(coalesce(trim(p_actual_progress),''))<10 then raise exception 'Add a brief overall progress/result summary'; end if;
 if coalesce(c.verified_measure_count,0)=coalesce(c.total_measure_count,0) and coalesce(c.total_measure_count,0)>0 then
  v_suggested=case when coalesce(c.current_verified_progress_percent,0)>=100 then 'exceeded' when c.current_verified_progress_percent>=75 then 'on_track' when c.current_verified_progress_percent>=50 then 'at_risk' else 'off_track' end;
 end if;
 if v_suggested is not null and p_status<>v_suggested and length(coalesce(trim(p_override_reason),''))<10 then raise exception 'Explain why the supervisor status differs from the system suggestion'; end if;
 update hr_performance_checkins set status=p_status,actual_progress=nullif(trim(p_actual_progress),''),achievements=nullif(trim(p_achievements),''),blockers=nullif(trim(p_blockers),''),evidence=nullif(trim(p_evidence),''),support_required=nullif(trim(p_support_required),''),next_actions=nullif(trim(p_next_actions),''),status_override_reason=case when v_suggested is not null and p_status<>v_suggested then nullif(trim(p_override_reason),'') else null end where id=p_checkin and tenant_id=p_tenant;
 return jsonb_build_object('checkin_id',p_checkin,'suggested_status',v_suggested,'status',p_status,'summary_saved',true);
end $$;
grant execute on function unimis.hr_save_performance_checkin_summary(uuid,uuid,text,text,text,text,text,text,text,text) to authenticated;

create or replace function unimis.hr_finalize_performance_checkin(p_tenant uuid,p_checkin uuid) returns jsonb
language plpgsql security definer set search_path=unimis as $$
declare c record;
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 select * into c from hr_performance_checkins where tenant_id=p_tenant and id=p_checkin for update;
 if not found then raise exception 'Check-in not found'; end if;
 if c.finalization_status='finalized' then return jsonb_build_object('checkin_id',p_checkin,'already_finalized',true,'recorded_progress_percent',c.recorded_progress_percent); end if;
 perform unimis.hr_refresh_checkin_verified_progress(p_tenant,p_checkin);
 select * into c from hr_performance_checkins where tenant_id=p_tenant and id=p_checkin for update;
 if coalesce(c.total_measure_count,0)=0 or coalesce(c.verified_measure_count,0)<>c.total_measure_count then raise exception 'All performance measures must be verified before finalizing this check-in (% of % verified)',coalesce(c.verified_measure_count,0),coalesce(c.total_measure_count,0); end if;
 if length(coalesce(trim(c.actual_progress),''))<10 then raise exception 'Complete the Check-in Summary before finalizing'; end if;
 update hr_performance_checkins set recorded_progress_percent=current_verified_progress_percent,progress_percent=current_verified_progress_percent,finalization_status='finalized',finalized_at=now(),finalized_by=auth.uid() where tenant_id=p_tenant and id=p_checkin;
 return jsonb_build_object('checkin_id',p_checkin,'finalized',true,'recorded_progress_percent',c.current_verified_progress_percent);
end $$;
grant execute on function unimis.hr_finalize_performance_checkin(uuid,uuid) to authenticated;

-- 011r continuation, corrected: live evidence refresh must not overwrite Recorded Progress.
create or replace function unimis.hr_performance_record_period_checkin(
 p_tenant uuid,p_review uuid,p_period_key text,p_period_label text,p_period_start date,p_period_end date,p_checkin_date date,
 p_status text,p_actual_progress text,p_achievements text,p_blockers text,p_evidence text,p_support_required text,p_next_actions text,p_measures jsonb
) returns jsonb language plpgsql security definer set search_path=unimis as $$
declare v_checkin uuid; v_existing_item uuid; v_existing_verification text; m jsonb; v_item uuid; v_actual numeric; v_progress numeric; v_reviewer uuid; v_type text; v_source text; v_verification text; v_reused boolean:=false; v_final text;
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 select reviewer_employee_id into v_reviewer from hr_performance_reviews where tenant_id=p_tenant and id=p_review and plan_status='activated' and coalesce(finalization_status,'draft')<>'finalized';
 if not found then raise exception 'Review must be activated and not finalized'; end if;
 if coalesce(trim(p_period_key),'')='' then raise exception 'Check-in period is required'; end if;
 if p_period_start is not null and p_period_end is not null and p_period_end<p_period_start then raise exception 'Check-in period end date cannot be before its start date'; end if;
 if p_status not in ('on_track','at_risk','off_track','exceeded') then raise exception 'Invalid check-in status'; end if;
 if upper(p_period_key)<>'ADHOC' then select id,finalization_status into v_checkin,v_final from hr_performance_checkins where tenant_id=p_tenant and review_id=p_review and period_key=p_period_key order by created_at asc limit 1; end if;
 if v_final='finalized' then raise exception 'This check-in period is finalized and locked'; end if;
 if v_checkin is null then insert into hr_performance_checkins(tenant_id,review_id,checkin_date,period_key,period_label,period_start,period_end,reviewer_employee_id,progress_percent,status) values(p_tenant,p_review,coalesce(p_checkin_date,current_date),p_period_key,coalesce(nullif(trim(p_period_label),''),p_period_key),p_period_start,p_period_end,v_reviewer,null,p_status) returning id into v_checkin; else v_reused:=true; end if;
 for m in select * from jsonb_array_elements(coalesce(p_measures,'[]'::jsonb)) loop
  v_item=nullif(m->>'item_id','')::uuid; v_actual=nullif(m->>'actual_value','')::numeric;
  if v_item is not null and v_actual is not null then
   select coalesce(pi.measurement_type_snapshot,ml.measurement_type,'numeric'),coalesce(pi.data_source_snapshot,ml.data_source,'manager_verified') into v_type,v_source from hr_performance_plan_items pi left join hr_performance_metric_library ml on ml.id=pi.metric_id where pi.id=v_item and pi.tenant_id=p_tenant and pi.review_id=p_review;
   if not found then raise exception 'Invalid performance measure in check-in'; end if;
   v_verification=case when v_type='system_calculated' then 'system_verified' when v_type='behavioral_rubric' then 'manager_attested' else 'pending' end;
   if v_verification='pending' and coalesce(trim(m->>'evidence'),'')='' and not exists(select 1 from hr_performance_evidence_attachments a where a.tenant_id=p_tenant and a.review_id=p_review and a.plan_item_id=v_item) then raise exception 'Objective/manual source figures require evidence before submission'; end if;
   v_existing_item:=null;v_existing_verification:=null;
   select id,verification_status into v_existing_item,v_existing_verification from hr_performance_checkin_items where tenant_id=p_tenant and checkin_id=v_checkin and plan_item_id=v_item order by created_at desc limit 1;
   if v_existing_item is null then insert into hr_performance_checkin_items(tenant_id,checkin_id,review_id,plan_item_id,actual_value,evidence,evidence_source,measurement_inputs,measurement_type,verification_status) values(p_tenant,v_checkin,p_review,v_item,v_actual,nullif(trim(m->>'evidence'),''),coalesce(nullif(m->>'evidence_source',''),case when v_source='operational_record' then 'system_record' else 'manager_observation' end),coalesce(m->'measurement_inputs','{}'::jsonb),v_type,v_verification);
   elsif v_existing_verification in ('verified','system_verified') then null;
   else update hr_performance_checkin_items set actual_value=v_actual,evidence=nullif(trim(m->>'evidence'),''),evidence_source=coalesce(nullif(m->>'evidence_source',''),case when v_source='operational_record' then 'system_record' else 'manager_observation' end),measurement_inputs=coalesce(m->'measurement_inputs','{}'::jsonb),measurement_type=v_type,verification_status=v_verification,verified_by=null,verified_at=null,verification_note=null where id=v_existing_item; end if;
  end if;
 end loop;
 perform unimis.hr_performance_refresh_intelligence(p_tenant,p_review); perform unimis.hr_refresh_checkin_verified_progress(p_tenant,v_checkin);
 update hr_performance_checkins set progress_percent=current_verified_progress_percent where id=v_checkin;
 select current_verified_progress_percent into v_progress from hr_performance_checkins where id=v_checkin;
 return jsonb_build_object('checkin_id',v_checkin,'progress_percent',v_progress,'period',p_period_label,'verification_required',true,'reused_existing',v_reused);
end $$;
grant execute on function unimis.hr_performance_record_period_checkin(uuid,uuid,text,text,date,date,date,text,text,text,text,text,text,text,jsonb) to authenticated;


-- SOURCE 202610261045_012_performance_intelligence_simulation_foundation.sql
-- 012 Performance Intelligence & multi-industry simulation foundation
create table if not exists unimis.hr_performance_simulation_cases (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references unimis.tenants(id) on delete cascade,
  sector text not null,
  organization_name text not null,
  employee_name text not null,
  role_title text not null,
  scenario_code text not null,
  objective_score numeric(6,2),
  attendance_percent numeric(6,2),
  manager_rating numeric(4,2),
  evidence_completeness numeric(6,2) default 100,
  employee_reflection text,
  intelligence_summary text,
  exception_flags jsonb not null default '[]'::jsonb,
  recommended_action text,
  policy_gate text,
  created_at timestamptz not null default now(),
  unique(tenant_id,scenario_code)
);

alter table unimis.hr_performance_simulation_cases enable row level security;
drop policy if exists hr_performance_simulation_cases_member on unimis.hr_performance_simulation_cases;
create policy hr_performance_simulation_cases_member on unimis.hr_performance_simulation_cases
for all using (unimis.is_tenant_member(tenant_id)) with check (unimis.is_tenant_member(tenant_id));

create or replace function unimis.hr_seed_performance_intelligence_simulations(p_tenant uuid)
returns jsonb language plpgsql security definer set search_path=unimis as $$
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 insert into unimis.hr_performance_simulation_cases
 (tenant_id,sector,organization_name,employee_name,role_title,scenario_code,objective_score,attendance_percent,manager_rating,evidence_completeness,employee_reflection,intelligence_summary,exception_flags,recommended_action,policy_gate)
 values
 (p_tenant,'Trading','Aseda Trading Ltd','Adwoa Mensah','Sales Officer','TRADING-HIGH',96.4,97,4.6,100,'Exceeded my sales and collection targets and supported two new accounts.','Strong objective performance with complete evidence. Manager rating is aligned with operational results.','[]','Recognize performance; consider stretch targets and succession readiness.','Eligible subject to time-in-grade and approved vacancy.'),
 (p_tenant,'Trading','Aseda Trading Ltd','Kwame Boateng','Storekeeper','TRADING-BIAS',91.2,96,2.4,100,'Stock counts improved and variances reduced during the period.','Objective evidence is strong but the manager rating is materially lower. Calibration review is recommended before finalization.','["manager_objective_mismatch"]','Route to HR calibration; do not auto-adjust the rating.','Decision held pending calibration.'),
 (p_tenant,'Education','Apex Technical College','Efua Owusu','Lecturer','EDU-BALANCED',88.5,94,4.1,95,'Completed teaching plan and practical assessments; requested support for digital content.','Good teaching delivery with a minor attendance gap and a clear development request.','["attendance_below_target"]','Coaching plus digital-learning development plan.','No adverse decision; development action recommended.'),
 (p_tenant,'NGO','HopeBridge Foundation','Yaw Asare','Project Officer','NGO-EVIDENCE',92.0,98,4.3,62,'Field milestones were completed but several beneficiary reports are still being uploaded.','Reported outcomes are strong, but evidence completeness is insufficient for a high-confidence final assessment.','["evidence_gap"]','Request missing field evidence before assessment finalization.','Final score remains provisional until evidence threshold is met.'),
 (p_tenant,'Healthcare','Akwaaba Community Hospital','Akosua Frimpong','Records Officer','HEALTH-QUALITY',84.0,99,4.0,100,'Improved records turnaround but documentation errors remain a concern.','Attendance and conduct are strong; quality indicators show a recurring documentation issue.','["quality_risk"]','Targeted records-quality coaching and 60-day follow-up.','No PIP unless quality remains below policy threshold.'),
 (p_tenant,'Manufacturing','Prime Manufacturing Ltd','Kofi Antwi','Maintenance Technician','MFG-PIP',67.5,88,2.8,100,'Downtime response improved late in the period after additional coaching.','Multiple objective indicators remain below threshold despite complete evidence. Improvement is visible but not yet sustained.','["performance_below_threshold","attendance_risk"]','Supervisor review for structured PIP with measurable 60-day milestones.','PIP eligible; disciplinary action is not automatic.'),
 (p_tenant,'Hospitality','Akwaba Hotel','Mabel Addo','Front Desk Officer','HOTEL-PROMO-GATE',95.0,98,4.7,100,'Guest feedback and reservation accuracy were strong throughout the period.','High performance and strong service evidence. Promotion readiness is positive, but policy eligibility must still be checked.','["promotion_policy_gate"]','Place in talent pool; check time-in-grade before promotion approval.','Not yet eligible: minimum time-in-grade not satisfied.')
 on conflict (tenant_id,scenario_code) do update set
 objective_score=excluded.objective_score,attendance_percent=excluded.attendance_percent,manager_rating=excluded.manager_rating,evidence_completeness=excluded.evidence_completeness,
 employee_reflection=excluded.employee_reflection,intelligence_summary=excluded.intelligence_summary,exception_flags=excluded.exception_flags,recommended_action=excluded.recommended_action,policy_gate=excluded.policy_gate;
 return jsonb_build_object('ok',true,'cases',7);
end $$;

grant execute on function unimis.hr_seed_performance_intelligence_simulations(uuid) to authenticated;


-- SOURCE 202610261100_012b_leave_aware_performance_intelligence.sql
-- 012b Leave-aware Performance Intelligence simulation extension
alter table unimis.hr_performance_simulation_cases add column if not exists approved_leave_days numeric(7,2) not null default 0;
alter table unimis.hr_performance_simulation_cases add column if not exists adjusted_attendance_percent numeric(6,2);
alter table unimis.hr_performance_simulation_cases add column if not exists leave_intelligence text;
alter table unimis.hr_performance_simulation_cases add column if not exists employee_participation_status text not null default 'not_started';
alter table unimis.hr_performance_simulation_cases add column if not exists assessment_readiness text not null default 'system_prepared';

create or replace function unimis.hr_seed_performance_intelligence_simulations(p_tenant uuid)
returns jsonb language plpgsql security definer set search_path=unimis as $$
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 insert into unimis.hr_performance_simulation_cases
 (tenant_id,sector,organization_name,employee_name,role_title,scenario_code,objective_score,attendance_percent,manager_rating,evidence_completeness,employee_reflection,intelligence_summary,exception_flags,recommended_action,policy_gate,approved_leave_days,adjusted_attendance_percent,leave_intelligence,employee_participation_status,assessment_readiness)
 values
 (p_tenant,'Trading','Aseda Trading Ltd','Adwoa Mensah','Sales Officer','TRADING-HIGH',96.4,97,4.6,100,'Exceeded my sales and collection targets and supported two new accounts.','Strong objective performance with complete evidence. Manager rating is aligned with operational results.','[]','Recognize performance; consider stretch targets and succession readiness.','Eligible subject to time-in-grade and approved vacancy.',3,98.2,'Three approved leave days were excluded from attendance penalty. No leave-related concern.','submitted','ready'),
 (p_tenant,'Trading','Aseda Trading Ltd','Kwame Boateng','Storekeeper','TRADING-BIAS',91.2,96,2.4,100,'Stock counts improved and variances reduced during the period.','Objective evidence is strong but the manager rating is materially lower. Calibration review is recommended before finalization.','["manager_objective_mismatch"]','Route to HR calibration; do not auto-adjust the rating.','Decision held pending calibration.',2,96.8,'Approved leave is reconciled. The exception is the manager/objective mismatch, not attendance.','submitted','calibration_required'),
 (p_tenant,'Education','Apex Technical College','Efua Owusu','Lecturer','EDU-BALANCED',88.5,94,4.1,95,'Completed teaching plan and practical assessments; requested support for digital content.','Good teaching delivery with a minor attendance gap and a clear development request.','["attendance_below_target"]','Coaching plus digital-learning development plan.','No adverse decision; development action recommended.',6,96.8,'Six approved leave days were excluded. Adjusted attendance improves to 96.8%; no adverse leave inference should be made.','submitted','ready'),
 (p_tenant,'NGO','HopeBridge Foundation','Yaw Asare','Project Officer','NGO-EVIDENCE',92.0,98,4.3,62,'Field milestones were completed but several beneficiary reports are still being uploaded.','Reported outcomes are strong, but evidence completeness is insufficient for a high-confidence final assessment.','["evidence_gap"]','Request missing field evidence before assessment finalization.','Final score remains provisional until evidence threshold is met.',4,99.0,'Approved field/leave days are reconciled and do not explain the evidence gap.','submitted','evidence_required'),
 (p_tenant,'Healthcare','Akwaaba Community Hospital','Akosua Frimpong','Records Officer','HEALTH-QUALITY',84.0,99,4.0,100,'Improved records turnaround but documentation errors remain a concern.','Attendance and conduct are strong; quality indicators show a recurring documentation issue.','["quality_risk"]','Targeted records-quality coaching and 60-day follow-up.','No PIP unless quality remains below policy threshold.',8,99.0,'Eight approved leave days are neutral to performance. Quality, not leave, drives the exception.','submitted','supervisor_review'),
 (p_tenant,'Manufacturing','Prime Manufacturing Ltd','Kofi Antwi','Maintenance Technician','MFG-PIP',67.5,88,2.8,100,'Downtime response improved late in the period after additional coaching.','Multiple objective indicators remain below threshold despite complete evidence. Improvement is visible but not yet sustained.','["performance_below_threshold","attendance_risk"]','Supervisor review for structured PIP with measurable 60-day milestones.','PIP eligible; disciplinary action is not automatic.',1,88.4,'Only one approved leave day exists; low attendance remains a genuine exception after adjustment.','submitted','supervisor_review'),
 (p_tenant,'Hospitality','Akwaba Hotel','Mabel Addo','Front Desk Officer','HOTEL-PROMO-GATE',95.0,98,4.7,100,'Guest feedback and reservation accuracy were strong throughout the period.','High performance and strong service evidence. Promotion readiness is positive, but policy eligibility must still be checked.','["promotion_policy_gate"]','Place in talent pool; check time-in-grade before promotion approval.','Not yet eligible: minimum time-in-grade not satisfied.',5,99.1,'Approved leave is reconciled with no adverse attendance effect.','submitted','policy_check')
 on conflict (tenant_id,scenario_code) do update set
 objective_score=excluded.objective_score,attendance_percent=excluded.attendance_percent,manager_rating=excluded.manager_rating,evidence_completeness=excluded.evidence_completeness,employee_reflection=excluded.employee_reflection,intelligence_summary=excluded.intelligence_summary,exception_flags=excluded.exception_flags,recommended_action=excluded.recommended_action,policy_gate=excluded.policy_gate,approved_leave_days=excluded.approved_leave_days,adjusted_attendance_percent=excluded.adjusted_attendance_percent,leave_intelligence=excluded.leave_intelligence,employee_participation_status=excluded.employee_participation_status,assessment_readiness=excluded.assessment_readiness;
 return jsonb_build_object('ok',true,'cases',7,'leave_aware',true);
end $$;
grant execute on function unimis.hr_seed_performance_intelligence_simulations(uuid) to authenticated;


-- SOURCE 202610261115_012c_adaptive_sector_simulation.sql
-- 012c Adaptive sector simulations: retain existing seed then extend it.
alter function unimis.hr_seed_performance_intelligence_simulations(uuid) rename to hr_seed_performance_intelligence_simulations_012b;

create or replace function unimis.hr_seed_performance_intelligence_simulations(p_tenant uuid)
returns jsonb language plpgsql security definer set search_path=unimis as $$
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 perform unimis.hr_seed_performance_intelligence_simulations_012b(p_tenant);
 insert into unimis.hr_performance_simulation_cases
 (tenant_id,sector,organization_name,employee_name,role_title,scenario_code,objective_score,attendance_percent,manager_rating,evidence_completeness,employee_reflection,intelligence_summary,exception_flags,recommended_action,policy_gate,approved_leave_days,adjusted_attendance_percent,leave_intelligence,employee_participation_status,assessment_readiness) values
 (p_tenant,'Banking & Financial Services','Adom Rural Bank','Nana Osei','Credit Officer','BANK-CREDIT-RISK',89.0,96,4.1,100,'Collections improved, but two assigned facilities require closer follow-up.','Overall delivery is sound. Portfolio arrears require focused review before advancement decisions.','["portfolio_risk"]','Review arrears trend, recovery actions and documentation; set a 60-day portfolio follow-up.','No adverse employment decision is automatic; credit-risk evidence requires supervisor review.',4,97.2,'Approved leave is excluded. Attendance is not the source of the banking exception.','submitted','supervisor_review'),
 (p_tenant,'Broadcasting & Media','Unity FM','Abena Serwaa','Programs Producer','FM-PROGRAMS',93.0,95,4.4,92,'Delivered scheduled programmes and improved guest coordination; some programme logs remain outstanding.','Strong programme delivery with a small evidence/documentation gap in broadcast logs.','["evidence_gap"]','Complete programme logs and retain broadcast evidence before final assessment.','Content quality and compliance remain human-reviewed.',3,96.1,'Approved leave is reconciled and does not create an attendance penalty.','submitted','evidence_required'),
 (p_tenant,'General / Other','Adaptive Services Ltd','Daniel Mensah','Operations Officer','GENERAL-ADAPTIVE',87.0,97,4.0,90,'Completed core responsibilities and requested clearer targets for the next cycle.','General-purpose profile demonstrates the adaptive fallback when no specialist industry template exists.','["kpi_template_review"]','Use organization, department and position context to recommend editable KPIs for the next cycle.','General template remains configurable; HR approves organization-specific measures.',2,97.8,'Approved leave is neutral. Organization policy determines attendance thresholds.','submitted','ready')
 on conflict (tenant_id,scenario_code) do update set objective_score=excluded.objective_score,attendance_percent=excluded.attendance_percent,manager_rating=excluded.manager_rating,evidence_completeness=excluded.evidence_completeness,employee_reflection=excluded.employee_reflection,intelligence_summary=excluded.intelligence_summary,exception_flags=excluded.exception_flags,recommended_action=excluded.recommended_action,policy_gate=excluded.policy_gate,approved_leave_days=excluded.approved_leave_days,adjusted_attendance_percent=excluded.adjusted_attendance_percent,leave_intelligence=excluded.leave_intelligence,employee_participation_status=excluded.employee_participation_status,assessment_readiness=excluded.assessment_readiness;
 return jsonb_build_object('ok',true,'cases',10,'adaptive',true,'sectors',9);
end $$;
grant execute on function unimis.hr_seed_performance_intelligence_simulations(uuid) to authenticated;


-- SOURCE 202610271230_013_performance_automation_engine.sql
-- 013 Performance Automation Engine
-- Universal evidence model: KPI + Task/SLA + Work Standard + Compliance + Competency + Attendance.

alter table unimis.hr_performance_metric_library add column if not exists measurement_class text not null default 'kpi';
alter table unimis.hr_performance_metric_library add column if not exists measurement_frequency text not null default 'monthly';
alter table unimis.hr_performance_metric_library add column if not exists source_type text not null default 'verified_evidence';
alter table unimis.hr_performance_metric_library add column if not exists verification_rule text not null default 'supervisor_review';
alter table unimis.hr_performance_metric_library add column if not exists formula_expression text;

create table if not exists unimis.hr_performance_templates(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.tenants(id) on delete cascade,
 code text not null, name text not null, industry text not null default 'general', department_name text,
 position_title text not null, grade_name text, description text, active boolean not null default true,
 created_at timestamptz not null default now(), unique(tenant_id,code)
);
create table if not exists unimis.hr_performance_template_items(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.tenants(id) on delete cascade,
 template_id uuid not null references unimis.hr_performance_templates(id) on delete cascade,
 code text not null, name text not null, measurement_class text not null,
 target_value numeric(14,2), unit text not null default 'percent', direction text not null default 'higher_better',
 weight numeric(6,2) not null, frequency text not null default 'monthly', source_type text not null,
 verification_rule text not null default 'system_or_supervisor', formula_expression text, display_order int not null default 10,
 unique(template_id,code)
);
create table if not exists unimis.hr_performance_data_sources(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.tenants(id) on delete cascade,
 code text not null, name text not null, source_type text not null, trust_level text not null default 'verified',
 status text not null default 'active', description text, last_sync_at timestamptz, created_at timestamptz not null default now(),
 unique(tenant_id,code)
);
create table if not exists unimis.hr_performance_ledger(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.tenants(id) on delete cascade,
 employee_ref text not null, employee_name text not null, position_title text, grade_name text,
 period_key text not null, fact_code text not null, fact_name text not null, measurement_class text not null,
 actual_value numeric(14,2), target_value numeric(14,2), unit text, direction text not null default 'higher_better',
 source_code text not null, verification_status text not null default 'system_verified', evidence_note text,
 observed_at date not null, created_at timestamptz not null default now(), unique(tenant_id,employee_ref,period_key,fact_code)
);
create table if not exists unimis.hr_automated_checkins(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references unimis.tenants(id) on delete cascade,
 employee_ref text not null, employee_name text not null, period_key text not null, period_label text not null,
 prepared_score numeric(6,2), status text not null default 'prepared', exception_count int not null default 0,
 exception_summary text, employee_response text, supervisor_response text, prepared_at timestamptz not null default now(),
 unique(tenant_id,employee_ref,period_key)
);

do $$ declare t text; begin
 foreach t in array array['hr_performance_templates','hr_performance_template_items','hr_performance_data_sources','hr_performance_ledger','hr_automated_checkins'] loop
  execute format('alter table unimis.%I enable row level security',t);
  execute format('drop policy if exists tenant_member_all on unimis.%I',t);
  execute format('create policy tenant_member_all on unimis.%I for all using (unimis.is_tenant_member(tenant_id)) with check (unimis.is_tenant_member(tenant_id))',t);
 end loop;
end $$;

create index if not exists idx_perf_ledger_employee_period on unimis.hr_performance_ledger(tenant_id,employee_ref,period_key);
create index if not exists idx_auto_checkins_period on unimis.hr_automated_checkins(tenant_id,period_key,status);

create or replace function unimis.hr_seed_bank_performance_automation(p_tenant uuid) returns jsonb language plpgsql security definer set search_path=unimis as $$
declare tpl uuid; r record; p text; d date; disb numeric; npl numeric; tat numeric; kyc numeric; att numeric; sc numeric; exc int;
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 insert into hr_performance_templates(tenant_id,code,name,industry,department_name,position_title,grade_name,description)
 values(p_tenant,'BANK-CREDIT-G3','Grade 3 Credit Officer Performance Template','banking','Credit','Credit Officer','Grade 3','Reference template proving position/grade performance automation for Adom Rural Bank.')
 on conflict(tenant_id,code) do update set name=excluded.name,description=excluded.description returning id into tpl;
 if tpl is null then select id into tpl from hr_performance_templates where tenant_id=p_tenant and code='BANK-CREDIT-G3'; end if;
 insert into hr_performance_template_items(tenant_id,template_id,code,name,measurement_class,target_value,unit,direction,weight,frequency,source_type,verification_rule,formula_expression,display_order) values
 (p_tenant,tpl,'DISB','Loan Disbursement Volume','kpi',500000,'GHS','higher_better',25,'quarterly','import_or_api','trusted_source','actual / target * 100',10),
 (p_tenant,tpl,'NPL','NPL Ratio','kpi',3,'percent','lower_better',20,'monthly','import_or_api','trusted_source','target / actual * 100 capped at 100',20),
 (p_tenant,tpl,'TAT','Loan Turnaround Time','task_sla',48,'hours','lower_better',15,'monthly','workflow_or_import','trusted_source','target / actual * 100 capped at 100',30),
 (p_tenant,tpl,'KYC','KYC / Site Visit Accuracy','compliance',100,'percent','higher_better',15,'monthly','checklist_or_import','compliance_review','actual / target * 100',40),
 (p_tenant,tpl,'ATT','Attendance & Punctuality','attendance',95,'percent','higher_better',10,'monthly','hr_attendance','system_verified','leave-adjusted attendance',50),
 (p_tenant,tpl,'CONDUCT','Professional Conduct & Service','competency',4,'score_5','higher_better',15,'quarterly','anchored_observation','supervisor_review','anchored 1-5 rubric',60)
 on conflict(template_id,code) do update set name=excluded.name,measurement_class=excluded.measurement_class,target_value=excluded.target_value,weight=excluded.weight,source_type=excluded.source_type;
 insert into hr_performance_data_sources(tenant_id,code,name,source_type,trust_level,description) values
 (p_tenant,'HR-ATT','HRPayrollCore Attendance','native','system','Attendance and approved leave reconciliation.'),
 (p_tenant,'BANK-CSV','Core Banking CSV / Excel','import','verified','Fallback when direct API access is unavailable.'),
 (p_tenant,'BANK-API','Core Banking API','api','trusted','Future automated operational synchronization.'),
 (p_tenant,'CHECKLIST','Compliance / Work Checklist','checklist','verified','Structured compliance and work-standard observations.'),
 (p_tenant,'SUP-RUBRIC','Anchored Supervisor Observation','observation','human_verified','Behavioural judgment using observable anchors, not free-form scoring.')
 on conflict(tenant_id,code) do update set name=excluded.name,description=excluded.description;

 for r in select * from (values
  ('2026-07'::text,'2026-07-31'::date,150000::numeric,2.6::numeric,46::numeric,100::numeric,98::numeric),
  ('2026-08','2026-08-31'::date,160000,2.8,49,100,96),
  ('2026-09','2026-09-30'::date,165000,2.7,53,100,97)
 ) v(period_key,observed_date,disbursement,npl_ratio,turnaround,kyc_accuracy,attendance) loop
  p:=r.period_key; d:=r.observed_date; disb:=r.disbursement; npl:=r.npl_ratio; tat:=r.turnaround; kyc:=r.kyc_accuracy; att:=r.attendance;
  insert into hr_performance_ledger(tenant_id,employee_ref,employee_name,position_title,grade_name,period_key,fact_code,fact_name,measurement_class,actual_value,target_value,unit,direction,source_code,verification_status,evidence_note,observed_at) values
  (p_tenant,'BANK-KM-001','Kojo Mensah','Credit Officer','Grade 3',p,'DISB','Loan Disbursement Volume','kpi',disb,166666.67,'GHS','higher_better','BANK-CSV','system_verified','Imported core banking operational fact',d),
  (p_tenant,'BANK-KM-001','Kojo Mensah','Credit Officer','Grade 3',p,'NPL','NPL Ratio','kpi',npl,3,'percent','lower_better','BANK-CSV','system_verified','Portfolio quality extract',d),
  (p_tenant,'BANK-KM-001','Kojo Mensah','Credit Officer','Grade 3',p,'TAT','Loan Turnaround Time','task_sla',tat,48,'hours','lower_better','BANK-API','system_verified','Workflow turnaround measurement',d),
  (p_tenant,'BANK-KM-001','Kojo Mensah','Credit Officer','Grade 3',p,'KYC','KYC / Site Visit Accuracy','compliance',kyc,100,'percent','higher_better','CHECKLIST','verified','Compliance checklist result',d),
  (p_tenant,'BANK-KM-001','Kojo Mensah','Credit Officer','Grade 3',p,'ATT','Attendance & Punctuality','attendance',att,95,'percent','higher_better','HR-ATT','system_verified','Approved leave excluded from denominator',d)
  on conflict(tenant_id,employee_ref,period_key,fact_code) do update set actual_value=excluded.actual_value,evidence_note=excluded.evidence_note;
  sc:=round(((least(disb/166666.67,1)*25)+(least(3/npl,1)*20)+(least(48/tat,1)*15)+(least(kyc/100,1)*15)+(least(att/95,1)*10)+15)/100*100,1);
  exc:=case when tat>48 then 1 else 0 end;
  insert into hr_automated_checkins(tenant_id,employee_ref,employee_name,period_key,period_label,prepared_score,status,exception_count,exception_summary)
  values(p_tenant,'BANK-KM-001','Kojo Mensah',p,to_char(d,'FMMonth YYYY'),sc,case when exc>0 then 'exception_review' else 'prepared' end,exc,case when exc>0 then 'Loan turnaround exceeded the 48-hour SLA. Employee/supervisor context requested; all other verified facts require no re-entry.' else 'All verified measures are within expected range. Human input is optional.' end)
  on conflict(tenant_id,employee_ref,period_key) do update set prepared_score=excluded.prepared_score,status=excluded.status,exception_count=excluded.exception_count,exception_summary=excluded.exception_summary;
 end loop;
 return jsonb_build_object('template','BANK-CREDIT-G3','employee','Kojo Mensah','periods',3,'mode','deterministic simulation');
end $$;
grant execute on function unimis.hr_seed_bank_performance_automation(uuid) to authenticated;


-- SOURCE 202610271300_014_performance_setup_templates.sql
-- 014 Performance Setup restructure
alter table unimis.hr_performance_templates add column if not exists department_id uuid references unimis.departments(id) on delete set null;
alter table unimis.hr_performance_templates add column if not exists position_id uuid references unimis.hr_positions(id) on delete set null;
alter table unimis.hr_performance_templates add column if not exists grade_id uuid references unimis.hr_job_grades(id) on delete set null;
alter table unimis.hr_performance_template_items add column if not exists metric_id uuid references unimis.hr_performance_metric_library(id) on delete set null;
create unique index if not exists uq_perf_template_metric on unimis.hr_performance_template_items(template_id,metric_id) where metric_id is not null;
create index if not exists idx_perf_templates_assignment on unimis.hr_performance_templates(tenant_id,industry,department_id,position_id,grade_id,active);


-- SOURCE 202610271400_015_ai_assisted_performance_data_hub.sql
-- 015 AI-assisted Performance Data Hub
alter table unimis.hr_performance_metric_library add column if not exists aggregation_method text not null default 'sum'
 check (aggregation_method in ('sum','average','count','latest','min','max'));
alter table unimis.hr_performance_template_items add column if not exists aggregation_method text not null default 'sum'
 check (aggregation_method in ('sum','average','count','latest','min','max'));

create table if not exists unimis.hr_performance_mapping_profiles(
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references unimis.tenants(id) on delete cascade,
 name text not null, source_type text not null default 'csv',
 mapping_config jsonb not null default '{}'::jsonb,
 active boolean not null default true,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 unique(tenant_id,name)
);

create table if not exists unimis.hr_performance_import_batches(
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references unimis.tenants(id) on delete cascade,
 file_name text not null, source_type text not null default 'csv',
 mapping_config jsonb not null default '{}'::jsonb,
 total_rows int not null default 0, accepted_rows int not null default 0,
 rejected_rows int not null default 0, duplicate_rows int not null default 0,
 status text not null default 'uploaded', error_summary jsonb not null default '[]'::jsonb,
 created_at timestamptz not null default now(), completed_at timestamptz
);

create table if not exists unimis.hr_performance_source_records(
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references unimis.tenants(id) on delete cascade,
 batch_id uuid references unimis.hr_performance_import_batches(id) on delete set null,
 row_number int, employee_ref text not null, employee_name text,
 observed_at date not null, period_key text not null,
 metric_id uuid references unimis.hr_performance_metric_library(id) on delete set null,
 metric_code text not null, metric_name text not null,
 raw_column text, raw_value text, numeric_value numeric(18,4), unit text,
 aggregation_method text not null default 'sum',
 verification_status text not null default 'import_validated',
 source_record_key text not null, created_at timestamptz not null default now(),
 unique(tenant_id,source_record_key)
);

do $$ declare t text; begin
 foreach t in array array['hr_performance_mapping_profiles','hr_performance_import_batches','hr_performance_source_records'] loop
  execute format('alter table unimis.%I enable row level security',t);
  execute format('drop policy if exists tenant_member_all on unimis.%I',t);
  execute format('create policy tenant_member_all on unimis.%I for all using (unimis.is_tenant_member(tenant_id)) with check (unimis.is_tenant_member(tenant_id))',t);
 end loop;
end $$;

create index if not exists idx_perf_source_employee_period on unimis.hr_performance_source_records(tenant_id,employee_ref,period_key,metric_code);
create index if not exists idx_perf_import_batches_created on unimis.hr_performance_import_batches(tenant_id,created_at desc);

-- Aggregate validated source observations into the existing Performance Ledger.
create or replace function unimis.hr_aggregate_performance_source_records(p_tenant uuid,p_period text)
returns jsonb language plpgsql security definer set search_path=unimis as $$
declare r record; n int:=0; v numeric;
begin
 if not unimis.is_tenant_member(p_tenant) then raise exception 'Tenant access denied'; end if;
 for r in
  select employee_ref,max(coalesce(employee_name,employee_ref)) employee_name,metric_code,max(metric_name) metric_name,
         max(metric_id::text)::uuid metric_id,max(unit) unit,max(aggregation_method) aggregation_method,
         min(observed_at) first_date,max(observed_at) last_date
  from hr_performance_source_records
  where tenant_id=p_tenant and period_key=p_period and verification_status='import_validated'
  group by employee_ref,metric_code
 loop
  select case r.aggregation_method
    when 'average' then avg(numeric_value)
    when 'count' then count(numeric_value)::numeric
    when 'latest' then (array_agg(numeric_value order by observed_at desc,id desc))[1]
    when 'min' then min(numeric_value)
    when 'max' then max(numeric_value)
    else sum(numeric_value) end into v
  from hr_performance_source_records
  where tenant_id=p_tenant and period_key=p_period and employee_ref=r.employee_ref and metric_code=r.metric_code and verification_status='import_validated';

  insert into hr_performance_ledger(tenant_id,employee_ref,employee_name,period_key,fact_code,fact_name,measurement_class,actual_value,target_value,unit,direction,source_code,verification_status,evidence_note,observed_at)
  select p_tenant,r.employee_ref,r.employee_name,p_period,r.metric_code,r.metric_name,
         coalesce(m.measurement_class,'kpi'),v,m.default_target,r.unit,coalesce(m.direction,'higher_better'),
         'CSV-DATA-HUB','system_verified',
         'Aggregated from validated Performance Source Records using '||upper(r.aggregation_method)||'.',r.last_date
  from hr_performance_metric_library m where m.id=r.metric_id
  on conflict(tenant_id,employee_ref,period_key,fact_code) do update
   set actual_value=excluded.actual_value,verification_status=excluded.verification_status,evidence_note=excluded.evidence_note,observed_at=excluded.observed_at;
  n:=n+1;
 end loop;
 return jsonb_build_object('period',p_period,'ledger_facts',n);
end $$;
grant execute on function unimis.hr_aggregate_performance_source_records(uuid,text) to authenticated;


-- SOURCE 202610271430_016_generated_performance_collection_templates.sql
-- 016 Generated performance data collection templates
create table if not exists unimis.hr_performance_collection_templates(
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references unimis.tenants(id) on delete cascade,
 template_token text not null,
 name text not null,
 performance_template_id uuid references unimis.hr_performance_templates(id) on delete set null,
 period_key text not null,
 frequency text not null default 'monthly',
 employee_count int not null default 0,
 measure_count int not null default 0,
 metadata jsonb not null default '{}'::jsonb,
 active boolean not null default true,
 created_at timestamptz not null default now(),
 unique(tenant_id,template_token)
);
alter table unimis.hr_performance_collection_templates enable row level security;
drop policy if exists tenant_member_all on unimis.hr_performance_collection_templates;
create policy tenant_member_all on unimis.hr_performance_collection_templates for all
 using (unimis.is_tenant_member(tenant_id)) with check (unimis.is_tenant_member(tenant_id));
create index if not exists idx_perf_collection_template_lookup
 on unimis.hr_performance_collection_templates(tenant_id,period_key,performance_template_id,active);


-- UNIMIS BRIDGE 167
-- UniMIS Build 167: bridge UniMIS institution identity/RBAC into HRPayrollCore.
-- Requires the HRPayrollCore schema migrations to be installed in the same schema first.
create or replace function unimis.unimis_hrpayroll_context167()
returns table(tenant_id uuid,institution_name text,institution_code text,hr_role text)
language plpgsql security definer set search_path=unimis as $$
declare v_inst uuid; v_name text; v_code text; v_role text; v_hr_role text;
begin
 select m.institution_id,i.name,i.code,r.code
 into v_inst,v_name,v_code,v_role
 from unimis.unimis_effective_memberships116 m
 join unimis.institutions i on i.id=m.institution_id
 join unimis.roles r on r.id=m.role_id
 where m.user_id=auth.uid() and m.status='active' and r.is_active
 order by m.is_primary desc limit 1;
 if v_inst is null then return; end if;
 v_hr_role:=case
  when v_role='owner' then 'owner'
  when v_role in ('admin','administrator','registrar') then 'administrator'
  when v_role='hr_officer' then 'hr_officer'
  when v_role='payroll_officer' then 'payroll_officer'
  when v_role in ('finance_officer','accountant') then 'accountant'
  when v_role='auditor' then 'auditor'
  else 'employee' end;
 insert into unimis.tenants(id,name,code,hr_enabled,payroll_enabled,created_by)
 values(v_inst,v_name,coalesce(nullif(v_code,''),'UNI-'||left(v_inst::text,8)),true,true,auth.uid())
 on conflict(id) do update set name=excluded.name,hr_enabled=true,payroll_enabled=true;
 insert into unimis.tenant_memberships(tenant_id,user_id,role,status)
 values(v_inst,auth.uid(),v_hr_role,'active')
 on conflict(tenant_id,user_id) do update set role=excluded.role,status='active';
 return query select v_inst,v_name,v_code,v_hr_role;
end $$;
grant execute on function unimis.unimis_hrpayroll_context167() to authenticated;
