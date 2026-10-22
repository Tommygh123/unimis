
begin;

create or replace function public.unimis_student_academic_standing()
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_student public.students%rowtype;
  v_grad record;
  v_prog record;
  v_trails jsonb;
  v_courses int:=0;
  v_credits numeric:=0;
  v_kind text:='active';
  v_title text:='Active Student';
  v_message text:='Continue with your current academic activities.';
begin
  select * into v_student from public.students where user_id=auth.uid() limit 1;
  if v_student.id is null then raise exception 'Student account not found'; end if;

  select * into v_grad
  from public.graduation_reviews
  where student_id=v_student.id
  order by evaluated_at desc nulls last
  limit 1;

  select coalesce(jsonb_agg(jsonb_build_object(
    'course_code',t.course_code,'course_name',t.course_name,'credit_hours',t.credit_hours,
    'failed_score',t.failed_score,'failed_grade',t.failed_grade,'status',t.status
  ) order by t.course_code),'[]'::jsonb),
  count(*),coalesce(sum(t.credit_hours),0)
  into v_trails,v_courses,v_credits
  from public.academic_trails t
  where t.student_id=v_student.id and t.status='outstanding';

  if v_grad.id is not null and v_grad.decision='completion_exception' then
    v_kind:='completion_exception';
    v_title:='Programme Completion Pending';
    v_message:=coalesce(v_grad.reason,'Outstanding academic requirements must be cleared before graduation eligibility.');
  else
    select * into v_prog
    from public.student_progression_decisions
    where student_id=v_student.id
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
      v_message:=coalesce(v_prog.override_reason,'Your latest official progression decision is shown here.');
    elsif v_courses>0 then
      v_kind:='trail';
      v_title:='Academic Trail Outstanding';
      v_message:='You have outstanding course requirements to clear.';
    end if;
  end if;

  return jsonb_build_object(
    'kind',v_kind,'title',v_title,'message',v_message,
    'outstanding_courses',v_courses,'outstanding_credits',v_credits,'trails',v_trails
  );
end $$;

grant execute on function public.unimis_student_academic_standing() to authenticated;
commit;
