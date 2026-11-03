
begin;

-- 090C: the existing, proven Student Portal resolves a student by students.user_id.
-- Use exactly that same relationship for graduation data.
create or replace function public.unimis_student_graduation_status()
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_student_id uuid;
  v_row jsonb;
begin
  select s.id into v_student_id
  from public.students s
  where s.user_id = auth.uid()
  limit 1;

  if v_student_id is null then
    raise exception 'No student record is linked to this login';
  end if;

  select to_jsonb(x) into v_row
  from (
    select
      g.id review_id,
      g.decision,
      g.final_level,
      g.credits_required,
      g.credits_earned,
      g.cgpa,
      g.award_classification,
      g.outstanding_trails,
      g.graduation_date,
      g.approved_at,
      g.evaluated_at,
      p.code programme_code,
      p.name programme_name,
      p.award_type,
      ay.name academic_year
    from public.graduation_reviews g
    join public.programmes p on p.id=g.programme_id
    left join public.academic_years ay on ay.id=g.academic_year_id
    where g.student_id=v_student_id
    order by
      case g.decision when 'graduated' then 1 when 'approved' then 2 when 'eligible' then 3 else 4 end,
      coalesce(g.graduation_date,g.approved_at::date,g.evaluated_at::date) desc
    limit 1
  ) x;

  return coalesce(v_row,'{}'::jsonb);
end $$;

grant execute on function public.unimis_student_graduation_status() to authenticated;

commit;
