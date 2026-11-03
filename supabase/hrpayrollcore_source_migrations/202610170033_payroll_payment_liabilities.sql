-- HRPayrollCore 008d: payroll settlement/remittance register and accounting handoff foundation
create table if not exists public.payroll_payment_liabilities (
 id uuid primary key default gen_random_uuid(),
 tenant_id uuid not null references public.tenants(id) on delete cascade,
 payroll_run_id uuid null references public.payroll_runs(id) on delete cascade,
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
create unique index if not exists uq_payroll_liability_run_type_payee on public.payroll_payment_liabilities(payroll_run_id,liability_type,payee_name) where payroll_run_id is not null;
alter table public.payroll_payment_liabilities enable row level security;
drop policy if exists payroll_payment_liabilities_member on public.payroll_payment_liabilities;
create policy payroll_payment_liabilities_member on public.payroll_payment_liabilities for all to authenticated using (public.is_tenant_member(tenant_id)) with check (public.is_tenant_member(tenant_id));
comment on table public.payroll_payment_liabilities is 'Settlement register for salaries, PAYE, pension and third-party payroll liabilities; suitable for accounting handoff.';
