begin;
create or replace function public.unimis_academic_report(
 p_report text,p_academic_year_id uuid default null,p_academic_period_id uuid default null,p_faculty_id uuid default null,p_department_id uuid default null,p_programme_id uuid default null,p_level integer default null,p_status text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid:=public.unimis_reporting_access(); v_rows jsonb:='[]'::jsonb;
begin
 if v_inst is null then raise exception 'Academic reporting access required'; end if;
 if p_report='student_population' then
  select coalesce(jsonb_agg(to_jsonb(x) order by x.faculty_name,x.department_name,x.programme_code,x.current_level),'[]'::jsonb) into v_rows from (
   select (select name from public.academic_years where id=p_academic_year_id and institution_id=v_inst) academic_year,(select name from public.academic_periods where id=p_academic_period_id and institution_id=v_inst) academic_period,f.name faculty_name,d.name department_name,p.code programme_code,p.name programme_name,e.current_level,count(*) students,
    count(*) filter(where s.status='active') active,count(*) filter(where s.status<>'active') other_status
   from public.students s join public.student_programme_enrolments e on e.student_id=s.id and e.is_primary=true join public.programmes p on p.id=e.programme_id left join public.departments d on d.id=p.department_id left join public.faculties f on f.id=d.faculty_id
   where s.institution_id=v_inst and ((p_academic_year_id is null and p_academic_period_id is null) or exists(select 1 from public.student_period_registrations spr where spr.student_id=s.id and spr.institution_id=v_inst and (p_academic_year_id is null or spr.academic_year_id=p_academic_year_id) and (p_academic_period_id is null or spr.academic_period_id=p_academic_period_id))) and (p_faculty_id is null or d.faculty_id=p_faculty_id) and (p_department_id is null or p.department_id=p_department_id) and (p_programme_id is null or p.id=p_programme_id) and (p_level is null or e.current_level=p_level) and (p_status is null or p_status='' or s.status=p_status)
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
   select f.name faculty_name,d.name department_name,ay.name academic_year,s.student_number,concat_ws(' ',s.first_name,s.middle_name,s.last_name) student,p.code programme_code,e.current_level,ap.name academic_period,c.code course_code,c.name course_name,t.credits,t.failed_grade,t.status
   from public.student_academic_trails t join public.students s on s.id=t.student_id join public.courses c on c.id=t.course_id left join public.programmes p on p.id=t.programme_id left join public.departments d on d.id=p.department_id left join public.student_programme_enrolments e on e.student_id=s.id and e.is_primary=true left join public.academic_years ay on ay.id=t.source_academic_year_id left join public.course_results cr on cr.id=t.source_course_result_id left join public.course_offerings co on co.id=cr.course_offering_id left join public.academic_periods ap on ap.id=co.academic_period_id left join public.faculties f on f.id=d.faculty_id
   where t.institution_id=v_inst and (p_academic_period_id is null or ap.id=p_academic_period_id) and (p_academic_year_id is null or t.source_academic_year_id=p_academic_year_id) and (p_faculty_id is null or d.faculty_id=p_faculty_id) and (p_department_id is null or p.department_id=p_department_id) and (p_programme_id is null or p.id=p_programme_id) and (p_level is null or e.current_level=p_level) and (p_status is null or p_status='' or t.status=p_status))x;
 elsif p_report='graduation' then
  select coalesce(jsonb_agg(to_jsonb(x) order by x.academic_year,x.programme_code,x.decision,x.student_number),'[]'::jsonb) into v_rows from (
   select f.name faculty_name,d.name department_name,ay.name academic_year,s.student_number,concat_ws(' ',s.first_name,s.middle_name,s.last_name) student,p.code programme_code,g.final_level,g.credits_earned,g.credits_required,g.cgpa,g.outstanding_trails,g.decision,g.graduation_date
   from public.graduation_reviews g join public.academic_years ay on ay.id=g.academic_year_id join public.students s on s.id=g.student_id join public.programmes p on p.id=g.programme_id left join public.departments d on d.id=p.department_id left join public.faculties f on f.id=d.faculty_id
   where g.institution_id=v_inst and (p_academic_year_id is null or g.academic_year_id=p_academic_year_id) and (p_faculty_id is null or d.faculty_id=p_faculty_id) and (p_department_id is null or p.department_id=p_department_id) and (p_programme_id is null or p.id=p_programme_id) and (p_level is null or g.final_level=p_level) and (p_status is null or p_status='' or g.decision=p_status))x;
 elsif p_report='attendance' then
  select coalesce(jsonb_agg(to_jsonb(x) order by x.academic_year,x.academic_period,x.programme_code,x.course_code),'[]'::jsonb) into v_rows from (
   select f.name faculty_name,d.name department_name,ay.name academic_year,ap.name academic_period,p.code programme_code,co.level_number,c.code course_code,c.name course_name,count(*) attendance_records,count(*) filter(where a.attendance_status='present') present,count(*) filter(where a.attendance_status='absent') absent,round(count(*) filter(where a.attendance_status in('present','late'))*100.0/nullif(count(*),0),1) attendance_rate
   from public.student_attendance a join public.teaching_sessions ts on ts.id=a.teaching_session_id join public.course_offerings co on co.id=ts.course_offering_id join public.courses c on c.id=co.course_id join public.academic_periods ap on ap.id=co.academic_period_id join public.academic_years ay on ay.id=ap.academic_year_id left join public.programmes p on p.id=co.programme_id left join public.departments d on d.id=p.department_id left join public.faculties f on f.id=d.faculty_id
   where a.institution_id=v_inst and (p_faculty_id is null or d.faculty_id=p_faculty_id) and (p_department_id is null or d.id=p_department_id) and (p_programme_id is null or p.id=p_programme_id) and (p_academic_year_id is null or ap.academic_year_id=p_academic_year_id) and (p_academic_period_id is null or ap.id=p_academic_period_id) and (p_faculty_id is null or d.faculty_id=p_faculty_id) and (p_department_id is null or p.department_id=p_department_id) and (p_programme_id is null or p.id=p_programme_id) and (p_level is null or co.level_number=p_level)
   group by f.name,d.name,ay.name,ap.name,p.code,co.level_number,c.code,c.name)x;
 elsif p_report='admissions' then
  select coalesce(jsonb_agg(to_jsonb(x) order by x.academic_year,x.cycle,x.status),'[]'::jsonb) into v_rows from (
   select f.name faculty_name,d.name department_name,p.code programme_code,ay.name academic_year,ac.name cycle,a.status,count(*) applications
   from public.applications a join public.admission_cycles ac on ac.id=a.admission_cycle_id join public.academic_years ay on ay.id=ac.academic_year_id
   left join lateral (select ch.programme_id from public.application_choices ch where ch.application_id=a.id and ch.institution_id=v_inst order by ch.choice_order,ch.id limit 1) choice on true
   left join public.programmes p on p.id=choice.programme_id left join public.departments d on d.id=p.department_id left join public.faculties f on f.id=d.faculty_id
   where a.institution_id=v_inst and (p_faculty_id is null or d.faculty_id=p_faculty_id) and (p_department_id is null or d.id=p_department_id) and (p_programme_id is null or p.id=p_programme_id) and (p_academic_year_id is null or ac.academic_year_id=p_academic_year_id) and (p_status is null or p_status='' or a.status=p_status)
   group by f.name,d.name,p.code,ay.name,ac.name,a.status)x;
 else raise exception 'Unknown report type: %',p_report;
 end if;
 return jsonb_build_object('report',p_report,'generated_at',now(),'rows',v_rows,'count',jsonb_array_length(v_rows));
end $$;

grant execute on function public.unimis_academic_report(text,uuid,uuid,uuid,uuid,uuid,integer,text) to authenticated;
create or replace function public.unimis_lecturer_reporting_workspace(p_filters jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid; v_lp uuid; v_result jsonb; v_from date:=nullif(p_filters->>'from','')::date; v_to date:=nullif(p_filters->>'to','')::date;
begin
 select institution_id,lecturer_profile_id into v_inst,v_lp from public.unimis_current_lecturer();
 if v_lp is null then raise exception 'Active lecturer profile required'; end if;
 if v_from>v_to then raise exception 'Attendance start date must be on or before end date'; end if;
 with all_courses as (
  select distinct co.id course_offering_id,c.code course_code,c.name course_name,c.credit_hours,
   co.level_number,co.section_code,co.status offering_status,p.id programme_id,p.code programme_code,p.name programme_name,d.id department_id,d.name department_name,f.id faculty_id,f.name faculty_name,
   ap.id academic_period_id,ap.name academic_period,ap.is_current,ap.status period_status,
   ay.id academic_year_id,ay.name academic_year,ay.start_date year_start,ap.period_number
  from public.course_lecturers cl join public.course_offerings co on co.id=cl.course_offering_id and co.institution_id=v_inst
  join public.courses c on c.id=co.course_id and c.institution_id=v_inst
  join public.academic_periods ap on ap.id=co.academic_period_id and ap.institution_id=v_inst
  join public.academic_years ay on ay.id=ap.academic_year_id and ay.institution_id=v_inst
  left join public.programmes p on p.id=co.programme_id and p.institution_id=v_inst
  left join public.departments d on d.id=p.department_id and d.institution_id=v_inst
  left join public.faculties f on f.id=d.faculty_id and f.institution_id=v_inst
  where cl.institution_id=v_inst and cl.lecturer_profile_id=v_lp
 ), offerings as (
  select * from all_courses where
   (nullif(p_filters->>'year','') is null or academic_year_id=(p_filters->>'year')::uuid)
   and (nullif(p_filters->>'period','') is null or academic_period_id=(p_filters->>'period')::uuid)
   and (nullif(p_filters->>'faculty','') is null or faculty_id=(p_filters->>'faculty')::uuid)
   and (nullif(p_filters->>'department','') is null or department_id=(p_filters->>'department')::uuid)
   and (nullif(p_filters->>'programme','') is null or programme_id=(p_filters->>'programme')::uuid)
   and (nullif(p_filters->>'course','') is null or course_offering_id=(p_filters->>'course')::uuid)
   and (nullif(p_filters->>'level','') is null or level_number=(p_filters->>'level')::integer)
   and (coalesce(p_filters->>'scope','all')='all' or (p_filters->>'scope'='current' and is_current) or (p_filters->>'scope'='previous' and period_status in ('closed','archived')))
 ), roster as (
  select o.*,scr.id course_registration_id,s.id student_id,s.student_number,
   concat_ws(' ',s.first_name,s.middle_name,s.last_name) student_name,s.photo_url,s.email,
   scr.status registration_status,s.status student_status,
   (select d.storage_path from public.application_documents d where d.application_id=s.application_id and d.institution_id=v_inst and d.mime_type like 'image/%' and (lower(d.document_type) like '%photo%' or lower(d.document_type) like '%passport%') order by d.created_at desc limit 1) applicant_photo_path
  from offerings o join public.student_course_registrations scr on scr.course_offering_id=o.course_offering_id and scr.institution_id=v_inst
  join public.student_period_registrations spr on spr.id=scr.period_registration_id and spr.institution_id=v_inst and spr.registration_status='approved'
  join public.students s on s.id=scr.student_id and s.institution_id=v_inst
  where scr.status not in ('dropped','cancelled','withdrawn')
 ), sessions as (
  select ts.*,o.course_code,o.course_name,o.academic_year,o.academic_period,o.programme_code,o.level_number,o.faculty_name,o.department_name
  from offerings o join public.teaching_sessions ts on ts.course_offering_id=o.course_offering_id and ts.institution_id=v_inst and ts.lecturer_profile_id=v_lp
  where (v_from is null or ts.session_date>=v_from) and (v_to is null or ts.session_date<=v_to)
 ), attendance as (
  select r.student_id,r.student_number,r.student_name,r.course_offering_id,r.course_code,r.course_name,r.academic_year,r.academic_period,r.programme_code,r.level_number,r.faculty_name,r.department_name,
   count(sa.id) records,count(sa.id) filter(where sa.attendance_status='present') present,
   count(sa.id) filter(where sa.attendance_status='late') late,count(sa.id) filter(where sa.attendance_status='absent') absent,
   count(sa.id) filter(where sa.attendance_status='excused') excused,
   round(count(sa.id) filter(where sa.attendance_status in ('present','late'))*100.0/nullif(count(sa.id) filter(where sa.attendance_status<>'excused'),0),1) attendance_rate
  from roster r left join sessions ts on ts.course_offering_id=r.course_offering_id
  left join public.student_attendance sa on sa.teaching_session_id=ts.id and sa.student_id=r.student_id and sa.institution_id=v_inst
  group by r.student_id,r.student_number,r.student_name,r.course_offering_id,r.course_code,r.course_name,r.academic_year,r.academic_period,r.programme_code,r.level_number,r.faculty_name,r.department_name
 ), results as (
  select o.*,s.id student_id,s.student_number,concat_ws(' ',s.first_name,s.middle_name,s.last_name) student_name,
   cr.total_score,cr.letter_grade,cr.grade_point,cr.passed,cr.result_status
  from offerings o join public.course_results cr on cr.course_offering_id=o.course_offering_id and cr.institution_id=v_inst
  join public.students s on s.id=cr.student_id and s.institution_id=v_inst
 ), assessments as (
  select o.*,ai.id assessment_id,ai.name assessment_name,ai.assessment_type,ai.max_score,ai.weight_percent,ai.due_date,ai.status,
   (select count(*) from public.assessment_scores sc where sc.assessment_item_id=ai.id and sc.institution_id=v_inst and sc.raw_score is not null) scored_students
  from offerings o join public.assessment_items ai on ai.course_offering_id=o.course_offering_id and ai.institution_id=v_inst
 ), timetable as (
  select o.*,cs.id schedule_id,cs.day_of_week,cs.start_time,cs.end_time,cs.venue,cs.schedule_type
  from offerings o join public.course_schedules cs on cs.course_offering_id=o.course_offering_id and cs.institution_id=v_inst
 )
 select jsonb_build_object(
  'generated_at',now(),'institution',(select jsonb_build_object('name',i.name) from public.institutions i where i.id=v_inst),
  'options',coalesce((select jsonb_agg(to_jsonb(x) order by x.year_start desc,x.period_number,x.course_code) from all_courses x),'[]'::jsonb),
  'courses',coalesce((select jsonb_agg(to_jsonb(x) order by x.year_start desc,x.period_number,x.course_code) from offerings x),'[]'::jsonb),
  'students',coalesce((select jsonb_agg(to_jsonb(x) order by x.student_number,x.year_start desc,x.course_code) from roster x),'[]'::jsonb),
  'attendance',coalesce((select jsonb_agg(to_jsonb(x) order by x.student_number,x.course_code) from attendance x),'[]'::jsonb),
  'sessions',coalesce((select jsonb_agg(to_jsonb(x) order by x.session_date desc,x.start_time) from sessions x),'[]'::jsonb),
  'results',coalesce((select jsonb_agg(to_jsonb(x) order by x.student_number,x.year_start,x.period_number,x.course_code) from results x),'[]'::jsonb),
  'assessments',coalesce((select jsonb_agg(to_jsonb(x) order by x.course_code,x.due_date) from assessments x),'[]'::jsonb),
  'timetable',coalesce((select jsonb_agg(to_jsonb(x) order by x.day_of_week,x.start_time) from timetable x),'[]'::jsonb)
 ) into v_result;
 return v_result;
end $$;
revoke all on function public.unimis_lecturer_reporting_workspace(jsonb) from public;
grant execute on function public.unimis_lecturer_reporting_workspace(jsonb) to authenticated;
notify pgrst,'reload schema';
commit;
