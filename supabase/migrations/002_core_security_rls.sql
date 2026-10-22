-- ============================================================
-- UNIMIS
-- MODULE 01B: CORE SECURITY / RLS HELPERS
-- Run AFTER 001_core_foundation.sql
-- ============================================================

create or replace function public.is_institution_member(requested_institution_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.institution_users iu
    where iu.institution_id = requested_institution_id
      and iu.user_id = auth.uid()
      and iu.status = 'active'
  );
$$;

create or replace function public.has_permission(
  requested_institution_id uuid,
  requested_permission_code text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.institution_users iu
    join public.roles r on r.id = iu.role_id
    join public.role_permissions rp on rp.role_id = r.id
    join public.permissions p on p.id = rp.permission_id
    where iu.institution_id = requested_institution_id
      and iu.user_id = auth.uid()
      and iu.status = 'active'
      and r.is_active = true
      and p.code = requested_permission_code
  );
$$;

revoke all on function public.is_institution_member(uuid) from public;
revoke all on function public.has_permission(uuid,text) from public;
grant execute on function public.is_institution_member(uuid) to authenticated;
grant execute on function public.has_permission(uuid,text) to authenticated;

alter table public.institutions enable row level security;
alter table public.profiles enable row level security;
alter table public.roles enable row level security;
alter table public.permissions enable row level security;
alter table public.role_permissions enable row level security;
alter table public.institution_users enable row level security;
alter table public.institution_features enable row level security;
alter table public.institution_settings enable row level security;

drop policy if exists "Members can view their institution" on public.institutions;
create policy "Members can view their institution"
on public.institutions for select to authenticated
using (public.is_institution_member(id));

drop policy if exists "Users can view own profile" on public.profiles;
create policy "Users can view own profile"
on public.profiles for select to authenticated
using (id = auth.uid());

drop policy if exists "Users can update own profile" on public.profiles;
create policy "Users can update own profile"
on public.profiles for update to authenticated
using (id = auth.uid()) with check (id = auth.uid());

drop policy if exists "Members can view institution users" on public.institution_users;
create policy "Members can view institution users"
on public.institution_users for select to authenticated
using (public.is_institution_member(institution_id));

drop policy if exists "User managers can manage institution users" on public.institution_users;
create policy "User managers can manage institution users"
on public.institution_users for all to authenticated
using (public.has_permission(institution_id,'users.manage'))
with check (public.has_permission(institution_id,'users.manage'));

drop policy if exists "Members can view roles" on public.roles;
create policy "Members can view roles"
on public.roles for select to authenticated
using (institution_id is null or public.is_institution_member(institution_id));

drop policy if exists "Role managers can manage roles" on public.roles;
create policy "Role managers can manage roles"
on public.roles for all to authenticated
using (institution_id is not null and public.has_permission(institution_id,'roles.manage'))
with check (institution_id is not null and public.has_permission(institution_id,'roles.manage'));

drop policy if exists "Authenticated users can view permissions" on public.permissions;
create policy "Authenticated users can view permissions"
on public.permissions for select to authenticated using (true);

drop policy if exists "Members can view role permissions" on public.role_permissions;
create policy "Members can view role permissions"
on public.role_permissions for select to authenticated
using (exists (
  select 1 from public.roles r
  where r.id = role_id
    and (r.institution_id is null or public.is_institution_member(r.institution_id))
));

drop policy if exists "Role managers can manage role permissions" on public.role_permissions;
create policy "Role managers can manage role permissions"
on public.role_permissions for all to authenticated
using (exists (
  select 1 from public.roles r
  where r.id = role_id
    and r.institution_id is not null
    and public.has_permission(r.institution_id,'roles.manage')
))
with check (exists (
  select 1 from public.roles r
  where r.id = role_id
    and r.institution_id is not null
    and public.has_permission(r.institution_id,'roles.manage')
));

drop policy if exists "Members can view institution features" on public.institution_features;
create policy "Members can view institution features"
on public.institution_features for select to authenticated
using (public.is_institution_member(institution_id));

drop policy if exists "Institution managers can manage institution features" on public.institution_features;
create policy "Institution managers can manage institution features"
on public.institution_features for all to authenticated
using (public.has_permission(institution_id,'institution.manage'))
with check (public.has_permission(institution_id,'institution.manage'));

drop policy if exists "Members can view institution settings" on public.institution_settings;
create policy "Members can view institution settings"
on public.institution_settings for select to authenticated
using (public.is_institution_member(institution_id));

drop policy if exists "Institution managers can manage institution settings" on public.institution_settings;
create policy "Institution managers can manage institution settings"
on public.institution_settings for all to authenticated
using (public.has_permission(institution_id,'institution.manage'))
with check (public.has_permission(institution_id,'institution.manage'));

-- END MODULE 01B
