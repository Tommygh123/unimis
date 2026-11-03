begin;

create or replace function public.unimis_save_student_course_selection(
  p_period_registration_id uuid,
  p_course_offering_ids uuid[]
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_reg public.student_period_registrations%rowtype;
  v_student public.students%rowtype;
  v_enrol public.student_programme_enrolments%rowtype;
  v_period public.academic_periods%rowtype;
  v_policy jsonb;
  v_final_ids uuid[];
  v_invalid integer:=0;
  v_count integer:=0;
begin
  select * into v_reg from public.student_period_registrations where id=p_period_registration_id for update;
  if not found then raise exception 'Registration record not found'; end if;
  select * into v_student from public.students where id=v_reg.student_id;
  if v_student.user_id<>auth.uid() then raise exception 'You cannot edit another student registration'; end if;
  if v_reg.registration_status not in ('draft','rejected') then raise exception 'Only draft/returned registrations can be edited'; end if;

  select * into v_enrol from public.student_programme_enrolments where id=v_reg.programme_enrolment_id;
  select * into v_period from public.academic_periods where id=v_reg.academic_period_id;
  select coalesce(academic_settings->'registration','{}'::jsonb) into v_policy
  from public.institution_settings where institution_id=v_reg.institution_id;

  if v_period.registration_start is not null and current_date<v_period.registration_start then
    raise exception 'Course registration has not opened yet';
  end if;
  if v_period.registration_end is not null and current_date>v_period.registration_end
     and not coalesce((v_policy->>'allow_late_registration')::boolean,false) then
    raise exception 'Course registration has closed';
  end if;

  select count(*) into v_invalid
  from unnest(coalesce(p_course_offering_ids,array[]::uuid[])) x(id)
  left join public.course_offerings o on o.id=x.id
  where o.id is null or o.academic_period_id<>v_reg.academic_period_id or o.academic_year_id<>v_reg.academic_year_id
     or o.registration_open=false or (o.programme_id is not null and o.programme_id<>v_enrol.programme_id);
  if v_invalid>0 then raise exception 'One or more selected course offerings are not available for this registration'; end if;

  select coalesce(array_agg(distinct q.id),array[]::uuid[]) into v_final_ids
  from (
    select unnest(coalesce(p_course_offering_ids,array[]::uuid[])) id
    union
    select o.id
    from public.programme_courses pc
    join public.course_offerings o on o.course_id=pc.course_id
      and o.academic_year_id=v_reg.academic_year_id
      and o.academic_period_id=v_reg.academic_period_id
      and (o.programme_id is null or o.programme_id=v_enrol.programme_id)
      and o.registration_open=true
    where pc.programme_id=v_enrol.programme_id
      and pc.level_number=v_reg.level_number
      and pc.period_number=v_period.period_number
      and pc.is_required=true
      and coalesce((v_policy->>'auto_select_required_courses')::boolean,true)
  ) q;

  delete from public.student_course_registrations
  where period_registration_id=v_reg.id
    and not (course_offering_id=any(v_final_ids));

  insert into public.student_course_registrations(
    institution_id,period_registration_id,student_id,course_offering_id,registration_type,status
  )
  select v_reg.institution_id,v_reg.id,v_reg.student_id,x,'normal','registered'
  from unnest(v_final_ids) x
  where not exists(
    select 1 from public.student_course_registrations r
    where r.period_registration_id=v_reg.id and r.course_offering_id=x and r.status<>'dropped'
  );

  update public.student_period_registrations
  set registration_status='draft',submitted_at=null,approved_at=null,approved_by=null,updated_at=now()
  where id=v_reg.id;

  select count(*) into v_count from public.student_course_registrations
  where period_registration_id=v_reg.id and status<>'dropped';
  return jsonb_build_object('ok',true,'selected_count',v_count);
end $$;

grant execute on function public.unimis_save_student_course_selection(uuid,uuid[]) to authenticated;
commit;
