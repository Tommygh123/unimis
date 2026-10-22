-- Read-only configuration snapshot for a test cohort. No student/person records or secrets.
-- Run the complete script in Supabase Studio SQL Editor, then save/copy the JSON result.
create or replace function pg_temp.unimis_test_setup116()
returns jsonb language plpgsql as $$
declare t text; payload jsonb; result jsonb:='{}'::jsonb; total bigint;
begin
 foreach t in array array['institutions','faculties','departments','programmes','academic_years','academic_periods','courses','programme_courses','course_offerings','grading_schemes','grading_bands','grade_bands','grading_scheme_assignments','academic_progression_rules','graduation_rules','degree_classification_schemes','degree_classification_bands','degree_classification_assignments','fee_types','fee_structures','fee_structure_items','admission_cycles','admission_cycle_programmes','admission_programme_requirements','programme_admission_rules','programme_admission_subject_rules','admission_fee_rules','admission_document_requirements','admission_requirement_subjects','waec_subjects','waec_grade_points','roles','permissions'] loop
  if to_regclass('public.'||t) is not null then
   if t='institutions' then execute 'select coalesce(jsonb_agg(jsonb_build_object(''id'',id,''code'',code,''name'',name)),''[]''::jsonb) from public.institutions' into payload;
   else execute format('select coalesce(jsonb_agg(to_jsonb(x)),''[]''::jsonb) from (select * from public.%I limit 2000) x',t) into payload; end if;
   execute format('select count(*) from public.%I',t) into total;
   result:=result||jsonb_build_object(t,jsonb_build_object('rows',payload,'total',total));
  end if;
 end loop;
 if to_regclass('public.institution_settings') is not null then
  execute 'select coalesce(jsonb_agg(jsonb_build_object(''institution_id'',institution_id,''academic_settings'',academic_settings)),''[]''::jsonb) from public.institution_settings' into payload;
  result:=result||jsonb_build_object('academic_settings',payload);
 end if;
 foreach t in array array['applicants','applications','students','staff','lecturer_profiles'] loop
  if to_regclass('public.'||t) is not null then execute format('select count(*) from public.%I',t) into total; result:=result||jsonb_build_object(t||'_count',total); end if;
 end loop;
 return jsonb_build_object('snapshot',result,'generated_at',now());
end $$;
select pg_temp.unimis_test_setup116();
