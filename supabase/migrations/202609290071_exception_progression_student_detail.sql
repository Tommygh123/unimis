
begin;

create or replace function public.unimis_student_progression_status()
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_student uuid;
  r record;
  v_failed jsonb;
begin
  select s.id into v_student
  from public.students s
  where s.user_id=auth.uid()
  limit 1;

  if v_student is null then
    raise exception 'Student profile not found';
  end if;

  select
    pr.id, pr.decision, pr.from_level, pr.proposed_level,
    pr.credits_earned, pr.failed_credits, pr.courses_failed,
    pr.override_reason, pr.reasons, pr.updated_at,
    ay.name academic_year
  into r
  from public.student_progression_reviews pr
  join public.academic_years ay on ay.id=pr.academic_year_id
  where pr.student_id=v_student
    and pr.decision in ('promoted','repeat','probation','deferred','withdrawn')
  order by ay.start_date desc, pr.updated_at desc
  limit 1;

  if r.id is null then
    return '{}'::jsonb;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'course_code',c.code,
    'course_name',c.name,
    'credits',c.credit_hours,
    'grade',cr.letter_grade,
    'score',cr.total_score
  ) order by c.code),'[]'::jsonb)
  into v_failed
  from public.course_results cr
  join public.course_offerings co on co.id=cr.course_offering_id
  join public.courses c on c.id=co.course_id
  join public.academic_periods ap on ap.id=co.academic_period_id
  join public.academic_years ay on ay.id=ap.academic_year_id
  where cr.student_id=v_student
    and ay.name=r.academic_year
    and cr.result_status='published'
    and coalesce(cr.passed,false)=false;

  return jsonb_build_object(
    'review_id',r.id,
    'decision',r.decision,
    'academic_year',r.academic_year,
    'from_level',r.from_level,
    'proposed_level',r.proposed_level,
    'credits_earned',r.credits_earned,
    'failed_credits',r.failed_credits,
    'courses_failed',r.courses_failed,
    'reason',coalesce(nullif(r.override_reason,''), array_to_string(r.reasons,'; ')),
    'failed_courses',v_failed,
    'finalized_at',r.updated_at
  );
end $$;

grant execute on function public.unimis_student_progression_status() to authenticated;

commit;
