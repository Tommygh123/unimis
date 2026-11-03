begin;

create or replace function public.unimis_reporting_access()
returns uuid language sql stable security definer set search_path='' as $$
 select iu.institution_id from public.institution_users iu
 join public.roles r on r.id=iu.role_id
 where iu.user_id=auth.uid() and iu.status='active'
 and lower(coalesce(r.code,r.name)) in ('admin','administrator','owner','registrar','superadmin','super_admin','exams_officer','examination_officer','examinations_officer')
 limit 1
$$;

create or replace function public.unimis_academic_intelligence_filters()
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid:=public.unimis_reporting_access();
begin
 if v_inst is null then raise exception 'Academic review access required'; end if;
 return jsonb_build_object(
  'academic_years',coalesce((select jsonb_agg(jsonb_build_object('id',ay.id,'name',ay.name) order by ay.start_date desc) from public.academic_years ay where ay.institution_id=v_inst),'[]'::jsonb),
  'periods',coalesce((select jsonb_agg(jsonb_build_object('id',ap.id,'name',ap.name,'academic_year_id',ap.academic_year_id) order by ap.start_date desc) from public.academic_periods ap where ap.institution_id=v_inst),'[]'::jsonb),
  'faculties',coalesce((select jsonb_agg(jsonb_build_object('id',f.id,'name',f.name) order by f.name) from public.faculties f where f.institution_id=v_inst),'[]'::jsonb),
  'departments',coalesce((select jsonb_agg(jsonb_build_object('id',d.id,'name',d.name,'faculty_id',d.faculty_id) order by d.name) from public.departments d where d.institution_id=v_inst),'[]'::jsonb),
  'programmes',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'code',p.code,'name',p.name,'department_id',p.department_id,'faculty_id',d.faculty_id) order by p.code) from public.programmes p left join public.departments d on d.id=p.department_id where p.institution_id=v_inst),'[]'::jsonb),
  'levels',jsonb_build_array(100,200,300,400,500,600)
 );
end $$;

create or replace function public.unimis_academic_intelligence_report(
 p_academic_year_id uuid default null,p_academic_period_id uuid default null,p_faculty_id uuid default null,p_department_id uuid default null,
 p_programme_id uuid default null,p_level integer default null,p_result_status text default null,p_exception text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid:=public.unimis_reporting_access();
begin
 if v_inst is null then raise exception 'Academic review access required'; end if;
 return jsonb_build_object(
 'generated_at',now(),
 'summary',(select jsonb_build_object('students',count(distinct cr.student_id),'courses',count(distinct cr.course_offering_id),'results',count(*),'average',round(avg(cr.total_score),2),'pass_rate',round(count(*) filter(where cr.passed)*100.0/nullif(count(*),0),1),'failures',count(*) filter(where not coalesce(cr.passed,false)))
  from public.course_results cr join public.course_offerings co on co.id=cr.course_offering_id join public.academic_periods ap on ap.id=co.academic_period_id left join public.programmes p on p.id=co.programme_id left join public.departments d on d.id=p.department_id
  where cr.institution_id=v_inst and (p_academic_year_id is null or ap.academic_year_id=p_academic_year_id) and (p_academic_period_id is null or co.academic_period_id=p_academic_period_id) and (p_faculty_id is null or d.faculty_id=p_faculty_id) and (p_department_id is null or p.department_id=p_department_id) and (p_programme_id is null or co.programme_id=p_programme_id) and (p_level is null or co.level_number=p_level) and (p_result_status is null or p_result_status='' or cr.result_status=p_result_status)),
 'courses',coalesce((select jsonb_agg(to_jsonb(x) order by x.fail_rate desc,x.course_code) from (
  select co.id course_offering_id,c.code course_code,c.name course_name,p.code programme_code,p.name programme_name,d.name department_name,f.name faculty_name,co.level_number,ay.name academic_year,ap.name academic_period,count(*) students,round(avg(cr.total_score),2) average,
   round(count(*) filter(where cr.passed)*100.0/nullif(count(*),0),1) pass_rate,round(count(*) filter(where not coalesce(cr.passed,false))*100.0/nullif(count(*),0),1) fail_rate,min(cr.total_score) lowest,max(cr.total_score) highest,
   case when count(*) filter(where not coalesce(cr.passed,false))*100.0/nullif(count(*),0)>=40 then 'high_failure' when count(*) filter(where cr.passed)*100.0/nullif(count(*),0)>=95 then 'very_high_pass' when max(cr.total_score)-min(cr.total_score)>=50 then 'wide_spread' else 'normal' end exception_type
  from public.course_results cr join public.course_offerings co on co.id=cr.course_offering_id join public.courses c on c.id=co.course_id join public.academic_periods ap on ap.id=co.academic_period_id join public.academic_years ay on ay.id=ap.academic_year_id left join public.programmes p on p.id=co.programme_id left join public.departments d on d.id=p.department_id left join public.faculties f on f.id=d.faculty_id
  where cr.institution_id=v_inst and (p_academic_year_id is null or ap.academic_year_id=p_academic_year_id) and (p_academic_period_id is null or co.academic_period_id=p_academic_period_id) and (p_faculty_id is null or d.faculty_id=p_faculty_id) and (p_department_id is null or p.department_id=p_department_id) and (p_programme_id is null or co.programme_id=p_programme_id) and (p_level is null or co.level_number=p_level) and (p_result_status is null or p_result_status='' or cr.result_status=p_result_status)
  group by co.id,c.code,c.name,p.code,p.name,d.name,f.name,co.level_number,ay.name,ap.name
 )x where (p_exception is null or p_exception='' or p_exception='all' or x.exception_type=p_exception)),'[]'::jsonb),
 'students',coalesce((select jsonb_agg(to_jsonb(z) order by z.failed_courses desc,z.average) from (
  select s.id student_id,s.student_number,concat_ws(' ',s.first_name,s.middle_name,s.last_name) student_name,count(*) courses,round(avg(cr.total_score),2) average,min(cr.total_score) weakest_score,max(cr.total_score) strongest_score,round(stddev_pop(cr.total_score),2) variation,count(*) filter(where not coalesce(cr.passed,false)) failed_courses
  from public.course_results cr join public.course_offerings co on co.id=cr.course_offering_id join public.academic_periods ap on ap.id=co.academic_period_id join public.students s on s.id=cr.student_id left join public.programmes p on p.id=co.programme_id left join public.departments d on d.id=p.department_id
  where cr.institution_id=v_inst and (p_academic_year_id is null or ap.academic_year_id=p_academic_year_id) and (p_academic_period_id is null or co.academic_period_id=p_academic_period_id) and (p_faculty_id is null or d.faculty_id=p_faculty_id) and (p_department_id is null or p.department_id=p_department_id) and (p_programme_id is null or co.programme_id=p_programme_id) and (p_level is null or co.level_number=p_level) and (p_result_status is null or p_result_status='' or cr.result_status=p_result_status)
  group by s.id,s.student_number,s.first_name,s.middle_name,s.last_name
 )z),'[]'::jsonb));
end $$;

create or replace function public.unimis_exams_review_filters()
returns jsonb language plpgsql security definer set search_path='' as $$
begin return public.unimis_academic_intelligence_filters(); end $$;

create or replace function public.unimis_exams_review_queue(
 p_academic_year_id uuid default null,p_academic_period_id uuid default null,p_faculty_id uuid default null,p_department_id uuid default null,p_programme_id uuid default null,p_level integer default null,p_status text default null,p_exceptions_only boolean default false)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid:=public.unimis_reporting_access();
begin
 if v_inst is null then raise exception 'Examinations review access required'; end if;
 return jsonb_build_object(
 'summary',(select jsonb_build_object('courses',count(*),'submitted',count(*) filter(where q.result_status='submitted'),'approved',count(*) filter(where q.result_status='approved'),'published',count(*) filter(where q.result_status='published'),'flagged',count(*) filter(where q.exception_type<>'normal')) from (
   select co.id,cr.result_status,case when count(*) filter(where not coalesce(cr.passed,false))*100.0/nullif(count(*),0)>=40 then 'high_failure' when count(*) filter(where cr.passed)*100.0/nullif(count(*),0)>=95 then 'very_high_pass' when max(cr.total_score)-min(cr.total_score)>=50 then 'wide_spread' else 'normal' end exception_type
   from public.course_results cr join public.course_offerings co on co.id=cr.course_offering_id join public.academic_periods ap on ap.id=co.academic_period_id left join public.programmes p on p.id=co.programme_id left join public.departments d on d.id=p.department_id
   where cr.institution_id=v_inst and (p_academic_year_id is null or ap.academic_year_id=p_academic_year_id) and (p_academic_period_id is null or co.academic_period_id=p_academic_period_id) and (p_faculty_id is null or d.faculty_id=p_faculty_id) and (p_department_id is null or p.department_id=p_department_id) and (p_programme_id is null or co.programme_id=p_programme_id) and (p_level is null or co.level_number=p_level) and (p_status is null or p_status='' or cr.result_status=p_status) group by co.id,cr.result_status
 )q where (not p_exceptions_only or q.exception_type<>'normal')),
 'rows',coalesce((select jsonb_agg(to_jsonb(q) order by q.faculty_name,q.department_name,q.course_code) from (
   select co.id course_offering_id,c.code course_code,c.name course_name,co.level_number,ay.name academic_year,ap.name academic_period,p.id programme_id,p.code programme_code,p.name programme_name,d.id department_id,d.name department_name,f.id faculty_id,f.name faculty_name,cr.result_status,count(*) students,round(avg(cr.total_score),2) average,round(count(*) filter(where cr.passed)*100.0/nullif(count(*),0),1) pass_rate,round(count(*) filter(where not coalesce(cr.passed,false))*100.0/nullif(count(*),0),1) fail_rate,min(cr.total_score) lowest,max(cr.total_score) highest,min(cr.submitted_at) submitted_at,
   case when count(*) filter(where not coalesce(cr.passed,false))*100.0/nullif(count(*),0)>=40 then 'high_failure' when count(*) filter(where cr.passed)*100.0/nullif(count(*),0)>=95 then 'very_high_pass' when max(cr.total_score)-min(cr.total_score)>=50 then 'wide_spread' else 'normal' end exception_type
   from public.course_results cr join public.course_offerings co on co.id=cr.course_offering_id join public.courses c on c.id=co.course_id join public.academic_periods ap on ap.id=co.academic_period_id join public.academic_years ay on ay.id=ap.academic_year_id left join public.programmes p on p.id=co.programme_id left join public.departments d on d.id=p.department_id left join public.faculties f on f.id=d.faculty_id
   where cr.institution_id=v_inst and (p_academic_year_id is null or ap.academic_year_id=p_academic_year_id) and (p_academic_period_id is null or co.academic_period_id=p_academic_period_id) and (p_faculty_id is null or d.faculty_id=p_faculty_id) and (p_department_id is null or p.department_id=p_department_id) and (p_programme_id is null or co.programme_id=p_programme_id) and (p_level is null or co.level_number=p_level) and (p_status is null or p_status='' or cr.result_status=p_status)
   group by co.id,c.code,c.name,co.level_number,ay.name,ap.name,p.id,p.code,p.name,d.id,d.name,f.id,f.name,cr.result_status
 )q where (not p_exceptions_only or q.exception_type<>'normal')),'[]'::jsonb));
end $$;

create or replace function public.unimis_academic_report(
 p_report text,p_academic_year_id uuid default null,p_academic_period_id uuid default null,p_faculty_id uuid default null,p_department_id uuid default null,p_programme_id uuid default null,p_level integer default null,p_status text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid:=public.unimis_reporting_access(); v_rows jsonb:='[]'::jsonb;
begin
 if v_inst is null then raise exception 'Academic reporting access required'; end if;
 if p_report='student_population' then
  select coalesce(jsonb_agg(to_jsonb(x) order by x.faculty_name,x.department_name,x.programme_code,x.current_level),'[]'::jsonb) into v_rows from (
   select f.name faculty_name,d.name department_name,p.code programme_code,p.name programme_name,e.current_level,count(*) students,
    count(*) filter(where s.status='active') active,count(*) filter(where s.status<>'active') other_status
   from public.students s join public.student_programme_enrolments e on e.student_id=s.id and e.is_primary=true join public.programmes p on p.id=e.programme_id left join public.departments d on d.id=p.department_id left join public.faculties f on f.id=d.faculty_id
   where s.institution_id=v_inst and (p_faculty_id is null or d.faculty_id=p_faculty_id) and (p_department_id is null or p.department_id=p_department_id) and (p_programme_id is null or p.id=p_programme_id) and (p_level is null or e.current_level=p_level) and (p_status is null or p_status='' or s.status=p_status)
   group by f.name,d.name,p.code,p.name,e.current_level)x;
 elsif p_report='registration' then
  select coalesce(jsonb_agg(to_jsonb(x) order by x.academic_year,x.academic_period,x.programme_code,x.level_number),'[]'::jsonb) into v_rows from (
   select ay.name academic_year,ap.name academic_period,f.name faculty_name,d.name department_name,p.code programme_code,p.name programme_name,r.level_number,r.registration_status status,count(*) students
   from public.student_period_registrations r join public.academic_years ay on ay.id=r.academic_year_id join public.academic_periods ap on ap.id=r.academic_period_id join public.student_programme_enrolments e on e.id=r.programme_enrolment_id join public.programmes p on p.id=e.programme_id left join public.departments d on d.id=p.department_id left join public.faculties f on f.id=d.faculty_id
   where r.institution_id=v_inst and (p_academic_year_id is null or r.academic_year_id=p_academic_year_id) and (p_academic_period_id is null or r.academic_period_id=p_academic_period_id) and (p_faculty_id is null or d.faculty_id=p_faculty_id) and (p_department_id is null or p.department_id=p_department_id) and (p_programme_id is null or p.id=p_programme_id) and (p_level is null or r.level_number=p_level) and (p_status is null or p_status='' or r.registration_status=p_status)
   group by ay.name,ap.name,f.name,d.name,p.code,p.name,r.level_number,r.registration_status)x;
 elsif p_report='performance' then
  select coalesce(jsonb_agg(to_jsonb(x) order by x.academic_year,x.academic_period,x.programme_code,x.course_code),'[]'::jsonb) into v_rows from (
   select ay.name academic_year,ap.name academic_period,f.name faculty_name,d.name department_name,p.code programme_code,co.level_number,c.code course_code,c.name course_name,count(*) students,round(avg(cr.total_score),2) average,round(count(*) filter(where cr.passed)*100.0/nullif(count(*),0),1) pass_rate,count(*) filter(where not coalesce(cr.passed,false)) failures
   from public.course_results cr join public.course_offerings co on co.id=cr.course_offering_id join public.courses c on c.id=co.course_id join public.academic_periods ap on ap.id=co.academic_period_id join public.academic_years ay on ay.id=ap.academic_year_id left join public.programmes p on p.id=co.programme_id left join public.departments d on d.id=p.department_id left join public.faculties f on f.id=d.faculty_id
   where cr.institution_id=v_inst and (p_academic_year_id is null or ap.academic_year_id=p_academic_year_id) and (p_academic_period_id is null or ap.id=p_academic_period_id) and (p_faculty_id is null or d.faculty_id=p_faculty_id) and (p_department_id is null or p.department_id=p_department_id) and (p_programme_id is null or p.id=p_programme_id) and (p_level is null or co.level_number=p_level) and (p_status is null or p_status='' or cr.result_status=p_status)
   group by ay.name,ap.name,f.name,d.name,p.code,co.level_number,c.code,c.name)x;
 elsif p_report='progression' then
  select coalesce(jsonb_agg(to_jsonb(x) order by x.academic_year,x.programme_code,x.from_level,x.decision),'[]'::jsonb) into v_rows from (
   select ay.name academic_year,f.name faculty_name,d.name department_name,p.code programme_code,p.name programme_name,r.from_level,r.proposed_level,r.decision,count(*) students,round(avg(r.cgpa),2) average_cgpa
   from public.student_progression_reviews r join public.academic_years ay on ay.id=r.academic_year_id join public.programmes p on p.id=r.programme_id left join public.departments d on d.id=p.department_id left join public.faculties f on f.id=d.faculty_id
   where r.institution_id=v_inst and (p_academic_year_id is null or r.academic_year_id=p_academic_year_id) and (p_faculty_id is null or d.faculty_id=p_faculty_id) and (p_department_id is null or p.department_id=p_department_id) and (p_programme_id is null or p.id=p_programme_id) and (p_level is null or r.from_level=p_level) and (p_status is null or p_status='' or r.decision=p_status)
   group by ay.name,f.name,d.name,p.code,p.name,r.from_level,r.proposed_level,r.decision)x;
 elsif p_report='trails' then
  select coalesce(jsonb_agg(to_jsonb(x) order by x.academic_year,x.student_number,x.course_code),'[]'::jsonb) into v_rows from (
   select ay.name academic_year,s.student_number,concat_ws(' ',s.first_name,s.middle_name,s.last_name) student,p.code programme_code,e.current_level,c.code course_code,c.name course_name,t.credits,t.failed_grade,t.status
   from public.student_academic_trails t join public.students s on s.id=t.student_id join public.courses c on c.id=t.course_id left join public.programmes p on p.id=t.programme_id left join public.departments d on d.id=p.department_id left join public.student_programme_enrolments e on e.student_id=s.id and e.is_primary=true left join public.academic_years ay on ay.id=t.source_academic_year_id
   where t.institution_id=v_inst and (p_academic_year_id is null or t.source_academic_year_id=p_academic_year_id) and (p_faculty_id is null or d.faculty_id=p_faculty_id) and (p_department_id is null or p.department_id=p_department_id) and (p_programme_id is null or p.id=p_programme_id) and (p_level is null or e.current_level=p_level) and (p_status is null or p_status='' or t.status=p_status))x;
 elsif p_report='graduation' then
  select coalesce(jsonb_agg(to_jsonb(x) order by x.academic_year,x.programme_code,x.decision,x.student_number),'[]'::jsonb) into v_rows from (
   select ay.name academic_year,s.student_number,concat_ws(' ',s.first_name,s.middle_name,s.last_name) student,p.code programme_code,g.final_level,g.credits_earned,g.credits_required,g.cgpa,g.outstanding_trails,g.decision,g.graduation_date
   from public.graduation_reviews g join public.academic_years ay on ay.id=g.academic_year_id join public.students s on s.id=g.student_id join public.programmes p on p.id=g.programme_id left join public.departments d on d.id=p.department_id
   where g.institution_id=v_inst and (p_academic_year_id is null or g.academic_year_id=p_academic_year_id) and (p_faculty_id is null or d.faculty_id=p_faculty_id) and (p_department_id is null or p.department_id=p_department_id) and (p_programme_id is null or p.id=p_programme_id) and (p_level is null or g.final_level=p_level) and (p_status is null or p_status='' or g.decision=p_status))x;
 elsif p_report='attendance' then
  select coalesce(jsonb_agg(to_jsonb(x) order by x.academic_year,x.academic_period,x.programme_code,x.course_code),'[]'::jsonb) into v_rows from (
   select ay.name academic_year,ap.name academic_period,p.code programme_code,co.level_number,c.code course_code,c.name course_name,count(*) attendance_records,count(*) filter(where a.attendance_status='present') present,count(*) filter(where a.attendance_status='absent') absent,round(count(*) filter(where a.attendance_status in('present','late'))*100.0/nullif(count(*),0),1) attendance_rate
   from public.student_attendance a join public.teaching_sessions ts on ts.id=a.teaching_session_id join public.course_offerings co on co.id=ts.course_offering_id join public.courses c on c.id=co.course_id join public.academic_periods ap on ap.id=co.academic_period_id join public.academic_years ay on ay.id=ap.academic_year_id left join public.programmes p on p.id=co.programme_id left join public.departments d on d.id=p.department_id
   where a.institution_id=v_inst and (p_academic_year_id is null or ap.academic_year_id=p_academic_year_id) and (p_academic_period_id is null or ap.id=p_academic_period_id) and (p_faculty_id is null or d.faculty_id=p_faculty_id) and (p_department_id is null or p.department_id=p_department_id) and (p_programme_id is null or p.id=p_programme_id) and (p_level is null or co.level_number=p_level)
   group by ay.name,ap.name,p.code,co.level_number,c.code,c.name)x;
 elsif p_report='admissions' then
  select coalesce(jsonb_agg(to_jsonb(x) order by x.academic_year,x.cycle,x.status),'[]'::jsonb) into v_rows from (
   select ay.name academic_year,ac.name cycle,a.status,count(*) applications
   from public.applications a join public.admission_cycles ac on ac.id=a.admission_cycle_id join public.academic_years ay on ay.id=ac.academic_year_id
   where a.institution_id=v_inst and (p_academic_year_id is null or ac.academic_year_id=p_academic_year_id) and (p_status is null or p_status='' or a.status=p_status)
   group by ay.name,ac.name,a.status)x;
 else raise exception 'Unknown report type: %',p_report;
 end if;
 return jsonb_build_object('report',p_report,'generated_at',now(),'rows',v_rows,'count',jsonb_array_length(v_rows));
end $$;

grant execute on function public.unimis_reporting_access() to authenticated;
grant execute on function public.unimis_academic_intelligence_filters() to authenticated;
grant execute on function public.unimis_academic_intelligence_report(uuid,uuid,uuid,uuid,uuid,integer,text,text) to authenticated;
grant execute on function public.unimis_exams_review_filters() to authenticated;
grant execute on function public.unimis_exams_review_queue(uuid,uuid,uuid,uuid,uuid,integer,text,boolean) to authenticated;
grant execute on function public.unimis_academic_report(text,uuid,uuid,uuid,uuid,uuid,integer,text) to authenticated;
commit;