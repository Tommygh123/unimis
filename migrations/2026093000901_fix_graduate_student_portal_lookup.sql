
begin;

-- 090B: use the same account/profile relationship that the existing Student
-- Portal authorization already accepts. Do not require students.auth_user_id.
create or replace function public.unimis_student_graduation_status()
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_uid uuid := auth.uid();
  v_student_id uuid;
  v_row jsonb;
begin
  -- Normal direct linkage, where available.
  select s.id
    into v_student_id
  from public.students s
  where s.auth_user_id = v_uid
  limit 1;

  -- Compatibility with the existing UniMIS student-portal membership/profile
  -- linkage used by seeded and converted student accounts.
  if v_student_id is null then
    select s.id
      into v_student_id
    from public.students s
    join public.profiles p
      on lower(p.email) = lower(s.email)
    where p.id = v_uid
    limit 1;
  end if;

  if v_student_id is null then
    raise exception 'Student account not found';
  end if;

  select to_jsonb(x)
    into v_row
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
    join public.programmes p on p.id = g.programme_id
    left join public.academic_years ay on ay.id = g.academic_year_id
    where g.student_id = v_student_id
    order by
      case g.decision
        when 'graduated' then 1
        when 'approved' then 2
        when 'eligible' then 3
        else 4
      end,
      coalesce(g.graduation_date, g.approved_at::date, g.evaluated_at::date) desc
    limit 1
  ) x;

  return coalesce(v_row, '{}'::jsonb);
end
$$;

grant execute on function public.unimis_student_graduation_status() to authenticated;

commit;
