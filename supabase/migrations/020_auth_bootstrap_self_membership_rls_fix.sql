-- ============================================================
-- UNIMIS
-- MIGRATION 020: AUTH BOOTSTRAP / SELF MEMBERSHIP RLS FIX
-- Purpose:
--   Allow an authenticated user to read their own institution_users
--   membership so the React portal can determine their role.
-- ============================================================

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

-- Keep the broader institution-member policy for administrators/officers.
-- PostgreSQL combines permissive SELECT policies with OR logic, so this
-- self policy only guarantees that a user can bootstrap their own role.

-- ============================================================
-- END MIGRATION 020
-- ============================================================
