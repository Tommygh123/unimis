-- ============================================================
-- UniMIS Academics browser/API grants
-- Fixes: permission denied for table academic_years
--
-- RLS policies still decide which rows/actions are allowed.
-- These grants provide the underlying PostgreSQL privileges
-- required before RLS can be evaluated.
-- ============================================================

grant usage on schema public to authenticated;

grant select, insert, update, delete
on table public.academic_years
to authenticated;

grant select, insert, update, delete
on table public.academic_periods
to authenticated;

grant select, insert, update, delete
on table public.faculties
to authenticated;

grant select, insert, update, delete
on table public.schools
to authenticated;

grant select, insert, update, delete
on table public.departments
to authenticated;

grant select, insert, update, delete
on table public.programmes
to authenticated;

grant select, insert, update, delete
on table public.courses
to authenticated;

grant select, insert, update, delete
on table public.programme_courses
to authenticated;

revoke all
on table public.academic_years,
         public.academic_periods,
         public.faculties,
         public.schools,
         public.departments,
         public.programmes,
         public.courses,
         public.programme_courses
from anon;

notify pgrst, 'reload schema';
