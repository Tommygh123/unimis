begin;

create table if not exists public.course_prerequisites (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null,
  programme_id uuid null references public.programmes(id) on delete cascade,
  course_id uuid not null references public.courses(id) on delete cascade,
  prerequisite_course_id uuid not null references public.courses(id) on delete cascade,
  min_letter_grade text null,
  is_mandatory boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint course_prerequisites_not_self check (course_id <> prerequisite_course_id)
);

create unique index if not exists uq_course_prerequisites_scope
on public.course_prerequisites(
  institution_id,
  coalesce(programme_id,'00000000-0000-0000-0000-000000000000'::uuid),
  course_id,
  prerequisite_course_id
);

alter table public.course_prerequisites enable row level security;

drop policy if exists "Members view course prerequisites" on public.course_prerequisites;
create policy "Members view course prerequisites"
on public.course_prerequisites for select to authenticated
using (
  public.has_permission(institution_id,'academics.view')
  or public.has_permission(institution_id,'academics.manage')
  or public.has_permission(institution_id,'students.view')
  or public.has_permission(institution_id,'students.manage')
  or exists(select 1 from public.students s where s.institution_id=course_prerequisites.institution_id and s.user_id=auth.uid())
);

drop policy if exists "Managers manage course prerequisites" on public.course_prerequisites;
create policy "Managers manage course prerequisites"
on public.course_prerequisites for all to authenticated
using (public.has_permission(institution_id,'academics.manage'))
with check (public.has_permission(institution_id,'academics.manage'));

insert into public.permissions(code,name,module,description)
values
 ('registrations.view','View Registrations','students','View student registration records'),
 ('registrations.manage','Manage Registrations','students','Manage student semester/course registrations'),
 ('registrations.approve','Approve Registrations','students','Approve or return submitted student registrations')
on conflict(code) do update set name=excluded.name,module=excluded.module,description=excluded.description;

insert into public.role_permissions(role_id,permission_id)
select r.id,p.id from public.roles r cross join public.permissions p
where r.code in ('admin','owner','registrar')
  and p.code in ('registrations.view','registrations.manage','registrations.approve')
  and not exists(select 1 from public.role_permissions rp where rp.role_id=r.id and rp.permission_id=p.id);

insert into public.role_permissions(role_id,permission_id)
select r.id,p.id from public.roles r cross join public.permissions p
where r.code='admissions_officer' and p.code='registrations.view'
  and not exists(select 1 from public.role_permissions rp where rp.role_id=r.id and rp.permission_id=p.id);

update public.institution_settings
set academic_settings = coalesce(academic_settings,'{}'::jsonb)
  || jsonb_build_object(
      'registration',
      coalesce(academic_settings->'registration','{}'::jsonb)
      || jsonb_build_object(
        'min_credits',coalesce((academic_settings->'registration'->>'min_credits')::numeric,0),
        'max_credits',coalesce((academic_settings->'registration'->>'max_credits')::numeric,24),
        'require_fee_clearance',coalesce((academic_settings->'registration'->>'require_fee_clearance')::boolean,false),
        'minimum_fee_percentage',coalesce((academic_settings->'registration'->>'minimum_fee_percentage')::numeric,0),
        'allow_late_registration',coalesce((academic_settings->'registration'->>'allow_late_registration')::boolean,false),
        'require_adviser_approval',coalesce((academic_settings->'registration'->>'require_adviser_approval')::boolean,true),
        'auto_select_required_courses',coalesce((academic_settings->'registration'->>'auto_select_required_courses')::boolean,true)
      )
  ), updated_at=now();

commit;
