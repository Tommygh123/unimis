-- ============================================================
-- UNIMIS MODULE 16
-- AUDIT LOGS, SYSTEM SETTINGS & FINAL SECURITY UTILITIES
-- 018_audit_system_settings.sql
-- Run AFTER Module 15
-- ============================================================

-- ============================================================
-- SECTION 16A — INSTITUTION SYSTEM SETTINGS
-- ============================================================

create table if not exists public.institution_system_settings (
  id uuid primary key default gen_random_uuid(),

  institution_id uuid not null
    references public.institutions(id)
    on delete cascade,

  setting_key text not null,

  setting_value jsonb not null default '{}'::jsonb,

  category text not null default 'general',

  description text,

  is_public boolean not null default false,

  created_by uuid
    references auth.users(id)
    on delete set null,

  updated_by uuid
    references auth.users(id)
    on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (
    institution_id,
    setting_key
  )
);


-- ============================================================
-- SECTION 16B — SYSTEM AUDIT LOG
-- ============================================================

create table if not exists public.audit_logs (
  id uuid primary key default gen_random_uuid(),

  institution_id uuid
    references public.institutions(id)
    on delete set null,

  user_id uuid
    references auth.users(id)
    on delete set null,

  action text not null,

  entity_type text,

  entity_id uuid,

  old_data jsonb,

  new_data jsonb,

  metadata jsonb not null default '{}'::jsonb,

  ip_address inet,

  user_agent text,

  created_at timestamptz not null default now()
);


-- ============================================================
-- SECTION 16C — LOGIN / SECURITY EVENTS
-- ============================================================

create table if not exists public.security_events (
  id uuid primary key default gen_random_uuid(),

  institution_id uuid
    references public.institutions(id)
    on delete set null,

  user_id uuid
    references auth.users(id)
    on delete set null,

  event_type text not null
    check (
      event_type in (
        'login_success',
        'login_failure',
        'logout',
        'password_reset',
        'password_changed',
        'email_changed',
        'role_changed',
        'permission_changed',
        'account_locked',
        'account_unlocked',
        'other'
      )
    ),

  event_details jsonb not null default '{}'::jsonb,

  ip_address inet,

  user_agent text,

  created_at timestamptz not null default now()
);


-- ============================================================
-- SECTION 16D — MODULE CONFIGURATION
-- Controls which modules are enabled for an institution.
-- ============================================================

create table if not exists public.institution_modules (
  id uuid primary key default gen_random_uuid(),

  institution_id uuid not null
    references public.institutions(id)
    on delete cascade,

  module_code text not null,

  module_name text not null,

  is_enabled boolean not null default true,

  settings jsonb not null default '{}'::jsonb,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (
    institution_id,
    module_code
  )
);


-- ============================================================
-- SECTION 16E — FEATURE FLAGS
-- ============================================================

create table if not exists public.feature_flags (
  id uuid primary key default gen_random_uuid(),

  institution_id uuid not null
    references public.institutions(id)
    on delete cascade,

  feature_code text not null,

  is_enabled boolean not null default false,

  config jsonb not null default '{}'::jsonb,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (
    institution_id,
    feature_code
  )
);


-- ============================================================
-- SECTION 16F — SYSTEM PERMISSIONS
-- ============================================================

insert into public.permissions (
  code,
  name,
  module,
  description
)
values
  (
    'settings.view',
    'View System Settings',
    'system',
    'View institution system settings'
  ),
  (
    'settings.manage',
    'Manage System Settings',
    'system',
    'Manage institution system settings and module configuration'
  ),
  (
    'audit.view',
    'View Audit Logs',
    'system',
    'View system audit and security logs'
  ),
  (
    'security.manage',
    'Manage Security',
    'system',
    'Manage security-related configuration and administrative controls'
  )
on conflict (code)
do update set
  name = excluded.name,
  module = excluded.module,
  description = excluded.description;


-- ============================================================
-- SECTION 16G — OWNER / ADMIN PERMISSIONS
-- ============================================================

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
    'settings.view',
    'settings.manage',
    'audit.view',
    'security.manage'
  )
where i.code = 'UNIMIS-DEMO-UNIV'
  and r.code in (
    'owner',
    'admin'
  )
on conflict do nothing;


-- ============================================================
-- SECTION 16H — INDEXES
-- ============================================================

create index if not exists idx_institution_system_settings_institution
on public.institution_system_settings(institution_id);

create index if not exists idx_audit_logs_institution
on public.audit_logs(institution_id);

create index if not exists idx_audit_logs_user
on public.audit_logs(user_id);

create index if not exists idx_audit_logs_entity
on public.audit_logs(entity_type, entity_id);

create index if not exists idx_audit_logs_created_at
on public.audit_logs(created_at desc);

create index if not exists idx_security_events_institution
on public.security_events(institution_id);

create index if not exists idx_security_events_user
on public.security_events(user_id);

create index if not exists idx_security_events_type
on public.security_events(event_type);

create index if not exists idx_security_events_created_at
on public.security_events(created_at desc);

create index if not exists idx_institution_modules_institution
on public.institution_modules(institution_id);

create index if not exists idx_feature_flags_institution
on public.feature_flags(institution_id);


-- ============================================================
-- SECTION 16I — UPDATED_AT TRIGGERS
-- ============================================================

do $$
declare
  t text;
begin

  foreach t in array array[
    'institution_system_settings',
    'institution_modules',
    'feature_flags'
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
-- SECTION 16J — AUDIT LOG HELPER FUNCTION
-- ============================================================

create or replace function public.write_audit_log(
  requested_institution_id uuid,
  requested_action text,
  requested_entity_type text default null,
  requested_entity_id uuid default null,
  requested_old_data jsonb default null,
  requested_new_data jsonb default null,
  requested_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  log_id uuid;
begin

  if requested_institution_id is not null then
    if not public.is_institution_member(requested_institution_id) then
      raise exception 'Not authorised';
    end if;
  end if;

  insert into public.audit_logs (
    institution_id,
    user_id,
    action,
    entity_type,
    entity_id,
    old_data,
    new_data,
    metadata
  )
  values (
    requested_institution_id,
    auth.uid(),
    requested_action,
    requested_entity_type,
    requested_entity_id,
    requested_old_data,
    requested_new_data,
    coalesce(requested_metadata, '{}'::jsonb)
  )
  returning id into log_id;

  return log_id;

end;
$$;


revoke all
on function public.write_audit_log(
  uuid,
  text,
  text,
  uuid,
  jsonb,
  jsonb,
  jsonb
)
from public;


grant execute
on function public.write_audit_log(
  uuid,
  text,
  text,
  uuid,
  jsonb,
  jsonb,
  jsonb
)
to authenticated;


-- ============================================================
-- SECTION 16K — SECURITY EVENT HELPER FUNCTION
-- ============================================================

create or replace function public.write_security_event(
  requested_institution_id uuid,
  requested_event_type text,
  requested_event_details jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  event_id uuid;
begin

  insert into public.security_events (
    institution_id,
    user_id,
    event_type,
    event_details
  )
  values (
    requested_institution_id,
    auth.uid(),
    requested_event_type,
    coalesce(requested_event_details, '{}'::jsonb)
  )
  returning id into event_id;

  return event_id;

end;
$$;


revoke all
on function public.write_security_event(
  uuid,
  text,
  jsonb
)
from public;


grant execute
on function public.write_security_event(
  uuid,
  text,
  jsonb
)
to authenticated;


-- ============================================================
-- SECTION 16L — ENABLE RLS
-- ============================================================

alter table public.institution_system_settings
enable row level security;

alter table public.audit_logs
enable row level security;

alter table public.security_events
enable row level security;

alter table public.institution_modules
enable row level security;

alter table public.feature_flags
enable row level security;


-- ============================================================
-- SECTION 16M — SETTINGS RLS
-- ============================================================

do $$
declare
  t text;
begin

  foreach t in array array[
    'institution_system_settings',
    'institution_modules',
    'feature_flags'
  ]

  loop

    execute format(
      'drop policy if exists
       "Settings viewers can view %s"
       on public.%I',
      t,
      t
    );

    execute format(
      'create policy
       "Settings viewers can view %s"
       on public.%I
       for select
       to authenticated
       using (
         public.has_permission(
           institution_id,
           ''settings.view''
         )
         or public.has_permission(
           institution_id,
           ''settings.manage''
         )
       )',
      t,
      t
    );

    execute format(
      'drop policy if exists
       "Settings managers can manage %s"
       on public.%I',
      t,
      t
    );

    execute format(
      'create policy
       "Settings managers can manage %s"
       on public.%I
       for all
       to authenticated
       using (
         public.has_permission(
           institution_id,
           ''settings.manage''
         )
       )
       with check (
         public.has_permission(
           institution_id,
           ''settings.manage''
         )
       )',
      t,
      t
    );

  end loop;

end $$;


-- ============================================================
-- SECTION 16N — AUDIT / SECURITY LOG RLS
-- ============================================================

drop policy if exists
"Audit viewers can view logs"
on public.audit_logs;

create policy
"Audit viewers can view logs"
on public.audit_logs
for select
to authenticated
using (
  institution_id is not null
  and (
    public.has_permission(
      institution_id,
      'audit.view'
    )
    or public.has_permission(
      institution_id,
      'security.manage'
    )
  )
);


drop policy if exists
"Security viewers can view events"
on public.security_events;

create policy
"Security viewers can view events"
on public.security_events
for select
to authenticated
using (
  institution_id is not null
  and (
    public.has_permission(
      institution_id,
      'audit.view'
    )
    or public.has_permission(
      institution_id,
      'security.manage'
    )
  )
);


-- ============================================================
-- SECTION 16O — PUBLIC SETTINGS VIEW
-- Only settings explicitly marked public are exposed.
-- ============================================================

create or replace view public.v_public_institution_system_settings
with (security_invoker = true)
as
select
  institution_id,
  setting_key,
  setting_value,
  category
from public.institution_system_settings
where is_public = true;


-- ============================================================
-- SECTION 16P — DEFAULT MODULE CONFIGURATION FOR DEMO UNIVERSITY
-- ============================================================

insert into public.institution_modules (
  institution_id,
  module_code,
  module_name,
  is_enabled
)
select
  i.id,
  m.module_code,
  m.module_name,
  true
from public.institutions i
cross join (
  values
    ('admissions', 'Admissions'),
    ('students', 'Student Management'),
    ('academics', 'Academic Management'),
    ('registration', 'Course Registration'),
    ('results', 'Assessment & Results'),
    ('finance', 'Finance'),
    ('attendance', 'Attendance'),
    ('library', 'Library'),
    ('accommodation', 'Accommodation'),
    ('hr', 'Human Resources'),
    ('payroll', 'Payroll'),
    ('communications', 'Communications')
) as m(module_code, module_name)
where i.code = 'UNIMIS-DEMO-UNIV'
on conflict (
  institution_id,
  module_code
)
do update set
  module_name = excluded.module_name,
  is_enabled = excluded.is_enabled,
  updated_at = now();


-- ============================================================
-- SECTION 16Q — DEFAULT GENERAL SETTINGS
-- ============================================================

insert into public.institution_system_settings (
  institution_id,
  setting_key,
  setting_value,
  category,
  description,
  is_public
)
select
  i.id,
  x.setting_key,
  x.setting_value,
  x.category,
  x.description,
  x.is_public
from public.institutions i
cross join (
  values
    (
      'portal_name',
      to_jsonb('UniMIS Portal'::text),
      'branding',
      'Portal display name',
      true
    ),
    (
      'default_currency',
      to_jsonb('GHS'::text),
      'finance',
      'Default institution currency',
      false
    ),
    (
      'default_country',
      to_jsonb('Ghana'::text),
      'general',
      'Default country',
      true
    ),
    (
      'timezone',
      to_jsonb('Africa/Accra'::text),
      'general',
      'Institution timezone',
      false
    )
) as x(
  setting_key,
  setting_value,
  category,
  description,
  is_public
)
where i.code = 'UNIMIS-DEMO-UNIV'
on conflict (
  institution_id,
  setting_key
)
do update set
  setting_value = excluded.setting_value,
  category = excluded.category,
  description = excluded.description,
  is_public = excluded.is_public,
  updated_at = now();


-- ============================================================
-- SECTION 16R — FINAL FOUNDATION VERIFICATION
-- ============================================================

select
  (
    select count(*)
    from public.institution_system_settings
  ) as institution_system_settings,

  (
    select count(*)
    from public.institution_modules
  ) as institution_modules,

  (
    select count(*)
    from public.feature_flags
  ) as feature_flags,

  (
    select count(*)
    from public.audit_logs
  ) as audit_logs,

  (
    select count(*)
    from public.security_events
  ) as security_events;


-- ============================================================
-- END UNIMIS MODULE 16
-- AUDIT LOGS, SYSTEM SETTINGS & FINAL SECURITY UTILITIES
-- ============================================================
