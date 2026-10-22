-- ============================================================
-- UNIMIS MODULE 05
-- STAFF & LECTURER MANAGEMENT
-- 007_staff_lecturer_management.sql
-- Run AFTER Module 04
-- ============================================================

-- ============================================================
-- SECTION 05A — STAFF MASTER RECORD
-- ============================================================
create table if not exists public.staff (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  user_id uuid references auth.users(id) on delete set null,
  department_id uuid references public.departments(id) on delete set null,

  staff_number text not null,
  first_name text not null,
  middle_name text,
  last_name text not null,
  date_of_birth date,
  gender text check (gender in ('male','female','other','prefer_not_to_say')),

  email text,
  phone text,
  alternate_phone text,
  nationality text default 'Ghanaian',
  address text,
  city text,
  region text,

  staff_category text not null default 'non_academic'
    check (staff_category in ('academic','non_academic','management','support','contract','other')),

  job_title text,
  employment_status text not null default 'active'
    check (employment_status in ('active','probation','leave','suspended','terminated','retired','resigned','inactive')),

  hire_date date,
  exit_date date,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (institution_id, staff_number),
  unique (institution_id, user_id)
);

-- ============================================================
-- SECTION 05B — EMPLOYMENT / APPOINTMENT HISTORY
-- ============================================================
create table if not exists public.staff_appointments (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  staff_id uuid not null references public.staff(id) on delete cascade,
  department_id uuid references public.departments(id) on delete set null,

  appointment_type text not null default 'permanent'
    check (appointment_type in ('permanent','temporary','contract','part_time','visiting','internship','other')),

  position_title text not null,
  grade text,
  rank text,

  start_date date not null,
  end_date date,
  is_current boolean not null default true,

  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  check (end_date is null or end_date >= start_date)
);

create unique index if not exists uq_current_staff_appointment
on public.staff_appointments(staff_id)
where is_current = true;

-- ============================================================
-- SECTION 05C — ACADEMIC / LECTURER PROFILE
-- ============================================================
create table if not exists public.lecturer_profiles (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  staff_id uuid not null references public.staff(id) on delete cascade,

  academic_rank text,
  specialization text,
  research_interests text,
  office_location text,
  consultation_hours text,
  bio text,

  is_active boolean not null default true,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (staff_id)
);

-- ============================================================
-- SECTION 05D — STAFF QUALIFICATIONS
-- ============================================================
create table if not exists public.staff_qualifications (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  staff_id uuid not null references public.staff(id) on delete cascade,

  qualification_type text not null,
  field_of_study text,
  institution_name text,
  country text,
  start_year integer,
  completion_year integer,
  certificate_number text,
  is_highest boolean not null default false,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  check (
    completion_year is null
    or start_year is null
    or completion_year >= start_year
  )
);

-- ============================================================
-- SECTION 05E — STAFF DOCUMENTS
-- ============================================================
create table if not exists public.staff_documents (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  staff_id uuid not null references public.staff(id) on delete cascade,

  document_type text not null,
  file_name text not null,
  storage_path text not null,
  mime_type text,
  file_size_bytes bigint check (file_size_bytes is null or file_size_bytes >= 0),

  created_at timestamptz not null default now()
);

-- ============================================================
-- SECTION 05F — STAFF STATUS HISTORY
-- ============================================================
create table if not exists public.staff_status_history (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  staff_id uuid not null references public.staff(id) on delete cascade,

  old_status text,
  new_status text not null,
  reason text,
  effective_date date not null default current_date,
  changed_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now()
);

-- ============================================================
-- SECTION 05G — STAFF NUMBER GENERATOR
-- Example: UDU-STF-2026-001001
-- ============================================================
create sequence if not exists public.staff_number_seq start 1001;

create or replace function public.generate_staff_number()
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
  if new.staff_number is null or btrim(new.staff_number) = '' then
    select coalesce(nullif(i.short_name,''), i.code)
      into inst_code
    from public.institutions i
    where i.id = new.institution_id;

    if inst_code is null then
      raise exception 'Invalid institution';
    end if;

    yr := coalesce(
      extract(year from new.hire_date)::integer::text,
      to_char(current_date,'YYYY')
    );

    seq_no := nextval('public.staff_number_seq');

    new.staff_number :=
      upper(regexp_replace(inst_code,'[^A-Za-z0-9]','','g'))
      || '-STF-' || yr || '-' || lpad(seq_no::text,6,'0');
  end if;

  return new;
end;
$$;

revoke all on function public.generate_staff_number() from public;

drop trigger if exists trg_generate_staff_number on public.staff;
create trigger trg_generate_staff_number
before insert on public.staff
for each row execute function public.generate_staff_number();

-- ============================================================
-- SECTION 05H — AUTOMATIC STAFF STATUS HISTORY
-- ============================================================
create or replace function public.log_staff_status_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.employment_status is distinct from new.employment_status then
    insert into public.staff_status_history (
      institution_id, staff_id, old_status, new_status,
      effective_date, changed_by
    )
    values (
      new.institution_id, new.id, old.employment_status,
      new.employment_status, current_date, auth.uid()
    );
  end if;

  return new;
end;
$$;

revoke all on function public.log_staff_status_change() from public;

drop trigger if exists trg_staff_status_history on public.staff;
create trigger trg_staff_status_history
after update of employment_status on public.staff
for each row execute function public.log_staff_status_change();

-- ============================================================
-- SECTION 05I — PERMISSIONS
-- ============================================================
insert into public.permissions (code, name, module, description)
values
  ('staff.view', 'View Staff', 'staff', 'View staff records'),
  ('staff.manage', 'Manage Staff', 'staff', 'Create and manage staff records'),
  ('lecturers.view', 'View Lecturers', 'staff', 'View lecturer profiles'),
  ('lecturers.manage', 'Manage Lecturers', 'staff', 'Manage lecturer profiles and academic staff data')
on conflict (code)
do update set
  name = excluded.name,
  module = excluded.module,
  description = excluded.description;

-- Owner/Admin receive staff management.
insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.institutions i on i.id = r.institution_id
join public.permissions p
  on p.code in ('staff.view','staff.manage','lecturers.view','lecturers.manage')
where i.code = 'UNIMIS-DEMO-UNIV'
  and r.code in ('owner','admin')
on conflict do nothing;

-- Registrar gets staff/lecturer read access.
insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.institutions i on i.id = r.institution_id
join public.permissions p
  on p.code in ('staff.view','lecturers.view')
where i.code = 'UNIMIS-DEMO-UNIV'
  and r.code = 'registrar'
on conflict do nothing;

-- Lecturer role gets lecturer read access.
insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.institutions i on i.id = r.institution_id
join public.permissions p on p.code = 'lecturers.view'
where i.code = 'UNIMIS-DEMO-UNIV'
  and r.code = 'lecturer'
on conflict do nothing;

-- ============================================================
-- SECTION 05J — INDEXES
-- ============================================================
create index if not exists idx_staff_institution on public.staff(institution_id);
create index if not exists idx_staff_department on public.staff(department_id);
create index if not exists idx_staff_status on public.staff(institution_id, employment_status);
create index if not exists idx_staff_user on public.staff(user_id);
create index if not exists idx_staff_appointments_staff on public.staff_appointments(staff_id);
create index if not exists idx_lecturer_profiles_staff on public.lecturer_profiles(staff_id);
create index if not exists idx_staff_qualifications_staff on public.staff_qualifications(staff_id);
create index if not exists idx_staff_documents_staff on public.staff_documents(staff_id);
create index if not exists idx_staff_status_history_staff on public.staff_status_history(staff_id);

-- ============================================================
-- SECTION 05K — UPDATED_AT TRIGGERS
-- ============================================================
do $$
declare
  t text;
begin
  foreach t in array array[
    'staff','staff_appointments','lecturer_profiles','staff_qualifications'
  ]
  loop
    execute format('drop trigger if exists trg_%I_updated_at on public.%I', t, t);
    execute format(
      'create trigger trg_%I_updated_at before update on public.%I
       for each row execute function public.set_updated_at()', t, t
    );
  end loop;
end $$;

-- ============================================================
-- SECTION 05L — ENABLE RLS
-- ============================================================
alter table public.staff enable row level security;
alter table public.staff_appointments enable row level security;
alter table public.lecturer_profiles enable row level security;
alter table public.staff_qualifications enable row level security;
alter table public.staff_documents enable row level security;
alter table public.staff_status_history enable row level security;

-- ============================================================
-- SECTION 05M — STAFF MANAGEMENT RLS
-- ============================================================
do $$
declare
  t text;
begin
  foreach t in array array[
    'staff','staff_appointments','lecturer_profiles',
    'staff_qualifications','staff_documents','staff_status_history'
  ]
  loop
    execute format('drop policy if exists "Staff viewers can view %s" on public.%I', t, t);
    execute format(
      'create policy "Staff viewers can view %s" on public.%I
       for select to authenticated
       using (
         public.has_permission(institution_id,''staff.view'')
         or public.has_permission(institution_id,''staff.manage'')
         or public.has_permission(institution_id,''lecturers.view'')
         or public.has_permission(institution_id,''lecturers.manage'')
       )', t, t
    );

    execute format('drop policy if exists "Staff managers can manage %s" on public.%I', t, t);
    execute format(
      'create policy "Staff managers can manage %s" on public.%I
       for all to authenticated
       using (
         public.has_permission(institution_id,''staff.manage'')
         or public.has_permission(institution_id,''lecturers.manage'')
       )
       with check (
         public.has_permission(institution_id,''staff.manage'')
         or public.has_permission(institution_id,''lecturers.manage'')
       )', t, t
    );
  end loop;
end $$;

-- ============================================================
-- SECTION 05N — STAFF SELF-SERVICE READ ACCESS
-- ============================================================
drop policy if exists "Staff can view own record" on public.staff;
create policy "Staff can view own record"
on public.staff for select to authenticated
using (user_id = (select auth.uid()));

drop policy if exists "Staff can view own appointments" on public.staff_appointments;
create policy "Staff can view own appointments"
on public.staff_appointments for select to authenticated
using (
  exists (
    select 1 from public.staff s
    where s.id = staff_id and s.user_id = (select auth.uid())
  )
);

drop policy if exists "Staff can view own qualifications" on public.staff_qualifications;
create policy "Staff can view own qualifications"
on public.staff_qualifications for select to authenticated
using (
  exists (
    select 1 from public.staff s
    where s.id = staff_id and s.user_id = (select auth.uid())
  )
);

drop policy if exists "Staff can view own documents" on public.staff_documents;
create policy "Staff can view own documents"
on public.staff_documents for select to authenticated
using (
  exists (
    select 1 from public.staff s
    where s.id = staff_id and s.user_id = (select auth.uid())
  )
);

drop policy if exists "Staff can view own status history" on public.staff_status_history;
create policy "Staff can view own status history"
on public.staff_status_history for select to authenticated
using (
  exists (
    select 1 from public.staff s
    where s.id = staff_id and s.user_id = (select auth.uid())
  )
);

drop policy if exists "Lecturers can view own lecturer profile" on public.lecturer_profiles;
create policy "Lecturers can view own lecturer profile"
on public.lecturer_profiles for select to authenticated
using (
  exists (
    select 1 from public.staff s
    where s.id = staff_id and s.user_id = (select auth.uid())
  )
);

-- ============================================================
-- SECTION 05O — VERIFICATION
-- ============================================================
select
  (select count(*) from public.staff) as staff,
  (select count(*) from public.staff_appointments) as appointments,
  (select count(*) from public.lecturer_profiles) as lecturer_profiles,
  (select count(*) from public.staff_qualifications) as qualifications,
  (select count(*) from public.staff_documents) as documents;

-- ============================================================
-- END UNIMIS MODULE 05 — STAFF & LECTURER MANAGEMENT
-- ============================================================
