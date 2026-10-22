-- ============================================================
-- UNIMIS
-- USER MANAGEMENT EDGE-INVITE AUTHORIZATION HELPER
-- ============================================================

create or replace function public.can_manage_users(
  p_institution_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.has_permission(
    p_institution_id,
    'users.manage'
  );
$$;

revoke all
on function public.can_manage_users(uuid)
from public;

grant execute
on function public.can_manage_users(uuid)
to authenticated;

notify pgrst, 'reload schema';
