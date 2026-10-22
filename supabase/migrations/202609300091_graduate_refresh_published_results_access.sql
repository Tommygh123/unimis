
begin;

-- 091: Graduated students remain entitled to read their published academic record.
-- The old function required students.status='active', which caused the refresh toast
-- immediately after a student was marked graduated.
create or replace function public.unimis_student_published_results()
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare v_student uuid;
begin
 select id into v_student
 from public.students
 where user_id=auth.uid()
   and status in ('active','graduated')
 limit 1;

 if v_student is null then
   raise exception 'Student account not found';
 end if;

 return coalesce((
   select jsonb_agg(
     jsonb_build_object(
       'course_code',course_code,
       'course_name',course_name,
       'academic_year',academic_year,
       'academic_period',academic_period,
       'credit_hours',credit_hours,
       'total_score',total_score,
       'letter_grade',letter_grade,
       'grade_point',grade_point,
       'quality_points',quality_points,
       'passed',passed
     )
     order by academic_year,academic_period,course_code
   )
   from public.v_student_results
   where student_id=v_student and result_status='published'
 ),'[]'::jsonb);
end $$;

grant execute on function public.unimis_student_published_results() to authenticated;

commit;
