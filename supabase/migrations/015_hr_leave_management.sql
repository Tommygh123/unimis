-- ============================================================
-- UNIMIS MODULE 13
-- HR & LEAVE MANAGEMENT
-- 015_hr_leave_management.sql
-- Run AFTER Module 12
-- ============================================================

-- ============================================================
-- SECTION 13A — LEAVE TYPES
-- ============================================================

create table if not exists public.leave_types (
  id uuid primary key default gen_random_uuid(),

  institution_id uuid not null
    references public.institutions(id)
    on delete cascade,

  name text not null,
  code text not null,

  description text,

  default_days numeric(6,2)
    check (
      default_days is null
      or default_days >= 0
    ),

  is_paid boolean not null default true,

  requires_approval boolean not null default true,

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
-- SECTION 13B — STAFF LEAVE BALANCES
-- ============================================================

create table if not exists public.staff_leave_balances (
  id uuid primary key default gen_random_uuid(),

  institution_id uuid not null
    references public.institutions(id)
    on delete cascade,

  staff_id uuid not null
    references public.staff(id)
    on delete cascade,

  leave_type_id uuid not null
    references public.leave_types(id)
    on delete cascade,

  academic_year_id uuid
    references public.academic_years(id)
    on delete set null,

  opening_balance numeric(7,2) not null default 0,

  accrued_days numeric(7,2) not null default 0,

  used_days numeric(7,2) not null default 0,

  adjusted_days numeric(7,2) not null default 0,

  remaining_days numeric(7,2) generated always as (
    opening_balance
    + accrued_days
    + adjusted_days
    - used_days
  ) stored,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (
    staff_id,
    leave_type_id,
    academic_year_id
  )
);


-- ============================================================
-- SECTION 13C — LEAVE REQUESTS
-- ============================================================

create table if not exists public.leave_requests (
  id uuid primary key default gen_random_uuid(),

  institution_id uuid not null
    references public.institutions(id)
    on delete cascade,

  staff_id uuid not null
    references public.staff(id)
    on delete cascade,

  leave_type_id uuid not null
    references public.leave_types(id)
    on delete restrict,

  start_date date not null,
  end_date date not null,

  requested_days numeric(6,2) not null
    check (
      requested_days > 0
    ),

  reason text,

  status text not null default 'submitted'
    check (
      status in (
        'draft',
        'submitted',
        'approved',
        'rejected',
        'cancelled',
        'completed'
      )
    ),

  submitted_at timestamptz not null default now(),

  approved_by uuid
    references auth.users(id)
    on delete set null,

  approved_at timestamptz,

  rejection_reason text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  check (
    end_date >= start_date
  )
);


-- ============================================================
-- SECTION 13D — LEAVE APPROVAL HISTORY
-- ============================================================

create table if not exists public.leave_approval_history (
  id uuid primary key default gen_random_uuid(),

  institution_id uuid not null
    references public.institutions(id)
    on delete cascade,

  leave_request_id uuid not null
    references public.leave_requests(id)
    on delete cascade,

  old_status text,
  new_status text not null,

  action_by uuid
    references auth.users(id)
    on delete set null,

  action_at timestamptz not null default now(),

  notes text
);


-- ============================================================
-- SECTION 13E — STAFF EMERGENCY CONTACTS
-- ============================================================

create table if not exists public.staff_emergency_contacts (
  id uuid primary key default gen_random_uuid(),

  institution_id uuid not null
    references public.institutions(id)
    on delete cascade,

  staff_id uuid not null
    references public.staff(id)
    on delete cascade,

  full_name text not null,

  relationship text,

  phone text not null,

  alternate_phone text,

  email text,

  address text,

  is_primary boolean not null default false,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);


-- ============================================================
-- SECTION 13F — PERFORMANCE REVIEWS
-- ============================================================

create table if not exists public.staff_performance_reviews (
  id uuid primary key default gen_random_uuid(),

  institution_id uuid not null
    references public.institutions(id)
    on delete cascade,

  staff_id uuid not null
    references public.staff(id)
    on delete cascade,

  reviewer_user_id uuid
    references auth.users(id)
    on delete set null,

  review_period_start date not null,
  review_period_end date not null,

  score numeric(5,2)
    check (
      score is null
      or (
        score >= 0
        and score <= 100
      )
    ),

  strengths text,

  improvement_areas text,

  goals text,

  status text not null default 'draft'
    check (
      status in (
        'draft',
        'submitted',
        'acknowledged',
        'completed'
      )
    ),

  reviewed_at timestamptz,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  check (
    review_period_end >= review_period_start
  )
);


-- ============================================================
-- SECTION 13G — HR PERMISSIONS
-- ============================================================

insert into public.permissions (
  code,
  name,
  module,
  description
)
values
  (
    'hr.view',
    'View HR',
    'hr',
    'View HR records and staff administration data'
  ),
  (
    'hr.manage',
    'Manage HR',
    'hr',
    'Manage HR records and staff administration'
  ),
  (
    'leave.view',
    'View Leave',
    'hr',
    'View leave requests and balances'
  ),
  (
    'leave.manage',
    'Manage Leave',
    'hr',
    'Create and manage leave types, balances and approvals'
  ),
  (
    'performance.view',
    'View Performance Reviews',
    'hr',
    'View staff performance reviews'
  ),
  (
    'performance.manage',
    'Manage Performance Reviews',
    'hr',
    'Create and manage staff performance reviews'
  )
on conflict (code)
do update set
  name = excluded.name,
  module = excluded.module,
  description = excluded.description;


-- ============================================================
-- SECTION 13H — HR OFFICER ROLE
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
  'HR Officer',
  'hr_officer',
  'Human resource, leave and staff administration',
  false,
  true
from public.institutions i
where i.code = 'UNIMIS-DEMO-UNIV'
on conflict (institution_id, code)
do update set
  name = excluded.name,
  description = excluded.description,
  is_active = true,
  updated_at = now();


-- ============================================================
-- SECTION 13I — ROLE PERMISSIONS
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
    'hr.view',
    'hr.manage',
    'leave.view',
    'leave.manage',
    'performance.view',
    'performance.manage'
  )
where i.code = 'UNIMIS-DEMO-UNIV'
  and r.code in ('owner','admin')
on conflict do nothing;


-- HR Officer
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
    'hr.view',
    'hr.manage',
    'leave.view',
    'leave.manage',
    'performance.view',
    'performance.manage'
  )
where i.code = 'UNIMIS-DEMO-UNIV'
  and r.code = 'hr_officer'
on conflict do nothing;


-- Lecturer/Staff style read access through role where applicable
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
    'leave.view',
    'performance.view'
  )
where i.code = 'UNIMIS-DEMO-UNIV'
  and r.code = 'lecturer'
on conflict do nothing;


-- ============================================================
-- SECTION 13J — LEAVE STATUS HISTORY TRIGGER
-- ============================================================

create or replace function public.log_leave_status_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin

  if old.status is distinct from new.status then

    insert into public.leave_approval_history (
      institution_id,
      leave_request_id,
      old_status,
      new_status,
      action_by,
      action_at
    )
    values (
      new.institution_id,
      new.id,
      old.status,
      new.status,
      auth.uid(),
      now()
    );

  end if;

  return new;

end;
$$;


revoke all
on function public.log_leave_status_change()
from public;


drop trigger if exists
trg_leave_status_history
on public.leave_requests;


create trigger
trg_leave_status_history
after update of status
on public.leave_requests
for each row
execute function public.log_leave_status_change();


-- ============================================================
-- SECTION 13K — LEAVE BALANCE UPDATE AFTER APPROVAL
-- ============================================================

create or replace function public.apply_leave_balance()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  year_id uuid;
begin

  if new.status = 'approved'
     and old.status is distinct from new.status then

    select ay.id
    into year_id
    from public.academic_years ay
    where ay.institution_id = new.institution_id
      and ay.is_current = true
    limit 1;

    if year_id is not null then

      update public.staff_leave_balances

      set
        used_days =
          used_days
          +
          new.requested_days,

        updated_at =
          now()

      where staff_id =
        new.staff_id

        and leave_type_id =
        new.leave_type_id

        and academic_year_id =
        year_id;

    end if;

  end if;

  return new;

end;
$$;


revoke all
on function public.apply_leave_balance()
from public;


drop trigger if exists
trg_apply_leave_balance
on public.leave_requests;


create trigger
trg_apply_leave_balance
after update of status
on public.leave_requests
for each row
execute function public.apply_leave_balance();


-- ============================================================
-- SECTION 13L — INDEXES
-- ============================================================

create index if not exists idx_leave_types_institution
on public.leave_types(institution_id);

create index if not exists idx_staff_leave_balances_staff
on public.staff_leave_balances(staff_id);

create index if not exists idx_leave_requests_staff
on public.leave_requests(staff_id);

create index if not exists idx_leave_requests_status
on public.leave_requests(
  institution_id,
  status
);

create index if not exists idx_leave_history_request
on public.leave_approval_history(leave_request_id);

create index if not exists idx_staff_emergency_contacts_staff
on public.staff_emergency_contacts(staff_id);

create index if not exists idx_performance_reviews_staff
on public.staff_performance_reviews(staff_id);


-- ============================================================
-- SECTION 13M — UPDATED_AT TRIGGERS
-- ============================================================

do $$
declare
  t text;
begin

  foreach t in array array[
    'leave_types',
    'staff_leave_balances',
    'leave_requests',
    'staff_emergency_contacts',
    'staff_performance_reviews'
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
-- SECTION 13N — ENABLE RLS
-- ============================================================

alter table public.leave_types
enable row level security;

alter table public.staff_leave_balances
enable row level security;

alter table public.leave_requests
enable row level security;

alter table public.leave_approval_history
enable row level security;

alter table public.staff_emergency_contacts
enable row level security;

alter table public.staff_performance_reviews
enable row level security;


-- ============================================================
-- SECTION 13O — HR STAFF RLS
-- ============================================================

do $$
declare
  t text;
begin

  foreach t in array array[
    'leave_types',
    'staff_leave_balances',
    'leave_requests',
    'leave_approval_history',
    'staff_emergency_contacts',
    'staff_performance_reviews'
  ]

  loop

    execute format(
      'drop policy if exists
       "HR viewers can view %s"
       on public.%I',
      t, t
    );

    execute format(
      'create policy
       "HR viewers can view %s"
       on public.%I
       for select
       to authenticated
       using (
         public.has_permission(
           institution_id,
           ''hr.view''
         )
         or public.has_permission(
           institution_id,
           ''hr.manage''
         )
         or public.has_permission(
           institution_id,
           ''leave.view''
         )
         or public.has_permission(
           institution_id,
           ''leave.manage''
         )
         or public.has_permission(
           institution_id,
           ''performance.view''
         )
         or public.has_permission(
           institution_id,
           ''performance.manage''
         )
       )',
      t, t
    );

    execute format(
      'drop policy if exists
       "HR managers can manage %s"
       on public.%I',
      t, t
    );

    execute format(
      'create policy
       "HR managers can manage %s"
       on public.%I
       for all
       to authenticated
       using (
         public.has_permission(
           institution_id,
           ''hr.manage''
         )
         or public.has_permission(
           institution_id,
           ''leave.manage''
         )
         or public.has_permission(
           institution_id,
           ''performance.manage''
         )
       )
       with check (
         public.has_permission(
           institution_id,
           ''hr.manage''
         )
         or public.has_permission(
           institution_id,
           ''leave.manage''
         )
         or public.has_permission(
           institution_id,
           ''performance.manage''
         )
       )',
      t, t
    );

  end loop;

end $$;


-- ============================================================
-- SECTION 13P — STAFF SELF-SERVICE HR ACCESS
-- ============================================================

drop policy if exists
"Staff can view own leave balances"
on public.staff_leave_balances;

create policy
"Staff can view own leave balances"
on public.staff_leave_balances
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
"Staff can view own leave requests"
on public.leave_requests;

create policy
"Staff can view own leave requests"
on public.leave_requests
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
"Staff can view own emergency contacts"
on public.staff_emergency_contacts;

create policy
"Staff can view own emergency contacts"
on public.staff_emergency_contacts
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
"Staff can view own performance reviews"
on public.staff_performance_reviews;

create policy
"Staff can view own performance reviews"
on public.staff_performance_reviews
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


-- ============================================================
-- SECTION 13Q — LEAVE SUMMARY VIEW
-- ============================================================

create or replace view public.v_staff_leave_summary
with (security_invoker = true)
as
select

  slb.institution_id,

  slb.staff_id,

  s.staff_number,

  concat_ws(
    ' ',
    s.first_name,
    s.middle_name,
    s.last_name
  ) as staff_name,

  lt.name as leave_type,

  slb.opening_balance,

  slb.accrued_days,

  slb.used_days,

  slb.adjusted_days,

  slb.remaining_days

from public.staff_leave_balances slb

join public.staff s
  on s.id = slb.staff_id

join public.leave_types lt
  on lt.id = slb.leave_type_id;


-- ============================================================
-- SECTION 13R — VERIFY MODULE 13
-- ============================================================

select

  (
    select count(*)
    from public.leave_types
  )
  as leave_types,

  (
    select count(*)
    from public.staff_leave_balances
  )
  as leave_balances,

  (
    select count(*)
    from public.leave_requests
  )
  as leave_requests,

  (
    select count(*)
    from public.staff_performance_reviews
  )
  as performance_reviews;


-- ============================================================
-- END UNIMIS MODULE 13
-- HR & LEAVE MANAGEMENT
-- ============================================================
