begin;

-- UniMIS 081
-- Connect the flexible grading resolver (079) to the CURRENT result functions
-- found in the uploaded migration set.
--
-- Resolution for every student result:
--   Course override -> Student programme -> Institution default
--
-- Existing approved/published results are NOT regraded by this migration.

create or replace function public.unimis_lecturer_result_preview(p_course_offering_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_inst uuid;
  v_lp uuid;
  v_weight numeric;
  v_count int;
begin
  select institution_id,lecturer_profile_id
    into v_inst,v_lp
  from public.unimis_current_lecturer();

  if not exists(
    select 1
    from public.course_lecturers
    where institution_id=v_inst
      and lecturer_profile_id=v_lp
      and course_offering_id=p_course_offering_id
  ) then
    raise exception 'You are not allocated to this course offering';
  end if;

  select coalesce(sum(weight_percent),0),count(*)
    into v_weight,v_count
  from public.assessment_items
  where institution_id=v_inst
    and course_offering_id=p_course_offering_id
    and status<>'cancelled';

  return jsonb_build_object(
    -- Kept for backward compatibility. With flexible grading, the actual
    -- applicable scheme is resolved per student and returned on each row.
    'grading_scheme_id',null,
    'grading_resolution','course_override -> student_programme -> institution_default',
    'assessment_weight',v_weight,
    'assessment_count',v_count,
    'ready',v_count>0 and v_weight=100,
    'students',coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'student_id',q.student_id,
          'course_registration_id',q.scr_id,
          'student_number',q.student_number,
          'student_name',q.student_name,
          'total_score',q.total_score,
          'missing_assessments',q.missing_count,
          'grading_scheme_id',q.scheme_id,
          'grading_scheme_code',gs.code,
          'grading_scheme_name',gs.name,
          'letter_grade',gb.letter_grade,
          'grade_point',gb.grade_point,
          'passed',gb.is_pass,
          'result_status',cr.result_status,
          'remarks',cr.remarks
        )
        order by q.student_name
      )
      from (
        select
          s.id student_id,
          scr.id scr_id,
          s.student_number,
          concat_ws(' ',s.first_name,s.middle_name,s.last_name) student_name,
          coalesce(sum(sc.weighted_score),0)::numeric(7,2) total_score,
          count(ai.id) filter(where sc.id is null) missing_count,
          public.unimis_resolve_grading_scheme(p_course_offering_id,s.id) scheme_id
        from public.student_course_registrations scr
        join public.student_period_registrations spr
          on spr.id=scr.period_registration_id
        join public.students s
          on s.id=scr.student_id
        cross join public.assessment_items ai
        left join public.assessment_scores sc
          on sc.assessment_item_id=ai.id
         and sc.student_course_registration_id=scr.id
        where scr.institution_id=v_inst
          and scr.course_offering_id=p_course_offering_id
          and lower(coalesce(scr.status,'')) not in ('dropped','cancelled','withdrawn')
          and lower(coalesce(spr.registration_status,''))='approved'
          and ai.institution_id=v_inst
          and ai.course_offering_id=p_course_offering_id
          and ai.status<>'cancelled'
        group by s.id,scr.id,s.student_number,s.first_name,s.middle_name,s.last_name
      ) q
      join public.grading_schemes gs
        on gs.id=q.scheme_id
      left join lateral (
        select b.*
        from public.grade_bands b
        where b.institution_id=v_inst
          and b.grading_scheme_id=q.scheme_id
          and q.total_score>=b.min_score
          and q.total_score<=b.max_score
        order by b.min_score desc
        limit 1
      ) gb on true
      left join public.course_results cr
        on cr.student_course_registration_id=q.scr_id
    ),'[]'::jsonb)
  );
end $$;

grant execute on function public.unimis_lecturer_result_preview(uuid) to authenticated;


create or replace function public.unimis_submit_course_results(p_course_offering_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_inst uuid;
  v_lp uuid;
  v_weight numeric;
  v_assess int;
  v_credit numeric;
  v_scheme uuid;
  r record;
  b record;
  n int:=0;
  old_status text;
begin
  select institution_id,lecturer_profile_id
    into v_inst,v_lp
  from public.unimis_current_lecturer();

  if not exists(
    select 1
    from public.course_lecturers
    where institution_id=v_inst
      and lecturer_profile_id=v_lp
      and course_offering_id=p_course_offering_id
  ) then
    raise exception 'You are not allocated to this course offering';
  end if;

  select c.credit_hours
    into v_credit
  from public.course_offerings co
  join public.courses c on c.id=co.course_id
  where co.id=p_course_offering_id
    and co.institution_id=v_inst;

  if v_credit is null then
    raise exception 'Course offering or course credit hours could not be resolved';
  end if;

  select coalesce(sum(weight_percent),0),count(*)
    into v_weight,v_assess
  from public.assessment_items
  where institution_id=v_inst
    and course_offering_id=p_course_offering_id
    and status<>'cancelled';

  if v_assess=0 or v_weight<>100 then
    raise exception
      'Assessment weights must total exactly 100%% before results can be submitted. Current total: %%%',
      v_weight;
  end if;

  for r in
    select
      s.id student_id,
      scr.id scr_id,
      coalesce(sum(sc.weighted_score),0)::numeric(7,2) total_score,
      count(ai.id) filter(where sc.id is null) missing_count
    from public.student_course_registrations scr
    join public.student_period_registrations spr
      on spr.id=scr.period_registration_id
    join public.students s
      on s.id=scr.student_id
    cross join public.assessment_items ai
    left join public.assessment_scores sc
      on sc.assessment_item_id=ai.id
     and sc.student_course_registration_id=scr.id
    where scr.institution_id=v_inst
      and scr.course_offering_id=p_course_offering_id
      and lower(coalesce(scr.status,'')) not in ('dropped','cancelled','withdrawn')
      and lower(coalesce(spr.registration_status,''))='approved'
      and ai.institution_id=v_inst
      and ai.course_offering_id=p_course_offering_id
      and ai.status<>'cancelled'
    group by s.id,scr.id
  loop
    if r.missing_count>0 then
      raise exception 'Cannot submit: at least one registered student has missing assessment marks';
    end if;

    -- 079 resolver: course -> student's programme -> institution default.
    v_scheme:=public.unimis_resolve_grading_scheme(
      p_course_offering_id,
      r.student_id
    );

    select *
      into b
    from public.grade_bands
    where institution_id=v_inst
      and grading_scheme_id=v_scheme
      and r.total_score>=min_score
      and r.total_score<=max_score
    order by min_score desc
    limit 1;

    if b.id is null then
      raise exception
        'No grade band in the resolved grading scheme covers score % for student %',
        r.total_score,r.student_id;
    end if;

    select result_status
      into old_status
    from public.course_results
    where student_course_registration_id=r.scr_id;

    if old_status in ('approved','published') then
      raise exception 'Approved or published results cannot be resubmitted';
    end if;

    insert into public.course_results(
      institution_id,
      student_course_registration_id,
      student_id,
      course_offering_id,
      grading_scheme_id,
      total_score,
      letter_grade,
      grade_point,
      quality_points,
      result_status,
      passed,
      submitted_by,
      submitted_at
    )
    values(
      v_inst,
      r.scr_id,
      r.student_id,
      p_course_offering_id,
      v_scheme,
      r.total_score,
      b.letter_grade,
      b.grade_point,
      round(b.grade_point*coalesce(v_credit,0),2),
      'submitted',
      b.is_pass,
      auth.uid(),
      now()
    )
    on conflict(student_course_registration_id)
    do update set
      grading_scheme_id=excluded.grading_scheme_id,
      total_score=excluded.total_score,
      letter_grade=excluded.letter_grade,
      grade_point=excluded.grade_point,
      quality_points=excluded.quality_points,
      result_status='submitted',
      passed=excluded.passed,
      submitted_by=auth.uid(),
      submitted_at=now(),
      approved_by=null,
      approved_at=null,
      published_at=null,
      updated_at=now();

    insert into public.result_approval_history(
      institution_id,course_result_id,old_status,new_status,
      action_by,action_at,notes
    )
    select
      v_inst,id,coalesce(old_status,'draft'),'submitted',
      auth.uid(),now(),
      'Submitted by lecturer; grading scheme resolved automatically'
    from public.course_results
    where student_course_registration_id=r.scr_id;

    n:=n+1;
  end loop;

  return jsonb_build_object(
    'submitted',n,
    'grading_resolution','course_override -> student_programme -> institution_default'
  );
end $$;

grant execute on function public.unimis_submit_course_results(uuid) to authenticated;


-- Keep the older reusable calculator consistent with the same resolver.
create or replace function public.calculate_course_result(
  requested_student_course_registration_id uuid
)
returns uuid
language plpgsql
security definer
set search_path=''
as $$
declare
  scr public.student_course_registrations%rowtype;
  co public.course_offerings%rowtype;
  crs public.courses%rowtype;
  scheme_id uuid;
  total numeric(6,2);
  band public.grade_bands%rowtype;
  result_id uuid;
begin
  select *
    into scr
  from public.student_course_registrations
  where id=requested_student_course_registration_id;

  if not found then
    raise exception 'Student course registration not found';
  end if;

  if not public.has_permission(scr.institution_id,'results.enter')
     and not public.has_permission(scr.institution_id,'results.approve') then
    raise exception 'Not authorised';
  end if;

  select *
    into co
  from public.course_offerings
  where id=scr.course_offering_id;

  if not found then
    raise exception 'Course offering not found';
  end if;

  select *
    into crs
  from public.courses
  where id=co.course_id;

  scheme_id:=public.unimis_resolve_grading_scheme(
    scr.course_offering_id,
    scr.student_id
  );

  select coalesce(sum(ascs.weighted_score),0)
    into total
  from public.assessment_scores ascs
  join public.assessment_items ai
    on ai.id=ascs.assessment_item_id
  where ascs.student_course_registration_id=scr.id
    and ai.course_offering_id=scr.course_offering_id
    and ascs.status in ('entered','verified','published');

  select *
    into band
  from public.grade_bands gb
  where gb.grading_scheme_id=scheme_id
    and total between gb.min_score and gb.max_score
  order by gb.min_score desc
  limit 1;

  if band.id is null then
    raise exception 'No grade band matches total score % in the resolved grading scheme',total;
  end if;

  insert into public.course_results(
    institution_id,
    student_course_registration_id,
    student_id,
    course_offering_id,
    grading_scheme_id,
    total_score,
    letter_grade,
    grade_point,
    quality_points,
    result_status,
    passed
  )
  values(
    scr.institution_id,
    scr.id,
    scr.student_id,
    scr.course_offering_id,
    scheme_id,
    total,
    band.letter_grade,
    band.grade_point,
    round(band.grade_point*coalesce(crs.credit_hours,0),2),
    'draft',
    band.is_pass
  )
  on conflict(student_course_registration_id)
  do update set
    grading_scheme_id=excluded.grading_scheme_id,
    total_score=excluded.total_score,
    letter_grade=excluded.letter_grade,
    grade_point=excluded.grade_point,
    quality_points=excluded.quality_points,
    passed=excluded.passed,
    updated_at=now()
  returning id into result_id;

  return result_id;
end $$;

revoke all on function public.calculate_course_result(uuid) from public;
grant execute on function public.calculate_course_result(uuid) to authenticated;


-- Analytics preview for students without a course_result must also use the
-- same scheme that would be used on submission.
create or replace function public.unimis_result_analytics_core(
  p_inst uuid,
  p_course_offering_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_course uuid;
  v_n int;
  v_avg numeric;
  v_min numeric;
  v_max numeric;
  v_pass int;
  v_ca numeric;
  v_exam numeric;
begin
  select course_id
    into v_course
  from public.course_offerings
  where id=p_course_offering_id
    and institution_id=p_inst;

  with x as (
    select cr.total_score,cr.passed
    from public.course_results cr
    where cr.institution_id=p_inst
      and cr.course_offering_id=p_course_offering_id

    union all

    select q.total_score,gb.is_pass
    from (
      select
        scr.id,
        scr.student_id,
        coalesce(sum(sc.weighted_score),0)::numeric total_score,
        public.unimis_resolve_grading_scheme(
          p_course_offering_id,
          scr.student_id
        ) scheme_id
      from public.student_course_registrations scr
      join public.student_period_registrations spr
        on spr.id=scr.period_registration_id
      join public.assessment_items ai
        on ai.course_offering_id=scr.course_offering_id
       and ai.status<>'cancelled'
      left join public.assessment_scores sc
        on sc.assessment_item_id=ai.id
       and sc.student_course_registration_id=scr.id
      where scr.institution_id=p_inst
        and scr.course_offering_id=p_course_offering_id
        and lower(spr.registration_status)='approved'
        and not exists(
          select 1
          from public.course_results cr
          where cr.student_course_registration_id=scr.id
        )
      group by scr.id,scr.student_id
    ) q
    left join lateral(
      select b.is_pass
      from public.grade_bands b
      where b.grading_scheme_id=q.scheme_id
        and q.total_score between b.min_score and b.max_score
      order by b.min_score desc
      limit 1
    ) gb on true
  )
  select
    count(*),
    round(avg(total_score),2),
    min(total_score),
    max(total_score),
    count(*) filter(where passed)
  into v_n,v_avg,v_min,v_max,v_pass
  from x;

  select round(avg(sc.raw_score),2)
    into v_ca
  from public.assessment_scores sc
  join public.assessment_items ai on ai.id=sc.assessment_item_id
  where ai.course_offering_id=p_course_offering_id
    and ai.name='Continuous Assessment';

  select round(avg(sc.raw_score),2)
    into v_exam
  from public.assessment_scores sc
  join public.assessment_items ai on ai.id=sc.assessment_item_id
  where ai.course_offering_id=p_course_offering_id
    and ai.name='Final Examination';

  return jsonb_build_object(
    'student_count',coalesce(v_n,0),
    'average',coalesce(v_avg,0),
    'lowest',coalesce(v_min,0),
    'highest',coalesce(v_max,0),
    'pass_count',coalesce(v_pass,0),
    'fail_count',greatest(coalesce(v_n,0)-coalesce(v_pass,0),0),
    'pass_rate',case when v_n>0 then round(v_pass*100.0/v_n,1) else 0 end,
    'ca_average',v_ca,
    'exam_average',v_exam,
    'grade_distribution',coalesce((
      select jsonb_agg(
        jsonb_build_object('grade',letter_grade,'count',n)
        order by maxgp desc
      )
      from (
        select
          coalesce(cr.letter_grade,'—') letter_grade,
          count(*) n,
          max(coalesce(cr.grade_point,0)) maxgp
        from public.course_results cr
        where cr.institution_id=p_inst
          and cr.course_offering_id=p_course_offering_id
        group by cr.letter_grade
      ) g
    ),'[]'::jsonb),
    'trend',coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'period',z.period_name,
          'average',z.avg_score,
          'pass_rate',z.pass_rate,
          'students',z.n
        )
        order by z.start_date
      )
      from (
        select
          ap.name period_name,
          ap.start_date,
          count(*) n,
          round(avg(cr.total_score),2) avg_score,
          round(
            count(*) filter(where cr.passed)*100.0/nullif(count(*),0),
            1
          ) pass_rate
        from public.course_results cr
        join public.course_offerings co on co.id=cr.course_offering_id
        join public.academic_periods ap on ap.id=co.academic_period_id
        where cr.institution_id=p_inst
          and co.course_id=v_course
          and cr.result_status in ('submitted','approved','published')
        group by ap.id,ap.name,ap.start_date
      ) z
    ),'[]'::jsonb)
  );
end $$;

-- Diagnostic helper for administrators/testing.
-- It proves which scheme UniMIS will use before a result is submitted.
create or replace function public.unimis_result_grading_diagnostic(
  p_course_offering_id uuid,
  p_student_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_inst uuid;
  v_result jsonb;
  v_existing jsonb;
begin
  select institution_id
    into v_inst
  from public.course_offerings
  where id=p_course_offering_id;

  if v_inst is null then
    raise exception 'Course offering not found';
  end if;

  v_result:=public.unimis_explain_grading_resolution(
    p_course_offering_id,
    p_student_id
  );

  select jsonb_build_object(
    'result_status',cr.result_status,
    'score',cr.total_score,
    'letter_grade',cr.letter_grade,
    'grade_point',cr.grade_point,
    'quality_points',cr.quality_points,
    'stored_scheme_id',cr.grading_scheme_id
  )
  into v_existing
  from public.course_results cr
  where cr.course_offering_id=p_course_offering_id
    and cr.student_id=p_student_id;

  return v_result || jsonb_build_object(
    'existing_result',coalesce(v_existing,'{}'::jsonb),
    'note','Approved/published historical results are not automatically regraded.'
  );
end $$;

grant execute on function public.unimis_result_analytics_core(uuid,uuid) to authenticated;
grant execute on function public.unimis_result_grading_diagnostic(uuid,uuid) to authenticated;

notify pgrst,'reload schema';
commit;
