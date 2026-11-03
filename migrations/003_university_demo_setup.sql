-- ============================================================
-- UNIVERSAL EDUCATION MIS
-- MODULE 01C: UNIVERSITY DEMO SETUP
-- Run AFTER:
--   001_core_foundation.sql
--   002_core_security_rls.sql
-- ============================================================

-- ------------------------------------------------------------
-- 1. CREATE / UPDATE DEMO UNIVERSITY
-- You can later change the name, code, logo, colours and domain.
-- ------------------------------------------------------------

insert into public.institutions (
  name,
  short_name,
  code,
  institution_type,
  status,
  country,
  region,
  city,
  currency_code,
  timezone
)
values (
  'UniMIS Demo University',
  'UDU',
  'UNIMIS-DEMO-UNIV',
  'university',
  'active',
  'Ghana',
  'Ashanti',
  'Kumasi',
  'GHS',
  'Africa/Accra'
)
on conflict (code)
do update set
  name = excluded.name,
  short_name = excluded.short_name,
  institution_type = excluded.institution_type,
  status = excluded.status,
  country = excluded.country,
  region = excluded.region,
  city = excluded.city,
  currency_code = excluded.currency_code,
  timezone = excluded.timezone,
  updated_at = now();


-- ------------------------------------------------------------
-- 2. UNIVERSITY BRANDING / SETTINGS
-- ------------------------------------------------------------

insert into public.institution_settings (
  institution_id,
  primary_color,
  secondary_color,
  login_title,
  portal_name,
  academic_settings,
  branding_settings,
  communication_settings
)
select
  i.id,
  '#123B72',
  '#D4AF37',
  'University Management Information System',
  'UniMIS Portal',
  jsonb_build_object(
    'academic_structure', 'semester',
    'default_semesters_per_year', 2,
    'grading_mode', 'gpa_cgpa',
    'course_registration_required', true
  ),
  jsonb_build_object(
    'show_logo', true,
    'show_institution_name', true,
    'enable_public_website', true
  ),
  jsonb_build_object(
    'email_enabled', false,
    'sms_enabled', false
  )
from public.institutions i
where i.code = 'UNIMIS-DEMO-UNIV'
on conflict (institution_id)
do update set
  primary_color = excluded.primary_color,
  secondary_color = excluded.secondary_color,
  login_title = excluded.login_title,
  portal_name = excluded.portal_name,
  academic_settings = excluded.academic_settings,
  branding_settings = excluded.branding_settings,
  communication_settings = excluded.communication_settings,
  updated_at = now();


-- ------------------------------------------------------------
-- 3. STANDARD UNIVERSITY ROLES
-- ------------------------------------------------------------

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
  r.name,
  r.code,
  r.description,
  false,
  true
from public.institutions i
cross join (
  values
    ('Owner',               'owner',              'Institution owner / highest-level administrator'),
    ('Administrator',       'admin',              'General system administrator'),
    ('Registrar',           'registrar',          'Academic administration and student records'),
    ('Admissions Officer',  'admissions_officer', 'Applicant and admissions management'),
    ('Finance Officer',     'finance_officer',    'Fees, billing and payment management'),
    ('Examinations Officer','exam_officer',       'Assessment, examination and results management'),
    ('Lecturer',            'lecturer',           'Teaching, attendance and assessment entry'),
    ('Student',             'student',            'Student self-service portal')
) as r(name, code, description)
where i.code = 'UNIMIS-DEMO-UNIV'
on conflict (institution_id, code)
do update set
  name = excluded.name,
  description = excluded.description,
  is_active = true,
  updated_at = now();


-- ------------------------------------------------------------
-- 4. CORE PERMISSION CATALOGUE
-- ------------------------------------------------------------

insert into public.permissions (code, name, module, description)
values
  ('institution.view',        'View Institution',         'core',       'View institution profile and configuration'),
  ('institution.manage',      'Manage Institution',       'core',       'Edit institution profile and configuration'),

  ('users.view',              'View Users',               'core',       'View institution users'),
  ('users.manage',            'Manage Users',             'core',       'Create, update and manage institution users'),
  ('roles.view',              'View Roles',               'core',       'View roles and permissions'),
  ('roles.manage',            'Manage Roles',             'core',       'Manage roles and role permissions'),

  ('admissions.view',         'View Admissions',          'admissions', 'View applicants and applications'),
  ('admissions.manage',       'Manage Admissions',        'admissions', 'Manage applications and admissions decisions'),

  ('students.view',           'View Students',            'students',   'View student records'),
  ('students.manage',         'Manage Students',          'students',   'Create and update student records'),

  ('academics.view',          'View Academics',           'academics',  'View academic structures and offerings'),
  ('academics.manage',        'Manage Academics',         'academics',  'Manage academic structures and offerings'),

  ('courses.view',            'View Courses',             'academics',  'View courses and course offerings'),
  ('courses.manage',          'Manage Courses',           'academics',  'Manage courses and course offerings'),

  ('registration.view',       'View Registrations',       'academics',  'View course registrations'),
  ('registration.manage',     'Manage Registrations',     'academics',  'Manage course registrations'),

  ('results.view',            'View Results',             'results',    'View permitted academic results'),
  ('results.enter',           'Enter Results',            'results',    'Enter assessment and examination marks'),
  ('results.approve',         'Approve Results',          'results',    'Approve and publish results'),

  ('finance.view',            'View Finance',             'finance',    'View fees, invoices and payments'),
  ('finance.manage',          'Manage Finance',           'finance',    'Manage fees, invoices and payments'),

  ('reports.view',            'View Reports',             'reports',    'View institution reports'),
  ('website.manage',          'Manage Website',           'website',    'Manage public website content')
on conflict (code)
do update set
  name = excluded.name,
  module = excluded.module,
  description = excluded.description;


-- ------------------------------------------------------------
-- 5. ASSIGN ALL CORE PERMISSIONS TO OWNER
-- ------------------------------------------------------------

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.institutions i
  on i.id = r.institution_id
cross join public.permissions p
where i.code = 'UNIMIS-DEMO-UNIV'
  and r.code = 'owner'
on conflict do nothing;


-- ------------------------------------------------------------
-- 6. ASSIGN BROAD PERMISSIONS TO ADMIN
-- ------------------------------------------------------------

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.institutions i
  on i.id = r.institution_id
join public.permissions p
  on p.code in (
    'institution.view',
    'users.view',
    'users.manage',
    'roles.view',
    'roles.manage',
    'admissions.view',
    'admissions.manage',
    'students.view',
    'students.manage',
    'academics.view',
    'academics.manage',
    'courses.view',
    'courses.manage',
    'registration.view',
    'registration.manage',
    'results.view',
    'results.enter',
    'results.approve',
    'finance.view',
    'finance.manage',
    'reports.view',
    'website.manage'
  )
where i.code = 'UNIMIS-DEMO-UNIV'
  and r.code = 'admin'
on conflict do nothing;


-- ------------------------------------------------------------
-- 7. ROLE-SPECIFIC PERMISSIONS
-- ------------------------------------------------------------

-- Registrar
insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.institutions i on i.id = r.institution_id
join public.permissions p on p.code in (
  'students.view','students.manage',
  'academics.view','academics.manage',
  'courses.view',
  'registration.view','registration.manage',
  'results.view',
  'reports.view'
)
where i.code = 'UNIMIS-DEMO-UNIV'
  and r.code = 'registrar'
on conflict do nothing;

-- Admissions Officer
insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.institutions i on i.id = r.institution_id
join public.permissions p on p.code in (
  'admissions.view','admissions.manage',
  'students.view',
  'reports.view'
)
where i.code = 'UNIMIS-DEMO-UNIV'
  and r.code = 'admissions_officer'
on conflict do nothing;

-- Finance Officer
insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.institutions i on i.id = r.institution_id
join public.permissions p on p.code in (
  'students.view',
  'finance.view','finance.manage',
  'reports.view'
)
where i.code = 'UNIMIS-DEMO-UNIV'
  and r.code = 'finance_officer'
on conflict do nothing;

-- Examinations Officer
insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.institutions i on i.id = r.institution_id
join public.permissions p on p.code in (
  'students.view',
  'academics.view',
  'courses.view',
  'registration.view',
  'results.view','results.enter','results.approve',
  'reports.view'
)
where i.code = 'UNIMIS-DEMO-UNIV'
  and r.code = 'exam_officer'
on conflict do nothing;

-- Lecturer
insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.institutions i on i.id = r.institution_id
join public.permissions p on p.code in (
  'students.view',
  'academics.view',
  'courses.view',
  'registration.view',
  'results.view',
  'results.enter'
)
where i.code = 'UNIMIS-DEMO-UNIV'
  and r.code = 'lecturer'
on conflict do nothing;

-- Student
insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.institutions i on i.id = r.institution_id
join public.permissions p on p.code in (
  'academics.view',
  'courses.view',
  'registration.view',
  'results.view',
  'finance.view'
)
where i.code = 'UNIMIS-DEMO-UNIV'
  and r.code = 'student'
on conflict do nothing;


-- ------------------------------------------------------------
-- 8. ENABLE UNIVERSITY FEATURES
-- ------------------------------------------------------------

insert into public.institution_features (
  institution_id,
  feature_code,
  enabled,
  settings
)
select
  i.id,
  f.feature_code,
  true,
  f.settings
from public.institutions i
cross join (
  values
    ('public_website',       '{}'::jsonb),
    ('admissions',           '{}'::jsonb),
    ('student_management',   '{}'::jsonb),
    ('staff_management',     '{}'::jsonb),
    ('faculties',            '{}'::jsonb),
    ('departments',          '{}'::jsonb),
    ('programmes',           '{}'::jsonb),
    ('courses',              '{}'::jsonb),
    ('course_registration',  '{}'::jsonb),
    ('attendance',           '{}'::jsonb),
    ('assessments',          '{}'::jsonb),
    ('examinations',         '{}'::jsonb),
    ('gpa_cgpa',             '{"scale":4.0}'::jsonb),
    ('transcripts',          '{}'::jsonb),
    ('finance',              '{}'::jsonb),
    ('reports',              '{}'::jsonb),
    ('notifications',        '{}'::jsonb),
    ('audit_logs',           '{}'::jsonb)
) as f(feature_code, settings)
where i.code = 'UNIMIS-DEMO-UNIV'
on conflict (institution_id, feature_code)
do update set
  enabled = excluded.enabled,
  settings = excluded.settings,
  updated_at = now();


-- ============================================================
-- 9. QUICK VERIFICATION
-- ============================================================

select
  i.name,
  i.code,
  i.institution_type,
  count(distinct r.id) as roles,
  count(distinct f.id) as enabled_features
from public.institutions i
left join public.roles r
  on r.institution_id = i.id
left join public.institution_features f
  on f.institution_id = i.id
 and f.enabled = true
where i.code = 'UNIMIS-DEMO-UNIV'
group by i.id, i.name, i.code, i.institution_type;