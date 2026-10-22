-- UniMIS: allow the same course to have distinct offerings for different
-- programmes/sections in the same academic period.
begin;

do $$
declare
  r record;
begin
  for r in
    select c.conname
    from pg_constraint c
    join pg_class t on t.oid=c.conrelid
    join pg_namespace n on n.oid=t.relnamespace
    where n.nspname='public'
      and t.relname='course_offerings'
      and c.contype='u'
      and pg_get_constraintdef(c.oid) ilike '%institution_id%'
      and pg_get_constraintdef(c.oid) ilike '%course_id%'
      and pg_get_constraintdef(c.oid) ilike '%academic_period_id%'
      and pg_get_constraintdef(c.oid) not ilike '%programme_id%'
  loop
    execute format('alter table public.course_offerings drop constraint %I',r.conname);
  end loop;
end $$;

-- Programme-specific offerings are unique by institution/course/period/programme/section.
-- NULL programme means an institution-wide/shared offering.
create unique index if not exists uq_course_offerings_period_programme_section
on public.course_offerings(
  institution_id,
  course_id,
  academic_period_id,
  coalesce(programme_id,'00000000-0000-0000-0000-000000000000'::uuid),
  section_code
);

commit;
