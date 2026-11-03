-- HRPayrollCore 009 - Universal Payroll Rules & Workforce Earnings Engine Foundation
-- Adds effective-dated worker payroll classification, Tier 3 participation mode,
-- earnings-source definitions, and pension-age review flags without hard-coding
-- a person's statutory treatment from age alone.

create table if not exists public.payroll_worker_classifications (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  employee_id uuid not null references public.hr_employees(id) on delete cascade,
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
  on public.payroll_worker_classifications(tenant_id, employee_id, effective_from desc);
create unique index if not exists uq_payroll_worker_classification_active
  on public.payroll_worker_classifications(tenant_id, employee_id)
  where effective_to is null;

alter table public.payroll_worker_classifications enable row level security;
drop policy if exists payroll_worker_classifications_member on public.payroll_worker_classifications;
create policy payroll_worker_classifications_member on public.payroll_worker_classifications
  for all using (public.is_tenant_member(tenant_id))
  with check (public.is_tenant_member(tenant_id));

-- Explicit Tier 3 mode. Existing provident_fund_enabled/rates remain for compatibility.
alter table public.payroll_profiles
  add column if not exists tier3_participation_mode text not null default 'organization_default';

do $$ begin
  alter table public.payroll_profiles
    add constraint payroll_profiles_tier3_participation_mode_chk
    check (tier3_participation_mode in ('organization_default','participating','not_participating'));
exception when duplicate_object then null; end $$;

-- Reusable source catalogue: defines WHERE a payroll amount originates.
create table if not exists public.payroll_earning_sources (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
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

alter table public.payroll_earning_sources enable row level security;
drop policy if exists payroll_earning_sources_member on public.payroll_earning_sources;
create policy payroll_earning_sources_member on public.payroll_earning_sources
  for all using (public.is_tenant_member(tenant_id))
  with check (public.is_tenant_member(tenant_id));

-- Maps a configured payroll component to its normal source. No amount is created here.
create table if not exists public.payroll_component_sources (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  component_id uuid not null references public.payroll_components(id) on delete cascade,
  earning_source_id uuid not null references public.payroll_earning_sources(id) on delete cascade,
  priority integer not null default 100,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique(tenant_id, component_id, earning_source_id)
);

alter table public.payroll_component_sources enable row level security;
drop policy if exists payroll_component_sources_member on public.payroll_component_sources;
create policy payroll_component_sources_member on public.payroll_component_sources
  for all using (public.is_tenant_member(tenant_id))
  with check (public.is_tenant_member(tenant_id));

-- Configurable review milestones. A milestone raises a review flag only; it never
-- automatically stops SSNIT/Tier 2/Tier 3 or changes tax treatment.
create table if not exists public.payroll_pension_review_rules (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
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

alter table public.payroll_pension_review_rules enable row level security;
drop policy if exists payroll_pension_review_rules_member on public.payroll_pension_review_rules;
create policy payroll_pension_review_rules_member on public.payroll_pension_review_rules
  for all using (public.is_tenant_member(tenant_id))
  with check (public.is_tenant_member(tenant_id));

-- Seed source definitions for every tenant. Safe to rerun.
insert into public.payroll_earning_sources(tenant_id,code,name,source_type,description,requires_approval)
select t.id,v.code,v.name,v.source_type,v.description,v.requires_approval
from public.tenants t
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
insert into public.payroll_pension_review_rules(tenant_id,country_code,review_age,label,message,effective_from)
select id,'GH',55,'Pension status review','Employee has reached age 55. Review pension/contributor status; do not automatically stop statutory deductions.',current_date
from public.tenants
on conflict (tenant_id,country_code,review_age,effective_from) do nothing;

comment on table public.payroll_worker_classifications is 'Effective-dated payroll classification. Employment relationship, tax treatment and pension status are intentionally separate.';
comment on column public.payroll_worker_classifications.pension_status is 'Controls pension treatment; age alone must never silently change deductions.';
comment on column public.payroll_worker_classifications.tier3_participation is 'Organization default, explicit participation, or explicit non-participation.';
comment on table public.payroll_earning_sources is 'Defines the origin of payroll values so one payroll engine can consume compensation, attendance, roster, commission, loans and manual inputs.';
