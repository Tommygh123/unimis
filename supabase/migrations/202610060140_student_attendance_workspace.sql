create or replace function public.unimis_student_attendance140()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare sid uuid;inst uuid;rows jsonb;
begin
 select s.id,s.institution_id into sid,inst from public.students s where s.user_id=auth.uid()
 and exists(select 1 from public.unimis_effective_memberships116 m join public.roles r on r.id=m.role_id and r.is_active where m.user_id=auth.uid() and m.institution_id=s.institution_id and m.status='active' and r.code='student') order by s.id limit 1;
 if sid is null then raise exception 'Active student access required';end if;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.session_date desc,x.start_time desc),'[]'::jsonb) into rows from (
 select a.id,a.attendance_status,a.remarks,t.session_date,t.start_time,t.end_time,t.topic,t.venue,c.code,c.name,ay.name academic_year,ap.name semester
 from public.student_attendance a join public.teaching_sessions t on t.id=a.teaching_session_id and t.institution_id=inst
 join public.course_offerings o on o.id=t.course_offering_id and o.institution_id=inst
 join public.courses c on c.id=o.course_id and c.institution_id=inst
 join public.academic_periods ap on ap.id=o.academic_period_id and ap.institution_id=inst
 join public.academic_years ay on ay.id=ap.academic_year_id and ay.institution_id=inst
 where a.student_id=sid and a.institution_id=inst)x;
 return jsonb_build_object('rows',rows);
end $$;
revoke all on function public.unimis_student_attendance140() from public,anon;
grant execute on function public.unimis_student_attendance140() to authenticated;
