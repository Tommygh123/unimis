-- ============================================================
-- UNIMIS MODULE 12
-- HOSTEL / ACCOMMODATION MANAGEMENT
-- 014_hostel_accommodation.sql
-- Run AFTER Module 11
-- ============================================================

-- ============================================================
-- SECTION 12A — ACCOMMODATION FACILITIES
-- Works for University hostels and SHS/JHS boarding houses.
-- ============================================================

create table if not exists public.accommodation_facilities (
  id uuid primary key default gen_random_uuid(),

  institution_id uuid not null
    references public.institutions(id)
    on delete cascade,

  name text not null,
  code text not null,

  facility_type text not null default 'hostel'
    check (
      facility_type in (
        'hostel',
        'hall',
        'boarding_house',
        'staff_quarters',
        'other'
      )
    ),

  gender_policy text not null default 'mixed'
    check (
      gender_policy in (
        'male',
        'female',
        'mixed',
        'other'
      )
    ),

  location text,
  description text,

  total_capacity integer
    check (
      total_capacity is null
      or total_capacity >= 0
    ),

  status text not null default 'active'
    check (
      status in (
        'active',
        'inactive',
        'maintenance',
        'closed'
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
-- SECTION 12B — BLOCKS / WINGS
-- ============================================================

create table if not exists public.accommodation_blocks (
  id uuid primary key default gen_random_uuid(),

  institution_id uuid not null
    references public.institutions(id)
    on delete cascade,

  facility_id uuid not null
    references public.accommodation_facilities(id)
    on delete cascade,

  name text not null,
  code text not null,

  floor_count integer
    check (
      floor_count is null
      or floor_count > 0
    ),

  description text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (
    facility_id,
    code
  )
);


-- ============================================================
-- SECTION 12C — ROOMS
-- ============================================================

create table if not exists public.accommodation_rooms (
  id uuid primary key default gen_random_uuid(),

  institution_id uuid not null
    references public.institutions(id)
    on delete cascade,

  facility_id uuid not null
    references public.accommodation_facilities(id)
    on delete cascade,

  block_id uuid
    references public.accommodation_blocks(id)
    on delete set null,

  room_number text not null,

  floor_number integer,

  room_type text not null default 'shared'
    check (
      room_type in (
        'single',
        'double',
        'shared',
        'dormitory',
        'suite',
        'other'
      )
    ),

  capacity integer not null default 1
    check (
      capacity > 0
    ),

  status text not null default 'available'
    check (
      status in (
        'available',
        'full',
        'maintenance',
        'closed'
      )
    ),

  notes text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (
    facility_id,
    room_number
  )
);


-- ============================================================
-- SECTION 12D — BEDS / SPACES
-- ============================================================

create table if not exists public.accommodation_beds (
  id uuid primary key default gen_random_uuid(),

  institution_id uuid not null
    references public.institutions(id)
    on delete cascade,

  room_id uuid not null
    references public.accommodation_rooms(id)
    on delete cascade,

  bed_code text not null,

  status text not null default 'available'
    check (
      status in (
        'available',
        'occupied',
        'reserved',
        'maintenance',
        'inactive'
      )
    ),

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (
    room_id,
    bed_code
  )
);


-- ============================================================
-- SECTION 12E — ACCOMMODATION APPLICATIONS
-- ============================================================

create table if not exists public.accommodation_applications (
  id uuid primary key default gen_random_uuid(),

  institution_id uuid not null
    references public.institutions(id)
    on delete cascade,

  student_id uuid not null
    references public.students(id)
    on delete cascade,

  academic_year_id uuid not null
    references public.academic_years(id)
    on delete cascade,

  academic_period_id uuid
    references public.academic_periods(id)
    on delete set null,

  preferred_facility_id uuid
    references public.accommodation_facilities(id)
    on delete set null,

  application_date timestamptz not null default now(),

  status text not null default 'submitted'
    check (
      status in (
        'draft',
        'submitted',
        'approved',
        'rejected',
        'waitlisted',
        'cancelled'
      )
    ),

  special_requirements text,

  reviewed_by uuid
    references auth.users(id)
    on delete set null,

  reviewed_at timestamptz,

  notes text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (
    student_id,
    academic_year_id,
    academic_period_id
  )
);


-- ============================================================
-- SECTION 12F — ACCOMMODATION ALLOCATIONS
-- ============================================================

create table if not exists public.accommodation_allocations (
  id uuid primary key default gen_random_uuid(),

  institution_id uuid not null
    references public.institutions(id)
    on delete cascade,

  application_id uuid
    references public.accommodation_applications(id)
    on delete set null,

  student_id uuid not null
    references public.students(id)
    on delete cascade,

  academic_year_id uuid not null
    references public.academic_years(id)
    on delete cascade,

  academic_period_id uuid
    references public.academic_periods(id)
    on delete set null,

  facility_id uuid not null
    references public.accommodation_facilities(id)
    on delete restrict,

  room_id uuid not null
    references public.accommodation_rooms(id)
    on delete restrict,

  bed_id uuid
    references public.accommodation_beds(id)
    on delete restrict,

  allocation_status text not null default 'allocated'
    check (
      allocation_status in (
        'allocated',
        'checked_in',
        'checked_out',
        'cancelled',
        'transferred'
      )
    ),

  allocated_at timestamptz not null default now(),

  check_in_at timestamptz,
  check_out_at timestamptz,

  allocated_by uuid
    references auth.users(id)
    on delete set null,

  notes text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);


create unique index if not exists
uq_active_student_accommodation

on public.accommodation_allocations (
  student_id,
  academic_year_id,
  academic_period_id
)

where allocation_status in (
  'allocated',
  'checked_in'
);


create unique index if not exists
uq_active_bed_allocation

on public.accommodation_allocations (
  bed_id,
  academic_year_id,
  academic_period_id
)

where bed_id is not null
and allocation_status in (
  'allocated',
  'checked_in'
);


-- ============================================================
-- SECTION 12G — ACCOMMODATION CHARGES
-- Can later generate finance invoices.
-- ============================================================

create table if not exists public.accommodation_charges (
  id uuid primary key default gen_random_uuid(),

  institution_id uuid not null
    references public.institutions(id)
    on delete cascade,

  facility_id uuid not null
    references public.accommodation_facilities(id)
    on delete cascade,

  academic_year_id uuid not null
    references public.academic_years(id)
    on delete cascade,

  academic_period_id uuid
    references public.academic_periods(id)
    on delete set null,

  room_type text,

  amount numeric(12,2) not null
    check (
      amount >= 0
    ),

  currency_code text not null default 'GHS',

  status text not null default 'active'
    check (
      status in (
        'active',
        'inactive',
        'archived'
      )
    ),

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);


-- ============================================================
-- SECTION 12H — HOSTEL INCIDENTS / DISCIPLINE LOG
-- ============================================================

create table if not exists public.accommodation_incidents (
  id uuid primary key default gen_random_uuid(),

  institution_id uuid not null
    references public.institutions(id)
    on delete cascade,

  allocation_id uuid
    references public.accommodation_allocations(id)
    on delete set null,

  student_id uuid not null
    references public.students(id)
    on delete cascade,

  incident_date timestamptz not null default now(),

  incident_type text not null,

  description text not null,

  action_taken text,

  status text not null default 'open'
    check (
      status in (
        'open',
        'under_review',
        'resolved',
        'closed'
      )
    ),

  reported_by uuid
    references auth.users(id)
    on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);


-- ============================================================
-- SECTION 12I — ACCOMMODATION PERMISSIONS
-- ============================================================

insert into public.permissions (
  code,
  name,
  module,
  description
)
values
  (
    'accommodation.view',
    'View Accommodation',
    'accommodation',
    'View accommodation facilities, rooms and allocations'
  ),
  (
    'accommodation.manage',
    'Manage Accommodation',
    'accommodation',
    'Manage facilities, rooms, beds and allocations'
  ),
  (
    'accommodation.applications',
    'Manage Accommodation Applications',
    'accommodation',
    'Review and process accommodation applications'
  ),
  (
    'accommodation.incidents',
    'Manage Accommodation Incidents',
    'accommodation',
    'Record and manage hostel or boarding incidents'
  )
on conflict (code)
do update set
  name = excluded.name,
  module = excluded.module,
  description = excluded.description;


-- ============================================================
-- SECTION 12J — HOSTEL / ACCOMMODATION OFFICER ROLE
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
  'Accommodation Officer',
  'accommodation_officer',
  'Manages hostels, boarding facilities and student accommodation',
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
-- SECTION 12K — ROLE PERMISSION ASSIGNMENTS
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
    'accommodation.view',
    'accommodation.manage',
    'accommodation.applications',
    'accommodation.incidents'
  )
where i.code = 'UNIMIS-DEMO-UNIV'
  and r.code in ('owner','admin')
on conflict do nothing;


-- Accommodation Officer
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
    'accommodation.view',
    'accommodation.manage',
    'accommodation.applications',
    'accommodation.incidents'
  )
where i.code = 'UNIMIS-DEMO-UNIV'
  and r.code = 'accommodation_officer'
on conflict do nothing;


-- Student read permission
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
  on p.code = 'accommodation.view'
where i.code = 'UNIMIS-DEMO-UNIV'
  and r.code = 'student'
on conflict do nothing;


-- ============================================================
-- SECTION 12L — INDEXES
-- ============================================================

create index if not exists idx_accommodation_facilities_institution
on public.accommodation_facilities(institution_id);

create index if not exists idx_accommodation_blocks_facility
on public.accommodation_blocks(facility_id);

create index if not exists idx_accommodation_rooms_facility
on public.accommodation_rooms(facility_id);

create index if not exists idx_accommodation_rooms_status
on public.accommodation_rooms(institution_id, status);

create index if not exists idx_accommodation_beds_room
on public.accommodation_beds(room_id);

create index if not exists idx_accommodation_beds_status
on public.accommodation_beds(institution_id, status);

create index if not exists idx_accommodation_apps_student
on public.accommodation_applications(student_id);

create index if not exists idx_accommodation_apps_status
on public.accommodation_applications(institution_id, status);

create index if not exists idx_accommodation_alloc_student
on public.accommodation_allocations(student_id);

create index if not exists idx_accommodation_alloc_room
on public.accommodation_allocations(room_id);

create index if not exists idx_accommodation_alloc_bed
on public.accommodation_allocations(bed_id);

create index if not exists idx_accommodation_incidents_student
on public.accommodation_incidents(student_id);


-- ============================================================
-- SECTION 12M — UPDATED_AT TRIGGERS
-- ============================================================

do $$
declare
  t text;
begin

  foreach t in array array[
    'accommodation_facilities',
    'accommodation_blocks',
    'accommodation_rooms',
    'accommodation_beds',
    'accommodation_applications',
    'accommodation_allocations',
    'accommodation_charges',
    'accommodation_incidents'
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
-- SECTION 12N — ENABLE RLS
-- ============================================================

alter table public.accommodation_facilities
enable row level security;

alter table public.accommodation_blocks
enable row level security;

alter table public.accommodation_rooms
enable row level security;

alter table public.accommodation_beds
enable row level security;

alter table public.accommodation_applications
enable row level security;

alter table public.accommodation_allocations
enable row level security;

alter table public.accommodation_charges
enable row level security;

alter table public.accommodation_incidents
enable row level security;


-- ============================================================
-- SECTION 12O — ACCOMMODATION STAFF RLS
-- ============================================================

do $$
declare
  t text;
begin

  foreach t in array array[
    'accommodation_facilities',
    'accommodation_blocks',
    'accommodation_rooms',
    'accommodation_beds',
    'accommodation_applications',
    'accommodation_allocations',
    'accommodation_charges',
    'accommodation_incidents'
  ]

  loop

    execute format(
      'drop policy if exists
       "Accommodation viewers can view %s"
       on public.%I',
      t, t
    );

    execute format(
      'create policy
       "Accommodation viewers can view %s"
       on public.%I
       for select
       to authenticated
       using (
         public.has_permission(
           institution_id,
           ''accommodation.view''
         )
         or public.has_permission(
           institution_id,
           ''accommodation.manage''
         )
         or public.has_permission(
           institution_id,
           ''accommodation.applications''
         )
         or public.has_permission(
           institution_id,
           ''accommodation.incidents''
         )
       )',
      t, t
    );

    execute format(
      'drop policy if exists
       "Accommodation managers can manage %s"
       on public.%I',
      t, t
    );

    execute format(
      'create policy
       "Accommodation managers can manage %s"
       on public.%I
       for all
       to authenticated
       using (
         public.has_permission(
           institution_id,
           ''accommodation.manage''
         )
         or public.has_permission(
           institution_id,
           ''accommodation.applications''
         )
         or public.has_permission(
           institution_id,
           ''accommodation.incidents''
         )
       )
       with check (
         public.has_permission(
           institution_id,
           ''accommodation.manage''
         )
         or public.has_permission(
           institution_id,
           ''accommodation.applications''
         )
         or public.has_permission(
           institution_id,
           ''accommodation.incidents''
         )
       )',
      t, t
    );

  end loop;

end $$;


-- ============================================================
-- SECTION 12P — STUDENT SELF-SERVICE ACCOMMODATION
-- ============================================================

drop policy if exists
"Students can view own accommodation applications"
on public.accommodation_applications;

create policy
"Students can view own accommodation applications"
on public.accommodation_applications
for select
to authenticated
using (
  exists (
    select 1
    from public.students s
    where s.id = student_id
      and s.user_id = (select auth.uid())
  )
);


drop policy if exists
"Students can view own accommodation allocations"
on public.accommodation_allocations;

create policy
"Students can view own accommodation allocations"
on public.accommodation_allocations
for select
to authenticated
using (
  exists (
    select 1
    from public.students s
    where s.id = student_id
      and s.user_id = (select auth.uid())
  )
);


drop policy if exists
"Students can view own accommodation incidents"
on public.accommodation_incidents;

create policy
"Students can view own accommodation incidents"
on public.accommodation_incidents
for select
to authenticated
using (
  exists (
    select 1
    from public.students s
    where s.id = student_id
      and s.user_id = (select auth.uid())
  )
);


-- ============================================================
-- SECTION 12Q — ROOM OCCUPANCY VIEW
-- ============================================================

create or replace view
public.v_accommodation_room_occupancy

with (
  security_invoker = true
)

as

select
  ar.id as room_id,
  ar.institution_id,
  af.name as facility_name,
  ab.name as block_name,
  ar.room_number,
  ar.room_type,
  ar.capacity,

  count(aa.id) filter (
    where aa.allocation_status in (
      'allocated',
      'checked_in'
    )
  ) as occupied_spaces,

  greatest(
    ar.capacity
    -
    count(aa.id) filter (
      where aa.allocation_status in (
        'allocated',
        'checked_in'
      )
    ),
    0
  ) as available_spaces,

  ar.status

from public.accommodation_rooms ar

join public.accommodation_facilities af
  on af.id = ar.facility_id

left join public.accommodation_blocks ab
  on ab.id = ar.block_id

left join public.accommodation_allocations aa
  on aa.room_id = ar.id

group by
  ar.id,
  ar.institution_id,
  af.name,
  ab.name,
  ar.room_number,
  ar.room_type,
  ar.capacity,
  ar.status;


-- ============================================================
-- SECTION 12R — VERIFY MODULE 12
-- ============================================================

select

  (
    select count(*)
    from public.accommodation_facilities
  )
  as facilities,

  (
    select count(*)
    from public.accommodation_rooms
  )
  as rooms,

  (
    select count(*)
    from public.accommodation_beds
  )
  as beds,

  (
    select count(*)
    from public.accommodation_applications
  )
  as applications,

  (
    select count(*)
    from public.accommodation_allocations
  )
  as allocations;


-- ============================================================
-- END UNIMIS MODULE 12
-- HOSTEL / ACCOMMODATION MANAGEMENT
-- ============================================================
