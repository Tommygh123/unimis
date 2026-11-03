-- ============================================================
-- UNIMIS MODULE 08
-- ASSESSMENT, EXAMS, GRADES, GPA/CGPA & RESULTS
-- 010_assessment_results.sql
-- Run AFTER Module 07
-- ============================================================

-- ============================================================
-- SECTION 08A — GRADING SCHEMES
-- ============================================================

create table if not exists public.grading_schemes (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  name text not null,
  code text not null,
  gpa_scale numeric(4,2) not null default 4.00 check (gpa_scale > 0),
  is_default boolean not null default false,
  status text not null default 'active'
    check (status in ('active','inactive','archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (institution_id, code)
);

create unique index if not exists uq_default_grading_scheme_per_institution
on public.grading_schemes(institution_id)
where is_default = true;

-- ============================================================
-- SECTION 08B — GRADE BANDS
-- ============================================================

create table if not exists public.grade_bands (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  grading_scheme_id uuid not null references public.grading_schemes(id) on delete cascade,

  letter_grade text not null,
  min_score numeric(5,2) not null check (min_score >= 0 and min_score <= 100),
  max_score numeric(5,2) not null check (max_score >= 0 and max_score <= 100),

  grade_point numeric(4,2) not null check (grade_point >= 0),
  classification text,
  is_pass boolean not null default true,

  created_at timestamptz not null default now(),

  check (max_score >= min_score),
  unique (grading_scheme_id, letter_grade),
  unique (grading_scheme_id, min_score, max_score)
);

-- ============================================================
-- SECTION 08C — ASSESSMENT DEFINITIONS
-- E.g. Quiz, Assignment, Midsem, Practical, Final Exam
-- ============================================================

create table if not exists public.assessment_items (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  course_offering_id uuid not null references public.course_offerings(id) on delete cascade,

  name text not null,
  assessment_type text not null
    check (assessment_type in (
      'quiz','assignment','midsem','project','practical',
      'presentation','final_exam','other'
    )),

  max_score numeric(6,2) not null default 100 check (max_score > 0),
  weight_percent numeric(5,2) not null check (weight_percent > 0 and weight_percent <= 100),

  due_date timestamptz,
  sequence_no integer not null default 1 check (sequence_no > 0),

  status text not null default 'draft'
    check (status in ('draft','open','closed','published','cancelled')),

  created_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (course_offering_id, name)
);

-- ============================================================
-- SECTION 08D — STUDENT ASSESSMENT SCORES
-- ============================================================

create table if not exists public.assessment_scores (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  assessment_item_id uuid not null references public.assessment_items(id) on delete cascade,
  student_course_registration_id uuid not null
    references public.student_course_registrations(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,

  raw_score numeric(6,2) not null check (raw_score >= 0),
  weighted_score numeric(6,2),

  status text not null default 'entered'
    check (status in ('entered','verified','published','withheld')),

  entered_by uuid references auth.users(id) on delete set null,
  verified_by uuid references auth.users(id) on delete set null,

  entered_at timestamptz not null default now(),
  verified_at timestamptz,

  remarks text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (assessment_item_id, student_course_registration_id)
);

-- ============================================================
-- SECTION 08E — COURSE RESULTS
-- ============================================================

create table if not exists public.course_results (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  student_course_registration_id uuid not null
    references public.student_course_registrations(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  course_offering_id uuid not null references public.course_offerings(id) on delete cascade,
  grading_scheme_id uuid not null references public.grading_schemes(id) on delete restrict,

  total_score numeric(6,2) not null default 0 check (total_score >= 0 and total_score <= 100),
  letter_grade text,
  grade_point numeric(4,2),
  quality_points numeric(8,2),

  result_status text not null default 'draft'
    check (result_status in ('draft','submitted','approved','published','withheld','cancelled')),

  passed boolean,

  submitted_by uuid references auth.users(id) on delete set null,
  approved_by uuid references auth.users(id) on delete set null,

  submitted_at timestamptz,
  approved_at timestamptz,
  published_at timestamptz,

  remarks text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (student_course_registration_id)
);

-- ============================================================
-- SECTION 08F — PERIOD GPA SUMMARY
-- ============================================================

create table if not exists public.student_period_results (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  academic_period_id uuid not null references public.academic_periods(id) on delete cascade,

  attempted_credits numeric(8,2) not null default 0,
  earned_credits numeric(8,2) not null default 0,
  total_quality_points numeric(10,2) not null default 0,

  gpa numeric(5,3),
  cgpa numeric(5,3),

  academic_standing text,
  status text not null default 'calculated'
    check (status in ('calculated','approved','published')),

  calculated_at timestamptz not null default now(),
  approved_by uuid references auth.users(id) on delete set null,
  approved_at timestamptz,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (student_id, academic_period_id)
);

-- ============================================================
-- SECTION 08G — RESULT APPROVAL HISTORY
-- ============================================================

create table if not exists public.result_approval_history (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  course_result_id uuid not null references public.course_results(id) on delete cascade,

  old_status text,
  new_status text not null,

  action_by uuid references auth.users(id) on delete set null,
  action_at timestamptz not null default now(),
  notes text
);

-- ============================================================
-- SECTION 08H — DEFAULT UNIVERSITY GRADING SCHEME
-- ============================================================

insert into public.grading_schemes (
  institution_id,
  name,
  code,
  gpa_scale,
  is_default,
  status
)
select
  i.id,
  'Standard 4.0 GPA Scheme',
  'STD-4',
  4.00,
  true,
  'active'
from public.institutions i
where i.code = 'UNIMIS-DEMO-UNIV'
on conflict (institution_id, code)
do update set
  name = excluded.name,
  gpa_scale = excluded.gpa_scale,
  is_default = true,
  status = 'active',
  updated_at = now();

insert into public.grade_bands (
  institution_id,
  grading_scheme_id,
  letter_grade,
  min_score,
  max_score,
  grade_point,
  classification,
  is_pass
)
select
  i.id,
  gs.id,
  g.letter_grade,
  g.min_score,
  g.max_score,
  g.grade_point,
  g.classification,
  g.is_pass
from public.institutions i
join public.grading_schemes gs
  on gs.institution_id = i.id
 and gs.code = 'STD-4'
cross join (
  values
    ('A', 80.00, 100.00, 4.00, 'Excellent', true),
    ('B+',75.00, 79.99, 3.50, 'Very Good', true),
    ('B', 70.00, 74.99, 3.00, 'Good', true),
    ('C+',65.00, 69.99, 2.50, 'Fairly Good', true),
    ('C', 60.00, 64.99, 2.00, 'Average', true),
    ('D+',55.00, 59.99, 1.50, 'Below Average', true),
    ('D', 50.00, 54.99, 1.00, 'Pass', true),
    ('F',  0.00, 49.99, 0.00, 'Fail', false)
) as g(letter_grade,min_score,max_score,grade_point,classification,is_pass)
where i.code = 'UNIMIS-DEMO-UNIV'
on conflict (grading_scheme_id, letter_grade)
do update set
  min_score = excluded.min_score,
  max_score = excluded.max_score,
  grade_point = excluded.grade_point,
  classification = excluded.classification,
  is_pass = excluded.is_pass;

-- ============================================================
-- SECTION 08I — SCORE WEIGHTING FUNCTION
-- ============================================================

create or replace function public.calculate_weighted_score()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  max_value numeric(6,2);
  weight_value numeric(5,2);
begin
  select ai.max_score, ai.weight_percent
  into max_value, weight_value
  from public.assessment_items ai
  where ai.id = new.assessment_item_id;

  if max_value is null or max_value <= 0 then
    raise exception 'Invalid assessment item';
  end if;

  if new.raw_score > max_value then
    raise exception 'Raw score cannot exceed assessment maximum';
  end if;

  new.weighted_score :=
    round((new.raw_score / max_value) * weight_value, 2);

  return new;
end;
$$;

revoke all on function public.calculate_weighted_score() from public;

drop trigger if exists trg_calculate_weighted_score
on public.assessment_scores;

create trigger trg_calculate_weighted_score
before insert or update of raw_score, assessment_item_id
on public.assessment_scores
for each row
execute function public.calculate_weighted_score();

-- ============================================================
-- SECTION 08J — COURSE RESULT CALCULATION FUNCTION
-- ============================================================

create or replace function public.calculate_course_result(
  requested_student_course_registration_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  scr public.student_course_registrations%rowtype;
  co public.course_offerings%rowtype;
  crs public.courses%rowtype;
  scheme_id uuid;
  total numeric(6,2);
  band public.grade_bands%rowtype;
  result_id uuid;
begin

  select *
  into scr
  from public.student_course_registrations
  where id = requested_student_course_registration_id;

  if not found then
    raise exception 'Student course registration not found';
  end if;

  if not public.has_permission(scr.institution_id, 'results.enter')
     and not public.has_permission(scr.institution_id, 'results.approve') then
    raise exception 'Not authorised';
  end if;

  select *
  into co
  from public.course_offerings
  where id = scr.course_offering_id;

  select *
  into crs
  from public.courses
  where id = co.course_id;

  select gs.id
  into scheme_id
  from public.grading_schemes gs
  where gs.institution_id = scr.institution_id
    and gs.is_default = true
    and gs.status = 'active'
  limit 1;

  if scheme_id is null then
    raise exception 'No default grading scheme configured';
  end if;

  select coalesce(sum(ascs.weighted_score),0)
  into total
  from public.assessment_scores ascs
  join public.assessment_items ai
    on ai.id = ascs.assessment_item_id
  where ascs.student_course_registration_id = scr.id
    and ai.course_offering_id = scr.course_offering_id
    and ascs.status in ('entered','verified','published');

  select *
  into band
  from public.grade_bands gb
  where gb.grading_scheme_id = scheme_id
    and total between gb.min_score and gb.max_score
  order by gb.min_score desc
  limit 1;

  if band.id is null then
    raise exception 'No grade band matches total score %', total;
  end if;

  insert into public.course_results (
    institution_id,
    student_course_registration_id,
    student_id,
    course_offering_id,
    grading_scheme_id,
    total_score,
    letter_grade,
    grade_point,
    quality_points,
    result_status,
    passed
  )
  values (
    scr.institution_id,
    scr.id,
    scr.student_id,
    scr.course_offering_id,
    scheme_id,
    total,
    band.letter_grade,
    band.grade_point,
    round(band.grade_point * coalesce(crs.credit_hours,0),2),
    'draft',
    band.is_pass
  )
  on conflict (student_course_registration_id)
  do update set
    total_score = excluded.total_score,
    letter_grade = excluded.letter_grade,
    grade_point = excluded.grade_point,
    quality_points = excluded.quality_points,
    passed = excluded.passed,
    updated_at = now()
  returning id into result_id;

  return result_id;
end;
$$;

revoke all
on function public.calculate_course_result(uuid)
from public;

grant execute
on function public.calculate_course_result(uuid)
to authenticated;

-- ============================================================
-- SECTION 08K — PERIOD GPA/CGPA CALCULATION
-- ============================================================

create or replace function public.calculate_student_period_gpa(
  requested_student_id uuid,
  requested_academic_period_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  inst_id uuid;
  attempted numeric(8,2);
  earned numeric(8,2);
  qpoints numeric(10,2);
  period_gpa numeric(5,3);
  cumulative_credits numeric(10,2);
  cumulative_qpoints numeric(12,2);
  cumulative_gpa numeric(5,3);
  result_id uuid;
begin

  select s.institution_id
  into inst_id
  from public.students s
  where s.id = requested_student_id;

  if inst_id is null then
    raise exception 'Student not found';
  end if;

  if not public.has_permission(inst_id,'results.approve')
     and not public.has_permission(inst_id,'results.enter') then
    raise exception 'Not authorised';
  end if;

  select
    coalesce(sum(c.credit_hours),0),
    coalesce(sum(case when cr.passed then c.credit_hours else 0 end),0),
    coalesce(sum(cr.quality_points),0)
  into attempted, earned, qpoints
  from public.course_results cr
  join public.course_offerings co
    on co.id = cr.course_offering_id
  join public.courses c
    on c.id = co.course_id
  where cr.student_id = requested_student_id
    and co.academic_period_id = requested_academic_period_id
    and cr.result_status in ('approved','published');

  period_gpa :=
    case
      when attempted > 0 then round(qpoints / attempted,3)
      else null
    end;

  select
    coalesce(sum(c.credit_hours),0),
    coalesce(sum(cr.quality_points),0)
  into cumulative_credits, cumulative_qpoints
  from public.course_results cr
  join public.course_offerings co
    on co.id = cr.course_offering_id
  join public.courses c
    on c.id = co.course_id
  join public.academic_periods ap
    on ap.id = co.academic_period_id
  where cr.student_id = requested_student_id
    and cr.result_status in ('approved','published')
    and ap.start_date <= (
      select start_date
      from public.academic_periods
      where id = requested_academic_period_id
    );

  cumulative_gpa :=
    case
      when cumulative_credits > 0
        then round(cumulative_qpoints / cumulative_credits,3)
      else null
    end;

  insert into public.student_period_results (
    institution_id,
    student_id,
    academic_period_id,
    attempted_credits,
    earned_credits,
    total_quality_points,
    gpa,
    cgpa,
    academic_standing,
    status,
    calculated_at
  )
  values (
    inst_id,
    requested_student_id,
    requested_academic_period_id,
    attempted,
    earned,
    qpoints,
    period_gpa,
    cumulative_gpa,
    case
      when cumulative_gpa is null then null
      when cumulative_gpa >= 3.50 then 'Excellent'
      when cumulative_gpa >= 3.00 then 'Good'
      when cumulative_gpa >= 2.00 then 'Satisfactory'
      when cumulative_gpa >= 1.00 then 'Probation'
      else 'Unsatisfactory'
    end,
    'calculated',
    now()
  )
  on conflict (student_id, academic_period_id)
  do update set
    attempted_credits = excluded.attempted_credits,
    earned_credits = excluded.earned_credits,
    total_quality_points = excluded.total_quality_points,
    gpa = excluded.gpa,
    cgpa = excluded.cgpa,
    academic_standing = excluded.academic_standing,
    status = 'calculated',
    calculated_at = now(),
    updated_at = now()
  returning id into result_id;

  return result_id;
end;
$$;

revoke all
on function public.calculate_student_period_gpa(uuid, uuid)
from public;

grant execute
on function public.calculate_student_period_gpa(uuid, uuid)
to authenticated;

-- ============================================================
-- SECTION 08L — RESULT STATUS HISTORY TRIGGER
-- ============================================================

create or replace function public.log_result_status_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.result_status is distinct from new.result_status then
    insert into public.result_approval_history (
      institution_id,
      course_result_id,
      old_status,
      new_status,
      action_by,
      action_at
    )
    values (
      new.institution_id,
      new.id,
      old.result_status,
      new.result_status,
      auth.uid(),
      now()
    );
  end if;

  return new;
end;
$$;

revoke all on function public.log_result_status_change() from public;

drop trigger if exists trg_result_status_history
on public.course_results;

create trigger trg_result_status_history
after update of result_status
on public.course_results
for each row
execute function public.log_result_status_change();

-- ============================================================
-- SECTION 08M — PERMISSIONS
-- ============================================================

insert into public.permissions (
  code,
  name,
  module,
  description
)
values
  ('assessments.view','View Assessments','results','View assessment structures and scores'),
  ('assessments.manage','Manage Assessments','results','Create assessments and enter scores'),
  ('grading.manage','Manage Grading','results','Manage grading schemes and grade bands')
on conflict (code)
do update set
  name = excluded.name,
  module = excluded.module,
  description = excluded.description;

-- Owner/Admin: full
insert into public.role_permissions (role_id,permission_id)
select r.id,p.id
from public.roles r
join public.institutions i on i.id=r.institution_id
join public.permissions p
  on p.code in ('assessments.view','assessments.manage','grading.manage')
where i.code='UNIMIS-DEMO-UNIV'
  and r.code in ('owner','admin')
on conflict do nothing;

-- Exam officer
insert into public.role_permissions (role_id,permission_id)
select r.id,p.id
from public.roles r
join public.institutions i on i.id=r.institution_id
join public.permissions p
  on p.code in ('assessments.view','assessments.manage','grading.manage')
where i.code='UNIMIS-DEMO-UNIV'
  and r.code='exam_officer'
on conflict do nothing;

-- Lecturer
insert into public.role_permissions (role_id,permission_id)
select r.id,p.id
from public.roles r
join public.institutions i on i.id=r.institution_id
join public.permissions p
  on p.code in ('assessments.view','assessments.manage')
where i.code='UNIMIS-DEMO-UNIV'
  and r.code='lecturer'
on conflict do nothing;

-- ============================================================
-- SECTION 08N — INDEXES
-- ============================================================

create index if not exists idx_grading_schemes_institution on public.grading_schemes(institution_id);
create index if not exists idx_grade_bands_scheme on public.grade_bands(grading_scheme_id);
create index if not exists idx_assessment_items_offering on public.assessment_items(course_offering_id);
create index if not exists idx_assessment_scores_item on public.assessment_scores(assessment_item_id);
create index if not exists idx_assessment_scores_student on public.assessment_scores(student_id);
create index if not exists idx_course_results_student on public.course_results(student_id);
create index if not exists idx_course_results_offering on public.course_results(course_offering_id);
create index if not exists idx_period_results_student on public.student_period_results(student_id);
create index if not exists idx_result_history_result on public.result_approval_history(course_result_id);

-- ============================================================
-- SECTION 08O — UPDATED_AT TRIGGERS
-- ============================================================

do $$
declare t text;
begin
  foreach t in array array[
    'grading_schemes',
    'assessment_items',
    'assessment_scores',
    'course_results',
    'student_period_results'
  ]
  loop
    execute format('drop trigger if exists trg_%I_updated_at on public.%I',t,t);
    execute format(
      'create trigger trg_%I_updated_at
       before update on public.%I
       for each row execute function public.set_updated_at()',t,t
    );
  end loop;
end $$;

-- ============================================================
-- SECTION 08P — ENABLE RLS
-- ============================================================

alter table public.grading_schemes enable row level security;
alter table public.grade_bands enable row level security;
alter table public.assessment_items enable row level security;
alter table public.assessment_scores enable row level security;
alter table public.course_results enable row level security;
alter table public.student_period_results enable row level security;
alter table public.result_approval_history enable row level security;

-- ============================================================
-- SECTION 08Q — RESULT/ASSESSMENT RLS
-- ============================================================

do $$
declare t text;
begin
  foreach t in array array[
    'grading_schemes',
    'grade_bands',
    'assessment_items',
    'assessment_scores',
    'course_results',
    'student_period_results',
    'result_approval_history'
  ]
  loop
    execute format(
      'drop policy if exists "Results viewers can view %s" on public.%I',t,t
    );

    execute format(
      'create policy "Results viewers can view %s"
       on public.%I
       for select to authenticated
       using (
         public.has_permission(institution_id,''results.view'')
         or public.has_permission(institution_id,''results.enter'')
         or public.has_permission(institution_id,''results.approve'')
         or public.has_permission(institution_id,''assessments.view'')
         or public.has_permission(institution_id,''assessments.manage'')
         or public.has_permission(institution_id,''grading.manage'')
       )',t,t
    );

    execute format(
      'drop policy if exists "Results managers can manage %s" on public.%I',t,t
    );

    execute format(
      'create policy "Results managers can manage %s"
       on public.%I
       for all to authenticated
       using (
         public.has_permission(institution_id,''results.enter'')
         or public.has_permission(institution_id,''results.approve'')
         or public.has_permission(institution_id,''assessments.manage'')
         or public.has_permission(institution_id,''grading.manage'')
       )
       with check (
         public.has_permission(institution_id,''results.enter'')
         or public.has_permission(institution_id,''results.approve'')
         or public.has_permission(institution_id,''assessments.manage'')
         or public.has_permission(institution_id,''grading.manage'')
       )',t,t
    );
  end loop;
end $$;

-- ============================================================
-- SECTION 08R — STUDENT SELF-SERVICE RESULTS
-- ============================================================

drop policy if exists "Students can view own course results"
on public.course_results;

create policy "Students can view own course results"
on public.course_results
for select
to authenticated
using (
  result_status = 'published'
  and exists (
    select 1 from public.students s
    where s.id = student_id
      and s.user_id = (select auth.uid())
  )
);

drop policy if exists "Students can view own period results"
on public.student_period_results;

create policy "Students can view own period results"
on public.student_period_results
for select
to authenticated
using (
  status = 'published'
  and exists (
    select 1 from public.students s
    where s.id = student_id
      and s.user_id = (select auth.uid())
  )
);

-- ============================================================
-- SECTION 08S — RESULT REPORT VIEW
-- ============================================================

create or replace view public.v_student_results
with (security_invoker = true)
as
select
  cr.id,
  cr.institution_id,
  cr.student_id,
  s.student_number,
  concat_ws(' ',s.first_name,s.middle_name,s.last_name) as student_name,
  ay.name as academic_year,
  ap.name as academic_period,
  c.code as course_code,
  c.name as course_name,
  c.credit_hours,
  cr.total_score,
  cr.letter_grade,
  cr.grade_point,
  cr.quality_points,
  cr.passed,
  cr.result_status
from public.course_results cr
join public.students s
  on s.id = cr.student_id
join public.course_offerings co
  on co.id = cr.course_offering_id
join public.courses c
  on c.id = co.course_id
join public.academic_years ay
  on ay.id = co.academic_year_id
join public.academic_periods ap
  on ap.id = co.academic_period_id;

-- ============================================================
-- SECTION 08T — VERIFY MODULE 08
-- ============================================================

select
  (select count(*) from public.grading_schemes) as grading_schemes,
  (select count(*) from public.grade_bands) as grade_bands,
  (select count(*) from public.assessment_items) as assessment_items,
  (select count(*) from public.assessment_scores) as assessment_scores,
  (select count(*) from public.course_results) as course_results,
  (select count(*) from public.student_period_results) as period_results;

-- ============================================================
-- END UNIMIS MODULE 08
-- ASSESSMENT, EXAMS, GRADES, GPA/CGPA & RESULTS
-- ============================================================
