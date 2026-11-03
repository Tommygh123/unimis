
begin;

create or replace function public.unimis_student_academic_standing()
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_student_id uuid;
  v_grad record;
  v_prog record;
  v_trails jsonb := '[]'::jsonb;
  v_courses integer := 0;
  v_credits numeric := 0;
  v_kind text := 'active';
  v_title text := 'Active Student';
  v_message text := 'Continue with your current academic activities.';
begin
  select s.id into v_student_id
  from public.students s
  where s.user_id=auth.uid()
  limit 1;

  if v_student_id is null then
    raise exception 'Student account not found';
  end if;

  -- Student-facing outstanding courses: published failed results.
  -- DISTINCT ON prevents the same course being counted twice if historical attempts exist.
  with failed as (
    select distinct on (r.course_code)
      r.course_code,
      r.course_name,
      coalesce(r.credit_hours,0) credit_hours,
      r.total_score,
      r.letter_grade
    from public.v_student_results r
    where r.student_id=v_student_id
      and r.result_status='published'
      and coalesce(r.passed,false)=false
    order by r.course_code, r.academic_year desc, r.academic_period desc
  )
  select
    coalesce(jsonb_agg(jsonb_build_object(
      'course_code',course_code,
      'course_name',course_name,
      'credit_hours',credit_hours,
      'failed_score',total_score,
      'failed_grade',letter_grade,
      'status','outstanding'
    ) order by course_code),'[]'::jsonb),
    count(*),
    coalesce(sum(credit_hours),0)
  into v_trails,v_courses,v_credits
  from failed;

  select * into v_grad
  from public.graduation_reviews
  where student_id=v_student_id
  order by evaluated_at desc nulls last
  limit 1;

  if v_grad.id is not null and v_grad.decision='completion_exception' then
    v_kind:='completion_exception';
    v_title:='Programme Completion Pending';
    v_message:=case
      when v_courses>0 then
        'Graduation is pending until the outstanding academic requirement is cleared.'
      else
        coalesce(v_grad.reason,'Programme completion requirements have not yet been satisfied.')
    end;
  else
    select * into v_prog
    from public.student_progression_decisions
    where student_id=v_student_id
    order by updated_at desc nulls last, created_at desc nulls last
    limit 1;

    if v_prog.id is not null then
      v_kind:=coalesce(v_prog.decision,'active');
      v_title:=case v_prog.decision
        when 'repeat' then 'Repeat Level '||v_prog.from_level
        when 'probation' then 'Academic Probation'
        when 'deferred' then 'Progression Deferred'
        when 'promoted' then 'Progressed to Level '||v_prog.proposed_level
        else initcap(replace(v_prog.decision,'_',' '))
      end;
      v_message:=case
        when v_courses>0 then 'Your progression decision includes outstanding academic requirements shown below.'
        else coalesce(v_prog.override_reason,'Your latest official progression decision is shown here.')
      end;
    elsif v_courses>0 then
      v_kind:='trail';
      v_title:='Academic Trail Outstanding';
      v_message:='You have outstanding course requirements to clear.';
    end if;
  end if;

  return jsonb_build_object(
    'kind',v_kind,
    'title',v_title,
    'message',v_message,
    'outstanding_courses',v_courses,
    'outstanding_credits',v_credits,
    'trails',v_trails
  );
end $$;

grant execute on function public.unimis_student_academic_standing() to authenticated;

commit;
