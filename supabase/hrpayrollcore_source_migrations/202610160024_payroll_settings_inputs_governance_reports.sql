-- HRPayrollCore 007a: unified settings, employee payroll inputs, separate HR/payroll governance, report builder support

create table if not exists public.payroll_deduction_definitions(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.tenants(id) on delete cascade,
 code text not null, name text not null, description text, employee_or_employer text not null default 'employee' check(employee_or_employer in ('employee','employer','both')),
 calculation_method text not null default 'fixed' check(calculation_method in ('fixed','percentage')), default_value numeric(14,4) not null default 0,
 percentage_base text not null default 'basic', pre_tax boolean not null default false, recurring boolean not null default true,
 mandatory boolean not null default false, requires_consent boolean not null default true, requires_approval boolean not null default true,
 minimum_amount numeric(14,2), maximum_amount numeric(14,2), gl_account text, effective_from date not null default current_date, effective_to date,
 active boolean not null default true, created_at timestamptz not null default now(), unique(tenant_id,code)
);
create table if not exists public.payroll_employee_deductions(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.tenants(id) on delete cascade,
 employee_id uuid not null references public.hr_employees(id) on delete cascade, deduction_id uuid not null references public.payroll_deduction_definitions(id),
 amount numeric(14,2), rate numeric(8,4), effective_from date not null, effective_to date, consent_reference text,
 status text not null default 'pending' check(status in ('draft','pending','approved','rejected','inactive')), created_at timestamptz not null default now()
);
create table if not exists public.payroll_employee_loans(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.tenants(id) on delete cascade, employee_id uuid not null references public.hr_employees(id) on delete cascade,
 loan_type text not null default 'staff_loan', reference text, principal numeric(14,2) not null, installment numeric(14,2) not null, balance numeric(14,2) not null,
 start_period date not null, end_period date, status text not null default 'active' check(status in ('pending','active','settled','suspended','cancelled')), notes text, created_at timestamptz not null default now()
);
create table if not exists public.hrpay_approval_events(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.tenants(id) on delete cascade, domain text not null check(domain in ('hr','payroll')),
 workflow_type text not null, reference text, status text not null default 'pending', submitted_by uuid references auth.users(id), approved_by uuid references auth.users(id),
 submitted_label text, approved_label text, notes text, created_at timestamptz not null default now(), decided_at timestamptz
);
create table if not exists public.hrpay_audit_events(
 id uuid primary key default gen_random_uuid(), tenant_id uuid not null references public.tenants(id) on delete cascade, domain text not null check(domain in ('hr','payroll')),
 action text not null, entity_type text not null, entity_id uuid, entity_reference text, old_data jsonb, new_data jsonb, actor_id uuid references auth.users(id), actor_label text,
 created_at timestamptz not null default now()
);

alter table public.payroll_deduction_definitions enable row level security; alter table public.payroll_employee_deductions enable row level security; alter table public.payroll_employee_loans enable row level security; alter table public.hrpay_approval_events enable row level security; alter table public.hrpay_audit_events enable row level security;
do $$ declare t text; begin foreach t in array array['payroll_deduction_definitions','payroll_employee_deductions','payroll_employee_loans','hrpay_approval_events','hrpay_audit_events'] loop execute format('create policy %I on public.%I for select to authenticated using (public.is_tenant_member(tenant_id))',t||'_read_007a',t); execute format('create policy %I on public.%I for all to authenticated using (public.has_tenant_role(tenant_id,array[''owner'',''administrator'',''payroll_manager'',''payroll_officer''])) with check (public.has_tenant_role(tenant_id,array[''owner'',''administrator'',''payroll_manager'',''payroll_officer'']))',t||'_manage_007a',t); end loop; end $$;

-- Seed organization-specific non-statutory deductions for demonstration only; values remain editable.
insert into public.payroll_deduction_definitions(tenant_id,code,name,description,calculation_method,default_value,employee_or_employer,requires_consent,requires_approval,effective_from)
select t.id,'WELFARE','Staff Welfare','Agreed staff welfare contribution','fixed',50,'employee',true,true,'2026-10-01' from public.tenants t where not exists(select 1 from public.payroll_deduction_definitions d where d.tenant_id=t.id and d.code='WELFARE');
insert into public.payroll_deduction_definitions(tenant_id,code,name,description,calculation_method,default_value,employee_or_employer,requires_consent,requires_approval,effective_from)
select t.id,'STAFF_ASSOC','Staff Association','Agreed staff association contribution','fixed',25,'employee',true,true,'2026-10-01' from public.tenants t where not exists(select 1 from public.payroll_deduction_definitions d where d.tenant_id=t.id and d.code='STAFF_ASSOC');

-- Demonstration payroll inputs: pending so payroll approval is visible before calculation.
insert into public.payroll_adjustments(tenant_id,employee_id,period_id,adjustment_type,code,description,amount,taxable,pensionable,status,source_module,source_reference)
select e.tenant_id,e.id,p.id,'overtime','OT-DEMO','Approved HR overtime imported for payroll',180,true,false,'pending','attendance','DEMO-OT-001'
from public.hr_employees e join lateral(select id from public.payroll_periods p where p.tenant_id=e.tenant_id order by start_date desc limit 1)p on true
where e.employment_status='active' and e.employee_no=(select min(e2.employee_no) from public.hr_employees e2 where e2.tenant_id=e.tenant_id and e2.employment_status='active')
and not exists(select 1 from public.payroll_adjustments a where a.tenant_id=e.tenant_id and a.source_reference='DEMO-OT-001');

-- Separate governance seed demonstrates the two approval/audit streams.
insert into public.hrpay_approval_events(tenant_id,domain,workflow_type,reference,status,submitted_label,notes)
select id,'hr','attendance_correction','ATT-DEMO-001','pending','HR Officer','Example HR approval stream' from public.tenants t where not exists(select 1 from public.hrpay_approval_events a where a.tenant_id=t.id and a.reference='ATT-DEMO-001');
insert into public.hrpay_approval_events(tenant_id,domain,workflow_type,reference,status,submitted_label,notes)
select id,'payroll','payroll_input','PAY-DEMO-001','pending','Payroll Officer','Example payroll approval stream' from public.tenants t where not exists(select 1 from public.hrpay_approval_events a where a.tenant_id=t.id and a.reference='PAY-DEMO-001');
insert into public.hrpay_audit_events(tenant_id,domain,action,entity_type,entity_reference,actor_label,new_data)
select id,'payroll','settings_seeded','payroll_settings','007A','System',jsonb_build_object('package','007a','note','Configurable payroll settings enabled') from public.tenants t where not exists(select 1 from public.hrpay_audit_events a where a.tenant_id=t.id and a.entity_reference='007A');

-- Make tenant PAYE copies safely override global templates. Global templates remain immutable historical references.
create or replace function public.payroll_progressive_tax(p_tenant uuid,p_country text,p_date date,p_chargeable numeric)
returns numeric language plpgsql stable security definer set search_path=public as $$
declare rem numeric:=greatest(coalesce(p_chargeable,0),0); total numeric:=0; b record; take_amt numeric;
begin
 for b in select * from public.payroll_tax_bands x where x.country_code=p_country and x.frequency='monthly' and x.active and x.effective_from<=p_date and (x.effective_to is null or x.effective_to>=p_date) and (x.tenant_id=p_tenant or x.tenant_id is null) order by (x.tenant_id is not null) desc,x.effective_from desc,x.band_order loop
  -- If tenant-specific bands exist for the effective date, ignore global bands.
  if b.tenant_id is null and exists(select 1 from public.payroll_tax_bands z where z.tenant_id=p_tenant and z.country_code=p_country and z.frequency='monthly' and z.active and z.effective_from<=p_date and (z.effective_to is null or z.effective_to>=p_date)) then continue; end if;
  exit when rem<=0; take_amt:=case when b.band_amount is null then rem else least(rem,b.band_amount) end; total:=total+(take_amt*b.rate/100); rem:=rem-take_amt;
 end loop; return round(total,2);
end $$;

grant execute on function public.payroll_progressive_tax(uuid,text,date,numeric) to authenticated;
