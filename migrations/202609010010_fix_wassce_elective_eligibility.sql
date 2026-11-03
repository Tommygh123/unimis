-- ============================================================================
-- UniMIS Admissions eligibility correction
-- Fix false Not Eligible when a rule requires electives but has no explicit
-- elective_pool rows. In that case use the applicant's best passing WASSCE
-- subjects that are not already compulsory/required subjects.
-- ============================================================================

begin;

create or replace function public.unimis_evaluate_application_eligibility(
  p_application_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_app public.applications%rowtype;
  v_choice record;
  v_rule public.programme_admission_rules%rowtype;
  v_required_total integer;
  v_required_passed integer;
  v_elective_passed integer;
  v_core_sum integer;
  v_elective_sum integer;
  v_aggregate integer;
  v_results_verified boolean;
  v_failed_required jsonb;
  v_elective_detail jsonb;
  v_rows jsonb := '[]'::jsonb;
  v_status text;
  v_has_explicit_elective_pool boolean;
begin
  select * into v_app
  from public.applications
  where id = p_application_id;

  if not found then
    raise exception 'Application not found.';
  end if;

  if auth.role() <> 'service_role'
     and not public.unimis_is_institution_member(v_app.institution_id)
     and not public.unimis_applicant_owns_application(p_application_id) then
    raise exception 'Not authorized.' using errcode='42501';
  end if;

  for v_choice in
    select ch.choice_order, p.id as programme_id, p.code, p.name
    from public.application_choices ch
    join public.programmes p on p.id = ch.programme_id
    where ch.application_id = p_application_id
    order by ch.choice_order
  loop
    select r.* into v_rule
    from public.programme_admission_rules r
    where r.institution_id = v_app.institution_id
      and r.programme_id = v_choice.programme_id
      and r.is_active = true
      and upper(r.qualification_type) in (
        select upper(q.qualification_type)
        from public.applicant_qualifications q
        where q.applicant_id = v_app.applicant_id
      )
      and (r.admission_cycle_id = v_app.admission_cycle_id or r.admission_cycle_id is null)
    order by (r.admission_cycle_id = v_app.admission_cycle_id) desc,
             r.updated_at desc
    limit 1;

    if not found then
      v_rows := v_rows || jsonb_build_array(jsonb_build_object(
        'choice_order', v_choice.choice_order,
        'programme_id', v_choice.programme_id,
        'programme_code', v_choice.code,
        'programme_name', v_choice.name,
        'status', 'not_configured',
        'qualification_verified', false,
        'aggregate', null,
        'message', 'No active admission rule is configured for this programme and qualification.'
      ));
      continue;
    end if;

    -- Required/compulsory subjects.
    with best as (
      select public.unimis_subject_key(sr.subject_name) as subject_key,
             min(sr.grade_rank) as grade_rank
      from public.applicant_subject_results sr
      join public.applicant_qualifications q on q.id = sr.qualification_id
      where sr.applicant_id = v_app.applicant_id
        and upper(q.qualification_type) = upper(v_rule.qualification_type)
      group by public.unimis_subject_key(sr.subject_name)
    ), required_rules as (
      select s.*,
             coalesce(s.max_grade_rank, v_rule.default_max_grade_rank) as threshold
      from public.programme_admission_subject_rules s
      where s.rule_id = v_rule.id
        and s.subject_group = 'required'
    )
    select
      count(*)::integer,
      count(*) filter (where b.grade_rank is not null and b.grade_rank <= rr.threshold)::integer,
      coalesce(sum(b.grade_rank) filter (where b.grade_rank is not null and b.grade_rank <= rr.threshold),0)::integer,
      coalesce(jsonb_agg(jsonb_build_object(
        'subject',rr.subject_name,
        'max_grade_rank',rr.threshold,
        'best_grade_rank',b.grade_rank
      )) filter (where b.grade_rank is null or b.grade_rank > rr.threshold),'[]'::jsonb)
    into v_required_total, v_required_passed, v_core_sum, v_failed_required
    from required_rules rr
    left join best b on b.subject_key = public.unimis_subject_key(rr.subject_name);

    select exists (
      select 1
      from public.programme_admission_subject_rules s
      where s.rule_id = v_rule.id
        and s.subject_group = 'elective_pool'
    ) into v_has_explicit_elective_pool;

    if v_has_explicit_elective_pool then
      -- Programme has explicitly limited the subjects that may count as electives.
      with best as (
        select public.unimis_subject_key(sr.subject_name) as subject_key,
               min(sr.grade_rank) as grade_rank,
               (array_agg(sr.grade order by sr.grade_rank asc))[1] as grade
        from public.applicant_subject_results sr
        join public.applicant_qualifications q on q.id = sr.qualification_id
        where sr.applicant_id = v_app.applicant_id
          and upper(q.qualification_type) = upper(v_rule.qualification_type)
        group by public.unimis_subject_key(sr.subject_name)
      ), pool as (
        select s.subject_name,
               public.unimis_subject_key(s.subject_name) as subject_key,
               coalesce(s.max_grade_rank, v_rule.default_max_grade_rank) as threshold,
               b.grade_rank, b.grade
        from public.programme_admission_subject_rules s
        left join best b
          on b.subject_key = public.unimis_subject_key(s.subject_name)
        where s.rule_id = v_rule.id
          and s.subject_group = 'elective_pool'
      ), passed as (
        select * from pool
        where grade_rank is not null and grade_rank <= threshold
        order by grade_rank asc, subject_name
      ), chosen as (
        select * from passed
        limit greatest(v_rule.minimum_elective_passes,0)
      )
      select
        (select count(*)::integer from passed),
        coalesce((select sum(grade_rank)::integer from chosen),0),
        coalesce((select jsonb_agg(jsonb_build_object(
          'subject',subject_name,'grade',grade,'grade_rank',grade_rank,
          'max_grade_rank',threshold,'selection_source','configured_pool'
        ) order by grade_rank,subject_name) from passed),'[]'::jsonb)
      into v_elective_passed, v_elective_sum, v_elective_detail;
    else
      -- General WASSCE fallback: if the rule asks for N electives but no
      -- elective pool has been configured, take the applicant's best N
      -- passing subjects that are NOT already compulsory subjects.
      with required_keys as (
        select public.unimis_subject_key(s.subject_name) as subject_key
        from public.programme_admission_subject_rules s
        where s.rule_id = v_rule.id
          and s.subject_group = 'required'
      ), best as (
        select public.unimis_subject_key(sr.subject_name) as subject_key,
               (array_agg(sr.subject_name order by sr.grade_rank asc))[1] as subject_name,
               min(sr.grade_rank) as grade_rank,
               (array_agg(sr.grade order by sr.grade_rank asc))[1] as grade
        from public.applicant_subject_results sr
        join public.applicant_qualifications q on q.id = sr.qualification_id
        where sr.applicant_id = v_app.applicant_id
          and upper(q.qualification_type) = upper(v_rule.qualification_type)
        group by public.unimis_subject_key(sr.subject_name)
      ), passed as (
        select b.subject_name, b.subject_key, b.grade_rank, b.grade,
               v_rule.default_max_grade_rank as threshold
        from best b
        where not exists (
          select 1 from required_keys rk where rk.subject_key = b.subject_key
        )
          and b.grade_rank <= v_rule.default_max_grade_rank
        order by b.grade_rank asc, b.subject_name
      ), chosen as (
        select * from passed
        limit greatest(v_rule.minimum_elective_passes,0)
      )
      select
        (select count(*)::integer from passed),
        coalesce((select sum(grade_rank)::integer from chosen),0),
        coalesce((select jsonb_agg(jsonb_build_object(
          'subject',subject_name,'grade',grade,'grade_rank',grade_rank,
          'max_grade_rank',threshold,'selection_source','best_non_required'
        ) order by grade_rank,subject_name) from chosen),'[]'::jsonb)
      into v_elective_passed, v_elective_sum, v_elective_detail;
    end if;

    v_aggregate := case
      when v_required_total = v_required_passed
       and v_elective_passed >= v_rule.minimum_elective_passes
      then v_core_sum + v_elective_sum
      else null
    end;

    select not exists (
      select 1
      from public.applicant_qualifications q
      where q.applicant_id = v_app.applicant_id
        and upper(q.qualification_type) = upper(v_rule.qualification_type)
        and exists (
          select 1 from public.applicant_subject_results sr
          where sr.qualification_id = q.id
        )
        and coalesce(q.verification_status,'unverified') <> 'verified'
    )
    and exists (
      select 1
      from public.applicant_qualifications q
      where q.applicant_id = v_app.applicant_id
        and upper(q.qualification_type) = upper(v_rule.qualification_type)
        and exists (
          select 1 from public.applicant_subject_results sr
          where sr.qualification_id = q.id
        )
    )
    into v_results_verified;

    if v_required_total = 0
       and v_rule.minimum_elective_passes = 0 then
      v_status := 'not_configured';
    elsif v_required_passed < v_required_total
       or v_elective_passed < v_rule.minimum_elective_passes then
      v_status := 'not_eligible';
    elsif v_rule.max_aggregate is not null
       and v_aggregate is not null
       and v_aggregate > v_rule.max_aggregate then
      v_status := 'not_eligible';
    elsif v_aggregate is null then
      v_status := 'incomplete';
    else
      v_status := 'eligible';
    end if;

    v_rows := v_rows || jsonb_build_array(jsonb_build_object(
      'choice_order', v_choice.choice_order,
      'programme_id', v_choice.programme_id,
      'programme_code', v_choice.code,
      'programme_name', v_choice.name,
      'rule_id', v_rule.id,
      'qualification_type', v_rule.qualification_type,
      'status', v_status,
      'qualification_verified', v_results_verified,
      'aggregate', v_aggregate,
      'max_aggregate', v_rule.max_aggregate,
      'required_subjects_total', v_required_total,
      'required_subjects_passed', v_required_passed,
      'minimum_elective_passes', v_rule.minimum_elective_passes,
      'elective_passes', v_elective_passed,
      'elective_selection_mode', case when v_has_explicit_elective_pool then 'configured_pool' else 'best_non_required' end,
      'failed_required_subjects', coalesce(v_failed_required,'[]'::jsonb),
      'passing_electives', coalesce(v_elective_detail,'[]'::jsonb),
      'message', case
        when v_status = 'eligible' and v_results_verified then 'Academically eligible using verified results.'
        when v_status = 'eligible' then 'Academically eligible provisionally; result verification is still pending.'
        when v_status = 'not_eligible' and v_required_passed < v_required_total then 'One or more compulsory subjects do not satisfy the configured programme rule.'
        when v_status = 'not_eligible' and v_elective_passed < v_rule.minimum_elective_passes then 'Not enough qualifying elective subjects satisfy the configured programme rule.'
        when v_status = 'not_eligible' and v_rule.max_aggregate is not null and v_aggregate > v_rule.max_aggregate then 'The calculated aggregate is above the programme maximum.'
        when v_status = 'incomplete' then 'More structured subject results are required.'
        else 'Admission rule requires configuration.'
      end
    ));
  end loop;

  return jsonb_build_object(
    'application_id', p_application_id,
    'evaluated_at', now(),
    'choices', v_rows
  );
end;
$$;

revoke all on function public.unimis_evaluate_application_eligibility(uuid) from public;
grant execute on function public.unimis_evaluate_application_eligibility(uuid)
  to authenticated, service_role;

commit;

-- Optional test after migration:
-- select public.unimis_evaluate_application_eligibility('<application-id>');
