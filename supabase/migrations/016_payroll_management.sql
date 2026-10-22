-- ============================================================
-- UNIMIS MODULE 14
-- PAYROLL MANAGEMENT
-- 016_payroll_management.sql
-- Run AFTER Module 13
-- ============================================================

-- ============================================================
-- SECTION 14A — PAYROLL SETTINGS
-- Table-driven so statutory rates can be changed without code.
-- ============================================================

create table if not exists public.payroll_settings (
  id uuid primary key default gen_random_uuid(),

  institution_id uuid not null
    references public.institutions(id)
    on delete cascade,

  currency_code text not null default 'GHS',

  pay_frequency text not null default 'monthly'
    check (
      pay_frequency in (
        'monthly',
        'biweekly',
        'weekly',
        'other'
      )
    ),

  default_working_days numeric(6,2) not null default 22
    check (default_working_days > 0),

  settings jsonb not null default '{}'::jsonb,

  is_active boolean not null default true,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (institution_id)
);


-- ============================================================
-- SECTION 14B — PAY COMPONENTS
-- Earnings and deductions.
-- ============================================================

create table if not exists public.pay_components (
  id uuid primary key default gen_random_uuid(),

  institution_id uuid not null
    references public.institutions(id)
    on delete cascade,

  name text not null,
  code text not null,

  component_type text not null
    check (
      component_type in (
        'earning',
        'deduction',
        'employer_contribution'
      )
    ),

  calculation_type text not null default 'fixed'
    check (
      calculation_type in (
        'fixed',
        'percentage',
        'formula',
        'manual'
      )
    ),

  percentage_basis text,

  is_taxable boolean not null default false,

  is_pensionable boolean not null default false,

  is_recurring boolean not null default true,

  priority integer not null default 100,

  status text not null default 'active'
    check (
      status in (
        'active',
        'inactive',
        'archived'
      )
    ),

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (
    institution_id,
    code
  )
);


-- ============================================================
-- SECTION 14C — STAFF PAYROLL PROFILES
-- ============================================================

create table if not exists public.staff_payroll_profiles (
  id uuid primary key default gen_random_uuid(),

  institution_id uuid not null
    references public.institutions(id)
    on delete cascade,

  staff_id uuid not null
    references public.staff(id)
    on delete cascade,

  basic_salary numeric(14,2) not null default 0
    check (basic_salary >= 0),

  salary_grade text,

  bank_name text,
  bank_branch text,
  bank_account_name text,
  bank_account_number text,

  pension_number text,
  tax_identification_number text,

  payroll_status text not null default 'active'
    check (
      payroll_status in (
        'active',
        'suspended',
        'inactive'
      )
    ),

  effective_from date not null default current_date,
  effective_to date,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (staff_id),

  check (
    effective_to is null
    or effective_to >= effective_from
  )
);


-- ============================================================
-- SECTION 14D — STAFF PAY COMPONENT ASSIGNMENTS
-- ============================================================

create table if not exists public.staff_pay_components (
  id uuid primary key default gen_random_uuid(),

  institution_id uuid not null
    references public.institutions(id)
    on delete cascade,

  staff_id uuid not null
    references public.staff(id)
    on delete cascade,

  pay_component_id uuid not null
    references public.pay_components(id)
    on delete cascade,

  amount numeric(14,2),

  percentage numeric(8,4),

  effective_from date not null default current_date,
  effective_to date,

  is_active boolean not null default true,

  notes text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (
    staff_id,
    pay_component_id,
    effective_from
  ),

  check (
    effective_to is null
    or effective_to >= effective_from
  )
);


-- ============================================================
-- SECTION 14E — STATUTORY RULE SETS
-- Avoids hard-coding PAYE/pension rules in application code.
-- ============================================================

create table if not exists public.payroll_rule_sets (
  id uuid primary key default gen_random_uuid(),

  institution_id uuid not null
    references public.institutions(id)
    on delete cascade,

  name text not null,
  code text not null,

  rule_type text not null
    check (
      rule_type in (
        'tax',
        'pension',
        'insurance',
        'levy',
        'other'
      )
    ),

  effective_from date not null,
  effective_to date,

  status text not null default 'active'
    check (
      status in (
        'draft',
        'active',
        'inactive',
        'archived'
      )
    ),

  settings jsonb not null default '{}'::jsonb,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (
    institution_id,
    code,
    effective_from
  ),

  check (
    effective_to is null
    or effective_to >= effective_from
  )
);


-- ============================================================
-- SECTION 14F — RULE BANDS
-- Supports progressive tax/pension bands.
-- ============================================================

create table if not exists public.payroll_rule_bands (
  id uuid primary key default gen_random_uuid(),

  institution_id uuid not null
    references public.institutions(id)
    on delete cascade,

  rule_set_id uuid not null
    references public.payroll_rule_sets(id)
    on delete cascade,

  band_order integer not null
    check (band_order > 0),

  lower_limit numeric(14,2) not null default 0
    check (lower_limit >= 0),

  upper_limit numeric(14,2),

  rate_percent numeric(8,4) not null default 0
    check (rate_percent >= 0),

  fixed_amount numeric(14,2) not null default 0
    check (fixed_amount >= 0),

  created_at timestamptz not null default now(),

  unique (
    rule_set_id,
    band_order
  ),

  check (
    upper_limit is null
    or upper_limit >= lower_limit
  )
);


-- ============================================================
-- SECTION 14G — PAYROLL PERIODS
-- ============================================================

create table if not exists public.payroll_periods (
  id uuid primary key default gen_random_uuid(),

  institution_id uuid not null
    references public.institutions(id)
    on delete cascade,

  name text not null,

  period_start date not null,
  period_end date not null,

  payment_date date,

  status text not null default 'draft'
    check (
      status in (
        'draft',
        'processing',
        'review',
        'approved',
        'paid',
        'closed',
        'cancelled'
      )
    ),

  created_by uuid
    references auth.users(id)
    on delete set null,

  approved_by uuid
    references auth.users(id)
    on delete set null,

  approved_at timestamptz,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (
    institution_id,
    period_start,
    period_end
  ),

  check (
    period_end >= period_start
  )
);


-- ============================================================
-- SECTION 14H — PAYROLL RUNS
-- ============================================================

create table if not exists public.payroll_runs (
  id uuid primary key default gen_random_uuid(),

  institution_id uuid not null
    references public.institutions(id)
    on delete cascade,

  payroll_period_id uuid not null
    references public.payroll_periods(id)
    on delete cascade,

  run_number text not null,

  run_type text not null default 'regular'
    check (
      run_type in (
        'regular',
        'supplementary',
        'adjustment',
        'final'
      )
    ),

  status text not null default 'draft'
    check (
      status in (
        'draft',
        'processing',
        'completed',
        'approved',
        'posted',
        'cancelled'
      )
    ),

  total_gross numeric(16,2) not null default 0,
  total_deductions numeric(16,2) not null default 0,
  total_net numeric(16,2) not null default 0,

  processed_by uuid
    references auth.users(id)
    on delete set null,

  processed_at timestamptz,

  approved_by uuid
    references auth.users(id)
    on delete set null,

  approved_at timestamptz,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (
    institution_id,
    run_number
  )
);


-- ============================================================
-- SECTION 14I — PAYSLIPS
-- ============================================================

create table if not exists public.payslips (
  id uuid primary key default gen_random_uuid(),

  institution_id uuid not null
    references public.institutions(id)
    on delete cascade,

  payroll_run_id uuid not null
    references public.payroll_runs(id)
    on delete cascade,

  staff_id uuid not null
    references public.staff(id)
    on delete cascade,

  basic_salary numeric(14,2) not null default 0,

  gross_pay numeric(14,2) not null default 0,

  total_deductions numeric(14,2) not null default 0,

  net_pay numeric(14,2) not null default 0,

  employer_contributions numeric(14,2) not null default 0,

  status text not null default 'draft'
    check (
      status in (
        'draft',
        'calculated',
        'approved',
        'paid',
        'cancelled'
      )
    ),

  payment_reference text,

  payslip_path text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (
    payroll_run_id,
    staff_id
  )
);


-- ============================================================
-- SECTION 14J — PAYSLIP LINES
-- ============================================================

create table if not exists public.payslip_lines (
  id uuid primary key default gen_random_uuid(),

  institution_id uuid not null
    references public.institutions(id)
    on delete cascade,

  payslip_id uuid not null
    references public.payslips(id)
    on delete cascade,

  pay_component_id uuid
    references public.pay_components(id)
    on delete set null,

  description text not null,

  line_type text not null
    check (
      line_type in (
        'earning',
        'deduction',
        'employer_contribution'
      )
    ),

  amount numeric(14,2) not null default 0,

  taxable_amount numeric(14,2) not null default 0,

  created_at timestamptz not null default now()
);


-- ============================================================
-- SECTION 14K — AUTOMATIC PAYROLL RUN NUMBER
-- Example: UDU-PR-2026-001001
-- ============================================================

create sequence if not exists
public.payroll_run_number_seq start 1001;


create or replace function
public.generate_payroll_run_number()

returns trigger

language plpgsql
security definer
set search_path = ''

as $$

declare
  inst_code text;
  yr text;
  seq_no bigint;

begin

  if new.run_number is null
     or btrim(new.run_number) = '' then

    select
      coalesce(
        nullif(i.short_name,''),
        i.code
      )
    into inst_code
    from public.institutions i
    where i.id = new.institution_id;


    if inst_code is null then
      raise exception 'Invalid institution';
    end if;


    yr :=
      to_char(
        current_date,
        'YYYY'
      );


    seq_no :=
      nextval(
        'public.payroll_run_number_seq'
      );


    new.run_number :=
      upper(
        regexp_replace(
          inst_code,
          '[^A-Za-z0-9]',
          '',
          'g'
        )
      )
      || '-PR-'
      || yr
      || '-'
      || lpad(
           seq_no::text,
           6,
           '0'
         );

  end if;


  return new;

end;

$$;


revoke all
on function public.generate_payroll_run_number()
from public;


drop trigger if exists
trg_generate_payroll_run_number
on public.payroll_runs;


create trigger
trg_generate_payroll_run_number

before insert
on public.payroll_runs

for each row

execute function
public.generate_payroll_run_number();


-- ============================================================
-- SECTION 14L — PAYROLL PERMISSIONS
-- ============================================================

insert into public.permissions (
  code,
  name,
  module,
  description
)
values
  (
    'payroll.view',
    'View Payroll',
    'payroll',
    'View payroll periods, runs and payslips'
  ),
  (
    'payroll.manage',
    'Manage Payroll',
    'payroll',
    'Manage payroll settings, components and staff payroll profiles'
  ),
  (
    'payroll.process',
    'Process Payroll',
    'payroll',
    'Process payroll runs and calculate payslips'
  ),
  (
    'payroll.approve',
    'Approve Payroll',
    'payroll',
    'Approve and post payroll runs'
  )
on conflict (code)
do update set
  name = excluded.name,
  module = excluded.module,
  description = excluded.description;


-- ============================================================
-- SECTION 14M — PAYROLL OFFICER ROLE
-- ============================================================

insert into public.roles (
  institution_id,
  name,
  code,
  description,
  is_system_role,
  is_active
)

select
  i.id,
  'Payroll Officer',
  'payroll_officer',
  'Payroll setup, processing and payslip administration',
  false,
  true

from public.institutions i

where i.code = 'UNIMIS-DEMO-UNIV'

on conflict (
  institution_id,
  code
)

do update set
  name = excluded.name,
  description = excluded.description,
  is_active = true,
  updated_at = now();


-- ============================================================
-- SECTION 14N — ROLE PERMISSION ASSIGNMENTS
-- ============================================================

-- Owner/Admin
insert into public.role_permissions (
  role_id,
  permission_id
)
select
  r.id,
  p.id
from public.roles r
join public.institutions i
  on i.id = r.institution_id
join public.permissions p
  on p.code in (
    'payroll.view',
    'payroll.manage',
    'payroll.process',
    'payroll.approve'
  )
where i.code = 'UNIMIS-DEMO-UNIV'
  and r.code in ('owner','admin')
on conflict do nothing;


-- Payroll Officer
insert into public.role_permissions (
  role_id,
  permission_id
)
select
  r.id,
  p.id
from public.roles r
join public.institutions i
  on i.id = r.institution_id
join public.permissions p
  on p.code in (
    'payroll.view',
    'payroll.manage',
    'payroll.process'
  )
where i.code = 'UNIMIS-DEMO-UNIV'
  and r.code = 'payroll_officer'
on conflict do nothing;


-- HR Officer gets payroll read access
insert into public.role_permissions (
  role_id,
  permission_id
)
select
  r.id,
  p.id
from public.roles r
join public.institutions i
  on i.id = r.institution_id
join public.permissions p
  on p.code = 'payroll.view'
where i.code = 'UNIMIS-DEMO-UNIV'
  and r.code = 'hr_officer'
on conflict do nothing;


-- ============================================================
-- SECTION 14O — INDEXES
-- ============================================================

create index if not exists idx_pay_components_institution
on public.pay_components(institution_id);

create index if not exists idx_staff_payroll_profiles_staff
on public.staff_payroll_profiles(staff_id);

create index if not exists idx_staff_pay_components_staff
on public.staff_pay_components(staff_id);

create index if not exists idx_payroll_rule_sets_institution
on public.payroll_rule_sets(institution_id);

create index if not exists idx_payroll_rule_bands_rule_set
on public.payroll_rule_bands(rule_set_id);

create index if not exists idx_payroll_periods_institution
on public.payroll_periods(institution_id);

create index if not exists idx_payroll_runs_period
on public.payroll_runs(payroll_period_id);

create index if not exists idx_payslips_run
on public.payslips(payroll_run_id);

create index if not exists idx_payslips_staff
on public.payslips(staff_id);

create index if not exists idx_payslip_lines_payslip
on public.payslip_lines(payslip_id);


-- ============================================================
-- SECTION 14P — UPDATED_AT TRIGGERS
-- ============================================================

do $$
declare
  t text;
begin

  foreach t in array array[
    'payroll_settings',
    'pay_components',
    'staff_payroll_profiles',
    'staff_pay_components',
    'payroll_rule_sets',
    'payroll_periods',
    'payroll_runs',
    'payslips'
  ]

  loop

    execute format(
      'drop trigger if exists trg_%I_updated_at on public.%I',
      t,
      t
    );

    execute format(
      'create trigger trg_%I_updated_at
       before update on public.%I
       for each row
       execute function public.set_updated_at()',
      t,
      t
    );

  end loop;

end $$;


-- ============================================================
-- SECTION 14Q — ENABLE RLS
-- ============================================================

alter table public.payroll_settings
enable row level security;

alter table public.pay_components
enable row level security;

alter table public.staff_payroll_profiles
enable row level security;

alter table public.staff_pay_components
enable row level security;

alter table public.payroll_rule_sets
enable row level security;

alter table public.payroll_rule_bands
enable row level security;

alter table public.payroll_periods
enable row level security;

alter table public.payroll_runs
enable row level security;

alter table public.payslips
enable row level security;

alter table public.payslip_lines
enable row level security;


-- ============================================================
-- SECTION 14R — PAYROLL STAFF RLS
-- ============================================================

do $$
declare
  t text;
begin

  foreach t in array array[
    'payroll_settings',
    'pay_components',
    'staff_payroll_profiles',
    'staff_pay_components',
    'payroll_rule_sets',
    'payroll_rule_bands',
    'payroll_periods',
    'payroll_runs',
    'payslips',
    'payslip_lines'
  ]

  loop

    execute format(
      'drop policy if exists
       "Payroll viewers can view %s"
       on public.%I',
      t, t
    );

    execute format(
      'create policy
       "Payroll viewers can view %s"
       on public.%I
       for select
       to authenticated
       using (
         public.has_permission(
           institution_id,
           ''payroll.view''
         )
         or public.has_permission(
           institution_id,
           ''payroll.manage''
         )
         or public.has_permission(
           institution_id,
           ''payroll.process''
         )
         or public.has_permission(
           institution_id,
           ''payroll.approve''
         )
       )',
      t, t
    );

    execute format(
      'drop policy if exists
       "Payroll managers can manage %s"
       on public.%I',
      t, t
    );

    execute format(
      'create policy
       "Payroll managers can manage %s"
       on public.%I
       for all
       to authenticated
       using (
         public.has_permission(
           institution_id,
           ''payroll.manage''
         )
         or public.has_permission(
           institution_id,
           ''payroll.process''
         )
         or public.has_permission(
           institution_id,
           ''payroll.approve''
         )
       )
       with check (
         public.has_permission(
           institution_id,
           ''payroll.manage''
         )
         or public.has_permission(
           institution_id,
           ''payroll.process''
         )
         or public.has_permission(
           institution_id,
           ''payroll.approve''
         )
       )',
      t, t
    );

  end loop;

end $$;


-- ============================================================
-- SECTION 14S — STAFF SELF-SERVICE PAYSLIPS
-- ============================================================

drop policy if exists
"Staff can view own payroll profile"
on public.staff_payroll_profiles;

create policy
"Staff can view own payroll profile"
on public.staff_payroll_profiles
for select
to authenticated
using (
  exists (
    select 1
    from public.staff s
    where s.id = staff_id
      and s.user_id = (select auth.uid())
  )
);


drop policy if exists
"Staff can view own payslips"
on public.payslips;

create policy
"Staff can view own payslips"
on public.payslips
for select
to authenticated
using (
  status in ('approved','paid')
  and exists (
    select 1
    from public.staff s
    where s.id = staff_id
      and s.user_id = (select auth.uid())
  )
);


drop policy if exists
"Staff can view own payslip lines"
on public.payslip_lines;

create policy
"Staff can view own payslip lines"
on public.payslip_lines
for select
to authenticated
using (
  exists (
    select 1
    from public.payslips ps
    join public.staff s
      on s.id = ps.staff_id
    where ps.id = payslip_id
      and ps.status in ('approved','paid')
      and s.user_id = (select auth.uid())
  )
);


-- ============================================================
-- SECTION 14T — PAYROLL SUMMARY VIEW
-- ============================================================

create or replace view
public.v_payroll_summary

with (
  security_invoker = true
)

as

select

  pr.id as payroll_run_id,

  pr.institution_id,

  pp.name as payroll_period,

  pr.run_number,

  pr.run_type,

  pr.status,

  count(ps.id) as staff_count,

  coalesce(
    sum(ps.gross_pay),
    0
  ) as gross_pay,

  coalesce(
    sum(ps.total_deductions),
    0
  ) as total_deductions,

  coalesce(
    sum(ps.net_pay),
    0
  ) as net_pay

from public.payroll_runs pr

join public.payroll_periods pp
  on pp.id = pr.payroll_period_id

left join public.payslips ps
  on ps.payroll_run_id = pr.id

group by
  pr.id,
  pr.institution_id,
  pp.name,
  pr.run_number,
  pr.run_type,
  pr.status;


-- ============================================================
-- SECTION 14U — VERIFY MODULE 14
-- ============================================================

select

  (
    select count(*)
    from public.pay_components
  )
  as pay_components,

  (
    select count(*)
    from public.staff_payroll_profiles
  )
  as payroll_profiles,

  (
    select count(*)
    from public.payroll_periods
  )
  as payroll_periods,

  (
    select count(*)
    from public.payroll_runs
  )
  as payroll_runs,

  (
    select count(*)
    from public.payslips
  )
  as payslips;


-- ============================================================
-- END UNIMIS MODULE 14
-- PAYROLL MANAGEMENT
-- ============================================================
