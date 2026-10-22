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
  v_failed jsonb := '[]'::jsonb;
  v_reason text;
begin
  select s.id into v_student
  from public.students s
  where s.user_id=auth.uid()
  limit 1;

  if v_student is null then
    raise exception 'Student profile not found';
  end if;

  select pr.id,pr.student_id,pr.academic_year_id,pr.decision,
         pr.from_level,pr.proposed_level,pr.credits_earned,
         pr.failed_credits,pr.courses_failed,pr.override_reason,
         pr.reasons,pr.updated_at,ay.name academic_year
  into r
  from public.student_progression_reviews pr
  join public.academic_years ay on ay.id=pr.academic_year_id
  where pr.student_id=v_student
    and pr.decision in ('promoted','repeat','probation','deferred','withdrawn')
  order by pr.updated_at desc
  limit 1;

  if r.id is null then return '{}'::jsonb; end if;

  -- reasons is jsonb in the current schema, not text[].
  -- Convert common JSON shapes safely instead of calling array_to_string(jsonb,...).
  v_reason := nullif(trim(r.override_reason),'');

  if v_reason is null and r.reasons is not null then
    if jsonb_typeof(r.reasons)='array' then
      select string_agg(value,'; ' order by ordinality)
      into v_reason
      from jsonb_array_elements_text(r.reasons) with ordinality as x(value,ordinality);
    elsif jsonb_typeof(r.reasons)='string' then
      v_reason := trim(both '"' from r.reasons::text);
    else
      v_reason := r.reasons::text;
    end if;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
      'course_code',c.code,'course_name',c.name,'credits',c.credit_hours,
      'grade',cr.letter_grade,'score',cr.total_score
    ) order by c.code),'[]'::jsonb)
  into v_failed
  from public.course_results cr
  join public.course_offerings co on co.id=cr.course_offering_id
  join public.courses c on c.id=co.course_id
  join public.academic_periods ap on ap.id=co.academic_period_id
  where cr.student_id=v_student
    and ap.academic_year_id=r.academic_year_id
    and cr.result_status='published'
    and coalesce(cr.passed,false)=false;

  return jsonb_build_object(
    'review_id',r.id,
    'decision',r.decision,
    'academic_year',r.academic_year,
    'from_level',r.from_level,
    'proposed_level',r.proposed_level,
    'credits_earned',coalesce(r.credits_earned,0),
    'failed_credits',coalesce(r.failed_credits,0),
    'courses_failed',coalesce(r.courses_failed,0),
    'reason',v_reason,
    'failed_courses',v_failed,
    'finalized_at',r.updated_at
  );
end $$;

revoke all on function public.unimis_student_progression_status() from public;
grant execute on function public.unimis_student_progression_status() to authenticated;
notify pgrst,'reload schema';

commit;
