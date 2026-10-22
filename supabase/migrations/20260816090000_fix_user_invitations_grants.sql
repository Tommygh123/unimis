-- UniMIS: Fix table privileges for User Management invitations
-- RLS policies already control which authenticated users may read/write rows.
-- This migration grants the underlying table privileges required before RLS is evaluated.

grant select, insert, update, delete
on table public.user_invitations
to authenticated;

-- Keep anonymous users from accessing invitation records.
revoke all
on table public.user_invitations
from anon;

-- Re-assert view access used by the User Management directory.
grant select
on table public.institution_user_directory
to authenticated;
