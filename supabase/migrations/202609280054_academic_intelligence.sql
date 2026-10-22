
begin;
create or replace function public.unimis_academic_intelligence()
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid;
begin
 select iu.institution_id into v_inst
 from public.institution_users iu join public.roles r on r.id=iu.role_id
 where iu.user_id=auth.uid() and iu.status='active'
 and lower(coalesce(r.code,r.name)) in ('admin','administrator','owner','registrar','superadmin','super_admin','exams_officer','examinations_officer') limit 1;
 if v_inst is null then raise exception 'Academic review access required'; end if;
 return jsonb_build_object(
 'summary',(select jsonb_build_object('students',count(distinct cr.student_id),'courses',count(distinct cr.course_offering_id),'results',count(*),'average',round(avg(cr.total_score),2),'pass_rate',round(count(*) filter(where cr.passed)*100.0/nullif(count(*),0),1),'failures',count(*) filter(where not coalesce(cr.passed,false))) from public.course_results cr where cr.institution_id=v_inst and cr.result_status in ('submitted','approved','published')),
 'courses',coalesce((select jsonb_agg(to_jsonb(x) order by x.fail_rate desc) from (
 select co.id course_offering_id,c.code course_code,c.name course_name,p.code programme_code,co.level_number,ap.name academic_period,count(*) students,round(avg(cr.total_score),2) average,round(count(*) filter(where cr.passed)*100.0/nullif(count(*),0),1) pass_rate,round(count(*) filter(where not coalesce(cr.passed,false))*100.0/nullif(count(*),0),1) fail_rate,min(cr.total_score) lowest,max(cr.total_score) highest
 from public.course_results cr join public.course_offerings co on co.id=cr.course_offering_id join public.courses c on c.id=co.course_id left join public.programmes p on p.id=co.programme_id join public.academic_periods ap on ap.id=co.academic_period_id
 where cr.institution_id=v_inst and cr.result_status in ('submitted','approved','published')
 group by co.id,c.code,c.name,p.code,co.level_number,ap.name) x),'[]'::jsonb),
 'students',coalesce((select jsonb_agg(to_jsonb(z) order by z.average) from (
 select s.id student_id,s.student_number,concat_ws(' ',s.first_name,s.middle_name,s.last_name) student_name,count(*) courses,round(avg(cr.total_score),2) average,min(cr.total_score) weakest_score,max(cr.total_score) strongest_score,round(stddev_pop(cr.total_score),2) variation,count(*) filter(where not coalesce(cr.passed,false)) failed_courses
 from public.course_results cr join public.students s on s.id=cr.student_id
 where cr.institution_id=v_inst and cr.result_status in ('submitted','approved','published')
 group by s.id,s.student_number,s.first_name,s.middle_name,s.last_name) z),'[]'::jsonb));
end $$;
grant execute on function public.unimis_academic_intelligence() to authenticated;

create or replace function public.unimis_student_academic_profile(p_student_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid;
begin
 select iu.institution_id into v_inst from public.institution_users iu join public.roles r on r.id=iu.role_id
 where iu.user_id=auth.uid() and iu.status='active' and lower(coalesce(r.code,r.name)) in ('admin','administrator','owner','registrar','superadmin','super_admin','exams_officer','examinations_officer') limit 1;
 if v_inst is null then raise exception 'Academic review access required'; end if;
 return jsonb_build_object(
 'student',(select jsonb_build_object('student_number',s.student_number,'student_name',concat_ws(' ',s.first_name,s.middle_name,s.last_name)) from public.students s where s.id=p_student_id and s.institution_id=v_inst),
 'courses',coalesce((select jsonb_agg(to_jsonb(x) order by x.course_code) from (
 select c.code course_code,c.name course_name,cr.total_score,cr.letter_grade,cr.grade_point,cr.passed,round(avg(cr2.total_score),2) class_average,round(cr.total_score-avg(cr2.total_score),2) difference_from_class,ap.name academic_period
 from public.course_results cr join public.course_offerings co on co.id=cr.course_offering_id join public.courses c on c.id=co.course_id join public.academic_periods ap on ap.id=co.academic_period_id join public.course_results cr2 on cr2.course_offering_id=co.id and cr2.result_status in ('submitted','approved','published')
 where cr.institution_id=v_inst and cr.student_id=p_student_id and cr.result_status in ('submitted','approved','published')
 group by c.code,c.name,cr.total_score,cr.letter_grade,cr.grade_point,cr.passed,ap.name) x),'[]'::jsonb),
 'attendance',(select jsonb_build_object('sessions',count(*),'present',count(*) filter(where sa.attendance_status in ('present','late')),'rate',round(count(*) filter(where sa.attendance_status in ('present','late'))*100.0/nullif(count(*),0),1)) from public.student_attendance sa where sa.institution_id=v_inst and sa.student_id=p_student_id));
end $$;
grant execute on function public.unimis_student_academic_profile(uuid) to authenticated;
commit;
