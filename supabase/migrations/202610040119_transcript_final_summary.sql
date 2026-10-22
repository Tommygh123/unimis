begin;
create or replace function public.unimis_student_search_profile(p_student_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare inst uuid; result jsonb; photo text; summary jsonb; classification jsonb;
begin
 select institution_id into inst from public.students where id=p_student_id;
 if inst is null or not (public.has_permission(inst,'students.view') or public.has_permission(inst,'students.manage')) then raise exception 'Student record access required'; end if;
 result:=public.unimis_student_profile(p_student_id);
 select d.storage_path into photo from public.application_documents d join public.students s on s.application_id=d.application_id where s.id=p_student_id and d.institution_id=inst and (lower(d.document_type) like '%photo%' or lower(d.document_type) like '%passport%') and coalesce(d.mime_type,'') like 'image/%' order by d.created_at desc limit 1;
 select jsonb_build_object('attempted_credits',coalesce(sum(c.credit_hours),0),
 'quality_points',coalesce(sum(c.credit_hours*coalesce(cr.grade_point,0)),0),
 'cgpa',case when sum(c.credit_hours)>0 then round(sum(c.credit_hours*coalesce(cr.grade_point,0))/sum(c.credit_hours),3) end,
 'earned_credits',(select coalesce(sum(z.credit_hours),0) from (
  select distinct co2.course_id,c2.credit_hours from public.course_results cr2
  join public.course_offerings co2 on co2.id=cr2.course_offering_id join public.courses c2 on c2.id=co2.course_id
  where cr2.student_id=p_student_id and cr2.institution_id=inst and cr2.result_status='published' and cr2.passed=true
 )z)) into summary
 from public.course_results cr join public.course_offerings co on co.id=cr.course_offering_id
 join public.courses c on c.id=co.course_id
 where cr.student_id=p_student_id and cr.institution_id=inst and cr.result_status='published';
 if public.unimis_progression_access() is not null then
 classification:=public.unimis_resolve_degree_classification((result->>'programme_id')::uuid,(summary->>'cgpa')::numeric);
 end if;
 summary:=summary||jsonb_build_object('classification',classification->>'classification','scheme_name',classification->>'scheme_name');
 return result||jsonb_build_object('academic_summary',summary,'institution',(select jsonb_build_object('name',i.name) from public.institutions i where i.id=inst),'applicant_photo_path',photo,'gpa_history',coalesce((select jsonb_agg(to_jsonb(x) order by x.start_date desc,x.period_number desc) from (
 select spr.gpa,spr.cgpa,spr.attempted_credits,spr.earned_credits,spr.total_quality_points,ap.name academic_period,ay.name academic_year,ap.start_date,ap.period_number
 from public.student_period_results spr join public.academic_periods ap on ap.id=spr.academic_period_id join public.academic_years ay on ay.id=ap.academic_year_id
 where spr.student_id=p_student_id and spr.institution_id=inst and spr.status='published'
 )x),'[]'::jsonb));
end $$;
revoke all on function public.unimis_student_search_profile(uuid) from public;
grant execute on function public.unimis_student_search_profile(uuid) to authenticated;
notify pgrst,'reload schema';
commit;
