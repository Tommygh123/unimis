-- UniMIS Owner Protection
create or replace function public.change_institution_user_role(
  p_institution_user_id uuid,
  p_role_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_institution_id uuid;
  v_user_id uuid;
  v_current_role_code text;
begin
  select iu.institution_id, iu.user_id, r.code
  into v_institution_id, v_user_id, v_current_role_code
  from public.institution_users iu
  left join public.roles r on r.id = iu.role_id
  where iu.id = p_institution_user_id;

  if v_institution_id is null then
    raise exception 'Institution user not found';
  end if;

  if not public.has_permission(v_institution_id, 'users.manage') then
    raise exception 'You do not have permission to manage users';
  end if;

  if v_current_role_code = 'owner' then
    raise exception 'The Owner role cannot be changed from User Management';
  end if;

  if not exists (
    select 1
    from public.roles r
    where r.id = p_role_id
      and r.is_active = true
      and r.code <> 'owner'
      and (r.institution_id is null or r.institution_id = v_institution_id)
  ) then
    raise exception 'Invalid role for this institution';
  end if;

  if v_user_id = auth.uid() then
    raise exception 'You cannot change your own role';
  end if;

  update public.institution_users
  set role_id = p_role_id
  where id = p_institution_user_id;
end;
$$;

revoke all on function public.change_institution_user_role(uuid,uuid) from public;
grant execute on function public.change_institution_user_role(uuid,uuid) to authenticated;

create or replace function public.set_institution_user_status(
  p_institution_user_id uuid,
  p_status text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_institution_id uuid;
  v_user_id uuid;
  v_current_role_code text;
begin
  if p_status not in ('active','inactive','suspended') then
    raise exception 'Invalid user status';
  end if;

  select iu.institution_id, iu.user_id, r.code
  into v_institution_id, v_user_id, v_current_role_code
  from public.institution_users iu
  left join public.roles r on r.id = iu.role_id
  where iu.id = p_institution_user_id;

  if v_institution_id is null then
    raise exception 'Institution user not found';
  end if;

  if not public.has_permission(v_institution_id, 'users.manage') then
    raise exception 'You do not have permission to manage users';
  end if;

  if v_current_role_code = 'owner' and p_status <> 'active' then
    raise exception 'The Owner account cannot be deactivated or suspended';
  end if;

  if v_user_id = auth.uid() and p_status <> 'active' then
    raise exception 'You cannot deactivate your own account';
  end if;

  update public.institution_users
  set status = p_status
  where id = p_institution_user_id;
end;
$$;

revoke all on function public.set_institution_user_status(uuid,text) from public;
grant execute on function public.set_institution_user_status(uuid,text) to authenticated;

notify pgrst, 'reload schema';
