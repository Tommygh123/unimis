
-- UniMIS 045: permanent lecturer workspace fixes + Class List + Attendance
begin;

-- Repair demo Auth row created in 044 for current GoTrue versions.
update auth.users
set confirmation_token=coalesce(confirmation_token,''),
    recovery_token=coalesce(recovery_token,''),
    email_change_token_new=coalesce(email_change_token_new,''),
    email_change=coalesce(email_change,''),
    phone_change=coalesce(phone_change,''),
    phone_change_token=coalesce(phone_change_token,''),
    reauthentication_token=coalesce(reauthentication_token,'')
where lower(email)='kwame.mensah@unimis.local';

-- Shared helper: resolve logged-in lecturer.
create or replace function public.unimis_current_lecturer()
returns table(institution_id uuid, staff_id uuid, lecturer_profile_id uuid)
language sql security definer set search_path=''
as $$
  select iu.institution_id, s.id, lp.id
  from public.institution_users iu
  join public.roles r on r.id=iu.role_id and r.code='lecturer'
  join public.staff s on s.institution_id=iu.institution_id
    and (s.staff_number=iu.staff_number
         or lower(s.email)=lower(coalesce((select email from auth.users where id=auth.uid()),'')))
  join public.lecturer_profiles lp on lp.staff_id=s.id
    and lp.institution_id=iu.institution_id and lp.is_active=true
  where iu.user_id=auth.uid() and iu.status='active'
  order by iu.is_primary desc nulls last, iu.joined_at
  limit 1
$$;
revoke all on function public.unimis_current_lecturer() from public;
grant execute on function public.unimis_current_lecturer() to authenticated;

-- Correct 044 workspace: course_lecturers uses allocation_role, not role.
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
        'academic_period_id',ap.id)
        order by ay.start_date desc,ap.period_number,c.code)
      from public.course_lecturers cl
      join public.course_offerings co on co.id=cl.course_offering_id
      join public.courses c on c.id=co.course_id
      left join public.programmes p on p.id=co.programme_id
      left join public.academic_years ay on ay.id=co.academic_year_id
      left join public.academic_periods ap on ap.id=co.academic_period_id
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
      join public.course_lecturers cl on cl.course_offering_id=co.id and cl.lecturer_profile_id=v_lp
      join public.courses c on c.id=co.course_id
      left join public.programmes p on p.id=co.programme_id
      left join public.academic_periods ap on ap.id=co.academic_period_id
      where cs.institution_id=v_inst),'[]'::jsonb)
  ) into v_result
  from public.lecturer_profiles lp join public.staff s on s.id=lp.staff_id
  where lp.id=v_lp;
  return v_result;
end $$;
revoke all on function public.unimis_lecturer_workspace() from public;
grant execute on function public.unimis_lecturer_workspace() to authenticated;

-- Registered class list for one of the logged-in lecturer's offerings.
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
      'email',s.email,'registration_status',scr.status,'registration_type',scr.registration_type
   ) order by s.last_name,s.first_name) filter(where scr.id is not null),'[]'::jsonb),
   'count',count(scr.id)
 ) into v_result
 from public.student_course_registrations scr
 join public.students s on s.id=scr.student_id
 join public.student_period_registrations spr on spr.id=scr.period_registration_id
 where scr.institution_id=v_inst and scr.course_offering_id=p_course_offering_id
   and lower(coalesce(scr.status,'')) not in ('dropped','cancelled','withdrawn')
   and lower(coalesce(spr.registration_status,''))='approved';

 return coalesce(v_result,jsonb_build_object('students','[]'::jsonb,'count',0));
end $$;
revoke all on function public.unimis_lecturer_class_list(uuid) from public;
grant execute on function public.unimis_lecturer_class_list(uuid) to authenticated;

-- Sessions already created for an allocated offering.
create or replace function public.unimis_lecturer_attendance_sessions(p_course_offering_id uuid)
returns jsonb
language plpgsql security definer set search_path=''
as $$
declare v_inst uuid; v_lp uuid;
begin
 select institution_id,lecturer_profile_id into v_inst,v_lp from public.unimis_current_lecturer();
 if not exists(select 1 from public.course_lecturers where institution_id=v_inst
   and lecturer_profile_id=v_lp and course_offering_id=p_course_offering_id)
 then raise exception 'You are not allocated to this course offering'; end if;

 return coalesce((select jsonb_agg(jsonb_build_object(
   'id',ts.id,'session_date',ts.session_date,'start_time',ts.start_time,'end_time',ts.end_time,
   'venue',ts.venue,'topic',ts.topic,'session_type',ts.session_type,'status',ts.status,
   'attendance_open',ts.attendance_open,'attendance_opened_at',ts.attendance_opened_at,
   'attendance_closed_at',ts.attendance_closed_at)
   order by ts.session_date desc,ts.start_time desc)
 from public.teaching_sessions ts
 where ts.institution_id=v_inst and ts.course_offering_id=p_course_offering_id
   and ts.lecturer_profile_id=v_lp),'[]'::jsonb);
end $$;
revoke all on function public.unimis_lecturer_attendance_sessions(uuid) from public;
grant execute on function public.unimis_lecturer_attendance_sessions(uuid) to authenticated;

-- Create/open an attendance session. Only known existing columns are used.
create or replace function public.unimis_create_attendance_session(
 p_course_offering_id uuid,p_session_date date,p_start_time time,p_end_time time,
 p_topic text default null,p_venue text default null)
returns uuid
language plpgsql security definer set search_path=''
as $$
declare v_inst uuid; v_lp uuid; v_id uuid;
begin
 select institution_id,lecturer_profile_id into v_inst,v_lp from public.unimis_current_lecturer();
 if not exists(select 1 from public.course_lecturers where institution_id=v_inst
   and lecturer_profile_id=v_lp and course_offering_id=p_course_offering_id)
 then raise exception 'You are not allocated to this course offering'; end if;

 insert into public.teaching_sessions(
   institution_id,course_offering_id,lecturer_profile_id,session_date,start_time,end_time,
   venue,topic,session_type,status,attendance_open,attendance_opened_at,created_by)
 values(v_inst,p_course_offering_id,v_lp,p_session_date,p_start_time,p_end_time,
   nullif(btrim(p_venue),''),nullif(btrim(p_topic),''),'lecture','scheduled',true,now(),auth.uid())
 returning id into v_id;
 return v_id;
end $$;
revoke all on function public.unimis_create_attendance_session(uuid,date,time,time,text,text) from public;
grant execute on function public.unimis_create_attendance_session(uuid,date,time,time,text,text) to authenticated;

create or replace function public.unimis_attendance_register(p_teaching_session_id uuid)
returns jsonb
language plpgsql security definer set search_path=''
as $$
declare v_inst uuid; v_lp uuid; v_offering uuid;
begin
 select institution_id,lecturer_profile_id into v_inst,v_lp from public.unimis_current_lecturer();
 select course_offering_id into v_offering from public.teaching_sessions
 where id=p_teaching_session_id and institution_id=v_inst and lecturer_profile_id=v_lp;
 if v_offering is null then raise exception 'Teaching session not found'; end if;

 return coalesce((select jsonb_agg(jsonb_build_object(
   'course_registration_id',scr.id,'student_id',s.id,'student_number',s.student_number,
   'first_name',s.first_name,'middle_name',s.middle_name,'last_name',s.last_name,
   'attendance_id',sa.id,'attendance_status',coalesce(sa.attendance_status,'present'),
   'remarks',sa.remarks)
   order by s.last_name,s.first_name)
 from public.student_course_registrations scr
 join public.students s on s.id=scr.student_id
 join public.student_period_registrations spr on spr.id=scr.period_registration_id
 left join public.student_attendance sa on sa.teaching_session_id=p_teaching_session_id
   and sa.student_id=s.id
 where scr.institution_id=v_inst and scr.course_offering_id=v_offering
   and lower(coalesce(scr.status,'')) not in ('dropped','cancelled','withdrawn')
   and lower(coalesce(spr.registration_status,''))='approved'),'[]'::jsonb);
end $$;
revoke all on function public.unimis_attendance_register(uuid) from public;
grant execute on function public.unimis_attendance_register(uuid) to authenticated;

create or replace function public.unimis_save_attendance(
 p_teaching_session_id uuid,p_records jsonb)
returns jsonb
language plpgsql security definer set search_path=''
as $$
declare v_inst uuid; v_lp uuid; v_offering uuid; r jsonb; v_count int:=0;
begin
 select institution_id,lecturer_profile_id into v_inst,v_lp from public.unimis_current_lecturer();
 select course_offering_id into v_offering from public.teaching_sessions
 where id=p_teaching_session_id and institution_id=v_inst and lecturer_profile_id=v_lp;
 if v_offering is null then raise exception 'Teaching session not found'; end if;

 for r in select * from jsonb_array_elements(coalesce(p_records,'[]'::jsonb))
 loop
   if lower(coalesce(r->>'status','')) not in ('present','absent','late','excused') then
     raise exception 'Invalid attendance status';
   end if;
   if not exists(select 1 from public.student_course_registrations scr
      join public.student_period_registrations spr on spr.id=scr.period_registration_id
      where scr.id=(r->>'course_registration_id')::uuid
        and scr.student_id=(r->>'student_id')::uuid
        and scr.course_offering_id=v_offering and scr.institution_id=v_inst
        and lower(coalesce(scr.status,'')) not in ('dropped','cancelled','withdrawn')
        and lower(coalesce(spr.registration_status,''))='approved')
   then raise exception 'Student is not on the approved class list'; end if;

   insert into public.student_attendance(
     institution_id,teaching_session_id,student_id,student_course_registration_id,
     attendance_status,check_in_time,marked_by,remarks)
   values(v_inst,p_teaching_session_id,(r->>'student_id')::uuid,
     (r->>'course_registration_id')::uuid,lower(r->>'status'),
     case when lower(r->>'status') in ('present','late') then now() else null end,
     auth.uid(),nullif(btrim(r->>'remarks'),''))
   on conflict (teaching_session_id,student_id) do update
     set attendance_status=excluded.attendance_status,
         check_in_time=excluded.check_in_time,marked_by=excluded.marked_by,
         remarks=excluded.remarks,updated_at=now();
   v_count:=v_count+1;
 end loop;
 return jsonb_build_object('saved',v_count);
end $$;
revoke all on function public.unimis_save_attendance(uuid,jsonb) from public;
grant execute on function public.unimis_save_attendance(uuid,jsonb) to authenticated;

commit;
