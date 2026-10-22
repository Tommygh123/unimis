create or replace function public.unimis_attendance_students142(p_filters jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare inst uuid:=public.unimis_reporting_access();rows jsonb;
begin
 if inst is null then raise exception 'Academic reporting access required';end if;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.academic_year,x.semester,x.student_number,x.course_code),'[]'::jsonb) into rows from (
 select s.student_number,concat_ws(' ',s.first_name,s.middle_name,s.last_name) student_name,ay.name academic_year,ap.name semester,p.code programme_code,d.name department_name,f.name faculty_name,coalesce(spr.level_number,o.level_number) level_number,c.code course_code,
 count(*) recorded,count(*) filter(where a.attendance_status='present') present,count(*) filter(where a.attendance_status='late') late,count(*) filter(where a.attendance_status='absent') absent,count(*) filter(where a.attendance_status='excused') excused,
 round(100.0*count(*) filter(where a.attendance_status in('present','late'))/nullif(count(*) filter(where a.attendance_status<>'excused'),0),1) attendance_rate
 from public.student_attendance a join public.students s on s.id=a.student_id and s.institution_id=inst
 join public.teaching_sessions t on t.id=a.teaching_session_id and t.institution_id=inst join public.course_offerings o on o.id=t.course_offering_id and o.institution_id=inst join public.courses c on c.id=o.course_id and c.institution_id=inst
 join public.academic_periods ap on ap.id=o.academic_period_id and ap.institution_id=inst join public.academic_years ay on ay.id=ap.academic_year_id and ay.institution_id=inst
 left join public.student_course_registrations scr on scr.id=a.student_course_registration_id and scr.student_id=s.id and scr.institution_id=inst
 left join public.student_period_registrations spr on spr.id=scr.period_registration_id and spr.institution_id=inst
 left join public.student_programme_enrolments en on en.id=spr.programme_enrolment_id and en.institution_id=inst
 left join public.programmes p on p.id=coalesce(en.programme_id,o.programme_id) and p.institution_id=inst
 left join public.departments d on d.id=p.department_id and d.institution_id=inst left join public.faculties f on f.id=d.faculty_id and f.institution_id=inst
 where a.institution_id=inst and (nullif(p_filters->>'year','') is null or ay.id=(p_filters->>'year')::uuid) and (nullif(p_filters->>'period','') is null or ap.id=(p_filters->>'period')::uuid)
 and (nullif(p_filters->>'faculty','') is null or f.id=(p_filters->>'faculty')::uuid) and (nullif(p_filters->>'department','') is null or d.id=(p_filters->>'department')::uuid)
 and (nullif(p_filters->>'programme','') is null or p.id=(p_filters->>'programme')::uuid) and (nullif(p_filters->>'level','') is null or coalesce(spr.level_number,o.level_number)=(p_filters->>'level')::int)
 group by s.id,s.student_number,s.first_name,s.middle_name,s.last_name,ay.id,ay.name,ap.id,ap.name,p.code,d.name,f.name,coalesce(spr.level_number,o.level_number),c.id,c.code)x;
 return jsonb_build_object('rows',rows);
end $$;
revoke all on function public.unimis_attendance_students142(jsonb) from public,anon;
grant execute on function public.unimis_attendance_students142(jsonb) to authenticated;
