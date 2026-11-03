begin;

create or replace function public.unimis_registration_slip(p_period_registration_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_reg public.student_period_registrations%rowtype;
  v_student public.students%rowtype;
  v_header jsonb;
  v_courses jsonb;
begin
  select * into v_reg from public.student_period_registrations where id=p_period_registration_id;
  if not found then raise exception 'Registration not found'; end if;
  select * into v_student from public.students where id=v_reg.student_id;
  if not (
    v_student.user_id=auth.uid()
    or public.has_permission(v_reg.institution_id,'registrations.view')
    or public.has_permission(v_reg.institution_id,'registrations.approve')
  ) then raise exception 'You do not have permission to view this registration slip'; end if;

  select to_jsonb(x) into v_header from (
    select r.id as period_registration_id,r.registration_status,r.submitted_at,r.approved_at,
      s.student_number,s.first_name,s.middle_name,s.last_name,s.email,
      p.code as programme_code,p.name as programme_name,e.current_level,
      ay.name as academic_year,ap.name as academic_period
    from public.student_period_registrations r
    join public.students s on s.id=r.student_id
    left join public.student_programme_enrolments e on e.id=r.programme_enrolment_id
    left join public.programmes p on p.id=e.programme_id
    join public.academic_years ay on ay.id=r.academic_year_id
    join public.academic_periods ap on ap.id=r.academic_period_id
    where r.id=v_reg.id
  ) x;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.course_code),'[]'::jsonb) into v_courses from (
    select c.code as course_code,c.name as course_name,c.credit_hours,
      pc.course_category,pc.is_required,o.section_code,scr.registration_type,scr.status
    from public.student_course_registrations scr
    join public.course_offerings o on o.id=scr.course_offering_id
    join public.courses c on c.id=o.course_id
    left join public.programme_courses pc on pc.programme_id=(select programme_id from public.student_programme_enrolments where id=v_reg.programme_enrolment_id)
      and pc.course_id=c.id and pc.level_number=v_reg.level_number
    where scr.period_registration_id=v_reg.id and scr.status<>'dropped'
  ) x;

  return jsonb_build_object('header',v_header,'courses',v_courses);
end $$;

grant execute on function public.unimis_registration_slip(uuid) to authenticated;
commit;
