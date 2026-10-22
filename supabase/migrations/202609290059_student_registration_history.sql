begin;
create or replace function public.unimis_student_registration_history() returns jsonb language plpgsql security definer set search_path='' as $$
declare v_student_id uuid;
begin
 select id into v_student_id from public.students where user_id=auth.uid() limit 1;
 if v_student_id is null then raise exception 'Student profile not found'; end if;
 return coalesce((select jsonb_agg(to_jsonb(x) order by x.year_start desc,x.period_number desc) from (
  select spr.id period_registration_id,ay.name academic_year,ay.start_date year_start,ap.name academic_period,ap.period_number,
   spr.level_number,spr.registration_status,spr.submitted_at,spr.approved_at,
   count(scr.id) filter(where scr.status<>'dropped')::int course_count,
   coalesce(sum(c.credit_hours) filter(where scr.status<>'dropped'),0) credits,
   coalesce(jsonb_agg(jsonb_build_object('course_registration_id',scr.id,'course_offering_id',co.id,'course_code',c.code,'course_name',c.name,'credit_hours',c.credit_hours,'section_code',co.section_code,'registration_type',scr.registration_type,'status',scr.status) order by c.code) filter(where scr.id is not null and scr.status<>'dropped'),'[]'::jsonb) courses
  from public.student_period_registrations spr join public.academic_years ay on ay.id=spr.academic_year_id join public.academic_periods ap on ap.id=spr.academic_period_id
  left join public.student_course_registrations scr on scr.period_registration_id=spr.id left join public.course_offerings co on co.id=scr.course_offering_id left join public.courses c on c.id=co.course_id
  where spr.student_id=v_student_id group by spr.id,ay.name,ay.start_date,ap.name,ap.period_number,spr.level_number,spr.registration_status,spr.submitted_at,spr.approved_at
 ) x),'[]'::jsonb);
end $$;
revoke all on function public.unimis_student_registration_history() from public;
grant execute on function public.unimis_student_registration_history() to authenticated;
commit;