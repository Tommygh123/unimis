-- ============================================================
-- UNIMIS
-- AUTH API GRANTS + SELF-BOOTSTRAP POLICIES
-- Reconciled timestamped migration.
-- Safe to apply after existing User Management migrations.
-- ============================================================

grant usage on schema public to authenticated;

grant select on table public.profiles to authenticated;
grant select on table public.institution_users to authenticated;
grant select on table public.roles to authenticated;

alter table public.profiles enable row level security;

drop policy if exists "Users can view own profile"
on public.profiles;

create policy "Users can view own profile"
on public.profiles
for select
to authenticated
using (
  id = (select auth.uid())
);

alter table public.institution_users enable row level security;

drop policy if exists "Users can view own institution membership"
on public.institution_users;

create policy "Users can view own institution membership"
on public.institution_users
for select
to authenticated
using (
  user_id = (select auth.uid())
);

alter table public.roles enable row level security;

drop policy if exists "Authenticated users can view active roles"
on public.roles;

create policy "Authenticated users can view active roles"
on public.roles
for select
to authenticated
using (
  is_active = true
);

notify pgrst, 'reload schema';
