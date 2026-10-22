begin;

create or replace function public.unimis_submit_student_registration(p_period_registration_id uuid)
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
  v_credits numeric:=0;
  v_min numeric:=0;
  v_max numeric:=24;
  v_missing_required integer:=0;
  v_missing_prereq integer:=0;
  v_due numeric:=0;
  v_paid numeric:=0;
  v_fee_ok boolean:=true;
  v_min_pct numeric:=0;
  v_require_approval boolean:=true;
  v_new_status text;
begin
  select * into v_reg from public.student_period_registrations where id=p_period_registration_id for update;
  if not found then raise exception 'Registration record not found'; end if;
  select * into v_student from public.students where id=v_reg.student_id;
  if v_student.user_id<>auth.uid() then raise exception 'You cannot submit another student registration'; end if;
  if v_reg.registration_status not in ('draft','rejected') then raise exception 'This registration has already been submitted'; end if;

  select * into v_enrol from public.student_programme_enrolments where id=v_reg.programme_enrolment_id;
  select * into v_period from public.academic_periods where id=v_reg.academic_period_id;
  select coalesce(academic_settings->'registration','{}'::jsonb) into v_policy from public.institution_settings where institution_id=v_reg.institution_id;

  if v_period.registration_start is not null and current_date<v_period.registration_start then raise exception 'Course registration has not opened yet'; end if;
  if v_period.registration_end is not null and current_date>v_period.registration_end
     and not coalesce((v_policy->>'allow_late_registration')::boolean,false) then raise exception 'Course registration has closed'; end if;

  select coalesce(sum(c.credit_hours),0) into v_credits
  from public.student_course_registrations scr
  join public.course_offerings o on o.id=scr.course_offering_id
  join public.courses c on c.id=o.course_id
  where scr.period_registration_id=v_reg.id and scr.status<>'dropped';

  v_min:=coalesce((v_policy->>'min_credits')::numeric,0);
  v_max:=coalesce((v_policy->>'max_credits')::numeric,24);
  if v_credits<v_min then raise exception 'Selected credits (%) are below the minimum allowed (%)',v_credits,v_min; end if;
  if v_credits>v_max then raise exception 'Selected credits (%) exceed the maximum allowed (%)',v_credits,v_max; end if;

  select count(*) into v_missing_required
  from public.programme_courses pc
  where pc.programme_id=v_enrol.programme_id and pc.level_number=v_reg.level_number and pc.period_number=v_period.period_number
    and pc.is_required=true
    and not exists(
      select 1 from public.student_course_registrations scr
      join public.course_offerings o on o.id=scr.course_offering_id
      where scr.period_registration_id=v_reg.id and scr.status<>'dropped' and o.course_id=pc.course_id
    );
  if v_missing_required>0 then raise exception '% required course(s) have not been selected',v_missing_required; end if;

  select count(*) into v_missing_prereq
  from public.student_course_registrations scr
  join public.course_offerings o on o.id=scr.course_offering_id
  join public.course_prerequisites cp on cp.course_id=o.course_id
    and cp.institution_id=v_reg.institution_id
    and (cp.programme_id is null or cp.programme_id=v_enrol.programme_id)
    and cp.is_mandatory=true
  where scr.period_registration_id=v_reg.id and scr.status<>'dropped'
    and not exists(
      select 1 from public.course_results cr
      join public.course_offerings po on po.id=cr.course_offering_id
      where cr.student_id=v_reg.student_id and po.course_id=cp.prerequisite_course_id and cr.passed=true
    );
  if v_missing_prereq>0 then raise exception '% prerequisite requirement(s) are not satisfied',v_missing_prereq; end if;

  if coalesce((v_policy->>'require_fee_clearance')::boolean,false) then
    select coalesce(sum(total_amount),0),coalesce(sum(amount_paid),0) into v_due,v_paid
    from public.student_invoices
    where student_id=v_reg.student_id and academic_year_id=v_reg.academic_year_id
      and (academic_period_id is null or academic_period_id=v_reg.academic_period_id)
      and status not in ('cancelled','void');
    v_min_pct:=coalesce((v_policy->>'minimum_fee_percentage')::numeric,0);
    if v_due<=0 then v_fee_ok:=false;
    elsif v_min_pct>0 then v_fee_ok:=((v_paid/nullif(v_due,0))*100)>=v_min_pct;
    else v_fee_ok:=(v_due-v_paid)<=0;
    end if;
    if not v_fee_ok then raise exception 'Fee clearance requirement has not been satisfied'; end if;
  end if;

  v_require_approval:=coalesce((v_policy->>'require_adviser_approval')::boolean,true);
  v_new_status:=case when v_require_approval then 'submitted' else 'approved' end;

  update public.student_period_registrations
  set registration_status=v_new_status,submitted_at=now(),
      approved_at=case when v_require_approval then null else now() end,
      approved_by=case when v_require_approval then null else auth.uid() end,
      updated_at=now()
  where id=v_reg.id;

  insert into public.registration_approval_history(
    institution_id,period_registration_id,old_status,new_status,action_by,notes
  ) values (
    v_reg.institution_id,v_reg.id,v_reg.registration_status,v_new_status,auth.uid(),
    case when v_require_approval then 'Submitted by student' else 'Auto-approved by registration policy' end
  );

  return jsonb_build_object('ok',true,'registration_status',v_new_status,'total_credits',v_credits);
end $$;

grant execute on function public.unimis_submit_student_registration(uuid) to authenticated;
commit;
