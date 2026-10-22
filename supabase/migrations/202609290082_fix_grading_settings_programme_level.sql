begin;

-- 082: Fix grading settings reload after save.
-- programmes has no "level" column in the current UniMIS schema.
-- Level belongs to student/programme enrolment/academic workflow, not programme master data.

create or replace function public.unimis_grading_settings()
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_inst uuid;
begin
  select iu.institution_id into v_inst
  from public.institution_users iu
  where iu.user_id=auth.uid()
    and iu.status='active'
  order by iu.is_primary desc
  limit 1;

  if v_inst is null then
    raise exception 'Institution membership required';
  end if;

  return jsonb_build_object(
    'schemes',coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id',gs.id,
          'name',gs.name,
          'code',gs.code,
          'gpa_scale',gs.gpa_scale,
          'is_default',gs.is_default,
          'status',gs.status,
          'bands',coalesce((
            select jsonb_agg(
              jsonb_build_object(
                'id',gb.id,
                'letter_grade',gb.letter_grade,
                'min_score',gb.min_score,
                'max_score',gb.max_score,
                'grade_point',gb.grade_point,
                'classification',gb.classification,
                'is_pass',gb.is_pass
              )
              order by gb.min_score desc
            )
            from public.grade_bands gb
            where gb.grading_scheme_id=gs.id
          ),'[]'::jsonb)
        )
        order by gs.is_default desc,gs.name
      )
      from public.grading_schemes gs
      where gs.institution_id=v_inst
    ),'[]'::jsonb),

    'programmes',coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id',p.id,
          'code',p.code,
          'name',p.name,
          'department_id',p.department_id
        )
        order by p.name
      )
      from public.programmes p
      where p.institution_id=v_inst
    ),'[]'::jsonb),

    'courses',coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id',c.id,
          'code',c.code,
          'name',c.name
        )
        order by c.code
      )
      from public.courses c
      where c.institution_id=v_inst
    ),'[]'::jsonb),

    'assignments',coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id',a.id,
          'scope_type',a.scope_type,
          'programme_id',a.programme_id,
          'course_id',a.course_id,
          'grading_scheme_id',a.grading_scheme_id,
          'priority',a.priority,
          'is_active',a.is_active,
          'scheme_name',gs.name,
          'scheme_code',gs.code,
          'programme_code',p.code,
          'programme_name',p.name,
          'course_code',c.code,
          'course_name',c.name
        )
        order by a.scope_type,coalesce(p.code,c.code)
      )
      from public.grading_scheme_assignments a
      join public.grading_schemes gs on gs.id=a.grading_scheme_id
      left join public.programmes p on p.id=a.programme_id
      left join public.courses c on c.id=a.course_id
      where a.institution_id=v_inst
        and a.is_active
    ),'[]'::jsonb)
  );
end $$;

grant execute on function public.unimis_grading_settings() to authenticated;
notify pgrst,'reload schema';

commit;
