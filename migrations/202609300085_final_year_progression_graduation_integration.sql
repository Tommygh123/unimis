-- UniMIS 085 — Final-year progression -> graduation integration + controlled L300 test case
begin;

-- Harden final-year detection: duration_years is a duration (4 => level 400), while
-- current_level is the authoritative official level changed by progression.
create or replace function public.unimis_evaluate_graduation(p_academic_year_id uuid,p_programme_id uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid; rec record; v_final int; v_earned numeric; v_cgpa numeric; v_trails int; v_required numeric; v_reasons jsonb; v_decision text; n int:=0;
begin
 v_inst:=public.unimis_progression_access(); if v_inst is null then raise exception 'Graduation access required'; end if;
 perform public.unimis_sync_academic_trails(null);
 for rec in
   select s.id student_id,e.id enrolment_id,e.programme_id,e.current_level,p.duration_years,p.total_credits
   from public.students s
   join public.student_programme_enrolments e on e.student_id=s.id and e.is_primary=true
   join public.programmes p on p.id=e.programme_id
   where s.institution_id=v_inst and e.enrolment_status='active'
     and s.status<>'graduated'
     and (p_programme_id is null or e.programme_id=p_programme_id)
 loop
  v_final:=case when rec.duration_years is not null and rec.duration_years>0 then round(rec.duration_years*100)::int else null end;
  if v_final is null then continue; end if;
  if rec.current_level < v_final then continue; end if;
  v_required:=rec.total_credits;
  select coalesce(sum(z.credit_hours),0),case when sum(z.credit_hours)>0 then round(sum(z.grade_point*z.credit_hours)/sum(z.credit_hours),3) end
    into v_earned,v_cgpa
  from (
    select distinct on(co.course_id) co.course_id,c.credit_hours,cr.grade_point
    from public.course_results cr join public.course_offerings co on co.id=cr.course_offering_id join public.courses c on c.id=co.course_id
    where cr.student_id=rec.student_id and cr.result_status='published' and cr.passed=true
    order by co.course_id,cr.published_at desc nulls last
  ) z;
  select count(*) into v_trails from public.student_academic_trails where student_id=rec.student_id and status in('outstanding','registered');
  v_reasons:='[]'::jsonb;
  if v_required is null or v_required<=0 then v_reasons:=v_reasons||jsonb_build_array('Programme total credits are not configured');
  elsif v_earned<v_required then v_reasons:=v_reasons||jsonb_build_array(format('Credits earned %s below programme requirement %s',v_earned,v_required)); end if;
  if v_trails>0 then v_reasons:=v_reasons||jsonb_build_array(format('%s outstanding trail course(s)',v_trails)); end if;
  v_decision:=case when jsonb_array_length(v_reasons)=0 then 'eligible' else 'completion_exception' end;
  insert into public.graduation_reviews(institution_id,academic_year_id,student_id,programme_enrolment_id,programme_id,final_level,credits_required,credits_earned,cgpa,outstanding_trails,decision,reasons,evaluated_at,updated_at)
  values(v_inst,p_academic_year_id,rec.student_id,rec.enrolment_id,rec.programme_id,v_final,v_required,v_earned,v_cgpa,v_trails,v_decision,v_reasons,now(),now())
  on conflict(academic_year_id,student_id,programme_enrolment_id) do update set final_level=excluded.final_level,credits_required=excluded.credits_required,credits_earned=excluded.credits_earned,cgpa=excluded.cgpa,outstanding_trails=excluded.outstanding_trails,decision=case when graduation_reviews.decision in('approved','graduated') then graduation_reviews.decision else excluded.decision end,reasons=excluded.reasons,evaluated_at=now(),updated_at=now();
  n:=n+1;
 end loop;
 return jsonb_build_object('evaluated',n);
end $$;
grant execute on function public.unimis_evaluate_graduation(uuid,uuid) to authenticated;

-- Optional L300 test cohort archived; graduation function and grant above retained.
commit;
