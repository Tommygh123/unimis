create or replace function public.unimis_attendance_students144(p_filters jsonb default '{}'::jsonb)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare inst uuid:=public.unimis_reporting_access();rows jsonb;lp uuid;lecture boolean:=coalesce((p_filters->>'lecturer')::boolean,false);
begin
 if lecture then select me.institution_id,me.lecturer_profile_id into inst,lp from public.unimis_current_lecturer() me;if lp is null then raise exception 'Active lecturer required';end if;end if;
 if inst is null then raise exception 'Academic reporting access required';end if;
 if nullif(p_filters->>'from','')::date>nullif(p_filters->>'to','')::date then raise exception 'From date must be on or before To date';end if;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.academic_year,x.semester,x.student_number,x.course_code),'[]'::jsonb) into rows from (
 select s.id student_id,o.id course_offering_id,o.section_code,min(t.session_date) first_session,max(t.session_date) last_session,
 jsonb_agg(jsonb_build_object('date',t.session_date,'start',t.start_time,'end',t.end_time,'topic',t.topic,'venue',t.venue,'status',a.attendance_status,'remarks',a.remarks) order by t.session_date desc,t.start_time desc) details,
 s.student_number,concat_ws(' ',s.first_name,s.middle_name,s.last_name) student_name,ay.name academic_year,ap.name semester,p.code programme_code,d.name department_name,f.name faculty_name,coalesce(spr.level_number,o.level_number) level_number,c.code course_code,
 count(*) recorded,count(*) filter(where a.attendance_status='present') present,count(*) filter(where a.attendance_status='late') late,count(*) filter(where a.attendance_status='absent') absent,count(*) filter(where a.attendance_status='excused') excused,
 round(100.0*count(*) filter(where a.attendance_status in('present','late'))/nullif(count(*) filter(where a.attendance_status<>'excused'),0),1) attendance_rate
 from public.student_attendance a join public.students s on s.id=a.student_id and s.institution_id=inst
 join public.teaching_sessions t on t.id=a.teaching_session_id and t.institution_id=inst join public.course_offerings o on o.id=t.course_offering_id and o.institution_id=inst join public.courses c on c.id=o.course_id and c.institution_id=inst
 join public.academic_periods ap on ap.id=o.academic_period_id and ap.institution_id=inst join public.academic_years ay on ay.id=ap.academic_year_id and ay.institution_id=inst
 left join lateral (select reg.* from public.student_course_registrations reg where reg.student_id=s.id and reg.institution_id=inst and reg.course_offering_id=o.id and (reg.id=a.student_course_registration_id or a.student_course_registration_id is null) order by (reg.id=a.student_course_registration_id) desc nulls last,reg.id limit 1) scr on true
 left join public.student_period_registrations spr on spr.id=scr.period_registration_id and spr.institution_id=inst
 left join public.student_programme_enrolments en on en.id=spr.programme_enrolment_id and en.institution_id=inst
 left join public.programmes p on p.id=coalesce(en.programme_id,o.programme_id) and p.institution_id=inst
 left join public.departments d on d.id=p.department_id and d.institution_id=inst left join public.faculties f on f.id=d.faculty_id and f.institution_id=inst
 where a.institution_id=inst
 and (not lecture or exists(select 1 from public.course_lecturers cl where cl.institution_id=inst and cl.lecturer_profile_id=lp and cl.course_offering_id=o.id))
 and (nullif(p_filters->>'from','') is null or t.session_date>=(p_filters->>'from')::date) and (nullif(p_filters->>'to','') is null or t.session_date<=(p_filters->>'to')::date)
 and (nullif(p_filters->>'course','') is null or o.id=(p_filters->>'course')::uuid)
 and (coalesce(p_filters->>'scope','all')='all' or p_filters->>'scope'='current' and ap.is_current or p_filters->>'scope'='previous' and ap.status in('closed','archived'))
 and (nullif(p_filters->>'year','') is null or ay.id=(p_filters->>'year')::uuid) and (nullif(p_filters->>'period','') is null or ap.id=(p_filters->>'period')::uuid)
 and (nullif(p_filters->>'faculty','') is null or f.id=(p_filters->>'faculty')::uuid) and (nullif(p_filters->>'department','') is null or d.id=(p_filters->>'department')::uuid)
 and (nullif(p_filters->>'programme','') is null or p.id=(p_filters->>'programme')::uuid) and (nullif(p_filters->>'level','') is null or coalesce(spr.level_number,o.level_number)=(p_filters->>'level')::int)
 group by o.id,o.section_code,s.id,s.student_number,s.first_name,s.middle_name,s.last_name,ay.id,ay.name,ap.id,ap.name,p.code,d.name,f.name,coalesce(spr.level_number,o.level_number),c.id,c.code)x;
 return jsonb_build_object('rows',rows);
end $$;
revoke all on function public.unimis_attendance_students144(jsonb) from public,anon;
grant execute on function public.unimis_attendance_students144(jsonb) to authenticated;
