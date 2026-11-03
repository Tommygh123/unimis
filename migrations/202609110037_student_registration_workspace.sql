begin;

create or replace function public.unimis_student_registration_workspace()
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_student public.students%rowtype;
  v_enrol public.student_programme_enrolments%rowtype;
  v_year public.academic_years%rowtype;
  v_period public.academic_periods%rowtype;
  v_reg public.student_period_registrations%rowtype;
  v_policy jsonb;
  v_courses jsonb;
  v_total_due numeric:=0;
  v_total_paid numeric:=0;
  v_min_pct numeric:=0;
  v_fee_ok boolean:=true;
begin
  select * into v_student from public.students where user_id=auth.uid() limit 1;
  if not found then raise exception 'No student record is linked to this login'; end if;

  select * into v_enrol from public.student_programme_enrolments
  where student_id=v_student.id and is_primary=true and enrolment_status='active'
  order by created_at desc limit 1;
  if not found then raise exception 'No active programme enrolment found'; end if;

  select * into v_year from public.academic_years
  where institution_id=v_student.institution_id and is_current=true
  order by start_date desc limit 1;
  if not found then raise exception 'No current academic year is configured'; end if;

  select * into v_period from public.academic_periods
  where institution_id=v_student.institution_id and academic_year_id=v_year.id and is_current=true
  order by period_number limit 1;
  if not found then raise exception 'No current academic period is configured'; end if;

  select * into v_reg from public.student_period_registrations
  where student_id=v_student.id and academic_year_id=v_year.id and academic_period_id=v_period.id
  order by created_at desc limit 1;

  if not found then
    insert into public.student_period_registrations(
      institution_id,student_id,academic_year_id,academic_period_id,
      programme_enrolment_id,level_number,registration_status,notes
    ) values (
      v_student.institution_id,v_student.id,v_year.id,v_period.id,
      v_enrol.id,v_enrol.current_level,'draft','Created by Student Portal registration workspace'
    ) returning * into v_reg;
  end if;

  select coalesce(academic_settings->'registration','{}'::jsonb)
  into v_policy from public.institution_settings where institution_id=v_student.institution_id;

  select coalesce(sum(total_amount),0),coalesce(sum(amount_paid),0)
  into v_total_due,v_total_paid
  from public.student_invoices
  where student_id=v_student.id and academic_year_id=v_year.id
    and (academic_period_id is null or academic_period_id=v_period.id)
    and status not in ('cancelled','void');

  v_min_pct:=coalesce((v_policy->>'minimum_fee_percentage')::numeric,0);
  if coalesce((v_policy->>'require_fee_clearance')::boolean,false) then
    if v_total_due<=0 then v_fee_ok:=false;
    elsif v_min_pct>0 then v_fee_ok:=((v_total_paid/nullif(v_total_due,0))*100)>=v_min_pct;
    else v_fee_ok:=(v_total_due-v_total_paid)<=0;
    end if;
  end if;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.is_required desc,x.course_code),'[]'::jsonb)
  into v_courses
  from (
    select
      pc.id as programme_course_id,pc.course_id,pc.course_category,pc.is_required,
      c.code as course_code,c.name as course_name,c.credit_hours,c.lecture_hours,c.practical_hours,
      co.id as course_offering_id,co.section_code,co.capacity,co.registration_open,co.status as offering_status,
      scr.id as student_course_registration_id,
      case when scr.id is not null and scr.status<>'dropped' then true else false end as selected,
      scr.status as registration_status
    from public.programme_courses pc
    join public.courses c on c.id=pc.course_id
    left join lateral (
      select o.* from public.course_offerings o
      where o.course_id=pc.course_id
        and o.academic_year_id=v_year.id
        and o.academic_period_id=v_period.id
        and (o.programme_id is null or o.programme_id=v_enrol.programme_id)
      order by (o.programme_id is not null)::int desc,o.section_code
      limit 1
    ) co on true
    left join public.student_course_registrations scr
      on scr.period_registration_id=v_reg.id and scr.course_offering_id=co.id and scr.status<>'dropped'
    where pc.programme_id=v_enrol.programme_id
      and pc.level_number=v_enrol.current_level
      and pc.period_number=v_period.period_number
  ) x;

  return jsonb_build_object(
    'student',to_jsonb(v_student),
    'enrolment',to_jsonb(v_enrol),
    'academic_year',to_jsonb(v_year),
    'academic_period',to_jsonb(v_period),
    'period_registration',to_jsonb(v_reg),
    'policy',coalesce(v_policy,'{}'::jsonb),
    'fee_clearance',jsonb_build_object(
      'required',coalesce((v_policy->>'require_fee_clearance')::boolean,false),
      'minimum_percentage',v_min_pct,
      'total_due',v_total_due,'total_paid',v_total_paid,'balance',v_total_due-v_total_paid,'cleared',v_fee_ok
    ),
    'courses',v_courses
  );
end $$;

grant execute on function public.unimis_student_registration_workspace() to authenticated;
commit;
