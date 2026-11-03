-- ============================================================
-- UNIMIS MODULE 06
-- COURSE OFFERING & LECTURER ALLOCATION
-- 008_course_offerings_lecturer_allocation.sql
-- Run AFTER Module 05
-- ============================================================

-- ============================================================
-- SECTION 06A — COURSE OFFERINGS
-- A course offered in a specific academic year/period.
-- ============================================================

create table if not exists public.course_offerings (
  id uuid primary key default gen_random_uuid(),

  institution_id uuid not null
    references public.institutions(id)
    on delete cascade,

  course_id uuid not null
    references public.courses(id)
    on delete restrict,

  academic_year_id uuid not null
    references public.academic_years(id)
    on delete cascade,

  academic_period_id uuid not null
    references public.academic_periods(id)
    on delete cascade,

  department_id uuid
    references public.departments(id)
    on delete set null,

  programme_id uuid
    references public.programmes(id)
    on delete set null,

  level_number integer
    check (level_number is null or level_number > 0),

  section_code text not null default 'A',

  capacity integer
    check (capacity is null or capacity > 0),

  delivery_mode text not null default 'in_person'
    check (
      delivery_mode in (
        'in_person',
        'online',
        'hybrid',
        'other'
      )
    ),

  status text not null default 'planned'
    check (
      status in (
        'planned',
        'open',
        'closed',
        'cancelled',
        'completed'
      )
    ),

  registration_open boolean not null default true,

  notes text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (
    institution_id,
    course_id,
    academic_period_id,
    section_code
  )
);


-- ============================================================
-- SECTION 06B — LECTURER ALLOCATIONS
-- Supports one or more lecturers per course offering.
-- ============================================================

create table if not exists public.course_lecturers (
  id uuid primary key default gen_random_uuid(),

  institution_id uuid not null
    references public.institutions(id)
    on delete cascade,

  course_offering_id uuid not null
    references public.course_offerings(id)
    on delete cascade,

  lecturer_profile_id uuid not null
    references public.lecturer_profiles(id)
    on delete restrict,

  allocation_role text not null default 'lecturer'
    check (
      allocation_role in (
        'course_lead',
        'lecturer',
        'assistant',
        'tutor',
        'lab_instructor',
        'other'
      )
    ),

  workload_percentage numeric(5,2) not null default 100
    check (
      workload_percentage > 0
      and workload_percentage <= 100
    ),

  is_primary boolean not null default false,

  assigned_at timestamptz not null default now(),

  assigned_by uuid
    references auth.users(id)
    on delete set null,

  created_at timestamptz not null default now(),

  unique (
    course_offering_id,
    lecturer_profile_id
  )
);


-- ============================================================
-- SECTION 06C — COURSE OFFERING SCHEDULE
-- Basic timetable slots for the offering.
-- ============================================================

create table if not exists public.course_schedules (
  id uuid primary key default gen_random_uuid(),

  institution_id uuid not null
    references public.institutions(id)
    on delete cascade,

  course_offering_id uuid not null
    references public.course_offerings(id)
    on delete cascade,

  day_of_week integer not null
    check (day_of_week between 1 and 7),

  start_time time not null,
  end_time time not null,

  venue text,

  schedule_type text not null default 'lecture'
    check (
      schedule_type in (
        'lecture',
        'tutorial',
        'practical',
        'laboratory',
        'seminar',
        'online',
        'other'
      )
    ),

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  check (end_time > start_time)
);


-- ============================================================
-- SECTION 06D — OFFERING GROUPS / CLASSES
-- Useful for large classes, tutorials and lab groups.
-- ============================================================

create table if not exists public.course_groups (
  id uuid primary key default gen_random_uuid(),

  institution_id uuid not null
    references public.institutions(id)
    on delete cascade,

  course_offering_id uuid not null
    references public.course_offerings(id)
    on delete cascade,

  name text not null,
  code text not null,

  group_type text not null default 'class'
    check (
      group_type in (
        'class',
        'tutorial',
        'laboratory',
        'project',
        'other'
      )
    ),

  capacity integer
    check (capacity is null or capacity > 0),

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (course_offering_id, code)
);


-- ============================================================
-- SECTION 06E — PERMISSIONS
-- ============================================================

insert into public.permissions (
  code,
  name,
  module,
  description
)
values
  (
    'offerings.view',
    'View Course Offerings',
    'academics',
    'View course offerings and schedules'
  ),
  (
    'offerings.manage',
    'Manage Course Offerings',
    'academics',
    'Create and manage course offerings and schedules'
  ),
  (
    'lecturer_allocation.view',
    'View Lecturer Allocations',
    'academics',
    'View lecturer-course assignments'
  ),
  (
    'lecturer_allocation.manage',
    'Manage Lecturer Allocations',
    'academics',
    'Assign lecturers to course offerings'
  )
on conflict (code)
do update set
  name = excluded.name,
  module = excluded.module,
  description = excluded.description;


-- ============================================================
-- SECTION 06F — ROLE PERMISSION ASSIGNMENTS
-- ============================================================

-- Owner/Admin: full access
insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.institutions i
  on i.id = r.institution_id
join public.permissions p
  on p.code in (
    'offerings.view',
    'offerings.manage',
    'lecturer_allocation.view',
    'lecturer_allocation.manage'
  )
where i.code = 'UNIMIS-DEMO-UNIV'
  and r.code in ('owner','admin')
on conflict do nothing;

-- Registrar: manage academic offerings and lecturer allocations
insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.institutions i
  on i.id = r.institution_id
join public.permissions p
  on p.code in (
    'offerings.view',
    'offerings.manage',
    'lecturer_allocation.view',
    'lecturer_allocation.manage'
  )
where i.code = 'UNIMIS-DEMO-UNIV'
  and r.code = 'registrar'
on conflict do nothing;

-- Lecturer: read offerings and allocations
insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.institutions i
  on i.id = r.institution_id
join public.permissions p
  on p.code in (
    'offerings.view',
    'lecturer_allocation.view'
  )
where i.code = 'UNIMIS-DEMO-UNIV'
  and r.code = 'lecturer'
on conflict do nothing;

-- Student: can view offerings
insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.institutions i
  on i.id = r.institution_id
join public.permissions p
  on p.code = 'offerings.view'
where i.code = 'UNIMIS-DEMO-UNIV'
  and r.code = 'student'
on conflict do nothing;


-- ============================================================
-- SECTION 06G — INDEXES
-- ============================================================

create index if not exists idx_course_offerings_institution
on public.course_offerings(institution_id);

create index if not exists idx_course_offerings_course
on public.course_offerings(course_id);

create index if not exists idx_course_offerings_period
on public.course_offerings(academic_period_id);

create index if not exists idx_course_offerings_programme
on public.course_offerings(programme_id);

create index if not exists idx_course_lecturers_offering
on public.course_lecturers(course_offering_id);

create index if not exists idx_course_lecturers_lecturer
on public.course_lecturers(lecturer_profile_id);

create index if not exists idx_course_schedules_offering
on public.course_schedules(course_offering_id);

create index if not exists idx_course_groups_offering
on public.course_groups(course_offering_id);


-- ============================================================
-- SECTION 06H — UPDATED_AT TRIGGERS
-- ============================================================

do $$
declare
  t text;
begin
  foreach t in array array[
    'course_offerings',
    'course_schedules',
    'course_groups'
  ]
  loop
    execute format(
      'drop trigger if exists trg_%I_updated_at on public.%I',
      t, t
    );

    execute format(
      'create trigger trg_%I_updated_at
       before update on public.%I
       for each row
       execute function public.set_updated_at()',
      t, t
    );
  end loop;
end $$;


-- ============================================================
-- SECTION 06I — ENABLE RLS
-- ============================================================

alter table public.course_offerings
enable row level security;

alter table public.course_lecturers
enable row level security;

alter table public.course_schedules
enable row level security;

alter table public.course_groups
enable row level security;


-- ============================================================
-- SECTION 06J — COURSE OFFERING RLS
-- ============================================================

do $$
declare
  t text;
begin
  foreach t in array array[
    'course_offerings',
    'course_schedules',
    'course_groups'
  ]
  loop

    execute format(
      'drop policy if exists "Members can view %s" on public.%I',
      t, t
    );

    execute format(
      'create policy "Members can view %s"
       on public.%I
       for select
       to authenticated
       using (
         public.has_permission(institution_id,''offerings.view'')
         or public.has_permission(institution_id,''offerings.manage'')
       )',
      t, t
    );

    execute format(
      'drop policy if exists "Managers can manage %s" on public.%I',
      t, t
    );

    execute format(
      'create policy "Managers can manage %s"
       on public.%I
       for all
       to authenticated
       using (
         public.has_permission(institution_id,''offerings.manage'')
       )
       with check (
         public.has_permission(institution_id,''offerings.manage'')
       )',
      t, t
    );

  end loop;
end $$;


-- ============================================================
-- SECTION 06K — LECTURER ALLOCATION RLS
-- ============================================================

drop policy if exists
"Members can view lecturer allocations"
on public.course_lecturers;

create policy
"Members can view lecturer allocations"
on public.course_lecturers
for select
to authenticated
using (
  public.has_permission(
    institution_id,
    'lecturer_allocation.view'
  )
  or
  public.has_permission(
    institution_id,
    'lecturer_allocation.manage'
  )
);


drop policy if exists
"Managers can manage lecturer allocations"
on public.course_lecturers;

create policy
"Managers can manage lecturer allocations"
on public.course_lecturers
for all
to authenticated
using (
  public.has_permission(
    institution_id,
    'lecturer_allocation.manage'
  )
)
with check (
  public.has_permission(
    institution_id,
    'lecturer_allocation.manage'
  )
);


-- ============================================================
-- SECTION 06L — LECTURER SELF-SERVICE ACCESS
-- Lecturer can see allocations assigned to themselves.
-- ============================================================

drop policy if exists
"Lecturers can view own course allocations"
on public.course_lecturers;

create policy
"Lecturers can view own course allocations"
on public.course_lecturers
for select
to authenticated
using (
  exists (
    select 1
    from public.lecturer_profiles lp
    join public.staff s
      on s.id = lp.staff_id
    where lp.id = lecturer_profile_id
      and s.user_id = (select auth.uid())
  )
);


-- ============================================================
-- SECTION 06M — COURSE OFFERING VIEW
-- Convenient joined view for React dashboards/reports.
-- ============================================================

create or replace view public.v_course_offerings
with (security_invoker = true)
as
select
  co.id,
  co.institution_id,
  c.code as course_code,
  c.name as course_name,
  c.credit_hours,
  ay.name as academic_year,
  ap.name as academic_period,
  p.code as programme_code,
  p.name as programme_name,
  d.code as department_code,
  d.name as department_name,
  co.level_number,
  co.section_code,
  co.capacity,
  co.delivery_mode,
  co.status,
  co.registration_open
from public.course_offerings co
join public.courses c
  on c.id = co.course_id
join public.academic_years ay
  on ay.id = co.academic_year_id
join public.academic_periods ap
  on ap.id = co.academic_period_id
left join public.programmes p
  on p.id = co.programme_id
left join public.departments d
  on d.id = co.department_id;


-- ============================================================
-- SECTION 06N — VERIFICATION
-- ============================================================

select
  (select count(*) from public.course_offerings)
    as course_offerings,

  (select count(*) from public.course_lecturers)
    as lecturer_allocations,

  (select count(*) from public.course_schedules)
    as schedules,

  (select count(*) from public.course_groups)
    as course_groups;


-- ============================================================
-- END UNIMIS MODULE 06
-- COURSE OFFERING & LECTURER ALLOCATION
-- ============================================================
