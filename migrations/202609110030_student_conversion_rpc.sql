-- Accepted applicant -> Student conversion
begin;

create or replace function public.unimis_next_student_number(
  p_institution_id uuid,
  p_academic_year integer
)
returns text
language plpgsql
security definer
set search_path=public
as $$
declare
  v_settings jsonb;
  v_prefix text;
  v_digits integer;
  v_separator text;
  v_include_year boolean;
  v_seq bigint;
begin
  select coalesce(academic_settings->'student_numbering','{}'::jsonb)
  into v_settings
  from public.institution_settings
  where institution_id=p_institution_id;

  v_prefix := coalesce(nullif(v_settings->>'prefix',''),'STU');
  v_digits := greatest(3,least(10,coalesce((v_settings->>'digits')::integer,5)));
  v_separator := coalesce(v_settings->>'separator','/');
  v_include_year := coalesce((v_settings->>'include_year')::boolean,true);

  insert into public.student_number_sequences(institution_id,academic_year,last_number)
  values(p_institution_id,p_academic_year,1)
  on conflict(institution_id,academic_year)
  do update set last_number=public.student_number_sequences.last_number+1,updated_at=now()
  returning last_number into v_seq;

  return v_prefix || v_separator
    || case when v_include_year then p_academic_year::text || v_separator else '' end
    || lpad(v_seq::text,v_digits,'0');
end $$;

create or replace function public.unimis_convert_accepted_application_to_student(
  p_application_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
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

  return jsonb_build_object(
    'ok',true,
    'student_id',v_student.id,
    'student_number',v_number,
    'programme_enrolment_id',v_enrol.id,
    'period_registration_id',v_period_reg.id,
    'academic_year',v_year.name,
    'academic_period',v_period.name
  );
end $$;

grant execute on function public.unimis_next_student_number(uuid,integer) to authenticated;
grant execute on function public.unimis_convert_accepted_application_to_student(uuid) to authenticated;

commit;
