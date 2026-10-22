
begin;

-- 069 silently failed for a student self-call because the helper interpreted any
-- non-null student id as a staff request. Allow the signed-in student to recalculate
-- their own published GPA/CGPA, while retaining staff access for other students.
create or replace function public.unimis_recalculate_student_period_results(p_student_id uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
 v_student uuid; v_inst uuid; v_self uuid;
 pr record; v_attempt numeric; v_earned numeric; v_qp numeric;
 v_gpa numeric; v_cum_attempt numeric:=0; v_cum_qp numeric:=0; v_cgpa numeric; n int:=0;
begin
 select s.id,s.institution_id into v_self,v_inst
 from public.students s where s.user_id=auth.uid() limit 1;

 if p_student_id is null or p_student_id=v_self then
   v_student:=v_self;
 else
   v_inst:=public.unimis_progression_access();
   if v_inst is null then raise exception 'Academic access required'; end if;
   select s.id into v_student from public.students s
   where s.id=p_student_id and s.institution_id=v_inst;
 end if;

 if v_student is null then raise exception 'Student not found'; end if;
 if v_inst is null then select institution_id into v_inst from public.students where id=v_student; end if;

 for pr in
   select ap.id period_id,ap.start_date,ap.period_number
   from public.academic_periods ap
   where exists(
     select 1 from public.course_results cr
     join public.course_offerings co on co.id=cr.course_offering_id
     where cr.student_id=v_student
       and cr.result_status='published'
       and co.academic_period_id=ap.id
   )
   order by ap.start_date,ap.period_number
 loop
   select coalesce(sum(c.credit_hours),0),
          coalesce(sum(c.credit_hours) filter(where cr.passed),0),
          coalesce(sum(c.credit_hours*coalesce(cr.grade_point,0)),0)
   into v_attempt,v_earned,v_qp
   from public.course_results cr
   join public.course_offerings co on co.id=cr.course_offering_id
   join public.courses c on c.id=co.course_id
   where cr.student_id=v_student
     and cr.result_status='published'
     and co.academic_period_id=pr.period_id;

   v_gpa:=case when v_attempt>0 then round(v_qp/v_attempt,3) end;
   v_cum_attempt:=v_cum_attempt+v_attempt;
   v_cum_qp:=v_cum_qp+v_qp;
   v_cgpa:=case when v_cum_attempt>0 then round(v_cum_qp/v_cum_attempt,3) end;

   update public.student_period_results
   set attempted_credits=v_attempt,earned_credits=v_earned,total_quality_points=v_qp,
       gpa=v_gpa,cgpa=v_cgpa,status='calculated',calculated_at=now(),updated_at=now()
   where student_id=v_student and academic_period_id=pr.period_id;

   if not found then
     insert into public.student_period_results(
       institution_id,student_id,academic_period_id,attempted_credits,earned_credits,
       total_quality_points,gpa,cgpa,status,calculated_at,updated_at
     ) values(
       v_inst,v_student,pr.period_id,v_attempt,v_earned,v_qp,v_gpa,v_cgpa,'calculated',now(),now()
     );
   end if;
   n:=n+1;
 end loop;

 return jsonb_build_object('periods_calculated',n,'cgpa',v_cgpa);
end $$;

create or replace function public.unimis_student_gpa_summary()
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_student uuid;
begin
 select id into v_student from public.students where user_id=auth.uid() limit 1;
 if v_student is null then raise exception 'Student profile not found'; end if;

 perform public.unimis_recalculate_student_period_results(v_student);

 return jsonb_build_object(
   'latest',coalesce((select to_jsonb(x) from (
      select spr.gpa,spr.cgpa,spr.attempted_credits,spr.earned_credits,spr.total_quality_points,
             ap.name academic_period,ay.name academic_year
      from public.student_period_results spr
      join public.academic_periods ap on ap.id=spr.academic_period_id
      join public.academic_years ay on ay.id=ap.academic_year_id
      where spr.student_id=v_student
      order by ap.start_date desc,ap.period_number desc limit 1
   )x),'{}'::jsonb),
   'history',coalesce((select jsonb_agg(to_jsonb(x) order by x.start_date,x.period_number) from (
      select spr.gpa,spr.cgpa,spr.attempted_credits,spr.earned_credits,spr.total_quality_points,
             ap.name academic_period,ay.name academic_year,ap.start_date,ap.period_number
      from public.student_period_results spr
      join public.academic_periods ap on ap.id=spr.academic_period_id
      join public.academic_years ay on ay.id=ap.academic_year_id
      where spr.student_id=v_student
   )x),'[]'::jsonb)
 );
end $$;

grant execute on function public.unimis_recalculate_student_period_results(uuid) to authenticated;
grant execute on function public.unimis_student_gpa_summary() to authenticated;
commit;
