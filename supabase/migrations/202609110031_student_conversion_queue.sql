-- Conversion queue and student management RPC
begin;

create or replace function public.unimis_student_conversion_queue(p_institution_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare v_result jsonb;
begin
  if not (
    public.has_permission(p_institution_id,'students.view')
    or public.has_permission(p_institution_id,'students.manage')
    or public.has_permission(p_institution_id,'admissions.manage')
  ) then
    raise exception 'You do not have permission to view student conversion';
  end if;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.accepted_at desc),'[]'::jsonb)
  into v_result
  from (
    select
      app.id as application_id,
      app.application_number,
      app.decision_status,
      ap.id as applicant_id,
      ap.first_name,
      ap.middle_name,
      ap.last_name,
      ap.email,
      ao.id as offer_id,
      ao.offer_number,
      ao.programme_id,
      p.code as programme_code,
      p.name as programme_name,
      ao.responded_at as accepted_at,
      s.id as student_id,
      s.student_number,
      case when s.id is null then 'ready' else 'converted' end as conversion_status
    from public.admission_offers ao
    join public.applications app on app.id=ao.application_id
    join public.applicants ap on ap.id=app.applicant_id
    join public.programmes p on p.id=ao.programme_id
    left join public.students s on s.application_id=app.id
    where app.institution_id=p_institution_id
      and ao.response_status='accepted'
  ) x;

  return v_result;
end $$;

create or replace function public.unimis_students_directory(p_institution_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare v_result jsonb;
begin
  if not (
    public.has_permission(p_institution_id,'students.view')
    or public.has_permission(p_institution_id,'students.manage')
  ) then
    raise exception 'You do not have permission to view students';
  end if;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.student_number),'[]'::jsonb)
  into v_result
  from (
    select
      s.id,s.student_number,s.first_name,s.middle_name,s.last_name,
      s.email,s.phone,s.status,s.student_type,s.admission_date,
      e.id as enrolment_id,e.programme_id,e.current_level,e.enrolment_status,
      p.code as programme_code,p.name as programme_name,
      ay.name as admission_academic_year
    from public.students s
    left join public.student_programme_enrolments e
      on e.student_id=s.id and e.is_primary=true
    left join public.programmes p on p.id=e.programme_id
    left join public.academic_years ay on ay.id=e.admission_academic_year_id
    where s.institution_id=p_institution_id
  ) x;

  return v_result;
end $$;

grant execute on function public.unimis_student_conversion_queue(uuid) to authenticated;
grant execute on function public.unimis_students_directory(uuid) to authenticated;

commit;
