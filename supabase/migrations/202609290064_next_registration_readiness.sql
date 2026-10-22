
begin;

create or replace function public.unimis_next_registration_readiness(p_student_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
 v_inst uuid;
 v_student uuid;
 v_enrol record;
 v_next_year record;
 v_next_period record;
 v_offerings int:=0;
 v_courses jsonb:='[]'::jsonb;
begin
 v_inst:=public.unimis_progression_access();

 if p_student_id is null then
   select s.id into v_student from public.students s where s.user_id=auth.uid() limit 1;
 else
   if v_inst is null then raise exception 'Progression access required'; end if;
   v_student:=p_student_id;
 end if;

 if v_student is null then raise exception 'Student not found'; end if;

 select e.id,e.programme_id,e.current_level,p.code programme_code,p.name programme_name
 into v_enrol
 from public.student_programme_enrolments e
 join public.programmes p on p.id=e.programme_id
 where e.student_id=v_student and e.is_primary=true
 limit 1;

 if v_enrol.id is null then
   return jsonb_build_object('ready',false,'reason','No active primary programme enrolment');
 end if;

 -- Prefer the first academic year after the latest progression-reviewed year.
 select ay.* into v_next_year
 from public.academic_years ay
 where ay.institution_id=(select institution_id from public.students where id=v_student)
   and ay.start_date > coalesce((
      select max(y.start_date) from public.student_progression_reviews r
      join public.academic_years y on y.id=r.academic_year_id
      where r.student_id=v_student and r.decision='promoted'
   ),'-infinity'::date)
 order by ay.start_date
 limit 1;

 if v_next_year.id is null then
   return jsonb_build_object(
    'ready',false,'stage','academic_year',
    'current_level',v_enrol.current_level,'programme_code',v_enrol.programme_code,
    'reason','Next academic year has not been created yet'
   );
 end if;

 select ap.* into v_next_period
 from public.academic_periods ap
 where ap.academic_year_id=v_next_year.id
 order by ap.period_number
 limit 1;

 if v_next_period.id is null then
   return jsonb_build_object(
    'ready',false,'stage','semester','current_level',v_enrol.current_level,
    'next_academic_year',v_next_year.name,
    'reason','Semester 1 has not been created for the next academic year'
   );
 end if;

 select count(*),
   coalesce(jsonb_agg(jsonb_build_object(
     'course_code',c.code,'course_name',c.name,'credits',c.credit_hours,
     'section_code',co.section_code
   ) order by c.code),'[]'::jsonb)
 into v_offerings,v_courses
 from public.course_offerings co
 join public.courses c on c.id=co.course_id
 where co.academic_period_id=v_next_period.id
   and co.programme_id=v_enrol.programme_id
   and co.level_number=v_enrol.current_level;

 return jsonb_build_object(
   'ready',v_offerings>0,
   'stage',case when v_offerings>0 then 'ready' else 'offerings' end,
   'programme_code',v_enrol.programme_code,'programme_name',v_enrol.programme_name,
   'current_level',v_enrol.current_level,
   'next_academic_year_id',v_next_year.id,'next_academic_year',v_next_year.name,
   'next_period_id',v_next_period.id,'next_period',v_next_period.name,
   'offering_count',v_offerings,'courses',v_courses,
   'reason',case when v_offerings>0 then 'Ready for next-level registration'
                 else format('No Level %s course offerings have been created for %s',v_enrol.current_level,v_next_period.name) end
 );
end $$;

grant execute on function public.unimis_next_registration_readiness(uuid) to authenticated;
commit;
