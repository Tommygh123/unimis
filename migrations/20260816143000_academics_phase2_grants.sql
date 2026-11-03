-- ============================================================
-- UniMIS Academics Phase 2 API grants
--
-- Course Offerings / Lecturer Allocation / Timetable
-- Base PostgreSQL privileges only. Existing RLS still applies.
-- ============================================================

grant usage on schema public to authenticated;

grant select, insert, update, delete
on table public.course_offerings
to authenticated;

grant select, insert, update, delete
on table public.course_lecturers
to authenticated;

grant select, insert, update, delete
on table public.course_schedules
to authenticated;

grant select
on table public.lecturer_profiles
to authenticated;

grant select
on table public.staff
to authenticated;

revoke all
on table public.course_offerings,
         public.course_lecturers,
         public.course_schedules,
         public.lecturer_profiles,
         public.staff
from anon;

notify pgrst, 'reload schema';
