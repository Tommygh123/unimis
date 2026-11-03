-- ============================================================
-- UNIMIS MODULE 10
-- ATTENDANCE, TEACHING SESSIONS & TIMETABLE OPERATIONS
-- 012_attendance_teaching_sessions.sql
-- Run AFTER Module 09
-- ============================================================

-- ============================================================
-- SECTION 10A — TEACHING SESSIONS
-- A real class/lecture occurrence tied to a course offering.
-- ============================================================

create table if not exists public.teaching_sessions (
  id uuid primary key default gen_random_uuid(),

  institution_id uuid not null
    references public.institutions(id)
    on delete cascade,

  course_offering_id uuid not null
    references public.course_offerings(id)
    on delete cascade,

  course_schedule_id uuid
    references public.course_schedules(id)
    on delete set null,

  lecturer_profile_id uuid
    references public.lecturer_profiles(id)
    on delete set null,

  session_date date not null,

  start_time time not null,
  end_time time not null,

  venue text,

  topic text,
  notes text,

  session_type text not null default 'lecture'
    check (
      session_type in (
        'lecture',
        'tutorial',
        'practical',
        'laboratory',
        'seminar',
        'online',
        'exam_review',
        'other'
      )
    ),

  status text not null default 'scheduled'
    check (
      status in (
        'scheduled',
        'in_progress',
        'completed',
        'cancelled',
        'postponed'
      )
    ),

  attendance_open boolean not null default false,

  attendance_opened_at timestamptz,
  attendance_closed_at timestamptz,

  created_by uuid
    references auth.users(id)
    on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  check (end_time > start_time)
);


-- ============================================================
-- SECTION 10B — STUDENT ATTENDANCE
-- ============================================================

create table if not exists public.student_attendance (
  id uuid primary key default gen_random_uuid(),

  institution_id uuid not null
    references public.institutions(id)
    on delete cascade,

  teaching_session_id uuid not null
    references public.teaching_sessions(id)
    on delete cascade,

  student_id uuid not null
    references public.students(id)
    on delete cascade,

  student_course_registration_id uuid
    references public.student_course_registrations(id)
    on delete set null,

  attendance_status text not null default 'present'
    check (
      attendance_status in (
        'present',
        'absent',
        'late',
        'excused'
      )
    ),

  check_in_time timestamptz,

  marked_by uuid
    references auth.users(id)
    on delete set null,

  remarks text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (
    teaching_session_id,
    student_id
  )
);


-- ============================================================
-- SECTION 10C — STAFF ATTENDANCE
-- General staff clock-in/out, separate from lecture attendance.
-- ============================================================

create table if not exists public.staff_attendance (
  id uuid primary key default gen_random_uuid(),

  institution_id uuid not null
    references public.institutions(id)
    on delete cascade,

  staff_id uuid not null
    references public.staff(id)
    on delete cascade,

  attendance_date date not null default current_date,

  clock_in timestamptz,
  clock_out timestamptz,

  attendance_status text not null default 'present'
    check (
      attendance_status in (
        'present',
        'absent',
        'late',
        'leave',
        'official_duty',
        'holiday',
        'other'
      )
    ),

  source text not null default 'manual'
    check (
      source in (
        'manual',
        'qr',
        'biometric',
        'mobile',
        'web',
        'import',
        'other'
      )
    ),

  remarks text,

  recorded_by uuid
    references auth.users(id)
    on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (
    staff_id,
    attendance_date
  )
);


-- ============================================================
-- SECTION 10D — ATTENDANCE POLICIES
-- Configurable per institution.
-- ============================================================

create table if not exists public.attendance_policies (
  id uuid primary key default gen_random_uuid(),

  institution_id uuid not null
    references public.institutions(id)
    on delete cascade,

  name text not null,

  applies_to text not null
    check (
      applies_to in (
        'students',
        'staff',
        'both'
      )
    ),

  minimum_percentage numeric(5,2)
    check (
      minimum_percentage is null
      or (
        minimum_percentage >= 0
        and minimum_percentage <= 100
      )
    ),

  late_after_minutes integer
    check (
      late_after_minutes is null
      or late_after_minutes >= 0
    ),

  settings jsonb not null default '{}'::jsonb,

  is_active boolean not null default true,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);


-- ============================================================
-- SECTION 10E — ATTENDANCE PERMISSIONS
-- ============================================================

insert into public.permissions (
  code,
  name,
  module,
  description
)
values
  (
    'attendance.view',
    'View Attendance',
    'attendance',
    'View student and staff attendance records'
  ),
  (
    'attendance.manage',
    'Manage Attendance',
    'attendance',
    'Create and manage attendance records'
  ),
  (
    'attendance.mark',
    'Mark Attendance',
    'attendance',
    'Mark attendance for assigned teaching sessions'
  ),
  (
    'attendance.policy_manage',
    'Manage Attendance Policies',
    'attendance',
    'Configure attendance rules and thresholds'
  )
on conflict (code)
do update set
  name = excluded.name,
  module = excluded.module,
  description = excluded.description;


-- ============================================================
-- SECTION 10F — ROLE PERMISSIONS
-- ============================================================

-- Owner/Admin
insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.institutions i
  on i.id = r.institution_id
join public.permissions p
  on p.code in (
    'attendance.view',
    'attendance.manage',
    'attendance.mark',
    'attendance.policy_manage'
  )
where i.code = 'UNIMIS-DEMO-UNIV'
  and r.code in ('owner','admin')
on conflict do nothing;

-- Registrar
insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.institutions i
  on i.id = r.institution_id
join public.permissions p
  on p.code in (
    'attendance.view',
    'attendance.manage'
  )
where i.code = 'UNIMIS-DEMO-UNIV'
  and r.code = 'registrar'
on conflict do nothing;

-- Lecturer
insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.institutions i
  on i.id = r.institution_id
join public.permissions p
  on p.code in (
    'attendance.view',
    'attendance.mark'
  )
where i.code = 'UNIMIS-DEMO-UNIV'
  and r.code = 'lecturer'
on conflict do nothing;


-- ============================================================
-- SECTION 10G — INDEXES
-- ============================================================

create index if not exists idx_teaching_sessions_institution
on public.teaching_sessions(institution_id);

create index if not exists idx_teaching_sessions_offering
on public.teaching_sessions(course_offering_id);

create index if not exists idx_teaching_sessions_date
on public.teaching_sessions(session_date);

create index if not exists idx_student_attendance_session
on public.student_attendance(teaching_session_id);

create index if not exists idx_student_attendance_student
on public.student_attendance(student_id);

create index if not exists idx_staff_attendance_staff
on public.staff_attendance(staff_id);

create index if not exists idx_staff_attendance_date
on public.staff_attendance(attendance_date);

create index if not exists idx_attendance_policies_institution
on public.attendance_policies(institution_id);


-- ============================================================
-- SECTION 10H — UPDATED_AT TRIGGERS
-- ============================================================

do $$
declare
  t text;
begin
  foreach t in array array[
    'teaching_sessions',
    'student_attendance',
    'staff_attendance',
    'attendance_policies'
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
-- SECTION 10I — ENABLE RLS
-- ============================================================

alter table public.teaching_sessions
enable row level security;

alter table public.student_attendance
enable row level security;

alter table public.staff_attendance
enable row level security;

alter table public.attendance_policies
enable row level security;


-- ============================================================
-- SECTION 10J — ATTENDANCE STAFF RLS
-- ============================================================

do $$
declare
  t text;
begin
  foreach t in array array[
    'teaching_sessions',
    'student_attendance',
    'staff_attendance',
    'attendance_policies'
  ]
  loop

    execute format(
      'drop policy if exists "Attendance viewers can view %s" on public.%I',
      t, t
    );

    execute format(
      'create policy "Attendance viewers can view %s"
       on public.%I
       for select
       to authenticated
       using (
         public.has_permission(institution_id,''attendance.view'')
         or public.has_permission(institution_id,''attendance.manage'')
         or public.has_permission(institution_id,''attendance.mark'')
         or public.has_permission(institution_id,''attendance.policy_manage'')
       )',
      t, t
    );

    execute format(
      'drop policy if exists "Attendance managers can manage %s" on public.%I',
      t, t
    );

    execute format(
      'create policy "Attendance managers can manage %s"
       on public.%I
       for all
       to authenticated
       using (
         public.has_permission(institution_id,''attendance.manage'')
         or public.has_permission(institution_id,''attendance.policy_manage'')
       )
       with check (
         public.has_permission(institution_id,''attendance.manage'')
         or public.has_permission(institution_id,''attendance.policy_manage'')
       )',
      t, t
    );

  end loop;
end $$;


-- ============================================================
-- SECTION 10K — LECTURER ACCESS TO OWN TEACHING SESSIONS
-- ============================================================

drop policy if exists
"Lecturers can view own teaching sessions"
on public.teaching_sessions;

create policy
"Lecturers can view own teaching sessions"
on public.teaching_sessions
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
-- SECTION 10L — LECTURER CAN MARK ATTENDANCE
-- FOR OWN ASSIGNED TEACHING SESSIONS
-- ============================================================

drop policy if exists
"Lecturers can mark attendance for own sessions"
on public.student_attendance;

create policy
"Lecturers can mark attendance for own sessions"
on public.student_attendance
for all
to authenticated
using (
  exists (
    select 1
    from public.teaching_sessions ts
    join public.lecturer_profiles lp
      on lp.id = ts.lecturer_profile_id
    join public.staff s
      on s.id = lp.staff_id
    where ts.id = teaching_session_id
      and s.user_id = (select auth.uid())
  )
)
with check (
  exists (
    select 1
    from public.teaching_sessions ts
    join public.lecturer_profiles lp
      on lp.id = ts.lecturer_profile_id
    join public.staff s
      on s.id = lp.staff_id
    where ts.id = teaching_session_id
      and s.user_id = (select auth.uid())
  )
);


-- ============================================================
-- SECTION 10M — STUDENT SELF-SERVICE ATTENDANCE
-- ============================================================

drop policy if exists
"Students can view own attendance"
on public.student_attendance;

create policy
"Students can view own attendance"
on public.student_attendance
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
-- SECTION 10N — STAFF SELF-SERVICE ATTENDANCE
-- ============================================================

drop policy if exists
"Staff can view own attendance"
on public.staff_attendance;

create policy
"Staff can view own attendance"
on public.staff_attendance
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
-- SECTION 10O — STUDENT ATTENDANCE SUMMARY VIEW
-- ============================================================

create or replace view public.v_student_attendance_summary
with (security_invoker = true)
as
select
  sa.institution_id,
  sa.student_id,
  s.student_number,
  concat_ws(' ', s.first_name, s.middle_name, s.last_name) as student_name,
  ts.course_offering_id,
  c.code as course_code,
  c.name as course_name,

  count(*) as total_sessions,

  count(*) filter (
    where sa.attendance_status = 'present'
  ) as present_count,

  count(*) filter (
    where sa.attendance_status = 'late'
  ) as late_count,

  count(*) filter (
    where sa.attendance_status = 'absent'
  ) as absent_count,

  count(*) filter (
    where sa.attendance_status = 'excused'
  ) as excused_count,

  round(
    (
      count(*) filter (
        where sa.attendance_status in ('present','late')
      )::numeric
      /
      nullif(count(*),0)
    ) * 100,
    2
  ) as attendance_percentage

from public.student_attendance sa

join public.students s
  on s.id = sa.student_id

join public.teaching_sessions ts
  on ts.id = sa.teaching_session_id

join public.course_offerings co
  on co.id = ts.course_offering_id

join public.courses c
  on c.id = co.course_id

group by
  sa.institution_id,
  sa.student_id,
  s.student_number,
  s.first_name,
  s.middle_name,
  s.last_name,
  ts.course_offering_id,
  c.code,
  c.name;


-- ============================================================
-- SECTION 10P — STAFF ATTENDANCE SUMMARY VIEW
-- ============================================================

create or replace view public.v_staff_attendance_summary
with (security_invoker = true)
as
select
  sa.institution_id,
  sa.staff_id,
  st.staff_number,
  concat_ws(' ', st.first_name, st.middle_name, st.last_name) as staff_name,

  count(*) as total_days,

  count(*) filter (
    where sa.attendance_status = 'present'
  ) as present_days,

  count(*) filter (
    where sa.attendance_status = 'late'
  ) as late_days,

  count(*) filter (
    where sa.attendance_status = 'absent'
  ) as absent_days,

  count(*) filter (
    where sa.attendance_status = 'leave'
  ) as leave_days

from public.staff_attendance sa

join public.staff st
  on st.id = sa.staff_id

group by
  sa.institution_id,
  sa.staff_id,
  st.staff_number,
  st.first_name,
  st.middle_name,
  st.last_name;


-- ============================================================
-- SECTION 10Q — VERIFY MODULE 10
-- ============================================================

select

  (
    select count(*)
    from public.teaching_sessions
  )
  as teaching_sessions,

  (
    select count(*)
    from public.student_attendance
  )
  as student_attendance,

  (
    select count(*)
    from public.staff_attendance
  )
  as staff_attendance,

  (
    select count(*)
    from public.attendance_policies
  )
  as attendance_policies;


-- ============================================================
-- END UNIMIS MODULE 10
-- ATTENDANCE, TEACHING SESSIONS & TIMETABLE OPERATIONS
-- ============================================================
