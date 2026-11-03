-- ============================================================
-- UNIMIS MODULE 07
-- COURSE REGISTRATION & STUDENT ENROLMENT
-- 009_course_registration.sql
-- Run AFTER Module 06
-- ============================================================

-- ============================================================
-- SECTION 07A — SEMESTER / PERIOD REGISTRATIONS
-- One student registration record per academic period.
-- ============================================================

create table if not exists public.student_period_registrations (
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

  academic_period_id uuid not null
    references public.academic_periods(id)
    on delete cascade,

  programme_enrolment_id uuid
    references public.student_programme_enrolments(id)
    on delete set null,

  level_number integer
    check (level_number is null or level_number > 0),

  registration_status text not null default 'draft'
    check (
      registration_status in (
        'draft',
        'submitted',
        'approved',
        'rejected',
        'cancelled',
        'completed'
      )
    ),

  submitted_at timestamptz,
  approved_at timestamptz,

  approved_by uuid
    references auth.users(id)
    on delete set null,

  notes text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (
    student_id,
    academic_period_id
  )
);


-- ============================================================
-- SECTION 07B — REGISTERED COURSES
-- ============================================================

create table if not exists public.student_course_registrations (
  id uuid primary key default gen_random_uuid(),

  institution_id uuid not null
    references public.institutions(id)
    on delete cascade,

  period_registration_id uuid not null
    references public.student_period_registrations(id)
    on delete cascade,

  student_id uuid not null
    references public.students(id)
    on delete cascade,

  course_offering_id uuid not null
    references public.course_offerings(id)
    on delete restrict,

  course_group_id uuid
    references public.course_groups(id)
    on delete set null,

  registration_type text not null default 'normal'
    check (
      registration_type in (
        'normal',
        'repeat',
        'resit',
        'audit',
        'elective',
        'other'
      )
    ),

  status text not null default 'registered'
    check (
      status in (
        'registered',
        'dropped',
        'withdrawn',
        'completed',
        'failed',
        'passed'
      )
    ),

  registered_at timestamptz not null default now(),
  dropped_at timestamptz,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (
    student_id,
    course_offering_id
  )
);


-- ============================================================
-- SECTION 07C — REGISTRATION APPROVAL HISTORY
-- ============================================================

create table if not exists public.registration_approval_history (
  id uuid primary key default gen_random_uuid(),

  institution_id uuid not null
    references public.institutions(id)
    on delete cascade,

  period_registration_id uuid not null
    references public.student_period_registrations(id)
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
-- SECTION 07D — REGISTRATION PERMISSIONS
-- ============================================================

insert into public.permissions (
  code,
  name,
  module,
  description
)
values
  (
    'registration.submit',
    'Submit Course Registration',
    'academics',
    'Submit own course registration'
  ),
  (
    'registration.approve',
    'Approve Course Registration',
    'academics',
    'Approve or reject student course registrations'
  ),
  (
    'registration.override',
    'Override Course Registration',
    'academics',
    'Add, drop or modify registrations administratively'
  )
on conflict (code)
do update set
  name = excluded.name,
  module = excluded.module,
  description = excluded.description;


-- ============================================================
-- SECTION 07E — ROLE PERMISSION ASSIGNMENTS
-- ============================================================

-- Owner/Admin
insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.institutions i
  on i.id = r.institution_id
join public.permissions p
  on p.code in (
    'registration.submit',
    'registration.approve',
    'registration.override'
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
    'registration.approve',
    'registration.override'
  )
where i.code = 'UNIMIS-DEMO-UNIV'
  and r.code = 'registrar'
on conflict do nothing;

-- Student
insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.institutions i
  on i.id = r.institution_id
join public.permissions p
  on p.code = 'registration.submit'
where i.code = 'UNIMIS-DEMO-UNIV'
  and r.code = 'student'
on conflict do nothing;


-- ============================================================
-- SECTION 07F — REGISTRATION STATUS HISTORY TRIGGER
-- ============================================================

create or replace function public.log_registration_status_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.registration_status is distinct from new.registration_status then
    insert into public.registration_approval_history (
      institution_id,
      period_registration_id,
      old_status,
      new_status,
      action_by,
      action_at
    )
    values (
      new.institution_id,
      new.id,
      old.registration_status,
      new.registration_status,
      auth.uid(),
      now()
    );
  end if;

  return new;
end;
$$;

revoke all
on function public.log_registration_status_change()
from public;

drop trigger if exists
trg_registration_status_history
on public.student_period_registrations;

create trigger
trg_registration_status_history
after update of registration_status
on public.student_period_registrations
for each row
execute function public.log_registration_status_change();


-- ============================================================
-- SECTION 07G — INDEXES
-- ============================================================

create index if not exists idx_period_reg_student
on public.student_period_registrations(student_id);

create index if not exists idx_period_reg_period
on public.student_period_registrations(academic_period_id);

create index if not exists idx_period_reg_status
on public.student_period_registrations(institution_id, registration_status);

create index if not exists idx_student_course_reg_student
on public.student_course_registrations(student_id);

create index if not exists idx_student_course_reg_offering
on public.student_course_registrations(course_offering_id);

create index if not exists idx_student_course_reg_periodreg
on public.student_course_registrations(period_registration_id);

create index if not exists idx_registration_history_periodreg
on public.registration_approval_history(period_registration_id);


-- ============================================================
-- SECTION 07H — UPDATED_AT TRIGGERS
-- ============================================================

do $$
declare
  t text;
begin
  foreach t in array array[
    'student_period_registrations',
    'student_course_registrations'
  ]
  loop
    execute format(
      'drop trigger if exists trg_%I_updated_at on public.%I',
      t, t
    );

    execute format(
      'create trigger trg_%I_updated_at
       before update on public.%I
       for each row execute function public.set_updated_at()',
      t, t
    );
  end loop;
end $$;


-- ============================================================
-- SECTION 07I — ENABLE RLS
-- ============================================================

alter table public.student_period_registrations
enable row level security;

alter table public.student_course_registrations
enable row level security;

alter table public.registration_approval_history
enable row level security;


-- ============================================================
-- SECTION 07J — STAFF REGISTRATION SECURITY
-- ============================================================

do $$
declare
  t text;
begin
  foreach t in array array[
    'student_period_registrations',
    'student_course_registrations',
    'registration_approval_history'
  ]
  loop

    execute format(
      'drop policy if exists
       "Registration viewers can view %s"
       on public.%I',
      t, t
    );

    execute format(
      'create policy
       "Registration viewers can view %s"
       on public.%I
       for select
       to authenticated
       using (
         public.has_permission(
           institution_id,
           ''registration.view''
         )
         or public.has_permission(
           institution_id,
           ''registration.manage''
         )
         or public.has_permission(
           institution_id,
           ''registration.approve''
         )
         or public.has_permission(
           institution_id,
           ''registration.override''
         )
       )',
      t, t
    );

    execute format(
      'drop policy if exists
       "Registration managers can manage %s"
       on public.%I',
      t, t
    );

    execute format(
      'create policy
       "Registration managers can manage %s"
       on public.%I
       for all
       to authenticated
       using (
         public.has_permission(
           institution_id,
           ''registration.manage''
         )
         or public.has_permission(
           institution_id,
           ''registration.approve''
         )
         or public.has_permission(
           institution_id,
           ''registration.override''
         )
       )
       with check (
         public.has_permission(
           institution_id,
           ''registration.manage''
         )
         or public.has_permission(
           institution_id,
           ''registration.approve''
         )
         or public.has_permission(
           institution_id,
           ''registration.override''
         )
       )',
      t, t
    );

  end loop;
end $$;


-- ============================================================
-- SECTION 07K — STUDENT SELF-SERVICE READ ACCESS
-- ============================================================

drop policy if exists
"Students can view own period registrations"
on public.student_period_registrations;

create policy
"Students can view own period registrations"
on public.student_period_registrations
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
"Students can view own course registrations"
on public.student_course_registrations;

create policy
"Students can view own course registrations"
on public.student_course_registrations
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
"Students can view own registration history"
on public.registration_approval_history;

create policy
"Students can view own registration history"
on public.registration_approval_history
for select
to authenticated
using (
  exists (
    select 1
    from public.student_period_registrations spr
    join public.students s
      on s.id = spr.student_id
    where spr.id = period_registration_id
      and s.user_id = (select auth.uid())
  )
);


-- ============================================================
-- SECTION 07L — STUDENT SUBMISSION FUNCTION
-- Creates the period registration if missing and submits it.
-- ============================================================

create or replace function public.submit_student_period_registration(
  requested_academic_period_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_student_id uuid;
  inst_id uuid;
  year_id uuid;
  enrolment_id uuid;
  current_level_no integer;
  reg_id uuid;
begin

  select s.id, s.institution_id
  into current_student_id, inst_id
  from public.students s
  where s.user_id = auth.uid()
    and s.status = 'active'
  limit 1;

  if current_student_id is null then
    raise exception 'No active student profile found';
  end if;

  select ap.academic_year_id
  into year_id
  from public.academic_periods ap
  where ap.id = requested_academic_period_id
    and ap.institution_id = inst_id
    and ap.registration_start is not null
    and ap.registration_end is not null
    and current_date between ap.registration_start and ap.registration_end;

  if year_id is null then
    raise exception 'Registration period is not currently open';
  end if;

  select spe.id, spe.current_level
  into enrolment_id, current_level_no
  from public.student_programme_enrolments spe
  where spe.student_id = current_student_id
    and spe.is_primary = true
    and spe.enrolment_status = 'active'
  limit 1;

  insert into public.student_period_registrations (
    institution_id,
    student_id,
    academic_year_id,
    academic_period_id,
    programme_enrolment_id,
    level_number,
    registration_status,
    submitted_at
  )
  values (
    inst_id,
    current_student_id,
    year_id,
    requested_academic_period_id,
    enrolment_id,
    current_level_no,
    'submitted',
    now()
  )
  on conflict (student_id, academic_period_id)
  do update set
    registration_status = 'submitted',
    submitted_at = now(),
    updated_at = now()
  returning id into reg_id;

  return reg_id;
end;
$$;

revoke all
on function public.submit_student_period_registration(uuid)
from public;

grant execute
on function public.submit_student_period_registration(uuid)
to authenticated;


-- ============================================================
-- SECTION 07M — ADD COURSE TO OWN REGISTRATION FUNCTION
-- ============================================================

create or replace function public.add_course_to_own_registration(
  requested_period_registration_id uuid,
  requested_course_offering_id uuid,
  requested_registration_type text default 'normal'
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  reg_row public.student_period_registrations%rowtype;
  offering_row public.course_offerings%rowtype;
  result_id uuid;
begin

  select *
  into reg_row
  from public.student_period_registrations
  where id = requested_period_registration_id;

  if not found then
    raise exception 'Registration not found';
  end if;

  if not exists (
    select 1
    from public.students s
    where s.id = reg_row.student_id
      and s.user_id = auth.uid()
  ) then
    raise exception 'Not authorised';
  end if;

  if reg_row.registration_status not in ('draft','submitted') then
    raise exception 'Registration can no longer be modified';
  end if;

  select *
  into offering_row
  from public.course_offerings
  where id = requested_course_offering_id
    and institution_id = reg_row.institution_id
    and academic_period_id = reg_row.academic_period_id
    and registration_open = true
    and status = 'open';

  if not found then
    raise exception 'Course offering is not open for registration';
  end if;

  insert into public.student_course_registrations (
    institution_id,
    period_registration_id,
    student_id,
    course_offering_id,
    registration_type,
    status
  )
  values (
    reg_row.institution_id,
    reg_row.id,
    reg_row.student_id,
    offering_row.id,
    requested_registration_type,
    'registered'
  )
  on conflict (student_id, course_offering_id)
  do update set
    status = 'registered',
    registration_type = excluded.registration_type,
    dropped_at = null,
    updated_at = now()
  returning id into result_id;

  return result_id;
end;
$$;

revoke all
on function public.add_course_to_own_registration(uuid, uuid, text)
from public;

grant execute
on function public.add_course_to_own_registration(uuid, uuid, text)
to authenticated;


-- ============================================================
-- SECTION 07N — REGISTRATION SUMMARY VIEW
-- ============================================================

create or replace view public.v_student_course_registrations
with (security_invoker = true)
as
select
  scr.id,
  scr.institution_id,
  scr.student_id,
  s.student_number,
  concat_ws(' ', s.first_name, s.middle_name, s.last_name) as student_name,
  spr.academic_period_id,
  ay.name as academic_year,
  ap.name as academic_period,
  c.code as course_code,
  c.name as course_name,
  c.credit_hours,
  scr.registration_type,
  scr.status as course_registration_status,
  spr.registration_status as period_registration_status
from public.student_course_registrations scr
join public.students s
  on s.id = scr.student_id
join public.student_period_registrations spr
  on spr.id = scr.period_registration_id
join public.course_offerings co
  on co.id = scr.course_offering_id
join public.courses c
  on c.id = co.course_id
join public.academic_years ay
  on ay.id = spr.academic_year_id
join public.academic_periods ap
  on ap.id = spr.academic_period_id;


-- ============================================================
-- SECTION 07O — VERIFY MODULE 07
-- ============================================================

select
  (select count(*) from public.student_period_registrations)
    as period_registrations,

  (select count(*) from public.student_course_registrations)
    as course_registrations,

  (select count(*) from public.registration_approval_history)
    as approval_history;


-- ============================================================
-- END UNIMIS MODULE 07
-- COURSE REGISTRATION & STUDENT ENROLMENT
-- ============================================================
