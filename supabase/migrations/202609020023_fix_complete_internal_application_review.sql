create or replace function public.complete_internal_application_review(
  p_application_id uuid,
  p_notes text default null
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_institution_id uuid;
  v_old_status text;
  v_now timestamptz := now();
begin
  select institution_id, decision_status
  into v_institution_id, v_old_status
  from public.applications
  where id = p_application_id;

  if v_institution_id is null then
    raise exception 'Application not found';
  end if;

  if not public.has_permission(v_institution_id,'admissions.manage') then
    raise exception 'You do not have permission to review applications';
  end if;

  update public.applications
  set reviewed_at = coalesce(reviewed_at,v_now),
      reviewed_by = coalesce(reviewed_by,auth.uid()),
      notes = coalesce(nullif(trim(p_notes),''),notes),
      updated_at = v_now
  where id = p_application_id;

  if not exists (
    select 1 from public.application_reviews r
    where r.application_id = p_application_id
      and r.review_stage = 'officer_review'
      and r.action = 'completed'
  ) then
    insert into public.application_reviews(
      institution_id,application_id,review_stage,action,
      old_status,new_status,eligibility_status,recommendation,
      comments,reviewed_by,reviewed_at,metadata
    ) values (
      v_institution_id,p_application_id,'officer_review','completed',
      v_old_status,v_old_status,null,null,
      nullif(trim(p_notes),''),auth.uid(),v_now,
      jsonb_build_object(
        'source','unimis',
        'workflow','admissions_review',
        'completed_via','complete_internal_application_review'
      )
    );
  else
    update public.application_reviews
    set comments = coalesce(nullif(trim(p_notes),''),comments),
        reviewed_by = coalesce(reviewed_by,auth.uid()),
        reviewed_at = coalesce(reviewed_at,v_now),
        metadata = coalesce(metadata,'{}'::jsonb) ||
          jsonb_build_object('last_confirmed_at',v_now)
    where application_id = p_application_id
      and review_stage = 'officer_review'
      and action = 'completed';
  end if;

  return true;
end;
$$;

grant execute on function public.complete_internal_application_review(uuid,text)
to authenticated;
