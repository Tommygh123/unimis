begin;

create or replace function public.unimis_lecturer_workspace()
returns jsonb
language plpgsql security definer set search_path=''
as $$
declare v_inst uuid; v_staff uuid; v_lp uuid; v_result jsonb;
begin
  select institution_id,staff_id,lecturer_profile_id into v_inst,v_staff,v_lp
  from public.unimis_current_lecturer();
  if v_lp is null then raise exception 'Active lecturer profile not found'; end if;

  select jsonb_build_object(
    'lecturer',jsonb_build_object(
      'lecturer_profile_id',lp.id,'staff_id',s.id,'staff_number',s.staff_number,
      'first_name',s.first_name,'middle_name',s.middle_name,'last_name',s.last_name,
      'email',s.email,'job_title',s.job_title,'academic_rank',lp.academic_rank,
      'specialization',lp.specialization),
    'courses',coalesce((
      select jsonb_agg(jsonb_build_object(
        'allocation_id',cl.id,'allocation_role',cl.allocation_role,
        'workload_percentage',cl.workload_percentage,'is_primary',cl.is_primary,
        'course_offering_id',co.id,'course_code',c.code,'course_name',c.name,
        'credit_hours',c.credit_hours,'section_code',co.section_code,
        'level_number',co.level_number,'offering_status',co.status,
        'registration_open',co.registration_open,'programme_code',p.code,
        'programme_name',p.name,'academic_year',ay.name,'academic_period',ap.name,
        'academic_period_id',ap.id,'academic_year_id',ay.id,'programme_id',p.id,'is_current',coalesce(ap.is_current,false),'period_status',ap.status)
        order by ay.start_date desc,ap.period_number,c.code)
      from public.course_lecturers cl
      join public.course_offerings co on co.id=cl.course_offering_id and co.institution_id=v_inst
      join public.courses c on c.id=co.course_id and c.institution_id=v_inst
      left join public.programmes p on p.id=co.programme_id and p.institution_id=v_inst
      left join public.academic_years ay on ay.id=co.academic_year_id and ay.institution_id=v_inst
      left join public.academic_periods ap on ap.id=co.academic_period_id and ap.institution_id=v_inst
      where cl.institution_id=v_inst and cl.lecturer_profile_id=v_lp),'[]'::jsonb),
    'schedule',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',cs.id,'course_offering_id',cs.course_offering_id,'day_of_week',cs.day_of_week,
        'start_time',cs.start_time,'end_time',cs.end_time,'venue',cs.venue,
        'schedule_type',cs.schedule_type,'course_code',c.code,'course_name',c.name,
        'section_code',co.section_code,'programme_code',p.code,'academic_period',ap.name)
        order by cs.day_of_week,cs.start_time)
      from public.course_schedules cs
      join public.course_offerings co on co.id=cs.course_offering_id
      join public.course_lecturers cl on cl.course_offering_id=co.id and cl.institution_id=v_inst and cl.lecturer_profile_id=v_lp
      join public.courses c on c.id=co.course_id and c.institution_id=v_inst
      left join public.programmes p on p.id=co.programme_id and p.institution_id=v_inst
      left join public.academic_periods ap on ap.id=co.academic_period_id and ap.institution_id=v_inst
      where cs.institution_id=v_inst),'[]'::jsonb)
  ) into v_result
  from public.lecturer_profiles lp join public.staff s on s.id=lp.staff_id
  where lp.id=v_lp;
  return v_result;
end $$;
revoke all on function public.unimis_lecturer_workspace() from public;
grant execute on function public.unimis_lecturer_workspace() to authenticated;


create or replace function public.unimis_lecturer_class_list(p_course_offering_id uuid)
returns jsonb
language plpgsql security definer set search_path=''
as $$
declare v_inst uuid; v_lp uuid; v_allowed boolean; v_result jsonb;
begin
 select institution_id,lecturer_profile_id into v_inst,v_lp from public.unimis_current_lecturer();
 select exists(select 1 from public.course_lecturers
   where institution_id=v_inst and lecturer_profile_id=v_lp
     and course_offering_id=p_course_offering_id) into v_allowed;
 if not v_allowed then raise exception 'You are not allocated to this course offering'; end if;

 select jsonb_build_object(
   'students',coalesce(jsonb_agg(jsonb_build_object(
      'course_registration_id',scr.id,'student_id',s.id,'student_number',s.student_number,
      'first_name',s.first_name,'middle_name',s.middle_name,'last_name',s.last_name,
      'photo_url',s.photo_url,'applicant_photo_path',(select d.storage_path from public.application_documents d where d.application_id=s.application_id and d.institution_id=v_inst and coalesce(d.mime_type,'') like 'image/%' and (lower(d.document_type) like '%photo%' or lower(d.document_type) like '%passport%') order by d.created_at desc limit 1),'email',s.email,'registration_status',scr.status,'registration_type',scr.registration_type
   ) order by s.last_name,s.first_name) filter(where scr.id is not null),'[]'::jsonb),
   'count',count(scr.id)
 ) into v_result
 from public.student_course_registrations scr
 join public.students s on s.id=scr.student_id and s.institution_id=v_inst
 join public.student_period_registrations spr on spr.id=scr.period_registration_id and spr.institution_id=v_inst
 where scr.institution_id=v_inst and scr.course_offering_id=p_course_offering_id
   and lower(coalesce(scr.status,'')) not in ('dropped','cancelled','withdrawn')
   and lower(coalesce(spr.registration_status,''))='approved';

 return coalesce(v_result,jsonb_build_object('students','[]'::jsonb,'count',0));
end $$;
revoke all on function public.unimis_lecturer_class_list(uuid) from public;
grant execute on function public.unimis_lecturer_class_list(uuid) to authenticated;

-- Photo access is limited to students registered in the lecturer's own allocations.
create or replace function public.unimis_lecturer_photo_access115(p_path text)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.unimis_current_lecturer() me
 join public.course_lecturers cl on cl.institution_id=me.institution_id and cl.lecturer_profile_id=me.lecturer_profile_id
 join public.student_course_registrations scr on scr.course_offering_id=cl.course_offering_id and scr.institution_id=me.institution_id
 join public.student_period_registrations spr on spr.id=scr.period_registration_id and spr.institution_id=me.institution_id
 join public.students s on s.id=scr.student_id and s.institution_id=me.institution_id
 join public.application_documents d on d.application_id=s.application_id and d.institution_id=me.institution_id
 where d.storage_path=p_path and d.mime_type like 'image/%'
 and (lower(d.document_type) like '%photo%' or lower(d.document_type) like '%passport%')
 and spr.registration_status='approved' and scr.status not in ('dropped','cancelled','withdrawn'))
$$;
revoke all on function public.unimis_lecturer_photo_access115(text) from public;
grant execute on function public.unimis_lecturer_photo_access115(text) to authenticated;
drop policy if exists lecturer_student_photo_read115 on storage.objects;
create policy lecturer_student_photo_read115 on storage.objects for select to authenticated
 using(bucket_id='admission-documents' and public.unimis_lecturer_photo_access115(name));

create or replace function public.unimis_lecturer_reporting_workspace(p_filters jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid; v_lp uuid; v_result jsonb; v_from date:=nullif(p_filters->>'from','')::date; v_to date:=nullif(p_filters->>'to','')::date;
begin
 select institution_id,lecturer_profile_id into v_inst,v_lp from public.unimis_current_lecturer();
 if v_lp is null then raise exception 'Active lecturer profile required'; end if;
 if v_from>v_to then raise exception 'Attendance start date must be on or before end date'; end if;
 with all_courses as (
  select distinct co.id course_offering_id,c.code course_code,c.name course_name,c.credit_hours,
   co.level_number,co.section_code,co.status offering_status,p.id programme_id,p.code programme_code,p.name programme_name,
   ap.id academic_period_id,ap.name academic_period,ap.is_current,ap.status period_status,
   ay.id academic_year_id,ay.name academic_year,ay.start_date year_start,ap.period_number
  from public.course_lecturers cl join public.course_offerings co on co.id=cl.course_offering_id and co.institution_id=v_inst
  join public.courses c on c.id=co.course_id and c.institution_id=v_inst
  join public.academic_periods ap on ap.id=co.academic_period_id and ap.institution_id=v_inst
  join public.academic_years ay on ay.id=ap.academic_year_id and ay.institution_id=v_inst
  left join public.programmes p on p.id=co.programme_id and p.institution_id=v_inst
  where cl.institution_id=v_inst and cl.lecturer_profile_id=v_lp
 ), offerings as (
  select * from all_courses where
   (nullif(p_filters->>'year','') is null or academic_year_id=(p_filters->>'year')::uuid)
   and (nullif(p_filters->>'period','') is null or academic_period_id=(p_filters->>'period')::uuid)
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
  select ts.*,o.course_code,o.course_name,o.academic_year,o.academic_period,o.programme_code,o.level_number
  from offerings o join public.teaching_sessions ts on ts.course_offering_id=o.course_offering_id and ts.institution_id=v_inst and ts.lecturer_profile_id=v_lp
  where (v_from is null or ts.session_date>=v_from) and (v_to is null or ts.session_date<=v_to)
 ), attendance as (
  select r.student_id,r.student_number,r.student_name,r.course_offering_id,r.course_code,r.course_name,r.academic_year,r.academic_period,r.programme_code,r.level_number,
   count(sa.id) records,count(sa.id) filter(where sa.attendance_status='present') present,
   count(sa.id) filter(where sa.attendance_status='late') late,count(sa.id) filter(where sa.attendance_status='absent') absent,
   count(sa.id) filter(where sa.attendance_status='excused') excused,
   round(count(sa.id) filter(where sa.attendance_status in ('present','late'))*100.0/nullif(count(sa.id) filter(where sa.attendance_status<>'excused'),0),1) attendance_rate
  from roster r left join sessions ts on ts.course_offering_id=r.course_offering_id
  left join public.student_attendance sa on sa.teaching_session_id=ts.id and sa.student_id=r.student_id and sa.institution_id=v_inst
  group by r.student_id,r.student_number,r.student_name,r.course_offering_id,r.course_code,r.course_name,r.academic_year,r.academic_period,r.programme_code,r.level_number
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
create or replace function public.unimis_academic_intelligence_filters()
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid:=public.unimis_reporting_access();
begin
 if v_inst is null then raise exception 'Academic review access required'; end if;
 return jsonb_build_object(
  'institution',(select jsonb_build_object('name',i.name) from public.institutions i where i.id=v_inst),
  'academic_years',coalesce((select jsonb_agg(jsonb_build_object('id',ay.id,'name',ay.name) order by ay.start_date desc) from public.academic_years ay where ay.institution_id=v_inst),'[]'::jsonb),
  'periods',coalesce((select jsonb_agg(jsonb_build_object('id',ap.id,'name',ap.name,'academic_year_id',ap.academic_year_id) order by ap.start_date desc) from public.academic_periods ap where ap.institution_id=v_inst),'[]'::jsonb),
  'faculties',coalesce((select jsonb_agg(jsonb_build_object('id',f.id,'name',f.name) order by f.name) from public.faculties f where f.institution_id=v_inst),'[]'::jsonb),
  'departments',coalesce((select jsonb_agg(jsonb_build_object('id',d.id,'name',d.name,'faculty_id',d.faculty_id) order by d.name) from public.departments d where d.institution_id=v_inst),'[]'::jsonb),
  'programmes',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'code',p.code,'name',p.name,'department_id',p.department_id,'faculty_id',d.faculty_id) order by p.code) from public.programmes p left join public.departments d on d.id=p.department_id where p.institution_id=v_inst),'[]'::jsonb),
  'levels',jsonb_build_array(100,200,300,400,500,600)
 );
end $$;


commit;
notify pgrst,'reload schema';
