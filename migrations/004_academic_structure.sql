-- ============================================================
-- UNIVERSAL EDUCATION MIS
-- MODULE 02: ACADEMIC STRUCTURE
-- Run AFTER Module 01A, 01B and 01C
-- ============================================================

-- 1. FACULTIES
create table if not exists public.faculties (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  name text not null,
  code text not null,
  description text,
  status text not null default 'active' check (status in ('active','inactive','archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (institution_id, code)
);

-- 2. SCHOOLS (optional layer inside a faculty)
create table if not exists public.schools (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  faculty_id uuid references public.faculties(id) on delete set null,
  name text not null,
  code text not null,
  description text,
  status text not null default 'active' check (status in ('active','inactive','archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (institution_id, code)
);

-- 3. DEPARTMENTS
create table if not exists public.departments (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  faculty_id uuid references public.faculties(id) on delete set null,
  school_id uuid references public.schools(id) on delete set null,
  name text not null,
  code text not null,
  description text,
  status text not null default 'active' check (status in ('active','inactive','archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (institution_id, code)
);

-- 4. PROGRAMMES
create table if not exists public.programmes (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  department_id uuid references public.departments(id) on delete set null,
  name text not null,
  code text not null,
  award_type text,
  duration_years numeric(4,1),
  total_credits numeric(8,2),
  description text,
  status text not null default 'active' check (status in ('active','inactive','archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (institution_id, code)
);

-- 5. ACADEMIC YEARS
create table if not exists public.academic_years (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  name text not null,
  start_date date not null,
  end_date date not null,
  is_current boolean not null default false,
  status text not null default 'planned'
    check (status in ('planned','active','closed','archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (institution_id, name),
  check (end_date > start_date)
);

-- Only one current academic year per institution.
create unique index if not exists uq_current_academic_year_per_institution
on public.academic_years(institution_id)
where is_current = true;

-- 6. ACADEMIC PERIODS
-- Generic enough for semester, term, trimester, quarter, etc.
create table if not exists public.academic_periods (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  academic_year_id uuid not null references public.academic_years(id) on delete cascade,
  name text not null,
  period_type text not null default 'semester'
    check (period_type in ('semester','term','trimester','quarter','other')),
  period_number integer not null check (period_number > 0),
  start_date date not null,
  end_date date not null,
  registration_start date,
  registration_end date,
  is_current boolean not null default false,
  status text not null default 'planned'
    check (status in ('planned','active','closed','archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (academic_year_id, period_type, period_number),
  check (end_date > start_date),
  check (
    registration_end is null
    or registration_start is null
    or registration_end >= registration_start
  )
);

create unique index if not exists uq_current_period_per_institution
on public.academic_periods(institution_id)
where is_current = true;

-- 7. COURSES / SUBJECTS
-- Same table can later support JHS/SHS subjects.
create table if not exists public.courses (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  department_id uuid references public.departments(id) on delete set null,
  name text not null,
  code text not null,
  course_type text not null default 'course'
    check (course_type in ('course','subject')),
  credit_hours numeric(5,2) not null default 0 check (credit_hours >= 0),
  lecture_hours numeric(5,2) not null default 0 check (lecture_hours >= 0),
  practical_hours numeric(5,2) not null default 0 check (practical_hours >= 0),
  description text,
  status text not null default 'active' check (status in ('active','inactive','archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (institution_id, code)
);

-- 8. PROGRAMME CURRICULUM / PROGRAMME COURSES
create table if not exists public.programme_courses (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  programme_id uuid not null references public.programmes(id) on delete cascade,
  course_id uuid not null references public.courses(id) on delete cascade,
  level_number integer not null check (level_number > 0),
  period_number integer not null default 1 check (period_number > 0),
  course_category text not null default 'core'
    check (course_category in ('core','elective','required','optional')),
  is_required boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (programme_id, course_id, level_number, period_number)
);

-- 9. INDEXES
create index if not exists idx_faculties_institution on public.faculties(institution_id);
create index if not exists idx_schools_institution on public.schools(institution_id);
create index if not exists idx_schools_faculty on public.schools(faculty_id);
create index if not exists idx_departments_institution on public.departments(institution_id);
create index if not exists idx_departments_faculty on public.departments(faculty_id);
create index if not exists idx_programmes_institution on public.programmes(institution_id);
create index if not exists idx_programmes_department on public.programmes(department_id);
create index if not exists idx_academic_years_institution on public.academic_years(institution_id);
create index if not exists idx_academic_periods_year on public.academic_periods(academic_year_id);
create index if not exists idx_courses_institution on public.courses(institution_id);
create index if not exists idx_courses_department on public.courses(department_id);
create index if not exists idx_programme_courses_programme on public.programme_courses(programme_id);
create index if not exists idx_programme_courses_course on public.programme_courses(course_id);

-- 10. UPDATED_AT TRIGGERS
do $$
declare
  t text;
begin
  foreach t in array array[
    'faculties','schools','departments','programmes',
    'academic_years','academic_periods','courses','programme_courses'
  ]
  loop
    execute format('drop trigger if exists trg_%I_updated_at on public.%I', t, t);
    execute format(
      'create trigger trg_%I_updated_at before update on public.%I
       for each row execute function public.set_updated_at()', t, t
    );
  end loop;
end $$;

-- 11. ENABLE RLS
alter table public.faculties enable row level security;
alter table public.schools enable row level security;
alter table public.departments enable row level security;
alter table public.programmes enable row level security;
alter table public.academic_years enable row level security;
alter table public.academic_periods enable row level security;
alter table public.courses enable row level security;
alter table public.programme_courses enable row level security;

-- 12. RLS POLICIES
-- Members may view academic structure.
-- Users with academics.manage may create/update/delete it.

do $$
declare
  t text;
begin
  foreach t in array array[
    'faculties','schools','departments','programmes',
    'academic_years','academic_periods','courses','programme_courses'
  ]
  loop
    execute format('drop policy if exists "Members can view %s" on public.%I', t, t);
    execute format(
      'create policy "Members can view %s" on public.%I
       for select to authenticated
       using (public.is_institution_member(institution_id))', t, t
    );

    execute format('drop policy if exists "Academic managers can manage %s" on public.%I', t, t);
    execute format(
      'create policy "Academic managers can manage %s" on public.%I
       for all to authenticated
       using (public.has_permission(institution_id, ''academics.manage''))
       with check (public.has_permission(institution_id, ''academics.manage''))', t, t
    );
  end loop;
end $$;

-- 13. DEMO UNIVERSITY ACADEMIC YEAR + TWO SEMESTERS
insert into public.academic_years (
  institution_id, name, start_date, end_date, is_current, status
)
select
  i.id, '2026/2027', date '2026-08-01', date '2027-07-31', true, 'active'
from public.institutions i
where i.code = 'UNIMIS-DEMO-UNIV'
on conflict (institution_id, name)
do update set
  start_date = excluded.start_date,
  end_date = excluded.end_date,
  is_current = excluded.is_current,
  status = excluded.status,
  updated_at = now();

insert into public.academic_periods (
  institution_id, academic_year_id, name, period_type, period_number,
  start_date, end_date, registration_start, registration_end,
  is_current, status
)
select
  i.id, ay.id, x.name, 'semester', x.period_number,
  x.start_date, x.end_date, x.registration_start, x.registration_end,
  x.is_current, x.status
from public.institutions i
join public.academic_years ay
  on ay.institution_id = i.id and ay.name = '2026/2027'
cross join (
  values
    ('Semester 1', 1, date '2026-08-01', date '2026-12-31',
     date '2026-08-01', date '2026-09-15', true, 'active'),
    ('Semester 2', 2, date '2027-01-01', date '2027-07-31',
     date '2027-01-01', date '2027-02-15', false, 'planned')
) as x(name, period_number, start_date, end_date, registration_start, registration_end, is_current, status)
where i.code = 'UNIMIS-DEMO-UNIV'
on conflict (academic_year_id, period_type, period_number)
do update set
  name = excluded.name,
  start_date = excluded.start_date,
  end_date = excluded.end_date,
  registration_start = excluded.registration_start,
  registration_end = excluded.registration_end,
  is_current = excluded.is_current,
  status = excluded.status,
  updated_at = now();

-- 14. VERIFICATION
select
  (select count(*) from public.faculties) as faculties,
  (select count(*) from public.departments) as departments,
  (select count(*) from public.programmes) as programmes,
  (select count(*) from public.courses) as courses,
  (select count(*) from public.academic_years) as academic_years,
  (select count(*) from public.academic_periods) as academic_periods;

-- ============================================================
-- END MODULE 02
-- ============================================================
