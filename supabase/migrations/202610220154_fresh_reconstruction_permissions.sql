-- Reapply previously skipped grants without changing RLS.
-- UniMIS fix: authenticated users need table-level SELECT privilege
-- on admission_offers before RLS / RPC policies can be evaluated.

grant select on table public.admission_offers to authenticated;

-- The approval workflow also reads application_reviews directly in the Admin UI.
grant select on table public.application_reviews to authenticated;

-- Keep anonymous users blocked.
revoke all on table public.admission_offers from anon;
revoke all on table public.application_reviews from anon;
