
begin;

create or replace function public.unimis_academic_intelligence_filters()
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid;
begin
 select iu.institution_id into v_inst
 from public.institution_users iu join public.roles r on r.id=iu.role_id
 where iu.user_id=auth.uid() and iu.status='active'
 and lower(coalesce(r.code,r.name)) in ('admin','administrator','owner','registrar','superadmin','super_admin','exams_officer','examinations_officer') limit 1;
 if v_inst is null then raise exception 'Academic review access required'; end if;
 return jsonb_build_object(
  'periods',coalesce((select jsonb_agg(jsonb_build_object('id',ap.id,'name',ap.name) order by ap.start_date desc) from public.academic_periods ap where ap.institution_id=v_inst),'[]'::jsonb),
  'programmes',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'code',p.code,'name',p.name) order by p.code) from public.programmes p where p.institution_id=v_inst),'[]'::jsonb),
  'levels',jsonb_build_array(100,200,300,400,500,600)
 );
end $$;
grant execute on function public.unimis_academic_intelligence_filters() to authenticated;

create or replace function public.unimis_academic_intelligence_report(
 p_academic_period_id uuid default null,
 p_programme_id uuid default null,
 p_level integer default null,
 p_result_status text default null,
 p_exception text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid;
begin
 select iu.institution_id into v_inst
 from public.institution_users iu join public.roles r on r.id=iu.role_id
 where iu.user_id=auth.uid() and iu.status='active'
 and lower(coalesce(r.code,r.name)) in ('admin','administrator','owner','registrar','superadmin','super_admin','exams_officer','examinations_officer') limit 1;
 if v_inst is null then raise exception 'Academic review access required'; end if;

 return jsonb_build_object(
 'generated_at',now(),
 'summary',(select jsonb_build_object(
   'students',count(distinct cr.student_id),'courses',count(distinct cr.course_offering_id),'results',count(*),
   'average',round(avg(cr.total_score),2),
   'pass_rate',round(count(*) filter(where cr.passed)*100.0/nullif(count(*),0),1),
   'failures',count(*) filter(where not coalesce(cr.passed,false)))
  from public.course_results cr join public.course_offerings co on co.id=cr.course_offering_id
  where cr.institution_id=v_inst
   and (p_academic_period_id is null or co.academic_period_id=p_academic_period_id)
   and (p_programme_id is null or co.programme_id=p_programme_id)
   and (p_level is null or co.level_number=p_level)
   and (p_result_status is null or p_result_status='' or cr.result_status=p_result_status)),
 'courses',coalesce((select jsonb_agg(to_jsonb(x) order by x.fail_rate desc,x.course_code) from (
  select co.id course_offering_id,c.code course_code,c.name course_name,p.code programme_code,p.name programme_name,
   co.level_number,ap.name academic_period,count(*) students,round(avg(cr.total_score),2) average,
   round(count(*) filter(where cr.passed)*100.0/nullif(count(*),0),1) pass_rate,
   round(count(*) filter(where not coalesce(cr.passed,false))*100.0/nullif(count(*),0),1) fail_rate,
   min(cr.total_score) lowest,max(cr.total_score) highest,
   case when count(*) filter(where not coalesce(cr.passed,false))*100.0/nullif(count(*),0)>=40 then 'high_failure'
        when count(*) filter(where cr.passed)*100.0/nullif(count(*),0)>=95 then 'very_high_pass'
        when max(cr.total_score)-min(cr.total_score)>=50 then 'wide_spread'
        else 'normal' end exception_type
  from public.course_results cr join public.course_offerings co on co.id=cr.course_offering_id
  join public.courses c on c.id=co.course_id left join public.programmes p on p.id=co.programme_id
  join public.academic_periods ap on ap.id=co.academic_period_id
  where cr.institution_id=v_inst
   and (p_academic_period_id is null or co.academic_period_id=p_academic_period_id)
   and (p_programme_id is null or co.programme_id=p_programme_id)
   and (p_level is null or co.level_number=p_level)
   and (p_result_status is null or p_result_status='' or cr.result_status=p_result_status)
  group by co.id,c.code,c.name,p.code,p.name,co.level_number,ap.name
 ) x where (p_exception is null or p_exception='' or p_exception='all' or x.exception_type=p_exception)),'[]'::jsonb),
 'students',coalesce((select jsonb_agg(to_jsonb(z) order by z.failed_courses desc,z.average) from (
  select s.id student_id,s.student_number,concat_ws(' ',s.first_name,s.middle_name,s.last_name) student_name,
   count(*) courses,round(avg(cr.total_score),2) average,min(cr.total_score) weakest_score,max(cr.total_score) strongest_score,
   round(stddev_pop(cr.total_score),2) variation,count(*) filter(where not coalesce(cr.passed,false)) failed_courses
  from public.course_results cr join public.course_offerings co on co.id=cr.course_offering_id join public.students s on s.id=cr.student_id
  where cr.institution_id=v_inst
   and (p_academic_period_id is null or co.academic_period_id=p_academic_period_id)
   and (p_programme_id is null or co.programme_id=p_programme_id)
   and (p_level is null or co.level_number=p_level)
   and (p_result_status is null or p_result_status='' or cr.result_status=p_result_status)
  group by s.id,s.student_number,s.first_name,s.middle_name,s.last_name
 ) z),'[]'::jsonb));
end $$;
grant execute on function public.unimis_academic_intelligence_report(uuid,uuid,integer,text,text) to authenticated;
commit;
