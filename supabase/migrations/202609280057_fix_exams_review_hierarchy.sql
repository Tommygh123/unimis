
begin;

-- 057 fixes the real UniMIS academic hierarchy:
-- programmes -> departments -> faculties
-- programmes does NOT carry faculty_id directly.

create or replace function public.unimis_exams_review_filters()
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid;
begin
 select iu.institution_id into v_inst
 from public.institution_users iu join public.roles r on r.id=iu.role_id
 where iu.user_id=auth.uid() and iu.status='active'
 and lower(coalesce(r.code,r.name)) in ('admin','administrator','owner','registrar','superadmin','super_admin','exams_officer','examinations_officer')
 limit 1;
 if v_inst is null then raise exception 'Examinations review access required'; end if;

 return jsonb_build_object(
  'periods',coalesce((
    select jsonb_agg(jsonb_build_object('id',ap.id,'name',ap.name) order by ap.start_date desc)
    from public.academic_periods ap where ap.institution_id=v_inst
  ),'[]'::jsonb),
  'faculties',coalesce((
    select jsonb_agg(jsonb_build_object('id',f.id,'name',f.name) order by f.name)
    from public.faculties f where f.institution_id=v_inst
  ),'[]'::jsonb),
  'departments',coalesce((
    select jsonb_agg(jsonb_build_object('id',d.id,'name',d.name,'faculty_id',d.faculty_id) order by d.name)
    from public.departments d where d.institution_id=v_inst
  ),'[]'::jsonb),
  'programmes',coalesce((
    select jsonb_agg(jsonb_build_object(
      'id',p.id,'code',p.code,'name',p.name,
      'department_id',p.department_id,
      'faculty_id',d.faculty_id
    ) order by p.code)
    from public.programmes p
    left join public.departments d on d.id=p.department_id
    where p.institution_id=v_inst
  ),'[]'::jsonb)
 );
end $$;

create or replace function public.unimis_exams_review_queue(
 p_academic_period_id uuid default null,
 p_faculty_id uuid default null,
 p_department_id uuid default null,
 p_programme_id uuid default null,
 p_level integer default null,
 p_status text default null,
 p_exceptions_only boolean default false)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_inst uuid;
begin
 select iu.institution_id into v_inst
 from public.institution_users iu join public.roles r on r.id=iu.role_id
 where iu.user_id=auth.uid() and iu.status='active'
 and lower(coalesce(r.code,r.name)) in ('admin','administrator','owner','registrar','superadmin','super_admin','exams_officer','examinations_officer')
 limit 1;
 if v_inst is null then raise exception 'Examinations review access required'; end if;

 return jsonb_build_object(
 'summary',(
   select jsonb_build_object(
    'courses',count(*),
    'submitted',count(*) filter(where q.result_status='submitted'),
    'approved',count(*) filter(where q.result_status='approved'),
    'published',count(*) filter(where q.result_status='published'),
    'flagged',count(*) filter(where q.exception_type<>'normal'))
   from (
    select co.id,cr.result_status,
     case when count(*) filter(where not coalesce(cr.passed,false))*100.0/nullif(count(*),0)>=40 then 'high_failure'
          when count(*) filter(where cr.passed)*100.0/nullif(count(*),0)>=95 then 'very_high_pass'
          when max(cr.total_score)-min(cr.total_score)>=50 then 'wide_spread'
          else 'normal' end exception_type
    from public.course_results cr
    join public.course_offerings co on co.id=cr.course_offering_id
    left join public.programmes p on p.id=co.programme_id
    left join public.departments d on d.id=p.department_id
    where cr.institution_id=v_inst
      and (p_academic_period_id is null or co.academic_period_id=p_academic_period_id)
      and (p_faculty_id is null or d.faculty_id=p_faculty_id)
      and (p_department_id is null or p.department_id=p_department_id)
      and (p_programme_id is null or co.programme_id=p_programme_id)
      and (p_level is null or co.level_number=p_level)
      and (p_status is null or p_status='' or cr.result_status=p_status)
    group by co.id,cr.result_status
   ) q
   where (not p_exceptions_only or q.exception_type<>'normal')
 ),
 'rows',coalesce((
   select jsonb_agg(to_jsonb(q) order by q.faculty_name,q.department_name,q.course_code)
   from (
    select co.id course_offering_id,c.code course_code,c.name course_name,co.level_number,
     ap.name academic_period,p.id programme_id,p.code programme_code,p.name programme_name,
     d.id department_id,d.name department_name,f.id faculty_id,f.name faculty_name,
     cr.result_status,count(*) students,round(avg(cr.total_score),2) average,
     round(count(*) filter(where cr.passed)*100.0/nullif(count(*),0),1) pass_rate,
     round(count(*) filter(where not coalesce(cr.passed,false))*100.0/nullif(count(*),0),1) fail_rate,
     min(cr.total_score) lowest,max(cr.total_score) highest,min(cr.submitted_at) submitted_at,
     case when count(*) filter(where not coalesce(cr.passed,false))*100.0/nullif(count(*),0)>=40 then 'high_failure'
          when count(*) filter(where cr.passed)*100.0/nullif(count(*),0)>=95 then 'very_high_pass'
          when max(cr.total_score)-min(cr.total_score)>=50 then 'wide_spread'
          else 'normal' end exception_type
    from public.course_results cr
    join public.course_offerings co on co.id=cr.course_offering_id
    join public.courses c on c.id=co.course_id
    join public.academic_periods ap on ap.id=co.academic_period_id
    left join public.programmes p on p.id=co.programme_id
    left join public.departments d on d.id=p.department_id
    left join public.faculties f on f.id=d.faculty_id
    where cr.institution_id=v_inst
      and (p_academic_period_id is null or co.academic_period_id=p_academic_period_id)
      and (p_faculty_id is null or d.faculty_id=p_faculty_id)
      and (p_department_id is null or p.department_id=p_department_id)
      and (p_programme_id is null or co.programme_id=p_programme_id)
      and (p_level is null or co.level_number=p_level)
      and (p_status is null or p_status='' or cr.result_status=p_status)
    group by co.id,c.code,c.name,co.level_number,ap.name,p.id,p.code,p.name,d.id,d.name,f.id,f.name,cr.result_status
   ) q
   where (not p_exceptions_only or q.exception_type<>'normal')
 ),'[]'::jsonb));
end $$;

grant execute on function public.unimis_exams_review_filters() to authenticated;
grant execute on function public.unimis_exams_review_queue(uuid,uuid,uuid,uuid,integer,text,boolean) to authenticated;
commit;
