-- UniMIS 117: honour existing automatic-invoice setting; use transcript CGPA for award classification.
begin;
CREATE OR REPLACE FUNCTION public.unimis_convert_accepted_application_to_student(p_application_id uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
declare
  v_app public.applications%rowtype;
  v_applicant public.applicants%rowtype;
  v_offer public.admission_offers%rowtype;
  v_student public.students%rowtype;
  v_year public.academic_years%rowtype;
  v_period public.academic_periods%rowtype;
  v_enrol public.student_programme_enrolments%rowtype;
  v_period_reg public.student_period_registrations%rowtype;
  v_student_role uuid;
  v_settings jsonb;
  v_number text;
  v_initial_level integer;
  v_auto_period boolean;
  v_auto_role boolean;
  v_auto_invoice boolean;
  v_invoice jsonb;
begin
  select * into v_app from public.applications where id=p_application_id for update;
  if not found then raise exception 'Application not found'; end if;

  if not (
    public.has_permission(v_app.institution_id,'students.manage')
    or public.has_permission(v_app.institution_id,'admissions.manage')
  ) then
    raise exception 'You do not have permission to convert applicants to students';
  end if;

  select * into v_applicant from public.applicants where id=v_app.applicant_id;
  if not found then raise exception 'Applicant record not found'; end if;

  select * into v_offer
  from public.admission_offers
  where application_id=p_application_id
    and response_status='accepted'
  order by created_at desc
  limit 1;

  if not found then
    raise exception 'The applicant must accept an admission offer before student conversion';
  end if;

  select * into v_student
  from public.students
  where application_id=p_application_id
  limit 1;

  if found then
    return jsonb_build_object(
      'ok',true,'already_converted',true,'student_id',v_student.id,
      'student_number',v_student.student_number
    );
  end if;

  select * into v_year
  from public.academic_years
  where institution_id=v_app.institution_id
    and is_current=true
    and status in ('active','open','planned')
  order by start_date desc
  limit 1;

  if not found then
    raise exception 'No current academic year is configured. Go to Institution Settings → Academic Calendar first.';
  end if;

  select * into v_period
  from public.academic_periods
  where institution_id=v_app.institution_id
    and academic_year_id=v_year.id
    and is_current=true
  order by period_number
  limit 1;

  select coalesce(academic_settings->'student_conversion','{}'::jsonb)
  into v_settings
  from public.institution_settings
  where institution_id=v_app.institution_id;

  v_initial_level := coalesce((v_settings->>'initial_level')::integer,100);
  v_auto_period := coalesce((v_settings->>'auto_create_period_registration')::boolean,true);
  v_auto_role := coalesce((v_settings->>'auto_assign_student_role')::boolean,true);
  v_auto_invoice := coalesce((v_settings->>'auto_generate_initial_invoice')::boolean,false);

  v_number := public.unimis_next_student_number(
    v_app.institution_id,
    extract(year from v_year.start_date)::integer
  );

  insert into public.students(
    institution_id,user_id,applicant_id,application_id,student_number,
    first_name,middle_name,last_name,date_of_birth,gender,email,phone,
    nationality,address,city,region,admission_date,student_type,status
  ) values (
    v_app.institution_id,v_applicant.user_id,v_applicant.id,v_app.id,v_number,
    v_applicant.first_name,v_applicant.middle_name,v_applicant.last_name,
    v_applicant.date_of_birth,v_applicant.gender,v_applicant.email,v_applicant.phone,
    v_applicant.nationality,v_applicant.address,v_applicant.city,v_applicant.region,
    current_date,'regular','active'
  )
  returning * into v_student;

  insert into public.student_programme_enrolments(
    institution_id,student_id,programme_id,admission_academic_year_id,
    cohort_year,current_level,enrolment_status,start_date,is_primary
  ) values (
    v_app.institution_id,v_student.id,v_offer.programme_id,v_year.id,
    extract(year from v_year.start_date)::integer,v_initial_level,'active',current_date,true
  )
  returning * into v_enrol;

  if v_auto_period and v_period.id is not null then
    insert into public.student_period_registrations(
      institution_id,student_id,academic_year_id,academic_period_id,
      programme_enrolment_id,level_number,registration_status,notes
    ) values (
      v_app.institution_id,v_student.id,v_year.id,v_period.id,
      v_enrol.id,v_initial_level,'draft',
      'Created automatically during applicant-to-student conversion'
    )
    returning * into v_period_reg;
  end if;

  if v_auto_role and v_applicant.user_id is not null then
    select id into v_student_role
    from public.roles
    where code='student'
      and (institution_id=v_app.institution_id or institution_id is null)
      and is_active=true
    order by institution_id nulls last
    limit 1;

    if v_student_role is null then
      raise exception 'Student role is not configured for this institution';
    end if;

    if exists(
      select 1 from public.institution_users
      where institution_id=v_app.institution_id and user_id=v_applicant.user_id
    ) then
      update public.institution_users
      set role_id=v_student_role,student_number=v_number,status='active',updated_at=now()
      where institution_id=v_app.institution_id and user_id=v_applicant.user_id;
    else
      insert into public.institution_users(
        institution_id,user_id,role_id,student_number,status,is_primary
      ) values (
        v_app.institution_id,v_applicant.user_id,v_student_role,v_number,'active',true
      );
    end if;
  end if;

  insert into public.student_conversion_history(
    institution_id,application_id,applicant_id,student_id,offer_id,
    action,student_number,converted_by,metadata
  ) values (
    v_app.institution_id,v_app.id,v_applicant.id,v_student.id,v_offer.id,
    'converted',v_number,auth.uid(),
    jsonb_build_object(
      'programme_id',v_offer.programme_id,
      'academic_year_id',v_year.id,
      'academic_period_id',v_period.id,
      'programme_enrolment_id',v_enrol.id,
      'period_registration_id',v_period_reg.id
    )
  );

  if v_auto_invoice then
    v_invoice := public.unimis_generate_student_initial_invoice(v_student.id);
  end if;

  return jsonb_build_object(
    'ok',true,
    'student_id',v_student.id,
    'student_number',v_number,
    'programme_enrolment_id',v_enrol.id,
    'period_registration_id',v_period_reg.id,
    'academic_year',v_year.name,
    'academic_period',v_period.name,
    'initial_invoice',v_invoice
  );
end $$;
CREATE OR REPLACE FUNCTION public.unimis_evaluate_graduation(p_academic_year_id uuid, p_programme_id uuid = NULL) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
declare v_inst uuid; rec record; v_final int; v_earned numeric; v_cgpa numeric; v_trails int; v_required numeric; v_reasons jsonb; v_decision text; v_class jsonb; n int:=0;
begin
 v_inst:=public.unimis_progression_access(); if v_inst is null then raise exception 'Graduation access required'; end if;
 perform public.unimis_sync_academic_trails(null);
 for rec in select s.id student_id,e.id enrolment_id,e.programme_id,e.current_level,p.duration_years,p.total_credits from public.students s join public.student_programme_enrolments e on e.student_id=s.id and e.is_primary=true join public.programmes p on p.id=e.programme_id where s.institution_id=v_inst and e.enrolment_status='active' and (p_programme_id is null or e.programme_id=p_programme_id)
 loop
  v_final:=greatest(100,round(coalesce(rec.duration_years,rec.current_level/100.0))::int*100); if rec.current_level<v_final then continue; end if;
  v_required:=rec.total_credits;
  select coalesce(sum(z.credit_hours),0),case when sum(z.credit_hours)>0 then round(sum(z.grade_point*z.credit_hours)/sum(z.credit_hours),3) end into v_earned,v_cgpa from (select distinct on(co.course_id) co.course_id,c.credit_hours,cr.grade_point from public.course_results cr join public.course_offerings co on co.id=cr.course_offering_id join public.courses c on c.id=co.course_id where cr.student_id=rec.student_id and cr.result_status='published' and cr.passed=true order by co.course_id,cr.published_at desc nulls last)z;
  -- Keep award CGPA consistent with published transcript GPA: include every published attempt.
  select case when sum(c.credit_hours)>0 then round(sum(c.credit_hours*coalesce(cr.grade_point,0))/sum(c.credit_hours),3) end into v_cgpa
  from public.course_results cr join public.course_offerings co on co.id=cr.course_offering_id join public.courses c on c.id=co.course_id
  where cr.student_id=rec.student_id and cr.institution_id=v_inst and cr.result_status='published';
  select count(*) into v_trails from public.student_academic_trails where student_id=rec.student_id and status in('outstanding','registered');
  v_reasons:='[]'::jsonb;
  if v_required is null or v_required<=0 then v_reasons:=v_reasons||jsonb_build_array('Programme total credits are not configured'); elsif v_earned<v_required then v_reasons:=v_reasons||jsonb_build_array(format('Credits earned %s below programme requirement %s',v_earned,v_required)); end if;
  if v_trails>0 then v_reasons:=v_reasons||jsonb_build_array(format('%s outstanding trail course(s)',v_trails)); end if;
  v_class:=public.unimis_resolve_degree_classification(rec.programme_id,v_cgpa);
  if v_cgpa is not null and (v_class->>'scheme_id') is null then v_reasons:=v_reasons||jsonb_build_array('Degree classification scheme is not configured');
  elsif v_cgpa is not null and (v_class->>'classification') is null then v_reasons:=v_reasons||jsonb_build_array(format('CGPA %s does not match a degree classification band',v_cgpa)); end if;
  v_decision:=case when jsonb_array_length(v_reasons)=0 then 'eligible' else 'completion_exception' end;
  insert into public.graduation_reviews(institution_id,academic_year_id,student_id,programme_enrolment_id,programme_id,final_level,credits_required,credits_earned,cgpa,outstanding_trails,classification_scheme_id,award_classification,decision,reasons,evaluated_at,updated_at)
  values(v_inst,p_academic_year_id,rec.student_id,rec.enrolment_id,rec.programme_id,v_final,v_required,v_earned,v_cgpa,v_trails,nullif(v_class->>'scheme_id','')::uuid,v_class->>'classification',v_decision,v_reasons,now(),now())
  on conflict(academic_year_id,student_id,programme_enrolment_id) do update set final_level=excluded.final_level,credits_required=excluded.credits_required,credits_earned=excluded.credits_earned,cgpa=excluded.cgpa,outstanding_trails=excluded.outstanding_trails,classification_scheme_id=excluded.classification_scheme_id,award_classification=excluded.award_classification,decision=case when graduation_reviews.decision in('approved','graduated') then graduation_reviews.decision else excluded.decision end,reasons=excluded.reasons,evaluated_at=now(),updated_at=now(); n:=n+1;
 end loop;
 return jsonb_build_object('evaluated',n);
end $$;
commit;
