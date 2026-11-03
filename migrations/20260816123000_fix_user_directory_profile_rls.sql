-- ============================================================
-- UniMIS: User Management profile visibility fix
--
-- Problem:
-- institution_user_directory is SECURITY INVOKER, so the logged-in Admin
-- can only see profile rows allowed by profiles RLS. The existing policy
-- only allows users to see their own profile, which is why Dilys displays
-- correctly while other users appear as "Unnamed user".
--
-- Fix:
-- Add a SECURITY DEFINER helper and SELECT policy allowing users with
-- users.view permission for an institution to read profiles belonging to
-- that institution.
-- ============================================================

create or replace function public.can_view_user_profile(
  p_target_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    p_target_user_id = auth.uid()
    or exists (
      select 1
      from public.institution_users iu
      where iu.user_id = p_target_user_id
        and iu.status = 'active'
        and public.has_permission(
          iu.institution_id,
          'users.view'
        )
    );
$$;

revoke all
on function public.can_view_user_profile(uuid)
from public;

grant execute
on function public.can_view_user_profile(uuid)
to authenticated;


drop policy if exists
  "User managers can view institution profiles"
on public.profiles;

create policy
  "User managers can view institution profiles"
on public.profiles
for select
to authenticated
using (
  public.can_view_user_profile(id)
);

notify pgrst, 'reload schema';
