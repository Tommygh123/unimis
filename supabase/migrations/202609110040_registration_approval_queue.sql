begin;

create or replace function public.unimis_registration_approval_queue(p_institution_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare v_result jsonb;
begin
  if not (
    public.has_permission(p_institution_id,'registrations.view')
    or public.has_permission(p_institution_id,'registrations.approve')
    or public.has_permission(p_institution_id,'students.manage')
  ) then raise exception 'You do not have permission to view student registrations'; end if;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.submitted_at desc nulls last),'[]'::jsonb) into v_result
  from (
    select r.id as period_registration_id,r.registration_status,r.submitted_at,r.approved_at,r.notes,
      s.id as student_id,s.student_number,s.first_name,s.middle_name,s.last_name,
      p.code as programme_code,p.name as programme_name,e.current_level,
      ay.name as academic_year,ap.name as academic_period,
      coalesce(sum(case when scr.status<>'dropped' then c.credit_hours else 0 end),0) as total_credits,
      count(*) filter(where scr.status<>'dropped') as course_count
    from public.student_period_registrations r
    join public.students s on s.id=r.student_id
    left join public.student_programme_enrolments e on e.id=r.programme_enrolment_id
    left join public.programmes p on p.id=e.programme_id
    join public.academic_years ay on ay.id=r.academic_year_id
    join public.academic_periods ap on ap.id=r.academic_period_id
    left join public.student_course_registrations scr on scr.period_registration_id=r.id
    left join public.course_offerings o on o.id=scr.course_offering_id
    left join public.courses c on c.id=o.course_id
    where r.institution_id=p_institution_id
      and r.registration_status in ('submitted','approved','rejected')
    group by r.id,s.id,p.code,p.name,e.current_level,ay.name,ap.name
  ) x;
  return v_result;
end $$;

create or replace function public.unimis_decide_student_registration(
  p_period_registration_id uuid,
  p_action text,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare v_reg public.student_period_registrations%rowtype;v_new text;
begin
  if p_action not in ('approve','return') then raise exception 'Unsupported registration decision'; end if;
  select * into v_reg from public.student_period_registrations where id=p_period_registration_id for update;
  if not found then raise exception 'Registration not found'; end if;
  if not (
    public.has_permission(v_reg.institution_id,'registrations.approve')
    or public.has_permission(v_reg.institution_id,'students.manage')
  ) then raise exception 'You do not have permission to approve registrations'; end if;
  if v_reg.registration_status<>'submitted' then raise exception 'Only submitted registrations can be decided'; end if;
  v_new:=case when p_action='approve' then 'approved' else 'rejected' end;
  update public.student_period_registrations
  set registration_status=v_new,
      approved_at=case when p_action='approve' then now() else null end,
      approved_by=case when p_action='approve' then auth.uid() else null end,
      notes=coalesce(p_notes,notes),updated_at=now()
  where id=v_reg.id;
  insert into public.registration_approval_history(institution_id,period_registration_id,old_status,new_status,action_by,notes)
  values(v_reg.institution_id,v_reg.id,v_reg.registration_status,v_new,auth.uid(),p_notes);
  return jsonb_build_object('ok',true,'registration_status',v_new);
end $$;

grant execute on function public.unimis_registration_approval_queue(uuid) to authenticated;
grant execute on function public.unimis_decide_student_registration(uuid,text,text) to authenticated;
commit;
