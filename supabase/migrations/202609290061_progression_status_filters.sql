
begin;

create or replace function public.unimis_progression_filters()
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid;
begin
 v_inst:=public.unimis_progression_access();
 if v_inst is null then raise exception 'Progression access required'; end if;
 return jsonb_build_object(
  'academic_years',coalesce((select jsonb_agg(to_jsonb(x) order by x.start_date desc) from
    (select ay.id,ay.name,ay.start_date,ay.end_date,coalesce(ay.is_current,false) is_current
     from public.academic_years ay where ay.institution_id=v_inst) x),'[]'::jsonb),
  'programmes',coalesce((select jsonb_agg(to_jsonb(x) order by x.name) from
    (select p.id,p.code,p.name from public.programmes p where p.institution_id=v_inst and coalesce(p.is_active,true)) x),'[]'::jsonb)
 );
end $$;

create or replace function public.unimis_student_progression_status()
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_student uuid;
begin
 select id into v_student from public.students where user_id=auth.uid() limit 1;
 if v_student is null then raise exception 'Student profile not found'; end if;
 return coalesce((select to_jsonb(x) from (
   select r.academic_year_id,ay.name academic_year,r.from_level,r.proposed_level,r.decision,
          r.promoted_at,r.credits_earned,r.failed_credits,r.courses_failed,r.failed_courses
   from public.student_progression_reviews r
   join public.academic_years ay on ay.id=r.academic_year_id
   where r.student_id=v_student and r.decision in('promoted','repeat','probation','deferred','withdrawn')
   order by coalesce(r.promoted_at,r.updated_at) desc limit 1
 ) x),'{}'::jsonb);
end $$;

grant execute on function public.unimis_progression_filters() to authenticated;
grant execute on function public.unimis_student_progression_status() to authenticated;
commit;
