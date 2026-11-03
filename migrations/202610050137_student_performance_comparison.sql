-- Read-only comparison. Access follows result-review scopes, never grants new roles.
create or replace function public.unimis_student_comparison137(p_result uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare r public.course_results;manager boolean;rows jsonb;
begin
 select * into r from public.course_results where id=p_result;
 if r.id is null then raise exception 'Result not found';end if;
 manager:=public.unimis_review_manager130(r.institution_id);
 if not manager and not exists(select 1 from public.unimis_batch_results130 br where br.result_id=r.id and public.unimis_batch_access130(br.batch_id)) then raise exception 'Result review access denied';end if;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.year_start,x.period_number,x.code,x.id),'[]'::jsonb) into rows from (
 select cr.id,c.id course_id,c.code,c.name,ay.name academic_year,ay.start_date year_start,ap.id period_id,ap.name semester,ap.period_number,spr.level_number,
 cr.total_score,cr.letter_grade,cr.grade_point,cr.passed,cr.result_status,
 coalesce((select jsonb_agg(jsonb_build_object('name',ai.name,'raw',sc.raw_score,'maximum',ai.max_score,'weight',ai.weight_percent,'percent',round(100*sc.raw_score/nullif(ai.max_score,0),2)) order by ai.name)
 from public.assessment_items ai left join public.assessment_scores sc on sc.assessment_item_id=ai.id and sc.student_course_registration_id=cr.student_course_registration_id and sc.institution_id=r.institution_id
 where ai.course_offering_id=cr.course_offering_id and ai.institution_id=r.institution_id and ai.status<>'cancelled'),'[]'::jsonb) components
 from public.course_results cr join public.student_course_registrations scr on scr.id=cr.student_course_registration_id and scr.institution_id=r.institution_id
 join public.student_period_registrations spr on spr.id=scr.period_registration_id and spr.institution_id=r.institution_id
 join public.academic_periods ap on ap.id=spr.academic_period_id and ap.institution_id=r.institution_id
 join public.academic_years ay on ay.id=ap.academic_year_id and ay.institution_id=r.institution_id
 join public.course_offerings o on o.id=cr.course_offering_id and o.institution_id=r.institution_id
 join public.courses c on c.id=o.course_id and c.institution_id=r.institution_id
 where cr.institution_id=r.institution_id and cr.student_id=r.student_id and scr.student_id=r.student_id and spr.student_id=r.student_id
 and scr.status not in ('dropped','withdrawn')
 and (manager or exists(select 1 from public.unimis_batch_results130 br where br.result_id=cr.id and public.unimis_batch_access130(br.batch_id)))
 ) x;
 return jsonb_build_object('anchor_id',r.id,'rows',rows,'scope',case when manager then 'Student results within this institution' else 'Only student results in your accessible review batches; other courses and history may be unavailable' end);
end $$;
revoke all on function public.unimis_student_comparison137(uuid) from public,anon;
grant execute on function public.unimis_student_comparison137(uuid) to authenticated;
