
-- UniMIS 049 — Registration approval workflow fix
-- Ensures the Admin/Registrar action changes the actual period-registration status
-- and records the transition in registration_approval_history atomically.
begin;

create or replace function public.unimis_decide_student_registration(
  p_period_registration_id uuid,
  p_action text,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_inst uuid;
  v_old text;
  v_new text;
begin
  select spr.institution_id, spr.registration_status
    into v_inst, v_old
  from public.student_period_registrations spr
  where spr.id=p_period_registration_id
  for update;

  if v_inst is null then
    raise exception 'Registration record not found';
  end if;

  -- The daily workflow is Admin/Registrar/Owner. Accept common role codes/names
  -- already used across UniMIS while still requiring an active institution user.
  if not exists (
    select 1
    from public.institution_users iu
    join public.roles r on r.id=iu.role_id
    where iu.user_id=auth.uid()
      and iu.institution_id=v_inst
      and iu.status='active'
      and lower(coalesce(r.code,r.name,'')) in
          ('admin','administrator','owner','registrar','superadmin','super_admin')
  ) then
    raise exception 'You are not authorised to approve student registrations';
  end if;

  if v_old <> 'submitted' then
    raise exception 'Only submitted registrations can be decided. Current status: %',v_old;
  end if;

  if lower(p_action)='approve' then
    v_new := 'approved';
  elsif lower(p_action) in ('return','reject') then
    -- "Return for correction" goes back to draft so the student can edit/resubmit.
    v_new := 'draft';
  else
    raise exception 'Invalid action %. Use approve or return',p_action;
  end if;

  update public.student_period_registrations
  set registration_status=v_new,
      updated_at=now()
  where id=p_period_registration_id;

  insert into public.registration_approval_history(
    institution_id,
    period_registration_id,
    old_status,
    new_status,
    action_by,
    action_at,
    notes
  )
  values(
    v_inst,
    p_period_registration_id,
    v_old,
    v_new,
    auth.uid(),
    now(),
    nullif(btrim(coalesce(p_notes,'')),'')
  );

  return jsonb_build_object(
    'period_registration_id',p_period_registration_id,
    'old_status',v_old,
    'registration_status',v_new
  );
end $$;

grant execute on function public.unimis_decide_student_registration(uuid,text,text)
to authenticated;

-- Repair audit history for the already-corrected Akosua test registration,
-- but only if it is currently approved and no approval event exists.
insert into public.registration_approval_history(
  institution_id,period_registration_id,old_status,new_status,action_by,action_at,notes
)
select
  spr.institution_id,
  spr.id,
  'submitted',
  'approved',
  coalesce(
    (select rah.action_by
     from public.registration_approval_history rah
     where rah.period_registration_id=spr.id
     order by rah.action_at desc
     limit 1),
    s.user_id
  ),
  now(),
  'Audit reconciliation: registration had been approved during local workflow testing'
from public.student_period_registrations spr
join public.students s on s.id=spr.student_id
where s.student_number='FET/ECE/26/001'
  and spr.registration_status='approved'
  and not exists (
    select 1
    from public.registration_approval_history h
    where h.period_registration_id=spr.id
      and h.new_status='approved'
  )
  and coalesce(
    (select rah.action_by
     from public.registration_approval_history rah
     where rah.period_registration_id=spr.id
     order by rah.action_at desc
     limit 1),
    s.user_id
  ) is not null;

commit;
