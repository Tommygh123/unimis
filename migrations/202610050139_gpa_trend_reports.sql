create or replace function public.unimis_gpa_trends139()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare inst uuid;rows jsonb;
begin
 inst:=public.unimis_reporting_access();if inst is null then raise exception 'Academic reporting access required';end if;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.student_number,x.period_start,x.period_number),'[]'::jsonb) into rows from (
 select s.id student_id,s.student_number,concat_ws(' ',s.first_name,s.middle_name,s.last_name) student_name,
 ay.name academic_year,ap.id period_id,ap.name semester,ap.period_number,ap.start_date period_start,
 pr.gpa,pr.cgpa,e.level_number,e.programme_code,e.department_name,e.faculty_name
 from public.student_period_results pr join public.students s on s.id=pr.student_id and s.institution_id=inst
 join public.academic_periods ap on ap.id=pr.academic_period_id and ap.institution_id=inst
 join public.academic_years ay on ay.id=ap.academic_year_id and ay.institution_id=inst
 left join lateral(select spr.level_number,p.code programme_code,d.name department_name,f.name faculty_name
 from public.student_period_registrations spr join public.student_programme_enrolments en on en.id=spr.programme_enrolment_id and en.institution_id=inst join public.programmes p on p.id=en.programme_id and p.institution_id=inst
 left join public.departments d on d.id=p.department_id and d.institution_id=inst left join public.faculties f on f.id=d.faculty_id and f.institution_id=inst
 where spr.student_id=s.id and spr.academic_period_id=ap.id and spr.institution_id=inst order by spr.id limit 1)e on true
 where pr.institution_id=inst and pr.status='published')x;
 return jsonb_build_object('rows',rows);
end $$;
revoke all on function public.unimis_gpa_trends139() from public,anon;
grant execute on function public.unimis_gpa_trends139() to authenticated;
