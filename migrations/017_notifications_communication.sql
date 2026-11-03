-- ============================================================
-- UNIMIS MODULE 15
-- NOTIFICATIONS & COMMUNICATION
-- 017_notifications_communication.sql
-- Run AFTER Module 14
-- ============================================================

-- ============================================================
-- SECTION 15A — ANNOUNCEMENTS
-- ============================================================

create table if not exists public.announcements (
  id uuid primary key default gen_random_uuid(),

  institution_id uuid not null
    references public.institutions(id)
    on delete cascade,

  title text not null,
  message text not null,

  audience_type text not null default 'all'
    check (
      audience_type in (
        'all',
        'students',
        'staff',
        'lecturers',
        'role',
        'department',
        'programme',
        'custom'
      )
    ),

  audience_filter jsonb not null default '{}'::jsonb,

  priority text not null default 'normal'
    check (
      priority in (
        'low',
        'normal',
        'high',
        'urgent'
      )
    ),

  publish_at timestamptz not null default now(),
  expires_at timestamptz,

  status text not null default 'published'
    check (
      status in (
        'draft',
        'scheduled',
        'published',
        'expired',
        'cancelled'
      )
    ),

  created_by uuid
    references auth.users(id)
    on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  check (
    expires_at is null
    or expires_at >= publish_at
  )
);


-- ============================================================
-- SECTION 15B — NOTIFICATIONS
-- ============================================================

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),

  institution_id uuid not null
    references public.institutions(id)
    on delete cascade,

  recipient_user_id uuid not null
    references auth.users(id)
    on delete cascade,

  title text not null,
  message text not null,

  notification_type text not null default 'info'
    check (
      notification_type in (
        'info',
        'success',
        'warning',
        'error',
        'reminder',
        'announcement',
        'finance',
        'academic',
        'attendance',
        'hr',
        'system'
      )
    ),

  related_entity_type text,
  related_entity_id uuid,

  action_url text,

  is_read boolean not null default false,

  read_at timestamptz,

  created_at timestamptz not null default now()
);


-- ============================================================
-- SECTION 15C — MESSAGE TEMPLATES
-- ============================================================

create table if not exists public.communication_templates (
  id uuid primary key default gen_random_uuid(),

  institution_id uuid not null
    references public.institutions(id)
    on delete cascade,

  name text not null,
  code text not null,

  channel text not null
    check (
      channel in (
        'email',
        'sms',
        'in_app',
        'whatsapp',
        'other'
      )
    ),

  subject_template text,
  body_template text not null,

  variables jsonb not null default '[]'::jsonb,

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
    code,
    channel
  )
);


-- ============================================================
-- SECTION 15D — OUTBOUND COMMUNICATION QUEUE
-- Actual sending can later use Edge Functions / external providers.
-- ============================================================

create table if not exists public.communication_queue (
  id uuid primary key default gen_random_uuid(),

  institution_id uuid not null
    references public.institutions(id)
    on delete cascade,

  recipient_user_id uuid
    references auth.users(id)
    on delete set null,

  recipient_address text not null,

  channel text not null
    check (
      channel in (
        'email',
        'sms',
        'in_app',
        'whatsapp',
        'other'
      )
    ),

  template_id uuid
    references public.communication_templates(id)
    on delete set null,

  subject text,
  body text not null,

  payload jsonb not null default '{}'::jsonb,

  status text not null default 'pending'
    check (
      status in (
        'pending',
        'processing',
        'sent',
        'failed',
        'cancelled'
      )
    ),

  scheduled_at timestamptz not null default now(),

  sent_at timestamptz,

  provider text,
  provider_message_id text,

  attempts integer not null default 0
    check (
      attempts >= 0
    ),

  last_error text,

  created_by uuid
    references auth.users(id)
    on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);


-- ============================================================
-- SECTION 15E — USER COMMUNICATION PREFERENCES
-- ============================================================

create table if not exists public.user_communication_preferences (
  id uuid primary key default gen_random_uuid(),

  institution_id uuid not null
    references public.institutions(id)
    on delete cascade,

  user_id uuid not null
    references auth.users(id)
    on delete cascade,

  email_enabled boolean not null default true,
  sms_enabled boolean not null default true,
  in_app_enabled boolean not null default true,
  whatsapp_enabled boolean not null default false,

  settings jsonb not null default '{}'::jsonb,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (
    institution_id,
    user_id
  )
);


-- ============================================================
-- SECTION 15F — COMMUNICATION PERMISSIONS
-- ============================================================

insert into public.permissions (
  code,
  name,
  module,
  description
)
values
  (
    'communications.view',
    'View Communications',
    'communications',
    'View announcements, notifications and communication logs'
  ),
  (
    'communications.manage',
    'Manage Communications',
    'communications',
    'Create and manage announcements, templates and queued messages'
  ),
  (
    'announcements.publish',
    'Publish Announcements',
    'communications',
    'Create and publish institution announcements'
  )
on conflict (code)
do update set
  name = excluded.name,
  module = excluded.module,
  description = excluded.description;


-- ============================================================
-- SECTION 15G — COMMUNICATIONS OFFICER ROLE
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
  'Communications Officer',
  'communications_officer',
  'Manages announcements and institution communications',
  false,
  true

from public.institutions i

where i.code = 'UNIMIS-DEMO-UNIV'

on conflict (
  institution_id,
  code
)

do update set
  name = excluded.name,
  description = excluded.description,
  is_active = true,
  updated_at = now();


-- ============================================================
-- SECTION 15H — ROLE PERMISSION ASSIGNMENTS
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
    'communications.view',
    'communications.manage',
    'announcements.publish'
  )
where i.code = 'UNIMIS-DEMO-UNIV'
  and r.code in ('owner','admin')
on conflict do nothing;


-- Communications Officer
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
    'communications.view',
    'communications.manage',
    'announcements.publish'
  )
where i.code = 'UNIMIS-DEMO-UNIV'
  and r.code = 'communications_officer'
on conflict do nothing;


-- Registrar can publish academic announcements
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
    'communications.view',
    'announcements.publish'
  )
where i.code = 'UNIMIS-DEMO-UNIV'
  and r.code = 'registrar'
on conflict do nothing;


-- ============================================================
-- SECTION 15I — MARK NOTIFICATION READ FUNCTION
-- ============================================================

create or replace function public.mark_notification_read(
  requested_notification_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin

  update public.notifications
  set
    is_read = true,
    read_at = now()
  where id = requested_notification_id
    and recipient_user_id = auth.uid();

end;
$$;


revoke all
on function public.mark_notification_read(uuid)
from public;


grant execute
on function public.mark_notification_read(uuid)
to authenticated;


-- ============================================================
-- SECTION 15J — INDEXES
-- ============================================================

create index if not exists idx_announcements_institution
on public.announcements(institution_id);

create index if not exists idx_announcements_status
on public.announcements(institution_id, status);

create index if not exists idx_notifications_user
on public.notifications(recipient_user_id);

create index if not exists idx_notifications_unread
on public.notifications(recipient_user_id, is_read);

create index if not exists idx_templates_institution
on public.communication_templates(institution_id);

create index if not exists idx_queue_institution
on public.communication_queue(institution_id);

create index if not exists idx_queue_status
on public.communication_queue(institution_id, status);

create index if not exists idx_user_comm_prefs_user
on public.user_communication_preferences(user_id);


-- ============================================================
-- SECTION 15K — UPDATED_AT TRIGGERS
-- ============================================================

do $$
declare
  t text;
begin

  foreach t in array array[
    'announcements',
    'communication_templates',
    'communication_queue',
    'user_communication_preferences'
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
-- SECTION 15L — ENABLE RLS
-- ============================================================

alter table public.announcements
enable row level security;

alter table public.notifications
enable row level security;

alter table public.communication_templates
enable row level security;

alter table public.communication_queue
enable row level security;

alter table public.user_communication_preferences
enable row level security;


-- ============================================================
-- SECTION 15M — COMMUNICATION STAFF RLS
-- ============================================================

do $$
declare
  t text;
begin

  foreach t in array array[
    'announcements',
    'communication_templates',
    'communication_queue'
  ]

  loop

    execute format(
      'drop policy if exists
       "Communication viewers can view %s"
       on public.%I',
      t, t
    );

    execute format(
      'create policy
       "Communication viewers can view %s"
       on public.%I
       for select
       to authenticated
       using (
         public.has_permission(
           institution_id,
           ''communications.view''
         )
         or public.has_permission(
           institution_id,
           ''communications.manage''
         )
         or public.has_permission(
           institution_id,
           ''announcements.publish''
         )
       )',
      t, t
    );

    execute format(
      'drop policy if exists
       "Communication managers can manage %s"
       on public.%I',
      t, t
    );

    execute format(
      'create policy
       "Communication managers can manage %s"
       on public.%I
       for all
       to authenticated
       using (
         public.has_permission(
           institution_id,
           ''communications.manage''
         )
         or public.has_permission(
           institution_id,
           ''announcements.publish''
         )
       )
       with check (
         public.has_permission(
           institution_id,
           ''communications.manage''
         )
         or public.has_permission(
           institution_id,
           ''announcements.publish''
         )
       )',
      t, t
    );

  end loop;

end $$;


-- ============================================================
-- SECTION 15N — USER NOTIFICATION SELF-SERVICE
-- ============================================================

drop policy if exists
"Users can view own notifications"
on public.notifications;

create policy
"Users can view own notifications"
on public.notifications
for select
to authenticated
using (
  recipient_user_id =
    (select auth.uid())
);


drop policy if exists
"Users can view own communication preferences"
on public.user_communication_preferences;

create policy
"Users can view own communication preferences"
on public.user_communication_preferences
for select
to authenticated
using (
  user_id =
    (select auth.uid())
);


drop policy if exists
"Users can update own communication preferences"
on public.user_communication_preferences;

create policy
"Users can update own communication preferences"
on public.user_communication_preferences
for update
to authenticated
using (
  user_id =
    (select auth.uid())
)
with check (
  user_id =
    (select auth.uid())
);


-- ============================================================
-- SECTION 15O — ANNOUNCEMENT FEED VIEW
-- ============================================================

create or replace view public.v_active_announcements
with (security_invoker = true)
as
select
  a.id,
  a.institution_id,
  a.title,
  a.message,
  a.audience_type,
  a.audience_filter,
  a.priority,
  a.publish_at,
  a.expires_at,
  a.created_by,
  a.created_at
from public.announcements a
where
  a.status = 'published'
  and a.publish_at <= now()
  and (
    a.expires_at is null
    or a.expires_at >= now()
  );


-- ============================================================
-- SECTION 15P — NOTIFICATION COUNTS VIEW
-- ============================================================

create or replace view public.v_user_notification_counts
with (security_invoker = true)
as
select
  n.institution_id,
  n.recipient_user_id,
  count(*) as total_notifications,
  count(*) filter (
    where n.is_read = false
  ) as unread_notifications
from public.notifications n
group by
  n.institution_id,
  n.recipient_user_id;


-- ============================================================
-- SECTION 15Q — VERIFY MODULE 15
-- ============================================================

select

  (
    select count(*)
    from public.announcements
  )
  as announcements,

  (
    select count(*)
    from public.notifications
  )
  as notifications,

  (
    select count(*)
    from public.communication_templates
  )
  as templates,

  (
    select count(*)
    from public.communication_queue
  )
  as queue_items;


-- ============================================================
-- END UNIMIS MODULE 15
-- NOTIFICATIONS & COMMUNICATION
-- ============================================================
